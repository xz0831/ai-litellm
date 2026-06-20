"""Static, curated registry of executable `ai-litellm` commands for the command
palette. Grades are NOT stored — they are derived at run time via
safety.classify(argv) so the palette and the action bar share one risk oracle.
Excludes secret-bearing commands (key set — the log echoes argv) and launch
(special exit handoff)."""
from __future__ import annotations
import shlex
from dataclasses import dataclass


@dataclass(frozen=True)
class Command:
    group: str          # grouping label, e.g. "proxy" / "model" / "harness"
    label: str          # human label shown in the list, e.g. "restart proxy"
    argv: tuple[str, ...]  # base argv (after the `ai-litellm` binary)
    takes_args: bool    # whether the user must supply more args
    usage: str          # hint shown in arg mode (full `ai-litellm …` usage line)


COMMANDS: list[Command] = [
    # lifecycle / doctor (argv verified against safety.ACTIONS; have key bindings,
    # listed here for search-by-name discoverability)
    Command("proxy", "start proxy", ("proxy", "start"), False, "ai-litellm proxy start"),
    Command("proxy", "stop proxy", ("proxy", "stop"), False, "ai-litellm proxy stop"),
    Command("proxy", "restart proxy", ("proxy", "restart"), False, "ai-litellm proxy restart"),
    Command("proxy", "sync (regenerate + restart)", ("sync",), False, "ai-litellm sync"),
    Command("proxy", "doctor (full battery)", ("proxy", "doctor"), False, "ai-litellm proxy doctor"),
    # reasoning effort — keyless, the palette's real value-add (argv from lib.zsh usage)
    Command("model", "model reasoning set", ("model", "reasoning", "set"), True,
            "ai-litellm model reasoning set <model> <effort>"),
    Command("model", "model reasoning unset", ("model", "reasoning", "unset"), True,
            "ai-litellm model reasoning unset <model>"),
    Command("model", "model reasoning probe (billable)", ("model", "reasoning", "probe"), True,
            "ai-litellm model reasoning probe <model> [effort]"),
    Command("harness", "harness reasoning set", ("harness", "reasoning", "set"), True,
            "ai-litellm harness reasoning set <name> <effort>"),
    Command("harness", "harness reasoning unset", ("harness", "reasoning", "unset"), True,
            "ai-litellm harness reasoning unset <name>"),
]


def filter_commands(commands: list[Command], query: str) -> list[Command]:
    """Case-insensitive subsequence (fuzzy) match on 'group label'. Empty → all."""
    q = query.strip().lower()
    if not q:
        return list(commands)  # copy: never hand back the caller's (module-level) list
    out = []
    for c in commands:
        hay = f"{c.group} {c.label}".lower()
        i = 0
        for ch in hay:
            if i < len(q) and ch == q[i]:
                i += 1
        if i == len(q):
            out.append(c)
    return out


def resolve_argv(cmd: Command, arg_text: str) -> list[str]:
    """Final argv = base argv + shlex-split free-text args (no shell)."""
    extra = shlex.split(arg_text) if cmd.takes_args else []
    return list(cmd.argv) + extra
