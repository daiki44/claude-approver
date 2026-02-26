import AppKit
import SwiftUI

// MARK: - ApprovalPanel

/// NSPanel subclass configured as a non-activating floating panel.
/// This allows buttons to respond even when another app has focus.
final class ApprovalPanel: NSPanel {
    /// Called when Escape is pressed while the panel is key.
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

// MARK: - FirstMouseHostingView

/// NSHostingView subclass that accepts the first mouse click
/// even when the window is not active. This eliminates the
/// "click-to-activate, click-to-act" double-click problem.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - FirstMouseHostingController

/// NSHostingController that uses FirstMouseHostingView as its view.
final class FirstMouseHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = FirstMouseHostingView(rootView: rootView)
    }
}

// MARK: - ApprovalPanelController

/// Manages the approval panel lifecycle: showing, hiding, positioning,
/// and event monitors (outside-click dismiss, Escape key).
@MainActor
final class ApprovalPanelController {
    private var panel: ApprovalPanel?
    private var globalClickMonitor: Any?
    private var globalKeyMonitor: Any?
    private let contentSize = NSSize(width: 380, height: 480)

    /// Whether the panel is currently visible.
    var isShown: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - Setup

    /// Create and configure the panel with the given SwiftUI content.
    func setup<Content: View>(content: Content) {
        let hostingController = FirstMouseHostingController(rootView: content)

        let panel = ApprovalPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false

        panel.onEscape = { [weak self] in
            self?.close()
        }

        self.panel = panel
    }

    // MARK: - Public API

    /// Toggle panel from the status bar icon click.
    /// Does NOT activate the app — panel floats over other windows.
    func toggleFromStatusItem() {
        guard let panel else { return }
        if panel.isVisible {
            close()
        } else {
            positionNearStatusBar()
            panel.orderFrontRegardless()
            installEventMonitors()
        }
    }

    /// Show panel for an incoming approval request.
    /// Activates the app and requests user attention.
    func showForIncomingRequest() {
        guard let panel else { return }
        if !panel.isVisible {
            positionNearStatusBar()
            installEventMonitors()
        }
        activateApp()
        panel.makeKeyAndOrderFront(nil)
        NSApp.requestUserAttention(.criticalRequest)
    }

    /// Close the panel and clean up event monitors.
    func close() {
        panel?.orderOut(nil)
        removeEventMonitors()
    }

    /// Full cleanup on app termination.
    func teardown() {
        close()
        panel = nil
    }

    // MARK: - Private

    /// Position the panel near the menu bar, centered on screen.
    private func positionNearStatusBar() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - contentSize.width / 2
        let y = screenFrame.maxY - contentSize.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func installEventMonitors() {
        // Close on click outside panel
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                self?.close()
            }
        }
        // Close on Escape key (backup for when panel is not key)
        if globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // Escape
                    self?.close()
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
}
