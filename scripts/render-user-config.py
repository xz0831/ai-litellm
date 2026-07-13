#!/usr/bin/env python3
"""Render immutable package defaults plus durable user overrides.

The installer owns the two ``*.base`` inputs.  Public model/alias commands own
the JSON files below ``~/.config/claude-litellm``.  The LiteLLM and Claude Code
processes consume only the generated effective outputs, so package upgrades can
replace defaults without overwriting or mistaking user choices for package
drift.
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import stat
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

import yaml


USER_MODELS_BEGIN = "# BEGIN claude-litellm user models"
USER_MODELS_END = "# END claude-litellm user models"
DISCOVERED_BEGIN = "# BEGIN claude-litellm discovered local routes"
DISCOVERED_END = "# END claude-litellm discovered local routes"
SURFACE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:+-]{0,127}$")
RESERVED_SURFACES = frozenset(
    {
        "auth",
        "context",
        "doctor",
        "fable",
        "haiku",
        "harness",
        "key",
        "model",
        "opus",
        "permissions",
        "proxy",
        "reasoning",
        "runtime",
        "sonnet",
        "status",
        "sync",
        "uninstall",
        "use",
    }
)
BACKEND_RE = re.compile(r"^\S{1,512}$")
ENV_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
PROVIDER_SECRET_ENV_RE = re.compile(
    r"(?:^|_)(?:API_?KEY|APIKEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY|CREDENTIALS?|"
    r"ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN)(?:_|$)"
)
# User routes enter through LiteLLM's Anthropic pass-through adapter. In 1.92,
# unqualified models have no supports_xhigh/supports_max registry flags, so the
# adapter normalizes both values to high. Refuse a false selectable contract;
# raw provider claims belong in x_provider_reasoning_efforts instead.
EFFORTS = {"none", "minimal", "low", "medium", "high"}
SECRET_PARAM_NAMES = {
    "api_key",
    "authorization",
    "access_token",
    "refresh_token",
    "client_secret",
    "password",
    "aws_access_key_id",
    "aws_secret_access_key",
    "aws_session_token",
    "oci_key",
}
RESERVED_PROVIDER_SECRET_ENVS = {
    "ANTHROPIC_AUTH_TOKEN",
    "CLAUDE_CODE_OAUTH_TOKEN",
    "LITELLM_API_KEY",
    "LITELLM_MASTER_KEY",
    "XAI_API_KEY",
}
CONTROL_ENV_PREFIXES = (
    "AI_LITELLM_",
    "CLAUDE_LITELLM_",
    "CHATGPT_",
    "XAI_OAUTH_",
    "LITELLM_",
)
CONTROL_ENV_SUFFIXES = (
    "_DIR",
    "_PATH",
    "_HOME",
    "_CONFIG",
    "_FILE",
    "_ROOT",
    "_URL",
    "_HOST",
    "_PORT",
    "_ENABLED",
    "_MODEL",
)


def _is_public_token_metric(normalized: str) -> bool:
    """Return True for public LiteLLM capability/pricing token fields."""
    return bool(
        re.fullmatch(
            r"(?:max|input|output|prompt|completion|reasoning|cached|cache|audio|image|citation|tool)_[a-z0-9_]*tokens",
            normalized,
        )
        or re.fullmatch(
            r"(?:input|output|prompt|completion|cached|cache|audio|image|reasoning|citation)_[a-z0-9_]*cost_per_[a-z0-9_]*token",
            normalized,
        )
    )


def _is_secret_key(key: Any) -> bool:
    normalized = re.sub(r"[^a-z0-9]+", "_", str(key).lower()).strip("_")
    if _is_public_token_metric(normalized):
        return False
    return (
        normalized in SECRET_PARAM_NAMES
        or normalized.endswith((
            "_api_key",
            "_access_token",
            "_refresh_token",
            "_client_secret",
            "_password",
            "_token",
            "_secret",
            "_private_key",
            "_credential",
            "_credentials",
        ))
        or normalized in {
            "authorization",
            "proxy_authorization",
            "credentials",
            "credential",
            "token",
            "private_token",
            "secret",
            "private_key",
            "key",
            "service_key",
            "servicekey",
            "clientsecret",
            "clientkey",
        }
    )


def _is_metadata_secret_key(key: Any) -> bool:
    normalized = re.sub(r"[^a-z0-9]+", "_", str(key).lower()).strip("_")
    if _is_public_token_metric(normalized):
        return False
    return (
        normalized in SECRET_PARAM_NAMES
        or normalized in {
            "authorization",
            "proxy_authorization",
            "credentials",
            "credential",
            "token",
            "private_token",
            "secret",
            "private_key",
            "key",
            "service_key",
            "servicekey",
            "clientsecret",
            "clientkey",
        }
        or normalized.endswith((
            "_api_key",
            "_access_token",
            "_refresh_token",
            "_client_secret",
            "_password",
            "_token",
            "_tokens",
            "_private_token",
            "_secret",
            "_private_key",
            "_credential",
            "_credentials",
        ))
    )


def _validate_provider_secret_env(env_name: str, surface: str) -> None:
    if not ENV_NAME_RE.fullmatch(env_name):
        raise ValueError(f"{surface}: invalid provider credential environment variable")
    if (
        env_name in RESERVED_PROVIDER_SECRET_ENVS
        or env_name.startswith(CONTROL_ENV_PREFIXES)
        or env_name.endswith(CONTROL_ENV_SUFFIXES)
        or not (
            PROVIDER_SECRET_ENV_RE.search(env_name)
            or env_name.endswith("APIKEY")
            or env_name.endswith("_KEY")
        )
    ):
        raise ValueError(
            f"{surface}: provider credentials must use a dedicated secret-style environment variable"
        )


def _private_regular_file(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ValueError(f"user configuration must be a regular file: {path}")
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise ValueError(f"user configuration permissions must be 0600: {path}")


def _safe_effective_output(path: Path) -> None:
    """Reject an installed output that cannot be atomically replaced safely."""
    if not path.exists() and not path.is_symlink():
        return
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ValueError(f"effective configuration must be a regular file: {path}")


def _load_json(path: Path, default: dict[str, Any]) -> dict[str, Any]:
    if not path.exists() and not path.is_symlink():
        return copy.deepcopy(default)
    _private_regular_file(path)
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    if path.exists() and (path.is_symlink() or not path.is_file()):
        raise ValueError(f"refusing to replace non-regular path: {path}")
    encoded = content.encode("utf-8")
    if path.is_file() and path.read_bytes() == encoded:
        os.chmod(path, 0o600)
        return
    fd, staged_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    staged = Path(staged_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(staged, path)
        os.chmod(path, 0o600)
    finally:
        staged.unlink(missing_ok=True)


def _validate_api_base(value: Any, surface: str) -> None:
    if value in (None, ""):
        return
    parsed = urlparse(str(value))
    if (
        not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError(f"{surface}: api_base must have a host and no credentials, query, or fragment")
    if parsed.scheme == "https":
        return
    if parsed.scheme == "http" and parsed.hostname in {"127.0.0.1", "localhost", "::1"}:
        return
    raise ValueError(f"{surface}: api_base must use HTTPS or loopback HTTP")


def _validate_secret_references(value: Any, path: tuple[str, ...], surface: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if _is_secret_key(key) and child not in (None, "none"):
                if not isinstance(child, str) or not child.startswith("os.environ/"):
                    dotted = ".".join((*path, str(key)))
                    raise ValueError(
                        f"{surface}: store {dotted} in an environment variable, not the registry"
                    )
                env_name = child.removeprefix("os.environ/")
                _validate_provider_secret_env(env_name, surface)
            _validate_secret_references(child, (*path, str(key)), surface)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _validate_secret_references(child, (*path, str(index)), surface)


def _validate_public_metadata(value: Any, path: tuple[str, ...], surface: str) -> None:
    """model_info is returned by /model/info, so credentials never belong in it."""
    if isinstance(value, dict):
        for key, child in value.items():
            if _is_metadata_secret_key(key) and child not in (None, "none"):
                dotted = ".".join((*path, str(key)))
                raise ValueError(f"{surface}: credentials are forbidden in public {dotted}")
            _validate_public_metadata(child, (*path, str(key)), surface)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _validate_public_metadata(child, (*path, str(index)), surface)
    elif isinstance(value, str) and value.startswith("os.environ/"):
        dotted = ".".join(path)
        raise ValueError(f"{surface}: environment references are forbidden in public {dotted}")


def _validated_user_models(payload: dict[str, Any], base_names: set[str]) -> list[dict[str, Any]]:
    if payload.get("schemaVersion", 1) != 1:
        raise ValueError("unsupported user model registry schemaVersion")
    unknown = set(payload) - {"schemaVersion", "models"}
    if unknown:
        raise ValueError(f"unknown user model registry fields: {', '.join(sorted(unknown))}")
    models = payload.get("models", [])
    if not isinstance(models, list):
        raise ValueError("user model registry 'models' must be an array")

    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in models:
        if not isinstance(raw, dict):
            raise ValueError("every user model entry must be an object")
        unknown_entry = set(raw) - {"model_name", "litellm_params", "model_info"}
        if unknown_entry:
            raise ValueError(f"unknown user model fields: {', '.join(sorted(unknown_entry))}")
        surface = raw.get("model_name")
        params = raw.get("litellm_params")
        info = raw.get("model_info", {})
        if not isinstance(surface, str) or not SURFACE_RE.fullmatch(surface):
            raise ValueError(
                "user model_name must be 1-128 safe URL/name characters "
                "(letters, numbers, '.', '_', ':', '+', '-')"
            )
        if surface in RESERVED_SURFACES:
            raise ValueError(f"{surface}: model_name is reserved by the claude-litellm CLI")
        if surface in base_names:
            raise ValueError(f"{surface}: package model names cannot be overridden")
        if surface in seen:
            raise ValueError(f"duplicate user model_name: {surface}")
        if (
            not isinstance(params, dict)
            or not isinstance(params.get("model"), str)
            or not BACKEND_RE.fullmatch(params["model"])
        ):
            raise ValueError(f"{surface}: litellm_params.model is required")
        if params["model"].startswith("chatgpt/") or "use_xai_oauth" in params:
            raise ValueError(
                f"{surface}: OAuth adapters are package-defined routes and cannot be supplied by the user registry"
            )
        if "api_key" not in params:
            raise ValueError(
                f"{surface}: litellm_params.api_key must explicitly reference an environment variable or be 'none'"
            )
        api_key = params["api_key"]
        if api_key != "none" and (
            not isinstance(api_key, str) or not api_key.startswith("os.environ/")
        ):
            raise ValueError(
                f"{surface}: litellm_params.api_key must explicitly reference an environment variable or be 'none'"
            )
        if api_key != "none":
            _validate_provider_secret_env(api_key.removeprefix("os.environ/"), surface)
        if not isinstance(info, dict):
            raise ValueError(f"{surface}: model_info must be an object")
        for field in ("max_input_tokens", "max_output_tokens"):
            if not isinstance(info.get(field), int) or isinstance(info.get(field), bool) or info[field] <= 0:
                raise ValueError(f"{surface}: model_info.{field} must be a positive integer")
        if not isinstance(info.get("supports_reasoning"), bool):
            raise ValueError(f"{surface}: model_info.supports_reasoning must be true or false")
        efforts = info.get("x_reasoning_efforts")
        if (
            not isinstance(efforts, list)
            or len(efforts) != len(set(efforts))
            or any(not isinstance(item, str) or item not in EFFORTS for item in efforts)
        ):
            raise ValueError(
                f"{surface}: model_info.x_reasoning_efforts is invalid; "
                "xhigh/max are not selectable through the LiteLLM 1.92 "
                "Anthropic transport"
            )
        if efforts and not info["supports_reasoning"]:
            raise ValueError(f"{surface}: reasoning efforts require supports_reasoning=true")
        _validate_secret_references(params, ("litellm_params",), surface)
        _validate_public_metadata(info, ("model_info",), surface)
        _validate_api_base(params.get("api_base"), surface)
        entry = copy.deepcopy(raw)
        entry.setdefault("model_info", {})["x_registry_source"] = "user-overlay"
        result.append(entry)
        seen.add(surface)
    return result


def _managed_block(text: str, begin: str, end: str) -> str | None:
    if text.count(begin) != text.count(end):
        raise ValueError(f"unbalanced generated block markers: {begin}")
    if begin not in text:
        return None
    if text.count(begin) != 1:
        raise ValueError(f"duplicate generated block markers: {begin}")
    start = text.index(begin)
    finish = text.index(end, start) + len(end)
    if finish < len(text) and text[finish] == "\n":
        finish += 1
    return text[start:finish]


def _preserve_discovered_routes(base_text: str, effective_path: Path) -> str:
    """Carry forward only the last-known-good runtime-owned route block."""
    base_block = _managed_block(base_text, DISCOVERED_BEGIN, DISCOVERED_END)
    if base_block is None:
        raise ValueError("package base config is missing discovered-route markers")
    if not effective_path.is_file() or effective_path.is_symlink():
        return base_text
    existing_text = effective_path.read_text(encoding="utf-8")
    existing_block = _managed_block(existing_text, DISCOVERED_BEGIN, DISCOVERED_END)
    if existing_block is None:
        return base_text
    _validate_discovered_block(existing_block)
    return base_text.replace(base_block, existing_block, 1)


def _validate_discovered_block(block: str) -> None:
    """Validate the only generated effective-file content carried across renders."""
    lines = block.splitlines(keepends=True)
    if len(lines) < 2 or lines[0].strip() != DISCOVERED_BEGIN or lines[-1].strip() != DISCOVERED_END:
        raise ValueError("malformed discovered-route block")
    parsed = yaml.safe_load("model_list:\n" + "".join(lines[1:-1])) or {}
    entries = parsed.get("model_list") or []
    if not isinstance(entries, list):
        raise ValueError("discovered-route block must contain a model list")
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) - {"model_name", "litellm_params", "model_info"}:
            raise ValueError("invalid discovered-route entry")
        surface = entry.get("model_name")
        params = entry.get("litellm_params")
        info = entry.get("model_info")
        if (
            not isinstance(surface, str)
            or not SURFACE_RE.fullmatch(surface)
            or surface in RESERVED_SURFACES
            or surface in seen
        ):
            raise ValueError("invalid or duplicate discovered model_name")
        if not isinstance(params, dict) or not isinstance(info, dict):
            raise ValueError(f"{surface}: invalid discovered-route metadata")
        if not isinstance(params.get("model"), str) or not params["model"].startswith("openai/"):
            raise ValueError(f"{surface}: discovered routes must use an explicit openai/ backend")
        if params.get("api_key") != "none":
            raise ValueError(f"{surface}: discovered routes must explicitly disable provider credentials")
        _validate_api_base(params.get("api_base"), surface)
        discovered_base = urlparse(str(params.get("api_base", "")))
        if discovered_base.scheme != "http" or discovered_base.hostname not in {
            "127.0.0.1",
            "localhost",
            "::1",
        }:
            raise ValueError(f"{surface}: discovered routes require an explicit loopback HTTP api_base")
        for field in ("max_input_tokens", "max_output_tokens"):
            value = info.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
                raise ValueError(f"{surface}: discovered model_info.{field} must be a positive integer")
        if info.get("x_registry_source") != "runtime-discovery":
            raise ValueError(f"{surface}: invalid discovered-route ownership marker")
        _validate_secret_references(params, ("litellm_params",), surface)
        _validate_public_metadata(info, ("model_info",), surface)
        seen.add(surface)


def _render_models(
    base_path: Path, user_path: Path, effective_path: Path
) -> tuple[str, set[str], int]:
    base_text = base_path.read_text(encoding="utf-8")
    if USER_MODELS_BEGIN in base_text or USER_MODELS_END in base_text:
        raise ValueError(f"package base config contains generated user markers: {base_path}")
    base_text = _preserve_discovered_routes(base_text, effective_path)
    base = yaml.safe_load(base_text) or {}
    if not isinstance(base, dict):
        raise ValueError(f"package base config must be a YAML object: {base_path}")
    base_entries = base.get("model_list", [])
    if not isinstance(base_entries, list):
        raise ValueError("package model_list must be an array")
    base_names = {
        entry.get("model_name")
        for entry in base_entries
        if isinstance(entry, dict) and isinstance(entry.get("model_name"), str)
    }
    payload = _load_json(user_path, {"schemaVersion": 1, "models": []})
    models = _validated_user_models(payload, base_names)
    if not models:
        rendered = base_text
    else:
        blocks: list[str] = [USER_MODELS_BEGIN + "\n"]
        for model in models:
            dumped = yaml.safe_dump([model], sort_keys=False, allow_unicode=True, default_flow_style=False)
            blocks.append("".join(f"  {line}" for line in dumped.splitlines(keepends=True)))
        blocks.append(USER_MODELS_END + "\n\n")
        block = "".join(blocks)
        marker = DISCOVERED_BEGIN if DISCOVERED_BEGIN in base_text else "general_settings:"
        offset = base_text.find(marker)
        if offset < 0:
            raise ValueError("cannot find effective-config insertion point")
        rendered = base_text[:offset] + block + base_text[offset:]

    effective = yaml.safe_load(rendered) or {}
    effective_entries = effective.get("model_list", [])
    all_names = [
        entry.get("model_name")
        for entry in effective_entries
        if isinstance(entry, dict) and isinstance(entry.get("model_name"), str)
    ]
    if len(all_names) != len(set(all_names)):
        raise ValueError("effective model registry contains duplicate model_name values")
    return rendered, set(all_names), len(models)


def _render_settings(
    base_path: Path, override_path: Path, model_names: set[str]
) -> tuple[str, int, list[str]]:
    base = json.loads(base_path.read_text(encoding="utf-8"))
    if not isinstance(base, dict):
        raise ValueError(f"package Claude settings must be an object: {base_path}")
    payload = _load_json(override_path, {"schemaVersion": 1, "settings": {}})
    if payload.get("schemaVersion", 1) != 1:
        raise ValueError("unsupported Claude settings override schemaVersion")
    unknown = set(payload) - {"schemaVersion", "settings", "harness"}
    if unknown:
        raise ValueError(f"unknown Claude settings override fields: {', '.join(sorted(unknown))}")
    overrides = payload.get("settings", {})
    if not isinstance(overrides, dict):
        raise ValueError("Claude settings override 'settings' must be an object")
    unknown_settings = set(overrides) - {"default", "aliases", "displayNames"}
    if unknown_settings:
        raise ValueError(f"unsupported Claude settings overrides: {', '.join(sorted(unknown_settings))}")

    effective = copy.deepcopy(base)
    known_tiers = set(base.get("aliases", {}))
    if not known_tiers or not all(isinstance(tier, str) for tier in known_tiers):
        raise ValueError("package Claude settings must define string alias tiers")
    if "default" in overrides:
        if not isinstance(overrides["default"], str) or overrides["default"] not in known_tiers:
            raise ValueError(
                "Claude default override must name a package-defined tier: "
                + ", ".join(sorted(known_tiers))
            )
        effective["default"] = overrides["default"]
    for key in ("aliases", "displayNames"):
        values = overrides.get(key, {})
        if not isinstance(values, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in values.items()):
            raise ValueError(f"Claude {key} override must be a string map")
        unknown_tiers = set(values) - known_tiers
        if unknown_tiers:
            raise ValueError(
                f"Claude {key} contains unknown tiers: {', '.join(sorted(unknown_tiers))}"
            )
        effective.setdefault(key, {}).update(values)
    harness = payload.get("harness", {})
    if not isinstance(harness, dict):
        raise ValueError("Claude harness override must be an object")
    unknown_harness = set(harness) - {"reasoningEffort", "permissionMode"}
    if unknown_harness:
        raise ValueError(f"unsupported Claude harness overrides: {', '.join(sorted(unknown_harness))}")
    if "reasoningEffort" in harness and harness["reasoningEffort"] not in {
        "auto",
        "low",
        "medium",
        "high",
        "xhigh",
        "max",
    }:
        raise ValueError("unsupported Claude harness reasoningEffort")
    if "permissionMode" in harness and harness["permissionMode"] not in {
        "default",
        "bypassPermissions",
    }:
        raise ValueError("unsupported Claude harness permissionMode")

    unresolved = [
        f"{tier}:{model}"
        for tier, model in effective.get("aliases", {}).items()
        if model not in model_names
    ]
    default_route = effective.get("default")
    if (
        not isinstance(default_route, str)
        or (
            default_route not in model_names
            and default_route not in effective.get("aliases", {})
        )
    ):
        unresolved.append(f"default:{default_route}")
    return (
        json.dumps(effective, indent=2, ensure_ascii=False) + "\n",
        len(overrides) + (1 if harness else 0),
        unresolved,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-config", type=Path, required=True)
    parser.add_argument("--effective-config", type=Path, required=True)
    parser.add_argument("--user-models", type=Path, required=True)
    parser.add_argument("--base-settings", type=Path, required=True)
    parser.add_argument("--effective-settings", type=Path, required=True)
    parser.add_argument("--settings-override", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--check",
        action="store_true",
        help="validate and require the installed effective files to match exactly",
    )
    mode.add_argument(
        "--validate-only",
        action="store_true",
        help="validate inputs and render in memory without comparing or writing outputs",
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    _safe_effective_output(args.effective_config)
    _safe_effective_output(args.effective_settings)

    rendered_config, model_names, user_model_count = _render_models(
        args.base_config, args.user_models, args.effective_config
    )
    rendered_settings, override_count, unresolved_aliases = _render_settings(
        args.base_settings, args.settings_override, model_names
    )
    if unresolved_aliases:
        raise ValueError(
            "unresolved Claude model selections: " + ", ".join(unresolved_aliases)
        )
    if args.check:
        expected_outputs = (
            (args.effective_config, rendered_config),
            (args.effective_settings, rendered_settings),
        )
        for path, expected in expected_outputs:
            if not path.is_file() or path.read_bytes() != expected.encode("utf-8"):
                raise ValueError(
                    f"effective configuration is stale or modified: {path}; "
                    "run 'claude-litellm sync'"
                )
    elif not args.validate_only:
        _atomic_write(args.effective_config, rendered_config)
        _atomic_write(args.effective_settings, rendered_settings)
    summary = {
        "checked": True,
        "written": not (args.check or args.validate_only),
        "userModels": user_model_count,
        "settingOverrideGroups": override_count,
        "effectiveModels": len(model_names),
        "unresolvedAliases": unresolved_aliases,
    }
    if args.json:
        print(json.dumps(summary, sort_keys=True))
    else:
        action = "checked" if args.check else ("validated" if args.validate_only else "rendered")
        print(f"{action} effective config: {len(model_names)} models ({user_model_count} user), {override_count} setting override group(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
