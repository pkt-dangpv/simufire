"""Structural checks for SF-O1A: O₂ balance instrumentation.

Verifies that:
1. RoomModel declares all 6 O₂ balance accumulator fields.
2. reset_dynamic_state zeros all 6 fields (totals + steps).
3. CombustionSystem.step_room_fire zeros the 3 step fields at tick start.
4. OxygenExchangeSystem instruments each consumption path.
5. OxygenExchangeSystem instruments ACH exterior and exterior opening paths.
6. OxygenExchangeSystem._exchange_room_o2_immediate subtracts outgoing before write.
7. OxygenExchangeSystem._apply_room_o2_mass_delta accumulates net transport.
8. GasExchangeSystem.step_smoke accumulates o2_delta_kg as transport.
9. GasExchangeSystem.step_pressure_venting instruments exterior net.
10. GasExchangeSystem.step_ppv instruments exterior net.
11. ThermalSystem._apply_doorway_thermal_counterflow instruments transport.
12. ThermalSystem._apply_canonical_doorway_exchange instruments transport.
13. SimulationStateBuilder exports all 6 fields to per-room state.
14. SimulationLogWriter header contains all 6 column names.
15. SimulationLogWriter per-row appends all 6 fields.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ROOM = (ROOT / "sim" / "building" / "RoomModel.gd").read_text(encoding="utf-8")
COMBUSTION = (ROOT / "sim" / "fire" / "CombustionSystem.gd").read_text(encoding="utf-8")
OES = (ROOT / "sim" / "core" / "OxygenExchangeSystem.gd").read_text(encoding="utf-8")
GES = (ROOT / "sim" / "core" / "GasExchangeSystem.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim" / "core" / "ThermalSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim" / "core" / "SimulationLogWriter.gd").read_text(encoding="utf-8")

# All 6 field names
FIELDS = [
    "o2_consumed_kg_step_all",
    "o2_consumed_kg_total_all",
    "o2_exterior_net_kg_step",
    "o2_exterior_net_kg_total",
    "o2_net_transport_kg_step",
    "o2_net_transport_kg_total",
]

STEP_FIELDS = [f for f in FIELDS if "_step" in f and "_total" not in f]
TOTAL_FIELDS = [f for f in FIELDS if "_total" in f]


class TestRoomModelDeclarations(unittest.TestCase):
    def test_all_fields_declared(self):
        for field in FIELDS:
            self.assertIn(
                f"var {field}: float",
                ROOM,
                msg=f"RoomModel missing field declaration: {field}",
            )

    def test_reset_dynamic_state_zeros_all_fields(self):
        reset_body = ROOM.split("func reset_dynamic_state(", 1)[1].split("\nfunc ", 1)[0]
        for field in FIELDS:
            self.assertIn(
                f"{field} = 0.0",
                reset_body,
                msg=f"reset_dynamic_state missing zero for: {field}",
            )


class TestCombustionSystemStepReset(unittest.TestCase):
    def test_step_room_fire_zeros_step_fields(self):
        step_body = COMBUSTION.split("func step_room_fire(", 1)[1].split("\nfunc ", 1)[0]
        for field in STEP_FIELDS:
            self.assertIn(
                f"{field} = 0.0",
                step_body,
                msg=f"step_room_fire missing per-tick zero for: {field}",
            )

    def test_step_reset_before_fire_null_check(self):
        # The step-field resets must appear BEFORE "if room.fire == null"
        step_body = COMBUSTION.split("func step_room_fire(", 1)[1].split("\nfunc ", 1)[0]
        first_reset_pos = min(step_body.index(f"{f} = 0.0") for f in STEP_FIELDS)
        fire_null_pos = step_body.index("if room.fire == null")
        self.assertLess(
            first_reset_pos,
            fire_null_pos,
            msg="O1-A step resets must precede the 'if room.fire == null' branch",
        )


class TestOESConsumptionPaths(unittest.TestCase):
    def _step_body(self) -> str:
        return OES.split("func step(", 1)[1].split("\nfunc ", 1)[0]

    def test_bulk_consumption_accumulated(self):
        body = self._step_body()
        self.assertIn("o2_consumed_kg_step_all += consumed", body)
        self.assertIn("o2_consumed_kg_total_all += consumed", body)

    def test_ach_exterior_accumulated(self):
        body = self._step_body()
        self.assertIn("o2_exterior_net_kg_step += ach_o2_delta_kg", body)
        self.assertIn("o2_exterior_net_kg_total += ach_o2_delta_kg", body)

    def test_upper_consumed_accumulated(self):
        body = self._step_body()
        self.assertIn("o2_consumed_kg_step_all += upper_consumed", body)
        self.assertIn("o2_consumed_kg_total_all += upper_consumed", body)

    def test_lower_fire_uses_lower_accumulated(self):
        body = self._step_body()
        self.assertIn("o2_consumed_kg_step_all += consumed_lower", body)
        self.assertIn("o2_consumed_kg_total_all += consumed_lower", body)

    def test_plume_lower_accumulated(self):
        body = self._step_body()
        self.assertIn("o2_consumed_kg_step_all += plume_consumed", body)
        self.assertIn("o2_consumed_kg_total_all += plume_consumed", body)


class TestOESExteriorOpeningPath(unittest.TestCase):
    def test_outside_opening_exterior_net_accumulated(self):
        body = OES.split("func _step_outside_opening_o2(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("o2_exterior_net_kg_step +=", body)
        self.assertIn("o2_exterior_net_kg_total +=", body)
        # Before-after snapshot pattern
        self.assertIn("_o2_before_ext", body)


class TestOESTransportPaths(unittest.TestCase):
    def test_immediate_exchange_subtracts_outgoing(self):
        body = OES.split("func _exchange_room_o2_immediate(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("o2_net_transport_kg_step -= o2_a_out_kg", body)
        self.assertIn("o2_net_transport_kg_total -= o2_a_out_kg", body)
        self.assertIn("o2_net_transport_kg_step -= o2_b_out_kg", body)
        self.assertIn("o2_net_transport_kg_total -= o2_b_out_kg", body)

    def test_apply_mass_delta_accumulates_transport(self):
        body = OES.split("func _apply_room_o2_mass_delta(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("o2_net_transport_kg_step += delta_o2_kg", body)
        self.assertIn("o2_net_transport_kg_total += delta_o2_kg", body)


class TestGESInstrumentation(unittest.TestCase):
    def test_step_smoke_o2_delta_transport(self):
        # The background species apply loop must accumulate _ges_o2_delta as transport
        body = GES.split("func step_smoke(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_ges_o2_delta", body)
        self.assertIn("o2_net_transport_kg_step += _ges_o2_delta", body)
        self.assertIn("o2_net_transport_kg_total += _ges_o2_delta", body)

    def test_pressure_venting_exterior_net(self):
        body = GES.split("func step_pressure_venting(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_pv_o2_before", body)
        self.assertIn("o2_exterior_net_kg_step += _pv_o2_delta", body)
        self.assertIn("o2_exterior_net_kg_total += _pv_o2_delta", body)

    def test_ppv_exterior_net(self):
        body = GES.split("func step_ppv(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("_ppv_o2_before", body)
        self.assertIn("o2_exterior_net_kg_step += _ppv_o2_delta", body)
        self.assertIn("o2_exterior_net_kg_total += _ppv_o2_delta", body)


class TestThermalSystemInstrumentation(unittest.TestCase):
    def test_counterflow_transport_conserved(self):
        body = THERMAL.split("func _apply_doorway_thermal_counterflow(", 1)[1].split(
            "\nfunc ", 1
        )[0]
        self.assertIn("hot_room.o2_net_transport_kg_step += o2_delta_kg", body)
        self.assertIn("hot_room.o2_net_transport_kg_total += o2_delta_kg", body)
        self.assertIn("cold_room.o2_net_transport_kg_step -= o2_delta_kg", body)
        self.assertIn("cold_room.o2_net_transport_kg_total -= o2_delta_kg", body)

    def test_canonical_doorway_transport_conserved(self):
        body = THERMAL.split("func _apply_canonical_doorway_exchange(", 1)[1].split(
            "\nfunc ", 1
        )[0]
        self.assertIn("_cde_net_hot", body)
        self.assertIn("hot_room.o2_net_transport_kg_step += _cde_net_hot", body)
        self.assertIn("hot_room.o2_net_transport_kg_total += _cde_net_hot", body)
        self.assertIn("cold_room.o2_net_transport_kg_step -= _cde_net_hot", body)
        self.assertIn("cold_room.o2_net_transport_kg_total -= _cde_net_hot", body)


class TestStateBuilderExports(unittest.TestCase):
    def test_all_fields_exported(self):
        for field in FIELDS:
            self.assertIn(
                f'"{field}": room.{field}',
                STATE,
                msg=f"SimulationStateBuilder missing export: {field}",
            )


class TestLogWriterColumns(unittest.TestCase):
    def test_header_contains_all_columns(self):
        header_line = LOG.split("func _build_csv_header()", 1)[1].split("\n\n", 1)[0]
        for field in FIELDS:
            self.assertIn(
                field,
                header_line,
                msg=f"CSV header missing column: {field}",
            )

    def test_per_row_appends_all_fields(self):
        for field in FIELDS:
            self.assertIn(
                f'rs.get("{field}"',
                LOG,
                msg=f"SimulationLogWriter per-row missing: {field}",
            )


if __name__ == "__main__":
    unittest.main()
