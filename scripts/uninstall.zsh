#!/usr/bin/env zsh

set -euo pipefail

repo_root="${0:A:h:h}"
prefix="${AI_LITELLM_FABRIC_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm-fabric}"
bin_dir="$HOME/.local/bin"
dry_run=0
remove_legacy=0
purge_keychain=0

usage() {
  cat <<'EOF'
Usage: scripts/uninstall.zsh [--dry-run] [--prefix PATH] [--legacy] [--purge-keychain]

Removes the ai-litellm-fabric package directory and global command shims.
Stops the shared LiteLLM proxy first so its state is not deleted out from
under a live process.

With --purge-keychain, also deletes the macOS Keychain secrets the fabric
created (litellm-master-key, openrouter-api-key). Without it, the exact
removal commands are printed instead, since a provider key may be shared
with other tools.

Default removal:
  - ~/.local/share/ai-litellm-fabric
  - ~/.local/bin/ai-litellm
  - ~/.local/bin/claude-litellm
  - ~/.local/bin/codex-litellm
  - ~/.local/bin/opencode-litellm
  - ~/.local/bin/openrouter-key-status
  - ~/.local/bin/litellm-master-key-status

With --legacy, also removes older spread-out wrapper paths:
  - ~/litellm_config.yaml
  - ~/.config/ai-litellm
  - ~/.config/claude-litellm
  - ~/.config/codex-litellm
  - ~/.config/opencode-litellm

It never removes native ~/.claude or ~/.codex.
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
      [[ $# -gt 0 ]] || {
        echo "--prefix requires a path" >&2
        exit 1
      }
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

run() {
  if (( dry_run )); then
    printf 'dry-run '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

stop_running_proxy() {
  # The proxy pid file lives under the prefix we are about to delete; rm -rf'ing
  # it out from under a live process orphans the proxy. Stop it first, but only
  # if the pid is actually our litellm (never signal an unrelated recycled pid).
  local pid_file="$prefix/state/ai-litellm/litellm.pid"
  [[ -f "$pid_file" ]] || return 0
  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ "$pid" == <-> ]] || return 0
  kill -0 "$pid" 2>/dev/null || return 0
  ps -o command= -p "$pid" 2>/dev/null | grep -q 'litellm' || return 0

  if (( dry_run )); then
    printf 'dry-run '
    printf '%q ' kill -TERM "$pid"
    printf '\n'
    return 0
  fi

  echo "Stopping running LiteLLM proxy (pid $pid) before removing its state."
  kill -TERM "$pid" 2>/dev/null || true
  local i
  for i in {1..20}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
}

handle_keychain() {
  command -v security >/dev/null 2>&1 || return 0
  local -a services=(litellm-master-key openrouter-api-key)
  local svc
  local -a found=()
  for svc in $services; do
    if security find-generic-password -s "$svc" >/dev/null 2>&1; then
      found+=("$svc")
    fi
  done
  (( ${#found} )) || return 0

  if (( purge_keychain )); then
    for svc in $found; do
      run security delete-generic-password -a "$USER" -s "$svc"
    done
    return 0
  fi

  echo "Keychain secrets created by the fabric were left in place (they may be" >&2
  echo "shared with other tools). Re-run with --purge-keychain, or remove them with:" >&2
  for svc in $found; do
    echo "  security delete-generic-password -a \"$USER\" -s \"$svc\"" >&2
  done
}

assert_fabric_prefix_safe() {
  if [[ "${prefix:t}" != "ai-litellm-fabric" ]]; then
    echo "Refusing to remove non ai-litellm-fabric prefix: $prefix" >&2
    echo "Pass the real package prefix, not a parent directory." >&2
    exit 1
  fi

  if [[ -e "$prefix" && ! -f "$prefix/config/ai-litellm/lib.zsh" ]]; then
    echo "Refusing to remove prefix that does not look like an ai-litellm-fabric package: $prefix" >&2
    exit 1
  fi
}

assert_fabric_prefix_safe

for script in ai-litellm claude-litellm codex-litellm opencode-litellm openrouter-key-status litellm-master-key-status fabric goose-litellm; do
  run rm -f "$bin_dir/$script"
  for backup in "$bin_dir/$script".bak.*(N); do
    run rm -f "$backup"
  done
done

stop_running_proxy

run rm -rf "$prefix"

handle_keychain

if (( remove_legacy )); then
  run rm -f "$HOME/litellm_config.yaml"
  run rm -rf \
    "$HOME/.config/ai-litellm" \
    "$HOME/.config/claude-litellm" \
    "$HOME/.config/codex-litellm" \
    "$HOME/.config/opencode-litellm"
fi

print -r -- "Removed ai-litellm-fabric package/shims."
if (( remove_legacy )); then
  print -r -- "Removed legacy spread-out wrapper paths."
fi
