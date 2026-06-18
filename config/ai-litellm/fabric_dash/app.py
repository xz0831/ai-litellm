"""fabric — read-only control-plane TUI over ai-litellm."""
from __future__ import annotations
from pathlib import Path
from textual.app import App, ComposeResult
from textual.containers import Horizontal
from textual.widgets import Header, Footer, Tree, Static
from .client import FabricClient

CONCEPTS = [
    ("proxy", "Proxy"),
    ("harnesses", "Harnesses"),
    ("models", "Models / Routes"),
    ("runtimes", "Runtimes"),
    ("budget", "Budget & Policy"),
    ("keys", "Keys"),
]


class FabricApp(App):
    CSS_PATH = Path(__file__).parent / "app.tcss"
    TITLE = "ai-litellm fabric"
    BINDINGS = [("q", "quit", "Quit"), ("r", "refresh", "Refresh")]

    def __init__(self, client: FabricClient | None = None):
        super().__init__()
        self.client = client or FabricClient()
        self._selected = "proxy"

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
        dot = {"ok": "[green]●[/]", "unreachable": "[red]●[/]"}.get(health, "[yellow]●[/]")
        badge = "[yellow]STALE → sync[/]" if cur == "stale" else f"[dim]{cur}[/]"
        self.query_one("#status", Static).update(f"{dot} proxy: {health}   config: {badge}   {url}")

    def show_panel(self, node_id: str) -> None:
        content = self.query_one("#content", Static)
        if node_id == "proxy":
            s = self.client.proxy_status()
            lines = [f"{k}: {v}" for k, v in s.items()] or ["proxy not running — start it"]
            content.update("\n".join(lines))
        elif node_id == "models":
            rows = self.client.model_limits() or self.client.model_list()
            content.update(_table_text(rows) or "no models / routes (is the proxy synced?)")
        elif node_id == "harnesses":
            content.update(_table_text(self.client.harness_list()) or "no harnesses")
        elif node_id == "runtimes":
            content.update(_table_text(self.client.runtime_status()) or "no runtimes")
        elif node_id == "budget":
            content.update(_table_text(self.client.reasoning_matrix()) or "no reasoning matrix")
        elif node_id == "keys":
            k = self.client.key_status()
            content.update("\n".join(f"{name}: {info.get('source','?')}" for name, info in k.items()) or "no keys")
        else:
            content.update("")


def _table_text(rows: list) -> str:
    if not rows:
        return ""
    cols = list(rows[0].keys())
    head = "  ".join(f"{c:<18}" for c in cols)
    body = "\n".join("  ".join(f"{str(r.get(c,'')):<18}" for c in cols) for r in rows)
    return head + "\n" + body
