# Test firmware of the system verification. It runs any number of multiplications without being
# rebuilt: the environment writes each operation into the parameter block at the start of the
# data memory and sets CMD last; the firmware programs the DMA, starts it, polls STATUS until
# DONE, stores STATUS, clears CMD and only then counts the operation in DONE_COUNT.
# The order at the end matters: counting first would let a late CMD = 0 erase the next command.
#
# Only lui, addi, andi, lw, sw, beq, bne and jal are used, with word accesses, so any RV32I core
# that follows the interface contract runs it. Build: python3 03.Reference/tools/rv32i_asm.py.

.equ DMEM_BASE,      0x10000000
.equ DMAREG_BASE,    0x20000000

# Parameter block, byte offsets from DMEM_BASE.
.equ PB_CMD,         0
.equ PB_ADDR_A,      4
.equ PB_ADDR_B,      8
.equ PB_ADDR_C,      12
.equ PB_DIM_M,       16
.equ PB_DIM_K,       20
.equ PB_DIM_N,       24
.equ PB_FLAGS,       28
.equ PB_STATUS,      32
.equ PB_DONE_COUNT,  36

# FLAGS: bit 0 asks for the interrupt; the others inject faults on purpose.
.equ FLAG_IRQ_EN,       1
.equ FLAG_FAULT_DIM_K,  256
.equ FLAG_FAULT_HANG,   512

# DMA registers, byte offsets from DMAREG_BASE.
.equ DMA_ADDR_A,     0x00
.equ DMA_ADDR_B,     0x04
.equ DMA_ADDR_C,     0x08
.equ DMA_DIM_M,      0x0C
.equ DMA_DIM_K,      0x10
.equ DMA_DIM_N,      0x14
.equ DMA_CONTROL,    0x18
.equ DMA_STATUS,     0x1C

.equ CONTROL_START,         1
.equ CONTROL_START_IRQ_EN,  3
.equ STATUS_DONE,           2

start:
        li      s0, DMEM_BASE
        li      s1, DMAREG_BASE

wait_cmd:
        lw      t0, PB_CMD(s0)
        beq     t0, zero, wait_cmd

        lw      t1, PB_ADDR_A(s0)
        sw      t1, DMA_ADDR_A(s1)
        lw      t1, PB_ADDR_B(s0)
        sw      t1, DMA_ADDR_B(s1)
        lw      t1, PB_ADDR_C(s0)
        sw      t1, DMA_ADDR_C(s1)
        lw      t1, PB_DIM_M(s0)
        sw      t1, DMA_DIM_M(s1)

        lw      t2, PB_FLAGS(s0)
        lw      t1, PB_DIM_K(s0)
        andi    t3, t2, FLAG_FAULT_DIM_K
        beq     t3, zero, k_ok
        addi    t1, t1, -1
k_ok:
        sw      t1, DMA_DIM_K(s1)
        lw      t1, PB_DIM_N(s0)
        sw      t1, DMA_DIM_N(s1)

        li      t3, CONTROL_START
        andi    t4, t2, FLAG_IRQ_EN
        beq     t4, zero, go
        li      t3, CONTROL_START_IRQ_EN
go:
        sw      t3, DMA_CONTROL(s1)

poll:
        lw      t4, DMA_STATUS(s1)
        andi    t5, t4, STATUS_DONE
        beq     t5, zero, poll

        andi    t5, t2, FLAG_FAULT_HANG
        bne     t5, zero, hang

        sw      t4, PB_STATUS(s0)
        sw      zero, PB_CMD(s0)
        lw      t6, PB_DONE_COUNT(s0)
        addi    t6, t6, 1
        sw      t6, PB_DONE_COUNT(s0)
        jal     zero, wait_cmd

hang:
        jal     zero, hang
