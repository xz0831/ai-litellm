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

readonly LITELLM_VERSION="1.92.0"
readonly PRISMA_VERSION="0.15.0"

usage() {
  cat <<'EOF'
Usage: scripts/install.zsh [--dry-run] [--prefix PATH] [--skip-preflight]
                           [--no-migrate] [--no-shim]

Installs claude-litellm with one public command:
  package: ~/.local/share/claude-litellm
  command: ~/.local/bin/claude-litellm

The package contains an isolated, validated Python 3.11 runtime with
litellm[proxy]==1.92.0 and prisma==0.15.0. Runtime updates are assembled in a
staging directory and published only after import/version checks pass.

Model/provider/reasoning and Claude alias commands mutate installed configuration.
A reinstall refuses to overwrite those changes until they are merged into the
source checkout or the installed files are manually restored to their recorded
install baseline.

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

prefix="${prefix:A}"
default_prefix="${default_prefix:A}"
if (( prefix_explicit )) && [[ "$prefix" != "$default_prefix" ]]; then
  migrate_legacy=0
  install_shim=0
fi

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

cleanup() {
  [[ -z "$runtime_stage" || ! -e "$runtime_stage" ]] || rm -rf "$runtime_stage"
  [[ -z "$preflight_stage" || ! -e "$preflight_stage" ]] || rm -rf "$preflight_stage"
}
trap cleanup EXIT INT TERM

require_file() {
  local file_path="$1"
  [[ -f "$file_path" ]] || {
    echo "Missing repository file: $file_path" >&2
    exit 1
  }
}

assert_prefix_safe() {
  [[ "$prefix" != "/" && "$prefix" != "$HOME" && "$prefix" != "${XDG_DATA_HOME:-$HOME/.local/share}" ]] || {
    echo "Refusing unsafe package prefix: $prefix" >&2
    exit 1
  }
  [[ ! -L "$prefix" ]] || {
    echo "Refusing symlink package prefix: $prefix" >&2
    exit 1
  }
  if [[ -d "$prefix" && -n "$(find "$prefix" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    [[ -f "$prefix/config/ai-litellm/lib.zsh" || -f "$prefix/install-manifest.json" ]] || {
      echo "Refusing to overwrite a directory that is not a claude-litellm package: $prefix" >&2
      exit 1
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
         "$command_line" == "$process_executable -m litellm --config $config"* ]]
      ;;
    *) return 1 ;;
  esac
}

stop_owned_proxy() {
  local owner_prefix="$1"
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

preflight() {
  local -a required missing
  required=(zsh node ruby jq curl perl rg python3.11)
  missing=()
  local cmd
  for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} )); then
    echo "Missing claude-litellm install dependencies: ${missing[*]}" >&2
    echo "Typical macOS packages: brew install python@3.11 node jq ripgrep" >&2
    if (( ! dry_run )); then
      exit 1
    fi
  fi
  command -v python3.11 >/dev/null 2>&1 && \
    python3.11 -c 'import venv; assert (3, 11) <= __import__("sys").version_info < (3, 12)' >/dev/null
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
  if [[ -f "$target" ]] && cmp -s "$staged" "$target"; then
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

preflight_managed_mutable_file() {
  local source="$1"
  local target="$2"
  local relative_path="$3"
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
  if (( ! dry_run )) && [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    chmod 755 "$target"
    return 0
  fi
  backup_if_exists "$target"
  run cp "$source" "$target"
  run chmod 755 "$target"
}

runtime_python_matches_pins() {
  local python="$1"
  [[ -x "$python" ]] || return 1
  "$python" - "$LITELLM_VERSION" "$PRISMA_VERSION" <<'PY'
import importlib.metadata as metadata
import sys
expected_litellm, expected_prisma = sys.argv[1:]
assert sys.version_info[:2] == (3, 11)
assert metadata.version("litellm") == expected_litellm
assert metadata.version("prisma") == expected_prisma
import litellm, prisma  # noqa: F401
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
        "$first_line" == "#!$runtime_root/bin/python3.11" ]]; then
    return 0
  fi
  [[ "$first_line" == '#!/bin/sh' && "$third_line" == "' '''" ]] || return 1
  [[ "$second_line" == "'''exec' \"$runtime_root/bin/python\" \"\$0\" \"\$@\"" ||
     "$second_line" == "'''exec' \"$runtime_root/bin/python3.11\" \"\$0\" \"\$@\"" ]]
}

runtime_is_current() {
  local runtime_root="$prefix/runtime/venv"
  local python="$runtime_root/bin/python"
  litellm_console_script_targets_runtime "$runtime_root" || return 1
  "$runtime_root/bin/litellm" --version >/dev/null 2>&1 || return 1
  runtime_python_matches_pins "$python" >/dev/null 2>&1
}

install_runtime() {
  if (( dry_run )); then
    log "dry-run stage isolated Python 3.11 runtime: litellm[proxy]==$LITELLM_VERSION prisma==$PRISMA_VERSION"
    return 0
  fi
  if runtime_is_current; then
    log "Runtime already validated: LiteLLM $LITELLM_VERSION / prisma $PRISMA_VERSION"
    return 0
  fi

  mkdir -p "$prefix/runtime"
  chmod 700 "$prefix/runtime"
  runtime_stage="$prefix/runtime/.venv-stage.$$"
  rm -rf "$runtime_stage"
  python3.11 -m venv "$runtime_stage"
  PIP_DISABLE_PIP_VERSION_CHECK=1 "$runtime_stage/bin/python" -m pip install \
    --upgrade --upgrade-strategy eager \
    "litellm[proxy]==$LITELLM_VERSION" "prisma==$PRISMA_VERSION"

  "$runtime_stage/bin/python" - "$LITELLM_VERSION" "$PRISMA_VERSION" <<'PY'
import importlib.metadata as metadata
import sys
expected_litellm, expected_prisma = sys.argv[1:]
assert sys.version_info[:2] == (3, 11), sys.version
assert metadata.version("litellm") == expected_litellm
assert metadata.version("prisma") == expected_prisma
import litellm, prisma  # noqa: F401
PY

  local current="$prefix/runtime/venv"
  local previous="$prefix/runtime/.venv-previous.$$"
  local staged_root="$runtime_stage"
  [[ ! -e "$current" ]] || mv "$current" "$previous"
  if ! mv "$runtime_stage" "$current"; then
    [[ ! -e "$previous" ]] || mv "$previous" "$current"
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
     ! "$current/bin/litellm" --version >/dev/null 2>&1 ||
     ! runtime_python_matches_pins "$current/bin/python" >/dev/null 2>&1; then
    echo "Failed to relocate the staged LiteLLM console script." >&2
    rm -rf "$current"
    [[ ! -e "$previous" ]] || mv "$previous" "$current"
    return 1
  fi
  rm -rf "$previous"
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
  local python="$prefix/runtime/venv/bin/python"
  CLAUDE_LITELLM_PREFIX="$prefix" SOURCE_COMMIT="$commit" SOURCE_ORIGIN="$origin" \
    SOURCE_DIRTY="$dirty" INSTALLED_AT="$installed_at" LITELLM_PIN="$LITELLM_VERSION" \
    PRISMA_PIN="$PRISMA_VERSION" "$python" - <<'PY'
import json
import hashlib
import os
import platform
from pathlib import Path

prefix = Path(os.environ["CLAUDE_LITELLM_PREFIX"])
managed_mutable_files = {}
for relative in (
    "config/litellm_config.yaml",
    "config/claude-litellm/settings.json",
):
    path = prefix / relative
    if path.is_file() and not path.is_symlink():
        managed_mutable_files[relative] = {
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "upgradePolicy": "abort-on-drift",
        }
payload = {
    "product": "claude-litellm",
    "schemaVersion": 1,
    "installedAt": os.environ["INSTALLED_AT"],
    "prefix": str(prefix),
    "source": {
        "origin": os.environ["SOURCE_ORIGIN"],
        "commit": os.environ["SOURCE_COMMIT"],
        "dirty": os.environ["SOURCE_DIRTY"] == "true",
    },
    "runtime": {
        "python": platform.python_version(),
        "litellm": os.environ["LITELLM_PIN"],
        "prisma": os.environ["PRISMA_PIN"],
        "venv": str(prefix / "runtime" / "venv"),
    },
    "managedMutableFiles": managed_mutable_files,
}
target = prefix / "install-manifest.json"
staged = target.with_name(target.name + ".tmp")
staged.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
staged.replace(target)
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
  [[ -n "${LITELLM_MASTER_KEY:-}" ]] && return 0
  local env_file="$prefix/state/ai-litellm/env"
  if [[ -e "$env_file" || -L "$env_file" ]]; then
    [[ -f "$env_file" && ! -L "$env_file" ]] || {
      echo "Refusing unsafe package env path: $env_file" >&2
      return 1
    }
  fi
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
  generated="$($prefix/runtime/venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(48))')"
  mkdir -p "${env_file:h}"
  printf '%s' "$generated" | node -e '
const fs = require("fs");
const [file, key] = process.argv.slice(1);
const value = fs.readFileSync(0, "utf8");
let lines = [];
try {
  lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
  if (lines.length && lines[lines.length - 1] === "") lines.pop();
} catch (error) {
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
const staged = `${file}.tmp.${process.pid}`;
fs.writeFileSync(staged, lines.join("\n") + "\n", {mode: 0o600});
fs.renameSync(staged, file);
' "$env_file" LITELLM_MASTER_KEY
  chmod 600 "$env_file"
}

install_public_shim() {
  local target="$bin_dir/claude-litellm"
  run mkdir -p "$bin_dir"
  if (( dry_run )); then
    log "dry-run shim $target -> $prefix/bin/claude-litellm"
    return 0
  fi
  local staged="${target}.tmp.$$"
  {
    print -r -- '#!/usr/bin/env zsh'
    print -r -- "export CLAUDE_LITELLM_ROOT=${(qq)prefix}"
    print -r -- "export AI_LITELLM_HOME=${(qq)prefix}"
    print -r -- 'export PATH="$CLAUDE_LITELLM_ROOT/runtime/venv/bin:$PATH"'
    print -r -- 'exec "$CLAUDE_LITELLM_ROOT/bin/claude-litellm" "$@"'
  } > "$staged"
  if [[ -f "$target" ]] && cmp -s "$staged" "$target"; then
    rm -f "$staged"
    chmod 755 "$target"
    return 0
  fi
  backup_if_exists "$target"
  mv "$staged" "$target"
  chmod 755 "$target"
}

remove_owned_legacy_shims() {
  local name target
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
    run rm -f "$target"
  done
}

for file in \
  "$repo_root/bin/claude-litellm" \
  "$repo_root/config/litellm_config.yaml" \
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
  "$repo_root/scripts/migrate-legacy.zsh" \
  "$repo_root/scripts/uninstall.zsh"; do
  require_file "$file"
done

assert_prefix_safe
(( skip_preflight )) || preflight

# Public model/harness commands intentionally mutate these installed files.
# Refuse a reinstall before stopping a proxy or touching the prefix when either
# file has drifted from its recorded install baseline.
preflight_managed_mutable_files

# Detect legacy↔legacy and legacy↔destination state conflicts before this
# installer changes any destination package file. The real migration repeats the
# check after stopping legacy proxies, closing the race before publication.
if (( migrate_legacy )); then
  "$repo_root/scripts/migrate-legacy.zsh" --destination "$prefix" --preflight-only
fi

log "Installing claude-litellm from $repo_root"
log "Package: $prefix"
(( install_shim )) && log "Public command: $bin_dir/claude-litellm"
(( install_shim )) || log "Public shim disabled for this staged/custom install."
(( dry_run )) && log "Dry run: no files will be changed"

# Never replace a venv or package files underneath a live proxy. A PID is only
# signalled after both its command line and the prefix-owned runtime/config path
# prove ownership; ambiguous PID files abort the installation.
stop_owned_proxy "$prefix"

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

# Codex was intentionally retired from this product. These paths are package
# state only; native ~/.codex and the native codex binary are never touched.
run rm -rf "$prefix/config/codex-litellm" "$prefix/state/codex-litellm"
run rm -f "$prefix/bin/codex-litellm" "$prefix/config/ai-litellm/harnesses/codex.json"

install_rendered "$repo_root/config/litellm_config.yaml" "$prefix/config/litellm_config.yaml"
install_rendered "$repo_root/config/ai_litellm_callbacks/__init__.py" "$prefix/config/ai_litellm_callbacks/__init__.py"
install_rendered "$repo_root/config/ai_litellm_callbacks/oauth_guard.py" "$prefix/config/ai_litellm_callbacks/oauth_guard.py"
install_rendered "$repo_root/config/ai_litellm_callbacks/proxy_bootstrap.py" "$prefix/config/ai_litellm_callbacks/proxy_bootstrap.py"
install_rendered "$repo_root/config/ai_litellm_callbacks/output_clamp.py" "$prefix/config/ai_litellm_callbacks/output_clamp.py"
install_rendered "$repo_root/config/ai-litellm/context-observations.json" "$prefix/config/ai-litellm/context-observations.json"
install_rendered "$repo_root/config/ai-litellm/lib.zsh" "$prefix/config/ai-litellm/lib.zsh"
install_rendered "$repo_root/config/ai-litellm/settings.json" "$prefix/config/ai-litellm/settings.json"
install_rendered "$repo_root/config/ai-litellm/harnesses/schema.json" "$prefix/config/ai-litellm/harnesses/schema.json"
install_rendered "$repo_root/config/ai-litellm/harnesses/claude.json" "$prefix/config/ai-litellm/harnesses/claude.json"
install_rendered "$repo_root/config/claude-litellm/settings.json" "$prefix/config/claude-litellm/settings.json"
install_rendered "$repo_root/config/claude-litellm/oauth.py" "$prefix/config/claude-litellm/oauth.py"
install_rendered "$repo_root/config/claude-litellm/shell.zsh" "$prefix/config/claude-litellm/shell.zsh"

for document in "$repo_root"/docs/*(.N); do
  [[ -f "$document" ]] && install_rendered "$document" "$prefix/docs/${document:t}"
done
install_executable "$repo_root/bin/claude-litellm" "$prefix/bin/claude-litellm"
install_executable "$repo_root/scripts/migrate-legacy.zsh" "$prefix/scripts/migrate-legacy.zsh"
install_executable "$repo_root/scripts/uninstall.zsh" "$prefix/scripts/uninstall.zsh"

install_runtime
write_manifest

if (( migrate_legacy )); then
  typeset -a migration_args
  migration_args=(--destination "$prefix" --remove-source)
  (( dry_run )) && migration_args+=(--dry-run)
  "$repo_root/scripts/migrate-legacy.zsh" "${migration_args[@]}"
  remove_owned_legacy_shims
else
  log "Legacy migration disabled; older packages and shims were left unchanged."
fi

ensure_litellm_master_key
(( install_shim )) && install_public_shim

log "Installed claude-litellm."
log "Runtime: LiteLLM $LITELLM_VERSION / prisma $PRISMA_VERSION / Python 3.11"
log "Manifest: $prefix/install-manifest.json"
log "Delete with: $prefix/scripts/uninstall.zsh --prefix ${(q)prefix}"
log "Next: claude-litellm --status"
