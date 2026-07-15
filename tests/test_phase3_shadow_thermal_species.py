"""Structural checks for F3.0j ThermalSystem species shadow ownership."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_thermal_co_kg_total",
    "phase3_shadow_thermal_co2_kg_total",
    "phase3_shadow_thermal_hcn_kg_total",
    "phase3_shadow_thermal_source_upper_co_kg_total",
    "phase3_shadow_thermal_source_upper_co2_kg_total",
    "phase3_shadow_thermal_source_upper_hcn_kg_total",
    "phase3_shadow_thermal_source_lower_co_kg_total",
    "phase3_shadow_thermal_source_lower_co2_kg_total",
    "phase3_shadow_thermal_source_lower_hcn_kg_total",
    "phase3_shadow_thermal_destination_upper_co_kg_total",
    "phase3_shadow_thermal_destination_upper_co2_kg_total",
    "phase3_shadow_thermal_destination_upper_hcn_kg_total",
    "phase3_shadow_thermal_destination_lower_co_kg_total",
    "phase3_shadow_thermal_destination_lower_co2_kg_total",
    "phase3_shadow_thermal_destination_lower_hcn_kg_total",
    "phase3_shadow_thermal_applied_co_kg_total",
    "phase3_shadow_thermal_applied_co2_kg_total",
    "phase3_shadow_thermal_applied_hcn_kg_total",
    "phase3_shadow_thermal_rejected_co_kg_total",
    "phase3_shadow_thermal_rejected_co2_kg_total",
    "phase3_shadow_thermal_rejected_hcn_kg_total",
    "phase3_shadow_thermal_event_count",
    "phase3_shadow_thermal_duplicate_event_count",
    "phase3_shadow_thermal_co_residual_kg",
    "phase3_shadow_thermal_co2_residual_kg",
    "phase3_shadow_thermal_hcn_residual_kg",
    "phase3_shadow_thermal_doorway_kg_total",
    "phase3_shadow_thermal_outside_background_kg_total",
    "phase3_shadow_thermal_interior_background_kg_total",
    "phase3_shadow_thermal_interlayer_kg_total",
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestPhase3ShadowThermalSpecies(unittest.TestCase):
    def test_recorder_is_shadow_only_and_filters_owned_species(self):
        recorder = _function(THERMAL, "_record_phase3_shadow_thermal_species_event")
        self.assertIn("if not phase3_canonical_zone_shadow_enabled", recorder)
        self.assertIn('["co", "co2", "hcn"]', recorder)
        for forbidden in ("smoke", "hcl", "acrolein", "formaldehyde", "hvac"):
            self.assertNotIn(forbidden, recorder.lower())
        for mutation in (".co_kg =", ".co2_kg =", ".hcn_kg ="):
            self.assertNotIn(mutation, recorder)

    def test_event_contract_preserves_both_zonal_margins(self):
        recorder = _function(THERMAL, "_record_phase3_shadow_thermal_species_event")
        for field in (
            "event_id", "mechanism", "source_room_id", "destination_room_id",
            "species_kg", "source_upper_species_kg", "destination_upper_species_kg",
        ):
            self.assertIn(f'"{field}"', recorder)

    def test_queue_is_cleared_and_drained_once(self):
        step = _function(THERMAL, "step")
        drain = _function(THERMAL, "drain_phase3_shadow_thermal_species_events")
        self.assertIn("_phase3_shadow_thermal_species_events.clear()", step)
        self.assertIn("duplicate(true)", drain)
        self.assertIn("_phase3_shadow_thermal_species_events.clear()", drain)

    def test_hot_gas_events_precede_associated_delta_writes(self):
        transfer = _function(THERMAL, "_transfer_hot_gas_contaminants")
        self.assertLess(
            transfer.index('mechanism, source, target, "co",'),
            transfer.index("_delta_co_kg[src_id]"),
        )
        self.assertLess(
            transfer.index('mechanism, source, target, "co2",'),
            transfer.index("_delta_co2_kg[src_id]"),
        )
        self.assertLess(
            transfer.index('mechanism, source, target, "hcn",'),
            transfer.index("_delta_hcn_kg[src_id]"),
        )

    def test_all_thermal_transport_mechanisms_are_explicit(self):
        for mechanism in (
            "doorway_hot_gas",
            "outside_assisted_background_heat",
            "interior_background_heat",
            "co_interlayer_mixing",
        ):
            self.assertIn(f'"{mechanism}"', THERMAL)

    def test_interlayer_mixing_records_before_mutation(self):
        mixing = _function(THERMAL, "_apply_phase2f_co_interlayer_mixing")
        self.assertLess(
            mixing.index("_record_phase3_shadow_thermal_species_event"),
            mixing.index("room.co_upper_kg ="),
        )

    def test_projection_and_purge_are_not_claimed(self):
        for function_name in (
            "sync_room_upper_layer",
            "_sync_room_two_zone_layer",
            "reset_thermal_layer",
            "remove_upper_layer_fraction",
        ):
            body = _function(THERMAL, function_name)
            self.assertNotIn("_record_phase3_shadow_thermal_species_event", body)

    def test_engine_only_forwards_thermal_events(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_thermal_species_events")
        self.assertIn("drain_phase3_shadow_thermal_species_events()", collector)
        self.assertIn("apply_thermal_species_event(event)", collector)
        for forbidden in ("co_kg", "co2_kg", "hcn_kg", "carry_intensity"):
            self.assertNotIn(forbidden, collector)

    def test_engine_drains_events_after_thermal_step_once(self):
        step = _function(ENGINE, "step")
        self.assertEqual(step.count("_phase3_shadow_collect_thermal_species_events()"), 1)
        self.assertLess(
            step.index("thermal_system.step(building, dt"),
            step.index("_phase3_shadow_collect_thermal_species_events()"),
        )

    def test_ledger_uses_conservative_two_by_two_routes(self):
        apply_event = _function(SYSTEM, "apply_thermal_species_event")
        routes = _function(SYSTEM, "_add_thermal_species_route_requests")
        self.assertIn("_add_thermal_species_route_requests", apply_event)
        for route in ("upper_upper", "upper_lower", "lower_upper", "lower_lower"):
            self.assertIn(f'"{route}"', routes)
        self.assertIn("source_upper_kg - upper_upper_kg", routes)
        self.assertIn("destination_upper_kg - upper_upper_kg", routes)

    def test_duplicate_identity_is_visible(self):
        apply_event = _function(SYSTEM, "apply_thermal_species_event")
        self.assertIn("_thermal_species_event_ids.has(event_id)", apply_event)
        self.assertIn("_thermal_species_duplicate_event_count += 1", apply_event)
        self.assertIn("_duplicate_owner_count += 1", apply_event)

    def test_requested_applied_rejected_conservation_is_explicit(self):
        apply_request = _function(SYSTEM, "_apply_request")
        residual = _function(SYSTEM, "_thermal_species_residual_for")
        self.assertIn("_is_thermal_species_cause(request_cause)", apply_request)
        self.assertIn("_thermal_species_applied_kg", apply_request)
        self.assertIn("_thermal_species_rejected_kg", apply_request)
        for ledger in (
            "_thermal_species_requested_kg",
            "_thermal_species_applied_kg",
            "_thermal_species_rejected_kg",
        ):
            self.assertIn(ledger, residual)

    def test_reset_clears_cumulative_and_step_state(self):
        reset = _function(SYSTEM, "reset")
        step_reset = _function(SYSTEM, "_reset_step_state")
        for name in (
            "_thermal_species_requested_kg",
            "_thermal_species_applied_kg",
            "_thermal_species_rejected_kg",
            "_thermal_species_mechanism_kg",
        ):
            self.assertIn(f"{name}.clear()", reset)
        self.assertIn("_thermal_species_event_ids.clear()", step_reset)

    def test_csv_fields_are_shadow_gated_and_unique(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2, field)


if __name__ == "__main__":
    unittest.main()
