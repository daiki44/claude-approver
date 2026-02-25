import SwiftUI

@main
struct ClaudeApproverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No window - menu bar only app
        Settings {
            EmptyView()
        }
    }
}
