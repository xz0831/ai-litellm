# Claude Code through OpenRouter's Anthropic-compatible endpoint by default,
# with a LiteLLM proxy fallback for local and non-Claude routes.

if ! typeset -f ai_litellm >/dev/null 2>&1 && [[ -f "${AI_LITELLM_FABRIC_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm-fabric}/config/ai-litellm/lib.zsh" ]]; then
  source "${AI_LITELLM_FABRIC_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm-fabric}/config/ai-litellm/lib.zsh"
elif ! typeset -f ai_litellm >/dev/null 2>&1 && [[ -f "$HOME/.config/ai-litellm/lib.zsh" ]]; then
  source "$HOME/.config/ai-litellm/lib.zsh"
fi

export CLAUDE_LITELLM_HARNESS="${CLAUDE_LITELLM_HARNESS:-claude}"
export CLAUDE_LITELLM_HOME="${CLAUDE_LITELLM_HOME:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.home 2>/dev/null || printf "${AI_LITELLM_STATE_HOME:-${AI_LITELLM_FABRIC_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm-fabric}/state}/claude-litellm")}"
export CLAUDE_LITELLM_SETTINGS="${CLAUDE_LITELLM_SETTINGS:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settings 2>/dev/null || printf "$CLAUDE_LITELLM_HOME/settings.json")}"
export CLAUDE_LITELLM_CLAUDE_CONFIG="${CLAUDE_LITELLM_CLAUDE_CONFIG:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.configDir 2>/dev/null || printf "$CLAUDE_LITELLM_HOME/claude-config")}"
export CLAUDE_LITELLM_SETTINGS_ARG="${CLAUDE_LITELLM_SETTINGS_ARG:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settingsArg 2>/dev/null || printf "$CLAUDE_LITELLM_HOME/overlay-settings.json")}"
export CLAUDE_LITELLM_SETTINGS_ARG_PROXY="${CLAUDE_LITELLM_SETTINGS_ARG_PROXY:-$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settingsArgProxy 2>/dev/null || printf "$CLAUDE_LITELLM_HOME/overlay-settings-proxy.json")}"
export CLAUDE_LITELLM_CONFIG="${CLAUDE_LITELLM_CONFIG:-$AI_LITELLM_CONFIG}"

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

_claude_litellm_default_mode() {
  local mode
  mode="${CLAUDE_LITELLM_MODE:-$(_claude_litellm_json mode 2>/dev/null || printf 'direct')}"
  case "$mode" in
    direct|openrouter|openrouter-direct) printf 'direct\n' ;;
    proxy|litellm|litellm-proxy) printf 'proxy\n' ;;
    *)
      echo "Unknown claude-litellm mode: $mode" >&2
      return 1
      ;;
  esac
}

_claude_litellm_direct_model_like() {
  local candidate="$1"
  [[ "$candidate" == "~"* || "$candidate" == */* || "$candidate" == anthropic:* ]]
}

_claude_litellm_direct_default_request() {
  _claude_litellm_json directDefault 2>/dev/null || _claude_litellm_json default 2>/dev/null || printf 'opus\n'
}

_claude_litellm_proxy_default_request() {
  _claude_litellm_json proxyDefault 2>/dev/null || _claude_litellm_json default 2>/dev/null || printf 'sonnet\n'
}

_claude_litellm_direct_model_for_request() {
  local requested="$1"
  if [[ -z "$requested" ]]; then
    requested="$(_claude_litellm_direct_default_request)"
  fi

  if _claude_litellm_is_tier "$requested"; then
    _claude_litellm_json "directAliases.$requested" 2>/dev/null
    return $?
  fi

  printf '%s\n' "$requested"
}

_claude_litellm_direct_model_arg_for_request() {
  local requested="$1"
  if [[ -z "$requested" ]]; then
    requested="$(_claude_litellm_direct_default_request)"
  fi

  if _claude_litellm_is_tier "$requested"; then
    printf '%s\n' "$requested"
    return 0
  fi

  printf '%s\n' "$requested"
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

claude-litellm-start() {
  ai_litellm_start "$@"
}

claude-litellm-stop() {
  ai_litellm_stop "$@"
}

claude-litellm-restart() {
  ai_litellm_restart "$@"
}

claude-litellm-status() {
  echo "Claude settings: $CLAUDE_LITELLM_SETTINGS"
  echo "Claude config:   $CLAUDE_LITELLM_CLAUDE_CONFIG"
  echo "Overlay direct:  $CLAUDE_LITELLM_SETTINGS_ARG"
  echo "Overlay proxy:   $CLAUDE_LITELLM_SETTINGS_ARG_PROXY"
  echo "Shared env root: $(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" isolation.sharedEnvironment.targetRoot 2>/dev/null || printf '(disabled)')"
  echo "Claude mode:     $(_claude_litellm_default_mode 2>/dev/null || printf 'unknown')"
  echo "Direct base URL: $(ai_litellm_harness_template_json "$CLAUDE_LITELLM_HARNESS" provider.baseUrl 2>/dev/null || printf 'https://openrouter.ai/api')"
  ai_litellm_status
}

claude-litellm-list() {
  echo "Claude direct aliases:"
  echo "  default -> $(_claude_litellm_direct_default_request)"
  local tier
  _claude_litellm_tiers | while IFS= read -r tier; do
    printf '  %-7s -> %s\n' "$tier" "$(_claude_litellm_json "directAliases.$tier" 2>/dev/null || true)"
  done
  echo
  echo "Claude proxy aliases:"
  echo "  default -> $(_claude_litellm_proxy_default_request)"
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

# Shared launch preparation: ensure the shared-environment symlink layer,
# refuse to launch if the shared settings surface carries backend routing
# keys, and render both per-mode --settings overlays.
_claude_litellm_launch_prepare() {
  # Overlay paths inherited from a pre-upgrade shell point inside the config
  # dir, where settings.json is now a shared symlink; rendering there would
  # chmod/replace the native file through the link. Reset such values.
  local var fallback
  for var in CLAUDE_LITELLM_SETTINGS_ARG CLAUDE_LITELLM_SETTINGS_ARG_PROXY; do
    case "${(P)var}" in
      "$CLAUDE_LITELLM_CLAUDE_CONFIG"/*)
        if [[ "$var" == CLAUDE_LITELLM_SETTINGS_ARG ]]; then
          fallback="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settingsArg 2>/dev/null || printf '%s/overlay-settings.json' "$CLAUDE_LITELLM_HOME")"
        else
          fallback="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settingsArgProxy 2>/dev/null || printf '%s/overlay-settings-proxy.json' "$CLAUDE_LITELLM_HOME")"
        fi
        if [[ "$fallback" == "$CLAUDE_LITELLM_CLAUDE_CONFIG"/* ]]; then
          echo "claude-litellm: refusing overlay path inside the shared config dir: $fallback" >&2
          return 1
        fi
        echo "claude-litellm: ignoring stale $var inside the shared config dir; using $fallback" >&2
        typeset -g "$var=$fallback"
        ;;
    esac
  done
  ai_litellm_shared_env_links_ensure "$CLAUDE_LITELLM_HARNESS" "$CLAUDE_LITELLM_CLAUDE_CONFIG" || return $?
  ai_litellm_claude_shared_settings_lint "$CLAUDE_LITELLM_HARNESS" || return $?
  ai_litellm_render_claude_settings "$CLAUDE_LITELLM_HARNESS" "$CLAUDE_LITELLM_SETTINGS_ARG" "$CLAUDE_LITELLM_SETTINGS_ARG_PROXY"
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

  ai_litellm_model_runtime_ready "$target_model" || return $?
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
    "$discovery_env=1"
    "$isolation_env=$CLAUDE_LITELLM_CLAUDE_CONFIG"
    "$attribution_env=0"
  )

  local tier tier_upper tier_model tier_display tier_caps
  local -a tiers
  tiers=("${(@f)$(_claude_litellm_tiers)}")
  for tier in "${tiers[@]}"; do
    tier_upper="${tier:u}"
    tier_model="$(_claude_litellm_json "aliases.$tier" 2>/dev/null || true)"
    tier_display="$(_claude_litellm_json "displayNames.$tier" 2>/dev/null || printf '%s via LiteLLM' "$tier_upper")"
    env_assignments+=(
      "${tier_model_prefix}_${tier_upper}_MODEL=$tier_model"
      "${tier_display_prefix}_${tier_upper}_MODEL_NAME=$tier_display"
    )
    tier_caps="$(_claude_litellm_json "capabilities.$tier" 2>/dev/null || true)"
    if [[ -n "$tier_caps" ]]; then
      [[ "$tier_caps" == "none" ]] && tier_caps=""
      env_assignments+=("${tier_model_prefix}_${tier_upper}_MODEL_SUPPORTED_CAPABILITIES=$tier_caps")
    fi
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

_claude_litellm_launch_direct() {
  local requested="$1"
  shift

  local target_model claude_model_arg
  target_model="$(_claude_litellm_direct_model_for_request "$requested")" || {
    echo "Unknown claude-litellm direct alias: ${requested:-$(_claude_litellm_direct_default_request)}" >&2
    return 1
  }
  claude_model_arg="$(_claude_litellm_direct_model_arg_for_request "$requested")" || return $?

  _claude_litellm_launch_prepare || return $?

  local openrouter_key
  openrouter_key="$(ai_litellm_openrouter_key 2>/dev/null)" || {
    echo "Missing OpenRouter API key. Run: ai-litellm key set --keychain openrouter" >&2
    return 1
  }

  local claude_command
  claude_command="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" command 2>/dev/null || printf 'claude')"

  local base_url_env auth_env empty_api_key_env discovery_env isolation_env tier_model_prefix tier_display_prefix
  local subagent_model_env fast_mode_org_check_env attribution_env
  base_url_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.baseUrlEnv 2>/dev/null || printf 'ANTHROPIC_BASE_URL')"
  auth_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" provider.auth.env 2>/dev/null || printf 'ANTHROPIC_AUTH_TOKEN')"
  empty_api_key_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.emptyApiKeyEnv 2>/dev/null || printf 'ANTHROPIC_API_KEY')"
  discovery_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.discoveryEnv 2>/dev/null || printf 'CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY')"
  isolation_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" isolation.env 2>/dev/null || printf 'CLAUDE_CONFIG_DIR')"
  tier_model_prefix="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.tierModelEnvPrefix 2>/dev/null || printf 'ANTHROPIC_DEFAULT')"
  tier_display_prefix="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.tierDisplayNameEnvPrefix 2>/dev/null || printf 'ANTHROPIC_DEFAULT')"
  subagent_model_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.subagentModelEnv 2>/dev/null || printf 'CLAUDE_CODE_SUBAGENT_MODEL')"
  fast_mode_org_check_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.fastModeOrgCheckEnv 2>/dev/null || printf 'CLAUDE_CODE_SKIP_FAST_MODE_ORG_CHECK')"
  attribution_env="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.attributionHeaderEnv 2>/dev/null || printf 'CLAUDE_CODE_ATTRIBUTION_HEADER')"

  local -a env_assignments
  env_assignments=(
    "$base_url_env=$(ai_litellm_harness_template_json "$CLAUDE_LITELLM_HARNESS" provider.baseUrl 2>/dev/null || printf 'https://openrouter.ai/api')"
    "$auth_env=$openrouter_key"
    "$empty_api_key_env="
    "$discovery_env=0"
    "$isolation_env=$CLAUDE_LITELLM_CLAUDE_CONFIG"
    "$fast_mode_org_check_env=1"
    "$attribution_env=0"
  )

  local tier tier_upper tier_model tier_display tier_caps
  local -a tiers
  tiers=("${(@f)$(_claude_litellm_tiers)}")
  for tier in "${tiers[@]}"; do
    tier_upper="${tier:u}"
    tier_model="$(_claude_litellm_json "directAliases.$tier" 2>/dev/null || true)"
    tier_display="$(_claude_litellm_json "directDisplayNames.$tier" 2>/dev/null || printf '%s via OpenRouter' "$tier_upper")"
    [[ -n "$tier_model" ]] && env_assignments+=("${tier_model_prefix}_${tier_upper}_MODEL=$tier_model")
    [[ -n "$tier_display" ]] && env_assignments+=("${tier_display_prefix}_${tier_upper}_MODEL_NAME=$tier_display")
    tier_caps="$(_claude_litellm_json "directCapabilities.$tier" 2>/dev/null || true)"
    if [[ -n "$tier_caps" ]]; then
      [[ "$tier_caps" == "none" ]] && tier_caps=""
      env_assignments+=("${tier_model_prefix}_${tier_upper}_MODEL_SUPPORTED_CAPABILITIES=$tier_caps")
    fi
  done

  local subagent_model
  subagent_model="$(_claude_litellm_json subagentModel 2>/dev/null || _claude_litellm_json directAliases.opus 2>/dev/null || true)"
  [[ -n "$subagent_model" ]] && env_assignments+=("$subagent_model_env=$subagent_model")

  local reasoning_output
  local -a claude_extra_args
  reasoning_output="$(_claude_litellm_reasoning_args "$@")"
  [[ -n "$reasoning_output" ]] && claude_extra_args=("${(@f)reasoning_output}")

  ai_litellm_harness_exec_env "$CLAUDE_LITELLM_HARNESS" "${env_assignments[@]}" -- \
    "$claude_command" --settings "$CLAUDE_LITELLM_SETTINGS_ARG" --model "$claude_model_arg" "${claude_extra_args[@]}" "$@"
}

claude-litellm() {
  if ! typeset -f ai_litellm >/dev/null 2>&1; then
    echo "Missing shared LiteLLM library: $AI_LITELLM_CONFIG_HOME/ai-litellm/lib.zsh" >&2
    return 1
  fi

  case "$1" in
    -h|--help)
      echo "Usage: claude-litellm [--direct|--proxy] [opus|sonnet|haiku|model_name|provider_model] [claude args...]"
      echo "       claude-litellm --list|--status   (harness-specific info)"
      echo "Default: OpenRouter Anthropic-compatible direct mode; use --proxy for LiteLLM/local routes."
      echo "Reasoning defaults: ai-litellm harness reasoning [set|unset] claude"
      echo "Proxy lifecycle moved to: ai-litellm proxy start|stop|restart|logs|doctor"
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
    --start)
      echo "claude-litellm --start is deprecated; use 'ai-litellm proxy start'" >&2
      claude-litellm-start
      return $?
      ;;
    --stop)
      echo "claude-litellm --stop is deprecated; use 'ai-litellm proxy stop'" >&2
      claude-litellm-stop
      return $?
      ;;
    --restart)
      echo "claude-litellm --restart is deprecated; use 'ai-litellm proxy restart'" >&2
      claude-litellm-restart
      return $?
      ;;
    --logs)
      echo "claude-litellm --logs is deprecated; use 'ai-litellm proxy logs'" >&2
      shift
      ai_litellm_logs "$@"
      return $?
      ;;
    --doctor)
      echo "claude-litellm --doctor is deprecated; use 'ai-litellm proxy doctor'" >&2
      shift
      ai_litellm_doctor "$@"
      return $?
      ;;
  esac

  local mode mode_explicit=0
  mode="$(_claude_litellm_default_mode)" || return $?
  while (( $# > 0 )); do
    case "$1" in
      --direct|--openrouter-direct)
        mode="direct"
        mode_explicit=1
        shift
        ;;
      --proxy|--litellm-proxy)
        mode="proxy"
        mode_explicit=1
        shift
        ;;
      --mode)
        if [[ -z "${2:-}" ]]; then
          echo "Missing value for --mode (direct|proxy)." >&2
          return 1
        fi
        case "$2" in
          direct|openrouter|openrouter-direct) mode="direct" ;;
          proxy|litellm|litellm-proxy) mode="proxy" ;;
          *) echo "Unknown claude-litellm mode: $2" >&2; return 1 ;;
        esac
        mode_explicit=1
        shift 2
        ;;
      --mode=*)
        case "${1#--mode=}" in
          direct|openrouter|openrouter-direct) mode="direct" ;;
          proxy|litellm|litellm-proxy) mode="proxy" ;;
          *) echo "Unknown claude-litellm mode: ${1#--mode=}" >&2; return 1 ;;
        esac
        mode_explicit=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  local requested=""
  if [[ -n "${1:-}" && "$1" != -* ]]; then
    if [[ "$mode" == "proxy" ]]; then
      if _claude_litellm_resolve_model_arg "$1" >/dev/null 2>&1; then
        requested="$1"
        shift
      fi
    elif _claude_litellm_is_tier "$1"; then
      requested="$1"
      shift
    elif (( ! mode_explicit )) && _claude_litellm_resolve_model_arg "$1" >/dev/null 2>&1; then
      mode="proxy"
      requested="$1"
      shift
    elif _claude_litellm_direct_model_like "$1" || (( mode_explicit )); then
      requested="$1"
      shift
    fi
  fi

  case "$mode" in
    direct) _claude_litellm_launch_direct "$requested" "$@" ;;
    proxy) _claude_litellm_launch_proxy "$requested" "$@" ;;
  esac
}

claude-via-litellm() {
  claude-litellm "$@"
}
