from minicc import isa
from minicc.codegen import compile_source, compile_source_with_opcodes


def test_arithmetic_and_return():
    asm = compile_source(
        """
        int add3() {
            int a; int b; int c;
            a = 1;
            b = 2;
            c = a + b * 3;
            return c & 7 ^ 1;
        }
        """
    )
    assert ".data" in asm
    assert ".text" in asm
    assert "add3:" in asm
    assert "ADD r" in asm
    assert "MUL r" in asm
    assert "AND r" in asm
    assert "XOR r" in asm
    assert "JR r31" in asm


def test_unary_minus():
    asm = compile_source(
        """
        int neg() {
            int x;
            x = -5;
            return x;
        }
        """
    )
    assert "SUB r" in asm


def test_while_neq():
    asm = compile_source(
        """
        int count() {
            int n;
            n = 3;
            while (n != 0) {
                n = n - 1;
            }
            return n;
        }
        """
    )
    assert "BEQ r" in asm
    assert "BEQ r" in asm  # loop exit and back-edge


def test_if_without_else():
    asm = compile_source(
        """
        int pick() {
            int a; int b; int r;
            a = 1; b = 1; r = 0;
            if (a == b) { r = 1; }
            return r;
        }
        """
    )
    assert asm.count("BEQ r") >= 2


def test_if_with_else():
    asm = compile_source(
        """
        int pick() {
            int a; int b;
            a = 0; b = 1;
            if (a == b) { return 1; } else { return 2; }
        }
        """
    )
    assert "JR r31" in asm


def test_function_call_and_global_load():
    asm = compile_source(
        """
        int g = 10;
        int id(int x) { return x; }
        int main() {
            int y;
            y = id(g);
            return y;
        }
        """
    )
    assert "_g_g:" in asm
    assert "JAL id" in asm
    assert "LW r" in asm


def test_one_instruction_or_label_per_line_shape():
    asm = compile_source("int z() { return 0; }")
    for line in asm.splitlines():
        if not line.strip():
            continue
        assert line == line.strip() or line.startswith("    ")


def test_for_loop_relational_and_bitwise_ops():
    asm = compile_source(
        """
        int main() {
            int i; int s;
            i = 0; s = 0;
            for (i = 0; i < 4; i = i + 1) {
                s = (s | i) ^ (i << 1);
            }
            return s >> 1;
        }
        """
    )
    assert "OR r" in asm
    assert "XOR r" in asm
    assert "SLL r" in asm
    assert "SRL r" in asm
    assert "BEQ r" in asm


def test_for_loop_with_increment_and_plus_equal():
    asm = compile_source(
        """
        int main() {
            int i; int sum;
            sum = 0;
            for (i = 0; i < 10; i++) {
                sum += i;
            }
            return sum;
        }
        """
    )
    assert "ADD r" in asm
    assert "BEQ r" in asm


def test_jr_uses_return_register_r31():
    asm = compile_source("int f() { return 0; }")
    assert "JR r31" in asm


def test_main_return_is_terminator_not_jr():
    asm = compile_source("int main() { return 1; }")
    assert "JR r31" not in asm
    assert "BEQ r0, r0, MAIN_END" in asm


def test_main_emitted_first_in_text():
    asm = compile_source(
        """
        int helper() { return 7; }
        int main() { return 0; }
        """
    )
    assert asm.index("main:") < asm.index("helper:")


def test_generated_asm_has_no_use_before_def():
    asm = compile_source(
        """
        int main() {
            int a;
            int b;
            a = 1;
            b = 2;
            int sum = 0;
            for (int i = 0; i < 10; i++) {
                sum += i;
            }
            return 0;
        }
        """
    )
    defined = {0}
    for raw in asm.splitlines():
        line = raw.strip()
        if not line or line.endswith(":") or line.startswith("."):
            continue
        parts = line.replace(",", "").replace("(", " ").replace(")", " ").split()
        op = parts[0]
        regs = [int(tok[1:]) for tok in parts[1:] if tok.startswith("r") and tok[1:].isdigit()]
        if op in ("ADD", "SUB", "MUL", "AND", "OR", "XOR", "SLL", "SRL"):
            rd, rs1, rs2 = regs
            assert rs1 in defined
            assert rs2 in defined
            defined.add(rd)
        elif op == "LW":
            rd, rs1 = regs
            assert rs1 in defined
            defined.add(rd)
        elif op == "SW":
            rs2, rs1 = regs
            assert rs1 in defined
            assert rs2 in defined
        elif op == "BEQ":
            rs1, rs2 = regs[:2]
            assert rs1 in defined
            assert rs2 in defined
        elif op == "JR":
            rs = regs[0]
            assert rs in defined or rs == 31
        elif op == "NOP":
            pass


def test_opcode_map_simple_arithmetic_sequence():
    _, opcodes = compile_source_with_opcodes(
        """
        int z() {
            int a;
            a = 7;
            return a;
        }
        """,
        text_base=0x3000,
    )
    words = [opcodes[pc] for pc in sorted(opcodes)]
    assert len(words) >= 3
    assert words[-1] == isa.pack_nop()  # lowered JR fallback


def test_opcode_map_resolves_branch_and_jump_labels():
    _, opcodes = compile_source_with_opcodes(
        """
        int f() { return 1; }
        int g() {
            int a; int b;
            a = 1; b = 2;
            if (a == b) { return f(); }
            return 0;
        }
        """,
        text_base=0x3000,
    )
    words = list(opcodes.values())
    assert any((w >> 26) == isa.BRANCH_OPCODE for w in words)
    assert any((w >> 26) == isa.JAL_OPCODE for w in words)
