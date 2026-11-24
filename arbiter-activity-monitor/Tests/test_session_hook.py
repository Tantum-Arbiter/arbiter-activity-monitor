import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("session_hook", Path(__file__).parents[1] / "scripts/session-hook.py")
assert spec is not None and spec.loader is not None
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class HookTests(unittest.TestCase):
    def test_private_payload_is_not_emitted(self) -> None:
        event = hook.sanitize({"session_id": "abc-123", "hook_event_name": "PreToolUse",
                               "model": "model-fixture", "tool_name": "Bash",
                               "prompt": "PRIVATE", "tool_input": {"command": "PRIVATE"},
                               "tool_response": "PRIVATE", "cwd": "PRIVATE", "transcript_path": "PRIVATE"}, "Codex", 123.0)
        self.assertIsNotNone(event)
        self.assertNotIn("PRIVATE", json.dumps(event))
        with tempfile.TemporaryDirectory() as root:
            hook.append(event, Path(root))
            written = Path(root, "session-events.jsonl").read_text()
            self.assertNotIn("PRIVATE", written)
            self.assertEqual(Path(root, "session-events.jsonl").stat().st_mode & 0o777, 0o600)

    def test_mlx_agents_use_the_same_allowlist_and_other_apps_are_rejected(self) -> None:
        event = hook.sanitize({"session_id": "mlx-1", "hook_event_name": "Stop", "model": "mlx-community/model-fixture",
                               "prompt": "PRIVATE"}, "MLX", 5.0)
        self.assertEqual(event["app"], "MLX")
        self.assertEqual(event["model"], "mlx-community/model-fixture")
        self.assertNotIn("PRIVATE", json.dumps(event))
        self.assertIsNone(hook.sanitize({"session_id": "x", "hook_event_name": "Stop"}, "Other", 1.0))

    def test_unknown_events_and_invalid_identity_are_ignored(self) -> None:
        self.assertIsNone(hook.sanitize({"session_id": "x", "hook_event_name": "Unknown"}, "Claude", 1.0))
        self.assertIsNone(hook.sanitize({"session_id": "has spaces", "hook_event_name": "Stop"}, "Codex", 1.0))


if __name__ == "__main__":
    unittest.main()
