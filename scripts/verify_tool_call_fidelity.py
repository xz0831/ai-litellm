#!/usr/bin/env python3
"""Verify tool-call FIDELITY through LiteLLM's Anthropic <-> OpenAI translation.

This guards the one tool-calling concern that is the fabric's responsibility (not
the model's): when a capable model emits a well-formed tool call, does it survive
the Anthropic /v1/messages -> OpenAI chat/completions -> provider -> back round
trip without being dropped, corrupted, or 400'd? A model *choosing* the wrong tool
or wandering is a model limitation; a *well-formed* tool_use that the translation
layer mangles is OUR bug, and version-fragile across LiteLLM releases.

Design mirrors verify_litellm_token_clamp.py: a mock OpenAI-compatible provider +
a throwaway real LiteLLM proxy. The mock returns OpenAI `tool_calls` (and optional
`reasoning_content`) and LOGS every request body it receives, so we assert BOTH
directions: (a) Anthropic tools/tool_use/tool_result -> correct OpenAI request
shape (request fidelity), and (b) OpenAI tool_calls -> correct Anthropic tool_use
block (response fidelity). Zero spend, deterministic, CI-able — it isolates the
fabric's translation layer from any real model's competence.

Exit 0 iff every critical case passes. `--json` prints a machine-readable verdict.
`--live-model NAME` additionally runs the same Anthropic round trips against the
already-running deployed proxy at 127.0.0.1:4000 for NAME (BILLABLE for cloud
routes; needs the litellm master key in the keychain) as a real-backend smoke.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import http.server
import urllib.request
import urllib.error
from pathlib import Path
from typing import Any


def find_free_port() -> int:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class MockState:
    """Thread-safe log of request bodies the mock provider received."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._requests: list[dict[str, Any]] = []

    def append(self, body: dict[str, Any]) -> None:
        with self._lock:
            self._requests.append(body)

    def snapshot(self) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._requests)


def make_mock_handler(state: MockState) -> type[http.server.BaseHTTPRequestHandler]:
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:  # silence
            return

        def _send(self, status: int, payload: dict[str, Any]) -> None:
            data = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _send_stream(self, model: str) -> None:
            """Emit a fragmented OpenAI tool call to test streaming reassembly."""
            chunks = [
                {
                    "id": "chatcmpl-stream", "object": "chat.completion.chunk", "created": 0,
                    "model": model,
                    "choices": [{"index": 0, "delta": {
                        "role": "assistant",
                        "reasoning_content": "I will call get_weather.",
                        "tool_calls": [{"index": 0, "id": "call_stream_1", "type": "function",
                                        "function": {"name": "get_weather", "arguments": "{\"city\":\""}}],
                    }, "finish_reason": None}],
                },
                {
                    "id": "chatcmpl-stream", "object": "chat.completion.chunk", "created": 0,
                    "model": model,
                    "choices": [{"index": 0, "delta": {
                        "tool_calls": [{"index": 0, "function": {"arguments": "Seoul\"}"}}],
                    }, "finish_reason": None}],
                },
                {
                    "id": "chatcmpl-stream", "object": "chat.completion.chunk", "created": 0,
                    "model": model,
                    "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}],
                },
            ]
            body = "".join(f"data: {json.dumps(chunk)}\n\n" for chunk in chunks) + "data: [DONE]\n\n"
            encoded = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

        def do_GET(self) -> None:
            # LiteLLM health/model probes
            self._send(200, {"object": "list", "data": [{"id": "mock-tool-model", "object": "model"}]})

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length) if length else b"{}"
            try:
                body = json.loads(raw or b"{}")
            except json.JSONDecodeError:
                body = {"_unparseable": raw.decode("utf-8", "replace")}
            state.append(body)

            messages = body.get("messages", []) if isinstance(body, dict) else []
            has_tool_role = any(isinstance(m, dict) and m.get("role") == "tool" for m in messages)
            tools = body.get("tools") if isinstance(body, dict) else None
            model = body.get("model", "mock-tool-model") if isinstance(body, dict) else "mock-tool-model"

            if tools and body.get("stream") is True:
                self._send_stream(model)
                return

            if has_tool_role:
                # The client fed a tool_result back; emit a normal text completion.
                message = {"role": "assistant", "content": "The weather in Seoul is 18C and sunny."}
                finish = "stop"
            elif tools:
                # Emit a well-formed OpenAI tool call (this is what a capable model does).
                message = {
                    "role": "assistant",
                    "content": None,
                    "reasoning_content": "The user asked for weather; I will call get_weather.",
                    "tool_calls": [
                        {
                            "id": "call_mock_1",
                            "type": "function",
                            "function": {"name": "get_weather", "arguments": json.dumps({"city": "Seoul"})},
                        }
                    ],
                }
                finish = "tool_calls"
            else:
                message = {"role": "assistant", "content": "ok"}
                finish = "stop"

            self._send(200, {
                "id": "chatcmpl-mock",
                "object": "chat.completion",
                "created": 0,
                "model": model,
                "choices": [{"index": 0, "message": message, "finish_reason": finish}],
                "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
            })

    return Handler


def wait_for_http(url: str, timeout: float, log_path: Path | None = None) -> None:
    deadline = time.time() + timeout
    last = ""
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as resp:
                if resp.status < 500:
                    return
        except urllib.error.HTTPError as exc:
            if exc.code < 500:
                return
            last = f"HTTP {exc.code}"
        except Exception as exc:  # noqa: BLE001
            last = str(exc)
        if log_path and log_path.exists():
            tail = log_path.read_text("utf-8", "replace")[-400:]
            if "Traceback" in tail or "Address already in use" in tail:
                raise RuntimeError(f"proxy failed to start:\n{tail}")
        time.sleep(0.4)
    raise RuntimeError(f"timed out waiting for {url} ({last})")


def post_messages(base: str, master_key: str, payload: dict[str, Any], timeout: float = 60.0) -> tuple[int, dict[str, Any]]:
    req = urllib.request.Request(
        f"{base}/v1/messages",
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {master_key}",
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as exc:
        try:
            body = json.loads(exc.read() or b"{}")
        except Exception:  # noqa: BLE001
            body = {}
        return exc.code, body


def post_messages_stream(
    base: str, master_key: str, payload: dict[str, Any], timeout: float = 60.0,
) -> tuple[int, list[dict[str, Any]]]:
    req = urllib.request.Request(
        f"{base}/v1/messages",
        data=json.dumps({**payload, "stream": True}).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {master_key}",
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            events = []
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if not data or data == "[DONE]":
                    continue
                events.append(json.loads(data))
            return resp.status, events
    except urllib.error.HTTPError as exc:
        return exc.code, []


WEATHER_TOOL = {
    "name": "get_weather",
    "description": "Get current weather for a city",
    "input_schema": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]},
}


def _tool_use_block(content: list[dict[str, Any]]) -> dict[str, Any] | None:
    for block in content or []:
        if isinstance(block, dict) and block.get("type") == "tool_use":
            return block
    return None


def _text_blocks(content: list[dict[str, Any]]) -> str:
    return " ".join(b.get("text", "") for b in (content or []) if isinstance(b, dict) and b.get("type") == "text")


def run_cases(base: str, master_key: str, mock: MockState | None, model: str) -> dict[str, Any]:
    """Run the four fidelity cases against `base` for `model`. mock=None for live mode."""
    result: dict[str, Any] = {"model": model}

    # Case 1 — single-turn: a tool definition + a triggering prompt must come back
    # as a well-formed Anthropic tool_use block (response fidelity), and the mock
    # must have received OpenAI-shape tools (request fidelity).
    status, resp = post_messages(base, master_key, {
        "model": model, "max_tokens": 256, "tools": [WEATHER_TOOL],
        "messages": [{"role": "user", "content": "What is the weather in Seoul? Use the get_weather tool."}],
    })
    block = _tool_use_block(resp.get("content", [])) if status == 200 else None
    result["single_turn_tool_use_roundtrip"] = bool(
        status == 200 and resp.get("stop_reason") == "tool_use"
        and block is not None and block.get("name") == "get_weather"
        and isinstance(block.get("input"), dict) and block["input"].get("city") == "Seoul"
    )
    if mock is not None:
        reqs = mock.snapshot()
        last = reqs[-1] if reqs else {}
        otools = last.get("tools") or []
        result["request_tools_translated"] = bool(
            otools and isinstance(otools[0], dict)
            and (otools[0].get("function", {}).get("name") == "get_weather"
                 or otools[0].get("name") == "get_weather")
        )

    # Case 2 — multi-turn: assistant tool_use + user tool_result must translate to a
    # valid OpenAI history (assistant.tool_calls + tool message) and continue (no 400).
    status, resp = post_messages(base, master_key, {
        "model": model, "max_tokens": 256, "tools": [WEATHER_TOOL],
        "messages": [
            {"role": "user", "content": "Weather in Seoul? Use the tool."},
            {"role": "assistant", "content": [{"type": "tool_use", "id": "toolu_01", "name": "get_weather", "input": {"city": "Seoul"}}]},
            {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_01", "content": "18C, sunny"}]},
        ],
    })
    result["multiturn_tool_result_roundtrip"] = bool(status == 200 and _text_blocks(resp.get("content", [])))
    if mock is not None:
        last = mock.snapshot()[-1] if mock.snapshot() else {}
        msgs = last.get("messages", [])
        saw_tool_calls = any(isinstance(m, dict) and m.get("role") == "assistant" and m.get("tool_calls") for m in msgs)
        saw_tool_role = any(isinstance(m, dict) and m.get("role") == "tool" for m in msgs)
        result["multiturn_history_translated"] = bool(saw_tool_calls and saw_tool_role)

    # Case 3 — the #26395 trigger: an assistant turn carrying BOTH a thinking block
    # (with signature) AND a tool_use, then a tool_result. This is exactly the shape
    # Claude Code replays on resume; LiteLLM's Anthropic->OpenAI conversion has
    # historically 400'd here. We only require it not to hard-fail.
    status, resp = post_messages(base, master_key, {
        "model": model, "max_tokens": 256, "tools": [WEATHER_TOOL],
        "messages": [
            {"role": "user", "content": "Weather in Seoul? Use the tool."},
            {"role": "assistant", "content": [
                {"type": "thinking", "thinking": "I should call get_weather for Seoul.", "signature": "sig_mock_abc"},
                {"type": "tool_use", "id": "toolu_02", "name": "get_weather", "input": {"city": "Seoul"}},
            ]},
            {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_02", "content": "18C, sunny"}]},
        ],
    })
    result["thinking_plus_tooluse_resume_ok"] = bool(status == 200)
    result["thinking_plus_tooluse_status"] = status
    if mock is not None:
        last = mock.snapshot()[-1] if mock.snapshot() else {}
        assistant_messages = [m for m in last.get("messages", [])
                              if isinstance(m, dict) and m.get("role") == "assistant"]
        result["thinking_signature_forwarded"] = bool(
            assistant_messages and "sig_mock_abc" in json.dumps(assistant_messages[-1])
        )

    # Case 4 — streaming: tool arguments deliberately arrive in two provider
    # chunks. The Anthropic stream must preserve the id/name and reconstruct a
    # valid input JSON object rather than dropping or duplicating fragments.
    status, events = post_messages_stream(base, master_key, {
        "model": model, "max_tokens": 256, "tools": [WEATHER_TOOL],
        "messages": [{"role": "user", "content": "Weather in Seoul? Use the tool."}],
    })
    starts = [event.get("content_block", {}) for event in events
              if event.get("type") == "content_block_start"]
    tool_starts = [block for block in starts if block.get("type") == "tool_use"]
    argument_fragments = [event.get("delta", {}).get("partial_json", "") for event in events
                          if event.get("type") == "content_block_delta"
                          and event.get("delta", {}).get("type") == "input_json_delta"]
    try:
        streamed_input = json.loads("".join(argument_fragments))
    except json.JSONDecodeError:
        streamed_input = None
    result["streaming_tool_arguments_roundtrip"] = bool(
        status == 200 and tool_starts
        and tool_starts[0].get("id") == "call_stream_1"
        and tool_starts[0].get("name") == "get_weather"
        and streamed_input == {"city": "Seoul"}
    )
    result["streaming_status"] = status

    # Case 5 — Claude Code sends effort inside Anthropic output_config, often
    # together with thinking. For OpenAI-compatible providers LiteLLM must turn
    # that intent into the contracted `reasoning_effort` field. A 200 response
    # alone is not evidence: drop_params could silently delete the unsupported
    # field, so the mock must observe the exact upstream value.
    status, _resp = post_messages(base, master_key, {
        "model": model,
        "max_tokens": 2048,
        "output_config": {"effort": "high"},
        "thinking": {"type": "adaptive"},
        "messages": [{"role": "user", "content": "Think carefully, then answer OK."}],
    })
    result["effort_status"] = status
    if mock is not None:
        upstream = mock.snapshot()[-1] if mock.snapshot() else {}
        result["effort_upstream_shape"] = {
            key: upstream.get(key)
            for key in ("reasoning_effort", "reasoning", "thinking", "output_config")
            if key in upstream
        }
        result["output_config_effort_forwarded"] = bool(
            status == 200 and (
                upstream.get("reasoning_effort") == "high"
                or (upstream.get("reasoning") or {}).get("effort") == "high"
            )
        )

        # Case 6 — negative control. For an unknown/non-effort-capable model,
        # drop_params=true may return HTTP 200 after deleting the effort field.
        # Record that as a drop, never as evidence that configurable effort is
        # supported (the same distinction production must make for Kimi routes
        # that advertise reasoning but not reasoning_effort).
        dropped_status, _dropped_resp = post_messages(base, master_key, {
            "model": "mock-no-effort-model",
            "max_tokens": 2048,
            "output_config": {"effort": "high"},
            "thinking": {"type": "adaptive"},
            "messages": [{"role": "user", "content": "Answer OK."}],
        })
        dropped_upstream = mock.snapshot()[-1] if mock.snapshot() else {}
        result["drop_params_does_not_fake_effort_support"] = bool(
            dropped_status == 200
            and "reasoning_effort" not in dropped_upstream
            and not isinstance(dropped_upstream.get("reasoning"), dict)
        )

    return result


def write_config(tmpdir: Path, mock_port: int, master_key: str) -> Path:
    cfg = f"""model_list:
  - model_name: mock-tool-model
    litellm_params:
      # A known reasoning-capable model is required for the effort case. With
      # an unknown model and drop_params=true LiteLLM correctly removes
      # reasoning_effort, which would make a successful HTTP response a false
      # capability signal. api_base still points to the offline mock.
      model: openai/gpt-5.4
      api_base: http://127.0.0.1:{mock_port}/v1
      api_key: none
  - model_name: mock-no-effort-model
    litellm_params:
      model: openai/mock-no-effort-model
      api_base: http://127.0.0.1:{mock_port}/v1
      api_key: none
general_settings:
  master_key: {master_key}
litellm_settings:
  drop_params: true
  # Mirrors config/litellm_config.yaml: 1.9x routes Anthropic /v1/messages+tools
  # to the Responses API by default; force chat-completions so this fixture
  # exercises the same path production does. No-op on <=1.81.14.
  use_chat_completions_url_for_anthropic_messages: true
"""
    path = tmpdir / "litellm_config.yaml"
    path.write_text(cfg)
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true", help="emit machine-readable verdict")
    ap.add_argument("--litellm-bin", default=os.environ.get("LITELLM_BIN", "litellm"))
    ap.add_argument("--live-model", help="also run round trips against the deployed proxy (127.0.0.1:4000) for this model (BILLABLE)")
    args = ap.parse_args()

    master_key = "sk-fidelity-test"
    mock_state = MockState()
    mock_port = find_free_port()
    proxy_port = find_free_port()
    mock_server = http.server.ThreadingHTTPServer(("127.0.0.1", mock_port), make_mock_handler(mock_state))
    mock_thread = threading.Thread(target=mock_server.serve_forever, daemon=True)
    mock_thread.start()

    tmp = Path(tempfile.mkdtemp(prefix="litellm-fidelity-"))
    cfg = write_config(tmp, mock_port, master_key)
    log_path = tmp / "litellm.log"
    env = dict(os.environ)
    verdict: dict[str, Any] = {}
    proc = None
    try:
        with open(log_path, "wb") as log:
            proc = subprocess.Popen(
                [args.litellm_bin, "--config", str(cfg), "--port", str(proxy_port), "--host", "127.0.0.1"],
                cwd=str(tmp), env=env, stdout=log, stderr=subprocess.STDOUT,
            )
        wait_for_http(f"http://127.0.0.1:{proxy_port}/v1/models", timeout=60, log_path=log_path)
        verdict["mock"] = run_cases(f"http://127.0.0.1:{proxy_port}", master_key, mock_state, "mock-tool-model")
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
        mock_server.shutdown()
        shutil.rmtree(tmp, ignore_errors=True)

    if args.live_model:
        live_key = master_key
        sec = shutil.which("security")
        if sec:
            try:
                live_key = subprocess.check_output(
                    [sec, "find-generic-password", "-s", "litellm-master-key", "-a", os.environ.get("USER", ""), "-w"],
                    text=True,
                ).strip() or master_key
            except subprocess.CalledProcessError:
                pass
        verdict["live"] = run_cases("http://127.0.0.1:4000", live_key, None, args.live_model)

    critical = [
        verdict["mock"]["single_turn_tool_use_roundtrip"],
        verdict["mock"].get("request_tools_translated", False),
        verdict["mock"]["multiturn_tool_result_roundtrip"],
        verdict["mock"].get("multiturn_history_translated", False),
        verdict["mock"]["thinking_plus_tooluse_resume_ok"],
        verdict["mock"].get("thinking_signature_forwarded", False),
        verdict["mock"]["streaming_tool_arguments_roundtrip"],
        verdict["mock"].get("output_config_effort_forwarded", False),
        verdict["mock"].get("drop_params_does_not_fake_effort_support", False),
    ]
    verdict["all_critical_pass"] = all(critical)

    if args.json:
        print(json.dumps(verdict, indent=2))
    else:
        m = verdict["mock"]
        print("Tool-call fidelity (mock provider, deterministic):")
        print(f"  single-turn tool_use round-trip ............ {'PASS' if m['single_turn_tool_use_roundtrip'] else 'FAIL'}")
        print(f"  Anthropic tools -> OpenAI request .......... {'PASS' if m.get('request_tools_translated') else 'FAIL'}")
        print(f"  multi-turn tool_result round-trip .......... {'PASS' if m['multiturn_tool_result_roundtrip'] else 'FAIL'}")
        print(f"  tool_use+tool_result -> OpenAI history ..... {'PASS' if m.get('multiturn_history_translated') else 'FAIL'}")
        print(f"  thinking+tool_use resume (no 400) .......... {'PASS' if m['thinking_plus_tooluse_resume_ok'] else 'FAIL'} (status {m.get('thinking_plus_tooluse_status')})")
        print(f"  thinking signature forwarded upstream ...... {'PASS' if m.get('thinking_signature_forwarded') else 'FAIL'}")
        print(f"  streaming tool args reassembled ............ {'PASS' if m['streaming_tool_arguments_roundtrip'] else 'FAIL'} (status {m.get('streaming_status')})")
        print(f"  output_config.effort -> reasoning_effort ... {'PASS' if m.get('output_config_effort_forwarded') else 'FAIL'} (status {m.get('effort_status')})")
        print(f"  dropped effort is not capability evidence . {'PASS' if m.get('drop_params_does_not_fake_effort_support') else 'FAIL'}")
        if "live" in verdict:
            print(f"Live backend smoke ({verdict['live']['model']}):")
            print(f"  single-turn tool_use ....................... {'PASS' if verdict['live']['single_turn_tool_use_roundtrip'] else 'FAIL'}")
            print(f"  multi-turn tool_result ..................... {'PASS' if verdict['live']['multiturn_tool_result_roundtrip'] else 'FAIL'}")
        print(f"=> {'OK' if verdict['all_critical_pass'] else 'FIDELITY REGRESSION'}")

    return 0 if verdict["all_critical_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
