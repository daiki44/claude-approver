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

    func clear() {
        items.removeAll()
    }
}
