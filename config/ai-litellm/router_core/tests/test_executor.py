import unittest

from router_core.executor import build_execution_command


class ExecutorTests(unittest.TestCase):
    def test_claude_one_shot_command(self):
        cmd = build_execution_command(
            {"harness": "claude", "model": "opus"},
            "Reply OK",
            binary="/tmp/ai-litellm",
        )
        self.assertEqual(cmd, [
            "/tmp/ai-litellm",
            "harness",
            "launch",
            "claude",
            "opus",
            "-p",
            "Reply OK",
            "--no-session-persistence",
            "--tools",
            "",
        ])

    def test_codex_one_shot_command(self):
        cmd = build_execution_command({"harness": "codex", "model": "gpt-5.3-codex"}, "Reply OK")
        self.assertEqual(cmd, [
            "ai-litellm",
            "harness",
            "launch",
            "codex",
            "gpt-5.3-codex",
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "Reply OK",
        ])

    def test_opencode_one_shot_command(self):
        cmd = build_execution_command({"harness": "opencode", "model": "gpt-5.4"}, "Reply OK")
        self.assertEqual(cmd, [
            "ai-litellm",
            "harness",
            "launch",
            "opencode",
            "gpt-5.4",
            "run",
            "--agent",
            "plan",
            "--format",
            "json",
            "Reply OK",
        ])

    def test_unsupported_one_shot_harness_fails(self):
        with self.assertRaisesRegex(ValueError, "unsupported harness"):
            build_execution_command({"harness": "removed", "model": "gpt-5.4"}, "Reply OK")


if __name__ == "__main__":
    unittest.main()
