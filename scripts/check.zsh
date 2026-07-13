#!/usr/bin/env zsh

set -euo pipefail

# check.zsh never reads stdin. Pin it to /dev/null so any command that would
# otherwise fall back to reading stdin (e.g. a jq whose `< file` input binding is
# lost in a nested `zsh -fc` quoting context) gets immediate EOF instead of
# blocking forever when check runs non-interactively (background/CI/no TTY).
exec </dev/null

repo_root="${0:A:h:h}"
real_home="$HOME"

for file in \
  "$repo_root/scripts/install.zsh" \
  "$repo_root/scripts/uninstall.zsh" \
  "$repo_root/config/ai-litellm/lib.zsh" \
  "$repo_root/config/claude-litellm/shell.zsh" \
  "$repo_root"/bin/*(N); do
  zsh -n "$file"
done

python3 -m py_compile "$repo_root/scripts/verify_litellm_token_clamp.py"
python3 -m py_compile "$repo_root/scripts/verify_tool_call_fidelity.py"
python3 -m py_compile "$repo_root/scripts/verify_oauth_adapters.py"
python3 -m py_compile "$repo_root/config/ai_litellm_callbacks/oauth_guard.py"
python3 -m py_compile "$repo_root/config/ai_litellm_callbacks/proxy_bootstrap.py"
python3 -m py_compile "$repo_root/config/ai_litellm_callbacks/output_clamp.py"
python3 -m py_compile "$repo_root/scripts/verify_budget_consistency.py"

# Differential test: the four token-budget implementations (Node + 2 Ruby copies
# in lib.zsh, Python in output_clamp.py) must agree on every comparable quantity
# across the full input matrix. This is the real drift guard for the budget math;
# the legacy 1008384/237568/3277 single-point pins below remain as cheap smoke.
# Runs from the checkout so it slices the *live* lib.zsh (self-syncing, no copy).
# Non-interactive (no stdin/env prompts); exits nonzero on any cross-impl drift.
python3 "$repo_root/scripts/verify_budget_consistency.py"

for file in \
  "$repo_root/config/ai-litellm/settings.json" \
  "$repo_root/config/ai-litellm/context-observations.json" \
  "$repo_root/config/ai-litellm/harnesses"/*.json(N) \
  "$repo_root/config/claude-litellm/settings.json"; do
  jq empty "$file"
done

ruby -ryaml -e '(YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))' "$repo_root/config/litellm_config.yaml"

if rg --glob '!scripts/check.zsh' -n 'sk-or-v1-|sk-proj-|sk-ant-|OPENROUTER_API_KEY=.*sk-|LITELLM_MASTER_KEY=.*sk-|BRAVE_SEARCH_API_KEY\s*=|master_key:\s*sk-|api_key:\s*sk-' "$repo_root"; then
  echo "Secret-like value found in repository" >&2
  exit 1
fi

tmp_home="$(mktemp -d)"
spaced_home="$(mktemp -d)"
migration_tmp="$(mktemp -d)"
tmp_home="${tmp_home:A}"
spaced_home="${spaced_home:A}"
migration_tmp="${migration_tmp:A}"
durability_prefix=""
durability_pid=""
cleanup_owned_test_proxy() {
  local owned_prefix="$1" pid="$2" command_line="" attempt
  [[ -n "$owned_prefix" && "$pid" == <-> ]] || return 0
  command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
  [[ "$command_line" == *"$owned_prefix/config/litellm_config.yaml"* && \
        ( "$command_line" == *"$owned_prefix/runtime/venv/"* || \
          "$command_line" == *"$owned_prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"* ) ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  for attempt in {1..30}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done
  command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
  if [[ "$command_line" == *"$owned_prefix/config/litellm_config.yaml"* && \
        ( "$command_line" == *"$owned_prefix/runtime/venv/"* || \
          "$command_line" == *"$owned_prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"* ) ]]; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
}
cleanup_check() {
  local owned_prefix="$tmp_home/.local/share/claude-litellm"
  local pid_file="$owned_prefix/state/ai-litellm/litellm.pid"
  local pid=""
  if [[ -f "$pid_file" && ! -L "$pid_file" ]]; then
    pid="$(<"$pid_file")"
  fi
  cleanup_owned_test_proxy "$owned_prefix" "$pid"
  cleanup_owned_test_proxy "$durability_prefix" "$durability_pid"
  rm -rf "$tmp_home" "$spaced_home" "$migration_tmp"
}
trap cleanup_check EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Migration success: only durable Claude state and the package env are
# published, while a byte-identical whole-package backup retains excluded
# Codex/auth material before the recognized legacy root is removed.
migration_plan_tmp="$migration_tmp/plans"
mkdir -p "$migration_plan_tmp"
migration_case="$migration_tmp/success"
legacy_source="$migration_case/ai-litellm"
migration_destination="$migration_case/claude-litellm"
migration_backups="$migration_case/backups"
legacy_snapshot="$migration_case/source-snapshot"
mkdir -p \
  "$legacy_source/config/ai-litellm" \
  "$legacy_source/state/claude-litellm/claude-config/projects/demo" \
  "$legacy_source/state/ai-litellm" \
  "$legacy_source/state/codex-litellm" \
  "$legacy_source/state/auth/chatgpt"
print -r -- "legacy marker" > "$legacy_source/config/ai-litellm/lib.zsh"
print -r -- "session bytes" > "$legacy_source/state/claude-litellm/claude-config/projects/demo/session.jsonl"
print -r -- "history bytes" > "$legacy_source/state/claude-litellm/claude-config/history.jsonl"
print -r -- '{"account":"legacy"}' > "$legacy_source/state/claude-litellm/claude-config/.claude.json"
print -r -- "PROVIDER_SENTINEL=legacy" > "$legacy_source/state/ai-litellm/env"
print -r -- "excluded codex bytes" > "$legacy_source/state/codex-litellm/security.json"
print -r -- "excluded auth bytes" > "$legacy_source/state/auth/chatgpt/auth.json"
cp -R "$legacy_source" "$legacy_snapshot"
TMPDIR="$migration_plan_tmp" CLAUDE_LITELLM_BACKUP_ROOT="$migration_backups" \
  "$repo_root/scripts/migrate-legacy.zsh" \
  --destination "$migration_destination" --source "$legacy_source" --remove-source >/dev/null
test -z "$(find "$migration_plan_tmp" -mindepth 1 -print -quit)"
test ! -e "$legacy_source"
cmp -s "$legacy_snapshot/state/claude-litellm/claude-config/projects/demo/session.jsonl" \
  "$migration_destination/state/claude-litellm/claude-config/projects/demo/session.jsonl"
cmp -s "$legacy_snapshot/state/claude-litellm/claude-config/history.jsonl" \
  "$migration_destination/state/claude-litellm/claude-config/history.jsonl"
cmp -s "$legacy_snapshot/state/claude-litellm/claude-config/.claude.json" \
  "$migration_destination/state/claude-litellm/claude-config/.claude.json"
cmp -s "$legacy_snapshot/state/ai-litellm/env" \
  "$migration_destination/state/ai-litellm/env"
test ! -e "$migration_destination/state/codex-litellm"
test ! -e "$migration_destination/state/auth"
legacy_backup=("$migration_backups"/*/ai-litellm(N))
test "${#legacy_backup[@]}" = "1"
diff -qr "$legacy_snapshot" "$legacy_backup[1]" >/dev/null

# Destination conflict: the no-clobber preflight must fail before changing
# either tree or creating a backup.
migration_case="$migration_tmp/destination-conflict"
legacy_source="$migration_case/ai-litellm"
migration_destination="$migration_case/claude-litellm"
mkdir -p "$legacy_source/config/ai-litellm" \
  "$legacy_source/state/claude-litellm/claude-config" \
  "$migration_destination/state/claude-litellm/claude-config"
print -r -- "legacy marker" > "$legacy_source/config/ai-litellm/lib.zsh"
print -r -- "source history" > "$legacy_source/state/claude-litellm/claude-config/history.jsonl"
print -r -- "destination history" > "$migration_destination/state/claude-litellm/claude-config/history.jsonl"
cp -R "$legacy_source" "$migration_case/source-before"
cp -R "$migration_destination" "$migration_case/destination-before"
if TMPDIR="$migration_plan_tmp" CLAUDE_LITELLM_BACKUP_ROOT="$migration_case/backups" \
  "$repo_root/scripts/migrate-legacy.zsh" \
  --destination "$migration_destination" --source "$legacy_source" --remove-source >/dev/null 2>&1; then
  echo "Migration unexpectedly overwrote differing destination data" >&2
  exit 1
fi
test -z "$(find "$migration_plan_tmp" -mindepth 1 -print -quit)"
diff -qr "$migration_case/source-before" "$legacy_source" >/dev/null
diff -qr "$migration_case/destination-before" "$migration_destination" >/dev/null
test ! -e "$migration_case/backups"

# Source conflict: two recognized legacy roots selecting different bytes for
# the same destination path must leave both sources and the destination intact.
migration_case="$migration_tmp/source-conflict"
legacy_source_a="$migration_case/ai-litellm"
legacy_source_b="$migration_case/ai-litellm-fabric"
migration_destination="$migration_case/claude-litellm"
for legacy_source in "$legacy_source_a" "$legacy_source_b"; do
  mkdir -p "$legacy_source/config/ai-litellm" \
    "$legacy_source/state/claude-litellm/claude-config"
  print -r -- "legacy marker" > "$legacy_source/config/ai-litellm/lib.zsh"
done
print -r -- "source A history" > "$legacy_source_a/state/claude-litellm/claude-config/history.jsonl"
print -r -- "source B history" > "$legacy_source_b/state/claude-litellm/claude-config/history.jsonl"
cp -R "$legacy_source_a" "$migration_case/source-a-before"
cp -R "$legacy_source_b" "$migration_case/source-b-before"
if TMPDIR="$migration_plan_tmp" CLAUDE_LITELLM_BACKUP_ROOT="$migration_case/backups" \
  "$repo_root/scripts/migrate-legacy.zsh" \
  --destination "$migration_destination" \
  --source "$legacy_source_a" --source "$legacy_source_b" --remove-source >/dev/null 2>&1; then
  echo "Migration unexpectedly merged conflicting legacy sources" >&2
  exit 1
fi
test -z "$(find "$migration_plan_tmp" -mindepth 1 -print -quit)"
diff -qr "$migration_case/source-a-before" "$legacy_source_a" >/dev/null
diff -qr "$migration_case/source-b-before" "$legacy_source_b" >/dev/null
test ! -e "$migration_destination"
test ! -e "$migration_case/backups"
echo "ok: legacy migration is byte-verified and conflict-atomic"

LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-$$" HOME="$tmp_home" "$repo_root/scripts/install.zsh" >/dev/null
test_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
installed_settings="$tmp_home/.local/share/claude-litellm/config/ai-litellm/settings.json"
jq --argjson port "$test_port" '.server.port = $port' "$installed_settings" > "$installed_settings.tmp"
mv "$installed_settings.tmp" "$installed_settings"
REAL_HOME="$real_home" AI_LITELLM_TEST_PORT="$test_port" HOME="$tmp_home" OPENROUTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-openrouter-key-$$" zsh -fc '
set -e
prefix="$HOME/.local/share/claude-litellm"
test -f "$prefix/config/ai-litellm/lib.zsh"
test -f "$prefix/config/ai-litellm/context-observations.json"
test -f "$prefix/config/litellm_config.yaml"
test -f "$prefix/config/ai_litellm_callbacks/output_clamp.py"
test -f "$prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"
test -x "$prefix/scripts/uninstall.zsh"
test -x "$prefix/bin/claude-litellm"
test -x "$HOME/.local/bin/claude-litellm"
test ! -e "$HOME/.local/bin/ai-litellm"
test ! -e "$HOME/.local/bin/codex-litellm"
"$HOME/.local/bin/claude-litellm" --help >/dev/null
"$HOME/.local/bin/claude-litellm" status > "$HOME/status-text.out" 2>/dev/null
grep -q "Claude settings:" "$HOME/status-text.out"
grep -q "chatgpt: not authenticated" "$HOME/status-text.out"
grep -q "grok: not authenticated" "$HOME/status-text.out"
echo "ok: public status summary"
# ── P4 slimming: retired user-surface commands must loud-fail, not dispatch ──
# Every flat alias, the route/audit groups, and the top-level capabilities
# command are retired outright (see the H4/H5/H6 blocks below for the
# behavioral/usage-text rekeying of what still partially worked pre-P4).
# Leading non-option retired nouns fail model selection before launch. Known
# retired option-shaped controls must also be rejected before proxy startup.
if "$HOME/.local/bin/claude-litellm" start >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" stop >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" restart >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" logs >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" list >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" route-info >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" probe-route >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" runtime-status >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" harnesses >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" harness-info >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" launch >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" key-status >/dev/null 2>&1; then echo "FAIL: retired flat alias still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" capabilities >/dev/null 2>&1; then echo "FAIL: retired capabilities still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" route list >/dev/null 2>&1; then echo "FAIL: retired route group still dispatches"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" audit model-policy >/dev/null 2>&1; then echo "FAIL: retired audit group still dispatches"; exit 1; fi
for retired_flag in --start --stop --restart --logs --doctor; do
  if retired_out="$("$HOME/.local/bin/claude-litellm" "$retired_flag" 2>&1)"; then
    echo "FAIL: retired control flag still succeeds: $retired_flag" >&2
    exit 1
  fi
  [[ "$retired_out" == *"legacy control flag"*"is retired"* ]] || {
    echo "FAIL: retired control flag lacks a pre-launch rejection: $retired_flag" >&2
    exit 1
  }
done
echo "ok: retired surfaces loud-fail (P4 slimming)"
test ! -s "$prefix/state/ai-litellm/litellm.pid"
! grep -R "__HOME__\\|__AI_LITELLM_HOME__" "$prefix/config" "$prefix/docs" >/dev/null
grep -q "CLAUDE_LITELLM_ROOT=" "$HOME/.local/bin/claude-litellm"
grep -q "exec.*bin/claude-litellm" "$HOME/.local/bin/claude-litellm"
export AI_LITELLM_HOME="$prefix"
source "$prefix/config/ai-litellm/lib.zsh"
grep -q "^LITELLM_MASTER_KEY=" "$prefix/state/ai-litellm/env"
test "$(stat -f %Lp "$prefix/state/ai-litellm/env")" = "600"
test -n "$(ai_litellm_master_key)"
test "$(ai_litellm_model_resolve openrouter/moonshotai/kimi-k2.7-code)" = "Kimi-K2.7-Code-openrouter"
test "$(ai_litellm_model_resolve xiaomi/mimo-v2.5)" = "Mimo-V2.5-openrouter"
test "$(ai_litellm_model_backend openrouter/moonshotai/kimi-k2.7-code)" = "openrouter/moonshotai/kimi-k2.7-code"
ai_litellm_model_limits openrouter/xiaomi/mimo-v2.5 >/dev/null
test "$(ai_litellm_model_reasoning_allowed_efforts openrouter/z-ai/glm-5.2)" = "xhigh high"
test "$(ai_litellm_model_reasoning_allowed_efforts Grok-4.5-xai-oauth)" = "low medium high"
if ai_litellm_model_reasoning_allowed_efforts GPT-5.4-chatgpt-oauth >/dev/null 2>&1; then
  echo "FAIL: unverified ChatGPT OAuth effort was exposed as configurable" >&2
  exit 1
fi
if ai_litellm_model_reasoning_allowed_efforts Kimi-K2.7-Code-openrouter >/dev/null 2>&1; then
  echo "FAIL: Kimi reasoning support was misclassified as configurable effort" >&2
  exit 1
fi
if ai_litellm_model_reasoning_allowed_efforts Mimo-V2.5-openrouter >/dev/null 2>&1; then
  echo "FAIL: MiMo reasoning support was misclassified as configurable effort" >&2
  exit 1
fi
if ai_litellm_model_reasoning_allowed_efforts Qwen3.6-27B-omlx >/dev/null 2>&1; then
  echo "FAIL: non-reasoning local model accepted configurable effort" >&2
  exit 1
fi
# Un-rendered placeholder guard (run-from-checkout footgun): a literal
# __AI_LITELLM_HOME__ path must be refused; the rendered prefix path must pass.
# Non-vacuous: if the guard is missing, the positive assertion below fails.
if ai_litellm_assert_rendered_path "__AI_LITELLM_HOME__/state/claude-litellm" "test" 2>/dev/null; then
  echo "ai_litellm_assert_rendered_path accepted an un-rendered path" >&2
  exit 1
fi
ai_litellm_assert_rendered_path "$prefix/state/claude-litellm" "test"
runtime_routes_dry="$(ai_litellm_runtime_routes_write omlx 1 MarkItDown Qwen3.6-27B-4bit)"
[[ "$runtime_routes_dry" == *"MarkItDown-omlx -> openai/MarkItDown"* ]]
# Qwen3.6-27B-omlx registry entry serves openai/Qwen3.6-27B-4bit, so the
# discovered route for it must be deduped (absent from the dry output).
[[ "$runtime_routes_dry" != *"Qwen3.6-27B-4bit-omlx"* ]]
# Robustness: a runtime that is reachable but whose /v1/models returns an
# UNPARSEABLE body must NOT silently wipe existing discovered routes — discovery
# failure (rc!=0) is distinct from a genuine empty model list and must skip the
# rewrite, keeping the routes. (Regression for the 2026-06-15 silent-wipe fix.)
rob_port="$(python3 -c "import socket;s=socket.socket();s.bind((\"127.0.0.1\",0));print(s.getsockname()[1]);s.close()")"
python3 -c "
import sys,http.server,socketserver
# http.server.HTTPServer.server_bind() calls socket.getfqdn(host) for server_name;
# on CI runners with slow/absent reverse DNS for 127.0.0.1 that blocks ~30s before
# the socket starts listening, so this mock never becomes reachable and the
# discovery-robustness assertion below fails silently. Bind without the reverse
# lookup — server_name is unused by this throwaway mock.
class Srv(http.server.HTTPServer):
  def server_bind(self):
    socketserver.TCPServer.server_bind(self)
    self.server_name=\"127.0.0.1\"; self.server_port=self.server_address[1]
class H(http.server.BaseHTTPRequestHandler):
  def log_message(self,*a): pass
  def do_GET(self):
    self.send_response(200); self.end_headers(); self.wfile.write(b\"GARBAGE NOT JSON\")
Srv((\"127.0.0.1\",$rob_port),H).serve_forever()
" >/dev/null 2>&1 &
rob_mock_pid=$!
for i in $(seq 1 20); do curl -sf --max-time 1 "http://127.0.0.1:$rob_port/v1/models" >/dev/null 2>&1 && break; sleep 0.2; done
rob_settings="$HOME/rob-settings.json"
print -r -- "{\"runtimes\":{\"mock\":{\"kind\":\"openai-compatible\",\"baseUrl\":\"http://127.0.0.1:$rob_port\",\"apiBase\":\"http://127.0.0.1:$rob_port/v1\",\"discoverModels\":true,\"defaultModelInfo\":{\"max_input_tokens\":8192,\"max_output_tokens\":4096}}}}" > "$rob_settings"
rob_cfg="$HOME/rob-cfg.yaml"
print -r -- "model_list:
# BEGIN claude-litellm discovered local routes
  - model_name: Keep-mock
    litellm_params:
      model: openai/Keep
      api_base: http://127.0.0.1:9/v1
      api_key: none
    model_info:
      max_input_tokens: 8192
# END claude-litellm discovered local routes

general_settings:
  master_key: x" > "$rob_cfg"
rob_out="$(AI_LITELLM_SETTINGS="$rob_settings" AI_LITELLM_CONFIG="$rob_cfg" ai_litellm_runtime_routes_refresh 0 2>&1 || true)"
[[ "$rob_out" == *"discovery failed"* ]]
test "$(grep -c "model_name: Keep-mock" "$rob_cfg")" = "1"   # route PRESERVED, not wiped
kill "$rob_mock_pid" 2>/dev/null || true
# Robustness: a second concurrent sync must REFUSE loud (dedicated sync lock,
# deadlock-free vs the proxy-start lock) and do NO rewrite — held-lock returns
# immediately before any file is touched. (Reclaim-of-dead-holder + release are
# verified separately; not exercised here to keep the suite from running a full
# regenerating sync.)
mkdir -p "$AI_LITELLM_PROXY_HOME"; mkdir "$AI_LITELLM_PROXY_HOME/litellm.sync.lock"
print -r -- "$$" > "$AI_LITELLM_PROXY_HOME/litellm.sync.lock/pid"   # $$ is the live test shell -> kill -0 passes
date -u "+%Y-%m-%dT%H:%M:%SZ" > "$AI_LITELLM_PROXY_HOME/litellm.sync.lock/started_at"  # fresh -> age << max, no reclaim
sync_busy="$(ai_litellm_sync --no-restart 2>&1 || true)"
[[ "$sync_busy" == *"another sync is in progress"* ]]
rm -f "$AI_LITELLM_PROXY_HOME/litellm.sync.lock/pid" "$AI_LITELLM_PROXY_HOME/litellm.sync.lock/started_at"; rmdir "$AI_LITELLM_PROXY_HOME/litellm.sync.lock"
ai_litellm_runtime_routes_write omlx 0 "Qwen3.6-Test-27B" "PlainLocal" >/dev/null
grep -A8 "model_name: Qwen3.6-Test-27B-omlx" "$AI_LITELLM_CONFIG" | grep -q "max_input_tokens: 131072"
grep -A8 "model_name: Qwen3.6-Test-27B-omlx" "$AI_LITELLM_CONFIG" | grep -q "max_output_tokens: 16384"
grep -A8 "model_name: PlainLocal-omlx" "$AI_LITELLM_CONFIG" | grep -q "max_input_tokens: 8192"
# ── --json contract: proxy status ────────────────────────────────────────────
json_check() {
  local label="$1"; shift
  local out
  out="$("$@" 2>/dev/null)" || { echo "FAIL($label): nonzero exit"; exit 1; }
  print -r -- "$out" | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{try{JSON.parse(s)}catch(e){console.error(\"invalid JSON\");process.exit(1)}})" \
    || { echo "FAIL($label): invalid JSON"; exit 1; }
}
assert_json_key() {
  local label="$1" json="$2" key="$3"
  print -r -- "$json" | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const o=JSON.parse(s);if(!(process.argv[1] in o)){console.error(\"missing key\");process.exit(1)}})" "$key" \
    || { echo "FAIL($label): missing key $key"; exit 1; }
}
ps_json="$("$HOME/.local/bin/claude-litellm" proxy status --json 2>/dev/null)"
json_check "proxy status --json" "$HOME/.local/bin/claude-litellm" proxy status --json
for k in config settings baseUrl health configCurrency log pid pidFile lock; do
  assert_json_key "proxy status --json" "$ps_json" "$k"
done
# default output unchanged: still human text, no leading brace
ps_text="$("$HOME/.local/bin/claude-litellm" proxy status 2>/dev/null)"
[[ "$ps_text" != \{* ]] || { echo "FAIL: default proxy status became JSON"; exit 1; }
echo "ok: proxy status --json"
# ── --json contract: model list + model limits ────────────────────────────────
ml_json="$("$HOME/.local/bin/claude-litellm" model list --json 2>/dev/null)"
json_check "model list --json" "$HOME/.local/bin/claude-litellm" model list --json
print -r -- "$ml_json" | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const a=JSON.parse(s);if(!Array.isArray(a)||a.length===0){console.error(\"not a non-empty array\");process.exit(1)}if(!(\"name\" in a[0])||!(\"backend\" in a[0])){console.error(\"missing name/backend\");process.exit(1)}})" \
  || { echo "FAIL: model list --json shape"; exit 1; }
json_check "model limits --json" "$HOME/.local/bin/claude-litellm" model limits --json
echo "ok: model list/limits --json"
# ── --json contract: harness list + key status ────────────────────────────────
json_check "harness list --json" "$HOME/.local/bin/claude-litellm" harness list --json
hl_json="$("$HOME/.local/bin/claude-litellm" harness list --json 2>/dev/null)"
print -r -- "$hl_json" | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const a=JSON.parse(s);const names=a.map(x=>x.name).sort().join(\",\");if(names!==\"claude\"){console.error(\"unexpected harnesses: \"+names);process.exit(1)}for(const h of a){for(const k of [\"adapter\",\"valid\",\"cliInstalled\"]) if(!(k in h)){console.error(\"missing \"+k);process.exit(1)}}})" \
  || { echo "FAIL: harness list --json shape"; exit 1; }
json_check "key status --json" "$HOME/.local/bin/claude-litellm" key status --json
ks_json="$("$HOME/.local/bin/claude-litellm" key status --json 2>/dev/null)"
assert_json_key "key status --json" "$ks_json" openrouter
assert_json_key "key status --json" "$ks_json" master
echo "ok: harness/key --json"
# ── --json contract: harness info ────────────────────────────────────────────
# B1: harness info --json (no name) must emit {} and exit 0
hi_empty="$("$HOME/.local/bin/claude-litellm" harness info --json 2>/dev/null)"
[[ "$hi_empty" == "{}" ]] || { echo "FAIL: harness info --json (no name) did not emit {}; got: $hi_empty"; exit 1; }
echo "ok: harness info --json no-name = {}"
# B2: Claude-only harness info stays valid without duplicating proxy routing.
hi_claude="$("$HOME/.local/bin/claude-litellm" harness info claude --json 2>/dev/null)"
node -e "const o=JSON.parse(process.argv[1]);\
if(o.name!==\"claude\"||o.adapter!==\"claude-code\"||o.valid!==true){console.error(\"invalid Claude harness info\");process.exit(1)}" "$hi_claude" \
  || { echo "FAIL: harness info claude --json contract"; exit 1; }
echo "ok: harness info claude --json contract"
# M1: isolationEnv key present, isolation key absent
node -e "const o=JSON.parse(process.argv[1]);\
if(!(\"isolationEnv\" in o)){console.error(\"missing isolationEnv\");process.exit(1)}\
if(\"isolation\" in o){console.error(\"stale isolation key still present\");process.exit(1)}" "$hi_claude" \
  || { echo "FAIL: harness info claude --json isolationEnv key wrong"; exit 1; }
echo "ok: harness info claude --json isolationEnv key"
# ── --json contract: runtime status, reasoning matrix, context matrix ──
# (route list --json is retired along with the whole route group -- P4
# slimming; model list --json above already carries the name/backend shape
# that route list used to be the only place to see.)
for cmd in "runtime status" "reasoning matrix" "context matrix"; do
  json_check "$cmd --json" "$HOME/.local/bin/claude-litellm" ${=cmd} --json
done
echo "ok: runtime/reasoning/context --json"
# ── reasoning allowed --json (model + harness) ────────────────────────────────
m_allowed="$("$HOME/.local/bin/claude-litellm" model reasoning allowed GLM-5.2-openrouter --json 2>/dev/null)"
print -r -- "$m_allowed" | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const a=JSON.parse(s);if(!Array.isArray(a)||!a.includes(\"high\")){console.error(\"not an array with high\");process.exit(1)}})" \
  || { echo "FAIL: model reasoning allowed --json"; exit 1; }
h_allowed="$("$HOME/.local/bin/claude-litellm" harness reasoning allowed claude --json 2>/dev/null)"
print -r -- "$h_allowed" | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const a=JSON.parse(s);if(!Array.isArray(a)||a.length===0){console.error(\"not a non-empty array\");process.exit(1)}})" \
  || { echo "FAIL: harness reasoning allowed --json"; exit 1; }
echo "ok: reasoning allowed --json (model+harness)"
# ── harness alias get --json + set round-trip ─────────────────────────────────
a_json="$("$HOME/.local/bin/claude-litellm" harness alias get claude --json 2>/dev/null)"
print -r -- "$a_json" | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const a=JSON.parse(s);if(!Array.isArray(a)||a.length!==4||!(\"tier\" in a[0])||!(\"model\" in a[0])){console.error(\"bad alias get shape\");process.exit(1)}})" \
  || { echo "FAIL: harness alias get --json"; exit 1; }
orig="$("$HOME/.local/bin/claude-litellm" harness alias get claude --json | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const a=JSON.parse(s);const e=a.find(x=>x.tier===\"fable\");process.stdout.write(e?e.model:\"\")})")"
"$HOME/.local/bin/claude-litellm" harness alias set claude fable GLM-5.2-openrouter >/dev/null 2>&1
now="$("$HOME/.local/bin/claude-litellm" harness alias get claude --json | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const a=JSON.parse(s);const e=a.find(x=>x.tier===\"fable\");process.stdout.write(e?e.model:\"\")})")"
"$HOME/.local/bin/claude-litellm" harness alias set claude fable "$orig" >/dev/null 2>&1   # restore
[[ "$now" == "GLM-5.2-openrouter" && "$orig" != "$now" ]] \
  || { echo "FAIL: harness alias set round-trip"; exit 1; }
echo "ok: harness alias get/set (claude tiers)"
# R2 review: the dashboard pipes a newline-less secret to key set via stdin; zsh
# read returns nonzero on EOF-without-newline, which used to abort key set and
# store nothing. Verify the read tolerates it. Use --env-file with an isolated
# temp env so the real Keychain is never touched. (No apostrophes: -fc string.)
ks_env_file="$(mktemp)"
printf "%s" "pipe-no-newline-value-r2" | AI_LITELLM_ENV="$ks_env_file" "$HOME/.local/bin/claude-litellm" key set --env-file CHECKR2 >/dev/null 2>&1 \
  || { echo "FAIL: key set aborted on a newline-less piped secret"; rm -f "$ks_env_file"; exit 1; }
grep -q "pipe-no-newline-value-r2" "$ks_env_file" \
  || { echo "FAIL: key set did not store the newline-less piped secret"; rm -f "$ks_env_file"; exit 1; }
rm -f "$ks_env_file"
echo "ok: key set stores newline-less piped secret (dash stdin path)"
# ── Public help: the single command documents launch, OAuth, and controls ──
usage_out="$("$HOME/.local/bin/claude-litellm" --help 2>&1)"
[[ "$usage_out" == *"fable|opus|sonnet|haiku|model_name"* ]] || { echo "FAIL: public help missing launch models" >&2; exit 1; }
[[ "$usage_out" == *"auth login|status|logout"* ]]            || { echo "FAIL: public help missing OAuth controls" >&2; exit 1; }
[[ "$usage_out" == *"status|doctor|sync|proxy|model|key"* ]]  || { echo "FAIL: public help missing control nouns" >&2; exit 1; }
[[ "$usage_out" == *"All providers and local runtimes"* ]]    || { echo "FAIL: public help missing proxy contract" >&2; exit 1; }
echo "ok: public help surface"

# H6 REVERSAL (P4): route is retired entirely (absorbed into model: see the
# retired-surfaces loud-fail block above), so probe returns to model as the
# canonical spelling -- a conscious reversal of the prior H6 decision (route
# probe was canonical and model probe warned+delegated toward it; now route
# does not exist at all and model probe is canonical, with no deprecation
# warning). See DESIGN_RATIONALE for the decision-log entry.
# IMPORTANT: this whole battery runs inside a zsh -fc SINGLE-QUOTED string, so
# the source here must contain NO apostrophes.
# model probe X is canonical now: NO deprecation warning. X is a bogus model
# name, so ai_litellm_model_resolve fails before any billable network call
# (see ai_litellm_probe_route) -- this stays non-billable, same as pre-P4.
# (Note: ai_litellm_probe_route reassigns model_name from the failed resolve
# before printing the fail message, so the bogus name itself does not appear
# in the output -- "not present in" is the stable, existing substring.)
model_probe_out="$("$HOME/.local/bin/claude-litellm" model probe X 2>&1 || true)"
[[ "$model_probe_out" != *"is deprecated"* ]] || { echo "FAIL: model probe still prints a deprecation warning (H6 reversal: probe is canonical again)" >&2; exit 1; }
[[ "$model_probe_out" == *"not present in"* ]] || { echo "FAIL: model probe did not attempt to resolve the requested model" >&2; exit 1; }
# probe-route (flat alias) and route check are both retired along with the
# flat-alias set and the route group respectively; see the loud-fail block
# above (installed-copy smoke area) and route list there for their coverage --
# once route) dispatch is gone, every route subcommand fails identically.
# Canonical model probe with NO args defaults to all models (absorbed check):
# it must NOT print the empty-args usage error that the bare probe fn emits.
[[ "$("$HOME/.local/bin/claude-litellm" model probe 2>&1 || true)" != *"Usage: claude-litellm probe-route <model_name>"* ]] || { echo "FAIL: model probe with no arg did not default to all models" >&2; exit 1; }
# Model usage now advertises probe [model...] as a first-class verb (H6 reversal).
model_usage="$("$HOME/.local/bin/claude-litellm" model bogus 2>&1 || true)"
[[ "$model_usage" == *"|probe [model"* ]] || { echo "FAIL: model usage does not advertise probe [model...] (H6 reversal)" >&2; exit 1; }
echo "ok: model probe canonical again; route retired (H6 reversal)"

# ── H5: unified top-level `claude-litellm doctor` runs the full battery by default ──
# Doctors print headings and return nonzero when the proxy/runtime is down (it is,
# in the throwaway HOME), so we assert on OUTPUT headings, not exit codes -- hence
# the trailing || true. No apostrophes here (single-quoted zsh -fc block).
full_doctor="$("$HOME/.local/bin/claude-litellm" doctor 2>&1 || true)"
[[ "$full_doctor" == *"claude-litellm doctor"* ]]          || { echo "FAIL: doctor full battery missing global/proxy pass" >&2; exit 1; }
[[ "$full_doctor" == *"claude-litellm context doctor"* ]]  || { echo "FAIL: doctor full battery missing context pass" >&2; exit 1; }
[[ "$full_doctor" == *"claude-litellm reasoning doctor"* ]] || { echo "FAIL: doctor full battery missing reasoning pass" >&2; exit 1; }
[[ "$full_doctor" == *"claude-litellm model policy audit"* ]] || { echo "FAIL: doctor full battery missing model-policy pass" >&2; exit 1; }
# Scoping flags delegate to the matching group doctor (and only that one).
[[ "$("$HOME/.local/bin/claude-litellm" doctor --proxy 2>&1 || true)"     == *"claude-litellm doctor"* ]]              || { echo "FAIL: doctor --proxy" >&2; exit 1; }
[[ "$("$HOME/.local/bin/claude-litellm" doctor --context 2>&1 || true)"   == *"claude-litellm context doctor"* ]]      || { echo "FAIL: doctor --context" >&2; exit 1; }
[[ "$("$HOME/.local/bin/claude-litellm" doctor --reasoning 2>&1 || true)" == *"claude-litellm reasoning doctor"* ]]    || { echo "FAIL: doctor --reasoning" >&2; exit 1; }
[[ "$("$HOME/.local/bin/claude-litellm" doctor --policy 2>&1 || true)"    == *"claude-litellm model policy audit"* ]]  || { echo "FAIL: doctor --policy reaches model-policy audit" >&2; exit 1; }
# --runtime with no name errors with the runtime usage guard (reachable via doctor).
[[ "$("$HOME/.local/bin/claude-litellm" doctor --runtime 2>&1 || true)" == *"runtime <name>"* ]]                  || { echo "FAIL: doctor --runtime usage guard" >&2; exit 1; }
# Unknown scope prints the doctor usage and does NOT run a battery.
doctor_usage="$("$HOME/.local/bin/claude-litellm" doctor --bogus 2>&1 || true)"
[[ "$doctor_usage" == *"doctor [--proxy|--context|--reasoning|--policy|--runtime <name>]"* ]] || { echo "FAIL: doctor unknown scope usage" >&2; exit 1; }
# P4 slimming: the audit group and the per-group doctor VERBS are retired
# from the user surface; doctor --<scope> (asserted above) is the sole entry
# point. The underlying battery functions still exist (exercised via the
# unified doctor above), so we assert on the ABSENCE of their headings here --
# that proves the retired verb no longer reaches them, not just that the
# overall call failed (which could be true pre-P4 too, e.g. proxy down).
audit_out="$("$HOME/.local/bin/claude-litellm" audit model-policy 2>&1 || true)"
[[ "$audit_out" != *"claude-litellm model policy audit"* ]] || { echo "FAIL: audit model-policy still runs the policy battery (retire the group)" >&2; exit 1; }
proxy_doctor_out="$("$HOME/.local/bin/claude-litellm" proxy doctor 2>&1 || true)"
[[ "$proxy_doctor_out" != *"claude-litellm doctor"* ]] || { echo "FAIL: proxy doctor still runs the doctor battery (retire the verb)" >&2; exit 1; }
context_doctor_out="$("$HOME/.local/bin/claude-litellm" context doctor 2>&1 || true)"
[[ "$context_doctor_out" != *"claude-litellm context doctor"* ]] || { echo "FAIL: context doctor still runs the doctor battery (retire the verb)" >&2; exit 1; }
reasoning_doctor_out="$("$HOME/.local/bin/claude-litellm" reasoning doctor 2>&1 || true)"
[[ "$reasoning_doctor_out" != *"claude-litellm reasoning doctor"* ]] || { echo "FAIL: reasoning doctor still runs the doctor battery (retire the verb)" >&2; exit 1; }
# omlx is a real, local runtime (safe/non-billable to reference) so this exercises
# the same code path ai_litellm_doctor_runtime uses once given a name.
runtime_doctor_out="$("$HOME/.local/bin/claude-litellm" runtime doctor omlx 2>&1 || true)"
[[ "$runtime_doctor_out" != *"claude-litellm doctor --runtime omlx"* ]] || { echo "FAIL: runtime doctor <name> still runs the doctor battery (retire the verb)" >&2; exit 1; }
# --doctor (flat top-level alias) is one of the 13 retired flat forms; see the
# loud-fail block above (installed-copy smoke area) for its assertion.
echo "ok: unified doctor (H5); audit/per-group-doctor verbs retired (P4 slimming)"
# litellmParamsOverrides: a glob-matched discovered route gets extra litellm_params
# (e.g. thinking-off via extra_body) injected; non-matching routes do NOT. Tested
# via a temp settings overlay so the shipped empty {} stays behavior-preserving.
params_settings_tmp="$HOME/omlx-params-test.json"
test -n "$AI_LITELLM_SETTINGS" && test -f "$AI_LITELLM_SETTINGS"  # guard: never let jq fall back to stdin (would hang)
# P4-unrelated latent-bug fix: this filter previously used single quotes, which
# (unlike the apostrophe-embedding trick elsewhere in this file) closed and
# reopened the enclosing single-quoted zsh -fc string around SPACE-containing
# content. That handed everything from " = {...}" onward to the outer shell as
# separate, never-executed positional arguments (jq silently "succeeded" on the
# stray /dev/null stdin it fell back to reading instead) -- truncating the
# whole rest of the embedded script, including every check after this point.
# Escaped double quotes (same idiom already used for node -e "..." elsewhere in
# this file) keep the filter, spaces included, as one argument end to end.
jq ".runtimes.omlx.litellmParamsOverrides = {\"*Test-35B*\": {\"extra_body\": {\"chat_template_kwargs\": {\"enable_thinking\": false}}}}" < "$AI_LITELLM_SETTINGS" > "$params_settings_tmp"
AI_LITELLM_SETTINGS="$params_settings_tmp" ai_litellm_runtime_routes_write omlx 0 "Qwen3.6-Test-35B" "Qwen3.6-Test-27B" >/dev/null
grep -A12 "model_name: Qwen3.6-Test-35B-omlx" "$AI_LITELLM_CONFIG" | grep -q "enable_thinking: false"
! grep -A12 "model_name: Qwen3.6-Test-27B-omlx" "$AI_LITELLM_CONFIG" | grep -q "enable_thinking"
ai_litellm_model_info_anchor_refs_ok
for harness in "${(@f)$(ai_litellm_harness_names)}"; do
  ai_litellm_harness_validate "$harness"
done
ai_litellm_model_limits GLM-5.2-openrouter >/dev/null
ai_litellm_context_gateway_clamp_policy_ok
ai_litellm_context_gateway_clamp_configured
# Output-reservation policy must agree across all descriptors + the gateway copy.
ai_litellm_context_output_reservation_aligned
# Non-vacuous: a drifted gateway copy must trip the guard (if-form avoids the zsh
# `set -e` + return-1 early exit that bare !-negation can cause).
reservation_drift_cfg="$HOME/reservation-drift.yaml"
# Same P4-unrelated latent-bug fix as the jq filter above: this sed expression
# has a space either side of each ":", so naive single quotes here truncate
# the rest of the embedded script the same way; double quotes fix it (no
# internal double quotes or $ in this expression, so no escaping needed).
sed "s/tokenizer_headroom: 8192/tokenizer_headroom: 8191/" "$AI_LITELLM_CONFIG" > "$reservation_drift_cfg"
if AI_LITELLM_CONFIG="$reservation_drift_cfg" ai_litellm_context_output_reservation_aligned 2>/dev/null; then
  echo "output reservation alignment guard failed to detect a drifted gateway copy" >&2
  exit 1
fi
ai_litellm_context_gateway_cost_guardrail_policy_ok
ai_litellm_context_gateway_cost_guardrail_configured
ai_litellm_context_observations_ok
ai_litellm_model_info_anchor_refs_ok
openrouter_models_fixture="$HOME/openrouter-models.json"
print -r -- "{\"data\":[{\"id\":\"moonshotai/kimi-k2.7-code\",\"context_length\":262144,\"top_provider\":{\"context_length\":262144,\"max_completion_tokens\":262144},\"supported_parameters\":[\"reasoning\"],\"reasoning\":{\"mandatory\":true,\"default_enabled\":true}},{\"id\":\"xiaomi/mimo-v2.5\",\"context_length\":1048576,\"top_provider\":{\"context_length\":32000},\"supported_parameters\":[\"reasoning\"],\"reasoning\":{\"mandatory\":false}},{\"id\":\"z-ai/glm-5.2\",\"context_length\":1048576,\"top_provider\":{\"context_length\":1048576,\"max_completion_tokens\":1048576},\"supported_parameters\":[\"reasoning\",\"reasoning_effort\"],\"reasoning\":{\"mandatory\":false,\"default_enabled\":true,\"supported_efforts\":[\"xhigh\",\"high\"],\"default_effort\":\"high\"}},{\"id\":\"testorg/test-model-x\",\"context_length\":100000,\"top_provider\":{\"context_length\":100000,\"max_completion_tokens\":8000},\"supported_parameters\":[\"reasoning\"],\"reasoning\":{\"mandatory\":false}}]}" > "$openrouter_models_fixture"
export AI_LITELLM_OPENROUTER_MODELS_JSON="$openrouter_models_fixture"
ai_litellm_model_refresh_capabilities --check >/dev/null
ai_litellm_model_policy_audit >/dev/null
# ── P6 Task 1: model add/remove RED (offline, fixture-injected) ─────────────
# add/remove verbs do not exist yet (T2/T3 land them); this section is
# expected to fail loud at the very first assertion below until model add is
# implemented. Reuses openrouter_models_fixture (still exported above as
# AI_LITELLM_OPENROUTER_MODELS_JSON) plus the synthetic testorg/test-model-x
# entry appended to its data array. Ordered so nothing here can poison the
# lineup-model assertions further down: --dry-run writes nothing, the
# add-then-remove round trip fully reverts AI_LITELLM_CONFIG before the guard
# assertion runs, and the guard assertion (remove of a tier-referenced
# surface) must loud-fail without writing anything at all.
add_plan="$(AI_LITELLM_OPENROUTER_MODELS_JSON="$openrouter_models_fixture" "$HOME/.local/bin/claude-litellm" model add testorg/test-model-x --name Test-Model-X-openrouter --dry-run 2>&1)"
print -r -- "$add_plan" | grep -q "Test-Model-X-openrouter"
print -r -- "$add_plan" | grep -q "max_input_tokens: 100000"
# dry-run wrote nothing. if-form, not bare `! grep`: zsh exempts a bare
# negated pipeline from set -e/ERR_EXIT, which would make this assertion
# silently vacuous (see the ~L395 comment on the same hazard).
if grep -q "Test-Model-X-openrouter" "$AI_LITELLM_CONFIG"; then echo "FAIL: model add --dry-run wrote to the registry"; exit 1; fi
echo "ok: model add --dry-run plans without writing"
AI_LITELLM_SKIP_SYNC=1 AI_LITELLM_OPENROUTER_MODELS_JSON="$openrouter_models_fixture" "$HOME/.local/bin/claude-litellm" model add testorg/test-model-x --name Test-Model-X-openrouter >/dev/null 2>&1
grep -q "model_name: Test-Model-X-openrouter" "$AI_LITELLM_CONFIG"
grep -q "max_input_tokens: 100000" "$AI_LITELLM_CONFIG"
ai_litellm_ruby -ryaml -e "(YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))" "$AI_LITELLM_CONFIG"   # still valid YAML w/ aliases
AI_LITELLM_SKIP_SYNC=1 "$HOME/.local/bin/claude-litellm" model remove Test-Model-X-openrouter >/dev/null 2>&1
# revert check. if-form for the same zsh set-e/bare-! reason as above.
if grep -q "Test-Model-X-openrouter" "$AI_LITELLM_CONFIG"; then echo "FAIL: model remove did not revert the registry"; exit 1; fi
echo "ok: model add/remove round-trip writes+reverts registry"
# GLM-5.2-openrouter is the opus tier alias in the installed config under test
# (config/claude-litellm/settings.json aliases.opus); removing it must refuse.
if AI_LITELLM_SKIP_SYNC=1 "$HOME/.local/bin/claude-litellm" model remove GLM-5.2-openrouter >/dev/null 2>&1; then echo "FAIL: removed a tier-referenced model"; exit 1; fi
echo "ok: model remove refuses tier-referenced surface"
PYTHONPATH="$prefix/config" AI_LITELLM_CONFIG="$prefix/config/litellm_config.yaml" python3 - <<'"'"'PY'"'"'
from ai_litellm_callbacks.output_clamp import (
    CALLBACK_NAME,
    clamp_token_reservations,
    enforce_cost_guardrail,
    gateway_cost_guardrail_decision,
    gateway_output_cap,
)

assert CALLBACK_NAME == "ai_litellm_callbacks.output_clamp.proxy_handler_instance"
shared = {
    "max_tokens": 999999,
    "max_completion_tokens": 999999,
    "model_info": {"max_input_tokens": 262144, "max_output_tokens": 262144},
}
assert gateway_output_cap(shared) == 32000
clamp_token_reservations(shared)
assert shared["max_tokens"] == 32000
assert shared["max_completion_tokens"] == 32000

small = {
    "max_tokens": 999999,
    "model_info": {"max_input_tokens": 8192, "max_output_tokens": 4096},
}
assert gateway_output_cap(small) == 3277
clamp_token_reservations(small)
assert small["max_tokens"] == 3277

allowed = gateway_cost_guardrail_decision({"messages": [{"role": "user", "content": "short"}], "max_tokens": 8})
assert allowed["allowed"] is True
large = {"messages": [{"role": "user", "content": " ".join(f"w{i}" for i in range(200001))}], "max_tokens": 1}
blocked = gateway_cost_guardrail_decision(large)
assert blocked["allowed"] is False
try:
    enforce_cost_guardrail(large)
except Exception as exc:
    assert "cost guardrail rejected" in str(exc)
else:
    raise AssertionError("large request was not rejected by cost guardrail")
PY
ai_litellm_context_observations DeepSeek >/dev/null
budget="$(ai_litellm_harness_output_budget claude sonnet Mimo-V2.5-openrouter)"
test "$(print -r -- "$budget" | jq -r ".effectiveInput == 16000 and .reservation == 12800 and .reservation < .capability")" = "true"
fable_budget="$(ai_litellm_harness_output_budget claude fable Kimi-K2.7-Code-openrouter)"
test "$(print -r -- "$fable_budget" | jq -r ".effectiveInput == 221952 and .reservation == 32000")" = "true"
ai_litellm_render_claude_settings claude
claude_settings_proxy="$(ai_litellm_harness_json claude paths.settingsArgProxy)"
test -f "$claude_settings_proxy"
jq empty "$claude_settings_proxy"
test "$(jq -r ".enableWorkflows == true and .skipWorkflowUsageWarning == true" "$claude_settings_proxy")" = "true"
test "$(jq -r ".permissions.defaultMode" "$claude_settings_proxy")" = "default"
test "$(stat -f %Lp "$claude_settings_proxy")" = "600"
# Upgrade regression: rendering must repair a stale proxy overlay left by an
# older release. Pre-seed the unsafe value, render again, and require an
# explicit downgrade while preserving unrelated user settings.
print -r -- "{\"permissions\":{\"defaultMode\":\"bypassPermissions\"},\"env\":{\"KEEP_ME\":\"yes\"}}" > "$claude_settings_proxy"
ai_litellm_render_claude_settings claude
test "$(jq -r ".permissions.defaultMode" "$claude_settings_proxy")" = "default"
test "$(jq -r ".env.KEEP_ME" "$claude_settings_proxy")" = "yes"
test "$(stat -f %Lp "$claude_settings_proxy")" = "600"
echo "ok: stale Claude proxy overlay is forcibly downgraded"
lint_root="$HOME/lint-claude"
mkdir -p "$lint_root"
print -r -- "{\"env\":{\"ANTHROPIC_BASE_URL\":\"http://127.0.0.1:1\"}}" > "$lint_root/settings.json"
! ai_litellm_claude_shared_settings_lint claude "$lint_root" 2>/dev/null
print -r -- "{\"permissions\":{\"defaultMode\":\"bypassPermissions\"},\"env\":{\"BRAVE_SEARCH_API_KEY\":\"x\"}}" > "$lint_root/settings.json"
ai_litellm_claude_shared_settings_lint claude "$lint_root" 2>/dev/null
print -r -- "{\"model\":\"~anthropic/claude-opus-latest\"}" > "$lint_root/settings.json"
lint_warning="$(ai_litellm_claude_shared_settings_lint claude "$lint_root" 2>&1)"
[[ "$lint_warning" == *"warning"* ]]
rm -rf "$lint_root"
echo "ok: shared Claude settings lint"
source "$prefix/config/claude-litellm/shell.zsh"
test "$(_claude_litellm_proxy_default_request)" = "opus"
test "$(_claude_litellm_target_model_for_request "")" = "GLM-5.2-openrouter"
test "$(_claude_litellm_target_model_for_request openrouter/z-ai/glm-5.2)" = "GLM-5.2-openrouter"
test "$(_claude_litellm_resolve_model_arg openrouter/z-ai/glm-5.2)" = "GLM-5.2-openrouter"
(
  _claude_litellm_launch_proxy() { print -r -- "proxy:$1"; }
  test "$(claude-litellm sonnet)" = "proxy:sonnet"
  test "$(claude-litellm openrouter/z-ai/glm-5.2)" = "proxy:openrouter/z-ai/glm-5.2"
  # An unresolvable leading model selector must fail before the launcher so it
  # can never leak into Claude Code as a prompt.
  ! claude-litellm Qwen3.6-35B-omlx >/dev/null 2>&1
  claude-litellm Qwen3.6-35B-omlx 2>&1 | grep -q "is not a selectable model"
  ! claude-litellm h35 >/dev/null 2>&1
  ! claude-litellm not-a-real-model >/dev/null 2>&1
  test "$(claude-litellm Qwen3.6-27B-omlx)" = "proxy:Qwen3.6-27B-omlx"
)
echo "ok: proxy-only model selector guards"
if claude-litellm Kimi-K2.7-Code-openrouter --effort high -p noop >/dev/null 2>&1; then
  echo "FAIL: explicit effort reached a Kimi launch without configurable-effort support" >&2
  exit 1
fi
claude-litellm Kimi-K2.7-Code-openrouter --effort high -p noop 2>&1 | grep -q "does not expose selectable effort levels"
echo "ok: unsupported selectable effort is rejected"
stub_dir="$HOME/claude-stub"
mkdir -p "$stub_dir"
{
  print -r -- "#!/usr/bin/env zsh"
  print -r -- "print -r -- \"base=\$ANTHROPIC_BASE_URL\""
  print -r -- "print -r -- \"auth=\${ANTHROPIC_AUTH_TOKEN:+set}\""
  print -r -- "print -r -- \"api_key_set=\${+ANTHROPIC_API_KEY}\""
  print -r -- "print -r -- \"api_key_value=\$ANTHROPIC_API_KEY\""
  print -r -- "print -r -- \"discovery=\$CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY\""
  print -r -- "print -r -- \"attribution=\$CLAUDE_CODE_ATTRIBUTION_HEADER\""
  print -r -- "print -r -- \"max_tokens_set=\${+CLAUDE_CODE_MAX_OUTPUT_TOKENS}\""
  print -r -- "print -r -- \"sonnet=\$ANTHROPIC_DEFAULT_SONNET_MODEL\""
  print -r -- "print -r -- \"sonnet_name=\$ANTHROPIC_DEFAULT_SONNET_MODEL_NAME\""
  print -r -- "print -r -- \"haiku=\$ANTHROPIC_DEFAULT_HAIKU_MODEL\""
  print -r -- "print -r -- \"haiku_name=\$ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME\""
  print -r -- "print -r -- \"subagent=\$CLAUDE_CODE_SUBAGENT_MODEL\""
  print -r -- "print -r -- \"caps=\${+ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES}:\$ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES\""
  print -r -- "print -r -- \"args=\$*\""
} > "$stub_dir/claude"
chmod +x "$stub_dir/claude"
proxy_output="$(
  (
  ai_litellm_model_runtime_ready() { return 0; }
  ai_litellm_start() { return 0; }
  ai_litellm_master_key() { print -r -- "sk-test-master"; }
  ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES="ambient-poison" \
    PATH="$stub_dir:$PATH" claude-litellm sonnet -p noop
  )
)"
proxy_expect() {
  local expected="$1"
  [[ "$proxy_output" == *"$expected"* ]] || {
    echo "FAIL: proxy launcher output missing: $expected" >&2
    print -r -- "$proxy_output" >&2
    exit 1
  }
}
proxy_expect "base=http://127.0.0.1:$AI_LITELLM_TEST_PORT"
proxy_expect "auth=set"
proxy_expect "api_key_set=1"
proxy_expect "api_key_value="
proxy_expect "discovery=1"
proxy_expect "attribution=0"
proxy_expect "max_tokens_set=1"
proxy_expect "sonnet=Mimo-V2.5-openrouter"
proxy_expect "sonnet_name=Mimo-V2.5 (openrouter)"
proxy_expect "haiku=Qwen3.6-27B-omlx"
proxy_expect "haiku_name=Qwen3.6-27B (omlx)"
proxy_expect "subagent="
proxy_expect "caps=0:"
proxy_expect "--model sonnet"
proxy_expect "--settings $CLAUDE_LITELLM_SETTINGS_ARG_PROXY"
echo "ok: proxy launcher injects isolated routing environment"
claude_shared_root="$(ai_litellm_harness_json claude isolation.sharedEnvironment.targetRoot)"
test -L "$prefix/state/claude-litellm/claude-config/settings.json"
test "$(readlink "$prefix/state/claude-litellm/claude-config/settings.json")" = "$claude_shared_root/settings.json"
test -L "$prefix/state/claude-litellm/claude-config/CLAUDE.md"
test -L "$prefix/state/claude-litellm/claude-config/plugins"
test ! -e "$HOME/.claude"
echo "ok: Claude config links target the rendered shared environment"
proxy_output_repeat="$(
  (
  ai_litellm_model_runtime_ready() { return 0; }
  ai_litellm_start() { return 0; }
  ai_litellm_master_key() { print -r -- "sk-test-master"; }
  PATH="$stub_dir:$PATH" claude-litellm sonnet -p noop
  )
)"
[[ "$proxy_output_repeat" == *"attribution=0"* ]]
if find "$prefix/state/claude-litellm/claude-config" -name "*.isolated.bak*" | grep -q .; then
  echo "Unexpected shared-environment backups after repeated launch" >&2
  exit 1
fi
echo "ok: repeated proxy launch does not duplicate shared-environment backups"
(
  mig_config="$HOME/mig-config"
  mkdir -p "$mig_config"
  print -r -- "{\"old\":true}" > "$mig_config/settings.json"
  ai_litellm_model_runtime_ready() { return 0; }
  ai_litellm_start() { return 0; }
  ai_litellm_master_key() { print -r -- "sk-test-master"; }
  mig_output="$(PATH="$stub_dir:$PATH" CLAUDE_LITELLM_CLAUDE_CONFIG="$mig_config" claude-litellm sonnet -p noop 2>&1)"
  [[ "$mig_output" == *"moved isolated settings.json"* ]]
  test -L "$mig_config/settings.json"
  test "$(readlink "$mig_config/settings.json")" = "$claude_shared_root/settings.json"
  test "$(jq -r ".old" "$mig_config/settings.json.isolated.bak")" = "true"
)
echo "ok: isolated Claude settings migrate once before shared linking"
(
  ai_litellm_model_runtime_ready() { return 0; }
  ai_litellm_start() { return 0; }
  ai_litellm_master_key() { print -r -- "sk-test-master"; }
  stale_output="$(PATH="$stub_dir:$PATH" CLAUDE_LITELLM_SETTINGS_ARG_PROXY="$CLAUDE_LITELLM_CLAUDE_CONFIG/settings.json" claude-litellm sonnet -p noop 2>&1)"
  [[ "$stale_output" == *"ignoring stale CLAUDE_LITELLM_SETTINGS_ARG_PROXY"* ]]
  [[ "$stale_output" == *"--settings $CLAUDE_LITELLM_SETTINGS_ARG_PROXY"* ]]
  test -L "$prefix/state/claude-litellm/claude-config/settings.json"
)
echo "ok: stale proxy overlay path is canonicalized outside shared config"
ai_litellm_model_limits Qwen3.6-27B-omlx >/dev/null
runtime_routes_dedup="$(ai_litellm_runtime_routes_write omlx 1 Qwen3.6-27B-4bit)"
[[ -z "$runtime_routes_dedup" ]]  # dedup must yield NO route for an upstream a registry entry already serves
"$HOME/.local/bin/claude-litellm" --status >/dev/null
# ── P4 slimming: launcher lifecycle flags retired; --list/--status survive ──
# claude-litellm --start/--stop/--restart/--logs/--doctor move fully under
# claude-litellm proxy *; the branches (warning text included) are deleted, so the
# flag must no longer reach ai_litellm_start et al. The pre-P4 signature was a
# WARN-then-delegate ("--start is deprecated"); its absence is the reliable,
# environment-independent signal that the branch is gone. Known legacy flags
# now fail explicitly before reaching model resolution or proxy startup.
# NOTE: under the set -e this whole battery runs with, a bare `var="$(cmd)"`
# aborts the script the instant cmd exits nonzero (zsh errexit applies to
# assignments with command substitutions), before a separate `rc=$?` line
# could ever run.
# `if var="$(cmd)"; then ...` is exempt (assignment as an if-condition), so
# that is how output+exit-code are captured together here, not `2>&1 || true`
# (which would force success and hide a real nonzero-exit regression).
if claude_start_out="$(claude-litellm --start 2>&1)"; then
  echo "FAIL: claude-litellm --start no longer exits nonzero" >&2; exit 1
fi
[[ "$claude_start_out" == *"claude-litellm proxy start"* ]] || { echo "FAIL: --start lacks replacement command" >&2; exit 1; }
[[ "$claude_start_out" != *"--start is deprecated"* ]] || { echo "FAIL: claude-litellm --start still warns and delegates (retire the branch)" >&2; exit 1; }
if claude_doctor_out="$(claude-litellm --doctor 2>&1)"; then
  echo "FAIL: claude-litellm --doctor no longer exits nonzero" >&2; exit 1
fi
[[ "$claude_doctor_out" == *"claude-litellm doctor"* ]] || { echo "FAIL: --doctor lacks replacement command" >&2; exit 1; }
if ! claude_list_out="$(claude-litellm --list 2>&1)"; then
  echo "FAIL: claude-litellm --list no longer works" >&2; exit 1
fi
[[ "$claude_list_out" == *"Claude aliases:"* ]] || { echo "FAIL: claude-litellm --list output shape changed" >&2; exit 1; }
claude_status_rc=0
claude-litellm --status >/dev/null 2>&1 || claude_status_rc=$?
[[ $claude_status_rc -eq 0 ]] || { echo "FAIL: claude-litellm --status no longer works" >&2; exit 1; }
echo "ok: claude-litellm lifecycle flags retired; --list/--status survive"
test "$(stat -f %Lp "$prefix/state")" = "700"
test "$(stat -f %Lp "$prefix/state/ai-litellm")" = "700"
"$HOME/.local/bin/claude-litellm" key set openrouter "PLACEHOLDER\$(touch $HOME/PWNED)END" >/dev/null 2>/dev/null
test "$(ai_litellm_env_value OPENROUTER_API_KEY)" = "PLACEHOLDER\$(touch $HOME/PWNED)END"
test -n "$(ai_litellm_env_value LITELLM_MASTER_KEY)"
test ! -e "$HOME/PWNED"

# The installed lifecycle must use the guarded, prefix-owned single-process
# bootstrap. With no ChatGPT credential it stays healthy, omits only that eager
# OAuth deployment, never writes device state, and remains stoppable by the
# exact PID ownership checks.
rm -f "$prefix/state/auth/chatgpt/auth.json"
"$HOME/.local/bin/claude-litellm" proxy start >/dev/null
managed_pid="$(<$prefix/state/ai-litellm/litellm.pid)"
managed_command="$(ps -ww -o command= -p "$managed_pid")"
[[ "$managed_command" == *"$prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"* ]]
[[ "$managed_command" != *" -m ai_litellm_callbacks.proxy_bootstrap "* ]]
ai_litellm_health
proxy_models="$(ai_litellm_proxy_model_names)"
[[ "$proxy_models" == *"Qwen3.6-27B-omlx"* ]]
[[ "$proxy_models" == *"Grok-4.5-xai-oauth"* ]]
[[ "$proxy_models" != *"GPT-5.4-chatgpt-oauth"* ]]
test ! -e "$prefix/state/auth/chatgpt/auth.json"
"$HOME/.local/bin/claude-litellm" proxy stop >/dev/null 2>&1
test ! -e "$prefix/state/ai-litellm/litellm.pid"
! kill -0 "$managed_pid" 2>/dev/null
echo "ok: installed proxy uses guarded single-process bootstrap"

# A child that exits before readiness must not leave a PID/hash file or a
# partial proxy behind. Run in a subshell so the deliberately broken config and
# alternate bookkeeping paths cannot leak into later checks.
(
  failure_home="$HOME/start-failure"
  export AI_LITELLM_CONFIG="$failure_home/missing-litellm-config.yaml"
  export AI_LITELLM_PROXY_HOME="$failure_home/state"
  export AI_LITELLM_PID_FILE="$AI_LITELLM_PROXY_HOME/litellm.pid"
  export AI_LITELLM_LOCK_DIR="$AI_LITELLM_PROXY_HOME/litellm.lock"
  export AI_LITELLM_LOG_FILE="$AI_LITELLM_PROXY_HOME/litellm.log"
  export AI_LITELLM_CONFIG_HASH_FILE="$AI_LITELLM_PROXY_HOME/litellm.config.sha256"
  export AI_LITELLM_STARTED_AT_FILE="$AI_LITELLM_PROXY_HOME/litellm.started_at"
  export LITELLM_MASTER_KEY="sk-failed-start-cleanup-test"
  if ai_litellm_start >/dev/null 2>&1; then
    echo "Broken-config proxy unexpectedly started" >&2
    exit 1
  fi
  test ! -e "$AI_LITELLM_PID_FILE"
  test ! -e "$AI_LITELLM_CONFIG_HASH_FILE"
  test ! -e "$AI_LITELLM_STARTED_AT_FILE"
  test -z "$(ps -ww -axo command= | grep -F -- "--config $AI_LITELLM_CONFIG" | grep -v grep || true)"
)
echo "ok: failed proxy startup cleans partial process state"

if command -v security >/dev/null 2>&1; then
  keychain_service="ai-litellm-check-openrouter-$$"
  REAL_HOME="${REAL_HOME:?}" HOME="$REAL_HOME" OPENROUTER_KEYCHAIN_SERVICE="$keychain_service" "$prefix/bin/claude-litellm" key set --keychain openrouter "PLACEHOLDER_KEYCHAIN" >/dev/null 2>/dev/null
  # Account must match what the store call above actually used: this whole
  # script exports OPENROUTER_KEYCHAIN_ACCOUNT (see the zsh -fc env prefix,
  # top of file) to isolate it from the real machine account/key, so the
  # round-trip has to look it up under that same isolated account -- not the
  # real $USER, which is what the store call would use only in the absence
  # of that override.
  test "$(HOME="$REAL_HOME" security find-generic-password -s "$keychain_service" -a "$OPENROUTER_KEYCHAIN_ACCOUNT" -w)" = "PLACEHOLDER_KEYCHAIN"
  HOME="$REAL_HOME" security delete-generic-password -s "$keychain_service" -a "$OPENROUTER_KEYCHAIN_ACCOUNT" >/dev/null 2>&1
fi
"$HOME/.local/bin/claude-litellm" uninstall --dry-run >/dev/null
sleep 60 &
foreign_pid=$!
mkdir -p "$HOME/.config/ai-litellm"
print -r -- "$foreign_pid" > "$HOME/.config/ai-litellm/litellm.pid"
! ai_litellm_pid_running
ai_litellm_stop >/dev/null 2>&1 || true
kill -0 "$foreign_pid"
kill "$foreign_pid"
rmdir "$HOME/.config/ai-litellm" "$HOME/.config" 2>/dev/null || true
ai_litellm_restart() { echo "unexpected restart" >&2; return 99; }
sync_output="$(ai_litellm_sync --dry-run)"
[[ "$sync_output" == *"proxy restart skipped"* ]]
[[ "$sync_output" == *"- claude settings"* ]]
tool_dir="$HOME/toolbin"
mkdir -p "$tool_dir"
for tool in node jq ruby python3 curl rg grep sed awk shasum perl mkdir chmod stat find kill sleep rmdir; do
  tool_path="$(command -v "$tool" 2>/dev/null || true)"
  [[ "$tool_path" == /* ]] && ln -sf "$tool_path" "$tool_dir/$tool"
done
old_path="$PATH"
PATH="$tool_dir:/usr/bin:/bin:/usr/sbin:/sbin"
for harness in claude; do
  cli="$(ai_litellm_harness_json "$harness" command)"
  if command -v "$cli" >/dev/null 2>&1; then
    echo "Expected $cli to be absent from restricted PATH" >&2
    exit 1
  fi
  info="$(ai_litellm_harness_info "$harness")"
  [[ "$info" == *"Status:    ok"* ]]
  [[ "$info" == *"CLI:       not installed"* ]]
done
ai_litellm_doctor_harnesses >/dev/null
restricted_sync_output="$(ai_litellm_sync --dry-run)"
[[ "$restricted_sync_output" == *"- claude settings"* ]]
[[ "$restricted_sync_output" == *"proxy restart skipped"* ]]
PATH="$old_path"
test ! -e "$HOME/litellm_config.yaml"
test ! -e "$HOME/.config/ai-litellm"
test ! -e "$HOME/.config/claude-litellm"
test ! -e "$HOME/.claude"
'

spaced_prefix="$spaced_home/with space/claude-litellm"
LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-spaced-$$" HOME="$spaced_home" "$repo_root/scripts/install.zsh" --prefix "$spaced_prefix" >/dev/null
HOME="$spaced_home" "$spaced_prefix/bin/claude-litellm" --help >/dev/null
test ! -e "$spaced_home/.local/bin/claude-litellm"
print -r -- "PROVIDER_SENTINEL=preserve-me" > "$spaced_prefix/state/ai-litellm/env"
chmod 600 "$spaced_prefix/state/ai-litellm/env"
LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-spaced-$$" HOME="$spaced_home" "$repo_root/scripts/install.zsh" --prefix "$spaced_prefix" >/dev/null
grep -qx "PROVIDER_SENTINEL=preserve-me" "$spaced_prefix/state/ai-litellm/env"
grep -Eq '^LITELLM_MASTER_KEY=.+$' "$spaced_prefix/state/ai-litellm/env"
test "$(stat -f %Lp "$spaced_prefix/state/ai-litellm/env")" = "600"
mutable_config="$spaced_prefix/config/litellm_config.yaml"
mutable_settings="$spaced_prefix/config/claude-litellm/settings.json"
install_manifest="$spaced_prefix/install-manifest.json"
sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}
for relative in config/litellm_config.yaml config/claude-litellm/settings.json; do
  case "$relative" in
    config/litellm_config.yaml) tracked_file="$mutable_config" ;;
    config/claude-litellm/settings.json) tracked_file="$mutable_settings" ;;
  esac
  tracked_sha="$(sha256_file "$tracked_file")"
  jq -e --arg relative "$relative" --arg sha "$tracked_sha" \
    '.managedMutableFiles[$relative] == {sha256: $sha, upgradePolicy: "abort-on-drift"}' \
    "$install_manifest" >/dev/null
done
cp -p "$mutable_config" "$spaced_home/litellm-config.baseline"
cp -p "$mutable_settings" "$spaced_home/claude-settings.baseline"

assert_durable_reinstall_rejected() {
  local label="$1" reject_out
  local config_sha config_stat settings_sha settings_stat manifest_sha manifest_stat
  local runtime_stat runtime_python_sha pid_command
  config_sha="$(sha256_file "$mutable_config")"
  config_stat="$(stat -f '%i:%m:%c:%z' "$mutable_config")"
  settings_sha="$(sha256_file "$mutable_settings")"
  settings_stat="$(stat -f '%i:%m:%c:%z' "$mutable_settings")"
  manifest_sha="$(sha256_file "$install_manifest")"
  manifest_stat="$(stat -f '%i:%m:%c:%z' "$install_manifest")"
  runtime_stat="$(stat -f '%i:%m:%c' "$spaced_prefix/runtime/venv")"
  runtime_python_sha="$(sha256_file "$spaced_prefix/runtime/venv/bin/python")"
  pid_command="$(ps -ww -o command= -p "$durability_pid")"

  if reject_out="$(LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-spaced-$$" \
    HOME="$spaced_home" "$repo_root/scripts/install.zsh" --prefix "$spaced_prefix" 2>&1)"; then
    echo "Reinstall unexpectedly overwrote durable $label configuration" >&2
    exit 1
  fi
  [[ "$reject_out" == *"Refusing reinstall: durable user configuration differs"* ]]
  [[ "$reject_out" == *"No destination file, proxy, or runtime was changed."* ]]
  test "$(sha256_file "$mutable_config")" = "$config_sha"
  test "$(stat -f '%i:%m:%c:%z' "$mutable_config")" = "$config_stat"
  test "$(sha256_file "$mutable_settings")" = "$settings_sha"
  test "$(stat -f '%i:%m:%c:%z' "$mutable_settings")" = "$settings_stat"
  test "$(sha256_file "$install_manifest")" = "$manifest_sha"
  test "$(stat -f '%i:%m:%c:%z' "$install_manifest")" = "$manifest_stat"
  test "$(stat -f '%i:%m:%c' "$spaced_prefix/runtime/venv")" = "$runtime_stat"
  test "$(sha256_file "$spaced_prefix/runtime/venv/bin/python")" = "$runtime_python_sha"
  kill -0 "$durability_pid"
  test "$(ps -ww -o command= -p "$durability_pid")" = "$pid_command"
}

# First tracked file: add a custom route with an explicit reasoning setting.
ruby -e '
path = ARGV.fetch(0)
text = File.read(path)
route = [
  "  - model_name: Durability-Test-openrouter",
  "    litellm_params:",
  "      model: openrouter/testorg/durability-test",
  "      api_key: os.environ/OPENROUTER_API_KEY",
  "      reasoning_effort: high",
  "    model_info:",
  "      supports_reasoning: true",
  "      x_reasoning_efforts: [low, medium, high]",
].join("\n") + "\n\n"
abort "general_settings marker missing" unless text.sub!(/^general_settings:/, route + "general_settings:")
File.write(path, text)
' "$mutable_config"
ruby -ryaml -e '(YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))' "$mutable_config"

durability_prefix="$spaced_prefix"
durability_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
durability_master="$(sed -n 's/^LITELLM_MASTER_KEY=//p' "$spaced_prefix/state/ai-litellm/env" | tail -1)"
mkdir -p "$spaced_home/durability-auth/chatgpt" "$spaced_home/durability-auth/grok"
chmod 700 "$spaced_home/durability-auth" "$spaced_home/durability-auth/chatgpt" "$spaced_home/durability-auth/grok"
OPENROUTER_API_KEY="offline-test-only" LITELLM_MASTER_KEY="$durability_master" \
  CHATGPT_TOKEN_DIR="$spaced_home/durability-auth/chatgpt" \
  XAI_OAUTH_TOKEN_DIR="$spaced_home/durability-auth/grok" \
  NUM_WORKERS=1 \
  PYTHONPATH="$spaced_prefix/config" \
  "$spaced_prefix/runtime/venv/bin/python" \
  "$spaced_prefix/config/ai_litellm_callbacks/proxy_bootstrap.py" \
  --config "$mutable_config" \
  --host 127.0.0.1 --port "$durability_port" \
  > "$spaced_home/durability-proxy.log" 2>&1 &
durability_pid=$!
for attempt in {1..50}; do
  kill -0 "$durability_pid" 2>/dev/null || {
    tail -80 "$spaced_home/durability-proxy.log" >&2
    echo "Durability test proxy exited during startup" >&2
    exit 1
  }
  curl -fsS --max-time 1 "http://127.0.0.1:$durability_port/health/readiness" >/dev/null 2>&1 && break
  sleep 0.2
done
kill -0 "$durability_pid"
assert_durable_reinstall_rejected "custom route/reasoning"

# Restore the first baseline, then drift only the second tracked file by
# changing a Claude tier alias. It must independently trip the same preflight.
cp -p "$spaced_home/litellm-config.baseline" "$mutable_config"
test "$(sha256_file "$mutable_config")" = "$(sha256_file "$spaced_home/litellm-config.baseline")"
jq '.aliases.opus = "GPT-5.4-chatgpt-oauth"' "$mutable_settings" > "$mutable_settings.tmp"
mv "$mutable_settings.tmp" "$mutable_settings"
assert_durable_reinstall_rejected "Claude alias"
cleanup_owned_test_proxy "$durability_prefix" "$durability_pid"
durability_pid=""
echo "ok: reinstall refuses durable config drift before file/runtime/proxy mutation"

if [[ -d "$spaced_home/.local" ]] && find "$spaced_home/.local" -name "*.bak.*" | grep -q .; then
  echo "Unexpected backup files after identical reinstall" >&2
  find "$spaced_home/.local" -name "*.bak.*" >&2
  exit 1
fi
HOME="$spaced_home" "$repo_root/scripts/uninstall.zsh" --prefix "$spaced_prefix" >/dev/null
test ! -e "$spaced_prefix"
test ! -e "$spaced_home/.local/bin/claude-litellm"
unsafe_uninstall_prefix="$spaced_home/not-fabric"
mkdir -p "$unsafe_uninstall_prefix"
print -r -- "must-survive" > "$unsafe_uninstall_prefix/sentinel"
if HOME="$spaced_home" "$repo_root/scripts/uninstall.zsh" --prefix "$unsafe_uninstall_prefix" >/dev/null 2>&1; then
  echo "Unsafe uninstall prefix was accepted" >&2
  exit 1
fi
grep -qx "must-survive" "$unsafe_uninstall_prefix/sentinel"

echo "ok"
