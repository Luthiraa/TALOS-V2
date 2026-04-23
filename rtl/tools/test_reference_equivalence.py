import unittest
from pathlib import Path

from reference_equivalence import (
    collect_python_reference,
    collect_xorshift_reference,
    count_params,
    load_float_state,
    load_q12_dequant_state,
)


class ReferenceEquivalenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.weights_path = cls.root / "rtl/microgpt/weights_only.npy"
        cls.names_path = cls.root / "arm/training/names.txt"
        cls.float_state = load_float_state(cls.weights_path)
        cls.q12_state = load_q12_dequant_state(cls.weights_path)

    def test_param_count_is_unchanged(self) -> None:
        self.assertEqual(count_params(self.float_state), 4192)
        self.assertEqual(count_params(self.q12_state), 4192)

    def test_q12_dequant_matches_exact_python_reference(self) -> None:
        float_rows = collect_python_reference(self.float_state, self.names_path, count=5, temperature=0.5)
        q12_rows = collect_python_reference(self.q12_state, self.names_path, count=5, temperature=0.5)
        self.assertEqual(float_rows, q12_rows)
        self.assertEqual(
            [text for _, text, _ in float_rows],
            ["kamon", "ann", "karai", "jaire", "vialan"],
        )

    def test_q12_dequant_matches_exact_xorshift_reference(self) -> None:
        float_rows = collect_xorshift_reference(
            self.float_state, self.names_path, count=5, temperature=0.5, seed=2
        )
        q12_rows = collect_xorshift_reference(
            self.q12_state, self.names_path, count=5, temperature=0.5, seed=2
        )
        self.assertEqual(float_rows, q12_rows)
        self.assertEqual(
            [text for _, text, _, _ in float_rows],
            ["aarin", "anana", "alana", "jayx", "javian"],
        )


if __name__ == "__main__":
    unittest.main()
