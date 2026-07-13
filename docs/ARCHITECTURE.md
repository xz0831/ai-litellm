# Architecture

`claude-litellm` has one harness and one gateway boundary:

```text
Claude Code
  -> Anthropic Messages API on localhost
  -> LiteLLM 1.92.0
     -> OpenRouter and other API-key providers
     -> OpenAI-compatible local runtimes such as oMLX
     -> ChatGPT subscription OAuth (`chatgpt/*`)
     -> xAI OAuth (`xai/*` with `use_xai_oauth`)
```

Codex is intentionally not wrapped. Codex custom providers use the Responses
wire protocol and require a model catalog that controls tools, streaming events,
compaction, reasoning and multimodal capabilities. Pretending arbitrary models
have GPT capabilities was both brittle and unsafe. Native `codex` remains
untouched and is the supported way to use ChatGPT OAuth with the Codex product.

## Boundaries

- Claude Code sees one authenticated localhost gateway and real route names.
- LiteLLM owns provider translation, OAuth refresh and API-key injection.
- OAuth tokens live under the package state directory with mode `0700` parents
  and mode `0600` files. They are never copied into Claude's child environment.
- Claude transcripts and history are isolated from native Claude sessions, while
  user settings, plugins, skills and instructions are shared deliberately.
- The generated Claude proxy settings overlay forces
  `permissions.defaultMode="default"`, including upgrades from stale unsafe
  overlays.
- Provider limits are data. A configured input limit above the currently selected
  provider limit is a failing doctor condition, not an informational warning.
- Pre-call context checks and the estimated-input cost guardrail remain active
  for every route. Output reservation/clamping is enforceable only when the
  provider accepts token-limit fields. LiteLLM's ChatGPT subscription adapter
  strips those fields, so that route relies on the model's natural output cap.

## Provider classes

API-key providers resolve keys when the proxy starts. The package env file and
macOS Keychain are the supported stores; an inherited shell environment is also
accepted for compatibility but discouraged. The wrapper scrubs those
credentials from the Claude Code process and from tools the model launches.

That scrubbing prevents accidental propagation, not same-user access. This is a
localhost gateway for trusted code: Claude and its tools run as the same Unix
user and can read that user's accessible files, including package state, and the
client currently authenticates to LiteLLM with its master/admin key. Adversarial
containment requires a separate OS account or container.

Local providers use an explicit loopback `api_base` and do not require a secret.

OAuth providers require an explicit login command before the proxy can route to
them. The proxy is launched through a package bootstrap that installs the
pinned OAuth hook before LiteLLM constructs any deployment. The hook disables
LiteLLM's ChatGPT device-code fallback when credentials are missing or refresh
fails, so the proxy never blocks on an interactive background login. ChatGPT is
omitted from the live router while logged out; login/logout restarts an already
running managed proxy to load or unload the route. ChatGPT
OAuth is marked experimental because LiteLLM implements the Codex subscription
backend, while OpenAI does not document that backend as a general third-party
gateway contract. xAI OAuth uses LiteLLM's first-party xAI OAuth adapter.

The managed proxy is intentionally single-process. `NUM_WORKERS` is pinned to
`1`, and reload, gunicorn, hypercorn, Granian and multi-worker modes are rejected
because a child worker would re-import LiteLLM without the parent process's
OAuth safety hooks. Scale-out should use separate isolated gateway instances,
not workers inside one claude-litellm process.

## Compatibility policy

The pinned LiteLLM version is part of the product, not an ambient dependency.
An upgrade requires all deterministic translation, effort, OAuth redaction and
tool-resume tests to pass before the pin moves. Installed packages record the
source commit and runtime versions so `doctor` can detect drift.

The model registry and Claude alias settings are managed but intentionally
mutable. Their install-time SHA-256 baselines are recorded in the manifest. A
reinstall accepts an unchanged baseline (and can apply new source defaults), but
aborts before proxy shutdown or package mutation when user drift is detected.
Custom routes, reasoning settings, discovered routes, and alias changes must be
reconciled into the source checkout before upgrading; they are never silently
overwritten.

`config/ai-litellm/settings.json` (server/runtime policy) has no public mutator
and remains package-managed. Change it in the source checkout and reinstall;
the mutable-file drift contract is intentionally limited to files the public
CLI can edit.
