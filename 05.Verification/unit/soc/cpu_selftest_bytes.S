# Byte and half-word accesses, which the Python reference model does not run. The program checks
# itself and leaves at RESULT either 0x600D or the number of the first check that failed.

.equ BUF,     0x200
.equ RESULT,  0x2FC

        li      s0, BUF
        li      t0, 0x11223344
        sw      t0, 0(s0)

        li      t1, 0xAB
        sb      t1, 1(s0)
        lw      t2, 0(s0)
        li      t3, 0x1122AB44
        li      a0, 1
        bne     t2, t3, fail

        li      t1, -2
        sh      t1, 2(s0)
        lw      t2, 0(s0)
        li      t3, 0xFFFEAB44
        li      a0, 2
        bne     t2, t3, fail

        lb      t2, 1(s0)
        li      t3, -85
        li      a0, 3
        bne     t2, t3, fail

        lbu     t2, 1(s0)
        li      t3, 0xAB
        li      a0, 4
        bne     t2, t3, fail

        lh      t2, 2(s0)
        li      t3, -2
        li      a0, 5
        bne     t2, t3, fail

        lhu     t2, 2(s0)
        li      t3, 0xFFFE
        li      a0, 6
        bne     t2, t3, fail

        lb      t2, 0(s0)
        li      t3, 0x44
        li      a0, 7
        bne     t2, t3, fail

        sb      zero, 3(s0)
        lw      t2, 0(s0)
        li      t3, 0x00FEAB44
        li      a0, 8
        bne     t2, t3, fail

        li      a0, 0x600D
fail:   li      t0, RESULT
        sw      a0, 0(t0)
end:    j       end
