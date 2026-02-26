#!/usr/bin/env python3
"""
PermissionRequest Hook: Permission Request
Claude Code の許可ダイアログ表示時に発火し、ClaudeApprover.app に
Unix Socket 経由でリクエストを送信してユーザーの代わりに許可/拒否する。

PermissionRequest は許可ダイアログが表示される場面でのみ発火するため、
Read/Edit/Write 等の Claude Code 内部で自動承認されるツールや
settings.json の allow リスト内のツールでは発火しない。

Exit codes:
  0 - Hook が判定を返した (stdout に JSON)
  1 - パススルー (通常の承認ダイアログに委ねる)
"""

import json
import os
import socket
import struct
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SOCKET_DIR = Path.home() / "Library" / "Application Support" / "ClaudeApprover"
SOCKET_PATH = SOCKET_DIR / "claude-approver.sock"
TIMEOUT_SECONDS = 300  # 5 minutes
LOG_PATH = Path.home() / ".claude" / "approver_debug.log"


def _debug_log(msg: str):
    if not os.environ.get("CLAUDE_APPROVER_DEBUG"):
        return
    try:
        with open(LOG_PATH, "a") as f:
            f.write(f"[{datetime.now().isoformat()}] {msg}\n")
    except Exception:
        pass


def _send_request(request: dict) -> dict | None:
    """
    Unix Socket 経由で ClaudeApprover.app にリクエストを送信し、
    応答を受信する。App 未起動時は None を返す。

    フレーミング: 4バイト big-endian uint32 長さヘッダー + UTF-8 JSON ボディ
    """
    if not SOCKET_PATH.exists():
        return None

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(str(SOCKET_PATH))

        # Send: length-prefixed JSON
        body = json.dumps(request).encode("utf-8")
        header = struct.pack("!I", len(body))
        sock.sendall(header + body)

        # Receive: length-prefixed JSON
        raw_header = _recv_exact(sock, 4)
        if raw_header is None:
            return None
        (resp_len,) = struct.unpack("!I", raw_header)
        raw_body = _recv_exact(sock, resp_len)
        if raw_body is None:
            return None

        return json.loads(raw_body.decode("utf-8"))
    except (ConnectionRefusedError, FileNotFoundError, OSError):
        # App not running or socket gone
        return None
    except socket.timeout:
        # Timeout -> passthrough (fail-open: let terminal handle it)
        return None
    finally:
        try:
            sock.close()
        except Exception:
            pass


def _recv_exact(sock: socket.socket, n: int) -> bytes | None:
    """Receive exactly n bytes from socket."""
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def main():
    try:
        stdin_data = sys.stdin.read()
        hook_input = json.loads(stdin_data)

        tool_name = hook_input.get("tool_name", "")
        tool_input = hook_input.get("tool_input", {})
        session_id = hook_input.get("session_id", "")
        cwd = hook_input.get("cwd", "")

        tool_use_id = hook_input.get("tool_use_id", "")
        permission_suggestions_raw = hook_input.get("permission_suggestions", [])
        _debug_log(f"PermissionRequest: tool={tool_name} tool_use_id={tool_use_id} input_keys={list(tool_input.keys())} hook_keys={list(hook_input.keys())}")
        _debug_log(f"  permission_suggestions={json.dumps(permission_suggestions_raw, default=str)}")

        # PermissionRequest only fires when Claude Code is about to show
        # a permission dialog — no need to check allow/deny lists.
        # Send ALL requests to ClaudeApprover.app.
        permission_suggestions = hook_input.get("permission_suggestions", [])

        request_id = str(uuid.uuid4())
        request = {
            "request_id": request_id,
            "tool_name": tool_name,
            "tool_input": tool_input,
            "tool_use_id": hook_input.get("tool_use_id", ""),
            "session_id": session_id,
            "cwd": cwd,
            "received_at": datetime.now(timezone.utc).isoformat(),
            "permission_suggestions": permission_suggestions,
        }

        response = _send_request(request)

        if response is None:
            # App not running -> passthrough to normal approval dialog
            _debug_log(f"  -> PASSTHROUGH (app not running)")
            sys.exit(1)

        user_decision = response.get("decision", "deny")
        resp_message = response.get("message")
        resp_permissions = response.get("updated_permissions")
        _debug_log(f"  -> decision={user_decision} message={resp_message} permissions={resp_permissions}")

        # Normalize to allow/deny
        if user_decision not in ("allow", "deny"):
            sys.exit(1)

        # Build decision object for Claude Code
        decision_obj: dict = {"behavior": user_decision}
        if user_decision == "deny" and resp_message:
            decision_obj["message"] = resp_message
            decision_obj["interrupt"] = False
        if user_decision == "allow" and resp_permissions:
            decision_obj["updatedPermissions"] = resp_permissions

        # Return PermissionRequest decision to Claude Code
        output = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": decision_obj,
            }
        }
        print(json.dumps(output))
        sys.exit(0)

    except json.JSONDecodeError:
        # Invalid input -> passthrough
        _debug_log(f"ERROR: JSON decode failed")
        sys.exit(1)
    except Exception as e:
        # Any other error -> passthrough (fail open)
        _debug_log(f"ERROR: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
