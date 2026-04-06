#!/usr/bin/env python3
"""Convert project assembly (.asm) directly into IMEM/DMEM .mem files.

Supported directives:
  .data / .text
  .word <value>[, <value>...]
  <label>:
  <label>: .word <value>

Supported instructions:
  ADD/SUB/MUL/AND/OR/XOR/SLL/SRL rd, rs1, rs2
  LW rd, imm(rs1)
  SW rs2, imm(rs1)
  BEQ rs1, rs2, <label>
  JAL <label>
  JR rs     (encoded as NOP to match current backend behavior)
  NOP
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


R_OPCODE = 0b000000
LOAD_OPCODE = 0b100011
STORE_OPCODE = 0b101011
BRANCH_OPCODE = 0b000100
JAL_OPCODE = 0b000010
NOP_OPCODE = 0b000001

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


def pack_r(rd: int, rs1: int, rs2: int, funct: int) -> int:
    return (R_OPCODE << 26) | (rs1 << 21) | (rs2 << 16) | (rd << 11) | funct


def pack_i(opcode: int, rs1: int, rt: int, imm: int) -> int:
    if imm < -0x8000 or imm > 0x7FFF:
        raise ValueError(f"immediate {imm} out of 16-bit signed range")
    return (opcode << 26) | (rs1 << 21) | (rt << 16) | (imm & 0xFFFF)


def pack_j(target26: int) -> int:
    if not (0 <= target26 < (1 << 26)):
        raise ValueError(f"JAL target out of range: {target26}")
    return (JAL_OPCODE << 26) | target26


def parse_int(tok: str) -> int:
    return int(tok.strip(), 0)


def parse_reg(tok: str) -> int:
    m = re.fullmatch(r"r([0-9]|[12][0-9]|3[01])", tok.strip(), flags=re.IGNORECASE)
    if not m:
        raise ValueError(f"invalid register '{tok}'")
    return int(m.group(1))


def strip_comment(line: str) -> str:
    for sep in ("//", "#"):
        if sep in line:
            line = line.split(sep, 1)[0]
    return line.strip()


def normalize_tokens(s: str) -> list[str]:
    return [t.strip() for t in s.split(",") if t.strip()]


def parse_mem_operand(tok: str) -> tuple[int, int]:
    m = re.fullmatch(r"(.+)\((r[0-9]+)\)", tok.replace(" ", ""), flags=re.IGNORECASE)
    if not m:
        raise ValueError(f"invalid memory operand '{tok}'")
    imm = parse_int(m.group(1))
    rs = parse_reg(m.group(2))
    return imm, rs


def encode_text(lines: list[str], text_base: int) -> tuple[dict[int, int], dict[str, int]]:
    labels: dict[str, int] = {}
    parsed: list[tuple[int, str]] = []

    # Pass 1: label addresses
    pc = text_base
    for raw in lines:
        line = strip_comment(raw)
        if not line:
            continue
        if ":" in line:
            left, right = line.split(":", 1)
            lab = left.strip()
            if lab:
                labels[lab] = pc
            line = right.strip()
            if not line:
                continue
        parsed.append((pc, line))
        pc += 4

    # Pass 2: encode
    out: dict[int, int] = {}
    for pc, inst_line in parsed:
        parts = inst_line.split(None, 1)
        op = parts[0].upper()
        args_s = parts[1] if len(parts) > 1 else ""

        if op in FUNCT:
            args = normalize_tokens(args_s)
            if len(args) != 3:
                raise ValueError(f"{op} expects 3 operands")
            rd = parse_reg(args[0])
            rs1 = parse_reg(args[1])
            rs2 = parse_reg(args[2])
            out[pc] = pack_r(rd, rs1, rs2, FUNCT[op])
            continue

        if op == "LW":
            args = normalize_tokens(args_s)
            if len(args) != 2:
                raise ValueError("LW expects 2 operands")
            rd = parse_reg(args[0])
            imm, rs1 = parse_mem_operand(args[1])
            out[pc] = pack_i(LOAD_OPCODE, rs1, rd, imm)
            continue

        if op == "SW":
            args = normalize_tokens(args_s)
            if len(args) != 2:
                raise ValueError("SW expects 2 operands")
            rs2 = parse_reg(args[0])
            imm, rs1 = parse_mem_operand(args[1])
            out[pc] = pack_i(STORE_OPCODE, rs1, rs2, imm)
            continue

        if op == "BEQ":
            args = normalize_tokens(args_s)
            if len(args) != 3:
                raise ValueError("BEQ expects 3 operands")
            rs1 = parse_reg(args[0])
            rs2 = parse_reg(args[1])
            tgt = labels.get(args[2])
            if tgt is None:
                raise ValueError(f"unknown BEQ label '{args[2]}'")
            delta = tgt - pc
            if delta % 4 != 0:
                raise ValueError(f"BEQ target not word-aligned: {args[2]}")
            imm = delta // 4
            out[pc] = pack_i(BRANCH_OPCODE, rs1, rs2, imm)
            continue

        if op == "JAL":
            args = normalize_tokens(args_s)
            if len(args) != 1:
                raise ValueError("JAL expects 1 operand")
            tgt = labels.get(args[0])
            if tgt is None:
                raise ValueError(f"unknown JAL label '{args[0]}'")
            out[pc] = pack_j((tgt >> 2) & ((1 << 26) - 1))
            continue

        if op in ("JR", "NOP"):
            out[pc] = NOP_OPCODE << 26
            continue

        raise ValueError(f"unsupported instruction '{op}'")

    return out, labels


def parse_data(lines: list[str]) -> dict[int, int]:
    dmem: dict[int, int] = {}
    word_idx = 0
    for raw in lines:
        line = strip_comment(raw)
        if not line:
            continue
        if ":" in line:
            _, right = line.split(":", 1)
            line = right.strip()
            if not line:
                continue
        if not line:
            continue
        if not line.lower().startswith(".word"):
            raise ValueError(f"unsupported .data directive '{line}'")
        rhs = line[5:].strip()
        if not rhs:
            raise ValueError("empty .word directive")
        vals = [parse_int(tok) & 0xFFFFFFFF for tok in rhs.split(",")]
        for v in vals:
            dmem[word_idx] = v
            word_idx += 1
    return dmem


def write_mem(path: Path, pairs: list[tuple[int, int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for idx, word in pairs:
            f.write(f"{idx:08x} {word:08x}\n")


def main() -> int:
    p = argparse.ArgumentParser(description="Convert .asm to imem/dmem .mem files.")
    p.add_argument("--asm", required=True, help="Path to .asm input")
    p.add_argument("--imem-out", required=True, help="Output IMEM .mem path")
    p.add_argument("--dmem-out", required=True, help="Output DMEM .mem path")
    p.add_argument("--json-out", help="Optional output JSON opcode map path")
    p.add_argument("--text-base", default="0x3000", help="Text base byte address (default: 0x3000)")
    args = p.parse_args()

    asm_path = Path(args.asm)
    text_base = parse_int(args.text_base)
    if text_base < 0 or text_base % 4 != 0:
        raise ValueError("text-base must be non-negative and 4-byte aligned")

    mode = None
    data_lines: list[str] = []
    text_lines: list[str] = []
    for raw in asm_path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw)
        if not line:
            continue
        if line == ".data":
            mode = "data"
            continue
        if line == ".text":
            mode = "text"
            continue
        if mode == "data":
            data_lines.append(raw)
        elif mode == "text":
            text_lines.append(raw)

    imem_words, _ = encode_text(text_lines, text_base)
    dmem_words = parse_data(data_lines)

    imem_pairs = sorted(((addr >> 2, word) for addr, word in imem_words.items()), key=lambda x: x[0])
    dmem_pairs = sorted(dmem_words.items(), key=lambda x: x[0])

    write_mem(Path(args.imem_out), imem_pairs)
    write_mem(Path(args.dmem_out), dmem_pairs)

    if args.json_out:
        out_json = Path(args.json_out)
        out_json.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "text_base": f"0x{text_base:08x}",
            "instructions": {f"0x{addr:08x}": f"0x{word:08x}" for addr, word in sorted(imem_words.items())},
            "data": {f"0x{(idx << 2):08x}": f"0x{word:08x}" for idx, word in dmem_pairs},
        }
        out_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote opcode JSON to {args.json_out}")

    print(f"Wrote {len(imem_pairs)} IMEM entries to {args.imem_out}")
    print(f"Wrote {len(dmem_pairs)} DMEM entries to {args.dmem_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
