"""C-like subset compiler targeting a custom MIPS-style ISA."""

from minicc.codegen import compile_source, compile_source_with_opcodes
from minicc.errors import CompileError

__all__ = ["compile_source", "compile_source_with_opcodes", "CompileError"]
