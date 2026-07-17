"""F3.0a structural checks for the first explicit plume flux owner."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
SOLVER = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")


class TestPhase3CanonicalShadowPlume(unittest.TestCase):
    def test_solver_previews_before_applying_exact_transfer(self):
        self.assertIn("func preview_lower_to_upper_transfer", SOLVER)
        self.assertIn("func apply_lower_to_upper_transfer", SOLVER)
        transfer = SOLVER.split("func transfer_lower_to_upper", 1)[1].split(
            "func preview_lower_to_upper_transfer", 1
        )[0]
        self.assertLess(
            transfer.index("preview_lower_to_upper_transfer"),
            transfer.index("apply_lower_to_upper_transfer"),
        )

    def test_preview_is_pure(self):
        preview = SOLVER.split("func preview_lower_to_upper_transfer", 1)[1].split(
            "func apply_lower_to_upper_transfer", 1
        )[0]
        for assignment in (
            "room.lower_gas_kg =",
            "room.upper_gas_kg =",
            "room.lower_energy_kj =",
            "room.upper_energy_kj =",
        ):
            self.assertNotIn(assignment, preview)

    def test_thermal_records_result_before_legacy_mutation(self):
        plume = THERMAL.split("func _step_two_zone_plume_entrainment", 1)[1].split(
            "func _add_flame_region_entrainment", 1
        )[0]
        self.assertLess(
            plume.index("_phase3_shadow_flux_results.append"),
            plume.index("apply_lower_to_upper_transfer"),
        )

    def test_adapter_is_shadow_gated_and_topology_independent(self):
        plume = THERMAL.split("func _step_two_zone_plume_entrainment", 1)[1].split(
            "func _add_flame_region_entrainment", 1
        )[0]
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", plume)
        self.assertNotIn("_phase3_shadow_sealed_room_scope", plume)

    def test_mass_enthalpy_and_o2_share_one_result(self):
        for field in ("gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"):
            self.assertIn(f'"{field}"', THERMAL)
        self.assertIn("moved_mass_kg * clampf(room.o2_lower", THERMAL)

    def test_engine_owns_request_translation(self):
        self.assertIn("func _phase3_shadow_collect_thermal_requests", ENGINE)
        self.assertIn("thermal_system.drain_phase3_shadow_flux_results()", ENGINE)
        self.assertIn("phase3_zone_mass_system.make_request", ENGINE)

    def test_request_identity_contains_cause_room_and_time(self):
        self.assertIn('"%s:%d:%.6f" % [cause, room_id, sim_time_s]', ENGINE)

    def test_no_observed_stage_delta_feeds_adapter(self):
        collector = ENGINE.split("func _phase3_shadow_collect_thermal_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        self.assertNotIn("_phase3_zone_diag_step", collector)
        self.assertNotIn("projection_clamp", collector)


if __name__ == "__main__":
    unittest.main()
