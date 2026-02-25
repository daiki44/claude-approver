# Swift Conventions

## Platform & Toolchain

- macOS 14+ / Swift 5.9
- SPM only (no Xcode project) — `.app` bundle is created by Makefile
- No external dependencies — Apple frameworks only

## Concurrency

- `actor` for shared mutable state (e.g. `SocketServer`)
- `@MainActor` for all UI-touching code (ViewModels, Views)
- Blocking I/O (socket accept/recv/send) runs on GCD threads, NOT on actor executors
- Use `CheckedContinuation` to bridge GCD → Swift concurrency
- All types crossing concurrency boundaries must be `Sendable`

## Observation & UI

- Use `@Observable` macro (Observation framework), not Combine
- ViewModels are `@Observable @MainActor final class`
- Views use implicit observation — no `@ObservedObject` / `@StateObject` needed

## Architecture (MVVM)

- `ApproverViewModel` is the single top-level ViewModel
- ViewModel owns `SocketServer` (actor) and `RequestQueue` (value type)
- Views are pure — they call ViewModel methods for actions
- Models are plain structs/enums with `Sendable` conformance

## Naming

- Types: `PascalCase`
- Properties / methods: `camelCase`
- Swift enums: `.camelCase` cases (e.g. `.toolPermission`, `.high`)
- File names match the primary type they contain

## Error Handling

- SocketServer errors use a dedicated `SocketError` enum with `LocalizedError`
- Never force-unwrap optionals — use `guard let` or `if let`
- Debug logging via `debugLog()` to `~/.claude/approver_debug.log`
