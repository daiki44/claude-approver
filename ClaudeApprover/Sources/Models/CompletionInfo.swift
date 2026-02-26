import Foundation

/// Tool completion event received from PostToolUse hook.
struct CompletionInfo: Identifiable, Sendable {
    let id = UUID()
    let toolName: String
    let toolUseId: String
    let sessionId: String
    let tty: String?
    let cwd: String
    let resultSummary: String
    let isError: Bool
    let receivedAt = Date()
}
