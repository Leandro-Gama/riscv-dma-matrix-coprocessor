"""Inputs of the CPU model testbench: the two self-test programs as hex images, and the final
registers and data memory the Python RV32I reference model reaches on the first one.

Usage: python3 03.Reference/tools/cpu_selftest.py --out build/unit_soc
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from golden.rv32i_reference_model import RV32IReferenceModel  # noqa: E402
from tools.rv32i_asm import assemble_file, to_hex  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SOURCES = REPO / "05.Verification" / "unit" / "soc"


def main(argv: list = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    args.out.mkdir(parents=True, exist_ok=True)

    for name in ("cpu_selftest_iss", "cpu_selftest_bytes"):
        _, image = assemble_file(SOURCES / f"{name}.S")
        (args.out / f"{name}.hex").write_text(to_hex(image, f"{name}.S"), encoding="ascii")

    _, image = assemble_file(SOURCES / "cpu_selftest_iss.S")
    cpu = RV32IReferenceModel()
    cpu.load_instructions([word for _, word, _ in image])
    trace = cpu.run(max_steps=10000)
    lines = [f"// {len(trace)} instructions on the Python reference model"]
    lines += [f"R {index} {value:08x}" for index, value in enumerate(cpu.regs) if index]
    lines += [f"M {4 * index:08x} {value:08x}" for index, value in enumerate(cpu.dmem) if value]
    (args.out / "cpu_selftest_iss.expected").write_text("\n".join(lines) + "\n", encoding="ascii")
    print(f"CPU SELFTEST: {len(trace)} instructions, files in {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
