"""Deterministic functional model of C = A x B with matrix tiling."""

from __future__ import annotations

from itertools import product
from typing import Sequence


def _shape(matrix: Sequence[Sequence[int]], name: str) -> tuple[int, int]:
    if not matrix:
        raise ValueError(f"{name} must not be empty")
    columns = len(matrix[0])
    if columns == 0 or any(len(row) != columns for row in matrix):
        raise ValueError(f"{name} must be rectangular with nonempty rows")
    return len(matrix), columns


def _validate_values(
    matrix: Sequence[Sequence[int]], name: str, lower: int, upper: int
) -> None:
    for row in matrix:
        for value in row:
            if type(value) is not int:
                raise TypeError(f"{name} elements must be integers")
            if not lower <= value < upper:
                raise ValueError(f"{name} elements must be in [{lower}, {upper})")


def _accumulate_block(
    a: Sequence[Sequence[int]],
    b: Sequence[Sequence[int]],
    result: list[list[int]],
    start: tuple[int, int, int],
    array_size: int,
    accumulator_mask: int,
) -> None:
    row_start, column_start, inner_start = start
    inner_stop = min(inner_start + array_size, len(b))
    for i in range(row_start, min(row_start + array_size, len(a))):
        for j in range(column_start, min(column_start + array_size, len(b[0]))):
            partial = sum(a[i][k] * b[k][j] for k in range(inner_start, inner_stop))
            result[i][j] = (result[i][j] + partial) & accumulator_mask


def systolic_array(
    a: Sequence[Sequence[int]],
    b: Sequence[Sequence[int]],
    *,
    array_size: int = 2,
    data_width: int = 8,
    signed: bool = True,
) -> list[list[int]]:
    """Multiply A[M,K] by B[K,P] using blocks of size 2, 4 or 8.

    Operands and output use data_width bits (8, 16 or 32), signed by default.
    The accumulator uses 2*data_width + ceil(log2(K)) bits; output wraps.
    """
    if type(array_size) is not int or array_size not in (2, 4, 8):
        raise ValueError("array_size must be 2, 4 or 8")
    if type(data_width) is not int or data_width not in (8, 16, 32):
        raise ValueError("data_width must be 8, 16 or 32")
    if type(signed) is not bool:
        raise TypeError("signed must be a boolean")

    rows, inner = _shape(a, "A")
    b_rows, columns = _shape(b, "B")
    if inner != b_rows:
        raise ValueError("A columns must equal B rows")
    modulus = 1 << data_width
    offset = int(signed) * (modulus >> 1)
    _validate_values(a, "A", -offset, modulus - offset)
    _validate_values(b, "B", -offset, modulus - offset)

    accumulator_width = 2 * data_width + (inner - 1).bit_length()
    accumulator_mask = (1 << accumulator_width) - 1
    result = [[0] * columns for _ in range(rows)]
    blocks = product(
        range(0, rows, array_size),
        range(0, columns, array_size),
        range(0, inner, array_size),
    )
    for start in blocks:
        _accumulate_block(a, b, result, start, array_size, accumulator_mask)
    return [[(value + offset) % modulus - offset for value in row] for row in result]
