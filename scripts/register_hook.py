#!/usr/bin/env python3
"""
Register the ClaudeApprover PermissionRequest hook in ~/.claude/settings.json.
Idempotent: safe to run multiple times.
Also migrates from the old PreToolUse registration if present.
"""

import json
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"
HOOK_COMMAND = "python3 ~/.claude/claude-approver/hook/permission_request.py"
HOOK_TIMEOUT = 310  # 5 min socket timeout + 10s margin

HOOK_ENTRY = {
    "matcher": ".*",
    "hooks": [
        {
            "type": "command",
            "command": HOOK_COMMAND,
            "timeout": HOOK_TIMEOUT,
        }
    ],
}


def main():
    if not SETTINGS_PATH.exists():
        print(f"Error: {SETTINGS_PATH} not found", file=sys.stderr)
        sys.exit(1)

    with open(SETTINGS_PATH, "r") as f:
        settings = json.load(f)

    hooks = settings.setdefault("hooks", {})

    # Migrate: remove old PreToolUse registration if present
    pre_tool_use = hooks.get("PreToolUse", [])
    hooks["PreToolUse"] = [
        entry for entry in pre_tool_use
        if not any(
            h.get("command", "").endswith("permission_request.py")
            for h in entry.get("hooks", [])
        )
    ]
    if not hooks["PreToolUse"]:
        del hooks["PreToolUse"]

    # Register under PermissionRequest
    perm_request = hooks.setdefault("PermissionRequest", [])

    # Check if already registered
    for entry in perm_request:
        for h in entry.get("hooks", []):
            if h.get("command", "").endswith("permission_request.py"):
                print("Hook already registered under PermissionRequest. Skipping.")
                return

    # Insert at the beginning
    perm_request.insert(0, HOOK_ENTRY)

    with open(SETTINGS_PATH, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print("Hook registered successfully under PermissionRequest.")
    print(f"  matcher: .*")
    print(f"  command: {HOOK_COMMAND}")
    print(f"  timeout: {HOOK_TIMEOUT}s")
    print()
    print("Restart Claude Code for the hook to take effect.")


if __name__ == "__main__":
    main()
