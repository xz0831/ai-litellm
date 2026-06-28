# fabric `--json` Foundation — Implementation Plan (1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add additive, non-breaking `--json` output to the read-only `ai-litellm` commands that the `fabric` TUI core needs first, so the TUI can consume structured state instead of screen-scraping text.

**Architecture:** Each read command keeps its existing human text output as the default. A `--json` flag, parsed in the noun-verb sub-dispatcher, routes to a sibling JSON emitter that reuses the *same* underlying state helpers (`ai_litellm_health`, `ai_litellm_proxy_config_current`, etc.) and serializes with `node` (the project's existing JSON tool). No state logic is duplicated or changed.

**Tech Stack:** zsh (dispatchers/formatters), node (JSON serialization, already a hard dependency), Ruby+YAML (registry reads, already used), check.zsh (golden tests).

**Scope of this plan (1 of 3):** `proxy status`, `model list`, `model limits`, `harness list`, `harness info`, `key status` → `--json`. Out of scope (later plans): `context matrix`/`reasoning matrix`/`*doctor`/`route`/`runtime` `--json` (Plan 2 with the TUI core), and the Textual TUI itself (Plans 2–3).

## Global Constraints

- backend logic unchanged: `--json` is an **output formatter only**; never re-derive state. (spec §2, §4)
- additive & non-breaking: default output (no flag) stays byte-identical. (spec §4.1)
- no new runtime language: serialize with `node` (already required). (spec §3)
- `--json` is for **read-only** commands only; never add it to mutating/billable verbs. (spec §6)
- JSON key naming: **camelCase**, resolving spec §12's open item. Keys exactly as listed per task below.
- every `--json` emitter must produce a single line of valid JSON to stdout and exit 0 on success; on an unreadable source it prints `{}` (objects) or `[]` (arrays) to stdout and exits 0 (the TUI shows "empty", never a stack trace). Diagnostics go to stderr. (spec §9)

---

## File Structure

- Modify: `config/ai-litellm/lib.zsh`
  - Add one tiny shared helper `ai_litellm_emit_json` (near the other `ai_litellm_json*` helpers, ~line 80).
  - Add a sibling `*_json` emitter next to each target formatter.
  - Add `--json` flag handling in the relevant sub-dispatchers (`ai_litellm_cmd_proxy`, `ai_litellm_cmd_model`, `ai_litellm_cmd_harness`, `ai_litellm_cmd_key`).
- Modify: `scripts/check.zsh` — add a `--json` contract assertion block (golden keys, valid-JSON, default-output-unchanged).
- Modify: `README.md` — one line under the doctor/contract section noting `--json` is available on the listed read commands.

No new files in this plan.

---

## Task 1: `--json` plumbing + `proxy status --json`

**Files:**
- Modify: `config/ai-litellm/lib.zsh` (add `ai_litellm_emit_json` ~line 80; add `ai_litellm_status_json` after `ai_litellm_status` ends at 2134; add `--json` parse in `ai_litellm_cmd_proxy` at 5633–5644)
- Test: `scripts/check.zsh` (new assertion block)

**Interfaces:**
- Consumes (existing, verified): `ai_litellm_base_url`, `ai_litellm_pid_running`, `ai_litellm_active_pid`, `ai_litellm_active_pid_file`, `ai_litellm_health`, `ai_litellm_proxy_config_current` (returns 0=current,2=unknown,else stale), `ai_litellm_active_log_file`, `AI_LITELLM_CONFIG`, `AI_LITELLM_SETTINGS`, `AI_LITELLM_LOCK_DIR`.
- Produces: `ai_litellm_emit_json <<<json-via-stdin-node-args>` helper; `ai_litellm_status_json` printing object with keys: `config, settings, baseUrl, pid (number|null), pidFile (string|null), health ("ok"|"unreachable"), configCurrency ("current"|"unknown"|"stale"|"unknown-not-running"), lock (string|null), log`.

- [ ] **Step 1: Write the failing test** — append to `scripts/check.zsh` (before its final `echo ok`):

```zsh
# ── --json contract: proxy status ────────────────────────────────────────────
json_check() {
  local label="$1"; shift
  local out
  out="$("$@" 2>/dev/null)" || { echo "FAIL($label): nonzero exit"; exit 1; }
  print -r -- "$out" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{JSON.parse(s)}catch(e){console.error("invalid JSON");process.exit(1)}})' \
    || { echo "FAIL($label): invalid JSON"; exit 1; }
}
assert_json_key() {
  local label="$1" json="$2" key="$3"
  print -r -- "$json" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);if(!(process.argv[1] in o)){console.error("missing key");process.exit(1)}})' "$key" \
    || { echo "FAIL($label): missing key $key"; exit 1; }
}
ps_json="$(ai-litellm proxy status --json 2>/dev/null)"
json_check "proxy status --json" ai-litellm proxy status --json
for k in config settings baseUrl health configCurrency log; do
  assert_json_key "proxy status --json" "$ps_json" "$k"
done
# default output unchanged: still human text, no leading '{'
ps_text="$(ai-litellm proxy status 2>/dev/null)"
[[ "$ps_text" != \{* ]] || { echo "FAIL: default proxy status became JSON"; exit 1; }
echo "ok: proxy status --json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/check.zsh`
Expected: FAIL — `ai-litellm proxy status --json` currently prints human text, so `json_check` reports "invalid JSON" (or the key assertions fail).

- [ ] **Step 3: Add the shared emitter helper** — in `config/ai-litellm/lib.zsh` after `ai_litellm_json()` (line 90):

```zsh
# Serialize key/value pairs to one line of JSON. Args alternate KEY VALUE …;
# a VALUE of the form @num:<n> emits a JSON number, @bool:<true|false> a bool,
# @null emits null, otherwise a JSON string. Output formatter only — never
# computes state. Always exits 0 with valid JSON.
ai_litellm_emit_json() {
  node -e '
const a = process.argv.slice(1);
const o = {};
for (let i = 0; i + 1 < a.length; i += 2) {
  const k = a[i]; let v = a[i + 1];
  if (v === "@null") o[k] = null;
  else if (v.startsWith("@num:")) { const n = Number(v.slice(5)); o[k] = Number.isFinite(n) ? n : null; }
  else if (v.startsWith("@bool:")) o[k] = v.slice(6) === "true";
  else o[k] = v;
}
process.stdout.write(JSON.stringify(o));
' "$@"
}
```

- [ ] **Step 4: Add the JSON emitter** — in `config/ai-litellm/lib.zsh` immediately after `ai_litellm_status()` (after line 2134):

```zsh
ai_litellm_status_json() {
  local pid="@null" pidfile="@null" health="unreachable" currency log lock="@null"
  if ai_litellm_pid_running; then
    pid="@num:$(ai_litellm_active_pid)"
    pidfile="$(ai_litellm_active_pid_file)"
  fi
  ai_litellm_health && health="ok"
  if ai_litellm_pid_running; then
    ai_litellm_proxy_config_current
    case $? in
      0) currency="current" ;;
      2) currency="unknown" ;;
      *) currency="stale" ;;
    esac
  else
    currency="unknown-not-running"
  fi
  [[ -d "$AI_LITELLM_LOCK_DIR" ]] && lock="$AI_LITELLM_LOCK_DIR"
  log="$(ai_litellm_active_log_file)"
  ai_litellm_emit_json \
    config "$AI_LITELLM_CONFIG" \
    settings "$AI_LITELLM_SETTINGS" \
    baseUrl "$(ai_litellm_base_url)" \
    pid "$pid" \
    pidFile "$pidfile" \
    health "$health" \
    configCurrency "$currency" \
    lock "$lock" \
    log "$log"
}
```

- [ ] **Step 5: Wire `--json` into the proxy sub-dispatcher** — replace the `status|"")` line in `ai_litellm_cmd_proxy` (line 5636):

```zsh
    status|"")
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_status_json; else ai_litellm_status; fi
      ;;
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `./scripts/check.zsh`
Expected: PASS — prints `ok: proxy status --json` and the script's final `ok`.

- [ ] **Step 7: Commit**

```bash
git add config/ai-litellm/lib.zsh scripts/check.zsh
git commit -m "feat(cli): add proxy status --json + json emitter helper"
```

---

## Task 2: `model list --json` and `model limits --json`

**Files:**
- Modify: `config/ai-litellm/lib.zsh` (`ai_litellm_list` at 2136; `ai_litellm_model_limits` at 399; `ai_litellm_cmd_model` sub-dispatcher)
- Test: `scripts/check.zsh`

**Interfaces:**
- Consumes: `AI_LITELLM_CONFIG`, `ai_litellm_ruby` (UTF-8 Ruby with YAML aliases).
- Produces: `ai_litellm_list_json` → array of `{name, backend}`; `ai_litellm_model_limits_json [model]` → array of `{model, context (number|null), output (number|null), effectiveInput (number|null), sources (object)}`.

- [ ] **Step 1: Write the failing test** — append to `scripts/check.zsh`:

```zsh
ml_json="$(ai-litellm model list --json 2>/dev/null)"
json_check "model list --json" ai-litellm model list --json
print -r -- "$ml_json" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const a=JSON.parse(s);
if(!Array.isArray(a)||a.length===0){console.error("not a non-empty array");process.exit(1)}
if(!("name" in a[0])||!("backend" in a[0])){console.error("missing name/backend");process.exit(1)}})' \
  || { echo "FAIL: model list --json shape"; exit 1; }
json_check "model limits --json" ai-litellm model limits --json
echo "ok: model list/limits --json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/check.zsh`
Expected: FAIL — `model list --json` prints text.

- [ ] **Step 3: Add `ai_litellm_list_json`** — in `config/ai-litellm/lib.zsh` after `ai_litellm_list()` (after line 2151):

```zsh
ai_litellm_list_json() {
  ai_litellm_ruby -ryaml -rjson -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue (YAML.load_file(ARGV[0]) rescue nil))
rows = []
Array(config && config["model_list"]).each do |entry|
  name = entry["model_name"]
  next unless name
  backend = entry.dig("litellm_params", "model")
  rows << {"name" => name, "backend" => (backend || name)}
end
print JSON.generate(rows)
' "$AI_LITELLM_CONFIG" 2>/dev/null || printf "[]"
}
```

- [ ] **Step 4: Add `ai_litellm_model_limits_json`** — in `config/ai-litellm/lib.zsh` after `ai_litellm_model_limits()` ends (it begins at 399; insert after its closing brace, before `ai_litellm_harness_output_budget` at 421). Reuse the same `x-limits`/`model_info` read the text formatter uses:

```zsh
ai_litellm_model_limits_json() {
  local filter="${1:-}"
  ai_litellm_ruby -ryaml -rjson -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue (YAML.load_file(ARGV[0]) rescue nil))
filter = ARGV[1]
rows = []
Array(config && config["model_list"]).each do |entry|
  name = entry["model_name"]
  next unless name
  next if filter && !filter.empty? && name != filter
  info = entry["model_info"] || {}
  ctx = info["max_input_tokens"] || info["max_tokens"]
  out = info["max_output_tokens"]
  eff = (ctx && out) ? (ctx - out) : ctx
  rows << {
    "model" => name,
    "context" => ctx,
    "output" => out,
    "effectiveInput" => eff,
    "sources" => {"context" => (info["x-source-input"] || info["source"]), "output" => info["x-source-output"]}
  }
end
print JSON.generate(rows)
' "$AI_LITELLM_CONFIG" "$filter" 2>/dev/null || printf "[]"
}
```

> Note: if the running registry derives limits differently than the static read above (e.g. via `ai_litellm_limits_map` at line 503), prefer calling that existing derivation instead of re-reading YAML. Verify against `ai-litellm model limits` text output during Step 6 and adjust the Ruby to match the same numbers; the test asserts shape, the human comparison asserts values.

- [ ] **Step 5: Wire `--json` into `ai_litellm_cmd_model`** — locate the `list)` and `limits)` cases in `ai_litellm_cmd_model` and gate each:

```zsh
    list|"")
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_list_json; else ai_litellm_list; fi
      ;;
    limits)
      if [[ "${1:-}" == "--json" ]]; then shift; ai_litellm_model_limits_json "$@"
      elif [[ "${2:-}" == "--json" ]]; then ai_litellm_model_limits_json "$1"
      else ai_litellm_model_limits "$@"; fi
      ;;
```

- [ ] **Step 6: Run the test + value spot-check**

Run: `./scripts/check.zsh` → Expected: PASS (`ok: model list/limits --json`).
Run: `ai-litellm model limits | head` and `ai-litellm model limits --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).slice(0,2)))'` → Expected: the numbers agree. If not, adjust the Ruby in Step 4 to use the same derivation as the text formatter.

- [ ] **Step 7: Commit**

```bash
git add config/ai-litellm/lib.zsh scripts/check.zsh
git commit -m "feat(cli): add model list/limits --json"
```

---

## Task 3: `harness list --json`, `harness info --json`, `key status --json`

**Files:**
- Modify: `config/ai-litellm/lib.zsh` (`ai_litellm_harnesses` 1142; `ai_litellm_harness_info` 1150; `ai_litellm_key_status` 2298; `ai_litellm_cmd_harness` 5646; `ai_litellm_cmd_key`)
- Test: `scripts/check.zsh`

**Interfaces:**
- Consumes: `ai_litellm_harness_names`, `ai_litellm_harness_descriptor`, `ai_litellm_harness_json`/`ai_litellm_harness_json_array`, `ai_litellm_harness_cli_available`, `ai_litellm_harness_validate`, `ai_litellm_openrouter_key`/`ai_litellm_master_key` source reporting (as used by `ai_litellm_key_status`).
- Produces: `ai_litellm_harnesses_json` → array of `{name, adapter, command, baseUrl, valid (bool), cliInstalled (bool)}`; `ai_litellm_harness_info_json <name>` → single object same shape + `isolation`; `ai_litellm_key_status_json` → `{openrouter:{source}, master:{source}}`.

- [ ] **Step 1: Write the failing test** — append to `scripts/check.zsh`:

```zsh
json_check "harness list --json" ai-litellm harness list --json
hl_json="$(ai-litellm harness list --json 2>/dev/null)"
print -r -- "$hl_json" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const a=JSON.parse(s);
const names=a.map(x=>x.name).sort().join(",");
if(names!=="claude,codex,opencode"){console.error("unexpected harnesses: "+names);process.exit(1)}
for(const h of a){for(const k of ["adapter","valid","cliInstalled"]) if(!(k in h)){console.error("missing "+k);process.exit(1)}}})' \
  || { echo "FAIL: harness list --json shape"; exit 1; }
json_check "key status --json" ai-litellm key status --json
ks_json="$(ai-litellm key status --json 2>/dev/null)"
assert_json_key "key status --json" "$ks_json" openrouter
assert_json_key "key status --json" "$ks_json" master
echo "ok: harness/key --json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./scripts/check.zsh` → Expected: FAIL (text output).

- [ ] **Step 3: Add `ai_litellm_harnesses_json` and `ai_litellm_harness_info_json`** — after `ai_litellm_harness_info()` (line 1150 block):

```zsh
ai_litellm_harness_one_json() {
  local name="$1"
  local adapter command baseurl isolation valid="@bool:false" cli="@bool:false"
  adapter="$(ai_litellm_harness_json "$name" adapter 2>/dev/null)"
  command="$(ai_litellm_harness_json "$name" command 2>/dev/null)"
  baseurl="$(ai_litellm_harness_json "$name" baseUrl 2>/dev/null)"
  isolation="$(ai_litellm_harness_json "$name" isolation.envVar 2>/dev/null)"
  ai_litellm_harness_validate "$name" >/dev/null 2>&1 && valid="@bool:true"
  ai_litellm_harness_cli_available "$name" >/dev/null 2>&1 && cli="@bool:true"
  ai_litellm_emit_json \
    name "$name" adapter "${adapter:-}" command "${command:-}" \
    baseUrl "${baseurl:-}" isolation "${isolation:-}" valid "$valid" cliInstalled "$cli"
}

ai_litellm_harnesses_json() {
  local first=1 name
  printf '['
  for name in $(ai_litellm_harness_names); do
    (( first )) || printf ','
    first=0
    ai_litellm_harness_one_json "$name"
  done
  printf ']'
}

ai_litellm_harness_info_json() {
  [[ -n "${1:-}" ]] || { printf '{}'; return 0; }
  ai_litellm_harness_one_json "$1"
}
```

> Note: confirm the exact descriptor key paths (`adapter`, `command`, `baseUrl`, `isolation.envVar`) against `config/ai-litellm/harnesses/schema.json` and `ai_litellm_harness_json`'s path syntax during Step 6; adjust paths to match the schema (the helper signature is `ai_litellm_harness_json <name> <dotted.path>`).

- [ ] **Step 4: Add `ai_litellm_key_status_json`** — after `ai_litellm_key_status()` (line 2298). Mirror whatever source strings the text version reports (Keychain / env-file / environment / missing):

```zsh
ai_litellm_key_status_json() {
  local or_src ms_src
  or_src="$(ai_litellm_key_source openrouter 2>/dev/null || echo missing)"
  ms_src="$(ai_litellm_key_source master 2>/dev/null || echo missing)"
  node -e 'process.stdout.write(JSON.stringify({openrouter:{source:process.argv[1]},master:{source:process.argv[2]}}))' "$or_src" "$ms_src"
}
```

> Note: `ai_litellm_key_source` may not exist as a separate function. If `ai_litellm_key_status` inlines the source detection, extract a small `ai_litellm_key_source <openrouter|master>` returning one of `keychain|env-file|environment|missing` and have BOTH the text `ai_litellm_key_status` and this JSON emitter call it (DRY). Verify the source strings against the text output in Step 6.

- [ ] **Step 5: Wire `--json`** — in `ai_litellm_cmd_harness` (5648) and `ai_litellm_cmd_key`:

```zsh
# in ai_litellm_cmd_harness, replace list/info cases:
    list|"")
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_harnesses_json; else ai_litellm_harnesses; fi
      ;;
    info)
      if [[ "${2:-}" == "--json" ]]; then ai_litellm_harness_info_json "$1"
      else ai_litellm_harness_info "$@"; fi
      ;;
# in ai_litellm_cmd_key, replace the status case:
    status|"")
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_key_status_json; else ai_litellm_key_status; fi
      ;;
```

- [ ] **Step 6: Run the test + value spot-check**

Run: `./scripts/check.zsh` → Expected: PASS (`ok: harness/key --json`).
Run: `ai-litellm harness list --json` and `ai-litellm key status --json`; confirm `adapter`/`valid`/`cliInstalled` and the key `source` strings match the text commands. Adjust descriptor paths / source extraction if they differ.

- [ ] **Step 7: Commit**

```bash
git add config/ai-litellm/lib.zsh scripts/check.zsh
git commit -m "feat(cli): add harness list/info --json and key status --json"
```

---

## Task 4: Document the `--json` surface

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add a note** — under the "Use the doctors as the contract" / maintenance area of `README.md`, add:

```markdown
### Machine-readable output

Read-only commands accept `--json` for scripting and the `fabric` dashboard:

​```zsh
ai-litellm proxy status --json
ai-litellm model list --json
ai-litellm model limits [model] --json
ai-litellm harness list --json
ai-litellm harness info <name> --json
ai-litellm key status --json
​```

`--json` is additive: without it, output is unchanged human text. It is only
available on read-only commands.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document the --json read surface"
```

---

## Self-Review

**Spec coverage:** Plan covers spec §4.1's first-wave commands (proxy status, model list/limits, harness list/info, key status) and the additive/non-breaking, read-only-only, camelCase, empty-on-failure constraints (§4, §6, §9, §12). Deferred to Plan 2 (with TUI core): `context matrix`/`reasoning matrix`/`route`/`runtime`/`*doctor` `--json`. Deferred to Plans 2–3: the Textual TUI, `bin/fabric`, `ai-litellm dash`, install/packaging, Pilot tests.

**Placeholder scan:** Two `> Note:` blocks (Task 2 Step 4, Task 3 Steps 3–4) direct the engineer to verify derivation/paths against existing code and adjust to match — these are verification instructions with concrete fallbacks, not unspecified work. All code steps contain runnable code.

**Type consistency:** `ai_litellm_emit_json` arg convention (`@num:`/`@bool:`/`@null`/string) defined in Task 1 and reused in Tasks 1 & 3. JSON key names (`baseUrl`, `configCurrency`, `effectiveInput`, `cliInstalled`) are consistent across emitters and tests.

---

*Next: Plan 2 — `fabric` TUI core (concept tree + read panels consuming `--json`, the remaining read `--json` commands, `bin/fabric` + `ai-litellm dash` + install/check wiring). Plan 3 — TUI actions + safety (action bar, confirm modals, launch flow).*
