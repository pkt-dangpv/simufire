"""F3.0d structural checks for canonical combustion species sources."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


class TestPhase3CanonicalShadowSpecies(unittest.TestCase):
    def test_result_is_built_after_carbon_clamp(self):
        step = COMBUSTION.split("func step_room_fire", 1)[1].split(
            "func extinguish_room_fire", 1
        )[0]
        self.assertLess(step.index("generated_co_kg *= c_scale"), step.index("species_generation_result"))
        self.assertLess(step.index("generated_co2_kg *= c_scale"), step.index("species_generation_result"))
        self.assertLess(step.index("generated_hcn_kg *= c_scale"), step.index("species_generation_result"))

    def test_result_is_recorded_before_any_species_stock_write(self):
        step = COMBUSTION.split("func step_room_fire", 1)[1].split(
            "func extinguish_room_fire", 1
        )[0]
        result_pos = step.index("_phase3_shadow_species_results.append")
        apply_pos = step.index("_apply_species_generation_result(room, species_generation_result)")
        self.assertLess(result_pos, apply_pos)
        helper = COMBUSTION.split("func _apply_species_generation_result", 1)[1].split(
            "func ensure_room_fuel_objects", 1
        )[0]
        for write in ("room.co_kg +=", "room.co2_kg +=", "room.hcn_kg +="):
            self.assertIn(write, helper)

    def test_legacy_and_shadow_share_one_result_object(self):
        self.assertIn("species_generation_result.duplicate(true)", COMBUSTION)
        self.assertIn("_apply_species_generation_result(room, species_generation_result)", COMBUSTION)

    def test_exact_total_and_zonal_split_share_one_result(self):
        helper = COMBUSTION.split("func _apply_species_generation_result", 1)[1].split(
            "func ensure_room_fuel_objects", 1
        )[0]
        self.assertIn('total.get("co", 0.0)', helper)
        self.assertIn('upper.get("co", 0.0)', helper)
        result = COMBUSTION.split("var species_generation_result", 1)[1].split(
            "_apply_species_generation_result", 1
        )[0]
        self.assertIn('"total_species_kg"', result)
        collector = ENGINE.split("func _phase3_shadow_collect_species_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        self.assertEqual(collector.count('for zone_name in ["upper", "lower"]'), 1)
        self.assertNotIn("total_species_kg", collector)

    def test_co_split_respects_phase2g(self):
        result = COMBUSTION.split("var species_generation_result", 1)[1].split(
            "_apply_species_generation_result", 1
        )[0]
        self.assertIn('"co": generated_co_kg * _p2g_upper_frac', result)
        self.assertIn('"co": generated_co_kg * (1.0 - _p2g_upper_frac)', result)
        self.assertIn('"co2": 0.0', result)
        self.assertIn('"hcn": 0.0', result)

    def test_tracer_and_irritants_are_out_of_scope(self):
        result = COMBUSTION.split("var species_generation_result", 1)[1].split(
            "_apply_species_generation_result", 1
        )[0]
        for excluded in ("co2_upper", "hcl", "acrolein", "formaldehyde", "smoke"):
            self.assertNotIn(excluded, result)

    def test_engine_only_translates_the_result(self):
        collector = ENGINE.split("func _phase3_shadow_collect_species_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        self.assertIn("combustion_system.drain_phase3_shadow_species_results()", collector)
        for forbidden in ("yield", "phi", "c_scale", "generated_co", "co_generated_kg_step"):
            self.assertNotIn(forbidden, collector)

    def test_request_is_species_only_from_exterior(self):
        collector = ENGINE.split("func _phase3_shadow_collect_species_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        self.assertIn("phase3_zone_mass_system.EXTERIOR_ID", collector)
        self.assertIn("species", collector)
        self.assertIn("\n\t\t\t\t\t0.0,\n\t\t\t\t\t0.0,\n\t\t\t\t\t0.0,", collector)

    def test_pool_and_backdraft_feed_generation_before_result(self):
        step = COMBUSTION.split("func step_room_fire", 1)[1].split(
            "func extinguish_room_fire", 1
        )[0]
        result_pos = step.index("species_generation_result")
        self.assertLess(step.index("actual_pool_burn_kw"), result_pos)
        self.assertLess(step.index("room.backdraft_active"), result_pos)
        self.assertLess(step.index("co_basis_MJ"), result_pos)

    def test_species_bit_is_set_only_for_owned_cause(self):
        mask = SYSTEM.split("func _combustion_owned_mask", 1)[1].split(
            "func _sum_room_cause_mass", 1
        )[0]
        self.assertIn('"combustion_species_source"', mask)
        self.assertIn("mask |= 4", mask)

    def test_species_telemetry_is_shadow_gated(self):
        fields = (
            "phase3_shadow_combustion_co_request_kg",
            "phase3_shadow_combustion_co2_request_kg",
            "phase3_shadow_combustion_hcn_request_kg",
            "phase3_shadow_combustion_species_rejected_kg",
        )
        for field in fields:
            self.assertEqual(LOG.count(field), 2)

    def test_no_post_mutation_delta_feeds_adapter(self):
        collector = ENGINE.split("func _phase3_shadow_collect_species_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        for forbidden in ("_phase3_zone_diag_step", "projection_clamp", "reconcile"):
            self.assertNotIn(forbidden, collector)


if __name__ == "__main__":
    unittest.main()
