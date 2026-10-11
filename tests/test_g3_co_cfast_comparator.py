"""The G3 diagnostic must compare raw lower CO with CFAST LLCO, not room mean."""

from __future__ import annotations

import csv
import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/simulation/audit_g3_co_inventory_against_cfast.py"
spec = importlib.util.spec_from_file_location("g3_co_cfast_comparator", SCRIPT)
assert spec is not None and spec.loader is not None
comparator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparator)


def _fixtures(tmp_path: Path) -> tuple[Path, Path]:
    trace_root = tmp_path / "traces"
    case = "cfast_two_room_door_open"
    trace_dir = trace_root / case
    trace_dir.mkdir(parents=True)
    cfast_root = tmp_path / "cfast"
    cfast_root.mkdir()

    # CFAST room 1 has 29 ppm lower CO, room 2 has 0 ppm. The upper CO
    # columns intentionally differ so an accidental ULCO mapping is caught.
    with (cfast_root / f"{case}_compartments.csv").open(
        "w", encoding="utf-8", newline=""
    ) as handle:
        writer = csv.writer(handle)
        writer.writerow(["Time", "LLCO_1", "ULCO_1", "HGT_1", "LLCO_2", "ULCO_2", "HGT_2"])
        for _ in range(3):
            writer.writerow(["s", "%", "%", "m", "%", "%", "m"])
        for time in (120, 240, 360, 480):
            writer.writerow([time, 0.0029, 0.2, 1.7, 0.0, 0.3, 1.8])

    rows = []
    for time in (120, 240, 360, 480):
        for room_id in (0, 1):
            lower = 0.00028 if room_id == 0 else 0.0
            rows.append({
                "room_id": room_id,
                "time_s": time,
                "co_total_kg": lower + 0.001,
                "co_upper_raw_kg": 0.001,
                "co_lower_kg": lower,
                "co_lower_mass_ppm": lower * 29.0e6 / (10.0 * 28.0),
                "co_lower_legacy_ppm": 0.0,
                "lower_geometric_kg": 10.0,
                "upper_gas_kg": 2.0,
                "co_upper_ppm": 100.0 + room_id,
                "hot_layer_m": 1.7 + room_id * 0.1,
            })
    (trace_dir / "co_inventory_trace.jsonl").write_text(
        "\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8"
    )
    return trace_root, cfast_root


def test_lower_comparator_uses_raw_inventory_and_correct_cfast_room(tmp_path: Path) -> None:
    trace_root, cfast_root = _fixtures(tmp_path)
    report = comparator.compare_case("cfast_two_room_door_open", trace_root, cfast_root)
    assert len(report["points"]) == 8
    fire = next(point for point in report["points"] if point["room_id"] == 0)
    hall = next(point for point in report["points"] if point["room_id"] == 1)
    assert fire["sim_lower_co_mass_ppm"] == pytest.approx(29.0)
    assert fire["cfast_lower_co_ppm"] == pytest.approx(29.0)
    assert fire["sim_co_representation"] == "raw_lower_inventory"
    assert hall["sim_lower_co_mass_ppm"] == 0.0
    assert hall["cfast_lower_co_ppm"] == 0.0
    assert "co_avg_ppm" not in SCRIPT.read_text(encoding="utf-8")


@pytest.mark.parametrize("field,value,reason", [
    ("co_upper_raw_kg", 2.0, "invalid raw CO inventory"),
    ("co_lower_mass_ppm", 999.0, "lower ppm does not follow its source"),
])
def test_bad_inventory_fails_closed(
    tmp_path: Path, field: str, value: float, reason: str
) -> None:
    trace_root, cfast_root = _fixtures(tmp_path)
    path = trace_root / "cfast_two_room_door_open" / "co_inventory_trace.jsonl"
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    rows[0][field] = value
    path.write_text("\n".join(json.dumps(row) for row in rows), encoding="utf-8")
    with pytest.raises(ValueError, match=reason):
        comparator.compare_case("cfast_two_room_door_open", trace_root, cfast_root)


def test_missing_llco_column_fails_closed(tmp_path: Path) -> None:
    trace_root, cfast_root = _fixtures(tmp_path)
    path = cfast_root / "cfast_two_room_door_open_compartments.csv"
    path.write_text("Time,ULCO_1,HGT_1\n", encoding="utf-8")
    with pytest.raises(ValueError, match="missing CFAST columns"):
        comparator.compare_case("cfast_two_room_door_open", trace_root, cfast_root)


def test_collapsed_upper_layer_is_labelled_room_mean(tmp_path: Path) -> None:
    trace_root, cfast_root = _fixtures(tmp_path)
    path = trace_root / "cfast_two_room_door_open" / "co_inventory_trace.jsonl"
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    rows[0]["upper_gas_kg"] = 0.0
    rows[0]["co_lower_mass_ppm"] = 11.0
    rows[0]["co_lower_legacy_ppm"] = 11.0
    path.write_text("\n".join(json.dumps(row) for row in rows), encoding="utf-8")
    report = comparator.compare_case("cfast_two_room_door_open", trace_root, cfast_root)
    assert report["points"][0]["sim_co_representation"] == "room_mean_no_upper_zone"
    assert report["points"][0]["sim_lower_co_mass_ppm"] == 11.0
