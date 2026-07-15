"""Structural checks for the F3.0 canonical two-zone shadow transaction."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
RUN_SCRIPT = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_upper_gas_kg",
    "phase3_shadow_lower_gas_kg",
    "phase3_shadow_upper_energy_kj",
    "phase3_shadow_lower_energy_kj",
    "phase3_shadow_mass_residual_kg",
    "phase3_shadow_energy_residual_kj",
    "phase3_shadow_upper_mass_residual_kg",
    "phase3_shadow_lower_mass_residual_kg",
    "phase3_shadow_upper_energy_residual_kj",
    "phase3_shadow_lower_energy_residual_kj",
    "phase3_shadow_request_count",
    "phase3_shadow_plume_mass_request_kg",
    "phase3_shadow_combustion_energy_request_kj",
    "phase3_shadow_combustion_o2_request_kg",
    "phase3_shadow_combustion_o2_rejected_kg",
    "phase3_shadow_combustion_co_request_kg",
    "phase3_shadow_combustion_co2_request_kg",
    "phase3_shadow_combustion_hcn_request_kg",
    "phase3_shadow_combustion_species_rejected_kg",
    "phase3_shadow_doorway_co_request_kg",
    "phase3_shadow_doorway_co2_request_kg",
    "phase3_shadow_doorway_hcn_request_kg",
    "phase3_shadow_doorway_species_rejected_kg",
    "phase3_shadow_background_co_kg_total",
    "phase3_shadow_background_co2_kg_total",
    "phase3_shadow_background_hcn_kg_total",
    "phase3_shadow_counterflow_co_kg_total",
    "phase3_shadow_counterflow_co2_kg_total",
    "phase3_shadow_counterflow_hcn_kg_total",
    "phase3_shadow_immediate_transfer_count",
    "phase3_shadow_immediate_rejected_kg_total",
    "phase3_shadow_immediate_co_residual_kg",
    "phase3_shadow_immediate_co2_residual_kg",
    "phase3_shadow_immediate_hcn_residual_kg",
    "phase3_shadow_vertical_net_co_kg_total",
    "phase3_shadow_vertical_net_co2_kg_total",
    "phase3_shadow_vertical_net_hcn_kg_total",
    "phase3_shadow_vertical_directed_co_kg_total",
    "phase3_shadow_vertical_directed_co2_kg_total",
    "phase3_shadow_vertical_directed_hcn_kg_total",
    "phase3_shadow_vertical_transfer_count",
    "phase3_shadow_vertical_rejected_kg_total",
    "phase3_shadow_vertical_opposed_zone_direction_count",
    "phase3_shadow_vertical_co_residual_kg",
    "phase3_shadow_vertical_co2_residual_kg",
    "phase3_shadow_vertical_hcn_residual_kg",
    "phase3_shadow_species_inflight_co_kg",
    "phase3_shadow_species_inflight_co2_kg",
    "phase3_shadow_species_inflight_hcn_kg",
    "phase3_shadow_species_created_kg_total",
    "phase3_shadow_species_delivered_kg_total",
    "phase3_shadow_species_refunded_kg_total",
    "phase3_shadow_species_cancelled_kg_total",
    "phase3_shadow_species_active_parcel_count",
    "phase3_shadow_species_orphan_delivery_count",
    "phase3_shadow_species_duplicate_id_count",
    "phase3_shadow_species_negative_balance_count",
    "phase3_shadow_species_conservation_residual_kg",
    "phase3_shadow_species_conservation_residual_co_kg",
    "phase3_shadow_species_conservation_residual_co2_kg",
    "phase3_shadow_species_conservation_residual_hcn_kg",
    "phase3_shadow_species_transit_rejected_kg",
    "phase3_shadow_combustion_owned_mask",
    "phase3_shadow_owned_cause_count",
    "phase3_shadow_rejected_mass_kg",
    "phase3_shadow_duplicate_owner_flag",
    "phase3_shadow_zero_o2_flame_flag",
    "phase3_shadow_needs_flux_owner_flag",
)


class TestPhase3CanonicalShadow(unittest.TestCase):
    def test_flag_is_default_off(self):
        self.assertIn(
            "@export var phase3_canonical_zone_shadow_enabled: bool = false", ENGINE
        )

    def test_component_is_owned_by_engine(self):
        self.assertIn('preload("res://sim/core/Phase3ZoneMassSystem.gd")', ENGINE)
        self.assertIn("phase3_zone_mass_system.begin_step(building)", ENGINE)
        self.assertIn("phase3_zone_mass_system.finalize_step(building)", ENGINE)

    def test_headless_runner_has_explicit_opt_in(self):
        self.assertIn("--phase3-canonical-shadow", RUNNER)
        self.assertIn("engine.phase3_canonical_zone_shadow_enabled = true", RUNNER)
        self.assertIn('"--phase3-canonical-shadow"', RUN_SCRIPT)

    def test_shadow_never_mutates_room(self):
        self.assertNotIn("room.upper_gas_kg =", SYSTEM)
        self.assertNotIn("room.lower_gas_kg =", SYSTEM)
        self.assertNotIn("room.upper_energy_kj =", SYSTEM)
        self.assertNotIn("room.lower_energy_kj =", SYSTEM)

    def test_request_contract_has_identity_and_cause(self):
        for field in (
            "request_id", "cause", "source_room_id", "destination_room_id",
            "source_zone", "destination_zone", "gas_mass_kg",
            "sensible_enthalpy_kj", "o2_kg", "species_kg",
        ):
            self.assertIn(f'"{field}"', SYSTEM)

    def test_duplicate_and_rejected_requests_are_visible(self):
        self.assertIn("_duplicate_owner_count += 1", SYSTEM)
        self.assertIn("accepted_fraction", SYSTEM)
        self.assertIn("rejected_by_room", SYSTEM)

    def test_transaction_moves_o2_and_species_with_the_same_fraction(self):
        self.assertIn('source[source_zone + "_o2_kg"]', SYSTEM)
        self.assertIn('destination[destination_zone + "_o2_kg"]', SYSTEM)
        self.assertIn('source[source_zone + "_species_kg"]', SYSTEM)
        self.assertIn('destination[destination_zone + "_species_kg"]', SYSTEM)
        self.assertIn("* accepted_fraction", SYSTEM)

    def test_no_post_mutation_stage_delta_feeds_requests(self):
        self.assertNotIn("_phase3_zone_diag_step", SYSTEM)
        self.assertNotIn("boundary_mass_kg_step", SYSTEM)
        self.assertNotIn("projection_clamp", SYSTEM)

    def test_csv_columns_are_shadow_gated(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2)

    def test_state_builder_exports_shadow_separately(self):
        self.assertIn("phase3_canonical_zone_shadow_enabled", STATE)
        self.assertIn("phase3_canonical_zone_shadow", STATE)
        self.assertIn("for shadow_key in shadow_diag.keys()", STATE)

    def test_empty_ledger_exposes_missing_owner(self):
        self.assertIn("phase3_shadow_needs_flux_owner_flag", SYSTEM)
        self.assertIn("absf(mass_residual_kg)", SYSTEM)
        self.assertIn("absf(energy_residual_kj)", SYSTEM)

    def test_zero_o2_flame_is_visible(self):
        self.assertIn("phase3_shadow_zero_o2_flame_flag", SYSTEM)
        self.assertIn("room.fire_o2_ref < room.fire_o2_min_ref", SYSTEM)
        self.assertIn("room.o2_upper < 0.05", SYSTEM)


if __name__ == "__main__":
    unittest.main()
