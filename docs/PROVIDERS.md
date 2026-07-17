# Providers

## OpenRouter and API keys

OpenRouter routes use `OPENROUTER_API_KEY`, resolved at proxy startup from the
package env file or macOS Keychain. An inherited shell value is accepted but
discouraged. `claude-litellm model add <openrouter-id>` reads the live catalog
and writes a durable user route.

Simple API-key providers and compatible APIs use `model register`. Supply a
LiteLLM backend identifier, explicit limits, an optional HTTPS/loopback base
URL, and a required environment-variable *name* (or explicit `none` for a
no-auth local endpoint). Literal credentials and gateway-reserved variables
such as `LITELLM_MASTER_KEY` are rejected. Every referenced provider variable
is dynamically scrubbed from Claude Code and tools it launches.
Package defaults stay in the install prefix; user routes stay in
`~/.config/claude-litellm/models.json` and survive reinstall.
The Keychain writer accepts printable ASCII provider tokens and keeps their
bytes out of process arguments. Non-ASCII/binary credentials must use the
private env-file storage mode.

This command supports single-API-key or no-auth backends expressible with its
documented fields; it is not an arbitrary LiteLLM configuration passthrough.
Azure, Bedrock, Vertex, OCI, and other complex auth need a reviewed source
change. ChatGPT/xAI OAuth routes are package-defined because their adapters
require omitted keys or dedicated flags. `--api-key-env none` means no
authentication and does not select OAuth.

`model refresh-capabilities --check` audits both packaged and user-added
OpenRouter routes. If a user route drifts, move any Claude alias away, remove
and re-add it from the current catalog, qualify it again, then reactivate it.

## oMLX and local OpenAI-compatible servers

Local routes use `openai/<model>` with a loopback `api_base`. They remain behind
the same Anthropic-to-OpenAI translation and tool-fidelity tests as cloud routes.

oMLX discovery is automatic on `sync`. The validated last-known-good discovery
block is retained when oMLX is temporarily unavailable; a successful discovery
atomically replaces it. Qwen3.5 and Qwen3.6 models must receive
`litellm_params.extra_body.chat_template_kwargs.enable_thinking=false`. LiteLLM
merges that `extra_body` value into the final OpenAI-compatible request, so oMLX
receives top-level `chat_template_kwargs`. With default thinking, tested Qwen3.5
models emitted textual `<tool_call>` markup; Qwen3.6-27B returned repetitive
reasoning text and no forced tool call. Thinking-off produced native structured
tool calls. Nesting `chat_template_kwargs` one level deeper in the final request
does not disable the template and is not equivalent.
Exactly one runtime may enable `discoverModels`; multiple non-discovering
runtimes are allowed, but two discovery owners are rejected rather than merged
ambiguously.

## ChatGPT OAuth

The `chatgpt/*` provider in LiteLLM 1.92.0 implements device-code login, refresh
tokens and the ChatGPT Codex backend. `GPT-5.4-chatgpt-oauth` is the initial
route. This route is experimental: it is useful and implemented upstream in
LiteLLM, but it is not an OpenAI-supported general API contract for Claude Code.
Use native Codex or an OpenAI Platform API key when a supported OpenAI contract
is required. LiteLLM documents that this subscription adapter rejects and
strips token-limit fields, so the gateway cannot enforce a lower per-request
output cap on this route; it relies on GPT-5.4's natural model cap.

The managed proxy installs the non-interactive OAuth guard before LiteLLM
initialization. While logged out, the ChatGPT deployment fails closed and is
absent from the live router rather than opening a device flow. Explicit
login/logout restarts a running managed proxy so that deployment state follows
credential state. The managed bootstrap also removes `CHATGPT_API_BASE` and
`OPENAI_CHATGPT_API_BASE` before LiteLLM imports or sends a request. OAuth bearer
tokens are pinned to LiteLLM's packaged ChatGPT backend origin in both the
authenticator base getter and Responses URL construction. The latter ignores a
request-level explicit `api_base`, closing a second redirect path; a legacy
partial-hook marker is repaired rather than trusted. Custom ChatGPT OAuth
inference origins are not supported as ambient or request configuration.

The deterministic suite does not perform a real ChatGPT subscription login or
provider request. Its generic GPT translation mock is not proof of the
`chatgpt/*` provider-specific wire. After account authorization, run
`model qualify GPT-5.4-chatgpt-oauth` for all six live transport gates, then use
a real Claude Code `--print` request as a separate end-client smoke test.

LiteLLM 1.92.0 also drops streamed output items when ChatGPT closes with an
empty `response.completed.output`. The package carries a version-gated recovery
shim for this known upstream defect and an offline text/tool regression test.
It also mishandles Claude Code's list-valued Anthropic system prompt by leaving
it as a Responses `role=system` input, which the ChatGPT Codex backend rejects.
The same exact-version shim flattens ChatGPT text blocks into top-level
`instructions`; it preserves text order, deliberately drops Anthropic-only
`cache_control` hints, and fails locally on a future non-text system block.
Live qualification includes this real Claude system-block shape, so a minimal
user-only request can no longer produce a false qualification.

## Grok OAuth

The `Grok-4.5-xai-oauth` route uses LiteLLM's `xai/*` provider with
`use_xai_oauth: true`. Login uses xAI OIDC/PKCE and refreshes the stored token.
This route is experimental and entitlement-dependent. LiteLLM requests the
`api:access` scope and sends the bearer token to `https://api.x.ai/v1`; a Grok
consumer subscription is not by itself evidence that the account has xAI API
inference access, so the live route can return 403.
An API-key route can coexist as a stable fallback, but it must reference a
route-specific variable such as `XAI_FALLBACK_API_KEY`, not the provider-global
`XAI_API_KEY`: LiteLLM gives that global key precedence even on an OAuth-marked
route. Never attach an API key to the OAuth route itself.
The managed bootstrap removes `XAI_OAUTH_API_BASE` and `XAI_API_BASE` before
LiteLLM imports or sends an OAuth request, and the guarded adapter method returns
the packaged xAI API origin even if a later loader reintroduces either variable.
Offline tests validate xAI OAuth adapter selection and safe refresh behavior,
but `model qualify Grok-4.5-xai-oauth` is still required after account
authorization; it covers the complete six-gate contract rather than only a
single tool-call probe. A real Claude Code smoke remains a separate final check.
The 500K input window comes from xAI's Grok 4.5 model catalog. xAI does not
publish a separate maximum completion length, so this project deliberately uses
a conservative 32K owned-policy output ceiling instead of claiming 500K output.

## Effort

Claude's effort flag is intent, not proof that a provider supports discrete
reasoning levels. Only levels supported by provider metadata and the translated
wire contract should be advertised; a successful response still does not prove
behavioral impact. Missing or unsupported effort fields must be visible in
`doctor`; global silent dropping is not treated as capability support.

The registry therefore stores `model_info.x_reasoning_efforts` separately from
`supports_reasoning`. Current provider contracts are:

- Kimi K2.7 Code and MiMo V2.5: reasoning is available, but no selectable
  effort levels are advertised. Their sixth-gate PASS means the gateway removed
  the unsupported `high` selection while retaining adaptive/provider-default
  reasoning; it is not evidence that `high` reached the upstream.
- GLM 5.2 through OpenRouter: OpenRouter advertises `xhigh` and `high`, but the
  effective selectable contract is `high` only. LiteLLM 1.92's Anthropic
  pass-through adapter checks its own model registry and normalizes both
  unqualified `xhigh` and `max` to `high` before constructing the downstream
  request. Exposing either alias as a distinct level would therefore advertise
  multiple choices for one effective wire value.
- GPT-5.4 through ChatGPT OAuth: LiteLLM's local adapter has a reasoning slot
  and translates Claude's adaptive-thinking effort form. LiteLLM metadata does
  not publish selectable levels for this subscription route, and the logged-in
  upstream has not been traced or behaviorally compared. Explicit effort is
  therefore disabled pending that evidence, not because the local slot is
  absent. Its sixth-gate PASS likewise tests the gateway's remove-and-preserve
  policy, not upstream receipt of `high`.
- Grok 4.5: `low`, `medium`, `high`; reasoning cannot be disabled.

`claude-litellm` rejects an explicit unsupported `--effort` before starting the
proxy. This makes a missing provider slot observable instead of allowing
LiteLLM's broad `drop_params` compatibility policy to create a false impression
that the model searched or reasoned more deeply.

Claude Code 2.1.212 sends adaptive thinking plus `output_config.effort` even
without an explicit flag. The wrapper treats that shared/default value as
intent and applies the selected route contract:

- With no selectable effort slot, it warns; the gateway strips
  `output_config.effort`/equivalent effort fields but retains adaptive thinking,
  leaving depth to the provider default.
- With exactly one allowed level, the wrapper selects it when necessary and the
  gateway normalizes any incoming effort to that sole value.
- With multiple allowed levels, validated values are preserved and unsupported
  values are rejected.

The sixth live qualification gate sends the same adaptive-thinking plus
`output_config.effort` shape and requires a non-empty successful response under
that route policy. It proves that the gateway handled the shape consistently;
it does not prove that an untraceable upstream honored a particular depth.

OpenRouter catalog routes retain raw claims in
`x_provider_reasoning_efforts`, while `x_reasoning_efforts` contains only the
effective selectable values. Capability audit JSON reports both. User-registered
routes likewise reject `xhigh`/`max` until a pinned adapter/model-registry
combination is qualified to preserve those values; they are never silently
downgraded by this project's CLI.

Every Claude tier and subagent is pinned to the route selected for the current
process. Provider changes require exiting and relaunching, keeping the
process-global effort/context/output contract aligned with one backend.
