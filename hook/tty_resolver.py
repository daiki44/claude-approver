"""
TTY Resolver: Resolve the controlling TTY for the current process.
Walks up the process tree using `ps` to find the shell's TTY device path.

Used by both permission_request.py and post_tool_use.py to identify
which terminal tab the Claude Code session is running in.
"""

import os
import subprocess


def resolve_tty():
    """
    Get the controlling TTY by walking up the process tree.

    Returns: "/dev/ttysXXX" string, or None if unavailable.
    """
    pid = os.getpid()

    for _ in range(10):
        try:
            result = subprocess.run(
                ["ps", "-p", str(pid), "-o", "tty=,ppid="],
                capture_output=True,
                text=True,
                timeout=2,
            )
            if result.returncode != 0:
                return None

            line = result.stdout.strip()
            if not line:
                return None

            parts = line.split()
            if len(parts) < 2:
                return None

            tty_val = parts[0]
            ppid = int(parts[1])

            if tty_val not in ("??", "?", "-", ""):
                # macOS ps outputs "s000" format -> convert to "/dev/ttys000"
                if tty_val.startswith("s"):
                    return f"/dev/tty{tty_val}"
                if tty_val.startswith("/dev/"):
                    return tty_val
                return f"/dev/{tty_val}"

            # No TTY at this level -> walk up to parent
            if ppid <= 1:
                return None
            pid = ppid

        except (subprocess.TimeoutExpired, ValueError, OSError):
            return None

    return None
