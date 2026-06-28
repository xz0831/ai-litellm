from __future__ import annotations

import subprocess
import time
from typing import Any


def build_execution_command(
    selected: dict[str, Any],
    prompt: str | None = None,
    *,
    binary: str = "ai-litellm",
) -> list[str]:
    harness = str(selected.get("harness") or "")
    model = str(selected.get("model") or "")
    if not harness or not model:
        raise ValueError("selected route must include harness and model")

    base = [binary, "harness", "launch", harness, model]
    if prompt is None:
        return base

    if harness == "claude":
        return [*base, "-p", prompt, "--no-session-persistence", "--tools", ""]
    if harness == "codex":
        return [*base, "exec", "--skip-git-repo-check", "--sandbox", "read-only", prompt]
    if harness == "opencode":
        return [*base, "run", "--agent", "plan", "--format", "json", prompt]
    raise ValueError(f"unsupported harness for one-shot execution: {harness}")


def _limit_text(value: str, limit: int) -> tuple[str, bool]:
    if limit <= 0 or len(value) <= limit:
        return value, False
    return value[:limit], True


def run_command(command: list[str], *, timeout: float, capture_limit: int) -> dict[str, Any]:
    started = time.monotonic()
    try:
        proc = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        stdout, stdout_truncated = _limit_text(proc.stdout or "", capture_limit)
        stderr, stderr_truncated = _limit_text(proc.stderr or "", capture_limit)
        return {
            "exitCode": proc.returncode,
            "durationMs": round((time.monotonic() - started) * 1000),
            "stdout": stdout,
            "stderr": stderr,
            "truncated": {
                "stdout": stdout_truncated,
                "stderr": stderr_truncated,
            },
        }
    except subprocess.TimeoutExpired as exc:
        stdout_raw = exc.stdout if isinstance(exc.stdout, str) else (exc.stdout or b"").decode(errors="replace")
        stderr_raw = exc.stderr if isinstance(exc.stderr, str) else (exc.stderr or b"").decode(errors="replace")
        stdout, stdout_truncated = _limit_text(stdout_raw, capture_limit)
        stderr, stderr_truncated = _limit_text(stderr_raw, capture_limit)
        return {
            "exitCode": 124,
            "durationMs": round((time.monotonic() - started) * 1000),
            "stdout": stdout,
            "stderr": stderr,
            "timedOut": True,
            "truncated": {
                "stdout": stdout_truncated,
                "stderr": stderr_truncated,
            },
        }
