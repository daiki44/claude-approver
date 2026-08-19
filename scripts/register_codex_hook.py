#!/usr/bin/env python3
"""Register ClaudeApprover's Codex PermissionRequest hook idempotently."""

from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
import tempfile
from pathlib import Path
from typing import Any

CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")).expanduser()
HOOKS_PATH = CODEX_HOME / "hooks.json"
HOOK_PATH = Path(__file__).resolve().parents[1] / "hook" / "codex_permission_request.py"
SCRIPT_NAME = HOOK_PATH.name
HOOK_TIMEOUT_SECONDS = 310


def _command() -> str:
    return shlex.join([sys.executable, str(HOOK_PATH)])


def _hook_entry() -> dict[str, Any]:
    return {
        "matcher": ".*",
        "hooks": [
            {
                "type": "command",
                "command": _command(),
                "timeout": HOOK_TIMEOUT_SECONDS,
                "statusMessage": "Waiting for approval in ClaudeApprover",
            }
        ],
    }


def _is_registered(entries: list[Any]) -> bool:
    return any(
        isinstance(entry, dict)
        and any(
            isinstance(handler, dict)
            and SCRIPT_NAME in str(handler.get("command", ""))
            for handler in entry.get("hooks", [])
        )
        for entry in entries
    )


def _load_config() -> dict[str, Any]:
    if not HOOKS_PATH.exists():
        return {"hooks": {}}
    with HOOKS_PATH.open() as config_file:
        config = json.load(config_file)
    if not isinstance(config, dict):
        raise ValueError(f"{HOOKS_PATH} must contain a JSON object")
    hooks = config.get("hooks")
    if hooks is None:
        config["hooks"] = {}
    elif not isinstance(hooks, dict):
        raise ValueError(f"{HOOKS_PATH}: 'hooks' must be a JSON object")
    return config


def _write_config(config: dict[str, Any]) -> None:
    CODEX_HOME.mkdir(parents=True, exist_ok=True, mode=0o700)
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

    try:
        config = _load_config()
        hooks = config["hooks"]
        permission_requests = hooks.setdefault("PermissionRequest", [])
        if not isinstance(permission_requests, list):
            raise ValueError(f"{HOOKS_PATH}: 'PermissionRequest' must be a JSON array")

        if _is_registered(permission_requests):
            print(f"Codex PermissionRequest hook already registered in {HOOKS_PATH}")
            return 0

        entry = _hook_entry()
        permission_requests.insert(0, entry)
        if args.dry_run:
            print(json.dumps({"path": str(HOOKS_PATH), "entry": entry}, indent=2))
            return 0

        _write_config(config)
        print(f"Registered Codex PermissionRequest hook in {HOOKS_PATH}")
        print(f"  command: {entry['hooks'][0]['command']}")
        print(f"  timeout: {HOOK_TIMEOUT_SECONDS}s")
        print("Review and trust the hook in Codex with /hooks before using it.")
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
