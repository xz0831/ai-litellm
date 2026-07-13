#!/usr/bin/env python3
"""Differential test for the four token-budget implementations.

There are four independent copies of the output-reservation / token-budget math
in this repo. Three compute an *effectiveInput* (usable input budget); one
(Python) computes an *outputCap* (max output tokens). They MUST stay in
lockstep on the quantities that are comparable:

  1. Node      ai_litellm_harness_output_budget  (lib.zsh node -e block)   -> effectiveInput
  2. Ruby-mat  output_budget                      (lib.zsh ruby matrix)     -> effectiveInput
  3. Python    gateway_output_cap                 (output_clamp.py)         -> outputCap
  4. Ruby-res  output_budget                      (lib.zsh harness-         -> effectiveInput
               (ai_litellm_context_harness_reservations_ok ruby block)

This harness feeds one input matrix to ALL FOUR and asserts the comparable
fields are IDENTICAL. It is the real guard; check.zsh runs it in CI.

Anti-drift: the three lib.zsh copies are NOT pasted here. They are extracted
from lib.zsh at runtime using their unique function boundaries and executed
live, so ordinary insertions elsewhere in the library cannot stale numeric
line ranges. If a function is renamed or refactored, the boundary/needle guards
fail loudly rather than silently testing a stale copy.

Run:  python3 scripts/verify_budget_consistency.py
Exit: 0 = all four agree across the matrix; 1 = drift (a real latent bug) or
      an implementation could not be driven.
"""
from __future__ import annotations

import json
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / "config" / "ai-litellm" / "lib.zsh"
PY_PKG = REPO / "config"

# =============================================================================
# 1. ORACLE  -- the canonical spec both families derive from.
# =============================================================================
def posint(value: Any) -> int | None:
    """Mirror the loose Number()/to_i/int() coercion in the implementations.

    Non-finite and non-positive values resolve to ``None``.
    """
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(n) or n <= 0:
        return None
    return int(math.floor(n))


def canonical_budget(
    context_in: Any,
    capability_in: Any,
    *,
    default: int | None = 32000,
    tokenizer_headroom: Any = 8192,
    minimum_input: Any = 32768,
    per_selection: int | None = None,
    per_tier: int | None = None,
    per_model: int | None = None,
) -> dict[str, Any]:
    """The reference effectiveInput computation (Node and the two Ruby copies)."""
    context = posint(context_in)
    capability = posint(capability_in)
    cfg_headroom = posint(tokenizer_headroom)
    cfg_headroom = 0 if cfg_headroom is None else cfg_headroom
    cfg_min_input = posint(minimum_input)
    cfg_min_input = 32768 if cfg_min_input is None else cfg_min_input

    chosen = None
    for cand in (per_selection, per_tier, per_model, default):
        n = posint(cand)
        if n is not None:
            chosen = n
            break

    if chosen is None:
        if capability is None:
            return {"sentinel": "no-reservation", "context": context,
                    "capability": capability, "effectiveInput": None}
        reservation = min(capability, 32000)
    else:
        reservation = chosen

    if capability is not None and reservation > capability:
        reservation = capability

    headroom = cfg_headroom
    min_input = cfg_min_input
    if context is not None:
        headroom = min(headroom, math.floor(context * 0.1))
        min_input = min(min_input, max(1, math.floor(context * 0.5)))
        max_reservation = context - headroom - min_input
        if max_reservation < 1:
            reservation = 1
            headroom = max(0, context - min_input - reservation)
        elif reservation > max_reservation:
            reservation = max_reservation

    effective_input = None if context is None else max(0, context - reservation - headroom)
    return {
        "sentinel": None,
        "context": context,
        "capability": capability,
        "reservation": reservation,
        "tokenizerHeadroom": headroom,
        "minimumInput": min_input,
        "effectiveInput": effective_input,
    }


def canonical_output_cap(
    context_in: Any,
    capability_in: Any,
    *,
    default: int = 32000,
    per_model: int | None = None,
    tokenizer_headroom: Any = 8192,
    minimum_input: Any = 32768,
) -> int:
    """The reference Python outputCap computation (gateway_output_cap)."""
    cap = posint(per_model) or posint(default) or 32000
    capability = posint(capability_in)
    if capability is not None:
        cap = min(cap, capability)
    context = posint(context_in)
    if context is not None:
        headroom = posint(tokenizer_headroom) or 0
        headroom = min(headroom, math.floor(context * 0.1))
        min_input = posint(minimum_input) or 32768
        min_input = min(min_input, max(1, math.floor(context * 0.5)))
        max_reservation = context - headroom - min_input
        cap = min(cap, max_reservation if max_reservation > 0 else 1)
    return max(1, cap)


# =============================================================================
# 2. DRIVERS  -- invoke the four real implementations.
# =============================================================================
_LIB_TEXT = LIB.read_text(encoding="utf-8")


def _between(start: str, end: str, *, search_from: int = 0) -> str:
    start_at = _LIB_TEXT.find(start, search_from)
    if start_at < 0:
        raise RuntimeError(f"lib.zsh extraction marker missing: {start!r}")
    body_at = start_at + len(start)
    end_at = _LIB_TEXT.find(end, body_at)
    if end_at < 0:
        raise RuntimeError(f"lib.zsh extraction marker missing after {start!r}: {end!r}")
    return _LIB_TEXT[body_at:end_at]


_node_function = "ai_litellm_harness_output_budget()"
_node_at = _LIB_TEXT.find(_node_function)
if _node_at < 0:
    raise RuntimeError(f"lib.zsh extraction marker missing: {_node_function!r}")
_NODE_BODY = _between(
    "  node -e '\n",
    "\n' \"$descriptor\" \"$selection\" \"$model_name\" \"$limits\"",
    search_from=_node_at,
)

_mat_signature = "def output_budget(descriptor, selection, model, ctx, out)"
_mat_at = _LIB_TEXT.find(_mat_signature)
if _mat_at < 0:
    raise RuntimeError(f"lib.zsh extraction marker missing: {_mat_signature!r}")
_mat_start = _LIB_TEXT.rfind("def positive_int(value)", 0, _mat_at)
if _mat_start < 0:
    raise RuntimeError("lib.zsh Ruby matrix positive_int marker missing")
_RUBY_MAT_BODY = _LIB_TEXT[_mat_start:_LIB_TEXT.find("\n\ndef model_limit_confidence", _mat_at)]

_res_signature = "def output_budget(policy, selection, model, ctx, out)"
_res_at = _LIB_TEXT.find(_res_signature)
if _res_at < 0:
    raise RuntimeError(f"lib.zsh extraction marker missing: {_res_signature!r}")
_res_start = _LIB_TEXT.rfind("def positive_int(value)", 0, _res_at)
if _res_start < 0:
    raise RuntimeError("lib.zsh reservation positive_int marker missing")
_RUBY_RES_BODY = _LIB_TEXT[_res_start:_LIB_TEXT.find("\n\nerrors = []", _res_at)]

# Sanity: the extracted slices must define the functions we expect. If lib.zsh is
# refactored and the ranges go stale, fail loudly here -- never test a wrong slice.
_SLICE_GUARDS = [
    ("NODE", _NODE_BODY, ["const positiveInt", "effectiveInput", "console.log"]),
    ("RUBY_MAT", _RUBY_MAT_BODY, ["def positive_int", "def output_budget"]),
    # The 4th implementation: its output_budget signature is (policy, selection, model, ctx,
    # out) -- it takes the resolved POLICY, not the descriptor -- and it returns
    # the comparable budget under the :effective key (not :effective_input). The
    # capability-clamped-default fallback is the load-bearing line we guard on.
    ("RUBY_RES", _RUBY_RES_BODY, [
        "def positive_int", "def output_budget(policy, selection, model, ctx, out)",
        "[capability, 32000].compact.min", "effective = context ?",
    ]),
]


def _check_slices() -> list[str]:
    errs = []
    for name, body, needles in _SLICE_GUARDS:
        for needle in needles:
            if needle not in body:
                errs.append(f"lib.zsh extraction {name} is stale: missing {needle!r} "
                            f"(update semantic markers in {Path(__file__).name})")
    return errs


def policy_descriptor_json(policy: dict[str, Any]) -> str:
    return json.dumps({"adapterConfig": {"outputReservation": policy}})


def build_policy(default=32000, headroom=8192, min_input=32768,
                 per_selection=None, per_tier=None, per_model=None,
                 selection=None, model=None, empty=False,
                 no_default=False) -> dict[str, Any]:
    """no_default omits the ``default`` reservation key (and any perX) while
    keeping tokenizerHeadroom/minimumInput, so the policy is non-empty but NO
    reservation source resolves -- forcing the capability-clamped-default
    fallback (reservation = min(capability, 32000)) when a capability exists,
    or the no-reservation sentinel when it doesn't."""
    if empty:
        return {}
    p: dict[str, Any] = {}
    if default is not None and not no_default:
        p["default"] = default
    if headroom is not None:
        p["tokenizerHeadroom"] = headroom
    if min_input is not None:
        p["minimumInput"] = min_input
    if per_selection is not None and selection is not None:
        p["perSelection"] = {selection: per_selection}
    if per_tier is not None and selection is not None:
        p["perTier"] = {selection: per_tier}
    if per_model is not None and model is not None:
        p["perModel"] = {model: per_model}
    return p


def drive_node(policy: dict, selection: str, model: str,
               context: Any, capability: Any) -> dict[str, Any]:
    """Run the verbatim node -e block with its 4 argv. limits omits 'output'
    when capability is None (capability=null path)."""
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        f.write(policy_descriptor_json(policy))
        descriptor = f.name
    try:
        limits: dict[str, Any] = {}
        if context is not None:
            limits["context"] = context
        if capability is not None:
            limits["output"] = capability
        proc = subprocess.run(
            ["node", "-e", _NODE_BODY, descriptor, selection, model, json.dumps(limits)],
            capture_output=True, text=True,
        )
    finally:
        os.unlink(descriptor)
    if proc.returncode != 0:
        return {"sentinel": "exit-nonzero", "rc": proc.returncode, "stderr": proc.stderr.strip()}
    return {"sentinel": None, **json.loads(proc.stdout)}


_RUBY_MAT_SHIM = r'''
require "json"
%s
descriptor = JSON.parse(STDIN.read)
selection = ARGV[0]; model = ARGV[1]
ctx = ARGV[2].empty? ? nil : ARGV[2].to_i
out = ARGV[3].empty? ? nil : ARGV[3].to_i
b = output_budget(descriptor, selection, model, ctx, out)
if b.nil?
  puts JSON.generate({"nil" => true})
else
  puts JSON.generate(b)
end
'''


def drive_ruby_matrix(policy: dict, selection: str, model: str,
                      context: Any, capability: Any) -> dict[str, Any]:
    script = _RUBY_MAT_SHIM % _RUBY_MAT_BODY
    proc = subprocess.run(
        ["ruby", "-e", script,
         selection, model,
         "" if context is None else str(context),
         "" if capability is None else str(capability)],
        input=policy_descriptor_json(policy), capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return {"sentinel": "exit-nonzero", "rc": proc.returncode, "stderr": proc.stderr.strip()}
    out = json.loads(proc.stdout)
    if out.get("nil"):
        return {"sentinel": "nil"}
    return {"sentinel": None, **out}


# The 4th implementation: output_budget inside ai_litellm_context_harness_reservations_ok.
# Its signature is (policy, selection, model, ctx, out) -- it receives the resolved
# outputReservation POLICY directly (the surrounding shell does
# `policy = descriptor.dig("adapterConfig","outputReservation") || {}` and
# `next if policy.empty?` BEFORE calling it), and it returns a hash whose
# comparable budget lives under :effective (not :effective_input). We pass the
# raw policy on STDIN and reproduce the wrapper's empty-policy guard here so we
# only ever drive output_budget on states the production wrapper actually reaches.
_RUBY_RES_SHIM = r'''
require "json"
%s
policy = JSON.parse(STDIN.read)
selection = ARGV[0]; model = ARGV[1]
ctx = ARGV[2].empty? ? nil : ARGV[2].to_i
out = ARGV[3].empty? ? nil : ARGV[3].to_i
b = output_budget(policy, selection, model, ctx, out)
if b.nil?
  puts JSON.generate({"nil" => true})
else
  puts JSON.generate(b)
end
'''


def drive_ruby_reservations(policy: dict, selection: str, model: str,
                            context: Any, capability: Any) -> dict[str, Any]:
    """Drive the harness-reservations output_budget. It returns :effective; we
    normalise that to ``effective_input`` so callers compare the same field name
    as the other impls. nil -> sentinel 'nil' (matches Node exit / Ruby-mat nil
    when no reservation source and no capability resolve).

    Production contract: the surrounding shell does `next if policy.empty?`
    BEFORE calling output_budget, so an empty policy never reaches this copy.
    We honor that here (sentinel 'skipped-by-wrapper-guard') rather than driving
    a state the wrapper makes unreachable."""
    if not policy:
        return {"sentinel": "skipped-by-wrapper-guard"}
    script = _RUBY_RES_SHIM % _RUBY_RES_BODY
    proc = subprocess.run(
        ["ruby", "-e", script,
         selection, model,
         "" if context is None else str(context),
         "" if capability is None else str(capability)],
        # This copy takes the POLICY directly (not the full descriptor).
        input=json.dumps(policy), capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return {"sentinel": "exit-nonzero", "rc": proc.returncode, "stderr": proc.stderr.strip()}
    out = json.loads(proc.stdout)
    if out.get("nil"):
        return {"sentinel": "nil"}
    # Normalise :effective -> effective_input for uniform comparison.
    return {"sentinel": None, "effective_input": out.get("effective"), **out}


# Python is imported, not subprocessed. Policy is injected via env so we never
# touch the real config. Clear bleed between rows.
sys.path.insert(0, str(PY_PKG))
from ai_litellm_callbacks.output_clamp import (  # noqa: E402
    gateway_output_cap,
    clamp_token_reservations,
)

try:
    import yaml as _yaml  # noqa: F401
    _HAVE_YAML = True
except Exception:
    _HAVE_YAML = False

# checks that could not be driven in this environment (reported, not failed)
SKIPPED: list[str] = []

_PY_ENV_KEYS = [
    "AI_LITELLM_OUTPUT_CLAMP_DEFAULT",
    "AI_LITELLM_OUTPUT_CLAMP_TOKENIZER_HEADROOM",
    "AI_LITELLM_OUTPUT_CLAMP_MINIMUM_INPUT",
    "AI_LITELLM_CONFIG",
]


def _clear_py_env() -> None:
    for k in _PY_ENV_KEYS:
        os.environ.pop(k, None)


def drive_python_cap(context: Any, capability: Any, *,
                     default=32000, headroom=8192, min_input=32768,
                     per_model=None, model_name=None) -> int | None:
    _clear_py_env()
    os.environ["AI_LITELLM_OUTPUT_CLAMP_DEFAULT"] = str(default)
    os.environ["AI_LITELLM_OUTPUT_CLAMP_TOKENIZER_HEADROOM"] = str(headroom)
    os.environ["AI_LITELLM_OUTPUT_CLAMP_MINIMUM_INPUT"] = str(min_input)
    info: dict[str, Any] = {}
    if context is not None:
        info["max_input_tokens"] = context
    if capability is not None:
        info["max_output_tokens"] = capability
    kwargs: dict[str, Any] = {"model_info": info}
    if per_model is not None and model_name is not None:
        # perModel is read from the YAML policy, not env. Write a tiny fixture.
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
            f.write(
                "x-gateway-output-clamp:\n"
                f"  default: {default}\n"
                f"  tokenizer_headroom: {headroom}\n"
                f"  minimum_input: {min_input}\n"
                "  perModel:\n"
                f"    {model_name}: {per_model}\n"
            )
            cfg = f.name
        os.environ["AI_LITELLM_CONFIG"] = cfg
        kwargs["model"] = model_name
        try:
            return gateway_output_cap(kwargs)
        finally:
            os.unlink(cfg)
            _clear_py_env()
    try:
        return gateway_output_cap(kwargs)
    finally:
        _clear_py_env()


# =============================================================================
# 3. MATRIX
# =============================================================================
# Each row: id, regime, context, capability, policy kwargs, families to apply.
# Reservation overrides are expressed via build_policy kwargs.
ROWS: list[dict[str, Any]] = [
    dict(id="L1", regime="Large 1048576/384000", ctx=1048576, cap=384000, families="A,B,D"),
    dict(id="L2", regime="Large 262142/262142", ctx=262142, cap=262142, families="A,B,D"),
    dict(id="L3", regime="Large 1048576/131072", ctx=1048576, cap=131072, families="A,B,D"),
    dict(id="L4", regime="Large cap<32000", ctx=1048576, cap=20000, families="A,B"),
    dict(id="L5", regime="Kimi-K2.7-Code clamp (cap<reservation)", ctx=262144, cap=16384, families="A,B,D"),
    # B1/B2 do NOT hit the reservation==max_reservation edge: at ctx~72960 the
    # headroom scales to floor(ctx*0.1) so max_reservation=32896 vs reservation=
    # 32000 (896 apart). Relabeled to what they actually exercise (headroom
    # scaling under the 8192 cap). The exact MR==R edge is covered by BX-* below.
    dict(id="B1", regime="headroom scaled (R<MR by 896)", ctx=72960, cap=72960, families="A,B"),
    dict(id="B2", regime="headroom scaled, ctx-1", ctx=72959, cap=72959, families="A,B"),
    # --- Gap 2a: reservation == max_reservation EXACTLY (and +-1). ---
    # ctx=100000 keeps headroom=8192, min_input=32768 fixed, so MR=100000-40960=
    # 59040. The reservation source is the `default` key set equal to (and +-1 of)
    # MR, with a huge cap so the capabilityClamp never fires first. This is the
    # only place the `reservation > max_reservation` comparator sees equality.
    dict(id="BX-eq", regime="reservation==MR exactly", ctx=100000, cap=200000,
         default=59040, families="A"),       # MR=59040, R=59040 (not >), ei=32768
    dict(id="BX-m1", regime="reservation==MR-1", ctx=100000, cap=200000,
         default=59039, families="A"),       # R<MR, no clamp, ei=32769
    dict(id="BX-p1", regime="reservation==MR+1", ctx=100000, cap=200000,
         default=59041, families="A"),       # R>MR by 1 -> clamped to 59040, ei=32768
    # --- Gap 2b: EMPTY reservation policy (no default/perX) + capability present
    # forces reservation = min(capability, 32000). headroom/min_input still set so
    # the policy is non-empty (the Ruby copies do not take the empty short-cut).
    dict(id="CD-i", regime="cap-clamped-default, cap<32000", ctx=1048576, cap=20000,
         no_default=True, families="A"),      # reservation=cap=20000, ei=1020384
    dict(id="CD-ii", regime="cap-clamped-default, cap>=32000", ctx=1048576, cap=131072,
         no_default=True, families="A"),      # reservation=min(cap,32000)=32000, ei=1008384
    dict(id="B3a", regime="Kimi-1", ctx=262143, cap=262143, families="A,B"),
    dict(id="B3b", regime="Kimi+1", ctx=262144, cap=262144, families="A,B"),
    dict(id="S1", regime="Small, headroom scaled", ctx=80000, cap=80000, families="A,B"),
    dict(id="S2", regime="Small, R clamped to MR", ctx=50000, cap=50000, families="A,B"),
    dict(id="G1", regime="gemma 8192/4096", ctx=8192, cap=4096, families="A,B", pin_oc=3277),
    dict(id="G2", regime="gemma no capability", ctx=8192, cap=None, families="A,B", pin_oc=3277),
    dict(id="T1", regime="tiny window (MR<1)", ctx=1, cap=None, families="A,B,Ctiny"),
    dict(id="T2", regime="tiny, capability tiny", ctx=1, cap=1, families="A,B,Ctiny"),
    dict(id="D1", regime="output>=input degenerate", ctx=1000, cap=99999, families="A,B"),
    dict(id="P1", regime="perModel override", ctx=262142, cap=262142, families="A,B,m",
         per_model=50000, model="m1"),
    dict(id="P2", regime="perTier (Node/Ruby only)", ctx=262142, cap=262142, families="A2",
         per_tier=40000, selection="sel"),
    dict(id="P3", regime="perSel>perTier>perModel", ctx=262142, cap=262142, families="A2",
         per_selection=10000, per_tier=20000, per_model=30000, selection="sel", model="m1"),
    dict(id="Z1", regime="context=null", ctx=None, cap=4096, families="nullctx"),
    dict(id="N1", regime="NaN/negative floor to null", ctx=-5, cap=-1, families="nullctx"),
    dict(id="Z2", regime="no cap AND empty policy", ctx=50000, cap=None, families="Cempty", empty=True),
    # no capability AND no reservation source, but policy non-empty (headroom/
    # min_input present). Hits the no-reservation sentinel on Node (exit 1) and
    # both Ruby copies return nil because no reservation source resolves.
    dict(id="Z3", regime="no cap, reservation-empty policy", ctx=50000, cap=None,
         no_default=True, families="Cnodef"),
]


# =============================================================================
# 4. ASSERTIONS
# =============================================================================
class Failure:
    def __init__(self, row_id: str, msg: str, detail: dict | None = None):
        self.row_id = row_id
        self.msg = msg
        self.detail = detail or {}

    def __str__(self) -> str:
        d = json.dumps(self.detail, sort_keys=True) if self.detail else ""
        return f"[{self.row_id}] {self.msg}  {d}"


def run() -> int:
    slice_errs = _check_slices()
    if slice_errs:
        for e in slice_errs:
            print(f"SLICE-GUARD FAIL: {e}", file=sys.stderr)
        return 1

    failures: list[Failure] = []
    rows_checked = 0

    for row in ROWS:
        rid = row["id"]
        ctx = row["ctx"]
        cap = row["cap"]
        selection = row.get("selection", "default")
        model = row.get("model", "default")
        per_selection = row.get("per_selection")
        per_tier = row.get("per_tier")
        per_model = row.get("per_model")
        families = set(row["families"].split(","))
        empty = row.get("empty", False)
        no_default = row.get("no_default", False)
        # Per-row `default` reservation override (BX-* drive the MR==R edge). When
        # no_default is set the row deliberately has NO default reservation source.
        row_default = None if no_default else row.get("default", 32000)

        policy = build_policy(
            default=32000 if row_default is None else row_default,
            per_selection=per_selection, per_tier=per_tier, per_model=per_model,
            selection=selection, model=model, empty=empty, no_default=no_default,
        )

        # ---- ORACLE -------------------------------------------------------
        oracle = canonical_budget(
            ctx, cap,
            default=None if empty else row_default,
            tokenizer_headroom=None if empty else 8192,
            minimum_input=None if empty else 32768,
            per_selection=per_selection, per_tier=per_tier, per_model=per_model,
        )

        # ===================================================================
        # FAMILY A: effectiveInput agreement (Node + the two Ruby copies)
        # ===================================================================
        if "A" in families:
            rows_checked += 1
            node = drive_node(policy, selection, model, ctx, cap)
            rmat = drive_ruby_matrix(policy, selection, model, ctx, cap)
            rres = drive_ruby_reservations(policy, selection, model, ctx, cap)

            o_ei = oracle.get("effectiveInput")

            # Node effectiveInput
            if node.get("sentinel") is None:
                n_ei = node.get("effectiveInput")
                if n_ei != o_ei:
                    failures.append(Failure(rid, "Node.effectiveInput != oracle",
                                            {"node": n_ei, "oracle": o_ei}))
            else:
                failures.append(Failure(rid, "Node unexpectedly signalled sentinel in Family A",
                                        {"node": node}))

            # Ruby-matrix effectiveInput
            if rmat.get("sentinel") is None:
                m_ei = rmat.get("effective_input")
                if m_ei != o_ei:
                    failures.append(Failure(rid, "RubyMatrix.effective_input != oracle",
                                            {"ruby_matrix": m_ei, "oracle": o_ei}))
            else:
                failures.append(Failure(rid, "RubyMatrix unexpectedly nil in Family A",
                                        {"ruby_matrix": rmat}))

            # Ruby-reservations effectiveInput (:effective field)
            if rres.get("sentinel") is None:
                res_ei = rres.get("effective_input")
                if res_ei != o_ei:
                    failures.append(Failure(rid, "RubyReservations.effective != oracle",
                                            {"ruby_reservations": res_ei, "oracle": o_ei}))
            else:
                failures.append(Failure(rid, "RubyReservations unexpectedly nil in Family A",
                                        {"ruby_reservations": rres}))

            # Cross-impl: the three effectiveInput values must be identical.
            triple = {
                "node": node.get("effectiveInput") if node.get("sentinel") is None else "<sentinel>",
                "ruby_matrix": rmat.get("effective_input") if rmat.get("sentinel") is None else "<sentinel>",
                "ruby_reservations": rres.get("effective_input") if rres.get("sentinel") is None else "<sentinel>",
            }
            if len(set(map(json.dumps, triple.values()))) != 1:
                failures.append(Failure(rid, "effectiveInput DISAGREES across the three impls",
                                        triple))

            # Node + Ruby-matrix + Ruby-reservations must also agree on
            # reservation/headroom/minInput. (Ruby-reservations keys: :reservation,
            # :headroom, :minimum.)
            if (node.get("sentinel") is None and rmat.get("sentinel") is None
                    and rres.get("sentinel") is None):
                for nk, mk, rk, ok in (
                        ("reservation", "reservation", "reservation", "reservation"),
                        ("tokenizerHeadroom", "tokenizer_headroom", "headroom", "tokenizerHeadroom"),
                        ("minimumInput", "minimum_input", "minimum", "minimumInput")):
                    nv, mv, rv, ov = node.get(nk), rmat.get(mk), rres.get(rk), oracle.get(ok)
                    if not (nv == mv == rv == ov):
                        failures.append(Failure(rid, f"{ok} disagreement",
                                                {"node": nv, "ruby_matrix": mv,
                                                 "ruby_reservations": rv, "oracle": ov}))

        # ===================================================================
        # FAMILY A2: effectiveInput copies agree for perTier/perSelection; no Python.
        # ===================================================================
        if "A2" in families:
            rows_checked += 1
            node = drive_node(policy, selection, model, ctx, cap)
            rmat = drive_ruby_matrix(policy, selection, model, ctx, cap)
            rres = drive_ruby_reservations(policy, selection, model, ctx, cap)
            o_ei = oracle.get("effectiveInput")
            values = {
                "node": node.get("effectiveInput"),
                "ruby_matrix": rmat.get("effective_input"),
                "ruby_reservations": rres.get("effective_input"),
                "oracle": o_ei,
            }
            if not (values["node"] == values["ruby_matrix"]
                    == values["ruby_reservations"] == o_ei):
                failures.append(Failure(rid, "perTier/perSelection effectiveInput disagreement", values))

        # ===================================================================
        # FAMILY B: outputCap agreement (Python only, vs oracle output_cap)
        # ===================================================================
        if "B" in families:
            o_oc = canonical_output_cap(ctx, cap)
            py_oc = drive_python_cap(ctx, cap)
            if py_oc != o_oc:
                failures.append(Failure(rid, "Python.gateway_output_cap != oracle outputCap",
                                        {"python": py_oc, "oracle": o_oc}))
            if "pin_oc" in row and o_oc != row["pin_oc"]:
                failures.append(Failure(rid, "oracle outputCap drifted from pinned legacy value",
                                        {"oracle": o_oc, "pin": row["pin_oc"]}))
            if "pin_oc" in row and py_oc != row["pin_oc"]:
                failures.append(Failure(rid, "Python outputCap drifted from pinned legacy value",
                                        {"python": py_oc, "pin": row["pin_oc"]}))

        # FAMILY Bm: Python perModel cap. perModel is read ONLY from the YAML
        # payload (no env var). Without PyYAML, output_clamp._read_config_payload
        # returns {} by design, so this path is undriveable -- skip, don't false-fail.
        if "m" in families:
            if not _HAVE_YAML:
                SKIPPED.append(f"{rid}: Python perModel cap (PyYAML not importable; "
                               "perModel injects only via YAML config)")
            else:
                o_oc = canonical_output_cap(ctx, cap, per_model=per_model)
                py_oc = drive_python_cap(ctx, cap, per_model=per_model, model_name=model)
                if py_oc != o_oc:
                    failures.append(Failure(rid, "Python perModel outputCap != oracle",
                                            {"python": py_oc, "oracle": o_oc}))

        # ===================================================================
        # FAMILY C_tiny: tiny window -- reservation==1 (not 0), Python cap>=1.
        # ===================================================================
        if "Ctiny" in families:
            node = drive_node(policy, selection, model, ctx, cap)
            rmat = drive_ruby_matrix(policy, selection, model, ctx, cap)
            if node.get("sentinel") is None and node.get("reservation") != 1:
                failures.append(Failure(rid, "Node tiny-window reservation != 1",
                                        {"node_reservation": node.get("reservation")}))
            if rmat.get("sentinel") is None and rmat.get("reservation") != 1:
                failures.append(Failure(rid, "RubyMatrix tiny-window reservation != 1",
                                        {"ruby_matrix_reservation": rmat.get("reservation")}))
            py_oc = drive_python_cap(ctx, cap)
            if py_oc is None or py_oc < 1:
                failures.append(Failure(rid, "Python tiny-window outputCap < 1",
                                        {"python": py_oc}))

        # ===================================================================
        # FAMILY AB_nullctx: context==null path. effectiveInput must be null on
        # the three effectiveInput impls; reservation/headroom unscaled. Python
        # cap computed with no context clamp.
        # ===================================================================
        if "nullctx" in families:
            node = drive_node(policy, selection, model, ctx, cap)
            rmat = drive_ruby_matrix(policy, selection, model, ctx, cap)
            rres = drive_ruby_reservations(policy, selection, model, ctx, cap)
            # oracle effectiveInput is None (context None / non-finite)
            for label, val in (("node", node.get("effectiveInput") if node.get("sentinel") is None else "<sentinel>"),
                               ("ruby_matrix", rmat.get("effective_input") if rmat.get("sentinel") is None else "<sentinel>"),
                               ("ruby_reservations", rres.get("effective_input") if rres.get("sentinel") is None else "<sentinel>")):
                if val not in (None, "<sentinel>"):
                    failures.append(Failure(rid, f"{label} effectiveInput should be null with null context",
                                            {label: val}))
            # Python outputCap (no context clamp)
            o_oc = canonical_output_cap(ctx, cap)
            py_oc = drive_python_cap(ctx, cap)
            if py_oc != o_oc:
                failures.append(Failure(rid, "Python null-context outputCap != oracle",
                                        {"python": py_oc, "oracle": o_oc}))

        # ===================================================================
        # FAMILY C_empty: empty policy -- impl-specific behavior, NOT cross-impl.
        #   Node: exit(1).  Ruby-matrix output_budget: nil.
        #   Ruby-reservations wrapper: skips the empty policy.
        # ===================================================================
        if "Cempty" in families:
            node = drive_node(policy, selection, model, ctx, cap)
            rmat = drive_ruby_matrix(policy, selection, model, ctx, cap)
            rres = drive_ruby_reservations(policy, selection, model, ctx, cap)
            if node.get("sentinel") != "exit-nonzero":
                failures.append(Failure(rid, "Node empty-policy+no-cap should exit nonzero",
                                        {"node": node}))
            if rmat.get("sentinel") != "nil":
                failures.append(Failure(rid, "RubyMatrix empty-policy should return nil",
                                        {"ruby_matrix": rmat}))
            # Ruby-reservations: the wrapper skips empty policies before calling
            # output_budget, so this copy is never reached for an empty policy.
            if rres.get("sentinel") != "skipped-by-wrapper-guard":
                failures.append(Failure(rid, "RubyReservations empty-policy should be wrapper-skipped",
                                        {"ruby_reservations": rres}))

        # ===================================================================
        # FAMILY C_nodef: NO capability AND NO reservation source, but the policy
        # is NON-empty (headroom/min_input present). Impl-specific, NOT cross-impl:
        #   Node:        no reservation -> exit(1)  [SENTINEL_NO_RESERVATION]
        #   Ruby-matrix: no reservation -> nil      [SENTINEL_NO_RESERVATION]
        #   Ruby-reservations: no reservation source -> nil.
        # ===================================================================
        if "Cnodef" in families:
            rows_checked += 1
            node = drive_node(policy, selection, model, ctx, cap)
            rmat = drive_ruby_matrix(policy, selection, model, ctx, cap)
            rres = drive_ruby_reservations(policy, selection, model, ctx, cap)
            if node.get("sentinel") != "exit-nonzero":
                failures.append(Failure(rid, "Node no-cap+no-reservation should exit nonzero (sentinel)",
                                        {"node": node}))
            if rmat.get("sentinel") != "nil":
                failures.append(Failure(rid, "RubyMatrix no-cap+no-reservation should return nil (sentinel)",
                                        {"ruby_matrix": rmat}))
            # Ruby-reservations matches Node/Ruby-matrix here: `return nil unless
            # pick || capability` -> no reservation source + no capability -> nil.
            # (It does NOT short-circuit on policy.empty?, but the policy is
            # non-empty here -- headroom/min_input present -- so the nil comes from
            # the pick||capability guard, same sentinel as the other two.)
            if rres.get("sentinel") != "nil":
                failures.append(Failure(rid, "RubyReservations no-cap+no-reservation should return nil (sentinel)",
                                        {"ruby_reservations": rres}))

        # ===================================================================
        # FAMILY D: Python clamp_token_reservations lower-only semantics.
        # ===================================================================
        if "D" in families:
            _clear_py_env()
            cap_val = canonical_output_cap(ctx, cap)
            info = {"max_input_tokens": ctx, "max_output_tokens": cap}
            kw = {"max_tokens": 999999, "max_completion_tokens": 5, "model_info": info}
            clamp_token_reservations(kw)
            if kw["max_tokens"] != min(999999, cap_val):
                failures.append(Failure(rid, "clamp_token_reservations max_tokens not lower-clamped",
                                        {"got": kw["max_tokens"], "want": min(999999, cap_val)}))
            if kw["max_completion_tokens"] != min(5, cap_val):
                failures.append(Failure(rid, "clamp_token_reservations did not keep lower value",
                                        {"got": kw["max_completion_tokens"], "want": min(5, cap_val)}))
            kw2 = {"max_tokens": 999999, "model_info": info}
            clamp_token_reservations(kw2)
            if "max_completion_tokens" in kw2:
                failures.append(Failure(rid, "clamp_token_reservations injected an absent key",
                                        {"kwargs": kw2}))
            _clear_py_env()

    # ---- report -----------------------------------------------------------
    print(f"budget-consistency: {len(ROWS)} rows, {rows_checked} effectiveInput "
          f"cross-impl checks, {len(failures)} failures, {len(SKIPPED)} undriveable")
    for s in SKIPPED:
        print(f"  skip: {s}")
    if failures:
        print("\n==== DRIFT / DISAGREEMENT (each line is a real latent bug) ====", file=sys.stderr)
        for f in failures:
            print(f"FAIL {f}", file=sys.stderr)
        print("=============================================================", file=sys.stderr)
        return 1
    print("OK: all four token-budget implementations agree across the full matrix.")
    return 0


if __name__ == "__main__":
    sys.exit(run())
