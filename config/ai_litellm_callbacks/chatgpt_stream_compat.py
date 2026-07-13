"""LiteLLM 1.92.0 compatibility for ChatGPT's Responses bridge.

ChatGPT's Codex backend can stream the real assistant items in
``response.output_item.done`` events and then send ``response.completed`` with
``output: []``.  LiteLLM 1.92.0 discards those earlier items, so its
chat-completions bridge later fails with ``Unknown items ... []``.

The same bridge only promotes string-valued system messages to top-level
Responses ``instructions``. Claude Code sends its Anthropic system prompt as a
list of text blocks, which LiteLLM otherwise forwards as an ``input`` item with
``role=system``. The ChatGPT Codex backend rejects that shape with ``System
messages are not allowed``. Normalize only ChatGPT bridge inputs, keeping the
system text at instruction authority instead of merging it into a user turn.

The upstream fix is still unmerged (BerriAI/litellm#31332).  Keep this local
shim deliberately narrow: it applies only to exactly LiteLLM 1.92.0 and only
to ``chatgpt`` streams.  Remove it after upgrading to a release containing the
upstream output-recovery implementation.
"""

from __future__ import annotations

import importlib.metadata
import inspect
import json
from typing import Any


EXPECTED_LITELLM_VERSION = "1.92.0"
_STATE_ATTRIBUTE = "_claude_litellm_chatgpt_streamed_output_items"
_PATCH_MARKER = "_claude_litellm_chatgpt_output_recovery"
_SYSTEM_PATCH_MARKER = "_claude_litellm_chatgpt_system_blocks"


def _installed_litellm_version() -> str | None:
    try:
        return importlib.metadata.version("litellm")
    except importlib.metadata.PackageNotFoundError:
        return None


LITELLM_VERSION = _installed_litellm_version()
PATCH_REQUIRED = LITELLM_VERSION == EXPECTED_LITELLM_VERSION


def _is_chatgpt_stream(iterator: Any) -> bool:
    provider = getattr(iterator, "custom_llm_provider", None)
    model = getattr(iterator, "model", "")
    return provider == "chatgpt" or (
        isinstance(model, str) and model.startswith("chatgpt/")
    )


def _plain_output_item(item: Any) -> dict[str, Any]:
    if isinstance(item, dict):
        return dict(item)
    model_dump = getattr(item, "model_dump", None)
    if callable(model_dump):
        dumped = model_dump(mode="json")
        if isinstance(dumped, dict):
            return dumped
    raise TypeError("streamed output item is not serializable")


def _plain_system_block(block: Any) -> dict[str, Any]:
    if isinstance(block, dict):
        return block
    model_dump = getattr(block, "model_dump", None)
    if callable(model_dump):
        dumped = model_dump(mode="python")
        if isinstance(dumped, dict):
            return dumped
    raise TypeError("ChatGPT system content blocks must be text objects")


def _unsupported_system_content(message: str, model: str) -> None:
    from litellm.exceptions import UnsupportedParamsError

    raise UnsupportedParamsError(
        message=message,
        llm_provider="chatgpt",
        model=model,
    )


def normalize_chatgpt_system_messages(
    messages: Any, model: str = "unknown"
) -> list[Any]:
    """Copy messages and flatten text-block system content to strings.

    LiteLLM's common Responses bridge lifts string system content into the
    top-level ``instructions`` field. Unsupported system blocks fail closed
    instead of being silently demoted or sent in a provider-invalid shape.
    """
    if not isinstance(messages, list):
        _unsupported_system_content("ChatGPT messages must be a list", model)

    normalized: list[Any] = []
    for message in messages:
        if not isinstance(message, dict) or message.get("role") != "system":
            normalized.append(message)
            continue
        content = message.get("content", "")
        if isinstance(content, str):
            normalized.append(message)
            continue
        if not isinstance(content, list):
            _unsupported_system_content(
                "ChatGPT OAuth only supports text system content", model
            )

        text_parts: list[str] = []
        for index, raw_block in enumerate(content):
            try:
                block = _plain_system_block(raw_block)
            except TypeError:
                _unsupported_system_content(
                    f"ChatGPT OAuth system block {index} must be a text object",
                    model,
                )
            if block.get("type") not in ("text", "input_text"):
                _unsupported_system_content(
                    f"ChatGPT OAuth system block {index} is not text", model
                )
            text = block.get("text")
            if not isinstance(text, str):
                _unsupported_system_content(
                    f"ChatGPT OAuth system block {index} is missing text", model
                )
            text_parts.append(text)

        copied = dict(message)
        copied["content"] = "\n\n".join(text_parts)
        normalized.append(copied)
    return normalized


def install_chatgpt_system_block_normalization() -> bool:
    """Patch the completion-to-Responses bridge only for ChatGPT 1.92.0."""
    if not PATCH_REQUIRED:
        return False

    try:
        from litellm.completion_extras.litellm_responses_transformation.handler import (
            ResponsesToCompletionBridgeHandler,
        )
    except Exception as exc:
        raise RuntimeError(
            "LiteLLM 1.92.0 Responses bridge internals changed; refusing to "
            "install the ChatGPT system-block compatibility patch"
        ) from exc

    original = ResponsesToCompletionBridgeHandler.validate_input_kwargs
    if getattr(original, _SYSTEM_PATCH_MARKER, False):
        return True
    if tuple(inspect.signature(original).parameters) != ("self", "kwargs"):
        raise RuntimeError(
            "LiteLLM 1.92.0 validate_input_kwargs signature changed; refusing "
            "to install the ChatGPT system-block compatibility patch"
        )

    def validate_input_kwargs_with_chatgpt_system_blocks(
        self: Any, kwargs: dict[str, Any]
    ) -> Any:
        validated = original(self, kwargs)
        if validated.get("custom_llm_provider") == "chatgpt":
            validated["messages"] = normalize_chatgpt_system_messages(
                validated["messages"], str(validated.get("model") or "unknown")
            )
        return validated

    setattr(
        validate_input_kwargs_with_chatgpt_system_blocks,
        _SYSTEM_PATCH_MARKER,
        True,
    )
    ResponsesToCompletionBridgeHandler.validate_input_kwargs = (
        validate_input_kwargs_with_chatgpt_system_blocks
    )
    return True


def install_chatgpt_stream_output_recovery() -> bool:
    """Install the exact-version stream recovery shim, if it is required."""
    if not PATCH_REQUIRED:
        return False

    try:
        from litellm._logging import verbose_logger
        from litellm.responses.streaming_iterator import (
            BaseResponsesAPIStreamingIterator,
        )
    except Exception as exc:
        raise RuntimeError(
            "LiteLLM 1.92.0 streaming internals changed; refusing to install "
            "the ChatGPT output-recovery compatibility patch"
        ) from exc

    original = BaseResponsesAPIStreamingIterator._process_chunk
    if getattr(original, _PATCH_MARKER, False):
        return True
    if tuple(inspect.signature(original).parameters) != ("self", "chunk"):
        raise RuntimeError(
            "LiteLLM 1.92.0 _process_chunk signature changed; refusing to install "
            "the ChatGPT output-recovery compatibility patch"
        )

    def process_chunk_with_chatgpt_output_recovery(
        self: Any, chunk: Any
    ) -> Any:
        scoped = _is_chatgpt_stream(self)
        parsed: dict[str, Any] | None = None
        forwarded_chunk = chunk

        if scoped:
            try:
                candidate = json.loads(chunk)
                if isinstance(candidate, dict):
                    parsed = candidate
            except (json.JSONDecodeError, TypeError, UnicodeDecodeError):
                parsed = None

        if parsed is not None:
            event_type = parsed.get("type")
            if event_type == "response.created":
                setattr(self, _STATE_ATTRIBUTE, {})
            elif event_type in ("response.completed", "response.incomplete"):
                response = parsed.get("response")
                streamed_items = getattr(self, _STATE_ATTRIBUTE, {})
                if (
                    isinstance(response, dict)
                    and not response.get("output")
                    and isinstance(streamed_items, dict)
                    and streamed_items
                ):
                    try:
                        recovered = [
                            _plain_output_item(item)
                            for _, item in sorted(streamed_items.items())
                        ]
                        patched_event = dict(parsed)
                        patched_response = dict(response)
                        patched_response["output"] = recovered
                        patched_event["response"] = patched_response
                        forwarded_chunk = json.dumps(
                            patched_event,
                            ensure_ascii=False,
                            separators=(",", ":"),
                        )
                    except Exception:
                        # Preserve upstream behavior if an unexpected item cannot
                        # be represented.  Never fail an otherwise valid stream.
                        verbose_logger.warning(
                            "chatgpt_stream_compat: failed to recover completed output",
                            exc_info=True,
                        )

        result = original(self, forwarded_chunk)

        if scoped and getattr(result, "type", None) == "response.output_item.done":
            item = getattr(result, "item", None)
            if item is not None:
                streamed_items = getattr(self, _STATE_ATTRIBUTE, None)
                if not isinstance(streamed_items, dict):
                    streamed_items = {}
                    setattr(self, _STATE_ATTRIBUTE, streamed_items)
                output_index = getattr(result, "output_index", None)
                if not isinstance(output_index, int) or isinstance(output_index, bool):
                    output_index = max(streamed_items, default=-1) + 1
                streamed_items[output_index] = item

        return result

    setattr(process_chunk_with_chatgpt_output_recovery, _PATCH_MARKER, True)
    BaseResponsesAPIStreamingIterator._process_chunk = (
        process_chunk_with_chatgpt_output_recovery
    )
    return True


PATCH_ACTIVE = install_chatgpt_stream_output_recovery()
SYSTEM_PATCH_ACTIVE = install_chatgpt_system_block_normalization()
