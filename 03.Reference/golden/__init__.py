"""Golden model of C = A * B by blocks (tiling); standard library only (Python 3.9)."""

from .matmul import matmul_reference, matmul_tiled
from .matrix import PATTERNS, Matrix, generate, shape
from .numeric import NumericFormat
from .tiling import LOOP_ORDERS, Tile, TileConfig, tile_schedule

__all__ = [
    "LOOP_ORDERS",
    "Matrix",
    "NumericFormat",
    "PATTERNS",
    "Tile",
    "TileConfig",
    "generate",
    "matmul_reference",
    "matmul_tiled",
    "shape",
    "tile_schedule",
]
