"""Structural checks for passive Phase 3+ F2.2a pressure-vent diagnostics."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ROOM = (ROOT / "sim/building/RoomModel.gd").read_text(encoding="utf-8")
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")

FIELDS = (
    "pressure_therm_pa",
    "pressure_model_pa",
    "pressure_effective_pa",
    "pressure_buoyancy_pa",
    "pressure_stack_pa",
    "pressure_raw_vented_air_kg_total",
    "pressure_capped_vented_air_kg_total",
)


class TestPhase3PressureVentDiagnostics(unittest.TestCase):
    def test_room_fields_are_reset(self):
        for field in FIELDS:
            internal = f"phase3_diag_{field}"
            self.assertIn(f"var {internal}: float = 0.0", ROOM)
            self.assertIn(f"{internal} = 0.0", ROOM)

    def test_mutations_are_diagnostics_gated(self):
        body = GAS.split("func step_pressure_venting", 1)[1].split("func step_smoke", 1)[0]
        for line in body.splitlines():
            if "phase3_diag_pressure_" not in line:
                continue
            prefix = body[: body.index(line)]
            self.assertIn("if phase3_zone_diagnostics_enabled:", prefix[-400:])

    def test_raw_air_mass_is_captured_before_smoke_cap(self):
        raw = GAS.index("var raw_vented_air_kg")
        cap = GAS.index("smoke_out_kg = minf", raw)
        raw_total = GAS.index("phase3_diag_pressure_raw_vented_air_kg_total", raw)
        self.assertLess(raw, cap)
        self.assertLess(cap, raw_total)

    def test_state_and_csv_expose_all_fields(self):
        for field in FIELDS:
            self.assertIn(f'room_state["{field}"]', STATE)
            self.assertIn(field, LOG)


if __name__ == "__main__":
    unittest.main()
