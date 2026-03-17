import SwiftUI

/// Card for AskUserQuestion requests.
/// Shows the question text prominently and any options Claude provided.
/// Since answers cannot be injected via hooks, the user is guided to the terminal.
struct QuestionRowView: View {
    let request: PermissionRequest
    let onDismiss: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SharedHeaderView(request: request, onDismiss: onDismiss)

            // Question text
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude is asking:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(request.questionText ?? request.displayCommand)
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Options list (if any)
            if let options = request.questionOptions, !options.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Options:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                        HStack(spacing: 6) {
                            Text("\(idx + 1).")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 20, alignment: .trailing)
                            Text(option)
                                .font(.system(.caption))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Guidance
            Text("Answer in the terminal to respond to this question.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .italic()

            // Action buttons
            HStack {
                Spacer()

                Button(action: onDeny) {
                    Label("Skip Question", systemImage: "forward.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onDismiss) {
                    Label("Go to Terminal", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
