#!/usr/bin/env python3
"""Audit F3.3v3 exterior leakage topology, pressure and layer routing."""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.simulation import analyze_phase3_f33m_source_correspondence as f33m
from scripts.simulation import (
    analyze_phase3_f33v3b_mass_interface_attribution as f33v3b,
)


CFAST_DIR = ROOT / "sim" / "validation" / "cfast"
CHECKPOINTS = tuple(range(10, 181, 10))
SIM_DEFAULT_WINDOW_LEAKAGE_AREA_M2 = 0.005
PRESSURE_SIGN_EPS_PA = 1.0e-6
FLOW_EPS_KG_S = 1.0e-9


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def parse_cfast_compartment_leak_geometry(
    path: Path, compartment_id: str = "R0"
) -> dict[str, float]:
    text = path.read_text(encoding="utf-8-sig")
    pattern = re.compile(
        rf"&COMP\s+ID\s*=\s*'{re.escape(compartment_id)}'(?P<body>.*?)/",
        re.IGNORECASE | re.DOTALL,
    )
    match = pattern.search(text)
    if match is None:
        raise ValueError(f"CFAST compartment is missing: {compartment_id}")
    body = match.group("body")

    def field(name: str) -> float:
        found = re.search(
            rf"\b{name}\s*=\s*([-+0-9.Ee]+)", body, re.IGNORECASE
        )
        if found is None:
            raise ValueError(
                f"CFAST compartment {compartment_id} has no {name}"
            )
        return float(found.group(1))

    ratios = re.search(
        r"\bLEAK_AREA_RATIO\s*=\s*([-+0-9.Ee]+)\s*,\s*([-+0-9.Ee]+)",
        body,
        re.IGNORECASE,
    )
    if ratios is None:
        raise ValueError(
            f"CFAST compartment {compartment_id} has no LEAK_AREA_RATIO"
        )
    width_m = field("WIDTH")
    depth_m = field("DEPTH")
    height_m = field("HEIGHT")
    wall_ratio = float(ratios.group(1))
    floor_ratio = float(ratios.group(2))
    wall_area_m2 = 2.0 * (width_m + depth_m) * height_m * wall_ratio
    floor_area_m2 = width_m * depth_m * floor_ratio
    floor_leak_width_m = 0.9 * (width_m + depth_m) / 2.0
    return {
        "width_m": width_m,
        "depth_m": depth_m,
        "height_m": height_m,
        "wall_leak_ratio": wall_ratio,
        "floor_leak_ratio": floor_ratio,
        "wall_leak_area_m2": wall_area_m2,
        "wall_leak_sill_m": 0.05 * height_m,
        "wall_leak_soffit_m": 0.95 * height_m,
        "floor_leak_area_m2": floor_area_m2,
        "floor_leak_sill_m": 0.0,
        "floor_leak_soffit_m": (
            floor_area_m2 / floor_leak_width_m
            if floor_leak_width_m > 0.0
            else 0.0
        ),
        "total_leak_area_m2": wall_area_m2 + floor_area_m2,
        "discharge_coefficient": 0.7,
    }


def read_cfast_leak_layer_rows(
    path: Path, compartment_id: str = "R0"
) -> list[dict[str, float]]:
    time_s: float | None = None
    rows: list[dict[str, float]] = []
    time_pattern = re.compile(
        r"\*\s*Time\s*=\s*([0-9.]+)\s+seconds\.\s*\*"
    )
    prefix = f"Leak   {compartment_id}"
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        time_match = time_pattern.fullmatch(line.strip())
        if time_match is not None:
            time_s = float(time_match.group(1))
            continue
        if time_s is None or not line.startswith(prefix):
            continue
        padded = line.ljust(49 + 13 * 8)
        values: list[float] = []
        for index in range(8):
            raw = padded[
                49 + 13 * index : 49 + 13 * (index + 1)
            ].strip()
            values.append(float(raw) if raw else 0.0)
        rows.append(
            {
                "time_s": time_s,
                "room_upper_in_kg_s": values[0],
                "room_upper_out_kg_s": values[1],
                "room_lower_in_kg_s": values[2],
                "room_lower_out_kg_s": values[3],
                "outside_upper_in_kg_s": values[4],
                "outside_upper_out_kg_s": values[5],
                "outside_lower_in_kg_s": values[6],
                "outside_lower_out_kg_s": values[7],
            }
        )
    if not rows:
        raise ValueError(
            f"CFAST leakage rows are missing for compartment {compartment_id}"
        )
    return rows


def row_at(
    rows: Iterable[dict[str, Any]],
    checkpoint_s: float,
    time_field: str,
) -> dict[str, Any]:
    candidates = list(rows)
    if not candidates:
        raise ValueError("empty time series")
    row = min(
        candidates,
        key=lambda candidate: abs(
            _number(candidate.get(time_field)) - checkpoint_s
        ),
    )
    if abs(_number(row.get(time_field)) - checkpoint_s) > 0.11:
        raise ValueError(f"checkpoint {checkpoint_s:g}s is absent")
    return row


def integrate_net_layer_flow(
    rows: Iterable[dict[str, float]],
    checkpoint_s: float,
    layer: str,
) -> float:
    ordered = sorted(rows, key=lambda row: row["time_s"])
    out_key = f"room_{layer}_out_kg_s"
    in_key = f"room_{layer}_in_kg_s"
    total = 0.0
    found = abs(ordered[0]["time_s"] - checkpoint_s) <= 0.11
    for previous, current in zip(ordered, ordered[1:]):
        t0 = previous["time_s"]
        t1 = current["time_s"]
        if t0 >= checkpoint_s:
            break
        if t1 > checkpoint_s + 0.11:
            raise ValueError(f"checkpoint {checkpoint_s:g}s is absent")
        rate0 = previous[out_key] - previous[in_key]
        rate1 = current[out_key] - current[in_key]
        total += 0.5 * (rate0 + rate1) * (t1 - t0)
        if abs(t1 - checkpoint_s) <= 0.11:
            found = True
            break
    if not found:
        raise ValueError(f"checkpoint {checkpoint_s:g}s is absent")
    return total


def _sim_exterior_layer_net_out(
    row: dict[str, str], layer: str
) -> float:
    net_out = 0.0
    for family in ("exterior", "exterior_counterflow"):
        prefix = f"phase3_shadow_mass_residence_{family}_{layer}_"
        net_out += _number(row.get(prefix + "out_kg_total")) - _number(
            row.get(prefix + "in_kg_total")
        )
    return net_out


def load_manifest_inputs(
    manifest_path: Path,
) -> tuple[float, dict[str, Any], dict[str, Any]]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    scenario_path = Path(str(manifest["scenario_path"]))
    scenario = json.loads(scenario_path.read_text(encoding="utf-8"))
    step_s = _number(manifest.get("step_s"))
    if step_s <= 0.0:
        raise ValueError("run manifest has no positive step_s")
    return step_s, scenario, manifest


def sim_leak_topology(scenario: dict[str, Any]) -> dict[str, Any]:
    overrides = scenario.get("engine_overrides", {})
    leakage_area = _number(
        overrides.get("window_leakage_area_m2"),
        SIM_DEFAULT_WINDOW_LEAKAGE_AREA_M2,
    )
    closed_exterior = [
        opening
        for opening in scenario.get("opening_overrides", [])
        if int(opening.get("b", 0)) == -1
        and _number(opening.get("open_fraction")) <= 0.0
    ]
    return {
        "closed_leakage_area_per_opening_m2": leakage_area,
        "closed_exterior_opening_count": len(closed_exterior),
        "effective_total_area_m2": leakage_area * len(closed_exterior),
        "representation": "closed exterior opening",
    }


def build_audit(
    *,
    candidate_csv: Path,
    manifest_path: Path,
    cfast_input_path: Path,
    cfast_output_path: Path,
    cfast_compartments_path: Path,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    sim_rows = f33v3b.read_sim_rows(candidate_csv)
    step_s, scenario, _manifest = load_manifest_inputs(manifest_path)
    cfast_leak_rows = read_cfast_leak_layer_rows(cfast_output_path)
    cfast_compartment_rows = f33m.read_cfast_compartments(
        cfast_compartments_path
    )
    cfast_geometry = parse_cfast_compartment_leak_geometry(cfast_input_path)
    sim_geometry = sim_leak_topology(scenario)

    snapshots: dict[str, Any] = {}
    sign_mismatch_checkpoints: list[int] = []
    for checkpoint in checkpoints:
        sim = f33v3b.sim_row_at(sim_rows, 0, checkpoint)
        cfast_leak = row_at(cfast_leak_rows, checkpoint, "time_s")
        cfast_compartment = row_at(
            cfast_compartment_rows, checkpoint, "Time"
        )
        cfast_upper_net_out = integrate_net_layer_flow(
            cfast_leak_rows, checkpoint, "upper"
        )
        cfast_lower_net_out = integrate_net_layer_flow(
            cfast_leak_rows, checkpoint, "lower"
        )
        sim_upper_net_out = _sim_exterior_layer_net_out(sim, "upper")
        sim_lower_net_out = _sim_exterior_layer_net_out(sim, "lower")
        cfast_pressure = _number(cfast_compartment.get("PRS_1"))
        sim_pressure = _number(
            sim.get("phase3_shadow_exterior_pressure_pre_pa")
        )
        sim_direction = _number(
            sim.get("phase3_shadow_exterior_direction")
        )
        sim_signed_net_out_rate = (
            _number(sim.get("phase3_shadow_exterior_accepted_gas_kg"))
            / step_s
            * sim_direction
        )
        cfast_upper_rate = (
            cfast_leak["room_upper_out_kg_s"]
            - cfast_leak["room_upper_in_kg_s"]
        )
        cfast_lower_rate = (
            cfast_leak["room_lower_out_kg_s"]
            - cfast_leak["room_lower_in_kg_s"]
        )
        pressure_sign_mismatch = (
            abs(cfast_pressure) > PRESSURE_SIGN_EPS_PA
            and abs(sim_pressure) > PRESSURE_SIGN_EPS_PA
            and cfast_pressure * sim_pressure < 0.0
        )
        flow_sign_mismatch = (
            abs(cfast_upper_rate + cfast_lower_rate) > FLOW_EPS_KG_S
            and abs(sim_signed_net_out_rate) > FLOW_EPS_KG_S
            and (cfast_upper_rate + cfast_lower_rate)
            * sim_signed_net_out_rate
            < 0.0
        )
        if pressure_sign_mismatch:
            sign_mismatch_checkpoints.append(checkpoint)
        snapshots[str(checkpoint)] = {
            "cfast_pressure_pa": cfast_pressure,
            "sim_pressure_pre_pa": sim_pressure,
            "pressure_sign_mismatch": pressure_sign_mismatch,
            "cfast_upper_net_out_rate_kg_s": cfast_upper_rate,
            "cfast_lower_net_out_rate_kg_s": cfast_lower_rate,
            "cfast_total_net_out_rate_kg_s": (
                cfast_upper_rate + cfast_lower_rate
            ),
            "sim_total_net_out_rate_kg_s": sim_signed_net_out_rate,
            "flow_sign_mismatch": flow_sign_mismatch,
            "sim_source_zone_code": _number(
                sim.get("phase3_shadow_exterior_source_zone_code")
            ),
            "cfast_upper_net_out_kg": cfast_upper_net_out,
            "cfast_lower_net_out_kg": cfast_lower_net_out,
            "sim_upper_net_out_kg": sim_upper_net_out,
            "sim_lower_net_out_kg": sim_lower_net_out,
            "upper_net_out_deficit_kg": (
                cfast_upper_net_out - sim_upper_net_out
            ),
            "lower_net_out_deficit_kg": (
                cfast_lower_net_out - sim_lower_net_out
            ),
        }

    final_key = str(max(int(value) for value in snapshots))
    final = snapshots[final_key]
    total_deficit = (
        final["upper_net_out_deficit_kg"]
        + final["lower_net_out_deficit_kg"]
    )
    lower_share = (
        final["lower_net_out_deficit_kg"] / total_deficit
        if total_deficit > 0.0
        else 0.0
    )
    area_ratio = (
        cfast_geometry["total_leak_area_m2"]
        / sim_geometry["effective_total_area_m2"]
        if sim_geometry["effective_total_area_m2"] > 0.0
        else float("inf")
    )
    topology_equivalent = (
        abs(area_ratio - 1.0) <= 0.01
        and sim_geometry["representation"] == "distributed wall and floor"
    )
    return {
        "candidate_csv": str(candidate_csv),
        "cfast_geometry": cfast_geometry,
        "sim_geometry": sim_geometry,
        "geometry_area_ratio_cfast_to_sim": area_ratio,
        "checkpoints": snapshots,
        "verdict": {
            "cfast_layer_leakage_observable": True,
            "topology_equivalent": topology_equivalent,
            "pressure_sign_mismatch_checkpoints": sign_mismatch_checkpoints,
            "pressure_sign_mismatch_count": len(
                sign_mismatch_checkpoints
            ),
            "upper_net_out_deficit_kg": final[
                "upper_net_out_deficit_kg"
            ],
            "lower_net_out_deficit_kg": final[
                "lower_net_out_deficit_kg"
            ],
            "lower_share_of_total_deficit": lower_share,
            "primary_layer_owner": (
                "lower_exterior_net_outflow"
                if final["lower_net_out_deficit_kg"]
                > final["upper_net_out_deficit_kg"]
                else "upper_exterior_net_outflow"
            ),
            "area_only_experiment_allowed": (
                topology_equivalent
                and not sign_mismatch_checkpoints
            ),
            "next_experiment": (
                "audit the canonical pressure-state sign reversals before "
                "testing distributed leakage authority"
            ),
        },
    }


def _print_audit(audit: dict[str, Any]) -> None:
    print("F3.3v3c exterior leakage topology and layer audit")
    cfast = audit["cfast_geometry"]
    sim = audit["sim_geometry"]
    print(
        "leak area: "
        f"CFAST={cfast['total_leak_area_m2']:.6f} m2 "
        f"(wall={cfast['wall_leak_area_m2']:.6f}, "
        f"floor={cfast['floor_leak_area_m2']:.6f}); "
        f"SimuFire={sim['effective_total_area_m2']:.6f} m2"
    )
    print(
        "time  p_CFAST  p_SFpre  q_CFAST  q_SF  "
        "cum-upper-def  cum-lower-def"
    )
    for checkpoint, snapshot in audit["checkpoints"].items():
        print(
            f"{checkpoint:>4} "
            f"{snapshot['cfast_pressure_pa']:>8.2f} "
            f"{snapshot['sim_pressure_pre_pa']:>8.2f} "
            f"{snapshot['cfast_total_net_out_rate_kg_s']:>8.4f} "
            f"{snapshot['sim_total_net_out_rate_kg_s']:>8.4f} "
            f"{snapshot['upper_net_out_deficit_kg']:>13.3f} "
            f"{snapshot['lower_net_out_deficit_kg']:>13.3f}"
        )
    verdict = audit["verdict"]
    print(
        "\npressure sign mismatch checkpoints:",
        verdict["pressure_sign_mismatch_checkpoints"],
    )
    print("primary layer owner:", verdict["primary_layer_owner"])
    print(
        "lower share of deficit:",
        f"{100.0 * verdict['lower_share_of_total_deficit']:.1f}%",
    )
    print(
        "area-only experiment allowed:",
        verdict["area_only_experiment_allowed"],
    )
    print("next experiment:", verdict["next_experiment"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--candidate-csv",
        type=Path,
        default=Path("runs/phase3_f33v3a/180_on/sim_log.csv"),
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("runs/phase3_f33v3a/180_on/run_manifest.json"),
    )
    parser.add_argument(
        "--cfast-input",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain.in",
    )
    parser.add_argument(
        "--cfast-output",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain.out",
    )
    parser.add_argument(
        "--cfast-compartments",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain_compartments.csv",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)
    audit = build_audit(
        candidate_csv=args.candidate_csv,
        manifest_path=args.manifest,
        cfast_input_path=args.cfast_input,
        cfast_output_path=args.cfast_output,
        cfast_compartments_path=args.cfast_compartments,
    )
    _print_audit(audit)
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    verdict = audit["verdict"]
    return (
        0
        if verdict["cfast_layer_leakage_observable"]
        and not verdict["area_only_experiment_allowed"]
        and verdict["primary_layer_owner"] == "lower_exterior_net_outflow"
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
