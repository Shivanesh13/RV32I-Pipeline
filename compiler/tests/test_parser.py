from minicc import ast_nodes as A
from minicc.parser import parse


def test_global_int_and_function():
    p = parse(
        """
        int g = 1;
        int main() {
            return 0;
        }
        """
    )
    assert len(p.decls) == 2
    assert isinstance(p.decls[0], A.VarDecl)
    assert p.decls[0].name == "g"
    assert isinstance(p.decls[1], A.FuncDecl)
    assert p.decls[1].name == "main"


def test_if_else_parsed():
    p = parse(
        """
        int f() {
            if (a == b) { return 1; } else { return 2; }
        }
        """
    )
    fn = p.decls[0]
    assert isinstance(fn, A.FuncDecl)
    st = fn.body.stmts[0]
    assert isinstance(st, A.IfStmt)
    assert st.else_branch is not None


def test_while_and_call():
    p = parse(
        """
        int g(int x) {
            while (x != 0) { x = x - 1; }
            return foo(1, 2);
        }
        """
    )
    fn = p.decls[0]
    w = fn.body.stmts[0]
    assert isinstance(w, A.WhileStmt)
    ret = fn.body.stmts[1]
    assert isinstance(ret, A.ReturnStmt)
    assert isinstance(ret.value, A.Call)
    assert ret.value.name == "foo"


def test_for_loop_desugars_to_block_and_while():
    p = parse(
        """
        int f() {
            int s;
            s = 0;
            for (int i = 0; i < 4; i = i + 1) {
                s = s + i;
            }
            return s;
        }
        """
    )
    fn = p.decls[0]
    assert isinstance(fn, A.FuncDecl)
    assert isinstance(fn.body.stmts[2], A.BlockStmt)
    loop_block = fn.body.stmts[2]
    assert isinstance(loop_block.stmts[1], A.WhileStmt)
