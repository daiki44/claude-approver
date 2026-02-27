import SwiftUI

@MainActor
struct PopoverRootView: View {
    let viewModel: ApproverViewModel

    var body: some View {
        let hasContent = !viewModel.queue.isEmpty || !viewModel.completions.isEmpty

        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.blue)
                Text("Claude Approver")
                    .font(.headline)

                Image(systemName: "keyboard")
                    .foregroundStyle(viewModel.isKeyboardShortcutsActive ? .blue : .secondary.opacity(0.4))
                    .help(viewModel.isKeyboardShortcutsActive
                          ? "Keyboard shortcuts active"
                          : "Click panel to enable shortcuts")
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isKeyboardShortcutsActive)

                Spacer()
                if !viewModel.queue.isEmpty {
                    Button("Allow All") {
                        viewModel.allowAll()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)

                    Button("Deny All") {
                        viewModel.denyAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Content
            if hasContent {
                RequestListView(viewModel: viewModel)
            } else {
                EmptyStateView()
            }
        }
        .frame(width: 380, height: 480)
    }
}
