"""Keep OAuth refresh non-interactive inside the background LiteLLM proxy.

Explicit login is handled by ``claude-litellm auth login``. LiteLLM 1.92's
ChatGPT authenticator otherwise falls back to a new device-code flow when a
refresh token fails, which can block a detached proxy for fifteen minutes. The
installed proxy imports this module through the callback package and replaces
that fallback with a fast authentication error.
"""

from __future__ import annotations

import threading
from typing import Any


PATCH_ACTIVE = False


def install_noninteractive_chatgpt_auth() -> bool:
    try:
        import litellm  # noqa: F401 - distinguishes local syntax checks from runtime drift
    except ModuleNotFoundError:
        return False

    try:
        from litellm.llms.chatgpt.authenticator import Authenticator
        from litellm.llms.chatgpt.common_utils import (
            GetAccessTokenError,
            RefreshAccessTokenError,
        )
    except Exception as exc:
        raise RuntimeError(
            "LiteLLM ChatGPT OAuth internals changed; refusing to start without the non-interactive refresh guard"
        ) from exc

    if getattr(Authenticator, "_claude_litellm_noninteractive", False):
        return True

    refresh_lock = threading.Lock()

    def get_access_token_noninteractive(self: Any) -> str:
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

    Authenticator.get_access_token = get_access_token_noninteractive
    Authenticator._claude_litellm_noninteractive = True
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
    except Exception as exc:
        raise RuntimeError(
            "LiteLLM xAI OAuth internals changed; refusing to start without the refresh redaction guard"
        ) from exc

    if getattr(XAIOAuthAuthenticator, "_claude_litellm_redacted", False):
        return True

    original_get_access_token = XAIOAuthAuthenticator.get_access_token

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

    XAIOAuthAuthenticator.get_access_token = get_access_token_redacted
    XAIOAuthAuthenticator._claude_litellm_redacted = True
    return True


PATCH_ACTIVE = install_noninteractive_chatgpt_auth() and install_redacted_xai_auth()
