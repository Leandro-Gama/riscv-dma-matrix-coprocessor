from __future__ import annotations

from typing import Tuple

from .matrix import Matrix, shape
from .numeric import NumericFormat
from .tiling import TileConfig, tile_schedule


def _check_operands(a: Matrix, b: Matrix, fmt: NumericFormat) -> Tuple[int, int, int]:
    m, k = shape(a)
    k_b, n = shape(b)
    if k != k_b:
        raise ValueError(f"inner dimensions differ: A is {m}x{k}, B is {k_b}x{n}")
    for mat in (a, b):
        for row in mat:
            for value in row:
                fmt.check_operand(value)
    return m, n, k


def matmul_reference(a: Matrix, b: Matrix, fmt: NumericFormat) -> Matrix:
    """Direct C = A * B with the accumulator width of fmt."""
    m, n, k = _check_operands(a, b, fmt)
    return [
        [fmt.wrap_acc(sum(a[i][x] * b[x][j] for x in range(k))) for j in range(n)]
        for i in range(m)
    ]


def matmul_tiled(a: Matrix, b: Matrix, fmt: NumericFormat, cfg: TileConfig) -> Matrix:
    """C = A * B block by block, adding each partial block into C as the hardware would."""
    m, n, k = _check_operands(a, b, fmt)
    c = [[0] * n for _ in range(m)]
    for tile in tile_schedule(m, n, k, cfg):
        for i in range(tile.m0, tile.m0 + tile.rows):
            for j in range(tile.n0, tile.n0 + tile.cols):
                partial = sum(a[i][x] * b[x][j] for x in range(tile.k0, tile.k0 + tile.depth))
                c[i][j] = fmt.wrap_acc(c[i][j] + partial)
    return c
