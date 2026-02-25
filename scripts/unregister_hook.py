#!/usr/bin/env python3
"""
Unregister the ClaudeApprover hook from ~/.claude/settings.json.
Removes from both PermissionRequest and PreToolUse (legacy).
"""

import json
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"


def _remove_hook_entries(hook_list: list) -> tuple[list, int]:
    """Remove entries containing permission_request.py. Returns (filtered, removed_count)."""
    filtered = [
        entry
        for entry in hook_list
        if not any(
            h.get("command", "").endswith("permission_request.py")
            for h in entry.get("hooks", [])
        )
    ]
    return filtered, len(hook_list) - len(filtered)


def main():
    if not SETTINGS_PATH.exists():
        print(f"Error: {SETTINGS_PATH} not found", file=sys.stderr)
        sys.exit(1)

    with open(SETTINGS_PATH, "r") as f:
        settings = json.load(f)

    hooks = settings.get("hooks", {})
    total_removed = 0

    # Remove from PermissionRequest
    if "PermissionRequest" in hooks:
        filtered, removed = _remove_hook_entries(hooks["PermissionRequest"])
        total_removed += removed
        if filtered:
            hooks["PermissionRequest"] = filtered
        else:
            del hooks["PermissionRequest"]

    # Remove from PreToolUse (legacy)
    if "PreToolUse" in hooks:
        filtered, removed = _remove_hook_entries(hooks["PreToolUse"])
        total_removed += removed
        if filtered:
            hooks["PreToolUse"] = filtered
        else:
            del hooks["PreToolUse"]

    if total_removed == 0:
        print("Hook not found. Nothing to unregister.")
        return

    settings["hooks"] = hooks

    with open(SETTINGS_PATH, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Hook unregistered successfully ({total_removed} entries removed).")
    print("Restart Claude Code for the change to take effect.")


if __name__ == "__main__":
    main()
