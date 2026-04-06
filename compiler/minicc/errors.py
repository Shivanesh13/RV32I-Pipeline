from __future__ import annotations


class CompileError(Exception):
    def __init__(self, message: str, line: int | None = None, col: int | None = None):
        self.message = message
        self.line = line
        self.col = col
        super().__init__(self.format())

    def format(self) -> str:
        if self.line is not None:
            loc = f"line {self.line}"
            if self.col is not None:
                loc += f", col {self.col}"
            return f"{loc}: {self.message}"
        return self.message
