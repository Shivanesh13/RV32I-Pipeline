from __future__ import annotations

from minicc import ast_nodes as A
from minicc.errors import CompileError
from minicc.lexer import TokKind, Token


class Parser:
    def __init__(self, tokens: list[Token]):
        self.toks = tokens
        self.i = 0

    def _peek(self) -> Token:
        return self.toks[self.i]

    def _advance(self) -> Token:
        t = self.toks[self.i]
        self.i += 1
        return t

    def _expect(self, kind: TokKind, msg: str | None = None) -> Token:
        t = self._peek()
        if t.kind != kind:
            raise CompileError(msg or f"expected {kind.name}, got {t.kind.name}", t.line, t.col)
        return self._advance()

    def parse(self) -> A.Program:
        decls: list[A.Decl] = []
        while self._peek().kind != TokKind.EOF:
            decls.append(self._parse_decl())
        return A.Program(decls)

    def _parse_decl(self) -> A.VarDecl | A.FuncDecl:
        line = self._peek().line
        self._expect(TokKind.INT)
        name = self._expect(TokKind.IDENT, "expected identifier after int").lexeme
        if self._peek().kind == TokKind.LPAREN:
            self._advance()
            params: list[str] = []
            if self._peek().kind != TokKind.RPAREN:
                self._expect(TokKind.INT)
                params.append(self._expect(TokKind.IDENT).lexeme)
                while self._peek().kind == TokKind.COMMA:
                    self._advance()
                    self._expect(TokKind.INT)
                    params.append(self._expect(TokKind.IDENT).lexeme)
            self._expect(TokKind.RPAREN)
            body = self._parse_block()
            return A.FuncDecl(name, params, body, line)
        init = None
        if self._peek().kind == TokKind.EQ:
            self._advance()
            init = self._parse_expr()
        self._expect(TokKind.SEMI)
        return A.VarDecl(name, init, line)

    def _parse_block(self) -> A.Block:
        self._expect(TokKind.LBRACE)
        stmts: list[A.Stmt] = []
        while self._peek().kind != TokKind.RBRACE:
            stmts.append(self._parse_stmt())
        self._expect(TokKind.RBRACE)
        return A.Block(stmts)

    def _parse_assign_like_no_semi(self) -> A.Stmt:
        line = self._peek().line
        name = self._expect(TokKind.IDENT).lexeme
        op = self._advance()
        if op.kind == TokKind.EQ:
            return A.AssignStmt(name, self._parse_expr(), line)
        if op.kind == TokKind.PLUSEQ:
            rhs = self._parse_expr()
            return A.AssignStmt(name, A.BinOp("+", A.Ident(name, line), rhs, line), line)
        if op.kind == TokKind.MINUSEQ:
            rhs = self._parse_expr()
            return A.AssignStmt(name, A.BinOp("-", A.Ident(name, line), rhs, line), line)
        if op.kind == TokKind.PLUSPLUS:
            one = A.IntLiteral(1, line)
            return A.AssignStmt(name, A.BinOp("+", A.Ident(name, line), one, line), line)
        if op.kind == TokKind.MINUSMINUS:
            one = A.IntLiteral(1, line)
            return A.AssignStmt(name, A.BinOp("-", A.Ident(name, line), one, line), line)
        raise CompileError("expected assignment operator", op.line, op.col)

    def _parse_stmt(self) -> A.Stmt:
        t = self._peek()
        line = t.line
        if t.kind == TokKind.LBRACE:
            b = self._parse_block()
            return A.BlockStmt(b.stmts)
        if t.kind == TokKind.INT:
            decl = self._parse_local_vardecl()
            return A.VarDeclStmt(decl)
        if t.kind == TokKind.IF:
            self._advance()
            self._expect(TokKind.LPAREN)
            cond = self._parse_expr()
            self._expect(TokKind.RPAREN)
            then_b = self._parse_stmt()
            else_b = None
            if self._peek().kind == TokKind.ELSE:
                self._advance()
                else_b = self._parse_stmt()
            return A.IfStmt(cond, then_b, else_b, line)
        if t.kind == TokKind.WHILE:
            self._advance()
            self._expect(TokKind.LPAREN)
            cond = self._parse_expr()
            self._expect(TokKind.RPAREN)
            body = self._parse_stmt()
            return A.WhileStmt(cond, body, line)
        if t.kind == TokKind.FOR:
            return self._parse_for_stmt()
        if t.kind == TokKind.RETURN:
            self._advance()
            val = None
            if self._peek().kind != TokKind.SEMI:
                val = self._parse_expr()
            self._expect(TokKind.SEMI)
            return A.ReturnStmt(val, line)
        if t.kind == TokKind.IDENT and self.toks[self.i + 1].kind in (
            TokKind.EQ,
            TokKind.PLUSEQ,
            TokKind.MINUSEQ,
            TokKind.PLUSPLUS,
            TokKind.MINUSMINUS,
        ):
            st = self._parse_assign_like_no_semi()
            self._expect(TokKind.SEMI)
            return st
        expr = self._parse_expr()
        self._expect(TokKind.SEMI)
        return A.ExprStmt(expr, line)

    def _parse_simple_stmt_no_semi(self) -> A.Stmt:
        line = self._peek().line
        if self._peek().kind == TokKind.INT:
            return A.VarDeclStmt(self._parse_local_vardecl_no_semi())
        if self._peek().kind == TokKind.IDENT and self.toks[self.i + 1].kind in (
            TokKind.EQ,
            TokKind.PLUSEQ,
            TokKind.MINUSEQ,
            TokKind.PLUSPLUS,
            TokKind.MINUSMINUS,
        ):
            return self._parse_assign_like_no_semi()
        return A.ExprStmt(self._parse_expr(), line)

    def _parse_for_stmt(self) -> A.Stmt:
        line = self._peek().line
        self._expect(TokKind.FOR)
        self._expect(TokKind.LPAREN)

        init_stmt = None
        if self._peek().kind != TokKind.SEMI:
            init_stmt = self._parse_simple_stmt_no_semi()
        self._expect(TokKind.SEMI)

        cond = None
        if self._peek().kind != TokKind.SEMI:
            cond = self._parse_expr()
        self._expect(TokKind.SEMI)

        post_stmt = None
        if self._peek().kind != TokKind.RPAREN:
            post_stmt = self._parse_simple_stmt_no_semi()
        self._expect(TokKind.RPAREN)

        body = self._parse_stmt()
        body_stmts = body.stmts[:] if isinstance(body, A.BlockStmt) else [body]
        if post_stmt is not None:
            body_stmts.append(post_stmt)
        if cond is None:
            cond = A.BinOp("!=", A.IntLiteral(1, line), A.IntLiteral(0, line), line)
        while_stmt = A.WhileStmt(cond, A.BlockStmt(body_stmts), line)
        if init_stmt is not None:
            return A.BlockStmt([init_stmt, while_stmt])
        return while_stmt

    def _parse_local_vardecl(self) -> A.VarDecl:
        line = self._peek().line
        self._expect(TokKind.INT)
        name = self._expect(TokKind.IDENT).lexeme
        init = None
        if self._peek().kind == TokKind.EQ:
            self._advance()
            init = self._parse_expr()
        self._expect(TokKind.SEMI)
        return A.VarDecl(name, init, line)

    def _parse_local_vardecl_no_semi(self) -> A.VarDecl:
        line = self._peek().line
        self._expect(TokKind.INT)
        name = self._expect(TokKind.IDENT).lexeme
        init = None
        if self._peek().kind == TokKind.EQ:
            self._advance()
            init = self._parse_expr()
        return A.VarDecl(name, init, line)

    def _parse_expr(self) -> A.Expr:
        return self._parse_bitwise_or()

    def _parse_bitwise_or(self) -> A.Expr:
        left = self._parse_bitwise_xor()
        while self._peek().kind == TokKind.PIPE:
            op = self._advance().lexeme
            right = self._parse_bitwise_xor()
            left = A.BinOp(op, left, right, getattr(left, "line", self._peek().line))
        return left

    def _parse_bitwise_xor(self) -> A.Expr:
        left = self._parse_bitwise_and()
        while self._peek().kind == TokKind.CARET:
            op = self._advance().lexeme
            right = self._parse_bitwise_and()
            left = A.BinOp(op, left, right, getattr(left, "line", self._peek().line))
        return left

    def _parse_bitwise_and(self) -> A.Expr:
        left = self._parse_equality()
        while self._peek().kind == TokKind.AMP:
            op = self._advance().lexeme
            right = self._parse_equality()
            left = A.BinOp(op, left, right, getattr(left, "line", self._peek().line))
        return left

    def _parse_equality(self) -> A.Expr:
        left = self._parse_relational()
        while self._peek().kind in (TokKind.EQEQ, TokKind.NEQ):
            op = self._advance().lexeme
            right = self._parse_relational()
            left = A.BinOp(op, left, right, left.line if hasattr(left, "line") else self._peek().line)
        return left

    def _parse_relational(self) -> A.Expr:
        left = self._parse_shift()
        while self._peek().kind in (TokKind.LT, TokKind.GT, TokKind.LTE, TokKind.GTE):
            op = self._advance().lexeme
            right = self._parse_shift()
            left = A.BinOp(op, left, right, getattr(left, "line", self._peek().line))
        return left

    def _parse_shift(self) -> A.Expr:
        left = self._parse_additive()
        while self._peek().kind in (TokKind.LSHIFT, TokKind.RSHIFT):
            op = self._advance().lexeme
            right = self._parse_additive()
            left = A.BinOp(op, left, right, getattr(left, "line", self._peek().line))
        return left

    def _parse_additive(self) -> A.Expr:
        left = self._parse_multiplicative()
        while self._peek().kind in (TokKind.PLUS, TokKind.MINUS):
            op = self._advance().lexeme
            right = self._parse_multiplicative()
            line = getattr(left, "line", self._peek().line)
            left = A.BinOp(op, left, right, line)
        return left

    def _parse_multiplicative(self) -> A.Expr:
        left = self._parse_unary()
        while self._peek().kind == TokKind.STAR:
            self._advance()
            right = self._parse_unary()
            line = getattr(left, "line", self._peek().line)
            left = A.BinOp("*", left, right, line)
        return left

    def _parse_unary(self) -> A.Expr:
        if self._peek().kind == TokKind.MINUS:
            line = self._peek().line
            self._advance()
            inner = self._parse_unary()
            return A.BinOp("-", A.IntLiteral(0, line), inner, line)
        if self._peek().kind == TokKind.TILDE:
            line = self._peek().line
            self._advance()
            inner = self._parse_unary()
            return A.BinOp("^", inner, A.IntLiteral(-1, line), line)
        return self._parse_primary()

    def _parse_primary(self) -> A.Expr:
        t = self._peek()
        if t.kind == TokKind.NUM:
            self._advance()
            return A.IntLiteral(t.value or 0, t.line)
        if t.kind == TokKind.IDENT:
            name = self._advance().lexeme
            if self._peek().kind == TokKind.LPAREN:
                self._advance()
                args: list[A.Expr] = []
                if self._peek().kind != TokKind.RPAREN:
                    args.append(self._parse_expr())
                    while self._peek().kind == TokKind.COMMA:
                        self._advance()
                        args.append(self._parse_expr())
                self._expect(TokKind.RPAREN)
                return A.Call(name, args, t.line)
            return A.Ident(name, t.line)
        if t.kind == TokKind.LPAREN:
            self._advance()
            e = self._parse_expr()
            self._expect(TokKind.RPAREN)
            return e
        raise CompileError("expected expression", t.line, t.col)


def parse(source: str) -> A.Program:
    from minicc.lexer import tokenize

    return Parser(tokenize(source)).parse()
