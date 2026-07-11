"""Structural checks for Phase 3+ F1a conservative lower return flow.

F1a makes the canonical doorway exchange lower return flow move physical
lower_gas_kg mass (cold -> hot) instead of only energy/O2. Default OFF must be
an exact no-op; the flag is experimental and per-case only.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim" / "core" / "ThermalSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")

FLAG = "phase3_conservative_lower_return_enabled"


def _extract_f1a_gated_blocks(source: str) -> str:
    """Return the concatenated bodies of `if _f1a_active:` blocks in ThermalSystem."""
    blocks = []
    lines = source.splitlines()
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith("if _f1a_active:"):
            continue
        indent = len(line) - len(line.lstrip("\t"))
        j = i + 1
        while j < len(lines):
            nxt = lines[j]
            if nxt.strip() == "":
                j += 1
                continue
            nxt_indent = len(nxt) - len(nxt.lstrip("\t"))
            if nxt_indent <= indent:
                break
            blocks.append(nxt)
            j += 1
    return "\n".join(blocks)


class TestF1aFlagWiring(unittest.TestCase):
    def test_engine_flag_is_exported_and_default_false(self):
        self.assertIn(f"@export var {FLAG}: bool = false", ENGINE)

    def test_engine_propagates_flag_to_thermal_settings(self):
        self.assertIn(f'"{FLAG}": {FLAG},', ENGINE)

    def test_engine_exports_flag_in_state_context(self):
        # Same cosmetic-reporting pattern as doorway_thermal_counterflow_enabled.
        self.assertGreaterEqual(ENGINE.count(f'"{FLAG}": {FLAG}'), 2)

    def test_thermal_declares_flag_default_false(self):
        self.assertIn(f"var {FLAG}: bool = false", THERMAL)

    def test_thermal_reads_flag_in_configure(self):
        self.assertIn(
            f'{FLAG} = bool(settings.get("{FLAG}", {FLAG}))',
            THERMAL,
        )

    def test_state_builder_copies_flag(self):
        self.assertIn(
            f'"{FLAG}": bool(context.get("{FLAG}", false)),',
            STATE,
        )


class TestF1aGating(unittest.TestCase):
    def test_f1a_requires_two_zone_solver(self):
        # The active condition must AND the flag with two_zone_solver_enabled
        # so lower_gas_kg is only touched when the two-zone ledger exists.
        pattern = re.compile(
            r"var _f1a_active: bool = phase3_conservative_lower_return_enabled\s*\\\s*"
            r"\n\s*and two_zone_solver_enabled",
        )
        self.assertRegex(THERMAL, pattern)

    def test_mass_moves_only_inside_f1a_gate(self):
        gated = _extract_f1a_gated_blocks(THERMAL)
        self.assertIn("cold_room.lower_gas_kg = maxf(0.0, cold_room.lower_gas_kg - m_lower_kg)", gated)
        self.assertIn("hot_room.lower_gas_kg += m_to_lower_kg", gated)
        # OFF path must never move lower zone mass in the canonical exchange:
        # outside the gated blocks, Part B must not mutate lower_gas_kg.
        cde_body = THERMAL.split("func _apply_canonical_doorway_exchange(", 1)[1]
        cde_body = cde_body.split("\nfunc ", 1)[0]
        ungated = [
            line for line in cde_body.splitlines()
            if ("cold_room.lower_gas_kg =" in line or "hot_room.lower_gas_kg +=" in line)
        ]
        gated_lines = set(gated.splitlines())
        for line in ungated:
            self.assertIn(line, gated_lines, f"lower_gas_kg mutated outside _f1a_active gate: {line!r}")

    def test_f1a_caps_by_actual_ledger_mass(self):
        # Prevent negative lower_gas_kg: extra cap on the real ledger, not EOS estimate.
        self.assertIn(
            "m_lower_kg = minf(m_lower_kg, maxf(0.0, cold_room.lower_gas_kg) * 0.05)",
            THERMAL,
        )

    def test_f1a_records_opening_ledgers(self):
        gated = _extract_f1a_gated_blocks(THERMAL)
        self.assertIn("cold_room.two_zone_opening_lower_out_kg += m_lower_kg", gated)
        self.assertIn("hot_room.two_zone_opening_lower_in_kg += m_to_lower_kg", gated)
        self.assertIn("hot_room.two_zone_opening_upper_in_kg += m_direct_kg", gated)

    def test_f1a_uses_transported_enthalpy_not_mixing_delta(self):
        # When ON, hot.lower receives the sensible enthalpy of the moved air
        # (cold temp over ambient), not a fixed-mass mixing delta.
        self.assertIn(
            "m_to_lower_kg * maxf(0.0, cold_room.temp_lower_c - ambient_c) * _cp",
            THERMAL,
        )
        # Legacy mixing delta must remain for the OFF path.
        self.assertIn(
            "m_to_lower_kg * (cold_room.temp_lower_c - hot_room.temp_lower_c) * _cp",
            THERMAL,
        )


class TestF1aConservationShape(unittest.TestCase):
    def test_split_is_conservative(self):
        # cold loses the FULL m_lower_kg; hot receives m_to_lower (lower) and
        # m_direct (upper, pre-existing line). The split must remain
        # m_lower_kg = m_direct_kg + m_to_lower_kg with no double counting.
        self.assertIn("var m_direct_kg: float = m_lower_kg * _p3d_frac", THERMAL)
        self.assertIn("var m_to_lower_kg: float = m_lower_kg - m_direct_kg", THERMAL)
        gated = _extract_f1a_gated_blocks(THERMAL)
        # The cold decrement uses m_lower_kg (full), not m_to_lower_kg.
        self.assertIn("cold_room.lower_gas_kg - m_lower_kg", gated)


if __name__ == "__main__":
    unittest.main(verbosity=2)
