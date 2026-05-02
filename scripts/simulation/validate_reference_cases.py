#!/usr/bin/env python3
"""Compare Simufire validation outputs against external reference cases.

The checks are deliberately narrow:
- CFAST checks compare the local NIST CFAST CSV exported for the same room/window
  scenario against the current Simufire log.
- Ghanekar checks cover the measurable hallway O2 response currently represented by
  the engine. CO/HCN/FED-full-paper checks are emitted as known gaps, not as pass/fail
  gates, because the model does not yet include HCN and its far-hall CO/CO2 response is
  not calibrated to that paper.
"""

from __future__ import annotations

import csv
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
REPORTS_DIR = ROOT / "sim" / "validation" / "reports"
CFAST_DIR = ROOT / "sim" / "validation" / "cfast"


@dataclass
class Check:
    name: str
    actual: float | None
    expected: float | None = None
    tolerance: float | None = None
    minimum: float | None = None
    maximum: float | None = None
    required: bool = True
    note: str = ""

    def passed(self) -> bool:
        if self.actual is None:
            return False
        if self.expected is not None and self.tolerance is not None:
            if abs(self.actual - self.expected) > self.tolerance:
                return False
        if self.minimum is not None and self.actual < self.minimum:
            return False
        if self.maximum is not None and self.actual > self.maximum:
            return False
        return True

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "actual": self.actual,
            "expected": self.expected,
            "tolerance": self.tolerance,
            "minimum": self.minimum,
            "maximum": self.maximum,
            "required": self.required,
            "pass": self.passed(),
            "note": self.note,
        }


def _nearest(items: list[dict[str, float]], target_time_s: float) -> dict[str, float]:
    if not items:
        raise ValueError("no time-series samples available")
    return min(items, key=lambda item: abs(item["time_s"] - target_time_s))


def _load_cfast_compartments(path: Path) -> list[dict[str, float]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if len(rows) < 5:
        raise ValueError(f"CFAST CSV is too short: {path}")

    header = rows[0]
    index = {name: i for i, name in enumerate(header)}
    required_columns = ["Time", "HRR_1", "ULO2_1", "ULT_1", "LLT_1", "HGT_1", "ULCO_1"]
    missing = [name for name in required_columns if name not in index]
    if missing:
        raise ValueError(f"CFAST CSV missing columns {missing}: {path}")

    samples: list[dict[str, float]] = []
    for row in rows[4:]:
        if not row or not row[0].strip():
            continue
        values: list[float] = []
        for raw in row[: len(header)]:
            raw = raw.strip()
            values.append(float(raw) if raw else math.nan)
        samples.append(
            {
                "time_s": values[index["Time"]],
                "hrr_kw": values[index["HRR_1"]] / 1000.0,
                "o2": values[index["ULO2_1"]] / 100.0,
                "temp_upper_c": values[index["ULT_1"]],
                "temp_lower_c": values[index["LLT_1"]],
                "hot_layer_m": values[index["HGT_1"]],
                "co_upper_ppm": values[index["ULCO_1"]] * 10000.0,
            }
        )
    return samples


def _parse_simufire_log(path: Path, room_id: int) -> list[dict[str, float]]:
    time_s: float | None = None
    samples: list[dict[str, float]] = []
    time_re = re.compile(r"^TIME=([0-9.]+) s")
    room_re = re.compile(rf"^ROOM {room_id}\([^)]*\) \| (.*)$")

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match_time = time_re.match(line)
        if match_time:
            time_s = float(match_time.group(1))
            continue

        match_room = room_re.match(line)
        if not match_room or time_s is None:
            continue

        sample: dict[str, float] = {"time_s": time_s}
        for segment in match_room.group(1).split(" | "):
            if "=" not in segment:
                continue
            key, value = segment.split("=", 1)
            value = value.split()[0].replace("ppm", "").replace("Pa", "").replace("%", "")
            try:
                sample[key] = float(value)
            except ValueError:
                continue

        samples.append(
            {
                "time_s": sample["time_s"],
                "hrr_kw": sample.get("HRR", math.nan),
                "o2": sample.get("O2", math.nan),
                "temp_upper_c": sample.get("Up", math.nan),
                "temp_lower_c": sample.get("Low", math.nan),
                "hot_layer_m": sample.get("HotLayer", math.nan),
                "co_upper_ppm": sample.get("COu", math.nan),
                "fed": sample.get("FED", math.nan),
            }
        )
    return samples


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _metric(metrics: dict[str, Any], name: str) -> float | None:
    value = metrics.get(name)
    if value is None:
        return None
    return float(value)


def _add_abs_check(
    checks: list[Check],
    prefix: str,
    field: str,
    cfast_sample: dict[str, float],
    sim_sample: dict[str, float],
    tolerance: float,
    note: str = "",
) -> None:
    checks.append(
        Check(
            name=f"{prefix}_{field}",
            actual=sim_sample[field],
            expected=cfast_sample[field],
            tolerance=tolerance,
            note=note,
        )
    )


def build_cfast_checks() -> list[Check]:
    cfast = _load_cfast_compartments(CFAST_DIR / "r0_hall_window_360_compartments.csv")
    sim = _parse_simufire_log(REPORTS_DIR / "cfast_r0_window_360.log", room_id=0)
    report = _load_json(REPORTS_DIR / "cfast_r0_window_360.json")
    metrics = report.get("metrics", {})
    checks: list[Check] = []

    # Pre-opening: CFAST remains ventilation-limited rather than numerically extinct.
    for target_s in [350.0, 360.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_t{int(target_s)}"
        _add_abs_check(checks, prefix, "hrr_kw", c, s, 90.0)
        _add_abs_check(checks, prefix, "o2", c, s, 0.015)
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 80.0)
        _add_abs_check(checks, prefix, "temp_lower_c", c, s, 45.0)
        _add_abs_check(checks, prefix, "hot_layer_m", c, s, 0.50)

    # The first 20 s after opening are intentionally smoothed in Simufire; require
    # physical recovery, not exact replication of CFAST's prescribed HRR jump.
    s380 = _nearest(sim, 380.0)
    checks.extend(
        [
            Check("cfast_t380_hrr_recovering", s380["hrr_kw"], minimum=300.0),
            Check("cfast_t380_upper_temp_bounded", s380["temp_upper_c"], maximum=500.0),
            Check("cfast_t380_o2_recovered", s380["o2"], minimum=0.10),
        ]
    )

    # Post-opening quasi-steady state.
    for target_s in [420.0, 510.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_t{int(target_s)}"
        _add_abs_check(checks, prefix, "hrr_kw", c, s, 260.0)
        _add_abs_check(checks, prefix, "o2", c, s, 0.050)
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 80.0)
        _add_abs_check(checks, prefix, "hot_layer_m", c, s, 0.55)
        _add_abs_check(checks, prefix, "co_upper_ppm", c, s, 350.0)

    max_fed = max(sample.get("fed", 0.0) for sample in sim)
    checks.append(Check("cfast_fed_heat_not_explosive", max_fed, maximum=2.0))
    checks.append(
        Check(
            "cfast_no_temperature_cap",
            _metric(metrics, "watched_temp_upper_clamp_count"),
            expected=0.0,
            tolerance=0.0,
        )
    )
    return checks


def build_ghanekar_checks() -> list[Check]:
    report = _load_json(REPORTS_DIR / "ghanekar_bedroom_hallway.json")
    metrics = report.get("metrics", {})
    checks: list[Check] = [
        Check(
            "ghanekar_far_hall_o2_response_time_s",
            _metric(metrics, "time_room_2_o2_below_20_4pct_s"),
            expected=198.0,
            tolerance=30.0,
            note="Ghanekar bedroom tests report initial hallway O2 response near 3.3 min.",
        ),
        Check(
            "ghanekar_no_temperature_cap",
            _metric(metrics, "watched_temp_upper_clamp_count"),
            expected=0.0,
            tolerance=0.0,
        ),
        Check(
            "ghanekar_origin_peak_upper_temp_reasonable_c",
            _metric(metrics, "room_0_peak_temp_upper_c"),
            minimum=450.0,
            maximum=650.0,
        ),
        Check(
            "ghanekar_flashover_0_9m_known_gap",
            _metric(metrics, "time_room_0_temp_0_9m_above_600c_s"),
            expected=186.0,
            tolerance=30.0,
            required=False,
            note="Known gap: current two-zone vertical profile does not reproduce the paper's 0.9 m flashover criterion.",
        ),
        Check(
            "ghanekar_far_hall_co_known_gap",
            _metric(metrics, "time_room_2_co_above_200ppm_s"),
            expected=204.0,
            tolerance=45.0,
            required=False,
            note="Known gap: CO/HCN toxic-gas chemistry is not calibrated to the Ghanekar paper.",
        ),
    ]
    return checks


def main() -> int:
    all_checks = build_cfast_checks() + build_ghanekar_checks()
    required = [check for check in all_checks if check.required]
    failed = [check for check in required if not check.passed()]
    known_gaps = [check for check in all_checks if not check.required and not check.passed()]

    output = {
        "all_required_pass": not failed,
        "required_count": len(required),
        "failed_required_count": len(failed),
        "known_gap_count": len(known_gaps),
        "checks": [check.to_dict() for check in all_checks],
        "references": {
            "nist_cfast_csv": str(CFAST_DIR / "r0_hall_window_360_compartments.csv"),
            "cfast_case": str(REPORTS_DIR / "cfast_r0_window_360.json"),
            "ghanekar_case": str(REPORTS_DIR / "ghanekar_bedroom_hallway.json"),
        },
    }

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    out_path = REPORTS_DIR / "reference_checks.json"
    out_path.write_text(json.dumps(output, indent=2), encoding="utf-8")

    status = "PASS" if not failed else "FAIL"
    print(f"[Reference Checks] {status}: {len(required) - len(failed)}/{len(required)} required checks passed")
    if known_gaps:
        print(f"[Reference Checks] Known gaps: {len(known_gaps)} non-gating checks did not pass")
    print(f"[Reference Checks] Report: {out_path}")

    if failed:
        for check in failed:
            print(
                f"  FAIL {check.name}: actual={check.actual} expected={check.expected} "
                f"tol={check.tolerance} min={check.minimum} max={check.maximum}"
            )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
