.data
_arr_0: .word 1
    .word 2
    .word 3
    .word 4
    .word 5
    .word 6
    .word 7
    .word 8
    .word 9
    .word 10
__pool_1: .word 10
__pool_2: .word 4
__pool_3: .word 2147483648
__pool_4: .word 1
__pool_5: .word 40
__pool_6: .word 8

.text
main:
    ADD r1, r0, r0
    ADD r2, r0, r0
    LW r3, 56(r0)
    LW r5, 48(r0)
    LW r7, 60(r0)
W1:
    SUB r4, r2, r3
    AND r6, r4, r5
    BEQ r6, r0, E1
    BEQ r0, r0, B1
B1:
    LW r9, 0(r2)
    LW r10, 4(r2)
    ADD r1, r1, r9
    ADD r1, r1, r10
    ADD r2, r2, r7
    BEQ r0, r0, W1
E1:
    BEQ r0, r0, E1
    NOP