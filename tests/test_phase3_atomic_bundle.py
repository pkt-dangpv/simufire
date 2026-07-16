"""Structural checks for F3.0k.1c atomic shadow transactions."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


ATOMIC_FIELDS = (
    "phase3_shadow_atomic_bundle_count",
    "phase3_shadow_atomic_route_count",
    "phase3_shadow_atomic_min_accepted_fraction",
    "phase3_shadow_atomic_rejected_mass_kg",
    "phase3_shadow_atomic_rejected_energy_kj",
    "phase3_shadow_atomic_rejected_o2_kg",
    "phase3_shadow_atomic_rejected_species_kg",
    "phase3_shadow_atomic_duplicate_bundle_count",
    "phase3_shadow_atomic_invalid_bundle_count",
    "phase3_shadow_co_oxidation_o2_sink_kg_step",
    "phase3_shadow_co_oxidation_accepted_fraction",
    "phase3_shadow_co_oxidation_accepted_co_sink_kg_step",
    "phase3_shadow_co_oxidation_accepted_co2_source_kg_step",
    "phase3_shadow_co_oxidation_accepted_o2_sink_kg_step",
    "phase3_shadow_co_oxidation_o2_rejected_kg_step",
    "phase3_shadow_co_oxidation_oxygen_residual_kg_step",
    "phase3_shadow_co_oxidation_legacy_lower_co2_kg_step",
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestAtomicBundleApi(unittest.TestCase):
    def test_route_rejects_negative_or_unknown_quantities(self):
        route = _function(SYSTEM, "make_atomic_route")
        self.assertIn("gas_mass_kg >= 0.0", route)
        self.assertIn("sensible_enthalpy_kj >= 0.0", route)
        self.assertIn("o2_kg >= 0.0", route)
        self.assertIn("species_name not in TRANSIT_SPECIES", route)

    def test_route_requires_nonempty_payload_and_valid_zones(self):
        validate = _function(SYSTEM, "_atomic_route_is_valid")
        self.assertIn("source_zone not in [ZONE_UPPER, ZONE_LOWER]", validate)
        self.assertIn("destination_zone not in [ZONE_UPPER, ZONE_LOWER]", validate)
        self.assertIn("_sum_transit_species(raw_species) > 0.0", validate)

    def test_bundle_has_one_id_and_ordered_routes(self):
        bundle = _function(SYSTEM, "make_atomic_bundle")
        self.assertIn('"bundle_id": bundle_id', bundle)
        self.assertIn("for raw_route in routes:", bundle)
        self.assertIn("normalized_routes.append(route)", bundle)

    def test_simple_and_atomic_work_share_transaction_queue(self):
        add_request = _function(SYSTEM, "add_request")
        add_bundle = _function(SYSTEM, "add_atomic_bundle")
        self.assertIn('{"kind": "request", "value": record}', add_request)
        self.assertIn('{"kind": "atomic_bundle", "value": record}', add_bundle)

    def test_duplicate_and_invalid_bundles_are_visible(self):
        add_bundle = _function(SYSTEM, "add_atomic_bundle")
        self.assertIn("_atomic_invalid_bundle_count += 1", add_bundle)
        self.assertIn("_atomic_duplicate_bundle_count += 1", add_bundle)


class TestAtomicArbitration(unittest.TestCase):
    def test_finalize_preserves_transaction_order(self):
        finalize = _function(SYSTEM, "finalize_step")
        self.assertIn("for raw_transaction in _transactions:", finalize)
        self.assertIn('"request":', finalize)
        self.assertIn('"atomic_bundle":', finalize)

    def test_source_demands_are_aggregated_before_fraction(self):
        apply_bundle = _function(SYSTEM, "_apply_atomic_bundle")
        aggregate = apply_bundle.index("var source_demands: Dictionary")
        fraction = apply_bundle.index("var accepted_fraction: float")
        apply_route = apply_bundle.index("_apply_atomic_route(")
        self.assertLess(aggregate, fraction)
        self.assertLess(fraction, apply_route)
        self.assertIn("source_demands[demand_key] = demand", apply_bundle)

    def test_missing_internal_room_rejects_bundle_before_apply(self):
        apply_bundle = _function(SYSTEM, "_apply_atomic_bundle")
        preflight = apply_bundle.split("var source_demands: Dictionary", 1)[1]
        preflight = preflight.split("var accepted_fraction: float", 1)[0]
        self.assertIn("not shadow.has(str(source_id))", preflight)
        self.assertIn("not shadow.has(str(destination_id))", preflight)
        self.assertIn("_atomic_invalid_bundle_count += 1", preflight)

    def test_fraction_is_limited_by_all_canonical_inventories(self):
        apply_bundle = _function(SYSTEM, "_apply_atomic_bundle")
        for suffix in ("_gas_kg", "_energy_kj", "_o2_kg", "_species_kg"):
            self.assertIn(suffix, apply_bundle)
        self.assertGreaterEqual(apply_bundle.count("_limit_atomic_fraction("), 4)

    def test_every_route_receives_the_same_fraction(self):
        apply_bundle = _function(SYSTEM, "_apply_atomic_bundle")
        apply_route = _function(SYSTEM, "_apply_atomic_route")
        self.assertIn("_apply_atomic_route(shadow, route, accepted_fraction)", apply_bundle)
        self.assertNotIn("_limit_atomic_fraction", apply_route)

    def test_atomic_rejection_is_available_to_doorway_telemetry(self):
        apply_bundle = _function(SYSTEM, "_apply_atomic_bundle")
        self.assertIn("rejected_doorway_species_by_room", apply_bundle)
        self.assertIn('transport_family", "")) == "doorway_bulk"', apply_bundle)

    def test_shadow_atomic_path_never_writes_room_model(self):
        for name in ("_apply_atomic_bundle", "_apply_atomic_route"):
            body = _function(SYSTEM, name)
            self.assertNotIn("RoomModel", body)
            self.assertIsNone(re.search(r"\broom\.", body))


class TestAtomicCoOxidation(unittest.TestCase):
    def test_reactants_share_one_upper_source_route(self):
        event = _function(SYSTEM, "apply_co_oxidation_event")
        reactants = event.split('event_id + ":reactants"', 1)[1]
        reactants = reactants.split('event_id + ":products"', 1)[0]
        self.assertIn("o2_sink_kg", reactants)
        self.assertIn('{"co": co_sink_kg}', reactants)
        self.assertGreaterEqual(reactants.count("ZONE_UPPER"), 2)

    def test_product_is_tied_to_same_bundle_fraction(self):
        event = _function(SYSTEM, "apply_co_oxidation_event")
        self.assertIn("var routes: Array = [", event)
        self.assertIn("add_atomic_bundle(make_atomic_bundle(", event)
        self.assertIn('"co2_generated_kg": co2_source_kg', event)

    def test_accepted_chemistry_tracks_carbon_and_oxygen(self):
        result = _function(SYSTEM, "_record_atomic_bundle_result")
        self.assertIn("accepted_co_kg * (16.0 / 28.0)", result)
        self.assertIn("requested_o2_kg - accepted_o2_kg", result)
        event = _function(SYSTEM, "apply_co_oxidation_event")
        self.assertIn("12.0 / 28.0", event)
        self.assertIn("12.0 / 44.0", event)

    def test_engine_legacy_state_does_not_gain_an_o2_write(self):
        oxidation = _function(ENGINE, "_step_co_oxidation")
        self.assertIn("oxidized_kg * (16.0 / 28.0)", oxidation)
        self.assertNotIn("room.o2_upper =", oxidation)
        self.assertNotIn("room.o2_upper -=", oxidation)
        self.assertNotIn("room.o2 -=", oxidation)


class TestAtomicCsv(unittest.TestCase):
    def test_fields_are_shadow_gated_and_unique(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in ATOMIC_FIELDS:
            self.assertEqual(LOG.count(field), 2, field)


if __name__ == "__main__":
    unittest.main()
