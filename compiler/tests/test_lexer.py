import pytest

from minicc.errors import CompileError
from minicc.lexer import TokKind, tokenize


def test_tokenize_keywords_and_ident():
    toks = tokenize("int foo;")
    kinds = [t.kind for t in toks[:-1]]
    assert kinds == [TokKind.INT, TokKind.IDENT, TokKind.SEMI]


def test_tokenize_number():
    toks = tokenize("42")
    assert toks[0].kind == TokKind.NUM
    assert toks[0].value == 42


def test_line_comment_skipped():
    toks = tokenize("// c\nint x;")
    assert toks[0].kind == TokKind.INT


def test_equality_operators():
    toks = tokenize("a == b != c")
    assert [t.kind for t in toks[:5]] == [
        TokKind.IDENT,
        TokKind.EQEQ,
        TokKind.IDENT,
        TokKind.NEQ,
        TokKind.IDENT,
    ]


def test_relational_shift_and_bitwise_tokens():
    toks = tokenize("for (i = 0; i <= 8; i = i << 1) { x = x | ~i; }")
    kinds = [t.kind for t in toks]
    assert TokKind.FOR in kinds
    assert TokKind.LTE in kinds
    assert TokKind.LSHIFT in kinds
    assert TokKind.PIPE in kinds
    assert TokKind.TILDE in kinds


def test_increment_and_compound_assign_tokens():
    toks = tokenize("i++; x += 3; y -= 1; z--;")
    kinds = [t.kind for t in toks]
    assert TokKind.PLUSPLUS in kinds
    assert TokKind.PLUSEQ in kinds
    assert TokKind.MINUSEQ in kinds
    assert TokKind.MINUSMINUS in kinds


def test_unexpected_character_line_col():
    with pytest.raises(CompileError) as ei:
        tokenize("x @ y")
    e = ei.value
    assert e.line == 1
    assert e.col is not None
    assert "unexpected" in e.message.lower()
