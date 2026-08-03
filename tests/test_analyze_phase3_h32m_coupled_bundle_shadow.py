import csv
import json
from pathlib import Path

from scripts.simulation.analyze_phase3_h32m_coupled_bundle_shadow import (
    INVALID_REASON,
    PREFIX,
    PROVENANCE,
    audit_case,
)


def _write_csv(path: Path, header: list[str], rows: list[list[str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


def _make_case(tmp_path: Path) -> tuple[Path, Path]:
    baseline = tmp_path / "baseline"
    candidate = tmp_path / "candidate"
    baseline.mkdir()
    candidate.mkdir()
    _write_csv(
        baseline / "sim_log.csv",
        ["time_s", "room_id", "legacy"],
        [["0.0", "0", "1.0"], ["10.0", "0", "2.0"], ["20.0", "0", "3.0"]],
    )
    _write_csv(
        candidate / "sim_log.csv",
        ["time_s", "room_id", "legacy", PREFIX + "valid_flag"],
        [["0.0", "0", "1.0", "0.0"], ["10.0", "0", "2.0", "1.0"]],
    )
    (candidate / "run_manifest.json").write_text(
        json.dumps({"status": "completed", "duration_s": 10.0, "sim_time_s": 10.0}),
        encoding="utf-8",
    )
    bundle = {
        "source_inputs_independent": False,
        "source_provenance": PROVENANCE,
        "comparison_valid": False,
        "comparison_invalid_reason": INVALID_REASON,
        "current": {
            "mass_conservation_residual_kg": 0.0,
            "energy_conservation_residual_kj": 0.0,
            "inventory_limited_mass_kg": 1.0,
            "accepted_mass_kg": 1.0,
            "inventory_limited_energy_kj": 2.0,
            "accepted_energy_kj": 2.0,
        },
        "cumulative": {
            "step_count": 2.0,
            "valid_step_count": 2.0,
            "max_abs_mass_conservation_residual_kg": 0.0,
            "max_abs_energy_conservation_residual_kj": 0.0,
        },
    }
    (candidate / "summary.json").write_text(
        json.dumps({"phase3_coupled_interior_bundle_shadow": bundle}),
        encoding="utf-8",
    )
    return baseline, candidate


def test_audit_accepts_exact_shared_prefix_and_explicit_invalid_comparison(tmp_path):
    baseline, candidate = _make_case(tmp_path)
    result = audit_case(baseline, candidate)
    assert result["passed"]
    assert result["baseline_rows"] == result["candidate_rows"] == 2
    assert result["added_columns"] == 1


def test_audit_rejects_a_changed_legacy_value(tmp_path):
    baseline, candidate = _make_case(tmp_path)
    rows = list(csv.reader((candidate / "sim_log.csv").open(encoding="utf-8")))
    rows[2][2] = "9.0"
    _write_csv(candidate / "sim_log.csv", rows[0], rows[1:])
    result = audit_case(baseline, candidate)
    assert not result["passed"]
    assert "field=legacy" in result["first_difference"]


def test_audit_rejects_non_prefixed_added_column(tmp_path):
    baseline, candidate = _make_case(tmp_path)
    header, rows = _read(candidate / "sim_log.csv")
    _write_csv(candidate / "sim_log.csv", header + ["surprise"], [row + ["0"] for row in rows])
    assert not audit_case(baseline, candidate)["passed"]


def test_audit_rejects_fake_comparison_or_double_limit(tmp_path):
    baseline, candidate = _make_case(tmp_path)
    summary_path = candidate / "summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    bundle = summary["phase3_coupled_interior_bundle_shadow"]
    bundle["comparison_valid"] = True
    bundle["cumulative"]["double_limit_count"] = 1.0
    summary_path.write_text(json.dumps(summary), encoding="utf-8")
    assert not audit_case(baseline, candidate)["passed"]


def _read(path: Path) -> tuple[list[str], list[list[str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.reader(handle))
    return rows[0], rows[1:]
