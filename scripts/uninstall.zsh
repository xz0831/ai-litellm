#!/usr/bin/env zsh

set -euo pipefail

prefix="${CLAUDE_LITELLM_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm}"
bin_dir="$HOME/.local/bin"
dry_run=0
remove_legacy=0
purge_keychain=0

usage() {
  cat <<'EOF'
Usage: scripts/uninstall.zsh [--dry-run] [--prefix PATH] [--legacy]
                             [--purge-keychain]

Removes the claude-litellm package and its single public shim after stopping a
proxy owned by that package.

Default removal:
  ~/.local/share/claude-litellm
  ~/.local/bin/claude-litellm

With --legacy, recognized ai-litellm and ai-litellm-fabric package roots and
their owned shims are also removed. This is intentionally explicit because an
unmigrated legacy package may still contain Claude transcripts.

Native ~/.claude, ~/.codex, native claude/codex commands, and Keychain entries
are never removed by default. --purge-keychain is the only operation that
deletes known package Keychain entries.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --legacy)
      remove_legacy=1
      ;;
    --purge-keychain)
      purge_keychain=1
      ;;
    --prefix)
      shift
      [[ $# -gt 0 ]] || { echo "--prefix requires a path" >&2; exit 1; }
      prefix="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

prefix="${prefix:A}"

run() {
  if (( dry_run )); then
    printf 'dry-run '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

assert_prefix_safe() {
  local target="$1"
  [[ "$target" != "/" && "$target" != "$HOME" && "$target" != "${XDG_DATA_HOME:-$HOME/.local/share}" ]] || {
    echo "Refusing unsafe package prefix: $target" >&2
    exit 1
  }
  [[ ! -L "$target" ]] || {
    echo "Refusing symlink package prefix: $target" >&2
    exit 1
  }
  [[ ! -e "$target" || -f "$target/config/ai-litellm/lib.zsh" || -f "$target/install-manifest.json" ]] || {
    echo "Refusing directory that does not look like claude-litellm: $target" >&2
    exit 1
  }
}

proxy_command_owned_by_prefix() {
  local command_line="$1"
  local owner_prefix="$2"
  local allow_external_runtime="${3:-0}"
  local process_executable="${4:-}"
  local config="$owner_prefix/config/litellm_config.yaml"
  local venv="$owner_prefix/runtime/venv"
  local bootstrap="$owner_prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"
  local executable_name="${process_executable:t:l}"
  [[ "$command_line" == *"--config $config"* || "$command_line" == *"--config=$config"* ]] || return 1
  if [[ "$executable_name" == python* ]]; then
    [[ "$command_line" == "$process_executable $venv/bin/litellm "* || \
       "$command_line" == "$process_executable $venv/bin/litellm-proxy "* || \
       ( -f "$bootstrap" && ! -L "$bootstrap" && "$command_line" == "$process_executable $bootstrap --config $config"* ) || \
       ( -f "$bootstrap" && ! -L "$bootstrap" && "$command_line" == "$venv/bin/python $bootstrap --config $config"* ) || \
       "$command_line" == "$process_executable $venv/"*"/litellm/proxy/"* ]] && return 0
  elif [[ "$process_executable" == "$venv/bin/litellm" || \
          "$process_executable" == "$venv/bin/litellm-proxy" ]]; then
    [[ "$command_line" == "$process_executable "* ]] && return 0
  fi
  (( allow_external_runtime )) || return 1
  case "$executable_name" in
    litellm|litellm-proxy)
      [[ "$command_line" == "$process_executable "* ]]
      ;;
    python*)
      [[ "$command_line" == "$process_executable "*/bin/litellm" --config $config"* || \
         "$command_line" == "$process_executable "*/bin/litellm-proxy" --config $config"* || \
         "$command_line" == "$process_executable $bootstrap --config $config"* || \
         "$command_line" == "$process_executable -m litellm --config $config"* ]]
      ;;
    *) return 1 ;;
  esac
}

stop_running_proxy() {
  local target_prefix="$1"
  [[ -d "$target_prefix" ]] || return 0
  local pid_file="$target_prefix/state/ai-litellm/litellm.pid"
  local pid command_line process_executable line candidate
  typeset -A owned_pids
  owned_pids=()

  if [[ -e "$pid_file" || -L "$pid_file" ]]; then
    [[ -f "$pid_file" && ! -L "$pid_file" ]] || {
      echo "Refusing removal: proxy PID file is not a regular file: $pid_file" >&2
      return 1
    }
    pid="$(<"$pid_file")"
    [[ "$pid" == <-> ]] || {
      echo "Refusing removal: invalid proxy PID in $pid_file" >&2
      return 1
    }
    if kill -0 "$pid" 2>/dev/null; then
      command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
      process_executable="$(ps -ww -o comm= -p "$pid" 2>/dev/null || true)"
      proxy_command_owned_by_prefix "$command_line" "$target_prefix" 1 "$process_executable" || {
        echo "Refusing to signal pid $pid from $pid_file: process is not owned by $target_prefix" >&2
        return 1
      }
      owned_pids[$pid]=1
    fi
  fi

  while IFS= read -r line; do
    [[ "$line" =~ '^[[:space:]]*([0-9]+)[[:space:]]+(.*)$' ]] || continue
    candidate="${match[1]}"
    command_line="${match[2]}"
    [[ "$candidate" != "$$" ]] || continue
    [[ "$command_line" == *"--config $target_prefix/config/litellm_config.yaml"* || \
       "$command_line" == *"--config=$target_prefix/config/litellm_config.yaml"* ]] || continue
    [[ -z "${owned_pids[$candidate]:-}" ]] || continue
    process_executable="$(ps -ww -o comm= -p "$candidate" 2>/dev/null || true)"
    if proxy_command_owned_by_prefix "$command_line" "$target_prefix" 0 "$process_executable"; then
      owned_pids[$candidate]=0
    elif proxy_command_owned_by_prefix "$command_line" "$target_prefix" 1 "$process_executable"; then
      echo "Refusing removal: external LiteLLM pid $candidate uses $target_prefix config without an owned PID file." >&2
      return 1
    fi
  done < <(ps -axo pid=,command= 2>/dev/null)

  for pid in ${(k)owned_pids}; do
    command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
    process_executable="$(ps -ww -o comm= -p "$pid" 2>/dev/null || true)"
    proxy_command_owned_by_prefix "$command_line" "$target_prefix" "${owned_pids[$pid]}" "$process_executable" || {
      echo "Refusing to signal pid $pid: ownership changed during verification." >&2
      return 1
    }
    if (( dry_run )); then
      echo "dry-run stop proxy owned by $target_prefix (pid $pid)"
      continue
    fi
    echo "Stopping proxy owned by $target_prefix (pid $pid)."
    kill -TERM "$pid" 2>/dev/null || true
    local attempt
    for attempt in {1..30}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
      process_executable="$(ps -ww -o comm= -p "$pid" 2>/dev/null || true)"
      if proxy_command_owned_by_prefix "$command_line" "$target_prefix" "${owned_pids[$pid]}" "$process_executable"; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    fi
  done

  (( dry_run )) && return 0
  while IFS= read -r line; do
    [[ "$line" =~ '^[[:space:]]*([0-9]+)[[:space:]]+(.*)$' ]] || continue
    [[ "${match[2]}" == *"--config $target_prefix/config/litellm_config.yaml"* || \
       "${match[2]}" == *"--config=$target_prefix/config/litellm_config.yaml"* ]] || continue
    process_executable="$(ps -ww -o comm= -p "${match[1]}" 2>/dev/null || true)"
    if proxy_command_owned_by_prefix "${match[2]}" "$target_prefix" 0 "$process_executable"; then
      echo "Refusing removal: owned proxy pid ${match[1]} is still running." >&2
      return 1
    elif proxy_command_owned_by_prefix "${match[2]}" "$target_prefix" 1 "$process_executable"; then
      echo "Refusing removal: external LiteLLM pid ${match[1]} still uses $target_prefix config." >&2
      return 1
    fi
  done < <(ps -axo pid=,command= 2>/dev/null)
}

remove_shim_if_owned() {
  local target="$1"
  local expected_prefix="${2:-}"
  [[ -e "$target" || -L "$target" ]] || return 0
  if [[ -L "$target" ]]; then
    local link_target="$(readlink "$target" 2>/dev/null || true)"
    [[ "$link_target" == *litellm* && ( -z "$expected_prefix" || "$link_target" == *"$expected_prefix"* ) ]] || {
      echo "Leaving unrelated command in place: $target" >&2
      return 0
    }
  else
    grep -Eq 'claude-litellm|ai-litellm(-fabric)?|AI_LITELLM_HOME|CLAUDE_LITELLM_HOME' "$target" 2>/dev/null || {
      echo "Leaving unrelated command in place: $target" >&2
      return 0
    }
    if [[ -n "$expected_prefix" ]] && ! grep -Fq -- "$expected_prefix" "$target" 2>/dev/null; then
      echo "Leaving shim for a different package prefix in place: $target" >&2
      return 0
    fi
  fi
  run rm -f "$target"
}

recognized_legacy_prefix() {
  local target="$1"
  [[ ! -L "$target" ]] || return 1
  [[ "${target:t}" == "ai-litellm" || "${target:t}" == "ai-litellm-fabric" ]] || return 1
  [[ -f "$target/config/ai-litellm/lib.zsh" ]] || return 1
}

handle_keychain() {
  (( purge_keychain )) || {
    echo "Keychain entries were left unchanged. Use --purge-keychain only if their credentials are not shared." >&2
    return 0
  }
  command -v security >/dev/null 2>&1 || return 0
  local -a services=(litellm-master-key openrouter-api-key)
  local service
  for service in "${services[@]}"; do
    security find-generic-password -s "$service" >/dev/null 2>&1 || continue
    run security delete-generic-password -a "${USER:-}" -s "$service"
  done
}

assert_prefix_safe "$prefix"
stop_running_proxy "$prefix"
remove_shim_if_owned "$bin_dir/claude-litellm" "$prefix"
run rm -rf "$prefix"

if (( remove_legacy )); then
  typeset -a legacy_prefixes
  legacy_prefixes=(
    "${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm-fabric"
    "${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm"
  )
  local_prefix=""
  for local_prefix in "${legacy_prefixes[@]}"; do
    [[ -e "$local_prefix" ]] || continue
    recognized_legacy_prefix "$local_prefix" || {
      echo "Refusing unrecognized legacy directory: $local_prefix" >&2
      exit 1
    }
    stop_running_proxy "$local_prefix"
    run rm -rf "$local_prefix"
  done
  for shim in ai-litellm codex-litellm opencode-litellm goose-litellm fabric \
    openrouter-key-status litellm-master-key-status; do
    remove_shim_if_owned "$bin_dir/$shim"
  done
fi

handle_keychain

echo "Removed claude-litellm package and owned shim."
if (( remove_legacy )); then
  echo "Removed recognized legacy packages/shims. Native ~/.claude and ~/.codex were untouched."
fi
