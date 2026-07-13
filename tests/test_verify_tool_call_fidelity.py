from __future__ import annotations

import importlib.util
import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "verify_tool_call_fidelity.py"
SPEC = importlib.util.spec_from_file_location("verify_tool_call_fidelity", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
FIDELITY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIDELITY)


class LiveQualificationTests(unittest.TestCase):
    def test_live_gates_accept_provider_generated_tool_ids(self) -> None:
        dynamic_id = "call_provider_9c7e"
        text_events = [
            {
                "type": "content_block_delta",
                "delta": {"type": "text_delta", "text": "Route ready."},
            }
        ]
        tool_events = [
            {
                "type": "content_block_start",
                "content_block": {
                    "type": "tool_use",
                    "id": "call_stream_provider_42",
                    "name": "get_weather",
                    "input": {},
                },
            },
            {
                "type": "content_block_delta",
                "delta": {"type": "input_json_delta", "partial_json": '{"city":"'},
            },
            {
                "type": "content_block_delta",
                "delta": {"type": "input_json_delta", "partial_json": 'Seoul"}'},
            },
        ]
        forced_response = {
            "stop_reason": "tool_use",
            "content": [
                {
                    "type": "thinking",
                    "thinking": "I should call the tool.",
                    "signature": "provider-signature-must-survive",
                },
                {
                    "type": "tool_use",
                    "id": dynamic_id,
                    "name": "get_weather",
                    "input": {"city": "Seoul"},
                }
            ],
        }
        continuation_response = {
            "stop_reason": "end_turn",
            "content": [{"type": "text", "text": "It is 18C and sunny."}],
        }
        effort_response = {
            "stop_reason": "end_turn",
            "content": [{"type": "text", "text": "OK"}],
        }

        with (
            mock.patch.object(
                FIDELITY,
                "post_messages_stream",
                side_effect=[(200, text_events), (200, tool_events)],
            ) as stream_post,
            mock.patch.object(
                FIDELITY,
                "post_messages",
                side_effect=[
                    (200, forced_response),
                    (200, continuation_response),
                    (200, effort_response),
                ],
            ) as json_post,
        ):
            result = FIDELITY.run_live_qualification(
                "http://127.0.0.1:4000", "secret", "dynamic-model"
            )

        self.assertTrue(result["all_gates_pass"])
        self.assertTrue(result["text_sse"])
        self.assertTrue(result["forced_structured_tool"])
        self.assertTrue(result["streaming_input_json_delta"])
        self.assertTrue(result["tool_result_continuation"])
        self.assertTrue(result["claude_adaptive_effort_policy"])
        self.assertEqual(result["response_max_tokens"], 512)
        for call in (*stream_post.call_args_list, *json_post.call_args_list):
            self.assertGreaterEqual(call.args[2]["max_tokens"], 128)
        self.assertEqual(stream_post.call_args_list[0].args[2]["max_tokens"], 512)
        self.assertEqual(stream_post.call_args_list[1].args[2]["max_tokens"], 128)
        self.assertEqual(json_post.call_args_list[0].args[2]["max_tokens"], 128)
        self.assertEqual(json_post.call_args_list[1].args[2]["max_tokens"], 512)
        effort_payload = json_post.call_args_list[2].args[2]
        self.assertEqual(effort_payload["max_tokens"], 512)
        continuation_payload = json_post.call_args_list[1].args[2]
        self.assertEqual(
            continuation_payload["messages"][1]["content"],
            forced_response["content"],
        )
        self.assertEqual(
            continuation_payload["messages"][2]["content"][0]["tool_use_id"],
            dynamic_id,
        )

    def test_live_gate_failure_changes_process_verdict(self) -> None:
        failed = {
            "model": "broken-model",
            "text_sse": True,
            "forced_structured_tool": True,
            "streaming_input_json_delta": False,
            "tool_result_continuation": True,
        }
        argv = [
            str(SCRIPT),
            "--live-only",
            "--live-model",
            "broken-model",
            "--json",
        ]
        output = io.StringIO()
        with (
            mock.patch.object(sys, "argv", argv),
            mock.patch.object(FIDELITY, "resolve_live_master_key", return_value="secret"),
            mock.patch.object(FIDELITY, "run_live_qualification", return_value=failed),
            redirect_stdout(output),
        ):
            return_code = FIDELITY.main()

        self.assertEqual(return_code, 1)
        self.assertFalse(json.loads(output.getvalue())["all_critical_pass"])

    def test_master_key_environment_precedes_keychain(self) -> None:
        with (
            mock.patch.dict(os.environ, {"LITELLM_MASTER_KEY": "from-environment"}),
            mock.patch.object(FIDELITY.shutil, "which") as which,
        ):
            self.assertEqual(FIDELITY.resolve_live_master_key(), "from-environment")
        which.assert_not_called()


if __name__ == "__main__":
    unittest.main()
