import SwiftUI

struct PopoverRootView: View {
    let viewModel: ApproverViewModel

    private var hasContent: Bool {
        !viewModel.queue.isEmpty || !viewModel.completions.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.blue)
                Text("Claude Approver")
                    .font(.headline)
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
