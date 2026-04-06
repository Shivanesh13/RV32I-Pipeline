"""
Simple linear-scan register allocator over physical r1..r28 (r0 fixed zero).
r29 = frame pointer for spills, r30 scratch, r31 = return address (clobbered by JAL).
"""

from __future__ import annotations

from dataclasses import dataclass

from minicc.errors import CompileError
from minicc import ir


PHYS_MIN = 1
PHYS_MAX = 28  # leave r29-r31 reserved
RESERVED = {0, 29, 30, 31}


@dataclass
class Interval:
    v: int
    start: int
    end: int


def _uses_def(op: ir.IrOp, idx: int) -> tuple[set[int], set[int]]:
    """Return (uses, defs) virtual register sets at instruction index idx."""
    uses: set[int] = set()
    defs: set[int] = set()
    if isinstance(op, ir.MoveImm):
        defs.add(op.dst)
    elif isinstance(op, ir.RInst):
        defs.add(op.rd)
        uses.add(op.rs1)
        uses.add(op.rs2)
    elif isinstance(op, ir.LWInst):
        defs.add(op.rd)
        uses.add(op.rs1)
    elif isinstance(op, ir.SWInst):
        uses.add(op.rs2)
        uses.add(op.rs1)
    elif isinstance(op, ir.BEQInst):
        uses.add(op.rs1)
        uses.add(op.rs2)
    elif isinstance(op, ir.JALInst):
        pass
    elif isinstance(op, ir.JRInst):
        uses.add(op.rs)
    elif isinstance(op, ir.NOPInst):
        pass
    elif isinstance(op, ir.Label):
        pass
    return uses, defs


def build_intervals(ops: list[ir.IrOp]) -> dict[int, Interval]:
    """Per virtual reg, live interval [first appearance, last appearance] in op index."""
    first: dict[int, int] = {}
    last: dict[int, int] = {}
    idx = 0
    for op in ops:
        if isinstance(op, ir.Label):
            continue
        uses, defs = _uses_def(op, idx)
        for v in uses | defs:
            if v not in first:
                first[v] = idx
            last[v] = idx
        idx += 1

    return {v: Interval(v, first[v], last[v]) for v in first}


def linear_scan_allocate(ops: list[ir.IrOp], param_vregs: list[int]) -> dict[int, int]:
    """
    Map virtual register -> physical 1..28.
    Pre-assign params to r1, r2, ... in order.
    """
    intervals = build_intervals(ops)
    alloc: dict[int, int] = {0: 0}  # vreg 0 is always physical r0
    # Params fixed to r1..rN
    for i, pv in enumerate(param_vregs):
        phys = PHYS_MIN + i
        if phys > PHYS_MAX:
            raise CompileError("too many function parameters (max 28)")
        alloc[pv] = phys

    # Remove param intervals from pool
    sorted_iv = sorted(
        (iv for v, iv in intervals.items() if v not in alloc),
        key=lambda x: x.start,
    )
    free = [p for p in range(PHYS_MIN, PHYS_MAX + 1) if p not in alloc.values()]
    active: list[tuple[int, Interval]] = []  # (phys, interval)

    for iv in sorted_iv:
        # expire intervals that ended before this one starts
        active = [(p, j) for p, j in active if j.end >= iv.start]
        used_phys = {p for p, _ in active} | set(alloc.values())
        cand = [p for p in range(PHYS_MIN, PHYS_MAX + 1) if p not in used_phys]
        if not cand:
            raise CompileError(
                "register pressure: need spill (linear scan exhausted r1-r28); "
                "reduce live variables or add spill support"
            )
        p = cand[0]
        alloc[iv.v] = p
        active.append((p, iv))
    return alloc
