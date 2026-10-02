"""G3-2 source eligibility must stay conservative and traceable to stored bytes."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "docs/validation/G3_CO_SOURCE_ELIGIBILITY_MATRIX_2026-09-29.json"
FSRI = ROOT / "docs/literature/FSRI_ULRI/materials_database_a432697e"
DECISIONS = {"calibracion", "validacion", "exclusion"}


def _matrix() -> dict:
    return json.loads(MATRIX.read_text(encoding="utf-8"))


def test_every_row_is_complete_and_every_local_file_is_pinned() -> None:
    data = _matrix()
    assert set(data["decision_values"]) == DECISIONS
    ids = [row["id"] for row in data["rows"]]
    assert len(ids) == len(set(ids)) == 14
    required = {
        "source", "url", "test_ids", "actual_fuel", "local_files", "time_variables",
        "units", "regime", "igniter", "uncertainty", "limitations", "decision",
        "decision_scope", "calibration_blocker",
    }
    for row in data["rows"]:
        assert required <= set(row), row["id"]
        assert row["decision"] in DECISIONS, row["id"]
        for item in row["local_files"]:
            digest = hashlib.sha256((ROOT / item["path"]).read_bytes()).hexdigest()
            assert digest == item["sha256"], item["path"]


def test_no_source_is_promoted_to_per_object_co_calibration() -> None:
    data = _matrix()
    assert data["status"] == "G3-2_NO-GO_per_object_CO_calibration"
    assert len(data["missing_measurements"]) == 3
    calibration = [row for row in data["rows"] if row["decision"] == "calibracion"]
    # The only calibration candidate is bench-scale material data, not objects.
    assert [row["id"] for row in calibration] == ["E11"]
    assert "NOT a per-object" in calibration[0]["decision_scope"]
    for row in data["rows"]:
        mlr = row["time_variables"].get("mlr_t", "")
        co = row["time_variables"].get("co_t", "")
        if row["decision"] == "calibracion":
            assert "raw channel" in mlr and "raw channel" in co
        # Figures, gravimetric totals or missing columns never calibrate.
        if any(word in mlr for word in ("figure", "not_measured", "not_in")):
            assert row["decision"] != "calibracion", row["id"]


def test_mixed_igniter_dominated_and_below_detection_tests_are_excluded() -> None:
    rows = {row["id"]: row for row in _matrix()["rows"]}
    excluded = {t for row in rows.values() if row["decision"] == "exclusion" for t in row["test_ids"]}
    for test_id in ("Test014", "Test015", "Test018", "Test028", "Test033", "Test042", "Test043", "Test048"):
        assert test_id in excluded
    assert rows["E07"]["decision_scope"].startswith("reserved external")
    assert rows["E14"]["decision"] == "exclusion"


def test_fsri_files_contain_the_claimed_channels() -> None:
    scan = (FSRI / "Particleboard_Cone_HF50Scan_230705_R1.csv").read_text(encoding="utf-8-sig").splitlines()
    names = scan[0].split(",")
    assert "Sample Mass" in names and "CO Meter" in names and "O2 Meter" in names
    assert scan[4].split(",")[names.index("Sample Mass")] == "g"
    assert [line.split(",")[0] for line in scan[1:6]] == ["Chan Gain", "Offset", "Gain", "Units", "Baseline"]
    scalar = dict(
        line.split(",", 1)
        for line in (FSRI / "Particleboard_Cone_HF50Scalar_230705_R1.csv").read_text(encoding="utf-8-sig").splitlines()
        if "," in line
    )
    assert scalar["SCAN TIME"] == "0.25"
    assert scalar["CO DELAY TIME"] == "11"
    assert scalar["HEAT FLUX"] == "50"
    with (FSRI / "Overstuffed_Sofa_R1.csv").open(newline="", encoding="utf-8-sig") as source:
        header = next(csv.reader(source))
    assert "Load Cell" in header and "Heat Release Rate" in header
    assert not any("CO" in column.split() for column in header)
