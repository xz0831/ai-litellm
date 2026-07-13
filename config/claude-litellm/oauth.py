#!/usr/bin/env python3
"""Manage provider OAuth credentials without exposing token material."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import stat
import sys
import time
from pathlib import Path
from typing import Any


PROVIDERS = ("chatgpt", "grok")


def _auth_path(provider: str) -> Path:
    if provider == "chatgpt":
        root = Path(os.environ["CHATGPT_TOKEN_DIR"])
        filename = os.environ.get("CHATGPT_AUTH_FILE", "auth.json")
    else:
        root = Path(os.environ["XAI_OAUTH_TOKEN_DIR"])
        filename = os.environ.get("XAI_OAUTH_AUTH_FILE", "auth.json")
    return root / filename


def _secure_parent(path: Path) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.parent.chmod(0o700)


def _secure_auth_file(path: Path) -> None:
    if path.exists():
        path.chmod(0o600)


def _read_metadata(provider: str) -> dict[str, Any]:
    path = _auth_path(provider)
    result: dict[str, Any] = {
        "provider": provider,
        "authenticated": False,
        "path": str(path),
        "expiresAt": None,
        "expired": None,
        "permissionsSafe": True,
    }
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return result
    if not isinstance(raw, dict):
        return result

    mode = stat.S_IMODE(path.stat().st_mode)
    expires_at = raw.get("expires_at")
    try:
        expires_at = int(float(expires_at)) if expires_at is not None else None
    except (TypeError, ValueError):
        expires_at = None
    result.update(
        authenticated=bool(raw.get("access_token") or raw.get("refresh_token")),
        expiresAt=expires_at,
        expired=(time.time() >= expires_at) if expires_at is not None else None,
        permissionsSafe=(mode & 0o077) == 0,
    )
    return result


def login(provider: str, force: bool, no_browser: bool) -> dict[str, Any]:
    path = _auth_path(provider)
    _secure_parent(path)
    if provider == "chatgpt":
        print(
            "Experimental: LiteLLM uses the ChatGPT Codex subscription backend; "
            "OpenAI does not document it as a general Claude Code gateway contract.",
            file=sys.stderr,
        )
        if no_browser:
            print("ChatGPT OAuth uses a device code; complete it in any browser.", file=sys.stderr)
        from litellm.llms.chatgpt.authenticator import Authenticator

        if force and path.exists():
            path.unlink()
        Authenticator().get_access_token()
    else:
        from litellm.llms.xai.oauth import XAIOAuthAuthenticator

        XAIOAuthAuthenticator().login(force=force, no_browser=no_browser)
    _secure_auth_file(path)
    result = _read_metadata(provider)
    if not result["authenticated"]:
        raise RuntimeError(f"{provider} OAuth completed without a stored credential")
    return result


def logout(provider: str) -> dict[str, Any]:
    path = _auth_path(provider)
    removed = False
    if path.exists():
        path.unlink()
        removed = True
    return {"provider": provider, "removed": removed, "path": str(path)}


def _emit(payload: Any, as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return
    rows = payload if isinstance(payload, list) else [payload]
    for row in rows:
        provider = row["provider"]
        if "removed" in row:
            print(f"{provider}: {'logged out' if row['removed'] else 'already logged out'}")
        else:
            state = "authenticated" if row["authenticated"] else "not authenticated"
            suffix = "" if row.get("permissionsSafe", True) else " (unsafe file permissions)"
            print(f"{provider}: {state}{suffix}")


def _safe_error(provider: str, exc: Exception) -> str:
    """Return an actionable error without reflecting provider token payloads."""
    error_type = type(exc).__name__
    return (
        f"OAuth error ({error_type}): {provider} authentication failed. "
        f"Run `claude-litellm auth login {provider} --force` to retry."
    )


def main() -> int:
    os.umask(0o077)
    parser = argparse.ArgumentParser(prog="claude-litellm auth")
    sub = parser.add_subparsers(dest="command", required=True)

    login_parser = sub.add_parser("login")
    login_parser.add_argument("provider", choices=PROVIDERS)
    login_parser.add_argument("--force", action="store_true")
    login_parser.add_argument("--no-browser", action="store_true")
    login_parser.add_argument("--json", action="store_true")

    status_parser = sub.add_parser("status")
    status_parser.add_argument("provider", choices=(*PROVIDERS, "all"), nargs="?", default="all")
    status_parser.add_argument("--json", action="store_true")

    logout_parser = sub.add_parser("logout")
    logout_parser.add_argument("provider", choices=PROVIDERS)
    logout_parser.add_argument("--json", action="store_true")

    args = parser.parse_args()
    try:
        if args.command == "login":
            if args.json:
                # LiteLLM's device-flow helpers print browser instructions to
                # stdout. Keep stdout machine-readable without hiding those
                # instructions from the user.
                with contextlib.redirect_stdout(sys.stderr):
                    payload = login(args.provider, args.force, args.no_browser)
            else:
                payload = login(args.provider, args.force, args.no_browser)
        elif args.command == "logout":
            payload = logout(args.provider)
        else:
            selected = PROVIDERS if args.provider == "all" else (args.provider,)
            payload = [_read_metadata(provider) for provider in selected]
        _emit(payload, args.json)
        return 0
    except Exception as exc:
        provider = getattr(args, "provider", "provider")
        print(_safe_error(provider, exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
