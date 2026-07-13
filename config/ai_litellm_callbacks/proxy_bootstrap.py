"""Start LiteLLM only after claude-litellm's OAuth safety hooks are active.

The upstream ``litellm`` console script imports and initializes the proxy before
our configured callback package is guaranteed to load.  ChatGPT's subscription
adapter can request an interactive device code during that initialization.  A
detached proxy must never start an interactive login, so the package launches
this module instead of the upstream console script.
"""

from __future__ import annotations

import os
import sys

from ai_litellm_callbacks.oauth_guard import PATCH_ACTIVE


_CHILD_PROCESS_FLAGS = {
    "--reload",
    "--run_gunicorn",
    "--run_hypercorn",
    "--run_granian",
}


def _enforce_single_process(argv: list[str]) -> None:
    """Reject modes that re-import LiteLLM in an unpatched worker process."""
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg in _CHILD_PROCESS_FLAGS or any(
            arg.startswith(f"{flag}=") for flag in _CHILD_PROCESS_FLAGS
        ):
            raise SystemExit(
                f"claude-litellm refuses {arg.split('=', 1)[0]}: OAuth guards require the single-process proxy"
            )
        if arg in {"--num_workers", "--num-workers"}:
            if index + 1 >= len(argv) or argv[index + 1] != "1":
                raise SystemExit(
                    "claude-litellm requires --num_workers 1 so OAuth guards remain active"
                )
            index += 2
            continue
        if arg.startswith(("--num_workers=", "--num-workers=")):
            if arg.split("=", 1)[1] != "1":
                raise SystemExit(
                    "claude-litellm requires --num_workers 1 so OAuth guards remain active"
                )
        index += 1

    # LiteLLM's Click option also accepts ambient NUM_WORKERS.  Pin it before
    # importing run_server so a parent shell cannot silently spawn new workers
    # that bypass this process's monkeypatches.
    os.environ["NUM_WORKERS"] = "1"


def main() -> object:
    _enforce_single_process(sys.argv[1:])
    if PATCH_ACTIVE is not True:
        raise RuntimeError(
            "claude-litellm OAuth safety hooks are inactive; refusing to start LiteLLM"
        )

    # Import the Click command only after Authenticator.get_access_token has
    # been replaced.  The import order is the security boundary here.
    from litellm import run_server

    sys.argv[0] = "litellm"
    return run_server()


if __name__ == "__main__":
    raise SystemExit(main())
