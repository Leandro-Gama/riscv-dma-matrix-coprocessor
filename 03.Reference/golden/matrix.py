from __future__ import annotations

import random
from typing import List, Tuple

from .numeric import NumericFormat

Matrix = List[List[int]]

PATTERNS = ("random", "zeros", "max", "min", "identity")


def shape(mat: Matrix) -> Tuple[int, int]:
    if not mat or not mat[0]:
        raise ValueError("matrix must have at least one row and one column")
    cols = len(mat[0])
    if any(len(row) != cols for row in mat):
        raise ValueError("matrix rows must all have the same length")
    return len(mat), cols


def generate(
    rows: int, cols: int, fmt: NumericFormat, rng: random.Random, pattern: str = "random"
) -> Matrix:
    if rows < 1 or cols < 1:
        raise ValueError(f"dimensions must be >= 1, got {rows}x{cols}")
    if pattern == "random":
        return [[rng.randint(fmt.data_min, fmt.data_max) for _ in range(cols)] for _ in range(rows)]
    if pattern == "zeros":
        return [[0] * cols for _ in range(rows)]
    if pattern == "max":
        return [[fmt.data_max] * cols for _ in range(rows)]
    if pattern == "min":
        return [[fmt.data_min] * cols for _ in range(rows)]
    if pattern == "identity":
        return [[1 if r == c else 0 for c in range(cols)] for r in range(rows)]
    raise ValueError(f"unknown pattern {pattern!r}, expected one of {PATTERNS}")
