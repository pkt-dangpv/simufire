import csv
from pathlib import Path

import pytest

from scripts.simulation import analyze_phase3_f33v2_fire_products as audit


LEGACY_COLUMNS = ("time_s", "room_id", "hrr_kw")


def _row(time_s: float, room_id: int, **values: float) -> dict[str, str]:
    fire = room_id == 0
    row = {
        "time_s": str(time_s),
        "room_id": str(room_id),
        "hrr_kw": str(values.pop("legacy_hrr_kw", 100.0 if fire else 0.0)),
    }
    defaults = {field: 0.0 for field in audit.PRODUCT_FIELDS}
    if fire:
        defaults.update(
            {
                "active_flag": 1.0,
                "supported_flag": 1.0,
                "object_sync_required_flag": 1.0,
                "profile_object_count": 2.0,
                "quality_phi": 1.0,
                "carbon_scale": 1.0,
                "common_fraction": 0.5,
                "requested_fuel_MJ": 0.2,
                "accepted_fuel_MJ": 0.1,
                "requested_o2_kg": 0.0152,
                "accepted_o2_kg": 0.0076,
                "requested_total_energy_kj": 200.0,
                "accepted_total_energy_kj": 100.0,
                "effective_chi_rad": 0.35,
                "requested_radiative_energy_kj": 70.0,
                "accepted_radiative_energy_kj": 35.0,
                "requested_convective_energy_kj": 130.0,
                "accepted_convective_energy_kj": 65.0,
                "accepted_plume_driver_hrr_kw": 100.0,
                "accepted_plume_driver_qc_kw": 65.0,
                "requested_carbon_available_kg": 0.0054,
                "requested_carbon_products_kg": 0.004,
                "requested_carbon_untracked_kg": 0.0014,
                "accepted_carbon_available_kg": 0.0027,
                "accepted_carbon_products_kg": 0.002,
                "accepted_carbon_untracked_kg": 0.0007,
            }
        )
        for species in audit.SPECIES:
            defaults[f"requested_{species}_kg"] = 0.002
            defaults[f"accepted_{species}_kg"] = 0.001
    defaults.update(values)
    row.update(
        {
            audit.PREFIX + field: str(defaults[field])
            for field in audit.PRODUCT_FIELDS
        }
    )
    return row


def _write_csv(path: Path, rows: list[dict[str, str]], products: bool) -> None:
    fields = list(LEGACY_COLUMNS)
    if products:
        fields.extend(audit.PRODUCT_COLUMNS)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(
            [{field: row.get(field, "") for field in fields} for row in rows]
        )


def _pair(tmp_path: Path) -> tuple[Path, Path]:
    rows = [
        _row(10.0, 0),
        _row(10.0, 1),
        _row(20.0, 0),
        _row(20.0, 1),
    ]
    baseline = tmp_path / "baseline.csv"
    products = tmp_path / "products.csv"
    _write_csv(baseline, rows, products=False)
    _write_csv(products, rows, products=True)
    return baseline, products


def _rewrite(path: Path, rows: list[dict[str, str]]) -> None:
    _write_csv(path, rows, products=True)


def test_product_schema_has_expected_46_columns():
    assert len(audit.PRODUCT_COLUMNS) == 46
    assert len(set(audit.PRODUCT_COLUMNS)) == 46


def test_clean_pair_passes_stop_gate(tmp_path: Path):
    baseline, products = _pair(tmp_path)
    report = audit.build_report(baseline, products)
    assert report["stop_gate_pass"] is True
    assert report["no_op_pass"] is True
    assert report["schema_pass"] is True
    assert report["object_sync_required"] is True
    assert report["runtime_authority"] == "NO-GO"


def test_shared_value_change_fails_no_op(tmp_path: Path):
    baseline, products = _pair(tmp_path)
    rows, _ = audit.read_csv(products)
    rows[0]["hrr_kw"] = "101"
    _rewrite(products, rows)
    report = audit.build_report(baseline, products)
    assert report["no_op_pass"] is False
    assert report["shared_value_differences"][0]["column"] == "hrr_kw"


def test_missing_product_column_fails_schema(tmp_path: Path):
    baseline, products = _pair(tmp_path)
    rows, header = audit.read_csv(products)
    header.remove(audit.PRODUCT_COLUMNS[-1])
    with products.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=header)
        writer.writeheader()
        writer.writerows(
            [{field: row.get(field, "") for field in header} for row in rows]
        )
    assert audit.build_report(baseline, products)["schema_pass"] is False


@pytest.mark.parametrize(
    ("field", "value", "result_key"),
    [
        ("common_fraction", 1.1, "fractions_in_range"),
        ("accepted_fuel_MJ", 0.3, "accepted_not_above_requested"),
        ("accepted_co_kg", 0.0011, "species_share_common_fraction"),
        ("accepted_carbon_products_kg", 0.003, "carbon_bounded"),
        ("accepted_plume_driver_qc_kw", 101.0, "energy_partition_bounded"),
        ("energy_residual_kj", 0.001, "residuals_close"),
    ],
)
def test_contract_violation_fails_stop_gate(
    tmp_path: Path, field: str, value: float, result_key: str
):
    baseline, products = _pair(tmp_path)
    rows, _ = audit.read_csv(products)
    rows[0][audit.PREFIX + field] = str(value)
    _rewrite(products, rows)
    report = audit.build_report(baseline, products)
    assert report[result_key] is False
    assert report["stop_gate_pass"] is False


def test_non_fire_products_must_remain_zero(tmp_path: Path):
    baseline, products = _pair(tmp_path)
    rows, _ = audit.read_csv(products)
    rows[1][audit.PREFIX + "accepted_smoke_kg"] = "0.001"
    _rewrite(products, rows)
    report = audit.build_report(baseline, products)
    assert report["non_fire_products_zero"] is False
    assert report["stop_gate_pass"] is False


def test_cli_and_json_output(tmp_path: Path, capsys):
    baseline, products = _pair(tmp_path)
    json_out = tmp_path / "report.json"
    exit_code = audit.main(
        [
            "--baseline-csv",
            str(baseline),
            "--products-csv",
            str(products),
            "--json-out",
            str(json_out),
        ]
    )
    output = capsys.readouterr().out
    assert exit_code == 0
    assert "STOP gate: PASS" in output
    assert "runtime authority: NO-GO" in output
    assert json_out.exists()
