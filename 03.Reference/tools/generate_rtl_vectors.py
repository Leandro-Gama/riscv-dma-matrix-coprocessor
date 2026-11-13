"""Generate RTL inputs and expected outputs using the golden model."""

from __future__ import annotations

import argparse
import random
import sys
from itertools import product
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from golden.systolic_array import systolic_array


def matrix_cases(size: int, width: int, seed: int) -> list:
    rng = random.Random(seed + 100 * size + width)
    minimum, maximum = -(1 << (width - 1)), (1 << (width - 1)) - 1

    def random_matrix() -> list[list[int]]:
        return [[rng.randint(minimum, maximum) for _ in range(size)] for _ in range(size)]

    zero = [[0] * size for _ in range(size)]
    identity = [[int(i == j) for j in range(size)] for i in range(size)]
    known_a = [[i * size + j + 1 for j in range(size)] for i in range(size)]
    known_b = [[(i + j) % 7 - 3 for j in range(size)] for i in range(size)]
    limits = [[minimum if (i + j) % 2 else maximum for j in range(size)]
              for i in range(size)]
    upper = [[maximum] * size for _ in range(size)]
    weights = random_matrix()
    return [
        ("known", True, known_a, known_b),
        ("identity", True, random_matrix(), identity),
        ("zero_weights", True, random_matrix(), zero),
        ("numeric_limits", True, limits, limits),
        ("output_wrap", True, upper, upper),
        ("random_load", True, random_matrix(), weights),
        ("random_reuse", False, random_matrix(), weights),
        ("zero_input_reuse", False, zero, weights),
        ("random_reuse_again", False, random_matrix(), weights),
    ]


def write_vectors(directory: Path, size: int, width: int, seed: int) -> int:
    cases = matrix_cases(size, width, seed)
    mask = (1 << width) - 1
    path = directory / f"n{size}_w{width}.txt"
    with path.open("w", encoding="ascii") as stream:
        stream.write(f"{len(cases)}\n")
        for name, reload_weights, a, b in cases:
            expected = systolic_array(a, b, array_size=size, data_width=width, signed=True)
            stream.write(f"{name} {int(reload_weights)}\n")
            for matrix in (a, b, expected):
                for row in matrix:
                    stream.write(" ".join(f"{value & mask:0{width // 4}x}" for value in row))
                    stream.write("\n")
    return len(cases)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("build/accel/vectors"))
    parser.add_argument("--seed", type=int, default=2026)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    total = sum(write_vectors(args.output, size, width, args.seed)
                for size, width in product((2, 4, 8), (8, 16, 32)))
    print(f"Golden vectors: {total} cases, seed={args.seed}, output={args.output}")


if __name__ == "__main__":
    main()
