# fabric v2 — P2: Command Palette — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **2026-06-29 supersession:** This is a historical implementation plan. The current TUI intentionally narrows the palette: `:` is the only command-palette trigger, `ctrl+p` is no longer bound, and Router plan/explain/dry-run/execute are excluded from the raw palette in favor of the Router panel's structured `p`/`v`/`t`/`E` actions. Router row selection now seeds the modal intent, and the internal router `score` is not shown in the primary table. See `docs/FABRIC_DASHBOARD.md` for the live contract.

**Goal:** Add a `:` / `ctrl+p` command palette to the `fabric` TUI: fuzzy-search a curated `ai-litellm` command registry, supply args via a free-text form with a usage hint, gate mutating/billable commands through the existing confirm modal, and stream results to the log panel — so the user never has to memorize commands.

**Architecture:** A custom `CommandPalette(ModalScreen)` over a static registry (`commands.py`). Selecting a command resolves a final argv (base argv + `shlex`-split free-text args), which the app runs through a SHARED `_run_argv` core extracted from the existing `_run_action` — so the palette reuses the exact gate (`safety.classify(argv)`) + async-offload + log path, with zero duplicated execution logic and one source of truth for risk grading.

**Tech Stack:** Python 3, Textual 8.2.7, pytest + Textual Pilot, all under the package venv.

## Global Constraints

- ALL python runs under the package venv: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/ -q`. Never system python3 (PEP-668). Branch `feat/fabric-v2-p2-palette`; do NOT switch branches. (spec §3)
- **backend owns logic, TUI is a caller** — the palette only INVOKES `ai-litellm <command>` via the existing ActionRunner; it never writes config/YAML/JSON itself. (spec §3, §12)
- **Single source of truth for risk** — the gate is `safety.classify(full_argv)`: `!= SAFE` → ConfirmModal (P1's Cancel-first for RESTART/DESTRUCTIVE, Confirm-focus rules in modal.py), `SAFE` → run immediately. The palette and the contextual action bar share this oracle — no parallel hand-set grade list. (spec §12)
- **registry-only, no free-form passthrough** — the palette executes only curated registry entries (possibly with args), never an arbitrary typed command. (spec §12)
- **NO secret-bearing commands in the P2 registry** — `key set` and any command taking a secret are EXCLUDED: the log echoes `$ ai-litellm <argv>`, which would leak the secret. Key management is P3 (masked input). Also EXCLUDE `harness launch` (it uses the special `self.exit(("launch", …))` handoff, not ActionRunner). (security; spec §2 native-harness untouched)
- **No shell** — free-text args are split with `shlex.split` into an argv list and passed to `subprocess.run(argv, …)` (list form, no `shell=True`) — no injection. (spec §12)
- Reads/auto-refresh and the confirm-gate invariant from P1 must keep working unchanged. Tests make ZERO real subprocess/network calls (inject a fake runner/spawn). (spec §3, §10)
- The brief Textual snippets target a generic API — VALIDATE against installed textual 8.2.7 and adapt until green (event names like `Input.Submitted`/`Input.Changed`/`ListView.Selected`, `ListView.index`, `query`/`mount`, `ModalScreen.dismiss`). (P1 lessons)

---

## File Structure

- Create: `config/ai-litellm/fabric_dash/commands.py` — the `Command` dataclass, the static `COMMANDS` registry, `filter_commands`, `resolve_argv`. Pure data + functions, no Textual.
- Create: `config/ai-litellm/fabric_dash/palette.py` — `CommandPalette(ModalScreen)`: filter→select→arg-mode UI; dismisses with `(label, argv)` or `None`.
- Modify: `config/ai-litellm/fabric_dash/app.py` — extract shared `_run_argv`; add `:` / `ctrl+p` binding, `action_palette`, and `ENABLE_COMMAND_PALETTE = False`.
- Modify: `config/ai-litellm/fabric_dash/app.tcss` — `CommandPalette` / `#palette-*` styling (mirror ConfirmModal/HelpOverlay).
- Test: `config/ai-litellm/fabric_dash/tests/test_commands.py` (new), and additions to `tests/test_app.py`.

No backend / lib.zsh changes in P2.

---

## Task 1: Command registry (`commands.py`)

**Files:**
- Create: `config/ai-litellm/fabric_dash/commands.py`
- Test: `config/ai-litellm/fabric_dash/tests/test_commands.py`

**Interfaces:**
- Produces:
  - `Command` — frozen dataclass `(group: str, label: str, argv: tuple[str, ...], takes_args: bool, usage: str)`.
  - `COMMANDS: list[Command]` — the curated registry.
  - `filter_commands(commands: list[Command], query: str) -> list[Command]` — case-insensitive subsequence (fuzzy) match on `f"{group} {label}"`; empty query → all.
  - `resolve_argv(cmd: Command, arg_text: str) -> list[str]` — `list(cmd.argv) + (shlex.split(arg_text) if cmd.takes_args else [])`.

The registry entries are VERIFIED against the real CLI: lifecycle/doctor argv come from `safety.ACTIONS` (`["proxy","start"]`, `["proxy","stop"]`, `["proxy","restart"]`, `["sync"]`, `["proxy","doctor"]`); reasoning argv come from `lib.zsh` usage strings (`ai-litellm model reasoning set <model> <effort>` / `unset <model>` / `probe <model> [effort]`; `ai-litellm harness reasoning set <name> <effort>` / `unset <name>`). Do NOT add `key set` or `harness launch` (see Global Constraints).

- [ ] **Step 1: Write the failing tests** — create `tests/test_commands.py`:

```python
from fabric_dash.commands import Command, COMMANDS, filter_commands, resolve_argv
from fabric_dash import safety


def test_registry_excludes_secret_and_launch_commands():
    flat = [" ".join(c.argv) for c in COMMANDS]
    assert not any("key" in f and "set" in f for f in flat), "key set leaks secrets via log echo"
    assert not any("launch" in f for f in flat), "launch uses the special exit handoff, not the palette"


def test_registry_grades_resolve_via_classify():
    # Every no-arg command's grade must be discoverable by the shared oracle.
    for c in COMMANDS:
        if not c.takes_args:
            grade = safety.classify(list(c.argv))
            assert grade in (safety.SAFE, safety.RESTART, safety.BILLABLE, safety.DESTRUCTIVE)


def test_lifecycle_entries_match_safety_actions():
    argvs = {tuple(c.argv) for c in COMMANDS}
    assert ("proxy", "restart") in argvs and ("sync",) in argvs and ("proxy", "start") in argvs


def test_filter_is_fuzzy_subsequence_case_insensitive():
    res = filter_commands(COMMANDS, "rst")  # subsequence of "restart"
    assert any(c.argv == ("proxy", "restart") for c in res)
    assert filter_commands(COMMANDS, "") == COMMANDS          # empty → all
    assert filter_commands(COMMANDS, "zzzznope") == []        # no match → empty


def test_resolve_argv_splits_args_with_shlex():
    setcmd = next(c for c in COMMANDS if c.argv == ("model", "reasoning", "set"))
    assert resolve_argv(setcmd, "GLM-5.2 high") == ["model", "reasoning", "set", "GLM-5.2", "high"]
    start = next(c for c in COMMANDS if c.argv == ("proxy", "start"))
    assert resolve_argv(start, "ignored") == ["proxy", "start"]  # no-arg ignores text


def test_reasoning_probe_is_billable():
    probe = next(c for c in COMMANDS if c.argv == ("model", "reasoning", "probe"))
    # probe + a model resolves to a BILLABLE argv (gate path exercised in app tests)
    assert safety.classify(resolve_argv(probe, "GLM-5.2")) == safety.BILLABLE
```

- [ ] **Step 2: Run to verify failure**

Run: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/test_commands.py -q`
Expected: FAIL — `fabric_dash.commands` does not exist.

- [ ] **Step 3: Implement `commands.py`**:

```python
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
    argv: tuple         # base argv (after the `ai-litellm` binary)
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
        return commands
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
```

- [ ] **Step 4: Run tests to verify pass**

Run: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/test_commands.py -q`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add config/ai-litellm/fabric_dash/commands.py config/ai-litellm/fabric_dash/tests/test_commands.py
git commit -m "feat(dash): command registry for the palette (classify-graded, no secrets)"
```

---

## Task 2: Extract the shared `_run_argv` execution core

**Files:**
- Modify: `config/ai-litellm/fabric_dash/app.py` (`_run_action` ~L353-386)
- Test: `config/ai-litellm/fabric_dash/tests/test_app.py`

**Interfaces:**
- Produces: `async def _run_argv(self, argv: list[str], label: str | None = None, consequence: str | None = None) -> None` — gate via `classify(argv)` (non-SAFE → ConfirmModal), echo + offload `runner.run` via `asyncio.to_thread`, write results + exit code to `#results`, then `refresh_status`. NOT a `@work` (it is awaited from within a worker).
- Consumes (unchanged): `safety.classify`, `safety.SAFE`, `ConfirmModal`, `ActionRunner.run(argv, on_line) -> int`, `#results` RichLog.

The current `_run_action` gates on `Action.needs_confirm` and runs inline. Refactor so the gate/offload/log core lives in `_run_argv` (keyed off `classify`), and `_run_action` delegates. The drift-guard test (`classify(a.argv) == a.grade`, and `a.needs_confirm == (a.grade != SAFE)`) guarantees behavior is preserved for ACTIONS; the per-action `consequence` text is preserved by passing it through.

- [ ] **Step 1: Write the failing test** — append to `tests/test_app.py`:

```python
@pytest.mark.asyncio
async def test_run_argv_safe_runs_without_modal_and_logs():
    calls = []
    def spawn(argv):
        calls.append(argv)
        return (0, ["did the thing"])
    from fabric_dash.actions import ActionRunner
    app = FabricApp(client=make_client(), runner=ActionRunner(spawn=spawn))
    async with app.run_test() as pilot:
        await pilot.pause()
        await app._run_argv(["proxy", "start"], label="start proxy")  # SAFE → no modal
        await pilot.pause()
        from textual.widgets import RichLog
        assert calls and calls[0] == ["ai-litellm", "proxy", "start"]
        # not asserting modal absence beyond: the call completed inline (no hang)

@pytest.mark.asyncio
async def test_run_argv_restart_goes_through_confirm_modal():
    calls = []
    def spawn(argv):
        calls.append(argv)
        return (0, [])
    from fabric_dash.actions import ActionRunner
    app = FabricApp(client=make_client(), runner=ActionRunner(spawn=spawn))
    async with app.run_test() as pilot:
        await pilot.pause()
        app._run_argv_worker(["proxy", "restart"], "restart proxy")  # schedule via a worker wrapper
        await pilot.pause()
        from fabric_dash.modal import ConfirmModal
        assert isinstance(app.screen, ConfirmModal)   # RESTART → gated, not yet run
        assert calls == []
        await pilot.press("tab"); await pilot.press("enter"); await pilot.pause()
        assert calls and calls[0] == ["ai-litellm", "proxy", "restart"]
```

> Note: `_run_argv` is awaited from within a worker; the second test needs a tiny `@work` wrapper to drive it from a test. Add `@work def _run_argv_worker(self, argv, label=None): await self._run_argv(argv, label)` in app.py (or, if cleaner, have the test call `app._run_action`'s public worker path). Keep whatever you add minimal and used.

- [ ] **Step 2: Run to verify failure**

Run: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/test_app.py -k run_argv -q`
Expected: FAIL — `_run_argv` / `_run_argv_worker` do not exist.

- [ ] **Step 3: Refactor `app.py`** — extract the core and delegate. Add `from .safety import classify` to the existing safety import. Replace `_run_action` body:

```python
async def _run_argv(self, argv: list[str], label: str | None = None,
                    consequence: str | None = None) -> None:
    """Shared command execution core: gate by classify(argv), offload the
    blocking subprocess off the event loop, stream results to the log.
    Awaited from a worker (callers are @work) so push_screen_wait works."""
    grade = classify(argv)
    name = label or " ".join(argv)
    if grade != SAFE:
        msg = consequence or f"run `ai-litellm {' '.join(argv)}` — a {grade} action."
        ok = await self.push_screen_wait(
            ConfirmModal(msg, title=f"Confirm {name}", grade=grade)
        )
        if not ok:
            self.query_one("#results", RichLog).write(f"[dim]cancelled: {name}[/]")
            return
    log = self.query_one("#results", RichLog)
    log.write(f"$ ai-litellm {' '.join(argv)}")
    lines: list[str] = []
    rc = await asyncio.to_thread(self.runner.run, list(argv), lines.append)
    for ln in lines:
        log.write(ln)
    log.write(f"[{'green' if rc == 0 else 'red'}]exit {rc}[/]")
    await self.refresh_status()

@work
async def _run_action(self, key: str) -> None:
    a = self._action_by_key(key)
    if a is None:
        return
    await self._run_argv(list(a.argv), a.label, a.consequence)

@work
async def _run_argv_worker(self, argv: list[str], label: str | None = None) -> None:
    """Worker entrypoint to run an arbitrary registry argv (used by the palette)."""
    await self._run_argv(argv, label)
```

> Note: keep the existing `_refresh_in_flight` guard, the `asyncio` import, and the `RichLog` import. `_run_action` stays `@work`; `action_do_s/d/S/R/X` are unchanged (they call `self._run_action(...)`).

- [ ] **Step 4: Run the full suite to verify pass + no regression**

Run: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/ -q`
Expected: PASS — the two new tests plus ALL existing action/gate/freeze tests (behavior preserved).

- [ ] **Step 5: Commit**

```bash
git add config/ai-litellm/fabric_dash/app.py config/ai-litellm/fabric_dash/tests/test_app.py
git commit -m "refactor(dash): extract shared _run_argv (gate+offload+log) for reuse"
```

---

## Task 3: `CommandPalette` modal (`palette.py`)

**Files:**
- Create: `config/ai-litellm/fabric_dash/palette.py`
- Modify: `config/ai-litellm/fabric_dash/app.tcss`
- Test: `config/ai-litellm/fabric_dash/tests/test_app.py`

**Interfaces:**
- Consumes: `commands.COMMANDS`, `filter_commands`, `resolve_argv`, `Command`.
- Produces: `CommandPalette(ModalScreen)` — `__init__(self, commands)`. Dismisses with `(label: str, argv: list[str])` on selection/submit, or `None` on cancel. Two internal modes: `"filter"` (typing filters the list) and `"args"` (typing supplies free-text args for a `takes_args` command, with `cmd.usage` as the input placeholder).

- [ ] **Step 1: Write the failing tests** — append to `tests/test_app.py`:

```python
@pytest.mark.asyncio
async def test_palette_filter_and_select_noarg_returns_argv():
    from fabric_dash.palette import CommandPalette
    from fabric_dash.commands import COMMANDS
    captured = {}
    app = FabricApp(client=make_client())
    async with app.run_test() as pilot:
        await pilot.pause()
        async def grab():
            captured["choice"] = await app.push_screen_wait(CommandPalette(COMMANDS))
        app.run_worker(grab())
        await pilot.pause()
        await pilot.press("r", "e", "s", "t")          # filter -> "restart proxy"
        await pilot.pause()
        await pilot.press("enter")                     # no-arg -> selects + dismisses
        await pilot.pause()
        label, argv = captured["choice"]
        assert argv == ["proxy", "restart"]

@pytest.mark.asyncio
async def test_palette_args_mode_shows_usage_and_splits():
    from fabric_dash.palette import CommandPalette
    from fabric_dash.commands import COMMANDS
    captured = {}
    app = FabricApp(client=make_client())
    async with app.run_test() as pilot:
        await pilot.pause()
        async def grab():
            captured["choice"] = await app.push_screen_wait(CommandPalette(COMMANDS))
        app.run_worker(grab())
        await pilot.pause()
        # filter to a takes_args command (model reasoning set)
        for ch in "modelreasoningset":
            await pilot.press(ch)
        await pilot.pause()
        await pilot.press("enter")                     # enters ARG mode (does not dismiss yet)
        await pilot.pause()
        from textual.widgets import Input
        inp = app.screen.query_one(Input)
        assert "model reasoning set" in inp.placeholder  # usage hint shown
        for ch in "GLM-5.2 high":
            await pilot.press(ch if ch != " " else "space")
        await pilot.press("enter")                     # submit args -> dismiss
        await pilot.pause()
        label, argv = captured["choice"]
        assert argv == ["model", "reasoning", "set", "GLM-5.2", "high"]

@pytest.mark.asyncio
async def test_palette_escape_cancels():
    from fabric_dash.palette import CommandPalette
    from fabric_dash.commands import COMMANDS
    captured = {}
    app = FabricApp(client=make_client())
    async with app.run_test() as pilot:
        await pilot.pause()
        async def grab():
            captured["choice"] = await app.push_screen_wait(CommandPalette(COMMANDS))
        app.run_worker(grab())
        await pilot.pause()
        await pilot.press("escape")
        await pilot.pause()
        assert captured["choice"] is None
```

- [ ] **Step 2: Run to verify failure**

Run: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/test_app.py -k palette -q`
Expected: FAIL — `fabric_dash.palette` does not exist.

- [ ] **Step 3: Implement `palette.py`**:

```python
"""`:` / ctrl+p command palette — fuzzy-search the curated registry, supply
free-text args with a usage hint, return the resolved argv. Execution (gate +
run) is the app's job via _run_argv — the palette only SELECTS."""
from __future__ import annotations
from textual import on
from textual.app import ComposeResult
from textual.containers import Vertical
from textual.screen import ModalScreen
from textual.widgets import Input, ListView, ListItem, Label

from .commands import COMMANDS, Command, filter_commands, resolve_argv


class CommandPalette(ModalScreen):
    BINDINGS = [("escape", "cancel", "Cancel"), ("down", "cursor_down", ""), ("up", "cursor_up", "")]

    def __init__(self, commands: list[Command] | None = None) -> None:
        super().__init__()
        self._commands = commands if commands is not None else COMMANDS
        self._mode = "filter"
        self._chosen: Command | None = None

    def compose(self) -> ComposeResult:
        with Vertical(id="palette-box"):
            yield Input(placeholder="filter commands…  (enter to run, esc to close)", id="palette-input")
            yield ListView(id="palette-list")

    def on_mount(self) -> None:
        self._repopulate(self._commands)
        self.query_one("#palette-input", Input).focus()

    def _repopulate(self, commands: list[Command]) -> None:
        lv = self.query_one("#palette-list", ListView)
        lv.clear()
        for c in commands:
            lv.append(ListItem(Label(f"{c.label}   [dim]{c.group}[/]"), name=" ".join(c.argv)))
        if commands:
            lv.index = 0

    def _current(self) -> Command | None:
        """The command for the highlighted list row (filter mode)."""
        lv = self.query_one("#palette-list", ListView)
        if lv.index is None:
            return None
        visible = filter_commands(self._commands, self.query_one("#palette-input", Input).value)
        if 0 <= lv.index < len(visible):
            return visible[lv.index]
        return None

    @on(Input.Changed, "#palette-input")
    def _on_filter(self, event: Input.Changed) -> None:
        if self._mode == "filter":
            self._repopulate(filter_commands(self._commands, event.value))

    def action_cursor_down(self) -> None:
        if self._mode == "filter":
            self.query_one("#palette-list", ListView).action_cursor_down()

    def action_cursor_up(self) -> None:
        if self._mode == "filter":
            self.query_one("#palette-list", ListView).action_cursor_up()

    @on(Input.Submitted, "#palette-input")
    def _on_submit(self, event: Input.Submitted) -> None:
        inp = self.query_one("#palette-input", Input)
        if self._mode == "filter":
            cmd = self._current()
            if cmd is None:
                return
            if cmd.takes_args:
                self._chosen = cmd
                self._mode = "args"
                self.query_one("#palette-list", ListView).display = False
                inp.value = ""
                inp.placeholder = cmd.usage
                return
            self.dismiss((cmd.label, resolve_argv(cmd, "")))
        else:  # args mode
            cmd = self._chosen
            assert cmd is not None
            self.dismiss((cmd.label, resolve_argv(cmd, inp.value)))

    @on(ListView.Selected, "#palette-list")
    def _on_list_select(self, event: ListView.Selected) -> None:
        # Enter on a focused list row routes through the same submit logic.
        self._on_submit(None)  # type: ignore[arg-type]

    def action_cancel(self) -> None:
        self.dismiss(None)
```

> Note: Textual 8.2.7 specifics to VERIFY and adapt: `ListView.append/clear/index`, `ListItem(name=…)`, the `@on(...)` decorator + message classes (`Input.Changed`, `Input.Submitted`, `ListView.Selected`), and `action_cursor_down/up` on `ListView`. If `_on_list_select` calling `_on_submit(None)` is awkward, factor the submit body into a private `_choose()` method both call. The REQUIREMENT is the behavior the three tests pin: filter, no-arg select → dismiss argv; takes_args select → arg mode with `usage` placeholder → submit → dismiss split argv; escape → dismiss None.

- [ ] **Step 4: Style the palette in `app.tcss`** — append (mirror the ConfirmModal/HelpOverlay pattern):

```css
CommandPalette { align: center middle; background: $background 60%; }
#palette-box { width: 70; height: auto; max-height: 80%; padding: 1 2; background: $surface; border: round $primary; }
#palette-input { margin-bottom: 1; }
#palette-list { height: auto; max-height: 16; }
```

- [ ] **Step 5: Run tests to verify pass**

Run: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/test_app.py -k palette -q`
Expected: PASS (3 palette tests). Then run the full suite to confirm no regression.

- [ ] **Step 6: Commit**

```bash
git add config/ai-litellm/fabric_dash/palette.py config/ai-litellm/fabric_dash/app.tcss config/ai-litellm/fabric_dash/tests/test_app.py
git commit -m "feat(dash): CommandPalette modal (filter, arg-mode usage hint, shlex)"
```

---

## Task 4: Wire `:` / `ctrl+p` → palette → gated execution

**Files:**
- Modify: `config/ai-litellm/fabric_dash/app.py` (BINDINGS, `ENABLE_COMMAND_PALETTE`, `action_palette`)
- Test: `config/ai-litellm/fabric_dash/tests/test_app.py`

**Interfaces:**
- Consumes: `CommandPalette` (Task 3), `_run_argv` (Task 2), `push_screen_wait`.
- Produces: `action_palette` (a `@work` worker) that opens the palette, then runs the chosen argv through the shared gated `_run_argv`.

`ctrl+p` is Textual's DEFAULT command-palette binding, so we MUST disable the built-in (`ENABLE_COMMAND_PALETTE = False`) before binding our own, or the built-in steals the key.

- [ ] **Step 1: Write the failing tests** — append to `tests/test_app.py`:

```python
@pytest.mark.asyncio
async def test_colon_opens_palette():
    app = FabricApp(client=make_client())
    async with app.run_test() as pilot:
        await pilot.pause()
        await pilot.press("colon")          # ":" opens the palette
        await pilot.pause()
        from fabric_dash.palette import CommandPalette
        assert isinstance(app.screen, CommandPalette)

@pytest.mark.asyncio
async def test_palette_runs_safe_command_without_modal():
    calls = []
    def spawn(argv):
        calls.append(argv); return (0, ["ok"])
    from fabric_dash.actions import ActionRunner
    app = FabricApp(client=make_client(), runner=ActionRunner(spawn=spawn))
    async with app.run_test() as pilot:
        await pilot.pause()
        await pilot.press("colon"); await pilot.pause()
        for ch in "start":                  # filter -> "start proxy" (SAFE)
            await pilot.press(ch)
        await pilot.press("enter"); await pilot.pause()  # select+run, no modal
        assert calls and calls[0] == ["ai-litellm", "proxy", "start"]

@pytest.mark.asyncio
async def test_palette_restart_command_goes_through_confirm_modal():
    calls = []
    def spawn(argv):
        calls.append(argv); return (0, [])
    from fabric_dash.actions import ActionRunner
    app = FabricApp(client=make_client(), runner=ActionRunner(spawn=spawn))
    async with app.run_test() as pilot:
        await pilot.pause()
        await pilot.press("colon"); await pilot.pause()
        for ch in "restart":
            await pilot.press(ch)
        await pilot.press("enter"); await pilot.pause()  # palette closes, gate opens
        from fabric_dash.modal import ConfirmModal
        assert isinstance(app.screen, ConfirmModal)
        assert calls == []                               # not run until confirmed
        await pilot.press("tab"); await pilot.press("enter"); await pilot.pause()
        assert calls and calls[0] == ["ai-litellm", "proxy", "restart"]
```

- [ ] **Step 2: Run to verify failure**

Run: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/test_app.py -k "palette or colon" -q`
Expected: FAIL — no `:` binding / `action_palette`.

- [ ] **Step 3: Wire it in `app.py`** — add the class attr + binding + action:

```python
class FabricApp(App):
    CSS_PATH = Path(__file__).parent / "app.tcss"
    TITLE = "ai-litellm fabric"
    ENABLE_COMMAND_PALETTE = False  # we bind ctrl+p to our own CommandPalette
    BINDINGS = (
        [("q", "quit", "Quit"), ("r", "refresh", "Refresh"), ("l", "launch", "Launch"),
         ("question_mark", "help", "Help"), ("colon", "palette", "Commands"), ("ctrl+p", "palette", "Commands")]
        + [(a.key, f"do_{a.key}", a.label) for a in ACTIONS]
    )
```

And the action (import `CommandPalette` lazily, mirroring `action_help`):

```python
@work
async def action_palette(self) -> None:
    from .palette import CommandPalette
    from .commands import COMMANDS
    choice = await self.push_screen_wait(CommandPalette(COMMANDS))
    if not choice:
        return
    label, argv = choice
    await self._run_argv(argv, label)
```

> Note: the key name for `:` in textual 8.2.7 may be `"colon"` — verify (as P1 verified `"question_mark"`) and use the correct name consistently in the binding and the test (`pilot.press("colon")`). Add a `?`-help entry for the palette: in `help.py`'s `_KEYS`, add `(":", "command palette")` and `("ctrl+p", "command palette")` so the new surface is discoverable (keep that list accurate — it is load-bearing per the P1 review).

- [ ] **Step 4: Run the full suite to verify pass**

Run: `cd config/ai-litellm && "$HOME/.local/share/ai-litellm-fabric/state/dash-venv/bin/python" -m pytest fabric_dash/tests/ -q`
Expected: PASS — palette/colon tests + all prior tests. (If you updated `help.py` `_KEYS`, ensure the P1 help test still passes.)

- [ ] **Step 5: Commit**

```bash
git add config/ai-litellm/fabric_dash/app.py config/ai-litellm/fabric_dash/help.py config/ai-litellm/fabric_dash/tests/test_app.py
git commit -m "feat(dash): bind : / ctrl+p to the command palette (gated via _run_argv)"
```

---

## Self-Review

**Spec coverage (§5.1, §6 P2, §12):** Task 1 = static curated registry, classify-derived grades, shlex resolve, secret/launch exclusion. Task 2 = shared gated execution core (DRY, single risk oracle). Task 3 = CommandPalette modal (fuzzy filter, no-arg select, arg mode with usage hint, cancel). Task 4 = `:`/`ctrl+p` trigger, gate via classify, results to `#results`, `?`-help discoverability, built-in palette disabled. Reads/auto-refresh/confirm-gate from P1 untouched. P3/P4 (rich guided mutations, mapping editors) explicitly out of scope.

**Placeholder scan:** The `> Note:` blocks are concrete Textual-8.2.7 verification instructions with named fallbacks (same pattern P1 used successfully), not unspecified work. Every code step has runnable code and the registry entries are verified against safety.ACTIONS + lib.zsh usage lines.

**Type consistency:** `Command(group,label,argv,takes_args,usage)` (Task 1) consumed by `filter_commands`/`resolve_argv` (Task 1) and `CommandPalette` (Task 3). `CommandPalette` dismisses `(label, argv)` consumed by `action_palette` (Task 4) → `_run_argv(argv, label)` (Task 2). `_run_argv(argv, label=None, consequence=None)` signature is consistent across Tasks 2 and 4. `classify` import added in Task 2 and used by `_run_argv`.

---

*Next in the v2 series: P3 (tuning mutations — reasoning/key set via contextual actions + modals, masked secret input) → P4a/P4b (mapping editors). See docs/superpowers/specs/2026-06-20-fabric-control-surface-v2-design.md §6.*
