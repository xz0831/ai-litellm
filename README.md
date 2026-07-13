# claude-litellm

Run Claude Code with OpenRouter, local oMLX models, ChatGPT OAuth, Grok OAuth,
and other LiteLLM providers through one local gateway.

```text
Claude Code -> localhost LiteLLM -> selected provider/model
```

This project wraps Claude Code only. It does not replace native `claude`, modify
native `~/.claude`, or wrap Codex. Removing the Codex compatibility layer keeps
the product on one stable protocol: Anthropic Messages into LiteLLM.

## Install

Requirements: macOS, Claude Code, Python 3.13.x, Rust/Cargo, `jq`, `node`,
`ruby`, `ripgrep`, `perl`, and `curl`. LiteLLM 1.92.0 supports Python `<3.14`
and has no macOS wheel, so a fresh runtime builds its native extension from
source. If `rustup` is already installed, the installer can prepare its pinned
minimal Rust 1.97.0 toolchain;
otherwise install a current Rust first (for example, `brew install rust`).

```zsh
git clone https://github.com/xz0831/claude-litellm.git
cd claude-litellm
./scripts/install.zsh
```

The Python dependency contract has direct pins in
`config/python-requirements.in` and a fully resolved, hash-locked
`config/python-requirements.lock`. The installer uses pip's `--require-hashes`
mode rather than resolving during installation. The current direct pins are
LiteLLM 1.92.0, Prisma 0.15.0, and pip 26.1.2 on Python 3.13; Rust 1.97.0 is the
pinned macOS build toolchain. The installer records source/runtime provenance
and a deterministic byte fingerprint of `pyvenv.cfg`, the complete runtime
`bin` tree, and complete `site-packages`—including `__pycache__` directories and
`.pyc` files—then publishes one shim:

```text
~/.local/share/claude-litellm
~/.local/bin/claude-litellm
```

Python 3.13 is the gateway runtime. oMLX may keep its own Homebrew Python 3.11
dependency; the two environments are isolated.

Legacy `ai-litellm-fabric` and `ai-litellm` installations are migrated through a
byte-verified full backup under `~/.local/share/claude-litellm-backups`. Claude
transcripts/history are preserved; Codex state remains in the backup but is not
imported into the Claude-only package.

## Use

Launch the configured default tier:

```zsh
claude-litellm key set --keychain OPENROUTER_API_KEY
claude-litellm
```

The packaged default is OpenRouter-backed. If its credential is absent, launch
stops before the proxy starts and prints the exact key command; it never falls
through to an ambient provider credential.

Select a Claude tier or a real LiteLLM route:

```zsh
claude-litellm fable
claude-litellm GPT-5.4-chatgpt-oauth
claude-litellm Grok-4.5-xai-oauth
claude-litellm Qwen3.6-27B-omlx
```

Claude arguments pass through normally:

```zsh
claude-litellm opus -p 'Review this repository'
```

One Claude process is pinned to the route selected at launch. Every Claude tier
and subagent points to that validated route because effort, context, and output
settings are process-global. To change providers, exit and relaunch
`claude-litellm <route>`; in-session `/model` is not a cross-provider switch.

## OAuth

OAuth is explicit. A background proxy refreshes existing tokens but fails fast
instead of starting an interactive login when credentials are missing or
refresh is no longer possible. A logged-out ChatGPT deployment is omitted from
the live router; a successful login or logout automatically restarts an already
running managed proxy so its route set matches the new credential state:

```zsh
claude-litellm auth login chatgpt
claude-litellm auth login grok
claude-litellm auth status
claude-litellm auth logout chatgpt
```

- ChatGPT uses LiteLLM's `chatgpt/*` device-code provider. It is experimental:
  LiteLLM implements the ChatGPT Codex subscription backend, but OpenAI does not
  document that backend as a general Claude Code gateway contract. If a stored
  refresh token becomes invalid, startup fails closed; repair it with
  `claude-litellm auth login chatgpt --force` (or log out to remove the route).
- Grok uses LiteLLM's xAI OAuth adapter (`use_xai_oauth: true`) with OIDC/PKCE.
  It is experimental and account-entitlement dependent: LiteLLM requests
  `api:access` and sends the token to `api.x.ai`, so a Grok consumer
  subscription alone does not prove inference access and may return 403.
- API-key routes remain independent fallbacks. A parallel xAI API-key route must
  use a route-specific variable such as `XAI_FALLBACK_API_KEY`, because the
  provider-global `XAI_API_KEY` would override the OAuth-marked route.

Offline CI validates adapter imports, route boot, token paths, refresh behavior,
redaction and Anthropic/tool translation. It deliberately does not authorize a
real subscription account. After login, run live qualification; its six gates
include Claude-style system blocks, text streaming, tool calls, continuation,
and adaptive effort before treating an OAuth route as end-to-end qualified.

LiteLLM 1.92.0 has an upstream ChatGPT streaming defect where a valid
`response.output_item.done` can be lost when `response.completed.output` is
empty. The managed bootstrap applies an exact-version, ChatGPT-only recovery
shim and refuses startup if that required shim is inactive.

OAuth tokens are stored under `~/.local/share/claude-litellm/state/auth` with
private permissions and are scrubbed from the Claude child environment. This
reduces accidental propagation; it is not a sandbox against code running as the
same macOS user.

## Operations

```zsh
claude-litellm status
claude-litellm doctor
claude-litellm sync
claude-litellm proxy start
claude-litellm proxy stop
claude-litellm proxy restart
claude-litellm model list
claude-litellm model limits <route>
claude-litellm model add <openrouter-id> --name <route>
claude-litellm model register <route> --backend <provider/model> --context N --output N --api-key-env ENV_VAR|none
claude-litellm model qualify <route> --activate-tier sonnet
claude-litellm model reasoning probe <route> high --candidate
claude-litellm key set --keychain OPENROUTER_API_KEY
claude-litellm uninstall
```

`doctor` fails on unsafe overlay permissions, runtime/provenance drift, invalid
OAuth token permissions, broken proxy policy, or provider-backed context
overclaims. Provider underclaims remain warnings because they are conservative.
Proxy startup also rejects stale or directly modified generated configuration,
runtime package-byte drift, and Python imports shadowed by the caller's working
directory or `PYTHONPATH`.

Package defaults are immutable. `model add/register/remove` and Claude
alias/reasoning updates write private user overlays under
`~/.config/claude-litellm`; `sync` renders the effective files consumed by
LiteLLM and Claude Code. Reinstall replaces package defaults, preserves those
overlays, and regenerates the effective configuration. Direct edits below the
installed package are generated-state edits and are intentionally discarded.
The one deliberate exception is the validated, runtime-owned local-discovery
block: its last-known-good routes survive an offline sync/reinstall until a
successful runtime discovery replaces them.

`model register` intentionally covers simple single-API-key or no-auth routes
and OpenAI-compatible endpoints; it is not an arbitrary LiteLLM configuration
passthrough. Complex cloud auth needs a reviewed source change and reinstall.
The ChatGPT/xAI OAuth names are fixed package routes: `--api-key-env none`
means genuinely no authentication, not OAuth.

## Included routes

- `Kimi-K2.7-Code-openrouter`
- `GLM-5.2-openrouter`
- `Mimo-V2.5-openrouter`
- `Qwen3.6-27B-omlx`
- `Qwen3.6-35B-A3B-4bit-omlx`
- `GPT-5.4-chatgpt-oauth`
- `Grok-4.5-xai-oauth`

The packaged Claude tier defaults are in `config/claude-litellm/settings.json`;
user choices are stored in `~/.config/claude-litellm/settings.json`. Any
registered real route can also be selected directly without pretending it is
an Anthropic model.

## Safety

- The generated Claude settings overlay forces `permissions.defaultMode="default"`.
- Provider secrets are resolved at proxy startup from the package env file or
  macOS Keychain (a caller's environment is also accepted but discouraged), and
  are not inherited by tools Claude launches.
- Context pre-call checks count messages, system/instruction content, tool
  schemas and calls, reserved output, and tokenizer headroom; an unbounded or
  over-window generation is rejected before dispatch. Estimated-input cost
  guardrails apply separately to every route. Output clamps apply when the
  provider accepts token-limit fields.
  LiteLLM's ChatGPT subscription adapter intentionally strips those fields, so
  that experimental route relies on GPT-5.4's natural output cap rather than a
  lower gateway-enforced cap.
- Project auth status/JSON and guarded refresh errors do not render ChatGPT or
  Grok OAuth token payloads. Do not enable third-party trace logging around
  credentials.
- Native `claude`, `~/.claude`, native `codex`, and `~/.codex` are not modified.

This is a localhost, trusted-user gateway—not an adversarial containment
boundary. Claude and tools running under the same Unix account can read files
that account can read, and the client token currently authenticates with the
LiteLLM master key. Use a separate OS account or container when running
untrusted models, tools, or repository code.

The installed public shim pins the manifest digest. Before managed shell
libraries, callbacks, or the virtual environment run, an external Python 3.13
process in isolated `-I -B -S` mode verifies that manifest, the
manifest-pinned verifier, the exact package allow-list, and the complete
managed-runtime fingerprint.

This is unsigned, user-owned integrity: it detects accidental drift and
uncoordinated replacement, but a process controlling the same Unix account can
replace the shim, manifest, verifier, package, and runtime together. Source and
distribution authenticity therefore remain outside this mechanism.

Default uninstall preserves package state—including OAuth files, isolated
Claude history/transcripts, and logs—in a private timestamped backup below
`~/.local/state/claude-litellm/uninstall-backups`. `--purge-state` is the
explicit destructive variant. User overlays and Keychain entries remain.

## Verify

```zsh
./scripts/check.zsh
./scripts/verify_litellm_token_clamp.py --json
./scripts/verify_tool_call_fidelity.py --json
~/.local/share/claude-litellm/runtime/venv/bin/python scripts/verify_user_config_overlay.py
```

To intentionally update a direct pin or adopt newer compatible transitive
dependencies, edit `config/python-requirements.in`, regenerate the full lock,
review its diff, and run the repository checks:

```zsh
uv pip compile --python-version 3.13 --python-platform macos \
  --generate-hashes --no-header --upgrade \
  --output-file config/python-requirements.lock \
  config/python-requirements.in
./scripts/check.zsh
```

The CI pin moves only after the Anthropic translation, streaming tools,
multi-turn reasoning resume, token policy, OAuth configuration, and redaction
tests pass against the new LiteLLM release.

Reasoning support does not automatically imply an effort-control slot. The
wrapper validates model-specific effort levels and refuses unsupported
`--effort` values instead of silently dropping them.

Claude Code 2.1.207 also emits `thinking: {type: adaptive}` with
`output_config.effort` even when the user did not pass `--effort`. On a route
with no validated selectable slot, the wrapper warns and the gateway removes
only the effort selection while retaining adaptive/provider-default reasoning.
On a route with one allowed effort, the incoming shared/default effort is
normalized to that sole value. Qualification includes this request shape as a
sixth gate; a successful gate proves policy-compatible transport, not that the
provider changed its exploration depth.

For OpenRouter on the pinned LiteLLM 1.92 transport, raw `xhigh`/`max` catalog
claims are retained for audit but are not selectable when LiteLLM would
normalize them to `high`.

For ChatGPT OAuth specifically, LiteLLM has a local reasoning slot and can
translate Claude's adaptive-thinking effort shape. The route still advertises
no selectable levels: a 2xx response or returned reasoning proves neither that
the upstream honored the requested level nor that it changed exploration. That
requires repeated low/high comparison and, ideally, an outbound provider trace.

See [model runbook](docs/MODEL-RUNBOOK.md),
[architecture](docs/ARCHITECTURE.md), [providers](docs/PROVIDERS.md), and
[migration](docs/MIGRATION.md) for the maintained design contract.
