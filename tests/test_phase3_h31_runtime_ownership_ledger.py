"""Structural contracts for the passive H3.1 runtime ownership ledger."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
GES = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ZONE = (ROOT / "sim/core/ZoneFireSolver.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
RUN_SCRIPT = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")


class TestH31FlagAndIsolation(unittest.TestCase):
    def test_flag_is_default_off(self):
        self.assertIn(
            "@export var phase3_runtime_ownership_ledger_enabled: bool = false",
            ENGINE,
        )

    def test_projection_diagnostics_use_effective_or_without_mutating_flags(self):
        self.assertIn(
            "return phase3_zone_diagnostics_enabled or phase3_runtime_ownership_ledger_enabled",
            ENGINE,
        )
        self.assertIn(
            "zone_fire_solver.projection_diagnostics_enabled = _phase3_projection_diagnostics_active()",
            ENGINE,
        )
        self.assertNotIn(
            "phase3_zone_diagnostics_enabled = phase3_runtime_ownership_ledger_enabled",
            ENGINE,
        )

    def test_projection_trace_is_reused_not_duplicated(self):
        self.assertIn("zone_fire_solver.get_projection_trace_events()", ENGINE)
        self.assertNotIn("phase3_runtime_ownership", ZONE)
        self.assertEqual(ZONE.count("_projection_trace_records.append(trace_record)"), 1)

    def test_csv_schema_is_opt_in(self):
        self.assertIn("if phase3_runtime_ownership_ledger_enabled:", LOG)
        self.assertIn("func _phase3_runtime_ownership_fields()", LOG)
        self.assertIn("configure_phase3_runtime_ownership_ledger", LOG)


class TestH31OwnershipCoverage(unittest.TestCase):
    def test_real_writer_stages_are_observed(self):
        self.assertIn(
            '_phase3_zone_runtime_record_stage_shared("", "pool_fire")', ENGINE
        )
        for stage in (
            "oxygen_exchange",
            "combustion",
            "thermal",
            "suppression",
            "gas_exchange",
            "hvac",
            "other",
            "reconcile",
        ):
            self.assertIn(
                f'_phase3_zone_runtime_record_stage_shared("{stage}", "{stage}")',
                ENGINE,
            )
        self.assertIn(
            '_phase3_zone_runtime_record_stage_shared("projection_clamp", '
            '"clamp_rooms")',
            ENGINE,
        )

    def test_two_thermal_paths_and_upper_transport_are_distinct(self):
        for mechanism in (
            "canonical_doorway_upper",
            "canonical_doorway_lower",
            "doorway_thermal_counterflow",
        ):
            self.assertIn(f'"{mechanism}"', THERMAL)
        self.assertIn("drain_phase3_runtime_ownership_events", THERMAL)

    def test_parcel_inventory_spans_step_boundaries(self):
        self.assertIn("get_phase3_runtime_parcel_inventory", GES)
        self.assertIn("peek_phase3_runtime_parcel_events", GES)
        self.assertIn('"pre": _phase3_runtime_ownership_parcel_pre', ENGINE)
        self.assertIn('"post": _phase3_runtime_ownership_parcel_post', ENGINE)
        self.assertIn('parcel["mass_residual_kg"]', ENGINE)
        self.assertIn('parcel["energy_residual_kj"]', ENGINE)

    def test_projection_is_compared_to_existing_boundary_ledger(self):
        self.assertIn(
            "event[Phase3ProjectionTraceRecordScript.Field.TOTAL_ENERGY_DELTA_KJ]",
            ENGINE,
        )
        self.assertIn("finish[RuntimeOwnershipState.BOUNDARY_ENERGY_KJ]", ENGINE)
        self.assertIn(
            'room_diag["runtime_owner_projection_boundary_energy_residual_kj_step"]',
            ENGINE,
        )

    def test_structured_projection_and_parcel_ledgers_reach_summary(self):
        self.assertIn(
            'summary["phase3_runtime_ownership"] = _phase3_runtime_ownership_export()',
            ENGINE,
        )
        self.assertIn(
            'summary["phase3_projection_trace"] = '
            "zone_fire_solver.get_projection_trace_events()",
            ENGINE,
        )

    def test_state_builder_only_copies_diagnostics(self):
        self.assertIn("phase3_runtime_ownership_ledger_enabled", STATE)
        block = STATE.split("if phase3_runtime_ownership_ledger_enabled:", 1)[1]
        self.assertNotIn("room.upper_gas_kg =", block)
        self.assertNotIn("room.lower_gas_kg =", block)
        self.assertNotIn("room.upper_energy_kj =", block)
        self.assertNotIn("room.lower_energy_kj =", block)


class TestH31Runner(unittest.TestCase):
    def test_cli_is_wired_through_scene_runner(self):
        self.assertIn("--phase3-runtime-ownership-ledger", RUN_SCRIPT)
        self.assertIn("--phase3-runtime-ownership-ledger", RUNNER)
        self.assertIn("engine.phase3_runtime_ownership_ledger_enabled = true", RUNNER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
