#!/usr/bin/env python3
"""Convert compiler opcode JSON to tb_top imem load file.

Input JSON shape:
{
  "text_base": "0x00003000",
  "instructions": {
    "0x00003000": "0x8c010000",
    ...
  }
}

Output format (one instruction per line):
<word_index_hex> <word_hex>
Example:
00000c00 8c010000
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_int(v: str | int) -> int:
    if isinstance(v, int):
        return v
    return int(v, 0)


def main() -> int:
    p = argparse.ArgumentParser(description="Convert opcode JSON to imem mem file.")
    p.add_argument("--json", required=True, help="Path to program_opcodes.json")
    p.add_argument("--out", required=True, help="Path to output .mem file")
    args = p.parse_args()

    src = Path(args.json)
    out = Path(args.out)
    payload = json.loads(src.read_text(encoding="utf-8"))
    instructions = payload.get("instructions", {})
    if not isinstance(instructions, dict):
        raise ValueError("Invalid opcode JSON: 'instructions' must be an object")

    pairs: list[tuple[int, int]] = []
    for addr_s, word_s in instructions.items():
        addr = parse_int(addr_s)
        word = parse_int(word_s) & 0xFFFFFFFF
        if addr % 4 != 0:
            raise ValueError(f"Instruction address must be 4-byte aligned: {addr_s}")
        idx = addr >> 2
        pairs.append((idx, word))

    pairs.sort(key=lambda x: x[0])
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as f:
        for idx, word in pairs:
            f.write(f"{idx:08x} {word:08x}\n")

    print(f"Wrote {len(pairs)} entries to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
