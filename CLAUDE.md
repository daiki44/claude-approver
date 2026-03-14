# ClaudeApprover

macOS menu bar app that replaces Claude Code's terminal permission dialogs with a native GUI.
Python hooks intercept permission requests via Unix Domain Socket and route them to a SwiftUI popover.

## Architecture

```
Claude Code  ──(hook)──>  Python script  ──(UDS)──>  Swift menu bar app
                                                          │
                                                     User decides
                                                     Allow / Deny
                                                          │
Claude Code  <──(hook)──  Python script  <──(UDS)──  DecisionResponse
```

Three layers:
1. **Claude Code** — fires `PermissionRequest` hooks
2. **Python hooks** (`hook/`) — stdin JSON → UDS → stdout JSON; exit 0 = handled, exit 1 = passthrough
3. **Swift app** (`ClaudeApprover/`) — menu bar popover UI, `SocketServer` actor, MVVM

Communication: Unix Domain Socket at `~/Library/Application Support/ClaudeApprover/claude-approver.sock`
Protocol: 4-byte big-endian uint32 length header + UTF-8 JSON body

## Key Concepts

- **Fail-open**: hook errors → exit 1 → Claude Code shows its normal terminal dialog
- **Passthrough**: closing the socket without response → hook gets EOF → exit 1
- **earlyCancelledIds**: handles race condition where cancel arrives before enqueue
- **RequestType**: `toolPermission` (Bash, MCP, etc.), `question` (AskUserQuestion), `planApproval` (ExitPlanMode)

## Agent Auto-Approve

Agent tool 経由のエージェント（同期サブエージェント・バックグラウンドエージェント）からの
PermissionRequest は Python hook 内で自動承認される。GUI に表示せずノイズを排除する。

判別方法（OR 条件）:
1. `hook_input["transcript_path"]` に `/subagents/` が含まれる → 同期サブエージェント
2. `hook_input` に `agent_id` フィールドが存在する → バックグラウンドエージェント等

- メインセッション（`agent_id` なし）: GUI に送信
- エージェント（`agent_id` あり or `/subagents/` パス）: 自動承認
- `transcript_path` が空/未設定かつ `agent_id` なし → GUI に送信（fail-open）

## Build & Install

```bash
make build       # swift build -c release
make bundle      # .app bundle + codesign
make install     # bundle + register hook + LaunchAgent
make uninstall   # remove hook + LaunchAgent
make clean       # swift package clean + remove .app

make start       # launchctl load
make stop        # launchctl unload
make restart     # stop + start
```

## Project Structure

```
ClaudeApprover/
  Package.swift              # SPM (macOS 14+, Swift 5.9, no external deps)
  Sources/
    ClaudeApproverApp.swift  # @main, MenuBarExtra
    AppDelegate.swift        # NSPopover, status bar item
    Models/
      PermissionRequest.swift
      DecisionResponse.swift
      RequestType.swift
      RequestQueue.swift
    ViewModels/
      ApproverViewModel.swift  # @Observable @MainActor, owns SocketServer
    Views/
      PopoverRootView.swift
      RequestListView.swift
      RequestRowView.swift       # delegates to type-specific row
      ToolPermissionRowView.swift
      QuestionRowView.swift
      PlanApprovalRowView.swift
      SharedHeaderView.swift
      EmptyStateView.swift
    Services/
      SocketServer.swift       # actor, UDS accept loop on GCD
      NotificationService.swift
hook/
  permission_request.py   # PermissionRequest hook (timeout 300s)
scripts/
  register_hook.py        # Add hooks to ~/.claude/settings.json
  unregister_hook.py      # Remove hooks
  Info.plist
  launchagent.plist.template  # LaunchAgent (template)
Makefile
```

## Log Files

- `~/.claude/approver_debug.log` — hook + ViewModel debug log
- `~/Library/Logs/ClaudeApprover/stdout.log` — LaunchAgent stdout
- `~/Library/Logs/ClaudeApprover/stderr.log` — LaunchAgent stderr

## Socket Protocol Details

### Permission Request (hook → app)

```json
{
  "request_id": "uuid",
  "tool_name": "Bash",
  "tool_input": {"command": "ls"},
  "tool_use_id": "toolu_xxx",
  "session_id": "...",
  "cwd": "/path/to/project",
  "received_at": "ISO8601",
  "permission_suggestions": []
}
```

### Decision Response (app → hook)

```json
{
  "decision": "allow",
  "request_id": "uuid",
  "message": null,
  "updated_permissions": null
}
```

