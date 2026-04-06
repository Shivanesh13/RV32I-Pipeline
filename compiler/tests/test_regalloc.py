from minicc import ir
from minicc.regalloc import linear_scan_allocate


def test_vreg_zero_maps_to_r0():
    ops: list[ir.IrOp] = [
        ir.RInst("ADD", 1, 0, 0, 1),
        ir.RInst("SUB", 2, 1, 0, 1),
    ]
    alloc = linear_scan_allocate(ops, [])
    assert alloc[0] == 0
    assert alloc[1] != 0
    assert alloc[2] != 0


def test_params_pinned_to_r1_r2():
    ops: list[ir.IrOp] = [
        ir.RInst("ADD", 3, 1, 2, 1),
    ]
    alloc = linear_scan_allocate(ops, [1, 2])
    assert alloc[1] == 1
    assert alloc[2] == 2
