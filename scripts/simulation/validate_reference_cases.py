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


def _load_cfast_compartments(path: Path, room_suffix: str = "_1") -> list[dict[str, float]]:
    """Load CFAST compartment CSV for room with the given suffix (default '_1').

    Required columns (for suffix '_1'): Time, HRR_1, ULO2_1, ULT_1, LLT_1, HGT_1, ULCO_1.
    Optional columns loaded when present:
        ULCO2_{s}    -> co2_upper_pct  (mol %)
        LLO2_{s}     -> o2_lower       (mol fraction)
        LLCO_{s}     -> co_lower_ppm
        HRR_E{n}     -> hrr_expected_kw  (W -> kW)
    """
    s = room_suffix
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if len(rows) < 5:
        raise ValueError(f"CFAST CSV is too short: {path}")

    header = rows[0]
    index = {name: i for i, name in enumerate(header)}
    required_columns = ["Time", f"HRR{s.replace('_', '_', 1)}", f"ULO2{s}", f"ULT{s}", f"LLT{s}", f"HGT{s}", f"ULCO{s}"]
    # HRR column may be HRR_1 (single-room) – fall back gracefully
    if f"HRR{s}" not in index and "HRR_1" not in index:
        raise ValueError(f"CFAST CSV missing HRR column: {path}")
    hrr_col = f"HRR{s}" if f"HRR{s}" in index else "HRR_1"
    required_columns = ["Time", f"ULO2{s}", f"ULT{s}", f"LLT{s}", f"HGT{s}", f"ULCO{s}"]
    missing = [name for name in required_columns if name not in index]
    if missing:
        raise ValueError(f"CFAST CSV missing columns {missing}: {path}")

    def _opt(col: str, values: list[float]) -> float:
        return values[index[col]] if col in index else math.nan

    # Determine the fire number suffix (e.g., E1 for room 1)
    fire_num = s.lstrip("_")  # "1" from "_1"
    hrr_e_col = f"HRR_E{fire_num}"

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
                "hrr_kw": values[index[hrr_col]] / 1000.0,
                "o2": values[index[f"ULO2{s}"]] / 100.0,
                "temp_upper_c": values[index[f"ULT{s}"]],
                "temp_lower_c": values[index[f"LLT{s}"]],
                "hot_layer_m": values[index[f"HGT{s}"]],
                "co_upper_ppm": values[index[f"ULCO{s}"]] * 10000.0,
                # Optional enriched columns
                "co2_upper_pct": _opt(f"ULCO2{s}", values),
                "o2_lower": _opt(f"LLO2{s}", values) / 100.0 if f"LLO2{s}" in index else math.nan,
                "co_lower_ppm": _opt(f"LLCO{s}", values) * 10000.0 if f"LLCO{s}" in index else math.nan,
                "hrr_expected_kw": _opt(hrr_e_col, values) / 1000.0 if hrr_e_col in index else math.nan,
            }
        )
    return samples


def _load_cfast_walls(path: Path, room_suffix: str = "_1") -> list[dict[str, float]]:
    """Load CFAST wall-temperature CSV (e.g. *_walls.csv)."""
    s = room_suffix
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if len(rows) < 5:
        return []
    header = rows[0]
    index = {name: i for i, name in enumerate(header)}
    if "Time" not in index:
        return []

    def _opt(col: str, values: list[float]) -> float:
        return values[index[col]] if col in index else math.nan

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
                "ceilt_c": _opt(f"CEILT{s}", values),
                "uwallt_c": _opt(f"UWALLT{s}", values),
                "lwallt_c": _opt(f"LWALLT{s}", values),
                "floort_c": _opt(f"FLOORT{s}", values),
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
                "co2_upper_ppm": sample.get("CO2u"),  # None when key absent (old logs)
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

    # ── Growth phase (non-gating): verifies fire-growth calibration ────────────
    # CFAST data: t=60 → ULT=44.7°C, ULO2=20.05%; t=120 → ULT=121.9°C, ULO2=18.5%
    for target_s, exp_t, tol_t, exp_o2, tol_o2 in [
        (60.0,  44.66,  35.0, 0.20047, 0.015),
        (120.0, 121.88, 55.0, 0.18455, 0.022),
    ]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_t{int(target_s)}"
        checks.append(Check(f"{prefix}_temp_upper_c", s["temp_upper_c"],
                            expected=exp_t, tolerance=tol_t, required=False,
                            note="Non-gating growth-phase calibration check."))
        checks.append(Check(f"{prefix}_o2", s["o2"],
                            expected=exp_o2, tolerance=tol_o2, required=False,
                            note="Non-gating growth-phase calibration check."))

    # ── Ventilation-limited phase: O2 depletion and HRR suppression ────────────
    # CFAST at t=240: ULO2=8.51%, HRR_actual=276kW vs HRR_expected=1180kW (23%).
    c240 = _nearest(cfast, 240.0)
    s240 = _nearest(sim, 240.0)
    checks.append(Check("cfast_t240_o2_depleted", s240["o2"],
                        expected=c240["o2"], tolerance=0.022,
                        note="Deep O2 depletion by t=240s (CFAST: 8.51%)."))
    checks.append(Check("cfast_t240_hrr_ventilation_limited", s240["hrr_kw"],
                        maximum=420.0,
                        note="Fire must be ventilation-limited by t=240s (CFAST: 276kW vs 1180kW expected)."))

    # ── Pre-opening: CFAST remains ventilation-limited rather than numerically extinct.
    for target_s in [350.0, 360.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_t{int(target_s)}"
        _add_abs_check(checks, prefix, "hrr_kw", c, s, 90.0)
        _add_abs_check(checks, prefix, "o2", c, s, 0.015)
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 80.0)
        _add_abs_check(checks, prefix, "temp_lower_c", c, s, 45.0)
        _add_abs_check(checks, prefix, "hot_layer_m", c, s, 0.50)
        _add_abs_check(checks, prefix, "co_upper_ppm", c, s, 320.0,
                       note="CO upper layer pre-opening (CFAST: ~690 ppm).")

    # ── CO2 upper layer (non-gating until CO2u= key confirmed in log) ──────────
    # CFAST: t=350→11.06 mol%, t=420→6.08 mol%, t=510→5.23 mol% (×10000 = ppm)
    for target_s, exp_co2_pct, tol_ppm in [
        (350.0, 11.06, 28000.0),
        (420.0,  6.08, 22000.0),
        (510.0,  5.23, 20000.0),
    ]:
        s_co2 = _nearest(sim, target_s)
        checks.append(Check(
            f"cfast_t{int(target_s)}_co2_upper_ppm",
            actual=s_co2.get("co2_upper_ppm"),
            expected=exp_co2_pct * 10000.0,
            tolerance=tol_ppm,
            required=False,
            note="Non-gating: requires CO2u= key in log (updated SimulationLogWriter).",
        ))

    # ── The first 20 s after opening are intentionally smoothed in Simufire; require
    # physical recovery, not exact replication of CFAST's prescribed HRR jump.
    s380 = _nearest(sim, 380.0)
    checks.extend(
        [
            Check("cfast_t380_hrr_recovering", s380["hrr_kw"], minimum=300.0),
            Check("cfast_t380_upper_temp_bounded", s380["temp_upper_c"], maximum=500.0),
            Check("cfast_t380_o2_recovered", s380["o2"], minimum=0.10),
        ]
    )

    # ── Post-opening quasi-steady state ────────────────────────────────────────
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


def _pending_check(name: str, note: str) -> Check:
    """Placeholder for a check whose CFAST reference data does not yet exist."""
    return Check(name, actual=None, required=False, note=note)


def _load_cfast_or_none(path: Path) -> list[dict[str, float]] | None:
    """Return compartment samples list if path exists, else None."""
    if not path.exists():
        return None
    try:
        return _load_cfast_compartments(path)
    except Exception:
        return None


def build_cfast_single_room_closed_checks() -> list[Check]:
    """Checks for cfast_single_room_closed: sealed room, O2 depletion & CO buildup.

    CFAST scenario: R0 (4x5x2.4m), no vents, same wood fire.
    Run cfast_single_room_closed.in and place output CSV here before checks become active.
    """
    csv_path = CFAST_DIR / "cfast_single_room_closed_compartments.csv"
    cfast = _load_cfast_or_none(csv_path)
    log_path = REPORTS_DIR / "cfast_single_room_closed.log"

    if cfast is None or not log_path.exists():
        return [
            _pending_check(
                "cfast_closed_pending",
                "Pending: run CFAST with cfast_single_room_closed.in and re-run suite.",
            )
        ]

    sim = _parse_simufire_log(log_path, room_id=0)
    report_path = REPORTS_DIR / "cfast_single_room_closed.json"
    metrics = _load_json(report_path).get("metrics", {}) if report_path.exists() else {}
    checks: list[Check] = []

    # O2 depletes below LOL (10%) by t=~210s in sealed room.
    for target_s in [210.0, 300.0, 450.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_closed_t{int(target_s)}"
        _add_abs_check(checks, prefix, "o2", c, s, 0.018)
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 80.0)
        _add_abs_check(checks, prefix, "co_upper_ppm", c, s, 600.0)

    checks.append(Check(
        "cfast_closed_no_temperature_cap",
        _metric(metrics, "watched_temp_upper_clamp_count"),
        expected=0.0, tolerance=0.0,
    ))
    return checks


def build_cfast_two_room_door_open_checks() -> list[Check]:
    """Checks for cfast_two_room_door_open: R0 fire + Hall, door open from t=0.

    Tests inter-room smoke and O2 transport timing.
    Run cfast_two_room_door_open.in before these checks become active.
    """
    csv_path = CFAST_DIR / "cfast_two_room_door_open_compartments.csv"
    cfast_r0 = _load_cfast_or_none(csv_path)
    log_path = REPORTS_DIR / "cfast_two_room_door_open.log"

    if cfast_r0 is None or not log_path.exists():
        return [
            _pending_check(
                "cfast_two_room_door_pending",
                "Pending: run CFAST with cfast_two_room_door_open.in and re-run suite.",
            )
        ]

    # Load second compartment (Hall) data.
    cfast_r1: list[dict[str, float]] = []
    try:
        cfast_r1 = _load_cfast_compartments(csv_path, room_suffix="_2")
    except Exception:
        pass

    sim_r0 = _parse_simufire_log(log_path, room_id=0)
    sim_r1 = _parse_simufire_log(log_path, room_id=1)
    checks: list[Check] = []

    # Fire room (R0) ventilation-limited phase.
    for target_s in [180.0, 300.0, 450.0]:
        c = _nearest(cfast_r0, target_s)
        s = _nearest(sim_r0, target_s)
        prefix = f"cfast_2r_r0_t{int(target_s)}"
        _add_abs_check(checks, prefix, "o2", c, s, 0.025)
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 80.0)

    # Adjacent room (Hall/R1) receives smoke via open door.
    if cfast_r1:
        for target_s in [120.0, 240.0, 360.0]:
            c = _nearest(cfast_r1, target_s)
            s = _nearest(sim_r1, target_s)
            prefix = f"cfast_2r_hall_t{int(target_s)}"
            _add_abs_check(checks, prefix, "o2", c, s, 0.030)
            _add_abs_check(checks, prefix, "temp_upper_c", c, s, 60.0)

    return checks


def build_cfast_post_flashover_vented_checks() -> list[Check]:
    """Checks for cfast_post_flashover_vented: large fire, window open from t=0.

    Tests well-ventilated high-HRR steady state.
    Run cfast_post_flashover_vented.in before these checks become active.
    """
    csv_path = CFAST_DIR / "cfast_post_flashover_vented_compartments.csv"
    cfast = _load_cfast_or_none(csv_path)
    log_path = REPORTS_DIR / "cfast_post_flashover_vented.log"

    if cfast is None or not log_path.exists():
        return [
            _pending_check(
                "cfast_flashover_pending",
                "Pending: run CFAST with cfast_post_flashover_vented.in and re-run suite.",
            )
        ]

    sim = _parse_simufire_log(log_path, room_id=0)
    checks: list[Check] = []

    for target_s in [150.0, 240.0, 350.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_fo_t{int(target_s)}"
        _add_abs_check(checks, prefix, "hrr_kw", c, s, 300.0)
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 100.0)
        _add_abs_check(checks, prefix, "o2", c, s, 0.040)

    return checks


def build_cfast_hvac_residential_checks() -> list[Check]:
    """Checks for cfast_hvac_residential: R0 with mechanical ventilation (supply+return).

    Tests HVACSystem species transport and O2 dilution with fresh-air HVAC.
    Run cfast_hvac_residential.in before these checks become active.
    """
    csv_path = CFAST_DIR / "cfast_hvac_residential_compartments.csv"
    cfast = _load_cfast_or_none(csv_path)
    log_path = REPORTS_DIR / "cfast_hvac_residential.log"

    if cfast is None or not log_path.exists():
        return [
            _pending_check(
                "cfast_hvac_pending",
                "Pending: run CFAST with cfast_hvac_residential.in and re-run suite.",
            )
        ]

    sim = _parse_simufire_log(log_path, room_id=0)
    checks: list[Check] = []

    # HVAC fresh-air supply keeps O2 higher than sealed-room scenario.
    for target_s in [180.0, 300.0, 450.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_hvac_t{int(target_s)}"
        _add_abs_check(checks, prefix, "o2", c, s, 0.025)
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 80.0)
        _add_abs_check(checks, prefix, "co_upper_ppm", c, s, 500.0)

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
    all_checks = (
        build_cfast_checks()
        + build_cfast_single_room_closed_checks()
        + build_cfast_two_room_door_open_checks()
        + build_cfast_post_flashover_vented_checks()
        + build_cfast_hvac_residential_checks()
        + build_ghanekar_checks()
    )
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
            "cfast_new_scenarios": [
                str(CFAST_DIR / "cfast_single_room_closed.in"),
                str(CFAST_DIR / "cfast_two_room_door_open.in"),
                str(CFAST_DIR / "cfast_post_flashover_vented.in"),
                str(CFAST_DIR / "cfast_hvac_residential.in"),
            ],
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
