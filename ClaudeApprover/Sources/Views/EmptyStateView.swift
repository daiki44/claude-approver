import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No pending requests")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Permission requests from Claude Code\nwill appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
