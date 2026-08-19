#!/usr/bin/env python3
"""Route Codex CLI PermissionRequest hooks to the ClaudeApprover menu bar app.

Codex's hook contract differs slightly from Claude Code's contract:

* no response means "continue with Codex's normal approval prompt";
* PermissionRequest supports only allow/deny decisions;
* Claude-specific permission suggestions must not be returned.

The app-facing request intentionally uses the same length-prefixed socket
protocol as the existing Claude Code hook so both clients can share one app.
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

try:
    from .socket_bridge import send_request
except ImportError:  # Executed directly by Codex as a command hook.
    from socket_bridge import send_request

# Close slightly before SocketServer's 300-second Claude fallback. This lets
# Codex fall back to its native prompt instead of racing the app's deny timeout.
TIMEOUT_SECONDS = 295
LOG_PATH = Path.home() / ".claude" / "approver_debug.log"


def _debug_log(message: str) -> None:
    if not os.environ.get("CLAUDE_APPROVER_DEBUG"):
        return
    try:
        with LOG_PATH.open("a") as log_file:
            log_file.write(f"[{datetime.now().isoformat()}] [Codex] {message}\n")
    except OSError:
        pass


def _text(value: Any) -> str:
    return value if isinstance(value, str) else ""


def build_app_request(hook_input: dict[str, Any]) -> dict[str, Any]:
    tool_input = hook_input.get("tool_input", {})
    if not isinstance(tool_input, dict):
        tool_input = {"value": tool_input}

    request = {
        "request_id": str(uuid.uuid4()),
        "source": "codex",
        "tool_name": _text(hook_input.get("tool_name")),
        "tool_input": tool_input,
        "tool_use_id": _text(hook_input.get("tool_use_id")),
        "turn_id": _text(hook_input.get("turn_id")),
        "session_id": _text(hook_input.get("session_id")),
        "cwd": _text(hook_input.get("cwd")),
        "tty": None,
        "received_at": datetime.now(timezone.utc).isoformat(),
        "permission_suggestions": [],
        "permission_mode": _text(hook_input.get("permission_mode")),
    }
    return request


def _build_hook_output(decision: str, message: str | None = None) -> dict[str, Any]:
    decision_payload: dict[str, str] = {"behavior": decision}
    if decision == "deny" and message:
        decision_payload["message"] = message
    return {
        "hookSpecificOutput": {
            "hookEventName": "PermissionRequest",
            "decision": decision_payload,
        }
    }


def main() -> int:
    try:
        raw_input = sys.stdin.read()
        hook_input = json.loads(raw_input)
        if not isinstance(hook_input, dict):
            raise ValueError("Codex hook input must be a JSON object")

        request = build_app_request(hook_input)
        _debug_log(
            "PermissionRequest: "
            f"tool={request['tool_name']} session={request['session_id'][:8]} "
            f"mode={request['permission_mode']}"
        )

        response = send_request(request, timeout_seconds=TIMEOUT_SECONDS)
        if not isinstance(response, dict):
            _debug_log("-> PASSTHROUGH (app unavailable or closed the request)")
            return 0

        user_decision = response.get("decision")
        if user_decision not in ("allow", "deny"):
            _debug_log(f"-> PASSTHROUGH (unsupported decision={user_decision!r})")
            return 0

        message = response.get("message")
        message = message if isinstance(message, str) else None
        if response.get("updated_permissions"):
            _debug_log("Ignoring Claude-specific updated_permissions for Codex")

        _debug_log(f"-> decision={user_decision} message={message!r}")
        print(json.dumps(_build_hook_output(user_decision, message), ensure_ascii=False))
        return 0
    except (json.JSONDecodeError, OSError, ValueError) as error:
        # Fail open: malformed input or a local transport problem must not block
        # Codex's own approval prompt.
        _debug_log(f"ERROR: {error}")
        return 0
    except Exception as error:  # pragma: no cover - last-resort fail-open guard.
        _debug_log(f"ERROR: {error}")
        return 0


if __name__ == "__main__":
    sys.exit(main())
