# Providers

## OpenRouter and API keys

OpenRouter routes use `OPENROUTER_API_KEY`, resolved at proxy startup from the
package env file or macOS Keychain. An inherited shell value is accepted but
discouraged. Additional LiteLLM providers can be added to
`config/litellm_config.yaml`; never commit credentials.

When editing an installed registry through `claude-litellm model ...` or
`sync`, carry the intended change into the source checkout before reinstalling.
The installer detects registry drift and refuses the upgrade rather than
silently replacing custom routes.

## oMLX and local OpenAI-compatible servers

Local routes use `openai/<model>` with a loopback `api_base`. They remain behind
the same Anthropic-to-OpenAI translation and tool-fidelity tests as cloud routes.

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
credential state.

The deterministic suite does not perform a real ChatGPT subscription login or
provider request. Its generic GPT translation mock is not proof of the
`chatgpt/*` provider-specific wire. A live prompt plus tool call is required
after the user authorizes the account.

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
Offline tests validate xAI OAuth adapter selection and safe refresh behavior,
but a live tool-call probe is still required after account authorization.
The 500K input window comes from xAI's Grok 4.5 model catalog. xAI does not
publish a separate maximum completion length, so this project deliberately uses
a conservative 32K owned-policy output ceiling instead of claiming 500K output.

## Effort

Claude's effort flag is intent, not proof that a provider supports discrete
reasoning levels. Only levels confirmed by provider metadata and a wire test
should be advertised. Missing or unsupported effort fields must be visible in
`doctor`; global silent dropping is not treated as capability support.

The registry therefore stores `model_info.x_reasoning_efforts` separately from
`supports_reasoning`. Current provider contracts are:

- Kimi K2.7 Code and MiMo V2.5: reasoning is available, but no selectable
  effort levels are advertised.
- GLM 5.2 through OpenRouter: `high`, `xhigh`.
- GPT-5.4 through ChatGPT OAuth: reasoning is intrinsic, but selectable effort
  is not advertised by LiteLLM 1.92's `chatgpt/*` adapter and has not been
  validated on that production OAuth wire path. Explicit effort is therefore
  disabled rather than borrowing the OpenAI Platform API contract.
- Grok 4.5: `low`, `medium`, `high`; reasoning cannot be disabled.

`claude-litellm` rejects an explicit unsupported `--effort` before starting the
proxy. This makes a missing provider slot observable instead of allowing
LiteLLM's broad `drop_params` compatibility policy to create a false impression
that the model searched or reasoned more deeply.
