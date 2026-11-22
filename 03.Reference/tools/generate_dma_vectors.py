"""Generate DMA subsystem cases (A, B and the expected C) with the golden model.

Each file holds the cases for one ARRAY_SIZE x DATA_WIDTH pair. C keeps DATA_WIDTH bits per
element, as the accelerator output, so partial sums along K wrap modulo 2**DATA_WIDTH.
"""

from __future__ import annotations

import argparse
import random
import sys
from itertools import product
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from golden.systolic_array import systolic_array

# A, B and C share the 16 KiB data memory in 4 KiB regions (spec E1, section 4).
REGION_BYTES = 4096


def dimension_cases(size: int, rng: random.Random) -> list:
    cases = [
        ("one_element", 1, 1, 1),
        ("one_tile", size, size, size),
        ("edge_tiles", size + 1, 2 * size + 1, size - 1),
        ("k_accumulate", size, 3 * size, size),
        ("wide_c", 2 * size + 1, size, 2 * size + 3),
        ("tall_a", 3 * size, 2, 1),
    ]
    for index in range(4):
        dims = tuple(rng.randint(1, 2 * size + 3) for _ in range(3))
        cases.append((f"random_{index}",) + dims)
    return cases


def fits(m: int, k: int, n: int, width: int) -> bool:
    element = width // 8
    return max(m * k, k * n, m * n) * element <= REGION_BYTES


def write_vectors(directory: Path, size: int, width: int, seed: int) -> int:
    rng = random.Random(seed + 100 * size + width)
    low, high = -(1 << (width - 1)), (1 << (width - 1)) - 1
    mask = (1 << width) - 1
    digits = width // 4
    cases = [case for case in dimension_cases(size, rng) if fits(*case[1:], width)]
    path = directory / f"n{size}_w{width}.txt"
    with path.open("w", encoding="ascii") as stream:
        stream.write(f"{len(cases) + 1}\n")
        for name, m, k, n in cases:
            a = [[rng.randint(low, high) for _ in range(k)] for _ in range(m)]
            b = [[rng.randint(low, high) for _ in range(n)] for _ in range(k)]
            _write_case(stream, name, a, b, size, width, mask, digits)
        # Extreme values make every partial sum overflow DATA_WIDTH.
        m, k, n = size + 1, 2 * size, size + 1
        a = [[high if (i + j) % 2 else low for j in range(k)] for i in range(m)]
        b = [[low if (i + j) % 3 else high for j in range(n)] for i in range(k)]
        _write_case(stream, "numeric_limits", a, b, size, width, mask, digits)
    return len(cases) + 1


def _write_case(stream, name, a, b, size, width, mask, digits) -> None:
    c = systolic_array(a, b, array_size=size, data_width=width, signed=True)
    stream.write(f"{name} {len(a)} {len(b)} {len(b[0])}\n")
    for matrix in (a, b, c):
        for row in matrix:
            stream.write(" ".join(f"{value & mask:0{digits}x}" for value in row))
            stream.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("build/dma/vectors"))
    parser.add_argument("--seed", type=int, default=2026)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    total = sum(write_vectors(args.output, size, width, args.seed)
                for size, width in product((2, 4, 8), (8, 16, 32)))
    print(f"DMA vectors: {total} cases, seed={args.seed}, output={args.output}")


if __name__ == "__main__":
    main()
