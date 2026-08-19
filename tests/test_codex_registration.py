import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTER = ROOT / "scripts" / "register_codex_hook.py"
UNREGISTER = ROOT / "scripts" / "unregister_codex_hook.py"


class CodexRegistrationTests(unittest.TestCase):
    def _run(self, script: Path, codex_home: Path, *args: str):
        environment = os.environ.copy()
        environment["CODEX_HOME"] = str(codex_home)
        return subprocess.run(
            [sys.executable, str(script), *args],
            cwd=ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_register_preserves_existing_hooks_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            codex_home = Path(temporary)
            hooks_path = codex_home / "hooks.json"
            hooks_path.write_text(
                json.dumps(
                    {
                        "hooks": {
                            "PermissionRequest": [
                                {
                                    "matcher": ".*",
                                    "hooks": [
                                        {"type": "command", "command": "/usr/bin/afplay sound.mp3"}
                                    ],
                                }
                            ],
                            "Stop": [{"hooks": [{"type": "command", "command": "echo done"}]}],
                        }
                    }
                )
            )

            first = self._run(REGISTER, codex_home)
            self.assertEqual(first.returncode, 0, first.stderr)
            config = json.loads(hooks_path.read_text())
            permission_hooks = config["hooks"]["PermissionRequest"]
            self.assertEqual(len(permission_hooks), 2)
            self.assertIn("afplay", json.dumps(config))
            self.assertIn("codex_permission_request.py", json.dumps(config))

            second = self._run(REGISTER, codex_home)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(json.loads(hooks_path.read_text()), config)

            removed = self._run(UNREGISTER, codex_home)
            self.assertEqual(removed.returncode, 0, removed.stderr)
            config = json.loads(hooks_path.read_text())
            self.assertEqual(len(config["hooks"]["PermissionRequest"]), 1)
            self.assertIn("afplay", json.dumps(config))
            self.assertNotIn("codex_permission_request.py", json.dumps(config))


if __name__ == "__main__":
    unittest.main()
