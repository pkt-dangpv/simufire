"""F3.0e structural checks for direct two-zone doorway species ownership."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    return source.split(f"func {name}", 1)[1].split("\nfunc ", 1)[0]


class TestPhase3CanonicalShadowDoorwaySpecies(unittest.TestCase):
    def test_shadow_flag_is_wired_into_gas_exchange(self):
        self.assertIn("var phase3_canonical_zone_shadow_enabled: bool = false", GAS)
        configure = _function(GAS, "configure")
        self.assertIn('settings.get("phase3_canonical_zone_shadow_enabled"', configure)
        self.assertIn(
            '"phase3_canonical_zone_shadow_enabled": phase3_canonical_zone_shadow_enabled',
            ENGINE,
        )

    def test_only_canonical_two_zone_helpers_emit_direct_results(self):
        upper = _function(GAS, "_move_upper_zone_species")
        lower = _function(GAS, "_move_lower_zone_species")
        self.assertIn('"cause": "doorway_species_direct"', upper)
        self.assertIn('"cause": "doorway_species_direct"', lower)
        self.assertEqual(GAS.count('_record_phase3_shadow_doorway_species_result(species_result)'), 2)

    def test_result_is_recorded_before_legacy_delta_application(self):
        for name in ("_move_upper_zone_species", "_move_lower_zone_species"):
            body = _function(GAS, name)
            self.assertLess(
                body.index("_record_phase3_shadow_doorway_species_result(species_result)"),
                body.index("_apply_doorway_species_result("),
            )

    def test_legacy_and_shadow_share_the_same_result(self):
        for name in ("_move_upper_zone_species", "_move_lower_zone_species"):
            body = _function(GAS, name)
            self.assertIn("_record_phase3_shadow_doorway_species_result(species_result)", body)
            self.assertIn("_apply_doorway_species_result(\n\t\tspecies_result,", body)

    def test_result_has_explicit_zonal_route_and_three_species(self):
        upper = _function(GAS, "_move_upper_zone_species")
        lower = _function(GAS, "_move_lower_zone_species")
        self.assertIn('"source_zone": "upper"', upper)
        self.assertIn('"source_zone": "lower"', lower)
        for body in (upper, lower):
            self.assertIn('"destination_zone": "upper" if target_upper_zone else "lower"', body)
            for species in ("co", "co2", "hcn"):
                self.assertIn(f'"{species}": moved_{species}_kg', body)

    def test_apply_moves_total_and_only_the_selected_upper_subsets(self):
        apply_body = _function(GAS, "_apply_doorway_species_result")
        self.assertIn('_add_delta(co_delta_kg, source_id, -moved_co_kg)', apply_body)
        self.assertIn('_add_delta(co_delta_kg, destination_id, moved_co_kg)', apply_body)
        self.assertIn('if source_zone == "upper":', apply_body)
        self.assertIn('if destination_zone == "upper":', apply_body)
        self.assertNotIn("co_kg =", apply_body)

    def test_request_identity_is_created_by_the_physical_producer(self):
        recorder = _function(GAS, "_record_phase3_shadow_doorway_species_result")
        self.assertIn('recorded["request_id"]', recorder)
        self.assertIn('"doorway_species_direct:', recorder)
        collector = _function(ENGINE, "_phase3_shadow_collect_doorway_species_requests")
        self.assertIn('String(result.get("request_id", ""))', collector)

    def test_engine_only_translates_results(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_doorway_species_requests")
        self.assertIn("gas_exchange_system.drain_phase3_shadow_doorway_species_results()", collector)
        for forbidden in (
            "headroom", "cut_ratio", "co_delta_kg", "co2_delta_kg",
            "hcn_delta_kg", "net_transport", "projection", "reconcile",
        ):
            self.assertNotIn(forbidden, collector)

    def test_delayed_parcels_are_not_collected(self):
        collector = _function(ENGINE, "_phase3_shadow_collect_doorway_species_requests")
        for forbidden in ("pending", "parcel", "inflight", "delivery"):
            self.assertNotIn(forbidden, collector.lower())
        release = _function(GAS, "_release_pending_interior_deliveries")
        self.assertNotIn("_record_phase3_shadow_doorway_species_result", release)

    def test_background_and_exterior_paths_are_not_owned(self):
        background = _function(GAS, "_apply_background_species_exchange")
        exterior = _function(GAS, "_queue_upper_species_to_exterior")
        self.assertNotIn("_record_phase3_shadow_doorway_species_result", background)
        self.assertNotIn("_record_phase3_shadow_doorway_species_result", exterior)

    def test_shadow_rejection_tracks_species_not_zero_gas_mass(self):
        self.assertIn('String(request.get("cause", "")) == "doorway_species_direct"', SYSTEM)
        self.assertIn("rejected_species_kg", SYSTEM)
        self.assertIn("rejected_doorway_species_by_room", SYSTEM)

    def test_csv_telemetry_is_shadow_gated(self):
        for field in (
            "phase3_shadow_doorway_co_request_kg",
            "phase3_shadow_doorway_co2_request_kg",
            "phase3_shadow_doorway_hcn_request_kg",
            "phase3_shadow_doorway_species_rejected_kg",
        ):
            self.assertEqual(LOG.count(field), 2)


if __name__ == "__main__":
    unittest.main()
