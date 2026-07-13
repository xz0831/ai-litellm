#!/usr/bin/env python3
"""Offline contract checks for the ChatGPT and xAI OAuth LiteLLM routes.

The test deliberately never calls a login, refresh, discovery, or inference
endpoint. It validates the production YAML, LiteLLM 1.92.0 adapter surface,
token-path wiring, file permissions, and the redacted auth status contract.
"""

from __future__ import annotations

import importlib.metadata
import importlib.util
import contextlib
import io
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

import yaml


REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "config" / "litellm_config.yaml"
OAUTH_MANAGER = REPO / "config" / "claude-litellm" / "oauth.py"
EXPECTED_LITELLM = "1.92.0"


def _route(payload: dict[str, Any], name: str) -> dict[str, Any]:
    matches = [row for row in payload.get("model_list", []) if row.get("model_name") == name]
    assert len(matches) == 1, f"expected exactly one {name} route, got {len(matches)}"
    params = matches[0].get("litellm_params")
    assert isinstance(params, dict), f"{name} has no litellm_params mapping"
    return params


def _route_entry(payload: dict[str, Any], name: str) -> dict[str, Any]:
    matches = [row for row in payload.get("model_list", []) if row.get("model_name") == name]
    assert len(matches) == 1, f"expected exactly one {name} route, got {len(matches)}"
    return matches[0]


def _mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


def _load_oauth_manager() -> Any:
    spec = importlib.util.spec_from_file_location("claude_litellm_oauth", OAUTH_MANAGER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_oauth_guard() -> Any:
    path = REPO / "config" / "ai_litellm_callbacks" / "oauth_guard.py"
    spec = importlib.util.spec_from_file_location("claude_litellm_oauth_guard", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def _wait_for_models(
    port: int,
    master_key: str,
    *,
    process: subprocess.Popen[bytes] | None = None,
    log_path: Path | None = None,
    timeout: float = 60.0,
) -> dict[str, Any]:
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        if process is not None and process.poll() is not None:
            log = ""
            if log_path is not None and log_path.exists():
                log = log_path.read_text(encoding="utf-8", errors="replace")
            raise RuntimeError(
                f"LiteLLM bootstrap exited with status {process.returncode} before readiness:\n{log}"
            )
        req = urllib.request.Request(
            f"http://127.0.0.1:{port}/v1/models",
            headers={"Authorization": f"Bearer {master_key}"},
        )
        try:
            with urllib.request.urlopen(req, timeout=2) as response:
                return json.loads(response.read() or b"{}")
        except Exception as exc:  # noqa: BLE001 - bounded startup poll
            last = str(exc)
            time.sleep(0.25)
    raise RuntimeError(f"LiteLLM proxy did not expose /v1/models: {last}")


def _assert_lively(port: int) -> None:
    with urllib.request.urlopen(
        f"http://127.0.0.1:{port}/health/liveliness",
        timeout=5,
    ) as response:
        assert response.status == 200
        assert json.loads(response.read() or b"null") == "I'm alive!"


def _stop_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


def _run_bootstrap(
    env: dict[str, str],
    log_path: Path,
) -> tuple[dict[str, Any], str]:
    """Boot the production wrapper and prove both liveness and model discovery."""
    port = _free_port()
    command = [
        sys.executable,
        str(REPO / "config" / "ai_litellm_callbacks" / "proxy_bootstrap.py"),
        "--config",
        str(CONFIG),
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
    ]
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            command,
            cwd=REPO,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
        )
    try:
        models = _wait_for_models(
            port,
            env["LITELLM_MASTER_KEY"],
            process=process,
            log_path=log_path,
        )
        _assert_lively(port)
    finally:
        _stop_process(process)
    return models, log_path.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    assert importlib.metadata.version("litellm") == EXPECTED_LITELLM, (
        f"OAuth adapter contract is pinned to LiteLLM {EXPECTED_LITELLM}"
    )

    # A worker/reloader child would import LiteLLM without this process's OAuth
    # monkeypatches. The production bootstrap must pin one process even when an
    # ambient NUM_WORKERS value or an unsafe CLI option is supplied.
    config_import_root = str(REPO / "config")
    sys.path.insert(0, config_import_root)
    try:
        bootstrap_spec = importlib.util.spec_from_file_location(
            "claude_litellm_proxy_bootstrap",
            REPO / "config" / "ai_litellm_callbacks" / "proxy_bootstrap.py",
        )
        assert bootstrap_spec and bootstrap_spec.loader
        bootstrap = importlib.util.module_from_spec(bootstrap_spec)
        bootstrap_spec.loader.exec_module(bootstrap)
    finally:
        sys.path.remove(config_import_root)
    old_workers = os.environ.get("NUM_WORKERS")
    try:
        os.environ["NUM_WORKERS"] = "9"
        bootstrap._enforce_single_process([])
        assert os.environ["NUM_WORKERS"] == "1"
        bootstrap._enforce_single_process(["--num_workers", "1"])
        bootstrap._enforce_single_process(["--num_workers=1"])
        for unsafe_args in (
            ["--num_workers", "2"],
            ["--num_workers=4"],
            ["--reload"],
            ["--run_gunicorn"],
            ["--run_hypercorn"],
            ["--run_granian"],
        ):
            try:
                bootstrap._enforce_single_process(unsafe_args)
            except SystemExit:
                pass
            else:
                raise AssertionError(f"bootstrap accepted unsafe worker mode: {unsafe_args}")
    finally:
        if old_workers is None:
            os.environ.pop("NUM_WORKERS", None)
        else:
            os.environ["NUM_WORKERS"] = old_workers

    payload = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    assert isinstance(payload, dict)

    chatgpt = _route(payload, "GPT-5.4-chatgpt-oauth")
    assert chatgpt.get("model") == "chatgpt/gpt-5.4"
    assert "api_key" not in chatgpt, "ChatGPT OAuth route must not override OAuth with an API key"
    assert _route_entry(payload, "GPT-5.4-chatgpt-oauth")["model_info"]["x_reasoning_efforts"] == []

    grok = _route(payload, "Grok-4.5-xai-oauth")
    assert grok.get("model") == "xai/grok-4.5"
    assert grok.get("use_xai_oauth") is True
    assert "api_key" not in grok, "xAI OAuth route must not override OAuth with an API key"
    assert _route_entry(payload, "Grok-4.5-xai-oauth")["model_info"]["x_reasoning_efforts"] == [
        "low", "medium", "high",
    ]

    # Importing and constructing these adapters is offline. Access-token methods
    # are intentionally not called here because they may start interactive OAuth.
    from litellm.llms.chatgpt.authenticator import Authenticator
    from litellm.llms.chatgpt.chat.transformation import ChatGPTConfig
    from litellm.llms.xai.chat.transformation import XAIChatConfig
    from litellm.llms.xai.oauth import (
        XAIOAuthAuthenticator,
        XAIOAuthError,
        XAIOAuthLoginRequiredError,
        should_use_xai_oauth,
    )

    assert ChatGPTConfig is not None and XAIChatConfig is not None
    assert should_use_xai_oauth(grok) is True
    assert should_use_xai_oauth({}) is False

    access_sentinel = "ACCESS_TOKEN_MUST_NEVER_BE_PRINTED_7afc0d"
    refresh_sentinel = "REFRESH_TOKEN_MUST_NEVER_BE_PRINTED_94b3c1"
    id_sentinel = "ID_TOKEN_MUST_NEVER_BE_PRINTED_f2e8aa"
    with tempfile.TemporaryDirectory(prefix="claude-litellm-oauth-") as raw_tmp:
        tmp = Path(raw_tmp)
        chatgpt_dir = tmp / "state" / "auth" / "chatgpt"
        grok_dir = tmp / "state" / "auth" / "grok"
        env = os.environ.copy()
        env.update(
            CHATGPT_TOKEN_DIR=str(chatgpt_dir),
            CHATGPT_AUTH_FILE="auth.json",
            XAI_OAUTH_TOKEN_DIR=str(grok_dir),
            XAI_OAUTH_AUTH_FILE="auth.json",
        )
        os.environ.update({key: env[key] for key in (
            "CHATGPT_TOKEN_DIR", "CHATGPT_AUTH_FILE",
            "XAI_OAUTH_TOKEN_DIR", "XAI_OAUTH_AUTH_FILE",
        )})

        # The LiteLLM adapters must resolve exactly to package-owned state paths.
        chatgpt_auth = Authenticator()
        grok_auth = XAIOAuthAuthenticator()
        assert Path(chatgpt_auth.auth_file) == chatgpt_dir / "auth.json"
        assert Path(grok_auth.auth_file) == grok_dir / "auth.json"

        manager = _load_oauth_manager()
        records = {
            "chatgpt": chatgpt_dir / "auth.json",
            "grok": grok_dir / "auth.json",
        }
        for provider, path in records.items():
            manager._secure_parent(path)
            path.write_text(json.dumps({
                "access_token": access_sentinel,
                "refresh_token": refresh_sentinel,
                "expires_at": int(time.time()) + 3600,
            }), encoding="utf-8")
            # Simulate an older/insecure auth file and require the manager to
            # repair it before status can report the credential as safe.
            path.chmod(0o644)
            manager._secure_auth_file(path)
            assert _mode(path.parent) == 0o700, f"unsafe {provider} token directory mode"
            assert _mode(path) == 0o600, f"unsafe {provider} auth file mode"

        completed = subprocess.run(
            [sys.executable, str(OAUTH_MANAGER), "status", "all", "--json"],
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        combined = completed.stdout + completed.stderr
        assert access_sentinel not in combined
        assert refresh_sentinel not in combined
        status_payload = json.loads(completed.stdout)
        assert {row["provider"] for row in status_payload} == {"chatgpt", "grok"}
        for row in status_payload:
            assert row["authenticated"] is True
            assert row["permissionsSafe"] is True
            assert not ({"access_token", "refresh_token", "id_token"} & row.keys())

        # The proxy patch must return a valid cached access token, and a failed
        # refresh must fail fast without starting LiteLLM device login. Neither
        # the original exception nor token sentinels may leak to stderr.
        guard = _load_oauth_guard()
        assert guard.PATCH_ACTIVE is True
        from litellm.llms.chatgpt.authenticator import Authenticator
        from litellm.llms.chatgpt.common_utils import GetAccessTokenError, RefreshAccessTokenError

        auth = Authenticator.__new__(Authenticator)
        auth._read_auth_file = lambda: {"access_token": access_sentinel, "expires_at": time.time() + 3600}
        auth._is_token_expired = lambda _record, _token: False
        assert auth.get_access_token() == access_sentinel

        # Force two callers to observe the same expired record before either
        # can refresh. The process-global guard lock must serialize rotation;
        # the second caller then re-reads and reuses the first caller's token.
        expired_sentinel = "EXPIRED_ACCESS_TOKEN_18c7"
        rotated_sentinel = "ROTATED_ACCESS_TOKEN_c42e"
        shared_auth = {
            "access_token": expired_sentinel,
            "refresh_token": refresh_sentinel,
            "expires_at": 0,
        }
        shared_auth_lock = threading.Lock()
        first_read_barrier = threading.Barrier(2)
        thread_state = threading.local()
        refresh_calls = 0

        def concurrent_read() -> dict[str, Any]:
            reads = getattr(thread_state, "reads", 0) + 1
            thread_state.reads = reads
            with shared_auth_lock:
                snapshot = dict(shared_auth)
            if reads == 1:
                first_read_barrier.wait(timeout=5)
            return snapshot

        def concurrent_refresh(_refresh: str) -> dict[str, Any]:
            nonlocal refresh_calls
            refresh_calls += 1
            rotated = {
                "access_token": rotated_sentinel,
                "refresh_token": "ROTATED_REFRESH_TOKEN_NOT_PRINTED",
                "expires_at": time.time() + 3600,
            }
            with shared_auth_lock:
                shared_auth.clear()
                shared_auth.update(rotated)
            return rotated

        auth._read_auth_file = concurrent_read
        auth._is_token_expired = lambda _record, token: token != rotated_sentinel
        auth._refresh_tokens = concurrent_refresh
        concurrent_results: list[str] = []
        concurrent_errors: list[BaseException] = []

        def get_concurrently() -> None:
            try:
                concurrent_results.append(auth.get_access_token())
            except BaseException as exc:  # noqa: BLE001 - surfaced below
                concurrent_errors.append(exc)

        workers = [threading.Thread(target=get_concurrently) for _ in range(2)]
        for worker in workers:
            worker.start()
        for worker in workers:
            worker.join(timeout=10)
        assert all(not worker.is_alive() for worker in workers), "OAuth refresh threads deadlocked"
        assert concurrent_errors == []
        assert refresh_calls == 1
        assert concurrent_results == [rotated_sentinel, rotated_sentinel]

        device_login_called = False

        def forbidden_device_login() -> dict[str, str]:
            nonlocal device_login_called
            device_login_called = True
            raise AssertionError("background device login was called")

        def failed_refresh(_refresh: str) -> dict[str, str]:
            raise RefreshAccessTokenError(
                status_code=401,
                message=f"provider refresh failed {refresh_sentinel}",
            )

        auth._read_auth_file = lambda: {"refresh_token": refresh_sentinel}
        auth._refresh_tokens = failed_refresh
        auth._login_device_code = forbidden_device_login
        captured_out, captured_err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(captured_out), contextlib.redirect_stderr(captured_err):
            try:
                auth.get_access_token()
            except GetAccessTokenError as exc:
                safe_exc = exc
                rendered_error = str(exc)
            else:
                raise AssertionError("failed refresh did not raise GetAccessTokenError")
        assert device_login_called is False
        assert safe_exc.__cause__ is None
        rendered_traceback = "".join(traceback.format_exception(safe_exc))
        guard_output = captured_out.getvalue() + captured_err.getvalue() + rendered_error + rendered_traceback
        assert access_sentinel not in guard_output
        assert refresh_sentinel not in guard_output

        # xAI refresh failures may contain the provider response body. The
        # patched adapter must replace both the message and cause chain so a
        # proxy traceback cannot reflect token material from that response.
        xai_auth = XAIOAuthAuthenticator.__new__(XAIOAuthAuthenticator)
        xai_auth._read_auth_file = lambda: {
            "refresh_token": refresh_sentinel,
            "expires_at": 0,
        }
        xai_auth._is_expired = lambda _record: True

        def failed_xai_refresh(_record: dict[str, Any]) -> dict[str, str]:
            raise XAIOAuthError(f"provider refresh failed {id_sentinel}")

        xai_auth._refresh_tokens = failed_xai_refresh
        xai_out, xai_err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(xai_out), contextlib.redirect_stderr(xai_err):
            try:
                xai_auth.get_access_token()
            except XAIOAuthLoginRequiredError as exc:
                safe_xai_exc = exc
                rendered_xai_error = str(exc)
            else:
                raise AssertionError("failed xAI refresh did not require a new login")
        assert safe_xai_exc.__cause__ is None
        rendered_xai_traceback = "".join(traceback.format_exception(safe_xai_exc))
        xai_guard_output = (
            xai_out.getvalue()
            + xai_err.getvalue()
            + rendered_xai_error
            + rendered_xai_traceback
        )
        assert access_sentinel not in xai_guard_output
        assert refresh_sentinel not in xai_guard_output
        assert id_sentinel not in xai_guard_output

        # `login --json` must keep stdout machine-readable. Stub the networked
        # login implementation while exercising the real argparse/emitter path.
        instruction_sentinel = "DEVICE_INSTRUCTION_VISIBLE_ON_STDERR"

        def fake_login(provider: str, force: bool, no_browser: bool) -> dict[str, Any]:
            print(instruction_sentinel)
            return {
                "provider": provider,
                "authenticated": True,
                "path": str(records[provider]),
                "expiresAt": int(time.time()) + 3600,
                "expired": False,
                "permissionsSafe": True,
            }

        manager.login = fake_login
        old_argv = sys.argv
        login_out, login_err = io.StringIO(), io.StringIO()
        try:
            sys.argv = ["claude-litellm auth", "login", "chatgpt", "--json"]
            with contextlib.redirect_stdout(login_out), contextlib.redirect_stderr(login_err):
                assert manager.main() == 0
        finally:
            sys.argv = old_argv
        login_payload = json.loads(login_out.getvalue())
        assert login_payload["provider"] == "chatgpt"
        assert instruction_sentinel in login_err.getvalue()
        assert instruction_sentinel not in login_out.getvalue()
        assert access_sentinel not in login_out.getvalue()
        assert refresh_sentinel not in login_out.getvalue()

        safe_error = manager._safe_error(
            "chatgpt",
            RuntimeError(access_sentinel + refresh_sentinel + id_sentinel),
        )
        assert access_sentinel not in safe_error
        assert refresh_sentinel not in safe_error
        assert id_sentinel not in safe_error

        # The production bootstrap must preserve the authenticated ChatGPT
        # deployment and enumerate OAuth/local routes without an OpenRouter
        # credential. This proves startup does not make an unrelated cloud key
        # a global prerequisite.
        proxy_master = "sk-offline-oauth-startup"
        proxy_env = env.copy()
        for key in ("OPENROUTER_API_KEY", "OPENAI_API_KEY", "XAI_API_KEY"):
            proxy_env.pop(key, None)
        proxy_env["LITELLM_MASTER_KEY"] = proxy_master
        proxy_env["PYTHONPATH"] = str(REPO / "config")
        models_payload, _valid_log = _run_bootstrap(
            proxy_env,
            tmp / "proxy-valid-token-startup.log",
        )
        model_ids = {row.get("id") for row in models_payload.get("data", [])}
        assert "GPT-5.4-chatgpt-oauth" in model_ids
        assert "Grok-4.5-xai-oauth" in model_ids
        assert "Qwen3.6-27B-omlx" in model_ids

        # Regression: LiteLLM 1.92 eagerly initializes chatgpt/* deployments
        # during raw proxy startup. With an empty token directory that invokes
        # the interactive device flow, writes device_code_requested_at into
        # auth.json, and can block a detached gateway. Production therefore
        # boots only through proxy_bootstrap. Its explicit pre-auth policy is to
        # omit the unavailable ChatGPT deployment while keeping every unrelated
        # route available; users add it on the next restart after `auth login`.
        unauthenticated_chatgpt_dir = tmp / "state" / "auth" / "chatgpt-empty"
        unauthenticated_chatgpt_dir.mkdir(mode=0o700, parents=True)
        unauthenticated_env = proxy_env.copy()
        unauthenticated_env["CHATGPT_TOKEN_DIR"] = str(unauthenticated_chatgpt_dir)
        unauthenticated_payload, unauthenticated_log = _run_bootstrap(
            unauthenticated_env,
            tmp / "proxy-empty-chatgpt-startup.log",
        )
        unauthenticated_ids = {
            row.get("id") for row in unauthenticated_payload.get("data", [])
        }
        assert "GPT-5.4-chatgpt-oauth" not in unauthenticated_ids, (
            "pre-auth bootstrap policy must omit the unavailable ChatGPT deployment"
        )
        expected_non_chatgpt_ids = {
            row["model_name"]
            for row in payload["model_list"]
            if not row.get("litellm_params", {}).get("model", "").startswith("chatgpt/")
        }
        assert expected_non_chatgpt_ids <= unauthenticated_ids, (
            "bootstrap removed unrelated routes: "
            f"{sorted(expected_non_chatgpt_ids - unauthenticated_ids)}"
        )
        assert "Grok-4.5-xai-oauth" in unauthenticated_ids
        assert "Qwen3.6-27B-omlx" in unauthenticated_ids

        interactive_markers = (
            "Sign in with ChatGPT using device code:",
            "Enter code:",
            "Device codes are a common phishing target.",
            "https://auth.openai.com/codex/device",
        )
        assert not any(marker in unauthenticated_log for marker in interactive_markers), (
            "bootstrap startup entered the interactive ChatGPT device flow"
        )
        for artifact in unauthenticated_chatgpt_dir.rglob("*"):
            if not artifact.is_file():
                continue
            assert artifact.name != "device_code_requested_at"
            assert b"device_code_requested_at" not in artifact.read_bytes(), (
                f"bootstrap startup wrote a device-flow cooldown marker to {artifact}"
            )

    print(
        "OK: LiteLLM 1.92.0 OAuth routes, guard, redaction, and non-interactive bootstrap are valid."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
