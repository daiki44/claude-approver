import io
import json
import uuid
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from hook import codex_permission_request as hook


class CodexPermissionRequestTests(unittest.TestCase):
    def _run_hook(self, response, hook_input=None):
        hook_input = hook_input or {
            "session_id": "session-123",
            "turn_id": "turn-456",
            "cwd": "/tmp/project",
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": {"command": "echo hello"},
            "permission_mode": "default",
        }
        captured_requests = []

        def fake_send_request(request, timeout_seconds):
            captured_requests.append((request, timeout_seconds))
            return response

        output = io.StringIO()
        with (
            patch.object(hook, "send_request", side_effect=fake_send_request),
            patch("sys.stdin", io.StringIO(json.dumps(hook_input))),
            redirect_stdout(output),
        ):
            exit_code = hook.main()
        return exit_code, output.getvalue(), captured_requests

    def test_allow_response_uses_codex_permission_shape(self):
        exit_code, stdout, requests = self._run_hook({"decision": "allow"})

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        self.assertEqual(
            payload["hookSpecificOutput"],
            {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            },
        )
        self.assertEqual(len(requests), 1)
        request, timeout_seconds = requests[0]
        self.assertEqual(timeout_seconds, 295)
        self.assertEqual(request["source"], "codex")
        self.assertEqual(request["tool_name"], "Bash")
        self.assertEqual(request["tool_input"], {"command": "echo hello"})
        uuid.UUID(request["request_id"])

    def test_deny_response_preserves_message(self):
        exit_code, stdout, _ = self._run_hook(
            {"decision": "deny", "message": "Not allowed in this project"}
        )

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        self.assertEqual(
            payload["hookSpecificOutput"]["decision"],
            {"behavior": "deny", "message": "Not allowed in this project"},
        )

    def test_codex_ignores_claude_updated_permissions(self):
        exit_code, stdout, _ = self._run_hook(
            {"decision": "allow", "updated_permissions": [{"type": "setMode"}]}
        )

        self.assertEqual(exit_code, 0)
        payload = json.loads(stdout)
        self.assertNotIn("updatedPermissions", payload["hookSpecificOutput"]["decision"])

    def test_no_app_response_falls_back_to_codex_prompt(self):
        exit_code, stdout, _ = self._run_hook(None)

        self.assertEqual(exit_code, 0)
        self.assertEqual(stdout, "")

    def test_unsupported_decision_falls_back_to_codex_prompt(self):
        exit_code, stdout, _ = self._run_hook({"decision": "passthrough"})

        self.assertEqual(exit_code, 0)
        self.assertEqual(stdout, "")

    def test_non_object_tool_input_is_wrapped_for_swift_model(self):
        hook_input = {
            "session_id": "session-123",
            "cwd": "/tmp/project",
            "tool_name": "mcp__example__tool",
            "tool_input": "raw input",
        }
        exit_code, _, requests = self._run_hook({"decision": "allow"}, hook_input)

        self.assertEqual(exit_code, 0)
        self.assertEqual(requests[0][0]["tool_input"], {"value": "raw input"})

    def test_malformed_input_is_fail_open(self):
        output = io.StringIO()
        with patch("sys.stdin", io.StringIO("not-json")), redirect_stdout(output):
            exit_code = hook.main()

        self.assertEqual(exit_code, 0)
        self.assertEqual(output.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
