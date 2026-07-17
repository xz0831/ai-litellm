# Claude Code on non-Anthropic models through the local LiteLLM proxy.

shell_package_home="${AI_LITELLM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm}"
if ! typeset -f ai_litellm >/dev/null 2>&1; then
  if [[ -e "$shell_package_home/install-manifest.json" || -L "$shell_package_home/install-manifest.json" ]]; then
    if [[ ! -f "$shell_package_home/install-manifest.json" || -L "$shell_package_home/install-manifest.json" || \
          ! -f "$shell_package_home/config/ai-litellm/lib.zsh" || -L "$shell_package_home/config/ai-litellm/lib.zsh" ]]; then
      echo "claude-litellm installation is damaged; refusing legacy helper fallback. Reinstall the package." >&2
      return 1 2>/dev/null || exit 1
    fi
    source "$shell_package_home/config/ai-litellm/lib.zsh"
  elif [[ -f "$shell_package_home/config/ai-litellm/lib.zsh" && ! -L "$shell_package_home/config/ai-litellm/lib.zsh" ]]; then
    source "$shell_package_home/config/ai-litellm/lib.zsh"
  elif [[ -f "$HOME/.config/ai-litellm/lib.zsh" ]]; then
    source "$HOME/.config/ai-litellm/lib.zsh"
  fi
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
  ai_litellm_litellm_python
}

_claude_litellm_auth() {
  local python action was_running=0 stopped=0 rc=0 restart_rc=0 auth_fd="" auth_lock lifecycle_held=0
  action="${1:-}"
  {
    if [[ "$action" == login || "$action" == logout ]]; then
      ai_litellm_lifecycle_lock_acquire || return $?
      lifecycle_held=1
      ai_litellm_install_integrity_ok || {
        echo "claude-litellm: installed package/runtime integrity failed; reinstall before changing OAuth state." >&2
        return 1
      }
    fi
    python="$(_claude_litellm_oauth_python)" || {
      echo "claude-litellm: Python runtime is unavailable; reinstall the package." >&2
      return 1
    }
    [[ -f "$AI_LITELLM_HOME/config/claude-litellm/oauth.py" && \
       ! -L "$AI_LITELLM_HOME/config/claude-litellm/oauth.py" ]] || {
      echo "claude-litellm: OAuth adapter is unavailable or unsafe; reinstall the package." >&2
      return 1
    }
    if [[ "$action" == login || "$action" == logout ]]; then
      # Python validates state/auth/provider one component at a time and creates
      # only descendants of the already-existing, non-symlink state root. Do
      # not let shell mkdir/chmod follow an attacker-controlled ancestor first.
      ai_litellm_python_isolated "$python" \
        "$AI_LITELLM_HOME/config/claude-litellm/oauth.py" --prepare-storage || return $?
      zmodload zsh/system || return 1
      auth_lock="$CLAUDE_LITELLM_AUTH_HOME/.auth-mutation.lock"
      ai_litellm_lock_file_prepare "$auth_lock" || return 1
      if ! zsystem flock -t 0 -f auth_fd "$auth_lock"; then
        echo "claude-litellm: another OAuth login/logout is already in progress." >&2
        return 1
      fi
      chmod 600 "$auth_lock" 2>/dev/null || true
      ai_litellm_pid_running && was_running=1
      if (( was_running )); then
        echo "claude-litellm: stopping the managed proxy before OAuth state changes." >&2
        ai_litellm_stop >&2 || return 1
        stopped=1
      fi
    fi
    if ai_litellm_python_isolated "$python" \
      "$AI_LITELLM_HOME/config/claude-litellm/oauth.py" "$@"; then
      rc=0
    else
      rc=$?
    fi
  } always {
    # ChatGPT deployment construction resolves OAuth during proxy startup. The
    # process must remain down for the whole credential transaction so refresh
    # cannot recreate a logout or overwrite a new login. Always restore prior
    # liveness and release the kernel lock, including Ctrl-C/error paths.
    if (( stopped )); then
      echo "claude-litellm: restarting the managed proxy after the OAuth command." >&2
      ai_litellm_start >&2 || restart_rc=$?
    fi
    [[ "$auth_fd" == <-> ]] && zsystem flock -u "$auth_fd" 2>/dev/null || true
    (( lifecycle_held )) && ai_litellm_lifecycle_lock_release
  }
  (( rc == 0 )) || return $rc
  (( restart_rc == 0 )) || return $restart_rc
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
  ai_litellm_python_configured "$python" -c '
import importlib.metadata
import os
from ai_litellm_callbacks import proxy_bootstrap
from ai_litellm_callbacks.oauth_guard import PATCH_ACTIVE
from litellm.llms.chatgpt.authenticator import Authenticator
from litellm.llms.chatgpt.common_utils import CHATGPT_API_BASE
from litellm.llms.chatgpt.responses.transformation import ChatGPTResponsesAPIConfig
from litellm.constants import XAI_API_BASE
from litellm.llms.xai.oauth import XAIOAuthAuthenticator
assert importlib.metadata.version("litellm") == "1.92.0"
assert PATCH_ACTIVE is True
expected_overrides = {
    "CHATGPT_API_BASE",
    "OPENAI_CHATGPT_API_BASE",
    "XAI_OAUTH_API_BASE",
    "XAI_API_BASE",
}
assert set(proxy_bootstrap.OAUTH_PROVIDER_ENDPOINT_OVERRIDE_ENV) == expected_overrides
for name in expected_overrides:
    os.environ[name] = "http://127.0.0.1:9/oauth-token-capture"
# The guard pins both adapter methods even if a later loader reintroduces an
# override after the bootstrap initial environment scrub.
assert Authenticator.__new__(Authenticator).get_api_base() == CHATGPT_API_BASE
assert ChatGPTResponsesAPIConfig.__new__(ChatGPTResponsesAPIConfig).get_complete_url(
    "http://127.0.0.1:9/oauth-token-capture", {}
) == f"{CHATGPT_API_BASE}/responses"
assert XAIOAuthAuthenticator.__new__(XAIOAuthAuthenticator).get_api_base() == XAI_API_BASE
proxy_bootstrap.enforce_official_oauth_provider_endpoints()
assert all(name not in os.environ for name in expected_overrides)
assert Authenticator.__new__(Authenticator).get_api_base() == CHATGPT_API_BASE
assert XAIOAuthAuthenticator.__new__(XAIOAuthAuthenticator).get_api_base() == XAI_API_BASE
' >/dev/null 2>&1 || {
    echo "fail OAuth runtime: expected LiteLLM 1.92.0 guards and pinned provider endpoints" >&2
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

# For tiers, return the tier label for Claude's UI. The launch environment maps
# every tier and subagent to the same validated route, so in-session /model can
# change a label but cannot cross the provider/session boundary.
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
  if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--json" ]] }; then
    echo "Usage: claude-litellm status [--json]" >&2
    return 1
  fi
  if [[ "${1:-}" == "--json" ]]; then
    local control oauth
    control="$(ai_litellm status --json)" || return $?
    oauth="$(_claude_litellm_auth status all --json)" || return $?
    node -e '
const [control, oauth] = process.argv.slice(1).map(JSON.parse);
process.stdout.write(JSON.stringify({...control, oauth}) + "\n");
' "$control" "$oauth"
    return $?
  fi
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

_claude_litellm_shared_effort() {
  local target_root file configured="" candidate=""
  target_root="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" isolation.sharedEnvironment.targetRoot 2>/dev/null || true)"
  for file in "$target_root/settings.json" "$target_root/settings.local.json"; do
    [[ -f "$file" && ! -L "$file" ]] || continue
    candidate="$(jq -r '.effortLevel // empty' "$file" 2>/dev/null || true)"
    [[ -n "$candidate" ]] || continue
    configured="$candidate"
  done
  # Claude Code 2.1.207 emits adaptive thinking + high when no setting/flag is
  # present. Treat that wire default as intent instead of pretending effort is
  # absent at validation time.
  [[ -n "$configured" ]] || configured=high
  print -r -- "${configured:l}"
}

_claude_litellm_reasoning_args() {
  local model="$1"
  shift
  local harness_effort allowed implicit selected
  harness_effort="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" adapterConfig.reasoning.effort 2>/dev/null || true)"
  if [[ -n "$harness_effort" && "$harness_effort" != "auto" && "$harness_effort" != "none" ]]; then
    if ! ai_litellm_cli_arg_present --effort "$@"; then
      printf '%s\n%s\n' --effort "$harness_effort"
    fi
    return 0
  fi
  ai_litellm_cli_arg_present --effort "$@" && return 0
  allowed="$(ai_litellm_model_reasoning_allowed_efforts "$model" 2>/dev/null || true)"
  [[ -n "$allowed" ]] || return 0
  implicit="$(_claude_litellm_shared_effort)"
  case " $allowed " in
    *" $implicit "*) return 0 ;;
  esac
  if [[ " $allowed " == *" high "* ]]; then
    selected=high
  else
    selected="${allowed%% *}"
  fi
  printf '%s\n%s\n' --effort "$selected"
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
  local effort allowed rc explicit=0
  effort="$(_claude_litellm_effective_effort "$@")"
  rc=$?
  if (( rc == 1 )); then
    effort="$(_claude_litellm_shared_effort)"
  elif (( rc != 0 )); then
    echo "claude-litellm: --effort requires a value." >&2
    return 1
  fi
  ai_litellm_cli_arg_present --effort "$@" && explicit=1

  case "$effort" in
    low|medium|high|xhigh|max) ;;
    *)
      echo "claude-litellm: --effort=$effort is not accepted by this Claude Code CLI (allowed: low, medium, high, xhigh, max)." >&2
      return 1
      ;;
  esac

  allowed="$(ai_litellm_model_reasoning_allowed_efforts "$model" 2>/dev/null || true)"
  if [[ -z "$allowed" ]]; then
    if (( explicit )); then
      echo "claude-litellm: $model supports reasoning but does not expose selectable effort levels; refusing --effort=$effort instead of silently dropping it." >&2
      return 1
    fi
    echo "claude-litellm: $model has no validated selectable effort slot; Claude's implicit effort=$effort will be removed at the gateway and the provider will use its reasoning default." >&2
    return 0
  fi
  case " $allowed " in
    *" $effort "*) return 0 ;;
  esac
  if (( explicit )); then
    echo "claude-litellm: --effort=$effort is not supported by $model (allowed: ${allowed// /, })." >&2
    return 1
  fi
  echo "claude-litellm: shared/default effort=$effort is not supported by $model; the wrapper will pin an allowed effort (${allowed// /, })." >&2
  return 0
}

# Shared launch preparation: ensure the shared-environment symlink layer,
# refuse to launch if the shared settings surface carries backend routing
# keys, and render the proxy --settings overlay.
_claude_litellm_launch_prepare() {
  typeset -g CLAUDE_LITELLM_LAUNCH_SETTINGS_ARG=""
  # Overlay paths inherited from a pre-upgrade shell point inside the config
  # dir, where settings.json is now a shared symlink; rendering there would
  # chmod/replace the native file through the link. Reset such values.
  local fallback canonical
  canonical="$(ai_litellm_harness_json "$CLAUDE_LITELLM_HARNESS" paths.settingsArgProxy 2>/dev/null || true)"
  if [[ -n "$canonical" && "$CLAUDE_LITELLM_SETTINGS_ARG_PROXY" != "$canonical" ]]; then
    echo "claude-litellm: ignoring non-canonical proxy settings path; using $canonical" >&2
    typeset -g "CLAUDE_LITELLM_SETTINGS_ARG_PROXY=$canonical"
  fi
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

  # Freeze a private per-launch copy while holding the same mutation lock as
  # `permissions set/reset`. Claude reads --settings after this function
  # returns; passing the shared generated path directly would let a concurrent
  # update change the permission mode between validation and process startup.
  local lock_preowned=0 rc=0 launch_settings=""
  [[ "${AI_LITELLM_USER_MUTATION_FD:-}" == <-> ]] && lock_preowned=1
  ai_litellm_user_mutation_lock_acquire || return 1
  ai_litellm_render_claude_settings "$CLAUDE_LITELLM_HARNESS" "$CLAUDE_LITELLM_SETTINGS_ARG_PROXY" || rc=$?
  if (( rc == 0 )); then
    launch_settings="$(mktemp "${CLAUDE_LITELLM_SETTINGS_ARG_PROXY:h}/.overlay-settings-launch.XXXXXX")" || rc=$?
  fi
  if (( rc == 0 )); then
    cp -p "$CLAUDE_LITELLM_SETTINGS_ARG_PROXY" "$launch_settings" || rc=$?
  fi
  if (( rc == 0 )); then
    chmod 600 "$launch_settings" || rc=$?
  fi
  if (( lock_preowned == 0 )); then
    ai_litellm_user_mutation_lock_release
  fi
  if (( rc != 0 )); then
    [[ -n "$launch_settings" ]] && rm -f "$launch_settings"
    return $rc
  fi
  typeset -g CLAUDE_LITELLM_LAUNCH_SETTINGS_ARG="$launch_settings"
}

_claude_litellm_assert_safe_passthrough() {
  local arg
  for arg in "$@"; do
    [[ "$arg" == "--" ]] && break
    case "$arg" in
      --model|--model=*|--settings|--settings=*|--fallback-model|--fallback-model=*)
        echo "claude-litellm: $arg is managed by the wrapper and cannot be passed through." >&2
        echo "Select a model with: claude-litellm use <tier-or-registered-route> [claude args...]" >&2
        return 1
        ;;
    esac
  done
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

  _claude_litellm_assert_safe_passthrough "$@" || return $?
  _claude_litellm_validate_effort "$target_model" "$@" || return $?
  ai_litellm_model_runtime_ready "$target_model" || return $?
  _claude_litellm_require_oauth "$target_model" || return $?
  ai_litellm_model_provider_credentials_ready "$target_model" || return $?
  ai_litellm_start >/dev/null || return $?

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
  local loopback_no_proxy no_proxy_entry inherited_no_proxy
  local -a no_proxy_entries no_proxy_merged
  local -A no_proxy_seen
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
  # Preserve bypasses supplied in either conventional case. Both child
  # variables receive the same de-duplicated value so libraries choosing one
  # spelling cannot accidentally lose the user's existing exclusions.
  inherited_no_proxy="${NO_PROXY:-}"
  if [[ -n "${no_proxy:-}" ]]; then
    [[ -n "$inherited_no_proxy" ]] && inherited_no_proxy+=","
    inherited_no_proxy+="$no_proxy"
  fi
  no_proxy_entries=("${(@s:,:)inherited_no_proxy}" 127.0.0.1 localhost ::1)
  for no_proxy_entry in "${no_proxy_entries[@]}"; do
    [[ -n "$no_proxy_entry" && -z "${no_proxy_seen[$no_proxy_entry]-}" ]] || continue
    no_proxy_seen[$no_proxy_entry]=1
    no_proxy_merged+=("$no_proxy_entry")
  done
  loopback_no_proxy="${(j:,:)no_proxy_merged}"

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
    "NO_PROXY=$loopback_no_proxy"
    "no_proxy=$loopback_no_proxy"
  )

  local tier tier_upper tier_model tier_display
  local -a tiers
  tiers=("${(@f)$(_claude_litellm_tiers)}")
  for tier in "${tiers[@]}"; do
    tier_upper="${tier:u}"
    # Claude's effort/context/output knobs are process-global. Pin every tier
    # and subagent surface to the route validated for this process; otherwise
    # /model or fallback selection could bypass OAuth/runtime/effort checks and
    # retain an incompatible token budget. Switch providers by exiting and
    # relaunching `claude-litellm use <route>`.
    tier_model="$target_model"
    tier_display="$target_model"
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
  reasoning_output="$(_claude_litellm_reasoning_args "$target_model" "$@")"
  [[ -n "$reasoning_output" ]] && claude_extra_args=("${(@f)reasoning_output}")

  _claude_litellm_launch_prepare || return $?
  local launch_rc=0 launch_settings="$CLAUDE_LITELLM_LAUNCH_SETTINGS_ARG"
  ai_litellm_harness_exec_env "$CLAUDE_LITELLM_HARNESS" "${env_assignments[@]}" -- \
    "$claude_command" --settings "$launch_settings" --model "$claude_model_arg" "${claude_extra_args[@]}" "$@" || launch_rc=$?
  rm -f "$launch_settings"
  typeset -g CLAUDE_LITELLM_LAUNCH_SETTINGS_ARG=""
  return $launch_rc
}

_claude_litellm_use() {
  if [[ -z "${1:-}" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: claude-litellm use <tier-or-route> [claude args...]
       claude-litellm use <registered-route> --default

Launch one session with the selected route. --default runs the six live
compatibility gates and, only on PASS, replaces the current default preset;
it does not launch Claude and cloud routes may incur a small provider charge.
EOF
    [[ -n "${1:-}" ]] && return 0
    return 1
  fi

  local selector="$1"
  shift
  local target_model
  target_model="$(_claude_litellm_target_model_for_request "$selector")" || {
    echo "Unknown claude-litellm tier, route, or provider model: $selector" >&2
    echo "List selectable routes with: claude-litellm --list" >&2
    return 1
  }

  if [[ "${1:-}" == "--default" ]]; then
    shift
    (( $# == 0 )) || {
      echo "claude-litellm use: --default does not launch Claude or accept Claude arguments." >&2
      echo "Run 'claude-litellm use $selector' after the default change completes." >&2
      return 1
    }
    case "$selector" in
      fable|opus|sonnet|haiku)
        echo "claude-litellm use: --default requires a concrete registered route, not the '$selector' preset." >&2
        echo "Choose the route name shown by 'claude-litellm --list'." >&2
        return 1
        ;;
    esac
    local default_tier
    default_tier="$(_claude_litellm_proxy_default_request)" || return $?
    case "$default_tier" in
      fable|opus|sonnet|haiku) ;;
      *)
        echo "claude-litellm use: current default '$default_tier' is not a supported preset." >&2
        return 1
        ;;
    esac
    ai_litellm model qualify "$target_model" --activate-tier "$default_tier" || return $?
    echo "Default preset '$default_tier' now selects '$target_model'."
    echo "Run 'claude-litellm' to launch it."
    return 0
  fi

  _claude_litellm_launch_proxy "$selector" "$@"
}

_claude_litellm_task_handoff() {
  local -a normalized
  local selector="" target=""
  while (( $# > 0 )); do
    case "$1" in
      --to)
        (( $# >= 2 )) || {
          echo "claude-litellm task handoff: --to requires a route." >&2
          return 1
        }
        selector="$2"
        target="$(_claude_litellm_target_model_for_request "$selector")" || {
          echo "Unknown handoff route: $selector" >&2
          return 1
        }
        normalized+=(--to "$target")
        shift 2
        ;;
      --to=*)
        selector="${1#--to=}"
        target="$(_claude_litellm_target_model_for_request "$selector")" || {
          echo "Unknown handoff route: $selector" >&2
          return 1
        }
        normalized+=("--to=$target")
        shift
        ;;
      *)
        normalized+=("$1")
        shift
        ;;
    esac
  done
  [[ -n "$target" ]] || {
    echo "claude-litellm task handoff: --to <route> is required." >&2
    return 1
  }
  ai_litellm task handoff "${normalized[@]}"
}

_claude_litellm_task_launch() {
  if [[ -z "${1:-}" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: claude-litellm task launch <id> [--handoff <n|latest>]
       [--skip-local-readiness-check] [-- <claude args...>]

Launch a new Claude process in the task worktree, pinned to the handoff route.
Local runtime routes receive a live, non-billable probe before Claude starts.
Use --skip-local-readiness-check only to diagnose a route whose probe is known
to be incompatible. Arguments for Claude must follow --.
EOF
    [[ -n "${1:-}" ]] && return 0
    return 1
  fi

  local task_id="$1" handoff="latest" skip_readiness=0
  shift
  local -a claude_args
  while (( $# > 0 )); do
    case "$1" in
      --handoff)
        (( $# >= 2 )) || {
          echo "claude-litellm task launch: --handoff requires an index or latest." >&2
          return 1
        }
        handoff="$2"
        shift 2
        ;;
      --handoff=*)
        handoff="${1#--handoff=}"
        shift
        ;;
      --skip-local-readiness-check)
        skip_readiness=1
        shift
        ;;
      --)
        shift
        claude_args=("$@")
        break
        ;;
      *)
        echo "claude-litellm task launch: unknown option before --: $1" >&2
        return 1
        ;;
    esac
  done

  local plan route target_model worktree prompt
  plan="$(ai_litellm task prompt "$task_id" --handoff "$handoff" --json)" || return $?
  route="$(print -r -- "$plan" | jq -er '.route')" || return 1
  worktree="$(print -r -- "$plan" | jq -er '.worktree')" || return 1
  prompt="$(print -r -- "$plan" | jq -er '.prompt')" || return 1
  [[ -d "$worktree" ]] || {
    echo "Task worktree is no longer a directory: $worktree" >&2
    return 1
  }
  target_model="$(_claude_litellm_target_model_for_request "$route")" || {
    echo "Task handoff route is no longer registered: $route" >&2
    return 1
  }

  local runtime=""
  runtime="$(ai_litellm_model_runtime "$target_model" 2>/dev/null || true)"
  if [[ -n "$runtime" && "$skip_readiness" -eq 0 ]]; then
    echo "Checking local route readiness before starting a new worker: $target_model"
    ai_litellm_model_runtime_ready "$target_model" || return $?
    ai_litellm_start >/dev/null || return $?
    ai_litellm_probe_route "$target_model" || {
      echo "Refusing task launch because local route '$target_model' did not answer a live probe." >&2
      echo "Fix the runtime/model, choose another handoff route, or explicitly pass --skip-local-readiness-check for diagnostics." >&2
      return 1
    }
  fi

  ai_litellm task _mark-launched "$task_id" --handoff "$handoff" || return $?
  (
    cd "$worktree" || return 1
    _claude_litellm_launch_proxy "$target_model" "${claude_args[@]}" "$prompt"
  )
}

_claude_litellm_task() {
  local verb="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$verb" in
    launch)  _claude_litellm_task_launch "$@" ;;
    handoff) _claude_litellm_task_handoff "$@" ;;
    *)       ai_litellm task "$verb" "$@" ;;
  esac
}

claude-litellm() {
  if ! typeset -f ai_litellm >/dev/null 2>&1; then
    echo "Missing shared LiteLLM library: $AI_LITELLM_CONFIG_HOME/ai-litellm/lib.zsh" >&2
    return 1
  fi

  case "${1:-}" in
    -h|--help)
      echo "Usage: claude-litellm use <tier-or-route> [claude args...]"
      echo "       claude-litellm [fable|opus|sonnet|haiku|model_name] [claude args...]"
      echo "       claude-litellm use <registered-route> --default"
      echo "       claude-litellm task create|handoff|launch|complete ..."
      echo "       claude-litellm auth login|status|logout [chatgpt|grok]"
      echo "       claude-litellm status|doctor|sync|proxy|model|task|key|runtime|context|reasoning|permissions ..."
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
    use)
      shift
      _claude_litellm_use "$@"
      return $?
      ;;
    task)
      shift
      _claude_litellm_task "$@"
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
    proxy|harness|runtime|model|context|reasoning|key|permissions|sync)
      local control="$1"
      shift
      ai_litellm "$control" "$@"
      return $?
      ;;
    uninstall)
      shift
      ai_litellm uninstall "$@"
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
    # Tiers and registered model names are the only valid selectors.
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
