# Migration

The legacy package roots were
`${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm-fabric` and
`${XDG_DATA_HOME:-$HOME/.local/share}/ai-litellm`. The default new root is
`${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm`.
`CLAUDE_LITELLM_ROOT` changes that default for both tools; `--prefix` changes
the installer destination, while `--destination` changes the standalone
migrator destination. `CLAUDE_LITELLM_BACKUP_ROOT` overrides the default
verified-backup root at
`${XDG_DATA_HOME:-$HOME/.local/share}/claude-litellm-backups`.

## What moves

Migration imports only durable Claude/LiteLLM data:

- project transcripts and auto-memory under `claude-config/projects/`
- `claude-config/history.jsonl`
- isolated `claude-config/.claude.json` metadata
- the historical `state/ai-litellm/env` file, including existing
  provider/master keys, when it does not conflict with the destination

It does not import generated settings overlays, caches, session environments,
OAuth tokens, virtual environments, Codex state, model qualification records,
reasoning preferences, or context observations. On the default installer
cutover or standalone `--remove-source`, old Codex/security/runtime state
remains in the full source backup; without source removal it remains in the
legacy package itself. Native `~/.claude`, `~/.codex`, and native commands are
never read, changed, or removed by the migrator. The normal installer may read
the dedicated `litellm-master-key` Keychain item during master-key setup, but it
does not change or remove Keychain entries.

This exclusion applies to a legacy cutover. A normal upgrade of an existing
`claude-litellm` destination preserves its private user overlays and current
`state/auth/chatgpt` and `state/auth/grok` OAuth state while replacing only
package-managed files and regenerating effective configuration.

## Default install and cutover

```zsh
./scripts/install.zsh
```

The installer performs its package/runtime preflight and validates incoming
configuration before mutation. It also runs the migrator's complete no-clobber
preflight before staging the runtime. After the runtime and user overlays are
validated, it stops only a verified current-prefix proxy, publishes the new
package, runtime, and public shim on one rollback boundary, and commits that
package transaction.

Legacy migration is a post-commit operation because it changes independent
durable state. The migrator stops only verified legacy-prefix proxies, rebuilds
and checks its strict merge plan, and rejects differing destination collisions
before creating a backup or changing the destination. It then backs up selected
destination state and byte-verifies a full backup of every recognized legacy
package, publishes and verifies the durable-state merge, and only then removes
the legacy package. Master-key setup and restoration of a previously running
current proxy follow migration.

A migration, key-setup, or restart failure is reported as an explicit
post-install warning. It does not falsely claim that the already-committed
package publication rolled back. Post-install model/Claude smoke tests are an
operator or CI step rather than part of this mutating transaction.

To install without touching recognized legacy packages or shims:

```zsh
./scripts/install.zsh --no-migrate
```

A non-default `--prefix` is staging-oriented: automatic legacy migration and
the global shim are disabled unless the prefix is the standard package root.

## Inspect or run migration separately

The no-clobber preflight computes and validates the complete plan without
signalling processes, creating backups, publishing data, or removing a source:

```zsh
./scripts/migrate-legacy.zsh --preflight-only
```

Use a dry run to print the mutating operations without executing them:

```zsh
./scripts/migrate-legacy.zsh --dry-run --remove-source
```

Explicit source/destination paths are supported; repeat `--source` for more
than one recognized legacy root:

```zsh
CLAUDE_LITELLM_BACKUP_ROOT="$HOME/private/claude-litellm-backups" \
  ./scripts/migrate-legacy.zsh \
  --source "$HOME/.local/share/ai-litellm" \
  --destination "$HOME/.local/share/claude-litellm" \
  --remove-source
```

Without `--remove-source`, selected durable state is copied and verified but
the recognized legacy package remains. With it, the entire package is first
copied and byte-verified below the backup root, including excluded Codex state,
old runtimes, overlays, and logs. Source removal never precedes that verified
backup and verified destination publication.

## Reauthorize and requalify

Legacy OAuth and qualification evidence are deliberately not trusted across the
architecture change. Reauthorize the subscription routes you intend to use,
then qualify every target route against the current six-gate contract:

```zsh
claude-litellm auth login chatgpt
claude-litellm auth login grok
claude-litellm auth status --json
claude-litellm model qualify GPT-5.4-chatgpt-oauth
claude-litellm model qualify Grok-4.5-xai-oauth
claude-litellm model qualify <other-route>
```

Authentication status proves token presence only. A PASS from `model qualify`
is current transport evidence; a real `claude-litellm use <route> -p '...'` smoke
then exercises the full Claude Code client path. Add
`--activate-tier <fable|opus|sonnet|haiku>` only when that route should replace
the chosen durable tier after PASS.
