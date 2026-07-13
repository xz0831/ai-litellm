"""LiteLLM proxy callbacks and OAuth safety hooks for claude-litellm."""

from . import oauth_guard, output_clamp

__all__ = ["oauth_guard", "output_clamp"]
