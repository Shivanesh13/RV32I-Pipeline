"""Encodings aligned with defines.svh (RV32I-Pipeline project)."""

R_OPCODE = 0b000000
LOAD_OPCODE = 0b100011   # 0x23
STORE_OPCODE = 0b101011   # 0x2B
BRANCH_OPCODE = 0b000100  # 0x04
JAL_OPCODE = 0b000010    # 0x02
NOP_OPCODE = 0b000001    # NO_OPERATION

FUNCT = {
    "ADD": 0b000001,
    "SUB": 0b000010,
    "MUL": 0b000100,
    "AND": 0b000110,
    "OR": 0b000111,
    "XOR": 0b001000,
    "SLL": 0b001001,
    "SRL": 0b001010,
}

# Mnemonics for text emission
R_MNEMONICS = {v: k for k, v in FUNCT.items()}


def pack_r(rd: int, rs1: int, rs2: int, funct: int) -> int:
    if not all(0 <= x <= 31 for x in (rd, rs1, rs2)):
        raise ValueError("register out of range")
    return (
        (R_OPCODE << 26)
        | (rs1 << 21)
        | (rs2 << 16)
        | (rd << 11)
        | (0 << 6)
        | funct
    )


def pack_i_load(opcode: int, rd: int, rs1: int, imm: int) -> int:
    imm16 = imm & 0xFFFF
    if imm16 & 0x8000:
        imm16 |= ~0xFFFF  # sign-extend for sanity check
    if imm < -0x8000 or imm > 0x7FFF:
        raise ValueError(f"immediate {imm} out of 16-bit signed range")
    uimm = imm & 0xFFFF
    return (opcode << 26) | (rs1 << 21) | (rd << 16) | uimm


def pack_i_store(opcode: int, rs1: int, rs2: int, imm: int) -> int:
    if imm < -0x8000 or imm > 0x7FFF:
        raise ValueError(f"immediate {imm} out of 16-bit signed range")
    uimm = imm & 0xFFFF
    return (opcode << 26) | (rs1 << 21) | (rs2 << 16) | uimm


def pack_j(opcode: int, target26: int) -> int:
    if not (0 <= target26 < (1 << 26)):
        raise ValueError("J-type target out of range")
    return (opcode << 26) | target26


def pack_nop() -> int:
    return NOP_OPCODE << 26
