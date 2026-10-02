"""Checkout-independent reference provenance, without masking content edits."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts/simulation/validate_reference_cases.py"
REPORT = ROOT / "sim/validation/reports/reference_checks.json"
HISTORICAL_REV = "35d0f978"


def _load_validator():
    name = "validate_reference_cases_portability_contract"
    spec = importlib.util.spec_from_file_location(name, VALIDATOR)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _artifacts(report: dict) -> dict[str, dict]:
    artifacts = {}
    for check in report["checks"]:
        for row in check.get("provenance", {}).get("artifacts", []):
            previous = artifacts.setdefault(row["path"], row)
            assert previous == row, row["path"]
    return artifacts


def test_text_provenance_ignores_only_checkout_line_endings(tmp_path: Path) -> None:
    validator = _load_validator()
    path = tmp_path / "evidence.csv"
    path.write_bytes(b"time,co\n0,1\n1,2\n")
    lf = validator._artifact_record(path)
    path.write_bytes(b"time,co\r\n0,1\r\n1,2\r\n")
    validator._ARTIFACT_CACHE.clear()
    assert validator._artifact_record(path) == lf

    path.write_bytes(b"time,co\r\n0,1\r\n1,3\r\n")
    validator._ARTIFACT_CACHE.clear()
    assert validator._artifact_record(path)["sha256"] != lf["sha256"]


def test_binary_provenance_remains_byte_exact(tmp_path: Path) -> None:
    validator = _load_validator()
    path = tmp_path / "evidence.pdf"
    payload = b"%PDF-1.7\r\n\x00binary\r\n"
    path.write_bytes(payload)
    row = validator._artifact_record(path)
    assert row["bytes"] == len(payload)
    assert row["sha256"] == hashlib.sha256(payload).hexdigest()


def test_reference_paths_do_not_embed_checkout_location() -> None:
    validator = _load_validator()
    references = validator._reference_paths()
    paths = [
        value
        for item in references.values()
        for value in (item if isinstance(item, list) else [item])
    ]
    assert len(paths) == 7
    assert all(path.startswith("sim/validation/") for path in paths)
    assert all(not Path(path).is_absolute() for path in paths)


def test_historical_38_artifact_changes_are_exactly_lf_crlf() -> None:
    old_text = subprocess.run(
        ["git", "show", f"{HISTORICAL_REV}:sim/validation/reports/reference_checks.json"],
        cwd=ROOT,
        capture_output=True,
        check=True,
    ).stdout
    old = _artifacts(json.loads(old_text))
    new = _artifacts(json.loads(REPORT.read_text(encoding="utf-8")))
    assert old.keys() == new.keys()
    changed = [path for path in old if old[path] != new[path]]
    assert len(changed) == 38

    for path in changed:
        raw = (ROOT / path).read_bytes()
        lf = raw.replace(b"\r\n", b"\n")
        crlf = lf.replace(b"\n", b"\r\n")
        assert b"\r" not in lf, path
        assert old[path]["bytes"] == len(crlf), path
        assert old[path]["sha256"] == hashlib.sha256(crlf).hexdigest(), path
        assert new[path]["bytes"] == len(lf), path
        assert new[path]["sha256"] == hashlib.sha256(lf).hexdigest(), path
        assert len(crlf) - len(lf) == lf.count(b"\n"), path


def test_historical_38_artifacts_have_unchanged_committed_content() -> None:
    """The 38 hash changes are EOL only: the committed blob is the LF form."""
    old = _artifacts(json.loads(subprocess.run(
        ["git", "show", f"{HISTORICAL_REV}:sim/validation/reports/reference_checks.json"],
        cwd=ROOT, capture_output=True, check=True,
    ).stdout))
    new = _artifacts(json.loads(REPORT.read_text(encoding="utf-8")))
    changed = [path for path in old if old[path] != new[path]]
    assert len(changed) == 38
    for path in changed:
        blob = subprocess.run(
            ["git", "show", f"{HISTORICAL_REV}:{path}"],
            cwd=ROOT, capture_output=True, check=True,
        ).stdout
        assert b"\r" not in blob, path
        assert new[path]["sha256"] == hashlib.sha256(blob).hexdigest(), path
        crlf = blob.replace(b"\n", b"\r\n")
        assert old[path]["sha256"] == hashlib.sha256(crlf).hexdigest(), path


def test_bare_carriage_return_is_content_not_line_ending(tmp_path: Path) -> None:
    validator = _load_validator()
    path = tmp_path / "evidence.csv"
    path.write_bytes(b"time,co\n0,1\n")
    lf = validator._artifact_record(path)
    path.write_bytes(b"time,co\n0,\r1\n")
    validator._ARTIFACT_CACHE.clear()
    assert validator._artifact_record(path)["sha256"] != lf["sha256"]


GAP_EVIDENCE = ROOT / "sim/validation/evidence/p1r8_gap_disposition_evidence.json"
REAL_GAP = "cfast_2r_hall_rmse_o2"


def _crlf_checkout_of_gap(tmp_path: Path, monkeypatch):
    """Copy one real gap's evidence into a CRLF checkout rooted at tmp_path."""
    validator = _load_validator()
    registry = json.loads(GAP_EVIDENCE.read_text(encoding="utf-8"))["checks"]
    row = registry[REAL_GAP]
    for artifact in row["source_artifacts"]:
        payload = (ROOT / artifact["path"]).read_bytes()
        assert b"\r\n" not in payload, artifact["path"]
        target = tmp_path / artifact["path"]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload.replace(b"\n", b"\r\n"))
    monkeypatch.setattr(validator, "ROOT", tmp_path)
    monkeypatch.setattr(validator, "REPORTS_DIR", tmp_path / "sim/validation/reports")
    monkeypatch.setattr(validator, "CFAST_DIR", tmp_path / "sim/validation/cfast")
    validator._ARTIFACT_CACHE.clear()
    report = {
        check["name"]: check
        for check in json.loads(REPORT.read_text(encoding="utf-8"))["checks"]
    }[REAL_GAP]
    fields = ("actual", "expected", "tolerance", "minimum", "maximum", "required", "note")

    def evaluate() -> None:
        validator._ARTIFACT_CACHE.clear()
        check = validator.Check(REAL_GAP, **{field: report[field] for field in fields})
        validator._attach_provenance([check])
        validator._apply_gap_dispositions([check], verify_evidence=True)
        assert check.disposition == row["disposition"]

    monkeypatch.setattr(
        validator, "_GAP_DISPOSITIONS",
        {REAL_GAP: validator._GAP_DISPOSITIONS[REAL_GAP]},
    )
    return validator, row, evaluate


def test_real_gap_evidence_survives_crlf_checkout(tmp_path: Path, monkeypatch) -> None:
    _, _, evaluate = _crlf_checkout_of_gap(tmp_path, monkeypatch)
    evaluate()


def test_real_gap_evidence_rejects_content_mutation_in_crlf_checkout(
    tmp_path: Path, monkeypatch
) -> None:
    validator, row, evaluate = _crlf_checkout_of_gap(tmp_path, monkeypatch)
    csv = next(a["path"] for a in row["source_artifacts"] if a["path"].endswith(".csv"))
    target = tmp_path / csv
    payload = target.read_bytes()
    lines = payload.split(b"\r\n")
    data_row = lines[len(lines) // 2]
    index = next(i for i, byte in enumerate(data_row) if 0x31 <= byte <= 0x38)
    mutated = data_row[:index] + bytes([data_row[index] + 1]) + data_row[index + 1:]
    lines[len(lines) // 2] = mutated
    target.write_bytes(b"\r\n".join(lines))
    assert len(target.read_bytes()) == len(payload)
    with pytest.raises(ValueError, match="stale gap source artifacts"):
        evaluate()
