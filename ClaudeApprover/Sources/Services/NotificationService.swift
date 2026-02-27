import AppKit
import Foundation
import UserNotifications

/// Manages native macOS notifications for incoming permission requests.
/// Gracefully handles cases where UNUserNotificationCenter is unavailable
/// (e.g., when running outside a proper .app bundle).
/// @unchecked Sendable: center is set once in init() and only read thereafter.
/// NSObject conformance prevents automatic Sendable synthesis.
final class NotificationService: NSObject, @unchecked Sendable {
    static let shared = NotificationService()
    private var center: UNUserNotificationCenter?

    private override init() {
        super.init()
        // UNUserNotificationCenter requires a proper app bundle.
        // Lazily attempt to get it; if it fails, notifications are disabled.
        do {
            let c = try Self.getCenter()
            self.center = c
            c.delegate = self
            writeLog("Notification center initialized successfully")
        } catch {
            writeLog("Notifications unavailable: \(error.localizedDescription)")
        }
    }

    private static func getCenter() throws -> UNUserNotificationCenter {
        // Check if we have a valid bundle identifier (required for notifications)
        guard Bundle.main.bundleIdentifier != nil else {
            throw NotificationError.noBundleIdentifier
        }
        return UNUserNotificationCenter.current()
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error {
                self?.writeLog("Authorization error: \(error.localizedDescription)")
            }
            self?.writeLog("Authorization result: granted=\(granted)")
        }

        // Register notification categories with actions
        let openTerminalAction = UNNotificationAction(
            identifier: "OPEN_TERMINAL",
            title: "Open Terminal",
            options: .foreground
        )
        let completionCategory = UNNotificationCategory(
            identifier: "TOOL_COMPLETION",
            actions: [openTerminalAction],
            intentIdentifiers: []
        )
        let permissionCategory = UNNotificationCategory(
            identifier: "PERMISSION_REQUEST",
            actions: [],
            intentIdentifiers: []
        )
        center?.setNotificationCategories([completionCategory, permissionCategory])
    }

    /// Remove all delivered notification banners from Notification Center.
    /// Called when the popover opens to prevent lingering banners from overlaying buttons.
    func removeAllDelivered() {
        center?.removeAllDeliveredNotifications()
    }

    /// Remove a specific delivered notification by request ID.
    /// Called when a request is resolved or cancelled (e.g. handled in terminal).
    func removeDelivered(requestId: UUID) {
        center?.removeDeliveredNotifications(withIdentifiers: [requestId.uuidString])
    }

    func notify(request: PermissionRequest) {
        guard let center else {
            writeLog("notify: center is nil, skipping notification for \(request.toolName)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Claude Approver"
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"

        switch request.requestType {
        case .toolPermission:
            content.subtitle = request.toolName
            content.body = request.displayCommand
        case .question:
            content.subtitle = "Claude has a question"
            content.body = request.questionText ?? request.displayCommand
        case .planApproval:
            content.subtitle = "Plan needs approval"
            content.body = String((request.planText ?? request.displayCommand).prefix(200))
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let notifRequest = UNNotificationRequest(
            identifier: request.id.uuidString,
            content: content,
            trigger: trigger
        )
        center.add(notifRequest) { [weak self] error in
            if let error {
                self?.writeLog("Failed to add notification: \(error.localizedDescription)")
            } else {
                self?.writeLog("Notification added for \(request.toolName) (id: \(request.id.uuidString))")
            }
        }
    }

    func notifyCompletion(info: CompletionInfo) {
        guard let center else {
            writeLog("notifyCompletion: center is nil, skipping for \(info.toolName)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = info.isError ? "Tool Failed" : "Tool Completed"
        content.subtitle = info.toolName
        content.body = info.resultSummary.isEmpty
            ? (info.isError ? "Error occurred" : "Completed successfully")
            : String(info.resultSummary.prefix(200))
        content.sound = .default
        content.categoryIdentifier = "TOOL_COMPLETION"

        // Store TTY in userInfo for terminal tab navigation on click
        var userInfo: [String: String] = [:]
        if let tty = info.tty, !tty.isEmpty {
            userInfo["tty"] = tty
        }
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let notifRequest = UNNotificationRequest(
            identifier: "completion-\(info.toolUseId)",
            content: content,
            trigger: trigger
        )
        center.add(notifRequest) { [weak self] error in
            if let error {
                self?.writeLog("Failed to add completion notification: \(error.localizedDescription)")
            } else {
                self?.writeLog("Completion notification added for \(info.toolName)")
            }
        }
    }

    // MARK: - File-based logging

    private func writeLog(_ message: String) {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ClaudeApprover")
        let logPath = logDir.appendingPathComponent("notification.log")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [NotificationService] \(message)\n"

        // Ensure log directory exists
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

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
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Suppress banners when the popover is visible — banners overlay the popover
        // and intercept click events, making buttons unresponsive.
        let popoverShown = await MainActor.run { AppDelegate.shared?.isPopoverShown ?? false }
        if popoverShown {
            return []
        }
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let categoryId = response.notification.request.content.categoryIdentifier
        let actionId = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        if categoryId == "TOOL_COMPLETION"
            || actionId == "OPEN_TERMINAL"
            || (categoryId == "TOOL_COMPLETION" && actionId == UNNotificationDefaultActionIdentifier) {
            let tty = userInfo["tty"] as? String
            await MainActor.run {
                TerminalNavigator.navigate(tty: tty)
            }
        } else {
            // Permission request notification — activate Approver
            await MainActor.run {
                if let delegate = AppDelegate.shared {
                    delegate.showPopover()
                }
            }
        }
    }
}

private enum NotificationError: LocalizedError {
    case noBundleIdentifier

    var errorDescription: String? {
        switch self {
        case .noBundleIdentifier:
            return "No bundle identifier - run as .app bundle for notifications"
        }
    }
}
