#!/usr/bin/env zsh

set -euo pipefail

# check.zsh never reads stdin. Pin it to /dev/null so any command that would
# otherwise fall back to reading stdin (e.g. a jq whose `< file` input binding is
# lost in a nested `zsh -fc` quoting context) gets immediate EOF instead of
# blocking forever when check runs non-interactively (background/CI/no TTY).
exec </dev/null

repo_root="${0:A:h:h}"
real_home="$HOME"
for inherited_name in ${(k)parameters}; do
  case "$inherited_name" in
    AI_LITELLM_*|CLAUDE_LITELLM_*) unset "$inherited_name" 2>/dev/null || true ;;
  esac
done
unset XDG_DATA_HOME XDG_CONFIG_HOME XDG_CACHE_HOME OPENROUTER_API_KEY LITELLM_MASTER_KEY
check_python="$(command -v python3.13 2>/dev/null || true)"
[[ -x "$check_python" ]] || { echo "Python 3.13 is required for checks." >&2; exit 1; }
"$check_python" -c 'import sys; assert sys.version_info[:2] == (3, 13)'
export CHECK_PYTHON="$check_python"

for file in \
  "$repo_root/scripts/install.zsh" \
  "$repo_root/scripts/uninstall.zsh" \
  "$repo_root/config/ai-litellm/lib.zsh" \
  "$repo_root/config/claude-litellm/shell.zsh" \
  "$repo_root"/bin/*(N); do
  zsh -n "$file"
done

"$check_python" -m py_compile "$repo_root/scripts/verify_litellm_token_clamp.py"
"$check_python" -m py_compile "$repo_root/scripts/verify_tool_call_fidelity.py"
"$check_python" -m py_compile "$repo_root/scripts/verify_oauth_adapters.py"
"$check_python" -m py_compile "$repo_root/config/ai_litellm_callbacks/oauth_guard.py"
"$check_python" -m py_compile "$repo_root/config/ai_litellm_callbacks/chatgpt_stream_compat.py"
"$check_python" -m py_compile "$repo_root/config/ai_litellm_callbacks/proxy_bootstrap.py"
"$check_python" -m py_compile "$repo_root/config/ai_litellm_callbacks/output_clamp.py"
"$check_python" -m py_compile "$repo_root/scripts/verify_budget_consistency.py"
"$check_python" -m py_compile "$repo_root/scripts/render-user-config.py"
"$check_python" -m py_compile "$repo_root/scripts/runtime-fingerprint.py"
"$check_python" -m py_compile "$repo_root/scripts/task-ledger.py"
"$check_python" -m py_compile "$repo_root/scripts/verify-install.py"
"$check_python" -m py_compile "$repo_root/scripts/verify_user_config_overlay.py"

# Differential test: the four token-budget implementations (Node + 2 Ruby copies
# in lib.zsh, Python in output_clamp.py) must agree on every comparable quantity
# across the full input matrix. This is the real drift guard for the budget math;
# the legacy 1008384/237568/3277 single-point pins below remain as cheap smoke.
# Runs from the checkout so it slices the *live* lib.zsh (self-syncing, no copy).
# Non-interactive (no stdin/env prompts); exits nonzero on any cross-impl drift.
"$check_python" "$repo_root/scripts/verify_budget_consistency.py"
"$check_python" -m unittest discover -s "$repo_root/tests" -p 'test_*.py'

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

dry_run_prefix="$spaced_home/dry-run/claude-litellm"
HOME="$spaced_home" "$repo_root/scripts/install.zsh" --dry-run --prefix "$dry_run_prefix" >/dev/null
test ! -e "$dry_run_prefix"
test ! -e "$spaced_home/.config"
test ! -e "$spaced_home/.local"

# XDG layouts must not make rebuildable package bytes overlap the public shim,
# durable user overlays, or native Claude/Codex state.
if HOME="$spaced_home" XDG_DATA_HOME="$spaced_home/.local/bin" \
  "$repo_root/scripts/install.zsh" --dry-run >/dev/null 2>&1; then
  echo "FAIL: installer accepted package/public-command path overlap" >&2
  exit 1
fi
if HOME="$spaced_home" XDG_DATA_HOME="$spaced_home/.config" XDG_CONFIG_HOME="$spaced_home/.config" \
  "$repo_root/scripts/install.zsh" --dry-run >/dev/null 2>&1; then
  echo "FAIL: installer accepted package/user-config path overlap" >&2
  exit 1
fi
if HOME="$spaced_home" XDG_CONFIG_HOME="$spaced_home/.config" \
  "$repo_root/scripts/uninstall.zsh" --dry-run \
  --prefix "$spaced_home/.config/claude-litellm" >/dev/null 2>&1; then
  echo "FAIL: uninstaller accepted package/current-user-config path overlap" >&2
  exit 1
fi
if HOME="$spaced_home" "$repo_root/scripts/uninstall.zsh" --dry-run \
  --prefix "$spaced_home/.local" >/dev/null 2>&1; then
  echo "FAIL: uninstaller accepted a package root owning unrelated public commands" >&2
  exit 1
fi
recorded_overlap_prefix="$spaced_home/recorded-overlap-package"
mkdir -p "$recorded_overlap_prefix"
jq -n --arg prefix "$recorded_overlap_prefix" \
  '{product:"claude-litellm",schemaVersion:2,prefix:$prefix,userConfig:{upgradePolicy:"preserve-and-render-over-package-defaults",models:($prefix+"/models.json"),claudeSettings:"/outside/settings.json"}}' \
  > "$recorded_overlap_prefix/install-manifest.json"
chmod 600 "$recorded_overlap_prefix/install-manifest.json"
if HOME="$spaced_home" XDG_CONFIG_HOME="$spaced_home/different-config" \
  "$repo_root/scripts/uninstall.zsh" --dry-run \
  --prefix "$recorded_overlap_prefix" >/dev/null 2>&1; then
  echo "FAIL: uninstaller ignored manifest-recorded user-config overlap" >&2
  exit 1
fi
rm -rf "$recorded_overlap_prefix"
symlink_config_alias="$spaced_home/config-link"
ln -s "$spaced_home" "$symlink_config_alias"
if HOME="$spaced_home" XDG_CONFIG_HOME="$symlink_config_alias" \
  "$repo_root/scripts/install.zsh" --dry-run \
  --prefix "$spaced_home/claude-litellm" >/dev/null 2>&1; then
  echo "FAIL: installer accepted a symlink-aliased user-config root" >&2
  exit 1
fi
recorded_symlink_prefix="$spaced_home/recorded-symlink-package"
mkdir -p "$recorded_symlink_prefix"
print -r -- preserved > "$recorded_symlink_prefix/models.json"
jq -n --arg prefix "$recorded_symlink_prefix" --arg alias "$symlink_config_alias" \
  '{product:"claude-litellm",schemaVersion:2,prefix:$prefix,userConfig:{upgradePolicy:"preserve-and-render-over-package-defaults",models:($alias+"/recorded-symlink-package/models.json"),claudeSettings:($alias+"/recorded-symlink-package/settings.json")}}' \
  > "$recorded_symlink_prefix/install-manifest.json"
chmod 600 "$recorded_symlink_prefix/install-manifest.json"
if HOME="$spaced_home" XDG_CONFIG_HOME="$spaced_home/different-config" \
  "$repo_root/scripts/uninstall.zsh" --dry-run \
  --prefix "$recorded_symlink_prefix" >/dev/null 2>&1; then
  echo "FAIL: uninstaller ignored a symlink-resolved manifest user-config overlap" >&2
  exit 1
fi
grep -qx preserved "$recorded_symlink_prefix/models.json"
rm -rf "$recorded_symlink_prefix" "$symlink_config_alias"
for protected_prefix in "$spaced_home/.claude" "$spaced_home/.claude/child" \
  "$spaced_home/.codex" "$spaced_home/.codex/child"; do
  if HOME="$spaced_home" "$repo_root/scripts/install.zsh" --dry-run \
    --prefix "$protected_prefix" >/dev/null 2>&1; then
    echo "FAIL: installer accepted protected native prefix: $protected_prefix" >&2
    exit 1
  fi
  if HOME="$spaced_home" "$repo_root/scripts/uninstall.zsh" --dry-run \
    --prefix "$protected_prefix" >/dev/null 2>&1; then
    echo "FAIL: uninstaller accepted protected native prefix: $protected_prefix" >&2
    exit 1
  fi
done
echo "ok: package, shim, overlays, and native state roots stay disjoint"
symlink_prefix_target="$spaced_home/symlink-prefix-target"
symlink_prefix_parent="$spaced_home/symlink-prefix-parent"
mkdir -p "$symlink_prefix_target"
ln -s "$symlink_prefix_target" "$symlink_prefix_parent"
if HOME="$spaced_home" "$repo_root/scripts/install.zsh" --dry-run \
  --prefix "$symlink_prefix_parent/claude-litellm" >/dev/null 2>&1; then
  echo "FAIL: installer accepted a user-controlled symlink prefix ancestor" >&2
  exit 1
fi
leaf_prefix_target="$spaced_home/leaf-prefix-target"
leaf_prefix="$spaced_home/leaf-prefix"
mkdir -p "$leaf_prefix_target"
ln -s "$leaf_prefix_target" "$leaf_prefix"
if HOME="$spaced_home" "$repo_root/scripts/install.zsh" --dry-run \
  --prefix "$leaf_prefix" >/dev/null 2>&1; then
  echo "FAIL: installer accepted a symlink prefix leaf" >&2
  exit 1
fi
echo "ok: installer dry-run leaves no filesystem state"

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
"$tmp_home/.local/share/claude-litellm/runtime/venv/bin/python" \
  "$repo_root/scripts/verify_user_config_overlay.py"
test_port="$("$check_python" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
installed_settings="$tmp_home/.local/share/claude-litellm/config/ai-litellm/settings.json"
test_settings="$tmp_home/test-ai-litellm-settings.json"
jq --argjson port "$test_port" '.server.port = $port' "$installed_settings" > "$test_settings"
chmod 600 "$test_settings"
REAL_HOME="$real_home" CHECK_PYTHON="$check_python" AI_LITELLM_TEST_PORT="$test_port" AI_LITELLM_SETTINGS="$test_settings" HOME="$tmp_home" OPENROUTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-openrouter-key-$$" zsh -fc '
set -e
prefix="$HOME/.local/share/claude-litellm"
test -f "$prefix/config/ai-litellm/lib.zsh"
test -f "$prefix/config/ai-litellm/context-observations.json"
test -f "$prefix/config/litellm_config.yaml"
test -f "$prefix/config/ai_litellm_callbacks/output_clamp.py"
test -f "$prefix/config/ai_litellm_callbacks/chatgpt_stream_compat.py"
test -f "$prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"
test -x "$prefix/scripts/verify_tool_call_fidelity.py"
test -x "$prefix/scripts/task-ledger.py"
test -x "$prefix/scripts/uninstall.zsh"
test -x "$prefix/bin/claude-litellm"
test -x "$HOME/.local/bin/claude-litellm"
test ! -e "$HOME/.local/bin/ai-litellm"
test ! -e "$HOME/.local/bin/codex-litellm"
"$HOME/.local/bin/claude-litellm" --help >/dev/null
"$HOME/.local/bin/claude-litellm" status > "$HOME/status-text.out" 2>/dev/null
grep -q "Claude settings:" "$HOME/status-text.out"
grep -q "Effort:.*OpenRouter xhigh/max normalize to high" "$HOME/status-text.out"
grep -q "chatgpt: not authenticated" "$HOME/status-text.out"
grep -q "grok: not authenticated" "$HOME/status-text.out"
echo "ok: public status summary"
damaged_root="$HOME/damaged-installed-root"
legacy_fallback_root="$HOME/.config/ai-litellm"
legacy_fallback_sentinel="$HOME/legacy-fallback-sourced"
mkdir -p "$damaged_root" "$legacy_fallback_root"
print -r -- "{}" > "$damaged_root/install-manifest.json"
chmod 600 "$damaged_root/install-manifest.json"
print -r -- ": > \"$legacy_fallback_sentinel\"" > "$legacy_fallback_root/lib.zsh"
if CLAUDE_LITELLM_ROOT="$damaged_root" "$prefix/bin/claude-litellm" status >/dev/null 2>&1; then
  echo "FAIL: damaged installed package fell through to a legacy helper" >&2
  exit 1
fi
test ! -e "$legacy_fallback_sentinel"
rm -rf "$damaged_root" "$legacy_fallback_root"
echo "ok: installed launcher fails closed instead of sourcing legacy helpers"
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
test "$(ai_litellm_model_reasoning_allowed_efforts openrouter/z-ai/glm-5.2)" = "high"
grep -A14 "^  glm52:" "$AI_LITELLM_CONFIG" | grep -q "x_provider_reasoning_efforts: \[xhigh, high\]"
grep -A14 "^  glm52:" "$AI_LITELLM_CONFIG" | grep -q "x_reasoning_effort_ceiling: high"
ai_litellm_reasoning_effort_metadata_ok
effort_transport_drift="$HOME/effort-transport-drift.yaml"
sed "s/x_reasoning_efforts: \[high\]/x_reasoning_efforts: [xhigh, high]/" \
  "$AI_LITELLM_CONFIG" > "$effort_transport_drift"
if AI_LITELLM_CONFIG="$effort_transport_drift" ai_litellm_reasoning_effort_metadata_ok >/dev/null 2>&1; then
  echo "FAIL: OpenRouter xhigh was exposed despite the LiteLLM 1.92 high ceiling" >&2
  exit 1
fi
test "$(ai_litellm_model_reasoning_allowed_efforts Grok-4.5-xai-oauth)" = "low medium high"
if ai_litellm_model_reasoning_allowed_efforts GPT-5.6-Sol-chatgpt-oauth >/dev/null 2>&1; then
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
rob_port="$("$CHECK_PYTHON" -c "import socket;s=socket.socket();s.bind((\"127.0.0.1\",0));print(s.getsockname()[1]);s.close()")"
"$CHECK_PYTHON" -c "
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
grep -A16 "model_name: Qwen3.6-Test-27B-omlx" "$AI_LITELLM_CONFIG" | grep -q "enable_thinking: false"
grep -A16 "model_name: Qwen3.6-Test-27B-omlx" "$AI_LITELLM_CONFIG" | grep -q "max_input_tokens: 131072"
grep -A16 "model_name: Qwen3.6-Test-27B-omlx" "$AI_LITELLM_CONFIG" | grep -q "max_output_tokens: 16384"
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
for k in config settings baseUrl health configCurrency reasoningEffortCeiling reasoningEffortTransport log pid pidFile lock; do
  assert_json_key "proxy status --json" "$ps_json" "$k"
done
print -r -- "$ps_json" | jq -e ".reasoningEffortCeiling == \"high\" and (.reasoningEffortTransport | contains(\"xhigh-max-to-high\"))" >/dev/null
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
print -r -- "$m_allowed" | node -e "let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const a=JSON.parse(s);if(!Array.isArray(a)||a.length!==1||a[0]!==\"high\"){console.error(\"expected exactly high\");process.exit(1)}})" \
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
# ── durable Claude permission mode round-trip ────────────────────────────────
p_json="$("$HOME/.local/bin/claude-litellm" permissions get --json 2>/dev/null)"
print -r -- "$p_json" | jq -e ".mode == \"default\" and .source == \"package-default\"" >/dev/null \
  || { echo "FAIL: initial permission mode is not the safe package default"; exit 1; }
"$HOME/.local/bin/claude-litellm" permissions set default >/dev/null 2>&1
p_json="$("$HOME/.local/bin/claude-litellm" permissions get --json 2>/dev/null)"
print -r -- "$p_json" | jq -e ".mode == \"default\" and .source == \"user-override\"" >/dev/null \
  || { echo "FAIL: explicit safe permission override did not retain its source"; exit 1; }
"$HOME/.local/bin/claude-litellm" permissions set bypassPermissions >/dev/null 2>&1
p_json="$("$HOME/.local/bin/claude-litellm" permissions get --json 2>/dev/null)"
print -r -- "$p_json" | jq -e ".mode == \"bypassPermissions\" and .source == \"user-override\"" >/dev/null \
  || { echo "FAIL: persistent bypass permission mode did not activate"; exit 1; }
test "$(jq -r ".harness.permissionMode" "$HOME/.config/claude-litellm/settings.json")" = "bypassPermissions"
test "$(jq -r ".permissions.defaultMode" "$HOME/.local/share/claude-litellm/state/claude-litellm/overlay-settings-proxy.json")" = "bypassPermissions"
permission_settings_backup="$HOME/permission-settings.backup"
cp -p "$HOME/.config/claude-litellm/settings.json" "$permission_settings_backup"
jq ".harness.permissionMode = true" "$permission_settings_backup" > "$HOME/.config/claude-litellm/settings.json.tmp"
chmod 600 "$HOME/.config/claude-litellm/settings.json.tmp"
mv "$HOME/.config/claude-litellm/settings.json.tmp" "$HOME/.config/claude-litellm/settings.json"
if "$HOME/.local/bin/claude-litellm" permissions get --json >/dev/null 2>&1; then
  echo "FAIL: malformed present permission mode was treated as absent"; exit 1
fi
cp -p "$permission_settings_backup" "$HOME/.config/claude-litellm/settings.json"
rm -f "$permission_settings_backup"
if "$HOME/.local/bin/claude-litellm" permissions set plan >/dev/null 2>&1; then
  echo "FAIL: unsupported persistent permission mode was accepted"; exit 1
fi
if "$HOME/.local/bin/claude-litellm" permissions set bypassPermissions typo >/dev/null 2>&1; then
  echo "FAIL: permission mutation accepted trailing arguments"; exit 1
fi
if "$HOME/.local/bin/claude-litellm" permissions get --json typo >/dev/null 2>&1; then
  echo "FAIL: permission read accepted trailing arguments"; exit 1
fi
test "$(jq -r ".harness.permissionMode" "$HOME/.config/claude-litellm/settings.json")" = "bypassPermissions"
"$HOME/.local/bin/claude-litellm" permissions reset >/dev/null 2>&1
p_json="$("$HOME/.local/bin/claude-litellm" permissions get --json 2>/dev/null)"
print -r -- "$p_json" | jq -e ".mode == \"default\" and .source == \"package-default\"" >/dev/null \
  || { echo "FAIL: permission reset did not restore the package default"; exit 1; }
test "$(jq -r ".harness.permissionMode // empty" "$HOME/.config/claude-litellm/settings.json")" = ""
test "$(jq -r ".permissions.defaultMode" "$HOME/.local/share/claude-litellm/state/claude-litellm/overlay-settings-proxy.json")" = "default"
test "$("$HOME/.local/bin/claude-litellm" harness alias get claude --json | jq -r ".[] | select(.tier == \"fable\") | .model")" = "$orig"
echo "ok: persistent Claude permission mode set/get/reset"
# R2 review: the dashboard pipes a newline-less secret to key set via stdin; zsh
# read returns nonzero on EOF-without-newline, which used to abort key set and
# store nothing. Verify the read tolerates it. Use --env-file with an isolated
# attacker-selected root as well: installed mode must ignore those path
# overrides and write only its trusted private env. This HOME and installation
# are test-isolated; preserve the original env so later checks see no test key.
ks_proxy="$HOME/key-set-check-$$"
ks_env_file="$AI_LITELLM_ENV"
ks_env_backup="$HOME/key-set-env-backup-$$"
cp -p "$ks_env_file" "$ks_env_backup"
printf "%s" "pipe-no-newline-value-r2" | AI_LITELLM_PROXY_HOME="$ks_proxy" AI_LITELLM_ENV="$ks_proxy/env" "$HOME/.local/bin/claude-litellm" key set --env-file CHECKR2 >/dev/null 2>&1 \
  || { echo "FAIL: key set aborted on a newline-less piped secret"; mv "$ks_env_backup" "$ks_env_file"; rm -rf "$ks_proxy"; exit 1; }
grep -q "pipe-no-newline-value-r2" "$ks_env_file" \
  || { echo "FAIL: key set did not store the newline-less piped secret"; mv "$ks_env_backup" "$ks_env_file"; rm -rf "$ks_proxy"; exit 1; }
test ! -e "$ks_proxy/env" \
  || { echo "FAIL: installed key set honored an untrusted credential path override"; mv "$ks_env_backup" "$ks_env_file"; rm -rf "$ks_proxy"; exit 1; }
ks_multiline_value="$(printf "first\nsecond")"
if AI_LITELLM_PROXY_HOME="$ks_proxy" AI_LITELLM_ENV="$ks_proxy/env" "$HOME/.local/bin/claude-litellm" key set --env-file CHECKR2 "$ks_multiline_value" >/dev/null 2>&1; then
  echo "FAIL: key set accepted a multiline env credential"; mv "$ks_env_backup" "$ks_env_file"; rm -rf "$ks_proxy"; exit 1
fi
mv "$ks_env_backup" "$ks_env_file"
rm -rf "$ks_proxy"
echo "ok: key set stores newline-less piped secret in trusted state only"
# ── Public help: the single command documents launch, OAuth, and controls ──
usage_out="$("$HOME/.local/bin/claude-litellm" --help 2>&1)"
[[ "$usage_out" == *"fable|opus|sonnet|haiku|model_name"* ]] || { echo "FAIL: public help missing launch models" >&2; exit 1; }
[[ "$usage_out" == *"auth login|status|logout"* ]]            || { echo "FAIL: public help missing OAuth controls" >&2; exit 1; }
[[ "$usage_out" == *"status|doctor|sync|proxy|model|task|key"* ]] || { echo "FAIL: public help missing control nouns" >&2; exit 1; }
[[ "$usage_out" == *"task create|handoff|launch|complete"* ]] || { echo "FAIL: public help missing task orchestration" >&2; exit 1; }
[[ "$usage_out" == *"All providers and local runtimes"* ]]    || { echo "FAIL: public help missing proxy contract" >&2; exit 1; }
echo "ok: public help surface"

# Task handoffs normalize presets to concrete catalog routes and keep their
# durable ledger private. A failed local live probe blocks the worker before
# Claude starts; a passing probe launches in the recorded worktree.
task_worktree="$HOME/task-worktree"
mkdir -p "$task_worktree"
task_id="$("$HOME/.local/bin/claude-litellm" task create smoke \
  --goal task_handoff_smoke --worktree "$task_worktree")"
"$HOME/.local/bin/claude-litellm" task handoff "$task_id" \
  --to haiku --objective review_local_route --summary prior_worker_done >/dev/null
task_plan="$("$HOME/.local/bin/claude-litellm" task prompt "$task_id" --json)"
[[ "$(print -r -- "$task_plan" | jq -r .route)" == "Qwen3.6-27B-omlx" ]] || { echo "FAIL: task handoff did not normalize preset route" >&2; exit 1; }
[[ "$(print -r -- "$task_plan" | jq -r .worktree)" == "$task_worktree" ]] || { echo "FAIL: task handoff lost worktree" >&2; exit 1; }
test "$(stat -f %Lp "$prefix/state/claude-litellm/tasks")" = "700"
test "$(stat -f %Lp "$prefix/state/claude-litellm/tasks/$task_id.json")" = "600"
(
  source "$prefix/config/claude-litellm/shell.zsh"
  ai_litellm_model_runtime() { print -r -- omlx; }
  ai_litellm_model_runtime_ready() { return 0; }
  ai_litellm_start() { return 0; }
  ai_litellm_probe_route() { return 1; }
  _claude_litellm_launch_proxy() { echo "FAIL: worker launched after failed local probe" >&2; return 99; }
  ! claude-litellm task launch "$task_id" -- --print >/dev/null 2>&1
)
task_launch_out="$(
  source "$prefix/config/claude-litellm/shell.zsh"
  ai_litellm_model_runtime() { print -r -- omlx; }
  ai_litellm_model_runtime_ready() { return 0; }
  ai_litellm_start() { return 0; }
  ai_litellm_probe_route() { return 0; }
  _claude_litellm_launch_proxy() { local route="$1"; shift; print -r -- "launch:$route:$PWD:$*"; }
  claude-litellm task launch "$task_id" -- --print
)"
[[ "$task_launch_out" == *"launch:Qwen3.6-27B-omlx:$task_worktree:"* ]] || { echo "FAIL: task worker did not launch concrete route in worktree" >&2; exit 1; }
[[ "$task_launch_out" == *"review_local_route"* ]] || { echo "FAIL: task worker did not receive bounded handoff prompt" >&2; exit 1; }
"$HOME/.local/bin/claude-litellm" task complete "$task_id" \
  --summary worker_done --tests focused_tests --close >/dev/null
[[ "$("$HOME/.local/bin/claude-litellm" task show "$task_id" --json | jq -r .status)" == "completed" ]] || { echo "FAIL: task completion did not close ledger" >&2; exit 1; }
echo "ok: model-session task handoff and local readiness gate"

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
# (e.g. thinking-off via extra_body) injected; non-matching routes do NOT. The
# temp overlay below replaces the shipped Qwen policies with one narrow pattern
# so both the positive and negative matcher branches remain observable.
params_settings_tmp="$HOME/omlx-params-test.json"
test -n "$AI_LITELLM_SETTINGS" && test -f "$AI_LITELLM_SETTINGS"  # guard: never let jq fall back to stdin (would hang)
# The shipped policy applies thinking-off to both Qwen generations. The
# first-class routes carry the same setting even when discovery deduplicates
# them, while generated Qwen3.6 routes receive it from the glob override.
grep -A14 "model_name: Qwen3.6-27B-omlx" "$AI_LITELLM_CONFIG" | grep -q "enable_thinking: false"
grep -A14 "model_name: Qwen3.6-35B-A3B-4bit-omlx" "$AI_LITELLM_CONFIG" | grep -q "enable_thinking: false"
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
limits_json="$("$HOME/.local/bin/claude-litellm" model limits GLM-5.2-openrouter --json)"
print -r -- "$limits_json" | jq -e ".[0].effectiveInput == 1008384 and .[0].outputReservation == 32000 and .[0].tokenizerHeadroom == 8192" >/dev/null
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
print -r -- "{\"data\":[{\"id\":\"moonshotai/kimi-k2.7-code\",\"context_length\":262144,\"top_provider\":{\"context_length\":262144,\"max_completion_tokens\":262144},\"supported_parameters\":[\"reasoning\"],\"reasoning\":{\"mandatory\":true,\"default_enabled\":true}},{\"id\":\"xiaomi/mimo-v2.5\",\"context_length\":262144,\"top_provider\":{\"context_length\":262144},\"supported_parameters\":[\"reasoning\"],\"reasoning\":{\"mandatory\":false}},{\"id\":\"z-ai/glm-5.2\",\"context_length\":1048576,\"top_provider\":{\"context_length\":1048576,\"max_completion_tokens\":32768},\"supported_parameters\":[\"reasoning\",\"reasoning_effort\"],\"reasoning\":{\"mandatory\":false,\"default_enabled\":true,\"supported_efforts\":[\"xhigh\",\"high\"],\"default_effort\":\"high\"}},{\"id\":\"testorg/test-model-x\",\"context_length\":100000,\"top_provider\":{\"context_length\":100000,\"max_completion_tokens\":8000},\"supported_parameters\":[\"reasoning\",\"reasoning_effort\"],\"reasoning\":{\"mandatory\":false,\"supported_efforts\":[\"xhigh\",\"high\",\"max\"]}}]}" > "$openrouter_models_fixture"
export AI_LITELLM_OPENROUTER_MODELS_JSON="$openrouter_models_fixture"
ai_litellm_model_refresh_capabilities --check >/dev/null
capability_transport="$(ai_litellm_model_refresh_capabilities --json)"
print -r -- "$capability_transport" | jq -e \
  "any(.rows[]; .alias == \"glm52\" and .effort.provider == [\"xhigh\",\"high\"] and .effort.effective_provider == [\"high\"] and .effort.configured == [\"high\"] and .effort.status == \"ok\")" >/dev/null
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
effective_effort_plan="$(print -r -- "$add_plan" | sed -n "/x_reasoning_efforts:/,/x_input_confidence:/p")"
[[ "$effective_effort_plan" == *"- high"* && "$effective_effort_plan" != *"xhigh"* && "$effective_effort_plan" != *"- max"* ]]
raw_effort_plan="$(print -r -- "$add_plan" | sed -n "/x_provider_reasoning_efforts:/,/x_reasoning_effort_ceiling:/p")"
[[ "$raw_effort_plan" == *"- xhigh"* && "$raw_effort_plan" == *"- high"* && "$raw_effort_plan" == *"- max"* ]]
print -r -- "$add_plan" | grep -q "x_reasoning_effort_ceiling: high"
# dry-run wrote nothing. if-form, not bare `! grep`: zsh exempts a bare
# negated pipeline from set -e/ERR_EXIT, which would make this assertion
# silently vacuous (see the ~L395 comment on the same hazard).
if grep -q "Test-Model-X-openrouter" "$AI_LITELLM_CONFIG"; then echo "FAIL: model add --dry-run wrote to the registry"; exit 1; fi
if AI_LITELLM_OPENROUTER_MODELS_JSON="$openrouter_models_fixture" \
  "$HOME/.local/bin/claude-litellm" model add testorg/test-model-x --name --dry-run >/dev/null 2>&1; then
  echo "FAIL: model add swallowed --dry-run as an option value" >&2; exit 1
fi
echo "ok: model add --dry-run plans without writing"
AI_LITELLM_SKIP_SYNC=1 AI_LITELLM_OPENROUTER_MODELS_JSON="$openrouter_models_fixture" "$HOME/.local/bin/claude-litellm" model add testorg/test-model-x --name Test-Model-X-openrouter >/dev/null 2>&1
grep -q "model_name: Test-Model-X-openrouter" "$AI_LITELLM_CONFIG"
grep -q "max_input_tokens: 100000" "$AI_LITELLM_CONFIG"
ai_litellm_ruby -ryaml -e "(YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))" "$AI_LITELLM_CONFIG"   # still valid YAML w/ aliases
user_capabilities="$(ai_litellm_model_refresh_capabilities --json)"
print -r -- "$user_capabilities" | jq -e \
  "any(.rows[]; .scope == \"user-overlay\" and .alias == \"Test-Model-X-openrouter\" and .input.status == \"ok\" and .effort.provider == [\"xhigh\",\"high\",\"max\"] and .effort.effective_provider == [\"high\"] and .effort.configured == [\"high\"] and .effort.status == \"ok\")" >/dev/null
user_drift_fixture="$HOME/openrouter-models-user-drift.json"
jq "(.data[] | select(.id == \"testorg/test-model-x\") | .top_provider.context_length) = 99999" \
  "$openrouter_models_fixture" > "$user_drift_fixture"
if AI_LITELLM_OPENROUTER_MODELS_JSON="$user_drift_fixture" \
  ai_litellm_model_refresh_capabilities --check >/dev/null 2>&1; then
  echo "FAIL: user-overlay OpenRouter capability drift was not audited" >&2; exit 1
fi
AI_LITELLM_SKIP_SYNC=1 "$HOME/.local/bin/claude-litellm" model remove Test-Model-X-openrouter >/dev/null 2>&1
# revert check. if-form for the same zsh set-e/bare-! reason as above.
if grep -q "Test-Model-X-openrouter" "$AI_LITELLM_CONFIG"; then echo "FAIL: model remove did not revert the registry"; exit 1; fi
echo "ok: model add/remove round-trip and user capability-drift audit"
# Arbitrary LiteLLM/OpenAI-compatible providers use the explicit register path;
# credentials are references, never literal values.
register_plan="$("$HOME/.local/bin/claude-litellm" model register Test-Local-openai \
  --backend openai/test-local --context 32768 --output 4096 \
  --api-base http://127.0.0.1:9999/v1 --api-key-env none --dry-run 2>&1)"
[[ "$register_plan" == *"model_name: Test-Local-openai"* ]]
if grep -q "Test-Local-openai" "$AI_LITELLM_CONFIG"; then echo "FAIL: model register --dry-run wrote"; exit 1; fi
if "$HOME/.local/bin/claude-litellm" model register Missing-Key-openai \
  --backend openai/missing-key --context 32768 --output 4096 --dry-run >/dev/null 2>&1; then
  echo "FAIL: model register accepted an implicit ambient provider credential" >&2; exit 1
fi
if "$HOME/.local/bin/claude-litellm" model register Swallowed-Dry-Run \
  --context 32768 --output 4096 --api-key-env none --backend --dry-run >/dev/null 2>&1; then
  echo "FAIL: model register swallowed --dry-run and performed an apply path" >&2; exit 1
fi
if "$HOME/.local/bin/claude-litellm" model register Reserved-Key-openai \
  --backend openai/reserved-key --context 32768 --output 4096 \
  --api-key-env LITELLM_MASTER_KEY --dry-run >/dev/null 2>&1; then
  echo "FAIL: model register accepted the gateway master key as a provider credential" >&2; exit 1
fi
for reserved_surface in use permissions opus; do
  if "$HOME/.local/bin/claude-litellm" model register "$reserved_surface" \
    --backend openai/reserved-surface --context 32768 --output 4096 \
    --api-key-env none --dry-run >/dev/null 2>&1; then
    echo "FAIL: model register accepted reserved CLI surface $reserved_surface" >&2; exit 1
  fi
done
for blocked_effort in xhigh max; do
  if "$HOME/.local/bin/claude-litellm" model register Blocked-Effort-openai \
    --backend openai/blocked-effort --context 32768 --output 4096 \
    --api-key-env none --reasoning-efforts "$blocked_effort" --dry-run >/dev/null 2>&1; then
    echo "FAIL: model register exposed normalized effort $blocked_effort" >&2
    exit 1
  fi
done
AI_LITELLM_SKIP_SYNC=1 "$HOME/.local/bin/claude-litellm" model register Test-Local-openai \
  --backend openai/test-local --context 32768 --output 4096 \
  --api-base http://127.0.0.1:9999/v1 --api-key-env TEST_LOCAL_PROVIDER_KEY >/dev/null
grep -q "model_name: Test-Local-openai" "$AI_LITELLM_CONFIG"
TEST_LOCAL_PROVIDER_KEY=must-not-reach-claude \
  ai_litellm_harness_exec_env claude -- sh -c "test -z \"\${TEST_LOCAL_PROVIDER_KEY:-}\""
harness_argv_secret="harness-argv-secret-$$-quote\"-slash\\"
ai_litellm_harness_exec_env claude "ANTHROPIC_AUTH_TOKEN=$harness_argv_secret" -- sh -c "
  test -n \"\$ANTHROPIC_AUTH_TOKEN\"
  command_line=\"\$(ps -ww -o command= -p \$\$)\"
  case \"\$command_line\" in
    *\"\$ANTHROPIC_AUTH_TOKEN\"*) exit 91 ;;
  esac
"
harness_env_function="$(typeset -f ai_litellm_harness_exec_env)"
[[ "$harness_env_function" != *"exec env "* ]] || {
  echo "FAIL: harness secrets still pass through env argv" >&2; exit 1
}
malformed_registry="$HOME/malformed-provider-registry.yaml"
print -r -- "model_list: [unterminated" > "$malformed_registry"
if AI_LITELLM_CONFIG="$malformed_registry" TEST_LOCAL_PROVIDER_KEY=must-not-reach-claude \
  ai_litellm_harness_exec_env claude -- sh -c "exit 0" >/dev/null 2>&1; then
  echo "FAIL: malformed registry disabled dynamic provider-secret isolation" >&2; exit 1
fi
malformed_harnesses="$HOME/malformed-harnesses"
mkdir -p "$malformed_harnesses"
print -r -- "{" > "$malformed_harnesses/claude.json"
if AI_LITELLM_HARNESSES_DIR="$malformed_harnesses" OPENAI_API_KEY=must-not-reach-claude \
  ai_litellm_harness_exec_env claude -- sh -c "exit 0" >/dev/null 2>&1; then
  echo "FAIL: malformed harness disabled its static environment scrub policy" >&2; exit 1
fi
bad_overlay="$HOME/bad-user-models.json"
print -r -- "{\"schemaVersion\":1,\"models\":[{\"model_name\":\"Unsafe\",\"litellm_params\":{\"model\":\"openai/unsafe\",\"api_key\":\"literal-secret\"},\"model_info\":{\"max_input_tokens\":1,\"max_output_tokens\":1,\"supports_reasoning\":false,\"x_reasoning_efforts\":[]}}]}" > "$bad_overlay"
chmod 600 "$bad_overlay"
sync_side_effect="$HOME/unsafe-sync-side-effect"
config_before_bad_sync="$(shasum -a 256 "$AI_LITELLM_CONFIG" | awk "{print \$1}")"
(
  export AI_LITELLM_USER_MODELS="$bad_overlay"
  ai_litellm_runtime_routes_refresh() { : > "$sync_side_effect"; }
  ai_litellm_restart() { : > "$sync_side_effect"; }
  if ai_litellm_sync >/dev/null 2>&1; then
    echo "FAIL: sync accepted an unsafe user overlay" >&2; exit 1
  fi
)
test ! -e "$sync_side_effect"
test "$(shasum -a 256 "$AI_LITELLM_CONFIG" | awk "{print \$1}")" = "$config_before_bad_sync"
test ! -e "$AI_LITELLM_USER_CONFIG_HOME/.mutation.lock"
test ! -e "$AI_LITELLM_PROXY_HOME/litellm.sync.lock"
AI_LITELLM_SKIP_SYNC=1 "$HOME/.local/bin/claude-litellm" model remove Test-Local-openai >/dev/null
if grep -q "Test-Local-openai" "$AI_LITELLM_CONFIG"; then echo "FAIL: registered model remove did not revert"; exit 1; fi
echo "ok: arbitrary provider registration is explicit and its secret is scrubbed from Claude"
# GLM-5.2-openrouter is the opus tier alias in the installed config under test
# (config/claude-litellm/settings.json aliases.opus); removing it must refuse.
if AI_LITELLM_SKIP_SYNC=1 "$HOME/.local/bin/claude-litellm" model remove GLM-5.2-openrouter >/dev/null 2>&1; then echo "FAIL: removed a tier-referenced model"; exit 1; fi
echo "ok: model remove refuses tier-referenced surface"
if AI_LITELLM_SKIP_SYNC=1 "$HOME/.local/bin/claude-litellm" model reasoning set GLM-5.2-openrouter high >/dev/null 2>&1; then
  echo "FAIL: mutated a package-owned model default"; exit 1
fi
echo "ok: package model reasoning defaults are immutable"
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$prefix/config" \
  AI_LITELLM_CONFIG="$prefix/config/litellm_config.yaml" "$CHECK_PYTHON" - <<'"'"'PY'"'"'
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
tool_history = {
    "messages": [{
        "role": "assistant",
        "content": None,
        "tool_calls": [{
            "id": "call_large",
            "type": "function",
            "function": {"name": "write_blob", "arguments": "x" * 900000},
        }],
    }],
    "max_tokens": 128,
}
tool_blocked = gateway_cost_guardrail_decision(tool_history)
assert tool_blocked["allowed"] is False
assert tool_blocked["estimated_input_tokens"] >= 225000
try:
    enforce_cost_guardrail(large)
except Exception as exc:
    assert "cost guardrail rejected" in str(exc)
else:
    raise AssertionError("large request was not rejected by cost guardrail")
PY
ai_litellm_context_observations DeepSeek >/dev/null
budget="$(ai_litellm_harness_output_budget claude sonnet Mimo-V2.5-openrouter)"
test "$(print -r -- "$budget" | jq -r ".effectiveInput == 237568 and .reservation == 16384 and .reservation == .capability")" = "true"
fable_budget="$(ai_litellm_harness_output_budget claude fable Kimi-K2.7-Code-openrouter)"
test "$(print -r -- "$fable_budget" | jq -r ".effectiveInput == 221952 and .reservation == 32000")" = "true"
ai_litellm_render_claude_settings claude
claude_settings_proxy="$(ai_litellm_harness_json claude paths.settingsArgProxy)"
test -f "$claude_settings_proxy"
jq empty "$claude_settings_proxy"
test "$(jq -r ".enableWorkflows == true and .skipWorkflowUsageWarning == true" "$claude_settings_proxy")" = "true"
test "$(jq -r ".permissions.defaultMode" "$claude_settings_proxy")" = "default"
test "$(stat -f %Lp "$claude_settings_proxy")" = "600"
# A descriptor with no generated-settings fields must write the exact empty
# object. This covers both sides of the zsh JSON-default regression: the normal
# non-empty payload above must not gain a trailing brace, while an absent
# payload must still become `{}`.
empty_settings_harnesses="$HOME/empty-settings-harnesses"
mkdir -p "$empty_settings_harnesses"
jq "del(.adapterConfig.generatedSettings, .adapterConfig.generatedSettingsProxy)" \
  "$AI_LITELLM_HARNESSES_DIR/claude.json" > "$empty_settings_harnesses/claude.json"
empty_settings_proxy="$HOME/empty-generated-settings.json"
(
  export AI_LITELLM_HARNESSES_DIR="$empty_settings_harnesses"
  ai_litellm_render_claude_settings claude "$empty_settings_proxy" "$empty_settings_proxy"
  if ai_litellm_permissions_get --json >/dev/null 2>&1; then
    echo "FAIL: permission read succeeded without a generated permission slot"; exit 1
  fi
  if ai_litellm_permissions_update set default >/dev/null 2>&1; then
    echo "FAIL: permission set succeeded without a generated permission slot"; exit 1
  fi
  if ai_litellm_permissions_update reset >/dev/null 2>&1; then
    echo "FAIL: permission reset succeeded without a generated permission slot"; exit 1
  fi
)
test "$(jq -c . "$empty_settings_proxy")" = "{}"
# Upgrade regression: rendering must repair a stale proxy overlay left by an
# older release. Pre-seed the unsafe value, render again, and require an
# explicit downgrade while discarding unrelated state from this generated-only file.
print -r -- "{\"permissions\":{\"defaultMode\":\"bypassPermissions\"},\"env\":{\"KEEP_ME\":\"yes\"}}" > "$claude_settings_proxy"
ai_litellm_render_claude_settings claude
test "$(jq -r ".permissions.defaultMode" "$claude_settings_proxy")" = "default"
test "$(jq -r ".env.KEEP_ME // empty" "$claude_settings_proxy")" = ""
test "$(stat -f %Lp "$claude_settings_proxy")" = "600"
echo "ok: stale Claude proxy overlay is forcibly downgraded"
lint_root="$HOME/lint-claude"
mkdir -p "$lint_root"
print -r -- "{\"env\":{\"ANTHROPIC_BASE_URL\":\"http://127.0.0.1:1\"}}" > "$lint_root/settings.json"
if ai_litellm_claude_shared_settings_lint claude "$lint_root" 2>/dev/null; then
  echo "FAIL: shared Claude settings lint accepted a backend-routing key" >&2
  exit 1
fi
print -r -- "{\"permissions\":{\"defaultMode\":\"bypassPermissions\"},\"env\":{\"BRAVE_SEARCH_API_KEY\":\"x\"}}" > "$lint_root/settings.json"
ai_litellm_claude_shared_settings_lint claude "$lint_root" 2>/dev/null
print -r -- "{\"model\":\"~anthropic/claude-opus-latest\"}" > "$lint_root/settings.json"
lint_warning="$(ai_litellm_claude_shared_settings_lint claude "$lint_root" 2>&1)"
[[ "$lint_warning" == *"warning"* ]]
rm -rf "$lint_root"
echo "ok: shared Claude settings lint"
source "$prefix/config/claude-litellm/shell.zsh"
python_shadow_root="$HOME/python-shadow"
python_shadow_cwd="$python_shadow_root/cwd"
python_shadow_path="$python_shadow_root/path"
python_shadow_sentinel="$python_shadow_root/SHADOWED"
mkdir -p "$python_shadow_cwd" "$python_shadow_path/ai_litellm_callbacks"
shadow_code="from pathlib import Path; Path(\"$python_shadow_sentinel\").write_text(\"shadowed\")"
for shadow_module in litellm fastapi yaml prisma uvicorn; do
  print -r -- "$shadow_code" > "$python_shadow_cwd/$shadow_module.py"
  print -r -- "$shadow_code" > "$python_shadow_path/$shadow_module.py"
done
print -r -- "$shadow_code" > "$python_shadow_path/ai_litellm_callbacks/__init__.py"
print -r -- "$shadow_code
PATCH_ACTIVE = True" > "$python_shadow_path/ai_litellm_callbacks/oauth_guard.py"
(
  cd "$python_shadow_cwd"
  export PYTHONPATH="$python_shadow_path"
  ai_litellm_litellm_python >/dev/null
  ai_litellm_install_integrity_ok
  _claude_litellm_oauth_doctor >/dev/null
)
test ! -e "$python_shadow_sentinel"
echo "ok: managed Python imports ignore cwd and ambient PYTHONPATH"
test "$(_claude_litellm_proxy_default_request)" = "opus"
test "$(_claude_litellm_target_model_for_request "")" = "GLM-5.2-openrouter"
test "$(_claude_litellm_target_model_for_request openrouter/z-ai/glm-5.2)" = "GLM-5.2-openrouter"
test "$(_claude_litellm_resolve_model_arg openrouter/z-ai/glm-5.2)" = "GLM-5.2-openrouter"
(
  _claude_litellm_launch_proxy() { print -r -- "proxy:$1"; }
  test "$(claude-litellm sonnet)" = "proxy:sonnet"
  test "$(claude-litellm openrouter/z-ai/glm-5.2)" = "proxy:openrouter/z-ai/glm-5.2"
  test "$(claude-litellm use sonnet)" = "proxy:sonnet"
  test "$(claude-litellm use openrouter/z-ai/glm-5.2)" = "proxy:openrouter/z-ai/glm-5.2"
  # An unresolvable leading model selector must fail before the launcher so it
  # can never leak into Claude Code as a prompt.
  ! claude-litellm Qwen3.6-35B-omlx >/dev/null 2>&1
  claude-litellm Qwen3.6-35B-omlx 2>&1 | grep -q "is not a selectable model"
  ! claude-litellm h35 >/dev/null 2>&1
  ! claude-litellm not-a-real-model >/dev/null 2>&1
  test "$(claude-litellm Qwen3.6-27B-omlx)" = "proxy:Qwen3.6-27B-omlx"
)
echo "ok: proxy-only model selector guards"
(
  _claude_litellm_launch_proxy() { print -r -- "proxy:${(j:|:)@}"; }
  test "$(claude-litellm use sonnet -p hello_world)" = "proxy:sonnet|-p|hello_world"
  ! claude-litellm use >/dev/null 2>&1
  ! claude-litellm use not-a-real-model >/dev/null 2>&1
)
(
  _claude_litellm_launch_proxy() { echo "unexpected launch" >&2; return 99; }
  _claude_litellm_proxy_default_request() { print -r -- "sonnet"; }
  ai_litellm() { print -r -- "control:${(j:|:)@}"; }
  use_default_output="$(claude-litellm use GLM-5.2-openrouter --default)"
  [[ "$use_default_output" == *"control:model|qualify|GLM-5.2-openrouter|--activate-tier|sonnet"* ]]
  [[ "$use_default_output" == *"to launch it."* ]]
  ! claude-litellm use sonnet --default >/dev/null 2>&1
  ! claude-litellm use GLM-5.2-openrouter --default -p nope >/dev/null 2>&1
)
echo "ok: explicit use command launches or safely qualifies the dynamic default preset"
# The selector checks above deliberately replace the complete launch function,
# which also owns effort validation. Exercise the real validator directly here
# instead of accidentally asserting against that test double.
_claude_litellm_validate_effort GLM-5.2-openrouter --effort high -p noop
if _claude_litellm_validate_effort GLM-5.2-openrouter --effort xhigh -p noop >/dev/null 2>&1; then
  echo "FAIL: normalized GLM xhigh passed launch validation" >&2
  exit 1
fi
if claude-litellm Kimi-K2.7-Code-openrouter --effort high -p noop >/dev/null 2>&1; then
  echo "FAIL: explicit effort reached a Kimi launch without configurable-effort support" >&2
  exit 1
fi
claude-litellm Kimi-K2.7-Code-openrouter --effort high -p noop 2>&1 | grep -q "does not expose selectable effort levels"
(
  ai_litellm_model_reasoning_allowed_efforts() { print -r -- "minimal low"; }
  if _claude_litellm_validate_effort Synthetic-route --effort minimal >/dev/null 2>&1; then
    echo "FAIL: Claude Code-incompatible minimal effort passed wrapper validation" >&2; exit 1
  fi
  _claude_litellm_validate_effort Synthetic-route --effort low
)
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
  print -r -- "print -r -- \"no_proxy=\$NO_PROXY\""
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
    OPENROUTER_API_KEY=PLACEHOLDER_LAUNCH PATH="$stub_dir:$PATH" claude-litellm sonnet -p noop
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
proxy_expect "base=http://127.0.0.1:$(ai_litellm_port)"
proxy_expect "auth=set"
proxy_expect "api_key_set=1"
proxy_expect "api_key_value="
proxy_expect "discovery=1"
proxy_expect "attribution=0"
proxy_expect "no_proxy="
proxy_expect "127.0.0.1"
proxy_expect "max_tokens_set=1"
proxy_expect "sonnet=Mimo-V2.5-openrouter"
proxy_expect "sonnet_name=Mimo-V2.5-openrouter"
proxy_expect "haiku=Mimo-V2.5-openrouter"
proxy_expect "haiku_name=Mimo-V2.5-openrouter"
proxy_expect "subagent="
proxy_expect "caps=0:"
proxy_expect "--model sonnet"
proxy_expect "--settings ${CLAUDE_LITELLM_SETTINGS_ARG_PROXY:h}/.overlay-settings-launch."
if find "${CLAUDE_LITELLM_SETTINGS_ARG_PROXY:h}" -maxdepth 1 -name ".overlay-settings-launch.*" | grep -q .; then
  echo "FAIL: per-launch Claude settings snapshot was not removed" >&2
  exit 1
fi
echo "ok: proxy launcher injects isolated routing environment"
# A launch freezes its permission policy into a private snapshot. A concurrent
# durable update may replace the shared generated overlay, but it must not
# retroactively change the already-prepared session.
ai_litellm_permissions_update reset >/dev/null
_claude_litellm_launch_prepare
permission_snapshot="$CLAUDE_LITELLM_LAUNCH_SETTINGS_ARG"
test "$(jq -r ".permissions.defaultMode" "$permission_snapshot")" = "default"
ai_litellm_permissions_update set bypassPermissions >/dev/null 2>&1
test "$(jq -r ".permissions.defaultMode" "$CLAUDE_LITELLM_SETTINGS_ARG_PROXY")" = "bypassPermissions"
test "$(jq -r ".permissions.defaultMode" "$permission_snapshot")" = "default"
rm -f "$permission_snapshot"
typeset -g CLAUDE_LITELLM_LAUNCH_SETTINGS_ARG=""
ai_litellm_permissions_update reset >/dev/null
echo "ok: launch permission snapshot is stable across concurrent policy changes"
for forbidden in --model=Kimi-K2.7-Code-openrouter --settings=/tmp/attacker.json --fallback-model=Kimi-K2.7-Code-openrouter; do
  if (
    ai_litellm_model_runtime_ready() { return 0; }
    ai_litellm_start() { echo "unexpected proxy start" >&2; return 99; }
    ai_litellm_master_key() { print -r -- "sk-test-master"; }
    OPENROUTER_API_KEY=PLACEHOLDER_LAUNCH PATH="$stub_dir:$PATH" claude-litellm sonnet "$forbidden" -p noop
  ) >/dev/null 2>&1; then
    echo "FAIL: proxy launcher accepted wrapper-owned argument $forbidden" >&2
    exit 1
  fi
done
echo "ok: proxy launcher rejects model/settings override bypasses before startup"
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
  OPENROUTER_API_KEY=PLACEHOLDER_LAUNCH PATH="$stub_dir:$PATH" claude-litellm sonnet -p noop
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
  mig_output="$(OPENROUTER_API_KEY=PLACEHOLDER_LAUNCH PATH="$stub_dir:$PATH" CLAUDE_LITELLM_CLAUDE_CONFIG="$mig_config" claude-litellm sonnet -p noop 2>&1)"
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
  stale_output="$(OPENROUTER_API_KEY=PLACEHOLDER_LAUNCH PATH="$stub_dir:$PATH" CLAUDE_LITELLM_SETTINGS_ARG_PROXY="$CLAUDE_LITELLM_CLAUDE_CONFIG/settings.json" claude-litellm sonnet -p noop 2>&1)"
  # The descriptor-owned canonical path check runs before the narrower
  # shared-directory fallback, so this caller override is reported as
  # non-canonical and replaced with the same safe outside path.
  [[ "$stale_output" == *"ignoring non-canonical proxy settings path"* ]] || {
    echo "FAIL: stale proxy overlay override was not reported as non-canonical" >&2
    print -r -- "$stale_output" >&2
    exit 1
  }
  [[ "$stale_output" == *"--settings ${CLAUDE_LITELLM_SETTINGS_ARG_PROXY:h}/.overlay-settings-launch."* ]] || {
    echo "FAIL: stale proxy overlay override did not use a canonical-root launch snapshot" >&2
    print -r -- "$stale_output" >&2
    exit 1
  }
  test -L "$prefix/state/claude-litellm/claude-config/settings.json"
)
echo "ok: stale proxy overlay path is canonicalized outside shared config"
ai_litellm_model_limits Qwen3.6-27B-omlx >/dev/null
runtime_routes_dedup="$(ai_litellm_runtime_routes_write omlx 1 Qwen3.6-27B-4bit)"
[[ -z "$runtime_routes_dedup" ]]  # dedup must yield NO route for an upstream a registry entry already serves
"$HOME/.local/bin/claude-litellm" --status >/dev/null
"$HOME/.local/bin/claude-litellm" status --json | jq -e \
  "(.proxy | type == \"object\") and (.oauth | type == \"array\") and (.oauth | length == 2)" >/dev/null
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

# Credential reads must validate both the descriptor they actually open and
# every directory component used to reach it. A leaf symlink, a symlinked
# ancestor, or a group/world-readable file must never become an env source.
unsafe_env_home="$HOME/unsafe-provider-home"
unsafe_env_state_real="$unsafe_env_home/state-real"
unsafe_env_proxy_real="$unsafe_env_state_real/ai-litellm"
unsafe_env_state_link="$unsafe_env_home/state-link"
mkdir -p "$unsafe_env_proxy_real"
chmod 700 "$unsafe_env_home" "$unsafe_env_state_real" "$unsafe_env_proxy_real"
unsafe_env_target="$unsafe_env_proxy_real/env-target"
unsafe_env_link="$unsafe_env_proxy_real/env-link"
unsafe_env_mode="$unsafe_env_proxy_real/env-mode"
print -r -- "UNSAFE_PROVIDER_KEY=must-not-load" > "$unsafe_env_target"
chmod 600 "$unsafe_env_target"
ln -s "$unsafe_env_target" "$unsafe_env_link"
ln -s "$unsafe_env_state_real" "$unsafe_env_state_link"
cp "$unsafe_env_target" "$unsafe_env_mode"
chmod 644 "$unsafe_env_mode"
(
  export AI_LITELLM_LEGACY_ENV="$HOME/missing-legacy-env"
  export AI_LITELLM_LEGACY_CLAUDE_ENV="$HOME/missing-legacy-claude-env"
  export AI_LITELLM_HOME="$unsafe_env_home"
  export AI_LITELLM_STATE_HOME="$unsafe_env_state_real"
  export AI_LITELLM_PROXY_HOME="$unsafe_env_proxy_real"
  export AI_LITELLM_ENV="$unsafe_env_link"
  if ai_litellm_env_value UNSAFE_PROVIDER_KEY >/dev/null 2>&1; then
    echo "FAIL: credential reader followed a symlink" >&2; exit 1
  fi
  if ai_litellm_env_set_value UNSAFE_PROVIDER_KEY changed >/dev/null 2>&1; then
    echo "FAIL: credential writer followed a symlink" >&2; exit 1
  fi
  [[ "$(<"$unsafe_env_target")" == "UNSAFE_PROVIDER_KEY=must-not-load" ]] || {
    echo "FAIL: rejected credential symlink changed its target" >&2; exit 1
  }
  export AI_LITELLM_ENV="$unsafe_env_mode"
  if ai_litellm_env_value UNSAFE_PROVIDER_KEY >/dev/null 2>&1; then
    echo "FAIL: credential reader accepted non-0600 permissions" >&2; exit 1
  fi
  export AI_LITELLM_STATE_HOME="$unsafe_env_state_link"
  export AI_LITELLM_PROXY_HOME="$unsafe_env_state_link/ai-litellm"
  export AI_LITELLM_ENV="$unsafe_env_state_link/ai-litellm/env-target"
  if ai_litellm_env_value UNSAFE_PROVIDER_KEY >/dev/null 2>&1; then
    echo "FAIL: credential reader followed a symlinked ancestor" >&2; exit 1
  fi

  # The managed file is a key/value data format, not shell source. Exact RHS
  # bytes (including quote characters and padding spaces) must survive a
  # descriptor-safe atomic rewrite and read.
  export AI_LITELLM_STATE_HOME="$unsafe_env_state_real"
  export AI_LITELLM_PROXY_HOME="$unsafe_env_proxy_real"
  export AI_LITELLM_ENV="$unsafe_env_proxy_real/env-roundtrip"
  quoted_env_value="\"literal-quotes\""
  spaced_env_value="  literal padding  "
  ai_litellm_env_set_value QUOTED_ENV_VALUE "$quoted_env_value"
  ai_litellm_env_set_value SPACED_ENV_VALUE "$spaced_env_value"
  [[ "$(ai_litellm_env_value QUOTED_ENV_VALUE)" == "$quoted_env_value" ]] || {
    echo "FAIL: credential quotes did not round-trip exactly" >&2; exit 1
  }
  [[ "$(ai_litellm_env_value SPACED_ENV_VALUE)" == "$spaced_env_value" ]] || {
    echo "FAIL: credential padding spaces did not round-trip exactly" >&2; exit 1
  }
  [[ "$(stat -f %Lp "$AI_LITELLM_ENV")" == "600" ]]
  test -z "$(find "$unsafe_env_proxy_real" -maxdepth 1 -name "env-roundtrip.tmp.*" -print -quit)"

  # Only an explicit key miss may consult legacy state. An unexpected reader
  # failure must stop at the higher-priority file.
  mkdir -p "$HOME/.config/ai-litellm"
  print -r -- "LEGACY_FAIL_CLOSED=legacy" > "$HOME/.config/ai-litellm/env"
  chmod 600 "$HOME/.config/ai-litellm/env"
  export AI_LITELLM_LEGACY_ENV="$HOME/.config/ai-litellm/env"
  [[ "$(ai_litellm_env_value LEGACY_FAIL_CLOSED)" == "legacy" ]]
  node_calls=0
  node() { (( node_calls += 1 )); return 1; }
  if ai_litellm_env_value LEGACY_FAIL_CLOSED >/dev/null 2>&1; then
    echo "FAIL: unexpected primary credential read failure fell back to legacy" >&2; exit 1
  fi
  [[ "$node_calls" == "1" ]] || {
    echo "FAIL: unexpected credential reader failure consulted another file" >&2; exit 1
  }
)
rm -rf "$unsafe_env_home"
rm -rf "$HOME/.config/ai-litellm"
echo "ok: provider credential reads reject unsafe leaves and parent chains"

# User-owned model/settings mutations and the renderer must reject a symlinked
# config root or overlay leaf before creating a lock or touching the target.
user_guard_real="$HOME/user-config-guard-real"
user_guard_link="$HOME/user-config-guard-link"
user_guard_outside="$HOME/user-config-guard-outside.json"
mkdir -p "$user_guard_real"
ln -s "$user_guard_real" "$user_guard_link"
print -r -- "{\"schemaVersion\":1,\"models\":[]}" > "$user_guard_outside"
chmod 600 "$user_guard_outside"
(
  export AI_LITELLM_USER_CONFIG_HOME="$user_guard_link"
  export AI_LITELLM_USER_MODELS="$user_guard_link/models.json"
  export AI_LITELLM_USER_CLAUDE_SETTINGS="$user_guard_link/settings.json"
  if ai_litellm_user_mutation_lock_acquire >/dev/null 2>&1; then
    echo "FAIL: user mutation lock followed a symlinked config root" >&2; exit 1
  fi
  if ai_litellm_render_user_config --check >/dev/null 2>&1; then
    echo "FAIL: user config renderer accepted a symlinked config root" >&2; exit 1
  fi
)
test ! -e "$user_guard_real/.mutation.lock"
ln -s "$user_guard_outside" "$user_guard_real/models.json"
(
  export AI_LITELLM_USER_CONFIG_HOME="$user_guard_real"
  export AI_LITELLM_USER_MODELS="$user_guard_real/models.json"
  export AI_LITELLM_USER_CLAUDE_SETTINGS="$user_guard_real/settings.json"
  if ai_litellm_user_mutation_lock_acquire >/dev/null 2>&1; then
    echo "FAIL: user mutation lock followed a symlinked overlay leaf" >&2; exit 1
  fi
  if ai_litellm_render_user_config --check >/dev/null 2>&1; then
    echo "FAIL: user config renderer accepted a symlinked overlay leaf" >&2; exit 1
  fi
)
test ! -e "$user_guard_real/.mutation.lock"
[[ "$(<"$user_guard_outside")" == "{\"schemaVersion\":1,\"models\":[]}" ]]
rm -rf "$user_guard_link" "$user_guard_real" "$user_guard_outside"
echo "ok: user overlay mutations reject symlinked roots and leaves"

# Authenticated curl receives the exact raw key through a stdin header, never
# through curl config syntax or process argv. Quotes and backslashes are data;
# CR/LF is rejected to prevent header injection.
(
  curl_key="quote\"slash\\literal"
  curl() {
    [[ "$1" == "-H" && "$2" == "@-" ]] || return 90
    shift 2
    for curl_arg in "$@"; do
      [[ "$curl_arg" != *"$curl_key"* ]] || return 91
    done
    while IFS= read -r curl_header; do
      print -r -- "$curl_header"
    done
  }
  received_header="$(ai_litellm_curl_auth "$curl_key" sentinel)"
  [[ "$received_header" == "Authorization: Bearer $curl_key" ]] || {
    echo "FAIL: curl auth changed a quoted or backslashed key" >&2; exit 1
  }
  invalid_curl_key="$(printf "line\nbreak")"
  if ai_litellm_curl_auth "$invalid_curl_key" sentinel >/dev/null 2>&1; then
    echo "FAIL: curl auth accepted a newline in the master key" >&2; exit 1
  fi
)
echo "ok: curl auth preserves raw keys without argv exposure"

# Dynamic provider values are shell-builtin exports inside the launcher
# subshell, never NAME=secret arguments to /usr/bin/env. Package imports must
# also stay bytecode-free because exact-tree provenance rejects __pycache__.
start_function="$(typeset -f _ai_litellm_start_unlocked)"
[[ "$start_function" != *"env -u OPENAI_API_KEY -u XAI_API_KEY"* ]] || {
  echo "FAIL: generic provider secrets still pass through env argv" >&2; exit 1
}
[[ "$start_function" == *"export \"\${extra_env_names[\$_extra_index]}=\${extra_env_values[\$_extra_index]}\""* ]] || {
  echo "FAIL: generic provider secret builtin-export path missing" >&2; exit 1
}
test ! -e "$prefix/config/ai_litellm_callbacks/__pycache__"

# The installed lifecycle must use the guarded, prefix-owned single-process
# bootstrap. With no ChatGPT credential it stays healthy, omits only that eager
# OAuth deployment, never writes device state, and remains stoppable by the
# exact PID ownership checks.
rm -f "$prefix/state/auth/chatgpt/auth.json"
(
  cd "$python_shadow_cwd"
  PYTHONPATH="$python_shadow_path" "$HOME/.local/bin/claude-litellm" proxy start >/dev/null
)
test ! -e "$python_shadow_sentinel"
managed_pid="$(<$prefix/state/ai-litellm/litellm.pid)"
managed_command="$(ps -ww -o command= -p "$managed_pid")"
[[ "$managed_command" == *"$prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"* ]]
[[ "$managed_command" != *" -m ai_litellm_callbacks.proxy_bootstrap "* ]]
ai_litellm_health
proxy_models="$(ai_litellm_proxy_model_names)"
[[ "$proxy_models" == *"Qwen3.6-27B-omlx"* ]]
[[ "$proxy_models" == *"Grok-4.5-xai-oauth"* ]]
[[ "$proxy_models" != *"GPT-5.6-Sol-chatgpt-oauth"* ]]
test ! -e "$prefix/state/auth/chatgpt/auth.json"
"$HOME/.local/bin/claude-litellm" proxy stop >/dev/null 2>&1
test ! -e "$prefix/state/ai-litellm/litellm.pid"
! kill -0 "$managed_pid" 2>/dev/null
test ! -e "$prefix/config/ai_litellm_callbacks/__pycache__"
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
  (
    keychain_service="ai-litellm-check-openrouter-$$"
    keychain_placeholder="PLACEHOLDER_KEYCHAIN quote\" slash\\ dollar\$"
    cleanup_keychain_fixture() {
      HOME="$REAL_HOME" security delete-generic-password \
        -s "$keychain_service" -a "$OPENROUTER_KEYCHAIN_ACCOUNT" >/dev/null 2>&1 || true
    }
    trap cleanup_keychain_fixture EXIT
    REAL_HOME="${REAL_HOME:?}" HOME="$REAL_HOME" OPENROUTER_KEYCHAIN_SERVICE="$keychain_service" "$prefix/bin/claude-litellm" key set --keychain openrouter "$keychain_placeholder" >/dev/null 2>/dev/null
    # Account must match what the store call above actually used: this whole
    # script exports OPENROUTER_KEYCHAIN_ACCOUNT (see the zsh -fc env prefix,
    # top of file) to isolate it from the real machine account/key, so the
    # round-trip has to look it up under that same isolated account -- not the
    # real $USER, which is what the store call would use only in the absence
    # of that override.
    test "$(HOME="$REAL_HOME" security find-generic-password -s "$keychain_service" -a "$OPENROUTER_KEYCHAIN_ACCOUNT" -w)" = "$keychain_placeholder"
    if HOME="$REAL_HOME" ai_litellm_keychain_set_value \
      "$keychain_service" "$OPENROUTER_KEYCHAIN_ACCOUNT" "non-ASCII-거부" >/dev/null 2>&1; then
      echo "FAIL: Keychain writer accepted a value it cannot round-trip" >&2
      exit 1
    fi
  )
fi
"$HOME/.local/bin/claude-litellm" uninstall --dry-run >/dev/null
echo "ok: installed uninstall dry-run preserves state and package"
sleep 60 &
foreign_pid=$!
mkdir -p "$HOME/.config/ai-litellm"
print -r -- "$foreign_pid" > "$HOME/.config/ai-litellm/litellm.pid"
! ai_litellm_pid_running
ai_litellm_stop >/dev/null 2>&1 || true
kill -0 "$foreign_pid"
kill "$foreign_pid"
test "$(<"$HOME/.config/ai-litellm/litellm.pid")" = "$foreign_pid"
rm -f "$HOME/.config/ai-litellm/litellm.pid"
echo "ok: legacy PID files cannot claim an unrelated process"
rmdir "$HOME/.config/ai-litellm" "$HOME/.config" 2>/dev/null || true
ai_litellm_restart() { echo "unexpected restart" >&2; return 99; }
sync_output="$(ai_litellm_sync --dry-run)"
[[ "$sync_output" == *"proxy restart skipped"* ]]
[[ "$sync_output" == *"- claude settings"* ]]
echo "ok: sync dry-run leaves proxy stopped"
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
echo "ok: harness diagnostics tolerate a restricted PATH"
test ! -e "$HOME/litellm_config.yaml"
test ! -e "$HOME/.config/ai-litellm"
test -d "$HOME/.config/claude-litellm"
test -f "$HOME/.config/claude-litellm/models.json"
test -f "$HOME/.config/claude-litellm/settings.json"
test "$(stat -f %Lp "$HOME/.config/claude-litellm")" = "700"
test "$(stat -f %Lp "$HOME/.config/claude-litellm/models.json")" = "600"
test "$(stat -f %Lp "$HOME/.config/claude-litellm/settings.json")" = "600"
test ! -e "$HOME/.claude"
'

spaced_prefix="$spaced_home/with space/claude-litellm"
LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-spaced-$$" HOME="$spaced_home" "$repo_root/scripts/install.zsh" --prefix "$spaced_prefix" >/dev/null
HOME="$spaced_home" "$spaced_prefix/bin/claude-litellm" --help >/dev/null
custom_uninstall_plan="$(HOME="$spaced_home" "$spaced_prefix/bin/claude-litellm" uninstall --dry-run)"
quoted_spaced_prefix="${(q)spaced_prefix}"
[[ "$custom_uninstall_plan" == *"$quoted_spaced_prefix"* ]] || {
  echo "FAIL: custom-prefix uninstall plan does not name the shell-quoted package path" >&2
  print -r -- "$custom_uninstall_plan" >&2
  exit 1
}
test ! -e "$spaced_home/.local/bin/claude-litellm"
print -r -- "PROVIDER_SENTINEL=preserve-me" > "$spaced_prefix/state/ai-litellm/env"
chmod 600 "$spaced_prefix/state/ai-litellm/env"

# Reinstall must reduce package-owned roots to the current explicit layout. An
# expected file symlink with byte-identical contents used to hit the cmp fast
# path and survive; a symlinked expected parent directory could redirect every
# subsequent install write outside the prefix. Stale files were also swept into
# the next manifest by the old recursive package scan.
hostile_ai_dir="$spaced_home/hostile-ai-litellm-dir"
mkdir -p "$hostile_ai_dir"
print -r -- "outside-prefix-sentinel" > "$hostile_ai_dir/sentinel"
rm -rf "$spaced_prefix/config/ai-litellm"
ln -s "$hostile_ai_dir" "$spaced_prefix/config/ai-litellm"
hostile_oauth_target="$spaced_home/hostile-oauth.py"
cp "$spaced_prefix/config/claude-litellm/oauth.py" "$hostile_oauth_target"
rm -f "$spaced_prefix/config/claude-litellm/oauth.py"
ln -s "$hostile_oauth_target" "$spaced_prefix/config/claude-litellm/oauth.py"
mkdir -p "$spaced_prefix/config/retired-callback" "$spaced_prefix/scripts/__pycache__"
print -r -- "stale" > "$spaced_prefix/config/retired-callback/old.py"
print -r -- "stale" > "$spaced_prefix/scripts/__pycache__/old.pyc"
print -r -- "stale" > "$spaced_prefix/docs/RETIRED.md"
ln -s "$spaced_home" "$spaced_prefix/docs/hostile-link"

LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-spaced-$$" HOME="$spaced_home" "$repo_root/scripts/install.zsh" --prefix "$spaced_prefix" >/dev/null
grep -qx "PROVIDER_SENTINEL=preserve-me" "$spaced_prefix/state/ai-litellm/env"
grep -Eq '^LITELLM_MASTER_KEY=.+$' "$spaced_prefix/state/ai-litellm/env"
test "$(stat -f %Lp "$spaced_prefix/state/ai-litellm/env")" = "600"
test -d "$spaced_prefix/config/ai-litellm"
test ! -L "$spaced_prefix/config/ai-litellm"
test -f "$spaced_prefix/config/ai-litellm/lib.zsh"
test ! -e "$hostile_ai_dir/lib.zsh"
grep -qx "outside-prefix-sentinel" "$hostile_ai_dir/sentinel"
test -f "$spaced_prefix/config/claude-litellm/oauth.py"
test ! -L "$spaced_prefix/config/claude-litellm/oauth.py"
cmp -s "$hostile_oauth_target" "$repo_root/config/claude-litellm/oauth.py"
test ! -e "$spaced_prefix/config/retired-callback"
test ! -e "$spaced_prefix/scripts/__pycache__"
test ! -e "$spaced_prefix/docs/RETIRED.md"
test ! -e "$spaced_prefix/docs/hostile-link"
test ! -L "$spaced_prefix/docs/hostile-link"
echo "ok: reinstall replaces hostile symlinks and prunes stale package files"
mutable_config="$spaced_prefix/config/litellm_config.yaml"
mutable_settings="$spaced_prefix/config/claude-litellm/settings.json"
install_manifest="$spaced_prefix/install-manifest.json"
user_models="$spaced_home/.config/claude-litellm/models.json"
user_settings="$spaced_home/.config/claude-litellm/settings.json"
sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}
jq -e '
  .schemaVersion == 2 and
  .managedMutableFiles == {} and
  (.runtime.contentFingerprint | type == "string" and test("^[0-9a-f]{64}$")) and
  .userConfig.upgradePolicy == "preserve-and-render-over-package-defaults" and
  ((.packageFiles | keys | sort) == ([
    "bin/claude-litellm",
    "config/ai-litellm/context-observations.json",
    "config/ai-litellm/harnesses/claude.json",
    "config/ai-litellm/harnesses/schema.json",
    "config/ai-litellm/lib.zsh",
    "config/ai-litellm/settings.json",
    "config/ai_litellm_callbacks/__init__.py",
    "config/ai_litellm_callbacks/chatgpt_stream_compat.py",
    "config/ai_litellm_callbacks/oauth_guard.py",
    "config/ai_litellm_callbacks/output_clamp.py",
    "config/ai_litellm_callbacks/proxy_bootstrap.py",
    "config/claude-litellm/oauth.py",
    "config/claude-litellm/settings.base.json",
    "config/claude-litellm/shell.zsh",
    "config/litellm_config.base.yaml",
    "config/python-requirements.in",
    "config/python-requirements.lock",
    "docs/ARCHITECTURE.md",
    "docs/MIGRATION.md",
    "docs/MODEL-RUNBOOK.md",
    "docs/PROVIDERS.md",
    "scripts/migrate-legacy.zsh",
    "scripts/render-user-config.py",
    "scripts/runtime-fingerprint.py",
    "scripts/task-ledger.py",
    "scripts/verify-install.py",
    "scripts/uninstall.zsh",
    "scripts/verify_tool_call_fidelity.py"
  ] | sort))
' "$install_manifest" >/dev/null
echo "ok: manifest hashes the explicit immutable package file set"

installed_integrity_ok() {
  AI_LITELLM_HOME="$spaced_prefix" HOME="$spaced_home" zsh -fc '
    source "$AI_LITELLM_HOME/config/ai-litellm/lib.zsh"
    ai_litellm_install_integrity_ok
  '
}
installed_integrity_ok
typeset -a runtime_litellm_init
runtime_litellm_init=("$spaced_prefix"/runtime/venv/lib/python*/site-packages/litellm/__init__.py(N))
(( ${#runtime_litellm_init[@]} == 1 ))
runtime_package_backup="$(mktemp "$spaced_home/runtime-package-backup.XXXXXX")"
cp -p "$runtime_litellm_init[1]" "$runtime_package_backup"
print -r -- '# claude-litellm integrity tamper probe' >> "$runtime_litellm_init[1]"
if installed_integrity_ok >/dev/null 2>&1; then
  echo "FAIL: installed integrity accepted a tampered runtime package byte" >&2
  exit 1
fi
cp -p "$runtime_package_backup" "$runtime_litellm_init[1]"
rm -f "$runtime_package_backup"
runtime_unlisted_file="${runtime_litellm_init[1]:h:h}/claude_litellm_unlisted_probe.pth"
runtime_pth_sentinel="$spaced_home/runtime-pth-executed"
"$check_python" -c '
import sys
print(f"import pathlib; pathlib.Path({sys.argv[1]!r}).write_text(\"executed\")")
' "$runtime_pth_sentinel" > "$runtime_unlisted_file"
if installed_integrity_ok >/dev/null 2>&1; then
  echo "FAIL: installed integrity accepted an unlisted site-packages file" >&2
  exit 1
fi
test ! -e "$runtime_pth_sentinel"
rm -f "$runtime_unlisted_file"
installed_integrity_ok
echo "ok: runtime fingerprint rejects byte tampering and unlisted .pth before site initialization"

# Durable state differs from rebuildable package roots: a symlinked ancestor
# must fail before any package byte changes instead of being followed or pruned.
state_auth_real="$spaced_prefix/state/auth.real-check"
state_auth_external="$spaced_home/hostile-auth-target"
mkdir -p "$state_auth_external"
print -r -- "auth-target-sentinel" > "$state_auth_external/sentinel"
mv "$spaced_prefix/state/auth" "$state_auth_real"
ln -s "$state_auth_external" "$spaced_prefix/state/auth"
manifest_before_state_guard="$(sha256_file "$install_manifest")"
config_before_state_guard="$(sha256_file "$mutable_config")"
if LITELLM_MASTER_KEY= HOME="$spaced_home" "$repo_root/scripts/install.zsh" \
  --prefix "$spaced_prefix" >/dev/null 2>&1; then
  echo "FAIL: reinstall followed a symlinked durable-state ancestor" >&2
  exit 1
fi
test "$(sha256_file "$install_manifest")" = "$manifest_before_state_guard"
test "$(sha256_file "$mutable_config")" = "$config_before_state_guard"
grep -qx "auth-target-sentinel" "$state_auth_external/sentinel"
test ! -e "$state_auth_external/chatgpt"
test ! -e "$state_auth_external/grok"
rm -f "$spaced_prefix/state/auth"
mv "$state_auth_real" "$spaced_prefix/state/auth"
echo "ok: installer fails closed on symlinked durable-state ancestors"

# The public command lives outside the package prefix, so exercise its part of
# the same pre-commit transaction explicitly. A byte-different existing shim
# must return with its original bytes, inode, and mode after the failpoint.
default_public_shim="$tmp_home/.local/bin/claude-litellm"
print -r -- '# PUBLIC-SHIM-ROLLBACK-SENTINEL' >> "$default_public_shim"
public_shim_sha="$(sha256_file "$default_public_shim")"
public_shim_inode="$(stat -f %i "$default_public_shim")"
public_shim_mode="$(stat -f %Lp "$default_public_shim")"
if CLAUDE_LITELLM_INSTALL_TEST_FAILPOINT=before-commit \
  LITELLM_MASTER_KEY= \
  LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-$$" \
  HOME="$tmp_home" "$repo_root/scripts/install.zsh" >/dev/null 2>&1; then
  echo "FAIL: public-shim rollback failpoint unexpectedly committed" >&2
  exit 1
fi
test "$(sha256_file "$default_public_shim")" = "$public_shim_sha"
test "$(stat -f %i "$default_public_shim")" = "$public_shim_inode"
test "$(stat -f %Lp "$default_public_shim")" = "$public_shim_mode"
LITELLM_MASTER_KEY= \
  LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-$$" \
  HOME="$tmp_home" "$repo_root/scripts/install.zsh" >/dev/null
if grep -q 'PUBLIC-SHIM-ROLLBACK-SENTINEL' "$default_public_shim"; then
  echo "FAIL: successful reinstall retained the rollback shim fixture" >&2
  exit 1
fi
echo "ok: public shim publishes and rolls back with the package transaction"

# Package publication is transactional through the manifest replacement. Force
# a failure immediately before commit while a proxy is live: the exact old
# root directory nodes, valid generated config, old manifest, and prior runtime
# must return, and the proxy must be made healthy again. A
# subsequent successful upgrade must also preserve prior liveness.
transaction_port="$("$check_python" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
transaction_settings="$spaced_home/transaction-settings.json"
jq --argjson port "$transaction_port" '.server.port = $port' \
  "$spaced_prefix/config/ai-litellm/settings.json" > "$transaction_settings"
print -r -- "# ROLLBACK-EFFECTIVE-SENTINEL" >> "$mutable_config"
if AI_LITELLM_SETTINGS="$transaction_settings" HOME="$spaced_home" \
  "$spaced_prefix/bin/claude-litellm" proxy start >/dev/null 2>&1; then
  echo "FAIL: proxy start accepted a modified generated configuration" >&2
  exit 1
fi
grep -q 'ROLLBACK-EFFECTIVE-SENTINEL' "$mutable_config"
AI_LITELLM_SETTINGS="$transaction_settings" HOME="$spaced_home" \
  "$spaced_prefix/bin/claude-litellm" sync --no-restart >/dev/null
if grep -q 'ROLLBACK-EFFECTIVE-SENTINEL' "$mutable_config"; then
  echo "FAIL: sync did not repair generated configuration drift" >&2
  exit 1
fi
echo "ok: proxy start rejects generated drift and sync repairs it"
transaction_manifest_sha="$(sha256_file "$install_manifest")"
transaction_config_sha="$(sha256_file "$mutable_config")"
transaction_runtime_inode="$(stat -f %i "$spaced_prefix/runtime/venv")"
transaction_bin_inode="$(stat -f %i "$spaced_prefix/bin")"
transaction_config_inode="$(stat -f %i "$spaced_prefix/config")"
transaction_docs_inode="$(stat -f %i "$spaced_prefix/docs")"
transaction_scripts_inode="$(stat -f %i "$spaced_prefix/scripts")"
AI_LITELLM_SETTINGS="$transaction_settings" HOME="$spaced_home" \
  "$spaced_prefix/bin/claude-litellm" proxy start >/dev/null
transaction_old_pid="$(<"$spaced_prefix/state/ai-litellm/litellm.pid")"

# Deliver TERM from the exact mv that consumes the retained bin backup during
# rollback. Recovery must mask termination locally; otherwise EXIT re-enters
# with stale journal flags and deletes the just-restored old package.
rollback_signal_bin="$spaced_home/rollback-signal-bin"
rollback_signal_marker="$spaced_home/rollback-signal-delivered"
mkdir -p "$rollback_signal_bin"
{
  print -r -- '#!/usr/bin/env zsh'
  print -r -- '/bin/mv "$@"'
  print -r -- 'rc=$?'
  print -r -- '(( rc == 0 )) || exit $rc'
  print -r -- 'if (( $# == 2 )) && [[ "$1" == *".publication-backup."*"/bin" && "$2" == "$ROLLBACK_SIGNAL_PREFIX/bin" ]]; then'
  print -r -- '  print -r -- delivered > "$ROLLBACK_SIGNAL_MARKER"'
  print -r -- '  kill -TERM "$PPID"'
  print -r -- 'fi'
  print -r -- 'exit 0'
} > "$rollback_signal_bin/mv"
chmod 700 "$rollback_signal_bin/mv"
if CLAUDE_LITELLM_INSTALL_TEST_FAILPOINT=before-commit \
  AI_LITELLM_SETTINGS="$transaction_settings" LITELLM_MASTER_KEY= \
  LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-spaced-$$" \
  ROLLBACK_SIGNAL_PREFIX="$spaced_prefix" ROLLBACK_SIGNAL_MARKER="$rollback_signal_marker" \
  PATH="$rollback_signal_bin:$PATH" \
  HOME="$spaced_home" "$repo_root/scripts/install.zsh" \
  --prefix "$spaced_prefix" >/dev/null 2>&1; then
  echo "FAIL: installer publication failpoint unexpectedly committed" >&2
  exit 1
fi
test -f "$rollback_signal_marker" || {
  echo "FAIL: rollback signal-injection fixture did not fire" >&2
  exit 1
}
test "$(sha256_file "$install_manifest")" = "$transaction_manifest_sha"
test "$(sha256_file "$mutable_config")" = "$transaction_config_sha"
test "$(stat -f %i "$spaced_prefix/runtime/venv")" = "$transaction_runtime_inode"
test "$(stat -f %i "$spaced_prefix/bin")" = "$transaction_bin_inode"
test "$(stat -f %i "$spaced_prefix/config")" = "$transaction_config_inode"
test "$(stat -f %i "$spaced_prefix/docs")" = "$transaction_docs_inode"
test "$(stat -f %i "$spaced_prefix/scripts")" = "$transaction_scripts_inode"
transaction_rollback_pid="$(<"$spaced_prefix/state/ai-litellm/litellm.pid")"
test "$transaction_rollback_pid" != "$transaction_old_pid"
kill -0 "$transaction_rollback_pid"
AI_LITELLM_SETTINGS="$transaction_settings" HOME="$spaced_home" \
  "$spaced_prefix/bin/claude-litellm" proxy status --json | \
  jq -e '.health == "ok" and .configCurrency == "current"' >/dev/null
if find "${spaced_prefix:h}" -maxdepth 1 -name '.claude-litellm.publication-backup.*' -print -quit | grep -q .; then
  echo "FAIL: installer rollback left a publication backup" >&2
  exit 1
fi

AI_LITELLM_SETTINGS="$transaction_settings" LITELLM_MASTER_KEY= \
  LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-spaced-$$" \
  HOME="$spaced_home" "$repo_root/scripts/install.zsh" \
  --prefix "$spaced_prefix" >/dev/null
if grep -q 'ROLLBACK-EFFECTIVE-SENTINEL' "$mutable_config"; then
  echo "FAIL: successful upgrade retained generated config drift" >&2
  exit 1
fi
transaction_success_pid="$(<"$spaced_prefix/state/ai-litellm/litellm.pid")"
test "$transaction_success_pid" != "$transaction_rollback_pid"
kill -0 "$transaction_success_pid"
AI_LITELLM_SETTINGS="$transaction_settings" HOME="$spaced_home" \
  "$spaced_prefix/bin/claude-litellm" proxy status --json | \
  jq -e '.health == "ok" and .configCurrency == "current"' >/dev/null
AI_LITELLM_SETTINGS="$transaction_settings" HOME="$spaced_home" \
  "$spaced_prefix/bin/claude-litellm" proxy stop >/dev/null
echo "ok: failed and successful upgrades restore prior proxy liveness transactionally"

# A damaged or non-regular schema-v2 manifest must never turn the legacy drift
# guard into a silent skip. Rejection happens before package/runtime mutation.
manifest_saved="$(mktemp "$spaced_home/claude-litellm-manifest.XXXXXX")"
cp -p "$install_manifest" "$manifest_saved"
config_before_manifest_test="$(sha256_file "$mutable_config")"
print -r -- '{broken-json' > "$install_manifest"
if LITELLM_MASTER_KEY= HOME="$spaced_home" "$repo_root/scripts/install.zsh" \
  --prefix "$spaced_prefix" >/dev/null 2>&1; then
  echo "FAIL: reinstall accepted a malformed install manifest" >&2; exit 1
fi
test "$(sha256_file "$mutable_config")" = "$config_before_manifest_test"
cp -p "$manifest_saved" "$install_manifest"
rm -f "$install_manifest"
ln -s "$manifest_saved" "$install_manifest"
if LITELLM_MASTER_KEY= HOME="$spaced_home" "$repo_root/scripts/install.zsh" \
  --prefix "$spaced_prefix" >/dev/null 2>&1; then
  echo "FAIL: reinstall accepted a symlink install manifest" >&2; exit 1
fi
rm -f "$install_manifest"
cp -p "$manifest_saved" "$install_manifest"
rm -f "$manifest_saved"
echo "ok: malformed and symlink manifests fail closed before mutation"

# Public mutations write only the private user overlay. Package defaults remain
# immutable, while the historical effective paths are generated from both.
durability_fixture="$spaced_home/openrouter-durability-models.json"
print -r -- '{"data":[{"id":"testorg/durability-test","context_length":100000,"top_provider":{"context_length":100000,"max_completion_tokens":8000},"supported_parameters":["reasoning","reasoning_effort"],"reasoning":{"supported_efforts":["low","medium","high"]}}]}' > "$durability_fixture"
AI_LITELLM_SKIP_SYNC=1 AI_LITELLM_OPENROUTER_MODELS_JSON="$durability_fixture" \
  HOME="$spaced_home" "$spaced_prefix/bin/claude-litellm" \
  model add testorg/durability-test --name Durability-Test-openrouter >/dev/null
AI_LITELLM_SKIP_SYNC=1 HOME="$spaced_home" "$spaced_prefix/bin/claude-litellm" \
  model reasoning set Durability-Test-openrouter high >/dev/null
for durability_tier in fable opus sonnet haiku; do
  HOME="$spaced_home" "$spaced_prefix/bin/claude-litellm" \
    harness alias set claude "$durability_tier" Durability-Test-openrouter >/dev/null
done
HOME="$spaced_home" "$spaced_prefix/bin/claude-litellm" \
  harness reasoning set claude high >/dev/null
HOME="$spaced_home" "$spaced_prefix/bin/claude-litellm" \
  permissions set bypassPermissions >/dev/null 2>&1

test "$(stat -f %Lp "$spaced_home/.config/claude-litellm")" = "700"
test "$(stat -f %Lp "$user_models")" = "600"
test "$(stat -f %Lp "$user_settings")" = "600"
grep -q 'model_name: Durability-Test-openrouter' "$mutable_config"
grep -q 'reasoning_effort: high' "$mutable_config"
if grep -q 'Durability-Test-openrouter' "$spaced_prefix/config/litellm_config.base.yaml"; then
  echo "User model leaked into package base config" >&2
  exit 1
fi
jq -e '.settings.aliases.opus == "Durability-Test-openrouter" and .harness.reasoningEffort == "high" and .harness.permissionMode == "bypassPermissions"' \
  "$user_settings" >/dev/null
models_sha="$(sha256_file "$user_models")"
settings_sha="$(sha256_file "$user_settings")"

# Direct edits to generated outputs are disposable. Reinstall regenerates them
# while preserving the authoritative user overlays byte-for-byte.
print -r -- '# GENERATED-DRIFT-MUST-DISAPPEAR' >> "$mutable_config"
jq '.aliases.opus = "GLM-5.2-openrouter"' "$mutable_settings" > "$mutable_settings.tmp"
mv "$mutable_settings.tmp" "$mutable_settings"
LITELLM_MASTER_KEY= LITELLM_MASTER_KEYCHAIN_ACCOUNT="ai-litellm-check-no-key-spaced-$$" \
  HOME="$spaced_home" "$repo_root/scripts/install.zsh" --prefix "$spaced_prefix" >/dev/null
test "$(sha256_file "$user_models")" = "$models_sha"
test "$(sha256_file "$user_settings")" = "$settings_sha"
if grep -q 'GENERATED-DRIFT-MUST-DISAPPEAR' "$mutable_config"; then
  echo "Reinstall retained a direct edit to generated config" >&2
  exit 1
fi
grep -q 'model_name: Durability-Test-openrouter' "$mutable_config"
grep -q 'reasoning_effort: high' "$mutable_config"
jq -e '.aliases.opus == "Durability-Test-openrouter"' "$mutable_settings" >/dev/null
test "$(jq -r '.permissions.defaultMode' "$spaced_prefix/state/claude-litellm/overlay-settings-proxy.json")" = "bypassPermissions"
echo "ok: user models, aliases, reasoning, and permission mode survive reinstall through private overlays"

if [[ -d "$spaced_home/.local" ]] && find "$spaced_home/.local" -name "*.bak.*" | grep -q .; then
  echo "Unexpected backup files after identical reinstall" >&2
  find "$spaced_home/.local" -name "*.bak.*" >&2
  exit 1
fi
valid_package_link="$spaced_home/valid-package-through-link"
ln -s "$spaced_prefix" "$valid_package_link"
if HOME="$spaced_home" "$repo_root/scripts/uninstall.zsh" \
  --prefix "$valid_package_link" >/dev/null 2>&1; then
  echo "Unsafe symlink uninstall prefix was accepted" >&2
  exit 1
fi
test -f "$install_manifest"
test -x "$spaced_prefix/bin/claude-litellm"
rm -f "$valid_package_link"
HOME="$spaced_home" "$repo_root/scripts/uninstall.zsh" --prefix "$spaced_prefix" >/dev/null
test ! -e "$spaced_prefix"
test ! -e "$spaced_home/.local/bin/claude-litellm"
test "$(sha256_file "$user_models")" = "$models_sha"
test "$(sha256_file "$user_settings")" = "$settings_sha"
unsafe_uninstall_prefix="$spaced_home/not-fabric"
mkdir -p "$unsafe_uninstall_prefix"
print -r -- "must-survive" > "$unsafe_uninstall_prefix/sentinel"
print -r -- '{"schemaVersion":2,"managedMutableFiles":{}}' > "$unsafe_uninstall_prefix/install-manifest.json"
if HOME="$spaced_home" "$repo_root/scripts/uninstall.zsh" --prefix "$unsafe_uninstall_prefix" >/dev/null 2>&1; then
  echo "Unsafe uninstall prefix was accepted" >&2
  exit 1
fi
grep -qx "must-survive" "$unsafe_uninstall_prefix/sentinel"
if HOME="$spaced_home" "$repo_root/scripts/install.zsh" --prefix "$unsafe_uninstall_prefix" >/dev/null 2>&1; then
  echo "Unsafe install prefix with a forged minimal manifest was accepted" >&2
  exit 1
fi
grep -qx "must-survive" "$unsafe_uninstall_prefix/sentinel"

echo "ok"
