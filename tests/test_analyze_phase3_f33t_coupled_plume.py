from pathlib import Path

import pytest

from scripts.simulation import analyze_phase3_f33t_coupled_plume as audit


def test_rmse():
    assert audit._rmse([3.0, 4.0]) == pytest.approx(3.5355339059)


def test_rmse_rejects_empty_series():
    with pytest.raises(ValueError):
        audit._rmse([])


def test_sim_room_rows_selects_room_and_rounds_time():
    rows = [
        {"time_s": "9.999999", "room_id": "0"},
        {"time_s": "10", "room_id": "1"},
    ]
    result = audit._sim_room_rows(rows)
    assert list(result) == [10]
    assert result[10]["room_id"] == "0"


def test_max_residuals_uses_absolute_peak():
    rows = [
        {column: "0" for column in audit.RESIDUAL_COLUMNS},
        {column: "0" for column in audit.RESIDUAL_COLUMNS},
    ]
    rows[0][audit.RESIDUAL_COLUMNS[0]] = "-0.25"
    rows[1][audit.RESIDUAL_COLUMNS[0]] = "0.20"
    result = audit._max_residuals(rows)
    assert result[audit.RESIDUAL_COLUMNS[0]] == pytest.approx(0.25)


def test_sha256_distinguishes_content(tmp_path: Path):
    first = tmp_path / "first.csv"
    second = tmp_path / "second.csv"
    first.write_text("same\n", encoding="utf-8")
    second.write_text("same\n", encoding="utf-8")
    assert audit._sha256(first) == audit._sha256(second)
    second.write_text("different\n", encoding="utf-8")
    assert audit._sha256(first) != audit._sha256(second)


def test_report_printer_names_non_authority(capsys):
    report = {
        "metrics": {
            "upper_mass_kg": {
                "off_rmse": 2.0,
                "on_rmse": 1.0,
                "improvement_fraction": 0.5,
            }
        },
        "off_byte_identical_to_baseline": True,
        "ledger_pass": True,
        "stop_gate_pass": True,
    }
    audit.print_report(report)
    output = capsys.readouterr().out
    assert "STOP gate: PASS" in output
    assert "runtime authority: NO-GO" in output
    assert "Group C retirement: NO-GO" in output
