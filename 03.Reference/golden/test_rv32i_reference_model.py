"""Testes unitários do Golden Model RV32I."""

import unittest
import tempfile
from pathlib import Path

from rv32i_reference_model import RV32IReferenceModel, MASK32


# ============================================================
# FUNÇÕES AUXILIARES PARA CODIFICAÇÃO DE INSTRUÇÕES
# ============================================================

def encode_r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return (
        ((funct7 & 0x7F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def encode_i(imm, rs1, funct3, rd, opcode=0x13):
    return (
        ((imm & 0xFFF) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def encode_s(imm, rs2, rs1, funct3, opcode=0x23):
    imm &= 0xFFF

    return (
        (((imm >> 5) & 0x7F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((imm & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def encode_b(imm, rs2, rs1, funct3, opcode=0x63):
    imm &= 0x1FFF

    return (
        (((imm >> 12) & 0x1) << 31)
        | (((imm >> 5) & 0x3F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | (((imm >> 1) & 0xF) << 8)
        | (((imm >> 11) & 0x1) << 7)
        | (opcode & 0x7F)
    )


def encode_u(imm, rd, opcode=0x37):
    return (
        (imm & 0xFFFFF000)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def encode_j(imm, rd, opcode=0x6F):
    imm &= 0x1FFFFF

    return (
        (((imm >> 20) & 0x1) << 31)
        | (((imm >> 1) & 0x3FF) << 21)
        | (((imm >> 11) & 0x1) << 20)
        | (((imm >> 12) & 0xFF) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


# ============================================================
# TESTES DO MODELO DE REFERÊNCIA
# ============================================================

class TestRV32IReferenceModel(unittest.TestCase):

    def setUp(self):
        self.cpu = RV32IReferenceModel()

    # --------------------------------------------------------
    # 1. INSTRUÇÕES R-TYPE
    # --------------------------------------------------------

    def test_r_type_instructions(self):

        self.cpu.regs[1] = 10
        self.cpu.regs[2] = 3

        instructions = [
            encode_r(0x00, 2, 1, 0x0, 3),   # ADD
            encode_r(0x20, 2, 1, 0x0, 4),   # SUB
            encode_r(0x00, 2, 1, 0x1, 5),   # SLL
            encode_r(0x00, 2, 1, 0x2, 6),   # SLT
            encode_r(0x00, 2, 1, 0x3, 7),   # SLTU
            encode_r(0x00, 2, 1, 0x4, 8),   # XOR
            encode_r(0x00, 2, 1, 0x5, 9),   # SRL
            encode_r(0x20, 2, 1, 0x5, 10),  # SRA
            encode_r(0x00, 2, 1, 0x6, 11),  # OR
            encode_r(0x00, 2, 1, 0x7, 12),  # AND
        ]

        self.cpu.load_instructions(instructions)
        trace = self.cpu.run()

        self.assertEqual(len(trace), 10)

        self.assertEqual(self.cpu.regs[3], 13)
        self.assertEqual(self.cpu.regs[4], 7)
        self.assertEqual(self.cpu.regs[5], 80)
        self.assertEqual(self.cpu.regs[6], 0)
        self.assertEqual(self.cpu.regs[7], 0)
        self.assertEqual(self.cpu.regs[8], 9)
        self.assertEqual(self.cpu.regs[9], 1)
        self.assertEqual(self.cpu.regs[10], 1)
        self.assertEqual(self.cpu.regs[11], 11)
        self.assertEqual(self.cpu.regs[12], 2)

    # --------------------------------------------------------
    # 2. INSTRUÇÕES I-TYPE
    # --------------------------------------------------------

    def test_i_type_instructions(self):

        self.cpu.regs[1] = 0xFFFFFFF0  # -16
        self.cpu.regs[2] = 3

        instructions = [
            encode_i(5, 1, 0x0, 3),       # ADDI
            encode_i(-20, 1, 0x2, 4),     # SLTI
            encode_i(10, 1, 0x3, 5),      # SLTIU
            encode_i(0x0F, 1, 0x4, 6),    # XORI
            encode_i(0x0F, 1, 0x6, 7),    # ORI
            encode_i(0x0F, 1, 0x7, 8),    # ANDI
            encode_i(2, 2, 0x1, 9),       # SLLI
            encode_i(1, 1, 0x5, 10),      # SRLI
            encode_i(0x402, 1, 0x5, 11),  # SRAI
        ]

        self.cpu.load_instructions(instructions)
        trace = self.cpu.run()

        self.assertEqual(len(trace), 9)

        self.assertEqual(self.cpu.regs[3], 0xFFFFFFF5)
        self.assertEqual(self.cpu.regs[4], 0)
        self.assertEqual(self.cpu.regs[5], 0)
        self.assertEqual(self.cpu.regs[6], 0xFFFFFFFF)
        self.assertEqual(self.cpu.regs[7], 0xFFFFFFFF)
        self.assertEqual(self.cpu.regs[8], 0)
        self.assertEqual(self.cpu.regs[9], 12)
        self.assertEqual(self.cpu.regs[10], 0x7FFFFFF8)
        self.assertEqual(self.cpu.regs[11], 0xFFFFFFFC)

    # --------------------------------------------------------
    # 3. LUI
    # --------------------------------------------------------

    def test_lui(self):

        instruction = encode_u(0x12345000, 5)

        self.cpu.load_instructions([instruction])
        self.cpu.step()

        self.assertEqual(self.cpu.regs[5], 0x12345000)

    # --------------------------------------------------------
    # 4. AUIPC
    # --------------------------------------------------------

    def test_auipc(self):

        instruction = encode_u(
            0x00001000,
            5,
            opcode=0x17
        )

        self.cpu.load_instructions([instruction])
        self.cpu.step()

        self.assertEqual(self.cpu.regs[5], 0x00001000)

    # --------------------------------------------------------
    # 5. SW E LW
    # --------------------------------------------------------

    def test_sw_and_lw(self):

        self.cpu.regs[1] = 0x00000000
        self.cpu.regs[2] = 0x12345678

        instructions = [
            encode_s(0, 2, 1, 0x2),             # SW x2, 0(x1)
            encode_i(0, 1, 0x2, 3, 0x03),       # LW x3, 0(x1)
        ]

        self.cpu.load_instructions(instructions)
        trace = self.cpu.run()

        self.assertEqual(len(trace), 2)

        self.assertEqual(
            self.cpu.read_word(0),
            0x12345678
        )

        self.assertEqual(
            self.cpu.regs[3],
            0x12345678
        )

    # --------------------------------------------------------
    # 6. MÚLTIPLOS ENDEREÇOS DA MEMÓRIA
    # --------------------------------------------------------

    def test_multiple_memory_addresses(self):

        self.cpu.write_word(0, 10)
        self.cpu.write_word(4, 20)
        self.cpu.write_word(8, 30)

        self.assertEqual(self.cpu.read_word(0), 10)
        self.assertEqual(self.cpu.read_word(4), 20)
        self.assertEqual(self.cpu.read_word(8), 30)

    # --------------------------------------------------------
    # 7. TODAS AS CONDIÇÕES DE BRANCH
    # --------------------------------------------------------

    def test_all_branch_conditions_taken_and_not_taken(self):

        cases = [
            # BEQ
            (0x0, 5, 5, True),
            (0x0, 5, 3, False),

            # BNE
            (0x1, 5, 3, True),
            (0x1, 5, 5, False),

            # BLT
            (0x4, 3, 5, True),
            (0x4, 5, 3, False),

            # BGE
            (0x5, 5, 3, True),
            (0x5, 3, 5, False),

            # BLTU
            (0x6, 3, 5, True),
            (0x6, 5, 3, False),

            # BGEU
            (0x7, 5, 3, True),
            (0x7, 3, 5, False),
        ]

        for funct3, a, b, expected_taken in cases:

            with self.subTest(
                funct3=funct3,
                a=a,
                b=b,
                expected=expected_taken
            ):

                cpu = RV32IReferenceModel()

                cpu.regs[1] = a & MASK32
                cpu.regs[2] = b & MASK32

                instruction = encode_b(
                    8,
                    rs2=2,
                    rs1=1,
                    funct3=funct3
                )

                cpu.load_instructions([instruction])

                result = cpu.step()

                # Verifica se a condição lógica do branch está correta.
                self.assertEqual(
                    result["branch_taken"],
                    expected_taken
                )

                # A ALU calcula a subtração dos operandos.
                self.assertEqual(
                    result["alu_result"],
                    (a - b) & MASK32
                )

                # Verifica o endereço do próximo PC.
                self.assertEqual(
                    result["next_pc"],
                    8 if expected_taken else 4
                )

    # --------------------------------------------------------
    # 8. COMPARAÇÕES COM NÚMEROS NEGATIVOS
    # --------------------------------------------------------

    def test_negative_signed_unsigned_comparisons(self):

        cases = [
            # BLT: -1 < 5 (verdadeiro)
            (0x4, -1, 5, True),

            # BLTU: 0xFFFFFFFF < 5 (falso)
            (0x6, -1, 5, False),

            # BGE: -1 >= 5 (falso)
            (0x5, -1, 5, False),

            # BGEU: 0xFFFFFFFF >= 5 (verdadeiro)
            (0x7, -1, 5, True),
        ]

        for funct3, a, b, expected in cases:

            with self.subTest(
                funct3=funct3,
                a=a,
                b=b
            ):

                cpu = RV32IReferenceModel()

                cpu.regs[1] = a & MASK32
                cpu.regs[2] = b & MASK32

                instruction = encode_b(
                    8,
                    rs2=2,
                    rs1=1,
                    funct3=funct3
                )

                cpu.load_instructions([instruction])

                result = cpu.step()

                self.assertEqual(
                    result["branch_taken"],
                    expected
                )

    # --------------------------------------------------------
    # 9. JAL
    # --------------------------------------------------------

    def test_jal(self):

        instruction = encode_j(8, 5)

        self.cpu.load_instructions([instruction])
        trace = self.cpu.run()

        self.assertEqual(len(trace), 1)
        self.assertEqual(self.cpu.regs[5], 4)
        self.assertEqual(self.cpu.pc, 8)

    # --------------------------------------------------------
    # 10. JALR
    # --------------------------------------------------------

    def test_jalr(self):

        self.cpu.regs[5] = 0x21

        instruction = encode_i(
            0,
            rs1=5,
            funct3=0,
            rd=6,
            opcode=0x67
        )

        self.cpu.load_instructions([instruction])
        result = self.cpu.step()

        # O bit menos significativo do endereço é zerado.
        self.assertEqual(self.cpu.pc, 0x20)

        # Endereço de retorno é PC + 4.
        self.assertEqual(self.cpu.regs[6], 4)

        self.assertEqual(result["next_pc"], 0x20)

    # --------------------------------------------------------
    # 11. REGISTRADOR ZERO (x0)
    # --------------------------------------------------------

    def test_x0_is_always_zero(self):

        self.cpu.regs[1] = 5

        instruction = encode_i(
            123,
            rs1=1,
            funct3=0,
            rd=0
        )

        self.cpu.load_instructions([instruction])
        self.cpu.run()

        self.assertEqual(self.cpu.regs[0], 0)
        self.assertEqual(self.cpu.read_reg(0), 0)

        # Também testa tentativa de escrita direta em x0.
        self.cpu.write_reg(0, 0xFFFFFFFF)

        self.assertEqual(self.cpu.regs[0], 0)

    # --------------------------------------------------------
    # 12. INCREMENTO SEQUENCIAL DO PC
    # --------------------------------------------------------

    def test_sequential_pc_increment(self):

        instructions = [
            encode_i(1, 0, 0, 1),  # ADDI x1, x0, 1
            encode_i(2, 0, 0, 2),  # ADDI x2, x0, 2
            encode_i(3, 0, 0, 3),  # ADDI x3, x0, 3
        ]

        self.cpu.load_instructions(instructions)

        trace = self.cpu.run()

        self.assertEqual(len(trace), 3)

        self.assertEqual(
            [item["next_pc"] for item in trace],
            [4, 8, 12]
        )

        self.assertEqual(self.cpu.pc, 12)

        self.assertEqual(self.cpu.regs[1], 1)
        self.assertEqual(self.cpu.regs[2], 2)
        self.assertEqual(self.cpu.regs[3], 3)

    # --------------------------------------------------------
    # 13. RESET
    # --------------------------------------------------------

    def test_reset(self):

        self.cpu.regs[1] = 10
        self.cpu.regs[2] = 20
        self.cpu.write_word(0, 100)

        self.cpu.pc = 16

        self.cpu.reset()

        self.assertEqual(self.cpu.pc, 0)
        self.assertTrue(all(reg == 0 for reg in self.cpu.regs))
        self.assertEqual(self.cpu.read_word(0), 0)

    # --------------------------------------------------------
    # 14. RESET PRESERVANDO MEMÓRIA DE DADOS
    # --------------------------------------------------------

    def test_reset_preserving_data_memory(self):

        self.cpu.regs[1] = 10
        self.cpu.write_word(4, 0x12345678)

        self.cpu.reset(clear_data_memory=False)

        self.assertEqual(self.cpu.pc, 0)
        self.assertEqual(self.cpu.regs[1], 0)

        self.assertEqual(
            self.cpu.read_word(4),
            0x12345678
        )

    # --------------------------------------------------------
    # 15. ACESSO DESALINHADO À MEMÓRIA
    # --------------------------------------------------------

    def test_unaligned_memory_access(self):

        with self.assertRaises(ValueError):
            self.cpu.read_word(2)

        with self.assertRaises(ValueError):
            self.cpu.write_word(6, 100)

    # --------------------------------------------------------
    # 16. ACESSO FORA DO INTERVALO DA MEMÓRIA
    # --------------------------------------------------------

    def test_out_of_range_memory_access(self):

        cpu = RV32IReferenceModel(dmem_words=4)

        with self.assertRaises(IndexError):
            cpu.read_word(16)

        with self.assertRaises(IndexError):
            cpu.write_word(16, 100)

    # --------------------------------------------------------
    # 17. CARREGAMENTO DE PROGRAMA HEXADECIMAL
    # --------------------------------------------------------

    def test_load_hex_program(self):

        instructions = [
            encode_i(5, 0, 0, 1),  # ADDI x1, x0, 5
            encode_i(3, 1, 0, 2),  # ADDI x2, x1, 3
        ]

        with tempfile.TemporaryDirectory() as temp_dir:

            hex_path = Path(temp_dir) / "test_program.hex"

            with hex_path.open("w", encoding="utf-8") as file:

                for instruction in instructions:
                    file.write(f"{instruction:08x}\n")

            cpu = RV32IReferenceModel()

            cpu.load_hex(hex_path)

            self.assertEqual(cpu.program_length, 2)

            trace = cpu.run()

            self.assertEqual(len(trace), 2)
            self.assertEqual(cpu.regs[1], 5)
            self.assertEqual(cpu.regs[2], 8)

    # --------------------------------------------------------
    # 18. JAL x0, 0 COMO INSTRUÇÃO DE PARADA
    # --------------------------------------------------------

    def test_jal_x0_zero_stops_execution(self):

        instructions = [
            encode_j(0, 0),         # JAL x0, 0
            encode_i(5, 0, 0, 1),   # ADDI x1, x0, 5
        ]

        self.cpu.load_instructions(instructions)

        trace = self.cpu.run(stop_on_self_jump=True)

        # Apenas a instrução JAL x0, 0 deve ser executada.
        self.assertEqual(len(trace), 1)

        self.assertEqual(self.cpu.pc, 0)

        # A segunda instrução não deve ser executada.
        self.assertEqual(self.cpu.regs[1], 0)


# ============================================================
# EXECUÇÃO DOS TESTES
# ============================================================

if __name__ == "__main__":
    unittest.main(verbosity=2)
