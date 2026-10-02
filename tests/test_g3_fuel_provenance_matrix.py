"""The human review matrix must not drift from the distributed scenarios."""

from __future__ import annotations

from pathlib import Path

from scripts.simulation.audit_g3_fuel_sources import DEFAULT_SCENARIOS, audit_directory


ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "docs/validation/G3_FUEL_PROVENANCE_MATRIX_2026-09-27.md"


def test_all_23_mismatch_rows_match_scenario_inventory() -> None:
    rows = {}
    for line in MATRIX.read_text(encoding="utf-8").splitlines():
        if not line.startswith("| ") or ".json |" not in line:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        assert len(cells) == 9
        file_name, room_id, name, *numbers = cells
        key = (file_name, int(room_id))
        assert key not in rows
        rows[key] = (name, tuple(float(number) for number in numbers))

    inventory = audit_directory(DEFAULT_SCENARIOS)
    expected = {}
    for scenario in inventory["scenarios"]:
        for room in scenario["rooms"]:
            if room["shape"] != "both_mismatch_unclassified":
                continue
            key = (scenario["file"], room["room_id"])
            expected[key] = (
                room["room_name"],
                (
                    room["declared_room_energy_MJ"],
                    room["object_energy_MJ"],
                    room["energy_difference_MJ"],
                    room["declared_room_max_hrr_kw"],
                    room["object_max_hrr_kw"],
                    room["power_difference_kw"],
                ),
            )
    assert len(rows) == len(expected) == 23
    assert rows == expected
