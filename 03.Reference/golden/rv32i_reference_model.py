"""Modelo de referência funcional para um subconjunto RV32I.

O modelo executa instruções de 32 bits e mantém o estado arquitetural da CPU:
PC, registradores x0-x31 e memória de dados.
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable, Optional


MASK32 = 0xFFFFFFFF
NOP = 0x00000013  # addi x0, x0, 0
IMEM_WORDS = 256
DMEM_WORDS = 256


def u32(value: int) -> int:
    """Retorna value representado como inteiro sem sinal de 32 bits."""
    return value & MASK32


def signed32(value: int) -> int:
    """Interpreta os 32 bits de value como inteiro com sinal (complemento de 2)."""
    value &= MASK32
    return value - (1 << 32) if value & 0x80000000 else value


def sign_extend(value: int, bits: int) -> int:
    """Estende o sinal de um campo de bits para um inteiro Python."""
    sign_bit = 1 << (bits - 1)
    return (value ^ sign_bit) - sign_bit


class RV32IReferenceModel:
    """Modelo de referência para 31 instruções do conjunto RV32I usado no projeto."""

    def __init__(self, imem_words: int = IMEM_WORDS, dmem_words: int = DMEM_WORDS):
        if imem_words <= 0 or dmem_words <= 0:
            raise ValueError("As memórias devem possuir pelo menos uma palavra.")

        self.imem_words = imem_words
        self.dmem_words = dmem_words

        # A memória é preenchida com NOPs, mas program_length registra apenas
        # quantas instruções válidas foram efetivamente carregadas.
        self.imem = [NOP] * self.imem_words
        self.instruction_memory = self.imem
        self.program_length = 0

        self.dmem = [0] * self.dmem_words
        self.data_memory = self.dmem

        self.regs = [0] * 32
        self.pc = 0

    # ------------------------------------------------------------------
    # Estado e carregamento do programa
    # ------------------------------------------------------------------

    def reset(self, clear_data_memory: bool = True) -> None:
        """Reinicia PC e registradores; opcionalmente limpa a memória de dados.

        A memória de instruções e o tamanho do programa são preservados.
        """
        self.pc = 0
        self.regs = [0] * 32

        if clear_data_memory:
            self.dmem = [0] * self.dmem_words
            self.data_memory = self.dmem

    def load_instructions(self, instructions: Iterable[int]) -> None:
        """Carrega uma sequência de palavras de 32 bits na memória de instruções."""
        words = [u32(int(instr)) for instr in instructions]

        if len(words) > self.imem_words:
            raise ValueError(
                f"Programa possui {len(words)} instruções, mas a memória comporta "
                f"{self.imem_words}."
            )

        self.imem = [NOP] * self.imem_words
        self.instruction_memory = self.imem

        for index, instr in enumerate(words):
            self.imem[index] = instr

        # Registra o número real de instruções carregadas.
        self.program_length = len(words)

        self.pc = 0

    def load_hex(self, filename: str | Path) -> None:
        """Carrega arquivo hexadecimal, uma instrução de 32 bits por linha.

        Linhas vazias e comentários iniciados por #, // ou ; são ignorados.
        Também são aceitos comentários ao final da linha.
        """
        path = Path(filename)

        if not path.is_file():
            raise FileNotFoundError(f"Arquivo hexadecimal não encontrado: {path}")

        instructions: list[int] = []

        with path.open("r", encoding="utf-8") as file:
            for line_number, raw_line in enumerate(file, start=1):
                line = raw_line.strip()

                if not line or line.startswith(("#", "//", ";")):
                    continue

                # Remove comentários de fim de linha.
                for marker in ("#", "//", ";"):
                    if marker in line:
                        line = line.split(marker, 1)[0].strip()

                if not line:
                    continue

                token = line.split()[0]

                try:
                    instruction = int(token, 16)
                except ValueError as exc:
                    raise ValueError(
                        f"Valor hexadecimal inválido na linha {line_number}: {token!r}"
                    ) from exc

                if instruction < 0 or instruction > MASK32:
                    raise ValueError(
                        f"Instrução fora de 32 bits na linha {line_number}: {token}"
                    )

                instructions.append(instruction)

        # load_instructions também atualiza program_length.
        self.load_instructions(instructions)

    # ------------------------------------------------------------------
    # Registradores
    # ------------------------------------------------------------------

    def read_reg(self, index: int) -> int:
        if not 0 <= index < 32:
            raise IndexError(f"Registrador inválido: x{index}")

        return 0 if index == 0 else self.regs[index]

    def write_reg(self, index: int, value: int) -> None:
        if not 0 <= index < 32:
            raise IndexError(f"Registrador inválido: x{index}")

        if index != 0:
            self.regs[index] = u32(value)

        # x0 sempre permanece zero.
        self.regs[0] = 0

    # ------------------------------------------------------------------
    # Geração de imediatos
    # ------------------------------------------------------------------

    @staticmethod
    def imm_i(instr: int) -> int:
        return sign_extend((instr >> 20) & 0xFFF, 12)

    @staticmethod
    def imm_s(instr: int) -> int:
        value = (((instr >> 25) & 0x7F) << 5) | ((instr >> 7) & 0x1F)
        return sign_extend(value, 12)

    @staticmethod
    def imm_b(instr: int) -> int:
        value = (
            (((instr >> 31) & 0x1) << 12)
            | (((instr >> 7) & 0x1) << 11)
            | (((instr >> 25) & 0x3F) << 5)
            | (((instr >> 8) & 0xF) << 1)
        )

        return sign_extend(value, 13)

    @staticmethod
    def imm_u(instr: int) -> int:
        return instr & 0xFFFFF000

    @staticmethod
    def imm_j(instr: int) -> int:
        value = (
            (((instr >> 31) & 0x1) << 20)
            | (((instr >> 12) & 0xFF) << 12)
            | (((instr >> 20) & 0x1) << 11)
            | (((instr >> 21) & 0x3FF) << 1)
        )

        return sign_extend(value, 21)

    # ------------------------------------------------------------------
    # Memória de dados
    # ------------------------------------------------------------------

    def _check_address(self, address: int) -> int:
        """Valida endereço de palavra e retorna o índice correspondente."""
        address = u32(address)

        if address & 0x3:
            raise ValueError(f"Acesso desalinhado à memória: 0x{address:08X}")

        index = address // 4

        if index >= self.dmem_words:
            raise IndexError(
                f"Endereço de memória fora do intervalo: 0x{address:08X}"
            )

        return index

    def read_word(self, address: int) -> int:
        return self.dmem[self._check_address(address)]

    def write_word(self, address: int, value: int) -> None:
        self.dmem[self._check_address(address)] = u32(value)

    # Aliases explícitos, úteis em scripts de validação.
    def read_data_memory(self, address: int) -> int:
        return self.read_word(address)

    def write_data_memory(self, address: int, value: int) -> None:
        self.write_word(address, value)

    # ------------------------------------------------------------------
    # Busca e execução de instruções
    # ------------------------------------------------------------------

    def fetch(self) -> int:
        if self.pc & 0x3:
            raise ValueError(f"PC desalinhado: 0x{self.pc:08X}")

        index = self.pc // 4

        if index >= self.imem_words:
            raise IndexError(
                f"Instruction address out of range: 0x{self.pc:08X}"
            )

        return self.imem[index]

    def step(self) -> dict:
        """Busca, decodifica e executa uma instrução; retorna os sinais/resultados."""
        pc_current = u32(self.pc)
        instr = self.fetch()

        opcode = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        funct3 = (instr >> 12) & 0x7
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        funct7 = (instr >> 25) & 0x7F

        a = self.read_reg(rs1)
        b = self.read_reg(rs2)

        next_pc = u32(pc_current + 4)

        alu_result: Optional[int] = None
        reg_write_enable = False
        reg_write_data: Optional[int] = None
        register_updated = False

        mem_write_enable = False
        mem_address: Optional[int] = None
        mem_write_data: Optional[int] = None
        mem_read_data: Optional[int] = None

        branch_taken = False

        # --------------------------------------------------------------
        # R-type: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND.
        # --------------------------------------------------------------

        if opcode == 0x33:
            reg_write_enable = True
            shamt = b & 0x1F

            if funct3 == 0x0 and funct7 == 0x00:       # ADD
                alu_result = u32(a + b)

            elif funct3 == 0x0 and funct7 == 0x20:     # SUB
                alu_result = u32(a - b)

            elif funct3 == 0x1 and funct7 == 0x00:     # SLL
                alu_result = u32(a << shamt)

            elif funct3 == 0x2 and funct7 == 0x00:     # SLT
                alu_result = int(signed32(a) < signed32(b))

            elif funct3 == 0x3 and funct7 == 0x00:     # SLTU
                alu_result = int(a < b)

            elif funct3 == 0x4 and funct7 == 0x00:     # XOR
                alu_result = u32(a ^ b)

            elif funct3 == 0x5 and funct7 == 0x00:     # SRL
                alu_result = u32(a >> shamt)

            elif funct3 == 0x5 and funct7 == 0x20:     # SRA
                alu_result = u32(signed32(a) >> shamt)

            elif funct3 == 0x6 and funct7 == 0x00:     # OR
                alu_result = u32(a | b)

            elif funct3 == 0x7 and funct7 == 0x00:     # AND
                alu_result = u32(a & b)

            else:
                raise ValueError(
                    f"Instrução R-type não suportada: 0x{instr:08X}"
                )

            reg_write_data = alu_result

        # --------------------------------------------------------------
        # I-type: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI.
        # --------------------------------------------------------------

        elif opcode == 0x13:
            immediate = self.imm_i(instr)
            immediate_u = u32(immediate)
            shamt = (instr >> 20) & 0x1F

            reg_write_enable = True

            if funct3 == 0x0:                         # ADDI
                alu_result = u32(a + immediate)

            elif funct3 == 0x2:                       # SLTI
                alu_result = int(signed32(a) < immediate)

            elif funct3 == 0x3:                       # SLTIU
                alu_result = int(a < immediate_u)

            elif funct3 == 0x4:                       # XORI
                alu_result = u32(a ^ immediate_u)

            elif funct3 == 0x6:                       # ORI
                alu_result = u32(a | immediate_u)

            elif funct3 == 0x7:                       # ANDI
                alu_result = u32(a & immediate_u)

            elif funct3 == 0x1 and funct7 == 0x00:     # SLLI
                alu_result = u32(a << shamt)

            elif funct3 == 0x5 and funct7 == 0x00:     # SRLI
                alu_result = u32(a >> shamt)

            elif funct3 == 0x5 and funct7 == 0x20:     # SRAI
                alu_result = u32(signed32(a) >> shamt)

            else:
                raise ValueError(
                    f"Instrução I-type não suportada: 0x{instr:08X}"
                )

            reg_write_data = alu_result

        # --------------------------------------------------------------
        # LW.
        # --------------------------------------------------------------

        elif opcode == 0x03:
            if funct3 != 0x2:
                raise ValueError(f"Load não suportado: 0x{instr:08X}")

            address = u32(a + self.imm_i(instr))

            mem_address = address
            alu_result = address
            mem_read_data = self.read_word(address)

            reg_write_enable = True
            reg_write_data = mem_read_data

        # --------------------------------------------------------------
        # SW.
        # --------------------------------------------------------------

        elif opcode == 0x23:
            if funct3 != 0x2:
                raise ValueError(f"Store não suportado: 0x{instr:08X}")

            address = u32(a + self.imm_s(instr))

            mem_address = address
            alu_result = address
            mem_write_data = b

            self.write_word(address, b)
            mem_write_enable = True

        # --------------------------------------------------------------
        # Branches: BEQ, BNE, BLT, BGE, BLTU, BGEU.
        # --------------------------------------------------------------

        elif opcode == 0x63:
            immediate = self.imm_b(instr)

            alu_result = u32(a - b)

            if funct3 == 0x0:                         # BEQ
                branch_taken = a == b

            elif funct3 == 0x1:                       # BNE
                branch_taken = a != b

            elif funct3 == 0x4:                       # BLT
                branch_taken = signed32(a) < signed32(b)

            elif funct3 == 0x5:                       # BGE
                branch_taken = signed32(a) >= signed32(b)

            elif funct3 == 0x6:                       # BLTU
                branch_taken = a < b

            elif funct3 == 0x7:                       # BGEU
                branch_taken = a >= b

            else:
                raise ValueError(f"Branch não suportado: 0x{instr:08X}")

            if branch_taken:
                next_pc = u32(pc_current + immediate)

        # --------------------------------------------------------------
        # LUI.
        # --------------------------------------------------------------

        elif opcode == 0x37:
            alu_result = u32(self.imm_u(instr))

            reg_write_enable = True
            reg_write_data = alu_result

        # --------------------------------------------------------------
        # AUIPC.
        # --------------------------------------------------------------

        elif opcode == 0x17:
            alu_result = u32(pc_current + self.imm_u(instr))

            reg_write_enable = True
            reg_write_data = alu_result

        # --------------------------------------------------------------
        # JAL.
        # --------------------------------------------------------------

        elif opcode == 0x6F:
            next_pc = u32(pc_current + self.imm_j(instr))

            reg_write_enable = True
            reg_write_data = u32(pc_current + 4)

            alu_result = None

        # --------------------------------------------------------------
        # JALR.
        # --------------------------------------------------------------

        elif opcode == 0x67:
            if funct3 != 0x0:
                raise ValueError(f"JALR não suportado: 0x{instr:08X}")

            target = u32(a + self.imm_i(instr)) & 0xFFFFFFFE

            next_pc = target

            reg_write_enable = True
            reg_write_data = u32(pc_current + 4)

            alu_result = None

        else:
            raise ValueError(
                f"Opcode não suportado: 0x{opcode:02X} "
                f"(instrução 0x{instr:08X})"
            )

        # --------------------------------------------------------------
        # Escrita no banco de registradores.
        # --------------------------------------------------------------

        if reg_write_enable:
            self.write_reg(
                rd,
                reg_write_data if reg_write_data is not None else 0
            )

            register_updated = rd != 0

        self.pc = u32(next_pc)

        # Garante que x0 permaneça sempre zero.
        self.regs[0] = 0

        return {
            "pc": pc_current,
            "instr": instr,
            "next_pc": self.pc,
            "alu_result": alu_result,
            "reg_write_enable": reg_write_enable,
            "rd": rd,
            "reg_write_data": reg_write_data,
            "register_updated": register_updated,
            "mem_write_enable": mem_write_enable,
            "mem_address": mem_address,
            "mem_write_data": mem_write_data,
            "mem_read_data": mem_read_data,
            "branch_taken": branch_taken,
        }

    # ------------------------------------------------------------------
    # Execução do programa
    # ------------------------------------------------------------------

    def run(
        self,
        stop_on_self_jump: bool = True,
        max_steps: int = 10000
    ) -> list[dict]:
        """Executa o programa carregado e retorna o traço de execução.

        A execução termina quando:
        - o PC alcança o primeiro endereço após as instruções carregadas;
        - é encontrado JAL x0, 0, se stop_on_self_jump=True; ou
        - o limite max_steps é atingido.

        O limite evita que um programa com laço infinito bloqueie a simulação.
        """

        if max_steps <= 0:
            raise ValueError("max_steps deve ser maior que zero.")

        trace: list[dict] = []

        for _ in range(max_steps):

            # Não executa NOPs de preenchimento após o fim do programa.
            if self.pc >= self.program_length * 4:
                break

            result = self.step()
            trace.append(result)

            # JAL x0, 0: salto para o próprio endereço, usado como sentinela.
            if stop_on_self_jump:
                is_jal = (result["instr"] & 0x7F) == 0x6F
                rd_is_zero = result["rd"] == 0
                jumps_to_self = result["next_pc"] == result["pc"]

                if is_jal and rd_is_zero and jumps_to_self:
                    break

        return trace


# ----------------------------------------------------------------------
# Execução direta do Golden Model
# ----------------------------------------------------------------------

def main() -> None:
    """Executa imem.hex."""

    hex_path = Path(__file__).with_name("imem.hex")

    if not hex_path.exists():
        print(
            f"Arquivo {hex_path.name} não encontrado; "
            "nenhum programa foi executado."
        )
        print(
            "Coloque imem.hex na mesma pasta "
            "ou importe RV32IReferenceModel."
        )
        return

    cpu = RV32IReferenceModel()
    cpu.load_hex(hex_path)

    trace = cpu.run()

    print("=== GOLDEN MODEL RV32I ===")
    print(f"Arquivo: {hex_path.name}")
    print(f"Instruções carregadas: {cpu.program_length}")
    print(f"Instruções executadas: {len(trace)}")
    print(f"PC final: 0x{cpu.pc:08X}")

    print("\n=== REGISTRADORES ===")

    for index, value in enumerate(cpu.regs):
        print(f"x{index:02d} = 0x{value:08X}")

    print("\n=== MEMÓRIA DE DADOS (palavras não nulas) ===")

    nonzero_words = [
        (index * 4, value)
        for index, value in enumerate(cpu.dmem)
        if value != 0
    ]

    if not nonzero_words:
        print("Nenhuma palavra não nula.")

    else:
        for address, value in nonzero_words:
            print(f"MEM[0x{address:08X}] = 0x{value:08X}")

    print(
        f"\nx0 permanece em zero: "
        f"{'SIM' if cpu.regs[0] == 0 else 'NÃO'}"
    )


if __name__ == "__main__":
    main()
