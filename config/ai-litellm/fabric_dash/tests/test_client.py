import json
from fabric_dash.client import FabricClient

def fake(out_by_cmd):
    def run(argv):
        key = " ".join(argv)
        if key in out_by_cmd:
            return (0, out_by_cmd[key])
        return (1, "")
    return run

def test_proxy_status_parses():
    c = FabricClient(runner=fake({
        "ai-litellm proxy status --json": json.dumps({"health": "ok", "configCurrency": "stale"})
    }))
    s = c.proxy_status()
    assert s["health"] == "ok"
    assert s["configCurrency"] == "stale"

def test_list_method_empty_on_failure():
    c = FabricClient(runner=fake({}))  # every cmd returns rc=1
    assert c.model_list() == []

def test_object_method_empty_on_invalid_json():
    c = FabricClient(runner=fake({"ai-litellm proxy status --json": "not json"}))
    assert c.proxy_status() == {}

def test_reasoning_allowed_reads():
    from fabric_dash.client import FabricClient
    seen = []
    def run(argv):
        seen.append(argv)
        if argv[:4] == ["ai-litellm", "model", "reasoning", "allowed"]:
            return (0, '["low","high","xhigh"]')
        if argv[:4] == ["ai-litellm", "harness", "reasoning", "allowed"]:
            return (0, '["auto","high","max"]')
        return (1, "")
    c = FabricClient(runner=run)
    assert c.model_reasoning_allowed("GLM-5.2") == ["low", "high", "xhigh"]
    assert c.harness_reasoning_allowed("claude") == ["auto", "high", "max"]
    assert ["ai-litellm", "model", "reasoning", "allowed", "GLM-5.2", "--json"] in seen
    # failure → empty list, never raises
    assert FabricClient(runner=lambda a: (1, "")).model_reasoning_allowed("x") == []
