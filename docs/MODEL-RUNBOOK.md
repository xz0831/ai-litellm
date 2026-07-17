# Model change runbook

Every model follows the same lifecycle:

```text
register/discover -> inspect limits -> qualify /v1/messages -> activate tier
```

Activation is last. `model qualify --activate-tier` changes a Claude tier only
when all six compatibility gates pass. Direct `harness alias set` remains an
explicit administrative bypass. `claude-litellm use <route> --default` is the
short, safe form for qualifying a concrete route and replacing whichever
preset currently backs a no-argument launch.

Choose the integration path from the model's credential and endpoint shape:

| Model source | Establish the route |
| --- | --- |
| Packaged OpenRouter route | Store `OPENROUTER_API_KEY`; the route already exists |
| Additional OpenRouter catalog model | `model add <openrouter-id> --name <surface>` |
| Running oMLX model | `sync` discovers it from the loopback `/v1/models` response |
| Packaged ChatGPT/Grok subscription route | `auth login chatgpt` or `auth login grok` |
| Simple LiteLLM/API-compatible backend | `model register` with one API-key variable or explicit `none` |
| Multi-field cloud authentication | Reviewed source configuration and reinstall |

For every path, inspect the resulting route, qualify it, then exit and relaunch
`claude-litellm use <route>` to change the provider used by Claude Code. The
historical short form `claude-litellm <route>` remains equivalent.

## Configuration layers

- Package defaults: installed `config/litellm_config.base.yaml` and
  `config/claude-litellm/settings.base.json`
- User models: `~/.config/claude-litellm/models.json`
- User aliases/reasoning/permission mode: `~/.config/claude-litellm/settings.json`
- Generated effective files: the historical non-`.base` paths in the package

Do not edit generated effective files. Under one mutation lock,
`claude-litellm sync` atomically replaces each generated file from package
defaults and private user overlays, then refreshes oMLX routes.
Only the validated runtime-owned discovery block is carried forward when oMLX
is offline; the next successful discovery replaces it.

## Selecting and replacing the default

Launch a concrete registered route without changing configuration:

```zsh
claude-litellm use <route> [claude args...]
```

Replace the route used by `claude-litellm` with no model argument:

```zsh
claude-litellm use <concrete-route> --default
```

The second command is persistence-only: it does not launch Claude or accept
Claude arguments. It resolves the current default preset, performs the same
six live/billable gates as `model qualify`, and updates that preset only on
PASS. Preset names such as `opus` are rejected here because following one
preset into another would make the requested durable mapping ambiguous. Use a
route name from `claude-litellm --list`.

## OpenRouter

Store the key once. Packaged OpenRouter routes already exist, so inspect and
qualify one directly:

```zsh
claude-litellm key set --keychain OPENROUTER_API_KEY
claude-litellm model limits Kimi-K2.7-Code-openrouter --json
claude-litellm model qualify Kimi-K2.7-Code-openrouter \
  --activate-tier sonnet
```

To add a different model from the live catalog:

```zsh
claude-litellm model add <openrouter-id> --name <surface>
claude-litellm model limits <surface> --json
claude-litellm model qualify <surface> --activate-tier sonnet
```

Keychain storage accepts printable ASCII API tokens. The non-interactive writer
passes the credential through `security` command stdin rather than process
arguments; use `key set --env-file` for a credential containing other bytes.

`model add` reads OpenRouter's current context, output and reasoning metadata.
Use `--dry-run` to inspect the route without writing. `--claude-tier` on
`model add` is a compatibility shortcut that bypasses qualification; prefer the
separate qualification command above.

## Simple API-key providers or compatible APIs

Register the LiteLLM backend and verified limits. Pass only the environment
variable name, never the credential value:

```zsh
claude-litellm model register My-Provider-model \
  --backend provider/model-id \
  --context 131072 \
  --output 16384 \
  --api-key-env PROVIDER_API_KEY

claude-litellm key set --keychain PROVIDER_API_KEY
claude-litellm model qualify My-Provider-model --activate-tier opus
```

This registration surface is deliberately narrow: single-API-key/no-auth
LiteLLM routes and OpenAI-compatible endpoints expressible with the shown
fields. Azure, Bedrock, Vertex, OCI, and other multi-field/provider-specific
auth require a reviewed source configuration and reinstall. Package-defined
ChatGPT/xAI OAuth routes cannot be created with `model register`;
`--api-key-env none` means no authentication, not OAuth.

User and runtime-discovered surface names may not collide with the four Claude
presets or top-level commands such as `use`, `model`, `permissions`, and
`status`. Rejecting those reserved names ensures both the explicit and short
launch forms always resolve the same concrete route.

For an OpenAI-compatible endpoint, add `--api-base https://.../v1`. Plain HTTP
is accepted only for `localhost`, `127.0.0.1`, or `::1`. A local endpoint that
needs no key must use `--api-key-env none`; every registration must explicitly
choose `ENV_VAR` or `none`. Gateway credentials such as `LITELLM_MASTER_KEY`
cannot be reused as provider keys, and provider variables are scrubbed from the
Claude/tool child environment. Optional declarations are
`--supports-reasoning` or `--reasoning-efforts low,medium,high`; these remain
user claims. `xhigh` and `max` are rejected for user routes: LiteLLM 1.92
normalizes those values to `high` when its Anthropic adapter has no matching
model-registry capability flag, so accepting them would create false choices.
Qualification tests Anthropic text/tool compatibility and the gateway policy
for Claude Code's real adaptive-effort request shape. It does not prove that a
provider honored a distinct effort level, nor does it prove provider limits.

## ChatGPT and Grok OAuth

Authorize explicitly, inspect token presence, and then qualify each package
route before assigning it to a tier:

```zsh
claude-litellm auth login chatgpt
claude-litellm auth login grok
claude-litellm auth status --json
claude-litellm model qualify GPT-5.4-chatgpt-oauth \
  --activate-tier sonnet
claude-litellm model qualify Grok-4.5-xai-oauth
claude-litellm GPT-5.4-chatgpt-oauth -p 'Reply exactly READY'
```

Login and logout hold the shared mutation lock. If the managed proxy is already
running, the command stops it for the credential change and restores its prior
running state afterward so the live deployment set is refreshed. Use
`auth login <provider> --force` to discard that provider's stored credential
and perform a fresh login, or `auth logout <provider>` to remove it.

`authenticated: true` means stored token material is present; it is not proof
of inference entitlement, current upstream availability, or Claude Code
compatibility. ChatGPT is omitted from the live router while logged out. Grok's
adapter initializes lazily, but the launcher still blocks that route before a
request when its OAuth state is missing. After any login, provider/runtime
upgrade, or relevant gateway change, rerun the six live gates. A short real
Claude Code `--print` smoke is a separate final check of the client path.

## oMLX

Start/load models through oMLX, then discover and qualify them:

```zsh
omlx start
claude-litellm sync
claude-litellm model list
claude-litellm model qualify Qwen3.5-9B-MLX-8bit-omlx \
  --activate-tier haiku
```

The packaged runtime policy applies
`extra_body.chat_template_kwargs.enable_thinking=false` to `Qwen3.5*` and
`Qwen3.6*`. LiteLLM merges `extra_body` into the outgoing request, so the oMLX
wire must contain top-level `chat_template_kwargs.enable_thinking=false`; an
extra nested `extra_body` on that final wire is ineffective. Live tests found
that default thinking exposed reasoning or returned text instead of a native
forced tool call, while thinking-off produced structured tool calls. The
packaged `Qwen3.6-27B-omlx` and `Qwen3.6-35B-A3B-4bit-omlx` routes carry the
same override directly.

If a model is unloaded, run `sync` again. A durable tier alias may temporarily
refer to an unavailable discovered route; `doctor`/launch will make that state
visible instead of silently selecting another model.

Exactly one runtime may enable `discoverModels`. Multiple non-discovering
runtimes are fine, but two discovery owners are rejected instead of competing
for the single generated block.

## Qualification contract

The live command keeps structured tool-call requests at `max_tokens=128`.
Text SSE, Claude system-block, tool-result continuation, and adaptive-effort
requests use `max_tokens=512` so reasoning-first models have room to finish a
visible answer. It requires:

1. Anthropic text SSE with a non-empty text delta and clean `message_stop`
2. Two Claude-style system text blocks—including an ephemeral cache hint on the
   first—whose two response markers survive, with a clean completed stream
3. Forced tool selection returned as a native `tool_use`
4. Streaming `input_json_delta` fragments that reconstruct valid JSON and end
   with a clean `message_stop`
5. A successful continuation after replaying the exact assistant content
   (including thinking/signatures) and actual tool ID in `tool_result`
6. A non-empty successful response to Claude Code's adaptive-thinking request
   with `output_config.effort: high`, after applying the route's effort policy

The verifier can run for up to 420 seconds and makes up to six requests; cloud
qualification can therefore incur provider charges. If it starts a stopped
managed proxy, that proxy remains running for subsequent use.

Every completed live-verifier run atomically replaces the route's record under
the package state directory. A gate-set v2 record contains `attemptedAt`,
`passed`, and—only on success—`qualifiedAt`, plus the provider model, verifier
exit code, effective config and verifier hashes, install-manifest hash, source
commit, runtime content fingerprint, and all gate results. A failed live-gate
run overwrites an older PASS with a failure tombstone; a preflight error before
verifier execution writes no record. Requalify after the provider, effective
config, verifier, install manifest, or runtime changes; the stored record is
historical evidence, not an automatic launch permit. Only `--activate-tier`
makes alias activation conditional on a current PASS; `use <route> --default`
delegates to that exact transaction rather than trusting old evidence.

## Reasoning and effort

`supports_reasoning` and a selectable effort list are separate capabilities.
Use:

```zsh
claude-litellm model reasoning allowed <route> --json
claude-litellm model reasoning probe <route> [effort]
claude-litellm model reasoning probe <route> high --candidate
claude-litellm harness reasoning set claude high
claude-litellm harness reasoning unset claude
```

The harness default is durable and becomes Claude Code's `--effort` intent. An
explicit unsupported `--effort` fails before proxy startup. Claude Code 2.1.212
also sends an implicit `high` effort with adaptive thinking when neither a flag
nor setting is present, so the absence of a CLI flag is not the absence of
effort on the wire. The wrapper warns when a selected route has no selectable
slot, and the gateway removes the effort fields while preserving adaptive
thinking for provider-default reasoning. A route with one allowed value
normalizes the incoming shared/default value to that sole choice; a multi-level
route preserves a supported value and rejects an unsupported one.

Effort remains process-global. Every tier and subagent in one Claude process is
pinned to its initial validated route—exit and relaunch to switch providers.
Provider-default mutations are allowed only on user-owned routes; package route
defaults are immutable.

The probe mirrors Claude Code with `thinking: {type: adaptive}` plus
`output_config.effort`. `--candidate` bypasses only the published-level
allow-list and never updates capability metadata. Even a 2xx with reasoning is
not proof that the level reached or influenced the upstream model. Compare
repeated low/high trials and inspect a provider-side outbound trace where one is
available before advertising a level.

The same `high` shape is the sixth qualification gate. Its policy depends on
the route: a selectable value is forwarded, a sole allowed value is normalized,
and a route with no selectable slot removes only effort while retaining
adaptive/provider-default reasoning. A dropped effort is never recorded as
capability evidence.

For OpenRouter, `model refresh-capabilities --json` intentionally separates the
provider's raw `supported_efforts` from the effective transport contract. With
LiteLLM 1.92, unqualified `xhigh` and `max` normalize to `high` in the Anthropic
adapter. They remain visible as provider metadata but are removed from the
selectable list, and an explicit wrapper request is rejected rather than
silently downgraded.

Audit catalog drift periodically:

```zsh
claude-litellm model refresh-capabilities --check
```

The audit covers packaged and user-added OpenRouter routes. To refresh a
drifted user route, move its alias to a known-good model, remove and re-add the
route from the current catalog, requalify it, then reactivate it.
`--apply` edits package anchors only from a source checkout and is rejected for
an installed immutable package.

## Permission mode

Permission mode is independent of model routing. The safe package default is
`default`, even if native Claude is configured for `bypassPermissions`. Inspect
or change only the wrapper's generated settings overlay with:

```zsh
claude-litellm permissions get [--json]
claude-litellm permissions set default
claude-litellm permissions set bypassPermissions
claude-litellm permissions reset
```

Only `default` and `bypassPermissions` are accepted as durable values. The
bypass choice is an explicit opt-in that disables all Claude Code permission
checks for newly launched wrapper sessions. `set default` keeps an explicit
user override whose source is reported as `user-override`; `reset` removes only
`harness.permissionMode`, preserves aliases and reasoning preferences, and
inherits the package default. The private override is mode `0600`, is written
atomically under the shared configuration lock, and survives sync/reinstall.
Direct edits to the generated proxy overlay never survive regeneration.

For a single session without persisting the choice:

```zsh
claude-litellm use <route> --dangerously-skip-permissions
```

## Rollback

Reassign a tier before removing its user route:

```zsh
claude-litellm model qualify Known-Good-route --activate-tier sonnet
claude-litellm model remove Experimental-route
```

Package routes, OAuth routes and runtime-discovered routes cannot be removed by
`model remove`. Reinstall reconstructs package/OAuth routes. `sync` owns local
discovery: it retains the last-known-good block on discovery failure, but a
successful response that no longer lists a model removes that route. Default
uninstall leaves user overlays in place and moves package state to a private
timestamped backup; `--purge-state` is the explicit destructive variant.
