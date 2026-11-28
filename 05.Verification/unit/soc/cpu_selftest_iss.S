# Every instruction the Python RV32I reference model runs, so the CPU model can be compared with
# it register by register and word by word. Data lives at low addresses because the reference
# model has its data memory at address 0. Ends in a jump to itself.

        lui     x1, 0x12345
        addi    x2, x0, -7
        addi    x3, x0, 21
        add     x4, x1, x3
        sub     x5, x3, x2
        sll     x6, x3, x3
        slt     x7, x2, x3
        sltu    x8, x2, x3
        xor     x9, x1, x2
        addi    x11, x0, 4
        srl     x10, x2, x11
        sra     x12, x2, x11
        or      x13, x1, x3
        and     x14, x1, x2
        slti    x15, x2, -6
        sltiu   x16, x3, 22
        xori    x17, x3, -1
        ori     x18, x2, 0x0F0
        andi    x19, x1, 0x7FF
        slli    x20, x3, 27
        srli    x21, x2, 28
        srai    x22, x2, 1
        auipc   x23, 1
        sw      x4, 0x100(x0)
        sw      x2, 0x104(x0)
        lw      x24, 0x100(x0)
        lw      x25, 0x104(x0)

# Taken branches skip an addi, branches not taken run it: x26 ends as a fingerprint of all twelve.
        addi    x26, x0, 0
        beq     x3, x3, b1
        addi    x26, x26, 1
b1:     bne     x3, x2, b2
        addi    x26, x26, 2
b2:     blt     x2, x3, b3
        addi    x26, x26, 4
b3:     bge     x3, x2, b4
        addi    x26, x26, 8
b4:     bltu    x3, x2, b5
        addi    x26, x26, 16
b5:     bgeu    x2, x3, b6
        addi    x26, x26, 32
b6:     beq     x3, x2, b7
        addi    x26, x26, 64
b7:     bne     x3, x3, b8
        addi    x26, x26, 128
b8:     blt     x3, x2, b9
        addi    x26, x26, 256
b9:     bge     x2, x3, b10
        addi    x26, x26, 512
b10:    bltu    x2, x3, b11
        addi    x26, x26, 1024
b11:    bgeu    x3, x2, b12
        addi    x26, x26, 2047
b12:    jal     x27, sub1
        addi    x28, x0, 77
        jal     x0, done
sub1:   addi    x29, x0, 99
        jalr    x30, 0(x27)
done:   addi    x31, x0, 1
        sw      x26, 0x108(x0)
end:    jal     x0, end
