"""Assembler and test firmware. Run from the repository root with make test.

The encodings are checked against values from the RISC-V specification, the programs run on the
Python RV32I reference model, and the firmware is run with the data memory and the DMA registers
emulated, so its protocol with the environment is checked without any simulator.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from golden.rv32i_reference_model import RV32IReferenceModel
from tools.rv32i_asm import AsmError, Assembler, assemble_file, to_hex

REPO = Path(__file__).resolve().parents[2]
FW_SOURCE = REPO / "05.Verification" / "soc" / "firmware" / "mm_fw.S"
FW_HEX = REPO / "05.Verification" / "soc" / "firmware" / "mm_fw.hex"
SOC_PKG = REPO / "04.RTL" / "common" / "soc_pkg.sv"
AGENT_PKG = REPO / "05.Verification" / "soc" / "agents" / "mm_agent" / "mm_agent_pkg.sv"


def words(source: str) -> list:
    return [word for _, word, _ in Assembler().assemble(source)]


class EncodingTest(unittest.TestCase):
    def test_reference_encodings(self) -> None:
        cases = {
            "addi x1, x0, 5": 0x00500093,
            "addi t1, t1, -1": 0xFFF30313,
            "lui t0, 0x10000": 0x100002B7,
            "sw t1, 4(t0)": 0x0062A223,
            "lw t0, 0(s0)": 0x00042283,
            "sub a0, a1, a2": 0x40C58533,
            "srai t0, t1, 3": 0x40335293,
            "andi t5, t4, 2": 0x002EFF13,
            "jal zero, 0": 0x0000006F,
            "jalr ra, 0(t0)": 0x000280E7,
            "sb a0, -1(sp)": 0xFEA10FA3,
            "lbu a1, 3(a0)": 0x00354583,
        }
        for text, expected in cases.items():
            with self.subTest(text=text):
                self.assertEqual(words(text), [expected], f"{text}: 0x{words(text)[0]:08x}")

    def test_backward_branch(self) -> None:
        self.assertEqual(words("loop: nop\nbeq t0, zero, loop")[1], 0xFE028EE3)

    def test_li_splits_with_carry(self) -> None:
        self.assertEqual(words("li a0, 0x12345FFF"), [0x12346537, 0xFFF50513])
        self.assertEqual(words("li a0, -2048"), [0x80000513])

    def test_forward_symbol_keeps_size(self) -> None:
        image = Assembler().assemble("li a0, LATER\nend: jal zero, end\n.equ LATER, 7")
        self.assertEqual(len(image), 3)
        self.assertEqual(image[2][1], 0x0000006F)

    def test_errors(self) -> None:
        for bad in ("addi x1, x0, 4096", "lw t0, t1", "foo t0", "beq t0, t1, nowhere",
                    "add x1, x2, x40", ".word 1, 2", "nop ; nop"):
            with self.subTest(bad=bad), self.assertRaises(AsmError):
                Assembler().assemble(bad)

    def test_hex_format(self) -> None:
        text = to_hex(Assembler().assemble("nop"), "title")
        self.assertEqual(text, "// title\n00000013 // 0000: nop\n")


class ProgramTest(unittest.TestCase):
    def run_program(self, source: str, steps: int = 2000) -> RV32IReferenceModel:
        cpu = RV32IReferenceModel()
        cpu.load_instructions(words(source))
        cpu.run(max_steps=steps)
        return cpu

    def test_loop_and_memory(self) -> None:
        cpu = self.run_program("""
                li   t0, 10
                li   t1, 0
        loop:   add  t1, t1, t0
                addi t0, t0, -1
                bne  t0, zero, loop
                sw   t1, 0x40(zero)
                li   a0, 0x12345FFF
                srai a1, a0, 4
                sltu a2, zero, a0
        end:    j    end
        """)
        self.assertEqual(cpu.regs[6], 55)
        self.assertEqual(cpu.read_word(0x40), 55)
        self.assertEqual(cpu.regs[10], 0x12345FFF)
        self.assertEqual(cpu.regs[11], 0x012345FF)
        self.assertEqual(cpu.regs[12], 1)


class SocEmulation(RV32IReferenceModel):
    """Data memory and DMA registers at their system addresses; STATUS shows DONE after a few
    reads, like a DMA that takes a while."""

    def __init__(self, consts: dict, busy_reads: int = 3) -> None:
        super().__init__()
        self.c = consts
        self.mem: dict = {}
        self.dma_writes: list = []
        self.mem_writes: list = []
        self.busy_reads = busy_reads
        self.status_reads = 0

    def read_word(self, address: int) -> int:
        c = self.c
        if c["DMEM_BASE"] <= address < c["DMEM_BASE"] + 16384:
            return self.mem.get(address, 0)
        if c["DMAREG_BASE"] <= address < c["DMAREG_BASE"] + 4096:
            if address - c["DMAREG_BASE"] == c["DMA_STATUS"]:
                self.status_reads += 1
                return 0x2 if self.status_reads > self.busy_reads else 0x1
            return 0
        raise AssertionError(f"read outside the map: 0x{address:08x}")

    def write_word(self, address: int, value: int) -> None:
        c = self.c
        if c["DMEM_BASE"] <= address < c["DMEM_BASE"] + 16384:
            self.mem[address] = value & 0xFFFFFFFF
            self.mem_writes.append((address - c["DMEM_BASE"], value))
            return
        if c["DMAREG_BASE"] <= address < c["DMAREG_BASE"] + 4096:
            self.dma_writes.append((address - c["DMAREG_BASE"], value))
            if address - c["DMAREG_BASE"] == c["DMA_CONTROL"]:
                self.status_reads = 0
            return
        raise AssertionError(f"write outside the map: 0x{address:08x}")


class FirmwareTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.asm, cls.image = assemble_file(FW_SOURCE)
        cls.c = cls.asm.symbols

    def test_hex_is_up_to_date(self) -> None:
        expected = to_hex(self.image, f"generated from {FW_SOURCE.name} by rv32i_asm.py; do not edit")
        self.assertEqual(FW_HEX.read_text(encoding="utf-8"), expected,
                         "mm_fw.hex is stale: run make fw")

    def test_subset_of_instructions(self) -> None:
        opcodes = {word & 0x7F for _, word, _ in self.image}
        self.assertLessEqual(opcodes, {0x37, 0x13, 0x03, 0x23, 0x63, 0x6F})

    def test_addresses_match_the_rtl_package(self) -> None:
        text = SOC_PKG.read_text(encoding="utf-8")

        def rtl(name: str) -> int:
            match = re.search(rf"\b{name}\s*=\s*\d*'h([0-9A-Fa-f_]+)", text)
            self.assertIsNotNone(match, name)
            return int(match.group(1).replace("_", ""), 16)

        self.assertEqual(self.c["DMEM_BASE"], rtl("DMEM_BASE"))
        self.assertEqual(self.c["DMAREG_BASE"], rtl("DMAREG_BASE"))
        for reg in ("ADDR_A", "ADDR_B", "ADDR_C", "DIM_M", "DIM_K", "DIM_N", "CONTROL", "STATUS"):
            self.assertEqual(self.c[f"DMA_{reg}"], rtl(f"DMA_REG_{reg}"), reg)

    def test_parameter_block_matches_the_agent(self) -> None:
        text = AGENT_PKG.read_text(encoding="utf-8")
        for name in ("CMD", "ADDR_A", "ADDR_B", "ADDR_C", "DIM_M", "DIM_K", "DIM_N", "FLAGS",
                     "STATUS", "DONE_COUNT"):
            match = re.search(rf"localparam int PB_{name} = (\d+);", text)
            self.assertIsNotNone(match, name)
            self.assertEqual(self.c[f"PB_{name}"], 4 * int(match.group(1)), name)
        for name in ("FAULT_DIM_K", "FAULT_HANG"):
            match = re.search(rf"localparam int FLAG_{name} = (\d+);", text)
            self.assertEqual(self.c[f"FLAG_{name}"], 1 << int(match.group(1)), name)

    def start(self, soc: SocEmulation, flags: int, k: int = 5) -> None:
        base = self.c["DMEM_BASE"]
        values = {"ADDR_A": 0x10001000, "ADDR_B": 0x10002000, "ADDR_C": 0x10003000,
                  "DIM_M": 3, "DIM_K": k, "DIM_N": 7, "FLAGS": flags}
        for name, value in values.items():
            soc.mem[base + self.c[f"PB_{name}"]] = value
        soc.mem[base + self.c["PB_CMD"]] = 1

    def run_fw(self, soc: SocEmulation, steps: int) -> None:
        soc.load_instructions([word for _, word, _ in self.image])
        for _ in range(steps):
            soc.step()

    def test_one_operation(self) -> None:
        soc = SocEmulation(self.c)
        self.start(soc, flags=1)
        self.run_fw(soc, 200)
        c, base = self.c, self.c["DMEM_BASE"]
        self.assertEqual(soc.dma_writes, [
            (c["DMA_ADDR_A"], 0x10001000), (c["DMA_ADDR_B"], 0x10002000),
            (c["DMA_ADDR_C"], 0x10003000), (c["DMA_DIM_M"], 3), (c["DMA_DIM_K"], 5),
            (c["DMA_DIM_N"], 7), (c["DMA_CONTROL"], 3)])
        self.assertEqual(soc.mem[base + c["PB_STATUS"]], 0x2)
        self.assertEqual(soc.mem[base + c["PB_CMD"]], 0)
        self.assertEqual(soc.mem[base + c["PB_DONE_COUNT"]], 1)
        order = [offset for offset, _ in soc.mem_writes]
        self.assertEqual(order, [c["PB_STATUS"], c["PB_CMD"], c["PB_DONE_COUNT"]])

    def test_back_to_back_and_fault(self) -> None:
        soc = SocEmulation(self.c)
        self.start(soc, flags=0)
        self.run_fw(soc, 200)
        self.start(soc, flags=self.c["FLAG_FAULT_DIM_K"], k=4)
        for _ in range(200):
            soc.step()
        c = self.c
        self.assertEqual(soc.dma_writes[7 + 4], (c["DMA_DIM_K"], 3))
        self.assertEqual(soc.dma_writes[6], (c["DMA_CONTROL"], 1))
        self.assertEqual(soc.mem[c["DMEM_BASE"] + c["PB_DONE_COUNT"]], 2)

    def test_hang_never_reports(self) -> None:
        soc = SocEmulation(self.c)
        self.start(soc, flags=self.c["FLAG_FAULT_HANG"])
        self.run_fw(soc, 300)
        self.assertEqual(soc.mem.get(self.c["DMEM_BASE"] + self.c["PB_DONE_COUNT"], 0), 0)
        self.assertEqual(soc.mem[self.c["DMEM_BASE"] + self.c["PB_CMD"]], 1)


if __name__ == "__main__":
    unittest.main()
