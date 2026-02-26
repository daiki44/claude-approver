import Foundation

/// Unix Domain Socket server that receives permission requests from Hook scripts
/// and resolves them when the user makes a decision in the UI.
///
/// Architecture: All blocking I/O (accept, recv, send) runs on GCD threads,
/// NOT on the actor executor. Only state mutations (pendingHandlers, onRequest)
/// are actor-isolated and accessed via `await`.
actor SocketServer {
    private let socketPath: String
    private var serverFD: Int32 = -1
    private var isRunning = false

    /// Pending continuations keyed by request_id, resolved when user decides
    private var pendingHandlers: [UUID: CheckedContinuation<DecisionResponse, Never>] = [:]

    /// Callback when a new permission request arrives
    var onRequest: (@Sendable (PermissionRequest) -> Void)?

    /// Callback when a request is cancelled (hook script died / terminal handled it)
    var onCancel: (@Sendable (UUID) -> Void)?

    /// Callback when a tool completion event arrives
    var onCompletion: (@Sendable (CompletionInfo) -> Void)?

    init() {
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeApprover")
        self.socketPath = supportDir.appendingPathComponent("claude-approver.sock").path
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else {
            debugLog("Already running, skipping start")
            return
        }

        debugLog("Starting... socketPath=\(socketPath)")

        // Ensure directory exists
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        // Restrict socket directory access to current user only
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: dir
        )

        // Remove stale socket file
        if FileManager.default.fileExists(atPath: socketPath) {
            try FileManager.default.removeItem(atPath: socketPath)
            debugLog("Removed stale socket")
        }

        // Create socket
        serverFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw SocketError.createFailed(errno: errno)
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                _ = strcpy(UnsafeMutableRawPointer(ptr)
                    .assumingMemoryBound(to: CChar.self), cstr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(serverFD)
            throw SocketError.bindFailed(errno: errno)
        }

        // Listen
        guard Darwin.listen(serverFD, 16) == 0 else {
            Darwin.close(serverFD)
            throw SocketError.listenFailed(errno: errno)
        }

        isRunning = true
        debugLog("Listening on \(socketPath)")

        // Start accept loop on GCD (NOT on actor executor)
        let fd = serverFD
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptLoop(serverFD: fd)
        }
    }

    func shutdown() {
        isRunning = false

        if serverFD >= 0 {
            Darwin.close(serverFD)
            serverFD = -1
        }

        // Clean up socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        // Deny all pending requests
        let handlers = pendingHandlers
        pendingHandlers.removeAll()
        for (_, continuation) in handlers {
            continuation.resume(returning: .deny)
        }
    }

    // MARK: - Actor-isolated state accessors

    func storeContinuation(_ id: UUID, _ continuation: CheckedContinuation<DecisionResponse, Never>) {
        pendingHandlers[id] = continuation
    }

    /// Called by ViewModel when user taps Allow/Deny
    func resolve(requestId: UUID, decision: DecisionResponse) {
        guard let continuation = pendingHandlers.removeValue(forKey: requestId) else {
            debugLog("WARNING: resolve() continuation not found for \(requestId)")
            return
        }
        continuation.resume(returning: decision)
    }

    /// Cancel a pending request and notify UI to remove it from queue
    func cancelAndNotify(_ id: UUID) {
        if let cont = pendingHandlers.removeValue(forKey: id) {
            cont.resume(returning: .deny)
        } else {
            debugLog("WARNING: cancelAndNotify() continuation not found for \(id)")
        }
        onCancel?(id)
    }

    func getOnRequest() -> (@Sendable (PermissionRequest) -> Void)? {
        onRequest
    }

    // MARK: - Accept Loop (runs on GCD, NOT on actor)

    nonisolated private func acceptLoop(serverFD: Int32) {
        while true {
            let clientFD = Darwin.accept(serverFD, nil, nil)
            if clientFD < 0 { break }

            // Handle each connection on its own GCD thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    Darwin.close(clientFD)
                    return
                }
                self.handleConnection(clientFD)
            }
        }
    }

    // MARK: - Connection Handling (runs on GCD, NOT on actor)

    nonisolated private func handleConnection(_ fd: Int32) {
        defer { Darwin.close(fd) }

        // Read 4-byte length header
        guard let header = readExact(fd: fd, count: 4) else { return }
        let bodyLen = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard bodyLen > 0, bodyLen < 1_000_000 else { return }

        // Read JSON body
        guard let body = readExact(fd: fd, count: Int(bodyLen)),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return }

        // Route by message type
        let messageType = json["type"] as? String ?? "permission_request"
        if messageType == "completion" {
            handleCompletionMessage(fd: fd, json: json)
            return
        }

        // Permission request flow: requires request_id
        guard let requestIdStr = json["request_id"] as? String,
              let requestId = UUID(uuidString: requestIdStr)
        else { return }

        // Parse into PermissionRequest
        let request = PermissionRequest(
            id: requestId,
            toolName: json["tool_name"] as? String ?? "Unknown",
            toolInput: json["tool_input"] as? [String: Any] ?? [:],
            toolUseId: json["tool_use_id"] as? String ?? "",
            sessionId: json["session_id"] as? String ?? "",
            cwd: json["cwd"] as? String ?? "",
            receivedAt: Date(),
            permissionSuggestions: json["permission_suggestions"] as? [[String: Any]] ?? []
        )

        // Bridge blocking GCD thread to Swift concurrency
        let semaphore = DispatchSemaphore(value: 0)
        let decisionBox = UnsafeSendableBox<DecisionResponse>(.deny)
        var cancelled = false

        // Store continuation FIRST, then notify UI.
        // This guarantees pendingHandlers[requestId] exists before the user
        // can see and interact with the request, preventing the race condition
        // where resolve() runs before storeContinuation() completes.
        Task { [weak self] in
            guard let self else {
                semaphore.signal()
                return
            }

            let callback = await self.getOnRequest()

            let result = await withCheckedContinuation { (continuation: CheckedContinuation<DecisionResponse, Never>) in
                Task {
                    await self.storeContinuation(requestId, continuation)
                    callback?(request)
                }
            }
            decisionBox.value = result
            semaphore.signal()
        }

        // Monitor socket for remote close (hook script died / terminal handled it).
        // When the hook process is killed or exits, the kernel closes the socket,
        // and DispatchSource fires so we can clean up the request from the queue.
        let monitorSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        monitorSource.setEventHandler { [weak self] in
            var buf = UInt8(0)
            let n = Darwin.recv(fd, &buf, 1, Int32(MSG_PEEK))
            if n <= 0 {
                // Remote end closed — hook script died or terminal handled the request
                cancelled = true
                Task { [weak self] in
                    await self?.cancelAndNotify(requestId)
                }
                semaphore.signal()
            }
        }
        monitorSource.resume()

        // Block this GCD thread until: user decision, remote close, or timeout
        let waitResult = semaphore.wait(timeout: .now() + 300)
        monitorSource.cancel()

        if cancelled {
            // Connection already closed — no response to send
            return
        }

        if waitResult == .timedOut {
            decisionBox.value = .deny
            Task { [weak self] in
                await self?.cancelAndNotify(requestId)
            }
        }

        let decision = decisionBox.value

        // Passthrough: close connection without sending a response.
        // Hook script receives EOF → returns None → exits with code 1 → passthrough.
        if decision.behavior == "passthrough" {
            return
        }

        // Send response back to Hook — extended format with message/updatedPermissions
        var response = decision.toJSON()
        response["request_id"] = requestIdStr
        guard let responseData = try? JSONSerialization.data(withJSONObject: response) else { return }

        var lengthHeader = UInt32(responseData.count).bigEndian
        let headerData = Data(bytes: &lengthHeader, count: 4)

        _ = headerData.withUnsafeBytes { ptr in
            Darwin.send(fd, ptr.baseAddress!, 4, 0)
        }
        _ = responseData.withUnsafeBytes { ptr in
            Darwin.send(fd, ptr.baseAddress!, responseData.count, 0)
        }
    }

    // MARK: - Completion Handling (runs on GCD, NOT on actor)

    nonisolated private func handleCompletionMessage(fd: Int32, json: [String: Any]) {
        let info = CompletionInfo(
            toolName: json["tool_name"] as? String ?? "Unknown",
            toolUseId: json["tool_use_id"] as? String ?? "",
            sessionId: json["session_id"] as? String ?? "",
            resultSummary: json["result_summary"] as? String ?? "",
            isError: json["is_error"] as? Bool ?? false
        )

        // Fire callback (async to actor)
        Task { [weak self] in
            await self?.onCompletion?(info)
        }

        // Send immediate ACK
        let ack: [String: Any] = ["status": "ok"]
        guard let ackData = try? JSONSerialization.data(withJSONObject: ack) else { return }
        var ackLen = UInt32(ackData.count).bigEndian
        let ackHeader = Data(bytes: &ackLen, count: 4)
        _ = ackHeader.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, 4, 0) }
        _ = ackData.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, ackData.count, 0) }
    }

    // MARK: - Debug Logging

    nonisolated private func debugLog(_ message: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/approver_debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [SocketServer] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logPath.path) {
            if let handle = try? FileHandle(forWritingTo: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logPath)
        }
    }

    // MARK: - I/O Helpers

    nonisolated private func readExact(fd: Int32, count: Int) -> Data? {
        var buffer = Data(count: count)
        var totalRead = 0
        while totalRead < count {
            let n = buffer.withUnsafeMutableBytes { ptr in
                Darwin.recv(fd, ptr.baseAddress!.advanced(by: totalRead), count - totalRead, 0)
            }
            if n <= 0 { return nil }
            totalRead += n
        }
        return buffer
    }
}

// MARK: - Sendable Box

/// Thread-unsafe box that allows mutating a captured value across concurrency boundaries.
/// Safety is guaranteed by the caller via DispatchSemaphore synchronization.
private final class UnsafeSendableBox<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Errors

enum SocketError: Error, LocalizedError {
    case createFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .createFailed(let e): return "Socket create failed: \(String(cString: strerror(e)))"
        case .bindFailed(let e): return "Socket bind failed: \(String(cString: strerror(e)))"
        case .listenFailed(let e): return "Socket listen failed: \(String(cString: strerror(e)))"
        }
    }
}
