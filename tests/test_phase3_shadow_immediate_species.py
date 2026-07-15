"""Structural checks for F3.0g immediate background/counterflow ownership."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
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
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestPhase3ShadowImmediateSpecies(unittest.TestCase):
    def test_events_are_shadow_only(self):
        recorder = _function(GAS, "_record_phase3_shadow_directional_species_event")
        self.assertIn("if not phase3_canonical_zone_shadow_enabled", recorder)
        self.assertNotIn(".co_kg =", recorder)
        self.assertNotIn(".co2_kg =", recorder)
        self.assertNotIn(".hcn_kg =", recorder)

    def test_event_contract_has_route_split_and_identity(self):
        recorder = _function(GAS, "_record_phase3_shadow_directional_species_event")
        for field in (
            "request_id", "cause", "source_room_id", "destination_room_id",
            "species_kg", "upper_species_kg",
        ):
            self.assertIn(f'"{field}"', recorder)

    def test_background_uses_exact_signed_pre_delta_values(self):
        exchange = _function(GAS, "_apply_background_species_exchange")
        for species in ("co", "co2", "hcn"):
            marker = f'"background_species_exchange", room_a, room_b, "{species}"'
            self.assertIn(marker, exchange)
        self.assertLess(
            exchange.index('"background_species_exchange", room_a, room_b, "co"'),
            exchange.index("co_delta_kg[room_a.id] -= net_co_a_to_b"),
        )
        self.assertLess(
            exchange.index('"background_species_exchange", room_a, room_b, "co2"'),
            exchange.index("co2_delta_kg[room_a.id] -= net_co2_a_to_b"),
        )

    def test_background_bulk_only_species_are_lower_zone(self):
        exchange = _function(GAS, "_apply_background_species_exchange")
        co2_call = exchange.split(
            '"background_species_exchange", room_a, room_b, "co2"', 1
        )[1].split(")", 1)[0]
        hcn_call = exchange.split(
            '"background_species_exchange", room_a, room_b, "hcn"', 1
        )[1].split(")", 1)[0]
        self.assertIn("net_co2_a_to_b, 0.0", co2_call)
        self.assertIn("net_hcn_a_to_b, 0.0", hcn_call)

    def test_counterflow_records_both_gross_directions(self):
        step = _function(GAS, "step_smoke")
        for species in ("co", "co2", "hcn"):
            self.assertIn(
                f'"doorway_species_counterflow", source, target, "{species}"', step
            )
            self.assertIn(
                f'"doorway_species_counterflow", target, source, "{species}"', step
            )

    def test_counterflow_event_precedes_legacy_delta(self):
        step = _function(GAS, "step_smoke")
        self.assertLess(
            step.index('"doorway_species_counterflow", source, target, "co"'),
            step.index("co_delta_kg[from_id] += target_co_out_kg - source_co_out_kg"),
        )

    def test_two_zone_direct_and_parcels_keep_separate_causes(self):
        self.assertIn('"doorway_species_direct"', GAS)
        self.assertIn('"delayed_species_parcel_carve"', SYSTEM)
        self.assertIn('"background_species_exchange"', GAS)
        self.assertIn('"doorway_species_counterflow"', GAS)

    def test_vertical_helpers_are_not_silently_owned(self):
        net_vertical = _function(GAS, "_apply_species_net_exchange")
        directed_vertical = _function(GAS, "_apply_directed_species_exchange")
        self.assertNotIn("phase3_shadow", net_vertical)
        self.assertNotIn("phase3_shadow", directed_vertical)

    def test_events_are_drained_once_per_step(self):
        begin = _function(GAS, "begin_phase3_shadow_step")
        drain = _function(GAS, "drain_phase3_shadow_immediate_species_events")
        self.assertIn("_phase3_shadow_immediate_species_events.clear()", begin)
        self.assertIn("duplicate(true)", drain)
        self.assertIn("_phase3_shadow_immediate_species_events.clear()", drain)

    def test_engine_only_forwards_immediate_events(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_immediate_species_events")
        self.assertIn("drain_phase3_shadow_immediate_species_events()", collector)
        self.assertIn("apply_immediate_species_event(event)", collector)
        for forbidden in ("exchange_air_kg", "co_kg", "co2_kg", "hcn_kg"):
            self.assertNotIn(forbidden, collector)

    def test_phase3_splits_upper_and_lower_requests(self):
        apply_event = _function(SYSTEM, "apply_immediate_species_event")
        self.assertIn("_bounded_upper_transit_species", apply_event)
        self.assertIn("_add_transit_zone_requests", apply_event)

    def test_only_owned_species_are_filtered(self):
        apply_event = _function(SYSTEM, "apply_immediate_species_event")
        self.assertIn("_transit_species", apply_event)
        for excluded in ("smoke", "hcl", "acrolein", "formaldehyde", "o2"):
            self.assertNotIn(f'"{excluded}"', apply_event)

    def test_reset_is_atomic_for_cumulative_and_step_ledgers(self):
        reset = _function(SYSTEM, "reset")
        step_reset = _function(SYSTEM, "_reset_step_state")
        self.assertIn("_immediate_background_species_kg.clear()", reset)
        self.assertIn("_immediate_counterflow_species_kg.clear()", reset)
        self.assertIn("_immediate_debited_species_kg_step.clear()", step_reset)
        self.assertIn("_immediate_credited_species_kg_step.clear()", step_reset)

    def test_conservation_and_rejection_are_visible(self):
        apply_request = _function(SYSTEM, "_apply_request")
        self.assertIn("_immediate_rejected_kg_total", apply_request)
        self.assertIn("_immediate_debited_species_kg_step", apply_request)
        self.assertIn("_immediate_credited_species_kg_step", apply_request)

    def test_csv_telemetry_is_shadow_gated(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2)


if __name__ == "__main__":
    unittest.main()
