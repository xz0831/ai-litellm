import unittest

from router_core.contract import CONTRACT_VERSION, schema_bundle, validate_contract
from router_core.planner import plan_routes

from test_planner import _snapshot


class ContractTests(unittest.TestCase):
    def test_schema_bundle_is_contract_payload(self):
        payload = schema_bundle()
        self.assertEqual(payload["contractVersion"], CONTRACT_VERSION)
        self.assertIn("plan", payload["schemas"])
        self.assertEqual(validate_contract(payload), [])

    def test_plan_contract_includes_diagnostic_codes(self):
        plan = plan_routes(_snapshot(), {"estimatedInputTokens": 1000}, include_rejected=True)
        self.assertEqual(validate_contract(plan), [])
        self.assertEqual(plan["contractVersion"], CONTRACT_VERSION)
        self.assertTrue(plan["selected"]["selectionReasons"])
        self.assertTrue(all("code" in item and "message" in item for item in plan["selected"]["selectionReasons"]))
        self.assertTrue(all(isinstance(item, str) for item in plan["selected"]["reasons"]))

    def test_rejected_contract_includes_machine_readable_rejections(self):
        snapshot = _snapshot()
        snapshot["normalized"]["availableLocalRuntimeModels"] = []
        plan = plan_routes(snapshot, {"allowBillable": False}, include_rejected=True)
        self.assertEqual(validate_contract(plan), [])
        rejected_codes = {
            diag["code"]
            for row in plan["rejected"]
            for diag in row["rejections"]
        }
        self.assertIn("runtime.model_unavailable", rejected_codes)
        self.assertIn("billing.disallowed", rejected_codes)

    def test_minimal_snapshot_contract(self):
        payload = {
            "schemaVersion": 1,
            "contractVersion": CONTRACT_VERSION,
            "kind": "ai-litellm.router.snapshot",
            "generatedAt": "2026-06-28T00:00:00Z",
            "source": {"binary": "ai-litellm"},
            "raw": {},
            "normalized": {},
            "errors": [],
        }
        self.assertEqual(validate_contract(payload), [])


if __name__ == "__main__":
    unittest.main()
