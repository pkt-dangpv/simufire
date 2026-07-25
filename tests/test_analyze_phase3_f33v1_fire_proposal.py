import csv
from pathlib import Path

import pytest

from scripts.simulation import analyze_phase3_f33v1_fire_proposal as audit


LEGACY_COLUMNS = ("time_s", "room_id", "hrr_kw")


def _row(time_s: float, room_id: int, **values: float) -> dict[str, str]:
    row = {
        "time_s": str(time_s),
        "room_id": str(room_id),
        "hrr_kw": str(values.pop("legacy_hrr_kw", 0.0)),
    }
    defaults = {
        "active_flag": 1.0 if room_id == 0 else 0.0,
        "supported_flag": 1.0 if room_id == 0 else 0.0,
        "unsupported_reason_mask": 0.0 if room_id == 0 else 1.0,
        "age_s": time_s if room_id == 0 else 0.0,
        "curve_hrr_kw": 100.0 if room_id == 0 else 0.0,
        "target_kw": 100.0 if room_id == 0 else 0.0,
        "hrr_kw": 100.0 if room_id == 0 else 0.0,
        "remaining_fuel_pre_MJ": 1000.0 - time_s,
        "remaining_fuel_post_MJ": 999.0 - time_s,
        "hard_extinction_flag": 0.0,
        "o2_inventory_cap_kw": 1000.0,
        "ventilation_cap_kw": -1.0,
        "fuel_cap_kw": 10000.0,
        "decision_fraction": 1.0 if room_id == 0 else 0.0,
        "accepted_hrr_kw": 100.0 if room_id == 0 else 0.0,
        "requested_o2_kg": 0.01 if room_id == 0 else 0.0,
        "accepted_o2_kg": 0.01 if room_id == 0 else 0.0,
        "accepted_fuel_MJ": 0.1 if room_id == 0 else 0.0,
        "zero_o2_flame_flag": 0.0,
    }
    defaults.update(values)
    row.update(
        {
            audit.PREFIX + field: str(defaults[field])
            for field in audit.PROPOSAL_FIELDS
        }
    )
    return row


def _write_csv(path: Path, rows: list[dict[str, str]], on: bool) -> None:
    fields = list(LEGACY_COLUMNS)
    if on:
        fields.extend(audit.PROPOSAL_COLUMNS)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(
            [{field: row.get(field, "") for field in fields} for row in rows]
        )


def _pair(tmp_path: Path) -> tuple[Path, Path]:
    rows = [
        _row(10.0, 0, remaining_fuel_post_MJ=990.0),
        _row(10.0, 1),
        _row(20.0, 0, remaining_fuel_post_MJ=980.0),
        _row(20.0, 1),
    ]
    off = tmp_path / "off.csv"
    on = tmp_path / "on.csv"
    _write_csv(off, rows, on=False)
    _write_csv(on, rows, on=True)
    return off, on


def test_clean_pair_passes_stop_gate(tmp_path: Path):
    off, on = _pair(tmp_path)
    report = audit.build_report(off, on)
    assert report["stop_gate_pass"] is True
    assert report["no_op_pass"] is True
    assert report["schema_pass"] is True
    assert report["supported_fire_rows"] == 2


def test_shared_value_change_fails_no_op(tmp_path: Path):
    off, on = _pair(tmp_path)
    rows, _ = audit.read_csv(on)
    rows[0]["hrr_kw"] = "101.0"
    _write_csv(on, rows, on=True)
    report = audit.build_report(off, on)
    assert report["no_op_pass"] is False
    assert report["shared_value_differences"][0]["column"] == "hrr_kw"


def test_missing_proposal_column_fails_schema(tmp_path: Path):
    off, on = _pair(tmp_path)
    rows, header = audit.read_csv(on)
    header.remove(audit.PROPOSAL_COLUMNS[-1])
    with on.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=header)
        writer.writeheader()
        writer.writerows(
            [{field: row.get(field, "") for field in header} for row in rows]
        )
    assert audit.build_report(off, on)["schema_pass"] is False


def test_zero_o2_flame_fails_contract(tmp_path: Path):
    off, on = _pair(tmp_path)
    rows, _ = audit.read_csv(on)
    rows[0][audit.PREFIX + "zero_o2_flame_flag"] = "1"
    _write_csv(on, rows, on=True)
    report = audit.build_report(off, on)
    assert report["fire_contract_pass"] is False
    assert report["zero_o2_flame_peak"] == pytest.approx(1.0)


def test_increasing_fuel_fails_contract(tmp_path: Path):
    off, on = _pair(tmp_path)
    rows, _ = audit.read_csv(on)
    rows[2][audit.PREFIX + "remaining_fuel_post_MJ"] = "995"
    _write_csv(on, rows, on=True)
    assert audit.build_report(off, on)["fuel_monotonic"] is False


def test_non_fire_room_requires_explicit_no_fire_reason(tmp_path: Path):
    off, on = _pair(tmp_path)
    rows, _ = audit.read_csv(on)
    rows[1][audit.PREFIX + "unsupported_reason_mask"] = "0"
    _write_csv(on, rows, on=True)
    assert audit.build_report(off, on)["non_fire_rows_explicit"] is False


def test_accepted_hrr_cannot_exceed_proposal(tmp_path: Path):
    off, on = _pair(tmp_path)
    rows, _ = audit.read_csv(on)
    rows[0][audit.PREFIX + "accepted_hrr_kw"] = "101"
    _write_csv(on, rows, on=True)
    report = audit.build_report(off, on)
    assert report["fire_contract_pass"] is False
    assert report["accepted_above_proposal_peak_kw"] == pytest.approx(1.0)


def test_report_printer_keeps_authority_and_gap_open(capsys):
    report = {
        "row_count_off": 4,
        "row_count_on": 4,
        "column_count_off": 3,
        "column_count_on": 22,
        "shared_column_count": 3,
        "schema_pass": True,
        "no_op_pass": True,
        "supported_fire_rows": 2,
        "fire_rows": 2,
        "fuel_monotonic": True,
        "zero_o2_flame_peak": 0.0,
        "max_proposal_hrr_kw": 100.0,
        "max_accepted_hrr_kw": 100.0,
        "stop_gate_pass": True,
    }
    audit.print_report(report)
    output = capsys.readouterr().out
    assert "STOP gate: PASS" in output
    assert "runtime authority: NO-GO" in output
    assert "Group C retirement: NO-GO" in output
