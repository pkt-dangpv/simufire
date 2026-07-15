from __future__ import annotations

import csv
import json
from pathlib import Path

from scripts.simulation.audit_artifact_integrity import audit_csv, audit_run_packages


HEADER = ["time_s", "room_id", "room_name", "hrr_kw"]


def _write_csv(path: Path, rows: list[list[object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(HEADER)
        writer.writerows(rows)


def _case(path: Path, duration: float = 2.0, interval: float = 1.0) -> None:
    path.write_text(
        json.dumps({"duration_s": duration, "engine_overrides": {"log_interval_s": interval}}),
        encoding="utf-8",
    )


def test_clean_csv_accepts_fixed_step_quantization(tmp_path: Path) -> None:
    csv_path = tmp_path / "case.csv"
    case_path = tmp_path / "case.json"
    _write_csv(
        csv_path,
        [
            [0.0, 0, "A", 0.0],
            [0.0, 1, "B", 0.0],
            [1.1, 0, "A", 1.0],
            [1.1, 1, "B", 0.0],
            [2.0, 0, "A", 2.0],
            [2.0, 1, "B", 0.0],
        ],
    )
    _case(case_path)

    result = audit_csv(csv_path, case_path)

    assert result["status"] == "PASS"
    assert result["snapshots"] == 3
    assert result["rooms"] == 2


def test_duplicate_time_room_fails(tmp_path: Path) -> None:
    csv_path = tmp_path / "duplicate.csv"
    _write_csv(csv_path, [[0, 0, "A", 0], [0, 0, "A", 0]])

    result = audit_csv(csv_path)

    assert result["status"] == "FAIL"
    assert any("duplicate" in issue for issue in result["critical"])


def test_inconsistent_room_set_fails(tmp_path: Path) -> None:
    csv_path = tmp_path / "rooms.csv"
    _write_csv(
        csv_path,
        [[0, 0, "A", 0], [0, 1, "B", 0], [1, 0, "A", 1]],
    )

    result = audit_csv(csv_path)

    assert result["status"] == "FAIL"
    assert any("room set" in issue for issue in result["critical"])


def test_nonfinite_value_fails(tmp_path: Path) -> None:
    csv_path = tmp_path / "nan.csv"
    _write_csv(csv_path, [[0, 0, "A", "nan"]])

    result = audit_csv(csv_path)

    assert result["status"] == "FAIL"
    assert any("non-finite" in issue for issue in result["critical"])


def test_wrong_final_duration_fails(tmp_path: Path) -> None:
    csv_path = tmp_path / "short.csv"
    case_path = tmp_path / "short.json"
    _write_csv(csv_path, [[0, 0, "A", 0], [1, 0, "A", 0]])
    _case(case_path, duration=2.0)

    result = audit_csv(csv_path, case_path)

    assert result["status"] == "FAIL"
    assert any("final time" in issue for issue in result["critical"])


def test_malformed_matching_json_fails(tmp_path: Path) -> None:
    csv_path = tmp_path / "broken.csv"
    case_path = tmp_path / "broken.json"
    _write_csv(csv_path, [[0, 0, "A", 0]])
    case_path.write_text("{not json", encoding="utf-8")

    result = audit_csv(csv_path, case_path)

    assert result["status"] == "FAIL"
    assert "matching case JSON is malformed" in result["critical"]


def test_run_package_audit_detects_complete_and_partial(tmp_path: Path) -> None:
    complete = tmp_path / "complete"
    complete.mkdir()
    _write_csv(complete / "sim_log.csv", [[0, 0, "A", 0]])
    (complete / "summary.json").write_text(
        json.dumps({"schema_version": "simufire_technical_summary_v1"}), encoding="utf-8"
    )
    (complete / "run_manifest.json").write_text(
        json.dumps({"schema_version": "simufire_run_scenario_manifest_v1"}), encoding="utf-8"
    )
    (complete / "events.json").write_text("[]", encoding="utf-8")
    (complete / "sim_log.txt").write_text("ok", encoding="utf-8")

    partial = tmp_path / "partial"
    partial.mkdir()
    _write_csv(partial / "sim_log.csv", [[0, 0, "A", 0]])

    result = audit_run_packages(tmp_path)

    assert result["packages"] == 2
    assert result["complete"] == 1
    assert len(result["partial"]) == 1
    assert result["malformed"] == []
