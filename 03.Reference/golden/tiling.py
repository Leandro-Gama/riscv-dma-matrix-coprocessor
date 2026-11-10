from __future__ import annotations

from dataclasses import dataclass
from itertools import permutations
from typing import Dict, Iterator

LOOP_ORDERS = tuple("".join(p) for p in permutations("mnk"))


@dataclass(frozen=True)
class Tile:
    m0: int
    n0: int
    k0: int
    rows: int
    cols: int
    depth: int


@dataclass(frozen=True)
class TileConfig:
    """Block sizes and loop nesting (outermost first).

    Owned by the DMA/accelerator; defaults are provisional. "nkm" keeps a B block (the
    weights of a weight-stationary array) fixed while the A blocks stream through it.
    """

    tile_m: int
    tile_n: int
    tile_k: int
    order: str = "nkm"

    def __post_init__(self) -> None:
        if min(self.tile_m, self.tile_n, self.tile_k) < 1:
            raise ValueError("tile sizes must be >= 1")
        if self.order not in LOOP_ORDERS:
            raise ValueError(f"order must be one of {LOOP_ORDERS}, got {self.order!r}")

    @classmethod
    def square(cls, size: int, order: str = "nkm") -> TileConfig:
        return cls(size, size, size, order)


def tile_schedule(m: int, n: int, k: int, cfg: TileConfig) -> Iterator[Tile]:
    """Every block of C = A(m x k) * B(k x n), clipping the edge blocks."""
    if min(m, n, k) < 1:
        raise ValueError(f"dimensions must be >= 1, got m={m} n={n} k={k}")
    return _tiles(m, n, k, cfg)


def _tiles(m: int, n: int, k: int, cfg: TileConfig) -> Iterator[Tile]:
    extent: Dict[str, int] = {"m": m, "n": n, "k": k}
    step: Dict[str, int] = {"m": cfg.tile_m, "n": cfg.tile_n, "k": cfg.tile_k}
    outer, middle, inner = cfg.order
    for a in range(0, extent[outer], step[outer]):
        for b in range(0, extent[middle], step[middle]):
            for c in range(0, extent[inner], step[inner]):
                start = {outer: a, middle: b, inner: c}
                yield Tile(
                    m0=start["m"],
                    n0=start["n"],
                    k0=start["k"],
                    rows=min(cfg.tile_m, m - start["m"]),
                    cols=min(cfg.tile_n, n - start["n"]),
                    depth=min(cfg.tile_k, k - start["k"]),
                )
