import Foundation

/// Classification of permission request types for contextual UX.
enum RequestType: String, Sendable {
    /// Standard tool permission (Bash, Write, MCP, etc.)
    case toolPermission
    /// Claude is asking the user a question (AskUserQuestion)
    case question
    /// Plan mode approval (ExitPlanMode)
    case planApproval

    /// Classify a request based on its tool name.
    static func classify(toolName: String) -> RequestType {
        switch toolName {
        case "AskUserQuestion": return .question
        case "ExitPlanMode": return .planApproval
        default: return .toolPermission
        }
    }

    var displayLabel: String {
        switch self {
        case .toolPermission: return "Permission"
        case .question: return "Question"
        case .planApproval: return "Plan Approval"
        }
    }

    var iconName: String {
        switch self {
        case .toolPermission: return "lock.shield"
        case .question: return "questionmark.bubble"
        case .planApproval: return "doc.text.magnifyingglass"
        }
    }

    var badgeColor: String {
        switch self {
        case .toolPermission: return "orange"
        case .question: return "blue"
        case .planApproval: return "purple"
        }
    }
}
