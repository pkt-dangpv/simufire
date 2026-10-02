"""Audit four unmodified NIST FCD CSVs; never attribute mixed-fuel emissions."""

from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CASES = {
    "Test029": {
        "sha256": "c588f8803729e6742c2d7e91cdf37b3908628c7408c2456e4db1a6767da21631",
        "first_s": -292, "last_s": 2869, "fire_out_s": 2080,
        "peak_hrr_kW": 1984.0, "thr_MJ": 811.0,
    },
    "Test030": {
        "sha256": "8ba0f6bb59cc1c8112367a03a0ea4fdcf63883cba5d15a031af5be499fe7bd5c",
        "first_s": -375, "last_s": 2842, "fire_out_s": 2211,
        "peak_hrr_kW": 2994.0, "thr_MJ": 1426.0,
    },
    "Test028": {
        "sha256": "35b815a540d51b994e21a429ebfad48851b4a64b3735fa7073bb4db857f9aeea",
        "first_s": -193, "last_s": 1317, "fire_out_s": 1230,
        "peak_hrr_kW": 145.8, "thr_MJ": 23.2,
    },
    "Test018": {
        "sha256": "787126cccf725f04ffde64e70fd772f835205aa9198fd3241d0a199865bb320f",
        "first_s": -209, "last_s": 1176, "fire_out_s": 1082,
        "peak_hrr_kW": 2.22, "thr_MJ": 0.93,
    },
}
CSV_PATH = ROOT / "docs/literature/NIST/FCD_Test029_2026-04-07.csv"
EXPECTED_COLUMNS = (
    "Time (s)",
    "Heat Release Rate (kW)",
    "Burner HRR (kW)",
    "Exhaust Mass Flow Rate (kg/s)",
    "Oxygen (Vol Fr)",
    "CO2 (Vol Fr)",
    "CO (Vol Fr)",
    "Radiant Heat Flux (kW/m^2)",
    "Ksmoke (1/m)",
)


def csv_path(test_id: str) -> Path:
    if test_id not in CASES:
        raise ValueError(f"unreviewed NIST FCD test: {test_id}")
    return ROOT / f"docs/literature/NIST/FCD_{test_id}_2026-04-07.csv"


def audit(test_id: str = "Test029") -> dict[str, object]:
    config = CASES[test_id] if test_id in CASES else None
    if config is None:
        raise ValueError(f"unreviewed NIST FCD test: {test_id}")
    path = csv_path(test_id)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != config["sha256"]:
        raise ValueError(f"{test_id} source bytes changed: {digest}")
    with path.open(newline="", encoding="utf-8-sig") as source:
        reader = csv.DictReader(source)
        if tuple(reader.fieldnames or ()) != EXPECTED_COLUMNS:
            raise ValueError(f"{test_id} columns changed")
        rows = list(reader)
    expected_rows = config["last_s"] - config["first_s"] + 1
    if len(rows) != expected_rows:
        raise ValueError(f"{test_id} row count changed: {len(rows)}")
    times = [int(row["Time (s)"]) for row in rows]
    if times != list(range(config["first_s"], config["last_s"] + 1)):
        raise ValueError(f"{test_id} time axis is not contiguous at 1 s")
    missing: list[tuple[int, str]] = []
    for row in rows:
        for column in EXPECTED_COLUMNS[1:]:
            value = float(row[column])
            if not math.isfinite(value):
                missing.append((int(row["Time (s)"]), column))
    expected_missing = [] if test_id == "Test018" else [
        (config["last_s"], "Heat Release Rate (kW)"),
        (config["last_s"], "Oxygen (Vol Fr)"),
    ]
    if missing != expected_missing:
        raise ValueError(f"Unexpected non-finite cells: {missing}")

    fire_rows = [row for row in rows if 0 <= int(row["Time (s)"]) <= config["fire_out_s"]]
    hrr = [float(row["Heat Release Rate (kW)"]) for row in fire_rows]
    peak_index = max(range(len(hrr)), key=hrr.__getitem__)
    # NIST marks ignition t=0 and each fire-out event on its test page.
    # This is a check of the published rounded THR, not a replacement for its
    # processing script or an estimate of object mass-loss rate.
    integrated_hrr_mj = (sum(hrr) - (hrr[0] + hrr[-1]) / 2) / 1000
    if abs(integrated_hrr_mj - config["thr_MJ"]) > max(0.1, config["thr_MJ"] * 0.001):
        raise ValueError("HRR integral does not reproduce rounded NIST THR")
    if abs(hrr[peak_index] - config["peak_hrr_kW"]) > 0.5:
        raise ValueError("HRR peak does not reproduce rounded NIST PHRR")
    return {
        "test_id": test_id,
        "source": str(path.relative_to(ROOT)).replace("\\", "/"),
        "sha256": digest,
        "rows": len(rows),
        "time_range_s": [times[0], times[-1]],
        "missing_cells": [{"time_s": t, "column": col} for t, col in missing],
        "peak_hrr_kW": hrr[peak_index],
        "peak_hrr_time_s": int(fire_rows[peak_index]["Time (s)"]),
        "fire_out_sample_s": config["fire_out_s"],
        "hrr_integral_ignition_to_fire_out_MJ": round(integrated_hrr_mj, 5),
        "co_column": "dry exhaust volume fraction",
        "co_mass_rate_status": "see_research_only_reconstruction",
    }


if __name__ == "__main__":
    print(json.dumps({test_id: audit(test_id) for test_id in CASES}, indent=2, ensure_ascii=False))
