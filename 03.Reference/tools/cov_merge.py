"""Functional coverage of a whole regression, added up from the simulation logs.

There is no coverage database tool on the simulation machine, so the coverage component writes
one MM_COV line per operation with the bins it hit. This script unites those bins per harness,
mesh and data width, using the same rule as the simulator (a covergroup is the mean of its
coverpoints and crosses), and first recomputes every log alone to confirm that it matches the
percentages the simulator printed. Only runs that ended in TEST PASS with no simulator or
assertion error count, and runs on an RTL mutant are left out.

Usage: python3 03.Reference/tools/cov_merge.py build/uvm [--out build/regress/coverage.md]
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from itertools import product
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

DIMS = ["DIM_SUB", "DIM_ONE", "DIM_MULTI", "DIM_REM"]
EXTS = ["EXT_NONE", "EXT_MIN", "EXT_MAX", "EXT_BOTH"]
ZEROS = ["00", "10", "01"]
STATUS = ["ST_OK", "ST_ERR_DIM", "ST_ERR_ADDR"]

# Every coverpoint and cross with its full list of bins, as declared in mm_coverage.svh.
GROUPS = {
    "cg_tiling": {
        "cp_m": DIMS, "cp_k": DIMS, "cp_n": DIMS,
        "cx_mkn": [f"{m}/{k}/{n}" for m, k, n in product(DIMS, DIMS, DIMS)],
    },
    "cg_data": {
        "cp_a": EXTS, "cp_b": EXTS, "cp_zero": ZEROS, "cp_wrap": ["0", "1"], "cp_k": DIMS,
        "cx_wrap_k": [f"{w}/{k}" for w, k in product(["0", "1"], DIMS)],
    },
    "cg_ctrl": {
        "cp_irq": ["0", "1"], "cp_seq": ["0", "1"], "cp_addr": ["0", "1"], "cp_status": STATUS,
        "cx_irq_seq": [f"{i}/{s}" for i, s in product(["0", "1"], ["0", "1"])],
    },
}

OP_LINE = re.compile(r"\[MM_COV\] op=(\d+) (.*)$")
SUMMARY = re.compile(r"\[MM_COV_SUMMARY\] ARRAY_SIZE=(\d+) samples=(\d+) cg_tiling=([\d.]+)% "
                     r".*cg_data=([\d.]+)% cg_ctrl=([\d.]+)%")
FIELD = re.compile(r"(\w+):([\w]+)")

Hits = Dict[str, Dict[str, Set[str]]]


def empty_hits() -> Hits:
    return {group: {point: set() for point in points} for group, points in GROUPS.items()}


def parse_op(text: str, hits: Hits) -> None:
    parts = dict(item.split("=", 1) for item in text.split() if "=" in item)
    ctrl = dict(FIELD.findall(parts["ctrl"]))
    c = hits["cg_ctrl"]
    c["cp_irq"].add(ctrl["irq"])
    c["cp_seq"].add(ctrl["b2b"])
    c["cp_addr"].add(ctrl["reloc"])
    if ctrl["status"] in STATUS:
        c["cp_status"].add(ctrl["status"])
    c["cx_irq_seq"].add(f"{ctrl['irq']}/{ctrl['b2b']}")
    if "tiling" not in parts:
        return
    m, k, n = parts["tiling"].split("/")
    t = hits["cg_tiling"]
    t["cp_m"].add(m)
    t["cp_k"].add(k)
    t["cp_n"].add(n)
    t["cx_mkn"].add(f"{m}/{k}/{n}")
    data = dict(FIELD.findall(parts["data"]))
    d = hits["cg_data"]
    d["cp_a"].add(data["a"])
    d["cp_b"].add(data["b"])
    if data["zero"] in ZEROS:
        d["cp_zero"].add(data["zero"])
    d["cp_wrap"].add(data["wrap"])
    d["cp_k"].add(k)
    d["cx_wrap_k"].add(f"{data['wrap']}/{k}")


def percent(hits: Hits, group: str) -> float:
    items = GROUPS[group]
    return sum(100.0 * len(hits[group][p] & set(bins)) / len(bins)
               for p, bins in items.items()) / len(items)


def read_log(path: Path) -> Optional[Tuple[int, Hits, Optional[Tuple[float, float, float]]]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    # The same rule as the verdict script: a pass line with simulator or assertion errors failed.
    if not re.search(r"^TEST PASS", text, re.M) or re.search(r"\*[EF],", text):
        return None
    hits = empty_hits()
    mesh, reported = None, None
    for line in text.splitlines():
        match = OP_LINE.search(line)
        if match:
            parse_op(match.group(2), hits)
            continue
        match = SUMMARY.search(line)
        if match and reported is None:
            mesh = int(match.group(1))
            reported = (float(match.group(3)), float(match.group(4)), float(match.group(5)))
    if mesh is None:
        return None
    return mesh, hits, reported


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("build", type=Path, help="directory with one folder per configuration")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    merged: Dict[str, Hits] = defaultdict(empty_hits)
    runs: Dict[str, int] = defaultdict(int)
    mismatches: List[str] = []
    checked = 0
    for log in sorted(args.build.glob("*/*.log")):
        # Runs on an RTL mutant are not coverage of the design.
        if log.name == "elab.log" or "_bug_" in log.parent.name:
            continue
        result = read_log(log)
        if result is None:
            continue
        _, hits, reported = result
        config = log.parent.name
        runs[config] += 1
        mine = tuple(round(percent(hits, g), 2) for g in GROUPS)
        if reported is not None:
            checked += 1
            if any(abs(a - b) > 0.011 for a, b in zip(mine, reported)):
                mismatches.append(f"{log}: simulator {reported}, recomputed {mine}")
        for group, points in hits.items():
            for point, bins in points.items():
                merged[config][group][point] |= bins

    lines = ["| Configuracao | Execucoes | cg_tiling | cruzamento M x K x N | cg_data | cg_ctrl | Total |",
             "|---|---|---|---|---|---|---|"]
    missing_report = []
    for config in sorted(merged):
        hits = merged[config]
        values = [percent(hits, g) for g in GROUPS]
        cross = len(hits["cg_tiling"]["cx_mkn"])
        lines.append(f"| {config} | {runs[config]} | {values[0]:.2f}% | {cross}/64 | "
                     f"{values[1]:.2f}% | {values[2]:.2f}% | {sum(values) / 3:.2f}% |")
        for group, points in GROUPS.items():
            for point, bins in points.items():
                absent = [b for b in bins if b not in hits[group][point]]
                if absent:
                    missing_report.append(f"{config} {group}.{point}: {', '.join(absent)}")
    lines.append("")
    lines.append(f"COV MERGE: {sum(runs.values())} passing run(s), {checked} log(s) checked against "
                 f"the simulator, {len(mismatches)} mismatch(es)")
    if missing_report:
        lines.append("")
        lines.append("Bins not hit:")
        lines.extend(f"- {item}" for item in missing_report)
    if mismatches:
        lines.append("")
        lines.append("Logs where the recomputed coverage differs from the simulator:")
        lines.extend(f"- {item}" for item in mismatches)
    text = "\n".join(lines) + "\n"
    print(text, end="")
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
