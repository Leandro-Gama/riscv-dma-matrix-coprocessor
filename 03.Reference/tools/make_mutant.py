"""Builds an RTL mutant for a fault-injection run, without touching the RTL of anyone.

The mutant is a copy of one source file with a single, known change, written in the build
directory together with a copy of the file list that points to it instead of the original. A
run with the mutant must end in TEST FAIL; if it passes, the checking has a hole.

Usage: python3 03.Reference/tools/make_mutant.py --bug NAME --filelist F.f --out DIR
       python3 03.Reference/tools/make_mutant.py --list
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REPO = Path(__file__).resolve().parents[2]

# name: (file, original text, mutated text, what goes wrong)
MUTANTS: Dict[str, Tuple[str, str, str, str]] = {
    "dma_k_sum": (
        "04.RTL/dma/dma_dp.sv",
        "else if (c_capture_i) out_q <= out_q + pick(bus_rdata_i, elem_addr[1:0]);",
        "else if (c_capture_i) out_q <= pick(bus_rdata_i, elem_addr[1:0]);",
        "the DMA replaces the partial sum of C instead of adding to it (K larger than the mesh)",
    ),
    "dma_row_step": (
        "04.RTL/dma/dma_dp.sv",
        "row_ptr_q <= row_ptr_q + stride_q;",
        "row_ptr_q <= row_ptr_q + stride_q + 32'd4;",
        "the DMA steps one word too far at the end of each row of a tile",
    ),
    "accel_mac_sign": (
        "04.RTL/accel/accel_systolic.sv",
        "assign mac[row][col] = previous_sum +",
        "assign mac[row][col] = previous_sum -",
        "each processing element subtracts its product instead of adding it",
    ),
    "mem_strobe": (
        "04.RTL/common/mem_data.sv",
        "if (be[b]) mem[idx][8*b+:8] <= wdata[8*b+:8];",
        "mem[idx][8*b+:8] <= wdata[8*b+:8];",
        "the data memory ignores the byte strobes and writes the whole word",
    ),
    "adapter_level": (
        "04.RTL/soc/accel_adapter_dp.sv",
        "    end else begin\n      pulse_q <= '0;\n      if (ack_i",
        "    end else begin\n      if (ack_i",
        "the adapter holds the command bits as levels instead of one-cycle pulses",
    ),
}


def rewrite(line: str, src_dir: Path, out_dir: Path, target: Path, mutant: Path) -> str:
    stripped = line.strip()
    if not stripped or stripped.startswith("//") or stripped.startswith("#"):
        return line
    if stripped.startswith("+incdir+"):
        path = (src_dir / stripped[len("+incdir+"):]).resolve()
        return "+incdir+" + os.path.relpath(path, out_dir).replace(os.sep, "/")
    if stripped.startswith("+") or stripped.startswith("-"):
        return stripped
    path = (src_dir / stripped).resolve()
    if path == target:
        path = mutant
    return os.path.relpath(path, out_dir).replace(os.sep, "/")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bug")
    parser.add_argument("--filelist", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)

    if args.list or not args.bug:
        for name, (file, _, _, what) in MUTANTS.items():
            print(f"{name:15s} {file}: {what}")
        return 0 if args.list else 1
    if args.bug not in MUTANTS:
        print(f"unknown mutant '{args.bug}'; known: {', '.join(MUTANTS)}", file=sys.stderr)
        return 1

    file, old, new, what = MUTANTS[args.bug]
    source = (REPO / file).read_text(encoding="utf-8")
    if source.count(old) != 1:
        print(f"MUTANT {args.bug}: the original text appears {source.count(old)} time(s) in {file};"
              " the RTL changed, update the mutant", file=sys.stderr)
        return 1
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    mutant = out / f"mutant_{Path(file).name}"
    mutant.write_text(source.replace(old, new), encoding="utf-8")

    filelist = args.filelist.resolve()
    lines = filelist.read_text(encoding="utf-8").splitlines()
    target = (REPO / file).resolve()
    rewritten = [rewrite(line, filelist.parent, out, target, mutant) for line in lines]
    if not any(Path(line).name == mutant.name for line in rewritten):
        print(f"MUTANT {args.bug}: {file} is not in {args.filelist}", file=sys.stderr)
        return 1
    (out / "mutant.f").write_text("\n".join(rewritten) + "\n", encoding="utf-8")
    print(f"MUTANT {args.bug}: {what} ({file})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
