import SwiftUI

struct RequestListView: View {
    let viewModel: ApproverViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Completions (shown at top)
                ForEach(viewModel.completions) { completion in
                    CompletionRowView(
                        completion: completion,
                        onGoToTerminal: {
                            viewModel.goToTerminal(completionId: completion.id)
                        },
                        onDismiss: {
                            viewModel.dismissCompletion(id: completion.id)
                        }
                    )
                }

                // Pending requests
                ForEach(viewModel.queue.items) { request in
                    RequestRowView(
                        request: request,
                        viewModel: viewModel
                    )
                }
            }
            .padding(12)
        }
    }
}
