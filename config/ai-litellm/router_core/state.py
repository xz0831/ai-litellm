from __future__ import annotations

import datetime as _dt
import json
import os
import subprocess
from typing import Any

from .contract import CONTRACT_VERSION, SCHEMA_VERSION


def _utc_now() -> str:
    return _dt.datetime.now(_dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def as_int(value: Any) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    text = str(value).strip().replace(",", "")
    if not text or text == "-":
        return None
    try:
        return int(float(text))
    except ValueError:
        return None


def provider_from_backend(backend: str | None, name: str | None = None) -> str:
    b = (backend or "").strip()
    n = (name or "").strip()
    if b.startswith("openrouter/"):
        return "openrouter"
    if b.startswith("openai/local-") or n.endswith("-omlx") or "local-omlx" in b:
        return "local"
    if b.startswith("openai/"):
        return "openai"
    if b:
        return b.split("/", 1)[0]
    return "unknown"


def is_local_route(backend: str | None, name: str | None = None) -> bool:
    return provider_from_backend(backend, name) == "local"


def runtime_model_from_backend(backend: str | None) -> str | None:
    b = (backend or "").strip()
    if b.startswith("openai/"):
        return b.split("/", 1)[1]
    return None


class StateReader:
    def __init__(self, binary: str | None = None, timeout: float = 20.0):
        self.binary = binary or os.environ.get("AI_LITELLM_ROUTER_BINARY") or "ai-litellm"
        self.timeout = timeout
        self.errors: list[dict[str, Any]] = []

    def read_json(self, key: str, args: list[str], default: Any) -> Any:
        try:
            proc = subprocess.run(
                [self.binary, *args],
                capture_output=True,
                text=True,
                timeout=self.timeout,
            )
        except Exception as exc:  # subprocess/timeout/errors all become data
            self.errors.append({"key": key, "argv": args, "error": str(exc)})
            return default
        if proc.returncode != 0:
            self.errors.append({
                "key": key,
                "argv": args,
                "exitCode": proc.returncode,
                "stderr": proc.stderr.strip(),
            })
            return default
        try:
            return json.loads(proc.stdout or "")
        except Exception as exc:
            self.errors.append({"key": key, "argv": args, "error": f"invalid JSON: {exc}"})
            return default


def _index_models(model_list: list[dict[str, Any]], model_limits: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_name: dict[str, dict[str, Any]] = {}
    for row in model_list:
        name = str(row.get("name") or "")
        if not name:
            continue
        by_name.setdefault(name, {})["name"] = name
        by_name[name]["backend"] = row.get("backend")
    for row in model_limits:
        name = str(row.get("model") or row.get("name") or "")
        if not name:
            continue
        rec = by_name.setdefault(name, {"name": name})
        rec["context"] = as_int(row.get("context"))
        rec["output"] = as_int(row.get("output"))
        rec["effectiveInput"] = as_int(row.get("effectiveInput"))
        rec["sources"] = row.get("sources") if isinstance(row.get("sources"), dict) else {}
    out = []
    for rec in by_name.values():
        provider = provider_from_backend(rec.get("backend"), rec.get("name"))
        rec["provider"] = provider
        rec["local"] = provider == "local"
        rec["billable"] = provider != "local"
        out.append(rec)
    return sorted(out, key=lambda r: str(r.get("name") or ""))


def _healthy_local_runtime(runtime_status: list[dict[str, Any]]) -> bool:
    for row in runtime_status:
        health = str(row.get("health") or "").lower()
        if health == "ok":
            return True
    return False


def _available_local_runtime_models(runtime_status: list[dict[str, Any]]) -> list[str]:
    models: set[str] = set()
    for row in runtime_status:
        if str(row.get("health") or "").lower() != "ok":
            continue
        for model in row.get("advertisedModels") or []:
            if isinstance(model, str) and model:
                models.add(model)
        for req in row.get("requiredModels") or []:
            if isinstance(req, dict) and req.get("ok") and isinstance(req.get("model"), str):
                models.add(req["model"])
    return sorted(models)


def build_snapshot(binary: str | None = None, timeout: float = 20.0) -> dict[str, Any]:
    reader = StateReader(binary=binary, timeout=timeout)
    raw: dict[str, Any] = {
        "proxyStatus": reader.read_json("proxyStatus", ["proxy", "status", "--json"], {}),
        "keyStatus": reader.read_json("keyStatus", ["key", "status", "--json"], {}),
        "modelList": reader.read_json("modelList", ["model", "list", "--json"], []),
        "modelLimits": reader.read_json("modelLimits", ["model", "limits", "--json"], []),
        "harnesses": reader.read_json("harnesses", ["harness", "list", "--json"], []),
        "runtimes": reader.read_json("runtimes", ["runtime", "status", "--json"], []),
        "reasoningMatrix": reader.read_json("reasoningMatrix", ["reasoning", "matrix", "--json"], []),
        "contextMatrix": reader.read_json("contextMatrix", ["context", "matrix", "--json"], []),
        "claudeAliases": reader.read_json("claudeAliases", ["harness", "alias", "get", "claude", "--json"], []),
        "codexFacades": reader.read_json("codexFacades", ["codex", "facade", "get", "--json"], []),
    }
    models = _index_models(raw["modelList"] if isinstance(raw["modelList"], list) else [],
                           raw["modelLimits"] if isinstance(raw["modelLimits"], list) else [])
    return {
        "schemaVersion": SCHEMA_VERSION,
        "contractVersion": CONTRACT_VERSION,
        "kind": "ai-litellm.router.snapshot",
        "generatedAt": _utc_now(),
        "source": {"binary": reader.binary},
        "raw": raw,
        "normalized": {
            "models": models,
            "harnesses": raw["harnesses"] if isinstance(raw["harnesses"], list) else [],
            "healthyLocalRuntime": _healthy_local_runtime(raw["runtimes"] if isinstance(raw["runtimes"], list) else []),
            "availableLocalRuntimeModels": _available_local_runtime_models(raw["runtimes"] if isinstance(raw["runtimes"], list) else []),
            "claudeAliases": raw["claudeAliases"] if isinstance(raw["claudeAliases"], list) else [],
            "codexFacades": raw["codexFacades"] if isinstance(raw["codexFacades"], list) else [],
        },
        "errors": reader.errors,
    }
