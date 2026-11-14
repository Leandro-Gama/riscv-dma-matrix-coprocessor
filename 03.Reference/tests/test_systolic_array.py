"""Run from the repository root with make test (random seed: 2026)."""

from __future__ import annotations

import random
import unittest
from copy import deepcopy
from itertools import product

from golden.systolic_array import systolic_array


class SystolicArrayTest(unittest.TestCase):
    def assert_matrix_equal(self, actual: list[list[int]], expected: list[list[int]]) -> None:
        self.assertEqual(len(actual), len(expected))
        for i, row in enumerate(expected):
            self.assertEqual(len(actual[i]), len(row))
            for j, value in enumerate(row):
                self.assertEqual(actual[i][j], value, f"C[{i}][{j}]: expected {value}")

    def test_known_product(self) -> None:
        a = [[1, 2], [3, 4]]
        b = [[5, 6], [7, 8]]
        self.assert_matrix_equal(systolic_array(a, b), [[19, 22], [43, 50]])

    def test_negative_operands(self) -> None:
        a = [[-1, 2], [3, -4]]
        b = [[5, -6], [-7, 8]]
        self.assert_matrix_equal(systolic_array(a, b), [[-19, 22], [43, -50]])

    def test_zero_and_identity(self) -> None:
        for size in (2, 4, 8):
            with self.subTest(array_size=size):
                a = [[i - j for j in range(size)] for i in range(size)]
                zero = [[0] * size for _ in range(size)]
                identity = [[int(i == j) for j in range(size)] for i in range(size)]
                self.assert_matrix_equal(systolic_array(a, zero, array_size=size), zero)
                self.assert_matrix_equal(systolic_array(a, identity, array_size=size), a)

    def test_rectangular_partial_blocks(self) -> None:
        a = [[1, 2, 3], [4, 5, 6]]
        b = [[7, 8, 9], [10, 11, 12], [13, 14, 15]]
        for size in (2, 4, 8):
            with self.subTest(array_size=size):
                self.assert_matrix_equal(
                    systolic_array(a, b, array_size=size, data_width=16),
                    [[66, 72, 78], [156, 171, 186]],
                )

    def test_single_element(self) -> None:
        self.assert_matrix_equal(systolic_array([[-3]], [[7]]), [[-21]])

    def test_numeric_limits_and_output_wrap(self) -> None:
        for width, signed in product((8, 16, 32), (True, False)):
            with self.subTest(data_width=width, signed=signed):
                maximum = (1 << (width - int(signed))) - 1
                upper_expected = -2 if signed else (1 << width) - 2
                result = systolic_array(
                    [[maximum, maximum]], [[1], [1]], data_width=width, signed=signed
                )
                self.assert_matrix_equal(result, [[upper_expected]])
                self.assert_matrix_equal(
                    systolic_array([[maximum]], [[maximum]], data_width=width, signed=signed),
                    [[1]],
                )
                if signed:
                    minimum = -(1 << (width - 1))
                    self.assert_matrix_equal(
                        systolic_array([[minimum]], [[-1]], data_width=width), [[minimum]]
                    )
                    self.assert_matrix_equal(
                        systolic_array([[minimum]], [[minimum]], data_width=width), [[0]]
                    )

    def test_tiling_against_direct_product(self) -> None:
        rng = random.Random(2026)
        configurations = product((2, 4, 8), (8, 16, 32), (True, False))
        for size, width, signed in configurations:
            rows, inner, columns = size + 1, 2 * size + 1, size + 3
            lower = -(1 << (width - 1)) if signed else 0
            upper = (1 << (width - int(signed))) - 1
            a = [[rng.randint(lower, upper) for _ in range(inner)] for _ in range(rows)]
            b = [[rng.randint(lower, upper) for _ in range(columns)] for _ in range(inner)]
            expected = [[0] * columns for _ in range(rows)]
            for i, j in product(range(rows), range(columns)):
                value = sum(x * y for x, y in zip(a[i], (row[j] for row in b)))
                bits = value % (1 << width)
                if signed and bits >= 1 << (width - 1):
                    bits -= 1 << width
                expected[i][j] = bits
            with self.subTest(array_size=size, data_width=width, signed=signed):
                actual = systolic_array(a, b, array_size=size, data_width=width, signed=signed)
                self.assert_matrix_equal(actual, expected)

    def test_determinism_and_input_preservation(self) -> None:
        a, b = [[1, -2], [3, 4]], [[5, 6], [-7, 8]]
        original = deepcopy((a, b))
        first = systolic_array(a, b)
        self.assert_matrix_equal(first, systolic_array(a, b))
        first[0][0] = 0
        self.assert_matrix_equal(systolic_array(a, b), [[19, -10], [-13, 50]])
        self.assertEqual((a, b), original)

    def test_invalid_shapes(self) -> None:
        cases = [
            ([], [[1]]), ([[1]], []), ([[]], [[1]]), ([[1]], [[]]),
            ([[1, 2], [3]], [[1], [2]]), ([[1, 2]], [[1], [2, 3]]),
            ([[1, 2]], [[1]]),
        ]
        for a, b in cases:
            with self.subTest(a=a, b=b), self.assertRaises(ValueError):
                systolic_array(a, b)

    def test_invalid_parameters(self) -> None:
        cases = [
            {"array_size": 0}, {"array_size": 3}, {"array_size": 2.0},
            {"array_size": True}, {"data_width": 7}, {"data_width": 8.0},
        ]
        for parameters in cases:
            with self.subTest(parameters=parameters), self.assertRaises(ValueError):
                systolic_array([[1]], [[1]], **parameters)
        with self.assertRaises(TypeError):
            systolic_array([[1]], [[1]], signed=1)

    def test_invalid_operand_values(self) -> None:
        for width, signed in product((8, 16, 32), (True, False)):
            lower = -(1 << (width - 1)) if signed else 0
            upper = 1 << (width - int(signed))
            for invalid in (lower - 1, upper):
                for a, b in (([[invalid]], [[1]]), ([[1]], [[invalid]])):
                    with self.subTest(data_width=width, signed=signed, a=a, b=b):
                        with self.assertRaises(ValueError):
                            systolic_array(a, b, data_width=width, signed=signed)
        for invalid in (1.5, True, "1"):
            for a, b in (([[invalid]], [[1]]), ([[1]], [[invalid]])):
                with self.subTest(a=a, b=b), self.assertRaises(TypeError):
                    systolic_array(a, b)


if __name__ == "__main__":
    unittest.main()
