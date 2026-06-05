"""Structural and arithmetic checks for the M1 canonical two-zone energy core."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ROOM = (ROOT / "sim" / "building" / "RoomModel.gd").read_text(encoding="utf-8")
ZONE = (ROOT / "sim" / "core" / "ZoneFireSolver.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim" / "core" / "ThermalSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
RUN_CASE = (ROOT / "sim" / "validation" / "run_case.ps1").read_text(encoding="utf-8")
COMPARE_RUNNER = (
    ROOT / "sim" / "validation" / "run_legacy_two_zone_compare.ps1"
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
