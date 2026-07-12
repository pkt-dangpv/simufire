"""Structural checks for Phase 3+ F2.0 zone mass flow ledger diagnostics.

F2.0 adds cumulative, sampling-proof counters at every site that moves or
removes upper-zone mass without recording in two_zone_boundary or the opening
ledgers. Pure passive instrumentation gated by phase3_zone_diagnostics_enabled;
default OFF must be an exact no-op.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim" / "core" / "ThermalSystem.gd").read_text(encoding="utf-8")
GES = (ROOT / "sim" / "core" / "GasExchangeSystem.gd").read_text(encoding="utf-8")
ROOM = (ROOT / "sim" / "building" / "RoomModel.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim" / "core" / "SimulationLogWriter.gd").read_text(encoding="utf-8")

COUNTERS = [
    "phase3_diag_zone_doorway_upper_out_kg_total",
    "phase3_diag_zone_doorway_upper_in_kg_total",
    "phase3_diag_zone_parcel_upper_out_kg_total",
    "phase3_diag_zone_parcel_upper_in_kg_total",
    "phase3_diag_zone_upper_removed_kg_total",
]

CSV_COLUMNS = [
    "zone_doorway_upper_out_kg_total",
    "zone_doorway_upper_in_kg_total",
    "zone_parcel_upper_out_kg_total",
    "zone_parcel_upper_in_kg_total",
    "zone_upper_removed_kg_total",
]


class TestRoomModelCounters(unittest.TestCase):
    def test_counters_declared_default_zero(self):
        for c in COUNTERS:
            self.assertIn(f"var {c}: float = 0.0", ROOM)

    def test_counters_reset(self):
        for c in COUNTERS:
            self.assertIn(f"{c} = 0.0", ROOM)


class TestAccumulationIsGated(unittest.TestCase):
    def _assert_gated(self, source: str, needle: str, name: str):
        """Every accumulation of `needle` must sit inside a
        phase3_zone_diagnostics_enabled gate (within the preceding 6 lines)."""
        lines = source.splitlines()
        found = 0
        for i, line in enumerate(lines):
            if needle in line and "+=" in line:
                found += 1
                window = "\n".join(lines[max(0, i - 6):i])
                self.assertIn(
                    "if phase3_zone_diagnostics_enabled:",
                    window,
                    f"{name}: accumulation at line {i+1} not gated",
                )
        self.assertGreater(found, 0, f"{name}: no accumulation of {needle} found")

    def test_thermal_doorway_out_gated(self):
        self._assert_gated(THERMAL, "phase3_diag_zone_doorway_upper_out_kg_total", "ThermalSystem")

    def test_thermal_doorway_in_gated(self):
        self._assert_gated(THERMAL, "phase3_diag_zone_doorway_upper_in_kg_total", "ThermalSystem")

    def test_thermal_removed_gated(self):
        self._assert_gated(THERMAL, "phase3_diag_zone_upper_removed_kg_total", "ThermalSystem")

    def test_removed_recorded_before_mutation(self):
        # The removed counter must capture upper_gas_kg * frac BEFORE the multiply.
        idx_counter = THERMAL.index("phase3_diag_zone_upper_removed_kg_total += room.upper_gas_kg * frac")
        idx_mutation = THERMAL.index("room.upper_gas_kg *= (1.0 - frac)")
        self.assertLess(idx_counter, idx_mutation)

    def test_ges_parcel_out_gated(self):
        self._assert_gated(GES, "phase3_diag_zone_parcel_upper_out_kg_total", "GasExchangeSystem")

    def test_ges_parcel_in_gated(self):
        self._assert_gated(GES, "phase3_diag_zone_parcel_upper_in_kg_total", "GasExchangeSystem")

    def test_ges_background_pair_gated(self):
        self._assert_gated(GES, "phase3_diag_zone_doorway_upper_out_kg_total", "GasExchangeSystem")
        self._assert_gated(GES, "phase3_diag_zone_doorway_upper_in_kg_total", "GasExchangeSystem")


class TestWiring(unittest.TestCase):
    def test_ges_declares_and_reads_flag(self):
        self.assertIn("var phase3_zone_diagnostics_enabled: bool = false", GES)
        self.assertIn(
            'phase3_zone_diagnostics_enabled = bool(settings.get("phase3_zone_diagnostics_enabled", phase3_zone_diagnostics_enabled))',
            GES,
        )

    def test_engine_passes_flag_to_gas_exchange(self):
        gas_cfg = ENGINE.split("gas_exchange_system.configure({", 1)[1].split("})", 1)[0]
        self.assertIn('"phase3_zone_diagnostics_enabled": phase3_zone_diagnostics_enabled', gas_cfg)

    def test_state_builder_exports_counters_in_gated_block(self):
        gated = STATE.split("if phase3_zone_diagnostics_enabled:", 1)[1]
        for col, counter in zip(CSV_COLUMNS, COUNTERS):
            self.assertIn(f'room_state["{col}"] = room.{counter}', gated)

    def test_log_writer_header_and_fields(self):
        for col in CSV_COLUMNS:
            self.assertEqual(LOG.count(col), 2, f"{col} must appear in header and field list")
        # Both usages must live inside the diagnostics gate (header line and fields loop).
        header_gate = LOG.split("func _build_csv_header()", 1)[1].split("return header", 1)[0]
        self.assertIn("if phase3_zone_diagnostics_enabled:", header_gate)
        for col in CSV_COLUMNS:
            self.assertIn(col, header_gate)


if __name__ == "__main__":
    unittest.main(verbosity=2)
