"""Small RV32I assembler, standard library only, for the test firmware of the verification.

There is no RISC-V toolchain in the simulation machine, so the firmware is written in assembly and
turned into a hex image here. The image has one 32-bit word per line and only // comments, which
both $readmemh and the Python reference model read.

Supported: every RV32I base instruction except the system ones (fence is accepted as a no-op
encoding), ABI register names, labels, .equ NAME, value, .word value, and the pseudo-instructions
nop, li, la, mv, not, neg, j, jr, ret, beqz, bnez, call (near).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ABI = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4, "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9, "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14,
    "a5": 15, "a6": 16, "a7": 17, "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22,
    "s7": 23, "s8": 24, "s9": 25, "s10": 26, "s11": 27, "t3": 28, "t4": 29, "t5": 30,
    "t6": 31,
}

R_TYPE = {
    "add": (0x00, 0x0), "sub": (0x20, 0x0), "sll": (0x00, 0x1), "slt": (0x00, 0x2),
    "sltu": (0x00, 0x3), "xor": (0x00, 0x4), "srl": (0x00, 0x5), "sra": (0x20, 0x5),
    "or": (0x00, 0x6), "and": (0x00, 0x7),
}
I_ALU = {"addi": 0x0, "slti": 0x2, "sltiu": 0x3, "xori": 0x4, "ori": 0x6, "andi": 0x7}
I_SHIFT = {"slli": (0x00, 0x1), "srli": (0x00, 0x5), "srai": (0x20, 0x5)}
LOADS = {"lb": 0x0, "lh": 0x1, "lw": 0x2, "lbu": 0x4, "lhu": 0x5}
STORES = {"sb": 0x0, "sh": 0x1, "sw": 0x2}
BRANCHES = {"beq": 0x0, "bne": 0x1, "blt": 0x4, "bge": 0x5, "bltu": 0x6, "bgeu": 0x7}

OP_LUI, OP_AUIPC, OP_JAL, OP_JALR = 0x37, 0x17, 0x6F, 0x67
OP_BRANCH, OP_LOAD, OP_STORE, OP_IMM, OP_REG, OP_FENCE = 0x63, 0x03, 0x23, 0x13, 0x33, 0x0F


class AsmError(Exception):
    pass


def _fits_signed(value: int, bits: int) -> bool:
    return -(1 << (bits - 1)) <= value < (1 << (bits - 1))


def _split_hi_lo(value: int) -> Tuple[int, int]:
    """lui/addi pair: addi sign-extends its 12 bits, so the upper part absorbs the carry."""
    value &= 0xFFFFFFFF
    lo = value & 0xFFF
    if lo & 0x800:
        lo -= 0x1000
    hi = ((value - lo) >> 12) & 0xFFFFF
    return hi, lo


class Assembler:
    def __init__(self) -> None:
        self.symbols: Dict[str, int] = {}
        self.lines: List[Tuple[int, str, str, List[str], int]] = []

    # Parsing -------------------------------------------------------------------------------

    @staticmethod
    def _strip(line: str) -> str:
        for marker in ("#", "//"):
            if marker in line:
                line = line.split(marker, 1)[0]
        return line.strip()

    @staticmethod
    def _operands(text: str) -> List[str]:
        return [op.strip() for op in text.split(",") if op.strip()]

    def _reg(self, token: str, line_no: int) -> int:
        token = token.strip().lower()
        if token in ABI:
            return ABI[token]
        match = re.fullmatch(r"x(\d+)", token)
        if match and int(match.group(1)) < 32:
            return int(match.group(1))
        raise AsmError(f"line {line_no}: unknown register '{token}'")

    def _value(self, token: str, line_no: int) -> int:
        """Integer expression of numbers and symbols with + - * << >> | & ~ and parentheses."""
        token = token.strip()

        def resolve(match: "re.Match[str]") -> str:
            text = match.group(0)
            if text[0].isdigit():
                return str(int(text, 0))
            if text not in self.symbols:
                raise AsmError(f"line {line_no}: undefined symbol '{text}'")
            return str(self.symbols[text])

        expr = re.sub(r"0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d+|[A-Za-z_]\w*", resolve, token)
        if not expr or not re.fullmatch(r"[0-9+\-*()<>|&~\s]+", expr):
            raise AsmError(f"line {line_no}: bad expression '{token}'")
        try:
            # Only digits and operators are left at this point.
            return int(eval(expr, {"__builtins__": {}}, {}))  # noqa: S307
        except Exception as exc:
            raise AsmError(f"line {line_no}: bad expression '{token}'") from exc

    def _mem_operand(self, token: str, line_no: int) -> Tuple[int, int]:
        match = re.fullmatch(r"(.*)\((\s*\w+\s*)\)", token.strip())
        if not match:
            raise AsmError(f"line {line_no}: expected offset(reg), got '{token}'")
        offset = self._value(match.group(1), line_no) if match.group(1).strip() else 0
        return offset, self._reg(match.group(2), line_no)

    # Sizes, so labels can be placed in the first pass ----------------------------------------

    def _size(self, mnemonic: str, ops: List[str], line_no: int) -> int:
        if mnemonic == "la":
            return 2
        if mnemonic == "li":
            try:
                value = self._value(ops[1], line_no)
            except AsmError:
                return 2
            return 1 if _fits_signed(value, 12) else 2
        return 1

    # Encoders -------------------------------------------------------------------------------

    @staticmethod
    def _r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
        return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    @staticmethod
    def _i(imm: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
        return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

    @staticmethod
    def _s(imm: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
        imm &= 0xFFF
        return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | \
            ((imm & 0x1F) << 7) | opcode

    @staticmethod
    def _b(imm: int, rs2: int, rs1: int, funct3: int) -> int:
        imm &= 0x1FFF
        return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | \
            (rs1 << 15) | (funct3 << 12) | (((imm >> 1) & 0xF) << 8) | \
            (((imm >> 11) & 1) << 7) | OP_BRANCH

    @staticmethod
    def _u(imm20: int, rd: int, opcode: int) -> int:
        return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opcode

    @staticmethod
    def _j(imm: int, rd: int) -> int:
        imm &= 0x1FFFFF
        return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | \
            (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | OP_JAL

    def _target(self, token: str, pc: int, bits: int, line_no: int) -> int:
        offset = self._value(token, line_no) - pc
        if offset & 1 or not _fits_signed(offset, bits):
            raise AsmError(f"line {line_no}: target '{token}' out of reach ({offset})")
        return offset

    def _encode(self, mnemonic: str, ops: List[str], pc: int, line_no: int,
                size: int = 1) -> List[int]:
        reg = lambda i: self._reg(ops[i], line_no)  # noqa: E731
        val = lambda i: self._value(ops[i], line_no)  # noqa: E731

        def need(count: int) -> None:
            if len(ops) != count:
                raise AsmError(f"line {line_no}: '{mnemonic}' takes {count} operand(s)")

        if mnemonic in R_TYPE:
            need(3)
            funct7, funct3 = R_TYPE[mnemonic]
            return [self._r(funct7, reg(2), reg(1), funct3, reg(0), OP_REG)]
        if mnemonic in I_ALU:
            need(3)
            imm = val(2)
            if not _fits_signed(imm, 12):
                raise AsmError(f"line {line_no}: immediate {imm} does not fit 12 bits")
            return [self._i(imm, reg(1), I_ALU[mnemonic], reg(0), OP_IMM)]
        if mnemonic in I_SHIFT:
            need(3)
            funct7, funct3 = I_SHIFT[mnemonic]
            shamt = val(2)
            if not 0 <= shamt < 32:
                raise AsmError(f"line {line_no}: shift amount {shamt} out of range")
            return [self._i((funct7 << 5) | shamt, reg(1), funct3, reg(0), OP_IMM)]
        if mnemonic in LOADS:
            need(2)
            offset, base = self._mem_operand(ops[1], line_no)
            if not _fits_signed(offset, 12):
                raise AsmError(f"line {line_no}: offset {offset} does not fit 12 bits")
            return [self._i(offset, base, LOADS[mnemonic], reg(0), OP_LOAD)]
        if mnemonic in STORES:
            need(2)
            offset, base = self._mem_operand(ops[1], line_no)
            if not _fits_signed(offset, 12):
                raise AsmError(f"line {line_no}: offset {offset} does not fit 12 bits")
            return [self._s(offset, reg(0), base, STORES[mnemonic], OP_STORE)]
        if mnemonic in BRANCHES:
            need(3)
            offset = self._target(ops[2], pc, 13, line_no)
            return [self._b(offset, reg(1), reg(0), BRANCHES[mnemonic])]
        if mnemonic == "lui" or mnemonic == "auipc":
            need(2)
            imm = val(1)
            if not 0 <= imm < (1 << 20):
                raise AsmError(f"line {line_no}: {mnemonic} immediate must be 20 bits unsigned")
            return [self._u(imm, reg(0), OP_LUI if mnemonic == "lui" else OP_AUIPC)]
        if mnemonic == "jal":
            if len(ops) == 1:
                ops = ["ra"] + ops
            need(2)
            return [self._j(self._target(ops[1], pc, 21, line_no), reg(0))]
        if mnemonic == "jalr":
            if len(ops) == 1:
                return [self._i(0, reg(0), 0, ABI["ra"], OP_JALR)]
            if len(ops) == 2:
                offset, base = self._mem_operand(ops[1], line_no)
                return [self._i(offset, base, 0, reg(0), OP_JALR)]
            need(3)
            return [self._i(val(2), reg(1), 0, reg(0), OP_JALR)]
        if mnemonic == "fence":
            return [0x0FF0000F]

        # Pseudo-instructions.
        if mnemonic == "nop":
            need(0)
            return [self._i(0, 0, 0, 0, OP_IMM)]
        if mnemonic in ("li", "la"):
            need(2)
            value = val(1)
            if size == 1:
                return [self._i(value, 0, 0, reg(0), OP_IMM)]
            hi, lo = _split_hi_lo(value)
            return [self._u(hi, reg(0), OP_LUI), self._i(lo, reg(0), 0, reg(0), OP_IMM)]
        if mnemonic == "mv":
            need(2)
            return [self._i(0, reg(1), 0, reg(0), OP_IMM)]
        if mnemonic == "not":
            need(2)
            return [self._i(-1, reg(1), 0x4, reg(0), OP_IMM)]
        if mnemonic == "neg":
            need(2)
            return [self._r(0x20, reg(1), 0, 0x0, reg(0), OP_REG)]
        if mnemonic == "j":
            need(1)
            return [self._j(self._target(ops[0], pc, 21, line_no), 0)]
        if mnemonic == "call":
            need(1)
            return [self._j(self._target(ops[0], pc, 21, line_no), ABI["ra"])]
        if mnemonic == "jr":
            need(1)
            return [self._i(0, reg(0), 0, 0, OP_JALR)]
        if mnemonic == "ret":
            need(0)
            return [self._i(0, ABI["ra"], 0, 0, OP_JALR)]
        if mnemonic in ("beqz", "bnez"):
            need(2)
            offset = self._target(ops[1], pc, 13, line_no)
            return [self._b(offset, 0, reg(0), BRANCHES["beq" if mnemonic == "beqz" else "bne"])]
        raise AsmError(f"line {line_no}: unknown instruction '{mnemonic}'")

    # Driver ---------------------------------------------------------------------------------

    def assemble(self, source: str, origin: int = 0) -> List[Tuple[int, int, str]]:
        """Returns (address, word, source line) for every word of the image."""
        pc = origin
        self.lines = []
        for line_no, raw in enumerate(source.splitlines(), start=1):
            text = self._strip(raw)
            # In GNU as a semicolon separates statements; accepting it would drop one silently.
            if ";" in text:
                raise AsmError(f"line {line_no}: one statement per line (found ';')")
            while True:
                match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", text)
                if not match:
                    break
                label = match.group(1)
                if label in self.symbols:
                    raise AsmError(f"line {line_no}: symbol '{label}' defined twice")
                self.symbols[label] = pc
                text = match.group(2)
            if not text:
                continue
            parts = text.split(None, 1)
            mnemonic = parts[0].lower()
            ops = self._operands(parts[1]) if len(parts) > 1 else []
            if mnemonic == ".equ":
                if len(ops) != 2:
                    raise AsmError(f"line {line_no}: .equ NAME, value")
                if ops[0] in self.symbols:
                    raise AsmError(f"line {line_no}: symbol '{ops[0]}' defined twice")
                self.symbols[ops[0]] = self._value(ops[1], line_no)
                continue
            if mnemonic == ".word" and len(ops) != 1:
                raise AsmError(f"line {line_no}: .word takes one value per line")
            # The size chosen here is kept, so the labels of the first pass stay valid.
            size = 1 if mnemonic == ".word" else self._size(mnemonic, ops, line_no)
            self.lines.append((line_no, mnemonic, raw.strip(), ops, size))
            pc += 4 * size

        image: List[Tuple[int, int, str]] = []
        pc = origin
        for line_no, mnemonic, raw, ops, size in self.lines:
            if mnemonic == ".word":
                words = [self._value(ops[0], line_no) & 0xFFFFFFFF]
            else:
                words = self._encode(mnemonic, ops, pc, line_no, size)
            for index, word in enumerate(words):
                image.append((pc, word & 0xFFFFFFFF, raw if index == 0 else ""))
                pc += 4
        return image


def to_hex(image: List[Tuple[int, int, str]], title: Optional[str] = None) -> str:
    lines = []
    if title:
        lines.append(f"// {title}")
    for address, word, source in image:
        comment = f" // {address:04x}: {source}" if source else f" // {address:04x}"
        lines.append(f"{word:08x}{comment}")
    return "\n".join(lines) + "\n"


def assemble_file(source: Path, origin: int = 0) -> Tuple[Assembler, List[Tuple[int, int, str]]]:
    asm = Assembler()
    image = asm.assemble(source.read_text(encoding="utf-8"), origin)
    return asm, image


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true",
                        help="do not write; fail if the output file is not up to date")
    args = parser.parse_args(argv)
    try:
        _, image = assemble_file(args.source)
    except AsmError as exc:
        print(f"{args.source}: {exc}", file=sys.stderr)
        return 1
    text = to_hex(image, f"generated from {args.source.name} by rv32i_asm.py; do not edit")
    if args.check:
        current = args.output.read_text(encoding="utf-8") if args.output.exists() else ""
        if current != text:
            print(f"FW STALE: {args.output} does not match {args.source}", file=sys.stderr)
            return 1
        print(f"FW OK: {args.output} matches {args.source} ({len(image)} words)")
        return 0
    args.output.write_text(text, encoding="ascii", newline="\n")
    print(f"FW OK: {args.output} ({len(image)} words)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
