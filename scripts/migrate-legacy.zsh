#!/usr/bin/env zsh

set -euo pipefail

dry_run=0
remove_source=0
preflight_only=0
destination="${CLAUDE_LITELLM_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm}"
backup_root="${CLAUDE_LITELLM_BACKUP_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm-backups}"
backup_run=""
plan_root=""
typeset -a sources
sources=()

usage() {
  cat <<'EOF'
Usage: scripts/migrate-legacy.zsh [--dry-run] [--remove-source] [--preflight-only]
       [--destination PATH] [--source PATH ...]

Copies only durable Claude/LiteLLM data from an older ai-litellm installation:
  - Claude project/session transcripts (claude-config/projects)
  - Claude prompt history (claude-config/history.jsonl)
  - Claude account/project metadata (claude-config/.claude.json)
  - the package env file, when the destination does not already have one

Generated overlays, permission settings, security state, virtual environments,
caches, and all Codex state are deliberately excluded. Native ~/.claude and
~/.codex are never read, changed, or removed.

Without --source, the known legacy package roots are inspected:
  ~/.local/share/ai-litellm-fabric
  ~/.local/share/ai-litellm

--remove-source removes a recognized legacy package only after the selected data
has been copied and verified. Before removal, the entire legacy package
(including excluded Codex/security/runtime state) is copied and byte-verified
under ~/.local/share/claude-litellm-backups. Keychain entries are never changed.
--preflight-only performs the complete no-clobber plan/check without signalling
processes, creating backups, publishing data, or removing a source.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --remove-source)
      remove_source=1
      ;;
    --preflight-only)
      preflight_only=1
      ;;
    --destination)
      shift
      [[ $# -gt 0 ]] || { echo "--destination requires a path" >&2; exit 1; }
      destination="$1"
      ;;
    --source)
      shift
      [[ $# -gt 0 ]] || { echo "--source requires a path" >&2; exit 1; }
      sources+=("$1")
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

if (( ${#sources[@]} == 0 )); then
  sources=(
    "${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm-fabric"
    "${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm"
  )
fi

run() {
  if (( dry_run )); then
    printf 'dry-run '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

cleanup() {
  [[ -n "$plan_root" && -d "$plan_root" ]] || return 0
  rm -rf "$plan_root"
}
trap cleanup EXIT INT TERM

# zsh can bypass an EXIT trap when ERR_EXIT propagates out of a nested
# function. Keep the explicit plan/check gates below, and also clean the
# ephemeral plan on any other unhandled error without touching backups,
# published destination state, or a legacy source.
TRAPZERR() {
  local exit_status=$?
  cleanup || true
  return "$exit_status"
}

recognized_legacy_prefix() {
  local source="$1"
  local base="${source:t}"
  [[ "$base" == "ai-litellm" || "$base" == "ai-litellm-fabric" ]] || return 1
  [[ ! -L "$source" ]] || return 1
  [[ -f "$source/config/ai-litellm/lib.zsh" ]] || return 1
}

assert_destination_safe() {
  destination="${destination:A}"
  backup_root="${backup_root:A}"
  [[ "$destination" != "/" && "$destination" != "$HOME" && "$destination" != "${XDG_DATA_HOME:-$HOME/.local/share}" ]] || {
    echo "Refusing unsafe destination: $destination" >&2
    exit 1
  }
  [[ ! -L "$destination" ]] || {
    echo "Refusing symlink destination: $destination" >&2
    exit 1
  }
  [[ ! -e "$destination" || -d "$destination" ]] || {
    echo "Refusing non-directory destination: $destination" >&2
    exit 1
  }
  [[ "$backup_root" != "$destination" && "$backup_root" != "$destination"/* ]] || {
    echo "Refusing backup root inside migration destination: $backup_root" >&2
    exit 1
  }
  [[ ! -L "$backup_root" && ( ! -e "$backup_root" || -d "$backup_root" ) ]] || {
    echo "Refusing unsafe backup root: $backup_root" >&2
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
  local executable_name="${process_executable:t:l}"
  [[ "$command_line" == *"--config $config"* || "$command_line" == *"--config=$config"* ]] || return 1
  if [[ "$executable_name" == python* ]]; then
    [[ "$command_line" == "$process_executable $venv/bin/litellm "* || \
       "$command_line" == "$process_executable $venv/bin/litellm-proxy "* || \
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
         "$command_line" == "$process_executable -m litellm --config $config"* ]]
      ;;
    *) return 1 ;;
  esac
}

stop_owned_proxy() {
  local owner_prefix="$1"
  local pid_file="$owner_prefix/state/ai-litellm/litellm.pid"
  local pid command_line process_executable line candidate
  typeset -A owned_pids
  owned_pids=()

  if [[ -e "$pid_file" || -L "$pid_file" ]]; then
    [[ -f "$pid_file" && ! -L "$pid_file" ]] || {
      echo "Refusing to migrate $owner_prefix: proxy PID file is not a regular file: $pid_file" >&2
      return 1
    }
    pid="$(<"$pid_file")"
    [[ "$pid" == <-> ]] || {
      echo "Refusing to migrate $owner_prefix: invalid proxy PID in $pid_file" >&2
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
      echo "Refusing to migrate $owner_prefix: external LiteLLM pid $candidate uses its config without an owned PID file." >&2
      return 1
    fi
  done < <(ps -axo pid=,command= 2>/dev/null)

  for pid in ${(k)owned_pids}; do
    command_line="$(ps -ww -o command= -p "$pid" 2>/dev/null || true)"
    process_executable="$(ps -ww -o comm= -p "$pid" 2>/dev/null || true)"
    proxy_command_owned_by_prefix "$command_line" "$owner_prefix" "${owned_pids[$pid]}" "$process_executable" || {
      echo "Refusing to signal pid $pid: ownership changed during verification." >&2
      return 1
    }
    if (( dry_run )); then
      echo "dry-run stop proxy owned by $owner_prefix (pid $pid)"
      continue
    fi
    echo "Stopping proxy owned by $owner_prefix (pid $pid)."
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
      echo "Refusing to migrate $owner_prefix: owned proxy pid ${match[1]} is still running." >&2
      return 1
    elif proxy_command_owned_by_prefix "${match[2]}" "$owner_prefix" 1 "$process_executable"; then
      echo "Refusing to migrate $owner_prefix: external LiteLLM pid ${match[1]} still uses its config." >&2
      return 1
    fi
  done < <(ps -axo pid=,command= 2>/dev/null)
}

copy_tree() {
  local source="$1"
  local target="$2"
  [[ -d "$source" ]] || return 0
  run mkdir -p "$target"
  if (( dry_run )); then
    run cp -R -p "$source/." "$target/"
  else
    cp -R -p "$source/." "$target/"
    local source_entry relative target_entry
    while IFS= read -r source_entry; do
      relative="${source_entry#$source/}"
      target_entry="$target/$relative"
      if [[ -L "$source_entry" ]]; then
        [[ -L "$target_entry" && "$(readlink "$source_entry")" == "$(readlink "$target_entry")" ]] || {
          echo "Migration verification failed for symlink: $target_entry" >&2
          return 1
        }
      elif [[ -d "$source_entry" ]]; then
        [[ -d "$target_entry" && ! -L "$target_entry" ]] || {
          echo "Migration verification failed for directory: $target_entry" >&2
          return 1
        }
      elif [[ -f "$source_entry" ]]; then
        [[ -f "$target_entry" && ! -L "$target_entry" ]] && cmp -s "$source_entry" "$target_entry" || {
          echo "Migration verification failed for file: $target_entry" >&2
          return 1
        }
      else
        echo "Migration verification does not support source entry: $source_entry" >&2
        return 1
      fi
    done < <(find "$source" -mindepth 1 -print)
  fi
}

copy_file() {
  local source="$1"
  local target="$2"
  [[ -f "$source" ]] || return 0
  run mkdir -p "${target:h}"
  if (( dry_run )); then
    run cp -p "$source" "$target"
  else
    cp -p "$source" "$target"
    cmp -s "$source" "$target" || {
      echo "Migration verification failed for file: $target" >&2
      return 1
    }
  fi
}

entry_compatible() {
  local source_entry="$1"
  local target_entry="$2"
  [[ -e "$target_entry" || -L "$target_entry" ]] || return 0
  if [[ -L "$source_entry" ]]; then
    [[ -L "$target_entry" && "$(readlink "$source_entry")" == "$(readlink "$target_entry")" ]]
  elif [[ -d "$source_entry" ]]; then
    [[ -d "$target_entry" && ! -L "$target_entry" ]]
  elif [[ -f "$source_entry" ]]; then
    [[ -f "$target_entry" && ! -L "$target_entry" ]] && cmp -s "$source_entry" "$target_entry"
  else
    return 1
  fi
}

strict_merge_tree() {
  local source="$1"
  local target="$2"
  [[ -e "$source" || -L "$source" ]] || return 0
  [[ -d "$source" && ! -L "$source" ]] || {
    echo "Migration source tree is not a real directory: $source" >&2
    return 1
  }
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -d "$target" && ! -L "$target" ]] || {
      echo "Migration conflict (directory/type): $target" >&2
      return 1
    }
  else
    mkdir -p "$target"
  fi

  local source_entry relative target_entry
  while IFS= read -r source_entry; do
    relative="${source_entry#$source/}"
    target_entry="$target/$relative"
    if [[ -e "$target_entry" || -L "$target_entry" ]]; then
      entry_compatible "$source_entry" "$target_entry" || {
        echo "Migration conflict (different content or type): $target_entry" >&2
        return 1
      }
      continue
    fi
    mkdir -p "${target_entry:h}"
    if [[ -L "$source_entry" ]]; then
      ln -s "$(readlink "$source_entry")" "$target_entry"
    elif [[ -d "$source_entry" ]]; then
      mkdir "$target_entry"
      chmod --reference="$source_entry" "$target_entry" 2>/dev/null || true
    elif [[ -f "$source_entry" ]]; then
      cp -p "$source_entry" "$target_entry"
    else
      echo "Unsupported migration source entry: $source_entry" >&2
      return 1
    fi
  done < <(find "$source" -mindepth 1 -print)
}

strict_merge_file() {
  local source="$1"
  local target="$2"
  [[ -e "$source" || -L "$source" ]] || return 0
  [[ -f "$source" && ! -L "$source" ]] || {
    echo "Migration source file is not a regular file: $source" >&2
    return 1
  }
  if [[ -e "$target" || -L "$target" ]]; then
    entry_compatible "$source" "$target" || {
      echo "Migration conflict (different content or type): $target" >&2
      return 1
    }
    return 0
  fi
  mkdir -p "${target:h}"
  cp -p "$source" "$target"
}

check_tree_compatible() {
  local source="$1"
  local target="$2"
  [[ -d "$source" && ! -L "$source" ]] || return 0
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -d "$target" && ! -L "$target" ]] || {
      echo "Migration conflict (directory/type): $target" >&2
      return 1
    }
  fi
  local source_entry relative target_entry
  while IFS= read -r source_entry; do
    relative="${source_entry#$source/}"
    target_entry="$target/$relative"
    [[ -e "$target_entry" || -L "$target_entry" ]] || continue
    entry_compatible "$source_entry" "$target_entry" || {
      echo "Migration conflict (different content or type): $target_entry" >&2
      return 1
    }
  done < <(find "$source" -mindepth 1 -print)
}

check_file_compatible() {
  local source="$1"
  local target="$2"
  [[ -f "$source" && ! -L "$source" ]] || return 0
  [[ -e "$target" || -L "$target" ]] || return 0
  entry_compatible "$source" "$target" || {
    echo "Migration conflict (different content or type): $target" >&2
    return 1
  }
}

verify_tree_exact() {
  local source="$1"
  local target="$2"
  [[ -d "$source" && ! -L "$source" ]] || return 0
  [[ -d "$target" && ! -L "$target" ]] || {
    echo "Post-migration verification missing directory: $target" >&2
    return 1
  }
  local source_entry relative target_entry
  while IFS= read -r source_entry; do
    relative="${source_entry#$source/}"
    target_entry="$target/$relative"
    [[ -e "$target_entry" || -L "$target_entry" ]] && \
      entry_compatible "$source_entry" "$target_entry" || {
        echo "Post-migration verification failed: $target_entry" >&2
        return 1
      }
  done < <(find "$source" -mindepth 1 -print)
}

verify_file_exact() {
  local source="$1"
  local target="$2"
  [[ -f "$source" && ! -L "$source" ]] || return 0
  [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target" || {
    echo "Post-migration verification failed: $target" >&2
    return 1
  }
}

verify_published_plan() {
  verify_tree_exact \
    "$plan_root/state/claude-litellm/claude-config/projects" \
    "$destination/state/claude-litellm/claude-config/projects"
  verify_file_exact \
    "$plan_root/state/claude-litellm/claude-config/history.jsonl" \
    "$destination/state/claude-litellm/claude-config/history.jsonl"
  verify_file_exact \
    "$plan_root/state/claude-litellm/claude-config/.claude.json" \
    "$destination/state/claude-litellm/claude-config/.claude.json"
  verify_file_exact \
    "$plan_root/state/ai-litellm/env" \
    "$destination/state/ai-litellm/env"
}

assert_destination_layout_safe() {
  local path
  for path in \
    "$destination/state" \
    "$destination/state/claude-litellm" \
    "$destination/state/claude-litellm/claude-config" \
    "$destination/state/ai-litellm"; do
    [[ -e "$path" || -L "$path" ]] || continue
    [[ -d "$path" && ! -L "$path" ]] || {
      echo "Migration conflict (unsafe destination path): $path" >&2
      return 1
    }
  done

  local projects="$destination/state/claude-litellm/claude-config/projects"
  if [[ -e "$projects" || -L "$projects" ]]; then
    [[ -d "$projects" && ! -L "$projects" ]] || {
      echo "Migration conflict (unsafe projects path): $projects" >&2
      return 1
    }
  fi
  local selected_file
  for selected_file in \
    "$destination/state/claude-litellm/claude-config/history.jsonl" \
    "$destination/state/claude-litellm/claude-config/.claude.json" \
    "$destination/state/ai-litellm/env"; do
    [[ -e "$selected_file" || -L "$selected_file" ]] || continue
    [[ -f "$selected_file" && ! -L "$selected_file" ]] || {
      echo "Migration conflict (unsafe selected file): $selected_file" >&2
      return 1
    }
  done
}

ensure_backup_run() {
  [[ -z "$backup_run" ]] || return 0
  local stamp
  stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  backup_run="$backup_root/${stamp}-$$"
  run mkdir -p "$backup_run"
  (( dry_run )) || chmod 700 "$backup_root" "$backup_run"
}

backup_source() {
  local source="$1"
  (( remove_source )) || return 0
  ensure_backup_run
  local target="$backup_run/${source:t}"
  [[ ! -e "$target" ]] || {
    echo "Refusing to overwrite legacy backup: $target" >&2
    return 1
  }
  echo "Backing up complete legacy package to $target"
  copy_tree "$source" "$target"
  (( dry_run )) || chmod 700 "$target"
}

destination_has_selected_data() {
  local base="$destination/state/claude-litellm/claude-config"
  [[ -e "$base/projects" || -L "$base/projects" || \
     -e "$base/history.jsonl" || -L "$base/history.jsonl" || \
     -e "$base/.claude.json" || -L "$base/.claude.json" || \
     -e "$destination/state/ai-litellm/env" || -L "$destination/state/ai-litellm/env" ]]
}

backup_selected_destination() {
  destination_has_selected_data || return 0
  ensure_backup_run
  local target="$backup_run/destination-before-migration"
  [[ ! -e "$target" ]] || {
    echo "Refusing to overwrite destination backup: $target" >&2
    return 1
  }
  echo "Backing up destination state before migration to $target"
  local old_claude="$destination/state/claude-litellm/claude-config"
  copy_tree "$old_claude/projects" "$target/state/claude-litellm/claude-config/projects"
  copy_file "$old_claude/history.jsonl" "$target/state/claude-litellm/claude-config/history.jsonl"
  copy_file "$old_claude/.claude.json" "$target/state/claude-litellm/claude-config/.claude.json"
  copy_file "$destination/state/ai-litellm/env" "$target/state/ai-litellm/env"
  (( dry_run )) || chmod 700 "$target"
}

build_migration_plan() {
  local source old_claude
  for source in "${active_sources[@]}"; do
    old_claude="$source/state/claude-litellm/claude-config"
    strict_merge_tree \
      "$old_claude/projects" \
      "$plan_root/state/claude-litellm/claude-config/projects" || return $?
    strict_merge_file \
      "$old_claude/history.jsonl" \
      "$plan_root/state/claude-litellm/claude-config/history.jsonl" || return $?
    strict_merge_file \
      "$old_claude/.claude.json" \
      "$plan_root/state/claude-litellm/claude-config/.claude.json" || return $?
    strict_merge_file \
      "$source/state/ai-litellm/env" \
      "$plan_root/state/ai-litellm/env" || return $?
  done
}

check_plan_against_destination() {
  assert_destination_layout_safe || return $?
  check_tree_compatible \
    "$plan_root/state/claude-litellm/claude-config/projects" \
    "$destination/state/claude-litellm/claude-config/projects" || return $?
  check_file_compatible \
    "$plan_root/state/claude-litellm/claude-config/history.jsonl" \
    "$destination/state/claude-litellm/claude-config/history.jsonl" || return $?
  check_file_compatible \
    "$plan_root/state/claude-litellm/claude-config/.claude.json" \
    "$destination/state/claude-litellm/claude-config/.claude.json" || return $?
  check_file_compatible \
    "$plan_root/state/ai-litellm/env" \
    "$destination/state/ai-litellm/env" || return $?
}

plan_has_data() {
  [[ -n "$(find "$plan_root" -mindepth 1 -print -quit 2>/dev/null)" ]]
}

publish_plan() {
  plan_has_data || return 0
  if (( dry_run )); then
    echo "dry-run strictly merge planned durable state into $destination"
    return 0
  fi

  mkdir -p "$destination/state/claude-litellm/claude-config" "$destination/state/ai-litellm"
  chmod 700 "$destination/state" \
    "$destination/state/claude-litellm" \
    "$destination/state/claude-litellm/claude-config" \
    "$destination/state/ai-litellm"
  strict_merge_tree \
    "$plan_root/state/claude-litellm/claude-config/projects" \
    "$destination/state/claude-litellm/claude-config/projects"
  strict_merge_file \
    "$plan_root/state/claude-litellm/claude-config/history.jsonl" \
    "$destination/state/claude-litellm/claude-config/history.jsonl"
  strict_merge_file \
    "$plan_root/state/claude-litellm/claude-config/.claude.json" \
    "$destination/state/claude-litellm/claude-config/.claude.json"
  strict_merge_file \
    "$plan_root/state/ai-litellm/env" \
    "$destination/state/ai-litellm/env"
  [[ ! -f "$destination/state/ai-litellm/env" ]] || chmod 600 "$destination/state/ai-litellm/env"
}

assert_destination_safe

typeset -a active_sources
typeset -A seen_sources
active_sources=()
seen_sources=()
for source in "${sources[@]}"; do
  source="${source:A}"
  [[ "$source" != "$destination" ]] || continue
  [[ -e "$source" ]] || continue
  [[ -z "${seen_sources[$source]:-}" ]] || continue
  recognized_legacy_prefix "$source" || {
    echo "Refusing unrecognized legacy prefix: $source" >&2
    exit 1
  }
  [[ "$backup_root" != "$source" && "$backup_root" != "$source"/* ]] || {
    echo "Refusing backup root inside legacy source: $backup_root" >&2
    exit 1
  }
  seen_sources[$source]=1
  active_sources+=("$source")
done

if (( ${#active_sources[@]} == 0 )); then
  echo "No recognized legacy package found; nothing to migrate."
  exit 0
fi

# Freeze each legacy package before planning or backing it up. An ambiguous PID
# file aborts; only a process whose command line names this prefix's venv/config
# is signalled.
if (( ! preflight_only )); then
  for source in "${active_sources[@]}"; do
    stop_owned_proxy "$source"
  done
fi

plan_root="$(mktemp -d "${TMPDIR:-/tmp}/claude-litellm-migration.XXXXXX")"
chmod 700 "$plan_root"
build_migration_plan || {
  exit_status=$?
  cleanup
  exit "$exit_status"
}

# This is the no-clobber gate. It runs before any destination mkdir/copy. Files
# may overlap only when their types and bytes (or symlink targets) are identical;
# conflicts between two legacy sources are caught while building the plan.
check_plan_against_destination || {
  exit_status=$?
  cleanup
  exit "$exit_status"
}

if (( preflight_only )); then
  echo "Legacy migration preflight passed; destination was not modified."
  exit 0
fi

# Back up every destination path that could participate in the merge before the
# first destination mutation, then back up complete legacy roots before removal.
plan_has_data && backup_selected_destination
for source in "${active_sources[@]}"; do
  backup_source "$source"
done

publish_plan

# Re-verify every selected entry after publication and before any legacy root is
# removed. This catches short/failed copies and destination races; source removal
# is permitted only when destination types, link targets, and file bytes match.
(( dry_run )) || verify_published_plan

for source in "${active_sources[@]}"; do
  echo "Migrated durable Claude state from $source"
  if (( remove_source )); then
    echo "Removing migrated legacy package: $source"
    run rm -rf "$source"
  fi
done

echo "Legacy state migration complete. Native Claude/Codex homes and Keychain were untouched."
