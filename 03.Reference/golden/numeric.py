from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class NumericFormat:
    """Operand and accumulator formats (C is stored with acc_bits).

    Owned by the accelerator; defaults are provisional.
    """

    data_bits: int = 8
    acc_bits: int = 32
    signed: bool = True

    def __post_init__(self) -> None:
        if self.data_bits < 1:
            raise ValueError(f"data_bits must be >= 1, got {self.data_bits}")
        if self.acc_bits < self.data_bits:
            raise ValueError(f"acc_bits ({self.acc_bits}) must be >= data_bits ({self.data_bits})")

    @property
    def data_min(self) -> int:
        return -(1 << (self.data_bits - 1)) if self.signed else 0

    @property
    def data_max(self) -> int:
        return (1 << (self.data_bits - 1)) - 1 if self.signed else (1 << self.data_bits) - 1

    def check_operand(self, value: int) -> None:
        if isinstance(value, bool) or not isinstance(value, int):
            raise TypeError(f"operand must be int, got {type(value).__name__}")
        if not self.data_min <= value <= self.data_max:
            raise ValueError(f"operand {value} outside [{self.data_min}, {self.data_max}]")

    def wrap_acc(self, value: int) -> int:
        """Two's complement wrap, as a fixed-width hardware accumulator does on overflow."""
        modulus = 1 << self.acc_bits
        value %= modulus
        if self.signed and value >= modulus >> 1:
            value -= modulus
        return value
