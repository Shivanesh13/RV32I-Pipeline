from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto

from minicc.errors import CompileError


class TokKind(Enum):
    INT = auto()
    IF = auto()
    WHILE = auto()
    FOR = auto()
    ELSE = auto()
    RETURN = auto()
    IDENT = auto()
    NUM = auto()
    PLUS = auto()
    MINUS = auto()
    PLUSPLUS = auto()
    MINUSMINUS = auto()
    PLUSEQ = auto()
    MINUSEQ = auto()
    STAR = auto()
    AMP = auto()
    PIPE = auto()
    CARET = auto()
    TILDE = auto()
    LSHIFT = auto()
    RSHIFT = auto()
    EQEQ = auto()
    NEQ = auto()
    LT = auto()
    GT = auto()
    LTE = auto()
    GTE = auto()
    EQ = auto()
    SEMI = auto()
    COMMA = auto()
    LPAREN = auto()
    RPAREN = auto()
    LBRACE = auto()
    RBRACE = auto()
    EOF = auto()


@dataclass
class Token:
    kind: TokKind
    lexeme: str
    line: int
    col: int
    value: int | None = None  # for NUM


_KEYWORDS = {
    "int": TokKind.INT,
    "if": TokKind.IF,
    "while": TokKind.WHILE,
    "for": TokKind.FOR,
    "else": TokKind.ELSE,
    "return": TokKind.RETURN,
}


def tokenize(source: str) -> list[Token]:
    tokens: list[Token] = []
    i = 0
    line = 1
    col = 1
    n = len(source)

    def err(msg: str) -> None:
        raise CompileError(msg, line, col)

    while i < n:
        c = source[i]
        if c in " \t\r":
            if c == "\t":
                col += 4
            else:
                col += 1
            i += 1
            continue
        if c == "\n":
            line += 1
            col = 1
            i += 1
            continue
        if c == "/" and i + 1 < n and source[i + 1] == "/":
            while i < n and source[i] != "\n":
                i += 1
            continue
        start_col = col
        if c.isalpha() or c == "_":
            j = i
            while j < n and (source[j].isalnum() or source[j] == "_"):
                j += 1
            lex = source[i:j]
            kind = _KEYWORDS.get(lex, TokKind.IDENT)
            tokens.append(Token(kind, lex, line, start_col))
            col += j - i
            i = j
            continue
        if c.isdigit():
            j = i
            while j < n and source[j].isdigit():
                j += 1
            num = int(source[i:j])
            tokens.append(Token(TokKind.NUM, source[i:j], line, start_col, num))
            col += j - i
            i = j
            continue
        two = source[i : i + 2]
        if two == "==":
            tokens.append(Token(TokKind.EQEQ, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == "++":
            tokens.append(Token(TokKind.PLUSPLUS, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == "--":
            tokens.append(Token(TokKind.MINUSMINUS, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == "+=":
            tokens.append(Token(TokKind.PLUSEQ, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == "-=":
            tokens.append(Token(TokKind.MINUSEQ, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == "!=":
            tokens.append(Token(TokKind.NEQ, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == "<=":
            tokens.append(Token(TokKind.LTE, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == ">=":
            tokens.append(Token(TokKind.GTE, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == "<<":
            tokens.append(Token(TokKind.LSHIFT, two, line, start_col))
            col += 2
            i += 2
            continue
        if two == ">>":
            tokens.append(Token(TokKind.RSHIFT, two, line, start_col))
            col += 2
            i += 2
            continue
        single = {
            "+": TokKind.PLUS,
            "-": TokKind.MINUS,
            "*": TokKind.STAR,
            "&": TokKind.AMP,
            "|": TokKind.PIPE,
            "^": TokKind.CARET,
            "~": TokKind.TILDE,
            "<": TokKind.LT,
            ">": TokKind.GT,
            "=": TokKind.EQ,
            ";": TokKind.SEMI,
            ",": TokKind.COMMA,
            "(": TokKind.LPAREN,
            ")": TokKind.RPAREN,
            "{": TokKind.LBRACE,
            "}": TokKind.RBRACE,
        }
        if c in single:
            tokens.append(Token(single[c], c, line, start_col))
            col += 1
            i += 1
            continue
        err(f"unexpected character {c!r}")

    tokens.append(Token(TokKind.EOF, "", line, col))
    return tokens
