import importlib.util
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "simulation" / "validate_reference_cases.py"
SPEC = importlib.util.spec_from_file_location("validate_reference_cases", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
validate_reference_cases = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = validate_reference_cases
SPEC.loader.exec_module(validate_reference_cases)


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
