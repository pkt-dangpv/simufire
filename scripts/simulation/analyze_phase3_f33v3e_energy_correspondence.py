#!/usr/bin/env python3
"""Compare F3.3v3 gas-surface and doorway energy authority with CFAST."""

from __future__ import annotations

import argparse
import json
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
from scripts.simulation import (
    analyze_phase3_f33v3c_exterior_leakage as f33v3c,
)
from scripts.simulation import (
    analyze_phase3_f33v3d_pressure_inventory as f33v3d,
)


CFAST_DIR = ROOT / "sim" / "validation" / "cfast"
CHECKPOINTS = tuple(range(10, 181, 10))
AMBIENT_C = 20.0
ENERGY_CLOSURE_TOLERANCE_KJ = 1.0e-3
OPENING_MATCH_TOLERANCE_KJ = 10.0


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def _row_at(
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


def integrate_cfast_exterior_sensible_energy(
    leak_rows: list[dict[str, float]],
    compartment_rows: list[dict[str, str]],
    checkpoint_s: float,
) -> float:
    """Return sensible energy entering R0; ambient inflow has zero excess."""
    ordered = sorted(leak_rows, key=lambda row: row["time_s"])
    total_kj = 0.0

    def rate(row: dict[str, float]) -> float:
        compartment = _row_at(
            compartment_rows, row["time_s"], "Time"
        )
        upper_excess_c = _number(compartment.get("ULT_1")) - AMBIENT_C
        lower_excess_c = _number(compartment.get("LLT_1")) - AMBIENT_C
        return -(
            row["room_upper_out_kg_s"] * upper_excess_c
            + row["room_lower_out_kg_s"] * lower_excess_c
        )

    found = abs(ordered[0]["time_s"] - checkpoint_s) <= 0.11
    for previous, current in zip(ordered, ordered[1:]):
        t0 = previous["time_s"]
        t1 = current["time_s"]
        if t0 >= checkpoint_s:
            break
        if t1 > checkpoint_s + 0.11:
            raise ValueError(f"checkpoint {checkpoint_s:g}s is absent")
        total_kj += 0.5 * (rate(previous) + rate(current)) * (t1 - t0)
        if abs(t1 - checkpoint_s) <= 0.11:
            found = True
            break
    if not found:
        raise ValueError(f"checkpoint {checkpoint_s:g}s is absent")
    return total_kj


def cfast_energy_checkpoint(
    checkpoint_s: int,
    *,
    zone_rows: list[dict[str, str]],
    compartment_rows: list[dict[str, str]],
    leak_rows: list[dict[str, float]],
) -> dict[str, float]:
    checkpoint = f33m.build_cfast_checkpoint(
        checkpoint_s, zone_rows, compartment_rows
    )
    room = checkpoint["r0"]
    doorway_kj = (
        checkpoint["routes"]["1->0"]["enthalpy_kj"]
        - checkpoint["routes"]["0->1"]["enthalpy_kj"]
    )
    exterior_kj = integrate_cfast_exterior_sensible_energy(
        leak_rows, compartment_rows, checkpoint_s
    )
    observed_kj = room["sensible_energy_kj"]
    combustion_kj = room["convective_energy_kj"]
    surface_kj = observed_kj - combustion_kj - doorway_kj - exterior_kj
    return {
        "observed_kj": observed_kj,
        "combustion_kj": combustion_kj,
        "surface_kj": surface_kj,
        "doorway_kj": doorway_kj,
        "exterior_kj": exterior_kj,
        "budget_residual_kj": (
            observed_kj
            - combustion_kj
            - surface_kj
            - doorway_kj
            - exterior_kj
        ),
    }


def sim_energy_checkpoint(row: dict[str, str]) -> dict[str, float]:
    inventory = f33v3d.pressure_snapshot(row)
    owners = inventory["owners"]
    result = {
        "observed_kj": inventory["observed_energy_kj"],
        "combustion_kj": owners["combustion"]["energy_kj"],
        "surface_kj": owners["multisurface"]["energy_kj"],
        "doorway_kj": (
            owners["interior_opening"]["energy_kj"]
            + owners["interior_pressure"]["energy_kj"]
        ),
        "exterior_kj": (
            owners["exterior"]["energy_kj"]
            + owners["exterior_counterflow"]["energy_kj"]
        ),
        "interior_opening_only_kj": owners["interior_opening"][
            "energy_kj"
        ],
        "interior_pressure_only_kj": owners["interior_pressure"][
            "energy_kj"
        ],
    }
    result["budget_residual_kj"] = result["observed_kj"] - sum(
        result[key]
        for key in (
            "combustion_kj",
            "surface_kj",
            "doorway_kj",
            "exterior_kj",
        )
    )
    return result


def _window(
    current: dict[str, float],
    previous: dict[str, float] | None,
) -> dict[str, float]:
    keys = (
        "observed_kj",
        "combustion_kj",
        "surface_kj",
        "doorway_kj",
        "exterior_kj",
    )
    return {
        key: current[key] - (previous[key] if previous else 0.0)
        for key in keys
    }


def _route_families(
    summary_path: Path,
    source_room_id: int,
    destination_room_id: int,
) -> dict[str, dict[str, float]]:
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    result: dict[str, dict[str, float]] = {}
    for record in summary.get("phase3_connection_residence", []):
        if (
            int(record.get("opening_id", -1)) != 0
            or int(record.get("source_room_id", -1)) != source_room_id
            or int(record.get("destination_room_id", -1))
            != destination_room_id
        ):
            continue
        family = str(record.get("family", "unknown"))
        values = result.setdefault(
            family, {"mass_kg": 0.0, "enthalpy_kj": 0.0}
        )
        values["mass_kg"] += _number(record.get("accepted_mass_kg"))
        values["enthalpy_kj"] += _number(
            record.get("accepted_enthalpy_kj")
        )
    return result


def final_directional_correspondence(
    *,
    sim_run_dir: Path,
    checkpoint_s: int,
    zone_rows: list[dict[str, str]],
    compartment_rows: list[dict[str, str]],
) -> dict[str, Any]:
    cfast = f33m.build_cfast_checkpoint(
        checkpoint_s, zone_rows, compartment_rows
    )
    sim = f33m.build_sim_checkpoint(checkpoint_s, sim_run_dir)
    outbound_families = _route_families(
        sim_run_dir / "summary.json", 0, 1
    )
    inbound_families = _route_families(
        sim_run_dir / "summary.json", 1, 0
    )

    cfast_out = cfast["routes"]["0->1"]
    cfast_in = cfast["routes"]["1->0"]
    sim_out = sim["routes"]["0->1"]
    sim_in = sim["routes"]["1->0"]

    def family_net_out(family: str, quantity: str) -> float:
        return _number(outbound_families.get(family, {}).get(quantity)) - (
            _number(inbound_families.get(family, {}).get(quantity))
        )

    cfast_net_mass_out = cfast_out["mass_kg"] - cfast_in["mass_kg"]
    cfast_net_enthalpy_out = (
        cfast_out["enthalpy_kj"] - cfast_in["enthalpy_kj"]
    )
    sim_opening_net_mass_out = family_net_out(
        "interior_opening", "mass_kg"
    )
    sim_pressure_net_mass_out = family_net_out(
        "interior_pressure", "mass_kg"
    )
    sim_opening_net_enthalpy_out = family_net_out(
        "interior_opening", "enthalpy_kj"
    )
    sim_pressure_net_enthalpy_out = family_net_out(
        "interior_pressure", "enthalpy_kj"
    )

    opening_gross_mass = (
        _number(
            outbound_families.get("interior_opening", {}).get("mass_kg")
        )
        + _number(
            inbound_families.get("interior_opening", {}).get("mass_kg")
        )
    )
    pressure_gross_mass = (
        _number(
            outbound_families.get("interior_pressure", {}).get("mass_kg")
        )
        + _number(
            inbound_families.get("interior_pressure", {}).get("mass_kg")
        )
    )
    cfast_gross_mass = cfast_out["mass_kg"] + cfast_in["mass_kg"]
    sim_gross_mass = sim_out["mass_kg"] + sim_in["mass_kg"]
    half_pressure_skew = 0.5 * sim_pressure_net_mass_out
    skewed_out_mass = _number(
        outbound_families.get("interior_opening", {}).get("mass_kg")
    ) + half_pressure_skew
    skewed_in_mass = _number(
        inbound_families.get("interior_opening", {}).get("mass_kg")
    ) - half_pressure_skew

    return {
        "cfast_out_mass_kg": cfast_out["mass_kg"],
        "cfast_in_mass_kg": cfast_in["mass_kg"],
        "cfast_gross_mass_kg": cfast_gross_mass,
        "cfast_net_mass_out_kg": cfast_net_mass_out,
        "cfast_net_enthalpy_out_kj": cfast_net_enthalpy_out,
        "sim_out_mass_kg": sim_out["mass_kg"],
        "sim_in_mass_kg": sim_in["mass_kg"],
        "sim_gross_mass_kg": sim_gross_mass,
        "sim_opening_gross_mass_kg": opening_gross_mass,
        "sim_pressure_gross_mass_kg": pressure_gross_mass,
        "sim_opening_net_mass_out_kg": sim_opening_net_mass_out,
        "sim_pressure_net_mass_out_kg": sim_pressure_net_mass_out,
        "sim_opening_net_enthalpy_out_kj": (
            sim_opening_net_enthalpy_out
        ),
        "sim_pressure_net_enthalpy_out_kj": (
            sim_pressure_net_enthalpy_out
        ),
        "opening_only_enthalpy_error_kj": (
            sim_opening_net_enthalpy_out - cfast_net_enthalpy_out
        ),
        "opening_only_enthalpy_relative_error": (
            abs(sim_opening_net_enthalpy_out - cfast_net_enthalpy_out)
            / abs(cfast_net_enthalpy_out)
        ),
        "pressure_route_net_mass_share_of_cfast": (
            sim_pressure_net_mass_out / cfast_net_mass_out
        ),
        "pressure_route_added_gross_mass_kg": pressure_gross_mass,
        "gross_mass_relative_error": (
            (sim_gross_mass - cfast_gross_mass) / cfast_gross_mass
        ),
        "opening_only_gross_mass_relative_error": (
            (opening_gross_mass - cfast_gross_mass) / cfast_gross_mass
        ),
        "fixed_gross_pressure_skew_out_mass_kg": skewed_out_mass,
        "fixed_gross_pressure_skew_in_mass_kg": skewed_in_mass,
    }


def build_audit(
    *,
    sim_run_dir: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    cfast_output_path: Path,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    sim_rows = f33v3b.read_sim_rows(sim_run_dir / "sim_log.csv")
    zone_rows = f33m.read_cfast_zone(cfast_zone_path)
    compartment_rows = f33m.read_cfast_compartments(
        cfast_compartments_path
    )
    leak_rows = f33v3c.read_cfast_leak_layer_rows(cfast_output_path)

    snapshots: dict[str, Any] = {}
    previous_cfast: dict[str, float] | None = None
    previous_sim: dict[str, float] | None = None
    for checkpoint in checkpoints:
        cfast = cfast_energy_checkpoint(
            checkpoint,
            zone_rows=zone_rows,
            compartment_rows=compartment_rows,
            leak_rows=leak_rows,
        )
        sim = sim_energy_checkpoint(
            f33v3b.sim_row_at(sim_rows, 0, checkpoint)
        )
        errors = {
            key: sim[key] - cfast[key]
            for key in (
                "observed_kj",
                "combustion_kj",
                "surface_kj",
                "doorway_kj",
                "exterior_kj",
            )
        }
        snapshots[str(checkpoint)] = {
            "cfast": cfast,
            "sim": sim,
            "error_sim_minus_cfast_kj": errors,
            "cfast_window_kj": _window(cfast, previous_cfast),
            "sim_window_kj": _window(sim, previous_sim),
        }
        previous_cfast = cfast
        previous_sim = sim

    final_checkpoint = max(int(key) for key in snapshots)
    final = snapshots[str(final_checkpoint)]
    directional = final_directional_correspondence(
        sim_run_dir=sim_run_dir,
        checkpoint_s=final_checkpoint,
        zone_rows=zone_rows,
        compartment_rows=compartment_rows,
    )
    first_mismatch = snapshots["120"]

    def primary_error(snapshot: dict[str, Any]) -> str:
        errors = snapshot["error_sim_minus_cfast_kj"]
        return max(
            ("combustion_kj", "surface_kj", "doorway_kj", "exterior_kj"),
            key=lambda key: abs(errors[key]),
        )

    final_surface_relative_error = abs(
        final["error_sim_minus_cfast_kj"]["surface_kj"]
    ) / abs(final["cfast"]["surface_kj"])
    final_doorway_relative_error = abs(
        final["error_sim_minus_cfast_kj"]["doorway_kj"]
    ) / abs(final["cfast"]["doorway_kj"])
    max_budget_residual = max(
        abs(snapshot[model]["budget_residual_kj"])
        for snapshot in snapshots.values()
        for model in ("cfast", "sim")
    )
    opening_only_match = (
        abs(directional["opening_only_enthalpy_error_kj"])
        <= OPENING_MATCH_TOLERANCE_KJ
    )
    return {
        "sim_run_dir": str(sim_run_dir),
        "checkpoints": snapshots,
        "final_directional_correspondence": directional,
        "verdict": {
            "energy_budgets_close": (
                max_budget_residual <= ENERGY_CLOSURE_TOLERANCE_KJ
            ),
            "max_energy_budget_residual_kj": max_budget_residual,
            "primary_error_owner_at_120s": primary_error(first_mismatch),
            "primary_error_owner_at_180s": primary_error(final),
            "final_surface_relative_error": final_surface_relative_error,
            "final_doorway_relative_error": final_doorway_relative_error,
            "interior_opening_only_matches_cfast_enthalpy": (
                opening_only_match
            ),
            "additive_pressure_route_is_excess_enthalpy_owner": (
                opening_only_match
                and directional["sim_pressure_net_enthalpy_out_kj"] > 0.0
            ),
            "next_motor_shadow_experiment": (
                "replace additive interior-pressure transport with a "
                "fixed-gross directional skew of canonical opening flow"
            ),
        },
    }


def _print_audit(audit: dict[str, Any]) -> None:
    print("F3.3v3e energy and doorway correspondence")
    print(
        "time  observed-error  surface-error  doorway-error  exterior-error"
    )
    for checkpoint, snapshot in audit["checkpoints"].items():
        error = snapshot["error_sim_minus_cfast_kj"]
        print(
            f"{checkpoint:>4} "
            f"{error['observed_kj']:>14.1f} "
            f"{error['surface_kj']:>13.1f} "
            f"{error['doorway_kj']:>13.1f} "
            f"{error['exterior_kj']:>14.1f}"
        )
    direction = audit["final_directional_correspondence"]
    print("\n180 s directional mass/enthalpy")
    for key in (
        "cfast_out_mass_kg",
        "cfast_in_mass_kg",
        "sim_out_mass_kg",
        "sim_in_mass_kg",
        "sim_opening_gross_mass_kg",
        "sim_pressure_gross_mass_kg",
        "cfast_net_enthalpy_out_kj",
        "sim_opening_net_enthalpy_out_kj",
        "sim_pressure_net_enthalpy_out_kj",
        "fixed_gross_pressure_skew_out_mass_kg",
        "fixed_gross_pressure_skew_in_mass_kg",
    ):
        print(f"  {key}: {direction[key]:.6f}")
    print("\nverdict:", audit["verdict"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sim-run-dir",
        type=Path,
        default=Path("runs/phase3_f33v3a/180_on"),
    )
    parser.add_argument(
        "--cfast-zone",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain_zone.csv",
    )
    parser.add_argument(
        "--cfast-compartments",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain_compartments.csv",
    )
    parser.add_argument(
        "--cfast-output",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain.out",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)
    audit = build_audit(
        sim_run_dir=args.sim_run_dir,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
        cfast_output_path=args.cfast_output,
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
        if verdict["energy_budgets_close"]
        and verdict["primary_error_owner_at_120s"] == "doorway_kj"
        and verdict["primary_error_owner_at_180s"] == "doorway_kj"
        and verdict["interior_opening_only_matches_cfast_enthalpy"]
        and verdict["additive_pressure_route_is_excess_enthalpy_owner"]
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
