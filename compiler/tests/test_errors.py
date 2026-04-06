import pytest

from minicc.errors import CompileError
from minicc.parser import parse


def test_parse_error_includes_line():
    with pytest.raises(CompileError) as ei:
        parse("int x = @;")
    assert ei.value.line is not None
