#!/usr/bin/env python3
"""Analyze Phase 3+ F0 two-zone diagnostic CSV outputs.

Reads one or more CSVs produced with phase3_zone_diagnostics_enabled=true and
prints a per-case, per-room summary of zonal mass/interface diagnostics.

Usage:
  python scripts/simulation/analyze_phase3_zone_diagnostics.py <csv> [<csv>...]
  python scripts/simulation/analyze_phase3_zone_diagnostics.py <csv> --json-out out.json
  python scripts/simulation/analyze_phase3_zone_diagnostics.py <csv> --room 0 --top 3
"""

import argparse
import json
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import List, Optional

try:
    import pandas as pd
except ImportError:
    print("ERROR: pandas not installed. Run: pip install pandas", file=sys.stderr)
    sys.exit(1)


F0_SENTINEL_COLS = {"upper_gas_kg", "upper_volume_m3_eos", "attribution_mass_residual_kg_step"}

F0_COLS = [
    "upper_gas_kg", "lower_gas_kg", "upper_energy_kj", "lower_energy_kj",
    "upper_volume_m3_eos", "lower_volume_m3_eos", "volume_closure_error_m3",
    "two_zone_boundary_mass_kg", "two_zone_boundary_energy_kj",
    "two_zone_boundary_mass_kg_step", "two_zone_boundary_energy_kj_step",
    "opening_upper_in_kg_step", "opening_upper_out_kg_step",
    "opening_lower_in_kg_step", "opening_lower_out_kg_step",
    "plume_entrained_kg_step",
    "oxygen_exchange_mass_delta_kg_step", "oxygen_exchange_energy_delta_kj_step",
    "combustion_mass_delta_kg_step", "combustion_energy_delta_kj_step",
    "thermal_mass_delta_kg_step", "thermal_energy_delta_kj_step",
    "suppression_mass_delta_kg_step", "suppression_energy_delta_kj_step",
    "gas_exchange_mass_delta_kg_step", "gas_exchange_energy_delta_kj_step",
    "hvac_mass_delta_kg_step", "hvac_energy_delta_kj_step",
    "other_mass_delta_kg_step", "other_energy_delta_kj_step",
    "reconcile_mass_delta_kg_step", "reconcile_energy_delta_kj_step",
    "projection_clamp_mass_delta_kg_step", "projection_clamp_energy_delta_kj_step",
    "attribution_mass_residual_kg_step", "attribution_energy_residual_kj_step",
]

# Classification thresholds
_PROJECTION_DOMINANT_KG = 1.0      # |cumulative boundary mass| at end > 1 kg
_FLUX_ACTIVE_KG = 0.01             # min summed step value to call a mechanism active
_ATTRIBUTION_RESIDUAL_KG = 0.001   # max |residual per step| that triggers ledger flag


@dataclass
class RoomSummary:
    csv_path: str
    room_id: int
    row_count: int
    t_start_s: float
    t_end_s: float

    # Upper-zone volume fraction (computed: upper_volume_m3_eos / volume_m3)
    upper_vf_min: float
    upper_vf_min_t: float
    upper_vf_max: float
    upper_vf_max_t: float
    upper_vf_final: float

    # Gas mass
    upper_gas_kg_min: float
    upper_gas_kg_min_t: float
    upper_gas_kg_max: float
    upper_gas_kg_max_t: float
    upper_gas_kg_final: float
    lower_gas_kg_final: float

    # Energy
    upper_energy_kj_final: float
    lower_energy_kj_final: float

    # Volume closure
    volume_closure_error_m3_max_abs: float
    volume_closure_error_m3_max_abs_t: float

    # Boundary corrections (cumulative)
    boundary_mass_kg_final: float
    boundary_mass_kg_peak: float
    boundary_mass_kg_peak_t: float
    boundary_energy_kj_final: float

    # Boundary per step (peak absolute)
    boundary_mass_step_max_abs: float
    boundary_mass_step_max_abs_t: float

    # Opening flows (summed step values across all rows)
    opening_upper_in_sum: float
    opening_upper_out_sum: float
    opening_lower_in_sum: float
    opening_lower_out_sum: float
    opening_total_sum: float

    # Plume entrainment
    plume_entrained_sum: float
    plume_entrained_step_max: float

    # Projection/clamp per step (peak absolute)
    projection_clamp_mass_step_max_abs: float
    projection_clamp_mass_step_max_abs_t: float

    # Attribution residual (peak absolute)
    attribution_residual_max_abs: float
    attribution_residual_max_abs_t: float

    # Artificial turnover: |boundary_mass_final| / initial_lower_mass
    boundary_turnover_ratio: float

    # Classification flags
    flags: List[str] = field(default_factory=list)


def _check_f0_columns(df: pd.DataFrame, csv_path: str) -> None:
    missing = F0_SENTINEL_COLS - set(df.columns)
    if missing:
        raise ValueError(
            f"{csv_path}: not a Phase 3+ F0 diagnostic CSV.\n"
            f"  Missing columns: {sorted(missing)}\n"
            "  Re-run with --phase3-zone-diagnostics or "
            "phase3_zone_diagnostics_enabled=true in the case JSON."
        )


def _extremum_t(df_room: pd.DataFrame, col: str, func: str) -> tuple:
    """Return (value, time_s) for min or max of col in df_room."""
    if func == "max":
        idx = df_room[col].idxmax()
    else:
        idx = df_room[col].idxmin()
    return float(df_room.loc[idx, col]), float(df_room.loc[idx, "time_s"])


def _extremum_abs_t(df_room: pd.DataFrame, col: str) -> tuple:
    """Return (abs_value, time_s) for the row with highest absolute value of col."""
    abs_col = df_room[col].abs()
    idx = abs_col.idxmax()
    return float(abs_col.loc[idx]), float(df_room.loc[idx, "time_s"])


def _classify(s: RoomSummary) -> List[str]:
    flags = []
    if abs(s.boundary_mass_kg_final) > _PROJECTION_DOMINANT_KG:
        flags.append("projection_dominant")
    if s.opening_total_sum > _FLUX_ACTIVE_KG and s.opening_total_sum >= s.plume_entrained_sum:
        flags.append("opening_transport_dominant")
    if s.plume_entrained_sum > _FLUX_ACTIVE_KG and s.plume_entrained_sum > s.opening_total_sum:
        flags.append("plume_dominant")
    if s.attribution_residual_max_abs > _ATTRIBUTION_RESIDUAL_KG:
        flags.append("needs_motor_flux_ledger")
    return flags


def summarize_room(csv_path: str, df_room: pd.DataFrame) -> RoomSummary:
    room_id = int(df_room["room_id"].iloc[0])

    # Compute upper volume fraction (non-physical at t=0 when volume_m3 may be 0)
    if "volume_m3" in df_room.columns:
        vol = df_room["volume_m3"].replace(0, float("nan"))
        df_room = df_room.copy()
        df_room["_upper_vf"] = df_room["upper_volume_m3_eos"] / vol
    else:
        df_room = df_room.copy()
        df_room["_upper_vf"] = float("nan")

    # Only consider rows where upper zone is active (upper_gas_kg > 0)
    active = df_room[df_room["upper_gas_kg"] > 0.0]

    if active.empty:
        upper_vf_min, upper_vf_min_t = 0.0, df_room["time_s"].iloc[0]
        upper_vf_max, upper_vf_max_t = 0.0, df_room["time_s"].iloc[0]
        upper_gas_min, upper_gas_min_t = 0.0, df_room["time_s"].iloc[0]
        upper_gas_max, upper_gas_max_t = 0.0, df_room["time_s"].iloc[0]
    else:
        upper_vf_min, upper_vf_min_t = _extremum_t(active, "_upper_vf", "min")
        upper_vf_max, upper_vf_max_t = _extremum_t(active, "_upper_vf", "max")
        upper_gas_min, upper_gas_min_t = _extremum_t(active, "upper_gas_kg", "min")
        upper_gas_max, upper_gas_max_t = _extremum_t(active, "upper_gas_kg", "max")

    last = df_room.iloc[-1]
    t_end = float(last["time_s"])

    vol_err_abs, vol_err_t = _extremum_abs_t(df_room, "volume_closure_error_m3")

    bm_peak, bm_peak_t = _extremum_abs_t(df_room, "two_zone_boundary_mass_kg")
    # Preserve sign for final
    bm_final = float(last["two_zone_boundary_mass_kg"])
    be_final = float(last["two_zone_boundary_energy_kj"])

    bm_step_abs, bm_step_t = _extremum_abs_t(df_room, "two_zone_boundary_mass_kg_step")

    pc_abs, pc_t = _extremum_abs_t(df_room, "projection_clamp_mass_delta_kg_step")
    ar_abs, ar_t = _extremum_abs_t(df_room, "attribution_mass_residual_kg_step")

    uo_in = float(df_room["opening_upper_in_kg_step"].sum())
    uo_out = float(df_room["opening_upper_out_kg_step"].sum())
    lo_in = float(df_room["opening_lower_in_kg_step"].sum())
    lo_out = float(df_room["opening_lower_out_kg_step"].sum())
    opening_total = uo_in + uo_out + lo_in + lo_out

    plume_sum = float(df_room["plume_entrained_kg_step"].sum())
    plume_max = float(df_room["plume_entrained_kg_step"].max())

    initial_lower = float(df_room["lower_gas_kg"].iloc[0])
    turnover = abs(bm_final) / max(1.0, initial_lower)

    s = RoomSummary(
        csv_path=csv_path,
        room_id=room_id,
        row_count=len(df_room),
        t_start_s=float(df_room["time_s"].iloc[0]),
        t_end_s=t_end,
        upper_vf_min=upper_vf_min,
        upper_vf_min_t=upper_vf_min_t,
        upper_vf_max=upper_vf_max,
        upper_vf_max_t=upper_vf_max_t,
        upper_vf_final=float(last["_upper_vf"]) if not pd.isna(last["_upper_vf"]) else 0.0,
        upper_gas_kg_min=upper_gas_min,
        upper_gas_kg_min_t=upper_gas_min_t,
        upper_gas_kg_max=upper_gas_max,
        upper_gas_kg_max_t=upper_gas_max_t,
        upper_gas_kg_final=float(last["upper_gas_kg"]),
        lower_gas_kg_final=float(last["lower_gas_kg"]),
        upper_energy_kj_final=float(last["upper_energy_kj"]),
        lower_energy_kj_final=float(last["lower_energy_kj"]),
        volume_closure_error_m3_max_abs=vol_err_abs,
        volume_closure_error_m3_max_abs_t=vol_err_t,
        boundary_mass_kg_final=bm_final,
        boundary_mass_kg_peak=bm_peak,
        boundary_mass_kg_peak_t=bm_peak_t,
        boundary_energy_kj_final=be_final,
        boundary_mass_step_max_abs=bm_step_abs,
        boundary_mass_step_max_abs_t=bm_step_t,
        opening_upper_in_sum=uo_in,
        opening_upper_out_sum=uo_out,
        opening_lower_in_sum=lo_in,
        opening_lower_out_sum=lo_out,
        opening_total_sum=opening_total,
        plume_entrained_sum=plume_sum,
        plume_entrained_step_max=plume_max,
        projection_clamp_mass_step_max_abs=pc_abs,
        projection_clamp_mass_step_max_abs_t=pc_t,
        attribution_residual_max_abs=ar_abs,
        attribution_residual_max_abs_t=ar_t,
        boundary_turnover_ratio=turnover,
    )
    s.flags = _classify(s)
    return s


def analyze_csv(csv_path: str, room_filter: Optional[int] = None) -> List[RoomSummary]:
    path = Path(csv_path)
    if not path.exists():
        raise FileNotFoundError(f"CSV not found: {csv_path}")

    df = pd.read_csv(path)
    _check_f0_columns(df, csv_path)

    rooms = sorted(df["room_id"].unique())
    if room_filter is not None:
        if room_filter not in rooms:
            raise ValueError(
                f"{csv_path}: room_id={room_filter} not found. Available: {rooms}"
            )
        rooms = [room_filter]

    results = []
    for rid in rooms:
        df_room = df[df["room_id"] == rid].reset_index(drop=True)
        results.append(summarize_room(csv_path, df_room))
    return results


def _fmt_row(label: str, value: str, unit: str = "") -> str:
    return f"  {label:<46}  {value}{' ' + unit if unit else ''}"


def print_room_summary(s: RoomSummary) -> None:
    csv_name = Path(s.csv_path).name
    print(f"\n{'='*70}")
    print(f"  {csv_name}  room {s.room_id}  "
          f"[t={s.t_start_s:.0f}–{s.t_end_s:.0f} s, {s.row_count} rows]")
    print(f"  flags: {', '.join(s.flags) if s.flags else '(none)'}")
    print(f"{'='*70}")

    print("\n  -- Upper-zone volume fraction (computed) --")
    print(_fmt_row("min", f"{s.upper_vf_min*100:.2f}%  @  t={s.upper_vf_min_t:.1f} s"))
    print(_fmt_row("max", f"{s.upper_vf_max*100:.2f}%  @  t={s.upper_vf_max_t:.1f} s"))
    print(_fmt_row("final", f"{s.upper_vf_final*100:.2f}%"))

    print("\n  -- Upper-zone gas mass --")
    print(_fmt_row("min (active)", f"{s.upper_gas_kg_min:.4f} kg  @  t={s.upper_gas_kg_min_t:.1f} s"))
    print(_fmt_row("max (active)", f"{s.upper_gas_kg_max:.4f} kg  @  t={s.upper_gas_kg_max_t:.1f} s"))
    print(_fmt_row("final", f"{s.upper_gas_kg_final:.4f} kg"))
    print(_fmt_row("lower final", f"{s.lower_gas_kg_final:.4f} kg"))

    print("\n  -- Energy --")
    print(_fmt_row("upper final", f"{s.upper_energy_kj_final:.2f} kJ"))
    print(_fmt_row("lower final", f"{s.lower_energy_kj_final:.2f} kJ"))

    print("\n  -- Volume closure --")
    print(_fmt_row("max |error|",
                   f"{s.volume_closure_error_m3_max_abs:.3e} m³  @  t={s.volume_closure_error_m3_max_abs_t:.1f} s"))

    print("\n  -- Boundary correction (project_room_state) --")
    print(_fmt_row("final cumulative", f"{s.boundary_mass_kg_final:+.4f} kg"))
    print(_fmt_row("peak |cumulative|",
                   f"{s.boundary_mass_kg_peak:.4f} kg  @  t={s.boundary_mass_kg_peak_t:.1f} s"))
    print(_fmt_row("energy final", f"{s.boundary_energy_kj_final:+.2f} kJ"))
    print(_fmt_row("max |per step|",
                   f"{s.boundary_mass_step_max_abs:.4f} kg  @  t={s.boundary_mass_step_max_abs_t:.1f} s"))
    print(_fmt_row("turnover ratio (|final| / initial_lower)",
                   f"{s.boundary_turnover_ratio:.4f}"))

    print("\n  -- Opening transport (step sums) --")
    print(_fmt_row("upper in", f"{s.opening_upper_in_sum:.4f} kg"))
    print(_fmt_row("upper out", f"{s.opening_upper_out_sum:.4f} kg"))
    print(_fmt_row("lower in", f"{s.opening_lower_in_sum:.4f} kg"))
    print(_fmt_row("lower out", f"{s.opening_lower_out_sum:.4f} kg"))
    print(_fmt_row("total", f"{s.opening_total_sum:.4f} kg"))

    print("\n  -- Plume entrainment (step sums) --")
    print(_fmt_row("total", f"{s.plume_entrained_sum:.4f} kg"))
    print(_fmt_row("max per step", f"{s.plume_entrained_step_max:.4f} kg"))

    print("\n  -- Projection/clamp --")
    print(_fmt_row("max |per step|",
                   f"{s.projection_clamp_mass_step_max_abs:.4f} kg  @  t={s.projection_clamp_mass_step_max_abs_t:.1f} s"))

    print("\n  -- Attribution residual --")
    print(_fmt_row("max |per step|",
                   f"{s.attribution_residual_max_abs:.3e} kg  @  t={s.attribution_residual_max_abs_t:.1f} s"))


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Analyze Phase 3+ F0 two-zone diagnostic CSV outputs."
    )
    parser.add_argument("csvs", nargs="+", metavar="CSV", help="F0 diagnostic CSV file(s)")
    parser.add_argument("--json-out", metavar="PATH", help="Write JSON summary to PATH")
    parser.add_argument("--room", type=int, metavar="N", help="Analyze only room N")
    parser.add_argument(
        "--top", type=int, metavar="N", default=0,
        help="Print only the top N rooms by |boundary_mass_kg_final|"
    )
    args = parser.parse_args(argv)

    all_summaries: List[RoomSummary] = []
    errors = []

    for csv_path in args.csvs:
        try:
            summaries = analyze_csv(csv_path, room_filter=args.room)
            all_summaries.extend(summaries)
        except (FileNotFoundError, ValueError) as exc:
            errors.append(str(exc))

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        if not all_summaries:
            return 1

    if args.top > 0:
        all_summaries = sorted(
            all_summaries,
            key=lambda s: abs(s.boundary_mass_kg_final),
            reverse=True,
        )[:args.top]

    for s in all_summaries:
        print_room_summary(s)

    if args.json_out:
        out_path = Path(args.json_out)
        records = []
        for s in all_summaries:
            d = asdict(s)
            records.append(d)
        out_path.write_text(json.dumps(records, indent=2), encoding="utf-8")
        print(f"\nJSON written to {out_path}")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
