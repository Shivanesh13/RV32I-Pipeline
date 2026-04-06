from __future__ import annotations

from dataclasses import dataclass, field
from typing import Union


@dataclass
class Label:
    name: str


@dataclass
class MoveImm:
    """Load small constant via pool or ORI-less path: use LW from .data"""
    dst: int  # virtual
    pool_label: str
    line: int


@dataclass
class RInst:
    op: str  # ADD SUB MUL AND XOR
    rd: int
    rs1: int
    rs2: int
    line: int


@dataclass
class LWInst:
    rd: int
    imm: int
    rs1: int
    line: int


@dataclass
class SWInst:
    rs2: int
    imm: int
    rs1: int
    line: int


@dataclass
class BEQInst:
    rs1: int
    rs2: int
    target: str  # label name
    line: int


@dataclass
class JALInst:
    target: str
    line: int


@dataclass
class JRInst:
    rs: int  # return: JR r31
    line: int


@dataclass
class NOPInst:
    line: int


IrOp = Union[MoveImm, RInst, LWInst, SWInst, BEQInst, JALInst, JRInst, NOPInst, Label]


@dataclass
class FunctionIR:
    name: str
    param_count: int
    ops: list[IrOp] = field(default_factory=list)
    stack_slots: int = 0  # spill count * 4
