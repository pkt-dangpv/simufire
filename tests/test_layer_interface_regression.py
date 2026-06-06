"""Tests for the LayerInterfaceModel regression audit helper."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = ROOT / "scripts" / "simulation" / "compare_layer_interface_regression.py"

spec = importlib.util.spec_from_file_location("compare_layer_interface_regression", SCRIPT_PATH)
assert spec is not None and spec.loader is not None
regression = importlib.util.module_from_spec(spec)
spec.loader.exec_module(regression)


class TestLayerInterfaceRegressionScope(unittest.TestCase):
    def test_default_cases_cover_minimal_cfast_hallway_and_remote(self):
        self.assertEqual(
            regression.DEFAULT_CASES,
            [
                "layer_interface_single_room_window",
                "cfast_r0_window_360",
                "living_room_hallway",
                "v4_co_remote_rooms",
            ],
        )

    def test_audit_fields_include_physics_and_layer_exports(self):
        for field in (
            "hrr_kw",
            "o2",
            "o2_upper",
            "o2_lower",
            "co_ppm",
            "co2_ppm",
            "hcn_ppm",
            "visible_smoke_layer_m",
            "thermal_layer_m",
            "flow_interface_m",
            "layer_150c_m",
            "visibility_m",
            "fed",
            "temp_upper_c",
            "temp_lower_c",
        ):
            self.assertIn(field, regression.AUDIT_FIELDS)


class TestLayerInterfaceRegressionMath(unittest.TestCase):
    def test_csv_series_metrics_include_requested_deltas(self):
        before_rows = [
            {"time_s": 0.0, "hrr_kw": 0.0},
            {"time_s": 60.0, "hrr_kw": 100.0},
            {"time_s": 120.0, "hrr_kw": 200.0},
            {"time_s": 180.0, "hrr_kw": 100.0},
        ]
        after_rows = [
            {"time_s": 0.0, "hrr_kw": 0.0},
            {"time_s": 60.0, "hrr_kw": 105.0},
            {"time_s": 120.0, "hrr_kw": 190.0},
            {"time_s": 180.0, "hrr_kw": 110.0},
        ]

        metric = regression.compare_csv_series(before_rows, after_rows, "hrr_kw")

        self.assertIsNotNone(metric)
        self.assertAlmostEqual(metric["max_abs_delta"], 10.0)
        self.assertAlmostEqual(metric["delta_at_60s"], 5.0)
        self.assertAlmostEqual(metric["delta_at_120s"], -10.0)
        self.assertAlmostEqual(metric["delta_at_180s"], 10.0)
        self.assertEqual(metric["peak_value_before"], 200.0)
        self.assertEqual(metric["peak_value_after"], 190.0)
        self.assertEqual(metric["peak_time_before"], 120.0)
        self.assertEqual(metric["peak_time_after"], 120.0)

    def test_warning_thresholds_match_audit_contract(self):
        hrr_warning = regression.warning_for_metric(
            "case",
            "0",
            "hrr_kw",
            {"max_abs_delta": 5.0, "max_rel_delta": 0.051},
        )
        o2_warning = regression.warning_for_metric(
            "case",
            "0",
            "o2",
            {"max_abs_delta": 0.011, "max_rel_delta": 0.0},
        )
        visibility_warning = regression.warning_for_metric(
            "case",
            "0",
            "visibility_m",
            {"max_abs_delta": 1.0, "max_rel_delta": 0.151},
        )

        self.assertIsNotNone(hrr_warning)
        self.assertEqual(hrr_warning["threshold"], 0.05)
        self.assertIsNotNone(o2_warning)
        self.assertEqual(o2_warning["threshold"], 0.01)
        self.assertIsNotNone(visibility_warning)
        self.assertEqual(visibility_warning["threshold"], 0.15)

    def test_flow_thermal_divergence_warning_requires_duration(self):
        rows = []
        for t in range(0, 70, 10):
            rows.append(
                {
                    "time_s": float(t),
                    "room_id": 0.0,
                    "hrr_kw": 150.0,
                    "flow_interface_m": 0.5,
                    "thermal_layer_m": 1.7,
                }
            )

        warnings = regression.flow_thermal_divergence_warnings("case", rows)

        self.assertEqual(len(warnings), 1)
        self.assertEqual(warnings[0]["field"], "flow_interface_m")
        self.assertGreater(warnings[0]["value"], 30.0)


class TestLayerInterfaceRegressionStructuralChecks(unittest.TestCase):
    def test_structural_checks_cover_special_failure_criteria(self):
        checks = regression.run_structural_checks(ROOT)
        names = {check["name"] for check in checks}

        for name in (
            "gas_exchange_zone_routing_uses_flow_interface",
            "visibility_uses_visible_smoke_layer",
            "fed_thermal_exposure_uses_thermal_layer_or_150c",
            "no_local_neutral_f_reintroduced",
        ):
            self.assertIn(name, names)

    def test_markdown_report_contains_required_sections(self):
        audit = {
            "conclusion": "PASS_WITH_WARNINGS",
            "generated_at_utc": "2026-06-06T00:00:00+00:00",
            "case_results": [
                {
                    "case": "layer_interface_single_room_window",
                    "artifact_notes": [],
                    "warnings": [],
                    "has_csv_comparison": True,
                    "has_report_comparison": True,
                    "rooms": {},
                }
            ],
            "structural_checks": [],
        }

        markdown = regression.render_markdown(audit)

        for heading in (
            "Resumen ejecutivo",
            "Casos ejecutados / comparados",
            "Warnings detectados",
            "Diferencias principales",
            "Checks estructurales",
            "Conclusión",
            "Recomendaciones siguientes",
        ):
            self.assertIn(heading, markdown)


if __name__ == "__main__":
    unittest.main()
