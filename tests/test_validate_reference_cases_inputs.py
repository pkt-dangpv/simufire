import importlib.util
import json
import math
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "simulation" / "validate_reference_cases.py"
SPEC = importlib.util.spec_from_file_location("validate_reference_cases", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
validate_reference_cases = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validate_reference_cases
SPEC.loader.exec_module(validate_reference_cases)


@pytest.mark.parametrize("actual", [math.nan, math.inf, -math.inf])
@pytest.mark.parametrize("contract", [{}, {"minimum": 1.0}, {"maximum": 10.0},
                                      {"expected": 1.0, "tolerance": 0.1}])
def test_nonfinite_measurement_never_passes(actual, contract):
    check = validate_reference_cases.Check("invalid_measurement", actual, **contract)
    assert check.passed() is False
    assert check.to_dict()["pass"] is False
    assert check.required is True


@pytest.mark.parametrize(
    ("actual", "contract", "passed"),
    [
        (None, {"minimum": 1.0}, False),
        (1.0, {"minimum": 1.0}, True),
        (0.999, {"minimum": 1.0}, False),
        (10.0, {"maximum": 10.0}, True),
        (10.001, {"maximum": 10.0}, False),
        (1.125, {"expected": 1.0, "tolerance": 0.125}, True),
        (1.25, {"expected": 1.0, "tolerance": 0.125}, False),
        (2.0, {"maximum": math.inf}, True),
    ],
)
def test_finite_measurements_keep_existing_contract(actual, contract, passed):
    assert validate_reference_cases.Check("measurement", actual, **contract).passed() is passed


@pytest.mark.parametrize("raw", ["267.527", "267.527(CO:238.6332 HCN:26.4768 O2:2.4167 Q:0.0000)"])
def test_log_parser_reads_fed_total_not_its_components(tmp_path, raw):
    log = tmp_path / "fed.log"
    log.write_text(f"TIME=900.0 s\nROOM 2(Bedroom) | HRR=0.0 | FED={raw} | O2u=0.08\n",
                   encoding="utf-8")
    samples = validate_reference_cases._parse_simufire_log(log, room_id=2)
    assert len(samples) == 1
    assert samples[0]["fed"] == 267.527
    assert samples[0]["o2_upper"] == 0.08


@pytest.mark.parametrize("raw", [None, "invalid(CO:2.0)", "NaN(CO:2.0)", "inf(CO:2.0)"])
def test_missing_or_invalid_fed_cannot_pass_lethal_guard(tmp_path, raw):
    log = tmp_path / "fed.log"
    fed = "" if raw is None else f" | FED={raw}"
    log.write_text(f"TIME=900.0 s\nROOM 2(Bedroom) | HRR=0.0{fed}\n", encoding="utf-8")
    sample = validate_reference_cases._parse_simufire_log(log, room_id=2)[0]
    assert not validate_reference_cases.Check("lethal_guard", sample["fed"], minimum=1.0).passed()


def test_bedroom_fed_guard_uses_the_measured_total():
    checks = validate_reference_cases.build_cfast_bedroom_closed_door_checks()
    check = next(check for check in checks if check.name == "cfast_bed_fed_lethal")
    report = json.loads(
        (validate_reference_cases.REPORTS_DIR / "cfast_bedroom_closed_door.json")
        .read_text(encoding="utf-8-sig")
    )
    assert math.isfinite(check.actual)
    assert check.actual == round(report["metrics"]["room_2_max_fed"], 3)
    assert check.required is True
    assert check.minimum == 1.0
    assert check.passed() is (check.actual >= check.minimum)


def test_runtime_corpus_covers_every_cfast_builder():
    source = SCRIPT.read_text(encoding="utf-8")
    for case_name in validate_reference_cases.CFAST_RUNTIME_CASES:
        assert f"def build_{case_name}_checks()" in source or case_name == "cfast_r0_window_360"


def test_missing_runtime_input_is_fail_closed(tmp_path, monkeypatch):
    reports = tmp_path / "reports"
    reports.mkdir()
    sentinel = reports / "reference_checks.json"
    sentinel.write_text('{"sentinel": true}', encoding="utf-8")
    monkeypatch.setattr(validate_reference_cases, "REPORTS_DIR", reports)

    assert validate_reference_cases.main([]) == 2
    assert sentinel.read_text(encoding="utf-8") == '{"sentinel": true}'


def test_complete_runtime_input_inventory(tmp_path, monkeypatch):
    reports = tmp_path / "reports"
    reports.mkdir()
    monkeypatch.setattr(validate_reference_cases, "REPORTS_DIR", reports)
    for case_name in validate_reference_cases.REFERENCE_RUNTIME_CASES:
        (reports / f"{case_name}.json").write_text("{}", encoding="utf-8")
    for case_name in validate_reference_cases.CFAST_RUNTIME_CASES:
        (reports / f"{case_name}.log").write_text("TIME=0\n", encoding="utf-8")

    assert validate_reference_cases._missing_runtime_inputs() == []


def test_list_runtime_cases_is_machine_readable(capsys):
    assert validate_reference_cases.main(["--list-runtime-cases"]) == 0
    assert capsys.readouterr().out.splitlines() == list(
        validate_reference_cases.REFERENCE_RUNTIME_CASES
    )
