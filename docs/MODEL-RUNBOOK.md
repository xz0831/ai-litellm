# Model change runbook

Every model follows the same lifecycle:

```text
register/discover -> inspect limits -> qualify /v1/messages -> activate tier
```

Activation is last. `model qualify --activate-tier` changes a Claude tier only
when all five compatibility gates pass. Direct `harness alias set` remains an
explicit administrative bypass.

## Configuration layers

- Package defaults: installed `config/litellm_config.base.yaml` and
  `config/claude-litellm/settings.base.json`
- User models: `~/.config/claude-litellm/models.json`
- User aliases/reasoning: `~/.config/claude-litellm/settings.json`
- Generated effective files: the historical non-`.base` paths in the package

Do not edit generated effective files. Under one mutation lock,
`claude-litellm sync` atomically replaces each generated file from package
defaults and private user overlays, then refreshes oMLX routes.
Only the validated runtime-owned discovery block is carried forward when oMLX
is offline; the next successful discovery replaces it.

## OpenRouter

Store the key once, add the catalog model, and qualify its surface name:

```zsh
claude-litellm key set --keychain OPENROUTER_API_KEY
claude-litellm model add moonshotai/kimi-k2.7-code \
  --name Kimi-K2.7-Code-openrouter
claude-litellm model limits Kimi-K2.7-Code-openrouter --json
claude-litellm model qualify Kimi-K2.7-Code-openrouter \
  --activate-tier sonnet
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
Qualification tests Anthropic text/tool compatibility, not reasoning-effort
behavior or provider limit truth.

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
packaged Qwen3.6-27B and 35B routes carry the same override directly.

If a model is unloaded, run `sync` again. A durable tier alias may temporarily
refer to an unavailable discovered route; `doctor`/launch will make that state
visible instead of silently selecting another model.

Exactly one runtime may enable `discoverModels`. Multiple non-discovering
runtimes are fine, but two discovery owners are rejected instead of competing
for the single generated block.

## Qualification contract

The live command keeps structured tool-call requests at `max_tokens=128`.
Text SSE, tool-result continuation, and adaptive-effort requests use
`max_tokens=512` so reasoning-first models have room to finish a visible
answer. It requires:

1. Anthropic text SSE with a non-empty text delta
2. Forced tool selection returned as a native `tool_use`
3. Streaming `input_json_delta` fragments that reconstruct valid JSON
4. A successful continuation after replaying the exact assistant content
   (including thinking/signatures) and actual tool ID in `tool_result`
5. A non-empty successful response to Claude Code's adaptive-thinking request
   with `output_config.effort`, after applying the route's effort policy

Cloud qualification can incur a small provider charge. A passing record is
stored under the package state directory with timestamp, provider model,
effective-config hash and gate results. It is evidence for that configuration,
not a permanent claim about a provider that may change later.

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
explicit unsupported `--effort` fails before proxy startup. Claude Code 2.1.207
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

The same shape is the fifth qualification gate. Its policy depends on the route:
a selectable value is forwarded, a sole allowed value is normalized, and a
route with no selectable slot removes only effort while retaining
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

## Rollback

Reassign a tier before removing its user route:

```zsh
claude-litellm model qualify Known-Good-route --activate-tier sonnet
claude-litellm model remove Experimental-route
```

Package routes, OAuth routes and runtime-discovered routes cannot be removed by
`model remove`; reinstall/sync can always reconstruct them. Default uninstall
leaves user overlays in place and moves package state to a private timestamped
backup; `--purge-state` is the explicit destructive variant.
