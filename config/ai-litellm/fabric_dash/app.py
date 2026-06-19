"""fabric — read-only control-plane TUI over ai-litellm."""
from __future__ import annotations
from pathlib import Path
from rich.text import Text
from textual.app import App, ComposeResult
from textual.containers import Horizontal
from textual.widgets import Header, Footer, Tree, Static, RichLog, DataTable
from textual import work
from .client import FabricClient
from .safety import ACTIONS
from .actions import ActionRunner
from .modal import ConfirmModal

CONCEPTS = [
    ("proxy", "Proxy"),
    ("harnesses", "Harnesses"),
    ("models", "Models / Routes"),
    ("runtimes", "Runtimes"),
    ("budget", "Budget & Policy"),
    ("keys", "Keys"),
]

# Friendly labels for raw --json dict keys, so panels don't read as a wall of
# camelCase. Unmapped keys fall back to a title-cased version of the key.
COLUMN_LABELS = {
    "name": "Name",
    "model": "Model",
    "backend": "Backend",
    "adapter": "Adapter",
    "valid": "Valid",
    "cliInstalled": "CLI",
    "tpm": "TPM",
    "rpm": "RPM",
    "maxOut": "Max Out",
    "maxIn": "Max In",
    "source": "Source",
}


def _label(key: str) -> str:
    return COLUMN_LABELS.get(key, key[:1].upper() + key[1:])


# Status color system (mirrors app.tcss .ok/.warn/.bad → $success/$warning/$error).
# Load-bearing: readiness columns must signal danger before a billable launch.
_OK = "green"
_BAD = "red"
# Columns whose truthiness is a readiness signal: False → red, True → green.
_BOOL_READY_KEYS = {"valid", "cliInstalled"}
# Key-status sources that mean "this key is not usable" → red.
_BAD_SOURCES = {"missing", "unset", "none", ""}


def _cell(key: str, value) -> Text:
    """Render one table cell, coloring readiness signals per the status system."""
    if key in _BOOL_READY_KEYS or isinstance(value, bool):
        truthy = value is True or str(value).strip().lower() in ("true", "yes", "1")
        return Text("✓" if truthy else "✗", style=_OK if truthy else _BAD)
    text = "" if value is None else str(value)
    if key == "source" and text.strip().lower() in _BAD_SOURCES:
        return Text(text, style=_BAD)
    return Text(text)


class FabricApp(App):
    CSS_PATH = Path(__file__).parent / "app.tcss"
    TITLE = "ai-litellm fabric"
    BINDINGS = (
        [("q", "quit", "Quit"), ("r", "refresh", "Refresh"), ("l", "launch", "Launch")]
        + [(a.key, f"do_{a.key}", a.label) for a in ACTIONS]
    )

    def __init__(self, client: FabricClient | None = None, runner: ActionRunner | None = None):
        super().__init__()
        self.client = client or FabricClient()
        self.runner = runner or ActionRunner()
        self._selected = "proxy"
        self._selected_harness: str | None = None

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static("", id="status")
        with Horizontal(id="body"):
            tree: Tree = Tree("Concepts", id="concepts")
            tree.show_root = False
            for node_id, label in CONCEPTS:
                tree.root.add_leaf(label, data=node_id)
            yield tree
            yield Static("", id="content")
            # One reusable table for every wide tabular view (harnesses, models,
            # runtimes, budget). DataTable sizes columns to content and scrolls,
            # so rows never wrap the way fixed-width text columns did.
            table: DataTable = DataTable(id="data-table", cursor_type="row", zebra_stripes=True)
            table.display = False  # shown only on tabular panels
            yield table
        yield RichLog(id="results", highlight=False, markup=True)
        yield Footer()

    def on_mount(self) -> None:
        self.refresh_status()
        self.show_panel("proxy")
        self.set_interval(4.0, self.refresh_status)  # safe/read-only auto-refresh only

    def on_tree_node_selected(self, event: Tree.NodeSelected) -> None:
        node_id = event.node.data
        if node_id:
            self._selected = node_id
            self.show_panel(node_id)

    def action_refresh(self) -> None:
        self.refresh_status()
        self.show_panel(self._selected)

    def refresh_status(self) -> None:
        s = self.client.proxy_status()
        health = s.get("health", "unknown")
        cur = s.get("configCurrency", "unknown")
        url = s.get("baseUrl", "")
        dot = {"ok": "[green]o[/]", "unreachable": "[red]x[/]"}.get(health, "[yellow]?[/]")
        badge = "[yellow]STALE -> sync[/]" if cur == "stale" else f"[dim]{cur}[/]"
        target = self._selected_harness or "select a harness"
        launch = f"[dim]launch ->[/] {target}"
        self.query_one("#status", Static).update(
            f"{dot} proxy: {health}   config: {badge}   {launch}   [dim]{url}[/]"
        )

    # Panels that render as a wide table; empty-state message shown otherwise.
    _EMPTY = {
        "harnesses": "no harnesses",
        "models": "no models / routes (is the proxy synced?)",
        "runtimes": "no runtimes",
        "budget": "no reasoning matrix",
    }

    def show_panel(self, node_id: str) -> None:
        content = self.query_one("#content", Static)
        table = self.query_one("#data-table", DataTable)
        # Default: text panel visible, table hidden.
        content.display = True
        table.display = False
        if node_id == "proxy":
            s = self.client.proxy_status()
            lines = [f"{_label(k)}: {v}" for k, v in s.items()] or ["proxy not running — start it"]
            content.update("\n".join(lines))
        elif node_id == "keys":
            content.update(self._keys_text() or "no keys")
        elif node_id in self._EMPTY:
            rows = self._panel_rows(node_id)
            if rows:
                self._fill_table(table, rows, select=(node_id == "harnesses"))
                content.display = False
                table.display = True
            else:
                if node_id == "harnesses":
                    self._selected_harness = None
                content.update(self._EMPTY[node_id])
        else:
            content.update("")

    def _panel_rows(self, node_id: str) -> list:
        if node_id == "harnesses":
            return self.client.harness_list()
        if node_id == "models":
            return self.client.model_limits() or self.client.model_list()
        if node_id == "runtimes":
            return self.client.runtime_status()
        if node_id == "budget":
            return self.client.reasoning_matrix()
        return []

    def _keys_text(self) -> Text:
        """Key status as colored lines: missing/unset keys render red (load-bearing)."""
        out = Text()
        for i, (name, info) in enumerate(self.client.key_status().items()):
            src = str(info.get("source", "?"))
            bad = src.strip().lower() in _BAD_SOURCES
            if i:
                out.append("\n")
            out.append(f"{name}: ")
            out.append(src, style=_BAD if bad else _OK)
        return out

    def _fill_table(self, table: DataTable, rows: list, *, select: bool) -> None:
        """Render rows into the shared DataTable with status-colored cells.

        When ``select`` is set, the first row seeds the launch target so 'l'
        always has a real harness to hand off to.
        """
        table.clear(columns=True)
        if not rows:
            return
        cols = list(rows[0].keys())
        for c in cols:
            table.add_column(_label(c), key=c)
        for r in rows:
            table.add_row(*[_cell(c, r.get(c)) for c in cols], key=str(r.get("name", "")))
        if select and self._selected_harness is None:
            self._selected_harness = str(rows[0].get("name", "")) or None
            self.refresh_status()

    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        # Only the Harnesses panel drives the launch target.
        if (
            event.data_table.id == "data-table"
            and self._selected == "harnesses"
            and event.row_key is not None
        ):
            self._selected_harness = str(event.row_key.value)
            self.refresh_status()

    # --- action helpers ---

    def _action_by_key(self, key: str):
        for a in ACTIONS:
            if a.key == key:
                return a
        return None

    @work
    async def _run_action(self, key: str) -> None:
        """Run an action; @work provides the worker context needed by push_screen_wait."""
        a = self._action_by_key(key)
        if a is None:
            return
        if a.needs_confirm:
            ok = await self.push_screen_wait(
                ConfirmModal(a.consequence, title=f"Confirm {a.label}", grade=a.grade)
            )
            if not ok:
                self.query_one("#results", RichLog).write(f"[dim]cancelled: {a.label}[/]")
                return
        log = self.query_one("#results", RichLog)
        log.write(f"$ ai-litellm {' '.join(a.argv)}")
        rc = self.runner.run(list(a.argv), on_line=lambda ln: log.write(ln))
        log.write(f"[{'green' if rc == 0 else 'red'}]exit {rc}[/]")
        self.refresh_status()

    # Per-key action methods (explicit, not metaprogrammed); @work makes _run_action sync-callable
    def action_do_s(self) -> None: self._run_action("s")
    def action_do_R(self) -> None: self._run_action("R")
    def action_do_S(self) -> None: self._run_action("S")
    def action_do_x(self) -> None: self._run_action("x")
    def action_do_d(self) -> None: self._run_action("d")

    @work
    async def action_launch(self) -> None:
        harness = self._selected_harness
        if not harness:
            self.query_one("#results", RichLog).write(
                "[yellow]no harness selected — open the Harnesses panel and pick one[/]"
            )
            return
        ok = await self.push_screen_wait(
            ConfirmModal(
                f"launch {harness}: cloud-backed tiers make billable provider requests.",
                title=f"Confirm launch -> {harness}",
                grade="billable",
            )
        )
        if not ok:
            return
        self.exit(result=("launch", [harness]))
