#!/usr/bin/env python3
"""
Compare the FDS simple-house device CSV against the SimuFire validation CSV.

This is an engineering trend report, not a scientific validation certificate.
It intentionally keeps the comparison outside the Godot runtime so calibration
experiments do not change the main simulator.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
from typing import Iterable


ROOMS = [
    {"id": 0, "fds": "Salon", "sim": "Salon", "volume_m3": 48.0},
    {"id": 1, "fds": "Pasillo", "sim": "Pasillo", "volume_m3": 25.2},
    {"id": 2, "fds": "Dormitorio1", "sim": "Dormitorio1", "volume_m3": 25.2},
    {"id": 3, "fds": "Dormitorio2", "sim": "Dormitorio2", "volume_m3": 16.8},
    {"id": 4, "fds": "Cocina", "sim": "Cocina", "volume_m3": 36.0},
    {"id": 5, "fds": "Bano", "sim": "Bano", "volume_m3": 16.8},
]


def parse_float(value: object, default: float = math.nan) -> float:
    try:
        if value is None:
            return default
        text = str(value).strip()
        if text == "":
            return default
        return float(text)
    except (TypeError, ValueError):
        return default


def first_time_below(rows: list[dict[str, str]], column: str, threshold: float) -> float | None:
    for row in rows:
        value = parse_float(row.get(column))
        if not math.isnan(value) and value < threshold:
            return parse_float(row.get("Time"))
    return None


def first_time_above(rows: list[dict[str, str]], column: str, threshold: float) -> float | None:
    for row in rows:
        value = parse_float(row.get(column))
        if not math.isnan(value) and value > threshold:
            return parse_float(row.get("time_s"))
    return None


def max_value(rows: Iterable[dict[str, str]], column: str, multiplier: float = 1.0) -> float:
    values = [parse_float(row.get(column)) * multiplier for row in rows]
    values = [value for value in values if not math.isnan(value)]
    return max(values) if values else math.nan


def min_value(rows: Iterable[dict[str, str]], column: str, multiplier: float = 1.0) -> float:
    values = [parse_float(row.get(column)) * multiplier for row in rows]
    values = [value for value in values if not math.isnan(value)]
    return min(values) if values else math.nan


def last_value(rows: list[dict[str, str]], column: str, multiplier: float = 1.0) -> float:
    if not rows:
        return math.nan
    return parse_float(rows[-1].get(column)) * multiplier


def read_fds_devc(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        raw_rows = list(csv.reader(handle))
    if len(raw_rows) < 3:
        raise ValueError(f"FDS DEVC CSV has too few rows: {path}")
    header = raw_rows[1]
    rows = [dict(zip(header, raw_row)) for raw_row in raw_rows[2:]]
    return header, rows


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        return list(reader.fieldnames or []), rows


def estimate_sim_visibility_m(smoke_kg: float, volume_m3: float, extinction_m2_kg: float, c_factor: float) -> float:
    if smoke_kg <= 0.0 or volume_m3 <= 0.0:
        return 30.0
    concentration_kg_m3 = smoke_kg / volume_m3
    extinction = extinction_m2_kg * concentration_kg_m3
    if extinction <= 1.0e-9:
        return 30.0
    return min(30.0, c_factor / extinction)


def sim_visibility_series(
    rows: list[dict[str, str]],
    volume_m3: float,
    extinction_m2_kg: float,
    c_factor: float,
) -> list[tuple[float, float]]:
    result: list[tuple[float, float]] = []
    for row in rows:
        time_s = parse_float(row.get("time_s"))
        smoke_kg = parse_float(row.get("smoke_kg"), 0.0)
        if math.isnan(time_s):
            continue
        exported_visibility_m = parse_float(row.get("visibility_m"))
        if math.isnan(exported_visibility_m):
            visibility_m = estimate_sim_visibility_m(smoke_kg, volume_m3, extinction_m2_kg, c_factor)
        else:
            visibility_m = min(30.0, max(0.0, exported_visibility_m))
        result.append((time_s, visibility_m))
    return result


def first_visibility_below(series: list[tuple[float, float]], threshold: float) -> float | None:
    for time_s, visibility_m in series:
        if visibility_m < threshold:
            return time_s
    return None


def format_number(value: float | None, digits: int = 1, suffix: str = "") -> str:
    if value is None:
        return "NA"
    if isinstance(value, float) and math.isnan(value):
        return "NA"
    return f"{value:.{digits}f}{suffix}"


def pct_to_ppm(value_pct: float) -> float:
    return value_pct * 10000.0


def fed_increment(
    dt_s: float,
    co_ppm: float,
    co2_ppm: float,
    o2_pct: float,
    gas_temp_c: float,
) -> float:
    if dt_s <= 0.0:
        return 0.0

    dt_min = dt_s / 60.0
    delta = 0.0
    if co_ppm > 0.0:
        co2_pct = co2_ppm / 10000.0
        v_co2 = 1.0
        if co2_pct > 2.0:
            v_co2 = math.exp(0.1903 * co2_pct + 2.0004) / 7.1
        delta += 3.317e-5 * math.pow(co_ppm, 1.036) * v_co2 * dt_min

    o2_deficit_pct = max(0.0, 20.9 - max(0.0, min(20.9, o2_pct)))
    if o2_deficit_pct > 0.0:
        t_crit_min = math.exp(8.13 - 0.54 * o2_deficit_pct)
        if t_crit_min > 0.0:
            delta += dt_min / t_crit_min

    if gas_temp_c > 60.0:
        tenab_min = 4.1e8 * math.pow(gas_temp_c, -3.61)
        tenab_s = tenab_min * 60.0
        if tenab_s > 0.0:
            delta += dt_s / tenab_s

    return max(0.0, delta)


def estimate_fds_fed(rows: list[dict[str, str]], room_name: str) -> float:
    total = 0.0
    previous_time = None
    for row in rows:
        time_s = parse_float(row.get("Time"))
        if math.isnan(time_s):
            continue
        if previous_time is None:
            previous_time = time_s
            continue
        dt_s = max(0.0, time_s - previous_time)
        previous_time = time_s
        t_lower = parse_float(row.get(f"{room_name}_T_lower"), 20.0)
        t_upper = parse_float(row.get(f"{room_name}_T_upper"), t_lower)
        # FDS devices are at 0.6 m and 2.1 m; estimate the 1.6 m breathing point.
        t_breathing = t_lower + (t_upper - t_lower) * ((1.6 - 0.6) / (2.1 - 0.6))
        total += fed_increment(
            dt_s,
            pct_to_ppm(parse_float(row.get(f"{room_name}_CO_pct"), 0.0)),
            pct_to_ppm(parse_float(row.get(f"{room_name}_CO2_pct"), 0.0)),
            parse_float(row.get(f"{room_name}_O2_pct"), 20.9),
            t_breathing,
        )
    return total


def build_report(
    fds_header: list[str],
    fds_rows: list[dict[str, str]],
    sim_header: list[str],
    sim_rows: list[dict[str, str]],
    extinction_m2_kg: float,
    c_factor: float,
) -> str:
    missing_fds_co = [room["fds"] for room in ROOMS if f"{room['fds']}_CO_pct" not in fds_header]
    has_sim_fed = "fed" in sim_header
    has_sim_co = "co_ppm" in sim_header
    has_sim_visibility = "visibility_m" in sim_header
    lines: list[str] = []
    lines.append("# Simple house FDS vs SimuFire measurement report")
    lines.append("")
    lines.append("This report compares aligned measurements for calibration. It is not a scientific validation dataset.")
    lines.append("")
    if missing_fds_co:
        lines.append("**Warning:** the FDS DEVC CSV does not contain CO columns yet. Re-run FDS after the updated `.fds` file.")
        lines.append("")
    if not has_sim_fed or not has_sim_co:
        lines.append("**Warning:** the SimuFire CSV does not contain all CO/FED columns expected by this report.")
        lines.append("")
    if has_sim_visibility:
        lines.append("SimuFire visibility uses the exported `visibility_m` column.")
        lines.append("Older CSV files without that column fall back to the whole-room smoke approximation:")
    else:
        lines.append("SimuFire visibility is estimated from total `smoke_kg` and room volume:")
    lines.append(f"`visibility_m = {c_factor:g} / ({extinction_m2_kg:g} * smoke_kg / volume_m3)`, capped at 30 m.")
    lines.append("")

    lines.append("| Room | FDS peak T up C | Sim peak T up C | FDS vis<10m s | Sim vis<10m s | FDS min O2 % | Sim min O2 % | FDS peak CO ppm | Sim peak CO ppm | FDS peak CO2 % | Sim peak CO2 % | FDS est FED | Sim max FED |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

    for room in ROOMS:
        fds_name = str(room["fds"])
        sim_room_rows = [row for row in sim_rows if int(parse_float(row.get("room_id"), -1.0)) == int(room["id"])]
        sim_vis = sim_visibility_series(
            sim_room_rows,
            float(room["volume_m3"]),
            extinction_m2_kg,
            c_factor,
        )
        fds_co_col = f"{fds_name}_CO_pct"
        fds_peak_co_ppm = pct_to_ppm(max_value(fds_rows, fds_co_col)) if fds_co_col in fds_header else math.nan
        lines.append(
            "| {room} | {fds_peak_t} | {sim_peak_t} | {fds_vis10} | {sim_vis10} | "
            "{fds_o2_min} | {sim_o2_min} | {fds_co_peak} | {sim_co_peak} | "
            "{fds_co2_peak} | {sim_co2_peak} | {fds_fed} | {sim_fed} |".format(
                room=fds_name,
                fds_peak_t=format_number(max_value(fds_rows, f"{fds_name}_T_upper"), 1),
                sim_peak_t=format_number(max_value(sim_room_rows, "temp_upper_c"), 1),
                fds_vis10=format_number(first_time_below(fds_rows, f"{fds_name}_visibility_m", 10.0), 1),
                sim_vis10=format_number(first_visibility_below(sim_vis, 10.0), 1),
                fds_o2_min=format_number(min_value(fds_rows, f"{fds_name}_O2_pct"), 2),
                sim_o2_min=format_number(min_value(sim_room_rows, "o2", 100.0), 2),
                fds_co_peak=format_number(fds_peak_co_ppm, 0),
                sim_co_peak=format_number(max_value(sim_room_rows, "co_ppm"), 0),
                fds_co2_peak=format_number(max_value(fds_rows, f"{fds_name}_CO2_pct"), 2),
                sim_co2_peak=format_number(max_value(sim_room_rows, "co2_ppm", 0.0001), 2),
                fds_fed=format_number(estimate_fds_fed(fds_rows, fds_name), 3),
                sim_fed=format_number(max_value(sim_room_rows, "fed"), 3),
            )
        )

    lines.append("")
    lines.append("## Notes")
    lines.append("")
    lines.append("- FDS visibility is a device quantity at breathing height.")
    lines.append("- SimuFire visibility is a whole-room smoke concentration approximation; it is useful for trends, not exact optics.")
    lines.append("- FDS estimated FED is computed from room-point CO, O2, CO2 and interpolated breathing-height temperature; it omits radiant heat.")
    lines.append("- If FDS CO columns show `NA`, regenerate `simufire_simple_house_default_devc.csv` by re-running FDS.")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    base_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fds-devc", type=Path, default=base_dir / "simufire_simple_house_default_devc.csv")
    parser.add_argument("--simufire-csv", type=Path, default=base_dir / "simufire_simple_house_default_simufire.csv")
    parser.add_argument("--out", type=Path, default=base_dir / "simufire_simple_house_measurement_report.md")
    parser.add_argument("--smoke-extinction-m2-kg", type=float, default=8700.0)
    parser.add_argument("--visibility-c-factor", type=float, default=3.0)
    args = parser.parse_args()

    fds_header, fds_rows = read_fds_devc(args.fds_devc)
    sim_header, sim_rows = read_csv(args.simufire_csv)
    report = build_report(
        fds_header,
        fds_rows,
        sim_header,
        sim_rows,
        args.smoke_extinction_m2_kg,
        args.visibility_c_factor,
    )
    args.out.write_text(report, encoding="utf-8")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

