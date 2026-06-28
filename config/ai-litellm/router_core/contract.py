from __future__ import annotations

from typing import Any


CONTRACT_VERSION = "router.v1"
SCHEMA_VERSION = 1


def diagnostic(code: str, message: str, **details: Any) -> dict[str, Any]:
    out: dict[str, Any] = {"code": code, "message": message}
    clean_details = {key: value for key, value in details.items() if value is not None}
    if clean_details:
        out["details"] = clean_details
    return out


ROUTE_REQUIRED_FIELDS = [
    "harness",
    "adapter",
    "model",
    "sourceModel",
    "backend",
    "provider",
    "local",
    "billable",
    "runtimeModel",
    "context",
    "output",
    "effectiveInput",
    "command",
]


DIAGNOSTIC_SCHEMA = {
    "type": "object",
    "required": ["code", "message"],
    "properties": {
        "code": {"type": "string"},
        "message": {"type": "string"},
        "details": {"type": "object"},
    },
    "additionalProperties": False,
}


ROUTE_SCHEMA = {
    "type": "object",
    "required": ROUTE_REQUIRED_FIELDS,
    "properties": {
        "harness": {"type": "string"},
        "adapter": {"type": ["string", "null"]},
        "model": {"type": "string"},
        "sourceModel": {"type": "string"},
        "backend": {"type": ["string", "null"]},
        "provider": {"type": "string"},
        "local": {"type": "boolean"},
        "billable": {"type": "boolean"},
        "runtimeModel": {"type": ["string", "null"]},
        "context": {"type": ["integer", "null"]},
        "output": {"type": ["integer", "null"]},
        "effectiveInput": {"type": ["integer", "null"]},
        "command": {"type": "array", "items": {"type": "string"}},
        "score": {"type": "number"},
        "reasons": {"type": "array", "items": {"type": "string"}},
        "selectionReasons": {"type": "array", "items": DIAGNOSTIC_SCHEMA},
        "risks": {"type": "array", "items": {"type": "string"}},
        "riskDiagnostics": {"type": "array", "items": DIAGNOSTIC_SCHEMA},
        "rejected": {"type": "array", "items": {"type": "string"}},
        "rejections": {"type": "array", "items": DIAGNOSTIC_SCHEMA},
    },
}


INTENT_SCHEMA = {
    "type": "object",
    "required": [
        "taskType",
        "estimatedInputTokens",
        "requiresTools",
        "requiresLocal",
        "localOnly",
        "allowBillable",
        "preferredHarness",
        "preferredModel",
    ],
    "properties": {
        "taskType": {"type": "string"},
        "estimatedInputTokens": {"type": "integer"},
        "requiresTools": {"type": "boolean"},
        "requiresLocal": {"type": "boolean"},
        "localOnly": {"type": "boolean"},
        "allowBillable": {"type": "boolean"},
        "preferredHarness": {"type": ["string", "null"]},
        "preferredModel": {"type": ["string", "null"]},
    },
}


PLAN_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "ai-litellm.router.plan.v1",
    "type": "object",
    "required": [
        "schemaVersion",
        "contractVersion",
        "kind",
        "intent",
        "selected",
        "candidates",
        "candidateCount",
        "rejectedCount",
        "snapshotErrors",
    ],
    "properties": {
        "schemaVersion": {"const": SCHEMA_VERSION},
        "contractVersion": {"const": CONTRACT_VERSION},
        "kind": {"const": "ai-litellm.router.plan"},
        "intent": INTENT_SCHEMA,
        "selected": {"oneOf": [ROUTE_SCHEMA, {"type": "null"}]},
        "candidates": {"type": "array", "items": ROUTE_SCHEMA},
        "candidateCount": {"type": "integer"},
        "rejectedCount": {"type": "integer"},
        "snapshotErrors": {"type": "array"},
        "rejected": {"type": "array", "items": ROUTE_SCHEMA},
    },
}


SNAPSHOT_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "ai-litellm.router.snapshot.v1",
    "type": "object",
    "required": [
        "schemaVersion",
        "contractVersion",
        "kind",
        "generatedAt",
        "source",
        "raw",
        "normalized",
        "errors",
    ],
    "properties": {
        "schemaVersion": {"const": SCHEMA_VERSION},
        "contractVersion": {"const": CONTRACT_VERSION},
        "kind": {"const": "ai-litellm.router.snapshot"},
        "generatedAt": {"type": "string"},
        "source": {"type": "object"},
        "raw": {"type": "object"},
        "normalized": {"type": "object"},
        "errors": {"type": "array"},
    },
}


EXECUTE_SCHEMA = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "ai-litellm.router.execute.v1",
    "type": "object",
    "required": [
        "schemaVersion",
        "contractVersion",
        "kind",
        "dryRun",
        "ready",
        "selected",
        "command",
        "requiresConfirmation",
        "plan",
    ],
    "properties": {
        "schemaVersion": {"const": SCHEMA_VERSION},
        "contractVersion": {"const": CONTRACT_VERSION},
        "kind": {"const": "ai-litellm.router.execute"},
        "dryRun": {"type": "boolean"},
        "ready": {"type": "boolean"},
        "selected": {"oneOf": [ROUTE_SCHEMA, {"type": "null"}]},
        "command": {"oneOf": [{"type": "array", "items": {"type": "string"}}, {"type": "null"}]},
        "requiresConfirmation": {"type": "boolean"},
        "plan": PLAN_SCHEMA,
        "error": {"type": "string"},
        "errorCode": {"type": "string"},
        "errorDiagnostic": DIAGNOSTIC_SCHEMA,
        "result": {"type": "object"},
    },
}


def schema_bundle() -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "contractVersion": CONTRACT_VERSION,
        "kind": "ai-litellm.router.schema",
        "schemas": {
            "snapshot": SNAPSHOT_SCHEMA,
            "plan": PLAN_SCHEMA,
            "execute": EXECUTE_SCHEMA,
            "diagnostic": DIAGNOSTIC_SCHEMA,
            "route": ROUTE_SCHEMA,
            "intent": INTENT_SCHEMA,
        },
    }


def _require_keys(payload: dict[str, Any], keys: list[str], path: str) -> list[str]:
    return [f"{path}.{key} is required" for key in keys if key not in payload]


def _validate_diagnostic(diag: Any, path: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(diag, dict):
        return [f"{path} must be an object"]
    errors.extend(_require_keys(diag, ["code", "message"], path))
    if "code" in diag and not isinstance(diag["code"], str):
        errors.append(f"{path}.code must be a string")
    if "message" in diag and not isinstance(diag["message"], str):
        errors.append(f"{path}.message must be a string")
    if "details" in diag and not isinstance(diag["details"], dict):
        errors.append(f"{path}.details must be an object")
    return errors


def _validate_route(route: Any, path: str, *, selected: bool = False, rejected: bool = False) -> list[str]:
    errors: list[str] = []
    if route is None:
        return errors
    if not isinstance(route, dict):
        return [f"{path} must be an object or null"]
    errors.extend(_require_keys(route, ROUTE_REQUIRED_FIELDS, path))
    if "command" in route and not (isinstance(route["command"], list) and all(isinstance(x, str) for x in route["command"])):
        errors.append(f"{path}.command must be an array of strings")
    if selected:
        errors.extend(_require_keys(route, ["score", "reasons", "selectionReasons", "risks", "riskDiagnostics"], path))
    if rejected:
        errors.extend(_require_keys(route, ["rejected", "rejections"], path))
    for key in ("selectionReasons", "riskDiagnostics", "rejections"):
        if key in route:
            if not isinstance(route[key], list):
                errors.append(f"{path}.{key} must be an array")
                continue
            for idx, diag in enumerate(route[key]):
                errors.extend(_validate_diagnostic(diag, f"{path}.{key}[{idx}]"))
    return errors


def _validate_plan(payload: dict[str, Any], path: str = "$") -> list[str]:
    errors: list[str] = []
    errors.extend(_require_keys(payload, PLAN_SCHEMA["required"], path))
    if payload.get("schemaVersion") != SCHEMA_VERSION:
        errors.append(f"{path}.schemaVersion must be {SCHEMA_VERSION}")
    if payload.get("contractVersion") != CONTRACT_VERSION:
        errors.append(f"{path}.contractVersion must be {CONTRACT_VERSION}")
    if payload.get("kind") != "ai-litellm.router.plan":
        errors.append(f"{path}.kind must be ai-litellm.router.plan")
    if "selected" in payload:
        errors.extend(_validate_route(payload["selected"], f"{path}.selected", selected=payload["selected"] is not None))
    if isinstance(payload.get("candidates"), list):
        for idx, route in enumerate(payload["candidates"]):
            errors.extend(_validate_route(route, f"{path}.candidates[{idx}]", selected=True))
    else:
        errors.append(f"{path}.candidates must be an array")
    if "rejected" in payload:
        if isinstance(payload["rejected"], list):
            for idx, route in enumerate(payload["rejected"]):
                errors.extend(_validate_route(route, f"{path}.rejected[{idx}]", rejected=True))
        else:
            errors.append(f"{path}.rejected must be an array")
    return errors


def validate_contract(payload: dict[str, Any]) -> list[str]:
    if not isinstance(payload, dict):
        return ["$ must be an object"]
    kind = payload.get("kind")
    if kind == "ai-litellm.router.plan":
        return _validate_plan(payload)
    if kind == "ai-litellm.router.snapshot":
        errors = _require_keys(payload, SNAPSHOT_SCHEMA["required"], "$")
        if payload.get("schemaVersion") != SCHEMA_VERSION:
            errors.append("$.schemaVersion must be 1")
        if payload.get("contractVersion") != CONTRACT_VERSION:
            errors.append(f"$.contractVersion must be {CONTRACT_VERSION}")
        return errors
    if kind == "ai-litellm.router.execute":
        errors = _require_keys(payload, EXECUTE_SCHEMA["required"], "$")
        if payload.get("schemaVersion") != SCHEMA_VERSION:
            errors.append("$.schemaVersion must be 1")
        if payload.get("contractVersion") != CONTRACT_VERSION:
            errors.append(f"$.contractVersion must be {CONTRACT_VERSION}")
        if "selected" in payload:
            errors.extend(_validate_route(payload["selected"], "$.selected", selected=payload["selected"] is not None))
        if isinstance(payload.get("plan"), dict):
            errors.extend(_validate_plan(payload["plan"], "$.plan"))
        if "errorDiagnostic" in payload:
            errors.extend(_validate_diagnostic(payload["errorDiagnostic"], "$.errorDiagnostic"))
        return errors
    if kind == "ai-litellm.router.schema":
        return _require_keys(payload, ["schemaVersion", "contractVersion", "kind", "schemas"], "$")
    return [f"unsupported kind: {kind}"]
