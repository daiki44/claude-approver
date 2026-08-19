#!/usr/bin/env python3
"""Remove only ClaudeApprover's Codex hook from hooks.json."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Any

CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()
HOOKS_PATH = CODEX_HOME / "hooks.json"
SCRIPT_NAME = "codex_permission_request.py"


def _load_config() -> dict[str, Any]:
    with HOOKS_PATH.open() as config_file:
        config = json.load(config_file)
    if not isinstance(config, dict) or not isinstance(config.get("hooks"), dict):
        raise ValueError(f"{HOOKS_PATH} must contain a JSON object with a 'hooks' object")
    return config


def _remove_from_entries(entries: list[Any]) -> tuple[list[Any], int]:
    kept_entries: list[Any] = []
    removed = 0
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
            kept_entries.append(entry)
            continue

        kept_handlers = [
            handler
            for handler in entry["hooks"]
            if not (
                isinstance(handler, dict)
                and SCRIPT_NAME in str(handler.get("command", ""))
            )
        ]
        removed += len(entry["hooks"]) - len(kept_handlers)
        if kept_handlers:
            updated_entry = dict(entry)
            updated_entry["hooks"] = kept_handlers
            kept_entries.append(updated_entry)
        elif len(entry["hooks"]) == 0:
            kept_entries.append(entry)
    return kept_entries, removed


def _write_config(config: dict[str, Any]) -> None:
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=CODEX_HOME, prefix=".hooks.json.", delete=False
    ) as temporary:
        json.dump(config, temporary, indent=2, ensure_ascii=False)
        temporary.write("\n")
        temporary_path = Path(temporary.name)
    os.chmod(temporary_path, 0o600)
    os.replace(temporary_path, HOOKS_PATH)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="Print the planned change without writing")
    args = parser.parse_args()

    if not HOOKS_PATH.exists():
        print(f"Codex hooks file not found: {HOOKS_PATH}")
        return 0

    try:
        config = _load_config()
        hooks = config["hooks"]
        entries = hooks.get("PermissionRequest", [])
        if not isinstance(entries, list):
            raise ValueError(f"{HOOKS_PATH}: 'PermissionRequest' must be a JSON array")

        updated_entries, removed = _remove_from_entries(entries)
        if removed == 0:
            print("Codex PermissionRequest hook not found. Nothing changed.")
            return 0

        if updated_entries:
            hooks["PermissionRequest"] = updated_entries
        else:
            hooks.pop("PermissionRequest", None)

        if args.dry_run:
            print(json.dumps(config, indent=2, ensure_ascii=False))
            return 0

        _write_config(config)
        print(f"Removed {removed} ClaudeApprover Codex hook(s) from {HOOKS_PATH}")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
