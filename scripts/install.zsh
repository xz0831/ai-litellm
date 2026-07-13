#!/usr/bin/env zsh

set -euo pipefail

repo_root="${0:A:h:h}"
default_prefix="${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm"
prefix="${CLAUDE_LITELLM_ROOT:-$default_prefix}"
bin_dir="$HOME/.local/bin"
dry_run=0
skip_preflight=0
migrate_legacy=1
prefix_explicit=0
install_shim=1
runtime_stage=""
preflight_stage=""
runtime_build_rust=""
user_config_root="${XDG_CONFIG_HOME:-$HOME/.config}/claude-litellm"
install_lock=""
user_mutation_lock=""
install_lock_fd=""
user_mutation_lock_fd=""
publication_backup=""
publication_active=0
publication_prefix_existed=0
publication_manifest_existed=0
publication_manifest_processed=0
publication_runtime_published=0
publication_runtime_root_moved=0
publication_runtime_venv_moved=0
public_shim_active=0
public_shim_target_existed=0
public_shim_stage=""
public_shim_backup=""
proxy_was_running=0
proxy_restart_pending=0
postcommit_warning_count=0
typeset -ga package_managed_files package_generated_files package_executable_files
typeset -ga package_allowed_files package_allowed_dirs
typeset -gA package_allowed_file_set package_allowed_dir_set
typeset -gA publication_processed_roots publication_moved_roots
initial_prefix_identity=""
initial_prefix_existed=0

readonly LITELLM_VERSION="1.92.0"
readonly PRISMA_VERSION="0.15.0"
readonly RUST_TOOLCHAIN_VERSION="1.97.0"
readonly RUNTIME_BUILD_EPOCH="2026-07-13.3"

usage() {
  cat <<'EOF'
Usage: scripts/install.zsh [--dry-run] [--prefix PATH] [--skip-preflight]
                           [--no-migrate] [--no-shim]

Installs claude-litellm with one public command:
  package: ~/.local/share/claude-litellm
  command: ~/.local/bin/claude-litellm

The package contains an isolated, validated Python 3.13 runtime with
litellm[proxy]==1.92.0 and prisma==0.15.0. Runtime updates are assembled in a
staging directory and published only after import/version checks pass.

Package defaults are immutable. User-added models, Claude aliases, reasoning
preferences and the permission-mode opt-in live under ~/.config/claude-litellm
and are preserved and validated when a new package version renders its
effective configuration.

On a normal install, durable Claude state is migrated from ai-litellm-fabric or
ai-litellm and those legacy package roots/shims are removed after verification.
The complete legacy package is first byte-verified under
~/.local/share/claude-litellm-backups; generated overlays, security state,
caches, venvs, and Codex state remain only in that backup and are not migrated.
Use --no-migrate to retain legacy packages unchanged.

A custom --prefix is staging-friendly: legacy migration is disabled unless the
prefix is the standard claude-litellm location, and no global shim is written.
Native ~/.claude, ~/.codex, the native claude/codex commands, and Keychain
entries are never changed.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --skip-preflight)
      skip_preflight=1
      ;;
    --no-migrate)
      migrate_legacy=0
      ;;
    --no-shim)
      install_shim=0
      ;;
    --prefix)
      shift
      [[ $# -gt 0 ]] || { echo "--prefix requires a path" >&2; exit 1; }
      prefix="$1"
      prefix_explicit=1
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

# `:a` makes the path lexical/absolute without resolving an existing symlink.
# Resolving first (`:A`) made the later symlink-prefix guard inspect the target
# instead of the path the caller actually supplied.
prefix="${prefix:a}"
default_prefix="${default_prefix:a}"
bin_dir="${bin_dir:a}"
user_config_root="${user_config_root:a}"
if (( prefix_explicit )) && [[ "$prefix" != "$default_prefix" ]]; then
  migrate_legacy=0
  install_shim=0
fi

# The public shim is a file below bin_dir while the package prefix is a managed
# directory tree. Overlap makes publication self-destructive (for example an
# XDG_DATA_HOME of ~/.local/bin would make the default package path equal the
# shim target). Keep both transaction domains strictly disjoint.
if [[ "$prefix" == "$bin_dir" || "$bin_dir" == "$prefix"/* ]]; then
  echo "Refusing package/public-command path overlap: package=$prefix command-dir=$bin_dir" >&2
  exit 1
fi
if (( install_shim )) && [[ "$prefix" == "$bin_dir"/* ]]; then
  echo "Refusing package/public-command path overlap: package=$prefix command-dir=$bin_dir" >&2
  exit 1
fi

# Durable overlays are not package bytes. They must remain outside the package
# tree so reinstall/uninstall can never prune the authoritative models/settings
# files through an unusual XDG layout.
if [[ "$prefix" == "$user_config_root" || "$prefix" == "$user_config_root"/* || \
      "$user_config_root" == "$prefix"/* ]]; then
  echo "Refusing package/user-configuration path overlap: package=$prefix user-config=$user_config_root" >&2
  exit 1
fi

# claude-litellm owns an isolated Claude configuration below package state; it
# never owns native Claude Code or Codex homes. Reject even package descendants
# there so the unconditional preservation promise remains true.
for protected_native_root in "${HOME:a}/.claude" "${HOME:a}/.codex"; do
  if [[ "$prefix" == "$protected_native_root" || "$prefix" == "$protected_native_root"/* ]]; then
    echo "Refusing package prefix inside protected native state: $prefix" >&2
    exit 1
  fi
done

log() {
  print -r -- "$*"
}

run() {
  if (( dry_run )); then
    printf 'dry-run '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# An isolated interpreter invocation must not import a same-named module from
# the caller's working directory or honor caller-supplied Python path settings.
# Keep this wrapper small so it also works for the bootstrap Python before the
# managed venv exists.
python_isolated() {
  local interpreter="$1"
  shift
  env -u PYTHONPATH -u PYTHONHOME -u PYTHONSTARTUP -u PYTHONINSPECT \
    -u PYTHONBREAKPOINT -u PYTHONUSERBASE -u PYTHONEXECUTABLE \
    -u PYTHONWARNINGS -u PYTHONPLATLIBDIR -u PYTHONPYCACHEPREFIX \
    "$interpreter" -I -B "$@"
}

cleanup_resources() {
  setopt localoptions noerrexit
  if (( publication_active )); then
    rollback_package_publication >/dev/null || true
  fi
  if [[ -n "$public_shim_backup" && ! -e "$public_shim_backup" && ! -L "$public_shim_backup" ]]; then
    rmdir "${public_shim_backup:h}" 2>/dev/null || true
  fi
  local owned_lock
  for owned_lock in "$user_mutation_lock" "$install_lock"; do
    [[ -n "$owned_lock" && -d "$owned_lock" ]] || continue
    if [[ "$(<"$owned_lock/pid" 2>/dev/null || true)" == "$$" ]]; then
      rm -rf "$owned_lock" 2>/dev/null || true
    fi
  done
  zmodload zsh/system 2>/dev/null || true
  [[ "$user_mutation_lock_fd" == <-> ]] && zsystem flock -u "$user_mutation_lock_fd" 2>/dev/null || true
  [[ "$install_lock_fd" == <-> ]] && zsystem flock -u "$install_lock_fd" 2>/dev/null || true
  user_mutation_lock_fd=""
  install_lock_fd=""
  if [[ -n "$runtime_stage" && -e "$runtime_stage" ]]; then
    rm -rf "$runtime_stage" 2>/dev/null || true
  fi
  if [[ -n "$preflight_stage" && -e "$preflight_stage" ]]; then
    rm -rf "$preflight_stage" 2>/dev/null || true
  fi
  if [[ -n "$public_shim_stage" && ( -e "$public_shim_stage" || -L "$public_shim_stage" ) ]]; then
    rm -f "$public_shim_stage" 2>/dev/null || true
    public_shim_stage=""
  fi
  # `proxy start` takes the same lifecycle flock as this installer. Rollback
  # must finish while locked, but restart only after both marker directories
  # and flock descriptors are gone or the CLI deadlocks against this process.
  if (( proxy_restart_pending )) && ! restore_proxy_liveness >/dev/null 2>&1; then
    echo "Warning: the previously running proxy could not be restarted." >&2
  fi
  return 0
}

cleanup() {
  local exit_status=$?
  cleanup_resources
  return $exit_status
}

# zsh does not run an EXIT trap when `ERR_EXIT` terminates the script because a
# function returned nonzero. The installer is function-heavy, so EXIT alone
# cannot guarantee rollback. ZERR runs in that case; cleanup_resources is
# idempotent so an eventual EXIT trap may safely run it a second time.
cleanup_error() {
  local exit_status=$?
  cleanup_resources
  return $exit_status
}
trap cleanup EXIT
trap cleanup_error ZERR
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_owned_lock() {
  # `path` is a special zsh array tied to PATH; never shadow it here or every
  # external command in this function disappears from command lookup.
  local lock_path="$1" label="$2" secure_parent="${3:-0}" fd_var="$4" owner fd
  local lock_file="${1}.flock"
  if (( secure_parent )); then
    assert_no_symlink_ancestors "${lock_path:h}" || return 1
    if [[ -e "${lock_path:h}" || -L "${lock_path:h}" ]]; then
      [[ -d "${lock_path:h}" && ! -L "${lock_path:h}" ]] || {
        echo "Refusing unsafe $label parent: ${lock_path:h}" >&2
        return 1
      }
    fi
  fi
  mkdir -p "${lock_path:h}"
  if (( secure_parent )); then
    assert_no_symlink_ancestors "${lock_path:h}" || return 1
    [[ -d "${lock_path:h}" && ! -L "${lock_path:h}" ]] || return 1
    chmod 700 "${lock_path:h}"
  fi
  if [[ ! -e "$lock_file" && ! -L "$lock_file" ]]; then
    ( umask 077; setopt noclobber; : > "$lock_file" ) 2>/dev/null || true
  fi
  [[ -f "$lock_file" && ! -L "$lock_file" ]] || {
    echo "Refusing unsafe lock file: $lock_file" >&2
    return 1
  }
  chmod 600 "$lock_file" 2>/dev/null || true
  zmodload zsh/system || { echo "zsh/system is required for installation locks." >&2; return 1; }
  if ! zsystem flock -t 0 -f fd "$lock_file"; then
    echo "Refusing concurrent $label." >&2
    return 1
  fi
  typeset -g "$fd_var=$fd"
  if [[ -L "$lock_path" || ( -e "$lock_path" && ! -d "$lock_path" ) ]]; then
    zsystem flock -u "$fd" 2>/dev/null || true
    typeset -g "$fd_var="
    echo "Refusing unsafe lock path: $lock_path" >&2
    return 1
  elif [[ -d "$lock_path" ]]; then
    owner="$(<"$lock_path/pid" 2>/dev/null || printf '?')"
    if [[ "$owner" != '?' && "$owner" != "$$" ]] && kill -0 "$owner" 2>/dev/null; then
      zsystem flock -u "$fd" 2>/dev/null || true
      typeset -g "$fd_var="
      echo "Refusing concurrent legacy $label (pid $owner)." >&2
      return 1
    fi
    rm -rf "$lock_path"
  fi
  mkdir "$lock_path" || { zsystem flock -u "$fd" 2>/dev/null || true; typeset -g "$fd_var="; return 1; }
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$lock_path/started_at"
  printf '%s\n' "$$" > "$lock_path/pid"
}

release_owned_lock() {
  local lock_path="$1" fd_var="$2" fd=""
  fd="${(P)fd_var}"
  [[ -d "$lock_path" && "$(<"$lock_path/pid" 2>/dev/null || true)" == "$$" ]] && rm -rf "$lock_path"
  [[ "$fd" == <-> ]] && zsystem flock -u "$fd" 2>/dev/null || true
  typeset -g "$fd_var="
}

require_file() {
  local file_path="$1"
  [[ -f "$file_path" ]] || {
    echo "Missing repository file: $file_path" >&2
    exit 1
  }
}

package_manifest_identity_valid() {
  local target="$1" manifest="$1/install-manifest.json"
  [[ -f "$manifest" && ! -L "$manifest" ]] || return 1
  node -e '
const fs = require("fs");
const [manifest, expectedPrefix] = process.argv.slice(1);
try {
  const payload = JSON.parse(fs.readFileSync(manifest, "utf8"));
  const ok = payload && typeof payload === "object" && !Array.isArray(payload)
    && payload.product === "claude-litellm"
    && payload.prefix === expectedPrefix
    && (payload.schemaVersion === 1 || payload.schemaVersion === 2);
  process.exit(ok ? 0 : 1);
} catch (_) { process.exit(1); }
' "$manifest" "$target"
}

assert_no_symlink_ancestors() {
  local target="$1" component current="/" link_target=""
  local -a components
  components=("${(@s:/:)target}")
  for component in "${components[@]}"; do
    [[ -n "$component" ]] || continue
    current="${current%/}/$component"
    if [[ -L "$current" ]]; then
      link_target="$(readlink "$current" 2>/dev/null || true)"
      # macOS exposes its real private directories through two fixed,
      # root-owned compatibility aliases. TMPDIR normally begins /var/folders,
      # so rejecting /var would make every staged/test install unusable. Permit
      # only these exact OS aliases; all later/user-controlled links and the
      # prefix leaf are still rejected below/by assert_prefix_safe.
      case "$current:$link_target" in
        /var:private/var|/tmp:private/tmp) ;;
        *)
          echo "Refusing path with a symlink component: $current" >&2
          return 1
          ;;
      esac
    fi
    if [[ "$current" != "$target" && ( -e "$current" || -L "$current" ) ]]; then
      [[ -d "$current" ]] || {
        echo "Refusing path with a non-directory ancestor: $current" >&2
        return 1
      }
    fi
  done
}

assert_user_config_root_safe() {
  assert_no_symlink_ancestors "$user_config_root" || return 1
  if [[ -e "$user_config_root" || -L "$user_config_root" ]]; then
    [[ -d "$user_config_root" && ! -L "$user_config_root" ]] || {
      echo "Refusing unsafe user configuration root: $user_config_root" >&2
      return 1
    }
  fi
}

assert_prefix_safe() {
  local home_abs="${HOME:a}"
  local data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
  data_root="${data_root:a}"
  [[ "$prefix" != "/" && "$prefix" != "$home_abs" && "$prefix" != "$data_root" ]] || {
    echo "Refusing unsafe package prefix: $prefix" >&2
    exit 1
  }
  assert_no_symlink_ancestors "$prefix" || exit 1
  [[ ! -L "$prefix" ]] || {
    echo "Refusing symlink package prefix: $prefix" >&2
    exit 1
  }
  if [[ -e "$prefix" && ! -d "$prefix" ]]; then
    echo "Refusing non-directory package prefix: $prefix" >&2
    exit 1
  fi
  # After the complete lexical chain has been inspected, normalize only the
  # two fixed macOS compatibility aliases we explicitly trusted above. The
  # installed launcher resolves its own path with `:A`; recording /var while
  # the launcher later reports /private/var would otherwise make a valid
  # manifest fail its own prefix identity check. Never resolve any other path.
  if [[ "$prefix" == /var/* && "$(readlink /var 2>/dev/null || true)" == "private/var" ]]; then
    prefix="/private$prefix"
  elif [[ "$prefix" == /tmp/* && "$(readlink /tmp 2>/dev/null || true)" == "private/tmp" ]]; then
    prefix="/private$prefix"
  fi
  if [[ -d "$prefix" && -n "$(find "$prefix" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    if [[ -e "$prefix/install-manifest.json" || -L "$prefix/install-manifest.json" ]]; then
      package_manifest_identity_valid "$prefix" || {
        echo "Refusing package prefix with an invalid ownership manifest: $prefix" >&2
        exit 1
      }
    elif [[ -f "$prefix/config/ai-litellm/lib.zsh" && \
            ! -L "$prefix/config/ai-litellm/lib.zsh" ]] && \
         grep -q 'claude-litellm' "$prefix/config/ai-litellm/lib.zsh" 2>/dev/null; then
      : # supported pre-manifest package migration
    else
      echo "Refusing to overwrite a directory that is not a claude-litellm package: $prefix" >&2
      exit 1
    fi
  fi
}

path_identity() {
  local target="$1" value
  value="$(stat -f '%d:%i' "$target" 2>/dev/null || true)"
  [[ -n "$value" ]] || value="$(stat -c '%d:%i' "$target" 2>/dev/null || true)"
  [[ -n "$value" ]] || return 1
  print -r -- "$value"
}

# State is durable and may contain OAuth credentials and isolated transcripts.
# Never "repair" it by deleting a suspicious component, and never let mkdir or
# a later credential write follow a symlinked ancestor outside the package.
validate_state_layout_for_writes() {
  local state_path
  local -a state_dirs=(
    "$prefix/state"
    "$prefix/state/ai-litellm"
    "$prefix/state/auth"
    "$prefix/state/auth/chatgpt"
    "$prefix/state/auth/grok"
    "$prefix/state/claude-litellm"
    "$prefix/state/claude-litellm/claude-config"
  )
  for state_path in "${state_dirs[@]}"; do
    [[ -e "$state_path" || -L "$state_path" ]] || continue
    [[ -d "$state_path" && ! -L "$state_path" ]] || {
      echo "Refusing unsafe package state directory component: $state_path" >&2
      echo "State was not changed; replace the symlink/non-directory manually after preserving its contents." >&2
      return 1
    }
  done
}

preflight_litellm_master_key() {
  local env_file="$prefix/state/ai-litellm/env"
  [[ -e "$env_file" || -L "$env_file" ]] || return 0
  [[ -f "$env_file" && ! -L "$env_file" ]] || {
    echo "Refusing unsafe package env path: $env_file" >&2
    return 1
  }
}

preflight_public_shim() {
  (( install_shim )) || return 0
  local target="$bin_dir/claude-litellm"
  assert_no_symlink_ancestors "$bin_dir" || return 1
  if [[ -e "$bin_dir" || -L "$bin_dir" ]]; then
    [[ -d "$bin_dir" && ! -L "$bin_dir" ]] || {
      echo "Refusing unsafe public command directory: $bin_dir" >&2
      return 1
    }
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -f "$target" || -L "$target" ]] || {
      echo "Refusing unsafe public command path: $target" >&2
      return 1
    }
  fi
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

  # Strong form used for ps-wide discovery: ps `comm` must be the prefix venv
  # executable, and argv must begin with that executable plus the LiteLLM
  # script/module. A path appearing later in rg/editor/backup argv is not proof.
  if [[ "$executable_name" == python* ]]; then
    [[ "$command_line" == "$process_executable $venv/bin/litellm "* || \
       "$command_line" == "$process_executable $venv/bin/litellm-proxy "* || \
       ( -f "$bootstrap" && ! -L "$bootstrap" && "$command_line" == "$process_executable $bootstrap --config $config"* ) || \
       ( -f "$bootstrap" && ! -L "$bootstrap" && "$command_line" == "$venv/bin/python $bootstrap --config $config"* ) || \
       ( -f "$bootstrap" && ! -L "$bootstrap" && "$command_line" == "$process_executable -sP -B $bootstrap --config $config"* ) || \
       ( -f "$bootstrap" && ! -L "$bootstrap" && "$command_line" == "$venv/bin/python -sP -B $bootstrap --config $config"* ) || \
       "$command_line" == "$process_executable $venv/"*"/litellm/proxy/"* ]] && return 0
  elif [[ "$process_executable" == "$venv/bin/litellm" || \
          "$process_executable" == "$venv/bin/litellm-proxy" ]]; then
    [[ "$command_line" == "$process_executable "* ]] && return 0
  fi

  # A legacy PID file may name a system/uv-managed LiteLLM runtime. Accept that
  # weaker form only for the explicit PID-file process, still requiring both an
  # actual LiteLLM executable/module and this exact config argument.
  (( allow_external_runtime )) || return 1
  case "$executable_name" in
    litellm|litellm-proxy)
      [[ "$command_line" == "$process_executable "* ]]
      ;;
    python*)
      [[ "$command_line" == "$process_executable "*/bin/litellm" --config $config"* || \
         "$command_line" == "$process_executable "*/bin/litellm-proxy" --config $config"* || \
         "$command_line" == "$process_executable $bootstrap --config $config"* || \
         "$command_line" == "$process_executable -sP -B $bootstrap --config $config"* || \
         "$command_line" == "$process_executable -m litellm --config $config"* ]]
      ;;
    *) return 1 ;;
  esac
}

stop_owned_proxy() {
  local owner_prefix="$1"
  local record_liveness="${2:-1}"
  [[ -d "$owner_prefix" ]] || return 0

  local pid_file="$owner_prefix/state/ai-litellm/litellm.pid"
  local pid command_line process_executable line candidate
  typeset -A owned_pids
  owned_pids=()

  if [[ -e "$pid_file" || -L "$pid_file" ]]; then
    [[ -f "$pid_file" && ! -L "$pid_file" ]] || {
      echo "Refusing to replace $owner_prefix: proxy PID file is not a regular file: $pid_file" >&2
      return 1
    }
    pid="$(<"$pid_file")"
    [[ "$pid" == <-> ]] || {
      echo "Refusing to replace $owner_prefix: invalid proxy PID in $pid_file" >&2
      return 1
    }
    if kill -0 "$pid" 2>/dev/null; then
      command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
      process_executable="$(ps -ww -o comm= -p "$pid" 2>/dev/null || true)"
      proxy_command_owned_by_prefix "$command_line" "$owner_prefix" 1 "$process_executable" || {
        echo "Refusing to signal pid $pid from $pid_file: process is not owned by $owner_prefix" >&2
        return 1
      }
      owned_pids[$pid]=1
    fi
  fi

  # Catch an owned proxy whose PID file is missing/stale, and multiple workers.
  while IFS= read -r line; do
    [[ "$line" =~ '^[[:space:]]*([0-9]+)[[:space:]]+(.*)$' ]] || continue
    candidate="${match[1]}"
    command_line="${match[2]}"
    [[ "$candidate" != "$$" ]] || continue
    [[ "$command_line" == *"--config $owner_prefix/config/litellm_config.yaml"* || \
       "$command_line" == *"--config=$owner_prefix/config/litellm_config.yaml"* ]] || continue
    [[ -z "${owned_pids[$candidate]:-}" ]] || continue
    process_executable="$(ps -ww -o comm= -p "$candidate" 2>/dev/null || true)"
    if proxy_command_owned_by_prefix "$command_line" "$owner_prefix" 0 "$process_executable"; then
      owned_pids[$candidate]=0
    elif proxy_command_owned_by_prefix "$command_line" "$owner_prefix" 1 "$process_executable"; then
      echo "Refusing to replace $owner_prefix: external LiteLLM pid $candidate uses its config without an owned PID file." >&2
      return 1
    fi
  done < <(ps -axo pid=,command= 2>/dev/null)

  if (( record_liveness )) && [[ "$owner_prefix" == "$prefix" ]] && (( ${#owned_pids} > 0 )); then
    proxy_was_running=1
    proxy_restart_pending=1
  fi

  for pid in ${(k)owned_pids}; do
    command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
    process_executable="$(ps -ww -o comm= -p "$pid" 2>/dev/null || true)"
    proxy_command_owned_by_prefix "$command_line" "$owner_prefix" "${owned_pids[$pid]}" "$process_executable" || {
      echo "Refusing to signal pid $pid: ownership changed during verification." >&2
      return 1
    }
    if (( dry_run )); then
      log "dry-run stop proxy owned by $owner_prefix (pid $pid)"
      continue
    fi
    log "Stopping proxy owned by $owner_prefix (pid $pid)."
    kill -TERM "$pid" 2>/dev/null || true
    local attempt
    for attempt in {1..30}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
      process_executable="$(ps -ww -o comm= -p "$pid" 2>/dev/null || true)"
      if proxy_command_owned_by_prefix "$command_line" "$owner_prefix" "${owned_pids[$pid]}" "$process_executable"; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    fi
  done

  (( dry_run )) && return 0
  while IFS= read -r line; do
    [[ "$line" =~ '^[[:space:]]*([0-9]+)[[:space:]]+(.*)$' ]] || continue
    [[ "${match[2]}" == *"--config $owner_prefix/config/litellm_config.yaml"* || \
       "${match[2]}" == *"--config=$owner_prefix/config/litellm_config.yaml"* ]] || continue
    process_executable="$(ps -ww -o comm= -p "${match[1]}" 2>/dev/null || true)"
    if proxy_command_owned_by_prefix "${match[2]}" "$owner_prefix" 0 "$process_executable"; then
      echo "Refusing to replace $owner_prefix: owned proxy pid ${match[1]} is still running." >&2
      return 1
    elif proxy_command_owned_by_prefix "${match[2]}" "$owner_prefix" 1 "$process_executable"; then
      echo "Refusing to replace $owner_prefix: external LiteLLM pid ${match[1]} still uses its config." >&2
      return 1
    fi
  done < <(ps -axo pid=,command= 2>/dev/null)
  return 0
}

begin_package_publication() {
  (( dry_run )) && return 0
  publication_backup="$(mktemp -d "${prefix:h}/.${prefix:t}.publication-backup.XXXXXX")"
  chmod 700 "$publication_backup"
  publication_active=1
  publication_processed_roots=()
  publication_moved_roots=()
  publication_manifest_processed=0
  publication_manifest_existed=0
  publication_runtime_root_moved=0
  publication_runtime_venv_moved=0

  if [[ -f "$prefix/install-manifest.json" && ! -L "$prefix/install-manifest.json" ]]; then
    local manifest_stage="$publication_backup/.install-manifest.json.tmp"
    cp -p "$prefix/install-manifest.json" "$manifest_stage"
    python_isolated python3.13 -S - "$manifest_stage" <<'PY'
import os
import sys
fd = os.open(sys.argv[1], os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
try:
    os.fsync(fd)
finally:
    os.close(fd)
PY
    mv "$manifest_stage" "$publication_backup/install-manifest.json"
    publication_manifest_existed=1
  fi
  publication_manifest_processed=1

  local root source
  for root in bin config docs scripts; do
    source="$prefix/$root"
    if [[ -e "$source" || -L "$source" ]]; then
      mv "$source" "$publication_backup/$root"
      publication_moved_roots[$root]=1
    fi
    publication_processed_roots[$root]=1
  done

  # A rebuildable runtime root with a hostile type must not be followed. Keep
  # the exact old node for rollback; a normal real runtime directory stays in
  # place and install_runtime separately retains its old venv when upgrading.
  if [[ -L "$prefix/runtime" || ( -e "$prefix/runtime" && ! -d "$prefix/runtime" ) ]]; then
    mv "$prefix/runtime" "$publication_backup/runtime-root"
    publication_runtime_root_moved=1
  fi
  mkdir -p "$prefix"
}

seed_generated_outputs_from_backup() {
  (( dry_run || ! publication_active )) && return 0
  local relative old parent target
  for relative in "${package_generated_files[@]}"; do
    old="$publication_backup/$relative"
    parent="${old:h}"
    target="$prefix/$relative"
    [[ -f "$old" && ! -L "$old" && -d "$parent" && ! -L "$parent" ]] || continue
    # config itself is also an ancestor and may have been a hostile symlink.
    [[ -d "$publication_backup/config" && ! -L "$publication_backup/config" ]] || continue
    mkdir -p "${target:h}"
    cp -p "$old" "$target"
  done
}

rollback_public_shim() {
  local target="$bin_dir/claude-litellm"
  local backup="${public_shim_backup:-$publication_backup/public-shim}"
  (( public_shim_active )) || [[ -e "$backup" || -L "$backup" ]] || return 0
  setopt localoptions localtraps noerrexit
  # Consuming a backup rename is not idempotent until the journal flags are
  # updated. Do not let termination re-enter this critical recovery section.
  trap '' HUP INT QUIT TERM
  local failed=0

  if [[ -e "$target" || -L "$target" ]]; then
    rm -f "$target" || failed=1
  fi
  if (( public_shim_target_existed )) || [[ -e "$backup" || -L "$backup" ]]; then
    if (( failed )); then
      :
    elif [[ -e "$backup" || -L "$backup" ]]; then
      mv "$backup" "$target" || failed=1
    else
      failed=1
    fi
  fi
  (( failed == 0 )) || \
    echo "Warning: could not restore the previous public command at $target" >&2
  public_shim_active=0
  public_shim_target_existed=0
  if (( failed == 0 )); then
    [[ -n "$backup" ]] && rmdir "${backup:h}" 2>/dev/null || true
    public_shim_backup=""
  fi
  return "$failed"
}

rollback_package_publication() {
  (( publication_active )) || return 0
  setopt localoptions localtraps noerrexit
  # Rollback consumes retained nodes one by one. A nested EXIT cleanup between
  # a restore rename and its flag update could otherwise delete the just-
  # restored package. Signals are ignored only for this local critical section.
  trap '' HUP INT QUIT TERM
  local restore_failed=0
  echo "Installer publication failed; restoring the previous claude-litellm package." >&2

  # The public command is outside the package prefix, but publishing it before
  # commit keeps command and package bytes on one transaction boundary.
  rollback_public_shim || restore_failed=1

  # Stop a partially started new proxy before replacing its code/runtime.
  stop_owned_proxy "$prefix" 0 >/dev/null 2>&1 || true

  if (( publication_runtime_root_moved )) || \
     [[ -e "$publication_backup/runtime-root" || -L "$publication_backup/runtime-root" ]]; then
    rm -rf "$prefix/runtime" || restore_failed=1
    if [[ ! -e "$prefix/runtime" && ! -L "$prefix/runtime" && \
          ( -e "$publication_backup/runtime-root" || -L "$publication_backup/runtime-root" ) ]]; then
      mv "$publication_backup/runtime-root" "$prefix/runtime" || restore_failed=1
    else
      restore_failed=1
    fi
  elif (( publication_runtime_published || publication_runtime_venv_moved )) || \
       [[ -e "$publication_backup/runtime-venv" || -L "$publication_backup/runtime-venv" ]]; then
    rm -rf "$prefix/runtime/venv" || restore_failed=1
    if [[ -e "$publication_backup/runtime-venv" || -L "$publication_backup/runtime-venv" ]]; then
      mkdir -p "$prefix/runtime" || restore_failed=1
      if [[ ! -e "$prefix/runtime/venv" && ! -L "$prefix/runtime/venv" ]]; then
        mv "$publication_backup/runtime-venv" "$prefix/runtime/venv" || restore_failed=1
      else
        restore_failed=1
      fi
    fi
  fi

  local root previous
  for root in bin config docs scripts; do
    previous="$publication_backup/$root"
    [[ -n "${publication_processed_roots[$root]-}" || -e "$previous" || -L "$previous" ]] || continue
    rm -rf "$prefix/$root" || restore_failed=1
    if [[ -n "${publication_moved_roots[$root]-}" || -e "$previous" || -L "$previous" ]]; then
      if [[ ! -e "$prefix/$root" && ! -L "$prefix/$root" && \
            ( -e "$previous" || -L "$previous" ) ]]; then
        mv "$previous" "$prefix/$root" || restore_failed=1
      else
        restore_failed=1
      fi
    fi
  done
  if (( publication_manifest_processed )) || \
     [[ -e "$publication_backup/install-manifest.json" || -L "$publication_backup/install-manifest.json" ]]; then
    rm -f "$prefix/install-manifest.json" || restore_failed=1
    if (( publication_manifest_existed )) || \
       [[ -e "$publication_backup/install-manifest.json" || -L "$publication_backup/install-manifest.json" ]]; then
      if [[ ! -e "$prefix/install-manifest.json" && ! -L "$prefix/install-manifest.json" && \
            -f "$publication_backup/install-manifest.json" && ! -L "$publication_backup/install-manifest.json" ]]; then
        mv "$publication_backup/install-manifest.json" "$prefix/install-manifest.json" || restore_failed=1
      else
        restore_failed=1
      fi
    fi
  fi

  if (( ! publication_prefix_existed )); then
    # Remove only transaction-owned rebuildable nodes. Durable state may have
    # appeared concurrently and must never be swept by a stale "fresh" flag.
    rmdir "$prefix/runtime" "$prefix" 2>/dev/null || true
  fi
  publication_active=0
  if (( restore_failed )); then
    echo "Package recovery was incomplete; recovery material was retained at $publication_backup" >&2
  else
    if [[ -n "$(find "$publication_backup" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
      restore_failed=1
      echo "Package recovery left retained nodes; recovery material was kept at $publication_backup" >&2
    elif ! rmdir "$publication_backup" 2>/dev/null; then
      restore_failed=1
      echo "Package bytes were restored, but transaction backup cleanup failed: $publication_backup" >&2
    fi
  fi
  if (( restore_failed == 0 )); then
    publication_backup=""
  fi
  return "$restore_failed"
}

commit_package_publication() {
  (( dry_run || ! publication_active )) && return 0

  # This is the logical commit point. Clear the rollback state before any
  # best-effort backup deletion: a signal after deleting one backup must never
  # combine the old package with the newly pinned public shim (or vice versa).
  local committed_public_shim_backup="$public_shim_backup"
  local committed_publication_backup="$publication_backup"
  publication_active=0
  public_shim_active=0
  public_shim_target_existed=0
  public_shim_backup=""
  publication_backup=""

  if [[ -n "$committed_public_shim_backup" && \
        ( -e "$committed_public_shim_backup" || -L "$committed_public_shim_backup" ) ]]; then
    rm -f "$committed_public_shim_backup" || \
      echo "Warning: installed successfully but could not remove old public-command backup: $committed_public_shim_backup" >&2
  fi
  [[ -n "$committed_public_shim_backup" ]] && \
    rmdir "${committed_public_shim_backup:h}" 2>/dev/null || true
  if [[ -n "$committed_publication_backup" ]]; then
    rm -rf "$committed_publication_backup" 2>/dev/null || \
      echo "Warning: installed successfully but could not remove transaction backup: $committed_publication_backup" >&2
  fi
  return 0
}

restore_proxy_liveness() {
  (( proxy_restart_pending )) || return 0
  if (( dry_run )); then
    proxy_restart_pending=0
    return 0
  fi
  [[ -x "$prefix/bin/claude-litellm" && ! -L "$prefix/bin/claude-litellm" ]] || {
    echo "Cannot restart the previously running proxy: package launcher is missing or unsafe." >&2
    return 1
  }
  log "Restarting the proxy that was running before installation."
  if CLAUDE_LITELLM_ROOT="$prefix" AI_LITELLM_HOME="$prefix" \
      "$prefix/bin/claude-litellm" proxy start >/dev/null; then
    proxy_restart_pending=0
    return 0
  fi
  echo "The installed package is complete, but its previously running proxy did not become healthy." >&2
  return 1
}

install_test_failpoint() {
  local point="$1"
  [[ "${CLAUDE_LITELLM_INSTALL_TEST_FAILPOINT:-}" != "$point" ]] || {
    echo "Injected installer publication failure at $point." >&2
    return 97
  }
}

preflight() {
  local -a required missing
  required=(zsh node ruby jq curl perl rg python3.13)
  missing=()
  local cmd
  for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} )); then
    echo "Missing claude-litellm install dependencies: ${missing[*]}" >&2
    echo "Typical macOS packages: brew install python@3.13 node jq ripgrep rust" >&2
    if (( ! dry_run )); then
      exit 1
    fi
  fi
  command -v python3.13 >/dev/null 2>&1 && \
    python_isolated python3.13 -c \
      'import venv; assert (3, 13) <= __import__("sys").version_info < (3, 14)' >/dev/null
  return 0
}

backup_if_exists() {
  local target="$1"
  [[ -e "$target" || -L "$target" ]] || return 0
  local backup="${target}.bak.$(date +%Y%m%d-%H%M%S).$$"
  run mv "$target" "$backup"
}

install_rendered() {
  local source="$1"
  local target="$2"
  run mkdir -p "${target:h}"
  if (( dry_run )); then
    log "dry-run render $source -> $target (__HOME__=$HOME, __AI_LITELLM_HOME__=$prefix)"
    return 0
  fi
  local staged="${target}.tmp.$$"
  HOME_REPL="$HOME" FABRIC_HOME_REPL="$prefix" perl -pe \
    's#__HOME__#$ENV{HOME_REPL}#g; s#__AI_LITELLM_HOME__#$ENV{FABRIC_HOME_REPL}#g' \
    "$source" > "$staged"
  if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$staged" "$target"; then
    rm -f "$staged"
    return 0
  fi
  backup_if_exists "$target"
  mv "$staged" "$target"
}

file_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

render_for_preflight() {
  local source="$1"
  local target="$2"
  mkdir -p "${target:h}"
  HOME_REPL="$HOME" FABRIC_HOME_REPL="$prefix" perl -pe \
    's#__HOME__#$ENV{HOME_REPL}#g; s#__AI_LITELLM_HOME__#$ENV{FABRIC_HOME_REPL}#g' \
    "$source" > "$target"
}

manifest_managed_hash() {
  local relative_path="$1"
  local manifest="$prefix/install-manifest.json"
  [[ -e "$manifest" || -L "$manifest" ]] || return 4
  [[ -f "$manifest" && ! -L "$manifest" ]] || {
    echo "Refusing reinstall: install manifest is not a regular file: $manifest" >&2
    return 3
  }
  node -e '
const fs = require("fs");
const [manifest, relative] = process.argv.slice(1);
let payload;
try { payload = JSON.parse(fs.readFileSync(manifest, "utf8")); }
catch (_) { process.exit(3); }
let entry = payload?.managedMutableFiles?.[relative];
if (entry && typeof entry === "object") entry = entry.sha256;
if (typeof entry !== "string" || !/^[a-f0-9]{64}$/i.test(entry)) process.exit(4);
process.stdout.write(entry.toLowerCase());
' "$manifest" "$relative_path"
}

manifest_uses_generated_overlay_layout() {
  local manifest="$prefix/install-manifest.json"
  [[ -e "$manifest" || -L "$manifest" ]] || return 1
  [[ -f "$manifest" && ! -L "$manifest" ]] || {
    echo "Refusing reinstall: install manifest is not a regular file: $manifest" >&2
    return 2
  }
  node -e '
const fs = require("fs");
const [manifest, expectedPrefix] = process.argv.slice(1);
try {
  const payload = JSON.parse(fs.readFileSync(manifest, "utf8"));
  const managed = payload?.managedMutableFiles;
  const plainObject = managed && typeof managed === "object" && !Array.isArray(managed);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) process.exit(2);
  if (payload.product !== "claude-litellm" || payload.prefix !== expectedPrefix) process.exit(2);
  if (payload.schemaVersion === 2) {
    const userConfig = payload.userConfig;
    const validUserConfig = userConfig && typeof userConfig === "object" && !Array.isArray(userConfig)
      && userConfig.upgradePolicy === "preserve-and-render-over-package-defaults";
    process.exit(plainObject && Object.keys(managed).length === 0 && validUserConfig ? 0 : 2);
  }
  if (payload.schemaVersion !== 1 || !plainObject) process.exit(2);
  const validHash = (value) => typeof value === "string" && /^[a-f0-9]{64}$/i.test(value);
  const requiredLegacy = ["config/litellm_config.yaml", "config/claude-litellm/settings.json"];
  if (Object.keys(managed).length !== requiredLegacy.length
      || !requiredLegacy.every((relative) => Object.prototype.hasOwnProperty.call(managed, relative))) process.exit(2);
  for (const [relative, raw] of Object.entries(managed)) {
    if (!relative || (!validHash(raw) && !validHash(raw?.sha256))) process.exit(2);
  }
  process.exit(1);
} catch (_) { process.exit(2); }
' "$manifest" "$prefix"
}

preflight_managed_mutable_file() {
  local source="$1"
  local target="$2"
  local relative_path="$3"
  # New installations keep user choices in ~/.config/claude-litellm and mark
  # these package paths as generated effective files. Only an older manifest
  # that explicitly tracked a mutable path invokes the one-time legacy drift
  # guard during migration to the overlay layout.
  local manifest_policy_rc=0
  if manifest_uses_generated_overlay_layout; then
    return 0
  else
    manifest_policy_rc=$?
    if (( manifest_policy_rc != 1 )); then
      echo "Refusing reinstall: install manifest is malformed or incompatible: $prefix/install-manifest.json" >&2
      return 1
    fi
  fi
  [[ -e "$target" || -L "$target" ]] || return 0
  [[ -f "$target" && ! -L "$target" ]] || {
    echo "Refusing reinstall: managed mutable path is not a regular file: $target" >&2
    return 1
  }

  local candidate="$preflight_stage/$relative_path"
  render_for_preflight "$source" "$candidate"
  local current_hash candidate_hash baseline_hash rc
  current_hash="$(file_sha256 "$target")"
  candidate_hash="$(file_sha256 "$candidate")"

  # A file already equal to the incoming source is safe even for a pre-manifest
  # installation. Otherwise only the exact hash recorded at the prior install is
  # considered unmodified and upgradeable.
  [[ "$current_hash" == "$candidate_hash" ]] && return 0
  if baseline_hash="$(manifest_managed_hash "$relative_path")"; then
    [[ "$current_hash" == "$baseline_hash" ]] && return 0
  else
    rc=$?
    if (( rc != 4 )); then
      echo "Refusing reinstall: cannot validate managed baseline in $prefix/install-manifest.json" >&2
      return 1
    fi
  fi

  echo "Refusing reinstall: durable user configuration differs from its managed baseline:" >&2
  echo "  $target" >&2
  echo "No destination file, proxy, or runtime was changed." >&2
  echo "Merge this configuration into the source checkout (or manually restore the installed baseline), then rerun install." >&2
  return 1
}

preflight_managed_mutable_files() {
  [[ -d "$prefix" ]] || return 0
  preflight_stage="$(mktemp -d "${TMPDIR:-/tmp}/claude-litellm-install-preflight.XXXXXX")"
  chmod 700 "$preflight_stage"
  preflight_managed_mutable_file \
    "$repo_root/config/litellm_config.yaml" \
    "$prefix/config/litellm_config.yaml" \
    "config/litellm_config.yaml" || {
      local rc=$?
      rm -rf "$preflight_stage"
      preflight_stage=""
      return "$rc"
    }
  preflight_managed_mutable_file \
    "$repo_root/config/claude-litellm/settings.json" \
    "$prefix/config/claude-litellm/settings.json" \
    "config/claude-litellm/settings.json" || {
      local rc=$?
      rm -rf "$preflight_stage"
      preflight_stage=""
      return "$rc"
    }
  rm -rf "$preflight_stage"
  preflight_stage=""
}

install_executable() {
  local source="$1"
  local target="$2"
  run mkdir -p "${target:h}"
  if (( ! dry_run )) && [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; then
    chmod 755 "$target"
    return 0
  fi
  backup_if_exists "$target"
  run cp "$source" "$target"
  run chmod 755 "$target"
}

# Keep package publication closed over an explicit set.  In particular, a
# removed callback/script from an older release, an untracked __pycache__, or a
# symlink planted at a managed path must not survive a reinstall and then become
# trusted merely because write_manifest happened to discover it on disk.
initialize_package_layout() {
  local document relative
  package_managed_files=(
    bin/claude-litellm
    config/litellm_config.base.yaml
    config/python-requirements.in
    config/python-requirements.lock
    config/ai_litellm_callbacks/__init__.py
    config/ai_litellm_callbacks/chatgpt_stream_compat.py
    config/ai_litellm_callbacks/oauth_guard.py
    config/ai_litellm_callbacks/proxy_bootstrap.py
    config/ai_litellm_callbacks/output_clamp.py
    config/ai-litellm/context-observations.json
    config/ai-litellm/lib.zsh
    config/ai-litellm/settings.json
    config/ai-litellm/harnesses/schema.json
    config/ai-litellm/harnesses/claude.json
    config/claude-litellm/settings.base.json
    config/claude-litellm/oauth.py
    config/claude-litellm/shell.zsh
    scripts/migrate-legacy.zsh
    scripts/render-user-config.py
    scripts/runtime-fingerprint.py
    scripts/verify-install.py
    scripts/verify_tool_call_fidelity.py
    scripts/uninstall.zsh
  )
  for document in "$repo_root"/docs/*(.N); do
    [[ -f "$document" && ! -L "$document" ]] || continue
    package_managed_files+=("docs/${document:t}")
  done

  # These two files are generated from immutable defaults plus private user
  # overlays. They belong in the exact on-disk layout, but their changing bytes
  # are intentionally not recorded as immutable package provenance.
  package_generated_files=(
    config/litellm_config.yaml
    config/claude-litellm/settings.json
  )
  package_executable_files=(
    bin/claude-litellm
    scripts/migrate-legacy.zsh
    scripts/render-user-config.py
    scripts/runtime-fingerprint.py
    scripts/verify-install.py
    scripts/verify_tool_call_fidelity.py
    scripts/uninstall.zsh
  )
  package_allowed_files=("${package_managed_files[@]}" "${package_generated_files[@]}")
  package_allowed_dirs=(
    bin
    config
    config/ai_litellm_callbacks
    config/ai-litellm
    config/ai-litellm/harnesses
    config/claude-litellm
    docs
    scripts
  )

  package_allowed_file_set=()
  for relative in "${package_allowed_files[@]}"; do
    if [[ -n "${package_allowed_file_set[$relative]-}" ]]; then
      echo "Duplicate managed package path: $relative" >&2
      return 1
    fi
    package_allowed_file_set[$relative]=1
  done
  package_allowed_dir_set=()
  for relative in "${package_allowed_dirs[@]}"; do
    if [[ -n "${package_allowed_file_set[$relative]-}" || \
          -n "${package_allowed_dir_set[$relative]-}" ]]; then
      echo "Conflicting managed package path: $relative" >&2
      return 1
    fi
    package_allowed_dir_set[$relative]=1
  done
}

prune_package_layout() {
  local root root_path entry relative
  for root in bin config docs scripts; do
    root_path="$prefix/$root"
    if [[ -L "$root_path" || ( -e "$root_path" && ! -d "$root_path" ) ]]; then
      run rm -rf "$root_path"
    fi
    [[ -d "$root_path" && ! -L "$root_path" ]] || continue
    while IFS= read -r -d $'\0' entry; do
      relative="${entry#$prefix/}"
      if [[ -n "${package_allowed_file_set[$relative]-}" ]]; then
        if [[ -L "$entry" || ! -f "$entry" ]]; then
          run rm -rf "$entry"
        fi
      elif [[ -n "${package_allowed_dir_set[$relative]-}" ]]; then
        if [[ -L "$entry" || ! -d "$entry" ]]; then
          run rm -rf "$entry"
        fi
      else
        run rm -rf "$entry"
      fi
    done < <(find "$root_path" -depth -mindepth 1 -print0)
  done
  for relative in "${package_allowed_dirs[@]}"; do
    run mkdir -p "$prefix/$relative"
  done
}

validate_package_layout() {
  local relative candidate root entry
  for relative in "${package_allowed_dirs[@]}"; do
    candidate="$prefix/$relative"
    [[ -d "$candidate" && ! -L "$candidate" ]] || {
      echo "Managed package directory is missing or unsafe: $candidate" >&2
      return 1
    }
  done
  for relative in "${package_allowed_files[@]}"; do
    candidate="$prefix/$relative"
    [[ -f "$candidate" && ! -L "$candidate" ]] || {
      echo "Managed package file is missing or unsafe: $candidate" >&2
      return 1
    }
  done
  for relative in "${package_executable_files[@]}"; do
    [[ -x "$prefix/$relative" ]] || {
      echo "Managed package executable is not executable: $prefix/$relative" >&2
      return 1
    }
  done
  for root in bin config docs scripts; do
    while IFS= read -r -d $'\0' entry; do
      relative="${entry#$prefix/}"
      if [[ -n "${package_allowed_file_set[$relative]-}" ]]; then
        [[ -f "$entry" && ! -L "$entry" ]] || {
          echo "Managed package file has an unsafe type: $entry" >&2
          return 1
        }
      elif [[ -n "${package_allowed_dir_set[$relative]-}" ]]; then
        [[ -d "$entry" && ! -L "$entry" ]] || {
          echo "Managed package directory has an unsafe type: $entry" >&2
          return 1
        }
      else
        echo "Unexpected file remains in managed package layout: $entry" >&2
        return 1
      fi
    done < <(find "$prefix/$root" -depth -mindepth 1 -print0)
  done
}

runtime_python_matches_pins() {
  local python="$1"
  [[ -x "$python" ]] || return 1
  python_isolated "$python" - "$LITELLM_VERSION" "$PRISMA_VERSION" <<'PY'
import importlib.metadata as metadata
import sys
expected_litellm, expected_prisma = sys.argv[1:]
assert sys.version_info[:2] == (3, 13)
assert metadata.version("litellm") == expected_litellm
assert metadata.version("prisma") == expected_prisma
import fastapi, litellm, prisma, uvicorn  # noqa: F401
import litellm.proxy.proxy_cli  # noqa: F401
PY
}

runtime_manifest_matches_build() {
  local python="$1" manifest="$prefix/install-manifest.json"
  local content_fingerprint
  [[ -f "$manifest" && ! -L "$manifest" ]] || return 1
  # Measure the managed runtime with the external bootstrap interpreter. The
  # managed Python is not executable trust until this byte comparison passes.
  content_fingerprint="$(python_isolated python3.13 -S "$repo_root/scripts/runtime-fingerprint.py" \
    --runtime-root "$prefix/runtime/venv")" || return 1
  python_isolated python3.13 -S - "$manifest" "$RUNTIME_BUILD_EPOCH" "$content_fingerprint" <<'PY'
import json
import re
import sys

manifest_path, expected_epoch, content_fingerprint = sys.argv[1:]
try:
    runtime = json.load(open(manifest_path, encoding="utf-8"))["runtime"]
except (OSError, ValueError, KeyError, TypeError):
    raise SystemExit(1)
raise SystemExit(
    0
    if runtime.get("buildEpoch") == expected_epoch
    and re.fullmatch(r"[0-9a-f]{64}", content_fingerprint)
    and runtime.get("contentFingerprint") == content_fingerprint
    else 1
)
PY
  # Only the matched runtime may now initialize site-packages.
  python_isolated "$python" - "$manifest" <<'PY'
import hashlib
import importlib.metadata as metadata
import json
import sys

manifest_path = sys.argv[1]
try:
    runtime = json.load(open(manifest_path, encoding="utf-8"))["runtime"]
except (OSError, ValueError, KeyError, TypeError):
    raise SystemExit(1)
packages = sorted(
    f"{dist.metadata['Name'].lower().replace('_', '-')}=={dist.version}"
    for dist in metadata.distributions()
    if dist.metadata.get("Name")
)
fingerprint = hashlib.sha256("\n".join(packages).encode()).hexdigest()
raise SystemExit(
    0
    if runtime.get("dependencyFingerprint") == fingerprint
    else 1
)
PY
}

litellm_console_script_targets_runtime() {
  local runtime_root="$1"
  local script="$runtime_root/bin/litellm"
  local first_line="" second_line="" third_line=""
  [[ -f "$script" && -x "$script" && ! -L "$script" ]] || return 1
  {
    IFS= read -r first_line || true
    IFS= read -r second_line || true
    IFS= read -r third_line || true
  } < "$script"

  # pip uses a direct shebang when the interpreter path is simple. For paths
  # containing spaces (or an overlong shebang), it emits this exact three-line
  # /bin/sh trampoline before the Python console-script body.
  if [[ "$first_line" == "#!$runtime_root/bin/python" ||
        "$first_line" == "#!$runtime_root/bin/python3.13" ]]; then
    return 0
  fi
  [[ "$first_line" == '#!/bin/sh' && "$third_line" == "' '''" ]] || return 1
  [[ "$second_line" == "'''exec' \"$runtime_root/bin/python\" \"\$0\" \"\$@\"" ||
     "$second_line" == "'''exec' \"$runtime_root/bin/python3.13\" \"\$0\" \"\$@\"" ]]
}

runtime_is_current() {
  local runtime_root="$prefix/runtime/venv"
  local python="$runtime_root/bin/python"
  [[ -d "$prefix/runtime" && ! -L "$prefix/runtime" && \
     -d "$runtime_root" && ! -L "$runtime_root" ]] || return 1
  # Start reuse validation with the trusted checkout fingerprint helper under
  # -I -S. No venv console script, .pth file, or third-party import may execute
  # until the recorded runtime bytes have matched.
  runtime_manifest_matches_build "$python" >/dev/null 2>&1 || return 1
  litellm_console_script_targets_runtime "$runtime_root" || return 1
  env -u PYTHONPATH -u PYTHONHOME PYTHONDONTWRITEBYTECODE=1 \
    "$runtime_root/bin/litellm" --version >/dev/null 2>&1 || return 1
  runtime_python_matches_pins "$python" >/dev/null 2>&1 || return 1
}

rust_toolchain_usable() {
  local selector="${1:-}" minimum="${2:-1.86.0}" rustc_version cargo_path rustc_path
  if [[ -n "$selector" ]]; then
    cargo_path="$(rustup which --toolchain "$selector" cargo 2>/dev/null)" || return 1
    rustc_path="$(rustup which --toolchain "$selector" rustc 2>/dev/null)" || return 1
    [[ -x "$cargo_path" && -x "$rustc_path" ]] || return 1
    "$cargo_path" --version >/dev/null 2>&1 || return 1
    rustc_version="$("$rustc_path" --version 2>/dev/null | awk '{print $2}')" || return 1
  else
    cargo --version >/dev/null 2>&1 || return 1
    rustc_version="$(rustc --version 2>/dev/null | awk '{print $2}')" || return 1
  fi
  python_isolated python3.13 - "$rustc_version" "$minimum" <<'PY'
import re
import sys
def version(value):
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)", value)
    return tuple(map(int, match.groups())) if match else None
actual, minimum = version(sys.argv[1]), version(sys.argv[2])
sys.exit(0 if actual and minimum and actual >= minimum else 1)
PY
}

prepare_runtime_build_toolchain() {
  # LiteLLM 1.92.0 publishes Linux wheels but no macOS wheel. A fresh macOS
  # runtime therefore builds its maturin extension from the sdist. Do this
  # preflight before stopping a proxy or mutating package files so a missing
  # compiler cannot leave a partial upgrade.
  runtime_is_current && return 0
  [[ "$(uname -s)" == Darwin ]] || return 0

  if command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1 && \
     rust_toolchain_usable "" "$RUST_TOOLCHAIN_VERSION"; then
    runtime_build_rust="$(rustc --version 2>/dev/null | awk '{print $2}')"
    return 0
  fi

  # GitHub macOS runners and many developer machines already have rustup but no
  # selected toolchain. Reuse or install the pinned minimal profile without
  # changing the user's global default; RUSTUP_TOOLCHAIN is inherited only by
  # this installer and its pip build subprocess.
  if command -v rustup >/dev/null 2>&1; then
    local pinned_cargo
    if ! rust_toolchain_usable "$RUST_TOOLCHAIN_VERSION" "$RUST_TOOLCHAIN_VERSION"; then
      log "Preparing minimal Rust $RUST_TOOLCHAIN_VERSION toolchain for the LiteLLM macOS build."
      rustup toolchain install "$RUST_TOOLCHAIN_VERSION" --profile minimal --no-self-update
    fi
    pinned_cargo="$(rustup which --toolchain "$RUST_TOOLCHAIN_VERSION" cargo)"
    export PATH="${pinned_cargo:h}:$PATH"
    export RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN_VERSION"
    rust_toolchain_usable "" "$RUST_TOOLCHAIN_VERSION" || {
      echo "Rust $RUST_TOOLCHAIN_VERSION was installed, but a usable cargo/rustc is still unavailable." >&2
      return 1
    }
    runtime_build_rust="$(rustc --version 2>/dev/null | awk '{print $2}')"
    return 0
  fi

  echo "LiteLLM $LITELLM_VERSION has no macOS wheel and requires Rust/Cargo for its source build." >&2
  echo "Install it first (for example: brew install rust), then rerun the installer." >&2
  return 1
}

stage_runtime() {
  if (( dry_run )); then
    log "dry-run stage isolated Python 3.13 runtime: litellm[proxy]==$LITELLM_VERSION prisma==$PRISMA_VERSION"
    return 0
  fi
  if runtime_is_current; then
    log "Runtime already validated: LiteLLM $LITELLM_VERSION / prisma $PRISMA_VERSION"
    return 0
  fi

  # Keep the expensive/networked build outside the destination package. It is
  # on the same filesystem as the final prefix so publication can still use an
  # atomic rename after the running proxy has been stopped.
  mkdir -p "${prefix:h}"
  runtime_stage="$(mktemp -d "${prefix:h}/.claude-litellm-venv-stage.XXXXXX")"
  chmod 700 "$runtime_stage"
  # Python resolves macOS' /var and /tmp compatibility symlinks when it writes
  # console-script shebangs. Track the just-created staging directory by its
  # canonical path so relocation finds those bytes even when the requested
  # package prefix deliberately remains lexical for symlink safety checks.
  runtime_stage="${runtime_stage:A}"
  python_isolated python3.13 -m venv "$runtime_stage"
  PIP_DISABLE_PIP_VERSION_CHECK=1 python_isolated \
    "$runtime_stage/bin/python" -m pip install \
    --require-hashes \
    -r "$repo_root/config/python-requirements.lock"

  python_isolated "$runtime_stage/bin/python" - "$LITELLM_VERSION" "$PRISMA_VERSION" <<'PY'
import importlib.metadata as metadata
import sys
expected_litellm, expected_prisma = sys.argv[1:]
assert sys.version_info[:2] == (3, 13), sys.version
assert metadata.version("litellm") == expected_litellm
assert metadata.version("prisma") == expected_prisma
import litellm, prisma  # noqa: F401
PY

  log "Staged isolated LiteLLM runtime $LITELLM_VERSION."
}

install_runtime() {
  (( dry_run )) && return 0
  if [[ -z "$runtime_stage" ]]; then
    runtime_is_current || {
      echo "No validated staged runtime is available for publication." >&2
      return 1
    }
    return 0
  fi

  # A runtime is rebuildable package state, unlike OAuth/transcript state. A
  # hostile symlink/non-directory here is replaced only after the new runtime
  # has already been staged and validated.
  if [[ -L "$prefix/runtime" || ( -e "$prefix/runtime" && ! -d "$prefix/runtime" ) ]]; then
    rm -rf "$prefix/runtime"
  fi
  mkdir -p "$prefix/runtime"
  [[ -d "$prefix/runtime" && ! -L "$prefix/runtime" ]] || {
    echo "Refusing unsafe runtime directory: $prefix/runtime" >&2
    return 1
  }
  chmod 700 "$prefix/runtime"
  local current="$prefix/runtime/venv"
  local previous="$prefix/runtime/.venv-previous.$$"
  (( publication_active )) && previous="$publication_backup/runtime-venv"
  local staged_root="$runtime_stage"
  if [[ -e "$current" || -L "$current" ]]; then
    mv "$current" "$previous" || return 1
    (( publication_active )) && publication_runtime_venv_moved=1
  fi
  # Mark the destination as transaction-owned before the rename. A signal in
  # the tiny interval after a successful mv must still make rollback remove
  # the new venv, including on a fresh install with no retained predecessor.
  (( publication_active )) && publication_runtime_published=1
  if ! mv "$runtime_stage" "$current"; then
    # During a package publication the retained venv is transaction backup.
    # Do not restore it locally: a TERM/INT between that rename and clearing
    # the flags would let the outer rollback delete the restored old runtime.
    # The single transaction rollback path owns all recovery while active.
    if (( ! publication_active )) && [[ -e "$previous" || -L "$previous" ]]; then
      if [[ ! -e "$current" && ! -L "$current" ]] && mv "$previous" "$current"; then
        :
      fi
    fi
    return 1
  fi
  runtime_stage=""

  # Python venv console scripts contain absolute interpreter paths. pip may put
  # that path in a direct shebang or in the second line of a /bin/sh trampoline
  # when the venv path contains spaces. Repair only textual shebang scripts;
  # binary files in bin/ are deliberately never rewritten.
  local executable first_line relocation_failed=0
  for executable in "$current"/bin/*(.N); do
    IFS= read -r first_line < "$executable" || true
    [[ "$first_line" == '#!'* ]] || continue
    grep -Fq -- "$staged_root" "$executable" || continue
    OLD_VENV_ROOT="$staged_root" NEW_VENV_ROOT="$current" perl -pi -e \
      's/\Q$ENV{OLD_VENV_ROOT}\E/$ENV{NEW_VENV_ROOT}/g' "$executable"
  done

  # A successfully relocated script cannot retain any staging path, including
  # paths hidden below a generic #!/bin/sh first line.
  for executable in "$current"/bin/*(.N); do
    IFS= read -r first_line < "$executable" || true
    [[ "$first_line" == '#!'* ]] || continue
    if grep -Fq -- "$staged_root" "$executable"; then
      relocation_failed=1
      break
    fi
  done

  if (( relocation_failed )) ||
     ! litellm_console_script_targets_runtime "$current" ||
     ! env -u PYTHONPATH -u PYTHONHOME PYTHONDONTWRITEBYTECODE=1 \
       "$current/bin/litellm" --version >/dev/null 2>&1 ||
     ! runtime_python_matches_pins "$current/bin/python" >/dev/null 2>&1; then
    echo "Failed to relocate the staged LiteLLM console script." >&2
    # As above, leave both the rejected current runtime and the retained old
    # venv to the outer transaction. It can remove/restore them without a
    # stale-positive signal window. Standalone publication keeps its local
    # recovery behavior because there is no outer rollback in that mode.
    if (( ! publication_active )); then
      rm -rf "$current" || true
      if [[ -e "$previous" || -L "$previous" ]]; then
        [[ -e "$current" || -L "$current" ]] || mv "$previous" "$current" || true
      fi
    fi
    return 1
  fi
  if (( ! publication_active )); then
    rm -rf "$previous"
  fi
  log "Installed isolated LiteLLM runtime $LITELLM_VERSION."
}

write_manifest() {
  if (( dry_run )); then
    log "dry-run write provenance manifest: $prefix/install-manifest.json"
    return 0
  fi
  local commit origin dirty installed_at
  commit="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unknown)"
  origin="$(git -C "$repo_root" config --get remote.origin.url 2>/dev/null || printf local)"
  dirty=false
  git -C "$repo_root" diff --quiet --ignore-submodules -- 2>/dev/null || dirty=true
  git -C "$repo_root" diff --cached --quiet --ignore-submodules -- 2>/dev/null || dirty=true
  [[ -z "$(git -C "$repo_root" status --porcelain --untracked-files=normal 2>/dev/null)" ]] || dirty=true
  installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local python="$prefix/runtime/venv/bin/python" runtime_content_fingerprint
  runtime_content_fingerprint="$(python_isolated python3.13 -S "$prefix/scripts/runtime-fingerprint.py" \
    --runtime-root "$prefix/runtime/venv")" || return 1
  CLAUDE_LITELLM_PREFIX="$prefix" SOURCE_COMMIT="$commit" SOURCE_ORIGIN="$origin" \
    SOURCE_DIRTY="$dirty" INSTALLED_AT="$installed_at" LITELLM_PIN="$LITELLM_VERSION" \
    PRISMA_PIN="$PRISMA_VERSION" BUILD_RUST_VERSION="$runtime_build_rust" \
    MANIFEST_RUNTIME_BUILD_EPOCH="$RUNTIME_BUILD_EPOCH" USER_CONFIG_ROOT="$user_config_root" \
    RUNTIME_CONTENT_FINGERPRINT="$runtime_content_fingerprint" \
    python_isolated "$python" - "${package_managed_files[@]}" <<'PY'
import hashlib
import importlib.metadata as metadata
import json
import os
import platform
import stat
import sys
import tempfile
from pathlib import Path

prefix = Path(os.environ["CLAUDE_LITELLM_PREFIX"])
managed_paths = sys.argv[1:]
if not managed_paths or len(managed_paths) != len(set(managed_paths)):
    raise SystemExit("managed package file list is empty or contains duplicates")
managed_mutable_files = {}
runtime = {
    "python": platform.python_version(),
    "litellm": os.environ["LITELLM_PIN"],
    "prisma": os.environ["PRISMA_PIN"],
    "venv": str(prefix / "runtime" / "venv"),
    "buildEpoch": os.environ["MANIFEST_RUNTIME_BUILD_EPOCH"],
    "contentFingerprint": os.environ["RUNTIME_CONTENT_FINGERPRINT"],
}
packages = sorted(
    f"{dist.metadata['Name'].lower().replace('_', '-')}=={dist.version}"
    for dist in metadata.distributions()
    if dist.metadata.get("Name")
)
runtime["dependencyFingerprint"] = hashlib.sha256("\n".join(packages).encode()).hexdigest()
build_rust = os.environ.get("BUILD_RUST_VERSION", "")
if not build_rust:
    try:
        build_rust = json.loads((prefix / "install-manifest.json").read_text()).get("runtime", {}).get("buildRust", "")
    except (OSError, ValueError, TypeError):
        pass
if build_rust:
    runtime["buildRust"] = build_rust

package_files = {}
for relative in sorted(managed_paths):
    relative_path = Path(relative)
    if relative_path.is_absolute() or ".." in relative_path.parts or relative_path.as_posix() != relative:
        raise SystemExit(f"unsafe managed package path: {relative}")
    path = prefix / relative_path
    try:
        info = path.lstat()
    except OSError as error:
        raise SystemExit(f"missing managed package file: {relative}: {error}") from error
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise SystemExit(f"managed package path is not a regular file: {relative}")
    package_files[relative] = hashlib.sha256(path.read_bytes()).hexdigest()

payload = {
    "product": "claude-litellm",
    "schemaVersion": 2,
    "installedAt": os.environ["INSTALLED_AT"],
    "prefix": str(prefix),
    "source": {
        "origin": os.environ["SOURCE_ORIGIN"],
        "commit": os.environ["SOURCE_COMMIT"],
        "dirty": os.environ["SOURCE_DIRTY"] == "true",
    },
    "runtime": runtime,
    "packageFiles": package_files,
    "managedMutableFiles": managed_mutable_files,
    "userConfig": {
        "models": str(Path(os.environ["USER_CONFIG_ROOT"]) / "models.json"),
        "claudeSettings": str(Path(os.environ["USER_CONFIG_ROOT"]) / "settings.json"),
        "upgradePolicy": "preserve-and-render-over-package-defaults",
    },
}
target = prefix / "install-manifest.json"
fd, staged_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
staged = Path(staged_name)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    staged.replace(target)
finally:
    staged.unlink(missing_ok=True)
PY
  chmod 600 "$prefix/install-manifest.json"
}

env_file_has_value() {
  local file_path="$1" key="$2"
  [[ -f "$file_path" ]] || return 1
  node -e '
const fs = require("fs");
const [file, wanted] = process.argv.slice(1);
for (let line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
  line = line.trim().replace(/^export\s+/, "");
  const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
  if (match && match[1] === wanted && match[2].length > 0) process.exit(0);
}
process.exit(1);
' "$file_path" "$key"
}

ensure_litellm_master_key() {
  local env_file="$prefix/state/ai-litellm/env"
  if (( dry_run )); then
    if [[ -e "$env_file" || -L "$env_file" ]]; then
      [[ -f "$env_file" && ! -L "$env_file" ]] || {
        echo "Refusing unsafe package env path: $env_file" >&2
        return 1
      }
    fi
    log "dry-run ensure private LiteLLM master-key storage under ${env_file:h}"
    return 0
  fi
  mkdir -p "${env_file:h}" || return 1
  chmod 700 "${env_file:h}" || return 1
  if [[ -e "$env_file" || -L "$env_file" ]]; then
    [[ -f "$env_file" && ! -L "$env_file" ]] || {
      echo "Refusing unsafe package env path: $env_file" >&2
      return 1
    }
    chmod 600 "$env_file" || return 1
  fi
  [[ -n "${LITELLM_MASTER_KEY:-}" ]] && return 0
  env_file_has_value "$env_file" LITELLM_MASTER_KEY && return 0
  local service="${LITELLM_MASTER_KEYCHAIN_SERVICE:-litellm-master-key}"
  local account="${LITELLM_MASTER_KEYCHAIN_ACCOUNT:-${USER:-}}"
  if command -v security >/dev/null 2>&1 && \
    security find-generic-password -s "$service" -a "$account" -w >/dev/null 2>&1; then
    return 0
  fi
  if (( dry_run )); then
    log "dry-run generate LITELLM_MASTER_KEY in $env_file when environment/Keychain do not provide one"
    return 0
  fi
  local generated
  generated="$(python_isolated python3.13 -c \
    'import secrets; print(secrets.token_urlsafe(48))')" || return 1
  mkdir -p "${env_file:h}" || return 1
  if ! printf '%s' "$generated" | node -e '
const fs = require("fs");
const crypto = require("crypto");
const [file, key] = process.argv.slice(1);
const value = fs.readFileSync(0, "utf8");
let lines = [];
let sourceFd;
try {
  sourceFd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  const info = fs.fstatSync(sourceFd);
  if (!info.isFile() || (info.mode & 0o777) !== 0o600) {
    throw new Error("existing credential file is not a private regular file");
  }
  lines = fs.readFileSync(sourceFd, "utf8").split(/\r?\n/);
  fs.closeSync(sourceFd);
  sourceFd = undefined;
  if (lines.length && lines[lines.length - 1] === "") lines.pop();
} catch (error) {
  if (sourceFd !== undefined) {
    try { fs.closeSync(sourceFd); } catch (_) {}
  }
  if (error.code !== "ENOENT") throw error;
}
let found = false;
const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const pattern = new RegExp(`^(\\s*(?:export\\s+)?)${escaped}=.*$`);
lines = lines.map((line) => {
  const match = line.match(pattern);
  if (!match) return line;
  found = true;
  return `${match[1] || ""}${key}=${value}`;
});
if (!found) lines.push(`${key}=${value}`);
const staged = `${file}.tmp.${process.pid}.${crypto.randomBytes(16).toString("hex")}`;
let stagedFd;
let directoryFd;
try {
  stagedFd = fs.openSync(
    staged,
    fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW,
    0o600,
  );
  fs.fchmodSync(stagedFd, 0o600);
  fs.writeFileSync(stagedFd, lines.join("\n") + "\n", "utf8");
  fs.fsyncSync(stagedFd);
  fs.closeSync(stagedFd);
  stagedFd = undefined;
  fs.renameSync(staged, file);
  directoryFd = fs.openSync(require("path").dirname(file), fs.constants.O_RDONLY | fs.constants.O_DIRECTORY);
  fs.fsyncSync(directoryFd);
  fs.closeSync(directoryFd);
  directoryFd = undefined;
} catch (error) {
  if (stagedFd !== undefined) try { fs.closeSync(stagedFd); } catch (_) {}
  if (directoryFd !== undefined) try { fs.closeSync(directoryFd); } catch (_) {}
  try { fs.unlinkSync(staged); } catch (_) {}
  throw error;
}
' "$env_file" LITELLM_MASTER_KEY; then
    return 1
  fi
  chmod 600 "$env_file" || return 1
  return 0
}

install_public_shim() {
  local target="$bin_dir/claude-litellm"
  local manifest_digest=""
  if (( dry_run )); then
    run mkdir -p "$bin_dir"
    log "dry-run shim $target -> $prefix/bin/claude-litellm"
    return 0
  fi
  (( publication_active )) || {
    echo "Refusing to publish the public command outside an active install transaction." >&2
    return 1
  }
  mkdir -p "$bin_dir"
  [[ -d "$bin_dir" && ! -L "$bin_dir" ]] || {
    echo "Refusing unsafe public command directory: $bin_dir" >&2
    return 1
  }
  manifest_digest="$(file_sha256 "$prefix/install-manifest.json")" || return 1
  [[ ${#manifest_digest} -eq 64 && "$manifest_digest" != *[^0-9a-f]* ]] || {
    echo "Could not pin the installed manifest in the public launcher." >&2
    return 1
  }
  public_shim_stage="$(mktemp "$bin_dir/.claude-litellm-shim.XXXXXX")"
  {
    print -r -- '#!/usr/bin/env zsh'
    print -r -- "export CLAUDE_LITELLM_ROOT=${(qq)prefix}"
    print -r -- "export AI_LITELLM_HOME=${(qq)prefix}"
    print -r -- "export CLAUDE_LITELLM_MANIFEST_SHA256=${(qq)manifest_digest}"
    print -r -- 'exec "$CLAUDE_LITELLM_ROOT/bin/claude-litellm" "$@"'
  } > "$public_shim_stage"
  chmod 755 "$public_shim_stage"

  if [[ -e "$target" || -L "$target" ]]; then
    local shim_backup_dir
    shim_backup_dir="$(mktemp -d "$bin_dir/.claude-litellm-previous.XXXXXX")" || return 1
    chmod 700 "$shim_backup_dir" || return 1
    public_shim_backup="$shim_backup_dir/claude-litellm"
    mv "$target" "$public_shim_backup"
    public_shim_target_existed=1
  fi
  public_shim_active=1
  [[ ! -e "$target" && ! -L "$target" ]] || {
    echo "Public command changed concurrently during installation: $target" >&2
    return 1
  }
  mv "$public_shim_stage" "$target"
  public_shim_stage=""
}

remove_owned_legacy_shims() {
  local name target failed=0
  for name in ai-litellm codex-litellm opencode-litellm goose-litellm fabric \
    openrouter-key-status litellm-master-key-status; do
    target="$bin_dir/$name"
    [[ -e "$target" || -L "$target" ]] || continue
    if [[ -L "$target" ]]; then
      local link_target="$(readlink "$target" 2>/dev/null || true)"
      [[ "$link_target" == *ai-litellm* ]] || continue
    elif ! grep -Eq 'ai-litellm(-fabric)?|AI_LITELLM_HOME' "$target" 2>/dev/null; then
      echo "Leaving unrelated command in place: $target" >&2
      continue
    fi
    if ! run rm -f "$target"; then
      echo "Could not remove migrated legacy command: $target" >&2
      failed=1
    fi
  done
  return "$failed"
}

postcommit_warning() {
  (( postcommit_warning_count += 1 ))
  echo "Warning: $*" >&2
}

# Package and public-command publication are already committed when this runs.
# Migration and credential setup affect durable/external state and cannot be
# honestly rolled back by restoring package bytes. Isolate each operation,
# report an actionable warning, and keep a complete package install from being
# misreported as a failed/rolled-back install.
finish_postcommit_steps() {
  setopt localoptions localtraps noerrexit
  trap - ZERR

  if (( migrate_legacy )); then
    local -a migration_args
    migration_args=(--destination "$prefix" --remove-source)
    (( dry_run )) && migration_args+=(--dry-run)
    if "$repo_root/scripts/migrate-legacy.zsh" "${migration_args[@]}"; then
      remove_owned_legacy_shims || \
        postcommit_warning "legacy state was migrated, but one or more old command shims could not be removed."
    else
      postcommit_warning "the package was installed, but legacy-state migration did not complete; inspect the migration backup/state and rerun the installer."
    fi
  else
    log "Legacy migration disabled; older packages and shims were left unchanged."
  fi

  ensure_litellm_master_key || \
    postcommit_warning "the package was installed, but LiteLLM master-key setup did not complete; provide LITELLM_MASTER_KEY or repair $prefix/state/ai-litellm/env before starting the proxy."

  if (( ! dry_run )); then
    release_owned_lock "$user_mutation_lock" user_mutation_lock_fd
    user_mutation_lock=""
    release_owned_lock "$install_lock" install_lock_fd
    install_lock=""
  fi
  if ! restore_proxy_liveness; then
    postcommit_warning "the package was installed, but the proxy that was running before the upgrade could not be restarted."
    proxy_restart_pending=0
  fi
  return 0
}

for file in \
  "$repo_root/bin/claude-litellm" \
  "$repo_root/config/litellm_config.yaml" \
  "$repo_root/config/python-requirements.in" \
  "$repo_root/config/python-requirements.lock" \
  "$repo_root/config/ai_litellm_callbacks/__init__.py" \
  "$repo_root/config/ai_litellm_callbacks/oauth_guard.py" \
  "$repo_root/config/ai_litellm_callbacks/proxy_bootstrap.py" \
  "$repo_root/config/ai_litellm_callbacks/output_clamp.py" \
  "$repo_root/config/ai-litellm/context-observations.json" \
  "$repo_root/config/ai-litellm/lib.zsh" \
  "$repo_root/config/ai-litellm/settings.json" \
  "$repo_root/config/ai-litellm/harnesses/schema.json" \
  "$repo_root/config/ai-litellm/harnesses/claude.json" \
  "$repo_root/config/claude-litellm/settings.json" \
  "$repo_root/config/claude-litellm/oauth.py" \
  "$repo_root/config/claude-litellm/shell.zsh" \
  "$repo_root/config/ai_litellm_callbacks/chatgpt_stream_compat.py" \
  "$repo_root/scripts/migrate-legacy.zsh" \
  "$repo_root/scripts/render-user-config.py" \
  "$repo_root/scripts/runtime-fingerprint.py" \
  "$repo_root/scripts/verify-install.py" \
  "$repo_root/scripts/verify_tool_call_fidelity.py" \
  "$repo_root/scripts/uninstall.zsh"; do
  require_file "$file"
done

initialize_package_layout
assert_prefix_safe
assert_user_config_root_safe || exit 1
if [[ -e "$prefix" || -L "$prefix" ]]; then
  initial_prefix_existed=1
  publication_prefix_existed=1
  initial_prefix_identity="$(path_identity "$prefix")" || {
    echo "Could not record package-prefix identity: $prefix" >&2
    exit 1
  }
fi
if (( ! dry_run )); then
  install_lock="${prefix:h}/.${prefix:t}.install.lock"
  acquire_owned_lock "$install_lock" "claude-litellm installation" 0 install_lock_fd || exit 1
fi
validate_state_layout_for_writes
preflight_litellm_master_key
preflight_public_shim
(( skip_preflight )) || preflight

# One-time transition guard for schema-v1 installations whose public commands
# mutated installed files. Schema-v2 installations keep durable state outside
# the prefix and therefore have no managed mutable package paths.
preflight_managed_mutable_files

# Detect legacy↔legacy and legacy↔destination state conflicts before this
# installer changes any destination package file. The real migration repeats the
# check after stopping legacy proxies, closing the race before publication.
if (( migrate_legacy )); then
  "$repo_root/scripts/migrate-legacy.zsh" --destination "$prefix" --preflight-only
fi

(( dry_run )) || prepare_runtime_build_toolchain

log "Installing claude-litellm from $repo_root"
log "Package: $prefix"
(( install_shim )) && log "Public command: $bin_dir/claude-litellm"
(( install_shim )) || log "Public shim disabled for this staged/custom install."
(( dry_run )) && log "Dry run: no files will be changed"

# Complete the networked/native runtime build before stopping the live proxy or
# replacing any package file. Only the already-validated venv is published in
# the mutation phase below.
stage_runtime

if (( ! dry_run )); then
  assert_user_config_root_safe || exit 1
  user_mutation_lock="$user_config_root/.mutation.lock"
  acquire_owned_lock "$user_mutation_lock" "model/alias configuration mutation" 1 user_mutation_lock_fd || exit 1
fi

# Validate private user overlays against the incoming package defaults with the
# already-built runtime. This happens before proxy shutdown or any package-file
# replacement, so an invalid/unsafe overlay cannot produce a partial upgrade.
if (( ! dry_run )); then
  validation_python="$prefix/runtime/venv/bin/python"
  [[ -z "$runtime_stage" ]] || validation_python="$runtime_stage/bin/python"
  python_isolated "$validation_python" "$repo_root/scripts/render-user-config.py" \
    --base-config "$repo_root/config/litellm_config.yaml" \
    --effective-config "$prefix/config/litellm_config.yaml" \
    --user-models "$user_config_root/models.json" \
    --base-settings "$repo_root/config/claude-litellm/settings.json" \
    --effective-settings "$prefix/config/claude-litellm/settings.json" \
    --settings-override "$user_config_root/settings.json" \
    --validate-only >/dev/null
fi

# Never replace a venv or package files underneath a live proxy. A PID is only
# signalled after both its command line and the prefix-owned runtime/config path
# prove ownership; ambiguous PID files abort the installation.
assert_prefix_safe
validate_state_layout_for_writes
if (( initial_prefix_existed )); then
  current_prefix_identity="$(path_identity "$prefix")" || {
    echo "Package prefix disappeared during runtime staging; refusing publication." >&2
    exit 1
  }
  [[ "$current_prefix_identity" == "$initial_prefix_identity" ]] || {
    echo "Package prefix identity changed during runtime staging; refusing publication." >&2
    exit 1
  }
  publication_prefix_existed=1
elif [[ -e "$prefix" || -L "$prefix" ]]; then
  echo "Package prefix appeared concurrently during runtime staging; refusing publication: $prefix" >&2
  exit 1
else
  publication_prefix_existed=0
fi
stop_owned_proxy "$prefix"
begin_package_publication

# The prefix ownership manifest makes these four roots package-owned. Reduce
# them to the explicit current-release layout before publishing any new file so
# stale executables, old callbacks, and symlinked parent directories cannot be
# retained or followed by the per-file install operations below.
prune_package_layout

for dir in \
  "$prefix/bin" \
  "$prefix/config/ai_litellm_callbacks" \
  "$prefix/config/ai-litellm/harnesses" \
  "$prefix/config/claude-litellm" \
  "$prefix/docs" \
  "$prefix/scripts" \
  "$prefix/state/ai-litellm" \
  "$prefix/state/auth/chatgpt" \
  "$prefix/state/auth/grok" \
  "$prefix/state/claude-litellm/claude-config"; do
  run mkdir -p "$dir"
done
for dir in "$prefix/state" "$prefix/state/ai-litellm" "$prefix/state/auth" \
  "$prefix/state/auth/chatgpt" "$prefix/state/auth/grok" \
  "$prefix/state/claude-litellm" "$prefix/state/claude-litellm/claude-config"; do
  (( dry_run )) || chmod 700 "$dir"
done

# Codex was intentionally retired from this product. Its managed config,
# launcher and descriptor are removed by the exact package-root allowlist.
# Historical state may contain transcripts, so leave it inert and untouched;
# native ~/.codex and the native codex binary are likewise never changed.

install_rendered "$repo_root/config/litellm_config.yaml" "$prefix/config/litellm_config.base.yaml"
install_rendered "$repo_root/config/python-requirements.in" "$prefix/config/python-requirements.in"
install_rendered "$repo_root/config/python-requirements.lock" "$prefix/config/python-requirements.lock"
install_rendered "$repo_root/config/ai_litellm_callbacks/__init__.py" "$prefix/config/ai_litellm_callbacks/__init__.py"
install_rendered "$repo_root/config/ai_litellm_callbacks/chatgpt_stream_compat.py" "$prefix/config/ai_litellm_callbacks/chatgpt_stream_compat.py"
install_rendered "$repo_root/config/ai_litellm_callbacks/oauth_guard.py" "$prefix/config/ai_litellm_callbacks/oauth_guard.py"
install_rendered "$repo_root/config/ai_litellm_callbacks/proxy_bootstrap.py" "$prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"
install_rendered "$repo_root/config/ai_litellm_callbacks/output_clamp.py" "$prefix/config/ai_litellm_callbacks/output_clamp.py"
install_rendered "$repo_root/config/ai-litellm/context-observations.json" "$prefix/config/ai-litellm/context-observations.json"
install_rendered "$repo_root/config/ai-litellm/lib.zsh" "$prefix/config/ai-litellm/lib.zsh"
install_rendered "$repo_root/config/ai-litellm/settings.json" "$prefix/config/ai-litellm/settings.json"
install_rendered "$repo_root/config/ai-litellm/harnesses/schema.json" "$prefix/config/ai-litellm/harnesses/schema.json"
install_rendered "$repo_root/config/ai-litellm/harnesses/claude.json" "$prefix/config/ai-litellm/harnesses/claude.json"
install_rendered "$repo_root/config/claude-litellm/settings.json" "$prefix/config/claude-litellm/settings.base.json"
install_rendered "$repo_root/config/claude-litellm/oauth.py" "$prefix/config/claude-litellm/oauth.py"
install_rendered "$repo_root/config/claude-litellm/shell.zsh" "$prefix/config/claude-litellm/shell.zsh"

for document in "$repo_root"/docs/*(.N); do
  [[ -f "$document" ]] && install_rendered "$document" "$prefix/docs/${document:t}"
done
install_executable "$repo_root/bin/claude-litellm" "$prefix/bin/claude-litellm"
install_executable "$repo_root/scripts/migrate-legacy.zsh" "$prefix/scripts/migrate-legacy.zsh"
install_executable "$repo_root/scripts/render-user-config.py" "$prefix/scripts/render-user-config.py"
install_executable "$repo_root/scripts/runtime-fingerprint.py" "$prefix/scripts/runtime-fingerprint.py"
install_executable "$repo_root/scripts/verify-install.py" "$prefix/scripts/verify-install.py"
install_executable "$repo_root/scripts/verify_tool_call_fidelity.py" "$prefix/scripts/verify_tool_call_fidelity.py"
install_executable "$repo_root/scripts/uninstall.zsh" "$prefix/scripts/uninstall.zsh"

seed_generated_outputs_from_backup
install_runtime
if (( ! dry_run )); then
  python_isolated "$prefix/runtime/venv/bin/python" \
    "$prefix/scripts/render-user-config.py" \
    --base-config "$prefix/config/litellm_config.base.yaml" \
    --effective-config "$prefix/config/litellm_config.yaml" \
    --user-models "$user_config_root/models.json" \
    --base-settings "$prefix/config/claude-litellm/settings.base.json" \
    --effective-settings "$prefix/config/claude-litellm/settings.json" \
    --settings-override "$user_config_root/settings.json" \
    >/dev/null
fi
# Per-file replacement keeps short-lived rollback copies until the incoming
# file is in place. Remove those copies and any concurrently-created cache file,
# then require the exact allowlist before provenance is published.
prune_package_layout
(( dry_run )) || validate_package_layout
write_manifest
(( install_shim )) && install_public_shim
install_test_failpoint before-commit
commit_package_publication
finish_postcommit_steps

log "Installed claude-litellm."
(( postcommit_warning_count == 0 )) || \
  log "Installation completed with $postcommit_warning_count post-install warning(s); review the messages above."
log "Runtime: LiteLLM $LITELLM_VERSION / prisma $PRISMA_VERSION / Python 3.13"
log "Manifest: $prefix/install-manifest.json"
log "Delete with: $prefix/scripts/uninstall.zsh --prefix ${(q)prefix}"
log "Next: claude-litellm --status"
