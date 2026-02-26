import SwiftUI

/// Dispatcher view that renders the appropriate card based on request type.
struct RequestRowView: View {
    let request: PermissionRequest
    let viewModel: ApproverViewModel

    var body: some View {
        switch request.requestType {
        case .toolPermission:
            ToolPermissionRowView(
                request: request,
                onAllow: { viewModel.allow(requestId: request.id) },
                onDeny: { viewModel.deny(requestId: request.id) },
                onAlwaysAllow: { permissions in
                    viewModel.alwaysAllow(requestId: request.id, permissions: permissions)
                },
                onDenyWithMessage: { message in
                    viewModel.denyWithMessage(requestId: request.id, message: message)
                }
            )

        case .question:
            QuestionRowView(
                request: request,
                onDismiss: { viewModel.goToTerminalForQuestion(requestId: request.id) },
                onDeny: { viewModel.deny(requestId: request.id) }
            )

        case .planApproval:
            PlanApprovalRowView(
                request: request,
                onApproveWithMode: { mode in
                    viewModel.approvePlan(requestId: request.id, mode: mode)
                },
                onReject: { viewModel.deny(requestId: request.id) },
                onRejectWithReason: { message in
                    viewModel.denyWithMessage(requestId: request.id, message: message)
                }
            )
        }
    }
}
