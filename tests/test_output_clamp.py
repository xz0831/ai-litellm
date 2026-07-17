from __future__ import annotations

import asyncio
import importlib.util
import os
import unittest
from pathlib import Path
from unittest.mock import patch


MODULE = Path(__file__).resolve().parents[1] / "config" / "ai_litellm_callbacks" / "output_clamp.py"
SPEC = importlib.util.spec_from_file_location("output_clamp", MODULE)
assert SPEC is not None and SPEC.loader is not None
OUTPUT_CLAMP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OUTPUT_CLAMP)


class OutputClampTests(unittest.TestCase):
    def test_unselectable_effort_is_removed_but_adaptive_thinking_remains(self) -> None:
        kwargs = {
            "model": "Kimi-K2.7-Code-openrouter",
            "model_info": {"supports_reasoning": True, "x_reasoning_efforts": []},
            "thinking": {"type": "adaptive"},
            "output_config": {"effort": "high"},
        }
        OUTPUT_CLAMP.enforce_reasoning_effort_policy(kwargs)
        self.assertEqual(kwargs["thinking"], {"type": "adaptive"})
        self.assertNotIn("output_config", kwargs)
        self.assertNotIn("reasoning_effort", kwargs)

    def test_single_allowed_effort_normalizes_claude_shared_default(self) -> None:
        kwargs = {
            "model": "GLM-5.2-openrouter",
            "model_info": {"supports_reasoning": True, "x_reasoning_efforts": ["high"]},
            "optional_params": {"reasoning_effort": "medium"},
        }
        OUTPUT_CLAMP.enforce_reasoning_effort_policy(kwargs)
        self.assertEqual(kwargs["optional_params"]["reasoning_effort"], "high")

    def test_supported_selectable_effort_is_preserved(self) -> None:
        kwargs = {
            "model": "Grok-4.5-xai-oauth",
            "model_info": {"supports_reasoning": True, "x_reasoning_efforts": ["low", "medium", "high"]},
            "output_config": {"effort": "medium"},
        }
        OUTPUT_CLAMP.enforce_reasoning_effort_policy(kwargs)
        self.assertEqual(kwargs["output_config"]["effort"], "medium")

    def test_unsupported_selectable_effort_is_rejected(self) -> None:
        kwargs = {
            "model": "selectable-route",
            "model_info": {"supports_reasoning": True, "x_reasoning_efforts": ["low", "medium"]},
            "reasoning_effort": "high",
        }
        with self.assertRaisesRegex(Exception, "not supported"):
            OUTPUT_CLAMP.enforce_reasoning_effort_policy(kwargs)

    def test_tool_arguments_are_counted_when_content_is_null(self) -> None:
        payload = "x" * 900_000
        estimated = OUTPUT_CLAMP.estimate_input_tokens(
            {
                "messages": [
                    {
                        "role": "assistant",
                        "content": None,
                        "tool_calls": [{"function": {"arguments": payload}}],
                    }
                ]
            }
        )
        self.assertGreaterEqual(estimated, 225_000)

    def test_omitted_output_limit_is_priced_at_gateway_cap(self) -> None:
        kwargs = {
            "model": "route",
            "model_info": {"max_input_tokens": 262_144, "max_output_tokens": 16_384},
        }
        self.assertEqual(OUTPUT_CLAMP.requested_output_tokens(kwargs), 16_384)

    def test_omitted_output_uses_capability_not_smaller_policy_default(self) -> None:
        kwargs = {
            "model": "large-route",
            "model_info": {"max_input_tokens": 1_000_000, "max_output_tokens": 128_000},
        }
        self.assertEqual(OUTPUT_CLAMP.requested_output_tokens(kwargs), 128_000)

    def test_korean_without_spaces_is_not_len_over_four(self) -> None:
        estimated = OUTPUT_CLAMP.estimate_input_tokens({"messages": [{"content": "가" * 10_000}]})
        self.assertGreaterEqual(estimated, 10_000)

    def test_adapter_that_strips_limit_is_priced_at_capability(self) -> None:
        kwargs = {
            "max_tokens": 1,
            "model_info": {
                "max_output_tokens": 128_000,
                "x_output_enforcement": "provider-natural-cap-only; chatgpt-adapter-strips-token-limit-fields",
            },
        }
        self.assertEqual(OUTPUT_CLAMP.requested_output_tokens(kwargs), 128_000)

    def test_large_tool_schema_keys_are_counted(self) -> None:
        properties = {
            f"property_{index:05d}_" + ("x" * 48): {"type": "string"}
            for index in range(20_000)
        }
        estimated = OUTPUT_CLAMP.estimate_input_tokens(
            {"tools": [{"name": "large_schema", "input_schema": {"properties": properties}}]}
        )
        self.assertGreater(estimated, 200_000)

    def test_responses_max_output_tokens_is_clamped_and_priced(self) -> None:
        kwargs = {
            "max_output_tokens": 128_000,
            "model_info": {"max_input_tokens": 262_144, "max_output_tokens": 128_000},
        }
        OUTPUT_CLAMP.clamp_token_reservations(kwargs)
        self.assertEqual(kwargs["max_output_tokens"], 32_000)
        self.assertEqual(OUTPUT_CLAMP.requested_output_tokens(kwargs), 32_000)

    def test_responses_instructions_are_counted(self) -> None:
        estimated = OUTPUT_CLAMP.estimate_input_tokens({"instructions": "x" * 900_000})
        self.assertGreaterEqual(estimated, 225_000)

    def test_context_guard_counts_system_tools_and_tool_calls(self) -> None:
        kwargs = {
            "model": "route",
            "model_info": {"max_input_tokens": 1_000, "max_output_tokens": 400},
            "max_tokens": 400,
            "system": "s" * 600,
            "tools": [
                {
                    "name": "write_record",
                    "input_schema": {
                        "type": "object",
                        "properties": {"payload": {"description": "d" * 400, "type": "string"}},
                    },
                }
            ],
            "messages": [
                {"role": "user", "content": "u" * 400},
                {
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [{"function": {"name": "write_record", "arguments": "a" * 400}}],
                },
            ],
        }
        with patch.dict(os.environ, {"AI_LITELLM_OUTPUT_CLAMP_TOKENIZER_HEADROOM": "100"}):
            decision = OUTPUT_CLAMP.gateway_context_window_decision(kwargs)

        self.assertFalse(decision["allowed"])
        self.assertEqual(decision["requested_output_tokens"], 400)
        self.assertEqual(decision["tokenizer_headroom_tokens"], 100)
        self.assertGreater(decision["estimated_input_tokens"], 500)
        self.assertGreater(decision["estimated_context_tokens"], decision["max_input_tokens"])

    def test_context_guard_allows_exact_capacity_boundary(self) -> None:
        kwargs = {
            "model": "route",
            "model_info": {"max_input_tokens": 10_000, "max_output_tokens": 500},
            "max_tokens": 500,
            "messages": [{"role": "user", "content": "boundary" * 600}],
        }
        with patch.dict(os.environ, {"AI_LITELLM_OUTPUT_CLAMP_TOKENIZER_HEADROOM": "100"}):
            estimated_input = OUTPUT_CLAMP.estimate_input_tokens(kwargs)
            kwargs["model_info"]["max_input_tokens"] = estimated_input + 500 + 100
            decision = OUTPUT_CLAMP.gateway_context_window_decision(kwargs)

        self.assertTrue(decision["allowed"])
        self.assertEqual(decision["estimated_context_tokens"], decision["max_input_tokens"])

    def test_context_guard_fails_closed_without_model_limit(self) -> None:
        kwargs = {"model": "unbounded-route", "messages": [{"role": "user", "content": "short"}], "max_tokens": 8}
        with self.assertRaisesRegex(Exception, "max_input_tokens is missing or invalid"):
            OUTPUT_CLAMP.enforce_context_window(kwargs)

    def test_non_generation_hook_does_not_require_context_metadata(self) -> None:
        kwargs = {"model": "embedding-route", "input": "short"}
        result = asyncio.run(
            OUTPUT_CLAMP.proxy_handler_instance.async_pre_call_deployment_hook(kwargs, "embedding")
        )
        self.assertIs(result, kwargs)

    def test_context_guard_is_independent_of_cost_guardrail_opt_out(self) -> None:
        kwargs = {
            "model": "tiny-route",
            "model_info": {"max_input_tokens": 100, "max_output_tokens": 80},
            "messages": [{"role": "user", "content": "x" * 400}],
            "max_tokens": 80,
        }
        with patch.dict(os.environ, {"AI_LITELLM_COST_GUARDRAIL_ENABLED": "false"}):
            cost_decision = OUTPUT_CLAMP.gateway_cost_guardrail_decision(kwargs)
            context_decision = OUTPUT_CLAMP.gateway_context_window_decision(kwargs)
            with self.assertRaisesRegex(Exception, "context guard rejected request before provider dispatch"):
                asyncio.run(
                    OUTPUT_CLAMP.proxy_handler_instance.async_pre_call_deployment_hook(kwargs, "completion")
                )

        self.assertTrue(cost_decision["allowed"])
        self.assertFalse(context_decision["allowed"])

    def test_chatgpt_stripped_limit_route_reserves_provider_capability(self) -> None:
        kwargs = {
            "model": "GPT-5.6-Sol-chatgpt-oauth",
            "model_info": {
                "max_input_tokens": 1_050_000,
                "max_output_tokens": 128_000,
                "x_output_enforcement": "provider-natural-cap-only; chatgpt-adapter-strips-token-limit-fields",
            },
            "messages": [{"role": "user", "content": "short"}],
            "max_tokens": 1,
        }
        decision = OUTPUT_CLAMP.gateway_context_window_decision(kwargs)
        self.assertTrue(decision["allowed"])
        self.assertEqual(decision["requested_output_tokens"], 128_000)


if __name__ == "__main__":
    unittest.main()
