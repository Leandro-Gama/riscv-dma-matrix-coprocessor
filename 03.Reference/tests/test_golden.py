import random
import unittest
from collections import Counter
from itertools import product

from golden import (
    LOOP_ORDERS,
    PATTERNS,
    NumericFormat,
    TileConfig,
    generate,
    matmul_reference,
    matmul_tiled,
    shape,
    tile_schedule,
)

try:
    import numpy
except ImportError:
    numpy = None

SHAPES = [(1, 1, 1), (3, 5, 2), (8, 8, 8), (9, 1, 7), (16, 16, 16), (17, 13, 11)]
FORMATS = [NumericFormat(bits, 32, signed) for bits in (8, 16) for signed in (True, False)]
FORMATS += [NumericFormat(32, 64, True), NumericFormat(32, 64, False)]
CONFIGS = [TileConfig.square(size, order) for size in (2, 4, 8) for order in LOOP_ORDERS]
CONFIGS += [TileConfig(2, 3, 5), TileConfig(8, 2, 4, "kmn"), TileConfig(1, 4, 2, "mnk")]


class NumericFormatTest(unittest.TestCase):
    def test_ranges(self):
        self.assertEqual((NumericFormat(8).data_min, NumericFormat(8).data_max), (-128, 127))
        unsigned = NumericFormat(8, 32, signed=False)
        self.assertEqual((unsigned.data_min, unsigned.data_max), (0, 255))

    def test_wrap(self):
        fmt = NumericFormat(8, 16, True)
        self.assertEqual(fmt.wrap_acc(32767), 32767)
        self.assertEqual(fmt.wrap_acc(32768), -32768)
        self.assertEqual(fmt.wrap_acc(-32769), 32767)
        self.assertEqual(NumericFormat(8, 16, False).wrap_acc(65536 + 5), 5)

    def test_invalid(self):
        with self.assertRaises(ValueError):
            NumericFormat(0)
        with self.assertRaises(ValueError):
            NumericFormat(16, 8)
        with self.assertRaises(ValueError):
            NumericFormat(8).check_operand(128)
        with self.assertRaises(TypeError):
            NumericFormat(8).check_operand(True)


class GenerateTest(unittest.TestCase):
    def test_patterns_stay_in_range(self):
        fmt = NumericFormat(8, 32, True)
        for pattern in PATTERNS:
            with self.subTest(pattern=pattern):
                mat = generate(4, 3, fmt, random.Random(0), pattern)
                self.assertEqual(shape(mat), (4, 3))
                for row in mat:
                    for value in row:
                        fmt.check_operand(value)

    def test_seed_is_deterministic(self):
        fmt = NumericFormat(16)
        self.assertEqual(
            generate(5, 5, fmt, random.Random(42)), generate(5, 5, fmt, random.Random(42))
        )

    def test_invalid(self):
        with self.assertRaises(ValueError):
            generate(0, 3, NumericFormat(), random.Random(0))
        with self.assertRaises(ValueError):
            generate(2, 2, NumericFormat(), random.Random(0), "diagonal")
        with self.assertRaises(ValueError):
            shape([[1, 2], [3]])


class TileScheduleTest(unittest.TestCase):
    def test_every_product_is_covered_once(self):
        for (m, n, k), cfg in product(SHAPES, CONFIGS):
            with self.subTest(m=m, n=n, k=k, cfg=cfg):
                covered = Counter()
                for t in tile_schedule(m, n, k, cfg):
                    self.assertTrue(1 <= t.rows <= cfg.tile_m and 1 <= t.cols <= cfg.tile_n)
                    self.assertTrue(1 <= t.depth <= cfg.tile_k)
                    for i in range(t.m0, t.m0 + t.rows):
                        for j in range(t.n0, t.n0 + t.cols):
                            for x in range(t.k0, t.k0 + t.depth):
                                covered[(i, j, x)] += 1
                self.assertEqual(set(covered), set(product(range(m), range(n), range(k))))
                self.assertEqual(set(covered.values()), {1})

    def test_order_matches_independent_oracle(self):
        m, n, k = 5, 3, 7
        steps = {"m": 2, "n": 3, "k": 4}
        extent = {"m": m, "n": n, "k": k}
        for order in LOOP_ORDERS:
            with self.subTest(order=order):
                cfg = TileConfig(steps["m"], steps["n"], steps["k"], order)
                expected = []
                for starts in product(*(range(0, extent[d], steps[d]) for d in order)):
                    at = dict(zip(order, starts))
                    expected.append((at["m"], at["n"], at["k"]))
                got = [(t.m0, t.n0, t.k0) for t in tile_schedule(m, n, k, cfg)]
                self.assertEqual(got, expected)

    def test_default_order_keeps_weights_fixed_while_a_streams(self):
        tiles = list(tile_schedule(4, 4, 4, TileConfig.square(2)))
        self.assertEqual([(t.n0, t.k0, t.m0) for t in tiles[:3]], [(0, 0, 0), (0, 0, 2), (0, 2, 0)])

    def test_invalid(self):
        with self.assertRaises(ValueError):
            TileConfig(0, 2, 2)
        with self.assertRaises(ValueError):
            TileConfig.square(2, "mkm")
        with self.assertRaises(ValueError):
            tile_schedule(0, 2, 2, TileConfig.square(2))


class MatmulTest(unittest.TestCase):
    def test_tiled_matches_reference(self):
        rng = random.Random(7)
        for fmt in FORMATS:
            for m, n, k in SHAPES:
                a = generate(m, k, fmt, rng)
                b = generate(k, n, fmt, rng)
                expected = matmul_reference(a, b, fmt)
                for cfg in CONFIGS:
                    with self.subTest(fmt=fmt, m=m, n=n, k=k, cfg=cfg):
                        self.assertEqual(matmul_tiled(a, b, fmt, cfg), expected)

    def test_known_product(self):
        fmt = NumericFormat()
        a = [[1, 2], [3, 4]]
        b = [[5, 6], [7, 8]]
        self.assertEqual(matmul_tiled(a, b, fmt, TileConfig.square(1)), [[19, 22], [43, 50]])

    def test_accumulator_wraps(self):
        # (-128)^2 * 4 = 65536 wraps to 0 in a 16-bit signed accumulator.
        fmt = NumericFormat(8, 16, True)
        a = generate(2, 4, fmt, random.Random(0), "min")
        b = generate(4, 2, fmt, random.Random(0), "min")
        self.assertEqual(matmul_reference(a, b, fmt), [[0, 0], [0, 0]])
        self.assertEqual(matmul_tiled(a, b, fmt, TileConfig.square(2)), [[0, 0], [0, 0]])

    def test_extreme_values(self):
        fmt = NumericFormat(8, 32, True)
        rng = random.Random(0)
        for pa in ("max", "min"):
            for pb in ("max", "min"):
                a = generate(17, 13, fmt, rng, pa)
                b = generate(13, 11, fmt, rng, pb)
                with self.subTest(a=pa, b=pb):
                    expected = fmt.wrap_acc(a[0][0] * b[0][0] * 13)
                    got = matmul_tiled(a, b, fmt, TileConfig.square(4))
                    self.assertEqual({v for row in got for v in row}, {expected})

    def test_invalid_operands(self):
        fmt = NumericFormat()
        cfg = TileConfig.square(2)
        with self.assertRaises(ValueError):
            matmul_tiled([[1, 2]], [[1, 2]], fmt, cfg)
        with self.assertRaises(ValueError):
            matmul_tiled([[200]], [[1]], fmt, cfg)

    @unittest.skipIf(numpy is None, "numpy not available")
    def test_against_numpy(self):
        fmt = NumericFormat(8, 32, True)
        rng = random.Random(3)
        a = generate(17, 13, fmt, rng)
        b = generate(13, 11, fmt, rng)
        expected = (numpy.array(a, dtype=numpy.int64) @ numpy.array(b, dtype=numpy.int64)).tolist()
        self.assertEqual(matmul_tiled(a, b, fmt, TileConfig.square(8)), expected)


if __name__ == "__main__":
    unittest.main()
