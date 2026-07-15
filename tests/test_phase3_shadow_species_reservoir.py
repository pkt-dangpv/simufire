"""Structural checks for the F3.0f persistent delayed-species reservoir."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
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
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestPhase3ShadowSpeciesReservoir(unittest.TestCase):
    def test_reservoir_is_persistent_state_not_step_state(self):
        self.assertIn("var _species_transit_reservoir: Dictionary = {}", SYSTEM)
        begin = _function(SYSTEM, "begin_step")
        self.assertIn("_reset_step_state()", begin)
        self.assertNotIn("_species_transit_reservoir.clear()", begin)

    def test_full_reset_clears_reservoir_and_counters(self):
        reset = _function(SYSTEM, "reset")
        self.assertIn("_species_transit_reservoir.clear()", reset)
        self.assertIn("_species_transit_created_kg.clear()", reset)
        self.assertIn("_species_transit_orphan_delivery_count = 0", reset)
        self.assertEqual(ENGINE.count("phase3_zone_mass_system.reset()"), 2)

    def test_identity_is_monotonic_and_shadow_only(self):
        assign = _function(GAS, "_phase3_shadow_assign_parcel_identity")
        self.assertIn("if not phase3_canonical_zone_shadow_enabled:", assign)
        self.assertIn('entry["phase3_shadow_parcel_id"]', assign)
        self.assertIn("_phase3_shadow_parcel_sequence += 1", assign)

    def test_created_event_uses_the_exact_queued_entry(self):
        step = _function(GAS, "step_smoke")
        self.assertLess(
            step.index("_record_phase3_shadow_parcel_created(pending_entry)"),
            step.index("_pending_interior_deliveries.append(pending_entry)"),
        )
        self.assertIn("_phase3_shadow_assign_parcel_identity(pending_entry)", step)

    def test_created_event_has_route_and_owned_species(self):
        created = _function(GAS, "_record_phase3_shadow_parcel_created")
        for field in (
            "parcel_id", "source_room_id", "destination_room_id",
            "source_zone", "destination_zone", "species_kg",
        ):
            self.assertIn(f'"{field}"', created)
        species = _function(GAS, "_phase3_shadow_parcel_species")
        upper_species = _function(GAS, "_phase3_shadow_parcel_upper_species")
        for name in ("co", "co2", "hcn"):
            self.assertIn(f'"{name}"', species)
            self.assertIn(f'"{name}"', upper_species)

    def test_smoke_and_irritants_remain_outside_f30f_contract(self):
        species = _function(GAS, "_phase3_shadow_parcel_species")
        for excluded in ("smoke", "hcl", "acrolein", "formaldehyde", "o2"):
            self.assertNotIn(f'"{excluded}"', species)

    def test_release_records_delivered_and_refunded_local_values(self):
        release = _function(GAS, "_release_pending_interior_deliveries")
        self.assertIn('"co": maxf(0.0, co_parcel_kg)', release)
        self.assertIn('"co2": maxf(0.0, co2_parcel_kg)', release)
        self.assertIn('"hcn": maxf(0.0, hcn_parcel_kg)', release)
        self.assertIn("original_shadow_species_kg", release)
        self.assertIn("refunded_shadow_species_kg", release)
        self.assertIn("_record_phase3_shadow_parcel_resolved(", release)

    def test_missing_target_is_an_explicit_cancellation(self):
        release = _function(GAS, "_release_pending_interior_deliveries")
        target_guard = release.split("if target == null:", 1)[1].split("continue", 1)[0]
        self.assertIn("_record_phase3_shadow_parcel_cancelled(entry)", target_guard)

    def test_events_are_drained_once_per_gas_step(self):
        begin = _function(GAS, "begin_phase3_shadow_step")
        drain = _function(GAS, "drain_phase3_shadow_parcel_events")
        self.assertIn("_phase3_shadow_parcel_events.clear()", begin)
        self.assertIn("duplicate(true)", drain)
        self.assertIn("_phase3_shadow_parcel_events.clear()", drain)

    def test_engine_only_forwards_events(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_parcel_species_events")
        self.assertIn("gas_exchange_system.drain_phase3_shadow_parcel_events()", collector)
        self.assertIn("phase3_zone_mass_system.apply_species_transit_event(event)", collector)
        for forbidden in ("headroom", "cut_ratio", "co_kg", "co2_kg", "hcn_kg"):
            self.assertNotIn(forbidden, collector)

    def test_resolved_event_removes_the_same_identity(self):
        apply_event = _function(SYSTEM, "apply_species_transit_event")
        self.assertIn('"created":', apply_event)
        self.assertIn('"resolved":', apply_event)
        self.assertIn('"cancelled":', apply_event)
        self.assertIn("_species_transit_reservoir.erase(parcel_id)", apply_event)

    def test_events_create_separate_upper_and_lower_shadow_requests(self):
        apply_event = _function(SYSTEM, "apply_species_transit_event")
        self.assertIn('"delayed_species_parcel_carve"', apply_event)
        self.assertIn('"delayed_species_parcel_delivery"', apply_event)
        self.assertIn('"delayed_species_parcel_refund"', apply_event)
        splitter = _function(SYSTEM, "_add_transit_zone_requests")
        self.assertIn("ZONE_UPPER", splitter)
        self.assertIn("ZONE_LOWER", splitter)
        self.assertIn("_lower_transit_species", splitter)

    def test_anomalies_are_visible(self):
        apply_event = _function(SYSTEM, "apply_species_transit_event")
        self.assertIn("_species_transit_duplicate_id_count += 1", apply_event)
        self.assertIn("_species_transit_orphan_delivery_count += 1", apply_event)
        self.assertIn("_species_transit_negative_balance_count += 1", apply_event)

    def test_conservation_includes_all_terminal_states(self):
        residual = _function(SYSTEM, "_species_transit_conservation_residual_kg")
        self.assertIn("_species_transit_created_kg", residual)
        self.assertIn("_species_transit_delivered_kg", residual)
        self.assertIn("_species_transit_refunded_kg", residual)
        self.assertIn("_species_transit_cancelled_kg", residual)
        self.assertIn("_inflight_transit_species()", residual)

    def test_conservation_is_also_reported_per_species(self):
        residual = _function(SYSTEM, "_species_transit_conservation_residual_for")
        self.assertIn("_species_transit_created_kg", residual)
        self.assertIn("_species_transit_delivered_kg", residual)
        self.assertIn("_species_transit_refunded_kg", residual)
        self.assertIn("_species_transit_cancelled_kg", residual)
        for species in ("co", "co2", "hcn"):
            self.assertIn(
                f'"phase3_shadow_species_conservation_residual_{species}_kg"', SYSTEM
            )

    def test_transit_events_do_not_become_same_step_room_requests(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_parcel_species_events")
        self.assertNotIn("make_request", collector)
        self.assertNotIn("add_request", collector)

    def test_csv_telemetry_is_shadow_gated(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2)


if __name__ == "__main__":
    unittest.main()
