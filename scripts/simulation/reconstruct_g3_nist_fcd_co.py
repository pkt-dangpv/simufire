"""Research-only reconstruction of four NIST FCD exhaust CO series.

The 2020 NIST FCD User Guide defines total CO as the ignition-to-fire-out
sum of (X_CO - X_CO,ambient) * exhaust mass flow * M_CO / M_air. The public
CSV does not state which ambient averaging interval the 2026 processing
script used, so this module reports a declared 60 s candidate and a 120 s
sensitivity. It does not reconstruct instantaneous fuel mass loss or Y_CO(t).
"""

from __future__ import annotations

import csv
import json
import statistics

from scripts.simulation.audit_g3_nist_fcd_csv import CASES, audit, csv_path


M_CO_KG_PER_KMOL = 28.01
M_AIR_KG_PER_KMOL = 28.97
ATTRIBUTION = {
    "Test029": "whole_sofa_with_pillows_open_air_only",
    "Test030": "whole_sofa_with_pillows_open_air_only",
    "Test028": "carpet_plus_pillows_not_carpet_only",
    "Test018": "pilot_contaminated_below_detection_not_calibratable",
}


def reconstruct(
    background_start_s: int = -60, test_id: str = "Test029"
) -> tuple[list[dict[str, float]], dict[str, object]]:
    audit(test_id)  # Fail closed on source bytes/schema and trailing NaNs.
    if background_start_s not in (-60, -120):
        raise ValueError("unreviewed ambient CO averaging interval")
    fire_out_s = CASES[test_id]["fire_out_s"]
    with csv_path(test_id).open(newline="", encoding="utf-8-sig") as source:
        rows = list(csv.DictReader(source))
    background = statistics.mean(
        float(row["CO (Vol Fr)"])
        for row in rows
        if background_start_s <= int(row["Time (s)"]) < 0
    )
    rate_rows: list[dict[str, float]] = []
    cumulative_kg = 0.0
    for row in rows:
        time_s = int(row["Time (s)"])
        if not 0 <= time_s <= fire_out_s:
            continue
        rate_kg_s = (
            (float(row["CO (Vol Fr)"]) - background)
            * float(row["Exhaust Mass Flow Rate (kg/s)"])
            * M_CO_KG_PER_KMOL / M_AIR_KG_PER_KMOL
        )
        # NIST's formula sums net rates; clipping negative instrument noise
        # would silently increase the total and break that contract.
        cumulative_kg += rate_kg_s
        rate_rows.append({
            "time_s": time_s,
            "net_co_exhaust_rate_kg_s": rate_kg_s,
            "net_co_exhaust_cumulative_kg": cumulative_kg,
        })
    peak = max(rate_rows, key=lambda row: row["net_co_exhaust_rate_kg_s"])
    periods = [(0, 299), (300, 599), (600, min(1199, fire_out_s))]
    if fire_out_s >= 1200:
        periods.append((1200, fire_out_s))
    by_period = {
        f"{start}_{end}_s": sum(
            row["net_co_exhaust_rate_kg_s"]
            for row in rate_rows
            if start <= row["time_s"] <= end
        )
        for start, end in periods
    }
    return rate_rows, {
        "test_id": test_id,
        "status": "research_only_ambient_window_candidate_not_engine_calibration",
        "attribution": ATTRIBUTION[test_id],
        "ambient_window_start_s": background_start_s,
        "ambient_co_vol_frac": background,
        "ignition_s": 0,
        "fire_out_sample_s": fire_out_s,
        "samples": len(rate_rows),
        "total_net_co_exhaust_kg": cumulative_kg,
        "peak_net_co_exhaust_rate_kg_s": peak["net_co_exhaust_rate_kg_s"],
        "peak_net_co_exhaust_rate_time_s": int(peak["time_s"]),
        "net_co_exhaust_kg_by_period": by_period,
        "negative_rate_samples": sum(row["net_co_exhaust_rate_kg_s"] < 0 for row in rate_rows),
        "instantaneous_specimen_mass_loss_status": "not_measured_in_public_csv",
        "instantaneous_co_yield_status": "not_derived",
        "nfrl_report_8_7_1_ambient_window_status": "not_verified",
    }


if __name__ == "__main__":
    report = {}
    for test_id in CASES:
        _, primary = reconstruct(-60, test_id)
        _, sensitivity = reconstruct(-120, test_id)
        report[test_id] = {"candidate_60s": primary, "sensitivity_120s": sensitivity}
    print(json.dumps(report, indent=2))
