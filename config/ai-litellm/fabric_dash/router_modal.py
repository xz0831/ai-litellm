"""Router intent form.

Collects the small set of routing knobs a human can reasonably set from the
TUI. Prompt text is returned to the caller and passed to router execute through
stdin; it is never placed in argv or the action log.
"""
from __future__ import annotations

from textual import on
from textual.app import ComposeResult
from textual.containers import Vertical
from textual.screen import ModalScreen
from textual.widgets import Input, Label, ListItem, ListView


class RouterIntentModal(ModalScreen):
    BINDINGS = [("escape", "cancel", "Cancel")]

    def __init__(
        self,
        title: str,
        *,
        require_prompt: bool = False,
        initial: dict | None = None,
    ) -> None:
        super().__init__()
        self._title = title
        self._require_prompt = require_prompt
        self._billing_modes = ["no-billable", "allow-billable"]
        self._initial = initial or {}

    def compose(self) -> ComposeResult:
        with Vertical(id="router-box"):
            yield Label(self._title, id="router-title")
            yield Input(placeholder="estimated input tokens (default 1000)", id="router-tokens")
            yield Input(placeholder="preferred harness (optional)", id="router-harness")
            yield Input(placeholder="preferred model (optional)", id="router-model")
            prompt = Input(placeholder="prompt for execute/dry-run", id="router-prompt")
            prompt.display = self._require_prompt
            yield prompt
            yield Label("billing mode", id="router-billing-title")
            yield ListView(id="router-billing")

    def on_mount(self) -> None:
        estimated = self._initial.get("estimated")
        if estimated is not None:
            self.query_one("#router-tokens", Input).value = str(estimated)
        self.query_one("#router-harness", Input).value = str(self._initial.get("preferred_harness") or "")
        self.query_one("#router-model", Input).value = str(self._initial.get("preferred_model") or "")
        billing = self.query_one("#router-billing", ListView)
        for mode in self._billing_modes:
            billing.append(ListItem(Label(mode), name=mode))
        billing.index = 1 if self._initial.get("allow_billable") else 0
        self.query_one("#router-tokens", Input).focus()

    @on(Input.Submitted)
    def _next_field(self, event: Input.Submitted) -> None:
        order = ["router-tokens", "router-harness", "router-model"]
        if self._require_prompt:
            order.append("router-prompt")
        current = event.input.id
        if current in order:
            idx = order.index(current)
            if idx + 1 < len(order):
                self.query_one(f"#{order[idx + 1]}", Input).focus()
            else:
                self.query_one("#router-billing", ListView).focus()

    @on(ListView.Selected, "#router-billing")
    def _picked(self, event: ListView.Selected) -> None:
        mode = event.item.name if event.item is not None else "no-billable"
        prompt = self.query_one("#router-prompt", Input).value.strip()
        if self._require_prompt and not prompt:
            self.query_one("#router-title", Label).update(f"{self._title} — prompt required")
            self.query_one("#router-prompt", Input).focus()
            return
        tokens_raw = self.query_one("#router-tokens", Input).value.strip()
        try:
            estimated = int(tokens_raw) if tokens_raw else 1000
        except ValueError:
            self.query_one("#router-title", Label).update(f"{self._title} — tokens must be an integer")
            self.query_one("#router-tokens", Input).focus()
            return
        if estimated < 0:
            self.query_one("#router-title", Label).update(f"{self._title} — tokens must be non-negative")
            self.query_one("#router-tokens", Input).focus()
            return
        self.dismiss({
            "estimated": estimated,
            "preferred_harness": self.query_one("#router-harness", Input).value.strip(),
            "preferred_model": self.query_one("#router-model", Input).value.strip(),
            "prompt": prompt,
            "allow_billable": mode == "allow-billable",
        })

    def action_cancel(self) -> None:
        self.dismiss(None)
