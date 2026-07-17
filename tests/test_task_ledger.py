from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "task-ledger.py"


class TaskLedgerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.base = Path(self.tempdir.name)
        self.root = self.base / "tasks"
        self.worktree = self.base / "worktree"
        self.worktree.mkdir()

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_ledger(
        self, *arguments: str, expect: int = 0
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [
                sys.executable,
                "-I",
                "-B",
                "-S",
                str(SCRIPT),
                "--root",
                str(self.root),
                *arguments,
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, expect, result.stderr)
        return result

    def create_task(self) -> str:
        result = self.run_ledger(
            "create",
            "Cross provider review",
            "--goal",
            "Review and test the current implementation.",
            "--worktree",
            str(self.worktree),
        )
        return result.stdout.strip()

    def test_create_handoff_prompt_launch_and_complete_lifecycle(self) -> None:
        task_id = self.create_task()
        task_file = self.root / f"{task_id}.json"
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(task_file.stat().st_mode), 0o600)

        self.run_ledger(
            "handoff",
            task_id,
            "--from",
            "GLM-5.2-openrouter",
            "--to",
            "local-omlx-gemma4-12b-omlx",
            "--objective",
            "Run a focused local review.",
            "--summary",
            "The gateway migration is complete; inspect the task layer.",
            "--commit",
            "abc123",
            "--tests",
            "unit tests passed",
        )

        plan = json.loads(
            self.run_ledger(
                "prompt", task_id, "--handoff", "latest", "--json"
            ).stdout
        )
        self.assertEqual(plan["route"], "local-omlx-gemma4-12b-omlx")
        self.assertEqual(plan["worktree"], str(self.worktree.resolve()))
        self.assertIn("Run a focused local review.", plan["prompt"])
        self.assertIn("Do not assume the previous model transcript", plan["prompt"])

        self.run_ledger("_mark-launched", task_id)
        self.run_ledger(
            "complete",
            task_id,
            "--summary",
            "Review completed.",
            "--tests",
            "focused tests passed",
            "--close",
        )
        task = json.loads(self.run_ledger("show", task_id, "--json").stdout)
        self.assertEqual(task["status"], "completed")
        self.assertEqual(task["handoffs"][0]["status"], "completed")
        self.assertIsNotNone(task["handoffs"][0]["launchedAt"])
        self.assertEqual(task["handoffs"][0]["resultSummary"], "Review completed.")

    def test_parallel_handoffs_keep_unique_monotonic_indexes(self) -> None:
        task_id = self.create_task()
        processes = [
            subprocess.Popen(
                [
                    sys.executable,
                    "-I",
                    "-B",
                    "-S",
                    str(SCRIPT),
                    "--root",
                    str(self.root),
                    "handoff",
                    task_id,
                    "--to",
                    f"route-{index}",
                    "--objective",
                    f"objective {index}",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for index in range(6)
        ]
        for process in processes:
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stderr or stdout)
        task = json.loads(self.run_ledger("show", task_id, "--json").stdout)
        indexes = sorted(item["index"] for item in task["handoffs"])
        self.assertEqual(indexes, [1, 2, 3, 4, 5, 6])

    def test_invalid_id_and_oversized_text_fail_without_writing(self) -> None:
        self.run_ledger("show", "../../escape", expect=1)
        result = self.run_ledger(
            "create",
            "too-large",
            "--goal",
            "x" * 16_385,
            "--worktree",
            str(self.worktree),
            expect=1,
        )
        self.assertIn("exceeds 16384", result.stderr)
        self.assertEqual(list(self.root.glob("*.json")), [])

    def test_symlink_task_root_is_rejected(self) -> None:
        real_root = self.base / "real-root"
        real_root.mkdir()
        os.symlink(real_root, self.root)
        result = self.run_ledger("list", expect=1)
        self.assertIn("unsafe task root", result.stderr)


if __name__ == "__main__":
    unittest.main()
