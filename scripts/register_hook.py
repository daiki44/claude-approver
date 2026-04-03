#!/usr/bin/env python3
"""
Register ClaudeApprover hooks in ~/.claude/settings.json.
Registers the PermissionRequest hook.
Idempotent: safe to run multiple times.
Also migrates from the old PreToolUse registration if present.
"""

import json
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"

PERM_HOOK_COMMAND = "python3 ~/.claude/claude-approver/hook/permission_request.py"
PERM_HOOK_TIMEOUT = 310  # 5 min socket timeout + 10s margin

POST_TOOL_HOOK_COMMAND = "python3 ~/.claude/claude-approver/hook/post_tool_use.py"
POST_TOOL_HOOK_TIMEOUT = 10  # fire-and-forget, 5s socket timeout + margin

PERM_HOOK_ENTRY = {
    "matcher": ".*",
    "hooks": [
        {
            "type": "command",
            "command": PERM_HOOK_COMMAND,
            "timeout": PERM_HOOK_TIMEOUT,
        }
    ],
}

POST_TOOL_HOOK_ENTRY = {
    "matcher": ".*",
    "hooks": [
        {
            "type": "command",
            "command": POST_TOOL_HOOK_COMMAND,
            "timeout": POST_TOOL_HOOK_TIMEOUT,
        }
    ],
}

def _is_registered(hook_list: list, script_name: str) -> bool:
    """Check if a hook with the given script name is already registered."""
    for entry in hook_list:
        for h in entry.get("hooks", []):
            if h.get("command", "").endswith(script_name):
                return True
    return False


def main():
    if not SETTINGS_PATH.exists():
        print(f"Error: {SETTINGS_PATH} not found", file=sys.stderr)
        sys.exit(1)

    with open(SETTINGS_PATH, "r") as f:
        settings = json.load(f)

    hooks = settings.setdefault("hooks", {})
    changed = False

    # Migrate: remove old PreToolUse registration if present
    pre_tool_use = hooks.get("PreToolUse", [])
    filtered = [
        entry for entry in pre_tool_use
        if not any(
            h.get("command", "").endswith("permission_request.py")
            for h in entry.get("hooks", [])
        )
    ]
    if len(filtered) != len(pre_tool_use):
        changed = True
    if filtered:
        hooks["PreToolUse"] = filtered
    elif "PreToolUse" in hooks:
        del hooks["PreToolUse"]

    # Register PermissionRequest hook
    perm_request = hooks.setdefault("PermissionRequest", [])
    if _is_registered(perm_request, "permission_request.py"):
        print("PermissionRequest hook already registered. Skipping.")
    else:
        perm_request.insert(0, PERM_HOOK_ENTRY)
        changed = True
        print("PermissionRequest hook registered.")
        print(f"  matcher: .*")
        print(f"  command: {PERM_HOOK_COMMAND}")
        print(f"  timeout: {PERM_HOOK_TIMEOUT}s")

    # Register PostToolUse hook (completion notification)
    post_tool_use = hooks.setdefault("PostToolUse", [])
    if _is_registered(post_tool_use, "post_tool_use.py"):
        print("PostToolUse hook already registered. Skipping.")
    else:
        post_tool_use.insert(0, POST_TOOL_HOOK_ENTRY)
        changed = True
        print("PostToolUse hook registered.")
        print(f"  matcher: .*")
        print(f"  command: {POST_TOOL_HOOK_COMMAND}")
        print(f"  timeout: {POST_TOOL_HOOK_TIMEOUT}s")

    if changed:
        with open(SETTINGS_PATH, "w") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print()
        print("Restart Claude Code for the hooks to take effect.")
    else:
        print()
        print("All hooks already registered. No changes made.")


if __name__ == "__main__":
    main()
