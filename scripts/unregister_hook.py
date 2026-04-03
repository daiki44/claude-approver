#!/usr/bin/env python3
"""
Unregister ClaudeApprover hooks from ~/.claude/settings.json.
Removes PermissionRequest and PreToolUse (legacy) entries.
"""

import json
import sys
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"


def _remove_hook_entries(hook_list: list, script_name: str) -> tuple[list, int]:
    """Remove entries containing the given script name. Returns (filtered, removed_count)."""
    filtered = [
        entry
        for entry in hook_list
        if not any(
            h.get("command", "").endswith(script_name)
            for h in entry.get("hooks", [])
        )
    ]
    return filtered, len(hook_list) - len(filtered)


def _clean_hook_section(hooks: dict, section: str, script_name: str) -> int:
    """Remove hook entries from a section and clean up empty sections. Returns removed count."""
    if section not in hooks:
        return 0
    filtered, removed = _remove_hook_entries(hooks[section], script_name)
    if filtered:
        hooks[section] = filtered
    else:
        del hooks[section]
    return removed


def main():
    if not SETTINGS_PATH.exists():
        print(f"Error: {SETTINGS_PATH} not found", file=sys.stderr)
        sys.exit(1)

    with open(SETTINGS_PATH, "r") as f:
        settings = json.load(f)

    hooks = settings.get("hooks", {})
    total_removed = 0

    # Remove from PermissionRequest
    total_removed += _clean_hook_section(hooks, "PermissionRequest", "permission_request.py")

    # Remove from PostToolUse
    total_removed += _clean_hook_section(hooks, "PostToolUse", "post_tool_use.py")

    # Remove from PreToolUse (legacy)
    total_removed += _clean_hook_section(hooks, "PreToolUse", "permission_request.py")

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
