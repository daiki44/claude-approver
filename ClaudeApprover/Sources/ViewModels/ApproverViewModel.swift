import AppKit
import Foundation

/// Main ViewModel coordinating the socket server, request queue, and UI.
@Observable
@MainActor
final class ApproverViewModel {
    let queue = RequestQueue()
    private let server = SocketServer()
    private let notificationService = NotificationService.shared

    /// Tracks request IDs that were cancelled before being enqueued (race condition fix)
    private var earlyCancelledIds: Set<UUID> = []

    /// Tracks toolUseIds of approved requests for completion notifications
    private var approvedToolUseIds: Set<String> = []

    func start() async {
        notificationService.requestAuthorization()

        // Wire up the server's onRequest callback
        await server.setOnRequest { [weak self] request in
            Task { @MainActor in
                self?.handleIncomingRequest(request)
            }
        }

        // Wire up the server's onCancel callback.
        // Fires when the hook script dies (terminal handled it, session ended, etc.)
        await server.setOnCancel { [weak self] requestId in
            Task { @MainActor in
                self?.handleCancelledRequest(requestId)
            }
        }

        // Wire up the server's onCompletion callback.
        // Fires when a PostToolUse hook reports tool completion.
        await server.setOnCompletion { [weak self] info in
            Task { @MainActor in
                self?.handleCompletion(info)
            }
        }

        do {
            try await server.start()
        } catch {
            debugLog("Failed to start socket server: \(error)")
        }
    }

    func shutdown() async {
        await server.shutdown()
    }

    // MARK: - Request Handling

    private func handleIncomingRequest(_ request: PermissionRequest) {
        debugLog("handleIncomingRequest: tool=\(request.toolName) type=\(request.requestType) id=\(request.id) toolUseId=\(request.toolUseId)")
        if let inputKeys = (request.toolInput as NSDictionary).allKeys as? [String] {
            debugLog("  input_keys=\(inputKeys)")
        }

        // Race condition fix: if this request was already cancelled before enqueue, skip it
        if earlyCancelledIds.remove(request.id) != nil {
            debugLog("  skipped enqueue: already cancelled (early cancel)")
            return
        }

        queue.enqueue(request)
        notificationService.notify(request: request)

        // UX: auto-open popover, play sound, highlight button
        if let delegate = AppDelegate.shared {
            debugLog("  calling showPopover()")
            delegate.showPopover()
            delegate.playAttentionSound()
            delegate.bounceButton()
            debugLog("  showPopover() completed")
        }

        updateAppDelegate()
    }

    /// Remove a request that was cancelled (handled in terminal or hook died).
    /// If the request hasn't been enqueued yet (race condition), record it for early skip.
    private func handleCancelledRequest(_ requestId: UUID) {
        if queue.dequeue(id: requestId) != nil {
            debugLog("handleCancelledRequest: dequeued id=\(requestId)")
            updateAppDelegate()
        } else {
            debugLog("handleCancelledRequest: early cancel id=\(requestId)")
            earlyCancelledIds.insert(requestId)
        }
    }

    // MARK: - User Actions

    func allow(requestId: UUID) {
        resolveRequest(requestId: requestId, decision: .allow)
    }

    func deny(requestId: UUID) {
        resolveRequest(requestId: requestId, decision: .deny)
    }

    func denyWithMessage(requestId: UUID, message: String) {
        resolveRequest(requestId: requestId, decision: .denyWith(message: message))
    }

    func alwaysAllow(requestId: UUID, permissions: [[String: Any]]) {
        resolveRequest(requestId: requestId, decision: .allowWith(permissions: permissions))
    }

    /// Dismiss a request without sending a response (passthrough).
    /// Used for "Go to Terminal" — lets Claude Code handle the tool normally.
    func dismiss(requestId: UUID) {
        debugLog("dismiss: id=\(requestId) (passthrough)")
        resolveRequest(requestId: requestId, decision: .passthrough)
    }

    func approvePlan(requestId: UUID, mode: PlanApprovalMode) {
        debugLog("approvePlan: id=\(requestId) mode=\(mode.label)")
        resolveRequest(requestId: requestId, decision: .allowPlan(mode: mode))
    }

    func allowAll() {
        let items = queue.items
        queue.clear()
        for item in items {
            Task {
                await server.resolve(requestId: item.id, decision: .allow)
            }
        }
        updateAppDelegate()
    }

    func denyAll() {
        let items = queue.items
        queue.clear()
        for item in items {
            Task {
                await server.resolve(requestId: item.id, decision: .deny)
            }
        }
        updateAppDelegate()
    }

    private func resolveRequest(requestId: UUID, decision: DecisionResponse) {
        guard let request = queue.dequeue(id: requestId) else { return }
        debugLog("resolveRequest: id=\(requestId) behavior=\(decision.behavior) toolUseId='\(request.toolUseId)'")

        // Track approved requests for completion notifications
        if decision.behavior == "allow", !request.toolUseId.isEmpty {
            approvedToolUseIds.insert(request.toolUseId)
            debugLog("  tracking toolUseId=\(request.toolUseId) for completion (total=\(approvedToolUseIds.count))")
        }

        Task {
            await server.resolve(requestId: requestId, decision: decision)
        }
        updateAppDelegate()
    }

    // MARK: - Completion Handling

    private func handleCompletion(_ info: CompletionInfo) {
        debugLog("handleCompletion: tool=\(info.toolName) toolUseId=\(info.toolUseId) isError=\(info.isError)")

        // Only notify for tools that were approved via the Approver
        guard approvedToolUseIds.remove(info.toolUseId) != nil else {
            debugLog("  skipped: toolUseId not tracked")
            return
        }

        debugLog("  showing completion notification")
        notificationService.notifyCompletion(info: info)
    }

    // MARK: - Badge

    private func updateAppDelegate() {
        guard let delegate = AppDelegate.shared else { return }
        delegate.updateBadge(count: queue.count)
    }

    // MARK: - Debug Logging

    private func debugLog(_ message: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/approver_debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [ViewModel] \(message)\n"
        if let data = line.data(using: .utf8) {
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
    }
}

// MARK: - SocketServer helpers to set callbacks from MainActor

extension SocketServer {
    func setOnRequest(_ handler: @escaping @Sendable (PermissionRequest) -> Void) {
        self.onRequest = handler
    }

    func setOnCancel(_ handler: @escaping @Sendable (UUID) -> Void) {
        self.onCancel = handler
    }

    func setOnCompletion(_ handler: @escaping @Sendable (CompletionInfo) -> Void) {
        self.onCompletion = handler
    }
}
