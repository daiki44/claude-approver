import SwiftUI

struct RequestListView: View {
    let viewModel: ApproverViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
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
