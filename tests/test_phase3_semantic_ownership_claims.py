"""Structural checks for F3.0k.1a semantic ownership claims."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
GES = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
OPENING = (ROOT / "sim/building/OpeningModel.gd").read_text(encoding="utf-8")
BUILDING = (ROOT / "sim/BuildingModel.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_semantic_claim_count",
    "phase3_shadow_semantic_conflict_count",
    "phase3_shadow_semantic_conflict_quantity_mask",
    "phase3_shadow_semantic_conflict_mass_kg",
    "phase3_shadow_semantic_conflict_energy_kj",
    "phase3_shadow_semantic_conflict_o2_kg",
    "phase3_shadow_semantic_conflict_species_kg",
    "phase3_shadow_semantic_unknown_connection_count",
)


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestPhase3SemanticOwnershipClaims(unittest.TestCase):
    def test_opening_identity_is_stable_and_assigned_by_building(self):
        self.assertIn("var opening_index: int = -1", OPENING)
        self.assertIn("op.opening_index = openings.size()", BUILDING)

    def test_claim_key_uses_connection_direction_zones_and_quantity(self):
        register = _function(SYSTEM, "register_semantic_claim")
        for field in (
            "connection_id",
            "source_room_id",
            "destination_room_id",
            "source_zone",
            "destination_zone",
            "quantity",
        ):
            self.assertIn(field, register)
        key_block = register.split('var key: String =', 1)[1].split("]", 1)[0]
        self.assertNotIn("producer", key_block)
        self.assertNotIn("transport_family", key_block)

    def test_producer_and_mechanism_are_claim_metadata(self):
        register = _function(SYSTEM, "register_semantic_claim")
        self.assertIn('claim.get("producer"', register)
        self.assertIn('claim.get("transport_family"', register)
        self.assertIn('record.get("producers"', register)
        self.assertIn('record.get("mechanisms"', register)

    def test_claim_registry_is_reset_each_physics_step(self):
        reset = _function(SYSTEM, "_reset_step_state")
        self.assertIn("_semantic_claims.clear()", reset)
        self.assertIn("_semantic_claim_count = 0", reset)
        self.assertIn("_semantic_unknown_connection_count = 0", reset)

    def test_conflict_requires_more_than_one_producer(self):
        summary = _function(SYSTEM, "_semantic_conflict_summary")
        self.assertIn("if producers.size() <= 1", summary)
        self.assertIn("total - largest", summary)
        self.assertIn("quantity_mask", summary)

    def test_claim_registry_never_mutates_room_model(self):
        register = _function(SYSTEM, "register_semantic_claim")
        self.assertNotIn("RoomModel", register)
        self.assertNotIn("room.", register)
        self.assertNotIn("_apply_request", register)

    def test_thermal_events_use_shared_opening_identity(self):
        recorder = _function(THERMAL, "_record_phase3_shadow_thermal_species_event")
        transfer = _function(THERMAL, "_transfer_hot_gas_contaminants")
        self.assertIn('"connection_id"', recorder)
        self.assertIn('"opening:%d" % opening_index', transfer)
        self.assertIn("op.opening_index", THERMAL)

    def test_ges_direct_background_and_parcels_keep_opening_identity(self):
        for token in (
            '"connection_id": "opening:%d" % opening_index',
            '"opening_index": op.opening_index',
            '"connection_id": "opening:%d" % transfer_opening_index',
            '"connection_id": String(entry.get("connection_id", ""))',
        ):
            self.assertIn(token, GES)

    def test_exterior_purge_has_stable_virtual_boundary_identity(self):
        recorder = _function(GES, "_record_phase3_shadow_exterior_purge_event")
        self.assertIn('"connection_id": "exterior:%d:%s"', recorder)
        self.assertIn('"destination_room_id": BuildingModel.OUTSIDE_ID', recorder)

    def test_parcel_claim_is_registered_only_at_creation(self):
        transit = _function(SYSTEM, "apply_species_transit_event")
        created = transit.split('"created":', 1)[1].split('"resolved":', 1)[0]
        resolved = transit.split('"resolved":', 1)[1].split('"cancelled":', 1)[0]
        self.assertIn("_register_split_species_claims", created)
        self.assertNotIn("_register_split_species_claims", resolved)

    def test_engine_registers_non_transport_chemical_claims(self):
        self.assertIn('"chemical:%d:combustion"', ENGINE)
        self.assertIn('"chemical:%d:combustion_species"', ENGINE)
        self.assertIn('"producer": "CombustionSystem"', ENGINE)
        self.assertIn('"producer": "OxygenExchangeSystem"', ENGINE)

    def test_generation_and_transport_use_distinct_connection_namespaces(self):
        self.assertIn('"chemical:%d:combustion_species"', ENGINE)
        self.assertIn('"opening:%d" % opening_index', THERMAL)
        self.assertIn('"opening:%d" % opening_index', GES)

    def test_engine_forwards_direct_doorway_as_one_atomic_event(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_doorway_species_requests")
        self.assertIn("apply_atomic_transport_event", collector)
        self.assertNotIn("register_semantic_unresolved", collector)
        self.assertNotIn("phase3_zone_mass_system.add_request", collector)

    def test_unknown_connections_remain_visible(self):
        register = _function(SYSTEM, "register_semantic_claim")
        self.assertIn("_semantic_unknown_connection_count += 1", register)
        self.assertIn("phase3_shadow_semantic_unknown_connection_count", SYSTEM)

    def test_csv_fields_are_shadow_gated_and_unique(self):
        self.assertIn("if phase3_canonical_zone_shadow_enabled:", LOG)
        for field in FIELDS:
            self.assertEqual(LOG.count(field), 2, field)


if __name__ == "__main__":
    unittest.main()
