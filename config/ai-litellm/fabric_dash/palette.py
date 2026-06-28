"""`:` command palette — fuzzy-search the curated registry, supply
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
            yield Input(placeholder="filter commands…  (enter to select, esc to close)", id="palette-input")
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
        inp = self.query_one("#palette-input", Input)
        visible = filter_commands(self._commands, inp.value)
        if 0 <= lv.index < len(visible):
            return visible[lv.index]
        return None

    def _choose(self) -> None:
        """Shared submit logic called from both Input.Submitted and ListView.Selected."""
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
        self._choose()

    @on(ListView.Selected, "#palette-list")
    def _on_list_select(self, event: ListView.Selected) -> None:
        # Enter on a focused list row routes through the same submit logic.
        self._choose()

    def action_cancel(self) -> None:
        self.dismiss(None)
