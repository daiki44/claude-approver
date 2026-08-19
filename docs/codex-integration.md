# Codex CLI integration

Agent Approver can receive approval requests from Codex CLI and show them in the same macOS menu bar popover used by other supported harnesses.

The integration uses Codex's `PermissionRequest` command hook. Codex sends one JSON object on stdin; the hook forwards it to the app over the existing Unix Domain Socket and returns the app's allow/deny decision to Codex.

Official references:

- [Codex CLI](https://developers.openai.com/codex/cli)
- [OpenAI Docs Hooks reference](https://learn.chatgpt.com/docs/hooks)

## Requirements

- macOS 14.0+
- A running Agent Approver app
- Python 3
- Codex CLI with hooks enabled

The app does not need to be rebuilt for each Codex session. The LaunchAgent installed by `make install` keeps the menu bar app running.

## Install

From the repository checkout:

```bash
cd /path/to/agent-approver
python3 scripts/register_codex_hook.py
```

The registration script:

1. Creates or updates `$CODEX_HOME/hooks.json` (`~/.codex/hooks.json` by default).
2. Preserves existing Codex hooks.
3. Adds an idempotent `PermissionRequest` hook for the app's absolute local path.
4. Uses a 310-second hook timeout. The adapter itself closes after 295 seconds, just before the app's 300-second internal fallback, so Codex can return to its native prompt instead of racing a deny response.

After registration, open Codex and run `/hooks`. Review and trust the new command hook. Codex requires non-managed command hooks to be reviewed before they run.

If `CODEX_HOME` is set, the script registers against that directory instead of `~/.codex`.

To remove only this integration:

```bash
python3 scripts/unregister_codex_hook.py
```

## Runtime behavior

Codex requests for Bash, `apply_patch`, and MCP tools are displayed as standard tool-permission cards. The existing Swift app and socket protocol are shared with Claude Code.

- **Allow** returns Codex's `PermissionRequest` allow decision.
- **Deny** returns a deny decision and an optional message.
- **Dismiss, timeout, app unavailable, or hook error** produces no hook decision, so Codex continues to its normal approval prompt.
- Claude-specific `updatedPermissions`, `AskUserQuestion`, and `ExitPlanMode` behavior is not exposed through the Codex adapter.
- Agent auto-approval is intentionally not inferred from Codex transcript paths or undocumented fields.

This is fail-open by design: the adapter must never make the native Codex prompt unavailable just because the menu bar app is not running.

## Data flow

```text
Codex CLI
  └─ PermissionRequest hook
       └─ hook/codex_permission_request.py
            └─ Unix Domain Socket
                 └─ ClaudeApprover.app
                      └─ allow / deny / no decision
```

The app-facing request includes `source: "codex"`, `session_id`, `turn_id`, `cwd`, `tool_name`, and `tool_input`. The adapter generates an internal UUID because the Swift socket server requires a UUID request key even when the Codex hook payload does not provide one.

## Troubleshooting

### The popover does not appear

Check that the socket exists and the app is running:

```bash
ls -l "$HOME/Library/Application Support/ClaudeApprover/claude-approver.sock"
```

Then confirm the hook is registered:

```bash
python3 scripts/register_codex_hook.py --dry-run
```

If the hook is listed but skipped by Codex, run `/hooks`, review the changed command definition, and trust it.

### Codex still shows its normal prompt

That is expected when the app is unavailable, the hook is not trusted, the request is dismissed, or the request times out. Confirm the app is running and inspect `~/.claude/approver_debug.log` with `CLAUDE_APPROVER_DEBUG=1` enabled.

### Disable verbose logging

```bash
unset CLAUDE_APPROVER_DEBUG
```
