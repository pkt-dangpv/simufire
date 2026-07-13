"""F3.0c structural checks for zonal combustion O2 shadow ownership."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
OES = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


class TestPhase3CanonicalShadowO2(unittest.TestCase):
    def test_shadow_flag_is_wired_into_oes(self):
        self.assertIn("var phase3_canonical_zone_shadow_enabled: bool = false", OES)
        self.assertIn(
            '"phase3_canonical_zone_shadow_enabled": phase3_canonical_zone_shadow_enabled',
            ENGINE,
        )

    def test_oes_owns_explicit_upper_and_lower_sinks(self):
        for cause in (
            "combustion_o2_upper_sink",
            "combustion_o2_lower_sink",
            "combustion_o2_plume_lower_sink",
        ):
            self.assertIn(cause, OES)

    def test_upper_result_is_computed_before_mutation(self):
        block = OES.split("var upper_o2_before", 1)[1].split(
            "var entr_frac", 1
        )[0]
        self.assertLess(
            block.index("_record_phase3_shadow_o2_sink"),
            block.index("room.o2_upper = upper_o2_after"),
        )
        self.assertIn("(upper_o2_before - upper_o2_after) * upper_air_mass", block)

    def test_lower_results_are_computed_before_mutation(self):
        lower = OES.split("var lower_o2_before", 1)[1].split(
            "# R2-2: consumo directo", 1
        )[0]
        plume = OES.split("var plume_o2_before", 1)[1].split(
            "var ach_lower_dt", 1
        )[0]
        self.assertLess(
            lower.index("_record_phase3_shadow_o2_sink"),
            lower.index("room.o2_lower = lower_o2_after"),
        )
        self.assertLess(
            plume.index("_record_phase3_shadow_o2_sink"),
            plume.index("room.o2_lower = plume_o2_after"),
        )

    def test_sink_contract_moves_only_o2_to_exterior(self):
        helper = OES.split("func _record_phase3_shadow_o2_sink", 1)[1].split(
            "func _uses_lower_o2_for_fire", 1
        )[0]
        self.assertIn('"source_room_id": room.id', helper)
        self.assertIn('"destination_room_id": -1', helper)
        self.assertIn('"gas_mass_kg": 0.0', helper)
        self.assertIn('"sensible_enthalpy_kj": 0.0', helper)
        self.assertIn('"o2_kg": accepted_o2_kg', helper)
        self.assertIn('"species_kg": {}', helper)

    def test_bulk_path_is_deliberately_not_emitted(self):
        bulk = OES.split("var o2_mass_kg", 1)[1].split(
            "var ach_o2_delta_kg", 1
        )[0]
        self.assertNotIn("_record_phase3_shadow_o2_sink", bulk)

    def test_engine_collects_once_after_either_oes_order(self):
        step = ENGINE.split("func step(delta", 1)[1].split(
            "func _build_fire_defaults", 1
        )[0]
        self.assertEqual(step.count("_phase3_shadow_collect_oxygen_requests()"), 2)
        self.assertIn("if pre_hrr_o2_step:", step)
        self.assertIn("if not pre_hrr_o2_step:", step)

    def test_engine_adapter_does_not_recalculate_combustion(self):
        collector = ENGINE.split("func _phase3_shadow_collect_oxygen_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        self.assertIn('flux.get("o2_kg", 0.0)', collector)
        self.assertNotIn("hrr_kw", collector)
        self.assertNotIn("Thornton", collector)
        self.assertNotIn("o2_consumed_kg_step", collector)

    def test_request_identity_contains_zone(self):
        self.assertIn('"%s:%d:%s:%.6f"', ENGINE)

    def test_rejected_o2_and_partial_ownership_are_visible(self):
        self.assertIn("rejected_combustion_o2_by_room", SYSTEM)
        self.assertIn("phase3_shadow_combustion_o2_rejected_kg", SYSTEM)
        self.assertIn("requested_o2_kg * (1.0 - accepted_fraction)", SYSTEM)
        self.assertIn("mask |= 2", SYSTEM)

    def test_csv_fields_are_shadow_gated(self):
        for field in (
            "phase3_shadow_combustion_o2_request_kg",
            "phase3_shadow_combustion_o2_rejected_kg",
        ):
            self.assertEqual(LOG.count(field), 2)

    def test_no_stage_delta_or_projection_feeds_o2_adapter(self):
        collector = ENGINE.split("func _phase3_shadow_collect_oxygen_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        self.assertNotIn("_phase3_zone_diag_step", collector)
        self.assertNotIn("projection_clamp", collector)


if __name__ == "__main__":
    unittest.main()
