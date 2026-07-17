# Shared LiteLLM proxy management for local agent wrappers.

export AI_LITELLM_HOME="${AI_LITELLM_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm}"
if [[ -f "$AI_LITELLM_HOME/install-manifest.json" && \
      ! -L "$AI_LITELLM_HOME/install-manifest.json" ]]; then
  # Installed mode is closed over its verified package and private state root.
  # Caller-controlled package/config/callback/state paths would otherwise let
  # a poisoned environment execute an unmanifested renderer or bootstrap after
  # provider credentials have been loaded. Checkout-only tests (no manifest)
  # retain the flexible overrides below.
  export AI_LITELLM_INSTALLED_MODE=1
  export AI_LITELLM_CONFIG_HOME="$AI_LITELLM_HOME/config"
  export AI_LITELLM_STATE_HOME="$AI_LITELLM_HOME/state"
  export AI_LITELLM_BIN_DIR="$AI_LITELLM_HOME/bin"
  export AI_LITELLM_PROXY_HOME="$AI_LITELLM_HOME/state/ai-litellm"
  export AI_LITELLM_BASE_CONFIG="$AI_LITELLM_HOME/config/litellm_config.base.yaml"
  export AI_LITELLM_CONFIG="$AI_LITELLM_HOME/config/litellm_config.yaml"
  export AI_LITELLM_BASE_CLAUDE_SETTINGS="$AI_LITELLM_HOME/config/claude-litellm/settings.base.json"
  export AI_LITELLM_EFFECTIVE_CLAUDE_SETTINGS="$AI_LITELLM_HOME/config/claude-litellm/settings.json"
  export AI_LITELLM_CONFIG_RENDERER="$AI_LITELLM_HOME/scripts/render-user-config.py"
  export AI_LITELLM_QUALIFICATIONS_FILE="$AI_LITELLM_HOME/state/ai-litellm/model-qualifications.json"
  export AI_LITELLM_SETTINGS="$AI_LITELLM_HOME/config/ai-litellm/settings.json"
  export AI_LITELLM_HARNESSES_DIR="$AI_LITELLM_HOME/config/ai-litellm/harnesses"
  export AI_LITELLM_ENV="$AI_LITELLM_HOME/state/ai-litellm/env"
  export AI_LITELLM_PID_FILE="$AI_LITELLM_HOME/state/ai-litellm/litellm.pid"
  export AI_LITELLM_LOCK_DIR="$AI_LITELLM_HOME/state/ai-litellm/litellm.lock"
  export AI_LITELLM_LOG_FILE="$AI_LITELLM_HOME/state/ai-litellm/litellm.log"
  export AI_LITELLM_CONFIG_HASH_FILE="$AI_LITELLM_HOME/state/ai-litellm/litellm.config.sha256"
  export AI_LITELLM_STARTED_AT_FILE="$AI_LITELLM_HOME/state/ai-litellm/litellm.started_at"
  export AI_LITELLM_REASONING_OBS_FILE="$AI_LITELLM_HOME/state/ai-litellm/reasoning-observations.json"
  export AI_LITELLM_CONTEXT_OBS_SEED="$AI_LITELLM_HOME/config/ai-litellm/context-observations.json"
  export AI_LITELLM_CONTEXT_OBS_FILE="$AI_LITELLM_HOME/state/ai-litellm/context-observations.json"
  export AI_LITELLM_TASKS_HOME="$AI_LITELLM_HOME/state/claude-litellm/tasks"
  export AI_LITELLM_TASK_LEDGER="$AI_LITELLM_HOME/scripts/task-ledger.py"
  export AI_LITELLM_LIFECYCLE_LOCK="${AI_LITELLM_HOME:h}/.${AI_LITELLM_HOME:t}.install.lock"
  export AI_LITELLM_LEGACY_ENV="$HOME/.config/ai-litellm/env"
  export AI_LITELLM_LEGACY_PID_FILE="$AI_LITELLM_HOME/state/ai-litellm/.legacy-ai-litellm.pid"
  export AI_LITELLM_LEGACY_LOG_FILE="$AI_LITELLM_HOME/state/ai-litellm/.legacy-ai-litellm.log"
  export AI_LITELLM_LEGACY_CLAUDE_ENV="$HOME/.config/claude-litellm/env"
  export AI_LITELLM_LEGACY_CLAUDE_PID_FILE="$AI_LITELLM_HOME/state/ai-litellm/.legacy-claude-litellm.pid"
  export AI_LITELLM_LEGACY_CLAUDE_LOG_FILE="$AI_LITELLM_HOME/state/ai-litellm/.legacy-claude-litellm.log"
fi
export AI_LITELLM_CONFIG_HOME="${AI_LITELLM_CONFIG_HOME:-$AI_LITELLM_HOME/config}"
export AI_LITELLM_STATE_HOME="${AI_LITELLM_STATE_HOME:-$AI_LITELLM_HOME/state}"
export AI_LITELLM_BIN_DIR="${AI_LITELLM_BIN_DIR:-$AI_LITELLM_HOME/bin}"
export AI_LITELLM_PROXY_HOME="${AI_LITELLM_PROXY_HOME:-$AI_LITELLM_STATE_HOME/ai-litellm}"
export AI_LITELLM_USER_CONFIG_HOME="${AI_LITELLM_USER_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-litellm}"
export AI_LITELLM_USER_MODELS="${AI_LITELLM_USER_MODELS:-$AI_LITELLM_USER_CONFIG_HOME/models.json}"
export AI_LITELLM_USER_CLAUDE_SETTINGS="${AI_LITELLM_USER_CLAUDE_SETTINGS:-$AI_LITELLM_USER_CONFIG_HOME/settings.json}"
if [[ -z "${AI_LITELLM_BASE_CONFIG:-}" ]]; then
  if [[ -f "$AI_LITELLM_CONFIG_HOME/litellm_config.base.yaml" ]]; then
    export AI_LITELLM_BASE_CONFIG="$AI_LITELLM_CONFIG_HOME/litellm_config.base.yaml"
  else
    export AI_LITELLM_BASE_CONFIG="$AI_LITELLM_CONFIG_HOME/litellm_config.yaml"
  fi
fi
export AI_LITELLM_CONFIG="${AI_LITELLM_CONFIG:-$AI_LITELLM_CONFIG_HOME/litellm_config.yaml}"
if [[ -z "${AI_LITELLM_BASE_CLAUDE_SETTINGS:-}" ]]; then
  if [[ -f "$AI_LITELLM_CONFIG_HOME/claude-litellm/settings.base.json" ]]; then
    export AI_LITELLM_BASE_CLAUDE_SETTINGS="$AI_LITELLM_CONFIG_HOME/claude-litellm/settings.base.json"
  else
    export AI_LITELLM_BASE_CLAUDE_SETTINGS="$AI_LITELLM_CONFIG_HOME/claude-litellm/settings.json"
  fi
fi
export AI_LITELLM_EFFECTIVE_CLAUDE_SETTINGS="${AI_LITELLM_EFFECTIVE_CLAUDE_SETTINGS:-$AI_LITELLM_CONFIG_HOME/claude-litellm/settings.json}"
export AI_LITELLM_CONFIG_RENDERER="${AI_LITELLM_CONFIG_RENDERER:-$AI_LITELLM_HOME/scripts/render-user-config.py}"
export AI_LITELLM_QUALIFICATIONS_FILE="${AI_LITELLM_QUALIFICATIONS_FILE:-$AI_LITELLM_PROXY_HOME/model-qualifications.json}"
export AI_LITELLM_SETTINGS="${AI_LITELLM_SETTINGS:-$AI_LITELLM_CONFIG_HOME/ai-litellm/settings.json}"
export AI_LITELLM_HARNESSES_DIR="${AI_LITELLM_HARNESSES_DIR:-$AI_LITELLM_CONFIG_HOME/ai-litellm/harnesses}"
export AI_LITELLM_ENV="${AI_LITELLM_ENV:-$AI_LITELLM_PROXY_HOME/env}"
export AI_LITELLM_PID_FILE="${AI_LITELLM_PID_FILE:-$AI_LITELLM_PROXY_HOME/litellm.pid}"
export AI_LITELLM_LOCK_DIR="${AI_LITELLM_LOCK_DIR:-$AI_LITELLM_PROXY_HOME/litellm.lock}"
export AI_LITELLM_LIFECYCLE_LOCK="${AI_LITELLM_LIFECYCLE_LOCK:-${AI_LITELLM_HOME:h}/.${AI_LITELLM_HOME:t}.install.lock}"
export AI_LITELLM_LOG_FILE="${AI_LITELLM_LOG_FILE:-$AI_LITELLM_PROXY_HOME/litellm.log}"
export AI_LITELLM_CONFIG_HASH_FILE="${AI_LITELLM_CONFIG_HASH_FILE:-$AI_LITELLM_PROXY_HOME/litellm.config.sha256}"
export AI_LITELLM_STARTED_AT_FILE="${AI_LITELLM_STARTED_AT_FILE:-$AI_LITELLM_PROXY_HOME/litellm.started_at}"
export AI_LITELLM_REASONING_OBS_FILE="${AI_LITELLM_REASONING_OBS_FILE:-$AI_LITELLM_PROXY_HOME/reasoning-observations.json}"
export AI_LITELLM_CONTEXT_OBS_SEED="${AI_LITELLM_CONTEXT_OBS_SEED:-$AI_LITELLM_CONFIG_HOME/ai-litellm/context-observations.json}"
export AI_LITELLM_CONTEXT_OBS_FILE="${AI_LITELLM_CONTEXT_OBS_FILE:-$AI_LITELLM_PROXY_HOME/context-observations.json}"
export AI_LITELLM_TASKS_HOME="${AI_LITELLM_TASKS_HOME:-$AI_LITELLM_STATE_HOME/claude-litellm/tasks}"
export AI_LITELLM_TASK_LEDGER="${AI_LITELLM_TASK_LEDGER:-$AI_LITELLM_HOME/scripts/task-ledger.py}"
export AI_LITELLM_LOCK_MAX_AGE_SECONDS="${AI_LITELLM_LOCK_MAX_AGE_SECONDS:-300}"
export AI_LITELLM_LEGACY_ENV="${AI_LITELLM_LEGACY_ENV:-$HOME/.config/ai-litellm/env}"
export AI_LITELLM_LEGACY_PID_FILE="${AI_LITELLM_LEGACY_PID_FILE:-$HOME/.config/ai-litellm/litellm.pid}"
export AI_LITELLM_LEGACY_LOG_FILE="${AI_LITELLM_LEGACY_LOG_FILE:-$HOME/.config/ai-litellm/litellm.log}"
export AI_LITELLM_LEGACY_CLAUDE_ENV="${AI_LITELLM_LEGACY_CLAUDE_ENV:-$HOME/.config/claude-litellm/env}"
export AI_LITELLM_LEGACY_CLAUDE_PID_FILE="${AI_LITELLM_LEGACY_CLAUDE_PID_FILE:-$HOME/.config/claude-litellm/litellm.pid}"
export AI_LITELLM_LEGACY_CLAUDE_LOG_FILE="${AI_LITELLM_LEGACY_CLAUDE_LOG_FILE:-$HOME/.config/claude-litellm/litellm.log}"
export OPENROUTER_KEYCHAIN_SERVICE="${OPENROUTER_KEYCHAIN_SERVICE:-openrouter-api-key}"
export OPENROUTER_KEYCHAIN_ACCOUNT="${OPENROUTER_KEYCHAIN_ACCOUNT:-$USER}"
export LITELLM_MASTER_KEYCHAIN_SERVICE="${LITELLM_MASTER_KEYCHAIN_SERVICE:-litellm-master-key}"
export LITELLM_MASTER_KEYCHAIN_ACCOUNT="${LITELLM_MASTER_KEYCHAIN_ACCOUNT:-$USER}"

# macOS zsh's `zsystem flock` opens an existing path; it does not create one.
# Publish lock files safely before flocking and reject symlinks/special files.
ai_litellm_lock_file_prepare() {
  local lock_file="$1" parent="${1:h}"
  if [[ -e "$parent" || -L "$parent" ]]; then
    [[ -d "$parent" && ! -L "$parent" ]] || {
      echo "Refusing unsafe lock parent: $parent" >&2
      return 1
    }
  else
    mkdir -p "$parent" || return 1
  fi
  if [[ ! -e "$lock_file" && ! -L "$lock_file" ]]; then
    ( umask 077; set -o noclobber; : > "$lock_file" ) 2>/dev/null || true
  fi
  [[ -f "$lock_file" && ! -L "$lock_file" ]] || {
    echo "Refusing unsafe lock file: $lock_file" >&2
    return 1
  }
  chmod 600 "$lock_file" 2>/dev/null || return 1
  [[ "$(stat -f %Lp "$lock_file" 2>/dev/null)" == "600" ]]
}

# Force UTF-8 for every inline Ruby invocation below. Under a C or empty locale
# Ruby's default external encoding is US-ASCII; the em-dashes shipped in
# litellm_config.yaml comments then make raw-line regex (sync/install route
# writing, the reasoning/anchor doctors) abort with "invalid byte sequence in
# US-ASCII". RUBYOPT is set per-invocation via a prefix assignment and never
# exported, so the shared-environment isolation guarantee is preserved.
ai_litellm_ruby() {
  (
    unset RUBYOPT RUBYLIB RUBYPATH
    cd /
    RUBYOPT="-Eutf-8:utf-8" command ruby "$@"
  )
}

# Managed Python must never inherit an import path from the repository being
# operated on.  `-I -B` is used whenever only stdlib/site-packages are needed;
# callback imports use a single trusted package config root with `-sP -B`.
# Both forms run from `/` so neither the caller's cwd nor a script directory can
# shadow LiteLLM or one of its dependencies.
ai_litellm_python_isolated() {
  local python="$1"
  shift
  (
    unset PYTHONPATH PYTHONHOME PYTHONSTARTUP PYTHONINSPECT PYTHONBREAKPOINT \
      PYTHONUSERBASE PYTHONEXECUTABLE PYTHONWARNINGS PYTHONPLATLIBDIR \
      PYTHONPYCACHEPREFIX
    cd /
    "$python" -I -B "$@"
  )
}

# Integrity verification must never execute the runtime it is measuring.
# Resolve a Python 3.13 target outside the managed prefix, including through a
# venv compatibility symlink, and invoke the resolved external file directly.
ai_litellm_external_python() {
  local directory candidate resolved
  local -a candidates
  candidates=(/opt/homebrew/bin/python3.13 /usr/local/bin/python3.13)
  for directory in ${(s/:/)PATH}; do
    [[ -n "$directory" ]] || directory=.
    candidates+=("$directory/python3.13")
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" && -f "$candidate" ]] || continue
    resolved="${candidate:A}"
    case "$resolved" in
      "$AI_LITELLM_HOME"|"$AI_LITELLM_HOME"/*) continue ;;
    esac
    if "$resolved" -I -B -S -c \
      'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 13) else 1)' \
      >/dev/null 2>&1; then
      print -r -- "$resolved"
      return 0
    fi
  done
  return 1
}

ai_litellm_python_configured() {
  local python="$1"
  shift
  (
    unset PYTHONPATH PYTHONHOME PYTHONSTARTUP PYTHONINSPECT PYTHONBREAKPOINT \
      PYTHONUSERBASE PYTHONEXECUTABLE PYTHONWARNINGS PYTHONPLATLIBDIR \
      PYTHONPYCACHEPREFIX
    export PYTHONPATH="$AI_LITELLM_CONFIG_HOME"
    export PYTHONNOUSERSITE=1
    cd /
    "$python" -sP -B "$@"
  )
}

ai_litellm_json_file() {
  local file="$1"
  local json_path="$2"
  [[ -f "$file" ]] || return 1
  node -e '
const fs = require("fs");
const file = process.argv[1];
const path = process.argv[2].split(".");
let value = JSON.parse(fs.readFileSync(file, "utf8"));
for (const key of path) {
  value = value != null && typeof value === "object" && Object.prototype.hasOwnProperty.call(value, key)
    ? value[key]
    : undefined;
}
if (value == null) process.exit(1);
if (typeof value === "object") console.log(JSON.stringify(value));
else console.log(String(value));
' "$file" "$json_path"
}

ai_litellm_json_array() {
  local file="$1"
  local json_path="$2"
  [[ -f "$file" ]] || return 1
  node -e '
const fs = require("fs");
const file = process.argv[1];
const path = process.argv[2].split(".");
let value = JSON.parse(fs.readFileSync(file, "utf8"));
for (const key of path) {
  value = value != null && typeof value === "object" && Object.prototype.hasOwnProperty.call(value, key)
    ? value[key]
    : undefined;
}
if (!Array.isArray(value)) process.exit(1);
for (const item of value) console.log(String(item));
' "$file" "$json_path"
}

ai_litellm_template_value() {
  local value="$1"
  value="${value//\{\{ai.baseUrl\}\}/$(ai_litellm_base_url)}"
  value="${value//\{\{ai.apiBaseUrl\}\}/$(ai_litellm_api_base_url)}"
  printf '%s\n' "$value"
}

ai_litellm_json() {
  ai_litellm_json_file "$AI_LITELLM_SETTINGS" "$1"
}

# Serialize key/value pairs to one line of JSON. Args alternate KEY VALUE …;
# a VALUE of the form @num:<n> emits a JSON number, @bool:<true|false> a bool,
# @null emits null, otherwise a JSON string. Output formatter only — never
# computes state. Always exits 0 with valid JSON.
ai_litellm_emit_json() {
  node -e '
const a = process.argv.slice(1);
const o = {};
for (let i = 0; i + 1 < a.length; i += 2) {
  const k = a[i]; let v = a[i + 1];
  if (v === "@null") o[k] = null;
  else if (v.startsWith("@num:")) { const n = Number(v.slice(5)); o[k] = Number.isFinite(n) ? n : null; }
  else if (v.startsWith("@bool:")) o[k] = v.slice(6) === "true";
  else o[k] = v;
}
process.stdout.write(JSON.stringify(o));
' "$@"
}

# Credential files are integrity-sensitive even when the leaf itself is opened
# with O_NOFOLLOW: open(2) still follows symlinks in parent components. Walk the
# lexical directory path one component at a time and reject every untrusted
# symlink or non-directory before opening or creating a managed env file.
ai_litellm_credential_directory_chain_trusted() {
  local target="${1:a}" component current="/" link_target=""
  local -a components
  components=("${(@s:/:)target}")
  for component in "${components[@]}"; do
    [[ -n "$component" ]] || continue
    current="${current%/}/$component"
    if [[ -L "$current" ]]; then
      link_target="$(readlink "$current" 2>/dev/null || true)"
      # Mirror the package-path policy: these are the only root-owned macOS
      # compatibility aliases. TMPDIR normally starts below /var/folders.
      # Every later/user-controlled symlink remains a hard failure.
      case "$current:$link_target" in
        /var:private/var|/tmp:private/tmp) ;;
        *) return 1 ;;
      esac
    elif [[ -e "$current" ]]; then
      [[ -d "$current" ]] || return 1
    fi
  done
}

# Create or tighten one private directory without ever chmodding a symlink
# through its pathname. The fd validation also makes the final component check
# apply to the object that is actually chmodded, not an earlier lstat result.
ai_litellm_private_directory_prepare() {
  local directory="${1:a}"
  ai_litellm_credential_directory_chain_trusted "$directory" || return 1
  ( umask 077; mkdir -p "$directory" ) || return 1
  ai_litellm_credential_directory_chain_trusted "$directory" || return 1
  node -e '
const fs = require("fs");
const directory = process.argv[1];
let fd;
try {
  fd = fs.openSync(
    directory,
    fs.constants.O_RDONLY | fs.constants.O_DIRECTORY | fs.constants.O_NOFOLLOW,
  );
  const info = fs.fstatSync(fd);
  if (!info.isDirectory()) throw new Error("not a directory");
  fs.fchmodSync(fd, 0o700);
  if ((fs.fstatSync(fd).mode & 0o777) !== 0o700) throw new Error("mode is not 0700");
  fs.closeSync(fd);
} catch (error) {
  if (fd !== undefined) {
    try { fs.closeSync(fd); } catch (_) {}
  }
  console.error(`Refusing unsafe private directory: ${directory}`);
  process.exit(1);
}
' "$directory"
}

ai_litellm_private_state_leaf_safe() {
  local state_path="${1:a}"
  ai_litellm_credential_directory_chain_trusted "${state_path:h}" || return 1
  node -e '
const fs = require("fs");
const path = process.argv[1];
try {
  const info = fs.lstatSync(path);
  if (info.isSymbolicLink() || !info.isFile()) process.exit(1);
} catch (error) {
  if (error.code !== "ENOENT") process.exit(1);
}
' "$state_path"
}

# Atomic private state writer. Content arrives on stdin, never argv. The
# random exclusive/no-follow staging file and directory fsync make PID/hash/
# timestamp publication resistant to symlink planting and partial writes.
ai_litellm_atomic_private_write() {
  local target_path="${1:a}"
  ai_litellm_credential_directory_chain_trusted "${target_path:h}" || return 1
  node -e '
const crypto = require("crypto");
const fs = require("fs");
const p = require("path");
const target = process.argv[1];
const content = fs.readFileSync(0);
const staged = `${target}.tmp.${process.pid}.${crypto.randomBytes(16).toString("hex")}`;
let fd;
let dirfd;
try {
  try {
    const current = fs.lstatSync(target);
    if (current.isSymbolicLink() || !current.isFile()) throw new Error("unsafe target");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  fd = fs.openSync(
    staged,
    fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW,
    0o600,
  );
  fs.fchmodSync(fd, 0o600);
  fs.writeFileSync(fd, content);
  fs.fsyncSync(fd);
  fs.closeSync(fd);
  fd = undefined;
  fs.renameSync(staged, target);
  dirfd = fs.openSync(p.dirname(target), fs.constants.O_RDONLY | fs.constants.O_DIRECTORY);
  fs.fsyncSync(dirfd);
  fs.closeSync(dirfd);
  dirfd = undefined;
} catch (error) {
  if (fd !== undefined) try { fs.closeSync(fd); } catch (_) {}
  if (dirfd !== undefined) try { fs.closeSync(dirfd); } catch (_) {}
  try { fs.unlinkSync(staged); } catch (_) {}
  process.exit(1);
}
' "$target_path"
}

ai_litellm_proxy_state_paths_safe() {
  local state_path
  ai_litellm_private_directory_prepare "$AI_LITELLM_STATE_HOME" || return 1
  ai_litellm_private_directory_prepare "$AI_LITELLM_PROXY_HOME" || return 1
  for state_path in "$AI_LITELLM_LOG_FILE" "$AI_LITELLM_PID_FILE" \
    "$AI_LITELLM_CONFIG_HASH_FILE" "$AI_LITELLM_STARTED_AT_FILE"; do
    [[ "${state_path:h:A}" == "${AI_LITELLM_PROXY_HOME:A}" ]] || return 1
    ai_litellm_private_state_leaf_safe "$state_path" || {
      echo "Refusing unsafe proxy state path: $state_path" >&2
      return 1
    }
  done
}

# User model/settings overlays are writable state. Keep both below one trusted
# lexical root and reject symlinks in the root, any nested parent, or either
# leaf before a lock holder or renderer can touch them.
ai_litellm_user_config_paths_trusted() {
  local root="${AI_LITELLM_USER_CONFIG_HOME:a}"
  local models="${AI_LITELLM_USER_MODELS:a}"
  local settings="${AI_LITELLM_USER_CLAUDE_SETTINGS:a}"
  local config_path

  [[ "$models" == "$root"/* && "$settings" == "$root"/* ]] || {
    echo "Refusing user configuration path outside $root" >&2
    return 1
  }
  ai_litellm_credential_directory_chain_trusted "$root" || {
    echo "Refusing unsafe user configuration directory: $root" >&2
    return 1
  }
  for config_path in "$models" "$settings"; do
    ai_litellm_credential_directory_chain_trusted "${config_path:h}" || {
      echo "Refusing unsafe user configuration parent: ${config_path:h}" >&2
      return 1
    }
    if [[ -e "$config_path" || -L "$config_path" ]]; then
      [[ -f "$config_path" && ! -L "$config_path" && \
         "$(stat -f %Lp "$config_path" 2>/dev/null)" == "600" ]] || {
        echo "Refusing unsafe user configuration file: $config_path" >&2
        return 1
      }
    fi
  done
}

ai_litellm_user_config_paths_prepare() {
  ai_litellm_user_config_paths_trusted || return 1
  ai_litellm_private_directory_prepare "$AI_LITELLM_USER_CONFIG_HOME" || return 1
  ai_litellm_user_config_paths_trusted
}

ai_litellm_credential_env_path_trusted() {
  local role="$1" env_file="${2:a}" trusted_root
  local package_home="${AI_LITELLM_HOME:a}"
  local state_home="${AI_LITELLM_STATE_HOME:a}"
  local proxy_home="${AI_LITELLM_PROXY_HOME:a}"

  case "$role" in
    primary)
      [[ "$state_home" == "$package_home"/* && \
         "$proxy_home" == "$state_home"/* && \
         "$env_file" == "$proxy_home"/* ]] || return 1
      trusted_root="${env_file:h}"
      ;;
    legacy-ai-litellm)
      trusted_root="${HOME:a}/.config/ai-litellm"
      [[ "$env_file" == "$trusted_root/env" ]] || return 1
      ;;
    legacy-claude-litellm)
      trusted_root="${HOME:a}/.config/claude-litellm"
      [[ "$env_file" == "$trusted_root/env" ]] || return 1
      ;;
    *) return 1 ;;
  esac

  ai_litellm_credential_directory_chain_trusted "$trusted_root"
}

ai_litellm_env_value() {
  local key="$1"
  [[ "$key" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]] || {
    echo "Invalid env key: $key" >&2
    return 1
  }

  local env_file role rc index
  local -a env_files env_roles
  env_files=("$AI_LITELLM_ENV" "$AI_LITELLM_LEGACY_ENV" "$AI_LITELLM_LEGACY_CLAUDE_ENV")
  env_roles=(primary legacy-ai-litellm legacy-claude-litellm)
  for index in {1..3}; do
    env_file="${env_files[$index]}"
    role="${env_roles[$index]}"
    [[ -e "$env_file" || -L "$env_file" ]] || continue
    ai_litellm_credential_env_path_trusted "$role" "$env_file" || {
      echo "Refusing credential file with an unsafe parent chain: $env_file" >&2
      return 1
    }
    node -e '
const fs = require("fs");
const file = process.argv[1];
const wanted = process.argv[2];
let fd;
try {
  // O_NOFOLLOW closes the lstat/open race on the credential leaf. Validate the
  // opened descriptor rather than trusting path metadata checked earlier.
  fd = fs.openSync(
    file,
    fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
  );
  const info = fs.fstatSync(fd);
  if (!info.isFile() || (info.mode & 0o777) !== 0o600) {
    console.error(`Refusing unsafe credential file (expected regular mode 0600): ${file}`);
    process.exit(2);
  }
} catch (error) {
  console.error(`Refusing unsafe credential file: ${file}`);
  process.exit(2);
}
let lines;
try {
  lines = fs.readFileSync(fd, "utf8").split(/\r?\n/);
  fs.closeSync(fd);
} catch (error) {
  if (fd !== undefined) {
    try { fs.closeSync(fd); } catch (_) {}
  }
  console.error(`Cannot read credential file: ${file}`);
  process.exit(2);
}
for (const line of lines) {
  if (!line.trim() || /^\s*#/.test(line)) continue;
  // This is a key/value data file, not shell source. Preserve every byte after
  // the first '=' (including quotes and leading/trailing spaces). `export` is
  // accepted only as a legacy line prefix; it is never evaluated.
  const match = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
  if (!match || match[1] !== wanted) continue;
  const value = match[2];
  if (!value) process.exit(3);
  process.stdout.write(value + "\n");
  process.exit(0);
}
// Exit 3 is the sole non-integrity miss. The caller may consult a lower-
// priority legacy file only for this explicit "key absent" result.
process.exit(3);
' "$env_file" "$key" && return 0
    rc=$?
    (( rc == 3 )) && continue
    # An existing candidate that cannot be opened, validated, or parsed is an
    # integrity error. Never silently fall back to a lower-priority credential.
    return 1
  done
  return 1
}

ai_litellm_env_set_value() {
  local key="$1"
  local value="$2"

  case "$key" in
    [A-Za-z_]*)
      ;;
    *)
      echo "Invalid env key: $key" >&2
      return 1
      ;;
  esac
  if [[ "$key" == *[^A-Za-z0-9_]* ]]; then
    echo "Invalid env key: $key" >&2
    return 1
  fi
  if [[ -z "$value" ]]; then
    echo "Refusing to store an empty value for $key" >&2
    return 1
  fi
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "Refusing to store multiline value for $key" >&2
    return 1
  fi

  ai_litellm_credential_env_path_trusted primary "$AI_LITELLM_ENV" || {
    echo "Refusing credential file with an unsafe parent chain: $AI_LITELLM_ENV" >&2
    return 1
  }
  ai_litellm_private_directory_prepare "$AI_LITELLM_STATE_HOME" || return 1
  ai_litellm_private_directory_prepare "$AI_LITELLM_PROXY_HOME" || return 1
  # Revalidate after mkdir so a concurrently materialized component cannot be
  # used without passing the same no-symlink policy.
  ai_litellm_credential_env_path_trusted primary "$AI_LITELLM_ENV" || {
    echo "Refusing credential file with an unsafe parent chain: $AI_LITELLM_ENV" >&2
    return 1
  }
  # Pass the secret to node via stdin, NOT as argv — argv is visible via `ps`.
  printf '%s' "$value" | node -e '
const fs = require("fs");
const [file, key] = process.argv.slice(1);
const value = fs.readFileSync(0, "utf8");
if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) throw new Error(`invalid env key: ${key}`);
if (/[\r\n]/.test(value)) throw new Error(`env value for ${key} contains a newline`);
let lines = [];
let sourceFd;
try {
  sourceFd = fs.openSync(
    file,
    fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
  );
  const sourceInfo = fs.fstatSync(sourceFd);
  if (!sourceInfo.isFile() || (sourceInfo.mode & 0o777) !== 0o600) {
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
  if (error.code !== "ENOENT") {
    console.error(`Refusing unsafe existing credential file: ${file}`);
    process.exit(2);
  }
}
let replaced = false;
const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const pattern = new RegExp(`^(\\s*(?:export\\s+)?)${escaped}=.*$`);
lines = lines.map((line) => {
  const match = line.match(pattern);
  if (!match) return line;
  replaced = true;
  return `${match[1] || ""}${key}=${value}`;
});
if (!replaced) lines.push(`${key}=${value}`);
const tmp = `${file}.tmp.${process.pid}`;
let tmpFd;
try {
  tmpFd = fs.openSync(
    tmp,
    fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW,
    0o600,
  );
  fs.fchmodSync(tmpFd, 0o600);
  fs.writeFileSync(tmpFd, lines.join("\n") + "\n", "utf8");
  fs.fsyncSync(tmpFd);
  fs.closeSync(tmpFd);
  tmpFd = undefined;
  fs.renameSync(tmp, file);
} catch (error) {
  if (tmpFd !== undefined) {
    try { fs.closeSync(tmpFd); } catch (_) {}
  }
  try { fs.unlinkSync(tmp); } catch (_) {}
  throw error;
}
' "$AI_LITELLM_ENV" "$key" || return $?
}

ai_litellm_keychain_value() {
  local service="$1"
  local account="$2"
  command -v security >/dev/null 2>&1 || return 1
  security find-generic-password -s "$service" -a "$account" -w 2>/dev/null
}

ai_litellm_keychain_service_for_env() {
  local var="$1"
  local service
  service="$(ai_litellm_json "secrets.$var.keychainService" 2>/dev/null || true)"
  if [[ -n "$service" ]]; then
    printf '%s\n' "$service"
    return 0
  fi
  case "$var" in
    OPENROUTER_API_KEY) printf '%s\n' "$OPENROUTER_KEYCHAIN_SERVICE" ;;
    LITELLM_MASTER_KEY) printf '%s\n' "$LITELLM_MASTER_KEYCHAIN_SERVICE" ;;
    *) printf '%s\n' "$(printf '%s' "$var" | tr 'A-Z_' 'a-z-')" ;;
  esac
}

ai_litellm_keychain_account_for_env() {
  local var="$1"
  local account
  account="$(ai_litellm_json "secrets.$var.keychainAccount" 2>/dev/null || true)"
  if [[ -n "$account" ]]; then
    printf '%s\n' "$account"
    return 0
  fi
  case "$var" in
    OPENROUTER_API_KEY) printf '%s\n' "$OPENROUTER_KEYCHAIN_ACCOUNT" ;;
    LITELLM_MASTER_KEY) printf '%s\n' "$LITELLM_MASTER_KEYCHAIN_ACCOUNT" ;;
    *) printf '%s\n' "$USER" ;;
  esac
}

ai_litellm_keychain_set_value() {
  local service="$1"
  local account="$2"
  local value="$3"
  command -v security >/dev/null 2>&1 || {
    echo "macOS Keychain command not found: security" >&2
    return 1
  }
  if [[ -z "$service" || -z "$account" ]]; then
    echo "Keychain service and account are required." >&2
    return 1
  fi
  if [[ -z "$value" ]]; then
    echo "Refusing to store an empty Keychain value." >&2
    return 1
  fi
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo "Refusing to store multiline Keychain value." >&2
    return 1
  fi

  # `security add-generic-password ... -w` does NOT read a password from stdin;
  # with no inline argument it opens a terminal prompt. Passing `-w <value>` or
  # `-X <hex>` directly would expose the credential in `ps`. Use security's
  # command-stdin mode instead: only `security -i` appears in argv, while the
  # command and hex-encoded credential travel through the pipe.
  #
  # macOS security(1) reports non-ASCII generic-password data as hex on a later
  # `find ... -w`, so fail explicitly instead of storing a value that this
  # gateway cannot round-trip. Provider API keys/tokens are printable ASCII;
  # use the private env file for any other byte format.
  local hex byte offset decimal
  hex="$(printf '%s' "$value" | od -An -v -tx1 | tr -d '[:space:]')" || return $?
  [[ -n "$hex" && "$hex" != *[^0-9a-f]* && $(( ${#hex} % 2 )) -eq 0 ]] || {
    echo "Could not encode the Keychain value safely." >&2
    return 1
  }
  for (( offset = 1; offset <= ${#hex}; offset += 2 )); do
    byte="${hex[$offset,$(( offset + 1 ))]}"
    decimal=$(( 16#$byte ))
    if (( decimal < 32 || decimal > 126 )); then
      echo "Keychain values must be printable ASCII; use --env-file for other bytes." >&2
      return 1
    fi
  done
  printf 'add-generic-password -U -s %q -a %q -X %s\n' \
    "$service" "$account" "$hex" | security -i >/dev/null
}

ai_litellm_openrouter_key() {
  if [[ -n "$OPENROUTER_API_KEY" ]]; then
    printf '%s\n' "$OPENROUTER_API_KEY"
    return 0
  fi

  ai_litellm_env_value OPENROUTER_API_KEY 2>/dev/null && return 0
  ai_litellm_keychain_value "$OPENROUTER_KEYCHAIN_SERVICE" "$OPENROUTER_KEYCHAIN_ACCOUNT"
}

ai_litellm_master_key() {
  if [[ -n "$LITELLM_MASTER_KEY" ]]; then
    printf '%s\n' "$LITELLM_MASTER_KEY"
    return 0
  fi

  ai_litellm_env_value LITELLM_MASTER_KEY 2>/dev/null && return 0
  ai_litellm_keychain_value "$LITELLM_MASTER_KEYCHAIN_SERVICE" "$LITELLM_MASTER_KEYCHAIN_ACCOUNT" && return 0

  local configured_key
  configured_key="$(ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
value = config.dig("general_settings", "master_key") rescue nil
puts value if value
' "$AI_LITELLM_CONFIG" 2>/dev/null)"

  if [[ -z "$configured_key" || "$configured_key" == os.environ/* ]]; then
    return 1
  fi

  printf '%s\n' "$configured_key"
}

ai_litellm_host() {
  ai_litellm_json server.host 2>/dev/null || printf '127.0.0.1\n'
}

ai_litellm_port() {
  ai_litellm_json server.port 2>/dev/null || printf '4000\n'
}

ai_litellm_base_url() {
  printf 'http://%s:%s\n' "$(ai_litellm_host)" "$(ai_litellm_port)"
}

ai_litellm_api_base_url() {
  printf '%s/v1\n' "$(ai_litellm_base_url)"
}

ai_litellm_curl_auth() {
  local master_key="$1"
  shift
  if [[ -n "$master_key" ]]; then
    if [[ "$master_key" == *$'\n'* || "$master_key" == *$'\r'* ]]; then
      echo "Refusing a LiteLLM master key containing a newline." >&2
      return 1
    fi
    # Read one raw header from stdin. Unlike `curl -K -`, this needs no config
    # quoting and cannot interpret quotes/backslashes in the key as directives;
    # unlike `-H <value>`, the credential never appears in process argv.
    printf 'Authorization: Bearer %s\n' "$master_key" | curl -H @- "$@"
  else
    curl "$@"
  fi
}

ai_litellm_model_names() {
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
Array(config["model_list"]).each do |entry|
  name = entry["model_name"]
  puts name if name
end
' "$AI_LITELLM_CONFIG"
}

ai_litellm_model_resolve() {
  local requested="$1"
  [[ -n "$requested" ]] || return 1
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
target = ARGV[1].to_s
entries = Array(config["model_list"])
backend = ->(entry) { entry.dig("litellm_params", "model").to_s }
normalize = ->(value) { value.to_s.sub(%r{\Aopenrouter/}, "") }

match =
  entries.find { |entry| entry["model_name"].to_s == target } ||
  entries.find { |entry| backend.call(entry) == target } ||
  entries.find { |entry| normalize.call(backend.call(entry)) == target }

exit 1 unless match && match["model_name"]
puts match["model_name"]
' "$AI_LITELLM_CONFIG" "$requested"
}

ai_litellm_model_exists() {
  local model_name="$1"
  ai_litellm_model_resolve "$model_name" >/dev/null 2>&1
}

ai_litellm_model_backend() {
  local model_name="$1"
  model_name="$(ai_litellm_model_resolve "$model_name" 2>/dev/null)" || return 1
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
target = ARGV[1]
models = Array(config["model_list"]).select { |entry| entry["model_name"] == target }
backends = models.map { |entry| entry.dig("litellm_params", "model") }.compact
exit 1 if backends.empty?
puts backends.join(",")
' "$AI_LITELLM_CONFIG" "$model_name"
}

ai_litellm_model_api_base() {
  local model_name="$1"
  model_name="$(ai_litellm_model_resolve "$model_name" 2>/dev/null)" || return 1
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
target = ARGV[1]
entry = Array(config["model_list"]).find { |e| e["model_name"] == target }
base = entry && entry.dig("litellm_params", "api_base")
exit 1 if base.to_s.empty?
puts base
' "$AI_LITELLM_CONFIG" "$model_name"
}

ai_litellm_litellm_setting() {
  local key="$1"
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
value = config.dig("litellm_settings", ARGV[1]) rescue nil
exit 1 if value.nil?
puts value
' "$AI_LITELLM_CONFIG" "$key"
}

ai_litellm_litellm_python() {
  local managed="$AI_LITELLM_HOME/runtime/venv/bin/python"
  if [[ -x "$managed" ]] && ai_litellm_python_isolated "$managed" -c '
import importlib.metadata as metadata, sys
assert sys.version_info[:2] == (3, 13)
assert metadata.version("litellm") == "1.92.0"
assert metadata.version("prisma") == "0.15.0"
import fastapi, litellm, prisma, uvicorn, yaml
import litellm.proxy.proxy_cli
' >/dev/null 2>&1; then
    printf '%s\n' "$managed"
    return 0
  fi

  # An installed product is pinned and fail-closed. Never let a damaged venv
  # silently switch to an unrelated ambient LiteLLM/Python implementation.
  if [[ -e "$AI_LITELLM_HOME/install-manifest.json" || -L "$AI_LITELLM_HOME/install-manifest.json" ]]; then
    return 1
  fi

  local litellm_bin shebang python_candidate
  litellm_bin="$(command -v litellm 2>/dev/null)" || return 1
  if [[ -f "$litellm_bin" ]]; then
    shebang="$(head -n 1 "$litellm_bin" 2>/dev/null || true)"
    if [[ "$shebang" == '#!'* ]]; then
      python_candidate="${shebang#\#!}"
      python_candidate="${python_candidate%% *}"
      if [[ -x "$python_candidate" ]]; then
        printf '%s\n' "$python_candidate"
        return 0
      fi
    fi
  fi

  if python3 -I -B -c 'import litellm' >/dev/null 2>&1; then
    printf 'python3\n'
    return 0
  fi

  return 1
}

# Combine package-owned defaults with durable user-owned model and Claude alias
# overlays. Installed packages keep the immutable inputs as *.base files and
# expose generated effective files at the historical paths consumed by LiteLLM
# and Claude Code. A checkout has no *.base files; it may validate defaults but
# must never apply a user's installed overlays into source-controlled files.
ai_litellm_render_user_config() {
  local mode="${1:-}"
  case "$mode" in
    ""|--check|--validate-only) ;;
    *) echo "Unknown user-config render mode: $mode" >&2; return 1 ;;
  esac
  ai_litellm_user_config_paths_trusted || return 1

  if [[ "$AI_LITELLM_BASE_CONFIG" == "$AI_LITELLM_CONFIG" || \
        "$AI_LITELLM_BASE_CLAUDE_SETTINGS" == "$AI_LITELLM_EFFECTIVE_CLAUDE_SETTINGS" ]]; then
    if [[ -f "$AI_LITELLM_USER_MODELS" || -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" ]]; then
      echo "User overlays require an installed claude-litellm package; refusing to render them into source defaults." >&2
      return 1
    fi
    return 0
  fi

  [[ -f "$AI_LITELLM_BASE_CONFIG" ]] || {
    echo "Missing package base model config: $AI_LITELLM_BASE_CONFIG" >&2
    return 1
  }
  [[ -f "$AI_LITELLM_BASE_CLAUDE_SETTINGS" ]] || {
    echo "Missing package base Claude settings: $AI_LITELLM_BASE_CLAUDE_SETTINGS" >&2
    return 1
  }
  [[ -f "$AI_LITELLM_CONFIG_RENDERER" ]] || {
    echo "Missing user config renderer: $AI_LITELLM_CONFIG_RENDERER" >&2
    return 1
  }

  local python
  python="$(ai_litellm_litellm_python 2>/dev/null)" || {
    echo "Missing managed LiteLLM Python runtime; reinstall claude-litellm." >&2
    return 1
  }
  local -a args
  args=(
    "$AI_LITELLM_CONFIG_RENDERER"
    --base-config "$AI_LITELLM_BASE_CONFIG"
    --effective-config "$AI_LITELLM_CONFIG"
    --user-models "$AI_LITELLM_USER_MODELS"
    --base-settings "$AI_LITELLM_BASE_CLAUDE_SETTINGS"
    --effective-settings "$AI_LITELLM_EFFECTIVE_CLAUDE_SETTINGS"
    --settings-override "$AI_LITELLM_USER_CLAUDE_SETTINGS"
  )
  [[ -n "$mode" ]] && args+=("$mode")
  ai_litellm_python_isolated "$python" "${args[@]}"
}

# Compare both generated effective files with the deterministic render while no
# model/alias writer can interleave the two reads.  A sync that already owns the
# mutation lock may call the start path recursively, so retain its lock instead
# of releasing a descriptor owned by the caller.
ai_litellm_effective_config_current() {
  local preowned=0 rc=0
  [[ "${AI_LITELLM_USER_MUTATION_FD:-}" == <-> ]] && preowned=1
  ai_litellm_user_mutation_lock_acquire || return 1
  ai_litellm_render_user_config --check >/dev/null || rc=$?
  (( preowned )) || ai_litellm_user_mutation_lock_release
  return $rc
}

# Resolve the per-model token limits from the single source (litellm_config.yaml
# model_info, anchors already expanded by the YAML parser). Prints JSON
# {"context":N,"output":M} for the given surface model_name, or exits 1 when the
# model has no model_info.max_input_tokens. This is the one reader every harness
# generator/launcher derives from.
ai_litellm_model_limits() {
  local model_name="$1"
  model_name="$(ai_litellm_model_resolve "$model_name" 2>/dev/null)" || return 1
  ai_litellm_ruby -ryaml -rjson -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
target = ARGV[1]
entry = Array(config["model_list"]).find { |e| e["model_name"] == target }
exit 1 if entry.nil?
mi = entry["model_info"] || {}
ctx = mi["max_input_tokens"]
out = mi["max_output_tokens"]
exit 1 if ctx.nil?
result = {"context" => ctx}
result["output"] = out unless out.nil?
puts JSON.generate(result)
' "$AI_LITELLM_CONFIG" "$model_name"
}

# Resolve a harness-specific output reservation from the descriptor. This is
# intentionally separate from model_info.max_output_tokens, which is a capability
# ceiling. The reservation is what a harness should ask the provider to reserve
# on each request when the provider accounts input + reserved output together.
ai_litellm_harness_output_budget() {
  local harness="$1"
  local selection="$2"
  local model_name="$3"
  local descriptor limits
  descriptor="$(ai_litellm_harness_descriptor "$harness")" || return 1
  limits="$(ai_litellm_model_limits "$model_name" 2>/dev/null)" || return 1

  node -e '
const fs = require("fs");
const descriptor = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const selection = process.argv[2] || "";
const model = process.argv[3] || "";
const limits = JSON.parse(process.argv[4] || "{}");
const policy = descriptor.adapterConfig?.outputReservation || {};

const positiveInt = (value) => {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : null;
};
const pick = (candidates) => {
  for (const [source, value] of candidates) {
    const n = positiveInt(value);
    if (n != null) return {source, value: n};
  }
  return null;
};

const context = positiveInt(limits.context);
const capability = positiveInt(limits.output);
const configuredHeadroom = positiveInt(policy.tokenizerHeadroom) ?? 0;
const configuredMinimumInput = positiveInt(policy.minimumInput) ?? 32768;
let chosen = pick([
  [`adapterConfig.outputReservation.perSelection.${selection}`, policy.perSelection?.[selection]],
  [`adapterConfig.outputReservation.perTier.${selection}`, policy.perTier?.[selection]],
  [`adapterConfig.outputReservation.perModel.${model}`, policy.perModel?.[model]],
  ["adapterConfig.outputReservation.default", policy.default],
]);

if (!chosen) {
  if (capability == null) process.exit(1);
  chosen = {source: "capability-clamped-default", value: Math.min(capability, 32000)};
}

let reservation = chosen.value;
let source = chosen.source;
if (capability != null && reservation > capability) {
  reservation = capability;
  source += "+capabilityClamp";
}
let headroom = configuredHeadroom;
let minimumInput = configuredMinimumInput;
if (context != null) {
  headroom = Math.min(headroom, Math.floor(context * 0.1));
  minimumInput = Math.min(minimumInput, Math.max(1, Math.floor(context * 0.5)));
  const maxReservationForMinimumInput = context - headroom - minimumInput;
  if (maxReservationForMinimumInput < 1) {
    reservation = 1;
    headroom = Math.max(0, context - minimumInput - reservation);
    source += "+tinyWindowClamp";
  } else if (reservation > maxReservationForMinimumInput) {
    reservation = maxReservationForMinimumInput;
    source += "+minimumInputClamp";
  }
}

const effectiveInput = context == null ? null : Math.max(0, context - reservation - headroom);
console.log(JSON.stringify({
  context,
  capability,
  reservation,
  tokenizerHeadroom: headroom,
  minimumInput,
  effectiveInput,
  source,
}));
' "$descriptor" "$selection" "$model_name" "$limits"
}

# Emit the full surface model_name -> max_input_tokens map (JSON) from the single
# source. Harness budget rendering and diagnostics both consume
# this so the derivation logic lives in exactly one place.
ai_litellm_limits_map() {
  ai_litellm_ruby -ryaml -rjson -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
out = {}
Array(config["model_list"]).each do |e|
  mi = e["model_info"] || {}
  next unless mi["max_input_tokens"]
  out[e["model_name"]] = mi["max_input_tokens"]
end
puts JSON.generate(out)
' "$AI_LITELLM_CONFIG"
}

ai_litellm_harness_descriptor() {
  local harness="$1"
  case "$harness" in
    ""|*[!A-Za-z0-9_-]*|[-_]*) return 1 ;;
  esac
  if [[ "${AI_LITELLM_INSTALLED_MODE:-0}" == "1" && "$harness" != "claude" ]]; then
    return 1
  fi
  local descriptor_path="$AI_LITELLM_HARNESSES_DIR/$harness.json"
  [[ "${descriptor_path:h:A}" == "${AI_LITELLM_HARNESSES_DIR:A}" ]] || return 1
  [[ -f "$descriptor_path" && ! -L "$descriptor_path" ]] || return 1
  printf '%s\n' "$descriptor_path"
}

ai_litellm_harness_json() {
  local harness="$1"
  local json_path="$2"
  local descriptor
  descriptor="$(ai_litellm_harness_descriptor "$harness")" || return 1
  if [[ "$harness" == "claude" && \
        ( "$json_path" == "adapterConfig.reasoning.effort" || \
          "$json_path" == "adapterConfig.generatedSettings.permissions.defaultMode" ) && \
        ( -e "$AI_LITELLM_USER_CLAUDE_SETTINGS" || -L "$AI_LITELLM_USER_CLAUDE_SETTINGS" ) ]]; then
    local override rc
    override="$(node -e '
const fs = require("fs");
const file = process.argv[1];
const jsonPath = process.argv[2];
let fd;
let raw;
try {
  fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  const stat = fs.fstatSync(fd);
  if (!stat.isFile() || (stat.mode & 0o777) !== 0o600) throw new Error("unsafe mode or type");
  raw = fs.readFileSync(fd, "utf8");
} catch (_) {
  console.error(`Unsafe Claude user override: ${file}`);
  process.exit(1);
} finally {
  if (fd !== undefined) try { fs.closeSync(fd); } catch (_) {}
}
const payload = JSON.parse(raw);
if ((payload.schemaVersion ?? 1) !== 1) {
  console.error("unsupported Claude user override schemaVersion");
  process.exit(1);
}
const field = jsonPath === "adapterConfig.reasoning.effort"
  ? "reasoningEffort"
  : "permissionMode";
const allowed = field === "reasoningEffort"
  ? ["auto", "low", "medium", "high", "xhigh", "max"]
  : ["default", "bypassPermissions"];
const value = payload?.harness?.[field];
if (value === undefined) process.exit(2);
if (typeof value !== "string" || !value) {
  console.error(`Unsupported Claude harness ${field}: expected a non-empty string`);
  process.exit(1);
}
if (!allowed.includes(value)) {
  console.error(`Unsupported Claude harness ${field}: ${value}`);
  process.exit(1);
}
process.stdout.write(value);
' "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$json_path")"
    rc=$?
    if (( rc == 0 )); then
      printf '%s\n' "$override"
      return 0
    elif (( rc != 2 )); then
      return $rc
    fi
  fi
  ai_litellm_json_file "$descriptor" "$json_path"
}

ai_litellm_harness_json_array() {
  local harness="$1"
  local json_path="$2"
  local descriptor
  descriptor="$(ai_litellm_harness_descriptor "$harness")" || return 1
  ai_litellm_json_array "$descriptor" "$json_path"
}

ai_litellm_harness_alias_json() {
  local harness="${1:-claude}"
  local settings
  settings="$(ai_litellm_harness_json "$harness" paths.settings 2>/dev/null)" || { printf '[]'; return 0; }
  [[ -f "$settings" ]] || { printf '[]'; return 0; }
  local tiers
  tiers="$(ai_litellm_harness_json_array "$harness" models.tiers 2>/dev/null)"
  ai_litellm_ruby -rjson -e '
    settings = JSON.parse(File.read(ARGV[0])) rescue {}
    tiers = ARGV[1].to_s.split("\n").reject(&:empty?)
    al = settings["aliases"] || {}
    dn = settings["displayNames"] || {}; out = []
    tiers.each do |t|
      out << {"tier" => t, "model" => al[t], "label" => dn[t]}
    end
    puts JSON.generate(out)
  ' "$settings" "$tiers" 2>/dev/null || printf '[]'
}

ai_litellm_harness_alias_set() {
  local harness="${1:-}" tier="${2:-}" model="${3:-}"
  if [[ -z "$harness" || -z "$tier" || -z "$model" ]]; then
    echo "Usage: claude-litellm harness alias set <harness> <tier> <model_name>" >&2
    return 1
  fi
  local settings
  settings="$(ai_litellm_harness_json "$harness" paths.settings 2>/dev/null)" || { echo "No settings for harness: $harness" >&2; return 1; }
  # Defense-in-depth, matching the launch paths: refuse an un-rendered placeholder
  # path (run-from-checkout footgun). The token is __AI_LITELLM_HOME__, never __HOME__,
  # so this can never resolve to a native harness config.
  ai_litellm_assert_rendered_path "$settings" "harness settings" || return $?
  if [[ "$harness" != "claude" ]]; then
    echo "User alias overlays are currently supported only for the Claude harness." >&2
    return 1
  fi
  case "$tier" in
    fable|opus|sonnet|haiku) ;;
    *) echo "Unknown Claude tier: $tier" >&2; return 1 ;;
  esac
  if [[ -e "$AI_LITELLM_USER_CLAUDE_SETTINGS" && \
        ( ! -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" || -L "$AI_LITELLM_USER_CLAUDE_SETTINGS" ) ]]; then
    echo "Refusing unsafe Claude settings override path: $AI_LITELLM_USER_CLAUDE_SETTINGS" >&2
    return 1
  fi
  local owns_lock=0 lock_path="$AI_LITELLM_USER_CONFIG_HOME/.mutation.lock"
  if [[ ! -d "$lock_path" || "$(<"$lock_path/pid" 2>/dev/null || true)" != "$$" ]]; then
    ai_litellm_user_mutation_lock_acquire || return 1
    owns_lock=1
  fi
  local backup existed=0 rc=0
  backup="$(mktemp "${TMPDIR:-/tmp}/claude-litellm-alias.json.XXXXXX")" || {
    (( owns_lock )) && ai_litellm_user_mutation_lock_release
    return 1
  }
  if [[ -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" ]]; then
    cp -p "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$backup"
    existed=1
  fi
  ai_litellm_ruby -rjson -ryaml -e '# encoding: utf-8
    config_path, settings_path, override_path, tier, model = ARGV
    settings = JSON.parse(File.read(settings_path))
    cfg = (YAML.load_file(config_path, aliases: true) rescue YAML.load_file(config_path)) rescue {"model_list"=>[]}
    entry = Array(cfg["model_list"]).find { |e| e["model_name"].to_s == model }
    abort("Unknown LiteLLM model_name: #{model}") unless entry
    backend = entry.dig("litellm_params", "model").to_s
    provider = backend.split("/", 2).first
    payload = if File.file?(override_path)
      JSON.parse(File.read(override_path))
    else
      {"schemaVersion" => 1, "settings" => {}}
    end
    abort("unsupported Claude settings override schemaVersion") unless payload.fetch("schemaVersion", 1) == 1
    overrides = (payload["settings"] ||= {})
    (overrides["aliases"] ||= {})[tier] = model
    name, _sep, suffix = model.rpartition("-")
    name = model if name.empty?      # model_name without a trailing -<x>
    label = "#{name} (#{suffix.empty? ? provider : suffix})"
    (overrides["displayNames"] ||= {})[tier] = label
    tmp = "#{override_path}.tmp.#{$$}"
    begin
      File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.pretty_generate(payload) + "\n")
        file.flush
        file.fsync
      end
      File.rename(tmp, override_path)
    ensure
      File.delete(tmp) if File.exist?(tmp)
    end
  ' "$AI_LITELLM_CONFIG" "$settings" "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$tier" "$model" || rc=$?
  if (( rc == 0 )); then
    ai_litellm_render_user_config >/dev/null || rc=$?
  fi
  if (( rc != 0 )); then
    (( existed )) && cp -p "$backup" "$AI_LITELLM_USER_CLAUDE_SETTINGS" || rm -f "$AI_LITELLM_USER_CLAUDE_SETTINGS"
    ai_litellm_render_user_config >/dev/null 2>&1 || true
  fi
  rm -f "$backup"
  (( owns_lock )) && ai_litellm_user_mutation_lock_release
  (( rc == 0 )) || return $rc
  echo "Set $harness $tier -> $model"
  echo "Run 'claude-litellm sync' to apply it to the running proxy."
}

# The proxy --settings file is generated state, so a durable permission choice
# lives beside the other private Claude harness overrides rather than in the
# generated overlay or the user's native ~/.claude/settings.json. The package
# default remains "default"; bypassPermissions is accepted only as an explicit
# opt-in and is applied to newly launched claude-litellm sessions.
ai_litellm_permissions_slot_supported() {
  local defaults proxy_extra merged
  defaults="$(ai_litellm_harness_json claude adapterConfig.generatedSettings 2>/dev/null || true)"
  proxy_extra="$(ai_litellm_harness_json claude adapterConfig.generatedSettingsProxy 2>/dev/null || true)"
  if [[ -n "$defaults" && -n "$proxy_extra" ]]; then
    merged="$(jq -cn --argjson base "$defaults" --argjson extra "$proxy_extra" '$base * $extra')" || return 1
  else
    merged="${proxy_extra:-$defaults}"
  fi
  [[ -n "$merged" ]] || merged='{}'
  print -r -- "$merged" | jq -e '.permissions.defaultMode? != null' >/dev/null 2>&1
}

ai_litellm_permissions_require_supported() {
  ai_litellm_permissions_slot_supported || {
    echo "The Claude harness does not expose a generated permission-mode slot." >&2
    return 1
  }
}

ai_litellm_permissions_get() {
  local as_json=0
  (( $# <= 1 )) || {
    echo "Usage: claude-litellm permissions get [--json]" >&2
    return 1
  }
  case "${1:-}" in
    "") ;;
    --json) as_json=1 ;;
    *) echo "Usage: claude-litellm permissions get [--json]" >&2; return 1 ;;
  esac
  ai_litellm_permissions_require_supported || return 1

  # Serialize the two-part read with mutations so mode and provenance always
  # describe the same override snapshot.
  local preowned=0 rc=0 mode="" source="package-default"
  [[ "${AI_LITELLM_USER_MUTATION_FD:-}" == <-> ]] && preowned=1
  ai_litellm_user_mutation_lock_acquire || return 1
  mode="$(ai_litellm_harness_json claude adapterConfig.generatedSettings.permissions.defaultMode)" || rc=$?
  if (( rc == 0 )) && \
     [[ -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" && ! -L "$AI_LITELLM_USER_CLAUDE_SETTINGS" ]] && \
     jq -e '.harness.permissionMode? != null' "$AI_LITELLM_USER_CLAUDE_SETTINGS" >/dev/null 2>&1; then
    source="user-override"
  fi
  (( preowned )) || ai_litellm_user_mutation_lock_release
  (( rc == 0 )) || return $rc
  if (( as_json )); then
    jq -cn --arg mode "$mode" --arg source "$source" '{mode: $mode, source: $source}'
  else
    echo "Claude permission mode: $mode ($source)"
  fi
}

ai_litellm_permissions_update() {
  local operation="${1:-}" mode="${2:-}"
  case "$operation" in
    set)
      (( $# == 2 )) || { echo "Usage: claude-litellm permissions set <default|bypassPermissions>" >&2; return 1; }
      case "$mode" in
        default|bypassPermissions) ;;
        *) echo "Usage: claude-litellm permissions set <default|bypassPermissions>" >&2; return 1 ;;
      esac
      ;;
    reset) (( $# == 1 )) || { echo "Usage: claude-litellm permissions reset" >&2; return 1; } ;;
    *) echo "Usage: claude-litellm permissions set <default|bypassPermissions> | reset" >&2; return 1 ;;
  esac
  ai_litellm_permissions_require_supported || return 1

  ai_litellm_user_config_paths_trusted || return 1
  local descriptor
  descriptor="$(ai_litellm_harness_descriptor claude)" || {
    echo "Claude harness descriptor is unavailable." >&2
    return 1
  }
  ai_litellm_assert_rendered_path "$AI_LITELLM_USER_CLAUDE_SETTINGS" "Claude user settings override" || return $?

  local owns_lock=0
  if [[ "${AI_LITELLM_USER_MUTATION_FD:-}" != <-> ]]; then
    ai_litellm_user_mutation_lock_acquire || return 1
    owns_lock=1
  fi
  local backup existed=0 rc=0
  backup="$(mktemp "${TMPDIR:-/tmp}/claude-litellm-permissions.json.XXXXXX")" || {
    (( owns_lock )) && ai_litellm_user_mutation_lock_release
    return 1
  }
  if [[ -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" && ! -L "$AI_LITELLM_USER_CLAUDE_SETTINGS" ]]; then
    cp -p "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$backup" || {
      echo "Failed to create a rollback copy of the Claude settings override." >&2
      rm -f "$backup"
      (( owns_lock )) && ai_litellm_user_mutation_lock_release
      return 1
    }
    existed=1
  elif [[ -e "$AI_LITELLM_USER_CLAUDE_SETTINGS" || -L "$AI_LITELLM_USER_CLAUDE_SETTINGS" ]]; then
    echo "Refusing unsafe Claude settings override path: $AI_LITELLM_USER_CLAUDE_SETTINGS" >&2
    rm -f "$backup"
    (( owns_lock )) && ai_litellm_user_mutation_lock_release
    return 1
  fi

  node -e '
const fs = require("fs");
const [overrideFile, operation, mode = ""] = process.argv.slice(1);
const fail = (message) => { console.error(message); process.exit(1); };
let payload = {schemaVersion: 1, settings: {}};
if (fs.existsSync(overrideFile)) {
  let fd;
  try {
    fd = fs.openSync(overrideFile, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    const stat = fs.fstatSync(fd);
    if (!stat.isFile() || (stat.mode & 0o777) !== 0o600) throw new Error("unsafe mode or type");
    payload = JSON.parse(fs.readFileSync(fd, "utf8"));
  } catch (_) {
    fail(`Unsafe Claude user override: ${overrideFile}`);
  } finally {
    if (fd !== undefined) try { fs.closeSync(fd); } catch (_) {}
  }
}
if ((payload.schemaVersion ?? 1) !== 1) fail("unsupported Claude user override schemaVersion");
payload.schemaVersion = 1;
payload.settings ||= {};
payload.harness ||= {};
if (operation === "set") {
  if (!["default", "bypassPermissions"].includes(mode)) fail(`Unsupported Claude permission mode: ${mode}`);
  payload.harness.permissionMode = mode;
} else if (operation === "reset") {
  delete payload.harness.permissionMode;
  if (Object.keys(payload.harness).length === 0) delete payload.harness;
} else {
  fail(`Unsupported permission update operation: ${operation}`);
}
const tmp = `${overrideFile}.tmp.${process.pid}`;
try {
  const fd = fs.openSync(tmp, "wx", 0o600);
  try {
    fs.writeFileSync(fd, JSON.stringify(payload, null, 2) + "\n");
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, overrideFile);
} catch (error) {
  try { fs.unlinkSync(tmp); } catch (_) {}
  throw error;
}
' "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$operation" "$mode" || rc=$?

  if (( rc == 0 )); then
    ai_litellm_render_user_config >/dev/null || rc=$?
  fi
  if (( rc == 0 )); then
    ai_litellm_render_claude_settings claude >/dev/null || rc=$?
  fi
  if (( rc != 0 )); then
    local restore_rc=0
    if (( existed )); then
      cp -p "$backup" "$AI_LITELLM_USER_CLAUDE_SETTINGS" || restore_rc=1
    else
      rm -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" || restore_rc=1
    fi
    if (( restore_rc != 0 )); then
      echo "Failed to restore the Claude settings override after a permission update error." >&2
      rc=1
    fi
    ai_litellm_render_user_config >/dev/null 2>&1 || true
    ai_litellm_render_claude_settings claude >/dev/null 2>&1 || true
  fi
  rm -f "$backup"
  (( owns_lock )) && ai_litellm_user_mutation_lock_release
  (( rc == 0 )) || return $rc

  if [[ "$operation" == "reset" ]]; then
    echo "Reset Claude permission mode to the package default (default)."
  else
    echo "Updated Claude permission mode: $mode"
    if [[ "$mode" == "bypassPermissions" ]]; then
      echo "WARNING: new claude-litellm sessions will bypass all Claude Code permission checks." >&2
    fi
  fi
  echo "The change applies to new sessions and survives sync and reinstall."
}

ai_litellm_cmd_permissions() {
  local verb="${1:-get}"; [[ $# -gt 0 ]] && shift
  case "$verb" in
    get|status) ai_litellm_permissions_get "$@" ;;
    set)        ai_litellm_permissions_update set "$@" ;;
    reset)      ai_litellm_permissions_update reset "$@" ;;
    *) echo "Usage: claude-litellm permissions get [--json] | set <default|bypassPermissions> | reset" >&2; return 1 ;;
  esac
}

ai_litellm_harness_names() {
  [[ -d "$AI_LITELLM_HARNESSES_DIR" ]] || return 0
  local descriptor
  for descriptor in "$AI_LITELLM_HARNESSES_DIR"/*.json(N); do
    [[ "${descriptor:t}" == "schema.json" ]] && continue
    printf '%s\n' "${descriptor:t:r}"
  done
}

# Refuse to act on an un-rendered install placeholder. Harness descriptor paths
# carry install tokens (HOME / AI_LITELLM_HOME, each wrapped in double underscores)
# that scripts/install.zsh renders at install time; running a bin/ wrapper
# straight from a source checkout skips that rendering, so a literal placeholder
# directory would be created under the current directory (the stray run-from-
# checkout state-tree footgun). The installed package is already covered by
# check.zsh's placeholder grep; this guards the run-from-checkout path.
#
# The marker patterns are assembled from fragments on purpose: install.zsh would
# otherwise render the literal tokens in this very function and defeat the guard.
ai_litellm_assert_rendered_path() {
  local candidate_path="$1" context="${2:-path}"
  local us="__" home_marker fabric_marker
  home_marker="${us}HOME${us}"
  fabric_marker="${us}AI_LITELLM_HOME${us}"
  case "$candidate_path" in
  *"$fabric_marker"*|*"$home_marker"*)
    echo "claude-litellm: refusing to create un-rendered ${context}: ${candidate_path}" >&2
    echo "  A command was likely run from a source checkout instead of the installed package;" >&2
    echo "  run scripts/install.zsh and use the installed command under ~/.local/bin." >&2
    return 1
    ;;
  esac
  return 0
}

ai_litellm_harness_validate() {
  local harness="$1"
  local descriptor adapter schema
  descriptor="$(ai_litellm_harness_descriptor "$harness")" || {
    echo "Missing harness descriptor: $AI_LITELLM_HARNESSES_DIR/$harness.json" >&2
    return 1
  }
  schema="$AI_LITELLM_HARNESSES_DIR/schema.json"

  node -e '
const fs = require("fs");
const descriptor = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const schema = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const required = schema.required || [];
const adapterEnum = new Set(schema.properties?.adapter?.enum || []);
const errors = [];
const isObject = (value) => value && typeof value === "object" && !Array.isArray(value);
const hasString = (object, key) => typeof object?.[key] === "string" && object[key].length > 0;
const requireString = (object, key, label) => {
  if (!hasString(object, key)) errors.push(`${label}.${key} must be a non-empty string`);
};
const requireStringArray = (object, key, label, {allowEmpty = false} = {}) => {
  const value = object?.[key];
  if (!Array.isArray(value) || (!allowEmpty && value.length === 0) || value.some((item) => typeof item !== "string" || item.length === 0)) {
    errors.push(`${label}.${key} must be ${allowEmpty ? "an" : "a non-empty"} array of strings`);
  }
};
const requirePositiveInteger = (object, key, label) => {
  const value = object?.[key];
  if (!Number.isInteger(value) || value <= 0) errors.push(`${label}.${key} must be a positive integer`);
};
const missing = required.filter((key) => descriptor[key] == null);
if (missing.length) {
  errors.push(`missing descriptor fields: ${missing.join(", ")}`);
}
if (descriptor.schemaVersion !== 1) {
  errors.push(`unsupported schemaVersion: ${descriptor.schemaVersion}`);
}
if (!adapterEnum.has(descriptor.adapter)) {
  errors.push(`unsupported adapter: ${descriptor.adapter}`);
}
requireString(descriptor, "name", "descriptor");
requireString(descriptor, "adapter", "descriptor");
requireString(descriptor, "command", "descriptor");
if (!isObject(descriptor.paths)) errors.push("paths must be an object");
if (!isObject(descriptor.isolation)) errors.push("isolation must be an object");
requireString(descriptor.isolation || {}, "kind", "isolation");
requireString(descriptor.isolation || {}, "env", "isolation");
if (descriptor.isolation?.scrubEnv != null) requireStringArray(descriptor.isolation, "scrubEnv", "isolation", {allowEmpty: true});

const provider = descriptor.provider || {};
const auth = provider.auth || {};
if (descriptor.provider != null) {
  if (provider.auth != null) {
    requireString(auth, "mode", "provider.auth");
    requireString(auth, "env", "provider.auth");
    requireString(auth, "source", "provider.auth");
  }
}

const paths = descriptor.paths || {};
const models = descriptor.models || {};
const adapterConfig = descriptor.adapterConfig || {};
switch (descriptor.adapter) {
  case "claude-code":
    for (const key of ["home", "settings", "configDir", "settingsArgProxy"]) requireString(paths, key, "paths");
    requireString(auth, "env", "provider.auth");
    requireStringArray(models, "tiers", "models");
    for (const key of ["baseUrlEnv", "discoveryEnv", "tierModelEnvPrefix", "tierDisplayNameEnvPrefix", "autoCompactWindowEnv", "maxOutputTokensEnv"]) requireString(adapterConfig, key, "adapterConfig");
    if (!isObject(adapterConfig.outputReservation)) errors.push("adapterConfig.outputReservation must be an object");
    requirePositiveInteger(adapterConfig.outputReservation || {}, "default", "adapterConfig.outputReservation");
    requirePositiveInteger(adapterConfig.outputReservation || {}, "tokenizerHeadroom", "adapterConfig.outputReservation");
    requirePositiveInteger(adapterConfig.outputReservation || {}, "minimumInput", "adapterConfig.outputReservation");
    break;
}

if (errors.length) {
  for (const error of errors) console.error(error);
  process.exit(1);
}
' "$descriptor" "$schema" || return 1

  adapter="$(ai_litellm_harness_json "$harness" adapter 2>/dev/null)" || return 1
  [[ -n "$adapter" ]]
}

ai_litellm_harness_cli_available() {
  local harness="$1"
  local command
  command="$(ai_litellm_harness_json "$harness" command 2>/dev/null)" || return 1
  command -v "$command" >/dev/null 2>&1 || {
    echo "Harness command not available for $harness: $command" >&2
    return 1
  }
}

ai_litellm_harness_template_json() {
  local harness="$1"
  local json_path="$2"
  local value
  value="$(ai_litellm_harness_json "$harness" "$json_path")" || return 1
  ai_litellm_template_value "$value"
}

# Distinct os.environ/<VAR> references in the registry. Drives generic
# multi-provider secret injection (not just OpenRouter).
ai_litellm_config_env_refs() {
  [[ -f "$AI_LITELLM_CONFIG" ]] || return 1
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
seen = {}
walk = nil
walk = lambda do |o|
  case o
  when Hash then o.each_value { |v| walk.call(v) }
  when Array then o.each { |v| walk.call(v) }
  when String then seen[$1] = true if o =~ %r{\Aos\.environ/(.+)\z}
  end
end
walk.call(config)
seen.keys.sort.each { |k| puts k }
' "$AI_LITELLM_CONFIG"
}

ai_litellm_model_env_refs() {
  local model="$1"
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
entry = Array(config["model_list"]).find { |row| row["model_name"].to_s == ARGV[1] }
exit 1 unless entry
seen = {}
walk = nil
walk = lambda do |value|
  case value
  when Hash then value.each_value { |child| walk.call(child) }
  when Array then value.each { |child| walk.call(child) }
  when String then seen[$1] = true if value =~ %r{\Aos\.environ/([A-Za-z_][A-Za-z0-9_]*)\z}
  end
end
walk.call(entry["litellm_params"] || {})
seen.keys.sort.each { |name| puts name }
' "$AI_LITELLM_CONFIG" "$model"
}

ai_litellm_model_provider_credentials_ready() {
  local model="$1" env_name
  for env_name in "${(@f)$(ai_litellm_model_env_refs "$model" 2>/dev/null)}"; do
    [[ -n "$env_name" ]] || continue
    case "$env_name" in LITELLM_MASTER_KEY) continue ;; esac
    if ! ai_litellm_resolve_secret_var "$env_name" >/dev/null 2>&1; then
      echo "Missing provider credential $env_name for $model." >&2
      echo "Store it with: claude-litellm key set --keychain $env_name" >&2
      return 1
    fi
  done
}

# Resolve a provider secret env var without exporting it to the interactive shell.
# Order: inherited shell env, private env file, then macOS Keychain. Keychain service defaults to the
# downcased dash form (OPENAI_API_KEY -> openai-api-key); override per var via
# settings.json secrets.<VAR>.{keychainService,keychainAccount}.
ai_litellm_resolve_secret_var() {
  local var="$1"
  [[ -n "$var" ]] || return 1
  if [[ -n "${parameters[$var]:-}" ]]; then
    local inherited="${(P)var}"
    [[ -n "$inherited" ]] && { printf '%s\n' "$inherited"; return 0; }
  fi
  ai_litellm_env_value "$var" 2>/dev/null && return 0
  local service account
  service="$(ai_litellm_json "secrets.$var.keychainService" 2>/dev/null || true)"
  account="$(ai_litellm_json "secrets.$var.keychainAccount" 2>/dev/null || printf '%s' "$USER")"
  if [[ -z "$service" ]]; then
    case "$var" in
      OPENROUTER_API_KEY) service="$OPENROUTER_KEYCHAIN_SERVICE" ;;
      LITELLM_MASTER_KEY) service="$LITELLM_MASTER_KEYCHAIN_SERVICE" ;;
      *) service="$(printf '%s' "$var" | tr 'A-Z_' 'a-z-')" ;;
    esac
  fi
  ai_litellm_keychain_value "$service" "$account" 2>/dev/null && return 0
  return 1
}

# Run a command with a wall-clock timeout (macOS ships no `timeout`/`gtimeout`).
# perl's alarm survives exec; on expiry SIGALRM terminates the child, so a hung
# external binary can never hang a sync indefinitely.
# Returns the child's status, or a non-zero signal status on timeout.
ai_litellm_run_timeout() {
  local secs="$1"; shift
  perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "$secs" "$@"
}

ai_litellm_harness_exec_env() {
  local harness="$1"
  shift

  local -a scrub_names assignment_names assignment_values
  local scrub seen_scrubs=$'\n' static_scrubs
  static_scrubs="$(ai_litellm_harness_json_array "$harness" isolation.scrubEnv 2>/dev/null)" || {
    echo "Cannot read environment scrub policy for harness: $harness" >&2
    return 1
  }
  for scrub in "${(@f)static_scrubs}"; do
    [[ -n "$scrub" ]] || continue
    [[ "$scrub" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
      echo "Invalid environment name in harness scrub policy: $scrub" >&2
      return 1
    }
    if [[ "$seen_scrubs" != *$'\n'"$scrub"$'\n'* ]]; then
      scrub_names+=("$scrub")
      seen_scrubs+="$scrub"$'\n'
    fi
  done

  # User-registered providers can name arbitrary credential variables. Scrub
  # every credential reference in the effective registry from Claude Code and
  # all tools it launches, not only the static well-known provider list. A
  # malformed/unreadable registry fails closed instead of silently producing an
  # empty dynamic scrub list.
  local dynamic_scrubs
  dynamic_scrubs="$(ai_litellm_config_env_refs 2>/dev/null)" || {
    echo "Cannot derive provider credential scrub policy from the model registry." >&2
    return 1
  }
  for scrub in "${(@f)dynamic_scrubs}"; do
    [[ -n "$scrub" ]] || continue
    [[ "$scrub" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
      echo "Invalid environment name in model registry: $scrub" >&2
      return 1
    }
    if [[ "$seen_scrubs" != *$'\n'"$scrub"$'\n'* ]]; then
      scrub_names+=("$scrub")
      seen_scrubs+="$scrub"$'\n'
    fi
  done

  local assignment name value
  while (( $# > 0 )); do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    assignment="$1"
    [[ "$assignment" == *=* ]] || {
      echo "Invalid harness environment assignment (expected NAME=value): $assignment" >&2
      return 1
    }
    name="${assignment%%=*}"
    value="${assignment#*=}"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
      echo "Invalid harness environment assignment name: $name" >&2
      return 1
    }
    assignment_names+=("$name")
    assignment_values+=("$value")
    shift
  done

  (( $# > 0 )) || {
    echo "Missing harness command after --" >&2
    return 1
  }

  # Keep every unset/assignment in a child subshell and use only zsh builtins
  # before exec. Passing ANTHROPIC_AUTH_TOKEN=<master-key> (or another provider
  # secret) as an argument to /usr/bin/env exposes it briefly through process
  # argv even though the final Claude process receives it only as environment.
  (
    local index=1
    for scrub in "${scrub_names[@]}"; do
      unset "$scrub"
    done
    while (( index <= ${#assignment_names[@]} )); do
      export "${assignment_names[$index]}=${assignment_values[$index]}"
      (( index += 1 ))
    done
    exec "$@"
  )
}

ai_litellm_ensure_claude_settings_file() {
  local settings_path="$1"
  [[ -n "$settings_path" ]] || {
    echo "Missing Claude settings path." >&2
    return 1
  }

  local settings_dir tmp
  settings_dir="${settings_path:h}"
  ai_litellm_assert_rendered_path "$settings_dir" "Claude settings dir" || return 1
  mkdir -p "$settings_dir" || return 1

  if [[ -f "$settings_path" ]]; then
    jq empty "$settings_path" >/dev/null || {
      echo "Invalid Claude LiteLLM settings JSON: $settings_path" >&2
      return 1
    }
    chmod 600 "$settings_path" 2>/dev/null || true
    return 0
  fi

  tmp="${settings_path}.$$"
  {
    print -r -- "{"
    print -r -- "}"
  } >| "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$settings_path"
}

ai_litellm_render_settings_defaults() {
  local settings_path="$1"
  local defaults="$2"
  ai_litellm_ensure_claude_settings_file "$settings_path" || return $?
  [[ -n "$defaults" ]] || return 0

  local tmp
  tmp="${settings_path}.$$"
  # Recursive fill preserves user-owned settings. permissions.defaultMode is
  # policy-owned by the wrapper, so upgrades must overwrite stale manual edits
  # with the validated effective mode (the safe package default or an explicit
  # durable user override).
  jq --argjson defaults "$defaults" '
    def fill($d):
      if (type == "object") and ($d | type == "object") then
        reduce ($d | keys_unsorted[]) as $key (.;
          if has($key) then .[$key] = (.[$key] | fill($d[$key]))
          else .[$key] = $d[$key] end
        )
      else . end;
    fill($defaults)
    | if ($defaults.permissions.defaultMode? != null)
      then .permissions.defaultMode = $defaults.permissions.defaultMode
      else . end
  ' "$settings_path" >| "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$settings_path"
}

ai_litellm_write_generated_settings_exact() {
  local settings_path="$1" payload="$2" settings_dir tmp
  settings_dir="${settings_path:h}"
  ai_litellm_assert_rendered_path "$settings_dir" "generated Claude settings dir" || return 1
  if [[ -e "$settings_path" || -L "$settings_path" ]]; then
    [[ -f "$settings_path" && ! -L "$settings_path" ]] || {
      echo "Refusing unsafe generated Claude settings path: $settings_path" >&2
      return 1
    }
  fi
  mkdir -p "$settings_dir" || return 1
  chmod 700 "$settings_dir" 2>/dev/null || true
  tmp="$(mktemp "$settings_dir/.${settings_path:t}.XXXXXX")" || return 1
  print -r -- "$payload" | jq '.' >| "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$settings_path"
}

ai_litellm_render_claude_settings() {
  local harness="${1:-claude}"
  local settings_path="${2:-}"
  local proxy_settings_path="${3:-}"
  local defaults proxy_extra proxy_defaults permission_mode

  [[ -n "$settings_path" ]] || settings_path="$(ai_litellm_harness_json "$harness" paths.settingsArgProxy)" || return 1
  [[ -n "$proxy_settings_path" ]] || proxy_settings_path="$(ai_litellm_harness_json "$harness" paths.settingsArgProxy 2>/dev/null || true)"

  defaults="$(ai_litellm_harness_json "$harness" adapterConfig.generatedSettings 2>/dev/null || true)"
  [[ -n "$proxy_settings_path" ]] || proxy_settings_path="$settings_path"
  proxy_extra="$(ai_litellm_harness_json "$harness" adapterConfig.generatedSettingsProxy 2>/dev/null || true)"
  if [[ -n "$defaults" && -n "$proxy_extra" ]]; then
    proxy_defaults="$(jq -cn --argjson base "$defaults" --argjson extra "$proxy_extra" '$base * $extra')" || return 1
  else
    proxy_defaults="${proxy_extra:-$defaults}"
  fi
  [[ -n "$proxy_defaults" ]] || proxy_defaults='{}'
  # Only harness descriptors that declare the generated permission slot own it.
  # This keeps a descriptor with no generated-settings surface exactly empty
  # instead of inventing Claude-specific policy fields for it.
  if [[ "$harness" == "claude" ]] && \
     print -r -- "$proxy_defaults" | jq -e '.permissions.defaultMode? != null' >/dev/null 2>&1; then
    permission_mode="$(ai_litellm_harness_json "$harness" adapterConfig.generatedSettings.permissions.defaultMode)" || return $?
    proxy_defaults="$(jq -cn --argjson payload "$proxy_defaults" --arg mode "$permission_mode" \
      '$payload | .permissions.defaultMode = $mode')" || return 1
  fi
  # This is a package-generated --settings overlay, not the user's native
  # settings file. Rewrite the exact allowlisted payload every time so an old
  # or edited overlay cannot retain env/model/apiKeyHelper routing overrides.
  # `${value:-{}}` is not a safe way to express a literal JSON object in zsh:
  # the first `}` terminates the parameter expansion and the second becomes a
  # literal suffix, turning every non-empty payload into malformed `...}}`.
  ai_litellm_write_generated_settings_exact "$proxy_settings_path" "$proxy_defaults"
}

# Shared-environment layer: link user-scope environment artifacts (settings,
# plugins, skills, memory-free instruction files) from the harness's isolated
# config dir to the native config root, so both variants read and accrue the
# same environment while transcripts/auto-memory/history stay per-variant.
# Dangling links are intentional: they light up if the native file appears
# later, and they never create the native root themselves.
ai_litellm_shared_env_links_ensure() {
  local harness="$1"
  local config_dir="$2"
  [[ "${AI_LITELLM_SHARED_ENV:-1}" == "0" ]] && return 0
  [[ -n "$config_dir" ]] || return 1

  local target_root
  target_root="$(ai_litellm_harness_json "$harness" isolation.sharedEnvironment.targetRoot 2>/dev/null || true)"
  [[ -n "$target_root" ]] || return 0
  # -ef alone misses the not-yet-existing case and would create self-loop
  # symlinks inside the native root; compare textually as well.
  if [[ "${config_dir%/}" == "${target_root%/}" || "$config_dir" -ef "$target_root" ]]; then
    return 0
  fi

  ai_litellm_assert_rendered_path "$config_dir" "harness shared-env dir" || return $?
  mkdir -p "$config_dir" || return 1

  local item link target backup
  for item in "${(@f)$(ai_litellm_harness_json_array "$harness" isolation.sharedEnvironment.items 2>/dev/null)}"; do
    [[ -n "$item" && "$item" != /* && "$item" != *..* ]] || continue
    link="$config_dir/$item"
    target="$target_root/$item"
    if [[ -L "$link" ]]; then
      [[ "$(readlink -- "$link")" == "$target" ]] || ln -sfn -- "$target" "$link" || return 1
      continue
    fi
    if [[ -e "$link" ]]; then
      backup="$link.isolated.bak"
      [[ -e "$backup" ]] && backup="$backup.$(date +%s).$RANDOM"
      mv -- "$link" "$backup" || return 1
      echo "claude-litellm: moved isolated $item to ${backup:t} (now shared from $target_root)" >&2
    fi
    ln -s -- "$target" "$link" || return 1
  done
}

# Guard the shared settings surface: backend routing must only ever travel as
# per-invocation process env or the per-mode --settings overlay. A routing or
# model key in the shared user settings silently re-routes BOTH variants
# (settings env is applied over process env at startup), so fail hard.
ai_litellm_claude_shared_settings_lint() {
  local harness="${1:-claude}"
  local target_root="${2:-}"
  [[ "${AI_LITELLM_SHARED_ENV_LINT:-1}" == "0" ]] && return 0

  [[ -n "$target_root" ]] || target_root="$(ai_litellm_harness_json "$harness" isolation.sharedEnvironment.targetRoot 2>/dev/null || true)"
  [[ -n "$target_root" ]] || return 0

  local file bad model
  for file in "$target_root/settings.json" "$target_root/settings.local.json"; do
    [[ -f "$file" ]] || continue
    jq empty "$file" 2>/dev/null || {
      echo "claude-litellm: shared settings file is not valid JSON: $file" >&2
      return 1
    }
    bad="$(jq -r '(.env // {}) | keys[] | select(test("^(ANTHROPIC_(BASE_URL|BEDROCK_BASE_URL|VERTEX_BASE_URL|AUTH_TOKEN|API_KEY|MODEL|SMALL_FAST_MODEL|CUSTOM_MODEL|CUSTOM_HEADERS|DEFAULT_)|CLAUDE_CODE_(SUBAGENT_MODEL|ENABLE_GATEWAY_MODEL_DISCOVERY|AUTO_COMPACT_WINDOW|MAX_OUTPUT_TOKENS|ATTRIBUTION_HEADER|USE_BEDROCK|USE_VERTEX|SKIP_BEDROCK_AUTH|SKIP_VERTEX_AUTH|API_KEY_HELPER_TTL_MS)|AWS_BEARER_TOKEN_BEDROCK|OPENROUTER_|LITELLM_|HTTP_PROXY$|HTTPS_PROXY$|ALL_PROXY$|NO_PROXY$|http_proxy$|https_proxy$|all_proxy$|no_proxy$)"))' "$file" 2>/dev/null || true)"
    if [[ -n "$bad" ]]; then
      echo "claude-litellm: refusing to launch — shared $file env block carries backend routing keys that would override per-invocation routing for every variant:" >&2
      print -r -- "$bad" | sed 's/^/  - /' >&2
      echo "Move them into the generated overlay ($(ai_litellm_harness_json "$harness" paths.settingsArgProxy 2>/dev/null || printf 'overlay-settings-proxy.json')) or set AI_LITELLM_SHARED_ENV_LINT=0 to override." >&2
      return 1
    fi
    # A top-level apiKeyHelper runs a credential-minting command on every launch,
    # including the non-Anthropic lanes — its output would be sent as the key to
    # the proxy/OpenRouter backend, leaking the user's real Anthropic credential
    # to a third party. The env denylist above never sees it (it is not an env
    # key), so refuse it explicitly.
    if [[ "$(jq -r 'has("apiKeyHelper")' "$file" 2>/dev/null || echo false)" == "true" ]]; then
      echo "claude-litellm: refusing to launch — shared $file defines apiKeyHelper, which mints a credential for every variant (including non-Anthropic backends) and would leak it to the proxy. Move it into the generated overlay ($(ai_litellm_harness_json "$harness" paths.settingsArgProxy 2>/dev/null || printf 'overlay-settings-proxy.json')) or set AI_LITELLM_SHARED_ENV_LINT=0 to override." >&2
      return 1
    fi
    model="$(jq -r '.model // empty' "$file" 2>/dev/null || true)"
    if [[ -n "$model" ]] && { [[ "$model" == "~"* || "$model" == */* ]] || ai_litellm_model_exists "$model" 2>/dev/null; }; then
      echo "claude-litellm: warning — shared $file pins model '$model', which native claude will send verbatim to api.anthropic.com. Re-run /model in a native session to fix." >&2
    fi
  done
  return 0
}

ai_litellm_cli_arg_present() {
  local wanted="$1"
  shift

  local arg
  for arg in "$@"; do
    [[ "$arg" == "--" ]] && break
    [[ "$arg" == "$wanted" || "$arg" == "$wanted="* ]] && return 0
  done
  return 1
}

ai_litellm_harnesses() {
  local harness
  echo "claude-litellm harnesses"
  ai_litellm_harness_names | while IFS= read -r harness; do
    printf '  %s -> %s\n' "$harness" "$(ai_litellm_harness_json "$harness" adapter 2>/dev/null || printf 'unknown')"
  done
}

ai_litellm_harness_info() {
  local harness="$1"
  [[ -n "$harness" ]] || {
    ai_litellm_harnesses
    return 0
  }

  local descriptor
  descriptor="$(ai_litellm_harness_descriptor "$harness")" || {
    echo "Unknown harness: $harness" >&2
    return 1
  }

  echo "Harness:   $harness"
  echo "Descriptor:$descriptor"
  echo "Adapter:   $(ai_litellm_harness_json "$harness" adapter 2>/dev/null || printf 'unknown')"
  echo "Command:   $(ai_litellm_harness_json "$harness" command 2>/dev/null || printf 'unknown')"
  echo "Settings:  $(ai_litellm_harness_json "$harness" paths.settings 2>/dev/null || printf 'none')"
  echo "Isolation: $(ai_litellm_harness_json "$harness" isolation.kind 2>/dev/null || printf 'unknown')"
  echo "Base URL:  $(ai_litellm_harness_json "$harness" provider.baseUrl 2>/dev/null | sed "s#{{ai.baseUrl}}#$(ai_litellm_base_url)#; s#{{ai.apiBaseUrl}}#$(ai_litellm_api_base_url)#" || printf 'n/a')"
  ai_litellm_harness_validate "$harness" >/dev/null 2>&1 && echo "Status:    ok" || echo "Status:    invalid"
  ai_litellm_harness_cli_available "$harness" >/dev/null 2>&1 && echo "CLI:       installed" || echo "CLI:       not installed"
}

ai_litellm_harness_one_json() {
  local name="$1"
  local adapter command baseurl isolationenv valid="@bool:false" cli="@bool:false"
  adapter="$(ai_litellm_harness_json "$name" adapter 2>/dev/null || true)"
  command="$(ai_litellm_harness_json "$name" command 2>/dev/null || true)"
  baseurl="$(ai_litellm_harness_json "$name" provider.baseUrl 2>/dev/null || true)"
  [[ -n "$baseurl" ]] && baseurl="$(ai_litellm_template_value "$baseurl")"
  isolationenv="$(ai_litellm_harness_json "$name" isolation.env 2>/dev/null || true)"
  ai_litellm_harness_validate "$name" >/dev/null 2>&1 && valid="@bool:true"
  ai_litellm_harness_cli_available "$name" >/dev/null 2>&1 && cli="@bool:true"
  ai_litellm_emit_json \
    name "$name" adapter "${adapter:-}" command "${command:-}" \
    baseUrl "${baseurl:-}" isolationEnv "${isolationenv:-}" valid "$valid" cliInstalled "$cli"
}

ai_litellm_harnesses_json() {
  local first=1 name
  printf '['
  for name in $(ai_litellm_harness_names); do
    (( first )) || printf ','
    first=0
    ai_litellm_harness_one_json "$name"
  done
  printf ']'
}

ai_litellm_harness_info_json() {
  [[ -n "${1:-}" ]] || { printf '{}'; return 0; }
  ai_litellm_harness_one_json "$1"
}

ai_litellm_launch() {
  local harness="$1"
  [[ -n "$harness" ]] || {
    echo "Usage: claude-litellm launch <harness> [args...]" >&2
    return 1
  }
  shift

  ai_litellm_harness_validate "$harness" || return $?
  ai_litellm_harness_cli_available "$harness" || return $?
  local adapter
  adapter="$(ai_litellm_harness_json "$harness" adapter)" || return 1

  case "$adapter" in
    claude-code)
      CLAUDE_LITELLM_HARNESS="$harness" "$AI_LITELLM_BIN_DIR/claude-litellm" "$@"
      ;;
    *)
      echo "Unsupported harness adapter: $adapter" >&2
      return 1
      ;;
  esac
}

ai_litellm_runtime_names() {
  [[ -f "$AI_LITELLM_SETTINGS" ]] || return 1
  node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const name of Object.keys(settings.runtimes || {})) console.log(name);
' "$AI_LITELLM_SETTINGS"
}

ai_litellm_runtime_field() {
  local runtime="$1"
  local field="$2"
  ai_litellm_json "runtimes.$runtime.$field"
}

ai_litellm_runtime_expected_models() {
  local runtime="$1"
  [[ -f "$AI_LITELLM_SETTINGS" ]] || return 1
  node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const runtime = settings.runtimes && settings.runtimes[process.argv[2]];
if (!runtime) process.exit(1);
for (const model of runtime.expectedModels || []) console.log(model);
	' "$AI_LITELLM_SETTINGS" "$runtime"
}

ai_litellm_runtime_recommended_models() {
  local runtime="$1"
  [[ -f "$AI_LITELLM_SETTINGS" ]] || return 1
  node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const runtime = settings.runtimes && settings.runtimes[process.argv[2]];
if (!runtime) process.exit(1);
for (const model of runtime.recommendedModels || []) console.log(model);
' "$AI_LITELLM_SETTINGS" "$runtime"
}

ai_litellm_model_runtime() {
  local model_name="$1"
  model_name="$(ai_litellm_model_resolve "$model_name" 2>/dev/null)" || return 1

  # Name-independent mapping: a model belongs to the runtime whose apiBase
  # equals its registry api_base. Naming (suffix conventions) never decides
  # runtime membership. Soundness depends on ai_litellm_runtime_ports_ok
  # keeping apiBase unique per runtime.
  local runtime api_base rt_base
  local -a runtimes
  runtimes=("${(@f)$(ai_litellm_runtime_names 2>/dev/null)}")
  api_base="$(ai_litellm_model_api_base "$model_name" 2>/dev/null || true)"
  if [[ -n "$api_base" ]]; then
    for runtime in "${runtimes[@]}"; do
      rt_base="$(ai_litellm_runtime_field "$runtime" apiBase 2>/dev/null || true)"
      if [[ -n "$rt_base" && "$api_base" == "$rt_base" ]]; then
        printf '%s\n' "$runtime"
        return 0
      fi
    done
  fi

  return 1
}

# Supported runtime kinds. openai-compatible covers oMLX, exo, vLLM, and Ollama
# (via its /v1 endpoint). Add a new kind here AND a branch in the two adapters below.
ai_litellm_runtime_supported_kinds() {
  printf 'openai-compatible\n'
}

ai_litellm_runtime_kind() {
  ai_litellm_runtime_field "$1" kind 2>/dev/null || printf 'openai-compatible'
}

# Readiness adapter selection is driven by runtimes.<name>.kind. An unknown kind
# fails loudly here instead of silently using the wrong probe.
ai_litellm_runtime_reachable() {
  local runtime="$1"
  local kind api_base
  kind="$(ai_litellm_runtime_kind "$runtime")"
  api_base="$(ai_litellm_runtime_field "$runtime" apiBase 2>/dev/null)" || return 1
  case "$kind" in
    openai-compatible)
      curl --max-time 3 -fsS "$api_base/models" >/dev/null 2>&1
      ;;
    *)
      echo "Unsupported runtime kind '$kind' for runtime '$runtime'" >&2
      return 1
      ;;
  esac
}

ai_litellm_runtime_model_available() {
  local runtime="$1"
  local model_name="$2"
  local kind api_base
  kind="$(ai_litellm_runtime_kind "$runtime")"
  api_base="$(ai_litellm_runtime_field "$runtime" apiBase 2>/dev/null)" || return 1
  case "$kind" in
    openai-compatible)
      curl --max-time 3 -fsS "$api_base/models" 2>/dev/null | node -e '
const fs = require("fs");
const target = process.argv[1];
let payload;
try {
  payload = JSON.parse(fs.readFileSync(0, "utf8"));
} catch {
  process.exit(1);
}
const ids = (payload.data || []).map((model) => model.id || model.model || model.name).filter(Boolean);
process.exit(ids.includes(target) ? 0 : 1);
' "$model_name"
      ;;
    *)
      echo "Unsupported runtime kind '$kind' for runtime '$runtime'" >&2
      return 1
      ;;
  esac
}

ai_litellm_runtime_available_models() {
  local runtime="$1"
  local kind api_base
  kind="$(ai_litellm_runtime_kind "$runtime")"
  api_base="$(ai_litellm_runtime_field "$runtime" apiBase 2>/dev/null)" || return 1
  case "$kind" in
    openai-compatible)
      curl --max-time 3 -fsS "$api_base/models" 2>/dev/null | node -e '
const fs = require("fs");
let payload;
try {
  payload = JSON.parse(fs.readFileSync(0, "utf8"));
} catch {
  process.exit(1);
}
const ids = (payload.data || payload.models || [])
  .map((model) => model.id || model.model || model.name)
  .filter(Boolean)
  .sort();
for (const id of ids) console.log(id);
'
      ;;
    *)
      echo "Unsupported runtime kind '$kind' for runtime '$runtime'" >&2
      return 1
      ;;
  esac
}

# Validate one runtime block: required string fields, supported kind, optional
# expected/recommended model arrays, and apiBase nested under baseUrl.
ai_litellm_runtime_validate() {
  local runtime="$1"
  [[ -f "$AI_LITELLM_SETTINGS" ]] || return 1
  local supported
  supported="$(ai_litellm_runtime_supported_kinds | paste -sd, -)"
  node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const name = process.argv[2];
const supported = (process.argv[3] || "").split(",").filter(Boolean);
const rt = (settings.runtimes || {})[name];
if (!rt) { console.error(`runtime not found: ${name}`); process.exit(1); }
const errs = [];
for (const k of ["kind", "baseUrl", "apiBase"]) {
  if (typeof rt[k] !== "string" || rt[k].length === 0) errs.push(`${k} must be a non-empty string`);
}
if (rt.kind && !supported.includes(rt.kind)) errs.push(`unsupported kind: ${rt.kind} (supported: ${supported.join(", ")})`);
if (rt.expectedModels != null && (!Array.isArray(rt.expectedModels) || rt.expectedModels.some((m) => typeof m !== "string" || !m.length))) {
  errs.push("expectedModels must be an array of strings when present");
}
if (rt.recommendedModels != null && (!Array.isArray(rt.recommendedModels) || rt.recommendedModels.some((m) => typeof m !== "string" || !m.length))) {
  errs.push("recommendedModels must be an array of strings when present");
}
if (typeof rt.apiBase === "string" && typeof rt.baseUrl === "string" && rt.baseUrl && !rt.apiBase.startsWith(rt.baseUrl)) {
  errs.push(`apiBase (${rt.apiBase}) should start with baseUrl (${rt.baseUrl})`);
}
if (errs.length) { console.error(`runtime ${name}: ${errs.join("; ")}`); process.exit(1); }
' "$AI_LITELLM_SETTINGS" "$runtime" "$supported"
}

# Cross-file consistency between settings.json runtimes and the litellm registry:
# required expectedModels exist in the registry, and suffix-named models
# (<Model>-<runtime>) point at that runtime's apiBase. Naming is a lint surface
# only — runtime MEMBERSHIP is decided by api_base equality (ai_litellm_model_runtime).
# recommendedModels are documentation/sample routes and may be absent.
ai_litellm_runtime_consistency() {
  [[ -f "$AI_LITELLM_SETTINGS" && -f "$AI_LITELLM_CONFIG" ]] || return 0
  ai_litellm_ruby -ryaml -rjson -e '
settings = JSON.parse(File.read(ARGV[0]))
config = (YAML.load_file(ARGV[1], aliases: true) rescue YAML.load_file(ARGV[1]))
models = Array(config["model_list"])
names = models.map { |e| e["model_name"] }.compact
errs = []
runtimes = settings["runtimes"] || {}
runtimes.each do |rt_name, rt|
  api_base = rt["apiBase"]
  Array(rt["expectedModels"]).each do |m|
    errs << "#{rt_name}: expectedModel #{m} missing from registry" unless names.include?(m)
  end
  suffix = rt["modelSuffix"].to_s
  suffix = "-#{rt_name.to_s.downcase}" if suffix.empty?
  models.each do |e|
    n = e["model_name"]
    next unless n && n.end_with?(suffix)
    mb = e.dig("litellm_params", "api_base")
    errs << "#{n}: api_base #{mb.inspect} != runtime #{rt_name} apiBase #{api_base.inspect}" unless mb == api_base
  end
end
if errs.any?
  errs.each { |e| warn e }
  exit 1
end
' "$AI_LITELLM_SETTINGS" "$AI_LITELLM_CONFIG"
}

# Endpoint/port collision detection across runtimes and against the proxy port.
ai_litellm_runtime_ports_ok() {
  [[ -f "$AI_LITELLM_SETTINGS" ]] || return 0
  local proxy_port
  proxy_port="$(ai_litellm_port 2>/dev/null || printf '4000')"
  node -e '
const fs = require("fs");
const settings = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const proxyPort = String(process.argv[2] || "");
const runtimes = settings.runtimes || {};
const seen = new Map();
const errs = [];
const hostport = (url) => {
  try { const u = new URL(url); return `${u.hostname}:${u.port || (u.protocol === "https:" ? "443" : "80")}`; }
  catch { return null; }
};
for (const [name, rt] of Object.entries(runtimes)) {
  const hp = hostport(rt.apiBase || rt.baseUrl || "");
  if (!hp) { errs.push(`${name}: cannot parse apiBase/baseUrl`); continue; }
  const port = hp.split(":").pop();
  if (port === proxyPort) errs.push(`${name}: port ${port} collides with LiteLLM proxy port`);
  if (seen.has(hp)) errs.push(`${name}: endpoint ${hp} collides with runtime ${seen.get(hp)}`);
  else seen.set(hp, name);
}
if (errs.length) { errs.forEach((e) => console.error(e)); process.exit(1); }
' "$AI_LITELLM_SETTINGS" "$proxy_port"
}

ai_litellm_runtime_status_one() {
  local runtime="$1"
  local base_url api_base models_dir start_command stop_command managed_by
  base_url="$(ai_litellm_runtime_field "$runtime" baseUrl 2>/dev/null || true)"
  api_base="$(ai_litellm_runtime_field "$runtime" apiBase 2>/dev/null || true)"
  models_dir="$(ai_litellm_runtime_field "$runtime" modelsDir 2>/dev/null || true)"
  start_command="$(ai_litellm_runtime_field "$runtime" startCommand 2>/dev/null || true)"
  stop_command="$(ai_litellm_runtime_field "$runtime" stopCommand 2>/dev/null || true)"
  managed_by="$(ai_litellm_runtime_field "$runtime" managedBy 2>/dev/null || true)"

  echo "Runtime:   $runtime"
  echo "Base URL:  ${base_url:-unknown}"
  echo "API base:  ${api_base:-unknown}"
  echo "Model dir: ${models_dir:-unknown}"
  echo "Start:     ${start_command:-manual}"
  echo "Stop:      ${stop_command:-manual}"
  echo "Managed:   ${managed_by:-user}"
  if ai_litellm_runtime_reachable "$runtime"; then
    echo "Health:    ok"
  else
    echo "Health:    not reachable"
  fi

  local model
  local -a expected_models recommended_models missing_models available_models
  expected_models=("${(@f)$(ai_litellm_runtime_expected_models "$runtime" 2>/dev/null)}")
  expected_models=("${(@)expected_models:#}")
  if (( ${#expected_models[@]} > 0 )); then
    echo "Required models:"
    for model in "${expected_models[@]}"; do
      if ai_litellm_runtime_model_available "$runtime" "$model"; then
        printf '  ok   %s\n' "$model"
      else
        printf '  fail %s\n' "$model"
        missing_models+=("$model")
      fi
    done
  else
    echo "Required models: none"
  fi

  recommended_models=("${(@f)$(ai_litellm_runtime_recommended_models "$runtime" 2>/dev/null)}")
  recommended_models=("${(@)recommended_models:#}")
  if (( ${#recommended_models[@]} > 0 )); then
    echo "Recommended sample routes:"
    printf '  %s\n' "${recommended_models[@]}"
  fi

  if ai_litellm_runtime_reachable "$runtime"; then
    available_models=("${(@f)$(ai_litellm_runtime_available_models "$runtime" 2>/dev/null)}")
    available_models=("${(@)available_models:#}")
    if (( ${#available_models[@]} > 0 )); then
      echo "Runtime advertises models:"
      printf '  %s\n' "${available_models[@]}"
      echo "Hint: run 'claude-litellm sync' to generate local routes for advertised models."
    fi
  fi
}

ai_litellm_runtime_status() {
  local runtime="$1"
  if [[ -n "$runtime" ]]; then
    ai_litellm_runtime_status_one "$runtime"
    return $?
  fi

  local -a runtimes
  runtimes=("${(@f)$(ai_litellm_runtime_names 2>/dev/null)}")
  if (( ${#runtimes[@]} == 0 )); then
    echo "No local runtimes configured"
    return 0
  fi

  local item
  for item in "${runtimes[@]}"; do
    ai_litellm_runtime_status_one "$item"
    echo
  done
}

ai_litellm_runtime_status_one_json() {
  local runtime="$1"
  local base_url api_base health
  base_url="$(ai_litellm_runtime_field "$runtime" baseUrl 2>/dev/null || true)"
  api_base="$(ai_litellm_runtime_field "$runtime" apiBase 2>/dev/null || true)"
  health="not reachable"
  ai_litellm_runtime_reachable "$runtime" 2>/dev/null && health="ok"
  local -a expected_models
  expected_models=("${(@f)$(ai_litellm_runtime_expected_models "$runtime" 2>/dev/null)}")
  expected_models=("${(@)expected_models:#}")
  local -a available_models
  if ai_litellm_runtime_reachable "$runtime" 2>/dev/null; then
    available_models=("${(@f)$(ai_litellm_runtime_available_models "$runtime" 2>/dev/null)}")
    available_models=("${(@)available_models:#}")
  fi
  # Build required models array
  local required_json="["
  local first=1 model
  for model in "${expected_models[@]}"; do
    local ok_val="false"
    ai_litellm_runtime_model_available "$runtime" "$model" 2>/dev/null && ok_val="true"
    [[ $first -eq 1 ]] || required_json+=","
    required_json+="{\"model\":$(node -e "process.stdout.write(JSON.stringify(process.argv[1]))" "$model"),\"ok\":$ok_val}"
    first=0
  done
  required_json+="]"
  # Build advertised models array
  local advertised_json="["
  first=1
  for model in "${available_models[@]}"; do
    [[ $first -eq 1 ]] || advertised_json+=","
    advertised_json+="$(node -e "process.stdout.write(JSON.stringify(process.argv[1]))" "$model")"
    first=0
  done
  advertised_json+="]"
  node -e "
const [name,baseUrl,apiBase,health,reqStr,advStr]=process.argv.slice(1);
const obj={name,baseUrl,apiBase,health,requiredModels:JSON.parse(reqStr),advertisedModels:JSON.parse(advStr)};
process.stdout.write(JSON.stringify(obj));
" "$runtime" "$base_url" "$api_base" "$health" "$required_json" "$advertised_json"
}

ai_litellm_runtime_status_json() {
  local runtime="$1"
  if [[ -n "$runtime" ]]; then
    local item_json
    item_json="$(ai_litellm_runtime_status_one_json "$runtime" 2>/dev/null)" || { printf '[]'; return 0; }
    printf '[%s]' "$item_json"
    return 0
  fi
  local -a runtimes
  runtimes=("${(@f)$(ai_litellm_runtime_names 2>/dev/null)}")
  if (( ${#runtimes[@]} == 0 )); then
    printf '[]'
    return 0
  fi
  local rows="["
  local first=1 item
  for item in "${runtimes[@]}"; do
    local item_json
    item_json="$(ai_litellm_runtime_status_one_json "$item" 2>/dev/null)" || continue
    [[ $first -eq 1 ]] || rows+=","
    rows+="$item_json"
    first=0
  done
  rows+="]"
  printf '%s' "$rows"
}

ai_litellm_model_runtime_ready() {
  local model_name="$1"
  local runtime backend_model runtime_model
  runtime="$(ai_litellm_model_runtime "$model_name" 2>/dev/null)" || return 0
  backend_model="$(ai_litellm_model_backend "$model_name" 2>/dev/null || printf '%s\n' "$model_name")"
  runtime_model="${backend_model#openai/}"

  if ai_litellm_runtime_model_available "$runtime" "$runtime_model"; then
    return 0
  fi

  local api_base start_command models_dir
  api_base="$(ai_litellm_runtime_field "$runtime" apiBase 2>/dev/null || printf 'unknown')"
  start_command="$(ai_litellm_runtime_field "$runtime" startCommand 2>/dev/null || printf 'manual start')"
  models_dir="$(ai_litellm_runtime_field "$runtime" modelsDir 2>/dev/null || printf 'unknown')"

  echo "Runtime '$runtime' is not ready for LiteLLM model '$model_name'." >&2
  echo "Endpoint: $api_base" >&2
  echo "Start it manually: $start_command" >&2
  echo "Expected runtime model: $runtime_model" >&2
  echo "Expected model directory: $models_dir/$runtime_model" >&2
  echo "No fallback was attempted." >&2
  return 1
}

ai_litellm_pid_from_file() {
  local pid_file="$1"
  [[ -f "$pid_file" && ! -L "$pid_file" ]] || return 1
  local pid
  pid="$(<"$pid_file")"
  ai_litellm_pid_is_litellm "$pid" || return 1
  printf '%s\n' "$pid"
}

ai_litellm_pid_is_litellm() {
  local pid="$1"
  [[ "$pid" == <-> ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  local command_line process_executable executable_name config venv bootstrap
  command_line="$(ps -ww -p "$pid" -o command= 2>/dev/null || true)"
  process_executable="$(ps -ww -p "$pid" -o comm= 2>/dev/null || true)"
  config="$AI_LITELLM_CONFIG"
  venv="$AI_LITELLM_HOME/runtime/venv"
  bootstrap="$AI_LITELLM_CONFIG_HOME/ai_litellm_callbacks/proxy_bootstrap.py"
  executable_name="${process_executable:t:l}"
  [[ "$command_line" == *"--config $config"* || "$command_line" == *"--config=$config"* ]] || return 1

  # Installed runtime: actual executable and argv must both belong to this
  # prefix. This rejects rg/editors/backups that merely mention these paths.
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

  # Checkout/legacy mode may launch a system or uv-managed LiteLLM. The PID file
  # is the primary ownership claim, but still require an actual executable/module
  # argv followed by this exact config; a substring match is never sufficient.
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

ai_litellm_owned_proxy_pids() {
  local line pid command_line
  while IFS= read -r line; do
    [[ "$line" =~ '^[[:space:]]*([0-9]+)[[:space:]]+(.*)$' ]] || continue
    pid="${match[1]}"
    command_line="${match[2]}"
    [[ "$pid" != "$$" ]] || continue
    [[ "$command_line" == *"--config $AI_LITELLM_CONFIG"* || \
       "$command_line" == *"--config=$AI_LITELLM_CONFIG"* ]] || continue
    ai_litellm_pid_is_litellm "$pid" && printf '%s\n' "$pid"
  done < <(ps -axo pid=,command= 2>/dev/null)
}

ai_litellm_active_pid_file() {
  local pid_file
  for pid_file in "$AI_LITELLM_PID_FILE" "$AI_LITELLM_LEGACY_PID_FILE" "$AI_LITELLM_LEGACY_CLAUDE_PID_FILE"; do
    ai_litellm_pid_from_file "$pid_file" >/dev/null 2>&1 || continue
    printf '%s\n' "$pid_file"
    return 0
  done
  return 1
}

ai_litellm_active_pid() {
  local pid_file
  if pid_file="$(ai_litellm_active_pid_file 2>/dev/null)"; then
    ai_litellm_pid_from_file "$pid_file"
    return
  fi
  ai_litellm_owned_proxy_pids | head -n 1
}

ai_litellm_pid_running() {
  [[ -n "$(ai_litellm_owned_proxy_pids 2>/dev/null)" ]]
}

ai_litellm_health() {
  local master_key
  master_key="$(ai_litellm_master_key 2>/dev/null)" || true

  if [[ -n "$master_key" ]]; then
    ai_litellm_curl_auth "$master_key" --max-time 3 -fsS "$(ai_litellm_base_url)/health/readiness" >/dev/null 2>&1
  else
    curl --max-time 3 -fsS "$(ai_litellm_base_url)/health/readiness" >/dev/null 2>&1
  fi
}

ai_litellm_config_hash() {
  [[ -f "$AI_LITELLM_CONFIG" ]] || return 1
  shasum -a 256 "$AI_LITELLM_CONFIG" | awk '{print $1}'
}

ai_litellm_record_proxy_config_state() {
  local config_hash started_at
  ai_litellm_proxy_state_paths_safe || return 1
  config_hash="$(ai_litellm_config_hash)" || return 1
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" || return 1
  printf '%s\n' "$config_hash" | \
    ai_litellm_atomic_private_write "$AI_LITELLM_CONFIG_HASH_FILE" || return 1
  printf '%s\n' "$started_at" | \
    ai_litellm_atomic_private_write "$AI_LITELLM_STARTED_AT_FILE"
}

ai_litellm_proxy_config_current() {
  [[ -f "$AI_LITELLM_CONFIG_HASH_FILE" && ! -L "$AI_LITELLM_CONFIG_HASH_FILE" ]] || return 2
  local current recorded
  current="$(ai_litellm_config_hash 2>/dev/null)" || return 1
  recorded="$(<"$AI_LITELLM_CONFIG_HASH_FILE")"
  [[ -n "$recorded" && "$current" == "$recorded" ]]
}

ai_litellm_proxy_model_names() {
  local master_key
  master_key="$(ai_litellm_master_key 2>/dev/null)" || return 1
  ai_litellm_curl_auth "$master_key" --max-time 5 -fsS "$(ai_litellm_base_url)/model/info" \
    | jq -r '.data[].model_name'
}

ai_litellm_proxy_registry_matches_file() {
  ai_litellm_health || return 0
  local oauth_python oauth_manager oauth_status actual_models
  oauth_python="$(ai_litellm_litellm_python 2>/dev/null)" || return 1
  oauth_manager="$AI_LITELLM_HOME/config/claude-litellm/oauth.py"
  [[ -f "$oauth_manager" ]] || return 1
  oauth_status="$(ai_litellm_python_isolated "$oauth_python" "$oauth_manager" status all --json 2>/dev/null)" || return 1
  actual_models="$(ai_litellm_proxy_model_names)" || return 1

  # LiteLLM resolves ChatGPT OAuth while constructing its deployment.  Our
  # non-interactive guard makes a logged-out deployment fail closed, and the
  # router continues without that one route.  Therefore every non-OAuth route
  # is required, while an OAuth route is required only when its credential is
  # currently authenticated and permission-safe.  Logged-out OAuth routes may
  # be present (xAI currently initializes lazily) or absent (ChatGPT currently
  # initializes eagerly), but no route outside the config is accepted.
  ai_litellm_ruby -ryaml -rjson -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
status = JSON.parse(ARGV[1]).each_with_object({}) { |row, out| out[row["provider"]] = row }
actual = ARGV[2].lines.map(&:strip).reject(&:empty?).uniq
configured = []
required = []
Array(config["model_list"]).each do |entry|
  name = entry["model_name"].to_s
  next if name.empty?
  configured << name
  params = entry["litellm_params"] || {}
  backend = params["model"].to_s
  provider = if backend.start_with?("chatgpt/")
    "chatgpt"
  elsif params["use_xai_oauth"] == true
    "grok"
  end
  row = provider && status[provider]
  authenticated = row && row["authenticated"] == true && row["permissionsSafe"] == true
  required << name if provider.nil? || authenticated
end
missing = required.uniq - actual
unexpected = actual - configured.uniq
unless missing.empty? && unexpected.empty?
  warn "missing required proxy routes: #{missing.join(", ")}" unless missing.empty?
  warn "unexpected proxy routes: #{unexpected.join(", ")}" unless unexpected.empty?
  exit 1
end
' "$AI_LITELLM_CONFIG" "$oauth_status" "$actual_models"
}

ai_litellm_reachable_proxy_current() {
  ai_litellm_proxy_config_current || return 1
  ai_litellm_proxy_registry_matches_file || return 1
}

ai_litellm_lock_stale() {
  [[ -d "$AI_LITELLM_LOCK_DIR" ]] || return 1
  local lock_pid="" age=0
  [[ -f "$AI_LITELLM_LOCK_DIR/pid" ]] && lock_pid="$(<"$AI_LITELLM_LOCK_DIR/pid")"
  age="$(perl -e 'my @s = stat($ARGV[0]); print @s ? int(time - $s[9]) : 0' "$AI_LITELLM_LOCK_DIR" 2>/dev/null || printf '0')"
  if [[ -z "$lock_pid" ]]; then
    # mkdir publishes before pid. Give the winner time to publish instead of
    # deleting a live lock in that tiny window.
    (( ${age:-0} > 2 ))
    return
  fi
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    if (( ${age:-0} > ${AI_LITELLM_LOCK_MAX_AGE_SECONDS:-300} )) && ! ai_litellm_health; then
      return 0
    fi
    return 1
  fi
  return 0
}

ai_litellm_clear_lock() {
  if [[ -d "$AI_LITELLM_LOCK_DIR" && \
        "$(<"$AI_LITELLM_LOCK_DIR/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "$AI_LITELLM_LOCK_DIR" 2>/dev/null || true
  fi
  if [[ "${AI_LITELLM_START_LOCK_FD:-}" == <-> ]]; then
    zsystem flock -u "$AI_LITELLM_START_LOCK_FD" 2>/dev/null || true
  fi
  typeset -g AI_LITELLM_START_LOCK_FD=""
}

ai_litellm_acquire_lock() {
  local lock_wait fd owner
  zmodload zsh/system || return 1
  typeset -g AI_LITELLM_START_LOCK_FD=""
  mkdir -p "$AI_LITELLM_PROXY_HOME"
  ai_litellm_lock_file_prepare "${AI_LITELLM_LOCK_DIR}.flock" || return 1
  for lock_wait in {1..50}; do
    if zsystem flock -t 0 -f fd "${AI_LITELLM_LOCK_DIR}.flock"; then
      chmod 600 "${AI_LITELLM_LOCK_DIR}.flock" 2>/dev/null || true
      if [[ -d "$AI_LITELLM_LOCK_DIR" ]]; then
        owner="$(<"$AI_LITELLM_LOCK_DIR/pid" 2>/dev/null || printf '?')"
        if [[ "$owner" != '?' ]] && kill -0 "$owner" 2>/dev/null; then
          zsystem flock -u "$fd" 2>/dev/null || true
          ai_litellm_health && return 2
          sleep 0.1
          continue
        fi
        rm -rf "$AI_LITELLM_LOCK_DIR"
      elif [[ -e "$AI_LITELLM_LOCK_DIR" || -L "$AI_LITELLM_LOCK_DIR" ]]; then
        zsystem flock -u "$fd" 2>/dev/null || true
        return 1
      fi
      mkdir "$AI_LITELLM_LOCK_DIR" || { zsystem flock -u "$fd" 2>/dev/null || true; return 1; }
      date -u '+%Y-%m-%dT%H:%M:%SZ' > "$AI_LITELLM_LOCK_DIR/started_at"
      printf '%s\n' "$$" > "$AI_LITELLM_LOCK_DIR/pid"
      AI_LITELLM_START_LOCK_FD="$fd"
      return 0
    fi

    if ai_litellm_health; then
      return 2
    fi

    sleep 0.1
  done

  return 1
}

ai_litellm_cleanup_failed_start() {
  local pid="$1" i
  [[ "$pid" == <-> ]] || return 0

  # Only signal the exact process we just launched if it still proves ownership
  # immediately before each signal. If it exited or the PID was reused, merely
  # discard our stale bookkeeping.
  if ai_litellm_pid_is_litellm "$pid"; then
    kill -TERM "$pid" 2>/dev/null || true
    for i in {1..30}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null && ai_litellm_pid_is_litellm "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  fi

  if [[ -f "$AI_LITELLM_PID_FILE" && ! -L "$AI_LITELLM_PID_FILE" && \
        "$(<$AI_LITELLM_PID_FILE)" == "$pid" ]]; then
    rm -f "$AI_LITELLM_PID_FILE"
  fi
  rm -f "$AI_LITELLM_CONFIG_HASH_FILE" "$AI_LITELLM_STARTED_AT_FILE"
}

ai_litellm_lifecycle_lock_acquire() {
  if [[ "${AI_LITELLM_LIFECYCLE_LOCK_FD:-}" == <-> ]]; then
    typeset -gi AI_LITELLM_LIFECYCLE_LOCK_DEPTH=$(( ${AI_LITELLM_LIFECYCLE_LOCK_DEPTH:-1} + 1 ))
    return 0
  fi
  local fd
  mkdir -p "${AI_LITELLM_LIFECYCLE_LOCK:h}"
  ai_litellm_lock_file_prepare "${AI_LITELLM_LIFECYCLE_LOCK}.flock" || return 1
  zmodload zsh/system || {
    echo "zsh/system is required for the package lifecycle lock." >&2
    return 1
  }
  if ! zsystem flock -t 0 -f fd "${AI_LITELLM_LIFECYCLE_LOCK}.flock"; then
    echo "claude-litellm package installation or removal is in progress; retry afterward." >&2
    return 1
  fi
  chmod 600 "${AI_LITELLM_LIFECYCLE_LOCK}.flock" 2>/dev/null || true
  typeset -g AI_LITELLM_LIFECYCLE_LOCK_FD="$fd"
  typeset -gi AI_LITELLM_LIFECYCLE_LOCK_DEPTH=1
}

ai_litellm_lifecycle_lock_release() {
  [[ "${AI_LITELLM_LIFECYCLE_LOCK_FD:-}" == <-> ]] || return 0
  if (( ${AI_LITELLM_LIFECYCLE_LOCK_DEPTH:-1} > 1 )); then
    typeset -gi AI_LITELLM_LIFECYCLE_LOCK_DEPTH=$(( AI_LITELLM_LIFECYCLE_LOCK_DEPTH - 1 ))
    return 0
  fi
  zmodload zsh/system 2>/dev/null || true
  zsystem flock -u "$AI_LITELLM_LIFECYCLE_LOCK_FD" 2>/dev/null || true
  typeset -g AI_LITELLM_LIFECYCLE_LOCK_FD=""
  typeset -gi AI_LITELLM_LIFECYCLE_LOCK_DEPTH=0
}

_ai_litellm_start_unlocked() {
  local master_key openrouter_key proxy_python
  if ! ai_litellm_install_integrity_ok; then
    echo "Installed package/runtime integrity failed; reinstall before starting the proxy." >&2
    return 1
  fi
  if ! ai_litellm_effective_config_current; then
    echo "Generated LiteLLM/Claude configuration is stale or modified; run 'claude-litellm sync' before starting the proxy." >&2
    return 1
  fi
  proxy_python="$(ai_litellm_litellm_python 2>/dev/null)" || {
    echo "LiteLLM Python runtime is unavailable; reinstall the pinned runtime." >&2
    return 1
  }
  if ! ai_litellm_proxy_state_paths_safe; then
    echo "Proxy state paths are unsafe; repair or remove the reported leaf before starting." >&2
    return 1
  fi
  if ! ai_litellm_python_configured "$proxy_python" -c '
from ai_litellm_callbacks.oauth_guard import PATCH_ACTIVE
assert PATCH_ACTIVE is True
' >/dev/null 2>&1; then
    echo "ChatGPT OAuth non-interactive refresh guard is inactive; refusing to start the proxy. Reinstall the pinned runtime." >&2
    return 1
  fi
  master_key="$(ai_litellm_master_key 2>/dev/null)" || true
  if [[ -z "$master_key" ]]; then
    echo "Missing LiteLLM master key. Store it in Keychain service $LITELLM_MASTER_KEYCHAIN_SERVICE or $AI_LITELLM_ENV." >&2
    return 1
  fi

  openrouter_key="$(ai_litellm_openrouter_key 2>/dev/null)" || true
  if grep -q 'os\.environ/OPENROUTER_API_KEY' "$AI_LITELLM_CONFIG" && [[ -z "$openrouter_key" ]]; then
    echo "warn: OpenRouter routes are configured without an OpenRouter API key; those routes will fail, while OAuth and local routes remain available." >&2
  fi

  if ai_litellm_health; then
    if ! ai_litellm_reachable_proxy_current; then
      echo "LiteLLM is reachable at $(ai_litellm_base_url), but it has not loaded the current $AI_LITELLM_CONFIG routes." >&2
      echo "Run 'claude-litellm sync' before launching harnesses." >&2
      return 1
    fi
    echo "LiteLLM is already reachable at $(ai_litellm_base_url)"
    return 0
  fi

  local lock_result
  ai_litellm_acquire_lock
  lock_result=$?
  if (( lock_result == 2 )); then
    if ! ai_litellm_reachable_proxy_current; then
      echo "LiteLLM is reachable at $(ai_litellm_base_url), but it has not loaded the current $AI_LITELLM_CONFIG routes." >&2
      echo "Run 'claude-litellm sync' before launching harnesses." >&2
      return 1
    fi
    echo "LiteLLM is already reachable at $(ai_litellm_base_url)"
    return 0
  fi
  if (( lock_result != 0 )); then
    echo "Timed out waiting for LiteLLM start lock: $AI_LITELLM_LOCK_DIR" >&2
    return 1
  fi

  if ai_litellm_health; then
    ai_litellm_clear_lock
    if ! ai_litellm_reachable_proxy_current; then
      echo "LiteLLM is reachable at $(ai_litellm_base_url), but it has not loaded the current $AI_LITELLM_CONFIG routes." >&2
      echo "Run 'claude-litellm sync' before launching harnesses." >&2
      return 1
    fi
    echo "LiteLLM is already reachable at $(ai_litellm_base_url)"
    return 0
  fi

  if ai_litellm_pid_running; then
    echo "LiteLLM pid file exists, but health check failed: $(ai_litellm_active_pid)"
    echo "Log: $(ai_litellm_active_log_file)"
    ai_litellm_clear_lock
    return 1
  fi

  rm -f "$AI_LITELLM_PID_FILE" "$AI_LITELLM_LEGACY_PID_FILE" "$AI_LITELLM_LEGACY_CLAUDE_PID_FILE"
  # Resolve every other os.environ/<VAR> the registry references (OpenAI, Anthropic,
  # Gemini, ... beyond OpenRouter) from Keychain/env-file and inject them into the
  # proxy subprocess only. Never exported to the interactive shell.
  local -a extra_env_names extra_env_values
  local _ref _val
  for _ref in ${(f)"$(ai_litellm_config_env_refs 2>/dev/null)"}; do
    case "$_ref" in
      OPENROUTER_API_KEY|LITELLM_MASTER_KEY) continue ;;
    esac
    [[ "$_ref" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]] || {
      echo "Refusing invalid provider credential environment name in the model registry: $_ref" >&2
      return 1
    }
    _val="$(ai_litellm_resolve_secret_var "$_ref" 2>/dev/null || true)"
    if [[ -n "$_val" ]]; then
      extra_env_names+=("$_ref")
      extra_env_values+=("$_val")
    else
      echo "warn: registry references os.environ/$_ref but it is not in Keychain/env-file; routes needing it will fail until you store it." >&2
    fi
  done

  local pid _extra_index
  pid="$(
    # This command substitution is a subshell. Dynamic exports therefore reach
    # only the launcher/proxy descendants and never the interactive shell. Do
    # not pass NAME=secret pairs through /usr/bin/env: they are process argv and
    # can be sampled by other same-user tools while the launcher is starting.
    # OAuth inference origins are package policy, not ambient configuration.
    # LiteLLM attaches bearer tokens after consulting these variables, so an
    # inherited override could otherwise redirect a token before the Python
    # bootstrap gets a chance to enforce the same boundary again.
    unset OPENAI_API_KEY XAI_API_KEY \
      CHATGPT_API_BASE OPENAI_CHATGPT_API_BASE \
      XAI_OAUTH_API_BASE XAI_API_BASE
    export OPENROUTER_API_KEY="$openrouter_key"
    export LITELLM_MASTER_KEY="$master_key"
    export AI_LITELLM_HOST="$(ai_litellm_host)"
    export AI_LITELLM_PORT="$(ai_litellm_port)"
    export AI_LITELLM_PYTHON="$proxy_python"
    export NUM_WORKERS=1
    _extra_index=1
    while (( _extra_index <= ${#extra_env_names[@]} )); do
      export "${extra_env_names[$_extra_index]}=${extra_env_values[$_extra_index]}"
      (( _extra_index += 1 ))
    done
    ai_litellm_python_isolated "$proxy_python" - <<'PY'
import os
import subprocess
import sys

cmd = [
    os.environ["AI_LITELLM_PYTHON"],
    "-sP",
    "-B",
    os.path.join(
        os.environ["AI_LITELLM_CONFIG_HOME"],
        "ai_litellm_callbacks",
        "proxy_bootstrap.py",
    ),
    "--config",
    os.environ["AI_LITELLM_CONFIG"],
    "--host",
    os.environ["AI_LITELLM_HOST"],
    "--port",
    os.environ["AI_LITELLM_PORT"],
]

child_env = os.environ.copy()
for name in (
    "PYTHONHOME", "PYTHONSTARTUP", "PYTHONINSPECT", "PYTHONBREAKPOINT",
    "PYTHONUSERBASE", "PYTHONEXECUTABLE", "PYTHONWARNINGS",
    "PYTHONPLATLIBDIR", "PYTHONPYCACHEPREFIX",
):
    child_env.pop(name, None)
child_env["PYTHONPATH"] = os.environ["AI_LITELLM_CONFIG_HOME"]
child_env["PYTHONNOUSERSITE"] = "1"

try:
    log_flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    if hasattr(os, "O_NOFOLLOW"):
        log_flags |= os.O_NOFOLLOW
    log_fd = os.open(os.environ["AI_LITELLM_LOG_FILE"], log_flags, 0o600)
    log_info = os.fstat(log_fd)
    if not __import__("stat").S_ISREG(log_info.st_mode):
        raise OSError("proxy log is not a regular file")
    os.fchmod(log_fd, 0o600)
    log = os.fdopen(log_fd, "ab", buffering=0)
    process = subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        close_fds=True,
        env=child_env,
    )
except Exception as exc:
    print(f"Failed to start LiteLLM: {exc}", file=sys.stderr)
    raise SystemExit(1)

print(process.pid)
PY
  )" || {
    echo "Failed to start LiteLLM. Log: $AI_LITELLM_LOG_FILE"
    ai_litellm_clear_lock
    return 1
  }
  printf '%s\n' "$pid" | ai_litellm_atomic_private_write "$AI_LITELLM_PID_FILE" || {
    ai_litellm_cleanup_failed_start "$pid"
    ai_litellm_clear_lock
    return 1
  }

  local i
  for i in {1..30}; do
    if ai_litellm_health && ai_litellm_proxy_registry_matches_file && ai_litellm_pid_is_litellm "$pid"; then
      ai_litellm_record_proxy_config_state || {
        echo "LiteLLM started but secure state publication failed; stopping it." >&2
        ai_litellm_cleanup_failed_start "$pid"
        ai_litellm_clear_lock
        return 1
      }
      echo "LiteLLM started at $(ai_litellm_base_url) (pid $pid)"
      ai_litellm_clear_lock
      return 0
    fi
    sleep 0.2
  done

  echo "LiteLLM did not become healthy. Log: $AI_LITELLM_LOG_FILE"
  ai_litellm_cleanup_failed_start "$pid"
  ai_litellm_clear_lock
  return 1
}

ai_litellm_start() {
  ai_litellm_lifecycle_lock_acquire || return $?
  local rc=0
  {
    _ai_litellm_start_unlocked "$@" || rc=$?
  } always {
    ai_litellm_clear_lock
    ai_litellm_lifecycle_lock_release
  }
  return $rc
}

_ai_litellm_stop_unlocked() {
  echo "Stopping shared LiteLLM proxy; active claude-litellm sessions may fail." >&2

  local pid attempt still_running=0
  local -a pids
  pids=("${(@f)$(ai_litellm_owned_proxy_pids 2>/dev/null)}")
  pids=("${(@)pids:#}")
  if (( ${#pids[@]} == 0 )); then
    rm -f "$AI_LITELLM_PID_FILE" "$AI_LITELLM_LEGACY_PID_FILE" "$AI_LITELLM_LEGACY_CLAUDE_PID_FILE"
    echo "No claude-litellm managed LiteLLM process is running"
    return 0
  fi

  # Close PID-reuse races: revalidate immediately before every signal.
  for pid in "${pids[@]}"; do
    ai_litellm_pid_is_litellm "$pid" || continue
    kill -TERM "$pid" 2>/dev/null || true
  done
  for attempt in {1..20}; do
    still_running=0
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null && ai_litellm_pid_is_litellm "$pid"; then
        still_running=1
        break
      fi
    done
    (( still_running )) || break
    sleep 0.25
  done
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null && ai_litellm_pid_is_litellm "$pid"; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null && ai_litellm_pid_is_litellm "$pid"; then
      echo "Failed to stop owned LiteLLM pid $pid; state was retained." >&2
      return 1
    fi
  done
  rm -f "$AI_LITELLM_PID_FILE" "$AI_LITELLM_LEGACY_PID_FILE" "$AI_LITELLM_LEGACY_CLAUDE_PID_FILE"
  rm -f "$AI_LITELLM_CONFIG_HASH_FILE" "$AI_LITELLM_STARTED_AT_FILE"
  ai_litellm_clear_lock
  echo "LiteLLM stopped (pid(s) ${(j:, :)pids})"
}

ai_litellm_stop() {
  ai_litellm_lifecycle_lock_acquire || return $?
  local rc=0
  {
    _ai_litellm_stop_unlocked "$@" || rc=$?
  } always {
    ai_litellm_clear_lock
    ai_litellm_lifecycle_lock_release
  }
  return $rc
}

ai_litellm_restart() {
  ai_litellm_lifecycle_lock_acquire || return $?
  local rc=0
  {
    _ai_litellm_stop_unlocked || rc=$?
    if (( rc == 0 )); then
      _ai_litellm_start_unlocked || rc=$?
    fi
  } always {
    ai_litellm_clear_lock
    ai_litellm_lifecycle_lock_release
  }
  return $rc
}

ai_litellm_active_log_file() {
  local pid_file
  pid_file="$(ai_litellm_active_pid_file 2>/dev/null)" || {
    printf '%s\n' "$AI_LITELLM_LOG_FILE"
    return 0
  }
  if [[ "$pid_file" == "$AI_LITELLM_LEGACY_PID_FILE" ]]; then
    printf '%s\n' "$AI_LITELLM_LEGACY_LOG_FILE"
  elif [[ "$pid_file" == "$AI_LITELLM_LEGACY_CLAUDE_PID_FILE" ]]; then
    printf '%s\n' "$AI_LITELLM_LEGACY_CLAUDE_LOG_FILE"
  else
    printf '%s\n' "$AI_LITELLM_LOG_FILE"
  fi
}

ai_litellm_status() {
  echo "Config:   $AI_LITELLM_CONFIG"
  echo "Settings: $AI_LITELLM_SETTINGS"
  echo "Base URL: $(ai_litellm_base_url)"
  echo "Effort:   OpenRouter xhigh/max normalize to high on LiteLLM 1.92; only effective levels are selectable"
  if ai_litellm_pid_running; then
    echo "PID:      $(ai_litellm_active_pid)"
    echo "PID file: $(ai_litellm_active_pid_file)"
  else
    echo "PID:      none"
  fi
  if ai_litellm_health; then
    echo "Health:   ok"
  else
    echo "Health:   not reachable"
  fi
  if ai_litellm_pid_running; then
    local config_state
    ai_litellm_proxy_config_current
    config_state=$?
    case "$config_state" in
      0)
        echo "Config:   current in running proxy"
        ;;
      2)
        echo "Config:   unknown in running proxy; restart once to record hash"
        ;;
      *)
        echo "Config:   stale in running proxy; restart required"
        ;;
    esac
  fi
  if [[ -d "$AI_LITELLM_LOCK_DIR" ]]; then
    echo "Lock:     $AI_LITELLM_LOCK_DIR"
  else
    echo "Lock:     none"
  fi
  echo "Log:      $(ai_litellm_active_log_file)"
}

ai_litellm_status_json() {
  local pid="@null" pidfile="@null" health="unreachable" currency log lock="@null"
  if ai_litellm_pid_running; then
    pid="@num:$(ai_litellm_active_pid)"
    pidfile="$(ai_litellm_active_pid_file)"
  fi
  ai_litellm_health && health="ok"
  if ai_litellm_pid_running; then
    ai_litellm_proxy_config_current
    case $? in
      0) currency="current" ;;
      2) currency="unknown" ;;
      *) currency="stale" ;;
    esac
  else
    currency="unknown-not-running"
  fi
  [[ -d "$AI_LITELLM_LOCK_DIR" ]] && lock="$AI_LITELLM_LOCK_DIR"
  log="$(ai_litellm_active_log_file)"
  ai_litellm_emit_json \
    config "$AI_LITELLM_CONFIG" \
    settings "$AI_LITELLM_SETTINGS" \
    baseUrl "$(ai_litellm_base_url)" \
    pid "$pid" \
    pidFile "$pidfile" \
    health "$health" \
    configCurrency "$currency" \
    reasoningEffortCeiling "high" \
    reasoningEffortTransport "litellm-1.92-anthropic-adapter-normalizes-xhigh-max-to-high" \
    lock "$lock" \
    log "$log"
}

ai_litellm_list() {
  echo "LiteLLM model_name entries:"
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
Array(config["model_list"]).each do |entry|
  name = entry["model_name"]
  backend = entry.dig("litellm_params", "model")
  next unless name
  if backend && backend != name
    printf("  %-22s -> %s\n", name, backend)
  else
    puts "  #{name}"
  end
end
' "$AI_LITELLM_CONFIG"
}

ai_litellm_list_json() {
  ai_litellm_ruby -ryaml -rjson -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue (YAML.load_file(ARGV[0]) rescue nil))
rows = []
Array(config && config["model_list"]).each do |entry|
  name = entry["model_name"]
  next unless name
  backend = entry.dig("litellm_params", "model")
  rows << {"name" => name, "backend" => (backend || name)}
end
print JSON.generate(rows)
' "$AI_LITELLM_CONFIG" 2>/dev/null || printf "[]"
}

ai_litellm_route_info() {
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "Missing curl or jq." >&2
    return 1
  fi

  local master_key
  master_key="$(ai_litellm_master_key 2>/dev/null)" || true
  if [[ -z "$master_key" ]]; then
    echo "Missing LiteLLM master key." >&2
    return 1
  fi

  local model_filter="$1"
  if [[ -n "$model_filter" ]]; then
    model_filter="$(ai_litellm_model_resolve "$model_filter" 2>/dev/null || printf '%s\n' "$model_filter")"
  fi
  local payload
  if ! payload="$(ai_litellm_curl_auth "$master_key" --max-time 5 -fsS "$(ai_litellm_base_url)/model/info")"; then
    echo "LiteLLM route metadata unavailable at $(ai_litellm_base_url)/model/info; is the proxy running?" >&2
    return 1
  fi

  local jq_filter
  if [[ -n "$model_filter" ]]; then
    jq_filter='.data[] | select(.model_name == $model) | [.model_name, .litellm_params.model, .model_info.litellm_provider] | @tsv'
  else
    jq_filter='.data[] | [.model_name, .litellm_params.model, .model_info.litellm_provider] | @tsv'
  fi

  print -r -- "$payload" \
    | jq -r --arg model "$model_filter" "$jq_filter" \
    | awk 'BEGIN { printf "%-18s %-48s %s\n", "model_name", "provider_model", "provider" } { printf "%-18s %-48s %s\n", $1, $2, $3 }'
}

# Print the FULL model_info block (x-limits, extra_body, reasoning, litellm_provider,
# ...) echoed by GET /model/info, so `model info <name>` confirms a synced param landed.
# ai_litellm_route_info (above) stays the slim model_name/provider_model/provider
# view; it is now purely an internal helper (proxy doctor + context probe) since
# the route CLI group retired in P4 (route info converged with model info earlier).
ai_litellm_model_info() {
  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "Missing curl or jq." >&2
    return 1
  fi

  local master_key
  master_key="$(ai_litellm_master_key 2>/dev/null)" || true
  if [[ -z "$master_key" ]]; then
    echo "Missing LiteLLM master key." >&2
    return 1
  fi

  local model_filter="$1"
  if [[ -n "$model_filter" ]]; then
    model_filter="$(ai_litellm_model_resolve "$model_filter" 2>/dev/null || printf '%s\n' "$model_filter")"
  fi

  local payload
  if ! payload="$(ai_litellm_curl_auth "$master_key" --max-time 5 -fsS "$(ai_litellm_base_url)/model/info")"; then
    echo "LiteLLM model metadata unavailable at $(ai_litellm_base_url)/model/info; is the proxy running?" >&2
    return 1
  fi

  if [[ -n "$model_filter" ]]; then
    local block
    block="$(print -r -- "$payload" \
      | jq --arg model "$model_filter" '.data[] | select(.model_name == $model) | .model_info')"
    if [[ -z "$block" || "$block" == "null" ]]; then
      echo "No model_info for '$model_filter' (not present in GET /model/info; is it synced and the proxy reloaded?)." >&2
      return 1
    fi
    print -r -- "$block"
  else
    print -r -- "$payload" | jq '[.data[] | {model_name, model_info}]'
  fi
}

ai_litellm_probe_route() {
  local model_name="$1"
  [[ -n "$model_name" ]] || {
    echo "Usage: claude-litellm probe-route <model_name> [model_name...]" >&2
    return 1
  }

  model_name="$(ai_litellm_model_resolve "$model_name" 2>/dev/null)" || {
    echo "fail $model_name: not present in $AI_LITELLM_CONFIG" >&2
    return 1
  }
  ai_litellm_model_runtime_ready "$model_name" || return 1

  local master_key payload
  master_key="$(ai_litellm_master_key 2>/dev/null)" || {
    echo "Missing LiteLLM master key." >&2
    return 1
  }
  payload="$(jq -nc --arg model "$model_name" '{
    model: $model,
    messages: [{role: "user", content: "Reply with exactly OK"}],
    max_tokens: 8,
    temperature: 0
  }')"

  if ai_litellm_curl_auth "$master_key" --max-time 90 -fsS \
    -H "Content-Type: application/json" \
    "$(ai_litellm_api_base_url)/chat/completions" \
    -d "$payload" \
    | jq -e '.choices[0].message.content // .choices[0].text // empty' >/dev/null; then
    echo "ok   route probe: $model_name"
    return 0
  fi

  echo "fail route probe: $model_name" >&2
  return 1
}

ai_litellm_probe_routes() {
  local failed=0
  if (( $# == 0 )); then
    echo "Usage: claude-litellm probe-route <model_name> [model_name...]" >&2
    return 1
  fi

  local model_name
  for model_name in "$@"; do
    ai_litellm_probe_route "$model_name" || failed=1
  done
  return $failed
}

ai_litellm_openrouter_key_status() {
  if [[ -n "$OPENROUTER_API_KEY" ]]; then
    echo "OPENROUTER_API_KEY: set in current environment"
    return 0
  fi

  if ai_litellm_env_value OPENROUTER_API_KEY >/dev/null 2>&1; then
    echo "OPENROUTER_API_KEY: available in env file"
    echo "Env file: $AI_LITELLM_ENV"
    return 0
  fi

  if ai_litellm_keychain_value "$OPENROUTER_KEYCHAIN_SERVICE" "$OPENROUTER_KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
    echo "OPENROUTER_API_KEY: available in macOS Keychain"
    echo "Keychain service: $OPENROUTER_KEYCHAIN_SERVICE"
    return 0
  fi

  echo "OPENROUTER_API_KEY: not found"
  echo "Expected env file: $AI_LITELLM_ENV"
  echo "Expected Keychain service: $OPENROUTER_KEYCHAIN_SERVICE"
  return 1
}

ai_litellm_master_key_status() {
  if [[ -n "$LITELLM_MASTER_KEY" ]]; then
    echo "LITELLM_MASTER_KEY: set in current environment"
    return 0
  fi

  if ai_litellm_env_value LITELLM_MASTER_KEY >/dev/null 2>&1; then
    echo "LITELLM_MASTER_KEY: available in env file"
    echo "Env file: $AI_LITELLM_ENV"
    return 0
  fi

  if ai_litellm_keychain_value "$LITELLM_MASTER_KEYCHAIN_SERVICE" "$LITELLM_MASTER_KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
    echo "LITELLM_MASTER_KEY: available in macOS Keychain"
    echo "Keychain service: $LITELLM_MASTER_KEYCHAIN_SERVICE"
    return 0
  fi

  echo "LITELLM_MASTER_KEY: not found"
  echo "Expected env file: $AI_LITELLM_ENV"
  echo "Expected Keychain service: $LITELLM_MASTER_KEYCHAIN_SERVICE"
  return 1
}

openrouter-key-load() {
  echo "OPENROUTER_API_KEY shell export is intentionally disabled; wrappers inject it only into subprocesses." >&2
  return 1
}

litellm-master-key-load() {
  echo "LITELLM_MASTER_KEY shell export is intentionally disabled; wrappers inject it only into subprocesses." >&2
  return 1
}

ai_litellm_key_status() {
  ai_litellm_openrouter_key_status
  ai_litellm_master_key_status
  local env_name source printed=0
  for env_name in "${(@f)$(ai_litellm_config_env_refs 2>/dev/null)}"; do
    case "$env_name" in OPENROUTER_API_KEY|LITELLM_MASTER_KEY) continue ;; esac
    if (( ! printed )); then
      echo "Provider credentials:"
      printed=1
    fi
    source="$(ai_litellm_key_source_env "$env_name" 2>/dev/null || printf missing)"
    printf '  %-32s %s\n' "$env_name" "$source"
  done
}

ai_litellm_key_source_env() {
  local env_name="$1" service account
  [[ "$env_name" =~ '^[A-Za-z_][A-Za-z0-9_]*$' ]] || return 1
  if [[ -n "${parameters[$env_name]:-}" && -n "${(P)env_name}" ]]; then printf 'environment\n'; return 0; fi
  if ai_litellm_env_value "$env_name" >/dev/null 2>&1; then printf 'env-file\n'; return 0; fi
  service="$(ai_litellm_json "secrets.$env_name.keychainService" 2>/dev/null || true)"
  account="$(ai_litellm_json "secrets.$env_name.keychainAccount" 2>/dev/null || printf '%s' "$USER")"
  [[ -n "$service" ]] || service="$(printf '%s' "$env_name" | tr 'A-Z_' 'a-z-')"
  if ai_litellm_keychain_value "$service" "$account" >/dev/null 2>&1; then printf 'keychain\n'; return 0; fi
  printf 'missing\n'
  return 1
}

# Mirror of ai_litellm_openrouter_key_status / ai_litellm_master_key_status detection order — keep in sync.
ai_litellm_key_source() {
  local key="$1"
  case "$key" in
    openrouter)
      if [[ -n "$OPENROUTER_API_KEY" ]]; then printf 'environment\n'; return 0; fi
      if ai_litellm_env_value OPENROUTER_API_KEY >/dev/null 2>&1; then printf 'env-file\n'; return 0; fi
      if ai_litellm_keychain_value "$OPENROUTER_KEYCHAIN_SERVICE" "$OPENROUTER_KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then printf 'keychain\n'; return 0; fi
      printf 'missing\n'; return 1
      ;;
    master)
      if [[ -n "$LITELLM_MASTER_KEY" ]]; then printf 'environment\n'; return 0; fi
      if ai_litellm_env_value LITELLM_MASTER_KEY >/dev/null 2>&1; then printf 'env-file\n'; return 0; fi
      if ai_litellm_keychain_value "$LITELLM_MASTER_KEYCHAIN_SERVICE" "$LITELLM_MASTER_KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then printf 'keychain\n'; return 0; fi
      printf 'missing\n'; return 1
      ;;
    *) printf 'missing\n'; return 1 ;;
  esac
}

ai_litellm_key_status_json() {
  local or_src ms_src providers='[]' env_name source row
  or_src="$(ai_litellm_key_source openrouter 2>/dev/null || printf 'missing')"
  ms_src="$(ai_litellm_key_source master 2>/dev/null || printf 'missing')"
  for env_name in "${(@f)$(ai_litellm_config_env_refs 2>/dev/null)}"; do
    case "$env_name" in OPENROUTER_API_KEY|LITELLM_MASTER_KEY) continue ;; esac
    source="$(ai_litellm_key_source_env "$env_name" 2>/dev/null || printf missing)"
    row="$(jq -cn --arg name "$env_name" --arg source "$source" '{name:$name,source:$source}')" || return 1
    providers="$(jq -cn --argjson rows "$providers" --argjson row "$row" '$rows + [$row]')" || return 1
  done
  node -e '
const [openrouter, master, providers] = process.argv.slice(1);
process.stdout.write(JSON.stringify({openrouter:{source:openrouter},master:{source:master},providers:JSON.parse(providers)}));
' "$or_src" "$ms_src" "$providers"
}

ai_litellm_key_name_to_env() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  case "$name" in
    openrouter|OPENROUTER_API_KEY) printf 'OPENROUTER_API_KEY\n' ;;
    litellm-master|master|LITELLM_MASTER_KEY) printf 'LITELLM_MASTER_KEY\n' ;;
    brave|brave-search|BRAVE_SEARCH_API_KEY) printf 'BRAVE_SEARCH_API_KEY\n' ;;
    *)
      local normalized
      normalized="${name:u}"
      normalized="${normalized//-/_}"
      if [[ "$normalized" == *[^A-Z0-9_]* ]]; then
        echo "Invalid key name: $name" >&2
        return 1
      fi
      case "$normalized" in
        *_API_KEY|*_KEY) printf '%s\n' "$normalized" ;;
        *) printf '%s_API_KEY\n' "$normalized" ;;
      esac
      ;;
  esac
}

_ai_litellm_key_set_unlocked() {
  local storage="env-file"
  while (( $# > 0 )); do
    case "$1" in
      --keychain) storage="keychain"; shift ;;
      --env-file) storage="env-file"; shift ;;
      --) shift; break ;;
      -*) echo "Unknown key set option: $1" >&2; return 1 ;;
      *) break ;;
    esac
  done

  local name="${1:-}"
  local value="${2:-}"
  local value_provided=0
  (( $# == 2 )) && value_provided=1
  if [[ -z "$name" || $# -gt 2 ]]; then
    echo "Usage: claude-litellm key set [--keychain|--env-file] <openrouter|ENV_VAR|provider-name> [value]" >&2
    echo "Omit [value] to enter it without echoing. Prefer --keychain on macOS." >&2
    return 1
  fi

  local env_key
  env_key="$(ai_litellm_key_name_to_env "$name")" || return $?
  if (( value_provided )); then
    echo "warn: passing secrets as command arguments may be recorded by your shell or process tools; omit [value] for hidden input." >&2
  fi

  if [[ "$storage" == "keychain" && "$value_provided" == "0" && -t 0 ]]; then
    local service account
    service="$(ai_litellm_keychain_service_for_env "$env_key")" || return $?
    account="$(ai_litellm_keychain_account_for_env "$env_key")" || return $?
    echo "Value for $env_key will be read by macOS Keychain prompt." >&2
    security add-generic-password -U -s "$service" -a "$account" -w || return $?
    echo "Stored $env_key in macOS Keychain service $service"
    if ai_litellm_env_value "$env_key" >/dev/null 2>&1; then
      echo "warn: $AI_LITELLM_ENV also contains $env_key and currently takes precedence over Keychain." >&2
    fi
    echo "Run 'claude-litellm sync' if the proxy is already running."
    return 0
  fi

  if [[ -z "$value" ]]; then
    printf 'Value for %s: ' "$env_key" >&2
    # zsh `read` returns nonzero on EOF-without-trailing-newline even though it
    # populated $value. The dashboard pipes a newline-less secret via stdin, so
    # a strict `read ... || return` aborted with "No value read" and the key was
    # never stored (round-2 review). Treat "read some bytes" as success; only a
    # genuinely empty read is a failure.
    IFS= read -rs value
    printf '\n' >&2
    if [[ -z "$value" ]]; then
      echo "No value read for $env_key." >&2
      return 1
    fi
  fi

  if [[ "$storage" == "keychain" ]]; then
    local service account
    service="$(ai_litellm_keychain_service_for_env "$env_key")" || return $?
    account="$(ai_litellm_keychain_account_for_env "$env_key")" || return $?
    ai_litellm_keychain_set_value "$service" "$account" "$value" || return $?
    echo "Stored $env_key in macOS Keychain service $service"
    if ai_litellm_env_value "$env_key" >/dev/null 2>&1; then
      echo "warn: $AI_LITELLM_ENV also contains $env_key and currently takes precedence over Keychain." >&2
    fi
  else
    ai_litellm_env_set_value "$env_key" "$value" || return $?
    echo "Stored $env_key in $AI_LITELLM_ENV"
  fi
  echo "Run 'claude-litellm sync' if the proxy is already running."
}

ai_litellm_key_set() {
  ai_litellm_lifecycle_lock_acquire || return $?
  local rc=0
  {
    if ! ai_litellm_install_integrity_ok; then
      echo "Installed package/runtime integrity failed; reinstall before changing provider credentials." >&2
      rc=1
    else
      _ai_litellm_key_set_unlocked "$@" || rc=$?
    fi
  } always {
    ai_litellm_lifecycle_lock_release
  }
  return $rc
}

ai_litellm_logs() {
  local lines="${1:-$(ai_litellm_json logs.tail 2>/dev/null || printf '120')}"
  local log_file
  log_file="$(ai_litellm_active_log_file)"
  [[ -f "$log_file" ]] || {
    echo "No LiteLLM log file found: $log_file" >&2
    return 1
  }
  tail -n "$lines" "$log_file"
}

ai_litellm_doctor_check() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok   $label"
    return 0
  fi
  echo "fail $label"
  return 1
}

ai_litellm_quiet() {
  "$@" >/dev/null 2>&1
}

ai_litellm_doctor_warn_env() {
  [[ -n "$OPENROUTER_API_KEY" ]] && echo "warn OPENROUTER_API_KEY is set in current environment"
  [[ -n "$LITELLM_MASTER_KEY" ]] && echo "warn LITELLM_MASTER_KEY is set in current environment"
}

ai_litellm_doctor_harnesses() {
  local failed=0
  local harness
  for harness in "${(@f)$(ai_litellm_harness_names)}"; do
    ai_litellm_doctor_check "harness descriptor valid: $harness" ai_litellm_harness_validate "$harness" || failed=1
    if ! ai_litellm_harness_cli_available "$harness" >/dev/null 2>&1; then
      echo "warn harness CLI not installed: $harness ($(ai_litellm_harness_json "$harness" command 2>/dev/null || printf 'unknown'))"
    fi
  done
  return $failed
}

ai_litellm_doctor_reasoning_capability_truth() {
  local litellm_python
  litellm_python="$(ai_litellm_litellm_python 2>/dev/null)" || {
    echo "warn reasoning capability: LiteLLM Python runtime not available"
    return 0
  }

  ai_litellm_python_isolated "$litellm_python" - "$AI_LITELLM_CONFIG" "$AI_LITELLM_REASONING_OBS_FILE" <<'PY'
import json
import sys

import yaml

try:
    import litellm
except Exception as exc:
    print(f"warn reasoning capability: cannot import litellm ({exc})")
    raise SystemExit(0)

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    config = yaml.safe_load(fh) or {}
try:
    with open(sys.argv[2], "r", encoding="utf-8") as fh:
        observations = json.load(fh)
except Exception:
    observations = {}

drop_params = bool((config.get("litellm_settings") or {}).get("drop_params"))
seen = set()
for entry in config.get("model_list") or []:
    name = entry.get("model_name")
    litellm_params = entry.get("litellm_params") or {}
    backend = litellm_params.get("model")
    if not name or not backend:
        continue
    if (entry.get("model_info") or {}).get("supports_reasoning") is not True:
        continue
    # Never let a read-only doctor trigger OAuth/device login. OAuth capability
    # truth is checked from x_reasoning_efforts by the metadata doctor.
    if backend.startswith("chatgpt/") or litellm_params.get("use_xai_oauth") is True:
        continue
    key = (backend, drop_params)
    if key in seen:
        continue
    seen.add(key)
    # A 2xx probe response—even one containing reasoning—cannot prove that a
    # requested effort level was forwarded, honored, or changed behavior. Do
    # not let historical probe observations suppress this static drop check.
    try:
        params = litellm.get_supported_openai_params(model=backend) or []
        supported = bool(litellm.supports_reasoning(model=backend)) or any(
            p in params for p in ("reasoning_effort", "reasoning", "thinking")
        )
    except Exception:
        supported = False
    if not supported:
        mode = "dropped" if drop_params else "rejected"
        print(f"warn declared reasoning may be {mode} by local LiteLLM for backend {backend}")
PY
}

ai_litellm_runtime_discovery_enabled() {
  local runtime="$1"
  local value
  value="$(ai_litellm_runtime_field "$runtime" discoverModels 2>/dev/null || printf 'false')"
  [[ "$value" == "true" ]]
}

ai_litellm_runtime_routes_write() {
  local runtime="$1"
  local dry_run="$2"
  shift 2
  ai_litellm_ruby -ryaml -rjson -e '
settings_path, config_path, runtime_name, dry_run, *model_ids = ARGV
settings = JSON.parse(File.read(settings_path))
rt = (settings["runtimes"] || {})[runtime_name] || {}
api_base = rt["apiBase"].to_s
if api_base.empty?
  warn "runtime #{runtime_name}: apiBase is required for discovered routes"
  exit 1
end

# Fallback mirror of settings.json runtimes.<rt>.defaultModelInfo; keep the
# two in sync (deleting the settings block silently reverts to this copy).
default_info = rt["defaultModelInfo"] || {
  "max_input_tokens" => 8192,
  "max_output_tokens" => 4096,
  "supports_reasoning" => false,
  "x_reasoning_efforts" => [],
  "x_input_confidence" => "owned-policy",
  "x_input_source" => "quality-conservative-local-policy; runtime-specific",
  "x_output_confidence" => "owned-policy",
  "x_output_source" => "quality-conservative-local-policy",
  "x_reasoning_confidence" => "owned-policy",
  "x_reasoning_source" => "local-runtime-no-reasoning-routing"
}

# Per-model overrides for discovered routes: glob patterns matched against the
# upstream model id and the generated route name; later patterns win.
overrides = rt["modelInfoOverrides"] || {}
info_for = lambda do |model_id, route|
  info = default_info.dup
  overrides.each do |pattern, partial|
    next unless partial.is_a?(Hash)
    if File.fnmatch(pattern, model_id.to_s, File::FNM_CASEFOLD) ||
       File.fnmatch(pattern, route.to_s, File::FNM_CASEFOLD)
      info = info.merge(partial)
    end
  end
  info
end

# Per-route litellm_params overrides for discovered routes (e.g. thinking-off
# via extra_body.chat_template_kwargs). Same glob semantics as modelInfoOverrides
# (matched on upstream model id AND route name, later pattern wins whole-key).
# This is how a model qualified as "thinking-off" gets the param injected into
# its sync-regenerated route without hand-promotion. Default {} = no change.
param_overrides = rt["litellmParamsOverrides"] || {}
params_for = lambda do |model_id, route|
  extra = {}
  matched = []
  param_overrides.each do |pattern, partial|
    next unless partial.is_a?(Hash)
    if File.fnmatch(pattern, model_id.to_s, File::FNM_CASEFOLD) ||
       File.fnmatch(pattern, route.to_s, File::FNM_CASEFOLD)
      extra = extra.merge(partial)
      matched << pattern
    end
  end
  [extra, matched]
end
emit_params = lambda do |hash, indent|
  YAML.dump(hash).sub(/\A---\s*\n?/, "").each_line
    .map { |l| l.strip.empty? ? "\n" : (" " * indent) + l }.join
end

start_marker = "# BEGIN claude-litellm discovered local routes"
end_marker = "# END claude-litellm discovered local routes"
original = File.read(config_path)

clean_lines = []
in_block = false
original.each_line do |line|
  if line.start_with?(start_marker)
    in_block = true
    next
  end
  if line.start_with?(end_marker)
    in_block = false
    next
  end
  clean_lines << line unless in_block
end
clean = clean_lines.join
config = (YAML.load(clean, aliases: true) rescue YAML.load(clean))
existing = Array(config["model_list"]).map { |entry| entry["model_name"] }.compact
# Registry entries already serving the same upstream (model, api_base) make a
# discovered route redundant even under a different name (e.g. a promoted
# first-class entry like Qwen3.6-27B-oMLX).
existing_backends = {}
Array(config["model_list"]).each do |entry|
  params = entry["litellm_params"] || {}
  existing_backends[[params["model"].to_s, params["api_base"].to_s]] = true
end

# Route naming: <CleanedModelId>-<runtime> (suffix auto-derived from the
# runtime name, lowercase; modelSuffix overrides if explicitly set).
suffix = rt["modelSuffix"].to_s
suffix = "-#{runtime_name.to_s.downcase}" if suffix.empty?
clean_id = lambda do |value|
  value.to_s
    .gsub(%r{\Aopenai/}, "")
    .gsub(/[^A-Za-z0-9._-]+/, "-")
    .gsub(/\A[-.]+|[-.]+\z/, "")
end
scalar = lambda do |value|
  YAML.dump(value).strip.sub(/\A---\s*/, "")
end

seen = {}
routes = model_ids.map do |model_id|
  next if model_id.to_s.empty?
  base = clean_id.call(model_id)
  route = base.end_with?(suffix) ? base : "#{base}#{suffix}"
  next if route == suffix
  next if existing.include?(route) || seen[route]
  next if existing_backends[["openai/#{model_id}", api_base]]
  seen[route] = true
  [route, model_id]
end.compact

routes.each do |route, model_id|
  _extra, matched = params_for.call(model_id, route)
  suffix_note = matched.empty? ? "" : "  [litellm_params override: #{matched.join(%q{,})}]"
  puts "  + #{route} -> openai/#{model_id}#{suffix_note}"
end
exit 0 if dry_run == "1"

block = ""
unless routes.empty?
  block << "#{start_marker}\n"
  block << "# Managed by `claude-litellm sync`; generated from runtimes.#{runtime_name} /v1/models.\n"
  routes.each do |route, model_id|
    block << "  - model_name: #{scalar.call(route)}\n"
    block << "    litellm_params:\n"
    block << "      model: #{scalar.call("openai/#{model_id}")}\n"
    block << "      api_base: #{scalar.call(api_base)}\n"
    block << "      api_key: none\n"
    extra_params, = params_for.call(model_id, route)
    block << emit_params.call(extra_params, 6) unless extra_params.empty?
    # Inline, not *anchor refs: this block is regenerated wholesale and these
    # numbers are runtime POLICY (defaults/overrides), not provider capability
    # (see the ai_litellm_model_info_anchor_refs_ok exemption).
    block << "    model_info:\n"
    block << "      x_registry_source: runtime-discovery\n"
    info_for.call(model_id, route).each do |key, value|
      block << "      #{key}: #{scalar.call(value)}\n"
    end
  end
  block << "#{end_marker}\n\n"
end

insert_at = clean_lines.index { |line| line =~ /\Ageneral_settings:\s*$/ }
if insert_at.nil?
  warn "Cannot find general_settings: insertion point in #{config_path}"
  exit 1
end

next_lines = clean_lines.dup
next_lines.insert(insert_at, block) unless block.empty?
tmp = "#{config_path}.tmp.#{$$}"
File.write(tmp, next_lines.join)
File.rename(tmp, config_path)
' "$AI_LITELLM_SETTINGS" "$AI_LITELLM_CONFIG" "$runtime" "$dry_run" "$@"
}

ai_litellm_runtime_routes_refresh() {
  local dry_run="${1:-0}"
  local failed=0 runtime
  ai_litellm_runtime_discovery_layout_ok || return 1
  for runtime in "${(@f)$(ai_litellm_runtime_names 2>/dev/null)}"; do
    [[ -n "$runtime" ]] || continue
    ai_litellm_runtime_discovery_enabled "$runtime" || continue
    if ! ai_litellm_runtime_reachable "$runtime"; then
      echo "- runtime routes skipped: $runtime not reachable"
      continue
    fi
    # Distinguish a discovery FAILURE (unreachable mid-call, or /v1/models
    # returns an unparseable body even though it 200'd) from a genuine empty
    # model list. On failure we must NOT rewrite — passing an empty list to
    # routes_write would wipe every existing discovered route for this runtime
    # silently. Keep the existing routes and warn loud instead.
    local discovery_out discovery_rc
    discovery_out="$(ai_litellm_runtime_available_models "$runtime" 2>/dev/null)"
    discovery_rc=$?
    if (( discovery_rc != 0 )); then
      echo "- runtime routes skipped: $runtime discovery failed (rc=$discovery_rc, /v1/models unparseable); existing routes kept" >&2
      failed=1
      continue
    fi
    local -a available_models
    available_models=("${(@f)discovery_out}")
    available_models=("${(@)available_models:#}")
    echo "- runtime routes: $runtime (${#available_models[@]} discovered)"
    ai_litellm_runtime_routes_write "$runtime" "$dry_run" "${available_models[@]}" || failed=1
  done
  return $failed
}

ai_litellm_runtime_discovery_layout_ok() {
  local count=0 runtime
  local -a enabled
  for runtime in "${(@f)$(ai_litellm_runtime_names 2>/dev/null)}"; do
    [[ -n "$runtime" ]] || continue
    if ai_litellm_runtime_discovery_enabled "$runtime"; then
      enabled+=("$runtime")
      (( count += 1 ))
    fi
  done
  if (( count > 1 )); then
    echo "Only one discoverModels runtime is currently supported by the generated route block (enabled: ${(j:, :)enabled})." >&2
    return 1
  fi
  return 0
}

# Regenerate every derived artifact from the single source and reload the proxy.
# After editing a token limit in litellm_config.yaml, this is the one command to run.
_ai_litellm_sync_unlocked() {
  local failed=0 dry_run=0 restart=1 arg mutation_lock_held=0 mutation_lock_preowned=0
  for arg in "$@"; do
    case "$arg" in
      --dry-run)
        dry_run=1
        restart=0
        ;;
      --no-restart)
        restart=0
        ;;
      -h|--help)
        echo "Usage: claude-litellm sync [--dry-run] [--no-restart]"
        echo "  --dry-run     print derived-artifact actions without writing or restarting"
        echo "  --no-restart  regenerate derived artifacts without restarting the shared proxy"
        return 0
        ;;
      *)
        echo "Unknown sync option: $arg" >&2
        return 1
        ;;
    esac
  done

  echo "claude-litellm sync"
  (( dry_run )) && echo "- dry-run: no files will be changed and proxy will not restart"

  # Serialize the multi-file rewrite against another sync. Uses a DEDICATED lock
  # (not the proxy-start lock) so the restart step's own ai_litellm_start can still
  # acquire AI_LITELLM_LOCK_DIR without deadlocking. Non-blocking: a second sync
  # fails loud rather than interleaving cross-file writes. dry-run writes nothing,
  # so it needs no lock. Kernel flock ownership auto-releases on death; the
  # directory remains only as human-readable/legacy compatibility metadata.
  local sync_lock="$AI_LITELLM_PROXY_HOME/litellm.sync.lock" sync_lock_held=0 sync_fd="" other_pid=""
  {
  if (( ! dry_run )); then
    mkdir -p "$AI_LITELLM_PROXY_HOME"
    zmodload zsh/system || return 1
    ai_litellm_lock_file_prepare "${sync_lock}.flock" || return 1
    if ! zsystem flock -t 0 -f sync_fd "${sync_lock}.flock"; then
      echo "claude-litellm sync: another sync is in progress; refusing to run concurrently." >&2
      return 1
    fi
    chmod 600 "${sync_lock}.flock" 2>/dev/null || true
    if [[ -d "$sync_lock" ]]; then
      other_pid="$(<"$sync_lock/pid" 2>/dev/null || printf '?')"
      if [[ "$other_pid" != '?' ]] && kill -0 "$other_pid" 2>/dev/null; then
        zsystem flock -u "$sync_fd" 2>/dev/null || true
        echo "claude-litellm sync: another sync is in progress (legacy lock pid $other_pid)." >&2
        return 1
      fi
      rm -rf "$sync_lock"
    elif [[ -e "$sync_lock" || -L "$sync_lock" ]]; then
      zsystem flock -u "$sync_fd" 2>/dev/null || true
      echo "claude-litellm sync: unsafe non-directory lock path: $sync_lock" >&2
      return 1
    fi
    mkdir "$sync_lock" || { zsystem flock -u "$sync_fd" 2>/dev/null || true; return 1; }
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$sync_lock/started_at"
    printf '%s\n' "$$" > "$sync_lock/pid"
    sync_lock_held=1
    # Sweep orphaned tmp files from a sync that was killed between write and rename.
    # (N) = zsh nullglob qualifier: no error when nothing matches.
    rm -f -- "${AI_LITELLM_CONFIG}".tmp.*(N) 2>/dev/null || true
    [[ "${AI_LITELLM_USER_MUTATION_FD:-}" == <-> ]] && mutation_lock_preowned=1
    if ! ai_litellm_user_mutation_lock_acquire; then
      rm -rf "$sync_lock" 2>/dev/null
      zsystem flock -u "$sync_fd" 2>/dev/null || true
      echo "claude-litellm sync: a model/alias mutation is in progress; refusing to interleave configuration writes." >&2
      return 1
    fi
    mutation_lock_held=1
  fi

  # Rebuild the effective registry/settings from immutable package defaults and
  # durable user overlays before runtime discovery adds its generated block.
  echo "- user model/Claude settings overlays"
  if (( dry_run )); then
    if ! ai_litellm_render_user_config --validate-only; then
      echo "claude-litellm sync: overlay validation failed; no derived artifact was changed." >&2
      return 1
    fi
  else
    if ! ai_litellm_render_user_config; then
      echo "claude-litellm sync: overlay rendering failed; runtime discovery and proxy restart were skipped." >&2
      (( mutation_lock_held && ! mutation_lock_preowned )) && ai_litellm_user_mutation_lock_release
      (( sync_lock_held )) && rm -rf "$sync_lock" 2>/dev/null
      [[ "$sync_fd" == <-> ]] && zsystem flock -u "$sync_fd" 2>/dev/null || true
      return 1
    fi
  fi

  # Discover local routes after the effective base has been rebuilt.
  ai_litellm_runtime_routes_refresh "$dry_run" || failed=1

  # The runtime writer owns only the validated discovered-route block and uses
  # a compact line-oriented replacement. Normalize the complete effective
  # files once more so whitespace around that block, user-model insertion, and
  # the Claude settings bytes remain exactly what --check will reconstruct at
  # proxy startup. The renderer carries forward and validates the block that
  # discovery just wrote; it does not query the runtime again.
  if (( ! dry_run )); then
    ai_litellm_render_user_config >/dev/null || failed=1
  fi

  if ai_litellm_harness_descriptor claude >/dev/null 2>&1; then
    echo "- claude settings"
    if (( ! dry_run )); then
      ai_litellm_render_claude_settings claude || failed=1
    fi
    echo "- claude shared environment links"
    if (( ! dry_run )); then
      ai_litellm_shared_env_links_ensure claude "$(ai_litellm_harness_json claude paths.configDir)" || failed=1
    fi
  fi

  if (( restart )); then
    echo "- proxy restart (reloads model_info + enforcement)"
    ai_litellm_restart || failed=1
  else
    echo "- proxy restart skipped"
  fi

  echo "- claude output limits derive at next launch"
  (( mutation_lock_held && ! mutation_lock_preowned )) && ai_litellm_user_mutation_lock_release
  (( sync_lock_held )) && rm -rf "$sync_lock" 2>/dev/null
  [[ "$sync_fd" == <-> ]] && zsystem flock -u "$sync_fd" 2>/dev/null || true
  return $failed
  } always {
    (( mutation_lock_held && ! mutation_lock_preowned )) && ai_litellm_user_mutation_lock_release
    (( sync_lock_held )) && rm -rf "$sync_lock" 2>/dev/null || true
    [[ "$sync_fd" == <-> ]] && zsystem flock -u "$sync_fd" 2>/dev/null || true
  }
}

ai_litellm_sync() {
  ai_litellm_lifecycle_lock_acquire || return $?
  local rc=0
  {
    _ai_litellm_sync_unlocked "$@" || rc=$?
  } always {
    ai_litellm_lifecycle_lock_release
  }
  return $rc
}

ai_litellm_doctor_local_route_uniqueness() {
  # Scope: local-runtime routes only (api_key: none marker). Remote routes may
  # legitimately duplicate model_name for LiteLLM load balancing; a duplicated
  # local route is always a discovery/promotion bug.
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
local_names = Array(config["model_list"])
  .select { |entry| entry.dig("litellm_params", "api_key").to_s == "none" }
  .map { |entry| entry["model_name"] }
  .compact
counts = Hash.new(0)
local_names.each { |name| counts[name] += 1 }
duplicates = counts.select { |_name, count| count > 1 }.keys
if duplicates.any?
  warn "duplicate local model_name entries: #{duplicates.join(", ")}"
  exit 1
end
' "$AI_LITELLM_CONFIG"
}

ai_litellm_doctor_runtimes() {
  local failed=0 rt
  for rt in "${(@f)$(ai_litellm_runtime_names 2>/dev/null)}"; do
    [[ -n "$rt" ]] || continue
    ai_litellm_doctor_check "runtime block valid: $rt" ai_litellm_runtime_validate "$rt" || failed=1
  done
  return $failed
}

ai_litellm_install_integrity_ok() {
  local manifest="$AI_LITELLM_HOME/install-manifest.json"
  local python="$AI_LITELLM_HOME/runtime/venv/bin/python"
  local verifier="$AI_LITELLM_HOME/scripts/verify-install.py"
  local external_python
  [[ -f "$manifest" && ! -L "$manifest" && "$(stat -f %Lp "$manifest" 2>/dev/null)" == "600" ]] || return 1
  [[ -x "$python" && -f "$verifier" && ! -L "$verifier" ]] || return 1
  external_python="$(ai_litellm_external_python)" || return 1

  # The external interpreter measures every package/runtime byte first. Only
  # after that succeeds is the managed interpreter allowed to initialize its
  # site-packages and prove the live import/dependency contract.
  ai_litellm_python_isolated "$external_python" -S "$verifier"     --prefix "$AI_LITELLM_HOME" >/dev/null || return 1
  ai_litellm_python_isolated "$python" - "$manifest" <<'PY'
import hashlib
import importlib.metadata as metadata
import json
import platform

try:
    runtime = json.load(open(__import__("sys").argv[1], encoding="utf-8"))["runtime"]
except (OSError, ValueError, KeyError, TypeError):
    raise SystemExit(1)
packages = sorted(
    f"{dist.metadata['Name'].lower().replace('_', '-')}=={dist.version}"
    for dist in metadata.distributions()
    if dist.metadata.get("Name")
)
if not (
    platform.python_version() == runtime.get("python")
    and metadata.version("litellm") == "1.92.0"
    and metadata.version("prisma") == "0.15.0"
    and hashlib.sha256("\n".join(packages).encode()).hexdigest()
        == runtime.get("dependencyFingerprint")
):
    raise SystemExit(1)
import fastapi, litellm, prisma, uvicorn  # noqa: F401,E402
import litellm.proxy.proxy_cli  # noqa: F401,E402
PY
}

ai_litellm_doctor_runtime() {
  local runtime="$1"
  if [[ -z "$runtime" ]]; then
    echo "Usage: claude-litellm doctor --runtime <name>" >&2
    return 1
  fi

  local failed=0
  echo "claude-litellm doctor --runtime $runtime"
  ai_litellm_doctor_check "runtime block valid" ai_litellm_runtime_validate "$runtime" || failed=1
  ai_litellm_doctor_check "runtime configured" ai_litellm_quiet ai_litellm_runtime_field "$runtime" apiBase || failed=1

  local models_dir
  models_dir="$(ai_litellm_runtime_field "$runtime" modelsDir 2>/dev/null || true)"
  if [[ -n "$models_dir" ]]; then
    ai_litellm_doctor_check "model directory exists" test -d "$models_dir" || failed=1
  else
    echo "fail model directory configured"
    failed=1
  fi

  # Generalized binary check: prefer an explicit startCommandBinary, else derive
  # the binary from the first word of startCommand. Works for any runtime, not omlx.
  local start_binary start_cmd
  start_binary="$(ai_litellm_runtime_field "$runtime" startCommandBinary 2>/dev/null || true)"
  if [[ -z "$start_binary" ]]; then
    start_cmd="$(ai_litellm_runtime_field "$runtime" startCommand 2>/dev/null || true)"
    start_binary="${start_cmd%% *}"
  fi
  if [[ -n "$start_binary" ]]; then
    ai_litellm_doctor_check "runtime command available: $start_binary" ai_litellm_quiet command -v "$start_binary" || failed=1
  fi

  if ai_litellm_runtime_reachable "$runtime"; then
    echo "ok   runtime endpoint reachable"
    local model
    local -a expected_models missing_models available_models
    expected_models=("${(@f)$(ai_litellm_runtime_expected_models "$runtime" 2>/dev/null)}")
    expected_models=("${(@)expected_models:#}")
    for model in "${expected_models[@]}"; do
      if ! ai_litellm_doctor_check "runtime model available: $model" ai_litellm_runtime_model_available "$runtime" "$model"; then
        failed=1
        missing_models+=("$model")
      fi
    done
    if (( ${#missing_models[@]} > 0 )); then
      available_models=("${(@f)$(ai_litellm_runtime_available_models "$runtime" 2>/dev/null)}")
      available_models=("${(@)available_models:#}")
      if (( ${#available_models[@]} > 0 )); then
        echo "Runtime advertises models:"
        printf '  %s\n' "${available_models[@]}"
      fi
    fi
  else
    echo "fail runtime endpoint reachable"
    echo "hint start manually: $(ai_litellm_runtime_field "$runtime" startCommand 2>/dev/null || printf 'manual start')"
    failed=1
  fi

  return $failed
}

ai_litellm_capabilities() {
  echo "claude-litellm capabilities"
  echo "Proxy: $(ai_litellm_base_url)"
  if ai_litellm_health; then
    echo "Proxy health: ok"
  else
    echo "Proxy health: not reachable"
  fi
  echo "Runtime policy: manual start/stop, early inactive-runtime errors, no fallback"
  echo "LiteLLM drop_params: $(ai_litellm_litellm_setting drop_params 2>/dev/null || printf 'unset')"
  echo
  ai_litellm_runtime_status
}

ai_litellm_doctor() {
  if [[ "$1" == "--runtime" ]]; then
    shift
    ai_litellm_doctor_runtime "$@"
    return $?
  fi

  local probe_routes=0
  local -a probe_models
  while (( $# > 0 )); do
    case "$1" in
      --probe-routes)
        probe_routes=1
        ;;
      --probe-model)
        shift
        [[ -n "$1" ]] || {
          echo "Missing model after --probe-model" >&2
          return 1
        }
        probe_models+=("$1")
        ;;
      *)
        echo "Unknown doctor option: $1" >&2
        return 1
        ;;
    esac
    shift
  done

  local failed=0
  echo "claude-litellm doctor"
  ai_litellm_doctor_warn_env
  ai_litellm_doctor_check "config exists" test -f "$AI_LITELLM_CONFIG" || failed=1
  ai_litellm_doctor_check "settings exists" test -f "$AI_LITELLM_SETTINGS" || failed=1
  ai_litellm_doctor_check "installed package/runtime provenance intact" ai_litellm_quiet ai_litellm_install_integrity_ok || failed=1
  ai_litellm_doctor_check "user overlays valid and private" ai_litellm_quiet ai_litellm_render_user_config --check || failed=1
  ai_litellm_doctor_check "lib syntax" zsh -n "$AI_LITELLM_CONFIG_HOME/ai-litellm/lib.zsh" || failed=1
  ai_litellm_doctor_check "claude helper syntax" zsh -n "$AI_LITELLM_CONFIG_HOME/claude-litellm/shell.zsh" || failed=1
  ai_litellm_doctor_check "claude-litellm command syntax" zsh -n "$AI_LITELLM_BIN_DIR/claude-litellm" || failed=1
  ai_litellm_doctor_check "managed litellm command available" test -x "$AI_LITELLM_HOME/runtime/venv/bin/litellm" || failed=1
  ai_litellm_doctor_check "node command available" ai_litellm_quiet command -v node || failed=1
  ai_litellm_doctor_check "curl command available" ai_litellm_quiet command -v curl || failed=1
  ai_litellm_doctor_check "jq command available" ai_litellm_quiet command -v jq || failed=1
  # Only require the OpenRouter key if the registry actually references it (same
  # gate as ai_litellm_start), so a non-OpenRouter fabric does not false-FAIL.
  if grep -q 'os\.environ/OPENROUTER_API_KEY' "$AI_LITELLM_CONFIG" 2>/dev/null; then
    if ai_litellm_quiet ai_litellm_openrouter_key; then
      echo "ok   OpenRouter key available"
    else
      echo "warn OpenRouter key missing; only OpenRouter routes are unavailable"
    fi
  fi
  # Every other provider key the registry references must resolve too.
  local _pref
  for _pref in ${(f)"$(ai_litellm_config_env_refs 2>/dev/null)"}; do
    case "$_pref" in
      OPENROUTER_API_KEY|LITELLM_MASTER_KEY) continue ;;
    esac
    ai_litellm_doctor_check "provider key available: $_pref" ai_litellm_quiet ai_litellm_resolve_secret_var "$_pref" || failed=1
  done
  ai_litellm_doctor_check "LiteLLM master key available" ai_litellm_quiet ai_litellm_master_key || failed=1
  ai_litellm_doctor_harnesses || failed=1
  ai_litellm_doctor_check "local model routes are unique" ai_litellm_doctor_local_route_uniqueness || failed=1
  ai_litellm_doctor_check "gateway output clamp policy valid" ai_litellm_context_gateway_clamp_policy_ok || failed=1
  ai_litellm_doctor_check "output reservation policy aligned" ai_litellm_context_output_reservation_aligned || failed=1
  ai_litellm_doctor_check "gateway output clamp configured" ai_litellm_context_gateway_clamp_configured || failed=1
  ai_litellm_doctor_check "gateway estimated-token cost guardrail policy valid" ai_litellm_context_gateway_cost_guardrail_policy_ok || failed=1
  ai_litellm_doctor_check "gateway estimated-token cost guardrail configured" ai_litellm_context_gateway_cost_guardrail_configured || failed=1
  ai_litellm_doctor_check "context observations readable" ai_litellm_context_observations_ok || failed=1
  ai_litellm_doctor_check "harness output reservations leave input budget" ai_litellm_context_harness_reservations_ok || failed=1
  ai_litellm_doctor_reasoning_capability_truth
  ai_litellm_doctor_runtimes || failed=1
  ai_litellm_doctor_check "runtime discovery layout supported" ai_litellm_runtime_discovery_layout_ok || failed=1
  ai_litellm_doctor_check "runtime/registry consistency" ai_litellm_runtime_consistency || failed=1
  ai_litellm_doctor_check "runtime endpoints do not collide" ai_litellm_runtime_ports_ok || failed=1
  if ai_litellm_health; then
    echo "ok   proxy health"
    ai_litellm_doctor_check "route metadata reachable" ai_litellm_quiet ai_litellm_route_info || failed=1
    ai_litellm_doctor_check "running proxy loaded current config" ai_litellm_proxy_config_current || failed=1
    ai_litellm_doctor_check "running proxy routes match config" ai_litellm_proxy_registry_matches_file || failed=1
  else
    echo "warn proxy health not reachable"
  fi
  if (( probe_routes )); then
    if (( ${#probe_models[@]} == 0 )); then
      probe_models=("${(@f)$(ai_litellm_model_names)}")
    fi
    ai_litellm_probe_routes "${probe_models[@]}" || failed=1
  elif (( ${#probe_models[@]} > 0 )); then
    ai_litellm_probe_routes "${probe_models[@]}" || failed=1
  fi
  return $failed
}

# Token-limit table from the single source. Powers `claude-litellm model limits`.
ai_litellm_limits_table() {
  local filter="${1:-}" rows
  rows="$(ai_litellm_model_limits_json "$filter")" || return $?
  printf "%-30s %-11s %-11s %-11s %-14s %-14s\n" \
    "model_name" "context" "output_cap" "reserved" "effective_input" "sources"
  print -r -- "$rows" | jq -r '.[] | [
    .model,
    (.context // "-" | tostring),
    (.output // "-" | tostring),
    (.outputReservation // "-" | tostring),
    (.effectiveInput // "-" | tostring),
    ((.sources.context // "-") + "/" + (.sources.output // "-"))
  ] | @tsv' | while IFS=$'\t' read -r name context output reservation effective sources; do
    printf "%-30s %-11s %-11s %-11s %-14s %-14s\n" \
      "$name" "$context" "$output" "$reservation" "$effective" "$sources"
  done
}

ai_litellm_model_limits_json() {
  local filter="${1:-}"
  [[ -z "$filter" ]] || filter="$(ai_litellm_model_resolve "$filter" 2>/dev/null || printf '%s\n' "$filter")"
  local rows
  rows="$(ai_litellm_ruby -ryaml -rjson -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue (YAML.load_file(ARGV[0]) rescue nil))
filter = ARGV[1]
rows = []
Array(config && config["model_list"]).each do |entry|
  name = entry["model_name"]
  next unless name
  next if filter && !filter.empty? && name != filter
  mi = entry["model_info"] || {}
  ctx = mi["max_input_tokens"]
  out = mi["max_output_tokens"]
  rows << {
    "model" => name,
    "context" => ctx,
    "output" => out,
    "sources" => {"context" => (mi["x_input_confidence"] || "local-config"), "output" => (mi["x_output_confidence"] || "local-config")}
  }
end
print JSON.generate(rows)
' "$AI_LITELLM_CONFIG" "$filter" 2>/dev/null)" || { printf "[]"; return 0; }

  # max_output_tokens is a capability ceiling, not what Claude reserves on
  # every request. Report the same descriptor policy used at launch so large
  # context models do not misleadingly show zero effective input.
  local -a enriched
  local row name budget merged
  for row in "${(@f)$(print -r -- "$rows" | jq -c '.[]')}"; do
    name="$(print -r -- "$row" | jq -r '.model')"
    budget="$(ai_litellm_harness_output_budget claude "$name" "$name" 2>/dev/null || printf '{}')"
    merged="$(jq -cn --argjson row "$row" --argjson budget "$budget" '
      $row + {
        outputReservation: ($budget.reservation // null),
        tokenizerHeadroom: ($budget.tokenizerHeadroom // null),
        effectiveInput: ($budget.effectiveInput // null),
        reservationSource: ($budget.source // null)
      }')" || return 1
    enriched+=("$merged")
  done
  printf '%s\n' "${enriched[@]}" | jq -sc '.'
}

ai_litellm_model_refresh_capabilities() {
  local apply=0 as_json=0 check=0
  while (( $# > 0 )); do
    case "$1" in
      --apply) apply=1 ;;
      --json) as_json=1 ;;
      --check) check=1 ;;
      -h|--help)
        if [[ "$AI_LITELLM_BASE_CONFIG" != "$AI_LITELLM_CONFIG" ]]; then
          cat <<'EOF'
Usage: claude-litellm model refresh-capabilities [--json] [--check]

Audit installed OpenRouter-backed limits against OpenRouter /api/v1/models.
Installed package defaults are immutable; refresh a user route with remove/add,
qualification, and reactivation. --apply is source-maintainer-only.
EOF
        else
          cat <<'EOF'
Usage: claude-litellm model refresh-capabilities [--apply] [--json] [--check]

Reconcile OpenRouter-backed x-limits anchors with OpenRouter /api/v1/models.
Default mode is read-only. --apply updates provider-published fields only.
Set AI_LITELLM_OPENROUTER_MODELS_JSON to a local fixture path for offline tests.
EOF
        fi
        return 0
        ;;
      *) echo "Usage: claude-litellm model refresh-capabilities [--apply] [--json] [--check]" >&2; return 1 ;;
    esac
    shift
  done

  if (( apply )) && [[ "$AI_LITELLM_BASE_CONFIG" != "$AI_LITELLM_CONFIG" ]]; then
    echo "Installed package defaults are immutable; refresh-capabilities --apply is source-maintainer-only." >&2
    echo "Use --check to audit installed routes, or add a freshly cataloged user route with model add." >&2
    return 1
  fi

  local payload_file cleanup=0
  if [[ -n "${AI_LITELLM_OPENROUTER_MODELS_JSON:-}" ]]; then
    payload_file="$AI_LITELLM_OPENROUTER_MODELS_JSON"
    [[ -f "$payload_file" ]] || { echo "Missing AI_LITELLM_OPENROUTER_MODELS_JSON file: $payload_file" >&2; return 1; }
  else
    payload_file="$(mktemp "${TMPDIR:-/tmp}/openrouter-models.json.XXXXXX")" || return 1
    cleanup=1
    curl --connect-timeout 10 --max-time 60 -fsSL https://openrouter.ai/api/v1/models > "$payload_file" || {
      (( cleanup )) && rm -f "$payload_file"
      return 1
    }
  fi

  ai_litellm_ruby -rjson -ryaml - "$AI_LITELLM_CONFIG" "$payload_file" "$apply" "$as_json" "$check" <<'RUBY'
config_path, provider_path, apply_raw, json_raw, check_raw = ARGV
apply_changes = apply_raw == "1"
as_json = json_raw == "1"
check = check_raw == "1"

def positive_int(value)
  n = Integer(value)
  n.positive? ? n : nil
rescue
  nil
end

def yaml_scalar(value)
  case value
  when Integer
    value.to_s
  when TrueClass, FalseClass
    value ? "true" : "false"
  when Array
    value.to_json
  else
    text = value.to_s
    text.match?(/\A[A-Za-z0-9_.\/-]+\z/) ? text : text.to_json
  end
end

def first_positive_with_source(*pairs)
  pairs.each do |source, value|
    n = positive_int(value)
    return [n, source] if n
  end
  [nil, nil]
end

def source_conf(info, dimension)
  (info["x_#{dimension}_confidence"] || "local-config").to_s
end

def source_name(info, dimension)
  (info["x_#{dimension}_source"] || "-").to_s
end

def numeric_status(configured, provider, confidence)
  conf = confidence.to_s
  if provider
    return "drift" if positive_int(configured) != provider
    return "ok" if %w[provider observed].include?(conf)
    return "source-missing"
  end
  return "owned-policy" if conf == "owned-policy"
  return "observed" if conf == "observed"
  "provider-missing"
end

def bool_status(configured, provider, confidence)
  conf = confidence.to_s
  return "provider-missing" if provider.nil?
  return "drift" unless configured == provider
  return "ok" if %w[provider observed].include?(conf)
  "source-missing"
end

def array_status(configured, provider)
  return "drift" unless Array(configured).map(&:to_s) == Array(provider).map(&:to_s)
  "ok"
end

def update_anchor_field(lines, alias_name, field, value)
  start = lines.index { |line| line.match?(/^  #{Regexp.escape(alias_name)}:\s*&#{Regexp.escape(alias_name)}\s*$/) }
  raise "Cannot apply to missing or inline x-limits anchor: #{alias_name}" unless start
  finish = ((start + 1)...lines.length).find do |idx|
    lines[idx].match?(/^  [A-Za-z0-9_]+:\s*&[A-Za-z0-9_]+\s*$/) || lines[idx].match?(/^model_list:\s*$/)
  end || lines.length
  rendered = "    #{field}: #{yaml_scalar(value)}\n"
  current = ((start + 1)...finish).find { |idx| lines[idx].match?(/^    #{Regexp.escape(field)}:\s*/) }
  if current
    return false if lines[current] == rendered
    lines[current] = rendered
  else
    lines.insert(finish, rendered)
  end
  true
end

raw_config = File.read(config_path)
config = (YAML.load_file(config_path, aliases: true) rescue YAML.load_file(config_path))
provider_payload = JSON.parse(File.read(provider_path))
provider_index = Array(provider_payload["data"]).each_with_object({}) { |entry, acc| acc[entry["id"]] = entry if entry["id"] }

alias_routes = Hash.new { |h, k| h[k] = { "surfaces" => [], "routes" => [] } }
raw_config.split(/\n(?=  - model_name:\s*)/).each do |entry|
  next unless entry =~ /^\s+- model_name:\s*(.+?)\s*$/
  surface = Regexp.last_match(1).strip
  route = entry[/^\s+model:\s*(\S+)\s*$/, 1]
  anchor = entry[/^\s+model_info:\s*\*([A-Za-z0-9_]+)\s*$/, 1]
  next unless anchor && route
  alias_routes[anchor]["surfaces"] << surface
  alias_routes[anchor]["routes"] << route unless alias_routes[anchor]["routes"].include?(route)
end

capability_targets = []
(config["x-limits"] || {}).each do |alias_name, info|
  capability_targets << {
    "name" => alias_name,
    "scope" => "package-anchor",
    "info" => info || {},
    "route" => alias_routes.dig(alias_name, "routes", 0),
    "surfaces" => alias_routes.dig(alias_name, "surfaces") || []
  }
end
Array(config["model_list"]).each do |entry|
  info = entry["model_info"] || {}
  route = entry.dig("litellm_params", "model").to_s
  surface = entry["model_name"].to_s
  next unless info["x_registry_source"] == "user-overlay"
  next unless route.start_with?("openrouter/") && !surface.empty?
  capability_targets << {
    "name" => surface,
    "scope" => "user-overlay",
    "info" => info,
    "route" => route,
    "surfaces" => [surface]
  }
end

rows = []
capability_targets.each do |target|
  alias_name = target["name"]
  info = target["info"]
  route = target["route"]
  surfaces = target["surfaces"]
  openrouter = route.to_s.start_with?("openrouter/")
  provider_id = openrouter ? route.sub(/\Aopenrouter\//, "") : nil
  provider = provider_id && provider_index[provider_id]

  row = {
    "alias" => alias_name,
    "scope" => target["scope"],
    "provider_model" => route || "-",
    "surfaces" => surfaces,
    "openrouter" => openrouter,
    "provider_found" => !!provider
  }

  if provider
    provider_input, provider_input_source = first_positive_with_source(
      ["openrouter.top_provider.context_length", provider.dig("top_provider", "context_length")],
      ["openrouter.context_length", provider["context_length"]]
    )
    provider_output, provider_output_source = first_positive_with_source(
      ["openrouter.top_provider.max_completion_tokens", provider.dig("top_provider", "max_completion_tokens")],
      ["openrouter.max_completion_tokens", provider["max_completion_tokens"]]
    )
    params = Array(provider["supported_parameters"])
    provider_efforts = Array(provider.dig("reasoning", "supported_efforts")).map(&:to_s)
    # LiteLLM 1.92's Anthropic→OpenAI adapter normalizes xhigh/max before an
    # OpenRouter request is constructed. Preserve those raw provider claims in
    # the audit row, but compare/apply only the effective selectable contract.
    effective_provider_efforts = provider_efforts.reject { |effort| %w[xhigh max].include?(effort) }
    provider_reasoning = !provider_efforts.empty? || params.any? { |param| %w[reasoning reasoning_effort include_reasoning].include?(param.to_s) }

    input_conf = source_conf(info, "input")
    output_conf = source_conf(info, "output")
    reasoning_conf = source_conf(info, "reasoning")
    row["input"] = {
      "configured" => info["max_input_tokens"],
      "provider" => provider_input,
      "confidence" => input_conf,
      "source" => source_name(info, "input"),
      "provider_source" => provider_input_source,
      "status" => numeric_status(info["max_input_tokens"], provider_input, input_conf)
    }
    row["output"] = {
      "configured" => info["max_output_tokens"],
      "provider" => provider_output,
      "confidence" => output_conf,
      "source" => source_name(info, "output"),
      "provider_source" => provider_output_source,
      "status" => numeric_status(info["max_output_tokens"], provider_output, output_conf)
    }
    row["reasoning"] = {
      "configured" => info.key?("supports_reasoning") ? !!info["supports_reasoning"] : nil,
      "provider" => provider_reasoning,
      "confidence" => reasoning_conf,
      "source" => source_name(info, "reasoning"),
      "provider_source" => "openrouter.supported_parameters",
      "status" => bool_status(info.key?("supports_reasoning") ? !!info["supports_reasoning"] : nil, provider_reasoning, reasoning_conf)
    }
    configured_efforts = Array(info["x_reasoning_efforts"]).map(&:to_s)
    configured_provider_efforts = Array(info["x_provider_reasoning_efforts"]).map(&:to_s)
    effective_status = array_status(configured_efforts, effective_provider_efforts)
    provider_status = if info.key?("x_provider_reasoning_efforts")
      array_status(configured_provider_efforts, provider_efforts)
    elsif provider_efforts.empty?
      "ok"
    else
      "source-missing"
    end
    row["effort"] = {
      "configured" => configured_efforts,
      "configured_provider" => configured_provider_efforts,
      "provider" => provider_efforts,
      "effective_provider" => effective_provider_efforts,
      "provider_source" => "openrouter.reasoning.supported_efforts",
      "transport_ceiling" => "high",
      "transport_source" => "litellm-1.92-anthropic-adapter-normalizes-xhigh-max-to-high",
      "effective_status" => effective_status,
      "provider_status" => provider_status,
      "status" => effective_status == "ok" ? provider_status : effective_status
    }
    route_entries = Array(config["model_list"]).select do |candidate|
      candidate.dig("litellm_params", "model").to_s == route.to_s
    end
    passthrough = route_entries.any? do |candidate|
      Array(candidate.dig("litellm_params", "allowed_openai_params")).map(&:to_s).include?("reasoning_effort")
    end
    row["effort_wire"] = {
      "required" => !effective_provider_efforts.empty?,
      "configured" => passthrough,
      "status" => effective_provider_efforts.empty? || passthrough ? "ok" : "missing-passthrough"
    }
  else
    row["input"] = {
      "configured" => info["max_input_tokens"],
      "provider" => nil,
      "confidence" => source_conf(info, "input"),
      "source" => source_name(info, "input"),
      "provider_source" => nil,
      "status" => openrouter ? "no-provider-model" : source_conf(info, "input")
    }
    row["output"] = {
      "configured" => info["max_output_tokens"],
      "provider" => nil,
      "confidence" => source_conf(info, "output"),
      "source" => source_name(info, "output"),
      "provider_source" => nil,
      "status" => openrouter ? "no-provider-model" : source_conf(info, "output")
    }
    row["reasoning"] = {
      "configured" => info.key?("supports_reasoning") ? !!info["supports_reasoning"] : nil,
      "provider" => nil,
      "confidence" => source_conf(info, "reasoning"),
      "source" => source_name(info, "reasoning"),
      "provider_source" => nil,
      "status" => openrouter ? "no-provider-model" : source_conf(info, "reasoning")
    }
    row["effort"] = {
      "configured" => Array(info["x_reasoning_efforts"]).map(&:to_s),
      "configured_provider" => Array(info["x_provider_reasoning_efforts"]).map(&:to_s),
      "provider" => nil,
      "effective_provider" => nil,
      "provider_source" => nil,
      "status" => openrouter ? "no-provider-model" : "local-config"
    }
    row["effort_wire"] = {
      "required" => false,
      "configured" => false,
      "status" => openrouter ? "no-provider-model" : "local-config"
    }
  end
  rows << row
end

changes = []
if apply_changes
  lines = raw_config.lines
  rows.each do |row|
    next unless row["scope"] == "package-anchor" && row["openrouter"] && row["provider_found"]
    alias_name = row["alias"]
    input = row["input"] || {}
    output = row["output"] || {}
    reasoning = row["reasoning"] || {}
    effort = row["effort"] || {}

    if input["provider"] && input["status"] != "ok"
      changes << "#{alias_name}.max_input_tokens=#{input["provider"]}" if update_anchor_field(lines, alias_name, "max_input_tokens", input["provider"])
      changes << "#{alias_name}.x_input_confidence=provider" if update_anchor_field(lines, alias_name, "x_input_confidence", "provider")
      changes << "#{alias_name}.x_input_source=#{input["provider_source"]}" if update_anchor_field(lines, alias_name, "x_input_source", input["provider_source"])
    end
    if output["provider"] && output["status"] != "ok"
      changes << "#{alias_name}.max_output_tokens=#{output["provider"]}" if update_anchor_field(lines, alias_name, "max_output_tokens", output["provider"])
      changes << "#{alias_name}.x_output_confidence=provider" if update_anchor_field(lines, alias_name, "x_output_confidence", "provider")
      changes << "#{alias_name}.x_output_source=#{output["provider_source"]}" if update_anchor_field(lines, alias_name, "x_output_source", output["provider_source"])
    end
    if !reasoning["provider"].nil? && reasoning["status"] != "ok"
      changes << "#{alias_name}.supports_reasoning=#{reasoning["provider"]}" if update_anchor_field(lines, alias_name, "supports_reasoning", reasoning["provider"])
      changes << "#{alias_name}.x_reasoning_confidence=provider" if update_anchor_field(lines, alias_name, "x_reasoning_confidence", "provider")
      changes << "#{alias_name}.x_reasoning_source=#{reasoning["provider_source"]}" if update_anchor_field(lines, alias_name, "x_reasoning_source", reasoning["provider_source"])
    end
    effective_efforts = effort["effective_provider"]
    if effective_efforts.is_a?(Array) && effort["effective_status"] != "ok"
      if update_anchor_field(lines, alias_name, "x_reasoning_efforts", effective_efforts)
        changes << "#{alias_name}.x_reasoning_efforts=#{effective_efforts.join(",")}"
      end
    end
    provider_efforts = effort["provider"]
    if provider_efforts.is_a?(Array) && effort["provider_status"] != "ok"
      if update_anchor_field(lines, alias_name, "x_provider_reasoning_efforts", provider_efforts)
        changes << "#{alias_name}.x_provider_reasoning_efforts=#{provider_efforts.join(",")}"
      end
    end
    if provider_efforts.is_a?(Array) && !provider_efforts.empty?
      if update_anchor_field(lines, alias_name, "x_reasoning_effort_ceiling", "high")
        changes << "#{alias_name}.x_reasoning_effort_ceiling=high"
      end
      transport_source = "litellm-1.92-anthropic-adapter-normalizes-xhigh-max-to-high"
      if update_anchor_field(lines, alias_name, "x_reasoning_transport_source", transport_source)
        changes << "#{alias_name}.x_reasoning_transport_source=#{transport_source}"
      end
    end
  end

  if changes.any?
    tmp = "#{config_path}.tmp.#{$$}"
    File.write(tmp, lines.join)
    File.chmod(File.stat(config_path).mode & 0o777, tmp)
    File.rename(tmp, config_path)
  end
end

issue_statuses = %w[drift source-missing provider-missing no-provider-model missing-passthrough]
issues = rows.flat_map do |row|
  %w[input output reasoning effort effort_wire].map do |dim|
    status = row.dig(dim, "status").to_s
    issue_statuses.include?(status) ? {"alias" => row["alias"], "dimension" => dim, "status" => status} : nil
  end.compact
end

if as_json
  puts JSON.pretty_generate({
    "provider" => "openrouter",
    "applied" => apply_changes,
    "changes" => changes,
    "rows" => rows,
    "issues" => issues
  })
else
  printf("%-18s %-42s %-25s %-25s %-18s %-18s %-18s %-18s\n",
    "alias", "provider_model", "input(config/provider)", "output(config/provider)",
    "input_status", "output_status", "reasoning_status", "effort_status")
  rows.each do |row|
    input = row["input"] || {}
    output = row["output"] || {}
    reasoning = row["reasoning"] || {}
    effort = row["effort"] || {}
    printf("%-18s %-42s %-25s %-25s %-18s %-18s %-18s %-18s\n",
      row["alias"],
      row["provider_model"],
      "#{input["configured"] || "-"}/#{input["provider"] || "-"}",
      "#{output["configured"] || "-"}/#{output["provider"] || "-"}",
      input["status"] || "-",
      output["status"] || "-",
      reasoning["status"] || "-",
      effort["status"] || "-")
  end
  if apply_changes
    puts changes.empty? ? "No provider-published changes to apply." : "Applied #{changes.length} field update(s)."
  elsif issues.any?
    puts "Provider drift/source issues remain. Re-run with --apply for provider-published fields; owned-policy rows require an explicit local decision."
  end
end

exit(issues.any? && check ? 1 : 0)
RUBY
  local rc=$?
  (( cleanup )) && rm -f "$payload_file"
  return $rc
}

# Fetch OpenRouter /models capabilities for a single provider-id and write a
# new x-limits anchor + model_list route (input is always provider-confidence;
# output is provider-confidence when OpenRouter publishes a completion cap,
# else a conservative owned-policy fallback). Optionally wires a Claude tier
# alias (--claude-tier), then syncs.
# Fixture injection mirrors ai_litellm_model_refresh_capabilities:
# AI_LITELLM_OPENROUTER_MODELS_JSON substitutes for the live OpenRouter fetch.
# --dry-run prints the full plan without writing anything or syncing.
# AI_LITELLM_SKIP_SYNC=1 performs all writes but skips the closing sync (for
# offline registry-only tests).
ai_litellm_model_add_legacy() {
  echo "Internal legacy mutator retired: package-generated configuration is immutable." >&2
  return 1
  local provider_id="" custom_name="" claude_tier="" dry_run=0

  while (( $# > 0 )); do
    case "$1" in
      --name)
        shift
        if [[ $# -eq 0 ]]; then
          echo "Missing value after --name" >&2
          return 1
        fi
        custom_name="$1"
        ;;
      --claude-tier)
        shift
        if [[ $# -eq 0 ]]; then
          echo "Missing value after --claude-tier" >&2
          return 1
        fi
        claude_tier="$1"
        ;;
      --dry-run)
        dry_run=1
        ;;
      -h|--help)
        cat <<'EOF'
Usage: claude-litellm model add <provider-id> [--name <surface>] [--claude-tier <tier>] [--dry-run]

Fetch OpenRouter capabilities for <provider-id> (an OpenRouter catalog id,
e.g. z-ai/glm-5.2) and write a new x-limits anchor plus model_list route.
  --name <surface>       Explicit LiteLLM model_name. Default: derived from
                         the provider-id (e.g. deepseek/deepseek-v4-pro ->
                         Deepseek-V4-Pro-openrouter).
  --claude-tier <tier>   Also point a Claude Code tier at the new surface.
                         One of: fable opus sonnet haiku.
  --dry-run              Print the plan without writing anything or syncing.

Set AI_LITELLM_OPENROUTER_MODELS_JSON to a local fixture path to test offline.
Set AI_LITELLM_SKIP_SYNC=1 to write everything but skip the closing sync.
EOF
        return 0
        ;;
      -*)
        echo "Unknown option: $1" >&2
        return 1
        ;;
      *)
        if [[ -n "$provider_id" ]]; then
          echo "Usage: claude-litellm model add <provider-id> [--name <surface>] [--claude-tier <tier>] [--dry-run]" >&2
          return 1
        fi
        provider_id="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$provider_id" ]]; then
    echo "Usage: claude-litellm model add <provider-id> [--name <surface>] [--claude-tier <tier>] [--dry-run]" >&2
    return 1
  fi

  if [[ -n "$claude_tier" ]]; then
    case "$claude_tier" in
      fable|opus|sonnet|haiku) ;;
      *)
        echo "claude-litellm model add: invalid --claude-tier '$claude_tier' (expected one of: fable opus sonnet haiku)" >&2
        return 1
        ;;
    esac
  fi

  # Fixture injection mirrors ai_litellm_model_refresh_capabilities: point
  # AI_LITELLM_OPENROUTER_MODELS_JSON at a local payload for offline tests,
  # else fetch the live catalog.
  local payload_file cleanup=0
  if [[ -n "${AI_LITELLM_OPENROUTER_MODELS_JSON:-}" ]]; then
    payload_file="$AI_LITELLM_OPENROUTER_MODELS_JSON"
    [[ -f "$payload_file" ]] || { echo "Missing AI_LITELLM_OPENROUTER_MODELS_JSON file: $payload_file" >&2; return 1; }
  else
    payload_file="$(mktemp "${TMPDIR:-/tmp}/openrouter-models.json.XXXXXX")" || return 1
    cleanup=1
    curl --connect-timeout 10 --max-time 60 -fsSL https://openrouter.ai/api/v1/models > "$payload_file" || {
      (( cleanup )) && rm -f "$payload_file"
      return 1
    }
  fi

  local out
  out="$(ai_litellm_ruby -rjson -ryaml - "$AI_LITELLM_CONFIG" "$payload_file" "$provider_id" "$custom_name" "$dry_run" <<'RUBY'
config_path, payload_path, provider_id, custom_name, dry_run_raw = ARGV
dry_run = dry_run_raw == "1"

def positive_int(value)
  n = Integer(value)
  n.positive? ? n : nil
rescue
  nil
end

# Mirrors the yaml_scalar helper in ai_litellm_model_refresh_capabilities:
# bare for numbers/booleans/plain-safe strings, JSON-quoted otherwise so a
# decorated source note stays valid YAML.
def yaml_scalar(value)
  case value
  when Integer
    value.to_s
  when TrueClass, FalseClass
    value ? "true" : "false"
  else
    text = value.to_s
    text.match?(/\A[A-Za-z0-9_.\/-]+\z/) ? text : text.to_json
  end
end

payload = JSON.parse(File.read(payload_path))
entry = Array(payload["data"]).find { |e| e["id"] == provider_id }
abort("model not found in OpenRouter catalog: #{provider_id}") unless entry

top = entry["top_provider"] || {}
max_input, input_source =
  if (n = positive_int(top["context_length"]))
    [n, "openrouter.top_provider.context_length"]
  elsif (n = positive_int(entry["context_length"]))
    [n, "openrouter.context_length"]
  else
    [nil, nil]
  end
abort("could not determine max_input_tokens for #{provider_id} from the OpenRouter payload") unless max_input

max_out_pub = positive_int(top["max_completion_tokens"])
output_fallback = max_out_pub.nil?
if output_fallback
  max_output = [max_input, 32768].min
  output_confidence = "owned-policy"
  output_source = "openrouter-unpublished; conservative default, review recommended"
else
  max_output = max_out_pub
  output_confidence = "provider"
  output_source = "openrouter.top_provider.max_completion_tokens"
end

params = Array(entry["supported_parameters"]).map(&:to_s)
reasoning = params.include?("reasoning") || params.include?("reasoning_effort")
reasoning_efforts = Array(entry.dig("reasoning", "supported_efforts")).map(&:to_s)
reasoning_efforts &= %w[none minimal low medium high xhigh max]

raw = File.read(config_path)
config = (YAML.load_file(config_path, aliases: true) rescue YAML.load_file(config_path))
existing_names = Array(config["model_list"]).map { |e| e["model_name"] }.compact
existing_anchors = (config["x-limits"] || {}).keys.map(&:to_s)

if custom_name.to_s.empty?
  last_segment = provider_id.to_s.split("/").last.to_s
  surface = last_segment.split("-").map(&:capitalize).join("-") + "-openrouter"
else
  surface = custom_name
end
abort("model_name already exists in the registry: #{surface}") if existing_names.include?(surface)

anchor_base = provider_id.to_s.split("/").last.to_s.downcase.gsub(/[^a-z0-9]+/, "_")
anchor = anchor_base
suffix = 2
while existing_anchors.include?(anchor)
  anchor = "#{anchor_base}_#{suffix}"
  suffix += 1
end

anchor_lines = [
  "  #{anchor}: &#{anchor}\n",
  "    max_input_tokens: #{yaml_scalar(max_input)}\n",
  "    max_output_tokens: #{yaml_scalar(max_output)}\n",
  "    supports_reasoning: #{yaml_scalar(reasoning)}\n",
  "    x_reasoning_efforts: #{reasoning_efforts.to_json}\n",
  "    x_input_confidence: provider\n",
  "    x_input_source: #{yaml_scalar(input_source)}\n",
  "    x_output_confidence: #{yaml_scalar(output_confidence)}\n",
  "    x_output_source: #{yaml_scalar(output_source)}\n",
  "    x_reasoning_confidence: provider\n",
  "    x_reasoning_source: openrouter.supported_parameters\n",
  "\n",
]

backend_model = "openrouter/#{provider_id}"
route_lines = [
  "  - model_name: #{yaml_scalar(surface)}\n",
  "    litellm_params:\n",
  "      model: #{yaml_scalar(backend_model)}\n",
  "      api_key: os.environ/OPENROUTER_API_KEY\n",
  *(reasoning_efforts.empty? ? [] : ["      allowed_openai_params: [reasoning_effort]\n"]),
  "    model_info: *#{anchor}\n",
  "\n",
]

puts "claude-litellm model add #{provider_id}#{dry_run ? " (dry-run)" : ""}"
puts "- surface: #{surface}"
puts "- anchor: #{anchor}"
puts "- x-limits anchor to add:"
anchor_lines.each { |line| print line }
puts "- model_list route to add:"
route_lines.each { |line| print line }

if dry_run
  puts "- dry-run: no files changed"
else
  lines = raw.lines
  idx_model_list = lines.index { |line| line.match?(/^model_list:\s*$/) }
  abort("cannot locate model_list: in #{config_path}") unless idx_model_list
  lines.insert(idx_model_list, *anchor_lines)

  idx_discovered = lines.index { |line| line.match?(/^# BEGIN claude-litellm discovered local routes/) }
  idx_general = lines.index { |line| line.match?(/^general_settings:\s*$/) }
  insert_at = idx_discovered || idx_general || lines.length
  lines.insert(insert_at, *route_lines)

  tmp = "#{config_path}.tmp.#{$$}"
  File.write(tmp, lines.join)
  File.chmod(File.stat(config_path).mode & 0o777, tmp)
  File.rename(tmp, config_path)
  puts "- wrote #{config_path}"
end

puts "Surface: #{surface}"
puts "Anchor: #{anchor}"
puts "OutputCapFallback: #{output_fallback ? "yes" : "no"}"
puts "OutputCap: #{max_output}"
RUBY
)"
  local rc=$?
  (( cleanup )) && rm -f "$payload_file"

  # Split the captured report into display lines vs. machine-readable marker
  # lines (Surface/Anchor/OutputCapFallback/OutputCap), so the human-facing
  # preview stays clean while this function still learns the resolved surface
  # name (custom or derived) for the --claude-tier step below.
  local -a display_lines
  local surface="" anchor="" output_fallback="" output_cap="" line
  for line in "${(@f)out}"; do
    case "$line" in
      "Surface: "*) surface="${line#Surface: }" ;;
      "Anchor: "*) anchor="${line#Anchor: }" ;;
      "OutputCapFallback: "*) output_fallback="${line#OutputCapFallback: }" ;;
      "OutputCap: "*) output_cap="${line#OutputCap: }" ;;
      *) display_lines+=("$line") ;;
    esac
  done
  (( ${#display_lines[@]} > 0 )) && print -r -- "${(F)display_lines}"

  if (( rc != 0 )); then
    return $rc
  fi

  if [[ -z "$custom_name" ]]; then
    echo "claude-litellm model add: derived name '$surface'; use --name for exact casing (e.g. DeepSeek-V4-Pro-openrouter)" >&2
  fi
  if [[ "$output_fallback" == "yes" ]]; then
    echo "claude-litellm model add: output cap not published by OpenRouter — set a conservative $output_cap; review with 'claude-litellm model limits $surface'" >&2
  fi

  if (( dry_run )); then
    if [[ -n "$claude_tier" ]]; then
      echo "- would set claude tier: $claude_tier -> $surface (aliases/displayNames)"
    fi
    echo "- dry-run: sync not run"
    return 0
  fi

  if [[ -n "$claude_tier" ]]; then
    ai_litellm_harness_alias_set claude "$claude_tier" "$surface" || return $?
  fi

  if [[ -n "${AI_LITELLM_SKIP_SYNC:-}" ]]; then
    echo "claude-litellm model add: AI_LITELLM_SKIP_SYNC set; skipping sync (run claude-litellm sync to apply)"
    return 0
  fi

  ai_litellm_sync
}

# Reverse of ai_litellm_model_add: locate a model_list route by its LiteLLM
# model_name (surface) and remove it, plus its x-limits anchor if no other
# route still references that anchor. Refuses to remove:
#   - a discovered route (managed by claude-litellm sync, inside the BEGIN/END
#     block)
#   - a local runtime route (api_key: none; remove via runtime discovery
#     instead)
#   - a surface still referenced by a Claude tier alias -- reassign first
# --dry-run prints the plan without writing anything or syncing.
# AI_LITELLM_SKIP_SYNC=1 performs the write but skips the closing sync (for
# offline registry-only tests), mirroring ai_litellm_model_add.
ai_litellm_model_remove_legacy() {
  echo "Internal legacy mutator retired: package-generated configuration is immutable." >&2
  return 1
  local surface="" dry_run=0

  while (( $# > 0 )); do
    case "$1" in
      --dry-run)
        dry_run=1
        ;;
      -h|--help)
        cat <<'EOF'
Usage: claude-litellm model remove <surface> [--dry-run]

Remove a model_list route by its LiteLLM model_name, plus its x-limits
anchor if no other route still references it. Refuses to remove:
  - a discovered route (managed by claude-litellm sync)
  - a local route (api_key: none; remove via runtime discovery instead)
  - a surface still referenced by a Claude tier alias
  --dry-run              Print the plan without writing anything or syncing.

Set AI_LITELLM_SKIP_SYNC=1 to write everything but skip the closing sync.
EOF
        return 0
        ;;
      -*)
        echo "Unknown option: $1" >&2
        return 1
        ;;
      *)
        if [[ -n "$surface" ]]; then
          echo "Usage: claude-litellm model remove <surface> [--dry-run]" >&2
          return 1
        fi
        surface="$1"
        ;;
    esac
    shift
  done

  if [[ -z "$surface" ]]; then
    echo "Usage: claude-litellm model remove <surface> [--dry-run]" >&2
    return 1
  fi

  # Reference checks reuse the existing harness helpers rather than re-deriving
  # settings-file lookup here.
  local claude_alias_json
  claude_alias_json="$(ai_litellm_harness_alias_json claude 2>/dev/null)"
  [[ -n "$claude_alias_json" ]] || claude_alias_json="[]"

  ai_litellm_ruby -rjson -ryaml - "$AI_LITELLM_CONFIG" "$surface" "$dry_run" "$claude_alias_json" <<'RUBY'
config_path, surface, dry_run_raw, claude_alias_raw = ARGV
dry_run = dry_run_raw == "1"

# Mirrors the yaml_scalar helper in ai_litellm_model_add: bare for
# numbers/booleans/plain-safe strings, JSON-quoted otherwise -- used here to
# rebuild the exact raw model_name token so the surface can be located by
# regex in the raw text (not just the parsed YAML).
def yaml_scalar(value)
  case value
  when Integer
    value.to_s
  when TrueClass, FalseClass
    value ? "true" : "false"
  else
    text = value.to_s
    text.match?(/\A[A-Za-z0-9_.\/-]+\z/) ? text : text.to_json
  end
end

# A route entry (and an x-limits anchor stanza) ends at the last line
# indented as one of its own fields -- the first line that is blank, a
# comment, the next `- model_name:`, the discovered BEGIN marker, or a
# top-level key all have fewer than 4 leading spaces, so a single
# indentation test finds the boundary in every case. ai_litellm_model_add
# always appends its new stanza with a trailing blank separator line
# (mirroring the file convention that every route, and the last x-limits
# anchor before model_list, is followed by exactly one blank line); that
# insertion leaves the pre-existing separator blank immediately before the
# stanza and the new trailing blank immediately after it. Deleting only the
# stanza content would therefore leave those two blank lines adjacent (one
# too many); when that exact pattern is present, extend the deletion by one
# line to collapse back to a single blank, restoring byte-identical output
# on an add-then-remove round trip.
def block_finish(lines, start)
  finish = ((start + 1)...lines.length).find { |idx| !lines[idx].match?(/^\s{4,}\S/) } || lines.length
  before_blank = start > 0 && lines[start - 1].match?(/\A\s*\z/)
  after_blank = finish < lines.length && lines[finish].match?(/\A\s*\z/)
  finish += 1 if before_blank && after_blank
  finish
end

claude_aliases = (JSON.parse(claude_alias_raw) rescue [])
claude_aliases = [] unless claude_aliases.is_a?(Array)

raw = File.read(config_path)
config = (YAML.load_file(config_path, aliases: true) rescue YAML.load_file(config_path))

# Step 1: find the route.
entries = Array(config["model_list"])
target = entries.find { |e| e["model_name"].to_s == surface }
abort("model not found in registry: #{surface}") unless target

lines = raw.lines
name_pattern = /^  - model_name:\s*#{Regexp.escape(yaml_scalar(surface))}\s*$/
start = lines.index { |l| l.match?(name_pattern) }
abort("cannot locate model_list route for #{surface} in #{config_path}") unless start

# Step 2: guards (discovered block, functional slug, local runtime route).
idx_begin = lines.index { |l| l.match?(/^# BEGIN claude-litellm discovered local routes/) }
idx_end   = lines.index { |l| l.match?(/^# END claude-litellm discovered local routes/) }
if idx_begin && idx_end && start > idx_begin && start < idx_end
  abort("#{surface}: discovered route -- managed by runtime discovery")
end

api_key = target.dig("litellm_params", "api_key").to_s
abort("#{surface}: local route -- remove via runtime") if api_key == "none"

# Step 3: Claude tier reference checks.
backend = target.dig("litellm_params", "model").to_s
provider_id = backend.sub(%r{\Aopenrouter/}, "")

ref_tiers = claude_aliases.select do |row|
  row["model"].to_s == surface || (!provider_id.empty? && row["direct"].to_s == provider_id)
end.map { |row| row["tier"].to_s }
abort("#{surface}: referenced by tier #{ref_tiers.join(", ")}; reassign the tier first") unless ref_tiers.empty?

# Step 4: anchor determination.
finish = block_finish(lines, start)
route_text = lines[start...finish].join
anchor_name = route_text[/^\s+model_info:\s*\*([A-Za-z0-9_]+)\s*$/, 1]

anchor_counts = Hash.new(0)
raw.split(/\n(?=  - model_name:\s*)/).each do |chunk|
  chunk_anchor = chunk[/^\s+model_info:\s*\*([A-Za-z0-9_]+)\s*$/, 1]
  anchor_counts[chunk_anchor] += 1 if chunk_anchor
end
orphaned = anchor_name && anchor_counts[anchor_name] <= 1

a_start = a_finish = anchor_text = nil
if orphaned
  a_start = lines.index { |l| l.match?(/^  #{Regexp.escape(anchor_name)}:\s*&#{Regexp.escape(anchor_name)}\s*$/) }
  if a_start
    a_finish = block_finish(lines, a_start)
    anchor_text = lines[a_start...a_finish].join
  end
end

puts "claude-litellm model remove #{surface}#{dry_run ? " (dry-run)" : ""}"
puts "- backend: #{backend}"
if anchor_name
  if orphaned
    puts "- anchor: #{anchor_name} (orphaned, will be removed)"
  else
    puts "- anchor: #{anchor_name} (still referenced by #{anchor_counts[anchor_name] - 1} other route(s), kept)"
  end
else
  puts "- anchor: none"
end
puts "- model_list route to remove:"
route_text.each_line { |l| print l }
if orphaned && a_start
  puts "- x-limits anchor to remove:"
  anchor_text.each_line { |l| print l }
end

# Step 5/6: delete (route, then the now-orphaned anchor if any) + atomic
# write, unless --dry-run. The route is always deleted before the anchor so
# the anchor indices (computed above, earlier in the file) stay valid.
if dry_run
  puts "- dry-run: no files changed"
else
  lines.slice!(start...finish)
  lines.slice!(a_start...a_finish) if orphaned && a_start
  tmp = "#{config_path}.tmp.#{$$}"
  File.write(tmp, lines.join)
  File.chmod(File.stat(config_path).mode & 0o777, tmp)
  File.rename(tmp, config_path)
  puts "- wrote #{config_path}"
end
RUBY
  local rc=$?
  (( rc != 0 )) && return $rc

  (( dry_run )) && return 0

  if [[ -n "${AI_LITELLM_SKIP_SYNC:-}" ]]; then
    echo "claude-litellm model remove: AI_LITELLM_SKIP_SYNC set; skipping sync (run claude-litellm sync to apply)"
    return 0
  fi

  ai_litellm_sync
}

# Durable registry mutations live outside the package prefix. The tiny mkdir
# lock serializes model+alias/sync/qualification transactions. A dead or stale
# owner is reclaimed; a just-created directory without its PID gets a short
# publication grace period instead of being removed by a racing process.
ai_litellm_user_mutation_lock_acquire() {
  ai_litellm_user_config_paths_prepare || return 1
  typeset -g AI_LITELLM_USER_MUTATION_LOCK="$AI_LITELLM_USER_CONFIG_HOME/.mutation.lock"
  typeset -g AI_LITELLM_USER_MUTATION_FD="${AI_LITELLM_USER_MUTATION_FD:-}"
  if [[ "$AI_LITELLM_USER_MUTATION_FD" == <-> ]]; then
    return 0
  fi
  zmodload zsh/system || return 1
  local fd owner
  ai_litellm_lock_file_prepare "${AI_LITELLM_USER_MUTATION_LOCK}.flock" || return 1
  if ! zsystem flock -t 0 -f fd "${AI_LITELLM_USER_MUTATION_LOCK}.flock"; then
    echo "Another configuration mutation is in progress." >&2
    return 1
  fi
  chmod 600 "${AI_LITELLM_USER_MUTATION_LOCK}.flock" 2>/dev/null || true
  if [[ -d "$AI_LITELLM_USER_MUTATION_LOCK" ]]; then
    owner="$(<"$AI_LITELLM_USER_MUTATION_LOCK/pid" 2>/dev/null || printf '?')"
    if [[ "$owner" != '?' && "$owner" != "$$" ]] && kill -0 "$owner" 2>/dev/null; then
      zsystem flock -u "$fd" 2>/dev/null || true
      echo "Another legacy configuration mutation is in progress (pid $owner)." >&2
      return 1
    fi
    rm -rf "$AI_LITELLM_USER_MUTATION_LOCK"
  elif [[ -e "$AI_LITELLM_USER_MUTATION_LOCK" || -L "$AI_LITELLM_USER_MUTATION_LOCK" ]]; then
    zsystem flock -u "$fd" 2>/dev/null || true
    echo "Unsafe configuration mutation lock path: $AI_LITELLM_USER_MUTATION_LOCK" >&2
    return 1
  fi
  mkdir "$AI_LITELLM_USER_MUTATION_LOCK" || { zsystem flock -u "$fd" 2>/dev/null || true; return 1; }
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$AI_LITELLM_USER_MUTATION_LOCK/started_at"
  printf '%s\n' "$$" > "$AI_LITELLM_USER_MUTATION_LOCK/pid"
  AI_LITELLM_USER_MUTATION_FD="$fd"
}

ai_litellm_user_mutation_lock_release() {
  local lock="${AI_LITELLM_USER_MUTATION_LOCK:-}"
  if [[ -n "$lock" && -d "$lock" && "$(<"$lock/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "$lock"
  fi
  if [[ "${AI_LITELLM_USER_MUTATION_FD:-}" == <-> ]]; then
    zsystem flock -u "$AI_LITELLM_USER_MUTATION_FD" 2>/dev/null || true
  fi
  typeset -g AI_LITELLM_USER_MUTATION_FD=""
}

# Add an OpenRouter catalog model to the user registry. Package defaults remain
# immutable, so upgrades can replace them while this overlay is preserved.
ai_litellm_model_add() {
  local provider_id="" custom_name="" claude_tier="" dry_run=0
  while (( $# > 0 )); do
    case "$1" in
      --name) shift; [[ $# -gt 0 && "$1" != -* ]] || { echo "Missing value after --name" >&2; return 1; }; custom_name="$1" ;;
      --claude-tier) shift; [[ $# -gt 0 && "$1" != -* ]] || { echo "Missing value after --claude-tier" >&2; return 1; }; claude_tier="$1" ;;
      --dry-run) dry_run=1 ;;
      -h|--help)
        cat <<'EOF'
Usage: claude-litellm model add <openrouter-provider-id> [--name <surface>] [--claude-tier <tier>] [--dry-run]

Fetch OpenRouter capabilities and add a durable user model overlay. Package
defaults are never edited. Use `model qualify` before assigning important work.
EOF
        return 0 ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) [[ -z "$provider_id" ]] || { echo "Only one OpenRouter provider id may be added." >&2; return 1; }; provider_id="$1" ;;
    esac
    shift
  done
  [[ -n "$provider_id" ]] || { echo "Usage: claude-litellm model add <openrouter-provider-id> [options]" >&2; return 1; }
  if [[ -n "$claude_tier" ]]; then
    case "$claude_tier" in fable|opus|sonnet|haiku) ;; *) echo "Invalid Claude tier: $claude_tier" >&2; return 1 ;; esac
  fi

  local payload_file cleanup=0
  if [[ -n "${AI_LITELLM_OPENROUTER_MODELS_JSON:-}" ]]; then
    payload_file="$AI_LITELLM_OPENROUTER_MODELS_JSON"
    [[ -f "$payload_file" ]] || { echo "Missing OpenRouter fixture: $payload_file" >&2; return 1; }
  else
    payload_file="$(mktemp "${TMPDIR:-/tmp}/openrouter-models.json.XXXXXX")" || return 1
    cleanup=1
    curl --connect-timeout 10 --max-time 60 -fsSL https://openrouter.ai/api/v1/models > "$payload_file" || { rm -f "$payload_file"; return 1; }
  fi

  local python
  python="$(ai_litellm_litellm_python)" || { (( cleanup )) && rm -f "$payload_file"; return 1; }
  local backup_dir="" models_existed=0 settings_existed=0
  if (( ! dry_run )); then
    ai_litellm_user_mutation_lock_acquire || { (( cleanup )) && rm -f "$payload_file"; return 1; }
    backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/claude-litellm-user-model.XXXXXX")" || {
      ai_litellm_user_mutation_lock_release; (( cleanup )) && rm -f "$payload_file"; return 1
    }
    if [[ -f "$AI_LITELLM_USER_MODELS" ]]; then cp -p "$AI_LITELLM_USER_MODELS" "$backup_dir/models.json"; models_existed=1; fi
    if [[ -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" ]]; then cp -p "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$backup_dir/settings.json"; settings_existed=1; fi
  fi

  local out rc surface="" output_fallback="" output_cap=""
  out="$(ai_litellm_python_isolated "$python" - "$AI_LITELLM_CONFIG" "$AI_LITELLM_USER_MODELS" "$payload_file" "$provider_id" "$custom_name" "$dry_run" <<'PY'
import json, os, re, stat, sys, tempfile
from pathlib import Path
import yaml

config_path, user_path_raw, catalog_path, provider_id, custom_name, dry_raw = sys.argv[1:]
dry = dry_raw == "1"
catalog = json.load(open(catalog_path, encoding="utf-8"))
found = next((e for e in catalog.get("data", []) if e.get("id") == provider_id), None)
if not found:
    raise SystemExit(f"model not found in OpenRouter catalog: {provider_id}")
top = found.get("top_provider") or {}
context = top.get("context_length") or found.get("context_length")
if not isinstance(context, int) or context <= 0:
    raise SystemExit(f"OpenRouter did not publish a usable context limit for {provider_id}")
published_output = top.get("max_completion_tokens")
fallback = not isinstance(published_output, int) or published_output <= 0
output = min(context, 32768) if fallback else published_output
parameters = {str(v) for v in found.get("supported_parameters") or []}
valid_efforts = {"none", "minimal", "low", "medium", "high", "xhigh", "max"}
provider_efforts = []
for value in (found.get("reasoning") or {}).get("supported_efforts") or []:
    if value in valid_efforts and value not in provider_efforts:
        provider_efforts.append(value)
# LiteLLM 1.92 normalizes xhigh/max to high when the Anthropic adapter cannot
# find matching model-registry capability flags. Preserve the OpenRouter claim,
# but never advertise the normalized aliases as distinct selectable levels.
efforts = [value for value in provider_efforts if value not in {"xhigh", "max"}]
supports_reasoning = bool({"reasoning", "reasoning_effort", "include_reasoning"} & parameters) or bool(provider_efforts)
surface = custom_name or "-".join(part.capitalize() for part in provider_id.rsplit("/", 1)[-1].split("-")) + "-openrouter"
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:+-]{0,127}", surface):
    raise SystemExit("surface contains unsafe characters")
reserved_surfaces = {
    "auth", "context", "doctor", "fable", "haiku", "harness", "key",
    "model", "opus", "permissions", "proxy", "reasoning", "runtime",
    "sonnet", "status", "sync", "uninstall", "use",
}
if surface in reserved_surfaces:
    raise SystemExit(f"surface is reserved by the claude-litellm CLI: {surface}")
config = yaml.safe_load(open(config_path, encoding="utf-8")) or {}
existing = {e.get("model_name") for e in config.get("model_list", []) if isinstance(e, dict)}
if surface in existing:
    raise SystemExit(f"model_name already exists: {surface}")
path = Path(user_path_raw)
if path.exists() or path.is_symlink():
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode) or mode & 0o077:
        raise SystemExit(f"unsafe user model registry path or permissions: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
else:
    payload = {"schemaVersion": 1, "models": []}
if payload.get("schemaVersion", 1) != 1 or not isinstance(payload.get("models", []), list):
    raise SystemExit("unsupported or malformed user model registry")
models = payload.setdefault("models", [])
if any(isinstance(candidate, dict) and candidate.get("model_name") == surface for candidate in models):
    raise SystemExit(f"model_name already exists in user registry: {surface}")
entry = {
    "model_name": surface,
    "litellm_params": {
        "model": f"openrouter/{provider_id}",
        "api_key": "os.environ/OPENROUTER_API_KEY",
    },
    "model_info": {
        "max_input_tokens": context,
        "max_output_tokens": output,
        "supports_reasoning": supports_reasoning,
        "x_reasoning_efforts": efforts,
        "x_input_confidence": "provider",
        "x_input_source": "openrouter.top_provider.context_length" if top.get("context_length") else "openrouter.context_length",
        "x_output_confidence": "owned-policy" if fallback else "provider",
        "x_output_source": "openrouter-unpublished; conservative default" if fallback else "openrouter.top_provider.max_completion_tokens",
        "x_reasoning_confidence": "provider",
        "x_reasoning_source": "openrouter.supported_parameters",
    },
}
if provider_efforts:
    entry["model_info"].update({
        "x_provider_reasoning_efforts": provider_efforts,
        "x_reasoning_effort_ceiling": "high",
        "x_reasoning_transport_source": "litellm-1.92-anthropic-adapter-normalizes-xhigh-max-to-high",
    })
if efforts:
    entry["litellm_params"]["allowed_openai_params"] = ["reasoning_effort"]
print(f"claude-litellm model add {provider_id}{' (dry-run)' if dry else ''}")
print(f"- surface: {surface}")
print("- destination: durable user overlay")
print(yaml.safe_dump([entry], sort_keys=False, allow_unicode=True).rstrip())
if not dry:
    models.append(entry)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    fd, staged_raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        os.fchmod(stream.fileno(), 0o600)
        json.dump(payload, stream, indent=2, ensure_ascii=False)
        stream.write("\n")
        stream.flush(); os.fsync(stream.fileno())
    os.replace(staged_raw, path); os.chmod(path, 0o600)
print(f"Surface: {surface}")
print(f"OutputCapFallback: {'yes' if fallback else 'no'}")
print(f"OutputCap: {output}")
PY
)"
  rc=$?
  (( cleanup )) && rm -f "$payload_file"
  local -a display_lines
  local line
  for line in "${(@f)out}"; do
    case "$line" in
      "Surface: "*) surface="${line#Surface: }" ;;
      "OutputCapFallback: "*) output_fallback="${line#OutputCapFallback: }" ;;
      "OutputCap: "*) output_cap="${line#OutputCap: }" ;;
      *) display_lines+=("$line") ;;
    esac
  done
  (( ${#display_lines[@]} )) && print -r -- "${(F)display_lines}"

  if (( rc == 0 && ! dry_run )); then
    ai_litellm_render_user_config >/dev/null || rc=$?
  fi
  if (( rc == 0 && ! dry_run )) && [[ -n "$claude_tier" ]]; then
    ai_litellm_harness_alias_set claude "$claude_tier" "$surface" || rc=$?
  fi
  if (( rc != 0 && ! dry_run )); then
    (( models_existed )) && cp -p "$backup_dir/models.json" "$AI_LITELLM_USER_MODELS" || rm -f "$AI_LITELLM_USER_MODELS"
    (( settings_existed )) && cp -p "$backup_dir/settings.json" "$AI_LITELLM_USER_CLAUDE_SETTINGS" || rm -f "$AI_LITELLM_USER_CLAUDE_SETTINGS"
    ai_litellm_render_user_config >/dev/null 2>&1 || true
  fi
  [[ -n "$backup_dir" ]] && rm -rf "$backup_dir"
  (( ! dry_run )) && ai_litellm_user_mutation_lock_release
  (( rc == 0 )) || return $rc
  (( dry_run )) && return 0
  [[ "$output_fallback" == yes ]] && echo "Output cap was not published; conservative $output_cap is recorded and must be reviewed." >&2
  [[ -n "${AI_LITELLM_SKIP_SYNC:-}" ]] && { echo "User overlay written; sync skipped by AI_LITELLM_SKIP_SYNC."; return 0; }
  ai_litellm_sync
}

# Register an arbitrary LiteLLM backend without putting a credential value in
# configuration. OpenRouter users should prefer `model add`, which discovers
# provider metadata automatically; this command is for other LiteLLM providers
# and explicit OpenAI-compatible endpoints.
ai_litellm_model_register() {
  local surface="" backend="" context="" output="" api_base="" api_key_env=""
  local efforts="" supports_reasoning=0 dry_run=0
  while (( $# > 0 )); do
    case "$1" in
      --backend) shift; [[ $# -gt 0 && "$1" != -* ]] || { echo "Missing value after --backend" >&2; return 1; }; backend="$1" ;;
      --context) shift; [[ $# -gt 0 && "$1" != -* ]] || { echo "Missing value after --context" >&2; return 1; }; context="$1" ;;
      --output) shift; [[ $# -gt 0 && "$1" != -* ]] || { echo "Missing value after --output" >&2; return 1; }; output="$1" ;;
      --api-base) shift; [[ $# -gt 0 && "$1" != -* ]] || { echo "Missing value after --api-base" >&2; return 1; }; api_base="$1" ;;
      --api-key-env) shift; [[ $# -gt 0 && "$1" != -* ]] || { echo "Missing value after --api-key-env" >&2; return 1; }; api_key_env="$1" ;;
      --reasoning-efforts) shift; [[ $# -gt 0 && "$1" != -* ]] || { echo "Missing value after --reasoning-efforts" >&2; return 1; }; efforts="$1" ;;
      --supports-reasoning) supports_reasoning=1 ;;
      --dry-run) dry_run=1 ;;
      -h|--help)
        cat <<'EOF'
Usage: claude-litellm model register <surface> --backend <litellm/model> --context N --output N [options]

Options:
  --api-base <https-or-loopback-url>   Explicit compatible endpoint
  --api-key-env <ENV_VAR|none>         Required credential reference; never a key value
  --supports-reasoning                 Declare non-selectable reasoning support
  --reasoning-efforts <csv>            none,minimal,low,medium,high
                                       xhigh/max are blocked: LiteLLM 1.92
                                       normalizes unqualified values to high
  --dry-run                            Validate and print without writing

Run `model qualify` before assigning this route to a Claude tier.
EOF
        return 0 ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) [[ -z "$surface" ]] || { echo "Only one surface name may be registered." >&2; return 1; }; surface="$1" ;;
    esac
    shift
  done
  [[ -n "$surface" && -n "$backend" && "$context" == <-> && "$output" == <-> && \
     "$context" -gt 0 && "$output" -gt 0 ]] || {
    echo "Usage: claude-litellm model register <surface> --backend <provider/model> --context N --output N [options]" >&2
    return 1
  }
  [[ -n "$api_key_env" ]] || {
    echo "--api-key-env ENV_VAR|none is required so provider credentials are explicit" >&2
    return 1
  }
  case "$api_key_env" in
    ANTHROPIC_AUTH_TOKEN|CLAUDE_CODE_OAUTH_TOKEN|LITELLM_API_KEY|LITELLM_MASTER_KEY|XAI_API_KEY)
      echo "--api-key-env $api_key_env is reserved for the local gateway" >&2
      return 1
      ;;
  esac

  local python backup="" existed=0 rc=0
  python="$(ai_litellm_litellm_python 2>/dev/null)" || return 1
  if (( ! dry_run )); then
    ai_litellm_user_mutation_lock_acquire || return 1
    backup="$(mktemp "${TMPDIR:-/tmp}/claude-litellm-register.json.XXXXXX")" || {
      ai_litellm_user_mutation_lock_release
      return 1
    }
    if [[ -f "$AI_LITELLM_USER_MODELS" ]]; then
      cp -p "$AI_LITELLM_USER_MODELS" "$backup"
      existed=1
    fi
  fi

  ai_litellm_python_isolated "$python" - "$AI_LITELLM_CONFIG" "$AI_LITELLM_USER_MODELS" "$surface" "$backend" \
    "$context" "$output" "$api_base" "$api_key_env" "$supports_reasoning" "$efforts" "$dry_run" <<'PY' || rc=$?
import json, os, re, stat, sys, tempfile
from pathlib import Path
from urllib.parse import urlparse
import yaml

(
    config_raw, user_raw, surface, backend, context_raw, output_raw,
    api_base, api_key_env, supports_raw, efforts_raw, dry_raw,
) = sys.argv[1:]
dry = dry_raw == "1"
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:+-]{0,127}", surface):
    raise SystemExit("surface contains unsafe characters")
reserved_surfaces = {
    "auth", "context", "doctor", "fable", "haiku", "harness", "key",
    "model", "opus", "permissions", "proxy", "reasoning", "runtime",
    "sonnet", "status", "sync", "uninstall", "use",
}
if surface in reserved_surfaces:
    raise SystemExit(f"surface is reserved by the claude-litellm CLI: {surface}")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*/[^\s/][^\s]*", backend):
    raise SystemExit("backend must be an explicit provider/model LiteLLM identifier")
if not api_key_env:
    raise SystemExit("--api-key-env ENV_VAR|none is required so provider credentials are explicit")
if api_key_env != "none" and not re.fullmatch(r"[A-Z][A-Z0-9_]*", api_key_env):
    raise SystemExit("--api-key-env must be an uppercase environment variable name or none")
if api_key_env in {"ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "LITELLM_API_KEY", "LITELLM_MASTER_KEY", "XAI_API_KEY"}:
    raise SystemExit(f"--api-key-env {api_key_env} is reserved for the local gateway")
control_prefixes = ("AI_LITELLM_", "CLAUDE_LITELLM_", "CHATGPT_", "XAI_OAUTH_", "LITELLM_")
control_suffixes = ("_DIR", "_PATH", "_HOME", "_CONFIG", "_FILE", "_ROOT", "_URL", "_HOST", "_PORT", "_ENABLED", "_MODEL")
secret_marker = re.compile(
    r"(?:^|_)(?:API_?KEY|APIKEY|TOKEN|SECRET|PASSWORD|PRIVATE_KEY|CREDENTIALS?|ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN)(?:_|$)"
)
if api_key_env != "none" and (
    api_key_env.startswith(control_prefixes)
    or api_key_env.endswith(control_suffixes)
    or not (
        secret_marker.search(api_key_env)
        or api_key_env.endswith("APIKEY")
        or api_key_env.endswith("_KEY")
    )
):
    raise SystemExit("--api-key-env must name a dedicated provider credential variable")
if api_base:
    parsed = urlparse(api_base)
    if (
        not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or not (
            parsed.scheme == "https"
            or (parsed.scheme == "http" and parsed.hostname in {"127.0.0.1", "localhost", "::1"})
        )
    ):
        raise SystemExit("--api-base must use HTTPS or loopback HTTP and contain no credentials/query/fragment")
valid_efforts = {"none", "minimal", "low", "medium", "high"}
efforts = [value.strip() for value in efforts_raw.split(",") if value.strip()]
if len(efforts) != len(set(efforts)) or any(value not in valid_efforts for value in efforts):
    raise SystemExit(
        "invalid or duplicate --reasoning-efforts value; allowed: "
        "none,minimal,low,medium,high (LiteLLM 1.92 normalizes "
        "unqualified xhigh/max to high)"
    )
supports = supports_raw == "1" or bool(efforts)
config = yaml.safe_load(Path(config_raw).read_text(encoding="utf-8")) or {}
if any(entry.get("model_name") == surface for entry in config.get("model_list", [])):
    raise SystemExit(f"model_name already exists: {surface}")
params = {"model": backend}
if api_base:
    params["api_base"] = api_base
if api_key_env:
    params["api_key"] = "none" if api_key_env == "none" else f"os.environ/{api_key_env}"
if efforts:
    params["allowed_openai_params"] = ["reasoning_effort"]
entry = {
    "model_name": surface,
    "litellm_params": params,
    "model_info": {
        "max_input_tokens": int(context_raw),
        "max_output_tokens": int(output_raw),
        "supports_reasoning": supports,
        "x_reasoning_efforts": efforts,
        "x_input_confidence": "user-declared",
        "x_input_source": "model-register; qualify-and-verify",
        "x_output_confidence": "user-declared",
        "x_output_source": "model-register; qualify-and-verify",
        "x_reasoning_confidence": "user-declared",
        "x_reasoning_source": "model-register; qualify-and-verify",
    },
}
path = Path(user_raw)
if path.exists() or path.is_symlink():
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode) or stat.S_IMODE(mode) != 0o600:
        raise SystemExit(f"unsafe user model registry: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
else:
    payload = {"schemaVersion": 1, "models": []}
if payload.get("schemaVersion", 1) != 1 or not isinstance(payload.get("models", []), list):
    raise SystemExit("unsupported or malformed user model registry")
models = payload.setdefault("models", [])
if any(isinstance(candidate, dict) and candidate.get("model_name") == surface for candidate in models):
    raise SystemExit(f"model_name already exists in user registry: {surface}")
print(yaml.safe_dump([entry], sort_keys=False, allow_unicode=True).rstrip())
if dry:
    raise SystemExit(0)
models.append(entry)
path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
os.chmod(path.parent, 0o700)
fd, staged_raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    os.fchmod(stream.fileno(), 0o600)
    json.dump(payload, stream, indent=2, ensure_ascii=False)
    stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
os.replace(staged_raw, path); os.chmod(path, 0o600)
PY
  if (( rc == 0 && ! dry_run )); then
    ai_litellm_render_user_config >/dev/null || rc=$?
  fi
  if (( rc != 0 && ! dry_run )); then
    (( existed )) && cp -p "$backup" "$AI_LITELLM_USER_MODELS" || rm -f "$AI_LITELLM_USER_MODELS"
    ai_litellm_render_user_config >/dev/null 2>&1 || true
  fi
  [[ -n "$backup" ]] && rm -f "$backup"
  (( ! dry_run )) && ai_litellm_user_mutation_lock_release
  (( rc == 0 )) || return $rc
  (( dry_run )) && return 0
  echo "Registered durable user route: $surface -> $backend"
  [[ -n "${AI_LITELLM_SKIP_SYNC:-}" ]] && return 0
  ai_litellm_sync
}

# Remove only a user-owned route. Built-ins, OAuth routes and runtime-discovered
# routes are immutable through this command and therefore always recoverable.
ai_litellm_model_remove() {
  local surface="" dry_run=0
  while (( $# > 0 )); do
    case "$1" in
      --dry-run) dry_run=1 ;;
      -h|--help) echo "Usage: claude-litellm model remove <user-surface> [--dry-run]"; return 0 ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) [[ -z "$surface" ]] || { echo "Only one model may be removed." >&2; return 1; }; surface="$1" ;;
    esac
    shift
  done
  [[ -n "$surface" ]] || { echo "Usage: claude-litellm model remove <user-surface> [--dry-run]" >&2; return 1; }
  local aliases="" python
  python="$(ai_litellm_litellm_python)" || return 1
  local backup="" existed=0
  if (( ! dry_run )); then
    ai_litellm_user_mutation_lock_acquire || return 1
    backup="$(mktemp "${TMPDIR:-/tmp}/claude-litellm-models.json.XXXXXX")" || { ai_litellm_user_mutation_lock_release; return 1; }
    if [[ -f "$AI_LITELLM_USER_MODELS" ]]; then cp -p "$AI_LITELLM_USER_MODELS" "$backup"; existed=1; fi
  fi
  aliases="$(ai_litellm_harness_alias_json claude 2>/dev/null || printf '[]')"
  ai_litellm_python_isolated "$python" - "$AI_LITELLM_CONFIG" "$AI_LITELLM_USER_MODELS" "$surface" "$dry_run" "$aliases" <<'PY'
import json, os, stat, sys, tempfile
from pathlib import Path
import yaml
config_path, user_raw, surface, dry_raw, aliases_raw = sys.argv[1:]
dry = dry_raw == "1"
path = Path(user_raw)
if path.exists() or path.is_symlink():
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode) or stat.S_IMODE(mode) != 0o600:
        raise SystemExit(f"unsafe user model registry: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))
else:
    payload = {"schemaVersion": 1, "models": []}
models = payload.get("models", [])
index = next((i for i, e in enumerate(models) if e.get("model_name") == surface), None)
if index is None:
    config = yaml.safe_load(open(config_path, encoding="utf-8")) or {}
    known = any(e.get("model_name") == surface for e in config.get("model_list", []) if isinstance(e, dict))
    raise SystemExit(f"{surface}: package/runtime model is immutable; only user overlay models can be removed" if known else f"model not found: {surface}")
aliases = json.loads(aliases_raw or "[]")
tiers = [row.get("tier") for row in aliases if row.get("model") == surface]
if tiers:
    raise SystemExit(f"{surface}: referenced by Claude tier(s) {', '.join(tiers)}; reassign first")
target = models[index]
print(f"claude-litellm model remove {surface}{' (dry-run)' if dry else ''}")
print(json.dumps(target, indent=2, ensure_ascii=False))
if not dry:
    del models[index]
    fd, staged_raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        os.fchmod(stream.fileno(), 0o600)
        json.dump(payload, stream, indent=2, ensure_ascii=False); stream.write("\n")
        stream.flush(); os.fsync(stream.fileno())
    os.replace(staged_raw, path); os.chmod(path, 0o600)
PY
  local rc=$?
  if (( rc == 0 && ! dry_run )); then ai_litellm_render_user_config >/dev/null || rc=$?; fi
  if (( rc != 0 && ! dry_run )); then
    (( existed )) && cp -p "$backup" "$AI_LITELLM_USER_MODELS" || rm -f "$AI_LITELLM_USER_MODELS"
    ai_litellm_render_user_config >/dev/null 2>&1 || true
  fi
  [[ -n "$backup" ]] && rm -f "$backup"
  (( ! dry_run )) && ai_litellm_user_mutation_lock_release
  (( rc == 0 )) || return $rc
  (( dry_run )) && return 0
  [[ -n "${AI_LITELLM_SKIP_SYNC:-}" ]] && { echo "User overlay written; sync skipped by AI_LITELLM_SKIP_SYNC."; return 0; }
  ai_litellm_sync
}

# Exercise the exact Anthropic Messages surface Claude Code consumes. A model
# is qualified only after text SSE, Claude system blocks, forced tool_use,
# streamed input_json_delta, a tool_result continuation, and adaptive effort
# all pass with bounded response allowances.
# Optional activation is deliberately last so a failed candidate never replaces
# a working Claude tier.
_ai_litellm_model_qualify_unlocked() {
  local model="" activate_tier="" as_json=0
  while (( $# > 0 )); do
    case "$1" in
      --activate-tier)
        shift
        [[ $# -gt 0 ]] || { echo "Missing value after --activate-tier" >&2; return 1; }
        activate_tier="$1"
        ;;
      --json) as_json=1 ;;
      -h|--help)
        cat <<'EOF'
Usage: claude-litellm model qualify <surface> [--activate-tier fable|opus|sonnet|haiku] [--json]

Run the six live /v1/messages compatibility gates. Cloud routes can incur a
small provider charge. --activate-tier changes the Claude alias only on PASS.
EOF
        return 0
        ;;
      -*) echo "Unknown option: $1" >&2; return 1 ;;
      *) [[ -z "$model" ]] || { echo "Only one model may be qualified." >&2; return 1; }; model="$1" ;;
    esac
    shift
  done
  [[ -n "$model" ]] || { echo "Usage: claude-litellm model qualify <surface> [options]" >&2; return 1; }
  if [[ -n "$activate_tier" ]]; then
    case "$activate_tier" in fable|opus|sonnet|haiku) ;; *) echo "Invalid Claude tier: $activate_tier" >&2; return 1 ;; esac
  fi

  model="$(ai_litellm_model_resolve "$model" 2>/dev/null)" || {
    echo "Unknown LiteLLM model_name or provider model: $model" >&2
    return 1
  }
  local verifier="$AI_LITELLM_HOME/scripts/verify_tool_call_fidelity.py"
  local install_manifest="$AI_LITELLM_HOME/install-manifest.json"
  [[ -f "$verifier" ]] || { echo "Missing live qualification harness: $verifier" >&2; return 1; }
  [[ -f "$install_manifest" && ! -L "$install_manifest" ]] || {
    echo "Missing or unsafe install manifest: $install_manifest" >&2
    return 1
  }
  local python master_key backend
  python="$(ai_litellm_litellm_python 2>/dev/null)" || {
    echo "Missing managed LiteLLM Python runtime." >&2
    return 1
  }
  master_key="$(ai_litellm_master_key 2>/dev/null)" || {
    echo "Missing LiteLLM master key." >&2
    return 1
  }
  # Freeze route identity before the closing sync and re-resolve after taking
  # the lock. A remove/re-add racing the initial CLI parse must never attach
  # evidence for an old backend to a newly served surface.
  ai_litellm_user_mutation_lock_acquire || return 1
  model="$(ai_litellm_model_resolve "$model" 2>/dev/null)" || {
    ai_litellm_user_mutation_lock_release
    echo "Model disappeared before qualification started." >&2
    return 1
  }
  backend="$(ai_litellm_model_backend "$model" 2>/dev/null || printf unknown)"

  # Rebuild runtime-discovered routes while the model transaction lock is held.
  # sync recognizes the pre-owned kernel lock and remains reentrant.
  ai_litellm_sync >/dev/null || { local sync_rc=$?; ai_litellm_user_mutation_lock_release; return $sync_rc; }
  if ! ai_litellm_health; then
    ai_litellm_start >/dev/null || { local start_rc=$?; ai_litellm_user_mutation_lock_release; return $start_rc; }
  fi

  # Keep the lock across the exact live exchange, evidence write, and optional
  # alias update.
  ai_litellm_model_runtime "$model" >/dev/null 2>&1 || \
    echo "Live qualification may issue billable provider requests for $model." >&2
  local verdict rc verdict_rc
  if verdict="$(LITELLM_MASTER_KEY="$master_key" ai_litellm_run_timeout 420 "$python" -I -B "$verifier" \
    --live-only --live-model "$model" --live-base-url "$(ai_litellm_base_url)" --json)"; then
    verdict_rc=0
  else
    verdict_rc=$?
  fi
  if (( as_json )); then
    print -r -- "$verdict"
  else
    print -r -- "$verdict" | jq -r '
      .live as $v |
      "Live /v1/messages qualification (\($v.model)):",
      "  text SSE                    " + (if $v.text_sse then "PASS" else "FAIL" end),
      "  Claude system blocks        " + (if $v.claude_system_block_instructions then "PASS" else "FAIL" end),
      "  forced structured tool     " + (if $v.forced_structured_tool then "PASS" else "FAIL" end),
      "  streaming input_json_delta " + (if $v.streaming_input_json_delta then "PASS" else "FAIL" end),
      "  tool_result continuation   " + (if $v.tool_result_continuation then "PASS" else "FAIL" end),
      "  adaptive effort policy     " + (if $v.claude_adaptive_effort_policy then "PASS" else "FAIL" end),
      "=> " + (if .all_critical_pass then "QUALIFIED" else "FAILED" end)'
  fi
  mkdir -p "$AI_LITELLM_PROXY_HOME"
  chmod 700 "$AI_LITELLM_PROXY_HOME"
  ai_litellm_python_isolated "$python" - "$AI_LITELLM_QUALIFICATIONS_FILE" "$AI_LITELLM_CONFIG" "$verifier" "$install_manifest" "$model" "$backend" "$verdict_rc" "$verdict" <<'PY'
import hashlib, json, os, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path
import stat

(
    state_raw,
    config_raw,
    verifier_raw,
    manifest_raw,
    model,
    backend,
    verifier_exit_raw,
    verdict_raw,
) = sys.argv[1:]
state_path = Path(state_raw)
config_path = Path(config_raw)
verifier_path = Path(verifier_raw)
manifest_path = Path(manifest_raw)
if state_path.exists() or state_path.is_symlink():
    mode = state_path.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode) or stat.S_IMODE(mode) != 0o600:
        raise SystemExit(f"unsafe qualification state file: {state_path}")
    state = json.loads(state_path.read_text(encoding="utf-8"))
else:
    state = {"schemaVersion": 1, "models": {}}
if state.get("schemaVersion") != 1 or not isinstance(state.get("models"), dict):
    raise SystemExit("unsupported or malformed qualification state")
try:
    verdict = json.loads(verdict_raw)
    live = verdict["live"]
    verifier_exit = int(verifier_exit_raw)
    passed = (
        verifier_exit == 0
        and verdict.get("all_critical_pass") is True
        and live.get("all_gates_pass") is True
    )
except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
    live = {
        "model": model,
        "all_gates_pass": False,
        "qualification_error": "verifier exited without a valid verdict",
    }
    passed = False
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
attempted_at = datetime.now(timezone.utc).isoformat()
entry = {
    "attemptedAt": attempted_at,
    "passed": passed,
    "providerModel": backend,
    "gateSetVersion": 2,
    "verifierExitCode": int(verifier_exit_raw),
    "configSha256": hashlib.sha256(config_path.read_bytes()).hexdigest(),
    "verifierSha256": hashlib.sha256(verifier_path.read_bytes()).hexdigest(),
    "installManifestSha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
    "sourceCommit": (manifest.get("source") or {}).get("commit"),
    "runtimeContentFingerprint": (manifest.get("runtime") or {}).get("contentFingerprint"),
    "gates": live,
}
if passed:
    entry["qualifiedAt"] = attempted_at
state.setdefault("models", {})[model] = entry
state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
fd, staged_raw = tempfile.mkstemp(prefix=f".{state_path.name}.", dir=state_path.parent)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    os.fchmod(stream.fileno(), 0o600)
    json.dump(state, stream, indent=2, ensure_ascii=False)
    stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
os.replace(staged_raw, state_path); os.chmod(state_path, 0o600)
if not passed:
    raise SystemExit(3)
PY
  rc=$?
  if (( rc == 3 )); then
    ai_litellm_user_mutation_lock_release
    if (( verdict_rc != 0 )); then
      return $verdict_rc
    fi
    return 1
  fi
  if (( rc != 0 )); then
    ai_litellm_user_mutation_lock_release
    echo "Failed to persist qualification evidence; Claude aliases were not changed." >&2
    return $rc
  fi
  if (( verdict_rc != 0 )); then
    ai_litellm_user_mutation_lock_release
    return $verdict_rc
  fi

  if [[ -n "$activate_tier" ]]; then
    local activation_backup activation_settings_existed=0
    activation_backup="$(mktemp "${TMPDIR:-/tmp}/claude-litellm-qualification-settings.json.XXXXXX")" || {
      ai_litellm_user_mutation_lock_release
      return 1
    }
    if [[ -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" ]]; then
      cp -p "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$activation_backup"
      activation_settings_existed=1
    fi
    if (( as_json )); then
      ai_litellm_harness_alias_set claude "$activate_tier" "$model" >/dev/null || {
        rc=$?; rm -f "$activation_backup"; ai_litellm_user_mutation_lock_release; return $rc
      }
    else
      ai_litellm_harness_alias_set claude "$activate_tier" "$model" || {
        rc=$?; rm -f "$activation_backup"; ai_litellm_user_mutation_lock_release; return $rc
      }
    fi
    if ai_litellm_sync >/dev/null; then
      :
    else
      rc=$?
      (( activation_settings_existed )) && cp -p "$activation_backup" "$AI_LITELLM_USER_CLAUDE_SETTINGS" || rm -f "$AI_LITELLM_USER_CLAUDE_SETTINGS"
      ai_litellm_render_user_config >/dev/null 2>&1 || true
      ai_litellm_render_claude_settings claude >/dev/null 2>&1 || true
      rm -f "$activation_backup"
      ai_litellm_user_mutation_lock_release
      echo "Qualification passed, but activation sync failed; the Claude alias was rolled back." >&2
      return $rc
    fi
    rm -f "$activation_backup"
    ai_litellm_user_mutation_lock_release
    (( as_json )) || echo "Activated Claude $activate_tier -> $model after qualification."
  else
    ai_litellm_user_mutation_lock_release
  fi
}

ai_litellm_model_qualify() {
  ai_litellm_lifecycle_lock_acquire || return $?
  local rc=0 mutation_preowned=0
  [[ "${AI_LITELLM_USER_MUTATION_FD:-}" == <-> ]] && mutation_preowned=1
  {
    _ai_litellm_model_qualify_unlocked "$@" || rc=$?
  } always {
    if (( ! mutation_preowned )) && [[ "${AI_LITELLM_USER_MUTATION_FD:-}" == <-> ]]; then
      ai_litellm_user_mutation_lock_release
    fi
    ai_litellm_lifecycle_lock_release
  }
  return $rc
}

# Provider/backend reasoning capability table from the LiteLLM registry. It
# shows route-level defaults before any harness intent is considered.
ai_litellm_model_reasoning_table() {
  local filter="$1"
  local litellm_python
  litellm_python="$(ai_litellm_litellm_python 2>/dev/null)" || {
    echo "Missing LiteLLM Python runtime; cannot inspect local capability." >&2
    return 1
  }

  ai_litellm_python_isolated "$litellm_python" - "$AI_LITELLM_CONFIG" "$AI_LITELLM_REASONING_OBS_FILE" "$filter" <<'PY'
import json
import os
import sys

import yaml

try:
    import litellm
except Exception as exc:
    print(f"Failed to import litellm: {exc}", file=sys.stderr)
    raise SystemExit(1)

config_path, observations_path, raw_filter = sys.argv[1:4]
model_filter = raw_filter or ""
emit_json = os.environ.get("AI_LITELLM_MATRIX_JSON") == "1"
with open(config_path, "r", encoding="utf-8") as fh:
    config = yaml.safe_load(fh) or {}

try:
    with open(observations_path, "r", encoding="utf-8") as fh:
        observations = json.load(fh)
except Exception:
    observations = {}

drop_params = bool((config.get("litellm_settings") or {}).get("drop_params"))


def provider_for(model):
    return (model or "-").split("/", 1)[0]


def provider_default(entry):
    litellm_params = entry.get("litellm_params") or {}
    reasoning = litellm_params.get("reasoning")
    reasoning_effort = litellm_params.get("reasoning_effort")
    if isinstance(reasoning, dict):
        effort = reasoning.get("effort")
        return f"effort={effort}" if effort else "reasoning"
    if reasoning is not None:
        return str(reasoning)
    if reasoning_effort is not None:
        return f"effort={reasoning_effort}"
    return str((entry.get("model_info") or {}).get("reasoning_default") or "-")


def local_capability(entry, backend):
    params = []
    supports = False
    err = None
    litellm_params = entry.get("litellm_params") or {}
    model_info = entry.get("model_info") or {}
    # Capability inspection must be pure/offline. LiteLLM's ChatGPT capability
    # helper can call get_access_token(), which starts device OAuth in the
    # unpatched CLI process. OAuth routes use our validated registry contract.
    if backend.startswith("chatgpt/") or litellm_params.get("use_xai_oauth") is True:
        efforts = model_info.get("x_reasoning_efforts") or []
        params = ["reasoning_effort"] if efforts else []
        return model_info.get("supports_reasoning") is True, params, "oauth-registry"
    try:
        supports = bool(litellm.supports_reasoning(model=backend))
    except Exception as exc:
        err = f"{type(exc).__name__}"
    try:
        params = litellm.get_supported_openai_params(model=backend) or []
    except Exception as exc:
        err = err or f"{type(exc).__name__}"
    param_support = any(p in params for p in ("reasoning_effort", "reasoning", "thinking"))
    return supports or param_support, params, err


def local_wire(declared, params):
    if not declared:
        return "-"
    if "reasoning_effort" in params:
        return "reasoning_effort"
    if "reasoning" in params:
        return "reasoning"
    if "thinking" in params:
        return "thinking"
    return "-"


def drop_risk(declared, local_supported, observed):
    if not declared:
        return "-"
    if local_supported:
        return "low"
    return "high(drop)" if drop_params else "high(error)"


def raw_observed_for(name, backend):
    models = observations.get("models") or {}
    obs = models.get(name)
    if obs:
        observed_backend = obs.get("provider_model")
        if not observed_backend or observed_backend == backend:
            return obs
    for candidate in models.values():
        if candidate.get("provider_model") == backend:
            return candidate
    return None


def observed_for(name, backend):
    obs = raw_observed_for(name, backend)
    if not obs:
        return "-"
    status = obs.get("status") or "unknown"
    tokens = obs.get("reasoning_tokens")
    if status == "accepted_with_reasoning":
        return f"accept+r({tokens or 0})"
    if status == "accepted_without_reasoning_evidence":
        return "accept(no-r)"
    if status == "observed":
        return f"legacy+r({tokens or 0})"
    if status == "not_observed":
        return "legacy(no-r)"
    if status == "error":
        return "error"
    return status


rows = []
for entry in config.get("model_list") or []:
    name = entry.get("model_name") or ""
    backend = (entry.get("litellm_params") or {}).get("model") or "-"
    if model_filter and model_filter not in (name, backend):
        continue
    mi = entry.get("model_info") or {}
    declared = mi.get("supports_reasoning") is True
    local_supported, params, err = local_capability(entry, backend)
    local_label = "yes" if local_supported else "no"
    if err == "oauth-registry":
        local_label = "registry(oauth)"
    elif err and not local_supported:
        local_label = f"no({err})"
    rows.append({
        "model": name,
        "providerModel": backend,
        "declared": "yes" if declared else "no",
        "litellmCap": local_label,
        "default": provider_default(entry),
        "effort": provider_default(entry),
        "localWire": local_wire(declared, params),
        "dropRisk": drop_risk(declared, local_supported, raw_observed_for(name, backend)),
        "probe": observed_for(name, backend),
    })

if emit_json:
    print(json.dumps(rows), end="")
else:
    print(
        "%-22s %-42s %-9s %-12s %-14s %-22s %-12s %-12s"
        % (
            "model_name",
            "provider_model",
            "declared",
            "litellm_cap",
            "default",
            "local_wire",
            "drop_risk",
            "probe",
        )
    )
    for row in rows:
        print(
            "%-22s %-42s %-9s %-12s %-14s %-22s %-12s %-12s"
            % (
                row["model"],
                row["providerModel"],
                row["declared"],
                row["litellmCap"],
                row["default"],
                row["localWire"],
                row["dropRisk"],
                row["probe"],
            )
        )
PY
}

ai_litellm_reasoning_matrix_json() {
  AI_LITELLM_MATRIX_JSON=1 ai_litellm_model_reasoning_table "$@" 2>/dev/null || printf '[]'
}

ai_litellm_model_reasoning_allowed_efforts() {
  local model="$1"
  model="$(ai_litellm_model_resolve "$model" 2>/dev/null)" || {
    echo "Unknown LiteLLM model_name or provider model: $model" >&2
    return 1
  }
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
target = ARGV[1]
entry = Array(config["model_list"]).find { |item| item["model_name"] == target }
abort("Unknown LiteLLM model_name: #{target}") unless entry
supports = entry.dig("model_info", "supports_reasoning") == true
abort("Model does not declare supports_reasoning: true: #{target}") unless supports
allowed = entry.dig("model_info", "x_reasoning_efforts")
abort("Model does not publish configurable reasoning effort levels: #{target}") unless allowed.is_a?(Array) && !allowed.empty?
valid = %w[none minimal low medium high xhigh max]
unknown = allowed.map(&:to_s) - valid
abort("Invalid configured reasoning effort levels for #{target}: #{unknown.join(", ")}") unless unknown.empty?
puts allowed.join(" ")
' "$AI_LITELLM_CONFIG" "$model"
}

ai_litellm_reasoning_effort_metadata_ok() {
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
valid = %w[none minimal low medium high xhigh max]
errors = []
Array(config["model_list"]).each do |entry|
  name = entry["model_name"].to_s
  info = entry["model_info"] || {}
  backend = entry.dig("litellm_params", "model").to_s
  efforts = info["x_reasoning_efforts"]
  unless efforts.is_a?(Array)
    errors << "#{name}: model_info.x_reasoning_efforts must be an array"
    next
  end
  values = efforts.map(&:to_s)
  errors << "#{name}: duplicate x_reasoning_efforts" unless values.uniq == values
  unknown = values - valid
  errors << "#{name}: invalid x_reasoning_efforts #{unknown.join(",")}" unless unknown.empty?
  supports = info["supports_reasoning"] == true
  errors << "#{name}: effort levels require supports_reasoning=true" if !supports && !values.empty?
  transport_limited = backend.start_with?("openrouter/") || info["x_registry_source"] == "user-overlay"
  blocked = values & %w[xhigh max]
  if transport_limited && !blocked.empty?
    errors << "#{name}: #{blocked.join(",")} cannot be selectable; LiteLLM 1.92 normalizes unqualified xhigh/max to high"
  end
  if info.key?("x_provider_reasoning_efforts")
    provider_efforts = info["x_provider_reasoning_efforts"]
    unless provider_efforts.is_a?(Array)
      errors << "#{name}: model_info.x_provider_reasoning_efforts must be an array"
    else
      provider_values = provider_efforts.map(&:to_s)
      errors << "#{name}: duplicate x_provider_reasoning_efforts" unless provider_values.uniq == provider_values
      provider_unknown = provider_values - valid
      errors << "#{name}: invalid x_provider_reasoning_efforts #{provider_unknown.join(",")}" unless provider_unknown.empty?
      expected = provider_values.reject { |value| %w[xhigh max].include?(value) }
      if transport_limited && values != expected
        errors << "#{name}: selectable efforts must equal provider efforts after the high transport ceiling"
      end
      errors << "#{name}: x_reasoning_effort_ceiling must be high" unless info["x_reasoning_effort_ceiling"] == "high"
      source = info["x_reasoning_transport_source"]
      errors << "#{name}: x_reasoning_transport_source is required" unless source.is_a?(String) && !source.empty?
    end
  end
  allowed_params = Array(entry.dig("litellm_params", "allowed_openai_params")).map(&:to_s)
  if allowed_params.include?("reasoning_effort") && values.empty?
    errors << "#{name}: reasoning_effort passthrough requires explicit effort levels"
  end
end
unless errors.empty?
  errors.each { |error| warn error }
  exit 1
end
' "$AI_LITELLM_CONFIG"
}

ai_litellm_model_reasoning_allowed_json() {
  local allowed
  allowed="$(ai_litellm_model_reasoning_allowed_efforts "${1:-}" 2>/dev/null)" || { printf '[]'; return 0; }
  ai_litellm_ruby -rjson -e 'puts JSON.generate(ARGV[0].to_s.split)' "$allowed" 2>/dev/null || printf '[]'
}

ai_litellm_model_reasoning_update_legacy() {
  echo "Internal legacy mutator retired: package-generated configuration is immutable." >&2
  return 1
  local mode="$1"
  local model="$2"
  local effort="${3:-}"
  if [[ -z "$mode" || -z "$model" ]]; then
    echo "Usage: claude-litellm model reasoning set <model> <effort>" >&2
    echo "       claude-litellm model reasoning unset <model>" >&2
    return 1
  fi
  if [[ "$mode" == "set" && -z "$effort" ]]; then
    echo "Usage: claude-litellm model reasoning set <model> <effort>" >&2
    return 1
  fi
  model="$(ai_litellm_model_resolve "$model" 2>/dev/null)" || {
    echo "Unknown LiteLLM model_name or provider model: $model" >&2
    return 1
  }

  if [[ "$mode" == "set" ]]; then
    local allowed
    allowed="$(ai_litellm_model_reasoning_allowed_efforts "$model")" || return $?
    case " $allowed " in
      *" $effort "*) ;;
      *)
        echo "Unsupported provider reasoning effort for $model: $effort (allowed: ${allowed// /, })" >&2
        return 1
        ;;
    esac
  fi

  ai_litellm_ruby -ryaml -e '
path, mode, target, effort = ARGV
config = (YAML.load_file(path, aliases: true) rescue YAML.load_file(path))
entry = Array(config["model_list"]).find { |item| item["model_name"] == target }
abort("Unknown LiteLLM model_name: #{target}") unless entry
if mode == "set" && entry.dig("model_info", "supports_reasoning") != true
  abort("Model does not declare supports_reasoning: true: #{target}")
end

backend = entry.dig("litellm_params", "model").to_s
# Reasoning is a property of the UNDERLYING model, like the token-limit anchors.
# Apply mutations to every surface model_name that routes to the same backend.
targets = Array(config["model_list"])
  .select { |item| item.dig("litellm_params", "model").to_s == backend }
  .map { |item| item["model_name"] }.compact

def atomic_write(path, content)
  stat = File.stat(path)
  tmp = "#{path}.tmp.#{$$}"
  File.write(tmp, content)
  File.chmod(stat.mode & 0777, tmp)
  File.rename(tmp, path)
ensure
  File.delete(tmp) if tmp && File.exist?(tmp)
end

def entry_range(lines, name)
  start = lines.index { |line| line.match?(/^  - model_name:\s*#{Regexp.escape(name)}\s*$/) }
  return nil unless start
  finish = ((start + 1)...lines.length).find { |idx| lines[idx].match?(/^  - model_name:\s*/) } || lines.length
  [start, finish]
end

def strip_reasoning_defaults!(lines, start, finish)
  idx = start + 1
  while idx < finish
    if lines[idx].match?(/^      reasoning:\s*/) || lines[idx].match?(/^      reasoning_effort:\s*/)
      lines.delete_at(idx)
      finish -= 1
      while idx < finish && lines[idx].match?(/^        /)
        lines.delete_at(idx)
        finish -= 1
      end
      next
    end
    idx += 1
  end
  finish
end

lines = File.read(path).lines
targets.each do |name|
  range = entry_range(lines, name)
  next unless range
  start, finish = range
  litellm_params = (start...finish).find { |idx| lines[idx].match?(/^    litellm_params:\s*$/) }
  finish = strip_reasoning_defaults!(lines, start, finish)
  next unless mode == "set"
  next unless litellm_params
  # reasoning_effort is the contracted LiteLLM key (mapped to OpenRouter
  # reasoning:{effort} and to OpenAI reasoning_effort). Never hand-write a raw
  # top-level reasoning: key.
  insert = ((litellm_params + 1)...finish).find { |line_idx| lines[line_idx].match?(/^    model_info:/) } || finish
  lines.insert(insert, %(      reasoning_effort: "#{effort}"\n))
end

atomic_write(path, lines.join)
STDOUT.puts(mode == "set" ? "Applied to: #{targets.join(", ")}" : "Cleared: #{targets.join(", ")}")
' "$AI_LITELLM_CONFIG" "$mode" "$model" "$effort" || return $?

  if [[ "$mode" == "set" ]]; then
    echo "Updated provider reasoning default for $model's backend -> effort=$effort"
  else
    echo "Cleared provider reasoning default for $model's backend"
  fi
  echo "Run 'claude-litellm sync' to apply it to the running proxy."
}

# Provider defaults are mutable only for user-owned routes. Package routes are
# release defaults; changing their generated effective YAML would be lost on
# the next sync. Claude's per-launch --effort or the durable harness default is
# the correct control for those built-ins.
ai_litellm_model_reasoning_update() {
  local mode="$1" model="$2" effort="${3:-}"
  if [[ -z "$mode" || -z "$model" || ( "$mode" == set && -z "$effort" ) ]]; then
    echo "Usage: claude-litellm model reasoning set <user-model> <effort>" >&2
    echo "       claude-litellm model reasoning unset <user-model>" >&2
    return 1
  fi
  model="$(ai_litellm_model_resolve "$model" 2>/dev/null)" || {
    echo "Unknown LiteLLM model_name or provider model: $model" >&2
    return 1
  }
  if [[ "$mode" == set ]]; then
    local allowed
    allowed="$(ai_litellm_model_reasoning_allowed_efforts "$model")" || return $?
    case " $allowed " in
      *" $effort "*) ;;
      *) echo "Unsupported provider reasoning effort for $model: $effort (allowed: ${allowed// /, })" >&2; return 1 ;;
    esac
  fi

  local python backup="" existed=0 rc=0
  python="$(ai_litellm_litellm_python 2>/dev/null)" || return 1
  ai_litellm_user_mutation_lock_acquire || return 1
  backup="$(mktemp "${TMPDIR:-/tmp}/claude-litellm-model-reasoning.json.XXXXXX")" || {
    ai_litellm_user_mutation_lock_release
    return 1
  }
  if [[ -f "$AI_LITELLM_USER_MODELS" ]]; then
    cp -p "$AI_LITELLM_USER_MODELS" "$backup"
    existed=1
  fi

  ai_litellm_python_isolated "$python" - "$AI_LITELLM_CONFIG" "$AI_LITELLM_USER_MODELS" "$mode" "$model" "$effort" <<'PY' || rc=$?
import json, os, stat, sys, tempfile
from pathlib import Path
import yaml

config_raw, user_raw, mode, model, effort = sys.argv[1:]
config = yaml.safe_load(Path(config_raw).read_text(encoding="utf-8")) or {}
target = next((e for e in config.get("model_list", []) if e.get("model_name") == model), None)
if target is None:
    raise SystemExit(f"unknown model: {model}")
backend = (target.get("litellm_params") or {}).get("model")
path = Path(user_raw)
if not path.is_file() or path.is_symlink():
    raise SystemExit(
        f"{model}: package/runtime route is immutable; use Claude --effort "
        "or add a user-owned route"
    )
file_stat = path.lstat()
if stat.S_IMODE(file_stat.st_mode) != 0o600:
    raise SystemExit(f"unsafe user model registry permissions: {path}")
payload = json.loads(path.read_text(encoding="utf-8"))
targets = [
    entry for entry in payload.get("models", [])
    if (entry.get("litellm_params") or {}).get("model") == backend
]
if not targets:
    raise SystemExit(
        f"{model}: package/runtime route is immutable; use Claude --effort "
        "or add a user-owned route"
    )
for entry in targets:
    params = entry.setdefault("litellm_params", {})
    params.pop("reasoning", None)
    if mode == "set":
        params["reasoning_effort"] = effort
    else:
        params.pop("reasoning_effort", None)
fd, staged_raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
with os.fdopen(fd, "w", encoding="utf-8") as stream:
    os.fchmod(stream.fileno(), 0o600)
    json.dump(payload, stream, indent=2, ensure_ascii=False)
    stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
os.replace(staged_raw, path); os.chmod(path, 0o600)
print(
    ("Applied to: " if mode == "set" else "Cleared: ")
    + ", ".join(entry["model_name"] for entry in targets)
)
PY
  if (( rc == 0 )); then
    ai_litellm_render_user_config >/dev/null || rc=$?
  fi
  if (( rc != 0 )); then
    (( existed )) && cp -p "$backup" "$AI_LITELLM_USER_MODELS" || rm -f "$AI_LITELLM_USER_MODELS"
    ai_litellm_render_user_config >/dev/null 2>&1 || true
  fi
  rm -f "$backup"
  ai_litellm_user_mutation_lock_release
  (( rc == 0 )) || return $rc
  echo "Updated durable provider reasoning default for $model."
  [[ -n "${AI_LITELLM_SKIP_SYNC:-}" ]] && return 0
  ai_litellm_sync
}

ai_litellm_model_reasoning_set() {
  ai_litellm_model_reasoning_update set "$@"
}

ai_litellm_model_reasoning_unset() {
  ai_litellm_model_reasoning_update unset "$@"
}

ai_litellm_reasoning_observation_record() {
  local observation_json="$1"
  local safe_dir
  for safe_dir in "$AI_LITELLM_STATE_HOME" "$AI_LITELLM_PROXY_HOME"; do
    if [[ -e "$safe_dir" || -L "$safe_dir" ]]; then
      [[ -d "$safe_dir" && ! -L "$safe_dir" ]] || {
        echo "Refusing unsafe reasoning evidence directory: $safe_dir" >&2
        return 1
      }
    fi
  done
  mkdir -p "$AI_LITELLM_PROXY_HOME"
  chmod 700 "$AI_LITELLM_STATE_HOME" "$AI_LITELLM_PROXY_HOME" 2>/dev/null || true
  if [[ -e "$AI_LITELLM_REASONING_OBS_FILE" || -L "$AI_LITELLM_REASONING_OBS_FILE" ]]; then
    [[ -f "$AI_LITELLM_REASONING_OBS_FILE" && ! -L "$AI_LITELLM_REASONING_OBS_FILE" && \
       "$(stat -f %Lp "$AI_LITELLM_REASONING_OBS_FILE" 2>/dev/null)" == "600" ]] || {
      echo "Refusing unsafe reasoning evidence file: $AI_LITELLM_REASONING_OBS_FILE" >&2
      return 1
    }
  fi
  node -e '
const fs = require("fs");
const [file, raw] = process.argv.slice(1);
const observation = JSON.parse(raw);
let state = {models: {}, history: []};
try {
  state = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
if (!state || typeof state !== "object" || Array.isArray(state)) state = {models: {}, history: []};
if (!state.models || typeof state.models !== "object" || Array.isArray(state.models)) state.models = {};
if (!Array.isArray(state.history)) state.history = [];
state.models[observation.model_name] = observation;
state.history.push(observation);
state.history = state.history.slice(-100);
const tmp = `${file}.tmp.${process.pid}`;
try {
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2) + "\n", {mode: 0o600, flag: "wx"});
  fs.renameSync(tmp, file);
} catch (error) {
  try { fs.unlinkSync(tmp); } catch (_) {}
  throw error;
}
' "$AI_LITELLM_REASONING_OBS_FILE" "$observation_json"
}

_ai_litellm_model_reasoning_probe_unlocked() {
  local model="" effort="" candidate=0 arg
  for arg in "$@"; do
    case "$arg" in
      --candidate) candidate=1 ;;
      -*) echo "Unknown reasoning probe option: $arg" >&2; return 1 ;;
      *)
        if [[ -z "$model" ]]; then model="$arg"
        elif [[ -z "$effort" ]]; then effort="${arg:l}"
        else echo "Usage: claude-litellm model reasoning probe <model> [effort] [--candidate]" >&2; return 1
        fi
        ;;
    esac
  done
  if [[ -z "$model" ]]; then
    echo "Usage: claude-litellm model reasoning probe <model> [effort] [--candidate]" >&2
    return 1
  fi

  model="$(ai_litellm_model_resolve "$model" 2>/dev/null)" || {
    echo "Unknown LiteLLM model_name or provider model: $model" >&2
    return 1
  }
  local allowed=""
  if (( candidate )); then
    [[ -n "$effort" ]] || effort=medium
    case "$effort" in
      low|medium|high|xhigh|max) ;;
      *) echo "Candidate Claude effort must be low, medium, high, xhigh, or max." >&2; return 1 ;;
    esac
    echo "Experimental candidate probe: a 2xx only proves that the request shape was accepted." >&2
    echo "It does not prove effort was forwarded or honored, nor that exploration changed; compare repeated low/high runs and inspect an outbound provider trace. Capability metadata is unchanged." >&2
  else
    allowed="$(ai_litellm_model_reasoning_allowed_efforts "$model")" || return $?
  fi
  if (( ! candidate )) && [[ -z "$effort" ]]; then
    # Pick a broadly supported, non-extreme level. Provider contracts differ
    # (for example Grok omits xhigh), so a global xhigh default creates false
    # probe failures before any request reaches the model.
    case " $allowed " in
      *" medium "*) effort=medium ;;
      *" high "*) effort=high ;;
      *" low "*) effort=low ;;
      *) effort="${allowed%% *}" ;;
    esac
  fi
  if (( ! candidate )); then
    case " $allowed " in
      *" $effort "*) ;;
      *)
        echo "Unsupported reasoning effort for probe: $effort (allowed: ${allowed// /, })" >&2
        return 1
        ;;
    esac
  fi
  if ! ai_litellm_health; then
    echo "LiteLLM proxy is not reachable at $(ai_litellm_base_url); reasoning probe will not auto-start it." >&2
    return 1
  fi

  local master_key backend payload tmp http_code observation_json
  master_key="$(ai_litellm_master_key 2>/dev/null)" || {
    echo "Missing LiteLLM master key." >&2
    return 1
  }
  backend="$(ai_litellm_model_backend "$model" 2>/dev/null || printf '-')"
  payload="$(jq -nc --arg model "$model" --arg effort "$effort" '{
    model: $model,
    messages: [{role: "user", content: "Think carefully, then reply with exactly OK."}],
    max_tokens: 2048,
    thinking: {type: "adaptive"},
    output_config: {effort: $effort}
  }')"
  tmp="$(mktemp "${TMPDIR:-/tmp}/ai-litellm-reasoning-probe.XXXXXX")" || return 1

  http_code="$(
    ai_litellm_curl_auth "$master_key" --max-time 90 -sS -o "$tmp" -w "%{http_code}" \
      -H "Content-Type: application/json" \
      -H "anthropic-version: 2023-06-01" \
      "$(ai_litellm_base_url)/v1/messages" \
      -d "$payload"
  )"

  observation_json="$(jq -nc \
    --arg model "$model" \
    --arg backend "$backend" \
    --arg effort "$effort" \
    --arg path "proxy:anthropic.messages:output_config.effort" \
    --arg http_code "$http_code" \
    --arg candidate "$candidate" \
    --slurpfile response "$tmp" '
      def reasoning_tokens:
        ($response[0].usage.output_tokens_details.reasoning_tokens //
         $response[0].usage.completion_tokens_details.reasoning_tokens // 0);
      def has_reasoning:
        ([$response[0].content[]? | select(.type == "thinking" or .type == "reasoning")] | length) > 0 or
        (($response[0].reasoning? // null) != null) or
        (($response[0].reasoning_content? // null) != null);
      def ok: ($http_code | test("^2"));
      {
        timestamp: (now | todateiso8601),
        model_name: $model,
        provider_model: $backend,
        effort: $effort,
        path: $path,
        http_code: $http_code,
        candidate: ($candidate == "1")
      }
      + if ok then
          {
            status: (if (reasoning_tokens > 0 or has_reasoning) then "accepted_with_reasoning" else "accepted_without_reasoning_evidence" end),
            reasoning_tokens: reasoning_tokens,
            has_reasoning: has_reasoning,
            response_id: ($response[0].id // null),
            interpretation: "request accepted; effort forwarding and behavioral impact remain unverified"
          }
        else
          {
            status: "error",
            reasoning_tokens: 0,
            has_reasoning: false,
            error: ($response[0].error.message // $response[0].message // ($response[0] | tostring))
          }
        end
    ')" || {
    rm -f "$tmp"
    echo "Failed to parse reasoning probe response." >&2
    return 1
  }
  rm -f "$tmp"

  ai_litellm_reasoning_observation_record "$observation_json" || return $?
  print -r -- "$observation_json" | jq '{model_name, provider_model, effort, candidate, path, status, reasoning_tokens, has_reasoning, http_code, interpretation, error}'

  local probe_status
  probe_status="$(print -r -- "$observation_json" | jq -r '.status')"
  [[ "$probe_status" != "error" ]]
}

ai_litellm_model_reasoning_probe() {
  ai_litellm_lifecycle_lock_acquire || return $?
  local rc=0
  {
    _ai_litellm_model_reasoning_probe_unlocked "$@" || rc=$?
  } always {
    ai_litellm_lifecycle_lock_release
  }
  return $rc
}

# Harness reasoning resolver preview. Each adapter translates its local model
# selection and effort semantics into a common shape.
ai_litellm_harness_reasoning_table() {
  local filter="$1"
  ai_litellm_ruby -rjson -ryaml -e '
require "set"

config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
harness_dir = ARGV[1]
filter = ARGV[2] || ""

registry = {}
Array(config["model_list"]).each do |entry|
  registry[entry["model_name"]] = entry if entry["model_name"]
end

def read_json(path)
  return {} unless path && File.file?(path)
  JSON.parse(File.read(path))
rescue
  {}
end

user_override = read_json(ARGV[3])

def provider_model(registry, model)
  registry.dig(model, "litellm_params", "model") || "-"
end

def supports_reasoning(registry, model)
  registry.dig(model, "model_info", "supports_reasoning") == true
end

def provider_default(registry, model)
  entry = registry[model]
  return "-" unless entry
  reasoning = entry.dig("litellm_params", "reasoning")
  reasoning_effort = entry.dig("litellm_params", "reasoning_effort")
  if reasoning.is_a?(Hash)
    effort = reasoning["effort"]
    return "effort=#{effort}" if effort
    return "reasoning"
  elsif !reasoning.nil?
    return reasoning.to_s
  elsif !reasoning_effort.nil?
    return "effort=#{reasoning_effort}"
  end
  entry.dig("model_info", "reasoning_default") || "-"
end

def adapter_default_control(adapter)
  case adapter
  when "claude-code"
    "intent"
  else
    "none"
  end
end

def adapter_default_effort(adapter, descriptor)
  case adapter
  when "claude-code"
    "auto"
  else
    "-"
  end
end

def effective(control, provider_support, effort)
  if control == "none"
    provider_support ? "provider-default" : "no-reasoning"
  elsif effort.to_s == "auto"
    provider_support ? "harness-auto" : "no-reasoning"
  elsif provider_support
    "harness-intent"
  else
    "intent-unsupported"
  end
end

def add_row(rows, harness, selection, resolved, descriptor, registry)
  adapter = descriptor["adapter"]
  reasoning = descriptor.dig("adapterConfig", "reasoning") || {}
  control = reasoning["control"] || adapter_default_control(adapter)
  effort = reasoning["effort"] || adapter_default_effort(adapter, descriptor)
  if adapter == "claude-code"
    settings_arg = read_json(descriptor.dig("paths", "settingsArgProxy"))
    effort = settings_arg["effortLevel"] || effort
  end
  provider_support = supports_reasoning(registry, resolved)
  rows << {
    harness: harness,
    adapter: adapter,
    selection: selection,
    resolved: resolved || "-",
    provider_model: provider_model(registry, resolved),
    provider_reasoning: provider_support ? "yes" : "no",
    provider_default: provider_default(registry, resolved),
    control: control,
    effort: effort,
    source: reasoning["source"] || "-",
    effective: effective(control, provider_support, effort),
    confidence: reasoning["confidence"] || "inferred"
  }
end

def descriptor_paths(harness_dir)
  Dir[File.join(harness_dir, "*.json")].reject { |p| File.basename(p) == "schema.json" }.sort
end

rows = []
descriptor_paths(harness_dir).each do |path|
  descriptor = read_json(path)
  harness = descriptor["name"] || File.basename(path, ".json")
  next if !filter.empty? && harness != filter
  adapter = descriptor["adapter"]
  if adapter == "claude-code"
    user_effort = user_override.dig("harness", "reasoningEffort")
    if user_effort
      descriptor["adapterConfig"] ||= {}
      descriptor["adapterConfig"]["reasoning"] ||= {}
      descriptor["adapterConfig"]["reasoning"]["effort"] = user_effort
      descriptor["adapterConfig"]["reasoning"]["confidence"] = "configured" unless user_effort == "auto"
    end
  end

  case adapter
  when "claude-code"
    settings = read_json(descriptor.dig("paths", "settings"))
    tiers = Array(descriptor.dig("models", "tiers"))
    aliases = settings["aliases"] || {}
    default = settings["default"] || "sonnet"
    default_resolved = tiers.include?(default) ? aliases[default] : default
    add_row(rows, harness, "default(#{default})", default_resolved, descriptor, registry)
    tiers.each do |tier|
      add_row(rows, harness, tier, aliases[tier], descriptor, registry)
    end
  else
    default = descriptor.dig("models", "default")
    add_row(rows, harness, "default(#{default})", default, descriptor, registry) if default
  end
end

printf("%-9s %-13s %-22s %-22s %-42s %-10s %-9s %-8s %-28s %-18s %-10s\n",
  "harness", "adapter", "selection", "resolved_model", "provider_model",
  "prov_reas", "control", "effort", "source", "effective", "confidence")
rows.each do |row|
  printf("%-9s %-13s %-22s %-22s %-42s %-10s %-9s %-8s %-28s %-18s %-10s\n",
    row[:harness], row[:adapter], row[:selection], row[:resolved],
    row[:provider_model], row[:provider_reasoning], row[:control],
    row[:effort].to_s, row[:source], row[:effective], row[:confidence])
end
' "$AI_LITELLM_CONFIG" "$AI_LITELLM_HARNESSES_DIR" "$filter" "$AI_LITELLM_USER_CLAUDE_SETTINGS"
}

ai_litellm_harness_reasoning_update() {
  local mode="$1"
  local harness="$2"
  local effort="${3:-}"
  if [[ -z "$mode" || -z "$harness" ]]; then
    echo "Usage: claude-litellm harness reasoning set <name> <effort>" >&2
    echo "       claude-litellm harness reasoning unset <name>" >&2
    return 1
  fi
  if [[ "$mode" == "set" && -z "$effort" ]]; then
    echo "Usage: claude-litellm harness reasoning set <name> <effort>" >&2
    return 1
  fi

  local descriptor
  descriptor="$(ai_litellm_harness_descriptor "$harness")" || {
    echo "Unknown harness: $harness" >&2
    return 1
  }

  if [[ "$harness" != "claude" ]]; then
    echo "Only the Claude harness has a durable reasoning overlay." >&2
    return 1
  fi
  if [[ "$mode" == "allowed" ]]; then
    printf '["auto","low","medium","high","xhigh","max"]\n'
    return 0
  fi
  local owns_lock=0 lock_path="$AI_LITELLM_USER_CONFIG_HOME/.mutation.lock"
  if [[ ! -d "$lock_path" || "$(<"$lock_path/pid" 2>/dev/null || true)" != "$$" ]]; then
    ai_litellm_user_mutation_lock_acquire || return 1
    owns_lock=1
  fi
  local backup existed=0 rc=0
  backup="$(mktemp "${TMPDIR:-/tmp}/claude-litellm-harness-reasoning.json.XXXXXX")" || {
    (( owns_lock )) && ai_litellm_user_mutation_lock_release
    return 1
  }
  if [[ -f "$AI_LITELLM_USER_CLAUDE_SETTINGS" ]]; then
    cp -p "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$backup"
    existed=1
  fi

  node -e '
const fs = require("fs");
const [descriptorFile, overrideFile, mode, rawEffort = ""] = process.argv.slice(1);
const descriptor = JSON.parse(fs.readFileSync(descriptorFile, "utf8"));
const adapter = descriptor.adapter;
const effort = String(rawEffort).toLowerCase();

const fail = (message) => {
  console.error(message);
  process.exit(1);
};
const assertAllowed = (allowed) => {
  if (!allowed.includes(effort)) {
    fail(`Unsupported reasoning effort for ${adapter}: ${effort} (allowed: ${allowed.join(", ")})`);
  }
};
const adapterReasoning = {
  "claude-code": {
    allowed: ["auto", "low", "medium", "high", "xhigh", "max"],
    unsetEffort: "auto"
  }
};

if (!adapterReasoning[adapter]) fail(`Unsupported harness adapter for reasoning mutation: ${adapter}`);
if (mode === "allowed") { process.stdout.write(JSON.stringify(adapterReasoning[adapter].allowed)); process.exit(0); }
let payload = {schemaVersion: 1, settings: {}};
if (fs.existsSync(overrideFile)) {
  const stat = fs.lstatSync(overrideFile);
  if (!stat.isFile() || stat.isSymbolicLink() || (stat.mode & 0o777) !== 0o600) {
    fail(`Unsafe Claude user override: ${overrideFile}`);
  }
  payload = JSON.parse(fs.readFileSync(overrideFile, "utf8"));
}
if (payload.schemaVersion !== 1) fail("unsupported Claude user override schemaVersion");
payload.harness ||= {};
if (mode === "set") {
  assertAllowed(adapterReasoning[adapter].allowed);
  payload.harness.reasoningEffort = effort;
} else if (mode === "unset") {
  payload.harness.reasoningEffort = adapterReasoning[adapter].unsetEffort;
} else {
  fail(`Unsupported reasoning update mode: ${mode}`);
}

const tmp = `${overrideFile}.tmp.${process.pid}`;
try {
  const fd = fs.openSync(tmp, "wx", 0o600);
  try {
    fs.writeFileSync(fd, JSON.stringify(payload, null, 2) + "\n");
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(tmp, overrideFile);
} catch (error) {
  try { fs.unlinkSync(tmp); } catch (_) {}
  throw error;
}
' "$descriptor" "$AI_LITELLM_USER_CLAUDE_SETTINGS" "$mode" "$effort" || rc=$?

  if (( rc == 0 )); then
    ai_litellm_render_user_config >/dev/null || rc=$?
  fi
  if (( rc != 0 )); then
    (( existed )) && cp -p "$backup" "$AI_LITELLM_USER_CLAUDE_SETTINGS" || rm -f "$AI_LITELLM_USER_CLAUDE_SETTINGS"
    ai_litellm_render_user_config >/dev/null 2>&1 || true
  fi
  rm -f "$backup"
  (( owns_lock )) && ai_litellm_user_mutation_lock_release
  (( rc == 0 )) || return $rc

  if [[ "$mode" == "set" ]]; then
    echo "Updated harness reasoning default: $harness -> $effort"
  elif [[ "$mode" == "unset" ]]; then
    echo "Reset harness reasoning default: $harness"
  fi
  [[ "$mode" == "allowed" ]] || echo "The durable user overlay will survive sync and reinstall."
}

ai_litellm_harness_reasoning_set() {
  ai_litellm_harness_reasoning_update set "$@"
}

ai_litellm_harness_reasoning_unset() {
  ai_litellm_harness_reasoning_update unset "$@"
}

ai_litellm_harness_reasoning_allowed_json() {
  ai_litellm_harness_reasoning_update allowed "${1:-}"
}

ai_litellm_context_matrix() {
  local filter="$1"
  ai_litellm_ruby -rjson -ryaml -e '
config_path, settings_path, harness_dir, home, base_url, api_base_url, filter, context_obs_seed, context_obs_file = ARGV
filter ||= ""

def read_json(path)
  return nil unless path && File.file?(path)
  JSON.parse(File.read(path))
rescue
  nil
end

def model_config_context(models_dir, model)
  path = File.join(models_dir.to_s, model.to_s, "config.json")
  payload = read_json(path)
  return nil unless payload
  payload.dig("text_config", "max_position_embeddings") ||
    payload["max_position_embeddings"] ||
    payload["max_sequence_length"] ||
    payload["max_model_len"]
end

def fmt(value)
  value.nil? || value.to_s.empty? ? "-" : value.to_s
end

def fmt_pair(ctx, out)
  return "-" if ctx.nil? && out.nil?
  "#{fmt(ctx)}/#{fmt(out)}"
end

def provider_model(entry)
  entry&.dig("litellm_params", "model") || "-"
end

def add_row(rows, attrs)
  rows << {
    surface: attrs[:surface],
    selection: attrs[:selection] || "-",
    auth_lane: attrs[:auth_lane] || "-",
    provider_model: attrs[:provider_model] || "-",
    budget_kind: attrs[:budget_kind] || "-",
    declared: fmt_pair(attrs[:declared_context], attrs[:declared_output]),
    configured: fmt_pair(attrs[:configured_context], attrs[:configured_output]),
    observed: fmt(attrs[:observed_context]),
    effective_input: fmt(attrs[:effective_input_budget]),
    enforcement: attrs[:enforcement_layer] || "-",
    confidence: attrs[:source_confidence] || "unknown"
  }
end

def include_row?(row, filter)
  return true if filter.nil? || filter.empty?
  [row[:surface], row[:selection], row[:provider_model], row[:budget_kind], row[:confidence]].any? do |value|
    value.to_s.include?(filter)
  end
end

def read_context_observations(*paths)
  observations = []
  paths.each do |path|
    next unless path && File.file?(path)
    payload = read_json(path) || {}
    Array(payload["observations"]).each do |observation|
      observations << observation.merge("_source_file" => path) if observation.is_a?(Hash)
    end
  end
  observations
end

def context_observation_for(observations, surface, selection, model, provider)
  candidates = observations.map do |obs|
    scope = (obs["scope"] || "surface").to_s
    if scope == "backend"
      next unless obs["provider_model"].to_s == provider.to_s || obs["model_name"].to_s == model.to_s
    else
      next unless obs["surface"].to_s == surface.to_s
      next unless obs["provider_model"].to_s == provider.to_s || obs["model_name"].to_s == model.to_s
      if obs["selection"]
        selections = Array(obs["selections"]) + [obs["selection"]]
        next unless selections.include?(selection)
      end
    end
    score = 0
    score += 8 if obs["surface"].to_s == surface.to_s
    score += 4 if obs["selection"].to_s == selection.to_s
    score += 3 if obs["model_name"].to_s == model.to_s
    score += 3 if obs["provider_model"].to_s == provider.to_s
    [score, obs]
  end.compact
  candidates.max_by { |score, obs| [score, obs["timestamp"].to_s] }&.last
end

def observation_input_tokens(observation)
  positive_int(
    observation && (
      observation["observed_input_tokens"] ||
      observation["accepted_input_tokens"] ||
      observation["input_tokens"]
    )
  )
end

def format_context_observation(observation)
  tokens = observation_input_tokens(observation)
  return nil unless tokens
  status = observation["status"].to_s
  if %w[lower_bound accepted observed].include?(status)
    ">=#{tokens}"
  else
    tokens
  end
end

def context_observation_confidence(observation)
  return nil unless observation
  status = observation["status"].to_s
  case status
  when "upper_bound", "observed_max"
    "observed-max"
  when "error"
    "observed-error"
  else
    "observed-lower-bound"
  end
end

config = (YAML.load_file(config_path, aliases: true) rescue YAML.load_file(config_path))
settings = read_json(settings_path) || {}
context_observations = read_context_observations(context_obs_seed, context_obs_file)
registry = {}
Array(config["model_list"]).each do |entry|
  registry[entry["model_name"]] = entry if entry["model_name"]
end
pre_call = config.dig("router_settings", "enable_pre_call_checks") == true
router_enforcement = pre_call ? "LiteLLM pre-call" : "provider-only"

rows = []

def positive_int(value)
  n = Integer(value)
  n.positive? ? n : nil
rescue
  nil
end

def output_budget(descriptor, selection, model, ctx, out)
  policy = descriptor&.dig("adapterConfig", "outputReservation") || {}
  return nil if policy.empty?

  pick = nil
  [
    ["adapterConfig.outputReservation.perSelection.#{selection}", policy.dig("perSelection", selection)],
    ["adapterConfig.outputReservation.perTier.#{selection}", policy.dig("perTier", selection)],
    ["adapterConfig.outputReservation.perModel.#{model}", policy.dig("perModel", model)],
    ["adapterConfig.outputReservation.default", policy["default"]]
  ].each do |source, value|
    n = positive_int(value)
    if n
      pick = [source, n]
      break
    end
  end

  capability = positive_int(out)
  return nil unless pick || capability

  source, reservation = pick || ["capability-clamped-default", [capability, 32000].compact.min]
  configured_headroom = positive_int(policy["tokenizerHeadroom"]) || 0
  configured_minimum_input = positive_int(policy["minimumInput"]) || 32768
  context = positive_int(ctx)
  headroom = configured_headroom
  minimum_input = configured_minimum_input

  if capability && reservation > capability
    reservation = capability
    source += "+capabilityClamp"
  end
  if context
    headroom = [headroom, (context * 0.1).floor].min
    minimum_input = [minimum_input, [1, (context * 0.5).floor].max].min
    max_reservation_for_minimum_input = context - headroom - minimum_input
    if max_reservation_for_minimum_input < 1
      reservation = 1
      headroom = [0, context - minimum_input - reservation].max
      source += "+tinyWindowClamp"
    elsif reservation > max_reservation_for_minimum_input
      reservation = max_reservation_for_minimum_input
      source += "+minimumInputClamp"
    end
  end

  effective_input = context ? [0, context - reservation - headroom].max : nil
  {
    reservation: reservation,
    tokenizer_headroom: headroom,
    minimum_input: minimum_input,
    effective_input: effective_input,
    source: source
  }
end

def model_limit_confidence(mi)
  input = (mi["x_input_confidence"] || "local-config").to_s
  output = (mi["x_output_confidence"] || "local-config").to_s
  input == output ? input : "input:#{input}/output:#{output}"
end

def add_litellm_row(rows, registry, observations, model, surface, selection, budget_kind, auth_lane, enforcement, confidence, descriptor = nil)
  entry = registry[model]
  mi = entry && entry["model_info"] || {}
  ctx = mi["max_input_tokens"]
  out = mi["max_output_tokens"]
  provider = provider_model(entry)
  budget = output_budget(descriptor, selection, model, ctx, out)
  observation = context_observation_for(observations, surface, selection, model, provider)
  observed_context = format_context_observation(observation)
  observed_confidence = context_observation_confidence(observation)
  model_confidence = model_limit_confidence(mi)
  combined_confidence = [model_confidence, observed_confidence, confidence].reject { |v| v.nil? || v.to_s.empty? }.join("+")
  effective_input_budget = budget ? budget[:effective_input] : ctx
  if observation && %w[upper_bound observed_max].include?(observation["status"].to_s)
    tokens = observation_input_tokens(observation)
    effective_input_budget = [effective_input_budget, tokens].compact.map(&:to_i).min if tokens
  end
  add_row(rows,
    surface: surface,
    selection: selection,
    auth_lane: auth_lane,
    provider_model: provider,
    budget_kind: budget_kind,
    declared_context: ctx,
    declared_output: out,
    configured_context: ctx,
    configured_output: budget ? budget[:reservation] : out,
    observed_context: observed_context,
    effective_input_budget: effective_input_budget,
    enforcement_layer: enforcement,
    source_confidence: budget ? "#{combined_confidence}+reservation" : combined_confidence)
end

def descriptor_context(descriptor, harness, router_enforcement)
  context = descriptor.dig("adapterConfig", "context") || {}
  return nil if context["enabled"] == false
  {
    surface: context["surface"] || "#{harness}-litellm",
    budget_kind: context["budgetKind"] || "harness+router",
    auth_lane: context["authLane"] || "litellm-master-key",
    enforcement: context["enforcement"] || router_enforcement,
    confidence: context["confidence"] || "local-config"
  }
end

def descriptor_selections(descriptor, registry)
  models = descriptor["models"] || {}
  settings = read_json(descriptor.dig("paths", "settings")) || {}
  aliases = settings["aliases"] || {}
  rows = []

  if models["mode"] == "tier-aliases"
    tiers = Array(models["tiers"])
    default = settings["default"] || tiers.first
    rows << ["default(#{default})", aliases[default] || default] if default
    tiers.each do |tier|
      rows << [tier, aliases[tier]] if aliases[tier]
    end
  else
    default = models["default"]
    rows << ["default(#{default})", default] if default
    small = models["small"]
    rows << ["small(#{small})", small] if small
    Array(aliases.values).uniq.each do |model|
      rows << [model, model] if model
    end
    Array(models["catalogEntries"]).each do |entry|
      model = entry["slug"]
      rows << [model, model] if model
    end
    # api_key: none marks local-runtime routes (name-independent).
    registry.each { |model, entry| rows << [model, model] if entry.dig("litellm_params", "api_key").to_s == "none" }
  end

  Array(descriptor.dig("adapterConfig", "context", "selections")).each do |item|
    if item.is_a?(Hash)
      model = item["model"] || item["resolvedModel"] || item["slug"]
      selection = item["selection"] || model
      rows << [selection, model] if model
    elsif item.is_a?(String)
      rows << [item, item]
    end
  end

  seen = {}
  rows.each_with_object([]) do |(selection, model), acc|
    next unless model && registry.key?(model)
    key = [selection, model]
    next if seen[key]
    seen[key] = true
    acc << [selection, model]
  end
end

Dir[File.join(harness_dir, "*.json")].sort.each do |path|
  next if File.basename(path) == "schema.json"
  descriptor = read_json(path) || {}
  harness = descriptor["name"] || File.basename(path, ".json")
  context = descriptor_context(descriptor, harness, router_enforcement)
  next unless context
  descriptor_selections(descriptor, registry).each do |selection, model|
    add_litellm_row(rows, registry, context_observations, model, context[:surface], selection,
      context[:budget_kind], context[:auth_lane], context[:enforcement], context[:confidence], descriptor)
  end
end

native_claude = read_json(File.join(home, ".claude", "settings.json")) || {}
native_model = native_claude["model"] || "unknown"
add_row(rows,
  surface: "claude-code-native",
  selection: "default(#{native_model})",
  auth_lane: "claude.ai",
  provider_model: native_model,
  budget_kind: "harness-session",
  declared_context: nil,
  declared_output: nil,
  configured_context: nil,
  observed_context: nil,
  effective_input_budget: nil,
  enforcement_layer: "Claude Code",
  source_confidence: "native-unprobed")

Array(settings["runtimes"] || {}).each do |name, rt|
  Array(rt["expectedModels"]).each do |model|
    entry = registry[model]
    mi = entry && entry["model_info"] || {}
    runtime_ctx = model_config_context(rt["modelsDir"], model)
    add_row(rows,
      surface: "#{name}-runtime",
      selection: model,
      auth_lane: "local",
      provider_model: provider_model(entry),
      budget_kind: "runtime-capability",
      declared_context: runtime_ctx,
      declared_output: nil,
      configured_context: mi["max_input_tokens"],
      configured_output: mi["max_output_tokens"],
      observed_context: nil,
      # Effective input is the FLOOR across every layer: a runtime that physically
      # caps below the LiteLLM policy is the real ceiling, not the policy number.
      effective_input_budget: [runtime_ctx, mi["max_input_tokens"]].compact.map(&:to_i).min,
      enforcement_layer: "runtime+LiteLLM",
      source_confidence: runtime_ctx ? "model-file+#{model_limit_confidence(mi)}" : model_limit_confidence(mi))
  end
end

rows = rows.select { |row| include_row?(row, filter) }
if ENV["AI_LITELLM_MATRIX_JSON"] == "1"
  json_rows = rows.map do |row|
    {
      "surface"        => row[:surface],
      "model"          => row[:selection],
      "declared"       => row[:declared],
      "configured"     => row[:configured],
      "effectiveInput" => row[:effective_input],
      "enforcement"    => row[:enforcement]
    }
  end
  print JSON.generate(json_rows)
else
  printf("%-20s %-22s %-18s %-42s %-24s %-17s %-17s %-12s %-15s %-20s %-18s\n",
    "surface", "selection", "auth", "provider_model", "budget_kind",
    "declared(ctx/out)", "configured(ctx/out)", "observed", "effective_input",
    "enforcement", "confidence")
  rows.each do |row|
    printf("%-20s %-22s %-18s %-42s %-24s %-17s %-17s %-12s %-15s %-20s %-18s\n",
      row[:surface], row[:selection], row[:auth_lane], row[:provider_model],
      row[:budget_kind], row[:declared], row[:configured], row[:observed],
      row[:effective_input], row[:enforcement], row[:confidence])
  end
end
' "$AI_LITELLM_CONFIG" "$AI_LITELLM_SETTINGS" "$AI_LITELLM_HARNESSES_DIR" "$HOME" "$(ai_litellm_base_url)" "$(ai_litellm_api_base_url)" "$filter" "$AI_LITELLM_CONTEXT_OBS_SEED" "$AI_LITELLM_CONTEXT_OBS_FILE"
}

ai_litellm_context_matrix_json() {
  AI_LITELLM_MATRIX_JSON=1 ai_litellm_context_matrix "$@" 2>/dev/null || printf '[]'
}

ai_litellm_context_litellm_surfaces() {
  [[ -d "$AI_LITELLM_HARNESSES_DIR" ]] || return 0
  node -e '
const fs = require("fs");
const path = require("path");
const dir = process.argv[1];
for (const file of fs.readdirSync(dir).filter((name) => name.endsWith(".json") && name !== "schema.json").sort()) {
  const descriptor = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
  const context = descriptor.adapterConfig?.context || {};
  if (context.enabled === false) continue;
  const harness = descriptor.name || path.basename(file, ".json");
  console.log(context.surface || `${harness}-litellm`);
}
' "$AI_LITELLM_HARNESSES_DIR"
}

ai_litellm_context_runtime_surfaces() {
  local runtime
  for runtime in "${(@f)$(ai_litellm_runtime_names 2>/dev/null)}"; do
    [[ -n "$runtime" ]] && printf '%s-runtime\n' "$runtime"
  done
}

ai_litellm_context_surfaces() {
  ai_litellm_context_litellm_surfaces
  printf '%s\n' claude-code-native
  ai_litellm_context_runtime_surfaces
}

ai_litellm_context_surface_default_model() {
  local surface="$1"
  [[ -d "$AI_LITELLM_HARNESSES_DIR" ]] || return 1
  node -e '
const fs = require("fs");
const path = require("path");
const [dir, targetSurface] = process.argv.slice(1);
const readJson = (file) => {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); }
  catch { return {}; }
};
for (const file of fs.readdirSync(dir).filter((name) => name.endsWith(".json") && name !== "schema.json").sort()) {
  const descriptor = readJson(path.join(dir, file));
  const context = descriptor.adapterConfig?.context || {};
  if (context.enabled === false) continue;
  const harness = descriptor.name || path.basename(file, ".json");
  const surface = context.surface || `${harness}-litellm`;
  if (surface !== targetSurface) continue;
  const models = descriptor.models || {};
  let model = "";
  if (models.mode === "tier-aliases") {
    const settings = readJson(descriptor.paths?.settings || "");
    const tier = settings.default || (models.tiers || [])[0] || "";
    model = (settings.aliases || {})[tier] || tier;
  } else {
    model = models.default || models.small || "";
  }
  if (model) {
    console.log(model);
    process.exit(0);
  }
}
process.exit(1);
' "$AI_LITELLM_HARNESSES_DIR" "$surface"
}

ai_litellm_context_probe_litellm_surface() {
  local surface="$1"
  echo "Surface: $surface"
  ai_litellm_context_matrix "$surface"
  echo
  if ai_litellm_health; then
    echo "Running proxy metadata:"
    local default_model
    default_model="$(ai_litellm_context_surface_default_model "$surface" 2>/dev/null || true)"
    if [[ -n "$default_model" ]]; then
      ai_litellm_route_info "$default_model"
    else
      ai_litellm_route_info
    fi
  else
    echo "Running proxy metadata: unavailable (proxy not reachable; not auto-starting for read-only probe)"
  fi
}

ai_litellm_context_probe_runtime_surface() {
  local surface="$1"
  local runtime="${surface%-runtime}"
  echo "Surface: $surface"
  ai_litellm_context_matrix "$surface"
  echo
  ai_litellm_runtime_status "$runtime"
  echo
  local api_base
  api_base="$(ai_litellm_runtime_field "$runtime" apiBase 2>/dev/null || true)"
  echo "Runtime /models:"
  [[ -n "$api_base" ]] && curl --max-time 3 -fsS "$api_base/models" 2>/dev/null \
    | jq '(.data // .models // [])[]? | {id:(.id // .model // .name), max_model_len, max_context_window, max_tokens}' \
    || echo "  not reachable"
}

ai_litellm_context_observation_record() {
  local observation_json="$1"
  local safe_dir
  for safe_dir in "$AI_LITELLM_STATE_HOME" "$AI_LITELLM_PROXY_HOME"; do
    if [[ -e "$safe_dir" || -L "$safe_dir" ]]; then
      [[ -d "$safe_dir" && ! -L "$safe_dir" ]] || {
        echo "Refusing unsafe context evidence directory: $safe_dir" >&2
        return 1
      }
    fi
  done
  mkdir -p "$AI_LITELLM_PROXY_HOME"
  chmod 700 "$AI_LITELLM_STATE_HOME" "$AI_LITELLM_PROXY_HOME" 2>/dev/null || true
  if [[ -e "$AI_LITELLM_CONTEXT_OBS_FILE" || -L "$AI_LITELLM_CONTEXT_OBS_FILE" ]]; then
    [[ -f "$AI_LITELLM_CONTEXT_OBS_FILE" && ! -L "$AI_LITELLM_CONTEXT_OBS_FILE" && \
       "$(stat -f %Lp "$AI_LITELLM_CONTEXT_OBS_FILE" 2>/dev/null)" == "600" ]] || {
      echo "Refusing unsafe context evidence file: $AI_LITELLM_CONTEXT_OBS_FILE" >&2
      return 1
    }
  fi
  node -e '
const fs = require("fs");
const [file, raw] = process.argv.slice(1);
const observation = JSON.parse(raw);
let state = {schemaVersion: 1, observations: []};
try {
  state = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
if (!state || typeof state !== "object" || Array.isArray(state)) state = {schemaVersion: 1, observations: []};
if (!Array.isArray(state.observations)) state.observations = [];
if (!observation.id) {
  const parts = [
    observation.timestamp || new Date().toISOString(),
    observation.surface || "any",
    observation.selection || "any",
    observation.model_name || "unknown",
    observation.provider_model || "unknown"
  ].map((part) => String(part).replace(/[^A-Za-z0-9_.-]+/g, "-"));
  observation.id = parts.join(":");
}
state.schemaVersion = 1;
state.observations = state.observations.filter((item) => item && item.id !== observation.id);
state.observations.push(observation);
state.observations.sort((a, b) => String(a.id).localeCompare(String(b.id)));
const tmp = `${file}.tmp.${process.pid}`;
try {
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2) + "\n", {mode: 0o600, flag: "wx"});
  fs.renameSync(tmp, file);
} catch (error) {
  try { fs.unlinkSync(tmp); } catch (_) {}
  throw error;
}
' "$AI_LITELLM_CONTEXT_OBS_FILE" "$observation_json"
}

_ai_litellm_context_probe_record_unlocked() {
  local surface="${1:-}" selection="${2:-}" model="${3:-}" tokens="${4:-}"
  shift $(( $# < 4 ? $# : 4 ))
  if [[ -z "$surface" || -z "$selection" || -z "$model" || -z "$tokens" ]]; then
    echo "Usage: claude-litellm context probe record <surface> <selection> <model> <observed_input_tokens> [--provider-model model] [--status lower_bound|upper_bound|observed] [--cost-usd n] [--notes text]" >&2
    return 1
  fi

  local provider_model obs_status="lower_bound" cost_usd="" notes=""
  provider_model="$(ai_litellm_model_backend "$model" 2>/dev/null || true)"
  while (( $# )); do
    case "$1" in
      --provider-model) (( $# >= 2 )) || { echo "--provider-model requires a value" >&2; return 1; }; provider_model="$2"; shift 2 ;;
      --status) (( $# >= 2 )) || { echo "--status requires a value" >&2; return 1; }; obs_status="$2"; shift 2 ;;
      --cost-usd) (( $# >= 2 )) || { echo "--cost-usd requires a value" >&2; return 1; }; cost_usd="$2"; shift 2 ;;
      --notes) (( $# >= 2 )) || { echo "--notes requires a value" >&2; return 1; }; notes="$2"; shift 2 ;;
      *) echo "Unknown context observation option: $1" >&2; return 1 ;;
    esac
  done

  [[ "$tokens" == <-> ]] && (( tokens > 0 )) || {
    echo "observed_input_tokens must be a positive integer" >&2
    return 1
  }
  case "$obs_status" in
    lower_bound|upper_bound|observed) ;;
    *) echo "status must be lower_bound, upper_bound, or observed" >&2; return 1 ;;
  esac

  local observation_json
  observation_json="$(jq -nc \
    --arg surface "$surface" \
    --arg selection "$selection" \
    --arg model "$model" \
    --arg provider_model "$provider_model" \
    --arg status "$obs_status" \
    --argjson tokens "$tokens" \
    --arg cost "$cost_usd" \
    --arg notes "$notes" '
      {
        timestamp: (now | todateiso8601),
        scope: "surface",
        surface: $surface,
        selection: $selection,
        model_name: $model,
        provider_model: (if $provider_model == "" then null else $provider_model end),
        status: $status,
        observed_input_tokens: $tokens
      }
      + (if $cost == "" then {} else {cost_usd: ($cost | tonumber)} end)
      + (if $notes == "" then {} else {evidence: $notes} end)
    ')" || return $?

  ai_litellm_context_observation_record "$observation_json" || return $?
  print -r -- "$observation_json" | jq '{surface, selection, model_name, provider_model, status, observed_input_tokens, cost_usd, evidence}'
}

ai_litellm_context_probe_record() {
  ai_litellm_lifecycle_lock_acquire || return $?
  local rc=0
  {
    _ai_litellm_context_probe_record_unlocked "$@" || rc=$?
  } always {
    ai_litellm_lifecycle_lock_release
  }
  return $rc
}

ai_litellm_context_observations() {
  local filter="${1:-}"
  ai_litellm_ruby -rjson -e '
seed_path, state_path, filter = ARGV
filter ||= ""

def read_json(path)
  return {} unless path && File.file?(path)
  JSON.parse(File.read(path))
rescue
  {}
end

rows = []
[[seed_path, "seed"], [state_path, "state"]].each do |path, source|
  Array(read_json(path)["observations"]).each do |obs|
    next unless obs.is_a?(Hash)
    row = {
      source: source,
      surface: obs["surface"] || (obs["scope"] == "backend" ? "*" : "-"),
      selection: obs["selection"] || "-",
      model: obs["model_name"] || "-",
      provider: obs["provider_model"] || "-",
      status: obs["status"] || "-",
      observed: obs["observed_input_tokens"] || obs["accepted_input_tokens"] || obs["input_tokens"] || "-",
      cost: obs["cost_usd"] || "-",
      id: obs["id"] || "-"
    }
    next unless filter.empty? || row.values.any? { |v| v.to_s.include?(filter) }
    rows << row
  end
end

printf("%-6s %-18s %-18s %-22s %-42s %-18s %-10s %-8s %s\n",
  "source", "surface", "selection", "model", "provider_model", "status", "observed", "cost", "id")
rows.each do |row|
  printf("%-6s %-18s %-18s %-22s %-42s %-18s %-10s %-8s %s\n",
    row[:source], row[:surface], row[:selection], row[:model], row[:provider],
    row[:status], row[:observed], row[:cost], row[:id])
end
' "$AI_LITELLM_CONTEXT_OBS_SEED" "$AI_LITELLM_CONTEXT_OBS_FILE" "$filter"
}

ai_litellm_context_observations_ok() {
  node -e '
const fs = require("fs");
const files = process.argv.slice(1);
for (const file of files) {
  if (!file || !fs.existsSync(file)) continue;
  const payload = JSON.parse(fs.readFileSync(file, "utf8"));
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    throw new Error(`${file}: root must be an object`);
  }
  if (!Array.isArray(payload.observations)) {
    throw new Error(`${file}: observations must be an array`);
  }
  for (const [index, obs] of payload.observations.entries()) {
    if (!obs || typeof obs !== "object" || Array.isArray(obs)) {
      throw new Error(`${file}: observation ${index} must be an object`);
    }
    const tokens = Number(obs.observed_input_tokens ?? obs.accepted_input_tokens ?? obs.input_tokens ?? 0);
    if (!Number.isFinite(tokens) || tokens <= 0) {
      throw new Error(`${file}: observation ${index} must have positive observed input tokens`);
    }
  }
}
' "$AI_LITELLM_CONTEXT_OBS_SEED" "$AI_LITELLM_CONTEXT_OBS_FILE"
}

ai_litellm_context_probe() {
  local surface="$1"
  if [[ -z "$surface" ]]; then
    echo "Usage: claude-litellm context probe <surface|all>|record <surface> <selection> <model> <observed_input_tokens>" >&2
    echo "Surfaces: $(ai_litellm_context_surfaces | paste -sd ' ' -)" >&2
    return 1
  fi

  case "$surface" in
    record)
      shift
      ai_litellm_context_probe_record "$@"
      ;;
    all)
      local item failed=0
      for item in "${(@f)$(ai_litellm_context_surfaces)}"; do
        ai_litellm_context_probe "$item" || failed=1
        echo
      done
      return $failed
      ;;
    claude-litellm)
      ai_litellm_context_probe_litellm_surface "$surface"
      ;;
    claude-code-native)
      echo "Surface: claude-code-native"
      [[ -f "$HOME/.claude/settings.json" ]] && jq '{model, effortLevel}' "$HOME/.claude/settings.json" || echo "  missing $HOME/.claude/settings.json"
      echo "Observed session window: unknown (Claude Code native is not launched by this probe)"
      ;;
    *)
      if ai_litellm_context_litellm_surfaces | grep -Fx -- "$surface" >/dev/null; then
        ai_litellm_context_probe_litellm_surface "$surface"
      elif [[ "$surface" == *-runtime ]] && ai_litellm_runtime_names 2>/dev/null | grep -Fx -- "${surface%-runtime}" >/dev/null; then
        ai_litellm_context_probe_runtime_surface "$surface"
      else
        echo "Unknown context surface: $surface" >&2
        return 1
      fi
      ;;
  esac
}

ai_litellm_context_doctor_check() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok   $label"
    return 0
  fi
  echo "fail $label"
  return 1
}

ai_litellm_context_doctor_warn() {
  echo "warn $1"
}

ai_litellm_context_pre_call_enabled() {
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
exit(config.dig("router_settings", "enable_pre_call_checks") == true ? 0 : 1)
' "$AI_LITELLM_CONFIG"
}

ai_litellm_context_gateway_clamp_policy_ok() {
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
policy = config["x-gateway-output-clamp"] || {}
errors = []
if policy["enabled"] == false
  errors << "x-gateway-output-clamp.enabled must stay true for production C4"
end
%w[default tokenizer_headroom minimum_input].each do |key|
  value = policy[key]
  errors << "x-gateway-output-clamp.#{key} must be a positive integer" unless value.is_a?(Integer) && value.positive?
end
per_model = policy["perModel"] || policy["per_model"] || {}
unless per_model.is_a?(Hash)
  errors << "x-gateway-output-clamp.perModel must be an object when present"
else
  per_model.each do |model, value|
    errors << "x-gateway-output-clamp.perModel.#{model} must be a positive integer" unless value.is_a?(Integer) && value.positive?
  end
end
if errors.any?
  warn errors.join("\n")
  exit 1
end
' "$AI_LITELLM_CONFIG"
}

# Drift guard for the output-reservation policy. The triple {default,
# tokenizerHeadroom, minimumInput} is intentionally replicated across each
# harness descriptor (adapterConfig.outputReservation, camelCase) and the
# provider-facing gateway clamp (x-gateway-output-clamp, snake_case): they are
# distinct enforcement layers in different runtimes (zsh/node vs. python-in-
# litellm) that must nonetheless share one numeric policy. Rather than physically
# unify them, this asserts every copy agrees so the duplication can never
# silently drift. Per-harness divergence is deliberately disallowed.
ai_litellm_context_output_reservation_aligned() {
  ai_litellm_ruby -rjson -ryaml -e '
harness_dir, config = ARGV
errors = []
canon = nil
canon_src = nil
record = lambda do |src, triple|
  if canon.nil?
    canon = triple
    canon_src = src
  elsif triple != canon
    errors << "#{src} #{triple.inspect} != #{canon_src} #{canon.inspect}"
  end
end

Dir.glob(File.join(harness_dir, "*.json")).sort.each do |path|
  name = File.basename(path, ".json")
  next if name == "schema"
  desc = (JSON.parse(File.read(path)) rescue nil) or next
  res = desc.dig("adapterConfig", "outputReservation") or next
  record.call("#{name}.json", [res["default"], res["tokenizerHeadroom"], res["minimumInput"]])
end

cfg = (YAML.load_file(config, aliases: true) rescue (YAML.load_file(config) rescue {}))
gw = cfg["x-gateway-output-clamp"]
record.call("x-gateway-output-clamp", [gw["default"], gw["tokenizer_headroom"], gw["minimum_input"]]) if gw.is_a?(Hash)

if canon.nil?
  warn "no output-reservation policy found in any descriptor or gateway"
  exit 1
end
unless errors.empty?
  warn "output reservation policy drift detected (every copy must match):"
  errors.each { |e| warn "  #{e}" }
  exit 1
end
' "$AI_LITELLM_HARNESSES_DIR" "$AI_LITELLM_CONFIG"
}

ai_litellm_context_gateway_cost_guardrail_policy_ok() {
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
policy = config["x-gateway-cost-guardrail"] || {}
errors = []
if policy["enabled"] == false
  errors << "x-gateway-cost-guardrail.enabled must stay true unless the limitation is explicitly documented"
end
%w[max_estimated_input_tokens max_estimated_total_tokens chars_per_token].each do |key|
  value = policy[key]
  errors << "x-gateway-cost-guardrail.#{key} must be a positive integer" unless value.is_a?(Integer) && value.positive?
end
input = policy["max_estimated_input_tokens"].to_i
total = policy["max_estimated_total_tokens"].to_i
if input.positive? && total.positive? && total < input
  errors << "x-gateway-cost-guardrail.max_estimated_total_tokens must be >= max_estimated_input_tokens"
end
if errors.any?
  warn errors.join("\n")
  exit 1
end
' "$AI_LITELLM_CONFIG"
}

ai_litellm_context_gateway_clamp_configured() {
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
settings = config["litellm_settings"] || {}
callbacks = Array(settings["callbacks"])
has_hook = callbacks.include?("ai_litellm_callbacks.output_clamp.proxy_handler_instance")
enabled = (config.dig("x-gateway-output-clamp", "enabled") != false)
exit(has_hook && enabled ? 0 : 1)
' "$AI_LITELLM_CONFIG"
}

ai_litellm_context_gateway_cost_guardrail_configured() {
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
settings = config["litellm_settings"] || {}
callbacks = Array(settings["callbacks"])
has_hook = callbacks.include?("ai_litellm_callbacks.output_clamp.proxy_handler_instance")
enabled = (config.dig("x-gateway-cost-guardrail", "enabled") != false)
exit(has_hook && enabled ? 0 : 1)
' "$AI_LITELLM_CONFIG"
}

ai_litellm_model_info_anchor_refs_ok() {
  ai_litellm_ruby -e '
text = File.read(ARGV[0])
# Discovered local routes are generated with inline model_info derived from
# runtimes.<rt> defaults/overrides; the anchor policy applies to
# hand-maintained entries only.
text = text.gsub(/^# BEGIN claude-litellm discovered local routes\n.*?^# END claude-litellm discovered local routes\n/m, "")
# User overlay entries are generated from validated JSON and intentionally use
# inline model_info so they remain self-contained across package upgrades.
text = text.gsub(/^# BEGIN claude-litellm user models\n.*?^# END claude-litellm user models\n/m, "")
entries = text.split(/\n(?=  - model_name:\s*)/)
errors = []
entries.each do |entry|
  next unless entry =~ /^\s+- model_name:\s*(.+?)\s*$/
  name = Regexp.last_match(1)
  unless entry =~ /^\s+model_info:\s*\*[A-Za-z0-9_]+\s*$/
    errors << "#{name}: model_info must reference an x-limits YAML anchor"
  end
end
if errors.any?
  warn errors.join("\n")
  exit 1
end
' "$AI_LITELLM_CONFIG"
}

ai_litellm_context_harness_reservations_ok() {
  [[ -d "$AI_LITELLM_HARNESSES_DIR" ]] || return 0
  ai_litellm_ruby -rjson -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
harness_dir = ARGV[1]
registry = {}
Array(config["model_list"]).each { |e| registry[e["model_name"]] = e if e["model_name"] }

def read_json(path)
  JSON.parse(File.read(path))
rescue
  {}
end

def positive_int(value)
  n = Integer(value)
  n.positive? ? n : nil
rescue
  nil
end

def selections(descriptor, registry)
  models = descriptor["models"] || {}
  settings = read_json(descriptor.dig("paths", "settings"))
  aliases = settings["aliases"] || {}
  out = []
  if models["mode"] == "tier-aliases"
    tiers = Array(models["tiers"])
    default = settings["default"] || tiers.first
    out << [default, aliases[default] || default] if default
    tiers.each { |tier| out << [tier, aliases[tier]] if aliases[tier] }
  else
    out << ["default", models["default"]] if models["default"]
    out << ["small", models["small"]] if models["small"]
    Array(aliases.values).uniq.each { |model| out << [model, model] if model }
    Array(models["catalogEntries"]).each do |entry|
      model = entry["slug"]
      out << [model, model] if model
    end
    # api_key: none marks local-runtime routes (name-independent).
    registry.each { |model, entry| out << [model, model] if entry.dig("litellm_params", "api_key").to_s == "none" }
  end
  out.uniq.select { |_selection, model| model && registry.key?(model) }
end

def output_budget(policy, selection, model, ctx, out)
  pick = nil
  [
    ["perSelection.#{selection}", policy.dig("perSelection", selection)],
    ["perTier.#{selection}", policy.dig("perTier", selection)],
    ["perModel.#{model}", policy.dig("perModel", model)],
    ["default", policy["default"]]
  ].each do |source, value|
    n = positive_int(value)
    if n
      pick = [source, n]
      break
    end
  end
  capability = positive_int(out)
  return nil unless pick || capability
  source, reservation = pick || ["capability-clamped-default", [capability, 32000].compact.min]
  context = positive_int(ctx)
  headroom = positive_int(policy["tokenizerHeadroom"]) || 0
  minimum_input = positive_int(policy["minimumInput"]) || 32768
  reservation = capability if capability && reservation > capability
  if context
    headroom = [headroom, (context * 0.1).floor].min
    minimum_input = [minimum_input, [1, (context * 0.5).floor].max].min
    max_reservation = context - headroom - minimum_input
    if max_reservation < 1
      reservation = 1
      headroom = [0, context - minimum_input - reservation].max
    elsif reservation > max_reservation
      reservation = max_reservation
    end
  end
  effective = context ? [0, context - reservation - headroom].max : nil
  {reservation: reservation, effective: effective, minimum: minimum_input, context: context, headroom: headroom, capability: capability}
end

errors = []
Dir[File.join(harness_dir, "*.json")].sort.each do |path|
  next if File.basename(path) == "schema.json"
  descriptor = read_json(path)
  policy = descriptor.dig("adapterConfig", "outputReservation") || {}
  next if policy.empty?
  harness = descriptor["name"] || File.basename(path, ".json")
  selections(descriptor, registry).each do |selection, model|
    mi = registry.dig(model, "model_info") || {}
    budget = output_budget(policy, selection, model, mi["max_input_tokens"], mi["max_output_tokens"])
    if budget.nil? || budget[:reservation].to_i <= 0
      errors << "#{harness}/#{selection}->#{model}: reservation missing or non-positive"
      next
    end
    if budget[:effective].to_i < budget[:minimum].to_i
      errors << "#{harness}/#{selection}->#{model}: effective_input=#{budget[:effective]} minimum=#{budget[:minimum]} context=#{budget[:context]} reservation=#{budget[:reservation]} headroom=#{budget[:headroom]} capability=#{budget[:capability]}"
    end
  end
end

if errors.any?
  errors.each { |e| warn e }
  exit 1
end
' "$AI_LITELLM_CONFIG" "$AI_LITELLM_HARNESSES_DIR"
}

ai_litellm_context_warn_omlx_policy_cap() {
  ai_litellm_ruby -rjson -ryaml -e '
settings_path, config_path = ARGV
settings = JSON.parse(File.read(settings_path)) rescue {}
config = (YAML.load_file(config_path, aliases: true) rescue YAML.load_file(config_path))
registry = {}
Array(config["model_list"]).each { |e| registry[e["model_name"]] = e if e["model_name"] }
Array(settings["runtimes"] || {}).each do |name, rt|
  next unless name == "omlx"
  Array(rt["expectedModels"]).each do |model|
    path = File.join(rt["modelsDir"].to_s, model, "config.json")
    next unless File.file?(path)
    payload = JSON.parse(File.read(path)) rescue {}
    runtime_ctx = payload.dig("text_config", "max_position_embeddings") || payload["max_position_embeddings"] || payload["max_model_len"]
    configured = registry.dig(model, "model_info", "max_input_tokens")
    confidence = registry.dig(model, "model_info", "x_input_confidence").to_s
    if runtime_ctx && configured && configured.to_i < runtime_ctx.to_i
      if confidence == "owned-policy"
        puts "owned-policy: #{model} LiteLLM input cap intentionally remains below oMLX runtime capacity: runtime=#{runtime_ctx} configured=#{configured}"
      else
        puts "oMLX runtime/model context appears higher than LiteLLM policy cap for #{model}: runtime=#{runtime_ctx} configured=#{configured}"
      end
    elsif runtime_ctx && configured && configured.to_i > runtime_ctx.to_i
      # Dangerous direction: LiteLLM admits prompts up to `configured`, but the
      # runtime physically caps at `runtime_ctx` and will reject the overflow.
      puts "LiteLLM policy cap exceeds oMLX runtime capacity for #{model}: configured=#{configured} runtime=#{runtime_ctx} (lower max_input_tokens to #{runtime_ctx})"
    end
  end
end
' "$AI_LITELLM_SETTINGS" "$AI_LITELLM_CONFIG" | while IFS= read -r line; do
    [[ -n "$line" ]] && ai_litellm_context_doctor_warn "$line"
  done
}

ai_litellm_context_warn_owned_policy_output_source() {
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
Array(config["model_list"]).each do |e|
  model = e["model_name"]
  out = e.dig("model_info", "max_output_tokens")
  confidence = e.dig("model_info", "x_output_confidence").to_s
  next unless out && confidence == "owned-policy"
  puts "owned-policy: #{model} output cap #{out} is a conservative local ceiling (no provider/observed confirmation)."
end
' "$AI_LITELLM_CONFIG" | while IFS= read -r line; do
    [[ -n "$line" ]] && ai_litellm_context_doctor_warn "$line"
  done
}

ai_litellm_context_warn_provider_capability_drift() {
  local report
  report="$(ai_litellm_model_refresh_capabilities --json 2>/dev/null)" || return 0
  print -r -- "$report" | ai_litellm_ruby -rjson -e '
payload = JSON.parse(STDIN.read) rescue {}
rows = Array(payload["rows"])
issue_statuses = %w[drift source-missing provider-missing no-provider-model]
rows.each do |row|
  %w[input output reasoning].each do |dim|
    data = row[dim] || {}
    status = data["status"].to_s
    next unless issue_statuses.include?(status)
    configured = data.key?("configured") && !data["configured"].nil? ? data["configured"] : "-"
    provider = data.key?("provider") && !data["provider"].nil? ? data["provider"] : "-"
    puts "provider-capability #{status}: #{row["alias"]} #{dim} configured=#{configured} provider=#{provider}"
  end
end
' | while IFS= read -r line; do
    [[ -n "$line" ]] && ai_litellm_context_doctor_warn "$line"
  done
}

# Fail only on dangerous overclaims: a configured numeric ceiling above the
# provider-published ceiling, or declared reasoning when the provider reports
# it unsupported. Conservative underclaims and metadata gaps remain warnings.
ai_litellm_context_provider_capability_no_dangerous_overclaim() {
  local report
  report="$(ai_litellm_model_refresh_capabilities --json 2>/dev/null)" || return 0
  print -r -- "$report" | ai_litellm_ruby -rjson -e '
payload = JSON.parse(STDIN.read) rescue {}
errors = []
Array(payload["rows"]).each do |row|
  %w[input output].each do |dim|
    data = row[dim] || {}
    configured = data["configured"]
    provider = data["provider"]
    next unless configured.is_a?(Numeric) && provider.is_a?(Numeric)
    if configured > provider
      errors << "#{row["alias"]} #{dim} configured=#{configured} provider=#{provider}"
    end
  end
  reasoning = row["reasoning"] || {}
  if reasoning["configured"] == true && reasoning["provider"] == false
    errors << "#{row["alias"]} reasoning configured=true provider=false"
  end
end
errors.each { |error| warn "dangerous provider capability overclaim: #{error}" }
exit(errors.empty? ? 0 : 1)
'
}

ai_litellm_context_warn_output_clamp() {
  ai_litellm_context_gateway_clamp_configured >/dev/null 2>&1 && return 0
  ai_litellm_ruby -ryaml -e '
config = (YAML.load_file(ARGV[0], aliases: true) rescue YAML.load_file(ARGV[0]))
shared = Array(config["model_list"]).select do |entry|
  info = entry["model_info"] || {}
  ctx = info["max_input_tokens"].to_i
  out = info["max_output_tokens"].to_i
  ctx.positive? && out.positive? && ctx == out
end.map { |entry| entry["model_name"] }.compact.uniq
if shared.any?
  puts "shared-window routes have no gateway output clamp; harness reservation is the only output-reservation guard: #{shared.join(", ")}"
end
' "$AI_LITELLM_CONFIG" | while IFS= read -r line; do
    [[ -n "$line" ]] && ai_litellm_context_doctor_warn "$line"
  done
}

ai_litellm_context_descriptor_surfaces_ok() {
  [[ -d "$AI_LITELLM_HARNESSES_DIR" ]] || return 0
  node -e '
const fs = require("fs");
const path = require("path");
const dir = process.argv[1];
const seen = new Map();
const errors = [];
for (const file of fs.readdirSync(dir).filter((name) => name.endsWith(".json") && name !== "schema.json").sort()) {
  const descriptor = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
  const context = descriptor.adapterConfig?.context || {};
  if (context.enabled === false) continue;
  const harness = descriptor.name || path.basename(file, ".json");
  const surface = context.surface || `${harness}-litellm`;
  if (!surface) errors.push(`${harness}: context surface is empty`);
  if (seen.has(surface)) errors.push(`duplicate context surface ${surface}: ${seen.get(surface)} and ${harness}`);
  else seen.set(surface, harness);
}
if (errors.length) {
  for (const error of errors) console.error(error);
  process.exit(1);
}
' "$AI_LITELLM_HARNESSES_DIR"
}

ai_litellm_context_doctor() {
  local failed=0
  echo "claude-litellm context doctor"
  ai_litellm_context_doctor_check "LiteLLM pre-call context enforcement enabled" ai_litellm_context_pre_call_enabled || failed=1
  ai_litellm_context_doctor_check "gateway output clamp policy valid" ai_litellm_context_gateway_clamp_policy_ok || failed=1
  ai_litellm_context_doctor_check "output reservation policy aligned" ai_litellm_context_output_reservation_aligned || failed=1
  ai_litellm_context_doctor_check "gateway output clamp configured" ai_litellm_context_gateway_clamp_configured || failed=1
  ai_litellm_context_doctor_check "gateway estimated-token cost guardrail policy valid" ai_litellm_context_gateway_cost_guardrail_policy_ok || failed=1
  ai_litellm_context_doctor_check "gateway estimated-token cost guardrail configured" ai_litellm_context_gateway_cost_guardrail_configured || failed=1
  ai_litellm_context_doctor_check "context observations readable" ai_litellm_context_observations_ok || failed=1
  ai_litellm_context_doctor_check "harness context surfaces are unique" ai_litellm_context_descriptor_surfaces_ok || failed=1
  ai_litellm_context_doctor_check "harness output reservations leave input budget" ai_litellm_context_harness_reservations_ok || failed=1
  ai_litellm_context_doctor_check "context matrix renders" ai_litellm_quiet ai_litellm_context_matrix || failed=1
  ai_litellm_context_doctor_check "no dangerous provider capability overclaim" ai_litellm_context_provider_capability_no_dangerous_overclaim || failed=1
  ai_litellm_context_warn_omlx_policy_cap
  ai_litellm_context_warn_owned_policy_output_source
  ai_litellm_context_warn_provider_capability_drift
  ai_litellm_context_warn_output_clamp
  return $failed
}

# ── Noun-verb sub-dispatchers ────────────────────────────────────────────────
ai_litellm_cmd_proxy() {
  local verb="$1"; [[ $# -gt 0 ]] && shift
  case "$verb" in
    status|"")
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_status_json; else ai_litellm_status; fi
      ;;
    start)     ai_litellm_start ;;
    stop)      ai_litellm_stop ;;
    restart)   ai_litellm_restart ;;
    logs)      ai_litellm_logs "$@" ;;
    *) echo "Usage: claude-litellm proxy status|start|stop|restart|logs [lines] (diagnostics: run doctor --proxy)" >&2; return 1 ;;
  esac
}

ai_litellm_cmd_harness() {
  local verb="$1"; [[ $# -gt 0 ]] && shift
  case "$verb" in
    list|"")
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_harnesses_json; else ai_litellm_harnesses; fi
      ;;
    info)
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_harness_info_json "${2:-}"
      elif [[ "${2:-}" == "--json" ]]; then ai_litellm_harness_info_json "$1"
      else ai_litellm_harness_info "$@"; fi
      ;;
    launch)  ai_litellm_launch "$@" ;;
    reasoning)
      case "${1:-}" in
        set)     shift; ai_litellm_harness_reasoning_set "$@" ;;
        unset)   shift; ai_litellm_harness_reasoning_unset "$@" ;;
        allowed) shift; ai_litellm_harness_reasoning_allowed_json "${1:-}" ;;
        *)       ai_litellm_harness_reasoning_table "$@" ;;
      esac
      ;;
    alias)
      case "${1:-}" in
        set) shift; ai_litellm_harness_alias_set "$@" ;;
        get) shift; ai_litellm_harness_alias_json "${1:-claude}" ;;
        *)   ai_litellm_harness_alias_json "${1:-claude}" ;;
      esac
      ;;
    *) echo "Usage: claude-litellm harness list|info <name>|launch <name> [model] [args...]|reasoning [name]|reasoning set <name> <effort>|reasoning unset <name>|reasoning allowed <name>|alias get <name>|alias set <name> <tier> <model>" >&2; return 1 ;;
  esac
}

ai_litellm_cmd_runtime() {
  local verb="$1"; [[ $# -gt 0 ]] && shift
  case "$verb" in
    list)      ai_litellm_runtime_names ;;
    status|"")
      if [[ "${1:-}" == "--json" ]]; then shift; ai_litellm_runtime_status_json "$@"
      elif [[ "${2:-}" == "--json" ]]; then ai_litellm_runtime_status_json "$1"
      else ai_litellm_runtime_status "$@"; fi
      ;;
    *) echo "Usage: claude-litellm runtime list|status [name] (diagnostics: run doctor --runtime <name>)" >&2; return 1 ;;
  esac
}

ai_litellm_cmd_model() {
  local verb="$1"; [[ $# -gt 0 ]] && shift
  case "$verb" in
    list|"")
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_list_json; else ai_litellm_list; fi
      ;;
    info)         ai_litellm_model_info "$@" ;;
    limits)
      if [[ "${1:-}" == "--json" ]]; then shift; ai_litellm_model_limits_json "$@"
      elif [[ "${2:-}" == "--json" ]]; then ai_litellm_model_limits_json "$1"
      else ai_litellm_limits_table "$@"; fi
      ;;
    probe)
      # route retired entirely in P4 (absorbed into model); probe returns to
      # model as the canonical spelling -- a conscious reversal of the prior
      # H6 decision (route probe was canonical and model probe warned and
      # delegated toward it). No more deprecation delegation. The bare
      # (0-args) default-to-all-models behavior is migrated verbatim from the
      # probe dispatch branch that used to live on the retired route group.
      if (( $# == 0 )); then
        ai_litellm_probe_routes "${(@f)$(ai_litellm_model_names)}"
      else
        ai_litellm_probe_routes "$@"
      fi
      ;;
    refresh-capabilities) ai_litellm_model_refresh_capabilities "$@" ;;
    add)                  ai_litellm_model_add "$@" ;;
    register)             ai_litellm_model_register "$@" ;;
    remove)               ai_litellm_model_remove "$@" ;;
    qualify)              ai_litellm_model_qualify "$@" ;;
    reasoning)
      case "${1:-}" in
        probe)   shift; ai_litellm_model_reasoning_probe "$@" ;;
        set)     shift; ai_litellm_model_reasoning_set "$@" ;;
        unset)   shift; ai_litellm_model_reasoning_unset "$@" ;;
        allowed) shift; ai_litellm_model_reasoning_allowed_json "${1:-}" ;;
        *)       echo "Usage: claude-litellm model reasoning probe <model> [effort] [--candidate]|set <model> <effort>|unset <model>|allowed <model>" >&2; return 1 ;;
      esac
      ;;
    *) echo "Usage: claude-litellm model list|info [model]|limits [model]|probe [model...]|refresh-capabilities [--json|--check]|add <provider-id> [--name|--claude-tier|--dry-run]|register <surface> --backend <provider/model> --context N --output N [options]|remove <surface> [--dry-run]|qualify <surface> [--activate-tier <tier>|--json]|reasoning probe <model> [effort] [--candidate]|reasoning set <model> <effort>|reasoning unset <model>|reasoning allowed <model>" >&2; return 1 ;;
  esac
}

ai_litellm_task_ledger() {
  local script="$AI_LITELLM_TASK_LEDGER"
  [[ -f "$script" && ! -L "$script" ]] || {
    echo "Missing managed task ledger: $script" >&2
    return 1
  }

  local python="$AI_LITELLM_HOME/runtime/venv/bin/python"
  if [[ ! -x "$python" ]]; then
    python="$(ai_litellm_external_python 2>/dev/null)" || {
      echo "Python 3.13 is required for task orchestration." >&2
      return 1
    }
  fi
  ai_litellm_python_isolated "$python" -S "$script" --root "$AI_LITELLM_TASKS_HOME" "$@"
}

ai_litellm_cmd_task() {
  case "${1:-}" in
    create|list|show|handoff|complete|prompt|_mark-launched)
      ai_litellm_task_ledger "$@"
      ;;
    -h|--help|"")
      cat <<'EOF'
Usage: claude-litellm task create <name> --goal <text> [--worktree <path>]
       claude-litellm task handoff <id> --to <route> --objective <text> [evidence]
       claude-litellm task launch <id> [--handoff <n|latest>] [-- <claude args>]
       claude-litellm task complete <id> --summary <text> [--close]
       claude-litellm task list|show <id>|prompt <id> [--json]

Each launch creates a new Claude process pinned to one route. The task ledger
passes bounded goals, decisions, worktree and test/commit evidence between
model-specific sessions; it never attempts to transplant a provider transcript.
EOF
      ;;
    *)
      echo "Usage: claude-litellm task create|list|show|handoff|launch|complete|prompt ..." >&2
      return 1
      ;;
  esac
}

ai_litellm_cmd_key() {
  local verb="$1"; [[ $# -gt 0 ]] && shift
  case "$verb" in
    status|"")
      if [[ "${1:-}" == "--json" ]]; then ai_litellm_key_status_json; else ai_litellm_key_status; fi
      ;;
    set)       ai_litellm_key_set "$@" ;;
    *) echo "Usage: claude-litellm key status|set [--keychain|--env-file] <openrouter|ENV_VAR|provider-name> [value]" >&2; return 1 ;;
  esac
}

ai_litellm_uninstall() {
  local script="$AI_LITELLM_HOME/scripts/uninstall.zsh"
  if [[ ! -f "$script" ]]; then
    echo "Installed uninstall script not found: $script" >&2
    echo "Run scripts/uninstall.zsh from the repository checkout, or reinstall the package." >&2
    return 1
  fi
  zsh "$script" --prefix "$AI_LITELLM_HOME" "$@"
}

ai_litellm_cmd_context() {
  local verb="$1"; [[ $# -gt 0 ]] && shift
  case "$verb" in
    matrix|"")
      if [[ "${1:-}" == "--json" ]]; then shift; ai_litellm_context_matrix_json "$@"
      elif [[ "${2:-}" == "--json" ]]; then ai_litellm_context_matrix_json "$1"
      else ai_litellm_context_matrix "$@"; fi
      ;;
    probe)     ai_litellm_context_probe "$@" ;;
    observations) ai_litellm_context_observations "$@" ;;
    *) echo "Usage: claude-litellm context matrix [filter]|probe <surface|all>|observations [filter] (diagnostics: run doctor --context)" >&2; return 1 ;;
  esac
}

# The reasoning matrix introspects the local LiteLLM Python runtime
# (litellm.supports_reasoning / get_supported_openai_params). When litellm is
# not installed -- the lightweight CI check job, or a host not yet provisioned
# with the proxy runtime -- the matrix simply cannot render, which is not a
# policy failure. Skip it with a note (same litellm-absence tolerance as
# ai_litellm_doctor_reasoning_capability_truth). The user-facing
# `reasoning matrix` command keeps its hard error for a direct, unservable request.
ai_litellm_doctor_reasoning_matrix_check() {
  if ! ai_litellm_litellm_python >/dev/null 2>&1; then
    echo "skip reasoning matrix renders (LiteLLM Python runtime not available)"
    return 0
  fi
  ai_litellm_doctor_check "reasoning matrix renders" ai_litellm_quiet ai_litellm_model_reasoning_table
}

ai_litellm_reasoning_doctor() {
  local failed=0
  echo "claude-litellm reasoning doctor"
  ai_litellm_doctor_check "model-specific effort metadata valid" ai_litellm_reasoning_effort_metadata_ok || failed=1
  ai_litellm_doctor_reasoning_matrix_check || failed=1
  ai_litellm_doctor_reasoning_capability_truth
  return $failed
}

ai_litellm_model_policy_audit() {
  local failed=0
  echo "claude-litellm model policy audit"
  ai_litellm_doctor_check "model limits render" ai_litellm_quiet ai_litellm_limits_table || failed=1
  ai_litellm_doctor_check "model_info uses x-limits anchors" ai_litellm_model_info_anchor_refs_ok || failed=1
  ai_litellm_doctor_check "LiteLLM pre-call context enforcement enabled" ai_litellm_context_pre_call_enabled || failed=1
  ai_litellm_doctor_check "gateway output clamp policy valid" ai_litellm_context_gateway_clamp_policy_ok || failed=1
  ai_litellm_doctor_check "output reservation policy aligned" ai_litellm_context_output_reservation_aligned || failed=1
  ai_litellm_doctor_check "gateway output clamp configured" ai_litellm_context_gateway_clamp_configured || failed=1
  ai_litellm_doctor_check "gateway estimated-token cost guardrail policy valid" ai_litellm_context_gateway_cost_guardrail_policy_ok || failed=1
  ai_litellm_doctor_check "gateway estimated-token cost guardrail configured" ai_litellm_context_gateway_cost_guardrail_configured || failed=1
  ai_litellm_doctor_check "context observations readable" ai_litellm_context_observations_ok || failed=1
  ai_litellm_doctor_check "harness output reservations leave input budget" ai_litellm_context_harness_reservations_ok || failed=1
  ai_litellm_doctor_check "context matrix renders" ai_litellm_quiet ai_litellm_context_matrix || failed=1
  ai_litellm_doctor_reasoning_matrix_check || failed=1
  ai_litellm_context_warn_omlx_policy_cap
  ai_litellm_context_warn_owned_policy_output_source
  ai_litellm_context_warn_provider_capability_drift
  ai_litellm_context_warn_output_clamp
  return $failed
}

ai_litellm_cmd_reasoning() {
  local verb="$1"; [[ $# -gt 0 ]] && shift
  case "$verb" in
    matrix|"")
      if [[ "${1:-}" == "--json" ]]; then shift; ai_litellm_reasoning_matrix_json "$@"
      elif [[ "${2:-}" == "--json" ]]; then ai_litellm_reasoning_matrix_json "$1"
      else ai_litellm_model_reasoning_table "$@"; fi
      ;;
    probe)     ai_litellm_model_reasoning_probe "$@" ;;
    *) echo "Usage: claude-litellm reasoning matrix [model]|probe <model> [effort] (diagnostics: run doctor --reasoning)" >&2; return 1 ;;
  esac
}

ai_litellm_cmd_doctor() {
  # Unified top-level doctor. No args => run the FULL battery by default
  # (global/proxy + context + reasoning + model-policy), delegating to the
  # existing group doctor functions (no check logic is duplicated here).
  # Scoping flags narrow to one pass; "$@" is forwarded so e.g.
  # `doctor --proxy --probe-routes` still reaches the proxy doctor flags.
  if (( $# == 0 )); then
    local failed=0
    ai_litellm_doctor             || failed=1
    ai_litellm_context_doctor     || failed=1
    ai_litellm_reasoning_doctor   || failed=1
    ai_litellm_model_policy_audit || failed=1
    return $failed
  fi
  local scope="$1"; shift
  case "$scope" in
    --proxy)      ai_litellm_doctor "$@" ;;
    --context)    ai_litellm_context_doctor "$@" ;;
    --reasoning)  ai_litellm_reasoning_doctor "$@" ;;
    --policy)     ai_litellm_model_policy_audit "$@" ;;
    --runtime)    ai_litellm_doctor_runtime "$@" ;;
    *) echo "Usage: claude-litellm doctor [--proxy|--context|--reasoning|--policy|--runtime <name>]" >&2; return 1 ;;
  esac
}

# One-shot control-plane summary. Composes EXISTING read surfaces only — no
# state re-derivation (same contract as --json). Degraded sections render as
# empty/not-running instead of aborting, so the command always exits 0
# (observability command; mirrors the empty-output honesty of the json API).
ai_litellm_cmd_status() {
  if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--json" ]] }; then
    echo "Usage: claude-litellm status [--json]" >&2
    return 1
  fi
  if [[ "${1:-}" == "--json" ]]; then
    node -e '
const parse = (s) => { try { return JSON.parse(s); } catch { return null; } };
const [proxy, harnesses, runtimes, keys, models] = process.argv.slice(1).map(parse);
process.stdout.write(JSON.stringify({ proxy, harnesses, runtimes, keys, models }) + "\n");
' "$(ai_litellm_status_json)" "$(ai_litellm_harnesses_json)" "$(ai_litellm_runtime_status_json)" "$(ai_litellm_key_status_json)" "$(ai_litellm_list_json)"
    return 0
  fi
  ai_litellm_status
  echo
  echo "harness model mappings:"
  # alias get emits a compact JSON array of {tier, model, ...}; reformat the
  # already-fetched data for humans (raw-indented passthrough on parse failure).
  ai_litellm_cmd_harness alias get claude 2>/dev/null | node -e '
const input = require("fs").readFileSync(0, "utf8");
try {
  for (const e of JSON.parse(input)) console.log("  claude " + e.tier + " -> " + (e.model ?? "unset"));
} catch {
  if (input) process.stdout.write(input.replace(/^/gm, "  "));
}
'
  echo
  ai_litellm_key_status
  echo
  ai_litellm_capabilities
  return 0
}

ai_litellm_usage() {
  cat <<'EOF'
Usage: claude-litellm <group> <verb> [args]

  Status:        claude-litellm status [--json]  Proxy/harness/runtime/key/capability one-shot summary
  Proxy:         claude-litellm proxy status|start|stop|restart|logs [lines]
  Harness:       claude-litellm harness list|info <name>|launch <name> [model] [args...]
                 claude-litellm harness reasoning [name]
                 claude-litellm harness reasoning set <name> <effort>
                 claude-litellm harness reasoning unset <name>
  Runtime:       claude-litellm runtime list|status [name]
  Model:         claude-litellm model list|info [model]|limits [model]|probe [model...]|refresh-capabilities [opts]
                 claude-litellm model add <provider-id> [--name|--claude-tier|--dry-run]
                 claude-litellm model register <surface> --backend <provider/model> --context N --output N [options]
                 claude-litellm model remove <surface> [--dry-run]
                 claude-litellm model qualify <surface> [--activate-tier <tier>|--json]
                 claude-litellm model reasoning probe <model> [effort] [--candidate]
                 claude-litellm model reasoning set <model> <effort>
                 claude-litellm model reasoning unset <model>
  Task:          claude-litellm task create|list|show|handoff|launch|complete|prompt
  Context:       claude-litellm context matrix [filter]|probe <surface|all>|observations [filter]
  Reasoning:     claude-litellm reasoning matrix [model]|probe <model> [effort]
  Doctor:        claude-litellm doctor [--proxy|--context|--reasoning|--policy|--runtime <name>]
  Key:           claude-litellm key status|set [--keychain|--env-file] <openrouter|ENV_VAR|provider-name> [value]
  Permissions:   claude-litellm permissions get [--json]
                 claude-litellm permissions set <default|bypassPermissions>
                 claude-litellm permissions reset
  Sync:          claude-litellm sync      Regenerate derived configs + reload proxy from the single source
  Uninstall:     claude-litellm uninstall Remove package directory and global shim

Reasoning effort values (not a command — pass to reasoning/harness set):
  OpenRouter none|minimal|low|medium|high         Claude auto|low|medium|high|xhigh|max
  LiteLLM 1.92 normalizes unqualified OpenRouter xhigh/max to high; the CLI rejects those false choices.
EOF
}

ai_litellm() {
  local cmd="$1"; [[ $# -gt 0 ]] && shift
  case "$cmd" in
    -h|--help|"") ai_litellm_usage ;;

    # ── Canonical noun-verb groups ──
    status)       ai_litellm_cmd_status "$@" ;;
    proxy)        ai_litellm_cmd_proxy "$@" ;;
    harness)      ai_litellm_cmd_harness "$@" ;;
    runtime)      ai_litellm_cmd_runtime "$@" ;;
    model)        ai_litellm_cmd_model "$@" ;;
    task)         ai_litellm_cmd_task "$@" ;;
    context)      ai_litellm_cmd_context "$@" ;;
    reasoning)    ai_litellm_cmd_reasoning "$@" ;;
    doctor)       ai_litellm_cmd_doctor "$@" ;;
    key)          ai_litellm_cmd_key "$@" ;;
    permissions)  ai_litellm_cmd_permissions "$@" ;;
    sync|--sync)  ai_litellm_sync "$@" ;;
    uninstall)    ai_litellm_uninstall "$@" ;;

    *)
      echo "Unknown claude-litellm command: $cmd" >&2
      ai_litellm_usage >&2
      return 1
      ;;
  esac
}
