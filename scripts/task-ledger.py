#!/usr/bin/env python3
"""Private, atomic task and model-session handoff ledger."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import secrets
import stat
import sys
import tempfile
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Iterator


SCHEMA_VERSION = 1
TASK_ID = re.compile(r"[0-9]{8}T[0-9]{6}Z-[a-z0-9][a-z0-9-]{0,47}-[0-9a-f]{6}")
MAX_TEXT = 16_384
MAX_EVIDENCE = 8_192


class LedgerError(RuntimeError):
    """A task-ledger request is invalid or unsafe."""


def now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def limited(value: str | None, label: str, maximum: int = MAX_TEXT) -> str | None:
    if value is None:
        return None
    value = value.strip()
    if not value:
        raise LedgerError(f"{label} must not be empty")
    if len(value) > maximum:
        raise LedgerError(f"{label} exceeds {maximum} characters")
    return value


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return (slug[:48].rstrip("-") or "task")


def task_path(root: Path, task_id: str) -> Path:
    if not TASK_ID.fullmatch(task_id):
        raise LedgerError(f"invalid task id: {task_id}")
    return root / f"{task_id}.json"


def ensure_root(root: Path) -> None:
    if root.exists():
        info = root.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise LedgerError(f"unsafe task root: {root}")
    else:
        root.mkdir(parents=True, mode=0o700)
    os.chmod(root, 0o700)


@contextmanager
def ledger_lock(root: Path, *, exclusive: bool) -> Iterator[None]:
    ensure_root(root)
    lock_path = root / ".lock"
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(lock_path, flags, 0o600)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise LedgerError(f"unsafe task lock: {lock_path}")
        os.fchmod(descriptor, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)
        yield
    finally:
        os.close(descriptor)


def load_task(root: Path, task_id: str) -> dict[str, object]:
    path = task_path(root, task_id)
    try:
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise LedgerError(f"unsafe task file: {path}")
        if stat.S_IMODE(info.st_mode) != 0o600:
            raise LedgerError(f"unsafe task file mode (expected 600): {path}")
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise LedgerError(f"task not found: {task_id}") from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LedgerError(f"invalid task JSON: {path}") from error
    if (
        not isinstance(payload, dict)
        or payload.get("schemaVersion") != SCHEMA_VERSION
        or payload.get("id") != task_id
        or not isinstance(payload.get("handoffs"), list)
    ):
        raise LedgerError(f"invalid task schema: {path}")
    return payload


def write_task(root: Path, payload: dict[str, object], *, create: bool = False) -> None:
    task_id = str(payload["id"])
    path = task_path(root, task_id)
    if create and path.exists():
        raise LedgerError(f"task already exists: {task_id}")
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode()
    descriptor, temporary_name = tempfile.mkstemp(prefix=".task.", dir=root)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        temporary.unlink(missing_ok=True)


def handoff_by_index(task: dict[str, object], requested: str) -> dict[str, object]:
    handoffs = task["handoffs"]
    assert isinstance(handoffs, list)
    if not handoffs:
        raise LedgerError("task has no handoff; add one before launching")
    if requested == "latest":
        item = handoffs[-1]
    else:
        try:
            index = int(requested)
        except ValueError as error:
            raise LedgerError("handoff must be 'latest' or a positive integer") from error
        if index < 1 or index > len(handoffs):
            raise LedgerError(f"handoff does not exist: {requested}")
        item = handoffs[index - 1]
    if not isinstance(item, dict):
        raise LedgerError("invalid handoff record")
    return item


def prompt_for(task: dict[str, object], handoff: dict[str, object]) -> str:
    evidence: list[str] = []
    if handoff.get("commit"):
        evidence.append(f"- Commit/base: {handoff['commit']}")
    if handoff.get("tests"):
        evidence.append(f"- Test evidence: {handoff['tests']}")
    evidence_text = "\n".join(evidence) if evidence else "- No commit or test evidence recorded."
    from_route = handoff.get("fromRoute") or "unassigned/initial"
    summary = handoff.get("summary") or "No prior-session summary was supplied."
    return f"""You are worker session {handoff['index']} for claude-litellm task {task['id']}.

Task goal:
{task['goal']}

Worktree:
{task['worktree']}

Model-session handoff:
- From route: {from_route}
- To route: {handoff['toRoute']}
- Objective: {handoff['objective']}

Prior decisions and context:
{summary}

Recorded evidence:
{evidence_text}

Working contract:
1. Work only on the objective above and inspect the current worktree before changing it.
2. Preserve unrelated user changes and treat the worktree, commit, and tests as source of truth.
3. Do not assume the previous model transcript or token budget is available.
4. Before exiting, report Outcome, Changes, Tests, Risks, and Recommended next handoff.
"""


def emit(payload: object, *, as_json: bool) -> None:
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    elif isinstance(payload, str):
        print(payload)
    else:
        print(json.dumps(payload, ensure_ascii=False, indent=2))


def command_create(args: argparse.Namespace, root: Path) -> None:
    title = limited(args.name, "name", 256)
    goal = limited(args.goal, "goal")
    assert title is not None and goal is not None
    worktree = Path(args.worktree).expanduser().resolve()
    if not worktree.is_dir():
        raise LedgerError(f"worktree is not a directory: {worktree}")
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    task_id = f"{stamp}-{slugify(title)}-{secrets.token_hex(3)}"
    timestamp = now()
    payload: dict[str, object] = {
        "schemaVersion": SCHEMA_VERSION,
        "id": task_id,
        "name": title,
        "goal": goal,
        "worktree": str(worktree),
        "status": "active",
        "createdAt": timestamp,
        "updatedAt": timestamp,
        "closedSummary": None,
        "handoffs": [],
    }
    with ledger_lock(root, exclusive=True):
        write_task(root, payload, create=True)
    emit(payload if args.json else task_id, as_json=args.json)


def command_list(args: argparse.Namespace, root: Path) -> None:
    rows: list[dict[str, object]] = []
    with ledger_lock(root, exclusive=False):
        for path in sorted(root.glob("*.json")):
            if path.name.startswith("."):
                continue
            task_id = path.stem
            if not TASK_ID.fullmatch(task_id):
                continue
            task = load_task(root, task_id)
            rows.append(
                {
                    "id": task["id"],
                    "name": task["name"],
                    "status": task["status"],
                    "worktree": task["worktree"],
                    "handoffs": len(task["handoffs"]),
                    "updatedAt": task["updatedAt"],
                }
            )
    rows.sort(key=lambda row: str(row["updatedAt"]), reverse=True)
    if args.json:
        emit(rows, as_json=True)
        return
    if not rows:
        print("No claude-litellm tasks.")
        return
    for row in rows:
        print(
            f"{row['id']}  {row['status']:<9}  handoffs={row['handoffs']}  "
            f"{row['name']}"
        )


def command_show(args: argparse.Namespace, root: Path) -> None:
    with ledger_lock(root, exclusive=False):
        task = load_task(root, args.task_id)
    emit(task, as_json=args.json)


def command_handoff(args: argparse.Namespace, root: Path) -> None:
    to_route = limited(args.to, "to route", 256)
    from_route = limited(args.from_route, "from route", 256)
    objective = limited(args.objective, "objective")
    summary = limited(args.summary, "summary")
    commit = limited(args.commit, "commit", 512)
    tests = limited(args.tests, "tests", MAX_EVIDENCE)
    assert to_route is not None and objective is not None
    with ledger_lock(root, exclusive=True):
        task = load_task(root, args.task_id)
        if task["status"] != "active":
            raise LedgerError("cannot add a handoff to a closed task")
        handoffs = task["handoffs"]
        assert isinstance(handoffs, list)
        timestamp = now()
        handoff: dict[str, object] = {
            "index": len(handoffs) + 1,
            "fromRoute": from_route,
            "toRoute": to_route,
            "objective": objective,
            "summary": summary,
            "commit": commit,
            "tests": tests,
            "status": "pending",
            "createdAt": timestamp,
            "launchedAt": None,
            "completedAt": None,
            "resultSummary": None,
        }
        handoffs.append(handoff)
        task["updatedAt"] = timestamp
        write_task(root, task)
    emit(handoff if args.json else f"{args.task_id} handoff {handoff['index']} -> {to_route}", as_json=args.json)


def command_complete(args: argparse.Namespace, root: Path) -> None:
    summary = limited(args.summary, "summary")
    commit = limited(args.commit, "commit", 512)
    tests = limited(args.tests, "tests", MAX_EVIDENCE)
    assert summary is not None
    with ledger_lock(root, exclusive=True):
        task = load_task(root, args.task_id)
        handoff = handoff_by_index(task, args.handoff)
        timestamp = now()
        handoff["status"] = "completed"
        handoff["completedAt"] = timestamp
        handoff["resultSummary"] = summary
        if commit is not None:
            handoff["resultCommit"] = commit
        if tests is not None:
            handoff["resultTests"] = tests
        if args.close:
            task["status"] = "completed"
            task["closedSummary"] = summary
        task["updatedAt"] = timestamp
        write_task(root, task)
    emit(task if args.json else f"{args.task_id} handoff {handoff['index']} completed", as_json=args.json)


def command_prompt(args: argparse.Namespace, root: Path) -> None:
    with ledger_lock(root, exclusive=False):
        task = load_task(root, args.task_id)
        handoff = handoff_by_index(task, args.handoff)
        prompt = prompt_for(task, handoff)
    if args.json:
        emit(
            {
                "taskId": task["id"],
                "handoff": handoff["index"],
                "route": handoff["toRoute"],
                "worktree": task["worktree"],
                "prompt": prompt,
            },
            as_json=True,
        )
    else:
        print(prompt, end="")


def command_mark_launched(args: argparse.Namespace, root: Path) -> None:
    with ledger_lock(root, exclusive=True):
        task = load_task(root, args.task_id)
        handoff = handoff_by_index(task, args.handoff)
        timestamp = now()
        handoff["status"] = "launched"
        handoff["launchedAt"] = timestamp
        task["updatedAt"] = timestamp
        write_task(root, task)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, help=argparse.SUPPRESS)
    commands = parser.add_subparsers(dest="command", required=True)

    create = commands.add_parser("create", help="create a durable task")
    create.add_argument("name")
    create.add_argument("--goal", required=True)
    create.add_argument("--worktree", default=os.getcwd())
    create.add_argument("--json", action="store_true")
    create.set_defaults(func=command_create)

    list_command = commands.add_parser("list", help="list tasks")
    list_command.add_argument("--json", action="store_true")
    list_command.set_defaults(func=command_list)

    show = commands.add_parser("show", help="show one task")
    show.add_argument("task_id")
    show.add_argument("--json", action="store_true")
    show.set_defaults(func=command_show)

    handoff = commands.add_parser("handoff", help="record a model-session handoff")
    handoff.add_argument("task_id")
    handoff.add_argument("--to", required=True)
    handoff.add_argument("--from", dest="from_route")
    handoff.add_argument("--objective", required=True)
    handoff.add_argument("--summary")
    handoff.add_argument("--commit")
    handoff.add_argument("--tests")
    handoff.add_argument("--json", action="store_true")
    handoff.set_defaults(func=command_handoff)

    complete = commands.add_parser("complete", help="record a worker result")
    complete.add_argument("task_id")
    complete.add_argument("--handoff", default="latest")
    complete.add_argument("--summary", required=True)
    complete.add_argument("--commit")
    complete.add_argument("--tests")
    complete.add_argument("--close", action="store_true")
    complete.add_argument("--json", action="store_true")
    complete.set_defaults(func=command_complete)

    prompt = commands.add_parser("prompt", help="render a bounded handoff prompt")
    prompt.add_argument("task_id")
    prompt.add_argument("--handoff", default="latest")
    prompt.add_argument("--json", action="store_true")
    prompt.set_defaults(func=command_prompt)

    launched = commands.add_parser("_mark-launched", help=argparse.SUPPRESS)
    launched.add_argument("task_id")
    launched.add_argument("--handoff", default="latest")
    launched.set_defaults(func=command_mark_launched)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        args.func(args, Path(args.root).expanduser())
    except (LedgerError, OSError) as error:
        print(f"claude-litellm task: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
