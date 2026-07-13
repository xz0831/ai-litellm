"""Keep OAuth refresh non-interactive inside the background LiteLLM proxy.

Explicit login is handled by ``claude-litellm auth login``. LiteLLM 1.92's
ChatGPT authenticator otherwise falls back to a new device-code flow when a
refresh token fails, which can block a detached proxy for fifteen minutes. The
installed proxy imports this module through the callback package and replaces
that fallback with a fast authentication error.
"""

from __future__ import annotations

import inspect
import json
import os
import stat
import tempfile
import threading
from pathlib import Path
from typing import Any


PATCH_ACTIVE = False


def _absolute_env_path(name: str, default: Path | None = None) -> Path:
    value = os.environ.get(name)
    path = Path(value) if value is not None else default
    if path is None:
        raise OSError(f"missing OAuth storage setting: {name}")
    if not path.is_absolute():
        raise OSError(f"OAuth storage path must be absolute: {name}")
    return path


def _auth_filename(name: str, default: str = "auth.json") -> str:
    value = os.environ.get(name, default)
    if (
        not value
        or value in {".", ".."}
        or Path(value).name != value
        or "\x00" in value
    ):
        raise OSError(f"OAuth credential filename must be one path component: {name}")
    return value


def _auth_layout(provider: str) -> tuple[Path, Path, Path, Path, Path]:
    package_root = _absolute_env_path("AI_LITELLM_HOME")
    expected_state_root = package_root / "state"
    state_root = _absolute_env_path("AI_LITELLM_STATE_HOME", expected_state_root)
    if state_root != expected_state_root:
        raise OSError("OAuth state root must be AI_LITELLM_HOME/state")
    expected_auth_root = state_root / "auth"
    auth_root = _absolute_env_path("CLAUDE_LITELLM_AUTH_HOME", expected_auth_root)
    if auth_root != expected_auth_root:
        raise OSError("OAuth auth root must be AI_LITELLM_STATE_HOME/auth")

    if provider == "chatgpt":
        expected_provider_root = auth_root / "chatgpt"
        provider_root = _absolute_env_path("CHATGPT_TOKEN_DIR", expected_provider_root)
        filename = _auth_filename("CHATGPT_AUTH_FILE")
    elif provider == "grok":
        expected_provider_root = auth_root / "grok"
        provider_root = _absolute_env_path("XAI_OAUTH_TOKEN_DIR", expected_provider_root)
        filename = _auth_filename("XAI_OAUTH_AUTH_FILE")
    else:
        raise OSError(f"unsupported OAuth provider: {provider}")
    if provider_root != expected_provider_root:
        raise OSError(f"{provider} OAuth token directory is outside the managed auth root")
    return package_root, state_root, auth_root, provider_root, provider_root / filename


def _validate_parent_chain(
    path: Path,
    provider: str,
    *,
    create: bool,
    repair_permissions: bool,
) -> bool:
    package_root, state_root, auth_root, provider_root, expected_path = _auth_layout(provider)
    if path != expected_path:
        raise OSError(f"{provider} OAuth credential path is outside the managed auth root")

    for index, directory in enumerate((package_root, state_root, auth_root, provider_root)):
        try:
            info = directory.lstat()
        except FileNotFoundError:
            if not create:
                return False
            if index <= 1:
                label = "package root" if index == 0 else "state root"
                raise OSError(f"OAuth {label} does not exist: {directory}") from None
            try:
                directory.mkdir(mode=0o700)
            except FileExistsError:
                pass
            info = directory.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise OSError(f"unsafe OAuth directory in managed path: {directory}")
        if index == 0:
            continue
        if repair_permissions:
            directory.chmod(0o700)
        elif stat.S_IMODE(info.st_mode) & 0o077:
            raise OSError(f"unsafe OAuth directory permissions: {directory}")
    return True


def _read_auth_file_private(path: Path, provider: str) -> dict[str, Any] | None:
    if not _validate_parent_chain(
        path,
        provider,
        create=False,
        repair_permissions=False,
    ):
        return None
    fd = _open_auth_file_fd(path, provider, require_private=True)
    if fd is None:
        return None
    try:
        with os.fdopen(fd, "r", encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _open_auth_file_fd(path: Path, provider: str, *, require_private: bool) -> int | None:
    """Open and validate the credential leaf without following a symlink."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW)
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise OSError(f"unsafe {provider} OAuth credential path") from exc
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise OSError(f"unsafe {provider} OAuth credential path")
        if require_private and stat.S_IMODE(info.st_mode) != 0o600:
            raise OSError(f"unsafe {provider} OAuth credential permissions")
        return fd
    except BaseException:
        os.close(fd)
        raise


def _write_auth_file_atomic(path: Path, provider: str, data: dict[str, Any]) -> None:
    _validate_parent_chain(
        path,
        provider,
        create=True,
        repair_permissions=True,
    )
    existing_fd = _open_auth_file_fd(path, provider, require_private=False)
    if existing_fd is not None:
        os.close(existing_fd)
    fd, staged_raw = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    staged = Path(staged_raw)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(data, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(staged, path)
    finally:
        staged.unlink(missing_ok=True)


def install_noninteractive_chatgpt_auth() -> bool:
    try:
        import litellm  # noqa: F401 - distinguishes local syntax checks from runtime drift
    except ModuleNotFoundError:
        return False

    try:
        from litellm.llms.chatgpt.authenticator import Authenticator
        from litellm.llms.chatgpt.common_utils import (
            CHATGPT_API_BASE,
            GetAccessTokenError,
            RefreshAccessTokenError,
        )
        from litellm.llms.chatgpt.responses.transformation import (
            ChatGPTResponsesAPIConfig,
        )
    except Exception as exc:
        raise RuntimeError(
            "LiteLLM ChatGPT OAuth internals changed; refusing to start without the non-interactive refresh guard"
        ) from exc

    auth_patched = getattr(Authenticator, "_claude_litellm_noninteractive", False)
    auth_endpoint_patched = getattr(
        Authenticator.get_api_base,
        "_claude_litellm_official_endpoint",
        False,
    )
    responses_patched = getattr(
        ChatGPTResponsesAPIConfig.get_complete_url,
        "_claude_litellm_official_endpoint",
        False,
    )
    if auth_patched and auth_endpoint_patched and responses_patched:
        return True

    if tuple(inspect.signature(ChatGPTResponsesAPIConfig.get_complete_url).parameters) != (
        "self",
        "api_base",
        "litellm_params",
    ):
        raise RuntimeError(
            "LiteLLM ChatGPT Responses URL contract changed; refusing to start "
            "without an official-origin pin"
        )

    refresh_lock = threading.Lock()

    def get_official_api_base(self: Any) -> str:
        # The bearer token is valid only for LiteLLM's packaged ChatGPT Codex
        # backend. Never honor an environment value that can redirect it.
        return CHATGPT_API_BASE

    def get_official_complete_url(
        self: Any, api_base: str | None, litellm_params: dict[str, Any]
    ) -> str:
        # An explicit per-request ``api_base`` otherwise wins after the OAuth
        # bearer token has been selected. Subscription routes never permit that
        # request-level endpoint escape hatch.
        return f"{CHATGPT_API_BASE.rstrip('/')}/responses"

    def ensure_token_dir_private(self: Any) -> None:
        _validate_parent_chain(
            Path(self.auth_file),
            "chatgpt",
            create=True,
            repair_permissions=True,
        )

    def read_auth_file_private(self: Any) -> dict[str, Any] | None:
        return _read_auth_file_private(Path(self.auth_file), "chatgpt")

    def write_auth_file_atomic(self: Any, data: dict[str, Any]) -> None:
        _write_auth_file_atomic(Path(self.auth_file), "chatgpt", data)

    def get_access_token_noninteractive(self: Any) -> str:
        auth_data = self._read_auth_file()
        if not auth_data:
            # A login/logout process may be publishing the file at this exact
            # moment. Re-read under the same refresh lock before returning 401.
            with refresh_lock:
                auth_data = self._read_auth_file()
                if not auth_data:
                    raise GetAccessTokenError(
                        status_code=401,
                        message="ChatGPT OAuth login required. Run `claude-litellm auth login chatgpt`.",
                    )

        access_token = auth_data.get("access_token")
        if access_token and not self._is_token_expired(auth_data, access_token):
            return access_token

        # LiteLLM's upstream ChatGPT authenticator has no refresh lock. Serialize
        # refresh-token rotation and re-read after taking the lock so concurrent
        # requests reuse the first refresh instead of racing file writes.
        with refresh_lock:
            auth_data = self._read_auth_file()
            if not auth_data:
                raise GetAccessTokenError(
                    status_code=401,
                    message="ChatGPT OAuth login required. Run `claude-litellm auth login chatgpt`.",
                )
            access_token = auth_data.get("access_token")
            if access_token and not self._is_token_expired(auth_data, access_token):
                return access_token

            refresh_token = auth_data.get("refresh_token")
            if not refresh_token:
                raise GetAccessTokenError(
                    status_code=401,
                    message="ChatGPT OAuth refresh token missing. Run `claude-litellm auth login chatgpt`.",
                )
            try:
                refreshed = self._refresh_tokens(refresh_token)
            except RefreshAccessTokenError:
                raise GetAccessTokenError(
                    status_code=401,
                    message=(
                        "ChatGPT OAuth refresh failed; interactive fallback is disabled in the proxy. "
                        "Run `claude-litellm auth login chatgpt --force`."
                    ),
                ) from None
            token = refreshed.get("access_token")
            if not token:
                raise GetAccessTokenError(
                    status_code=401,
                    message="ChatGPT OAuth refresh returned no access token. Run `claude-litellm auth login chatgpt --force`.",
                )
            return token

    Authenticator._ensure_token_dir = ensure_token_dir_private
    Authenticator._read_auth_file = read_auth_file_private
    Authenticator._write_auth_file = write_auth_file_atomic
    get_official_api_base._claude_litellm_official_endpoint = True  # type: ignore[attr-defined]
    Authenticator.get_api_base = get_official_api_base
    Authenticator.get_access_token = get_access_token_noninteractive
    Authenticator._claude_litellm_noninteractive = True
    get_official_complete_url._claude_litellm_official_endpoint = True  # type: ignore[attr-defined]
    ChatGPTResponsesAPIConfig.get_complete_url = get_official_complete_url
    return True


def install_redacted_xai_auth() -> bool:
    try:
        import litellm  # noqa: F401
    except ModuleNotFoundError:
        return False

    try:
        from litellm.llms.xai.oauth import (
            XAIOAuthAuthenticator,
            XAIOAuthError,
            XAIOAuthLoginRequiredError,
        )
        from litellm.constants import XAI_API_BASE
    except Exception as exc:
        raise RuntimeError(
            "LiteLLM xAI OAuth internals changed; refusing to start without the refresh redaction guard"
        ) from exc

    auth_patched = getattr(XAIOAuthAuthenticator, "_claude_litellm_redacted", False)
    endpoint_patched = getattr(
        XAIOAuthAuthenticator.get_api_base,
        "_claude_litellm_official_endpoint",
        False,
    )
    if auth_patched and endpoint_patched:
        return True

    original_get_access_token = XAIOAuthAuthenticator.get_access_token

    def get_official_api_base(self: Any) -> str:
        # ``use_xai_oauth`` must always send its bearer token to the packaged
        # xAI API origin, irrespective of ambient endpoint overrides.
        return XAI_API_BASE

    def ensure_token_dir_private(self: Any) -> None:
        _validate_parent_chain(
            Path(self.auth_file),
            "grok",
            create=True,
            repair_permissions=True,
        )

    def read_auth_file_private(self: Any) -> dict[str, Any] | None:
        return _read_auth_file_private(Path(self.auth_file), "grok")

    def write_auth_file_atomic(self: Any, data: dict[str, Any]) -> None:
        _write_auth_file_atomic(Path(self.auth_file), "grok", data)

    def get_access_token_redacted(self: Any) -> str:
        try:
            return original_get_access_token(self)
        except XAIOAuthLoginRequiredError:
            raise XAIOAuthLoginRequiredError(
                "xAI OAuth login required. Run `claude-litellm auth login grok`."
            ) from None
        except XAIOAuthError:
            # Upstream includes the complete OAuth HTTP response body in some
            # error messages. Break the cause chain so proxy tracebacks cannot
            # reflect token payloads.
            raise XAIOAuthLoginRequiredError(
                "xAI OAuth refresh failed. Run `claude-litellm auth login grok --force`."
            ) from None

    XAIOAuthAuthenticator._ensure_token_dir = ensure_token_dir_private
    XAIOAuthAuthenticator._read_auth_file = read_auth_file_private
    XAIOAuthAuthenticator._write_auth_file = write_auth_file_atomic
    get_official_api_base._claude_litellm_official_endpoint = True  # type: ignore[attr-defined]
    XAIOAuthAuthenticator.get_api_base = get_official_api_base
    XAIOAuthAuthenticator.get_access_token = get_access_token_redacted
    XAIOAuthAuthenticator._claude_litellm_redacted = True
    return True


PATCH_ACTIVE = install_noninteractive_chatgpt_auth() and install_redacted_xai_auth()
