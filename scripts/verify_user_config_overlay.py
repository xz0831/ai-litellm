#!/usr/bin/env python3
"""Deterministic regression checks for durable user configuration overlays."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml


REPO = Path(__file__).resolve().parents[1]
RENDERER = REPO / "scripts" / "render-user-config.py"
BASE_CONFIG = REPO / "config" / "litellm_config.yaml"
BASE_SETTINGS = REPO / "config" / "claude-litellm" / "settings.json"


def write_private(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    path.chmod(0o600)


def invoke(root: Path, *extra: str, expect_ok: bool = True) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(RENDERER),
        "--base-config",
        str(BASE_CONFIG),
        "--effective-config",
        str(root / "effective.yaml"),
        "--user-models",
        str(root / "user" / "models.json"),
        "--base-settings",
        str(BASE_SETTINGS),
        "--effective-settings",
        str(root / "effective-settings.json"),
        "--settings-override",
        str(root / "user" / "settings.json"),
        *extra,
    ]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if expect_ok and result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    if not expect_ok and not result.returncode:
        raise AssertionError("renderer unexpectedly accepted an invalid overlay")
    return result


def model_payload(*, api_key: str = "os.environ/OPENROUTER_API_KEY", name: str = "Overlay-Test-openrouter") -> dict:
    return {
        "schemaVersion": 1,
        "models": [
            {
                "model_name": name,
                "litellm_params": {
                    "model": "openrouter/example/overlay-test",
                    "api_key": api_key,
                },
                "model_info": {
                    "max_input_tokens": 100000,
                    "max_output_tokens": 8000,
                    "supports_reasoning": False,
                    "x_reasoning_efforts": [],
                },
            }
        ],
    }


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="claude-litellm-overlay-") as raw:
        root = Path(raw)

        # Empty overlays reproduce package defaults while writing private
        # generated outputs.
        summary = json.loads(invoke(root, "--json").stdout)
        assert summary["userModels"] == 0
        assert summary["unresolvedAliases"] == []
        assert (root / "effective.yaml").read_bytes() == BASE_CONFIG.read_bytes()
        assert json.loads((root / "effective-settings.json").read_text()) == json.loads(
            BASE_SETTINGS.read_text()
        )
        assert (root / "effective.yaml").stat().st_mode & 0o777 == 0o600
        assert (root / "effective-settings.json").stat().st_mode & 0o777 == 0o600

        # A last-known-good runtime discovery block is the sole generated
        # effective-file state carried across a base+overlay render. This keeps
        # local routes available when oMLX is temporarily offline.
        effective_path = root / "effective.yaml"
        original = effective_path.read_text(encoding="utf-8")
        empty_discovered = (
            "# BEGIN claude-litellm discovered local routes\n"
            "# Managed by `claude-litellm sync`; generated from runtimes.omlx /v1/models.\n"
            "# END claude-litellm discovered local routes\n"
        )
        discovered = (
            "# BEGIN claude-litellm discovered local routes\n"
            "# Managed by `claude-litellm sync`; generated from runtimes.omlx /v1/models.\n"
            "  - model_name: Future-Local-omlx\n"
            "    litellm_params:\n"
            "      model: openai/Future-Local\n"
            "      api_base: http://127.0.0.1:8000/v1\n"
            "      api_key: none\n"
            "    model_info:\n"
            "      max_input_tokens: 32768\n"
            "      max_output_tokens: 4096\n"
            "      supports_reasoning: false\n"
            "      x_reasoning_efforts: []\n"
            "      x_registry_source: runtime-discovery\n"
            "# END claude-litellm discovered local routes\n"
        )
        assert empty_discovered in original
        effective_path.write_text(original.replace(empty_discovered, discovered), encoding="utf-8")
        effective_path.chmod(0o600)

        write_private(root / "user" / "models.json", model_payload())
        write_private(
            root / "user" / "settings.json",
            {
                "schemaVersion": 1,
                "settings": {
                    "aliases": {
                        "opus": "Overlay-Test-openrouter",
                        "haiku": "Future-Local-omlx",
                    },
                    "displayNames": {"opus": "Overlay Test"},
                },
                "harness": {
                    "reasoningEffort": "high",
                    "permissionMode": "bypassPermissions",
                },
            },
        )
        summary = json.loads(invoke(root, "--json").stdout)
        assert summary["userModels"] == 1
        assert summary["unresolvedAliases"] == []
        text = (root / "effective.yaml").read_text(encoding="utf-8")
        assert discovered in text
        assert text.index("# BEGIN claude-litellm user models") < text.index(
            "# BEGIN claude-litellm discovered local routes"
        )
        config = yaml.safe_load(text)
        added = next(row for row in config["model_list"] if row["model_name"] == "Overlay-Test-openrouter")
        assert added["model_info"]["x_registry_source"] == "user-overlay"
        assert json.loads((root / "effective-settings.json").read_text())["aliases"]["opus"] == (
            "Overlay-Test-openrouter"
        )

        # Check mode validates without touching already-rendered outputs and
        # proves that the installed effective bytes still match the immutable
        # defaults + overlays. Validation-only is reserved for installer/dry-run
        # preflight where an old or absent output must not be trusted or changed.
        before = (root / "effective.yaml").read_bytes()
        invoke(root, "--check", "--json")
        assert (root / "effective.yaml").read_bytes() == before
        effective_path.write_text(
            effective_path.read_text(encoding="utf-8") + "# untrusted generated drift\n",
            encoding="utf-8",
        )
        drifted = effective_path.read_bytes()
        invoke(root, "--check", expect_ok=False)
        invoke(root, "--validate-only")
        assert effective_path.read_bytes() == drifted
        invoke(root)

        effective_settings = root / "effective-settings.json"
        effective_settings.write_text(
            effective_settings.read_text(encoding="utf-8").rstrip() + " \n",
            encoding="utf-8",
        )
        invoke(root, "--check", expect_ok=False)
        invoke(root)
        invoke(root, "--check")

        # Typos or removed routes fail closed instead of restarting Claude with
        # an unusable durable alias.
        settings = json.loads((root / "user" / "settings.json").read_text())
        settings["settings"]["aliases"]["haiku"] = "Future-Local-omlx-Next"
        write_private(root / "user" / "settings.json", settings)
        invoke(root, "--json", expect_ok=False)
        settings["settings"]["aliases"]["haiku"] = "Future-Local-omlx"
        write_private(root / "user" / "settings.json", settings)
        invoke(root, "--json")
        settings["settings"]["default"] = "Definitely-Not-A-Route"
        write_private(root / "user" / "settings.json", settings)
        invoke(root, expect_ok=False)
        settings["settings"]["default"] = "Overlay-Test-openrouter"
        write_private(root / "user" / "settings.json", settings)
        invoke(root, expect_ok=False)
        del settings["settings"]["default"]
        settings["settings"]["aliases"]["invented-tier"] = "Overlay-Test-openrouter"
        write_private(root / "user" / "settings.json", settings)
        invoke(root, expect_ok=False)
        del settings["settings"]["aliases"]["invented-tier"]
        write_private(root / "user" / "settings.json", settings)
        invoke(root)

        # Permission bypass is a narrow, explicit harness opt-in. Both
        # supported modes validate, while other Claude CLI permission modes,
        # empty values and non-strings fail closed at the durable boundary.
        for valid_mode in ("default", "bypassPermissions"):
            settings["harness"]["permissionMode"] = valid_mode
            write_private(root / "user" / "settings.json", settings)
            invoke(root)
        for invalid_mode in ("plan", "", True, None):
            settings["harness"]["permissionMode"] = invalid_mode
            write_private(root / "user" / "settings.json", settings)
            invoke(root, expect_ok=False)
        settings["harness"]["permissionMode"] = "bypassPermissions"
        write_private(root / "user" / "settings.json", settings)
        invoke(root)

        # Marker ambiguity and malformed route YAML fail before replacing the
        # previously valid effective output.
        good_effective = effective_path.read_bytes()
        duplicate = effective_path.read_text(encoding="utf-8") + discovered
        effective_path.write_text(duplicate, encoding="utf-8")
        effective_path.chmod(0o600)
        invoke(root, expect_ok=False)
        effective_path.write_bytes(good_effective)
        effective_path.chmod(0o600)

        unsafe_target = root / "unsafe-effective-target.json"
        unsafe_target.write_text("{}\n", encoding="utf-8")
        effective_settings = root / "effective-settings.json"
        safe_settings = effective_settings.read_bytes()
        effective_settings.unlink()
        effective_settings.symlink_to(unsafe_target)
        invoke(root, expect_ok=False)
        effective_settings.unlink()
        effective_settings.write_bytes(safe_settings)
        effective_settings.chmod(0o600)
        malformed = effective_path.read_text(encoding="utf-8").replace(
            "      model: openai/Future-Local\n",
            "      model: [unterminated\n",
        )
        effective_path.write_text(malformed, encoding="utf-8")
        effective_path.chmod(0o600)
        invoke(root, expect_ok=False)
        effective_path.write_bytes(good_effective)
        effective_path.chmod(0o600)

        # Literal credentials, package-name collisions and non-private user
        # files all fail before replacing an effective file.
        write_private(root / "user" / "models.json", model_payload(api_key="sk-secret"))
        invoke(root, expect_ok=False)
        write_private(
            root / "user" / "models.json",
            model_payload(api_key="os.environ/LITELLM_MASTER_KEY"),
        )
        invoke(root, expect_ok=False)
        write_private(
            root / "user" / "models.json",
            model_payload(api_key="os.environ/XAI_API_KEY"),
        )
        invoke(root, expect_ok=False)
        token_payload = model_payload()
        token_payload["models"][0]["litellm_params"]["azure_ad_token"] = "literal-secret-token"
        write_private(root / "user" / "models.json", token_payload)
        invoke(root, expect_ok=False)
        sap_payload = model_payload()
        sap_payload["models"][0]["litellm_params"]["service_key"] = {
            "clientid": "public-id",
            "clientsecret": "literal-secret",
            "key": "literal-private-key",
        }
        write_private(root / "user" / "models.json", sap_payload)
        invoke(root, expect_ok=False)
        sap_env_payload = model_payload()
        sap_env_payload["models"][0]["litellm_params"]["service_key"] = "os.environ/AICORE_SERVICE_KEY"
        write_private(root / "user" / "models.json", sap_env_payload)
        invoke(root)
        vertex_payload = model_payload()
        vertex_payload["models"][0]["litellm_params"]["vertex_credentials"] = {
            "private_key": "literal-private-key"
        }
        write_private(root / "user" / "models.json", vertex_payload)
        invoke(root, expect_ok=False)
        vertex_env_payload = model_payload()
        vertex_env_payload["models"][0]["litellm_params"]["vertex_credentials"] = (
            "os.environ/GOOGLE_APPLICATION_CREDENTIALS"
        )
        write_private(root / "user" / "models.json", vertex_env_payload)
        invoke(root)
        oci_payload = model_payload()
        oci_payload["models"][0]["litellm_params"]["oci_key"] = "-----BEGIN PRIVATE KEY-----"
        write_private(root / "user" / "models.json", oci_payload)
        invoke(root, expect_ok=False)
        oci_env_payload = model_payload()
        oci_env_payload["models"][0]["litellm_params"]["oci_key"] = "os.environ/OCI_KEY"
        write_private(root / "user" / "models.json", oci_env_payload)
        invoke(root)
        chatgpt_user_payload = model_payload(api_key="none")
        chatgpt_user_payload["models"][0]["litellm_params"]["model"] = "chatgpt/gpt-5.6-sol"
        write_private(root / "user" / "models.json", chatgpt_user_payload)
        invoke(root, expect_ok=False)
        xai_oauth_user_payload = model_payload(api_key="os.environ/XAI_FALLBACK_API_KEY")
        xai_oauth_user_payload["models"][0]["litellm_params"]["model"] = "xai/grok-4.5"
        xai_oauth_user_payload["models"][0]["litellm_params"]["use_xai_oauth"] = True
        write_private(root / "user" / "models.json", xai_oauth_user_payload)
        invoke(root, expect_ok=False)
        xai_truthy_string_payload = model_payload(api_key="os.environ/XAI_FALLBACK_API_KEY")
        xai_truthy_string_payload["models"][0]["litellm_params"]["model"] = "xai/grok-4.5"
        xai_truthy_string_payload["models"][0]["litellm_params"]["use_xai_oauth"] = "true"
        write_private(root / "user" / "models.json", xai_truthy_string_payload)
        invoke(root, expect_ok=False)
        control_env_payload = model_payload(api_key="os.environ/PYTHONPATH")
        write_private(root / "user" / "models.json", control_env_payload)
        invoke(root, expect_ok=False)
        for compatible_env in (
            "WATSONX_APIKEY",
            "WATSONX_ZENAPIKEY",
            "AWS_BEARER_TOKEN_BEDROCK",
            "AICORE_SERVICE_KEY",
            "DD_APP_KEY",
        ):
            write_private(root / "user" / "models.json", model_payload(api_key=f"os.environ/{compatible_env}"))
            invoke(root)
        private_info_payload = model_payload()
        private_info_payload["models"][0]["model_info"]["private_token"] = "literal-secret"
        write_private(root / "user" / "models.json", private_info_payload)
        invoke(root, expect_ok=False)
        metadata_token_payload = model_payload()
        metadata_token_payload["models"][0]["model_info"]["azure_ad_token"] = "literal-secret"
        write_private(root / "user" / "models.json", metadata_token_payload)
        invoke(root, expect_ok=False)
        refresh_tokens_payload = model_payload()
        refresh_tokens_payload["models"][0]["model_info"]["refresh_tokens"] = ["literal-secret"]
        write_private(root / "user" / "models.json", refresh_tokens_payload)
        invoke(root, expect_ok=False)
        public_cost_payload = model_payload()
        public_cost_payload["models"][0]["model_info"]["input_cost_per_token"] = 0.000001
        public_cost_payload["models"][0]["model_info"]["input_cost_per_audio_token"] = 0.000002
        public_cost_payload["models"][0]["model_info"]["output_cost_per_reasoning_token"] = 0.000003
        public_cost_payload["models"][0]["model_info"]["citation_cost_per_token"] = 0.000004
        public_cost_payload["models"][0]["model_info"]["supports_function_calling"] = True
        write_private(root / "user" / "models.json", public_cost_payload)
        invoke(root)
        for normalized_effort in ("xhigh", "max"):
            normalized_effort_payload = model_payload()
            normalized_effort_payload["models"][0]["model_info"].update(
                {
                    "supports_reasoning": True,
                    "x_reasoning_efforts": [normalized_effort],
                }
            )
            write_private(root / "user" / "models.json", normalized_effort_payload)
            invoke(root, expect_ok=False)
        route_cost_payload = model_payload()
        route_cost_payload["models"][0]["litellm_params"]["input_cost_per_token"] = 0.000001
        route_cost_payload["models"][0]["litellm_params"]["input_cost_per_audio_token"] = 0.000002
        route_cost_payload["models"][0]["litellm_params"]["output_cost_per_reasoning_token"] = 0.000003
        route_cost_payload["models"][0]["litellm_params"]["citation_cost_per_token"] = 0.000004
        write_private(root / "user" / "models.json", route_cost_payload)
        invoke(root)
        write_private(
            root / "user" / "models.json",
            model_payload(name="Kimi-K2.7-Code-openrouter"),
        )
        invoke(root, expect_ok=False)
        for reserved_surface in ("use", "permissions", "opus"):
            write_private(
                root / "user" / "models.json",
                model_payload(name=reserved_surface),
            )
            invoke(root, expect_ok=False)
        write_private(root / "user" / "models.json", model_payload())
        os.chmod(root / "user" / "models.json", 0o644)
        invoke(root, expect_ok=False)
        (root / "user" / "models.json").unlink()
        (root / "user" / "models.json").symlink_to(root / "missing-user-models.json")
        invoke(root, expect_ok=False)

    print("ok: durable user config overlay")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
