.data
__pool_1: .word 1
__pool_2: .word 2
__pool_3: .word 0
__pool_4: .word 10
__pool_5: .word 2147483648

.text

main:
    ADD r1, r0, r0
    ADD r2, r0, r0
    LW r3, 0(r0)
    ADD r1, r3, r0
    LW r4, 4(r0)
    ADD r2, r4, r0
    LW r5, 8(r0)
    ADD r6, r5, r0
    LW r7, 8(r0)
    ADD r8, r7, r0
W2:
    LW r9, 12(r0)
    SUB r10, r8, r9
    LW r11, 16(r0)
    AND r12, r10, r11
    BEQ r12, r0, X4
    BEQ r0, r0, B3
B3:
    ADD r13, r6, r8
    ADD r6, r13, r0
    LW r14, 0(r0)
    ADD r15, r8, r14
    ADD r8, r15, r0
    BEQ r0, r0, W2
X4:
    BEQ r0, r0, MAIN_END1
MAIN_END1:
    BEQ r0, r0, MAIN_END1
    NOP
