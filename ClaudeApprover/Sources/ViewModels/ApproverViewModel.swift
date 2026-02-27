import AppKit
import Foundation

/// Main ViewModel coordinating the socket server, request queue, and UI.
@Observable
@MainActor
final class ApproverViewModel {
    let queue = RequestQueue()
    private let server = SocketServer()
    private(set) var isDemoMode = false
    private let notificationService = NotificationService.shared

    /// Whether the approval panel is the key window (keyboard shortcuts active).
    /// Set by AppDelegate via ApprovalPanelController.onKeyWindowChanged.
    var isKeyboardShortcutsActive = false

    /// Tracks request IDs that were cancelled before being enqueued (race condition fix)
    private var earlyCancelledIds: Set<UUID> = []

    /// Tracks toolUseIds of approved requests for completion notifications
    private var approvedToolUseIds: Set<String> = []

    /// Session ID to TTY mapping (learned from permission requests)
    private var sessionTtyMap: [String: String] = [:]

    /// Sessions where user enabled "Auto-approve file edits" (acceptEdits mode).
    /// Workaround for Claude Code race condition: when mode switch via updatedPermissions
    /// hasn't been applied before the next Edit/Write permission check fires.
    private var autoApproveEditSessions: Set<String> = []

    /// Tool names that are auto-approved in acceptEdits mode
    private static let editToolNames: Set<String> = ["Edit", "Write", "NotebookEdit"]

    /// Recently completed tools (shown in UI)
    private(set) var completions: [CompletionInfo] = []

    func start() async {
        notificationService.requestAuthorization()

        // Wire up the server's onRequest callback
        await server.setOnRequest { [weak self] request in
            let vm = self
            Task { @MainActor in
                vm?.handleIncomingRequest(request)
            }
        }

        // Wire up the server's onCancel callback.
        // Fires when the hook script dies (terminal handled it, session ended, etc.)
        await server.setOnCancel { [weak self] requestId in
            let vm = self
            Task { @MainActor in
                vm?.handleCancelledRequest(requestId)
            }
        }

        // Wire up the server's onCompletion callback.
        // Fires when a PostToolUse hook reports tool completion.
        await server.setOnCompletion { [weak self] info in
            let vm = self
            Task { @MainActor in
                vm?.handleCompletion(info)
            }
        }

        do {
            try await server.start()
        } catch {
            debugLog("Failed to start socket server: \(error)")
        }
    }

    /// デモモード: モックデータを直接キューに投入（SocketServer 不要）
    func loadDemoData() {
        isDemoMode = true
        for request in DemoDataProvider.mockRequests() {
            queue.enqueue(request)
        }
        completions = DemoDataProvider.mockCompletions()
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

        // Learn TTY mapping from this session
        if let tty = request.tty, !tty.isEmpty, !request.sessionId.isEmpty {
            sessionTtyMap[request.sessionId] = tty
            trimSessionTtyMap()
        }

        // Race condition fix: if this request was already cancelled before enqueue, skip it
        if earlyCancelledIds.remove(request.id) != nil {
            debugLog("  skipped enqueue: already cancelled (early cancel)")
            return
        }

        // Auto-approve Edit/Write/NotebookEdit if session has acceptEdits mode active.
        // This works around Claude Code's race condition where updatedPermissions
        // mode switch hasn't been applied before the next permission check fires.
        if autoApproveEditSessions.contains(request.sessionId),
           request.requestType == .toolPermission,
           Self.editToolNames.contains(request.toolName) {
            debugLog("  auto-approved: tool=\(request.toolName) session=\(request.shortSessionId) (acceptEdits mode active)")
            if !request.toolUseId.isEmpty {
                approvedToolUseIds.insert(request.toolUseId)
            }
            Task {
                await server.resolve(requestId: request.id, decision: .allow)
            }
            return
        }

        queue.enqueue(request)

        // UX: open popover FIRST so the app is active and willPresent sees it as shown.
        // This prevents notification banners from overlaying the popover buttons.
        if let delegate = AppDelegate.shared {
            debugLog("  calling showPopover()")
            delegate.showPopover()
            delegate.playAttentionSound()
            delegate.bounceButton()
            debugLog("  showPopover() completed")
        }

        // Send notification AFTER popover is shown — banners suppressed by willPresent
        notificationService.notify(request: request)
        // Remove any lingering banners from earlier notifications
        notificationService.removeAllDelivered()

        updateAppDelegate()
    }

    /// Remove a request that was cancelled (handled in terminal or hook died).
    /// If the request hasn't been enqueued yet (race condition), record it for early skip.
    private func handleCancelledRequest(_ requestId: UUID) {
        if queue.dequeue(id: requestId) != nil {
            debugLog("handleCancelledRequest: dequeued id=\(requestId)")
            notificationService.removeDelivered(requestId: requestId)
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
        // Track session for client-side auto-approve if setMode/acceptEdits
        if let request = queue.items.first(where: { $0.id == requestId }),
           !request.sessionId.isEmpty,
           permissions.contains(where: { Self.isSetModeAcceptEdits($0) }) {
            autoApproveEditSessions.insert(request.sessionId)
            trimAutoApproveEditSessions()
            debugLog("alwaysAllow: acceptEdits mode enabled for session=\(request.shortSessionId)")
        }
        resolveRequest(requestId: requestId, decision: .allowWith(permissions: permissions))
    }

    /// Dismiss a request without sending a response (passthrough).
    /// Used for "Go to Terminal" — lets Claude Code handle the tool normally.
    func dismiss(requestId: UUID) {
        debugLog("dismiss: id=\(requestId) (passthrough)")
        resolveRequest(requestId: requestId, decision: .passthrough)
    }

    /// Dismiss a question and switch focus to the terminal.
    func goToTerminalForQuestion(requestId: UUID) {
        debugLog("goToTerminalForQuestion: id=\(requestId)")
        let tty = queue.items.first(where: { $0.id == requestId })?.tty
        resolveRequest(requestId: requestId, decision: .passthrough)
        // Activate terminal FIRST, then close popover to avoid macOS restoring
        // focus to the previously-active app (e.g. Slack) during orderOut.
        TerminalNavigator.navigate(tty: tty)
        if let delegate = AppDelegate.shared {
            delegate.closePopover()
        }
    }

    func approvePlan(requestId: UUID, mode: PlanApprovalMode) {
        debugLog("approvePlan: id=\(requestId) mode=\(mode.label)")
        resolveRequest(requestId: requestId, decision: .allowPlan(mode: mode))
    }

    func allowAll() {
        let items = queue.items
        queue.clear()
        if !isDemoMode {
            for item in items {
                Task {
                    await server.resolve(requestId: item.id, decision: .allow)
                }
            }
        }
        updateAppDelegate()
    }

    func denyAll() {
        let items = queue.items
        queue.clear()
        if !isDemoMode {
            for item in items {
                Task {
                    await server.resolve(requestId: item.id, decision: .deny)
                }
            }
        }
        updateAppDelegate()
    }

    private func resolveRequest(requestId: UUID, decision: DecisionResponse) {
        guard let request = queue.dequeue(id: requestId) else { return }
        debugLog("resolveRequest: id=\(requestId) behavior=\(decision.behavior) toolUseId='\(request.toolUseId)'")
        notificationService.removeDelivered(requestId: requestId)

        // Track approved requests for completion notifications
        if decision.behavior == "allow", !request.toolUseId.isEmpty {
            approvedToolUseIds.insert(request.toolUseId)
            debugLog("  tracking toolUseId=\(request.toolUseId) for completion (total=\(approvedToolUseIds.count))")
        }

        if !isDemoMode {
            Task {
                await server.resolve(requestId: requestId, decision: decision)
            }
        }
        updateAppDelegate()
    }

    // MARK: - Completion Handling

    private func handleCompletion(_ info: CompletionInfo) {
        debugLog("handleCompletion: tool=\(info.toolName) toolUseId=\(info.toolUseId) isError=\(info.isError)")

        // Safety net: clean up stale requests with the same toolUseId.
        // If a completion arrives but the request is still in the queue, it means
        // the terminal handled it (e.g. AskUserQuestion answered in terminal).
        if !info.toolUseId.isEmpty,
           let staleRequest = queue.items.first(where: { $0.toolUseId == info.toolUseId }) {
            debugLog("  cleaning up stale request: id=\(staleRequest.id)")
            _ = queue.dequeue(id: staleRequest.id)
            notificationService.removeDelivered(requestId: staleRequest.id)
            // Continuation may already be gone (hook exited), but attempt to release it
            Task { await server.resolve(requestId: staleRequest.id, decision: .deny) }
            updateAppDelegate()
        }

        // Only notify for tools that were approved via the Approver
        guard approvedToolUseIds.remove(info.toolUseId) != nil else {
            debugLog("  skipped: toolUseId not tracked")
            return
        }

        // Resolve TTY from sessionTtyMap if missing
        let resolvedInfo: CompletionInfo
        if (info.tty == nil || info.tty?.isEmpty == true),
           let mappedTty = sessionTtyMap[info.sessionId] {
            resolvedInfo = CompletionInfo(
                toolName: info.toolName,
                toolUseId: info.toolUseId,
                sessionId: info.sessionId,
                tty: mappedTty,
                cwd: info.cwd,
                resultSummary: info.resultSummary,
                isError: info.isError
            )
        } else {
            resolvedInfo = info
        }

        debugLog("  showing completion in UI (tty=\(resolvedInfo.tty ?? "nil"))")
        completions.append(resolvedInfo)
        notificationService.notifyCompletion(info: resolvedInfo)

        // Only show popover for completion if there are pending requests
        // (don't reopen a closed popover just for informational completions)
        if !queue.isEmpty, let delegate = AppDelegate.shared {
            delegate.bounceButton()
        }
    }

    /// Dismiss a completion item from the UI
    func dismissCompletion(id: UUID) {
        completions.removeAll { $0.id == id }
        updateAppDelegate()
    }

    /// Go to terminal and dismiss the completion
    func goToTerminal(completionId: UUID) {
        let tty = completions.first(where: { $0.id == completionId })?.tty
        completions.removeAll { $0.id == completionId }

        // Activate terminal FIRST, then close popover to avoid macOS restoring
        // focus to the previously-active app (e.g. Slack) during orderOut.
        TerminalNavigator.navigate(tty: tty)
        if let delegate = AppDelegate.shared {
            delegate.closePopover()
        }

        updateAppDelegate()
    }

    // MARK: - Badge

    private func updateAppDelegate() {
        guard let delegate = AppDelegate.shared else { return }
        delegate.updateBadge(count: queue.count)

        // Auto-close popover when all requests have been handled
        // (skip in demo mode — user is taking screenshots)
        if queue.isEmpty && !isDemoMode {
            delegate.closePopover()
        }
    }

    // MARK: - Auto-Approve Helpers

    /// Check if a permission suggestion is a setMode/acceptEdits request
    private static func isSetModeAcceptEdits(_ suggestion: [String: Any]) -> Bool {
        suggestion["type"] as? String == "setMode"
            && suggestion["mode"] as? String == "acceptEdits"
    }

    private func trimAutoApproveEditSessions() {
        if autoApproveEditSessions.count > 50 {
            autoApproveEditSessions.removeAll()
        }
    }

    // MARK: - Session TTY Map

    private func trimSessionTtyMap() {
        if sessionTtyMap.count > 100 {
            sessionTtyMap.removeAll()
        }
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
