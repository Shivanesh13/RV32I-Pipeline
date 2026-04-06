from __future__ import annotations

import argparse
import json
import sys

from minicc.codegen import compile_source_with_opcodes
from minicc.errors import CompileError


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Compile C-like source to assembly.")
    p.add_argument("input", help="Source file (.c-like)")
    p.add_argument("-o", "--output", required=True, help="Output .asm file")
    p.add_argument(
        "--opcode-map",
        help="Optional JSON output mapping instruction address to machine opcode.",
    )
    p.add_argument(
        "--text-base",
        type=lambda v: int(v, 0),
        default=0x3000,
        help="Text section base address (default: 0x3000).",
    )
    args = p.parse_args(argv)

    try:
        with open(args.input, encoding="utf-8") as f:
            src = f.read()
    except OSError as e:
        print(f"minicc: {e}", file=sys.stderr)
        return 1

    try:
        asm, opcode_map = compile_source_with_opcodes(src, text_base=args.text_base)
    except CompileError as e:
        print(f"minicc: {e.format()}", file=sys.stderr)
        return 1

    try:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(asm)
    except OSError as e:
        print(f"minicc: {e}", file=sys.stderr)
        return 1

    if args.opcode_map:
        payload = {
            "text_base": f"0x{args.text_base:08x}",
            "instructions": {f"0x{pc:08x}": f"0x{word:08x}" for pc, word in opcode_map.items()},
        }
        try:
            with open(args.opcode_map, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2)
                f.write("\n")
        except OSError as e:
            print(f"minicc: {e}", file=sys.stderr)
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
