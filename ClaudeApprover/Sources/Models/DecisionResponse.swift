import Foundation

/// Plan approval modes matching Claude Code's terminal UI.
enum PlanApprovalMode: Int, CaseIterable {
    case clearContextAutoAccept = 0  // 1. Clear context + auto-accept edits (DEFAULT)
    case autoAcceptEdits = 1         // 2. Auto-accept edits
    case manualApprove = 2           // 3. Manually approve edits

    var label: String {
        switch self {
        case .clearContextAutoAccept: return "Clear context + auto-accept edits"
        case .autoAcceptEdits: return "Auto-accept edits"
        case .manualApprove: return "Manually approve edits"
        }
    }

    var description: String {
        switch self {
        case .clearContextAutoAccept: return "Clear context and auto-approve Edit/Write tools"
        case .autoAcceptEdits: return "Auto-approve Edit/Write tools"
        case .manualApprove: return "Manually approve each edit"
        }
    }

    /// Edit tool permissions granted by auto-accept modes
    static let editPermissions: [[String: Any]] = [
        ["tool": "Edit"],
        ["tool": "Write"],
        ["tool": "NotebookEdit"],
    ]
}

/// Extended response from the Approver UI back to the hook.
/// Carries not just allow/deny but also optional message and permission updates.
struct DecisionResponse: Sendable {
    let behavior: String  // "allow" or "deny"
    let message: String?  // Deny reason or answer text
    let updatedPermissions: [[String: Any]]?

    static let allow = DecisionResponse(behavior: "allow", message: nil, updatedPermissions: nil)
    static let deny = DecisionResponse(behavior: "deny", message: nil, updatedPermissions: nil)

    /// Passthrough: close the socket without sending a response.
    /// The hook script receives EOF, returns None, and exits with code 1 (passthrough).
    /// This lets Claude Code handle the tool normally (e.g., show question in terminal).
    static let passthrough = DecisionResponse(behavior: "passthrough", message: nil, updatedPermissions: nil)

    static func allowWith(permissions: [[String: Any]]) -> DecisionResponse {
        DecisionResponse(behavior: "allow", message: nil, updatedPermissions: permissions)
    }

    static func denyWith(message: String) -> DecisionResponse {
        DecisionResponse(behavior: "deny", message: message, updatedPermissions: nil)
    }

    /// Build a plan approval response based on the selected mode.
    /// Note: context clearing (option 1 vs 2) cannot be controlled via hooks —
    /// both auto-accept modes send the same response with updatedPermissions.
    static func allowPlan(mode: PlanApprovalMode) -> DecisionResponse {
        switch mode {
        case .clearContextAutoAccept, .autoAcceptEdits:
            return DecisionResponse(
                behavior: "allow",
                message: nil,
                updatedPermissions: PlanApprovalMode.editPermissions
            )
        case .manualApprove:
            return DecisionResponse(
                behavior: "allow",
                message: nil,
                updatedPermissions: nil
            )
        }
    }

    func toJSON() -> [String: Any] {
        var dict: [String: Any] = ["decision": behavior]
        if let message, !message.isEmpty {
            dict["message"] = message
        }
        if let updatedPermissions, !updatedPermissions.isEmpty {
            dict["updated_permissions"] = updatedPermissions
        }
        return dict
    }
}
