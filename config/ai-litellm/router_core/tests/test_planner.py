import unittest

from router_core.planner import plan_routes


def _snapshot():
    return {
        "errors": [],
        "raw": {"keyStatus": {"openrouter": {"source": "keychain"}}},
        "normalized": {
            "healthyLocalRuntime": True,
            "availableLocalRuntimeModels": ["local-omlx-gemma4-12b"],
            "harnesses": [
                {"name": "claude", "adapter": "claude-code", "valid": True, "cliInstalled": True},
                {"name": "codex", "adapter": "codex-cli", "valid": True, "cliInstalled": True},
                {"name": "opencode", "adapter": "opencode-cli", "valid": True, "cliInstalled": False},
            ],
            "models": [
                {"name": "DeepSeek-V4-Pro-openrouter", "backend": "openrouter/deepseek/deepseek-v4-pro",
                 "provider": "openrouter", "local": False, "billable": True,
                 "context": 1048576, "output": 384000, "effectiveInput": 1000000},
                {"name": "GLM-5.2-openrouter", "backend": "openrouter/z-ai/glm-5.2",
                 "provider": "openrouter", "local": False, "billable": True,
                 "context": 1048576, "output": 131072, "effectiveInput": 900000},
                {"name": "Gemma4-12B-omlx", "backend": "openai/local-omlx-gemma4-12b",
                 "provider": "local", "local": True, "billable": False,
                 "context": 8192, "output": 3277, "effectiveInput": 3277},
                {"name": "Qwen3.6-27B-omlx", "backend": "openai/Qwen3.6-27B-4bit",
                 "provider": "local", "local": True, "billable": False,
                 "context": 131072, "output": 16384, "effectiveInput": 114688},
                {"name": "gpt-5.5", "backend": "openrouter/z-ai/glm-5.2",
                 "provider": "openrouter", "local": False, "billable": True,
                 "context": 1048576, "output": 131072, "effectiveInput": 900000},
                {"name": "gpt-5.3-codex", "backend": "openai/local-omlx-gemma4-12b",
                 "provider": "local", "local": True, "billable": False,
                 "context": 8192, "output": 3277, "effectiveInput": 3277},
            ],
            "claudeAliases": [
                {"tier": "opus", "model": "DeepSeek-V4-Pro-openrouter", "label": "DeepSeek"},
                {"tier": "fable", "model": "GLM-5.2-openrouter", "label": "GLM"},
                {"tier": "haiku", "model": "Gemma4-12B-omlx", "label": "Gemma"},
            ],
            "codexFacades": [
                {"facade": "gpt-5.5", "model": "openrouter/z-ai/glm-5.2", "info": "*glm52"},
                {"facade": "gpt-5.3-codex", "model": "openai/local-omlx-gemma4-12b", "info": "*gemma"},
            ],
        },
    }


class PlannerTests(unittest.TestCase):
    def test_plan_defaults_to_claude_opus(self):
        plan = plan_routes(_snapshot(), {"estimatedInputTokens": 1000})
        self.assertEqual(plan["selected"]["harness"], "claude")
        self.assertEqual(plan["selected"]["model"], "opus")
        self.assertTrue(plan["selected"]["billable"])

    def test_local_only_selects_non_billable_candidate(self):
        plan = plan_routes(_snapshot(), {"estimatedInputTokens": 1000, "localOnly": True})
        self.assertFalse(plan["selected"]["billable"])
        self.assertIn(plan["selected"]["harness"], ("claude", "codex"))

    def test_disallow_billable_selects_non_billable_candidate(self):
        plan = plan_routes(_snapshot(), {"estimatedInputTokens": 1000, "allowBillable": False})
        self.assertFalse(plan["selected"]["billable"])

    def test_unadvertised_local_runtime_model_is_rejected(self):
        snapshot = _snapshot()
        snapshot["normalized"]["availableLocalRuntimeModels"] = []
        plan = plan_routes(snapshot, {"estimatedInputTokens": 1000, "allowBillable": False}, include_rejected=True)
        self.assertIsNone(plan["selected"])
        self.assertGreater(plan["rejectedCount"], 0)
        self.assertTrue(any(
            "local runtime does not advertise model" in reason
            for row in plan["rejected"]
            for reason in row["rejected"]
        ))

    def test_claude_can_fall_back_to_advertised_registered_local_model(self):
        snapshot = _snapshot()
        snapshot["normalized"]["availableLocalRuntimeModels"] = ["Qwen3.6-27B-4bit"]
        plan = plan_routes(snapshot, {"estimatedInputTokens": 1000, "allowBillable": False}, include_rejected=True)
        self.assertEqual(plan["selected"]["harness"], "claude")
        self.assertEqual(plan["selected"]["model"], "Qwen3.6-27B-omlx")

    def test_allow_billable_and_preferred_model_selects_cloud_route(self):
        plan = plan_routes(
            _snapshot(),
            {"estimatedInputTokens": 100000, "allowBillable": True, "preferredModel": "gpt-5.5"},
        )
        self.assertEqual(plan["selected"]["harness"], "codex")
        self.assertEqual(plan["selected"]["model"], "gpt-5.5")
        self.assertTrue(plan["selected"]["billable"])

    def test_missing_cli_rejects_harness_when_requested(self):
        plan = plan_routes(_snapshot(), {"preferredHarness": "opencode"}, include_rejected=True)
        self.assertIsNone(plan["selected"])
        self.assertTrue(any("harness CLI is not installed" in r["rejected"] for r in plan["rejected"]))


if __name__ == "__main__":
    unittest.main()
