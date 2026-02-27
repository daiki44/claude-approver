import AppKit
import SwiftUI

// MARK: - ApprovalPanel

/// NSPanel subclass configured as a non-activating floating panel.
/// This allows buttons to respond even when another app has focus.
final class ApprovalPanel: NSPanel {
    /// Called when Escape is pressed while the panel is key.
    var onEscape: (() -> Void)?
    /// Called when the user clicks inside the panel to activate it.
    var onActivate: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if !isKeyWindow {
            onActivate?()
        }
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

    /// Notifies whether the panel is the key window (keyboard shortcuts active).
    var onKeyWindowChanged: ((Bool) -> Void)?

    // Keyboard action closures (wired by AppDelegate)
    var onEnter: (() -> Void)?
    var onDenyTop: (() -> Void)?
    var onAllowAll: (() -> Void)?
    var onDenyAll: (() -> Void)?

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

        panel.onActivate = { [weak self] in
            self?.activateAndMakeKey()
        }

        // Track key window state for keyboard shortcut indicator
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onKeyWindowChanged?(true) }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onKeyWindowChanged?(false) }
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
    /// Does NOT steal focus — the panel floats over other windows.
    /// The user must click the panel to enable keyboard shortcuts.
    func showForIncomingRequest() {
        guard let panel else { return }
        if !panel.isVisible {
            positionNearStatusBar()
            installEventMonitors()
        }
        panel.orderFrontRegardless()
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

    /// User explicitly clicked the panel — activate app and make key.
    private func activateAndMakeKey() {
        guard let panel else { return }
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
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
        // Keyboard shortcuts for panel actions
        if globalKeyMonitor == nil {
            globalKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let isEditing = NSApp.keyWindow?.firstResponder is NSText
                switch event.keyCode {
                case 53:       // Escape
                    self.close()
                    return nil
                case 36, 76:   // Return / Enter
                    self.onEnter?()
                    return nil
                case 2:        // D
                    if isEditing { return event }
                    self.onDenyTop?()
                    return nil
                case 0:        // A
                    if isEditing { return event }
                    self.onAllowAll?()
                    return nil
                case 7:        // X
                    if isEditing { return event }
                    self.onDenyAll?()
                    return nil
                default:
                    return event
                }
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
