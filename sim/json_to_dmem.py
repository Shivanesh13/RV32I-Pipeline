#!/usr/bin/env python3
"""Convert opcode JSON optional data section to dmem .mem.

Expected JSON shape:
{
  "text_base": "0x00003000",
  "instructions": { ... },
  "data": {
    "0x00000000": "0x0000002a",
    "0x00000004": "0x00000010"
  }
}

The "data" section is optional. If missing, an empty .mem is emitted.
Each line in output is:
<word_index_hex> <word_hex>
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
    p = argparse.ArgumentParser(description="Convert opcode JSON optional data to dmem mem file.")
    p.add_argument("--json", required=True, help="Path to <program>_opcodes.json")
    p.add_argument("--out", required=True, help="Path to output dmem .mem file")
    args = p.parse_args()

    src = Path(args.json)
    out = Path(args.out)
    payload = json.loads(src.read_text(encoding="utf-8"))

    data = payload.get("data", {})
    if not isinstance(data, dict):
        raise ValueError("Invalid opcode JSON: 'data' must be an object when present")

    pairs: list[tuple[int, int]] = []
    for addr_s, word_s in data.items():
        addr = parse_int(addr_s)
        word = parse_int(word_s) & 0xFFFFFFFF
        if addr % 4 != 0:
            raise ValueError(f"Data address must be 4-byte aligned: {addr_s}")
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
