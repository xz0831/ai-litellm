from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from .contract import CONTRACT_VERSION, SCHEMA_VERSION, diagnostic, schema_bundle
from .executor import build_execution_command, run_command
from .planner import plan_routes
from .state import StateReader, build_snapshot


def _emit(payload: dict[str, Any], pretty: bool = False) -> int:
    if pretty:
        json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
    else:
        json.dump(payload, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


def _load_intent(args: argparse.Namespace) -> dict[str, Any]:
    intent: dict[str, Any] = {}
    if args.intent_file:
        with open(args.intent_file, "r", encoding="utf-8") as fh:
            intent.update(json.load(fh))
    if args.intent_json:
        intent.update(json.loads(args.intent_json))
    for key in ("taskType", "preferredHarness", "preferredModel"):
        value = getattr(args, key, None)
        if value is not None:
            intent[key] = value
    if args.estimated_input_tokens is not None:
        intent["estimatedInputTokens"] = args.estimated_input_tokens
    for key in ("requiresTools", "requiresLocal", "localOnly", "allowBillable"):
        value = getattr(args, key, None)
        if value is not None:
            intent[key] = bool(value)
    return intent


def _load_prompt(args: argparse.Namespace) -> str | None:
    prompt = getattr(args, "prompt", None)
    prompt_file = getattr(args, "prompt_file", None)
    if prompt is not None and prompt_file:
        raise ValueError("pass either --prompt or --prompt-file, not both")
    if prompt_file == "-":
        return sys.stdin.read()
    if prompt_file:
        with open(prompt_file, "r", encoding="utf-8") as fh:
            return fh.read()
    return prompt


def _add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--json", action="store_true", help="Emit JSON (default; accepted for consistency)")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON")
    parser.add_argument("--binary", help="ai-litellm binary to read from")
    parser.add_argument("--timeout", type=float, default=20.0, help="per-read timeout in seconds")


def _add_intent(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--intent-file", help="JSON file containing route intent")
    parser.add_argument("--intent-json", help="Inline JSON object containing route intent")
    parser.add_argument("--task-type", dest="taskType", help="freeform|code|analysis|review|long_context")
    parser.add_argument("--estimated-input-tokens", type=int)
    parser.add_argument("--requires-tools", dest="requiresTools", action="store_true", default=None)
    parser.add_argument("--requires-local", dest="requiresLocal", action="store_true", default=None)
    parser.add_argument("--local-only", dest="localOnly", action="store_true", default=None)
    parser.add_argument("--allow-billable", dest="allowBillable", action="store_true", default=None)
    parser.add_argument("--no-billable", dest="allowBillable", action="store_false")
    parser.add_argument("--preferred-harness", dest="preferredHarness")
    parser.add_argument("--preferred-model", dest="preferredModel")
    parser.add_argument("--include-rejected", action="store_true")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ai-litellm router")
    sub = parser.add_subparsers(dest="command", required=True)

    schema_p = sub.add_parser("schema", help="Emit the Router v1 JSON contract schemas")
    _add_common(schema_p)

    snapshot_p = sub.add_parser("snapshot", help="Read and normalize the current routing state")
    _add_common(snapshot_p)

    plan_p = sub.add_parser("plan", help="Plan a harness/model/provider route")
    _add_common(plan_p)
    _add_intent(plan_p)

    explain_p = sub.add_parser("explain", help="Plan a route and include rejection detail")
    _add_common(explain_p)
    _add_intent(explain_p)
    explain_p.set_defaults(include_rejected=True)

    execute_p = sub.add_parser("execute", help="Prepare a route execution")
    _add_common(execute_p)
    _add_intent(execute_p)
    execute_p.add_argument("--dry-run", action="store_true", help="Return the selected command without running it")
    execute_p.add_argument("--prompt", help="One-shot prompt to run through the selected harness")
    execute_p.add_argument("--prompt-file", help="Read one-shot prompt from a file, or '-' for stdin")
    execute_p.add_argument("--confirm-billable", action="store_true", help="Allow execution of a billable selected route")
    execute_p.add_argument("--execution-timeout", type=float, default=600.0, help="execution timeout in seconds")
    execute_p.add_argument("--capture-limit", type=int, default=200000, help="max characters to retain from stdout/stderr")

    args = parser.parse_args(argv)
    if args.command == "schema":
        return _emit(schema_bundle(), args.pretty)
    if args.command == "snapshot":
        return _emit(build_snapshot(binary=args.binary, timeout=args.timeout), args.pretty)
    snapshot = build_snapshot(binary=args.binary, timeout=args.timeout)
    intent = _load_intent(args)
    include_rejected = bool(getattr(args, "include_rejected", False))
    plan = plan_routes(snapshot, intent, include_rejected=include_rejected)
    if args.command == "execute":
        selected = plan.get("selected")
        try:
            prompt = _load_prompt(args)
            binary = args.binary or StateReader().binary
            command = build_execution_command(selected, prompt, binary=binary) if selected else None
        except Exception as exc:
            payload = {
                "schemaVersion": SCHEMA_VERSION,
                "contractVersion": CONTRACT_VERSION,
                "kind": "ai-litellm.router.execute",
                "dryRun": bool(args.dry_run),
                "ready": False,
                "selected": selected,
                "command": None,
                "requiresConfirmation": bool(selected and selected.get("billable")),
                "plan": plan,
                "error": str(exc),
                "errorCode": "execution.command_build_failed",
                "errorDiagnostic": diagnostic("execution.command_build_failed", str(exc)),
            }
            _emit(payload, args.pretty)
            return 2
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "contractVersion": CONTRACT_VERSION,
            "kind": "ai-litellm.router.execute",
            "dryRun": bool(args.dry_run),
            "ready": bool(selected),
            "selected": selected,
            "command": command,
            "requiresConfirmation": bool(selected and selected.get("billable")),
            "plan": plan,
        }
        if args.dry_run:
            return _emit(payload, args.pretty)
        if not selected:
            message = "no route selected"
            payload["error"] = message
            payload["errorCode"] = "routing.no_route_selected"
            payload["errorDiagnostic"] = diagnostic("routing.no_route_selected", message)
            _emit(payload, args.pretty)
            return 1
        if prompt is None:
            message = "router execute requires --prompt or --prompt-file for non-interactive one-shot execution"
            payload["error"] = message
            payload["errorCode"] = "execution.prompt_required"
            payload["errorDiagnostic"] = diagnostic("execution.prompt_required", message)
            _emit(payload, args.pretty)
            return 2
        if selected.get("billable") and not args.confirm_billable:
            message = "selected route is billable; pass --confirm-billable to execute"
            payload["error"] = message
            payload["errorCode"] = "billing.confirmation_required"
            payload["errorDiagnostic"] = diagnostic(
                "billing.confirmation_required",
                message,
                harness=selected.get("harness"),
                model=selected.get("model"),
                provider=selected.get("provider"),
            )
            _emit(payload, args.pretty)
            return 3
        result = run_command(command or [], timeout=args.execution_timeout, capture_limit=args.capture_limit)
        payload["result"] = result
        _emit(payload, args.pretty)
        return int(result.get("exitCode") or 0)
    return _emit(plan, args.pretty)
