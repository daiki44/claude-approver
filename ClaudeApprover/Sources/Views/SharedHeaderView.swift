import SwiftUI

/// Common header for all request type cards: icon + tool name + type badge + time.
struct SharedHeaderView: View {
    let request: PermissionRequest

    private var badgeColor: Color {
        switch request.requestType {
        case .toolPermission: return .orange
        case .question: return .blue
        case .planApproval: return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Icon + tool name + type badge + time
            HStack {
                Image(systemName: request.iconName)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                Text(request.toolName)
                    .font(.system(.body, design: .monospaced, weight: .semibold))

                Text(request.requestType.displayLabel)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                Text(request.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Row 2: Project path + session ID
            HStack(spacing: 8) {
                Label(request.displayPath, systemImage: "folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(request.shortSessionId)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
