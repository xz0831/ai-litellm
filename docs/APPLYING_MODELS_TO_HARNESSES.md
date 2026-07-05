# Applying a Model to a Harness — context & token playbook

> **Who this is for:** an agent (or human) who has a model — a cloud model reachable
> via OpenRouter, or a local model served by oMLX/vLLM/Ollama — and wants to drive
> **Claude Code or Codex** with it through `ai-litellm-fabric`.
> The wiring is easy; the part that bites is **context-window and token budgeting**.
> Get it wrong and the provider 400s on a too-large request, or the harness silently
> truncates context and the model answers confidently from amputated history.
> This guide is the recipe, with worked examples on the models the fabric actually runs.
>
> **Deeper "why"** lives in [`DESIGN_RATIONALE.md`](DESIGN_RATIONALE.md) (§4 token policy)
> and [`AI_AGENT_LITELLM_ARCHITECTURE.md`](AI_AGENT_LITELLM_ARCHITECTURE.md) (operations,
> decision logs). The empirical evidence base — boundary-probe numbers and the
> owned cost-guardrail interaction — is preserved in
> [`context-observations.json`](../config/ai-litellm/context-observations.json)
> and the token-policy sections of the two documents above.
> This file is the **practitioner's view**: given model X and harness Y, what do I set and why.

---

## 0. The one-paragraph mental model

A harness (Claude Code, Codex, …) speaks its native dialect to what it thinks is its
own backend. The fabric points its `*_BASE_URL` at a **LiteLLM proxy** (or, for Claude
direct mode, OpenRouter's Anthropic-compatible endpoint), and LiteLLM routes each
request to the real model (Kimi, GLM, Mimo, a local Qwen, …). The model is a
**registry entry** (`config/litellm_config.yaml`), addressed by a **surface
`model_name`**. The harness never sees the real model id; it sees a name the fabric
chose, plus a few **environment variables / config values** the fabric injects so the
harness's context accounting matches what the real provider will actually accept.

Everything hard is in those injected numbers. There are exactly two of them, and they
are **not the same number**.

---

## 1. The two numbers: capability vs reservation

| | what it is | where it lives | who owns it |
|---|---|---|---|
| **Capability** | what the model *can* do: real context window (`max_input_tokens`) and max generation (`max_output_tokens`) | one **`x-limits` YAML anchor** per underlying model in `litellm_config.yaml`, referenced by every surface via `model_info: *anchor` | the **provider** (reconciled from OpenRouter `/api/v1/models`), or an **owned-policy** cap with a labeled reason |
| **Reservation** | how much output to **set aside per request** so input + reserved output fit the window | `adapterConfig.outputReservation` in each **harness descriptor** (`harnesses/*.json`) — a small number (default **32000**) | the **harness policy**, not the model |

**Why they must differ — the shared-window trap.** Many providers count
`input + reserved_output ≤ context_window` for a single request, so a harness must never
treat "capability" as "how much to reserve." The trap runs in *both* directions.
**Kimi-K2.7-Code** is today's small-output-cap case: its window is huge (262,144) but its
own output ceiling is tiny (16,384) — reserving the naive 32,000 default would ask the
provider for more output than the model can ever emit, so the reservation is **clamped to
the capability** instead (`min(32000, 16384) = 16384`). **GLM-5.2** and **Mimo-V2.5** sit at
the other end of the shape: a 1,048,576-token window with a six-figure output cap
(128,000 / 131,072) — reserving that *whole* capability on every request would still claw
back over 10% of the window before a single input token is counted. Either way, putting
the reservation into `x-limits` would corrupt the capability metadata itself — hence the
two live in different files with different owners, and the reservation stays a small,
harness-owned constant (32000) decoupled from whatever the model can actually do.

The reservation is **clamped to the capability**: a model whose `max_output_tokens` is
smaller than the 32000 default reserves only what it can emit (see the Kimi-K2.7-Code and
Qwen-27B examples below — both reserve 16384, not 32000).

**Derived budget** (`ai_litellm_harness_output_budget`):

```
effectiveInput = max_input_tokens − reservation − tokenizerHeadroom(8192)
reservation    = min(policy_default(32000), max_output_tokens)
```

`effectiveInput` is the compaction/usable-input target the fabric hands each harness.

> **Don't compute it by hand for small windows.** For a context below ~40K the formula
> would go negative, so the implementation clamps: headroom → `min(8192, 10%·context)`,
> minimumInput floor → `min(32768, 50%·context)`, and reservation collapses toward 1 if
> it still won't fit (e.g. a synthetic 8192/4096 "gemma-shaped" regime in the budget test
> matrix → reservation cap 3277 — a test fixture, not a live registry entry). Always read
> the real value with `ai-litellm context matrix` / `ai-litellm model limits <name>`
> rather than hand-deriving it for edge cases.

---

## 2. The operational input ceiling (why your 1M model only uses ~200K on Claude)

Capability is *not* the per-request operating limit on the **Claude surface** today.
Two independent ~200K caps sit in front of it:

1. **Gateway cost guardrail** (`x-gateway-cost-guardrail`, `output_clamp.py`): rejects a
   request whose **estimated input** exceeds a **global** `max_estimated_input_tokens =
   200000` before it reaches the provider. It's a flat global value (not per-model
   today), so **effective per-request input = `min(model_window, 200000)`** for *every*
   model. GLM-5.2 1,048,576 / Mimo-V2.5 1,048,576 / Kimi-K2.7-Code 262,144 are all
   clamped to 200,000 here.
2. **Claude Code's window belief**: the `claude` binary grants a 1M window only to model
   ids matching `/[1m]/i` or to known first-party Claude families; **any unknown gateway
   id is believed to be 200,000 tokens**. So Claude Code self-compacts around 200K
   regardless of the real window.

The fabric injects `CLAUDE_CODE_AUTO_COMPACT_WINDOW = effectiveInput` so Claude compacts
**before** the provider would reject, and `CLAUDE_CODE_MAX_OUTPUT_TOKENS = reservation`
so a single request can't reserve the whole window. The **LiteLLM `enable_pre_call_checks`**
is the final backstop: an oversized prompt is **rejected (ContextWindowExceededError),
never silently truncated** — a loud error that triggers the harness's own compaction/retry,
which is the right failure for agent workloads.

**Consequence (important for routing decisions):** a model's long-context *strength* is
only realized on a surface that actually uses it.

- **Claude surface** → operationally ~200K input today. Don't fight it.
- **Codex surface** → the fabric shrinks the catalog window to the model's *real* safe
  input (e.g. GLM-5.2's real-name catalog entry, `GLM-5.2-openrouter` →
  **1,008,384**), so Codex can genuinely use the long context. **Route long-context work
  for GLM-5.2 or Mimo-V2.5 through Codex (`GLM-5.2-openrouter` / `Mimo-V2.5-openrouter`),
  not Claude.** To raise Claude's ceiling you'd need a per-model guardrail cap *and*
  `[1m]`-suffixed route naming (so the binary believes 1M) — both are deliberate,
  documented escape hatches, not defaults (raising it via `DISABLE_COMPACT` is
  discouraged: it turns off auto-compaction).

---

## 3. How each harness consumes the budget

The fabric translates `{capability, reservation, effectiveInput}` into each harness's
native control surface. You don't set these by hand — `ai-litellm sync` / launch derives
them — but you must know what lands where to reason about a model.

| harness | window control | output control | how the fabric sets it |
|---|---|---|---|
| **Claude Code** | `CLAUDE_CODE_AUTO_COMPACT_WINDOW = effectiveInput`; believed window 200K for unknown ids ([1m] → 1M) | `CLAUDE_CODE_MAX_OUTPUT_TOKENS = reservation` | per-invocation env, proxy mode only; tier via `ANTHROPIC_DEFAULT_<TIER>_MODEL` |
| **Codex** | generated **model-catalog** `context_window` shrunk to `effectiveInput` (Codex has *no* per-request output lever — `model_max_output_tokens` is parsed-but-ignored, verified) | none at the harness; Codex self-manages output within the shrunk window, and the gateway **output-clamp callback** caps generation at the model's `max_output_tokens` as a secondary safeguard | `state/codex-litellm/model-catalog.json`, regenerated by sync |

**Claude Code model selection** (the surface most people drive):

- **Tiers** `fable|opus|sonnet|haiku` are the stable 4-name facade. Claude Code understands
  them natively (background calls → haiku, plan → opus); the real model travels in
  `ANTHROPIC_DEFAULT_<TIER>_MODEL`. Selecting by tier is the normal path.
- **Any other registered model_name** is selectable directly:
  `claude-litellm --proxy <model_name>` (or just `claude-litellm <model_name>` — it
  auto-switches to proxy mode). An **unresolvable** name now **errors loudly** (it used
  to silently leak as the prompt — see commit 721e735 / the F1 decision log).
- Arbitrary "alias keys" are **not** expanded — an extra model beyond the tiers is
  selected by its real `model_name`, not by inventing another tier (a non-tier key has
  no Claude-native semantics and would leave the tier knobs pointing at the wrong model).

---

## 4. Worked examples (the models this fabric actually runs)

All numbers below are the live values (`x-limits` anchors + computed budgets). Verify on
your machine with `ai-litellm context matrix` and `ai-litellm model limits <name>`.

### 4a. GLM-5.2 — big window, reconciled output cap (cloud / OpenRouter)
- **Capability:** input **1,048,576** (1M), output **128,000** (**provider** — reconciled
  2026-07-04: OpenRouter lowered its published `max_completion_tokens` from 131,072 to
  128,000), reasoning yes.
- **Claude:** `opus` tier → `GLM-5.2-openrouter`. reservation **32,000**, `effectiveInput`
  **1,008,384** (`1048576 − 32000 − 8192`). **Operationally ~200K input** on Claude
  (guardrail + belief). The 1M is *not* used here.
- **Codex:** `GLM-5.2-openrouter` is also Codex's `models.default` — catalog window
  **1,008,384**. **This is where GLM's 1M actually lives** — use `codex-litellm glm`
  (or `codex-litellm GLM-5.2-openrouter`) for long-context jobs.
- **Lesson:** same model, two surfaces, two operating windows. Pick the surface by what
  you need (Claude's tooling vs Codex's real long context).

### 4b. Kimi-K2.7-Code — the small-output-cap clamp (cloud / OpenRouter)
- **Capability:** input **262,144**, output **16,384** (provider) — the output ceiling is
  a small slice of the window, the opposite shape from the classic shared-window trap.
- **Claude:** `fable` tier → `Kimi-K2.7-Code-openrouter`. reservation is **clamped to
  capability**: `min(32000, 16384) = 16384`, `effectiveInput` **237,568**
  (`262144 − 16384 − 8192`).
- **Why this is the canonical clamp example:** the naive 32,000 default reservation is
  *larger* than what this model can ever emit. Reserving it anyway would promise the
  provider output the model cannot produce; clamping the reservation down to 16,384 is
  what keeps the request honest. (On Claude the guardrail still caps the *operating*
  input at 200K; 237,568 is the true ceiling the Codex surface uses.)
- **Codex:** `Kimi-K2.7-Code-openrouter` (catalog window **237,568**) and
  `codex-auto-review` — a hidden bundled-catalog slug Codex's `review` subcommand
  hardcodes a request for — both share this exact anchor/backend (repointed to
  Kimi-K2.7-Code 2026-07-04 for code-specialized review).

### 4c. Mimo-V2.5 — provider omits the output cap (cloud / OpenRouter)
- **Capability:** input **1,048,576** (provider), output **131,072** — but this output is
  **owned-policy**: OpenRouter omits `max_completion_tokens` for Mimo, so the fabric sets a
  conservative ceiling and labels it (`x_output_source: openrouter-unpublished; conservative
  ceiling mirroring glm52 precedent` — GLM-5.2 played this same owned-policy role until
  OpenRouter published its number, 2026-07-04).
- **Claude:** `sonnet` tier → `Mimo-V2.5-openrouter`. reservation **32,000**,
  `effectiveInput` **1,008,384** (`1048576 − 32000 − 8192`).
- **Codex:** `Mimo-V2.5-openrouter` — real name, no facade — catalog window **1,008,384**.
- **Lesson:** when a provider doesn't publish a number, you don't guess silently — you set
  an **owned-policy** value with a `x_*_source` reason. `ai-litellm model refresh-capabilities`
  only auto-updates `provider`-confidence values, never owned-policy ones — which is exactly
  how GLM-5.2 graduated out of owned-policy while Mimo-V2.5 hasn't, yet.

### 4d. Qwen3.6-27B — local Claude haiku tier, thinking helps (oMLX)
- **Capability:** input **131,072**, output **16,384**, both **owned-policy** (native
  window is 262,144 per the model's `config.json`, capped to a local-throughput-conservative
  value; `x_input_source` records both facts).
- **Claude:** `haiku` tier → `Qwen3.6-27B-omlx` (a promoted first-class registry entry,
  not a discovered route, so the tier survives reinstall). It is fully local/free, so
  Claude Code background/subagent calls routed to haiku do not spend provider budget.
  reservation clamped to capability (`min(32000, 16384) = 16384`), `effectiveInput`
  **106,496** (`131072 − 16384 − 8192`).
- **Thinking:** stays **on** — qualification showed 27B follows instructions fine in the
  heavy harness with thinking enabled.

### 4e. Qwen3.6-35B-A3B — local, thinking must be off (oMLX)
- Same anchor as 27B (131,072 / 16,384). MoE; **qualified thinking-OFF**: under the heavy
  Claude system prompt with thinking on it drifts off-task (writes creative text instead
  of answering — finding M1).
- **Route:** promoted entry `Qwen3.6-35B-A3B-4bit-omlx` (full model id, canonical name)
  carrying `litellm_params.extra_body.chat_template_kwargs.enable_thinking: false`. LiteLLM
  forwards `extra_body` straight to oMLX (verified: thinking-on 148 tokens → thinking-off 2
  tokens on a trivial probe, prompt preserved). Select with
  `claude-litellm --proxy Qwen3.6-35B-A3B-4bit-omlx`.
- **For benchmarking churn** (swapping many local models), don't hand-promote each one:
  set `runtimes.<rt>.litellmParamsOverrides` (a glob map symmetric with `modelInfoOverrides`)
  to inject thinking-off into **discovered** routes automatically, e.g.
  `"Qwen3.6-35B*": {"extra_body": {"chat_template_kwargs": {"enable_thinking": false}}}`.
- **Lesson:** thinking on/off, instruction-following, and accuracy are **per-model facts**
  no fabric change removes — every new local model runs the **per-model qualification
  protocol** (in the architecture guide). The fabric only makes the model *runnable*.

---

## 5. Recipe: onboard a NEW model

### 5a. Cloud model via OpenRouter

**1. Get the capability numbers from the provider.**
```zsh
KEY=$(security find-generic-password -s openrouter-api-key -a "$USER" -w)   # macOS keychain
curl -s https://openrouter.ai/api/v1/models -H "Authorization: Bearer $KEY" \
  | jq '.data[] | select(.id=="<vendor>/<model>") | {id, context_length, top_provider}'
```
`context_length` → `max_input_tokens`; `top_provider.max_completion_tokens` → `max_output_tokens`.
If a field is **null/absent** (Mimo-V2.5 omits `max_completion_tokens` today; GLM-5.2 used
to before OpenRouter published it, 2026-07-04), do **not** guess — use an `owned-policy`
cap with a labeled reason.

**2. Add the capability anchor + surface entries** in `config/litellm_config.yaml`:
```yaml
x-limits:
  newmodel: &newmodel
    max_input_tokens: 1048576
    max_output_tokens: 384000
    supports_reasoning: true
    x_input_confidence: provider           # or owned-policy
    x_input_source: openrouter.top_provider.context_length
    x_output_confidence: provider          # owned-policy if the provider omits it
    x_output_source: openrouter.top_provider.max_completion_tokens
model_list:
  - model_name: NewModel-openrouter        # raw <Model>-<provider> name (canonical)
    litellm_params: { model: openrouter/<vendor>/<model>, api_key: os.environ/OPENROUTER_API_KEY }
    model_info: *newmodel                  # reference the anchor — NEVER inline numbers
```

**3. Wire the harness surface(s):**
- **Claude tier** — edit `config/claude-litellm/settings.json` `aliases.<tier>` (proxy) /
  `directAliases.<tier>` (direct) to the surface `model_name`. Or skip tiers and just select
  the raw name: `claude-litellm --proxy NewModel-openrouter`.
- **Codex** — Codex shares the exact same real `model_name` (no bundled-slug disguise;
  `gpt-*` facades were retired 2026-07-04 — see DESIGN_RATIONALE §3's supersede notes).
  Append **one entry** to `config/ai-litellm/harnesses/codex.json`'s `models.catalogEntries`:
  ```json
  { "slug": "NewModel-openrouter", "displayName": "NewModel (openrouter)", "description": "...", "priority": 80 }
  ```
  (`slug` must equal the registry `model_name`; `displayName` follows the
  `<Model> (<provider>)` convention if you omit it; add `"defaultReasoningLevel"` for a
  non-default reasoning level.) No slug-hunting via `codex debug models` is needed — the
  generator clones this entry's shape from the bundled schema template
  (`models.catalogBaseSlug`, currently `gpt-5.4-mini`) and stamps its context window from
  the same anchor + `outputReservation` used everywhere else. The **retention rule** means
  a registry route with no `catalogEntries` line simply never appears in the generated
  catalog (safe by construction, no manual bookkeeping needed there), and any bundled
  leftover without a matching registry route drops out automatically.

**4. Reconcile, regenerate, verify:**
```zsh
ai-litellm model refresh-capabilities --check   # compares anchors vs OpenRouter; flags drift.
                                                # --apply updates provider-confidence values
                                                # only (owned-policy is never auto-touched).
ai-litellm sync                                 # regenerates codex catalog/config, claude
                                                # settings; restarts the proxy (kills
                                                # in-flight sessions — never mid-batch).
ai-litellm model limits NewModel-openrouter     # capability
ai-litellm context matrix                       # window / reservation / effectiveInput per surface
ai-litellm doctor --context && ai-litellm doctor --proxy
```

### 5b. Local model via oMLX (or any `kind: openai-compatible` runtime)

**1. Serve it.** Load the model in oMLX (`http://127.0.0.1:8000/v1`). Runtimes are
user-managed — the fabric never auto-starts them.

**2. See the id it advertises, then discover:**
```zsh
curl -s http://127.0.0.1:8000/v1/models | jq -r '.data[].id'   # e.g. Qwen3.6-35B-A3B-4bit
ai-litellm sync                                                # generates route <id>-omlx
ai-litellm model list | grep -- -omlx                          # confirm; membership is by
                                                               # api_base equality, never name
```
A freshly discovered route gets conservative default limits (**8192/4096**).

**3. Set the real window** (usually needed). Find the native window in the model's
`config.json` (under `~/.omlx/models/<org>/<name>/config.json`, key `max_position_embeddings`),
then cap conservatively for local throughput/quality and record the reason as `owned-policy`:
```jsonc
// config/ai-litellm/settings.json → runtimes.omlx.modelInfoOverrides (glob, later wins)
"Qwen3*": {                       // native 262144 → capped to 131072 (~50%), owned-policy
  "max_input_tokens": 131072,
  "max_output_tokens": 16384,
  "x_input_source": "native 262144 (model config.json); owned-policy local throughput cap"
}
```

**4. Thinking control — decision tree:**
- **Benchmarking churn / temporary** → glob, no hand-promotion:
  `runtimes.omlx.litellmParamsOverrides`: `"Qwen3.6-35B*": {"extra_body":{"chat_template_kwargs":{"enable_thinking":false}}}`.
  Re-injected into the discovered route on every `sync`.
- **Durable / backs a tier** → promote to a first-class entry in `litellm_config.yaml` under
  the **full model id name** (e.g. `Qwen3.6-35B-A3B-4bit-omlx`) carrying the same `extra_body`.
  "Survives reinstall" = it's hand-maintained, not regenerated; discovery sees the same
  `(model, api_base)` and **dedups** (skips the auto route), so there's exactly one.
- Either way: `ai-litellm sync`, then `ai-litellm model info <name>` to confirm the param landed.

**5. Select & qualify.** Run with `claude-litellm --proxy <model_name>`, then walk the
**per-model qualification protocol** — defined in full in
[`AI_AGENT_LITELLM_ARCHITECTURE.md`](AI_AGENT_LITELLM_ARCHITECTURE.md#per-model-자격검증-프로토콜-신규-로컬-모델마다-실행). Minimal pass:
```zsh
MK=$(security find-generic-password -s litellm-master-key -a "$USER" -w)
# (1) direct oMLX, thinking on AND off — confirm it follows instructions both ways
curl -s http://127.0.0.1:8000/v1/chat/completions -d '{"model":"<id>","messages":[{"role":"user","content":"What is 7 times 6? Reply with only the number."}],"max_tokens":600,"chat_template_kwargs":{"enable_thinking":false}}' | jq -r '.choices[0].message.content'   # expect 42
# (2) proxy: same prompt, route name, Bearer $MK — verify the prompt ARRIVES unchanged
# (3) harness: claude-litellm --proxy <model_name> -p "What is 7 times 6? Reply with only the number." --no-session-persistence --tools ''
```
**Thinking decision:** if thinking-ON explodes tokens (>~10×) or the model drifts off-task
under the heavy harness system prompt, set thinking-off (step 4). **Accuracy gate:** 2–3
domain probes vs known answers. **Verdict:** record usable-in-harness? thinking on/off?
accuracy tier? — these are per-model facts the fabric cannot remove.

---

## 6. Reasoning / effort & dialect params

- **Effort:** harness intent layers above provider default (`explicit > harness-auto >
  provider-default`). Claude injects `--effort` only for a non-auto descriptor effort;
  Codex sets `model_reasoning_effort`. Inspect with `ai-litellm reasoning matrix`.
- **`drop_params: true`** (gateway): harnesses over-advertise dialect params
  (`thinking`, beta headers, `reasoning_effort`) that a given backend may not support;
  dropping them beats a provider 400 across N harnesses × M backends. The **cost is
  silent drops** — watch the `drop_risk` column in `ai-litellm reasoning matrix`. To stop
  a tier from advertising thinking at the source, set
  `ANTHROPIC_DEFAULT_<TIER>_MODEL_SUPPORTED_CAPABILITIES` (value `none` = declare empty).
  Do **not** flip `drop_params` to fix one model — that converts every `drop_risk` row
  into a hard 400.

---

## 7. Failure-mode checklist (what breaks, what the fabric does)

| symptom | cause | fabric's answer |
|---|---|---|
| provider 400 on a big prompt | input + reserved output > window (shared-window) | reservation kept small (32000), clamped to capability; `effectiveInput` = window − reservation − 8192 |
| silent wrong answers from amputated context | harness truncated instead of erroring | LiteLLM `enable_pre_call_checks` **rejects** oversized prompts; no silent truncation |
| 1M model only uses ~200K (Claude) | global cost-guardrail `min(window, 200000)` + Claude's 200K belief for unknown ids | route long-context to the **Codex** surface (catalog window = real `effectiveInput`); or per-model guardrail + `[1m]` naming (advanced) |
| Codex 400 on near-full input | Codex has no per-request output lever (`model_max_output_tokens` ignored) | catalog `context_window` shrunk to `effectiveInput` (belief-shaping replaces reservation) |
| local model burns 6000 tokens on a number | Qwen thinking-mode bloat | route-level `extra_body.chat_template_kwargs.enable_thinking: false` (forwarded to oMLX); per-model qualification decides on/off |
| `--proxy <typo>` does nothing useful | (fixed) used to leak the token as the prompt under the default tier | now a **loud error** naming the bad token + `ai-litellm model list` |
| reasoning quality silently drops | `drop_params` ate `reasoning_effort` | `ai-litellm reasoning matrix` `drop_risk`; declare capabilities at the tier |
| every mode switch re-pays cache | prompt cache is per-provider; switching backends re-reads the prefix uncached | `CLAUDE_CODE_ATTRIBUTION_HEADER=0` injected (stops per-turn prefix-cache busting); minimize mode switches |

---

## 8. Verify commands (cheat sheet)

```zsh
ai-litellm model list                       # all surface names + backend column (name -> backend)
ai-litellm model limits <name>              # capability (window / output)
ai-litellm model info <name>                # full model_info (echoed by GET /model/info)
ai-litellm context matrix [filter]          # per-surface window/reservation/effectiveInput
ai-litellm doctor --context                 # reservations leave input budget; pre-call on
ai-litellm reasoning matrix                 # effort + drop_risk per surface
ai-litellm doctor --proxy                   # running proxy loaded current registry?
ai-litellm sync [--dry-run|--no-restart]    # regenerate derived configs (restarts proxy)
```

**Golden rule:** capability is what the model *can* do; the per-request operating window
is `min(capability, harness belief, guardrail)`; reservation is harness policy, not
capability; and `enable_pre_call_checks` guarantees you get a loud rejection, never a
silent truncation. Everything else is choosing the surface that uses the model's strength.
