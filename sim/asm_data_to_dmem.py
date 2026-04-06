#!/usr/bin/env python3
"""Extract .data .word values from ASM and emit DMEM init file.

Input ASM snippet:
.data
label: .word 1
label2: .word 0x10
.text

Output .mem format (one word per line):
00000000 00000001
00000001 00000010
"""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_word_literal(token: str) -> int:
    token = token.strip()
    if token.startswith("-"):
        return int(token, 0) & 0xFFFFFFFF
    return int(token, 0) & 0xFFFFFFFF


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert ASM .data .word values to DMEM mem file.")
    parser.add_argument("--asm", required=True, help="Path to compiler-generated .asm file")
    parser.add_argument("--out", required=True, help="Path to output dmem .mem file")
    args = parser.parse_args()

    asm_path = Path(args.asm)
    out_path = Path(args.out)

    in_data = False
    values: list[int] = []

    for raw in asm_path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line == ".data":
            in_data = True
            continue
        if line == ".text":
            in_data = False
            continue
        if not in_data:
            continue

        # Accept both "label: .word X" and ".word X"
        if ".word" not in line:
            continue
        rhs = line.split(".word", 1)[1].strip()
        if not rhs:
            continue
        first_token = rhs.split(",", 1)[0].strip()
        values.append(parse_word_literal(first_token))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        for idx, word in enumerate(values):
            f.write(f"{idx:08x} {word:08x}\n")

    print(f"Wrote {len(values)} DMEM entries to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
