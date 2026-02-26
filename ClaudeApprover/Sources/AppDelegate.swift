import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Direct static reference — avoids NSApp.delegate cast issues with @NSApplicationDelegateAdaptor
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel = ApproverViewModel()
    private var globalClickMonitor: Any?
    private var globalKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "checkmark.shield",
                accessibilityDescription: "Claude Approver"
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(viewModel: viewModel)
        )

        // Start socket server
        Task {
            await viewModel.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitors()
        Task {
            await viewModel.shutdown()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            activateApp()
            installEventMonitors()
        }
    }

    /// Open the popover programmatically (called when a new request arrives)
    func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            activateApp()
            installEventMonitors()
            debugLog("[AppDelegate] showPopover: popover opened programmatically")
        }
    }

    /// Whether the popover is currently visible
    var isPopoverShown: Bool {
        popover?.isShown ?? false
    }

    /// Close the popover and remove event monitors
    func closePopover() {
        popover.performClose(nil)
        removeEventMonitors()
    }

    /// Play system beep to draw attention
    func playAttentionSound() {
        NSSound.beep()
    }

    /// Briefly highlight the status bar button for visual attention
    func bounceButton() {
        guard let button = statusItem.button else { return }
        button.highlight(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            button.highlight(false)
        }
    }

    /// Update the menu bar icon badge when queue changes
    func updateBadge(count: Int) {
        guard let button = statusItem.button else { return }

        let symbolName = count > 0 ? "checkmark.shield.fill" : "checkmark.shield"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Claude Approver"
        )

        // Show count as badge text
        if count > 0 {
            button.title = " \(count)"
        } else {
            button.title = ""
        }
    }

    // MARK: - Private

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func installEventMonitors() {
        // Close on click outside popover
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.closePopover()
            }
        }
        // Close on Escape key
        if globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    self?.closePopover()
                    return nil
                }
                return event
            }
        }
    }

    private func removeEventMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }

    private func debugLog(_ message: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/approver_debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
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
