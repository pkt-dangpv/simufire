from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "simulation" / "validate_reference_cases.py"
SPEC = importlib.util.spec_from_file_location("reference_required_policy_validator", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
validator = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validator
SPEC.loader.exec_module(validator)


def _write_report(
    reports: Path,
    case: str,
    check: str,
    passed: bool,
) -> None:
    reports.mkdir(parents=True, exist_ok=True)
    (reports / f"{case}.json").write_text(
        json.dumps(
            {
                "baseline": {
                    "checks": {
                        check: {
                            "actual": 1.0,
                            "pass": passed,
                            "rule": {"expected": 1.0, "tolerance": 0.1},
                        }
                    }
                }
            }
        ),
        encoding="utf-8",
    )


@pytest.mark.parametrize(
    ("case", "check", "expected_required"),
    [
        (
            "v3_hallway_fed_exposure",
            "time_room_1_fed_above_0_1_s",
            True,
        ),
        (
            "two_storey_smoke",
            "time_room_8_smoke_start_s",
            False,
        ),
    ],
)
def test_required_policy_is_independent_of_pass(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    case: str,
    check: str,
    expected_required: bool,
) -> None:
    reports = tmp_path / "reports"
    monkeypatch.setattr(validator, "REPORTS_DIR", reports)

    observed = []
    for passed in (False, True):
        _write_report(reports, case, check, passed)
        built = validator._build_checks_from_baseline_json(case)
        assert len(built) == 1
        observed.append(built[0].required)

    assert observed == [expected_required, expected_required]


def test_required_policy_fails_closed_for_unknown_check(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    reports = tmp_path / "reports"
    monkeypatch.setattr(validator, "REPORTS_DIR", reports)
    _write_report(reports, "v3_hallway_fed_exposure", "unknown_contract", True)

    with pytest.raises(ValueError, match="missing explicit required policy"):
        validator._build_checks_from_baseline_json("v3_hallway_fed_exposure")


def test_required_policy_covers_every_baseline_check() -> None:
    builders = (
        validator.build_physics_fundamentals_checks,
        validator.build_single_room_fire_checks,
        validator.build_smoke_transport_checks,
        validator.build_tenability_fed_checks,
        validator.build_fire_dynamics_checks,
        validator.build_gie_tactical_checks,
        validator.build_reference_benchmark_checks,
    )
    checks = [check for builder in builders for check in builder()]
    indexed = {check.name: check for check in checks}

    assert len(checks) == 239
    assert len(indexed) == 239
    assert set(indexed) == set(validator._BASELINE_REQUIRED_POLICY)
    assert {
        name: check.required for name, check in indexed.items()
    } == validator._BASELINE_REQUIRED_POLICY
