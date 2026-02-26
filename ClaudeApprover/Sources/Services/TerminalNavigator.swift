import AppKit
import Foundation

/// Navigates to a specific terminal tab using TTY matching via AppleScript.
/// Falls back to app-level activation when TTY is unavailable or the terminal
/// doesn't support tab-level AppleScript navigation.
enum TerminalNavigator {

    private static let terminalBundleIds = [
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "com.apple.Terminal",
    ]

    /// Navigate to the terminal tab associated with the given TTY.
    @MainActor
    static func navigate(tty: String?) {
        let workspace = NSWorkspace.shared

        guard let (bundleId, app) = findRunningTerminal(workspace: workspace) else {
            debugLog("No terminal app found")
            return
        }

        guard let tty, !tty.isEmpty else {
            debugLog("No TTY info, activating \(bundleId)")
            app.activate()
            return
        }

        let navigated: Bool
        switch bundleId {
        case "com.apple.Terminal":
            navigated = navigateTerminalApp(tty: tty)
        case "com.googlecode.iterm2":
            navigated = navigateITerm2(tty: tty)
        default:
            navigated = false
        }

        if navigated {
            debugLog("Tab navigation succeeded: \(bundleId) tty=\(tty)")
        } else {
            debugLog("Tab navigation unavailable for \(bundleId), activating app")
            app.activate()
        }
    }

    // MARK: - Terminal.app

    private static func navigateTerminalApp(tty: String) -> Bool {
        let escaped = escapedForAppleScript(tty)
        let script = """
        tell application "Terminal"
            activate
            set targetTTY to "\(escaped)"
            repeat with w in windows
                set tabCount to count of tabs of w
                repeat with i from 1 to tabCount
                    set t to tab i of w
                    if tty of t is targetTTY then
                        set selected tab of w to t
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        return executeAppleScript(script)
    }

    // MARK: - iTerm2

    private static func navigateITerm2(tty: String) -> Bool {
        let escaped = escapedForAppleScript(tty)
        let script = """
        tell application "iTerm2"
            activate
            set targetTTY to "\(escaped)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is targetTTY then
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        return executeAppleScript(script)
    }

    // MARK: - Helpers

    private static func findRunningTerminal(
        workspace: NSWorkspace
    ) -> (bundleId: String, app: NSRunningApplication)? {
        for bundleId in terminalBundleIds {
            if let app = workspace.runningApplications.first(
                where: { $0.bundleIdentifier == bundleId }
            ) {
                return (bundleId, app)
            }
        }
        return nil
    }

    private static func executeAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            debugLog("Failed to create AppleScript")
            return false
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            debugLog("AppleScript error: \(error)")
            return false
        }
        return result.booleanValue
    }

    private static func escapedForAppleScript(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func debugLog(_ message: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/approver_debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [TerminalNavigator] \(message)\n"
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
