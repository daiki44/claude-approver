import SwiftUI

/// Card for ExitPlanMode requests.
/// Shows the plan content, allowed prompts, approval mode picker, and action buttons.
struct PlanApprovalRowView: View {
    let request: PermissionRequest
    let onApproveWithMode: (PlanApprovalMode) -> Void
    let onReject: () -> Void
    let onRejectWithReason: (String) -> Void
    var onDismiss: (() -> Void)?

    @State private var selectedMode: PlanApprovalMode = .clearContextAutoAccept
    @State private var showFeedbackField = false
    @State private var feedbackText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SharedHeaderView(request: request, onDismiss: onDismiss)

            // Plan content (scrollable)
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan to approve:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(request.planText ?? request.displayCommand)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color.purple.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.purple.opacity(0.15), lineWidth: 1)
                )
            }

            // Allowed prompts (pre-approved tool calls)
            if let prompts = request.allowedPrompts, !prompts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pre-approved calls:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(prompts.prefix(5).enumerated()), id: \.offset) { _, prompt in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text("\(prompt.tool): \(prompt.prompt)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Approval mode picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Approval mode:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedMode) {
                    ForEach(PlanApprovalMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(selectedMode.description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(Color.purple.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Feedback text field (option 4: Tell Claude what to change)
            if showFeedbackField {
                HStack(spacing: 4) {
                    TextField("Tell Claude what to change...", text: $feedbackText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit {
                            guard !feedbackText.isEmpty else { return }
                            onRejectWithReason(feedbackText)
                        }
                    Button("Send") {
                        onRejectWithReason(feedbackText)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.orange)
                    .disabled(feedbackText.isEmpty)
                }
            }

            // Action buttons
            HStack {
                Spacer()

                Button {
                    showFeedbackField.toggle()
                } label: {
                    Label("Tell Claude...", systemImage: "text.bubble")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onReject) {
                    Label("Reject Plan", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onApproveWithMode(selectedMode)
                } label: {
                    Label("Approve Plan", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.purple)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
