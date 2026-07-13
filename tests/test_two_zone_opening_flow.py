"""M3 checks for two-zone opening species routing."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ROOM = (ROOT / "sim" / "building" / "RoomModel.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
GAS = (ROOT / "sim" / "core" / "GasExchangeSystem.gd").read_text(encoding="utf-8")
HVAC = (ROOT / "sim" / "core" / "HVACSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
CASE_RUNNER = (ROOT / "sim" / "validation" / "CaseRunner.gd").read_text(encoding="utf-8")
RUN_CASE = (ROOT / "sim" / "validation" / "run_case.ps1").read_text(encoding="utf-8")
COMPARE_RUNNER = (
    ROOT / "sim" / "validation" / "run_legacy_two_zone_compare.ps1"
).read_text(encoding="utf-8")


class TestTwoZoneOpeningArithmetic(unittest.TestCase):
    def test_upper_to_lower_route_conserves_total_and_reduces_upper_inventory(self):
        source_total = 0.50
        source_upper = 0.30
        target_total = 0.12
        target_upper = 0.02
        before_total = source_total + target_total
        before_upper = source_upper + target_upper

        moved = source_upper * 0.10
        source_total -= moved
        source_upper -= moved
        target_total += moved

        self.assertAlmostEqual(source_total + target_total, before_total)
        self.assertAlmostEqual(source_upper + target_upper, before_upper - moved)

    def test_lower_to_upper_route_conserves_total_and_promotes_to_upper_inventory(self):
        source_total = 0.50
        source_upper = 0.10
        target_total = 0.12
        target_upper = 0.02
        before_total = source_total + target_total
        before_upper = source_upper + target_upper

        moved = (source_total - source_upper) * 0.25
        source_total -= moved
        target_total += moved
        target_upper += moved

        self.assertAlmostEqual(source_total + target_total, before_total)
        self.assertAlmostEqual(source_upper + target_upper, before_upper + moved)


class TestTwoZoneOpeningStructure(unittest.TestCase):
    def test_engine_exposes_m3_flag_default_off(self):
        self.assertIn("@export var two_zone_opening_flow_enabled: bool = false", ENGINE)
        self.assertIn(
            '"two_zone_opening_flow_enabled": two_zone_solver_enabled and two_zone_opening_flow_enabled',
            ENGINE,
        )

    def test_gas_exchange_receives_shared_opening_flow_cache(self):
        self.assertIn('"opening_flow_cache": _opening_flow_cache', ENGINE)
        self.assertIn('var opening_flow_cache: Dictionary = hooks.get("opening_flow_cache", {})', GAS)

    def test_background_exchange_branches_to_two_zone_router(self):
        self.assertIn("if two_zone_opening_flow_enabled and _apply_two_zone_opening_species_exchange(", GAS)
        self.assertIn("func _apply_two_zone_opening_species_exchange(", GAS)
        self.assertIn('flow_state.get("bernoulli_upper_kg_s"', GAS)
        self.assertIn('flow_state.get("bernoulli_lower_kg_s"', GAS)

    def test_upper_path_routes_upper_species_to_resolved_destination_zone(self):
        body = GAS.split("func _move_upper_zone_species(", 1)[1].split("\nfunc ", 1)[0]
        apply_body = GAS.split("func _apply_doorway_species_result(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("target_upper_zone: bool", body)
        self.assertIn("clampf(from_r.co_upper_kg, 0.0, from_r.co_kg) * frac", body)
        self.assertIn('"source_zone": "upper"', body)
        self.assertIn('"destination_zone": "upper" if target_upper_zone else "lower"', body)
        self.assertIn('if source_zone == "upper":', apply_body)
        self.assertIn('_add_delta(co_upper_delta_kg, source_id, -moved_co_kg)', apply_body)
        self.assertIn('if destination_zone == "upper":', apply_body)
        self.assertIn("_add_delta(co_upper_delta_kg, destination_id, moved_co_kg)", apply_body)
        self.assertIn("_add_delta(co2_upper_delta_kg, destination_id, moved_co2_kg)", apply_body)
        self.assertIn("_add_delta(hcn_upper_delta_kg, destination_id, moved_hcn_kg)", apply_body)

    def test_lower_path_routes_lower_species_to_resolved_destination_zone(self):
        body = GAS.split("func _move_lower_zone_species(", 1)[1].split("\nfunc ", 1)[0]
        apply_body = GAS.split("func _apply_doorway_species_result(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("target_upper_zone: bool", body)
        self.assertIn("from_r.co_kg - clampf(from_r.co_upper_kg", body)
        self.assertIn("from_r.co2_kg - clampf(from_r.co2_upper_kg", body)
        self.assertNotIn("_add_delta(co_upper_delta_kg, from_r.id", body)
        self.assertIn('"source_zone": "lower"', body)
        self.assertIn('"destination_zone": "upper" if target_upper_zone else "lower"', body)
        self.assertIn('if destination_zone == "upper":', apply_body)
        self.assertIn("_add_delta(co_upper_delta_kg, destination_id, moved_co_kg)", apply_body)
        self.assertIn("_add_delta(co2_upper_delta_kg, destination_id, moved_co2_kg)", apply_body)
        self.assertIn("_add_delta(hcn_upper_delta_kg, destination_id, moved_hcn_kg)", apply_body)

    def test_opening_segment_route_uses_neutral_plane_and_vertical_floor_context(self):
        self.assertIn("func _resolve_opening_segment_route(", GAS)
        self.assertIn("func _opening_segment_midpoint_m(", GAS)
        self.assertIn("func _height_is_in_upper_zone(", GAS)
        self.assertIn('flow_state.get("neutral_plane_f", 0.5)', GAS)
        self.assertIn("if op.is_vertical:", GAS)
        self.assertIn("room.floor_level_z_m > other_room.floor_level_z_m", GAS)
        self.assertIn("return room.height_m", GAS)
        self.assertIn("LayerInterfaceModel.get_flow_interface_height_m(room, null, 20.0)", GAS)

    def test_opening_flow_telemetry_records_actual_source_and_destination_zones(self):
        body = GAS.split("func _record_two_zone_opening_flow(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("from_upper: bool", body)
        self.assertIn("to_upper: bool", body)
        self.assertIn("from_r.two_zone_opening_upper_out_kg += mass_kg", body)
        self.assertIn("from_r.two_zone_opening_lower_out_kg += mass_kg", body)
        self.assertIn("to_r.two_zone_opening_upper_in_kg += mass_kg", body)
        self.assertIn("to_r.two_zone_opening_lower_in_kg += mass_kg", body)

    def test_exterior_routes_purge_from_upper_zone_when_m3_flag_is_enabled(self):
        self.assertIn("func _purge_upper_species_to_exterior_direct(", GAS)
        self.assertIn("func _queue_upper_species_to_exterior(", GAS)
        self.assertIn("if two_zone_opening_flow_enabled:", GAS)
        self.assertIn("_purge_upper_species_to_exterior_direct(room, air_frac_out, smoke_out_kg)", GAS)
        self.assertIn("_queue_upper_species_to_exterior(", GAS)
        self.assertIn("room.c_exited_kg += co_removed_kg * (12.0 / 28.0)", GAS)

    def test_hvac_receives_m3_flag_and_samples_by_vent_height(self):
        self.assertIn(
            '"two_zone_opening_flow_enabled": two_zone_solver_enabled and two_zone_opening_flow_enabled',
            ENGINE,
        )
        self.assertIn('bool(hooks.get("two_zone_opening_flow_enabled", false))', HVAC)
        self.assertIn("sample_upper_zone: bool = vent_height_m >= hot_layer_m", HVAC)
        self.assertIn("use_two_zone_hvac,", HVAC)
        self.assertIn("sample_upper_zone", HVAC)

    def test_hvac_return_removes_upper_or_lower_species_under_m3_flag(self):
        body = HVAC.split("func _remove_species_from_room(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("two_zone_hvac_enabled: bool = false", body)
        self.assertIn("sample_upper_zone: bool = false", body)
        self.assertIn("if two_zone_hvac_enabled:", body)
        self.assertIn("if sample_upper_zone:", body)
        self.assertIn("room.co_upper_kg = maxf(0.0, co_upper_available_tz - co_upper_removed)", body)
        self.assertIn("room.co2_upper_kg = maxf(0.0, co2_upper_available_tz - co2_upper_removed)", body)
        self.assertIn("room.hcn_upper_kg = maxf(0.0, hcn_upper_available_tz - hcn_upper_removed)", body)
        self.assertIn("room.co2_kg = maxf(0.0, room.co2_kg - co2_lower_removed)", body)

    def test_hvac_supply_injects_species_into_destination_zone_under_m3_flag(self):
        body = HVAC.split("func _supply_air(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("var high_supply: bool = vent_height_m >= hot_layer_m", body)
        self.assertIn("if use_two_zone_hvac:", body)
        self.assertIn("room.co_upper_kg = clampf(room.co_upper_kg + co_added_kg", body)
        self.assertIn("room.co2_upper_kg = clampf(room.co2_upper_kg + co2_added_kg", body)
        self.assertIn("room.hcn_upper_kg = clampf(room.hcn_upper_kg + hcn_added_kg", body)
        self.assertIn("room.o2_upper = clampf(lerpf(room.o2_upper, supply_o2", body)
        self.assertIn("room.o2_lower = clampf(lerpf(room.o2_lower, supply_o2", body)

    def test_room_and_state_export_m3_opening_telemetry(self):
        for field in (
            "two_zone_opening_upper_in_kg",
            "two_zone_opening_upper_out_kg",
            "two_zone_opening_lower_in_kg",
            "two_zone_opening_lower_out_kg",
        ):
            self.assertIn(f"var {field}: float = 0.0", ROOM)
            self.assertIn(f"{field} = 0.0", ROOM)
            self.assertIn(f'"{field}": room.{field}', STATE)
            self.assertIn(f'room_state.get("{field}", 0.0)', CASE_RUNNER)

    def test_validation_cli_can_enable_m3_without_editing_case(self):
        self.assertIn("[switch]$TwoZoneOpeningFlow", RUN_CASE)
        self.assertIn("--validation-two-zone-opening-flow", RUN_CASE)
        self.assertIn("--validation-two-zone-opening-flow", CASE_RUNNER)
        self.assertIn("engine.two_zone_opening_flow_enabled", CASE_RUNNER)
        self.assertIn("-TwoZoneOpeningFlow:$TwoZoneOpeningFlow", COMPARE_RUNNER)


class TestCanonicalPressureStructure(unittest.TestCase):
    def test_engine_exposes_canonical_pressure_default_off(self):
        self.assertIn("@export var phase3_pressure_canonical_enabled: bool = false", ENGINE)
        self.assertIn('"phase3_pressure_canonical_enabled": phase3_pressure_canonical_enabled', ENGINE)

    def test_gas_exchange_can_promote_thermodynamic_pressure_to_overpressure(self):
        self.assertIn("var phase3_pressure_canonical_enabled: bool = false", GAS)
        self.assertIn("var phase3_pressure_component_equalization_enabled: bool = true", GAS)
        self.assertIn('settings.get("phase3_pressure_canonical_enabled"', GAS)
        self.assertIn('settings.get(\n\t\t\t"phase3_pressure_component_equalization_enabled"', GAS)
        self.assertIn("if phase3_pressure_canonical_enabled:", GAS)
        self.assertIn("room.overpressure_pa = room.pressure_pa_therm", GAS)

    def test_canonical_pressure_equalizes_connected_interior_components(self):
        self.assertIn("func _equalize_thermodynamic_pressure_components(", GAS)
        body = GAS.split("func _equalize_thermodynamic_pressure_components(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("op.is_exterior_opening()", body)
        self.assertIn("op.effective_open_fraction() <= 0.001", body)
        self.assertIn("pressure_volume_sum += component_room.pressure_pa_therm * volume_m3", body)
        self.assertIn("component_pressure_pa: float = pressure_volume_sum / volume_sum", body)
        self.assertIn("room_to_update.pressure_pa_therm = component_pressure_pa", body)
        self.assertIn("room_to_update.overpressure_pa = component_pressure_pa", body)

    def test_pressure_venting_skips_legacy_buoyancy_relaxation_when_canonical(self):
        body = GAS.split("func step_pressure_venting(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("var use_canonical_pressure: bool = phase3_thermodynamic_pressure_enabled", body)
        self.assertIn("if use_canonical_pressure:", body)
        self.assertIn("room.overpressure_pa = maxf(0.0, room.pressure_pa_therm)", body)
        self.assertIn("else:", body)
        self.assertIn("room.pressure_pa_therm = room.overpressure_pa", body)
        self.assertIn("if use_canonical_pressure and phase3_pressure_component_equalization_enabled:", body)

    def test_canonical_pressure_does_not_double_count_closed_leakage_for_smoke_purge(self):
        body = GAS.split("func step_pressure_venting(", 1)[1].split("\nfunc ", 1)[0]
        closed_branch = body.split("if op.open_fraction > 0.001:", 1)[1].split("area_m2 *= flow_path_factor", 1)[0]
        self.assertIn("else:", closed_branch)
        self.assertIn("if use_canonical_pressure:", closed_branch)
        self.assertIn("continue", closed_branch)
        self.assertIn("area_m2 = window_leakage_area_m2", closed_branch)

    def test_engine_integrates_canonical_pressure_before_venting(self):
        body = ENGINE.split("func _step_gas_exchange(dt: float) -> void:", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("var use_canonical_pressure: bool = phase3_thermodynamic_pressure_enabled", body)
        self.assertIn("if use_canonical_pressure:", body)
        self.assertLess(
            body.find("if use_canonical_pressure:"),
            body.find("var pressure_result: Dictionary = gas_exchange_system.step_pressure_venting"),
        )
        self.assertIn("if not use_canonical_pressure:", body)

    def test_state_and_case_runner_export_canonical_pressure_flag(self):
        self.assertIn(
            '"phase3_pressure_canonical_enabled": bool(context.get("phase3_pressure_canonical_enabled", false))',
            STATE,
        )
        self.assertIn('"phase3_pressure_canonical_enabled": phase3_thermodynamic_pressure_enabled', ENGINE)
        self.assertIn('state.get("phase3_pressure_canonical_enabled", false)', CASE_RUNNER)
        self.assertIn('phase3_pressure_canonical_enabled"] = 1.0', CASE_RUNNER)
        self.assertIn('room_state.get("pressure_pa_therm", 0.0)', CASE_RUNNER)
        self.assertIn('room_state.get("overpressure_model_pa", 0.0)', CASE_RUNNER)

    def test_validation_cli_can_enable_canonical_pressure_without_editing_case(self):
        self.assertIn("[switch]$CanonicalPressure", RUN_CASE)
        self.assertIn("--validation-canonical-pressure", RUN_CASE)
        self.assertIn("--validation-canonical-pressure", CASE_RUNNER)
        self.assertIn("engine.phase3_thermodynamic_pressure_enabled = true", CASE_RUNNER)
        self.assertIn("engine.phase3_pressure_canonical_enabled", CASE_RUNNER)
        self.assertIn("-CanonicalPressure:$CanonicalPressure", COMPARE_RUNNER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
