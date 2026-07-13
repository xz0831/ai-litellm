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

Requirements: macOS, Claude Code, Python 3.11.x, `jq`, `node`, `ruby`,
`ripgrep`, `perl`, and `curl`.

```zsh
git clone https://github.com/xz0831/claude-litellm.git
cd claude-litellm
./scripts/install.zsh
```

The installer creates an isolated runtime pinned to LiteLLM 1.92.0 plus Prisma,
records source/runtime provenance, and publishes one shim:

```text
~/.local/share/claude-litellm
~/.local/bin/claude-litellm
```

Legacy `ai-litellm-fabric` and `ai-litellm` installations are migrated through a
byte-verified full backup under `~/.local/share/claude-litellm-backups`. Claude
transcripts/history are preserved; Codex state remains in the backup but is not
imported into the Claude-only package.

## Use

Launch the configured default tier:

```zsh
claude-litellm
```

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
real subscription account. After login, run a live tool-call probe before
treating either OAuth route as account-level end-to-end qualified.

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
claude-litellm key set --keychain OPENROUTER_API_KEY
claude-litellm uninstall
```

`doctor` fails on unsafe overlay permissions, runtime/provenance drift, invalid
OAuth token permissions, broken proxy policy, or provider-backed context
overclaims. Provider underclaims remain warnings because they are conservative.

`model add/remove/reasoning`, `sync`, and Claude alias updates change installed
managed configuration. The manifest records its baseline hashes; a later
reinstall deliberately refuses before touching the proxy or runtime if those
files drifted. Merge wanted changes into the source checkout (or manually
restore the recorded baseline) before upgrading, so an update never silently
erases custom providers or aliases.

## Included routes

- `Kimi-K2.7-Code-openrouter`
- `GLM-5.2-openrouter`
- `Mimo-V2.5-openrouter`
- `Qwen3.6-27B-omlx`
- `Qwen3.6-35B-A3B-4bit-omlx`
- `GPT-5.4-chatgpt-oauth`
- `Grok-4.5-xai-oauth`

The Claude tier aliases are configured in
`config/claude-litellm/settings.json`. Any registered real route can also be
selected directly without pretending it is an Anthropic model.

## Safety

- The generated Claude settings overlay forces `permissions.defaultMode="default"`.
- Provider secrets are resolved at proxy startup from the package env file or
  macOS Keychain (a caller's environment is also accepted but discouraged), and
  are not inherited by tools Claude launches.
- Context pre-call checks and estimated-input cost guardrails apply to every
  route. Output clamps apply when the provider accepts token-limit fields.
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

## Verify

```zsh
./scripts/check.zsh
./scripts/verify_litellm_token_clamp.py --json
./scripts/verify_tool_call_fidelity.py --json
```

The CI pin moves only after the Anthropic translation, streaming tools,
multi-turn reasoning resume, token policy, OAuth configuration, and redaction
tests pass against the new LiteLLM release.

Reasoning support does not automatically imply an effort-control slot. The
wrapper validates model-specific effort levels and refuses unsupported
`--effort` values instead of silently dropping them.

See [architecture](docs/ARCHITECTURE.md), [providers](docs/PROVIDERS.md), and
[migration](docs/MIGRATION.md) for the maintained design contract.
