"""Structural and arithmetic checks for the M1 canonical two-zone energy core."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ROOM = (ROOT / "sim" / "building" / "RoomModel.gd").read_text(encoding="utf-8")
ZONE = (ROOT / "sim" / "core" / "ZoneFireSolver.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim" / "core" / "ThermalSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
CASE_RUNNER = (ROOT / "sim" / "validation" / "CaseRunner.gd").read_text(encoding="utf-8")
RUN_CASE = (ROOT / "sim" / "validation" / "run_case.ps1").read_text(encoding="utf-8")
COMPARE_RUNNER = (
    ROOT / "sim" / "validation" / "run_legacy_two_zone_compare.ps1"
).read_text(encoding="utf-8")
STAIRWELL_CASE = (
    ROOT / "sim" / "validation" / "cases" / "cfast_two_floor_stairwell.json"
).read_text(encoding="utf-8")


class TestTwoZoneArithmetic(unittest.TestCase):
    def test_lower_to_upper_transfer_conserves_mass_and_energy(self):
        upper_mass, lower_mass = 4.0, 36.0
        upper_energy, lower_energy = 800.0, 180.0
        moved_mass = 6.0
        moved_energy = moved_mass * lower_energy / lower_mass

        before_mass = upper_mass + lower_mass
        before_energy = upper_energy + lower_energy
        upper_mass += moved_mass
        lower_mass -= moved_mass
        upper_energy += moved_energy
        lower_energy -= moved_energy

        self.assertAlmostEqual(upper_mass + lower_mass, before_mass)
        self.assertAlmostEqual(upper_energy + lower_energy, before_energy)

    def test_boundary_outflow_removes_proportional_lower_energy(self):
        lower_mass, lower_energy = 40.0, 200.0
        target_mass = 30.0
        lower_energy *= target_mass / lower_mass
        self.assertAlmostEqual(lower_energy, 150.0)

    def test_boundary_inflow_arrives_at_ambient(self):
        lower_mass, lower_energy = 30.0, 150.0
        target_mass = 40.0
        lower_mass = target_mass
        self.assertAlmostEqual(lower_energy / lower_mass, 3.75)


class TestTwoZoneStructure(unittest.TestCase):
    def test_room_has_explicit_lower_mass_and_energy(self):
        self.assertIn("var lower_gas_kg: float = 0.0", ROOM)
        self.assertIn("var lower_energy_kj: float = 0.0", ROOM)

    def test_room_reuses_existing_upper_state(self):
        self.assertNotIn("var upper_zone_mass_kg:", ROOM)
        self.assertIn('"upper_zone_mass_kg": room.upper_gas_kg', STATE)

    def test_room_reset_initializes_lower_zone(self):
        self.assertIn("lower_gas_kg = maxf(0.0, volume_m3() * 1.2)", ROOM)
        self.assertIn("lower_energy_kj = 0.0", ROOM)
        self.assertIn("two_zone_boundary_mass_kg = 0.0", ROOM)
        self.assertIn("two_zone_boundary_energy_kj = 0.0", ROOM)

    def test_zone_solver_has_conservative_transfer(self):
        self.assertIn("func transfer_lower_to_upper(", ZONE)
        self.assertIn("room.lower_gas_kg - moved_mass_kg", ZONE)
        self.assertIn("room.upper_gas_kg += moved_mass_kg", ZONE)
        self.assertIn("room.lower_energy_kj - moved_energy_kj", ZONE)
        self.assertIn("room.upper_energy_kj += moved_energy_kj", ZONE)

    def test_zone_solver_projects_both_temperatures_from_energy(self):
        self.assertIn("func project_room_state(", ZONE)
        self.assertIn("room.lower_energy_kj", ZONE)
        self.assertIn("room.upper_energy_kj", ZONE)
        self.assertIn("room.thermal_layer_m = clampf(", ZONE)

    def test_thermal_mode_uses_plume_ode(self):
        self.assertIn("func _step_two_zone_plume_entrainment(", THERMAL)
        self.assertIn("_zone_fire_solver.transfer_lower_to_upper(", THERMAL)
        self.assertIn("if two_zone_solver_enabled:", THERMAL)

    def test_two_zone_interface_skips_legacy_plume_depth_projection(self):
        marker = "func effective_hot_layer_height_m(room: RoomModel) -> float:"
        body = THERMAL.split(marker, 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("if two_zone_solver_enabled:", body)
        self.assertIn("return clampf(room.thermal_layer_m", body)

    def test_engine_connects_flag_to_thermal_and_zone_solvers(self):
        self.assertIn("zone_fire_solver.two_zone_energy_enabled = two_zone_solver_enabled", ENGINE)
        self.assertIn('"two_zone_solver_enabled": two_zone_solver_enabled', ENGINE)
        self.assertIn("thermal_system.reconcile_two_zone_building(building, dt)", ENGINE)

    def test_state_exports_m1_telemetry(self):
        for field in (
            "upper_zone_mass_kg",
            "lower_zone_mass_kg",
            "upper_zone_energy_kj",
            "lower_zone_energy_kj",
            "zone_total_mass_kg",
            "zone_total_energy_kj",
            "two_zone_boundary_mass_kg",
            "two_zone_boundary_energy_kj",
        ):
            self.assertIn(f'"{field}"', STATE)

    def test_comparison_runner_can_preserve_candidate_baseline_failures(self):
        self.assertIn("[switch]$AllowBaselineFailure", RUN_CASE)
        self.assertIn("if ($AllowBaselineFailure)", RUN_CASE)
        self.assertIn("-AllowBaselineFailure:$AllowBaselineFailure", COMPARE_RUNNER)
        self.assertIn('Invoke-ModeCases $CandidateMode $true', COMPARE_RUNNER)
        self.assertIn("[switch]$AllowContractFailure", COMPARE_RUNNER)

    def test_two_zone_v1_validation_profile_is_stable_shortcut(self):
        self.assertIn("[switch]$TwoZoneV1", RUN_CASE)
        self.assertIn("TwoZoneV1 requiere EngineMode two-zone", RUN_CASE)
        self.assertIn('$EngineMode = "two-zone"', RUN_CASE)
        self.assertIn("--validation-two-zone-v1", RUN_CASE)
        self.assertIn("$TwoZoneOpeningFlow = $true", RUN_CASE)
        self.assertIn("$CanonicalPressure = $true", RUN_CASE)
        self.assertIn("[switch]$TwoZoneV1", COMPARE_RUNNER)
        self.assertIn("TwoZoneV1 requiere CandidateMode two-zone", COMPARE_RUNNER)
        self.assertIn("-TwoZoneV1:$($TwoZoneV1 -and $Mode -eq \"two-zone\")", COMPARE_RUNNER)
        self.assertIn("--validation-two-zone-v1", CASE_RUNNER)
        self.assertIn("func _configure_validation_two_zone_v1_profile() -> bool:", CASE_RUNNER)
        self.assertIn('_cli_args["validation_engine_mode"] = "two-zone"', CASE_RUNNER)
        self.assertIn('_cli_args["validation_two_zone_opening_flow"] = true', CASE_RUNNER)
        self.assertIn('_cli_args["validation_canonical_pressure"] = true', CASE_RUNNER)
        self.assertIn('"two_zone_v1_profile": _two_zone_v1_profile', CASE_RUNNER)


class TestStairwellHeatBridgeStructure(unittest.TestCase):
    def test_stairwell_heat_bridge_is_opt_in(self):
        self.assertIn("@export var phase3_stairwell_heat_bridge_enabled: bool = false", ENGINE)
        self.assertIn("@export var phase3_stairwell_heat_bridge_target_max_temp_c: float = 120.0", ENGINE)
        self.assertIn("@export var two_zone_convective_heat_multiplier: float = 1.0", ENGINE)
        self.assertIn("var phase3_stairwell_heat_bridge_enabled: bool = false", THERMAL)
        self.assertIn("var phase3_stairwell_heat_bridge_target_max_temp_c: float = 120.0", THERMAL)
        self.assertIn("var two_zone_convective_heat_multiplier: float = 1.0", THERMAL)
        self.assertIn(
            '"phase3_stairwell_heat_bridge_enabled": phase3_stairwell_heat_bridge_enabled',
            ENGINE,
        )
        self.assertIn(
            '"phase3_stairwell_heat_bridge_target_max_temp_c": phase3_stairwell_heat_bridge_target_max_temp_c',
            ENGINE,
        )
        self.assertIn(
            '"two_zone_convective_heat_multiplier": two_zone_convective_heat_multiplier',
            ENGINE,
        )
        self.assertIn("func _apply_phase3_stairwell_temperature_cap(", ENGINE)
        self.assertIn('room.kind != "escalera"', ENGINE)
        self.assertIn(
            'settings.get("phase3_stairwell_heat_bridge_enabled"',
            THERMAL,
        )
        self.assertIn(
            '"phase3_stairwell_heat_bridge_target_max_temp_c"',
            THERMAL,
        )
        self.assertIn(
            '"two_zone_convective_heat_multiplier"',
            THERMAL,
        )
        self.assertIn(
            "two_zone_solver_enabled and two_zone_convective_heat_multiplier > 0.0",
            THERMAL,
        )

    def test_stairwell_heat_bridge_moves_energy_without_species(self):
        self.assertIn("func _apply_stairwell_heat_bridge(", THERMAL)
        body = THERMAL.split("func _apply_stairwell_heat_bridge(", 1)[1].split("\nfunc ", 1)[0]
        self.assertIn("not op.is_vertical and op.type != OpeningModel.Type.HOLE", body)
        self.assertIn('room_a.kind == "escalera" or room_b.kind == "escalera"', body)
        self.assertIn("source.temp_upper_c - 0.1", body)
        self.assertIn("phase3_stairwell_heat_bridge_target_max_temp_c", body)
        self.assertIn("source.upper_energy_kj = maxf(0.0, source.upper_energy_kj - energy_moved_kj)", body)
        self.assertIn("target.upper_energy_kj = maxf(0.0, target.upper_energy_kj + energy_moved_kj)", body)
        self.assertIn("cold_energy_cap_kj", THERMAL)
        self.assertIn("cold_room.upper_gas_kg + gas_moved_kg", THERMAL)
        self.assertIn("radiation_energy_cap_kj", THERMAL)
        self.assertIn("stairwell_wall_cap_c", THERMAL)
        self.assertNotIn("_transfer_hot_gas_contaminants", body)
        self.assertNotIn("_delta_co_kg", body)

    def test_stairwell_case_enables_heat_bridge_by_override(self):
        self.assertIn('"phase3_stairwell_heat_bridge_enabled": true', STAIRWELL_CASE)
        self.assertIn('"phase3_stairwell_heat_bridge_kg_s_m2"', STAIRWELL_CASE)
        self.assertIn('"phase3_stairwell_heat_bridge_vertical_multiplier"', STAIRWELL_CASE)
        self.assertIn('"phase3_stairwell_heat_bridge_target_max_temp_c": 120.0', STAIRWELL_CASE)
        self.assertIn('"two_zone_convective_heat_multiplier": 1.18', STAIRWELL_CASE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
