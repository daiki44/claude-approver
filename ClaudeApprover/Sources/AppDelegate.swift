import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Direct static reference — avoids NSApp.delegate cast issues with @NSApplicationDelegateAdaptor
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private let viewModel = ApproverViewModel()
    private var panelController: ApprovalPanelController?

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

        // Create panel
        let controller = ApprovalPanelController()
        controller.setup(content: PopoverRootView(viewModel: viewModel))

        // Wire keyboard shortcuts
        controller.onEnter = { [weak self] in
            guard let self, let first = self.viewModel.queue.items.first else { return }
            switch first.requestType {
            case .toolPermission:
                self.viewModel.allow(requestId: first.id)
            case .question:
                self.viewModel.goToTerminalForQuestion(requestId: first.id)
            case .planApproval:
                self.viewModel.approvePlan(requestId: first.id, mode: .clearContextAutoAccept)
            }
        }
        controller.onDenyTop = { [weak self] in
            guard let self, let first = self.viewModel.queue.items.first else { return }
            self.viewModel.deny(requestId: first.id)
        }
        controller.onAllowAll = { [weak self] in
            self?.viewModel.allowAll()
        }
        controller.onDenyAll = { [weak self] in
            self?.viewModel.denyAll()
        }

        controller.onKeyWindowChanged = { [weak self] isKey in
            self?.viewModel.isKeyboardShortcutsActive = isKey
        }

        panelController = controller

        // Start in demo mode or normal mode
        if CommandLine.arguments.contains("--demo") {
            viewModel.loadDemoData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showPopover()
                self?.updateBadge(count: self?.viewModel.queue.count ?? 0)
            }
        } else {
            Task {
                await viewModel.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.teardown()
        Task {
            await viewModel.shutdown()
        }
    }

    @objc private func togglePopover() {
        panelController?.toggleFromStatusItem()
    }

    /// Open the panel programmatically (called when a new request arrives)
    func showPopover() {
        panelController?.showForIncomingRequest()
    }

    /// Whether the panel is currently visible
    var isPopoverShown: Bool {
        panelController?.isShown ?? false
    }

    /// Close the panel
    func closePopover() {
        panelController?.close()
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
}
