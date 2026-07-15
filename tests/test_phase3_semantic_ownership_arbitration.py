"""Structural checks for F3.0k.1b passive semantic arbitration."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_thermal_semantic_suppressed_kg_total",
    "phase3_shadow_semantic_accepted_claim_count",
    "phase3_shadow_semantic_suppressed_claim_count",
    "phase3_shadow_semantic_unresolved_claim_count",
    "phase3_shadow_semantic_suppressed_quantity_mask",
    "phase3_shadow_semantic_unresolved_quantity_mask",
    "phase3_shadow_semantic_suppressed_species_kg",
    "phase3_shadow_semantic_unresolved_mass_kg",
    "phase3_shadow_semantic_unresolved_energy_kj",
    "phase3_shadow_semantic_unresolved_o2_kg",
    "phase3_shadow_semantic_unresolved_species_kg",
    "phase3_shadow_semantic_unresolved_conflict_count",
    "phase3_shadow_co_oxidation_co_sink_kg_step",
    "phase3_shadow_co_oxidation_co2_source_kg_step",
    "phase3_shadow_co_oxidation_carbon_residual_kg_step",
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestSemanticOwnerPolicy(unittest.TestCase):
    def test_opening_species_owner_is_ges(self):
        policy = _function(SYSTEM, "_semantic_owner_for_claim")
        self.assertIn('"interior_opening", "vertical_opening", "exterior_opening"', policy)
        self.assertIn('"GasExchangeSystem" if quantity in TRANSIT_SPECIES', policy)

    def test_interlayer_owner_is_thermal(self):
        policy = _function(SYSTEM, "_semantic_owner_for_claim")
        self.assertIn('"interlayer":', policy)
        self.assertIn('return "ThermalSystem"', policy)

    def test_chemical_owners_are_explicit(self):
        policy = _function(SYSTEM, "_semantic_owner_for_claim")
        for owner in ("ThermalSystem", "OxygenExchangeSystem", "CombustionSystem"):
            self.assertIn(f'return "{owner}"', policy)

    def test_claim_classification_is_separate_from_raw_conflict_registry(self):
        register = _function(SYSTEM, "register_semantic_claim")
        self.assertIn('status = "accepted" if producer == owner else "suppressed"', register)
        self.assertIn('_semantic_claims[key] = record', register)
        self.assertIn('_semantic_suppressed_claim_count += 1', register)
        self.assertIn('_semantic_unresolved_claim_count += 1', register)

    def test_unresolved_declarations_are_deduplicated(self):
        unresolved = _function(SYSTEM, "register_semantic_unresolved")
        self.assertIn("_semantic_unresolved_keys.has(key)", unresolved)
        self.assertIn("_semantic_unresolved_quantity_mask", unresolved)

    def test_missing_transport_bundle_stays_unresolved(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_doorway_species_requests")
        self.assertIn('register_semantic_unresolved', collector)
        for quantity in ("gas_mass", "enthalpy", "o2"):
            self.assertIn(f'"{quantity}"', collector)


class TestShadowOnlySuppression(unittest.TestCase):
    def test_thermal_opening_claims_can_be_suppressed_in_shadow(self):
        apply_event = _function(SYSTEM, "apply_thermal_species_event")
        self.assertIn("var shadow_owned: bool", apply_event)
        self.assertIn("if not shadow_owned:", apply_event)
        self.assertLess(
            apply_event.index("if not shadow_owned:"),
            apply_event.index("_add_thermal_species_route_requests"),
        )

    def test_suppressed_thermal_mass_remains_in_contract_residual(self):
        residual = _function(SYSTEM, "_thermal_species_residual_for")
        self.assertIn("_thermal_species_semantic_suppressed_kg", residual)

    def test_shadow_component_never_writes_room_model(self):
        register = _function(SYSTEM, "register_semantic_claim")
        self.assertNotIn("RoomModel", register)
        self.assertNotIn("room.", register)

    def test_legacy_co_oxidation_writes_are_preserved(self):
        oxidation = _function(ENGINE, "_step_co_oxidation")
        self.assertIn("room.co_upper_kg -= oxidized_kg", oxidation)
        self.assertIn("room.co_kg = maxf", oxidation)
        self.assertIn("room.co2_kg += generated_co2_kg", oxidation)


class TestCoOxidationContract(unittest.TestCase):
    def test_event_is_emitted_before_legacy_writes(self):
        oxidation = _function(ENGINE, "_step_co_oxidation")
        self.assertLess(
            oxidation.index("apply_co_oxidation_event"),
            oxidation.index("room.co_upper_kg -= oxidized_kg"),
        )

    def test_event_is_shadow_gated(self):
        oxidation = _function(ENGINE, "_step_co_oxidation")
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", oxidation)

    def test_conversion_has_exact_co_sink_and_co2_source(self):
        event = _function(SYSTEM, "apply_co_oxidation_event")
        self.assertIn('event_id + ":co_sink"', event)
        self.assertIn('{"co": co_sink_kg}', event)
        self.assertIn('event_id + ":co2_source"', event)
        self.assertIn('{"co2": co2_source_kg}', event)

    def test_co2_source_preserves_legacy_lower_zone_semantics(self):
        event = _function(SYSTEM, "apply_co_oxidation_event")
        source = event.split('event_id + ":co2_source"', 1)[1]
        self.assertIn("ZONE_LOWER", source)

    def test_legacy_missing_o2_sink_is_visible(self):
        event = _function(SYSTEM, "apply_co_oxidation_event")
        self.assertIn("register_semantic_unresolved", event)
        self.assertIn('["o2"]', event)

    def test_carbon_residual_uses_molecular_weights(self):
        event = _function(SYSTEM, "apply_co_oxidation_event")
        self.assertIn("12.0 / 28.0", event)
        self.assertIn("12.0 / 44.0", event)


class TestArbitrationCsv(unittest.TestCase):
    def test_fields_are_shadow_gated_and_unique(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2, field)


if __name__ == "__main__":
    unittest.main()
