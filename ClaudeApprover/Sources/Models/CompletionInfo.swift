import Foundation

/// Tool completion event received from PostToolUse hook.
struct CompletionInfo: Sendable {
    let toolName: String
    let toolUseId: String
    let sessionId: String
    let resultSummary: String
    let isError: Bool
}
