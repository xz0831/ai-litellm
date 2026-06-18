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
