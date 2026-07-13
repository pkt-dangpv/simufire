"""F3.0b structural checks for the explicit combustion heat contract."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


class TestPhase3CanonicalShadowCombustion(unittest.TestCase):
    def test_thermal_owns_one_exact_convective_energy_value(self):
        block = THERMAL.split("var convective_energy_kj", 1)[1].split(
            "var pre_sync_upper_temp_c", 1
        )[0]
        self.assertIn("room.hrr_kw * conv_fraction * dt", block)
        self.assertIn('"sensible_enthalpy_kj": convective_energy_kj', block)
        self.assertIn("room.upper_energy_kj += convective_energy_kj", block)
        self.assertEqual(block.count("room.hrr_kw * conv_fraction * dt"), 1)

    def test_result_is_recorded_before_legacy_mutation(self):
        block = THERMAL.split("var convective_energy_kj", 1)[1].split(
            "var pre_sync_upper_temp_c", 1
        )[0]
        self.assertLess(
            block.index("_phase3_shadow_flux_results.append"),
            block.index("room.upper_energy_kj += convective_energy_kj"),
        )

    def test_contract_is_shadow_gated_and_sealed(self):
        self.assertIn(
            "if phase3_canonical_zone_shadow_enabled and _phase3_shadow_sealed_room_scope(room):",
            THERMAL,
        )

    def test_contract_owns_energy_only(self):
        block = THERMAL.split('"cause": "combustion_convective_heat"', 1)[1].split(
            "})", 1
        )[0]
        self.assertIn('"source_room_id": -1', block)
        self.assertIn('"destination_room_id": room.id', block)
        self.assertIn('"gas_mass_kg": 0.0', block)
        self.assertIn('"o2_kg": 0.0', block)
        self.assertIn('"species_kg": {}', block)

    def test_engine_accepts_zero_mass_energy_without_recalculation(self):
        collector = ENGINE.split("func _phase3_shadow_collect_thermal_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        self.assertIn("energy_kj <= 0.0", collector)
        self.assertIn('flux.get("source_room_id", room_id)', collector)
        self.assertNotIn("hrr_kw", collector)
        self.assertNotIn("conv_fraction", collector)

    def test_shadow_reports_energy_owner_and_mask(self):
        self.assertIn("phase3_shadow_combustion_energy_request_kj", SYSTEM)
        self.assertIn("phase3_shadow_combustion_owned_mask", SYSTEM)
        self.assertIn('room_id, "combustion_convective_heat"', SYSTEM)
        self.assertIn("energy=1, O2=2, species=4", SYSTEM)

    def test_csv_fields_remain_shadow_only(self):
        for field in (
            "phase3_shadow_combustion_energy_request_kj",
            "phase3_shadow_combustion_owned_mask",
        ):
            self.assertEqual(LOG.count(field), 2)

    def test_no_observed_stage_delta_feeds_contract(self):
        collector = ENGINE.split("func _phase3_shadow_collect_thermal_requests", 1)[1].split(
            "func _build_state_context", 1
        )[0]
        self.assertNotIn("_phase3_zone_diag_step", collector)
        self.assertNotIn("projection_clamp", collector)


if __name__ == "__main__":
    unittest.main()
