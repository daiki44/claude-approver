#!/usr/bin/env python3
"""Length-prefixed Unix Domain Socket transport used by agent hooks."""

from __future__ import annotations

import json
import socket
import struct
from pathlib import Path

SOCKET_PATH = (
    Path.home()
    / "Library"
    / "Application Support"
    / "ClaudeApprover"
    / "claude-approver.sock"
)
MAX_MESSAGE_BYTES = 1_000_000
DEFAULT_TIMEOUT_SECONDS = 300


def send_request(request: dict, timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS) -> dict | None:
    """Send one request and wait for the app's response.

    ``None`` represents every transport failure, including an unavailable app.
    Callers can then fall back to the agent's native approval flow.
    """
    if not SOCKET_PATH.exists():
        return None

    sock: socket.socket | None = None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(timeout_seconds)
        sock.connect(str(SOCKET_PATH))

        body = json.dumps(request, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if not body or len(body) > MAX_MESSAGE_BYTES:
            return None
        sock.sendall(struct.pack("!I", len(body)) + body)

        raw_header = _recv_exact(sock, 4)
        if raw_header is None:
            return None
        (response_length,) = struct.unpack("!I", raw_header)
        if response_length == 0 or response_length > MAX_MESSAGE_BYTES:
            return None

        raw_body = _recv_exact(sock, response_length)
        if raw_body is None:
            return None
        response = json.loads(raw_body.decode("utf-8"))
        return response if isinstance(response, dict) else None
    except (ConnectionRefusedError, FileNotFoundError, OSError, ValueError, struct.error):
        return None
    finally:
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass


def _recv_exact(sock: socket.socket, size: int) -> bytes | None:
    data = bytearray()
    while len(data) < size:
        try:
            chunk = sock.recv(size - len(data))
        except OSError:
            return None
        if not chunk:
            return None
        data.extend(chunk)
    return bytes(data)
