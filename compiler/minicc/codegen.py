"""
AST -> IR -> (linear scan) -> assembly text.
ABI: parameters in r1, r2, ...; return value in r1; JAL writes return address to r31; return via JR r31.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from minicc import ast_nodes as A
from minicc.errors import CompileError
from minicc import ir
from minicc import isa
from minicc.regalloc import linear_scan_allocate


@dataclass
class CompileContext:
    globals: dict[str, str] = field(default_factory=dict)  # name -> asm label
    global_inits: dict[str, int] = field(default_factory=dict)
    global_array_inits: dict[str, list[int]] = field(default_factory=dict)
    global_sizes: dict[str, int] = field(default_factory=dict)  # name -> number of words
    global_addrs: dict[str, int] = field(default_factory=dict)  # name -> byte address
    next_data_addr: int = 0
    pool: dict[int, str] = field(default_factory=dict)  # const -> label
    pool_next: int = 0
    label_id: int = 0
    funcs: dict[str, A.FuncDecl] = field(default_factory=dict)

    def fresh_label(self, prefix: str = "L") -> str:
        self.label_id += 1
        return f"{prefix}{self.label_id}"

    def pool_const(self, k: int) -> str:
        if k not in self.pool:
            self.pool_next += 1
            self.pool[k] = f"__pool_{self.pool_next}"
        return self.pool[k]


def _check_unsupported(program: A.Program) -> None:
    """Walk AST for unsupported constructs."""
    for d in program.decls:
        if isinstance(d, A.FuncDecl):
            _scan_func(d)


def _scan_func(f: A.FuncDecl) -> None:
    def walk_stmt(s: A.Stmt) -> None:
        if isinstance(s, A.BlockStmt):
            for x in s.stmts:
                walk_stmt(x)
        elif isinstance(s, A.VarDeclStmt):
            pass
        elif isinstance(s, A.AssignStmt):
            _scan_expr(s.value)
        elif isinstance(s, A.ArrayAssignStmt):
            _scan_expr(s.index)
            _scan_expr(s.value)
        elif isinstance(s, A.IfStmt):
            _scan_expr(s.cond)
            walk_stmt(s.then_branch)
            if s.else_branch:
                walk_stmt(s.else_branch)
        elif isinstance(s, A.WhileStmt):
            _scan_expr(s.cond)
            walk_stmt(s.body)
        elif isinstance(s, A.ReturnStmt):
            if s.value:
                _scan_expr(s.value)
        elif isinstance(s, A.ExprStmt):
            _scan_expr(s.expr)
        else:
            raise CompileError(f"unsupported statement {type(s)}", getattr(s, "line", f.line))

    for st in f.body.stmts:
        walk_stmt(st)


def _scan_expr(e: A.Expr) -> None:
    if isinstance(e, A.BinOp):
        if e.op not in (
            "+",
            "-",
            "*",
            "&",
            "|",
            "^",
            "<<",
            ">>",
            "==",
            "!=",
            "<",
            ">",
            "<=",
            ">=",
        ):
            raise CompileError(f"unsupported operator {e.op!r}", e.line)
        _scan_expr(e.left)
        _scan_expr(e.right)
    elif isinstance(e, A.Call):
        for a in e.args:
            _scan_expr(a)
    elif isinstance(e, A.ArrayRef):
        _scan_expr(e.index)
    elif isinstance(e, (A.IntLiteral, A.Ident)):
        pass


class FunctionGen:
    def __init__(self, ctx: CompileContext, fn: A.FuncDecl):
        self.ctx = ctx
        self.fn = fn
        self.ops: list[ir.IrOp] = []
        self.vreg = 0
        self.locals: dict[str, int] = {}
        self.local_arrays: dict[str, str] = {}
        self.param_v: list[int] = []
        self.main_end_label: str | None = None

    def new_v(self) -> int:
        self.vreg += 1
        return self.vreg

    def emit(self, op: ir.IrOp) -> None:
        self.ops.append(op)

    def bind_local(self, name: str) -> int:
        if name in self.locals:
            return self.locals[name]
        v = self.new_v()
        self.locals[name] = v
        return v

    def _resolve_array_key(self, name: str) -> str:
        if name in self.local_arrays:
            return self.local_arrays[name]
        return name

    def array_addr(self, name: str, index_expr: A.Expr, line: int) -> int:
        key = self._resolve_array_key(name)
        base_addr = self.ctx.global_addrs.get(key)
        if base_addr is None:
            raise CompileError(f"unknown array {name!r}", line)

        vbase = self.new_v()
        self.emit(ir.MoveImm(vbase, self.ctx.pool_const(base_addr), line))

        vidx, _ = self.expr(index_expr)
        vstride = self.new_v()
        self.emit(ir.MoveImm(vstride, self.ctx.pool_const(4), line))
        voff = self.new_v()
        self.emit(ir.RInst("MUL", voff, vidx, vstride, line))

        vaddr = self.new_v()
        self.emit(ir.RInst("ADD", vaddr, vbase, voff, line))
        return vaddr

    def lower(self) -> ir.FunctionIR:
        # params v1..vk map to vregs 1..k (reserved)
        for i, p in enumerate(self.fn.params):
            pv = i + 1
            self.param_v.append(pv)
            self.locals[p] = pv
        self.vreg = len(self.fn.params)  # next free vreg id starts after params

        if self.fn.name == "main":
            self.main_end_label = self.ctx.fresh_label("MAIN_END")

        for st in self.fn.body.stmts:
            self.stmt(st)

        if self.main_end_label is not None:
            # Main is an entrypoint, not a callable routine. End in a safe self-loop.
            self.emit(ir.Label(self.main_end_label))
            self.emit(ir.BEQInst(0, 0, self.main_end_label, self.fn.line))

        self.emit(ir.NOPInst(self.fn.line))
        return ir.FunctionIR(self.fn.name, len(self.fn.params), self.ops)

    def stmt(self, s: A.Stmt) -> None:
        line = getattr(s, "line", 0)
        if isinstance(s, A.BlockStmt):
            for x in s.stmts:
                self.stmt(x)
        elif isinstance(s, A.VarDeclStmt):
            d = s.decl
            if d.array_len is not None:
                if d.name in self.locals or d.name in self.local_arrays:
                    raise CompileError(f"duplicate local declaration {d.name!r}", d.line)
                gkey = f"__larr_{self.fn.name}_{d.name}_{self.ctx.fresh_label('A')}"
                glab = f"_g_{gkey}"
                self.ctx.globals[gkey] = glab
                self.ctx.global_sizes[gkey] = d.array_len
                init_vals = d.array_init or []
                if len(init_vals) > d.array_len:
                    raise CompileError(f"too many initializers for array {d.name!r}", d.line)
                self.ctx.global_array_inits[gkey] = init_vals
                self.ctx.global_inits[gkey] = init_vals[0] if init_vals else 0
                self.ctx.global_addrs[gkey] = self.ctx.next_data_addr
                self.ctx.next_data_addr += 4 * d.array_len
                self.local_arrays[d.name] = gkey
                return
            v = self.bind_local(d.name)
            if d.init is not None:
                vr, _ = self.expr(d.init)
                self.emit(ir.RInst("ADD", v, vr, 0, d.line))  # ADD v, vr, r0
            else:
                self.emit(ir.RInst("ADD", v, 0, 0, d.line))  # zero
        elif isinstance(s, A.AssignStmt):
            v = self.locals.get(s.name)
            if v is not None:
                vr, _ = self.expr(s.value)
                self.emit(ir.RInst("ADD", v, vr, 0, s.line))
                return
            if s.name in self.ctx.global_addrs and self.ctx.global_sizes.get(s.name, 0) == 1:
                vr, _ = self.expr(s.value)
                vaddr = self.new_v()
                self.emit(ir.MoveImm(vaddr, self.ctx.pool_const(self.ctx.global_addrs[s.name]), s.line))
                self.emit(ir.SWInst(vr, 0, vaddr, s.line))
                return
            if s.name in self.ctx.global_addrs and self.ctx.global_sizes.get(s.name, 0) > 1:
                raise CompileError(f"cannot assign whole array {s.name!r}; assign an element", s.line)
            if s.name in self.local_arrays:
                raise CompileError(f"cannot assign whole array {s.name!r}; assign an element", s.line)
            if v is None:
                raise CompileError(f"unknown variable {s.name!r}", s.line)
        elif isinstance(s, A.ArrayAssignStmt):
            key = self._resolve_array_key(s.name)
            if key not in self.ctx.global_addrs or self.ctx.global_sizes.get(key, 0) <= 1:
                raise CompileError(f"unknown array {s.name!r}", s.line)
            vaddr = self.array_addr(s.name, s.index, s.line)
            vr, _ = self.expr(s.value)
            self.emit(ir.SWInst(vr, 0, vaddr, s.line))
        elif isinstance(s, A.IfStmt):
            self._if_stmt(s)
        elif isinstance(s, A.WhileStmt):
            self._while_stmt(s)
        elif isinstance(s, A.ReturnStmt):
            if self.fn.name == "main":
                # For main(), return value is ignored and just terminates program flow.
                if self.main_end_label is None:
                    raise CompileError("internal error: main end label not initialized", s.line)
                self.emit(ir.BEQInst(0, 0, self.main_end_label, s.line))
            else:
                if s.value:
                    vr, _ = self.expr(s.value)
                    self.emit(ir.RInst("ADD", 1, vr, 0, s.line))  # return -> r1
                self.emit(ir.JRInst(31, s.line))
        elif isinstance(s, A.ExprStmt):
            self.expr(s.expr)
        else:
            raise CompileError(f"unsupported stmt {type(s)}", line)

    def _emit_cond_jump(self, cond: A.Expr, true_target: str, false_target: str, line: int) -> None:
        def emit_lt(rs_l: int, rs_r: int) -> None:
            vdiff = self.new_v()
            self.emit(ir.RInst("SUB", vdiff, rs_l, rs_r, line))
            vmsb = self.new_v()
            self.emit(ir.MoveImm(vmsb, self.ctx.pool_const(0x80000000), line))
            vand = self.new_v()
            self.emit(ir.RInst("AND", vand, vdiff, vmsb, line))
            self.emit(ir.BEQInst(vand, 0, false_target, line))
            self.emit(ir.BEQInst(0, 0, true_target, line))

        if isinstance(cond, A.BinOp) and cond.op in ("==", "!=", "<", ">", "<=", ">="):
            lreg, _ = self.expr(cond.left)
            rreg, _ = self.expr(cond.right)
            if cond.op == "==":
                self.emit(ir.BEQInst(lreg, rreg, true_target, line))
                self.emit(ir.BEQInst(0, 0, false_target, line))
                return
            if cond.op == "!=":
                self.emit(ir.BEQInst(lreg, rreg, false_target, line))
                self.emit(ir.BEQInst(0, 0, true_target, line))
                return
            if cond.op == "<":
                emit_lt(lreg, rreg)
                return
            if cond.op == ">":
                emit_lt(rreg, lreg)
                return
            if cond.op == "<=":
                self.emit(ir.BEQInst(lreg, rreg, true_target, line))
                emit_lt(lreg, rreg)
                return
            if cond.op == ">=":
                self.emit(ir.BEQInst(lreg, rreg, true_target, line))
                emit_lt(rreg, lreg)
                return
        vcond, _ = self.expr(cond)
        self.emit(ir.BEQInst(vcond, 0, false_target, line))
        self.emit(ir.BEQInst(0, 0, true_target, line))

    def _if_stmt(self, s: A.IfStmt) -> None:
        L_then = self.ctx.fresh_label("T")
        L_else = self.ctx.fresh_label("F")
        L_end = self.ctx.fresh_label("E")
        self._emit_cond_jump(s.cond, L_then, L_else, s.line)
        self.emit(ir.Label(L_then))
        self.stmt(s.then_branch)
        self.emit(ir.BEQInst(0, 0, L_end, s.line))
        self.emit(ir.Label(L_else))
        if s.else_branch:
            self.stmt(s.else_branch)
        self.emit(ir.Label(L_end))

    def _while_stmt(self, s: A.WhileStmt) -> None:
        L_top = self.ctx.fresh_label("W")
        L_body = self.ctx.fresh_label("B")
        L_end = self.ctx.fresh_label("X")
        self.emit(ir.Label(L_top))
        self._emit_cond_jump(s.cond, L_body, L_end, s.line)
        self.emit(ir.Label(L_body))
        self.stmt(s.body)
        self.emit(ir.BEQInst(0, 0, L_top, s.line))
        self.emit(ir.Label(L_end))

    def expr(self, e: A.Expr) -> tuple[int, int]:
        """Return (vreg, line)."""
        if isinstance(e, A.IntLiteral):
            v = self.new_v()
            lab = self.ctx.pool_const(e.value)
            self.emit(ir.MoveImm(v, lab, e.line))
            return v, e.line
        if isinstance(e, A.Ident):
            if e.name in self.locals:
                return self.locals[e.name], e.line
            if e.name in self.ctx.globals:
                v = self.new_v()
                gl = self.ctx.globals[e.name]
                self.emit(ir.LWInst(v, 0, 0, e.line))  # LW v, 0(r0) wrong - need symbol
                # encode as special: use MoveImm from global label
                self.ops.pop()
                self.emit(ir.MoveImm(v, gl, e.line))
                return v, e.line
            raise CompileError(f"unknown identifier {e.name!r}", e.line)
        if isinstance(e, A.ArrayRef):
            key = self._resolve_array_key(e.name)
            if key not in self.ctx.global_addrs or self.ctx.global_sizes.get(key, 0) <= 1:
                raise CompileError(f"unknown array {e.name!r}", e.line)
            vaddr = self.array_addr(e.name, e.index, e.line)
            v = self.new_v()
            self.emit(ir.LWInst(v, 0, vaddr, e.line))
            return v, e.line
        if isinstance(e, A.BinOp):
            if e.op == "-":
                if isinstance(e.left, A.IntLiteral) and e.left.value == 0:
                    r, _ = self.expr(e.right)
                    v = self.new_v()
                    self.emit(ir.RInst("SUB", v, 0, r, e.line))
                    return v, e.line
                l, _ = self.expr(e.left)
                r, _ = self.expr(e.right)
                v = self.new_v()
                self.emit(ir.RInst("SUB", v, l, r, e.line))
                return v, e.line
            if e.op == "+":
                l, _ = self.expr(e.left)
                r, _ = self.expr(e.right)
                v = self.new_v()
                self.emit(ir.RInst("ADD", v, l, r, e.line))
                return v, e.line
            if e.op == "*":
                l, _ = self.expr(e.left)
                r, _ = self.expr(e.right)
                v = self.new_v()
                self.emit(ir.RInst("MUL", v, l, r, e.line))
                return v, e.line
            if e.op == "&":
                l, _ = self.expr(e.left)
                r, _ = self.expr(e.right)
                v = self.new_v()
                self.emit(ir.RInst("AND", v, l, r, e.line))
                return v, e.line
            if e.op == "|":
                l, _ = self.expr(e.left)
                r, _ = self.expr(e.right)
                v = self.new_v()
                self.emit(ir.RInst("OR", v, l, r, e.line))
                return v, e.line
            if e.op == "^":
                l, _ = self.expr(e.left)
                r, _ = self.expr(e.right)
                v = self.new_v()
                self.emit(ir.RInst("XOR", v, l, r, e.line))
                return v, e.line
            if e.op == "<<":
                l, _ = self.expr(e.left)
                r, _ = self.expr(e.right)
                v = self.new_v()
                self.emit(ir.RInst("SLL", v, l, r, e.line))
                return v, e.line
            if e.op == ">>":
                l, _ = self.expr(e.left)
                r, _ = self.expr(e.right)
                v = self.new_v()
                self.emit(ir.RInst("SRL", v, l, r, e.line))
                return v, e.line
            if e.op in ("==", "!=", "<", ">", "<=", ">="):
                raise CompileError("boolean ops only in if/while head", e.line)
        if isinstance(e, A.Call):
            for i, arg in enumerate(e.args):
                vr, ln = self.expr(arg)
                dst = i + 1
                if vr != dst:
                    self.emit(ir.RInst("ADD", dst, vr, 0, ln))
            self.emit(ir.JALInst(e.name, e.line))
            v = self.new_v()
            self.emit(ir.RInst("ADD", v, 1, 0, e.line))
            return v, e.line
        raise CompileError(f"unsupported expression {type(e)}", getattr(e, "line", 0))


def _rewrite_moves_to_lw(
    ops: list[ir.IrOp], alloc: dict[int, int], data_off: dict[str, int]
) -> list[ir.IrOp]:
    out: list[ir.IrOp] = []
    for op in ops:
        if isinstance(op, ir.MoveImm):
            # Keep virtual destination here; allocation is applied exactly once later.
            rd = op.dst
            off = data_off.get(op.pool_label, 0)
            out.append(ir.LWInst(rd, off, 0, op.line))
        else:
            out.append(op)
    return out


def _apply_alloc(op: ir.IrOp, alloc: dict[int, int]) -> ir.IrOp:
    def m(v: int) -> int:
        if v == 0:
            return 0
        return alloc.get(v, v)

    if isinstance(op, ir.RInst):
        return ir.RInst(op.op, m(op.rd), m(op.rs1), m(op.rs2), op.line)
    if isinstance(op, ir.LWInst):
        return ir.LWInst(m(op.rd), op.imm, m(op.rs1), op.line)
    if isinstance(op, ir.SWInst):
        return ir.SWInst(m(op.rs2), op.imm, m(op.rs1), op.line)
    if isinstance(op, ir.BEQInst):
        return ir.BEQInst(m(op.rs1), m(op.rs2), op.target, op.line)
    if isinstance(op, ir.JRInst):
        # JR uses architectural register numbers directly (return path is r31).
        return ir.JRInst(op.rs, op.line)
    return op


def _build_data_offsets(ctx: CompileContext) -> dict[str, int]:
    data_off: dict[str, int] = {}
    off = 0

    for name, lab in ctx.globals.items():
        data_off[lab] = off
        off += 4 * ctx.global_sizes.get(name, 1)

    def _pool_key(kv: tuple[int, str]) -> int:
        return int(kv[1].split("_")[-1])

    for _, lab in sorted(ctx.pool.items(), key=_pool_key):
        data_off[lab] = off
        off += 4
    return data_off


def _lower_allocated_ops(fn: ir.FunctionIR, data_off: dict[str, int]) -> list[ir.IrOp]:
    alloc = linear_scan_allocate(fn.ops, list(range(1, fn.param_count + 1)))
    rops = _rewrite_moves_to_lw(fn.ops, alloc, data_off)
    return [_apply_alloc(op, alloc) for op in rops]


def emit_asm_text(funcs: list[ir.FunctionIR], ctx: CompileContext) -> str:
    lines: list[str] = []
    # .data: pool + globals at known offsets from __data_base
    data_off = _build_data_offsets(ctx)
    lines.append(".data")

    def _pool_key(kv: tuple[int, str]) -> int:
        return int(kv[1].split("_")[-1])

    for name, lab in ctx.globals.items():
        size = ctx.global_sizes.get(name, 1)
        if size == 1:
            init = ctx.global_inits.get(name, 0)
            lines.append(f"{lab}: .word {init}")
        else:
            arr_init = ctx.global_array_inits.get(name, [])
            first = arr_init[0] if arr_init else 0
            lines.append(f"{lab}: .word {first}")
            for i in range(1, size):
                v = arr_init[i] if i < len(arr_init) else 0
                lines.append(f"    .word {v}")
    for k, lab in sorted(ctx.pool.items(), key=_pool_key):
        lines.append(f"{lab}: .word {k}")
    lines.append("")
    lines.append(".text")
    lines.append("")

    for fn in funcs:
        lines.append(f"{fn.name}:")
        for op2 in _lower_allocated_ops(fn, data_off):
            if isinstance(op2, ir.Label):
                lines.append(f"{op2.name}:")
            elif isinstance(op2, ir.RInst):
                lines.append(f"    {op2.op} r{op2.rd}, r{op2.rs1}, r{op2.rs2}")
            elif isinstance(op2, ir.LWInst):
                lines.append(f"    LW r{op2.rd}, {op2.imm}(r{op2.rs1})")
            elif isinstance(op2, ir.SWInst):
                lines.append(f"    SW r{op2.rs2}, {op2.imm}(r{op2.rs1})")
            elif isinstance(op2, ir.BEQInst):
                lines.append(f"    BEQ r{op2.rs1}, r{op2.rs2}, {op2.target}")
            elif isinstance(op2, ir.JALInst):
                lines.append(f"    JAL {op2.target}")
            elif isinstance(op2, ir.JRInst):
                lines.append(f"    JR r{op2.rs}")
            elif isinstance(op2, ir.NOPInst):
                lines.append("    NOP")
            elif isinstance(op2, ir.MoveImm):
                pass  # rewritten
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def emit_opcode_map(
    funcs: list[ir.FunctionIR], ctx: CompileContext, text_base: int = 0
) -> dict[int, int]:
    if text_base < 0 or text_base % 4 != 0:
        raise CompileError("text base must be non-negative and 4-byte aligned", 0)

    data_off = _build_data_offsets(ctx)
    labels: dict[str, int] = {}
    linear: list[tuple[int, ir.IrOp]] = []

    pc = text_base
    for fn in funcs:
        labels[fn.name] = pc
        for op in _lower_allocated_ops(fn, data_off):
            if isinstance(op, ir.Label):
                labels[op.name] = pc
            else:
                linear.append((pc, op))
                pc += 4

    out: dict[int, int] = {}
    for pc, op in linear:
        word: int
        if isinstance(op, ir.RInst):
            funct = isa.FUNCT.get(op.op)
            if funct is None:
                raise CompileError(f"unknown R-type op {op.op!r}", op.line)
            word = isa.pack_r(op.rd, op.rs1, op.rs2, funct)
        elif isinstance(op, ir.LWInst):
            word = isa.pack_i_load(isa.LOAD_OPCODE, op.rd, op.rs1, op.imm)
        elif isinstance(op, ir.SWInst):
            word = isa.pack_i_store(isa.STORE_OPCODE, op.rs1, op.rs2, op.imm)
        elif isinstance(op, ir.BEQInst):
            tgt = labels.get(op.target)
            if tgt is None:
                raise CompileError(f"unknown branch label {op.target!r}", op.line)
            imm = (tgt - pc) // 4
            if (tgt - pc) % 4 != 0:
                raise CompileError("branch target must be 4-byte aligned", op.line)
            word = isa.pack_i_store(isa.BRANCH_OPCODE, op.rs1, op.rs2, imm)
        elif isinstance(op, ir.JALInst):
            tgt = labels.get(op.target)
            if tgt is None:
                raise CompileError(f"unknown jump label {op.target!r}", op.line)
            word = isa.pack_j(isa.JAL_OPCODE, (tgt >> 2) & ((1 << 26) - 1))
        elif isinstance(op, ir.JRInst):
            # Current hardware ISA has no JR opcode; treat as NOP so programs can halt cleanly.
            word = isa.pack_nop()
        elif isinstance(op, ir.NOPInst):
            word = isa.pack_nop()
        elif isinstance(op, (ir.MoveImm, ir.Label)):
            raise CompileError("internal encoding error: unresolved pseudo-op", op.line)
        else:
            raise CompileError(f"unsupported opcode class {type(op)!r}", getattr(op, "line", 0))
        out[pc] = word

    return out


def _compile_to_ir(source: str) -> tuple[list[ir.FunctionIR], CompileContext]:
    from minicc.parser import parse

    program = parse(source)
    _check_unsupported(program)
    ctx = CompileContext()
    func_list: list[A.FuncDecl] = []
    for d in program.decls:
        if isinstance(d, A.VarDecl):
            lab = f"_g_{d.name}"
            ctx.globals[d.name] = lab
            if d.array_len is not None:
                ctx.global_sizes[d.name] = d.array_len
                vals = d.array_init or []
                if len(vals) > d.array_len:
                    raise CompileError(f"too many initializers for array {d.name!r}", d.line)
                ctx.global_array_inits[d.name] = vals
                ctx.global_inits[d.name] = vals[0] if vals else 0
            else:
                ctx.global_sizes[d.name] = 1
                if d.array_init:
                    raise CompileError("scalar variable cannot use array initializer", d.line)
                if d.init and isinstance(d.init, A.IntLiteral):
                    ctx.global_inits[d.name] = d.init.value
                else:
                    ctx.global_inits[d.name] = 0
        elif isinstance(d, A.FuncDecl):
            ctx.funcs[d.name] = d
            func_list.append(d)

    # Globals are laid out first in .data in declaration order.
    off = 0
    for name in ctx.globals.keys():
        ctx.global_addrs[name] = off
        off += 4 * ctx.global_sizes.get(name, 1)
    ctx.next_data_addr = off

    ir_funcs: list[ir.FunctionIR] = []
    ordered_funcs = [f for f in func_list if f.name == "main"] + [
        f for f in func_list if f.name != "main"
    ]
    for f in ordered_funcs:
        gen = FunctionGen(ctx, f)
        ir_funcs.append(gen.lower())

    return ir_funcs, ctx


def compile_source(source: str) -> str:
    ir_funcs, ctx = _compile_to_ir(source)
    return emit_asm_text(ir_funcs, ctx)


def compile_source_with_opcodes(source: str, text_base: int = 0) -> tuple[str, dict[int, int]]:
    ir_funcs, ctx = _compile_to_ir(source)
    asm = emit_asm_text(ir_funcs, ctx)
    opcode_map = emit_opcode_map(ir_funcs, ctx, text_base=text_base)
    return asm, opcode_map
