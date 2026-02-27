import SwiftUI

/// Card for standard tool permission requests (Bash, Write, MCP, etc.).
/// Includes risk badge, command display, trust options disclosure, and Allow / Deny actions.
struct ToolPermissionRowView: View {
    let request: PermissionRequest
    let onAllow: () -> Void
    let onDeny: () -> Void
    let onAlwaysAllow: ([[String: Any]]) -> Void
    let onDenyWithMessage: (String) -> Void

    @State private var showDenyReason = false
    @State private var denyReason = ""
    @State private var showTrustOptions = false
    @State private var isCommandExpanded = false

    /// Whether the command text is long enough to warrant a Show more/less toggle
    private var isCommandTruncatable: Bool {
        let text = request.displayCommand
        return text.count > 200
            || text.components(separatedBy: "\n").count > 5
    }

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

            // Command / input — specialized for Edit and Write tools
            if request.isEditTool {
                EditDiffView(request: request)
            } else if request.isWriteTool {
                WriteContentView(request: request)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(request.displayCommand)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(isCommandExpanded ? nil : 5)
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard isCommandTruncatable else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCommandExpanded.toggle()
                            }
                        }

                    if isCommandTruncatable {
                        Divider()
                            .opacity(0.5)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCommandExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isCommandExpanded ? "chevron.up" : "ellipsis")
                                    .font(.caption2)
                                Text(isCommandExpanded ? "Show less" : "Show more")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.textBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Trust options disclosure section (only if suggestions available)
            if !request.permissionSuggestions.isEmpty {
                trustOptionsSection
            }

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

            // Action buttons (all right-aligned)
            HStack(spacing: 6) {
                // Always Allow menu (only if suggestions available)
                if !request.permissionSuggestions.isEmpty {
                    Menu {
                        ForEach(Array(request.permissionSuggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button(Self.labelForSuggestion(suggestion, defaultTool: request.toolName)) {
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
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Deny with message")

                Button(action: onDeny) {
                    Text("Deny")
                        .frame(minWidth: 44, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onAllow) {
                    Text("Allow")
                        .frame(minWidth: 52, minHeight: 28)
                        .contentShape(Rectangle())
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

    // MARK: - Suggestion Label

    /// Generate a human-readable label from a permission suggestion.
    /// Maps structured suggestion types to descriptive text matching
    /// Claude Code's terminal UI choices.
    private static func labelForSuggestion(_ suggestion: [String: Any], defaultTool: String) -> String {
        // Check for explicit prompt/label from Claude Code
        if let prompt = suggestion["prompt"] as? String { return prompt }
        if let label = suggestion["label"] as? String { return label }

        let type = suggestion["type"] as? String
        let tool = suggestion["tool"] as? String ?? defaultTool
        let destination = suggestion["destination"] as? String
        let scope = destination == "session" ? " (session)" : ""

        switch type {
        case "setMode":
            let mode = suggestion["mode"] as? String ?? ""
            switch mode {
            case "acceptEdits": return "Auto-accept edits\(scope)"
            default: return "Set mode: \(mode)\(scope)"
            }
        case "addDirectories":
            if let dirs = suggestion["directories"] as? [String], let first = dirs.first {
                return "Allow \(tool) in \(shortenPath(first))"
            }
            return "Allow \(tool) in project"
        default:
            return "Always allow \(tool)"
        }
    }

    private static func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return (path as NSString).lastPathComponent
    }
    // MARK: - Trust Options Disclosure

    @ViewBuilder
    private var trustOptionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Disclosure toggle — generous hit area
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTrustOptions.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(showTrustOptions ? 90 : 0))
                    Text("Remember this decision...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(minHeight: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showTrustOptions {
                let trustOptions = request.permissionSuggestions.map { suggestion in
                    Self.infoForSuggestion(suggestion, defaultTool: request.toolName, projectName: request.projectName)
                }
                let hasAnyPermanent = trustOptions.contains { $0.isPermanent }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(zip(request.permissionSuggestions.indices, trustOptions)), id: \.0) { index, info in
                        TrustOptionRow(info: info) {
                            onAlwaysAllow([request.permissionSuggestions[index]])
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)

                    Text(hasAnyPermanent
                         ? "Adds a permanent rule to your Claude Code settings."
                         : "Applies to the current session only.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(8)
                .background(Color(.controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Suggestion → TrustOptionInfo

    /// Convert a raw permission suggestion dict into structured display info.
    static func infoForSuggestion(
        _ suggestion: [String: Any],
        defaultTool: String,
        projectName: String
    ) -> TrustOptionInfo {
        // Check for explicit prompt/label from Claude Code
        if let prompt = suggestion["prompt"] as? String {
            let destination = suggestion["destination"] as? String
            let isPermanent = destination != "session"
            return TrustOptionInfo(
                label: prompt,
                icon: "checkmark.shield",
                scopeLabel: isPermanent ? "Permanent" : "This session",
                isPermanent: isPermanent
            )
        }

        let destination = suggestion["destination"] as? String
        let isPermanent = destination != "session"
        let scopeLabel = isPermanent ? "Permanent" : "This session"
        let type = suggestion["type"] as? String
        let tool = suggestion["tool"] as? String ?? defaultTool

        switch type {
        case "setMode":
            return TrustOptionInfo(
                label: "Auto-approve file edits",
                icon: "pencil.and.outline",
                scopeLabel: scopeLabel,
                isPermanent: isPermanent
            )
        case "addDirectories":
            return TrustOptionInfo(
                label: "Allow \(tool) in \(projectName)",
                icon: "folder.badge.checkmark",
                scopeLabel: scopeLabel,
                isPermanent: isPermanent
            )
        default:
            return TrustOptionInfo(
                label: "Allow \(tool) without asking",
                icon: "checkmark.shield",
                scopeLabel: scopeLabel,
                isPermanent: isPermanent
            )
        }
    }
}
