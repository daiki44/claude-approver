import SwiftUI

/// Structured info for a trust (always-allow) option, derived from a permission suggestion.
struct TrustOptionInfo {
    let label: String
    let icon: String
    let scopeLabel: String
    let isPermanent: Bool
}

/// A single row in the "Remember this decision" disclosure section.
/// Shows an icon, descriptive label, and a colored scope badge (Permanent / This session).
struct TrustOptionRow: View {
    let info: TrustOptionInfo
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: info.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(info.label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(info.scopeLabel)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(info.isPermanent ? .orange : .blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (info.isPermanent ? Color.orange : Color.blue).opacity(0.12)
                    )
                    .clipShape(Capsule())
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(isHovering ? Color(.controlBackgroundColor) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
