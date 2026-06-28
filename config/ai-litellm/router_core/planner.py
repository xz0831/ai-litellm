from __future__ import annotations

from typing import Any

from .contract import CONTRACT_VERSION, SCHEMA_VERSION, diagnostic
from .state import as_int, is_local_route, provider_from_backend, runtime_model_from_backend


DEFAULT_INTENT: dict[str, Any] = {
    "taskType": "freeform",
    "estimatedInputTokens": 0,
    "requiresTools": False,
    "requiresLocal": False,
    "localOnly": False,
    "allowBillable": True,
    "preferredHarness": None,
    "preferredModel": None,
}


def normalize_intent(intent: dict[str, Any] | None) -> dict[str, Any]:
    out = dict(DEFAULT_INTENT)
    if intent:
        out.update({k: v for k, v in intent.items() if v is not None})
    out["estimatedInputTokens"] = as_int(out.get("estimatedInputTokens")) or 0
    out["requiresTools"] = bool(out.get("requiresTools"))
    out["requiresLocal"] = bool(out.get("requiresLocal"))
    out["localOnly"] = bool(out.get("localOnly") or out.get("requiresLocal"))
    out["allowBillable"] = bool(out.get("allowBillable"))
    return out


def _models_by_name(snapshot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    models = snapshot.get("normalized", {}).get("models", [])
    return {str(m.get("name")): m for m in models if m.get("name")}


def _key_source(snapshot: dict[str, Any], name: str) -> str:
    info = snapshot.get("raw", {}).get("keyStatus", {}).get(name, {})
    if isinstance(info, dict):
        return str(info.get("source") or "missing").lower()
    return "missing"


def _openrouter_key_available(snapshot: dict[str, Any]) -> bool:
    return _key_source(snapshot, "openrouter") not in ("", "missing", "unset", "none")


def _model_like(candidate: dict[str, Any], wanted: str | None) -> bool:
    if not wanted:
        return True
    w = wanted.lower()
    for key in ("model", "sourceModel", "backend", "provider"):
        value = str(candidate.get(key) or "").lower()
        if value == w or w in value:
            return True
    return False


def _record_for_backend(models: dict[str, dict[str, Any]], backend: str) -> dict[str, Any] | None:
    for rec in models.values():
        if rec.get("backend") == backend:
            return rec
    return None


def _candidate_model_rows(harness: dict[str, Any], snapshot: dict[str, Any]) -> list[dict[str, Any]]:
    name = str(harness.get("name") or "")
    models = _models_by_name(snapshot)
    normalized = snapshot.get("normalized", {})
    rows: list[dict[str, Any]] = []
    if name == "claude":
        seen_sources: set[str] = set()
        for alias in normalized.get("claudeAliases", []):
            tier = str(alias.get("tier") or "")
            source = str(alias.get("model") or "")
            seen_sources.add(source)
            rec = dict(models.get(source, {"name": source}))
            rows.append({
                **rec,
                "model": tier,
                "sourceModel": source,
                "display": alias.get("label") or tier,
            })
        for rec in models.values():
            rec_name = str(rec.get("name") or "")
            if rec_name in seen_sources or not rec.get("local"):
                continue
            rows.append({
                **rec,
                "model": rec_name,
                "sourceModel": rec_name,
                "display": rec_name,
            })
        return rows
    if name == "codex":
        for facade in normalized.get("codexFacades", []):
            model = str(facade.get("facade") or "")
            backend = str(facade.get("model") or "")
            rec = dict(models.get(model) or _record_for_backend(models, backend) or {"name": model, "backend": backend})
            rows.append({
                **rec,
                "model": model,
                "sourceModel": rec.get("name") or model,
                "display": model,
            })
        return rows
    for rec in models.values():
        rows.append({**rec, "model": rec.get("name"), "sourceModel": rec.get("name"), "display": rec.get("name")})
    return rows


def _candidate_from(harness: dict[str, Any], model: dict[str, Any]) -> dict[str, Any]:
    backend = model.get("backend")
    provider = provider_from_backend(str(backend or ""), str(model.get("sourceModel") or model.get("model") or ""))
    local = is_local_route(str(backend or ""), str(model.get("sourceModel") or model.get("model") or ""))
    harness_name = str(harness.get("name") or "")
    model_name = str(model.get("model") or model.get("name") or "")
    return {
        "harness": harness_name,
        "adapter": harness.get("adapter"),
        "model": model_name,
        "sourceModel": model.get("sourceModel") or model.get("name") or model_name,
        "backend": backend,
        "provider": provider,
        "local": local,
        "billable": not local,
        "runtimeModel": runtime_model_from_backend(str(backend or "")) if local else None,
        "context": model.get("context"),
        "output": model.get("output"),
        "effectiveInput": model.get("effectiveInput"),
        "command": ["ai-litellm", "harness", "launch", harness_name, model_name],
    }


def _local_runtime_model_available(snapshot: dict[str, Any], candidate: dict[str, Any]) -> bool:
    runtime_model = str(candidate.get("runtimeModel") or "")
    if not runtime_model:
        return False
    available = snapshot.get("normalized", {}).get("availableLocalRuntimeModels", [])
    return runtime_model in set(str(model) for model in available)


def _reject_diagnostics(candidate: dict[str, Any], harness: dict[str, Any],
                        snapshot: dict[str, Any], intent: dict[str, Any]) -> list[dict[str, Any]]:
    rejections: list[dict[str, Any]] = []
    if harness.get("valid") is False:
        rejections.append(diagnostic("harness.invalid_descriptor", "harness descriptor is invalid",
                                     harness=candidate["harness"]))
    if harness.get("cliInstalled") is False:
        rejections.append(diagnostic("harness.cli_missing", "harness CLI is not installed",
                                     harness=candidate["harness"]))
    preferred_harness = intent.get("preferredHarness")
    if preferred_harness and candidate["harness"] != preferred_harness:
        rejections.append(diagnostic(
            "intent.preferred_harness_mismatch",
            f"preferredHarness={preferred_harness} excludes {candidate['harness']}",
            preferredHarness=preferred_harness,
            candidateHarness=candidate["harness"],
        ))
    if intent.get("preferredModel") and not _model_like(candidate, intent.get("preferredModel")):
        rejections.append(diagnostic(
            "intent.preferred_model_mismatch",
            f"preferredModel={intent.get('preferredModel')} excludes {candidate['model']}",
            preferredModel=intent.get("preferredModel"),
            candidateModel=candidate["model"],
        ))
    if intent.get("localOnly") and not candidate["local"]:
        rejections.append(diagnostic("intent.local_only_excludes_cloud", "localOnly excludes billable/cloud provider routes",
                                     provider=candidate["provider"]))
    if candidate["billable"] and not intent.get("allowBillable"):
        rejections.append(diagnostic("billing.disallowed", "billable route requires allowBillable=true",
                                     provider=candidate["provider"]))
    if candidate["provider"] == "openrouter" and not _openrouter_key_available(snapshot):
        rejections.append(diagnostic("auth.openrouter_key_missing", "OpenRouter key is not available"))
    if candidate["local"]:
        if not snapshot.get("normalized", {}).get("healthyLocalRuntime"):
            rejections.append(diagnostic("runtime.local_unhealthy", "local runtime is not healthy",
                                         runtimeModel=candidate.get("runtimeModel")))
        elif not _local_runtime_model_available(snapshot, candidate):
            runtime_model = candidate.get("runtimeModel") or candidate.get("backend")
            rejections.append(diagnostic(
                "runtime.model_unavailable",
                f"local runtime does not advertise model {runtime_model}",
                runtimeModel=runtime_model,
            ))
    estimated = as_int(intent.get("estimatedInputTokens")) or 0
    effective = as_int(candidate.get("effectiveInput"))
    if estimated and effective is not None and estimated > effective:
        rejections.append(diagnostic(
            "context.input_exceeds_effective",
            f"estimatedInputTokens={estimated} exceeds effectiveInput={effective}",
            estimatedInputTokens=estimated,
            effectiveInput=effective,
        ))
    return rejections


def _score(candidate: dict[str, Any], intent: dict[str, Any]) -> tuple[float, list[dict[str, Any]], list[dict[str, Any]]]:
    score = 50.0
    reasons: list[dict[str, Any]] = [
        diagnostic("route.eligible", "harness and model passed hard filters")
    ]
    risks: list[dict[str, Any]] = []
    estimated = as_int(intent.get("estimatedInputTokens")) or 0
    effective = as_int(candidate.get("effectiveInput"))
    context = as_int(candidate.get("context"))
    if effective and estimated:
        headroom = max(effective - estimated, 0)
        score += min(25.0, (headroom / max(estimated, 1)) * 10.0 + 10.0)
        reasons.append(diagnostic(
            "context.fits_estimate",
            f"effectiveInput {effective} fits estimated input {estimated}",
            effectiveInput=effective,
            estimatedInputTokens=estimated,
        ))
    elif context:
        score += min(15.0, context / 100000.0)
        reasons.append(diagnostic("context.available", f"context window {context} is available",
                                  context=context))
    if candidate["local"]:
        score += 15.0
        reasons.append(diagnostic("route.local_non_billable", "local route avoids provider billing and improves privacy"))
    else:
        risks.append(diagnostic("billing.provider_billable", "billable provider route",
                                provider=candidate["provider"]))
        score -= 5.0
    if (
        not intent.get("preferredHarness")
        and not intent.get("preferredModel")
        and candidate["harness"] == "claude"
        and candidate["model"] == "opus"
    ):
        score += 30.0
        reasons.append(diagnostic("route.default_claude_opus", "matches the default Claude tier"))
    if intent.get("preferredHarness") == candidate["harness"]:
        score += 20.0
        reasons.append(diagnostic("intent.preferred_harness_match", "matches preferred harness",
                                  preferredHarness=intent.get("preferredHarness")))
    if intent.get("preferredModel") and _model_like(candidate, intent.get("preferredModel")):
        score += 20.0
        reasons.append(diagnostic("intent.preferred_model_match", "matches preferred model",
                                  preferredModel=intent.get("preferredModel")))
    if intent.get("requiresTools") and candidate["harness"] in ("claude", "codex"):
        score += 8.0
        reasons.append(diagnostic("harness.tool_workflow_suitable", "harness is suitable for code/tool workflows"))
    if estimated > 200000 and candidate["harness"] == "codex":
        score += 10.0
        reasons.append(diagnostic("long_context.codex_preferred", "codex surface is preferred for long-context routing",
                                  estimatedInputTokens=estimated))
    return round(score, 3), reasons, risks


def plan_routes(snapshot: dict[str, Any], intent: dict[str, Any] | None = None,
                include_rejected: bool = False) -> dict[str, Any]:
    intent = normalize_intent(intent)
    accepted: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []
    rejected_count = 0
    harnesses = snapshot.get("normalized", {}).get("harnesses", [])
    for harness in harnesses:
        for model in _candidate_model_rows(harness, snapshot):
            candidate = _candidate_from(harness, model)
            rejects = _reject_diagnostics(candidate, harness, snapshot, intent)
            if rejects:
                rejected_count += 1
                if include_rejected:
                    rejected.append({**candidate, "rejected": [r["message"] for r in rejects], "rejections": rejects})
                continue
            score, reasons, risks = _score(candidate, intent)
            accepted.append({
                **candidate,
                "score": score,
                "reasons": [r["message"] for r in reasons],
                "selectionReasons": reasons,
                "risks": [r["message"] for r in risks],
                "riskDiagnostics": risks,
            })
    accepted.sort(key=lambda c: c["score"], reverse=True)
    result = {
        "schemaVersion": SCHEMA_VERSION,
        "contractVersion": CONTRACT_VERSION,
        "kind": "ai-litellm.router.plan",
        "intent": intent,
        "selected": accepted[0] if accepted else None,
        "candidates": accepted[:10],
        "candidateCount": len(accepted),
        "rejectedCount": rejected_count,
        "snapshotErrors": snapshot.get("errors", []),
    }
    if include_rejected:
        result["rejected"] = rejected[:50]
    return result
