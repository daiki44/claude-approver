#!/usr/bin/env python3
"""
Permission Matcher: settings.json の allow/deny ルールとツールコールを照合する。
結果が "allow" / "deny" なら Hook は即座に通過、"ask" なら App に承認リクエストを送信。
"""

import json
import os
import re
from pathlib import Path
from typing import Literal

# ---------------------------------------------------------------------------
# Cache: settings.json の mtime が変わるまで再読み込みしない
# ---------------------------------------------------------------------------
_settings_cache: dict | None = None
_settings_mtime: float = 0.0

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"


def _load_settings() -> dict:
    global _settings_cache, _settings_mtime
    try:
        mtime = SETTINGS_PATH.stat().st_mtime
    except FileNotFoundError:
        _settings_cache = {}
        _settings_mtime = 0.0
        return _settings_cache

    if _settings_cache is not None and mtime == _settings_mtime:
        return _settings_cache

    with open(SETTINGS_PATH, "r") as f:
        _settings_cache = json.load(f)
    _settings_mtime = mtime
    return _settings_cache


# ---------------------------------------------------------------------------
# Pattern parsing
# ---------------------------------------------------------------------------

def _parse_permission_pattern(pattern: str) -> tuple[str, str | None]:
    """
    Parse a permission pattern like:
      "Bash(git push:*)"  -> ("Bash", "git push:*")
      "mcp__chrome-devtools" -> ("mcp__chrome-devtools", None)
      "WebSearch"           -> ("WebSearch", None)

    Returns (tool_pattern, arg_pattern) where arg_pattern may be None.
    """
    match = re.match(r'^([^(]+)\((.+)\)$', pattern)
    if match:
        return match.group(1).strip(), match.group(2).strip()
    return pattern.strip(), None


def _tool_name_matches(pattern: str, tool_name: str) -> bool:
    """Check if a tool name matches a permission pattern (prefix matching)."""
    if pattern == tool_name:
        return True
    # Prefix match for patterns like "mcp__chrome-devtools"
    if tool_name.startswith(pattern):
        return True
    return False


def _arg_matches(arg_pattern: str, tool_input: dict) -> bool:
    """
    Check if tool_input matches the argument pattern.
    Patterns like "git push:*" match command starting with "git push".
    Patterns like "domain:*" match any domain in Fetch/WebFetch.

    The wildcard "*" at the end means "anything after this prefix".
    """
    if arg_pattern == "*":
        return True

    # Extract the relevant value from tool_input
    # For Bash: command field
    # For Edit/Write: file_path field
    # For Fetch/WebFetch: url/domain field
    value = ""
    if "command" in tool_input:
        value = tool_input["command"]
    elif "file_path" in tool_input:
        value = tool_input["file_path"]
    elif "url" in tool_input:
        value = tool_input["url"]
    elif "domain" in tool_input:
        value = tool_input["domain"]

    if not value:
        return False

    # Handle wildcard: "git push:*" -> prefix "git push"
    if arg_pattern.endswith(":*"):
        prefix = arg_pattern[:-2]  # Remove ":*"
        return value.startswith(prefix)

    # Handle glob-like patterns for file paths: "/etc/**"
    if "**" in arg_pattern or "*" in arg_pattern:
        # Convert glob to regex
        regex = arg_pattern.replace("**", "<<<DOUBLESTAR>>>")
        regex = regex.replace("*", "[^/]*")
        regex = regex.replace("<<<DOUBLESTAR>>>", ".*")
        regex = f"^{regex}$"
        # Expand ~ to home dir
        regex = regex.replace("~", re.escape(str(Path.home())))
        return bool(re.match(regex, value))

    # Exact match
    return value == arg_pattern


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

CORE_AUTO_APPROVED_TOOLS = frozenset({
    # Read-only tools
    "Read", "Glob", "Grep", "LS",
    "Task", "TodoRead", "TodoWrite",
    "WebSearch", "WebFetch",
    "NotebookRead", "ToolSearch",
    # Edit tools — Claude Code has its own permission system for these
    "Edit", "Write", "NotebookEdit",
    # Meta tools
    "Skill", "AskUserQuestion",
    "EnterPlanMode", "ExitPlanMode",
    "SendMessage",
    "TaskCreate", "TaskGet", "TaskList", "TaskOutput", "TaskStop", "TaskUpdate",
    "TeamCreate", "TeamDelete",
    "EnterWorktree",
    "ListMcpResourcesTool", "ReadMcpResourceTool",
    "TodoWrite",
})


def check_permission(tool_name: str, tool_input: dict) -> Literal["allow", "deny", "ask"]:
    """
    Check if a tool call is explicitly allowed or denied in settings.json.

    Returns:
      "allow" - Tool call is in the allow list -> skip approval
      "deny"  - Tool call is in the deny list  -> skip approval (Claude Code will block)
      "ask"   - Not in either list -> needs user approval via App
    """
    # Core tools that Claude Code auto-approves internally — skip Approver entirely
    if tool_name in CORE_AUTO_APPROVED_TOOLS:
        return "allow"

    settings = _load_settings()
    permissions = settings.get("permissions", {})
    allow_list = permissions.get("allow", [])
    deny_list = permissions.get("deny", [])

    # Check deny list first (deny takes precedence)
    for pattern in deny_list:
        tool_pattern, arg_pattern = _parse_permission_pattern(pattern)
        if _tool_name_matches(tool_pattern, tool_name):
            if arg_pattern is None:
                return "deny"
            if _arg_matches(arg_pattern, tool_input):
                return "deny"

    # Check allow list
    for pattern in allow_list:
        tool_pattern, arg_pattern = _parse_permission_pattern(pattern)
        if _tool_name_matches(tool_pattern, tool_name):
            if arg_pattern is None:
                return "allow"
            if _arg_matches(arg_pattern, tool_input):
                return "allow"

    # Not in either list -> needs approval
    return "ask"
