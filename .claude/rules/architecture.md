# Architecture Constraints

## Three-Layer Structure

```
Layer 1: Claude Code (fires hooks)
Layer 2: Python hooks (stdin/stdout JSON, UDS bridge)
Layer 3: Swift menu bar app (GUI, SocketServer actor)
```

This separation must be maintained. Python hooks are the only bridge between Claude Code and the Swift app.

## Passthrough Mechanism

When the app is not running or a request should fall through to the terminal:
1. Hook connects to socket → fails (no socket file or connection refused)
2. `_send_request()` returns `None`
3. Hook exits with code 1
4. Claude Code shows its normal terminal permission dialog

Alternatively, the app can trigger passthrough by closing the socket without sending a response (EOF).

## toolUseId Correlation

- `PermissionRequest` hook sends `tool_use_id` to the app
- App stores approved `toolUseId`s in `approvedToolUseIds`
- `PostToolUse` hook sends completion event with matching `tool_use_id`
- App matches completion to approved request → shows notification

## Race Condition: earlyCancelledIds

When a hook script dies (terminal handles it), the cancel event may arrive before the request is enqueued:
1. `onCancel` fires with `requestId`
2. Request not in queue yet → store in `earlyCancelledIds`
3. `onRequest` fires → check `earlyCancelledIds` → skip enqueue

## RequestType Classification

| Tool Name | RequestType | UI |
|-----------|-------------|-----|
| `AskUserQuestion` | `.question` | Text input / option selection |
| `ExitPlanMode` | `.planApproval` | Plan review with approval modes |
| Everything else | `.toolPermission` | Allow/Deny with command preview |

## State Ownership

- `ApproverViewModel` (`@MainActor`): owns `RequestQueue`, `SocketServer`, completion list
- `SocketServer` (`actor`): owns pending continuations, socket lifecycle
- `RequestQueue`: simple array wrapper, synchronous access from MainActor

## No Xcode Project

The project uses SPM (`Package.swift`) for compilation. The `.app` bundle is manually assembled by `make bundle` (copy binary + Info.plist, codesign). Do not introduce `.xcodeproj` or `.xcworkspace`.
