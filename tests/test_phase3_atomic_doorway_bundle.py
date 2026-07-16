"""Structural checks for F3.0k.1d direct-doorway atomic shadow bundles."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
GES = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestDoorwayProducerContract(unittest.TestCase):
    def test_upper_and_lower_routes_emit_complete_pre_apply_payloads(self):
        for name, zone in (
            ("_move_upper_zone_species", "true"),
            ("_move_lower_zone_species", "false"),
        ):
            body = _function(GES, name)
            record_at = body.index("_record_phase3_shadow_doorway_species_result")
            for field in ("gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"):
                self.assertIn(f'species_result["{field}"]', body[:record_at])
            self.assertIn(
                f"_zone_specific_sensible_energy_kj_kg(from_r, {zone})",
                body[:record_at],
            )

    def test_shadow_recording_does_not_change_legacy_room_writes(self):
        helper = _function(GES, "_record_phase3_shadow_doorway_species_result")
        self.assertNotIn("RoomModel", helper)
        self.assertIsNone(re.search(r"\broom\.", helper))


class TestAtomicDoorwayCollection(unittest.TestCase):
    def test_engine_forwards_doorway_event_once(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_doorway_species_requests")
        self.assertEqual(collector.count("apply_atomic_transport_event"), 1)
        self.assertNotIn("register_semantic_unresolved", collector)

    def test_atomic_transport_claims_all_quantities(self):
        apply_event = _function(SYSTEM, "apply_atomic_transport_event")
        for quantity in ("gas_mass", "enthalpy", "o2"):
            self.assertIn(f'"{quantity}"', apply_event)
        self.assertIn("_register_event_species_claims", apply_event)
        self.assertIn("make_atomic_route", apply_event)
        self.assertIn("add_atomic_bundle(make_atomic_bundle(", apply_event)

    def test_doorway_owner_is_scoped_to_exact_transport_family(self):
        policy = _function(SYSTEM, "_semantic_owner_for_claim")
        self.assertIn('transport_family == "doorway_bulk"', policy)
        self.assertIn('["gas_mass", "enthalpy", "o2"]', policy)

    def test_request_telemetry_is_not_applied_as_second_transaction(self):
        telemetry = _function(SYSTEM, "_record_request_telemetry")
        self.assertIn("_requests.append", telemetry)
        self.assertNotIn("_transactions.append", telemetry)


if __name__ == "__main__":
    unittest.main()
