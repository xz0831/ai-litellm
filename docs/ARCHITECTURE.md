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

Codex is intentionally not wrapped by this product. Current Codex supports
custom model providers configured with a base URL and `wire_api="responses"`,
so connecting another model is not fundamentally forbidden. The provider must,
however, implement the Responses wire and the tool, streaming, reasoning,
compaction and multimodal behavior Codex expects. That is a separate
qualification surface from Claude Code's Anthropic Messages contract. Native
`codex` remains untouched; this repository deliberately concentrates its test
budget on Claude Code.

## Boundaries

- Claude Code sees one authenticated localhost gateway and real route names.
- LiteLLM owns provider translation, OAuth refresh and API-key injection.
- OAuth tokens live under the package state directory with mode `0700` parents
  and mode `0600` files. They are never copied into Claude's child environment.
- Claude transcripts and history are isolated from native Claude sessions, while
  user settings, plugins, skills and instructions are shared deliberately.
- The generated Claude proxy settings overlay defaults to
  `permissions.defaultMode="default"`. A validated private user override may
  opt in to `bypassPermissions`; stale or manually edited generated overlays
  are still rewritten from the effective policy on every launch. The launcher
  freezes that policy into a private per-process snapshot under the shared
  mutation lock, passes the snapshot to Claude, and removes it when Claude
  exits, so a concurrent preference update cannot alter a starting session.
- Provider limits are data. A configured input limit above the currently selected
  provider limit is a failing doctor condition, not an informational warning.
- Pre-call context checks conservatively count messages, system/instruction
  text, tool schemas, tool-call arguments, requested output and tokenizer
  headroom. A generation request without a declared context limit, or whose
  estimated total exceeds it, is rejected before provider dispatch. This check
  is independent of the separate estimated-cost guardrail. Output
  reservation/clamping is enforceable only when the
  provider accepts token-limit fields. LiteLLM's ChatGPT subscription adapter
  strips those fields, so that route relies on the model's natural output cap.

## Provider classes

API-key providers resolve explicitly referenced keys when the proxy starts. An
inherited shell environment is checked first, followed by the private package
env file and macOS Keychain. Inherited values are accepted for compatibility
but discouraged. The wrapper scrubs those
credentials—including arbitrary variables introduced by user routes—from the
Claude Code process and from tools the model launches. Generic routes must state
`api_key: os.environ/NAME` or `api_key: none`; implicit provider-global keys and
gateway-reserved credentials are rejected.

That scrubbing prevents accidental propagation, not same-user access. This is a
localhost gateway for trusted code: Claude and its tools run as the same Unix
user and can read that user's accessible files, including package state, and the
client currently authenticates to LiteLLM with its master/admin key. Adversarial
containment requires a separate OS account or container.

Packaged oMLX routes use an explicit loopback `api_base` with no secret. A
user-registered loopback server must still declare either its dedicated API-key
environment variable or explicit `none`. The public `model register` command
intentionally covers this simple single-key/no-auth shape only; complex
provider credential schemas require a reviewed package change. OAuth routes are
package-owned, not synthesized with `api_key: none`.

OAuth providers require an explicit login command before the proxy can route to
them. The proxy is launched through a package bootstrap that installs the
pinned OAuth hook before LiteLLM constructs any deployment. The hook disables
LiteLLM's ChatGPT device-code fallback when credentials are missing or refresh
fails, so the proxy never blocks on an interactive background login. ChatGPT is
omitted from the live router while logged out; login/logout restarts an already
running managed proxy to load or unload the route. ChatGPT
OAuth is marked experimental because LiteLLM implements the Codex subscription
backend, while OpenAI does not document that backend as a general third-party
gateway contract. xAI OAuth uses LiteLLM's first-party xAI OAuth adapter. The
launcher and Python bootstrap both remove LiteLLM's ChatGPT/xAI inference-base
environment overrides before provider code runs. The OAuth guard pins the
ChatGPT and xAI authenticator base getters to packaged provider constants and
also pins ChatGPT Responses URL construction, including the request-level
`api_base` path. It repairs an older partial-hook marker rather than trusting it
as proof that every getter is guarded. OAuth routes consequently never trust an
ambient or later-injected variable for an origin that will receive a bearer
token.

The same exact-version ChatGPT hook closes two LiteLLM 1.92.0 compatibility
gaps. It recovers valid streamed output items when a terminal Responses event
omits its output list, and converts Claude Code's ordered, list-valued Anthropic
system text blocks into top-level Responses `instructions`. Anthropic-only
cache hints are dropped; an unknown non-text system block fails locally. Proxy
startup verifies these required patches before accepting traffic.

The managed proxy is intentionally single-process. `NUM_WORKERS` is pinned to
`1`, and reload, gunicorn, hypercorn, Granian and multi-worker modes are rejected
because a child worker would re-import LiteLLM without the parent process's
OAuth safety hooks. Scale-out should use separate isolated gateway instances,
not workers inside one claude-litellm process.

## Compatibility policy

The pinned LiteLLM version is part of the product, not an ambient dependency.
`config/python-requirements.in` declares the direct runtime contract:
LiteLLM 1.92.0, Prisma 0.15.0, and pip 26.1.2 on Python 3.13. The generated
`config/python-requirements.lock` pins every resolved transitive dependency and
its allowed distribution hashes; installation uses `pip --require-hashes` and
does not perform a fresh dependency resolution. An upgrade requires all
deterministic translation, effort, OAuth redaction and tool-resume tests to
pass before either direct pins or their lock move.

Claude Code and oMLX are external installations rather than files in this
Python lock. The current compatibility snapshot was exercised with Claude Code
2.1.207 and oMLX 0.5.1; a later external release requires the same live model
qualification and smoke checks rather than inheriting that result by version
assumption.

Installed packages record the source commit, runtime versions, dependency
inventory, and a path/type/mode/size/byte fingerprint of `pyvenv.cfg`, the
complete runtime `bin` tree, and every directory and file in `site-packages`.
`__pycache__` and `.pyc` are deliberately included: `-B` prevents new bytecode
writes but does not stop Python from loading a forged, timestamp-valid cache.
Reuse checks and `doctor` therefore detect version drift, added paths, and
in-place package or bytecode injection.

The public shim embeds the installed manifest's SHA-256 digest. Before managed
shell libraries, callbacks, or virtual-environment Python execute, an external
Python 3.13 interpreter running with `-I -B -S` checks that pin, checks the
verifier's digest from the manifest, enforces the exact package path allow-list,
and runs the already-hashed fingerprint helper over the managed runtime. The
managed runtime is initialized only after those checks succeed.

This chain is not a code signature or a security boundary against the owner of
the Unix account. The same user can coordinate replacement of the public shim,
manifest, verifier, package, and runtime. It is designed to fail closed on
accidental/partial drift and uncoordinated injection; repository checkout and
distribution authenticity require a separate trusted-source or signing
mechanism.

Every managed Python control path runs with an isolated import search path.
Pure runtime checks use Python isolated mode; callback loading receives only the
hashed package config directory. The caller's current directory, user site and
ambient `PYTHONPATH` cannot shadow LiteLLM, OAuth hooks, or their dependencies.

The installed model registry and Claude settings are generated outputs.
Immutable package inputs use `*.base` paths; durable user models, aliases,
reasoning preferences and the narrow Claude permission-mode opt-in live under
`~/.config/claude-litellm` with private permissions. Rendering validates names,
limits, endpoint schemes, secret references and allowlisted permission values,
then atomically replaces each output while holding the shared configuration
lock. The only effective-file state
carried forward is a structurally validated, loopback-only, runtime-owned
discovery block; sync replaces it after successful discovery and retains it on
runtime failure. Sync and user mutations share a configuration lock. Reinstall
can therefore replace package defaults without erasing user choices or losing
last-known-good local routes.

Before proxy startup, both generated outputs are rendered in memory and
compared byte-for-byte with the installed files under that same configuration
lock. Direct edits, stale callback wiring, or half-applied alias changes fail
closed with an instruction to run `claude-litellm sync`.

## Qualification evidence

`model qualify` holds the model-mutation lock across synchronization, the live
exchange, evidence publication, and optional alias activation. Gate-set v2
checks text SSE, Claude's list-valued system blocks, forced and streamed native
tool calls, exact `tool_result` continuation, and the adaptive-thinking effort
shape sent by Claude Code. A PASS is transport evidence for one provider model
and one effective gateway/runtime state; it is not a permanent provider claim
or proof that an effort level changed exploration depth.

Each completed live-verifier run atomically replaces that route's previous
record. It stores `attemptedAt`, `passed`, `providerModel`, `gateSetVersion`,
verifier exit code, effective-config/verifier/install-manifest hashes, source
commit, runtime content fingerprint, and the individual gate results.
`qualifiedAt` exists only on PASS. A failed live-gate run therefore becomes a
failure tombstone instead of leaving stale success evidence; a preflight error
that prevents verifier execution does not publish a record. Only
`model qualify --activate-tier` makes alias activation conditional on this
result. `use <route> --default` delegates to the same live transaction; direct
route launch and the administrative `harness alias set` command remain explicit
bypasses.

One Claude process maps every tier and subagent to the initial validated route.
This is deliberate: effort, compaction, context, and output controls are
process-global, so an in-session cross-provider switch could retain an invalid
budget or bypass OAuth/runtime checks. Provider changes are session boundaries.

Runtime discovery currently has one generated route block and therefore allows
only one enabled `discoverModels` runtime. Validation fails closed if multiple
runtimes request ownership of that block.

`config/ai-litellm/settings.json` (server/runtime policy) has no public mutator
and remains package-managed. Change it in the source checkout and reinstall;
the mutable-file drift contract is intentionally limited to files the public
CLI can edit.
