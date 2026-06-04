"""Unit and structural tests for the Pre-M1 legacy/two-zone comparison contract."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS_DIR = ROOT / "scripts" / "simulation"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import legacy_two_zone_compare as compare  # noqa: E402

FIXTURE_ROOT = ROOT / "tests" / "tmp_legacy_two_zone"
FIXTURE_ROOT.mkdir(parents=True, exist_ok=True)


def _fixture_dir(name: str) -> Path:
    path = FIXTURE_ROOT / name
    path.mkdir(parents=True, exist_ok=True)
    return path


def _manifest(required: bool = True) -> dict:
    return {
        "format_version": 1,
        "cases": {
            "case_a": {
                "metrics": {
                    "metric_a": {
                        "required": required,
                        "abs_tolerance": 1.0,
                    }
                }
            }
        },
    }


def _reference() -> dict:
    return {
        "format_version": 1,
        "engine_mode": "legacy",
        "source_commit": "abc",
        "cases": {
            "case_a": {
                "sim_time_s": 1.0,
                "metrics": {"metric_a": 10.0},
            }
        },
    }


def _write_report(directory: Path, value: float, mode: str = "two-zone") -> None:
    report = {
        "case": "case_a",
        "engine_mode": mode,
        "metrics": {"metric_a": value},
        "baseline": {},
    }
    (directory / "case_a.json").write_text(json.dumps(report), encoding="utf-8")


class TestComparisonArithmetic(unittest.TestCase):

    def test_required_metric_within_tolerance_passes(self):
        path = _fixture_dir("required_pass")
        _write_report(path, 10.5)
        result = compare.compare_reports(_manifest(), _reference(), path, "two-zone")
        self.assertTrue(result["all_required_pass"])

    def test_required_metric_outside_tolerance_fails(self):
        path = _fixture_dir("required_fail")
        _write_report(path, 12.0)
        result = compare.compare_reports(_manifest(), _reference(), path, "two-zone")
        self.assertFalse(result["all_required_pass"])
        self.assertEqual(result["failed_required_count"], 1)

    def test_non_gating_delta_does_not_fail_contract(self):
        path = _fixture_dir("non_gating")
        _write_report(path, 20.0)
        result = compare.compare_reports(_manifest(required=False), _reference(), path, "two-zone")
        self.assertTrue(result["all_required_pass"])
        self.assertEqual(result["failed_non_gating_count"], 1)

    def test_wrong_engine_mode_is_contract_error(self):
        path = _fixture_dir("wrong_mode")
        _write_report(path, 10.0, mode="legacy")
        result = compare.compare_reports(_manifest(), _reference(), path, "two-zone")
        self.assertFalse(result["all_required_pass"])
        self.assertTrue(result["contract_errors"])

    def test_max_abs_value_checks_candidate_not_delta(self):
        result = compare._evaluate_metric(0.001, 0.015, {"required": True, "max_abs_value": 0.02})
        self.assertTrue(result["pass"])
        result = compare._evaluate_metric(0.001, 0.025, {"required": True, "max_abs_value": 0.02})
        self.assertFalse(result["pass"])


class TestFreezeReference(unittest.TestCase):

    def test_freeze_rejects_non_legacy_report(self):
        path = _fixture_dir("freeze_reject")
        _write_report(path, 10.0, mode="two-zone")
        with self.assertRaises(compare.ContractError):
            compare.freeze_reference(_manifest(), path, path / "reference.json")

    def test_freeze_writes_valid_reference(self):
        path = _fixture_dir("freeze_pass")
        _write_report(path, 10.0, mode="legacy")
        reference = compare.freeze_reference(_manifest(), path, path / "reference.json")
        self.assertEqual(compare.validate_reference(_manifest(), reference), [])


class TestModeContractStructure(unittest.TestCase):

    def test_engine_flag_is_exported_and_default_off(self):
        source = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
        self.assertIn("@export var two_zone_solver_enabled: bool = false", source)

    def test_case_runner_exports_mode_metadata(self):
        source = (ROOT / "sim" / "validation" / "CaseRunner.gd").read_text(encoding="utf-8")
        self.assertIn('"engine_mode": _engine_mode', source)
        self.assertIn("--validation-engine-mode=", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
