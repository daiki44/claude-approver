import SwiftUI

/// Inline diff view for Edit tool operations.
/// Shows old_string (deletion) and new_string (addition) in a git-diff style.
struct EditDiffView: View {
    let request: PermissionRequest

    @State private var isExpanded = true

    /// Maximum lines to show before truncation (per section)
    private let maxCollapsedLines = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // File path header
            filePathHeader

            // Diff content
            if isExpanded {
                diffContent
            }
        }
    }

    // MARK: - File Path Header

    @ViewBuilder
    private var filePathHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                if let fileName = request.editFileName {
                    Text(fileName)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(.primary)
                }

                if request.editReplaceAll {
                    Text("replace all")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                // Change summary
                changeSummaryBadge
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        // Full path (subtle)
        if let path = request.editFilePath {
            Text(shortenPath(path))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Change Summary Badge

    @ViewBuilder
    private var changeSummaryBadge: some View {
        let oldLines = request.editOldString?.components(separatedBy: "\n").count ?? 0
        let newLines = request.editNewString?.components(separatedBy: "\n").count ?? 0

        HStack(spacing: 4) {
            if oldLines > 0 {
                Text("−\(oldLines)")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(Color(.systemRed))
            }
            if newLines > 0 {
                Text("+\(newLines)")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(Color(.systemGreen))
            }
        }
    }

    // MARK: - Diff Content

    @ViewBuilder
    private var diffContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Removed lines (old_string)
            if let oldString = request.editOldString, !oldString.isEmpty {
                DiffSection(
                    text: oldString,
                    kind: .removal,
                    maxLines: maxCollapsedLines
                )
            }

            // Separator between old and new
            if request.editOldString != nil && request.editNewString != nil {
                Divider()
                    .background(Color(.separatorColor))
            }

            // Added lines (new_string)
            if let newString = request.editNewString, !newString.isEmpty {
                DiffSection(
                    text: newString,
                    kind: .addition,
                    maxLines: maxCollapsedLines
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Helpers

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - DiffSection

/// A section of diff lines (either all additions or all removals).
struct DiffSection: View {
    let text: String
    let kind: DiffKind
    let maxLines: Int

    @State private var showAll = false

    enum DiffKind {
        case addition, removal

        var prefix: String {
            switch self {
            case .addition: return "+"
            case .removal: return "−"
            }
        }

        var backgroundColor: Color {
            switch self {
            case .addition: return Color(.systemGreen).opacity(0.08)
            case .removal: return Color(.systemRed).opacity(0.08)
            }
        }

        var prefixColor: Color {
            switch self {
            case .addition: return Color(.systemGreen)
            case .removal: return Color(.systemRed)
            }
        }

        var highlightColor: Color {
            switch self {
            case .addition: return Color(.systemGreen).opacity(0.15)
            case .removal: return Color(.systemRed).opacity(0.15)
            }
        }
    }

    private var lines: [String] {
        text.components(separatedBy: "\n")
    }

    private var isTruncated: Bool {
        lines.count > maxLines
    }

    private var displayLines: [String] {
        if showAll || !isTruncated {
            return lines
        }
        return Array(lines.prefix(maxLines))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .top, spacing: 0) {
                    // Prefix column (fixed width)
                    Text(kind.prefix)
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .foregroundStyle(kind.prefixColor)
                        .frame(width: 18, alignment: .center)
                        .padding(.vertical, 1)

                    // Line content
                    Text(line.isEmpty ? " " : line)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 1)
                        .padding(.trailing, 6)

                    Spacer(minLength: 0)
                }
                .background(index % 2 == 0 ? kind.backgroundColor : kind.highlightColor)
            }

            // "Show more" button when truncated
            if isTruncated && !showAll {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAll = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis")
                            .font(.caption2)
                        Text("\(lines.count - maxLines) more lines")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(kind.backgroundColor.opacity(0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - WriteContentView

/// Preview of file content being written by the Write tool.
struct WriteContentView: View {
    let request: PermissionRequest
    let maxLines: Int = 12

    @State private var isExpanded = true
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // File path header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    if let fileName = request.editFileName {
                        Text(fileName)
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundStyle(.primary)
                    }

                    Text("new file")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    if let content = request.writeContent {
                        let lineCount = content.components(separatedBy: "\n").count
                        Text("+\(lineCount)")
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundStyle(Color(.systemGreen))
                    }
                }
                .frame(minHeight: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Full path
            if let path = request.editFilePath {
                Text(shortenPath(path))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Content preview
            if isExpanded, let content = request.writeContent {
                DiffSection(
                    text: content,
                    kind: .addition,
                    maxLines: maxLines
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor).opacity(0.5), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
