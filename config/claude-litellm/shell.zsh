# Claude Code on non-Anthropic models through the local LiteLLM proxy.

if ! typeset -f ai_litellm >/dev/null 2>&1 && [[ -f "${AI_LITELLM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm}/config/ai-litellm/lib.zsh" ]]; then
  source "${AI_LITELLM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm}/config/ai-litellm/lib.zsh"
elif ! typeset -f ai_litellm >/dev/null 2>&1 && [[ -f "$HOME/.config/ai-litellm/lib.zsh" ]]; then
  source "$HOME/.config/ai-litellm/lib.zsh"
fi

export CLAUDE_LITELLM_HARNESS="${CLAUDE_LITELLM_HARNESS:-claude}"
export CLAUDE_LITELLM_HOME="${CLAUDE_LITELLM_HOME:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.home 2>/dev/null || printf "${AI_LITELLM_STATE_HOME:-${AI_LITELLM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm}/state}/claude-litellm")}"
export CLAUDE_LITELLM_SETTINGS="${CLAUDE_LITELLM_SETTINGS:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settings 2>/dev/null || printf "$CLAUDE_LITELLM_HOME/settings.json")}"
export CLAUDE_LITELLM_CLAUDE_CONFIG="${CLAUDE_LITELLM_CLAUDE_CONFIG:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.configDir 2>/dev/null || printf "$CLAUDE_LITELLM_HOME/claude-config")}"
export CLAUDE_LITELLM_SETTINGS_ARG_PROXY="${CLAUDE_LITELLM_SETTINGS_ARG_PROXY:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settingsArgProxy 2>/dev/null || printf "$CLAUDE_LITELLM_HOME/overlay-settings-proxy.json")}"
export CLAUDE_LITELLM_CONFIG="${CLAUDE_LITELLM_CONFIG:-$AI_LITELLM_CONFIG}"
export CLAUDE_LITELLM_AUTH_HOME="${CLAUDE_LITELLM_AUTH_HOME:-$AI_LITELLM_STATE_HOME/auth}"
export CHATGPT_TOKEN_DIR="${CHATGPT_TOKEN_DIR:-$CLAUDE_LITELLM_AUTH_HOME/chatgpt}"
export XAI_OAUTH_TOKEN_DIR="${XAI_OAUTH_TOKEN_DIR:-$CLAUDE_LITELLM_AUTH_HOME/grok}"
export CHATGPT_DEFAULT_INSTRUCTIONS="${CHATGPT_DEFAULT_INSTRUCTIONS:-You are the model backend for Claude Code. Follow the provided instructions and tool schemas.}"

_claude_litellm_oauth_python() {
  local managed="$AI_LITELLM_HOME/runtime/venv/bin/python"
  if [[ -x "$managed" ]]; then
    print -r -- "$managed"
  else
    command -v python3
  fi
}

_claude_litellm_auth() {
  local python action was_running=0 rc
  python="$(_claude_litellm_oauth_python)" || {
    echo "claude-litellm: Python runtime is unavailable; reinstall the package." >&2
    return 1
  }
  action="${1:-}"
  if [[ "$action" == login || "$action" == logout ]]; then
    ai_litellm_pid_running && was_running=1
  fi
  "$python" "$AI_LITELLM_HOME/config/claude-litellm/oauth.py" "$@"
  rc=$?
  (( rc == 0 )) || return $rc

  # ChatGPT deployment construction resolves OAuth during proxy startup.  It is
  # intentionally omitted while logged out; restart a managed proxy after any
  # credential transition so the route is added/removed and logout cannot keep
  # using an access token cached by the old process.  Keep notices off stdout so
  # `auth ... --json` remains valid JSON.
  if (( was_running )); then
    echo "claude-litellm: OAuth state changed; restarting the managed proxy." >&2
    ai_litellm_restart >&2 || return $?
  fi
  return 0
}

_claude_litellm_oauth_provider_for_model() {
  local model="$1"
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
entry = Array(config["model_list"]).find { |item| item["model_name"] == ARGV[1] }
exit 1 unless entry
backend = entry.dig("litellm_params", "model").to_s
if backend.start_with?("chatgpt/")
  puts "chatgpt"
elsif entry.dig("litellm_params", "use_xai_oauth") == true
  puts "grok"
end
' "$AI_LITELLM_CONFIG" "$model"
}

_claude_litellm_require_oauth() {
  local model="$1" provider payload
  provider="$(_claude_litellm_oauth_provider_for_model "$model" 2>/dev/null || true)"
  [[ -n "$provider" ]] || return 0
  payload="$(_claude_litellm_auth status "$provider" --json 2>/dev/null || true)"
  if [[ -z "$payload" ]] || ! print -r -- "$payload" | jq -e '.[0].authenticated == true and .[0].permissionsSafe == true' >/dev/null 2>&1; then
    echo "claude-litellm: $provider OAuth login is required for $model." >&2
    echo "Run: claude-litellm auth login $provider" >&2
    return 1
  fi
}

_claude_litellm_oauth_doctor() {
  local python payload
  python="$(_claude_litellm_oauth_python)" || {
    echo "fail OAuth runtime: Python unavailable" >&2
    return 1
  }
  PYTHONPATH="$AI_LITELLM_CONFIG_HOME${PYTHONPATH:+:$PYTHONPATH}" "$python" -c '
import importlib.metadata
from ai_litellm_callbacks.oauth_guard import PATCH_ACTIVE
from litellm.llms.chatgpt.authenticator import Authenticator
from litellm.llms.xai.oauth import XAIOAuthAuthenticator
assert importlib.metadata.version("litellm") == "1.92.0"
assert PATCH_ACTIVE is True
' >/dev/null 2>&1 || {
    echo "fail OAuth runtime: expected LiteLLM 1.92.0 adapters and active non-interactive refresh guard" >&2
    return 1
  }
  payload="$(_claude_litellm_auth status all --json)" || return $?
  if ! print -r -- "$payload" | jq -e 'all(.[]; .permissionsSafe == true)' >/dev/null; then
    echo "fail OAuth credential file permissions are not private" >&2
    return 1
  fi
  if ! ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
routes = Array(config["model_list"])
has_xai_oauth = routes.any? { |entry| entry.dig("litellm_params", "use_xai_oauth") == true }
has_global_xai_key = routes.any? do |entry|
  entry.dig("litellm_params", "api_key").to_s == "os.environ/XAI_API_KEY"
end
if has_xai_oauth && has_global_xai_key
  warn "XAI_API_KEY takes precedence over use_xai_oauth; use a route-specific variable such as XAI_FALLBACK_API_KEY for the API-key route"
  exit 1
end
' "$AI_LITELLM_CONFIG"; then
    echo "fail OAuth/API-key route precedence is unsafe" >&2
    return 1
  fi
  echo "ok   OAuth adapters and credential permissions"
}

_claude_litellm_json() {
  ai_litellm_json_file "$CLAUDE_LITELLM_SETTINGS" "$1"
}

_claude_litellm_tiers() {
  ai_litellm_harness_json_array "$CLAUDE_LITELLM_HARNESS" models.tiers 2>/dev/null || {
    printf 'opus\nsonnet\nhaiku\n'
  }
}

_claude_litellm_is_tier() {
  local candidate="$1"
  _claude_litellm_tiers | grep -Fx -- "$candidate" >/dev/null
}

_claude_litellm_proxy_default_request() {
  _claude_litellm_json default 2>/dev/null || printf 'opus\n'
}

_claude_litellm_target_model_for_request() {
  local requested="$1"
  if [[ -z "$requested" ]]; then
    requested="$(_claude_litellm_proxy_default_request)"
  fi

  if _claude_litellm_is_tier "$requested"; then
    local target_model
    target_model="$(_claude_litellm_json "aliases.$requested" 2>/dev/null)" || return 1
    ai_litellm_model_exists "$target_model" || return 1
    printf '%s\n' "$target_model"
    return 0
  fi

  local resolved_model
  resolved_model="$(ai_litellm_model_resolve "$requested" 2>/dev/null)" || return 1
  printf '%s\n' "$resolved_model"
}

# For tiers, return the tier name itself: --model <tier> preserves Claude
# Code's native tier semantics (in-session /model opus|sonnet|haiku, background
# calls on haiku) while ANTHROPIC_DEFAULT_<TIER>_MODEL carries the real route.
_claude_litellm_resolve_model_arg() {
  local requested="$1"
  if [[ -z "$requested" ]]; then
    requested="$(_claude_litellm_proxy_default_request)"
  fi

  if _claude_litellm_is_tier "$requested"; then
    local target_model
    target_model="$(_claude_litellm_json "aliases.$requested" 2>/dev/null)" || return 1
    ai_litellm_model_exists "$target_model" || return 1
    printf '%s\n' "$requested"
    return 0
  fi

  local resolved_model
  resolved_model="$(ai_litellm_model_resolve "$requested" 2>/dev/null)" || return 1
  printf '%s\n' "$resolved_model"
}

claude-litellm-status() {
  echo "Claude settings: $CLAUDE_LITELLM_SETTINGS"
  echo "Claude config:   $CLAUDE_LITELLM_CLAUDE_CONFIG"
  echo "Overlay:         $CLAUDE_LITELLM_SETTINGS_ARG_PROXY"
  echo "Shared env root: $(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" isolation.sharedEnvironment.targetRoot 2>/dev/null || printf '(disabled)')"
  echo "Claude mode:     LiteLLM proxy"
  ai_litellm_status
  _claude_litellm_auth status all
}

claude-litellm-list() {
  echo "Claude aliases:"
  echo "  default -> $(_claude_litellm_proxy_default_request)"
  local tier
  _claude_litellm_tiers | while IFS= read -r tier; do
    printf '  %-7s -> %s\n' "$tier" "$(_claude_litellm_json "aliases.$tier" 2>/dev/null || true)"
  done
  echo
  ai_litellm_list
}

_claude_litellm_reasoning_args() {
  local harness_effort
  harness_effort="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.reasoning.effort 2>/dev/null || true)"
  if [[ -n "$harness_effort" && "$harness_effort" != "auto" && "$harness_effort" != "none" ]]; then
    if ! ai_litellm_cli_arg_present --effort "$@"; then
      printf '%s\n%s\n' --effort "$harness_effort"
    fi
  fi
}

_claude_litellm_effective_effort() {
  local arg expect_value=0
  for arg in "$@"; do
    [[ "$arg" == "--" ]] && break
    if (( expect_value )); then
      [[ -n "$arg" ]] || return 2
      print -r -- "${arg:l}"
      return 0
    fi
    case "$arg" in
      --effort) expect_value=1 ;;
      --effort=*)
        [[ -n "${arg#--effort=}" ]] || return 2
        print -r -- "${${arg#--effort=}:l}"
        return 0
        ;;
    esac
  done
  (( expect_value )) && return 2

  local configured
  configured="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.reasoning.effort 2>/dev/null || true)"
  if [[ -n "$configured" && "$configured" != "auto" && "$configured" != "none" ]]; then
    print -r -- "${configured:l}"
    return 0
  fi
  return 1
}

_claude_litellm_validate_effort() {
  local model="$1"
  shift
  local effort allowed rc
  effort="$(_claude_litellm_effective_effort "$@")"
  rc=$?
  if (( rc == 1 )); then
    return 0
  elif (( rc != 0 )); then
    echo "claude-litellm: --effort requires a value." >&2
    return 1
  fi

  allowed="$(ai_litellm_model_reasoning_allowed_efforts "$model" 2>/dev/null || true)"
  if [[ -z "$allowed" ]]; then
    echo "claude-litellm: $model supports reasoning but does not expose selectable effort levels; refusing --effort=$effort instead of silently dropping it." >&2
    return 1
  fi
  case " $allowed " in
    *" $effort "*) return 0 ;;
  esac
  echo "claude-litellm: --effort=$effort is not supported by $model (allowed: ${allowed// /, })." >&2
  return 1
}

# Shared launch preparation: ensure the shared-environment symlink layer,
# refuse to launch if the shared settings surface carries backend routing
# keys, and render the proxy --settings overlay.
_claude_litellm_launch_prepare() {
  # Overlay paths inherited from a pre-upgrade shell point inside the config
  # dir, where settings.json is now a shared symlink; rendering there would
  # chmod/replace the native file through the link. Reset such values.
  local fallback
  case "$CLAUDE_LITELLM_SETTINGS_ARG_PROXY" in
    "$CLAUDE_LITELLM_CLAUDE_CONFIG"/*)
        fallback="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settingsArgProxy 2>/dev/null || printf '%s/overlay-settings-proxy.json' "$CLAUDE_LITELLM_HOME")"
        if [[ "$fallback" == "$CLAUDE_LITELLM_CLAUDE_CONFIG"/* ]]; then
          echo "claude-litellm: refusing overlay path inside the shared config dir: $fallback" >&2
          return 1
        fi
        echo "claude-litellm: ignoring stale CLAUDE_LITELLM_SETTINGS_ARG_PROXY inside the shared config dir; using $fallback" >&2
        typeset -g "CLAUDE_LITELLM_SETTINGS_ARG_PROXY=$fallback"
      ;;
  esac
  ai_litellm_shared_env_links_ensure "$CLAUDE_LITELLM_HARNESS" "$CLAUDE_LITELLM_CLAUDE_CONFIG" || return $?
  ai_litellm_claude_shared_settings_lint "$CLAUDE_LITELLM_HARNESS" || return $?
  ai_litellm_render_claude_settings "$CLAUDE_LITELLM_HARNESS" "$CLAUDE_LITELLM_SETTINGS_ARG_PROXY"
}

_claude_litellm_launch_proxy() {
  local requested="$1"
  shift
  local claude_model_arg
  local target_model
  target_model="$(_claude_litellm_target_model_for_request "$requested")" || {
    echo "Unknown claude-litellm proxy alias, LiteLLM model_name, or provider model: ${requested:-$(_claude_litellm_proxy_default_request)}" >&2
    return 1
  }
  claude_model_arg="$(_claude_litellm_resolve_model_arg "$requested")" || {
    echo "Unknown claude-litellm proxy alias, LiteLLM model_name, or provider model: ${requested:-$(_claude_litellm_proxy_default_request)}" >&2
    return 1
  }

  _claude_litellm_validate_effort "$target_model" "$@" || return $?
  ai_litellm_model_runtime_ready "$target_model" || return $?
  _claude_litellm_require_oauth "$target_model" || return $?
  ai_litellm_start >/dev/null || return $?
  _claude_litellm_launch_prepare || return $?

  local master_key
  master_key="$(ai_litellm_master_key)"

  if [[ -z "$master_key" ]]; then
    echo "Missing LiteLLM master key." >&2
    return 1
  fi

  local claude_command
  claude_command="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" command 2>/dev/null || printf 'claude')"

  local base_url_env auth_env discovery_env isolation_env tier_model_prefix tier_display_prefix
  local auto_compact_window_env max_output_tokens_env empty_api_key_env attribution_env
  base_url_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.baseUrlEnv 2>/dev/null || printf 'ANTHROPIC_BASE_URL')"
  auth_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" provider.auth.env 2>/dev/null || printf 'ANTHROPIC_AUTH_TOKEN')"
  empty_api_key_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.emptyApiKeyEnv 2>/dev/null || printf 'ANTHROPIC_API_KEY')"
  discovery_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.discoveryEnv 2>/dev/null || printf 'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY')"
  isolation_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" isolation.env 2>/dev/null || printf 'CLAUDE_CONFIG_DIR')"
  tier_model_prefix="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.tierModelEnvPrefix 2>/dev/null || printf 'ANTHROPIC_DEFAULT')"
  tier_display_prefix="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.tierDisplayNameEnvPrefix 2>/dev/null || printf 'ANTHROPIC_DEFAULT')"
  auto_compact_window_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.autoCompactWindowEnv 2>/dev/null || printf 'CLAUDE_CODE_AUTO_COMPACT_WINDOW')"
  max_output_tokens_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.maxOutputTokensEnv 2>/dev/null || printf 'CLAUDE_CODE_MAX_OUTPUT_TOKENS')"
  attribution_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.attributionHeaderEnv 2>/dev/null || printf 'CLAUDE_CODE_ATTRIBUTION_HEADER')"

  local -a env_assignments
  env_assignments=(
    "$base_url_env=$(ai_litellm_base_url)"
    "$auth_env=$master_key"
    "$empty_api_key_env="
    # Discovery stays on for proxy but is dormant: the binary only lists ids
    # matching ^(claude|anthropic) (verified); our surface names intentionally
    # do not, so this lights up only if such alias routes ever exist.
    "$discovery_env=1"
    "$isolation_env=$CLAUDE_LITELLM_CLAUDE_CONFIG"
    "$attribution_env=0"
  )

  local tier tier_upper tier_model tier_display
  local -a tiers
  tiers=("${(@f)$(_claude_litellm_tiers)}")
  for tier in "${tiers[@]}"; do
    tier_upper="${tier:u}"
    tier_model="$(_claude_litellm_json "aliases.$tier" 2>/dev/null || true)"
    # Display name defaults to the real model id so the picker shows what
    # actually serves the tier; displayNames.<tier> remains a cosmetic override.
    tier_display="$(_claude_litellm_json "displayNames.$tier" 2>/dev/null || printf '%s' "$tier_model")"
    env_assignments+=(
      "${tier_model_prefix}_${tier_upper}_MODEL=$tier_model"
    )
    [[ -n "$tier_display" ]] && env_assignments+=("${tier_display_prefix}_${tier_upper}_MODEL_NAME=$tier_display")
  done

  # Claude Code exposes process-global knobs for compact threshold and request
  # max_tokens. Shared-window providers count input + reserved output together,
  # so we inject a small reservation rather than the model's output capability.
  local active_budget active_effective_input active_reservation
  active_budget="$(ai_litellm_harness_output_budget "$CLAUDE_LITELLM_HARNESS" "$claude_model_arg" "$target_model" 2>/dev/null || true)"
  if [[ -n "$active_budget" ]]; then
    active_effective_input="$(print -r -- "$active_budget" | jq -r '.effectiveInput // empty')"
    active_reservation="$(print -r -- "$active_budget" | jq -r '.reservation // empty')"
    [[ -n "$active_effective_input" ]] && env_assignments+=("${auto_compact_window_env}=$active_effective_input")
    [[ -n "$active_reservation" ]] && env_assignments+=("${max_output_tokens_env}=$active_reservation")
  fi

  local reasoning_output
  local -a claude_extra_args
  reasoning_output="$(_claude_litellm_reasoning_args "$@")"
  [[ -n "$reasoning_output" ]] && claude_extra_args=("${(@f)reasoning_output}")

  ai_litellm_harness_exec_env "$CLAUDE_LITELLM_HARNESS" "${env_assignments[@]}" -- \
    "$claude_command" --settings "$CLAUDE_LITELLM_SETTINGS_ARG_PROXY" --model "$claude_model_arg" "${claude_extra_args[@]}" "$@"
}

claude-litellm() {
  if ! typeset -f ai_litellm >/dev/null 2>&1; then
    echo "Missing shared LiteLLM library: $AI_LITELLM_CONFIG_HOME/ai-litellm/lib.zsh" >&2
    return 1
  fi

  case "${1:-}" in
    -h|--help)
      echo "Usage: claude-litellm [fable|opus|sonnet|haiku|model_name] [claude args...]"
      echo "       claude-litellm auth login|status|logout [chatgpt|grok]"
      echo "       claude-litellm status|doctor|sync|proxy|model|key|runtime|context|reasoning ..."
      echo "       claude-litellm --list"
      echo "All providers and local runtimes are routed through the LiteLLM proxy."
      return 0
      ;;
    --list)
      claude-litellm-list
      return $?
      ;;
    --status)
      claude-litellm-status
      return $?
      ;;
    --start|--stop|--restart|--logs|--doctor)
      if [[ "$1" == "--doctor" ]]; then
        echo "claude-litellm: legacy control flag '--doctor' is retired; use 'claude-litellm doctor'." >&2
      else
        echo "claude-litellm: legacy control flag '$1' is retired; use 'claude-litellm proxy ${1#--}'." >&2
      fi
      return 2
      ;;
    auth)
      shift
      _claude_litellm_auth "$@"
      return $?
      ;;
    status)
      shift
      claude-litellm-status "$@"
      return $?
      ;;
    doctor)
      shift
      ai_litellm doctor "$@"
      local doctor_rc=$?
      _claude_litellm_oauth_doctor || doctor_rc=1
      return $doctor_rc
      ;;
    proxy|harness|runtime|model|context|reasoning|key|sync)
      local control="$1"
      shift
      ai_litellm "$control" "$@"
      return $?
      ;;
    uninstall)
      shift
      "$AI_LITELLM_HOME/scripts/uninstall.zsh" "$@"
      return $?
      ;;
  esac

  local requested="" consumed=0
  if [[ -n "${1:-}" && "$1" != -* ]]; then
    if _claude_litellm_resolve_model_arg "$1" >/dev/null 2>&1; then
      requested="$1"
      shift
      consumed=1
    fi
    # A leading non-flag positional is the model selector. If nothing consumed
    # it (unknown tier/model_name, or a typo), it would otherwise leak to claude
    # AS THE PROMPT — silently, and with the default model. Fail loud instead.
    # (Tiers/raw model_names are the only valid selectors; see DESIGN_RATIONALE
    # §3 "model selection contract".)
    if (( ! consumed )); then
      echo "claude-litellm: '$1' is not a selectable model — not a tier and not a registered LiteLLM model_name." >&2
      echo "  list routes:  claude-litellm model list" >&2
      echo "  meant a prompt?  claude-litellm -p '$1'" >&2
      return 1
    fi
  fi

  _claude_litellm_launch_proxy "$requested" "$@"
}

claude-via-litellm() {
  claude-litellm "$@"
}
