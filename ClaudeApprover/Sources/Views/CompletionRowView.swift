import SwiftUI

/// Card for tool completion events.
/// Shows the result summary and a "Go to Terminal" button.
struct CompletionRowView: View {
    let completion: CompletionInfo
    let onGoToTerminal: () -> Void
    let onDismiss: () -> Void

    private var statusColor: Color {
        completion.isError ? .red : .green
    }

    private var statusIcon: String {
        completion.isError ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(completion.isError ? "Failed" : "Completed")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                Text(completion.toolName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Result summary
            if !completion.resultSummary.isEmpty {
                Text(completion.resultSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(statusColor.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Go to Terminal button
            HStack {
                Spacer()
                Button(action: onGoToTerminal) {
                    Label("Go to Terminal", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(statusColor)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
