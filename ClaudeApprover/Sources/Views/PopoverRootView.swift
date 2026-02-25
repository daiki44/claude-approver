import SwiftUI

struct PopoverRootView: View {
    let viewModel: ApproverViewModel

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
            if viewModel.queue.isEmpty {
                EmptyStateView()
            } else {
                RequestListView(viewModel: viewModel)
            }
        }
        .frame(width: 380, height: 480)
    }
}
