# Python Hook Conventions

## Fail-Open Principle

Hooks must NEVER block Claude Code on error. Any exception → `sys.exit(1)` → passthrough to normal terminal dialog.

```python
try:
    # ... hook logic ...
except Exception:
    sys.exit(1)  # Always fail open
```

## I/O Contract

- **Input**: JSON from stdin (`sys.stdin.read()`)
- **Output**: JSON to stdout (`print(json.dumps(output))`)
- **Exit 0**: hook handled the request (stdout JSON is used)
- **Exit 1**: passthrough (Claude Code shows its normal dialog)

## Socket Communication

- Path: `~/Library/Application Support/ClaudeApprover/claude-approver.sock`
- Protocol: 4-byte big-endian uint32 length header + UTF-8 JSON body
- If socket file doesn't exist → app not running → return `None` → exit 1

## Timeouts

| Hook | Timeout | Rationale |
|------|---------|-----------|
| `permission_request.py` | 300s | User needs time to review and decide |
| `post_tool_use.py` | 5s | Fire-and-forget notification, no blocking |

## hookSpecificOutput Format

PermissionRequest hooks must return this structure:

```python
{
    "hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": {
            "behavior": "allow" | "deny",
            "message": "...",           # optional, deny reason
            "updatedPermissions": [...] # optional, always-allow rules
        }
    }
}
```

## Dependencies

- Python 3 standard library only (json, socket, struct, sys, uuid, pathlib, datetime)
- No pip dependencies — hooks must work on any macOS with Python 3

## File Structure

| File | Hook Event | Purpose |
|------|------------|---------|
| `permission_request.py` | PermissionRequest | Route approval to GUI app |
| `post_tool_use.py` | PostToolUse | Notify completion to GUI app |
| `permission_matcher.py` | (library) | Match tool calls against settings.json rules |
