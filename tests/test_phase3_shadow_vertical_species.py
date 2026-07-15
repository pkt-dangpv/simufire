"""Structural checks for F3.0h legacy vertical species shadow ownership."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
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
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestPhase3ShadowVerticalSpecies(unittest.TestCase):
    def test_zonal_event_is_shadow_only_and_explicit(self):
        recorder = _function(GAS, "_record_phase3_shadow_zonal_species_event")
        self.assertIn("if not phase3_canonical_zone_shadow_enabled", recorder)
        for field in (
            "source_room_id", "destination_room_id", "source_zone",
            "destination_zone", "species_kg", "opposed_zone_direction",
        ):
            self.assertIn(f'"{field}"', recorder)
        for mutation in (".co_kg =", ".co2_kg =", ".hcn_kg ="):
            self.assertNotIn(mutation, recorder)

    def test_net_co_uses_exact_bulk_upper_and_lower_difference(self):
        exchange = _function(GAS, "_apply_species_net_exchange")
        self.assertIn("var net_co_a_to_b: float = _compute_net_pair", exchange)
        self.assertIn("var net_co_upper_a_to_b: float = _compute_net_pair", exchange)
        self.assertIn(
            "var net_co_lower_a_to_b: float = net_co_a_to_b - net_co_upper_a_to_b",
            exchange,
        )

    def test_net_co_preserves_opposed_zone_directions(self):
        exchange = _function(GAS, "_apply_species_net_exchange")
        self.assertIn("net_co_upper_a_to_b * net_co_lower_a_to_b < -1.0e-18", exchange)
        self.assertIn('"upper", "co",', exchange)
        self.assertIn('"lower", "co",', exchange)
        self.assertIn("co_zones_opposed", exchange)

    def test_signed_zonal_recorder_reverses_rooms_not_zones(self):
        recorder = _function(GAS, "_record_phase3_shadow_signed_zonal_species_event")
        self.assertIn("cause, room_a, room_b, zone_name, zone_name", recorder)
        self.assertIn("cause, room_b, room_a, zone_name, zone_name", recorder)

    def test_net_bulk_only_species_are_lower_zone(self):
        exchange = _function(GAS, "_apply_species_net_exchange")
        for species in ("co2", "hcn"):
            self.assertIn(f'"lower", "{species}",', exchange)

    def test_net_events_precede_legacy_delta_application(self):
        exchange = _function(GAS, "_apply_species_net_exchange")
        self.assertLess(
            exchange.index('"vertical_species_net_exchange"'),
            exchange.index("_apply_net_pair_value"),
        )

    def test_directed_co_split_is_exact(self):
        exchange = _function(GAS, "_apply_directed_species_exchange")
        self.assertIn('"upper", "upper", "co", d_co_up', exchange)
        self.assertIn('"lower", "lower", "co", maxf(0.0, d_co - d_co_up)', exchange)

    def test_directed_bulk_only_species_are_lower_zone(self):
        exchange = _function(GAS, "_apply_directed_species_exchange")
        self.assertIn('"lower", "lower", "co2", d_co2', exchange)
        self.assertIn('"lower", "lower", "hcn", d_hcn', exchange)

    def test_directed_events_precede_legacy_deltas(self):
        exchange = _function(GAS, "_apply_directed_species_exchange")
        self.assertLess(
            exchange.index('"vertical_species_directed_exchange"'),
            exchange.index("smoke_delta_kg[from_r.id]"),
        )

    def test_contract_excludes_unowned_species(self):
        net_exchange = _function(GAS, "_apply_species_net_exchange")
        directed = _function(GAS, "_apply_directed_species_exchange")
        recorder_calls = net_exchange + directed
        for species in ("o2", "smoke", "hcl", "acrolein", "formaldehyde"):
            self.assertNotIn(f'"{species}"', recorder_calls)

    def test_two_zone_opening_path_returns_before_legacy_vertical(self):
        background = _function(GAS, "_apply_background_species_exchange")
        self.assertLess(
            background.index("_apply_two_zone_opening_species_exchange"),
            background.index("if op.is_vertical"),
        )
        self.assertLess(background.index("return"), background.index("if op.is_vertical"))

    def test_ledger_accepts_explicit_zonal_events(self):
        apply_event = _function(SYSTEM, "apply_immediate_species_event")
        self.assertIn('event.has("source_zone")', apply_event)
        self.assertIn('event.has("destination_zone")', apply_event)
        self.assertIn('String(event.get("source_zone", ZONE_UPPER))', apply_event)
        self.assertIn('String(event.get("destination_zone", ZONE_UPPER))', apply_event)

    def test_ledger_tracks_both_vertical_causes_separately(self):
        apply_event = _function(SYSTEM, "apply_immediate_species_event")
        self.assertIn('"vertical_species_net_exchange"', apply_event)
        self.assertIn("_vertical_net_species_kg", apply_event)
        self.assertIn('"vertical_species_directed_exchange"', apply_event)
        self.assertIn("_vertical_directed_species_kg", apply_event)

    def test_opposed_direction_counter_is_explicit(self):
        apply_event = _function(SYSTEM, "apply_immediate_species_event")
        self.assertIn('event.get("opposed_zone_direction", false)', apply_event)
        self.assertIn("_vertical_opposed_zone_direction_count += 1", apply_event)

    def test_vertical_rejection_and_conservation_are_visible(self):
        apply_request = _function(SYSTEM, "_apply_request")
        self.assertIn("_vertical_rejected_kg_total", apply_request)
        self.assertIn("_vertical_debited_species_kg_step", apply_request)
        self.assertIn("_vertical_credited_species_kg_step", apply_request)

    def test_reset_clears_vertical_cumulative_and_step_state(self):
        reset = _function(SYSTEM, "reset")
        step_reset = _function(SYSTEM, "_reset_step_state")
        for name in ("_vertical_net_species_kg", "_vertical_directed_species_kg"):
            self.assertIn(f"{name}.clear()", reset)
        self.assertIn("_vertical_debited_species_kg_step.clear()", step_reset)
        self.assertIn("_vertical_credited_species_kg_step.clear()", step_reset)

    def test_engine_uses_existing_single_event_drain(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_immediate_species_events")
        self.assertIn("drain_phase3_shadow_immediate_species_events()", collector)
        self.assertIn("apply_immediate_species_event(event)", collector)

    def test_csv_fields_are_shadow_gated_and_unique(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2)


if __name__ == "__main__":
    unittest.main()
