#!/usr/bin/env python3
"""
PostToolUse Hook: Tool Completion Notification
Sends tool completion events to ClaudeApprover.app via Unix Socket.
The Approver checks if this tool was previously approved and shows a notification.

This hook is lightweight: it connects to the socket, sends the event, and exits.
If the Approver is not running, it exits immediately with no side effects.
"""

import json
import re
import socket
import struct
import sys
from pathlib import Path

from tty_resolver import resolve_tty

SOCKET_PATH = (
    Path.home() / "Library" / "Application Support" / "ClaudeApprover" / "claude-approver.sock"
)
TIMEOUT_SECONDS = 5  # Short timeout — completion is fire-and-forget

_ANSI_ESCAPE = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')


def _strip_ansi(text: str) -> str:
    """Remove ANSI escape codes from text."""
    return _ANSI_ESCAPE.sub('', text)


def _build_result_summary(tool_name: str, tool_input: dict, tool_result) -> tuple[str, bool]:
    """Extract a brief result summary and error flag from tool_result."""
    is_error = False

    if tool_result is None:
        return ("", False)

    # tool_result can be string or structured
    if isinstance(tool_result, str):
        # Truncate long results
        summary = tool_result[:300]
        is_error = "error" in tool_result.lower()[:100]
        return (summary, is_error)

    if isinstance(tool_result, dict):
        # Bash: {"stdout": "...", "stderr": "...", "exitCode": 0}
        exit_code = tool_result.get("exitCode", tool_result.get("exit_code"))
        stdout = tool_result.get("stdout", "")
        stderr = tool_result.get("stderr", "")

        if exit_code is not None:
            is_error = exit_code != 0
            output = stderr if is_error and stderr else stdout
            lines = output.strip().split("\n")
            # Show last few lines (most relevant for build output)
            snippet = "\n".join(lines[-5:]) if len(lines) > 5 else output.strip()
            prefix = f"Exit {exit_code}"
            summary = f"{prefix}: {snippet}" if snippet else prefix
            return (summary[:300], is_error)

        # Write/Edit: show file path
        if "file_path" in tool_input:
            return (tool_input["file_path"], False)

        # Generic: first string value
        for v in tool_result.values():
            if isinstance(v, str) and v.strip():
                return (v[:300], False)

    return ("", False)


def main():
    if not SOCKET_PATH.exists():
        sys.exit(0)

    try:
        hook_input = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, Exception):
        sys.exit(0)

    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})
    tool_result = hook_input.get("tool_result")
    tool_use_id = hook_input.get("tool_use_id", "")
    session_id = hook_input.get("session_id", "")

    if not tool_use_id:
        sys.exit(0)

    result_summary, is_error = _build_result_summary(tool_name, tool_input, tool_result)
    result_summary = _strip_ansi(result_summary)

    message = {
        "type": "completion",
        "tool_name": tool_name,
        "tool_use_id": tool_use_id,
        "session_id": session_id,
        "cwd": hook_input.get("cwd", ""),
        "tty": resolve_tty(),
        "result_summary": result_summary,
        "is_error": is_error,
    }

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(str(SOCKET_PATH))

        body = json.dumps(message).encode("utf-8")
        header = struct.pack("!I", len(body))
        sock.sendall(header + body)

        # Read ACK (optional — don't block if not available)
        try:
            raw_header = sock.recv(4)
            if raw_header and len(raw_header) == 4:
                (resp_len,) = struct.unpack("!I", raw_header)
                sock.recv(resp_len)
        except Exception:
            pass
    except (ConnectionRefusedError, FileNotFoundError, OSError, socket.timeout):
        pass
    finally:
        try:
            sock.close()
        except Exception:
            pass

    sys.exit(0)


if __name__ == "__main__":
    main()
