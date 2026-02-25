import SwiftUI

/// Card for standard tool permission requests (Bash, Write, MCP, etc.).
/// Includes risk badge, command display, and Allow / Deny / Always Allow actions.
struct ToolPermissionRowView: View {
    let request: PermissionRequest
    let onAllow: () -> Void
    let onDeny: () -> Void
    let onAlwaysAllow: ([[String: Any]]) -> Void
    let onDenyWithMessage: (String) -> Void

    @State private var showDenyReason = false
    @State private var denyReason = ""

    private var riskColor: Color {
        switch request.riskLevel {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SharedHeaderView(request: request)

            // Risk badge
            HStack {
                Text(request.riskLevel.label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(riskColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(riskColor.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
            }

            // Command / input
            Text(request.displayCommand)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(5)
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Deny reason (expandable)
            if showDenyReason {
                HStack(spacing: 4) {
                    TextField("Deny reason (optional)", text: $denyReason)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button("Send") {
                        onDenyWithMessage(denyReason)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(denyReason.isEmpty)
                }
            }

            // Action buttons
            HStack {
                // Always Allow menu (only if suggestions available)
                if !request.permissionSuggestions.isEmpty {
                    Menu {
                        ForEach(Array(request.permissionSuggestions.enumerated()), id: \.offset) { _, suggestion in
                            let tool = suggestion["tool"] as? String ?? request.toolName
                            Button("Always allow \(tool)") {
                                onAlwaysAllow([suggestion])
                            }
                        }
                    } label: {
                        Label("Always Allow", systemImage: "checkmark.shield")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Spacer()

                Button {
                    showDenyReason.toggle()
                } label: {
                    Image(systemName: "text.bubble")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Deny with message")

                Button(action: onDeny) {
                    Label("Deny", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onAllow) {
                    Label("Allow", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(riskColor.opacity(0.4), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}
