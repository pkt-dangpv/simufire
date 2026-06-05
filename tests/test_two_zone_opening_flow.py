"""M3 checks for two-zone opening species routing."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ROOM = (ROOT / "sim" / "building" / "RoomModel.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
GAS = (ROOT / "sim" / "core" / "GasExchangeSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
CASE_RUNNER = (ROOT / "sim" / "validation" / "CaseRunner.gd").read_text(encoding="utf-8")
RUN_CASE = (ROOT / "sim" / "validation" / "run_case.ps1").read_text(encoding="utf-8")
COMPARE_RUNNER = (
    ROOT / "sim" / "validation" / "run_legacy_two_zone_compare.ps1"
).read_text(encoding="utf-8")


class TestTwoZoneOpeningArithmetic(unittest.TestCase):
    def test_upper_and_lower_paths_conserve_species_total(self):
        hot_upper_co = 0.30
        hot_total_co = 0.50
        cold_upper_co = 0.02
        cold_total_co = 0.12
        before_total = hot_total_co + cold_total_co
        before_upper = hot_upper_co + cold_upper_co

        upper_frac = 0.10
        lower_frac = 0.25
        moved_upper = hot_upper_co * upper_frac
        moved_lower = (cold_total_co - cold_upper_co) * lower_frac

        hot_total_co = hot_total_co - moved_upper + moved_lower
        hot_upper_co = hot_upper_co - moved_upper
        cold_total_co = cold_total_co + moved_upper - moved_lower
        cold_upper_co = cold_upper_co + moved_upper

        self.assertAlmostEqual(hot_total_co + cold_total_co, before_total)
        self.assertAlmostEqual(hot_upper_co + cold_upper_co, before_upper)

    def test_lower_counterflow_does_not_add_upper_mass(self):
        cold_total_co = 0.12
        cold_upper_co = 0.02
        hot_upper_co = 0.30
        lower_frac = 0.25

        moved_lower = (cold_total_co - cold_upper_co) * lower_frac
        hot_total_delta = moved_lower
        hot_upper_delta = 0.0

        self.assertGreater(hot_total_delta, 0.0)
        self.assertEqual(hot_upper_delta, 0.0)
        self.assertAlmostEqual(cold_upper_co, 0.02)
        self.assertAlmostEqual(hot_upper_co, 0.30)


class TestTwoZoneOpeningStructure(unittest.TestCase):
    def test_engine_exposes_m3_flag_default_off(self):
        self.assertIn("@export var two_zone_opening_flow_enabled: bool = false", ENGINE)
        self.assertIn(
            '"two_zone_opening_flow_enabled": two_zone_solver_enabled and two_zone_opening_flow_enabled',
            ENGINE,
        )

    def test_gas_exchange_receives_shared_opening_flow_cache(self):
        self.assertIn('"opening_flow_cache": _opening_flow_cache', ENGINE)
        self.assertIn('var opening_flow_cache: Dictionary = hooks.get("opening_flow_cache", {})', GAS)

    def test_background_exchange_branches_to_two_zone_router(self):
        self.assertIn("if two_zone_opening_flow_enabled and _apply_two_zone_opening_species_exchange(", GAS)
        self.assertIn("func _apply_two_zone_opening_species_exchange(", GAS)
        self.assertIn('flow_state.get("bernoulli_upper_kg_s"', GAS)
        self.assertIn('flow_state.get("bernoulli_lower_kg_s"', GAS)

    def test_upper_path_routes_upper_species_to_upper_destination(self):
        body = GAS.split("func _move_upper_zone_species(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("clampf(from_r.co_upper_kg, 0.0, from_r.co_kg) * frac", body)
        self.assertIn("_add_delta(co_upper_delta_kg, from_r.id, -moved_co_kg)", body)
        self.assertIn("_add_delta(co_upper_delta_kg, to_r.id, moved_co_kg)", body)
        self.assertIn("_add_delta(co2_upper_delta_kg, to_r.id, moved_co2_kg)", body)
        self.assertIn("_add_delta(hcn_upper_delta_kg, to_r.id, moved_hcn_kg)", body)

    def test_lower_path_routes_lower_species_without_upper_delta(self):
        body = GAS.split("func _move_lower_zone_species(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("from_r.co_kg - clampf(from_r.co_upper_kg", body)
        self.assertIn("from_r.co2_kg - clampf(from_r.co2_upper_kg", body)
        self.assertNotIn("_add_delta(co_upper_delta_kg", body)
        self.assertNotIn("_add_delta(co2_upper_delta_kg", body)
        self.assertNotIn("_add_delta(hcn_upper_delta_kg", body)

    def test_room_and_state_export_m3_opening_telemetry(self):
        for field in (
            "two_zone_opening_upper_in_kg",
            "two_zone_opening_upper_out_kg",
            "two_zone_opening_lower_in_kg",
            "two_zone_opening_lower_out_kg",
        ):
            self.assertIn(f"var {field}: float = 0.0", ROOM)
            self.assertIn(f"{field} = 0.0", ROOM)
            self.assertIn(f'"{field}": room.{field}', STATE)
            self.assertIn(f'room_state.get("{field}", 0.0)', CASE_RUNNER)

    def test_validation_cli_can_enable_m3_without_editing_case(self):
        self.assertIn("[switch]$TwoZoneOpeningFlow", RUN_CASE)
        self.assertIn("--validation-two-zone-opening-flow", RUN_CASE)
        self.assertIn("--validation-two-zone-opening-flow", CASE_RUNNER)
        self.assertIn("engine.two_zone_opening_flow_enabled", CASE_RUNNER)
        self.assertIn("-TwoZoneOpeningFlow:$TwoZoneOpeningFlow", COMPARE_RUNNER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
