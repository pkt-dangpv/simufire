"""Structural checks for passive Phase 3+ F0 two-zone diagnostics."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim" / "core" / "ThermalSystem.gd").read_text(encoding="utf-8")
ROOM = (ROOT / "sim" / "building" / "RoomModel.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim" / "core" / "SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools" / "run_scenario_headless.gd").read_text(encoding="utf-8")
RUN_SCRIPT = (ROOT / "scripts" / "run_scenario.py").read_text(encoding="utf-8")


class TestPhase3ZoneDiagnosticsStructure(unittest.TestCase):
    def test_feature_is_default_off_and_propagated_passively(self):
        self.assertIn(
            "@export var phase3_zone_diagnostics_enabled: bool = false",
            ENGINE,
        )
        self.assertIn(
            '"phase3_zone_diagnostics_enabled": phase3_zone_diagnostics_enabled',
            ENGINE,
        )
        self.assertIn(
            "log_writer.configure_phase3_zone_diagnostics(phase3_zone_diagnostics_enabled)",
            ENGINE,
        )
        self.assertIn("var phase3_zone_diagnostics_enabled: bool = false", THERMAL)

    def test_csv_schema_is_extended_only_when_enabled(self):
        self.assertIn("if phase3_zone_diagnostics_enabled:", LOG)
        self.assertIn("func configure_phase3_zone_diagnostics(is_enabled: bool)", LOG)
        for field in (
            "upper_volume_m3_eos",
            "lower_volume_m3_eos",
            "volume_closure_error_m3",
            "two_zone_boundary_mass_kg_step",
            "plume_entrained_kg_step",
            "reconcile_mass_delta_kg_step",
            "attribution_mass_residual_kg_step",
        ):
            self.assertIn(field, LOG)

    def test_engine_attributes_zone_mass_and_energy_by_stage(self):
        for stage in (
            "oxygen_exchange",
            "combustion",
            "thermal",
            "suppression",
            "gas_exchange",
            "hvac",
            "other",
            "reconcile",
            "projection_clamp",
        ):
            self.assertIn(f'_phase3_zone_diag_record_stage("{stage}")', ENGINE)
        self.assertIn("func _phase3_zone_diag_begin_step()", ENGINE)
        self.assertIn("func _phase3_zone_diag_export()", ENGINE)

    def test_plume_counter_is_diagnostic_only(self):
        self.assertIn("var phase3_diag_plume_entrained_kg_total: float = 0.0", ROOM)
        self.assertIn("if phase3_zone_diagnostics_enabled:", THERMAL)
        self.assertIn("room.phase3_diag_plume_entrained_kg_total += moved_mass_kg", THERMAL)

    def test_state_builder_computes_eos_without_mutating_room(self):
        self.assertIn("var upper_density_kg_m3: float = 1.2 * ambient_k / upper_k", STATE)
        self.assertIn("var lower_density_kg_m3: float = 1.2 * ambient_k / lower_k", STATE)
        self.assertIn('room_state["volume_closure_error_m3"]', STATE)
        diagnostics_body = STATE.split("if phase3_zone_diagnostics_enabled:", 1)[1]
        self.assertNotIn("room.upper_gas_kg =", diagnostics_body)
        self.assertNotIn("room.lower_gas_kg =", diagnostics_body)

    def test_headless_runner_supports_opt_in_without_case_edits(self):
        self.assertIn("--phase3-zone-diagnostics", RUNNER)
        self.assertIn("engine.phase3_zone_diagnostics_enabled = true", RUNNER)
        self.assertIn('"--phase3-zone-diagnostics"', RUN_SCRIPT)


if __name__ == "__main__":
    unittest.main(verbosity=2)
