"""
tests/test_room_model_reset.py — Regression tests for RoomModel.reset_dynamic_state().

Verifies that all two-zone gas fields are explicitly reset inside the function,
including fields added in Phase 2B/2C that were historically omitted:
  - co2_upper       (mol fraction, ambient = 0.0004)
  - co2_upper_kg    (mass in upper zone)
  - hcn_upper_kg    (mass in upper zone)

Strategy: parse the GDScript source as plain text and assert each reset
assignment is present. No Godot runtime required.

Run:
    python tests/test_room_model_reset.py
    # or:
    python -m pytest tests/test_room_model_reset.py -v
"""

import re
import unittest
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_ROOM_MODEL = _REPO_ROOT / "sim" / "building" / "RoomModel.gd"


def _extract_reset_body(source: str) -> str:
    """Return the body of reset_dynamic_state() as a string."""
    # Find the function declaration and collect lines until the next top-level func/class.
    lines = source.splitlines()
    in_func = False
    body_lines = []
    for line in lines:
        if re.match(r"^func reset_dynamic_state\s*\(", line):
            in_func = True
            continue
        if in_func:
            # Stop at the next top-level function or class definition
            if re.match(r"^func |^class ", line):
                break
            body_lines.append(line)
    return "\n".join(body_lines)


class TestRoomModelResetDynamicState(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.source = _ROOM_MODEL.read_text(encoding="utf-8")
        cls.reset_body = _extract_reset_body(cls.source)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _assert_reset(self, field: str, expected_value: str):
        """Assert that `field = <expected_value>` appears in the reset body."""
        # Allow optional whitespace around '='
        pattern = rf"\b{re.escape(field)}\s*=\s*{re.escape(expected_value)}\b"
        self.assertRegex(
            self.reset_body,
            pattern,
            msg=f"reset_dynamic_state() must set `{field} = {expected_value}` but it was not found.",
        )

    # ------------------------------------------------------------------
    # Pre-existing fields (smoke-test that we haven't broken them)
    # ------------------------------------------------------------------

    def test_co_kg_reset(self):
        self._assert_reset("co_kg", "0.0")

    def test_co_upper_kg_reset(self):
        self._assert_reset("co_upper_kg", "0.0")

    def test_co2_kg_reset(self):
        self._assert_reset("co2_kg", "0.0")

    def test_hcn_kg_reset(self):
        self._assert_reset("hcn_kg", "0.0")

    def test_o2_upper_reset(self):
        self._assert_reset("o2_upper", "ambient_o2")

    def test_o2_lower_reset(self):
        self._assert_reset("o2_lower", "ambient_o2")

    # ------------------------------------------------------------------
    # Previously-missing fields — the regression being fixed
    # ------------------------------------------------------------------

    def test_co2_upper_mol_fraction_reset(self):
        """co2_upper (mol fraction) must be reset to ambient CO2 (0.0004)."""
        self._assert_reset("co2_upper", "0.0004")

    def test_co2_upper_kg_reset(self):
        """co2_upper_kg (upper-zone mass) must be reset to 0.0."""
        self._assert_reset("co2_upper_kg", "0.0")

    def test_hcn_upper_kg_reset(self):
        """hcn_upper_kg (upper-zone mass) must be reset to 0.0."""
        self._assert_reset("hcn_upper_kg", "0.0")

    # ------------------------------------------------------------------
    # Ordering sanity: co2_upper_kg must appear after co2_kg
    # ------------------------------------------------------------------

    def test_co2_upper_kg_after_co2_kg(self):
        """co2_upper_kg reset must appear after co2_kg reset (logical grouping)."""
        pos_co2_kg = self.reset_body.find("co2_kg = 0.0")
        pos_co2_upper_kg = self.reset_body.find("co2_upper_kg = 0.0")
        self.assertGreater(
            pos_co2_upper_kg,
            pos_co2_kg,
            "co2_upper_kg = 0.0 must appear after co2_kg = 0.0 in reset_dynamic_state()",
        )

    def test_hcn_upper_kg_after_hcn_kg(self):
        """hcn_upper_kg reset must appear after hcn_kg reset (logical grouping)."""
        pos_hcn_kg = self.reset_body.find("hcn_kg = 0.0")
        pos_hcn_upper_kg = self.reset_body.find("hcn_upper_kg = 0.0")
        self.assertGreater(
            pos_hcn_upper_kg,
            pos_hcn_kg,
            "hcn_upper_kg = 0.0 must appear after hcn_kg = 0.0 in reset_dynamic_state()",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
