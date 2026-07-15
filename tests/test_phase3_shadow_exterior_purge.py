"""Structural checks for F3.0i exterior species purge shadow ownership."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_purge_co_out_kg_total",
    "phase3_shadow_purge_co2_out_kg_total",
    "phase3_shadow_purge_hcn_out_kg_total",
    "phase3_shadow_purge_upper_co_kg_total",
    "phase3_shadow_purge_upper_co2_kg_total",
    "phase3_shadow_purge_upper_hcn_kg_total",
    "phase3_shadow_purge_lower_co_kg_total",
    "phase3_shadow_purge_lower_co2_kg_total",
    "phase3_shadow_purge_lower_hcn_kg_total",
    "phase3_shadow_purge_applied_kg_total",
    "phase3_shadow_purge_rejected_kg_total",
    "phase3_shadow_purge_event_count",
    "phase3_shadow_purge_duplicate_event_count",
    "phase3_shadow_purge_co_residual_kg",
    "phase3_shadow_purge_co2_residual_kg",
    "phase3_shadow_purge_hcn_residual_kg",
    "phase3_shadow_purge_pressure_kg_total",
    "phase3_shadow_purge_smoke_vent_kg_total",
    "phase3_shadow_purge_natural_vent_kg_total",
    "phase3_shadow_purge_ach_kg_total",
    "phase3_shadow_purge_outside_open_kg_total",
    "phase3_shadow_purge_postfire_kg_total",
    "phase3_shadow_purge_ppv_inlet_kg_total",
    "phase3_shadow_purge_ppv_exhaust_kg_total",
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestPhase3ShadowExteriorPurge(unittest.TestCase):
    def test_recorder_is_shadow_only_and_filters_owned_species(self):
        recorder = _function(GAS, "_record_phase3_shadow_exterior_purge_event")
        self.assertIn("if not phase3_canonical_zone_shadow_enabled", recorder)
        self.assertIn('["co", "co2", "hcn"]', recorder)
        for mutation in (".co_kg =", ".co2_kg =", ".hcn_kg ="):
            self.assertNotIn(mutation, recorder)

    def test_event_contract_has_identity_mechanism_route_and_split(self):
        recorder = _function(GAS, "_record_phase3_shadow_exterior_purge_event")
        for field in (
            "event_id", "mechanism", "source_room_id",
            "species_kg", "upper_species_kg",
        ):
            self.assertIn(f'"{field}"', recorder)

    def test_event_queue_is_cleared_and_drained_once(self):
        begin = _function(GAS, "begin_phase3_shadow_step")
        drain = _function(GAS, "drain_phase3_shadow_exterior_purge_events")
        self.assertIn("_phase3_shadow_exterior_purge_events.clear()", begin)
        self.assertIn("duplicate(true)", drain)
        self.assertIn("_phase3_shadow_exterior_purge_events.clear()", drain)

    def test_pressure_legacy_event_precedes_species_mutation(self):
        step = _function(GAS, "step_pressure_venting")
        marker = '"pressure_venting", room,'
        self.assertLess(step.index(marker), step.index("room.co_kg = maxf"))

    def test_pressure_two_zone_helper_records_before_mutation(self):
        purge = _function(GAS, "_purge_upper_species_to_exterior_direct")
        self.assertLess(
            purge.index("_record_phase3_shadow_exterior_purge_event"),
            purge.index("room.co_upper_kg ="),
        )

    def test_queued_upper_purge_records_before_delta_writes(self):
        purge = _function(GAS, "_queue_upper_species_to_exterior")
        self.assertLess(
            purge.index("_record_phase3_shadow_exterior_purge_event"),
            purge.index("_add_delta(co_delta_kg"),
        )
        for species in ("co", "co2", "hcn"):
            self.assertIn(f'"{species}": {species}_removed_kg', purge)

    def test_all_gas_exchange_purge_mechanisms_are_explicit(self):
        for mechanism in (
            "pressure_venting",
            "exterior_smoke_vent",
            "natural_ventilation",
            "ach_infiltration",
            "outside_open_species_purge",
            "postfire_species_purge",
            "ppv_inlet_dilution",
            "ppv_exhaust",
        ):
            self.assertIn(f'"{mechanism}"', GAS)

    def test_ach_split_is_computed_before_direct_mutation(self):
        step = _function(GAS, "step_smoke")
        marker = '"ach_infiltration", room,'
        self.assertLess(step.index(marker), step.index("room.co_exterior_removed_kg_total += co_removed"))
        self.assertIn("room.co2_upper_kg * clampf(co2_remove_fraction", step)
        self.assertIn("room.hcn_upper_kg * clampf(hcn_remove_fraction", step)

    def test_outside_open_records_explicit_upper_and_lower_co(self):
        step = _function(GAS, "step_smoke")
        self.assertIn('"co": co_upper_removed_kg + co_lower_removed_kg', step)
        self.assertIn('"co": co_upper_removed_kg,', step)
        self.assertLess(
            step.index('"outside_open_species_purge", room,'),
            step.index("room.co_upper_kg = maxf(0.0, co_upper_kg - co_upper_removed_kg)"),
        )

    def test_ppv_mirrors_legacy_upper_semantics(self):
        ppv = _function(GAS, "step_ppv")
        self.assertIn(
            '{"co": inlet_room.co_upper_kg * mix_frac, "co2": 0.0, "hcn": 0.0}',
            ppv,
        )
        self.assertIn(
            '{"co": inlet_room.co_upper_kg * ex_frac, "co2": 0.0, "hcn": 0.0}',
            ppv,
        )

    def test_hvac_is_not_owned_by_gas_exchange_purge_contract(self):
        recorder = _function(GAS, "_record_phase3_shadow_exterior_purge_event")
        self.assertNotIn("hvac", recorder.lower())

    def test_engine_only_forwards_purge_events(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_exterior_purge_events")
        self.assertIn("drain_phase3_shadow_exterior_purge_events()", collector)
        self.assertIn("apply_exterior_purge_event(event)", collector)
        for forbidden in ("co_kg", "co2_kg", "hcn_kg", "purge_rate"):
            self.assertNotIn(forbidden, collector)

    def test_engine_drains_purge_after_gas_step_once(self):
        step = _function(ENGINE, "step")
        self.assertEqual(step.count("_phase3_shadow_collect_exterior_purge_events()"), 1)
        self.assertLess(
            step.index("_step_gas_exchange(dt)"),
            step.index("_phase3_shadow_collect_exterior_purge_events()"),
        )

    def test_ledger_routes_purge_to_exterior(self):
        apply_event = _function(SYSTEM, "apply_exterior_purge_event")
        self.assertIn("EXTERIOR_ID", apply_event)
        self.assertIn('"exterior_species_purge:" + mechanism', apply_event)
        self.assertIn("_add_transit_zone_requests", apply_event)

    def test_duplicate_event_identity_is_visible(self):
        apply_event = _function(SYSTEM, "apply_exterior_purge_event")
        self.assertIn("_exterior_purge_event_ids.has(event_id)", apply_event)
        self.assertIn("_exterior_purge_duplicate_event_count += 1", apply_event)

    def test_requested_applied_rejected_conservation_is_explicit(self):
        apply_request = _function(SYSTEM, "_apply_request")
        self.assertIn("_is_exterior_purge_cause(request_cause)", apply_request)
        self.assertIn("_exterior_purge_applied_species_kg", apply_request)
        self.assertIn("_exterior_purge_rejected_species_kg", apply_request)
        residual = _function(SYSTEM, "_exterior_purge_residual_for")
        self.assertIn("_exterior_purge_requested_species_kg", residual)
        self.assertIn("_exterior_purge_applied_species_kg", residual)
        self.assertIn("_exterior_purge_rejected_species_kg", residual)

    def test_reset_clears_cumulative_and_step_purge_state(self):
        reset = _function(SYSTEM, "reset")
        step_reset = _function(SYSTEM, "_reset_step_state")
        for name in (
            "_exterior_purge_requested_species_kg",
            "_exterior_purge_applied_species_kg",
            "_exterior_purge_rejected_species_kg",
            "_exterior_purge_mechanism_species_kg",
        ):
            self.assertIn(f"{name}.clear()", reset)
        self.assertIn("_exterior_purge_event_ids.clear()", step_reset)

    def test_csv_fields_are_shadow_gated_and_unique(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2)


if __name__ == "__main__":
    unittest.main()
