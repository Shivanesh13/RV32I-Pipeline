from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional, Union


Decl = Union["VarDecl", "FuncDecl"]


@dataclass
class Program:
    decls: list[Decl]


@dataclass
class VarDecl:
    name: str
    init: Optional["Expr"]
    line: int


@dataclass
class FuncDecl:
    name: str
    params: list[str]
    body: "Block"
    line: int


@dataclass
class Block:
    stmts: list["Stmt"]


Stmt = "VarDeclStmt | AssignStmt | IfStmt | WhileStmt | ReturnStmt | ExprStmt | BlockStmt"


@dataclass
class BlockStmt:
    stmts: list["Stmt"]


@dataclass
class VarDeclStmt:
    decl: VarDecl


@dataclass
class AssignStmt:
    name: str
    value: "Expr"
    line: int


@dataclass
class IfStmt:
    cond: "Expr"
    then_branch: "Stmt"
    else_branch: Optional["Stmt"]
    line: int


@dataclass
class WhileStmt:
    cond: "Expr"
    body: "Stmt"
    line: int


@dataclass
class ReturnStmt:
    value: Optional["Expr"]
    line: int


@dataclass
class ExprStmt:
    expr: "Expr"
    line: int


Expr = "IntLiteral | Ident | BinOp | Call"


@dataclass
class IntLiteral:
    value: int
    line: int


@dataclass
class Ident:
    name: str
    line: int


@dataclass
class BinOp:
    op: str  # + - * & | ^ << >> == != < > <= >=
    left: Expr
    right: Expr
    line: int


@dataclass
class Call:
    name: str
    args: list[Expr]
    line: int
