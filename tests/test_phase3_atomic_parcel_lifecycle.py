"""Structural checks for F3.0k.1e delayed-parcel atomic lifecycle."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_parcel_atomic_inflight_gas_kg",
    "phase3_shadow_parcel_atomic_inflight_energy_kj",
    "phase3_shadow_parcel_atomic_inflight_o2_kg",
    "phase3_shadow_parcel_atomic_inflight_species_kg",
    "phase3_shadow_parcel_atomic_created_gas_kg_total",
    "phase3_shadow_parcel_atomic_delivered_gas_kg_total",
    "phase3_shadow_parcel_atomic_refunded_gas_kg_total",
    "phase3_shadow_parcel_atomic_cancelled_gas_kg_total",
    "phase3_shadow_parcel_atomic_created_energy_kj_total",
    "phase3_shadow_parcel_atomic_delivered_energy_kj_total",
    "phase3_shadow_parcel_atomic_cancelled_energy_kj_total",
    "phase3_shadow_parcel_atomic_created_o2_kg_total",
    "phase3_shadow_parcel_atomic_delivered_o2_kg_total",
    "phase3_shadow_parcel_atomic_cancelled_o2_kg_total",
    "phase3_shadow_parcel_atomic_mass_residual_kg",
    "phase3_shadow_parcel_atomic_energy_residual_kj",
    "phase3_shadow_parcel_atomic_o2_residual_kg",
    "phase3_shadow_parcel_atomic_species_residual_kg",
    "phase3_shadow_parcel_atomic_unfinalized_resolution_count",
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestAtomicParcelProducer(unittest.TestCase):
    def test_created_event_captures_complete_queued_payload(self):
        created = _function(GAS, "_record_phase3_shadow_parcel_created")
        for field in (
            "parcel_id",
            "source_room_id",
            "destination_room_id",
            "connection_id",
            "gas_mass_kg",
            "sensible_enthalpy_kj",
            "o2_kg",
            "species_kg",
            "upper_species_kg",
        ):
            self.assertIn(f'"{field}"', created)

    def test_all_legacy_parcel_species_are_present(self):
        species = _function(GAS, "_phase3_shadow_parcel_species")
        for name in (
            "smoke", "co", "co2", "hcn", "hcl", "acrolein", "formaldehyde"
        ):
            self.assertIn(f'"{name}"', species)

    def test_delivery_reports_actual_post_headroom_split(self):
        release = _function(GAS, "_release_pending_interior_deliveries")
        for local in (
            "delivered_smoke_kg",
            "co_parcel_kg",
            "co2_parcel_kg",
            "hcn_parcel_kg",
            "hcl_parcel_kg",
            "acrolein_parcel_kg",
            "formaldehyde_parcel_kg",
        ):
            self.assertIn(local, release)
        self.assertIn("refunded_shadow_species_kg", release)
        self.assertIn("_record_phase3_shadow_parcel_resolved(", release)


class TestAtomicParcelLifecycle(unittest.TestCase):
    def test_reservoir_persists_payload_and_fraction(self):
        apply_event = _function(SYSTEM, "apply_species_transit_event")
        for field in (
            "gas_mass_kg",
            "sensible_enthalpy_kj",
            "o2_kg",
            "species_kg",
            "upper_species_kg",
            "accepted_fraction",
        ):
            self.assertIn(f'"{field}"', apply_event)
        begin = _function(SYSTEM, "begin_step")
        self.assertNotIn("_species_transit_reservoir.clear()", begin)

    def test_carve_uses_one_bundle_for_all_routes(self):
        carve = _function(SYSTEM, "_add_parcel_carve_bundle")
        self.assertIn("make_atomic_bundle(", carve)
        self.assertIn("add_atomic_bundle(", carve)
        self.assertIn('"kind": "delayed_parcel_carve"', carve)
        self.assertIn("gas_mass_kg", carve)
        self.assertIn("sensible_enthalpy_kj", carve)
        self.assertIn("upper_species", carve)

    def test_negative_o2_becomes_positive_reverse_route(self):
        carve = _function(SYSTEM, "_add_parcel_carve_bundle")
        self.assertIn("if signed_o2_kg < 0.0:", carve)
        self.assertIn("-signed_o2_kg", carve)
        self.assertIn("destination_room_id", carve)

    def test_accepted_fraction_is_written_after_carve_finalization(self):
        result = _function(SYSTEM, "_record_atomic_bundle_result")
        self.assertIn('result_kind == "delayed_parcel_carve"', result)
        self.assertIn('stored["accepted_fraction"]', result)
        self.assertIn("_parcel_atomic_created_payload", result)

    def test_resolution_requires_finalized_fraction_and_erases_identity(self):
        apply_event = _function(SYSTEM, "apply_species_transit_event")
        resolved = apply_event.split('"resolved":', 1)[1].split('"cancelled":', 1)[0]
        self.assertIn("accepted_fraction < 0.0", resolved)
        self.assertIn("_parcel_atomic_unfinalized_resolution_count += 1", resolved)
        self.assertEqual(resolved.count("_species_transit_reservoir.erase(parcel_id)"), 2)

    def test_delivery_and_refund_share_stored_fraction(self):
        resolution = _function(SYSTEM, "_add_parcel_resolution_bundle")
        self.assertIn('stored.get("accepted_fraction"', resolution)
        self.assertIn('parcel_id + ":delivery"', resolution)
        self.assertIn('parcel_id + ":refund"', resolution)
        self.assertIn("_scaled_parcel_species", resolution)

    def test_cancellation_is_an_explicit_terminal_sink(self):
        resolution = _function(SYSTEM, "_add_parcel_resolution_bundle")
        cancelled = resolution.split("if cancelled:", 1)[1].split("else:", 1)[0]
        self.assertIn("_parcel_atomic_cancelled_payload", cancelled)
        self.assertIn("_scaled_parcel_payload", cancelled)
        self.assertIn("return", cancelled)
        self.assertNotIn("_append_parcel_resolution_routes", cancelled)

    def test_semantic_owner_is_claimed_only_at_creation(self):
        apply_event = _function(SYSTEM, "apply_species_transit_event")
        created = apply_event.split('"created":', 1)[1].split('"resolved":', 1)[0]
        resolved = apply_event.split('"resolved":', 1)[1].split('"cancelled":', 1)[0]
        self.assertIn("_register_parcel_quantity_claims", created)
        self.assertIn("_register_split_parcel_species_claims", created)
        self.assertNotIn("_register_parcel_quantity_claims", resolved)
        self.assertNotIn("_register_split_parcel_species_claims", resolved)

    def test_lifecycle_residual_includes_inflight_and_all_terminal_states(self):
        residual = _function(SYSTEM, "_parcel_atomic_payload_residual")
        for token in (
            "_parcel_atomic_created_payload",
            "_parcel_atomic_delivered_payload",
            "_parcel_atomic_refunded_payload",
            "_parcel_atomic_cancelled_payload",
            "_inflight_atomic_parcel_payload",
        ):
            self.assertIn(token, residual)

    def test_csv_telemetry_is_shadow_gated_and_unique(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2, field)


if __name__ == "__main__":
    unittest.main()
