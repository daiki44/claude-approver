import Foundation

/// Thread-safe queue of pending permission requests.
@Observable
@MainActor
final class RequestQueue {
    private(set) var items: [PermissionRequest] = []

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    func enqueue(_ request: PermissionRequest) {
        items.append(request)
    }

    func dequeue(id: UUID) -> PermissionRequest? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    func dequeueByToolUseId(_ toolUseId: String) -> PermissionRequest? {
        guard let index = items.firstIndex(where: { $0.toolUseId == toolUseId }) else { return nil }
        return items.remove(at: index)
    }

    /// Find and remove the oldest request matching sessionId and toolName.
    /// Used as fallback when tool_use_id is not available in PermissionRequest.
    func dequeueBySessionAndTool(sessionId: String, toolName: String) -> PermissionRequest? {
        guard let index = items.firstIndex(where: {
            $0.sessionId == sessionId && $0.toolName == toolName
        }) else { return nil }
        return items.remove(at: index)
    }

    func clear() {
        items.removeAll()
    }
}
