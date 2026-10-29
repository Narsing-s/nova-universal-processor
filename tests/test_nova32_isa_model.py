"""Unit and randomized tests for nova32_isa_model.py; no third-party packages needed."""
import random
import unittest

from nova32_isa_model import (
    MASK32, alu_i, alu_r, branch_taken, load_value, s32, sign_extend,
    store_lanes, u32,
)


class Nova32ReferenceModelTests(unittest.TestCase):
    def test_r_type_known_edges(self):
        a, b = 0xFFFF_FFF1, 7
        expected = {
            (0, 0): 0xFFFF_FFF8, (0x20, 0): 0xFFFF_FFEA,
            (0, 1): 0xFFFF_F880, (0, 2): 1, (0, 3): 0,
            (0, 4): 0xFFFF_FFF6, (0, 5): 0x01FF_FFFF,
            (0x20, 5): 0xFFFF_FFFF, (0, 6): 0xFFFF_FFF7,
            (0, 7): 7,
        }
        functs = [(0,0),(0x20,0),(0,1),(0,2),(0,3),(0,4),(0,5),(0x20,5),(0,6),(0,7)]
        for key in functs:
            self.assertEqual(alu_r(*key, a, b), expected[key], f"encoding {key}")

    def test_randomized_r_type_matches_independent_integer_formulas(self):
        rng = random.Random(0x32C0FFEE)
        cases = [(0,0),(0x20,0),(0,1),(0,2),(0,3),(0,4),(0,5),(0x20,5),(0,6),(0,7)]
        for _ in range(5000):
            a, b = rng.getrandbits(32), rng.getrandbits(32)
            sh = b & 31
            for f7, f3 in cases:
                got = alu_r(f7, f3, a, b)
                if (f7, f3) == (0,0): exp = u32(a + b)
                elif (f7, f3) == (0x20,0): exp = u32(a - b)
                elif (f7, f3) == (0,1): exp = u32(a << sh)
                elif (f7, f3) == (0,2): exp = int(s32(a) < s32(b))
                elif (f7, f3) == (0,3): exp = int(u32(a) < u32(b))
                elif (f7, f3) == (0,4): exp = u32(a ^ b)
                elif (f7, f3) == (0,5): exp = u32(a) >> sh
                elif (f7, f3) == (0x20,5): exp = u32(s32(a) >> sh)
                elif (f7, f3) == (0,6): exp = u32(a | b)
                else: exp = u32(a & b)
                self.assertEqual(got, exp)

    def test_immediate_arithmetic_and_shifts(self):
        self.assertEqual(alu_i(0, 0xFFF, 1), 0)  # addi -1
        self.assertEqual(alu_i(2, 0xFFF, 0xFFFF_FFFF), 0)
        self.assertEqual(alu_i(3, 0xFFF, 0), 1)  # unsigned compare against 0xffffffff
        self.assertEqual(alu_i(1, 3, 0x8000_0001, shamt=1), 2)
        self.assertEqual(alu_i(5, 0x401, 0x8000_0000, shamt=1, funct7=0x20), 0xC000_0000)

    def test_signed_extension_and_branch_conditions(self):
        self.assertEqual(sign_extend(0x80, 8), 0xFFFF_FF80)
        self.assertTrue(branch_taken(4, 0xFFFF_FFFF, 0))
        self.assertFalse(branch_taken(6, 0xFFFF_FFFF, 0))
        self.assertTrue(branch_taken(7, 0xFFFF_FFFF, 0))
        self.assertTrue(branch_taken(0, 12, 12))
        self.assertTrue(branch_taken(1, 12, 13))

    def test_load_extensions_and_alignment(self):
        word = 0x80FF_7F01
        self.assertEqual(load_value(word, 3, 0), 0xFFFF_FF80)
        self.assertEqual(load_value(word, 3, 4), 0x80)
        self.assertEqual(load_value(word, 2, 1), 0xFFFF_80FF)
        self.assertEqual(load_value(word, 2, 5), 0x80FF)
        self.assertEqual(load_value(word, 0, 2), word)
        with self.assertRaises(ValueError): load_value(word, 1, 1)
        with self.assertRaises(ValueError): load_value(word, 2, 2)

    def test_store_strobes_and_alignment(self):
        self.assertEqual(store_lanes(0xAABBCCDD, 2, 0), (0b0100, 0x00DD0000))
        self.assertEqual(store_lanes(0xAABBCCDD, 2, 1), (0b1100, 0xCCDD0000))
        self.assertEqual(store_lanes(0xAABBCCDD, 0, 2), (0b1111, 0xAABBCCDD))
        with self.assertRaises(ValueError): store_lanes(1, 1, 1)
        with self.assertRaises(ValueError): store_lanes(1, 1, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
