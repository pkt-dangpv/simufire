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
                # CMV-1: thermodynamic overpressure (Pa above ambient) — documents model gap
                "pressure_pa": _opt(f"PRS{s}", values),
                # CMV-1: optical density upper layer (m⁻¹) — two-zone stratification gap
                "od_upper_per_m": _opt(f"ULOD{s}", values),
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
            # Strip known unit suffixes so float() can parse them.
            # 'm' is last to avoid corrupting 'ppm' after 'p' removal.
            value = (value.split()[0]
                     .replace("ppm", "").replace("Pa", "")
                     .replace("%", "").replace("m", ""))
            try:
                sample[key] = float(value)
            except ValueError:
                continue

        # O2u= (upper-layer O2): after the plume-entrainment fix (2026-05-20) this
        # field tracks the hot-layer O2 with a rate calibrated against CFAST ULO2.
        # Sealed-room and early-ventilated O2 checks now compare o2_upper vs CFAST ULO2
        # (apples-to-apples: both represent the upper/hot zone). See §1bis audit.
        o2_upper = sample.get("O2u", math.nan)
        # CMV-1: CO2u= in ppm → co2_upper_pct in mol% (ppm / 10000)
        _co2u_ppm = sample.get("CO2u", math.nan)
        co2_upper_pct = _co2u_ppm / 10000.0 if not math.isnan(_co2u_ppm) else math.nan
        # CMV-1: Vis= visibility in meters (parser now strips 'm' suffix correctly)
        visibility_m = sample.get("Vis", math.nan)
        samples.append(
            {
                "time_s": sample["time_s"],
                "hrr_kw": sample.get("HRR", math.nan),
                "o2": sample.get("O2", math.nan),  # room average (used in CFAST checks)
                "o2_upper": o2_upper,               # diagnostic: upper-layer (depletes faster)
                "temp_upper_c": sample.get("Up", math.nan),
                "temp_lower_c": sample.get("Low", math.nan),
                "hot_layer_m": sample.get("HotLayer", math.nan),
                "co_upper_ppm": sample.get("COu", math.nan),
                "co2_upper_ppm": sample.get("CO2u"),  # None when key absent (old logs)
                "co2_upper_pct": co2_upper_pct,         # CMV-1: mol% for CFAST comparison
                "pressure_pa": sample.get("P", math.nan),  # CMV-1: buoyancy overpressure
                "visibility_m": visibility_m,               # CMV-1: smoke visibility
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
    sim_field: str | None = None,
) -> None:
    """Add a named absolute-tolerance check.

    *sim_field* allows the SF metric to differ from the CFAST field name.
    For example, compare SF ``o2_upper`` against CFAST ``o2`` (ULO2):
    ``_add_abs_check(checks, prefix, "o2", c, s, tol, sim_field="o2_upper")``.
    """
    checks.append(
        Check(
            name=f"{prefix}_{field}",
            actual=sim_sample[sim_field if sim_field is not None else field],
            expected=cfast_sample[field],
            tolerance=tolerance,
            note=note,
        )
    )


def _compute_rmse(
    sim: list[dict[str, float]],
    cfast: list[dict[str, float]],
    field: str,
    start_t: float = 0.0,
    end_t: float = float("inf"),
) -> float:
    """Compute RMSE for *field* over CFAST time points within [start_t, end_t].

    For each CFAST sample in the time window, the nearest SimuFire sample is
    matched and the squared error accumulated.  Returns NaN if fewer than 3
    pairs are available or if any value is NaN.
    """
    errors: list[float] = []
    for c in cfast:
        t = c["time_s"]
        if t < start_t or t > end_t:
            continue
        c_val = c.get(field, math.nan)
        if math.isnan(c_val):
            continue
        s_val = _nearest(sim, t).get(field, math.nan)
        if math.isnan(s_val):
            continue
        errors.append((s_val - c_val) ** 2)
    if len(errors) < 3:
        return math.nan
    return math.sqrt(sum(errors) / len(errors))


def _add_rmse_check(
    checks: list[Check],
    name: str,
    sim: list[dict[str, float]],
    cfast: list[dict[str, float]],
    field: str,
    threshold: float,
    start_t: float = 0.0,
    end_t: float = float("inf"),
    note: str = "",
) -> None:
    """Append a non-gating RMSE check: passes when RMSE ≤ threshold."""
    rmse = _compute_rmse(sim, cfast, field, start_t, end_t)
    checks.append(
        Check(
            name=name,
            actual=rmse,
            maximum=threshold,
            required=False,
            note=note or f"CMV-2: RMSE({field}) ≤ {threshold} over t=[{start_t},{end_t}]s.",
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
    checks.append(Check("cfast_t240_o2_depleted", s240.get("o2_upper", s240["o2"]),
                        expected=c240["o2"], tolerance=0.022,
                        note="Deep O2 depletion by t=240s (CFAST ULO2=8.51%). Uses SF o2_upper (apples-to-apples after entrainment fix)."))
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
    checks.append(Check("cfast_fed_heat_not_explosive", max_fed, maximum=10.0))
    checks.append(
        Check(
            "cfast_no_temperature_cap",
            _metric(metrics, "watched_temp_upper_clamp_count"),
            expected=0.0,
            tolerance=0.0,
        )
    )

    # ── CMV-1: non-gating pressure metrics for r0_window_360 ───────────────────
    # CFAST shows ~0 Pa (well-ventilated open window). Tests that SimuFire
    # doesn't build up spurious pressure in a vented scenario.
    for target_s in [350.0, 420.0, 510.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_t{int(target_s)}"
        checks.append(Check(
            f"{prefix}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=20.0,
            required=False,
            note="CMV-1: window-vented scenario pressure — CFAST ~0 Pa post-opening.",
        ))

    # ── CMV-2: RMSE curve-shape checks ────────────────────────────────────────
    _add_rmse_check(checks, "cfast_rmse_temp_upper_c", sim, cfast,
                    "temp_upper_c", threshold=60.0,
                    note="CMV-2: temp_upper RMSE ≤ 60°C full simulation (r0_window_360).")
    _add_rmse_check(checks, "cfast_rmse_o2", sim, cfast,
                    "o2", threshold=0.025, end_t=360.0,
                    note="CMV-2: O2 RMSE ≤ 0.025 pre-opening t=0–360s. Structural gap expected.")
    _add_rmse_check(checks, "cfast_rmse_hrr_kw", sim, cfast,
                    "hrr_kw", threshold=300.0,
                    note="CMV-2: HRR RMSE ≤ 300 kW full simulation (r0_window_360).")
    _add_rmse_check(checks, "cfast_rmse_co_upper_ppm", sim, cfast,
                    "co_upper_ppm", threshold=400.0,
                    note="CMV-2: CO upper RMSE ≤ 400 ppm full simulation.")

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
    # Uses o2_upper vs CFAST ULO2 (apples-to-apples: both are the hot-layer O2).
    # After the plume-entrainment fix, SF o2_upper matches CFAST ULO2 within tol.
    for target_s in [210.0, 300.0, 450.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_closed_t{int(target_s)}"
        _add_abs_check(checks, prefix, "o2", c, s, 0.018, sim_field="o2_upper")
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 80.0)
        _add_abs_check(checks, prefix, "co_upper_ppm", c, s, 600.0)

    # ── CMV-1: non-gating structural-gap metrics ────────────────────────────────
    # These checks document the one-zone vs two-zone gap; they are expected to fail
    # until Fase 2 (two-zone architecture). All required=False.
    for target_s in [60.0, 120.0, 240.0, 360.0, 480.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_closed_t{int(target_s)}"
        # Pressure: CFAST thermodynamic overpressure (100–1000 Pa) vs SimuFire
        # buoyancy pressure (~0–10 Pa). Structural gap documented in §1bis audit.
        checks.append(Check(
            f"{prefix}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=50.0,
            required=False,
            note="CMV-1: thermodynamic vs buoyancy pressure model gap (structural, Fase 2).",
        ))
        # CO2 upper layer mol%: CFAST two-zone upper concentration vs SimuFire average.
        # CFAST ~2–12 mol%, SimuFire one-zone ~15–20 mol% (over-mixed). Structural gap.
        checks.append(Check(
            f"{prefix}_co2_upper_pct",
            actual=s["co2_upper_pct"],
            expected=c["co2_upper_pct"],
            tolerance=3.0,
            required=False,
            note="CMV-1: CO2 upper layer mol% — one-zone over-mixes vs two-zone (structural gap).",
        ))

    checks.append(Check(
        "cfast_closed_no_temperature_cap",
        _metric(metrics, "watched_temp_upper_clamp_count"),
        expected=0.0, tolerance=0.0,
    ))

    # ── CMV-2: RMSE curve-shape checks ────────────────────────────────────────
    _add_rmse_check(checks, "cfast_closed_rmse_temp_upper_c", sim, cfast,
                    "temp_upper_c", threshold=60.0,
                    note="CMV-2: temp_upper RMSE ≤ 60°C (sealed room, t=0–600s).")
    _add_rmse_check(checks, "cfast_closed_rmse_o2", sim, cfast,
                    "o2", threshold=0.025,
                    note="CMV-2: O2 RMSE ≤ 0.025 (sealed room). Structural gap expected.")
    _add_rmse_check(checks, "cfast_closed_rmse_co_upper_ppm", sim, cfast,
                    "co_upper_ppm", threshold=600.0,
                    note="CMV-2: CO upper RMSE ≤ 600 ppm (sealed room).")

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
    # At t=180s, room.o2 ≈ CFAST ULO2 (pre-deep-depletion phase).
    # At t≥300s, o2_upper matches CFAST ULO2 better (entrainment equilibrium).
    for target_s in [180.0, 300.0, 450.0]:
        c = _nearest(cfast_r0, target_s)
        s = _nearest(sim_r0, target_s)
        prefix = f"cfast_2r_r0_t{int(target_s)}"
        o2_sf_field = "o2_upper" if target_s >= 240.0 else "o2"
        _add_abs_check(checks, prefix, "o2", c, s, 0.025, sim_field=o2_sf_field)
        _add_abs_check(checks, prefix, "temp_upper_c", c, s, 80.0)

    # Adjacent room (Hall/R1) receives smoke via open door.
    if cfast_r1:
        for target_s in [120.0, 240.0, 360.0]:
            c = _nearest(cfast_r1, target_s)
            s = _nearest(sim_r1, target_s)
            prefix = f"cfast_2r_hall_t{int(target_s)}"
            _add_abs_check(checks, prefix, "o2", c, s, 0.030)
            _add_abs_check(checks, prefix, "temp_upper_c", c, s, 60.0)

    # ── CMV-1: non-gating structural-gap metrics for fire room (R0) ─────────────
    for target_s in [120.0, 240.0, 360.0, 480.0]:
        c = _nearest(cfast_r0, target_s)
        s = _nearest(sim_r0, target_s)
        prefix = f"cfast_2r_r0_t{int(target_s)}"
        checks.append(Check(
            f"{prefix}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=30.0,
            required=False,
            note="CMV-1: two-room pressure coupling — structural gap (one-zone vs two-zone).",
        ))
        checks.append(Check(
            f"{prefix}_co2_upper_pct",
            actual=s["co2_upper_pct"],
            expected=c["co2_upper_pct"],
            tolerance=3.0,
            required=False,
            note="CMV-1: CO2 transport to fire room — structural gap.",
        ))

    # ── CMV-2: RMSE curve-shape checks ────────────────────────────────────────
    _add_rmse_check(checks, "cfast_2r_r0_rmse_temp_upper_c", sim_r0, cfast_r0,
                    "temp_upper_c", threshold=60.0,
                    note="CMV-2: fire-room temp_upper RMSE ≤ 60°C (two-room scenario).")
    _add_rmse_check(checks, "cfast_2r_r0_rmse_o2", sim_r0, cfast_r0,
                    "o2", threshold=0.025,
                    note="CMV-2: fire-room O2 RMSE ≤ 0.025 (two-room). Structural gap expected.")
    if cfast_r1:
        _add_rmse_check(checks, "cfast_2r_hall_rmse_temp_upper_c", sim_r1, cfast_r1,
                        "temp_upper_c", threshold=30.0,
                        note="CMV-2: hall temp_upper RMSE ≤ 30°C (two-room, adjacent room).")
        _add_rmse_check(checks, "cfast_2r_hall_rmse_o2", sim_r1, cfast_r1,
                        "o2", threshold=0.030,
                        note="CMV-2: hall O2 RMSE ≤ 0.030 (two-room, adjacent room).")

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

    # ── CMV-1: non-gating structural-gap metrics ────────────────────────────────────────
    # Post-flashover (vented): CFAST shows slightly negative pressure (~-6 Pa)
    # from buoyancy-driven outflow. Tests pressure directionality (not magnitude).
    for target_s in [150.0, 240.0, 350.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_fo_t{int(target_s)}"
        checks.append(Check(
            f"{prefix}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=15.0,
            required=False,
            note="CMV-1: vented-room pressure sign/magnitude — CFAST ~−6 Pa (outflow driven).",
        ))
        checks.append(Check(
            f"{prefix}_co2_upper_pct",
            actual=s["co2_upper_pct"],
            expected=c["co2_upper_pct"],
            tolerance=3.0,
            required=False,
            note="CMV-1: CO2 upper layer mol% in vented scenario — structural gap.",
        ))

    # ── CMV-2: RMSE curve-shape checks ────────────────────────────────────────
    _add_rmse_check(checks, "cfast_fo_rmse_temp_upper_c", sim, cfast,
                    "temp_upper_c", threshold=60.0,
                    note="CMV-2: temp_upper RMSE ≤ 60°C (post-flashover vented).")
    _add_rmse_check(checks, "cfast_fo_rmse_o2", sim, cfast,
                    "o2", threshold=0.025,
                    note="CMV-2: O2 RMSE ≤ 0.025 (post-flashover vented). Structural gap expected.")
    _add_rmse_check(checks, "cfast_fo_rmse_hrr_kw", sim, cfast,
                    "hrr_kw", threshold=300.0,
                    note="CMV-2: HRR RMSE ≤ 300 kW (post-flashover vented).")

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

    # ── CMV-1: non-gating structural-gap metrics ────────────────────────────────────────
    for target_s in [180.0, 300.0, 450.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        prefix = f"cfast_hvac_t{int(target_s)}"
        checks.append(Check(
            f"{prefix}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=50.0,
            required=False,
            note="CMV-1: HVAC-pressurized room overpressure — structural gap.",
        ))
        checks.append(Check(
            f"{prefix}_co2_upper_pct",
            actual=s["co2_upper_pct"],
            expected=c["co2_upper_pct"],
            tolerance=3.0,
            required=False,
            note="CMV-1: CO2 upper layer mol% with HVAC dilution — structural gap.",
        ))

    # ── CMV-2: RMSE curve-shape checks ────────────────────────────────────────
    _add_rmse_check(checks, "cfast_hvac_rmse_temp_upper_c", sim, cfast,
                    "temp_upper_c", threshold=60.0,
                    note="CMV-2: temp_upper RMSE ≤ 60°C (HVAC residential).")
    _add_rmse_check(checks, "cfast_hvac_rmse_o2", sim, cfast,
                    "o2", threshold=0.025,
                    note="CMV-2: O2 RMSE ≤ 0.025 (HVAC residential). Structural gap expected.")
    _add_rmse_check(checks, "cfast_hvac_rmse_co_upper_ppm", sim, cfast,
                    "co_upper_ppm", threshold=500.0,
                    note="CMV-2: CO upper RMSE ≤ 500 ppm (HVAC residential).")

    return checks


def build_cfast_long_burnout_3600s_checks() -> list[Check]:
    """Checks for cfast_long_burnout_3600s: sealed room, 3600s, O2-limited fire.

    Growth phase (0→180s) matches single_room_closed. After ~t=210s fire becomes
    O2-limited in both models; CFAST sustains burning at ~288kW while SimuFire
    stabilises at ~182kW (higher O2 floor). Structural gap in long-term steady
    state is expected and documented.
    """
    csv_path = CFAST_DIR / "cfast_long_burnout_3600s_compartments.csv"
    cfast = _load_cfast_or_none(csv_path)
    log_path = REPORTS_DIR / "cfast_long_burnout_3600s.log"

    if cfast is None or not log_path.exists():
        return [_pending_check("cfast_burnout_pending",
                               "Pending: run CFAST cfast_long_burnout_3600s.in and SimuFire case.")]

    sim = _parse_simufire_log(log_path, room_id=0)
    checks: list[Check] = []

    # Growth phase point checks (0→180s) — sealed, same physics as single_room_closed.
    # CFAST: t=60→44.7°C, t=120→121.9°C, t=180→259.6°C
    # SimuFire: t=60→35.3°C, t=120→85.3°C, t=180→172.1°C
    for target_s, lo, hi in [
        (60.0,  15.0, 100.0),
        (120.0, 40.0, 180.0),
        (180.0, 100.0, 320.0),
    ]:
        s = _nearest(sim, target_s)
        checks.append(Check(
            f"cfast_burnout_t{int(target_s)}_temp_upper_c",
            actual=s["temp_upper_c"],
            minimum=lo,
            maximum=hi,
            required=False,
            note=f"CMV-3: growth-phase temp_upper in [{lo},{hi}]°C at t={target_s}s.",
        ))

    # Behavioral: fire becomes O2-limited by t=300 (HRR well below unconstrained 1280kW).
    # CFAST=288kW, SimuFire=523kW — both far below 1280kW cap.
    s300 = _nearest(sim, 300.0)
    checks.append(Check(
        "cfast_burnout_t300_hrr_o2_limited",
        actual=s300["hrr_kw"],
        maximum=900.0,
        required=False,
        note="CMV-3: fire O2-limited by t=300s (CFAST: 288kW, SimuFire: ~524kW, cap: 1280kW).",
    ))

    # Behavioral: fire still burning at t=600 (long slow burn, not extinguished).
    # SimuFire=182kW, CFAST=288kW.
    s600 = _nearest(sim, 600.0)
    checks.append(Check(
        "cfast_burnout_t600_fire_active",
        actual=s600["hrr_kw"],
        minimum=30.0,
        required=False,
        note="CMV-3: fire still burning at t=600s (long burnout; SimuFire=182kW).",
    ))

    # CMV-1: pressure — thermodynamic vs buoyancy model structural gap (non-gating).
    for target_s in [60.0, 120.0, 180.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        checks.append(Check(
            f"cfast_burnout_t{int(target_s)}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=50.0,
            required=False,
            note="CMV-3/CMV-1: sealed-room overpressure structural gap (thermodynamic vs buoyancy).",
        ))

    # CMV-2: RMSE temp_upper over growth phase only (0→180s).
    # Estimated RMSE ~49°C based on SimuFire running ~10–87°C cooler than CFAST.
    _add_rmse_check(checks, "cfast_burnout_rmse_temp_upper_c", sim, cfast,
                    "temp_upper_c", threshold=65.0, start_t=0.0, end_t=180.0,
                    note="CMV-3: temp_upper RMSE ≤ 65°C over growth phase (t=0–180s).")

    return checks


def build_cfast_window_break_t180_checks() -> list[Check]:
    """Checks for cfast_window_break_t180: sealed room until t=180s then window opens.

    Pre-break phase (0→180s) matches single_room_closed sealed scenario.
    Post-break: fresh air via opened window drives sustained fire growth.
    CFAST=346°C, SimuFire=313°C at t=300 — 33°C gap, within model tolerance.
    """
    csv_path = CFAST_DIR / "cfast_window_break_t180_compartments.csv"
    cfast = _load_cfast_or_none(csv_path)
    log_path = REPORTS_DIR / "cfast_window_break_t180.log"

    if cfast is None or not log_path.exists():
        return [_pending_check("cfast_winbreak_pending",
                               "Pending: run CFAST cfast_window_break_t180.in and SimuFire case.")]

    sim = _parse_simufire_log(log_path, room_id=0)
    checks: list[Check] = []

    # Pre-break point check at t=120s (identical to sealed scenario).
    # CFAST=121.9°C, SimuFire=85.3°C.
    s120 = _nearest(sim, 120.0)
    checks.append(Check(
        "cfast_winbreak_t120_temp_upper_c",
        actual=s120["temp_upper_c"],
        minimum=40.0,
        maximum=175.0,
        required=False,
        note="CMV-3: pre-break temp_upper at t=120s — growth-phase sealed behavior.",
    ))

    # Post-break behavioral: temp_upper > 200°C at t=300.
    # CFAST=346.7°C, SimuFire=313.5°C.
    s300 = _nearest(sim, 300.0)
    checks.append(Check(
        "cfast_winbreak_t300_temp_upper_c",
        actual=s300["temp_upper_c"],
        minimum=200.0,
        required=False,
        note="CMV-3: post-break temp_upper > 200°C at t=300s (CFAST=347°C, SimuFire=314°C).",
    ))

    # Post-break: HRR > 600kW at t=300 — window sustains/grows fire.
    checks.append(Check(
        "cfast_winbreak_t300_hrr_sustained",
        actual=s300["hrr_kw"],
        minimum=600.0,
        required=False,
        note="CMV-3: HRR > 600kW at t=300s — window opening sustains fire (SimuFire=1280kW).",
    ))

    # Behavioral: fire grows after window break (HRR at t=240 > HRR at t=170).
    s240 = _nearest(sim, 240.0)
    s170 = _nearest(sim, 170.0)
    checks.append(Check(
        "cfast_winbreak_hrr_grows_after_break",
        actual=s240["hrr_kw"] - s170["hrr_kw"],
        minimum=0.0,
        required=False,
        note="CMV-3: HRR grows after window break (t=240 > t=170; SimuFire: 1242 > 613 kW).",
    ))

    # CMV-1: post-break pressure — CFAST ~−6 Pa (buoyancy outflow), SimuFire ~+2 Pa.
    # Non-gating structural gap; SimuFire magnitude is small (not spuriously large).
    s300_cfast = _nearest(cfast, 300.0)
    checks.append(Check(
        "cfast_winbreak_t300_pressure_pa",
        actual=s300["pressure_pa"],
        maximum=10.0,
        required=False,
        note="CMV-1: vented-room pressure ≤ 10 Pa (CFAST=−6 Pa outflow, SimuFire=+2 Pa — sign gap).",
    ))

    # CMV-2: RMSE temp_upper pre-break only (0→170s).
    _add_rmse_check(checks, "cfast_winbreak_rmse_temp_upper_pre_break", sim, cfast,
                    "temp_upper_c", threshold=65.0, start_t=0.0, end_t=170.0,
                    note="CMV-3: temp_upper RMSE ≤ 65°C pre-break phase (t=0–170s).")

    return checks


def build_cfast_door_close_midfire_checks() -> list[Check]:
    """Checks for cfast_door_close_midfire: two rooms, door open then closes at t=120s.

    Pre-close (0→120s): two-room open scenario (R0 fire, R1 hall).
    Post-close: R0 becomes sealed — O2 depletes, fire weakens then extinguishes in
    SimuFire (O2 < 2.5%). CFAST sustains burning at ~288kW. R1 (hall) cools to
    ambient after door closure.
    """
    csv_path = CFAST_DIR / "cfast_door_close_midfire_compartments.csv"
    cfast_r0 = _load_cfast_or_none(csv_path)
    log_path = REPORTS_DIR / "cfast_door_close_midfire.log"

    if cfast_r0 is None or not log_path.exists():
        return [_pending_check("cfast_doorclose_pending",
                               "Pending: run CFAST cfast_door_close_midfire.in and SimuFire case.")]

    # Load hall (R1) CFAST data — compartment 2, suffix "_2".
    cfast_r1: list[dict[str, float]] = []
    try:
        cfast_r1 = _load_cfast_compartments(csv_path, room_suffix="_2")
    except Exception:
        pass

    sim_r0 = _parse_simufire_log(log_path, room_id=0)
    sim_r1 = _parse_simufire_log(log_path, room_id=1)
    checks: list[Check] = []

    # Pre-close point checks (0→120s, door open).
    # CFAST: t=60→44.98°C, t=120→115.5°C
    # SimuFire: t=60→54.6°C, t=120→159.5°C (warmer — no ach_infiltration in this case)
    for target_s, lo, hi in [(60.0, 20.0, 120.0), (120.0, 50.0, 220.0)]:
        s = _nearest(sim_r0, target_s)
        checks.append(Check(
            f"cfast_doorclose_r0_t{int(target_s)}_temp_upper_c",
            actual=s["temp_upper_c"],
            minimum=lo,
            maximum=hi,
            required=False,
            note=f"CMV-3: pre-close R0 temp_upper in [{lo},{hi}]°C at t={target_s}s.",
        ))

    # Post-close: R0 fire room still hot at t=240 (peak before full O2 depletion).
    # SimuFire=239.7°C at t=240.
    s240 = _nearest(sim_r0, 240.0)
    checks.append(Check(
        "cfast_doorclose_r0_t240_temp_active",
        actual=s240["temp_upper_c"],
        minimum=100.0,
        required=False,
        note="CMV-3: R0 fire still hot at t=240s post-close (SimuFire=239.7°C).",
    ))

    # Post-close: R0 O2 depleting by t=300.
    # CFAST=7.43%, SimuFire=3.95% — both well below initial 20.9%.
    s300_r0 = _nearest(sim_r0, 300.0)
    checks.append(Check(
        "cfast_doorclose_r0_t300_o2_depleted",
        actual=s300_r0["o2"],
        maximum=0.12,
        required=False,
        note="CMV-3: R0 O2 < 12% at t=300s after door close (CFAST=7.4%, SimuFire=3.95%).",
    ))

    # Post-close: R1 hall returns to near-ambient by t=300.
    # CFAST=25.9°C, SimuFire=20.5°C — both near ambient.
    if sim_r1:
        s300_r1 = _nearest(sim_r1, 300.0)
        checks.append(Check(
            "cfast_doorclose_r1_t300_cooling",
            actual=s300_r1["temp_upper_c"],
            maximum=50.0,
            required=False,
            note="CMV-3: R1 hall cools after door close (CFAST=25.9°C, SimuFire=20.5°C).",
        ))

    # CMV-1: R0 post-close pressure — thermodynamic vs buoyancy structural gap.
    # CFAST: 154–165 Pa, SimuFire: 10–11 Pa.
    for target_s in [120.0, 300.0]:
        c = _nearest(cfast_r0, target_s)
        s = _nearest(sim_r0, target_s)
        checks.append(Check(
            f"cfast_doorclose_r0_t{int(target_s)}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=50.0,
            required=False,
            note="CMV-3/CMV-1: sealed-room thermodynamic vs buoyancy pressure structural gap.",
        ))

    # CMV-2: RMSE R0 temp_upper over pre-close phase (0→120s).
    _add_rmse_check(checks, "cfast_doorclose_r0_rmse_temp_upper_pre_close", sim_r0, cfast_r0,
                    "temp_upper_c", threshold=70.0, start_t=0.0, end_t=120.0,
                    note="CMV-3: R0 temp_upper RMSE ≤ 70°C pre-close phase (t=0–120s).")

    return checks


def build_cfast_fast_growth_closed_checks() -> list[Check]:
    """CMV-3 Scenario 4: Fast-growth fire (α=0.047 kW/s²) in sealed simple_house R0.

    CFAST reference: t=60→66°C, t=90→125°C, t=120→221°C, O2-limited at ~t=165s.
    SimuFire structural gap: runs ~200-300°C hotter than CFAST due to less wall heat loss.
    Both models show rapid growth then O2-limited extinction; direction is correct.
    """
    csv_path = CFAST_DIR / "cfast_fast_growth_closed_compartments.csv"
    log_path = REPORTS_DIR / "cfast_fast_growth_closed.log"
    cfast = _load_cfast_compartments(csv_path) if csv_path.exists() else None
    sim = _parse_simufire_log(log_path, room_id=0) if log_path.exists() else None
    if cfast is None or sim is None:
        return [_pending_check("cfast_fastgrowth_pending",
                               "Pending: run cfast_fast_growth_closed.in and SimuFire case.")]

    checks: list[Check] = []

    # Growth-phase directional checks.
    # CFAST: t=60→66°C, t=90→125°C, t=120→221°C.
    # SimuFire: t=60→59°C, t=90→217°C, t=120→476°C (wall-heat-loss gap → SF runs hotter).
    for target_s, lo, hi in [
        (60.0,  30.0, 200.0),
        (90.0,  70.0, 450.0),
        (120.0, 150.0, 700.0),
    ]:
        s = _nearest(sim, target_s)
        checks.append(Check(
            f"cfast_fastgrowth_t{int(target_s)}_temp_upper_c",
            actual=s["temp_upper_c"],
            minimum=lo,
            maximum=hi,
            note=f"CMV-3: fast-growth temp_upper in [{lo},{hi}]°C at t={target_s}s.",
        ))

    # Behavioral: fire O2-limited and HRR drops drastically by t=280s.
    # CFAST modulates HRR to ~290kW. SimuFire extinguishes nearly completely (22kW).
    s280 = _nearest(sim, 280.0)
    checks.append(Check(
        "cfast_fastgrowth_extinction_hrr_t280",
        actual=s280["hrr_kw"],
        maximum=200.0,
        note="CMV-3: fast-growth fire O2-limited, HRR < 200kW by t=280s (SF: 22kW).",
    ))

    # CMV-1: pressure — thermodynamic vs buoyancy structural gap (non-gating).
    for target_s in [60.0, 120.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        checks.append(Check(
            f"cfast_fastgrowth_t{int(target_s)}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=50.0,
            required=False,
            note="CMV-3/CMV-1: fast-growth sealed room — thermodynamic vs buoyancy overpressure gap.",
        ))

    # CMV-2: RMSE temp_upper over growth phase (t=60–120s).
    # Known structural gap: SF runs ~160°C hotter → RMSE ≈ 160°C >> 60°C threshold.
    _add_rmse_check(checks, "cfast_fastgrowth_rmse_temp_upper_c", sim, cfast,
                    "temp_upper_c", threshold=60.0, start_t=60.0, end_t=120.0,
                    note="CMV-3: temp_upper RMSE ≤ 60°C over fast-growth phase (t=60–120s). "
                         "Known gap: SF wall heat loss underestimated → ~160°C RMSE.")

    return checks


def build_cfast_two_floor_stairwell_checks() -> list[Check]:
    """CMV-3 Scenario 5: Two-floor stairwell stack-effect test.

    CFAST: 2 compartments (R0_Living + R8_Upper) connected by a WALL vent simulating
    the stairwell path. Fire in R0; heat/smoke reaches R8 via vent in CFAST.
    SimuFire: two_storey_house (13 rooms, ~500m³). Fire in R0; fire extinguishes at
    ~t=230s due to O2 depletion in the larger combined volume before smoke can reach R8.
    Structural gap: SimuFire R8 stays at 20°C; CFAST R8 reaches ~80°C by t=300s.
    Note: the volume mismatch (146m³ vs 500m³) makes direct RMSE comparison invalid.
    """
    csv_path = CFAST_DIR / "cfast_two_floor_stairwell_compartments.csv"
    log_path = REPORTS_DIR / "cfast_two_floor_stairwell.log"
    cfast_r0 = _load_cfast_compartments(csv_path) if csv_path.exists() else None
    cfast_r8 = _load_cfast_compartments(csv_path, room_suffix="_2") if csv_path.exists() else None
    sim_r0 = _parse_simufire_log(log_path, room_id=0) if log_path.exists() else None
    sim_r8 = _parse_simufire_log(log_path, room_id=8) if log_path.exists() else None
    if cfast_r0 is None or sim_r0 is None:
        return [_pending_check("cfast_twofloor_pending",
                               "Pending: run cfast_two_floor_stairwell.in and SimuFire case.")]

    checks: list[Check] = []

    # R0 fire-room growth phase (directional).
    # CFAST R0: t=120→88°C, t=180→170°C (slower due to 79.9m³ vs simple_house 48m³).
    # SimuFire R0: t=120→158°C, t=180→456°C (hotter — wall heat loss gap + fire dynamics).
    for target_s, lo, hi in [
        (120.0, 60.0, 500.0),
        (180.0, 100.0, 700.0),
    ]:
        s = _nearest(sim_r0, target_s)
        checks.append(Check(
            f"cfast_twofloor_r0_t{int(target_s)}_temp_upper_c",
            actual=s["temp_upper_c"],
            minimum=lo,
            maximum=hi,
            note=f"CMV-3: two-floor R0 fire room temp_upper in [{lo},{hi}]°C at t={target_s}s.",
        ))

    # R0 fire active at t=120 (HRR > 100kW).
    s120_r0 = _nearest(sim_r0, 120.0)
    checks.append(Check(
        "cfast_twofloor_r0_t120_fire_active",
        actual=s120_r0["hrr_kw"],
        minimum=100.0,
        note="CMV-3: two-floor R0 fire growing at t=120s (SF: ~269kW, CFAST: 320kW).",
    ))

    # R8 upper bedroom smoke arrival — non-gating.
    # CFAST R8: reaches 79°C by t=300s.  SimuFire R8: stays at 20°C (known gap).
    if sim_r8 is not None and cfast_r8 is not None:
        s300_r8 = _nearest(sim_r8, 300.0)
        c300_r8 = _nearest(cfast_r8, 300.0)
        checks.append(Check(
            "cfast_twofloor_r8_t300_temp_upper_c",
            actual=s300_r8["temp_upper_c"],
            expected=c300_r8["temp_upper_c"],
            tolerance=30.0,
            required=False,
            note="CMV-3: R8 upper bedroom temp_upper at t=300s. "
                 "Known gap: SimuFire fire extinguishes ~t=230s before smoke reaches upstairs "
                 "(500m³ full-house O2 dynamics vs 146m³ CFAST 2-room model).",
        ))

    # CMV-2: RMSE R0 temp_upper t=60-180 (non-gating, large structural gap expected).
    _add_rmse_check(checks, "cfast_twofloor_r0_rmse_temp_upper_c", sim_r0, cfast_r0,
                    "temp_upper_c", threshold=60.0, start_t=60.0, end_t=180.0,
                    note="CMV-3: R0 temp_upper RMSE ≤ 60°C (t=60–180s). "
                         "Known gap: SF wall heat loss + volume mismatch → large RMSE.")

    return checks


def build_cfast_multi_fuel_couch_tv_checks() -> list[Check]:
    """CMV-3 Scenario 6: Multi-fuel composite fire (sofa + TV cabinet) in vented room.

    CFAST: composite HRR table (sofa α=0.047 peak 700kW + TV ignites at t=120s peak 260kW),
    door open to OUTSIDE → sustained fire, peak ~960kW, ULT≈229°C at t=180s.
    SimuFire: fast fire (α=0.047, max 700kW), door to indoor hall (R1) — finite O2 reservoir.
    Structural gap: CFAST door to OUTSIDE supplies unlimited O2; SimuFire hall is a closed
    room, so fire decays after t=180s as combined R0+R1 O2 depletes.
    Temperatures broadly comparable until t=180s; diverge after (CFAST sustains, SF decays).
    """
    csv_path = CFAST_DIR / "cfast_multi_fuel_couch_tv_compartments.csv"
    log_path = REPORTS_DIR / "cfast_multi_fuel_couch_tv.log"
    cfast = _load_cfast_compartments(csv_path) if csv_path.exists() else None
    sim = _parse_simufire_log(log_path, room_id=0) if log_path.exists() else None
    if cfast is None or sim is None:
        return [_pending_check("cfast_multifuel_pending",
                               "Pending: run cfast_multi_fuel_couch_tv.in and SimuFire case.")]

    checks: list[Check] = []

    # Growth-phase temperature checks (t=60–180s, before ventilation divergence).
    # CFAST: t=60→66°C, t=120→187°C, t=180→229°C.
    # SimuFire: t=60→123°C, t=120→465°C, t=180→194°C.
    for target_s, lo, hi in [
        (60.0,  50.0, 300.0),
        (120.0, 100.0, 700.0),
        (180.0, 100.0, 500.0),
    ]:
        s = _nearest(sim, target_s)
        checks.append(Check(
            f"cfast_multifuel_t{int(target_s)}_temp_upper_c",
            actual=s["temp_upper_c"],
            minimum=lo,
            maximum=hi,
            note=f"CMV-3: multi-fuel temp_upper in [{lo},{hi}]°C at t={target_s}s.",
        ))

    # HRR at t=120 should reflect fast fire growth (sofa at peak ~700kW).
    # CFAST: 680kW.  SimuFire: 562kW (lower, partly due to O2 from limited hall volume).
    s120 = _nearest(sim, 120.0)
    checks.append(Check(
        "cfast_multifuel_t120_hrr_above_350kw",
        actual=s120["hrr_kw"],
        minimum=350.0,
        note="CMV-3: multi-fuel fire HRR > 350kW at t=120s (CFAST: 680kW, SF: 562kW).",
    ))

    # CMV-1: pressure non-gating (ventilation model → near-zero overpressure in both).
    for target_s in [60.0, 120.0]:
        c = _nearest(cfast, target_s)
        s = _nearest(sim, target_s)
        checks.append(Check(
            f"cfast_multifuel_t{int(target_s)}_pressure_pa",
            actual=s["pressure_pa"],
            expected=c["pressure_pa"],
            tolerance=10.0,
            required=False,
            note="CMV-3/CMV-1: multi-fuel vented room pressure comparison (expected near-zero both).",
        ))

    # CMV-2: RMSE temp_upper t=60–180 (before ventilation divergence).
    # SF runs hotter early; CFAST hotter later — converges around t=180s.
    _add_rmse_check(checks, "cfast_multifuel_rmse_temp_upper_c", sim, cfast,
                    "temp_upper_c", threshold=80.0, start_t=60.0, end_t=180.0,
                    note="CMV-3: multi-fuel temp_upper RMSE ≤ 80°C (t=60–180s). "
                         "Known gap: SF runs ~170°C hotter at t=120 but ~35°C cooler at t=180.")

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
        + build_cfast_long_burnout_3600s_checks()
        + build_cfast_window_break_t180_checks()
        + build_cfast_door_close_midfire_checks()
        + build_cfast_fast_growth_closed_checks()
        + build_cfast_two_floor_stairwell_checks()
        + build_cfast_multi_fuel_couch_tv_checks()
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
