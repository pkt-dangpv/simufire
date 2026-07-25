#!/usr/bin/env python3
"""Attribute the F3.3r2c radiation shortfall and surface routing mismatch."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Callable, Iterable


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.simulation import analyze_phase3_f33m_source_correspondence as f33m
from scripts.simulation import analyze_phase3_f33r1_boundary_partition as f33r1
from scripts.simulation import analyze_phase3_f33r2c_correspondence as f33r2c


CHECKPOINTS = (60, 120, 180)
SURFACES = ("ceiling", "upper_wall", "lower_wall", "floor")
RADIATIVE_FRACTION = 0.35
LEDGER_TOLERANCE_KJ = 1.0e-4
DECISION_TOLERANCE = 1.0e-7


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def surface_weights(room_id: int, interface_m: float) -> dict[str, float]:
    """Return the equal-emissivity area weights used by the current router."""
    width_m, length_m, height_m = f33r1.ROOM_GEOMETRY_M[room_id]
    areas = f33r1.surface_areas_m2(
        width_m, length_m, height_m, interface_m
    )
    total_area = sum(areas.values())
    if total_area <= 0.0:
        raise ValueError("surface area is zero")
    return {name: areas[name] / total_area for name in SURFACES}


def counterfactual_routing(
    rows: Iterable[dict[str, str]],
    *,
    room_id: int,
    checkpoint_s: float,
    interface_at: Callable[[float], float],
) -> dict[str, float]:
    """Route observed accepted-radiation increments with another interface."""
    selected = sorted(
        (
            row
            for row in rows
            if int(_number(row.get("room_id"))) == room_id
            and _number(row.get("time_s")) <= checkpoint_s + 0.11
        ),
        key=lambda row: _number(row.get("time_s")),
    )
    if not selected:
        raise ValueError(f"room {room_id} has no rows before {checkpoint_s:g}s")
    routed = {surface: 0.0 for surface in SURFACES}
    previous_total = 0.0
    for row in selected:
        total = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_fire_radiation_kj"
            )
        )
        increment = max(0.0, total - previous_total)
        previous_total = total
        weights = surface_weights(
            room_id, interface_at(_number(row.get("time_s")))
        )
        for surface in SURFACES:
            routed[surface] += increment * weights[surface]
    return routed


def source_decomposition(
    *,
    cfast_radiation_kj: float,
    requested_kj: float,
    pre_atomic_kj: float,
    decision_rejected_kj: float,
    atomic_rejected_kj: float,
    routed_kj: float,
) -> dict[str, Any]:
    upstream_kj = cfast_radiation_kj - requested_kj
    cfast_shortfall_kj = cfast_radiation_kj - routed_kj
    requested_closure_kj = (
        requested_kj - pre_atomic_kj - decision_rejected_kj
    )
    accepted_closure_kj = (
        pre_atomic_kj - routed_kj - atomic_rejected_kj
    )
    decomposition_residual_kj = (
        cfast_shortfall_kj
        - upstream_kj
        - decision_rejected_kj
        - atomic_rejected_kj
    )
    contributions = {
        "upstream_source_trajectory": upstream_kj,
        "decision_rejection": decision_rejected_kj,
        "atomic_rejection": atomic_rejected_kj,
    }
    dominant = max(contributions, key=lambda name: abs(contributions[name]))
    return {
        "cfast_shortfall_kj": cfast_shortfall_kj,
        "upstream_source_trajectory_kj": upstream_kj,
        "decision_rejected_kj": decision_rejected_kj,
        "atomic_rejected_kj": atomic_rejected_kj,
        "requested_closure_kj": requested_closure_kj,
        "accepted_closure_kj": accepted_closure_kj,
        "decomposition_residual_kj": decomposition_residual_kj,
        "dominant_cause": dominant,
    }


def _actual_surface_radiation(row: dict[str, str]) -> dict[str, float]:
    return {
        surface: _number(
            row.get(
                "phase3_shadow_multisurface_"
                + surface
                + "_cumulative_fire_radiation_kj"
            )
        )
        for surface in SURFACES
    }


def _cfast_interface_lookup(
    zone_rows: list[dict[str, str]],
    compartment_rows: list[dict[str, str]],
    room_id: int,
) -> Callable[[float], float]:
    def interface_at(time_s: float) -> float:
        checkpoint = max(0, int(round(time_s)))
        return _number(
            f33m.build_cfast_checkpoint(
                checkpoint, zone_rows, compartment_rows
            )["rooms"][str(room_id)]["interface_m"]
        )

    return interface_at


def build_audit(
    *,
    off_csv: Path,
    candidate_csv: Path,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    checkpoint_values = tuple(checkpoints)
    if not checkpoint_values:
        raise ValueError("at least one checkpoint is required")
    off_rows = f33r2c.read_rows(off_csv)
    candidate_rows = f33r2c.read_rows(candidate_csv)
    zone_rows = f33m.read_cfast_zone(
        f33r2c.CFAST_DIR / "cfast_corridor_chain_zone.csv"
    )
    compartment_rows = f33m.read_cfast_compartments(
        f33r2c.CFAST_DIR / "cfast_corridor_chain_compartments.csv"
    )
    interface_at = _cfast_interface_lookup(zone_rows, compartment_rows, 0)
    snapshots: dict[str, Any] = {}
    for checkpoint in checkpoint_values:
        row = f33r2c.row_at(candidate_rows, 0, checkpoint)
        off_row = f33r2c.row_at(off_rows, 0, checkpoint)
        cfast_room = f33m.build_cfast_checkpoint(
            checkpoint, zone_rows, compartment_rows
        )["rooms"]["0"]
        cfast_radiation_kj = (
            RADIATIVE_FRACTION
            * _number(cfast_room.get("hrr_energy_kj"))
        )
        requested_kj = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_requested_fire_radiation_kj"
            )
        )
        pre_atomic_kj = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_pre_atomic_fire_radiation_kj"
            )
        )
        decision_rejected_kj = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_decision_rejected_radiation_kj"
            )
        )
        atomic_rejected_kj = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_atomic_rejected_radiation_kj"
            )
        )
        routed_kj = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_fire_radiation_kj"
            )
        )
        upper_exchange_kj = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_upper_exchange_kj"
            )
        )
        lower_exchange_kj = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_lower_exchange_kj"
            )
        )
        gas_exchange_kj = _number(
            row.get(
                "phase3_shadow_multisurface_cumulative_gas_exchange_kj"
            )
        )
        actual_routing = _actual_surface_radiation(row)
        cfast_interface_routing = counterfactual_routing(
            candidate_rows,
            room_id=0,
            checkpoint_s=checkpoint,
            interface_at=interface_at,
        )
        routing_delta = {
            surface: actual_routing[surface]
            - cfast_interface_routing[surface]
            for surface in SURFACES
        }
        redistribution_kj = 0.5 * sum(
            abs(value) for value in routing_delta.values()
        )
        decomposition = source_decomposition(
            cfast_radiation_kj=cfast_radiation_kj,
            requested_kj=requested_kj,
            pre_atomic_kj=pre_atomic_kj,
            decision_rejected_kj=decision_rejected_kj,
            atomic_rejected_kj=atomic_rejected_kj,
            routed_kj=routed_kj,
        )
        decision_fraction = _number(
            row.get("phase3_shadow_combustion_decision_fraction")
        )
        o2_hrr_factor = _number(
            row.get("phase3_shadow_combustion_canonical_o2_hrr_factor")
        )
        snapshots[str(checkpoint)] = {
            "cfast_radiation_kj": cfast_radiation_kj,
            "requested_radiation_kj": requested_kj,
            "pre_atomic_accepted_radiation_kj": pre_atomic_kj,
            "routed_radiation_kj": routed_kj,
            "source": decomposition,
            "actual_surface_radiation_kj": actual_routing,
            "cfast_interface_counterfactual_kj": cfast_interface_routing,
            "routing_delta_kj": routing_delta,
            "routing_redistribution_kj": redistribution_kj,
            "candidate_interface_m": _number(
                row.get("phase3_shadow_thermo_interface_m")
            ),
            "cfast_interface_m": _number(cfast_room.get("interface_m")),
            "migration_energy_kj": _number(
                row.get(
                    "phase3_shadow_multisurface_cumulative_migration_energy_kj"
                )
            ),
            "upper_gas_surface_exchange_kj": upper_exchange_kj,
            "lower_gas_surface_exchange_kj": lower_exchange_kj,
            "total_gas_surface_exchange_kj": gas_exchange_kj,
            "gas_surface_split_residual_kj": (
                gas_exchange_kj - upper_exchange_kj - lower_exchange_kj
            ),
            "candidate_o2_ref": _number(
                row.get("phase3_shadow_combustion_canonical_o2_ref")
            ),
            "cfast_upper_o2_fraction": _number(
                cfast_room.get("upper_o2_fraction")
            ),
            "cfast_lower_o2_fraction": _number(
                cfast_room.get("lower_o2_fraction")
            ),
            "candidate_o2_hrr_factor": o2_hrr_factor,
            "candidate_decision_fraction": decision_fraction,
            "decision_o2_factor_delta": decision_fraction - o2_hrr_factor,
            "decision_matches_o2_factor": abs(
                decision_fraction - o2_hrr_factor
            ) <= DECISION_TOLERANCE,
            "candidate_accepted_hrr_kw": _number(
                row.get("phase3_shadow_combustion_accepted_hrr_kw")
            ),
            "candidate_legacy_hrr_kw": _number(
                row.get("phase3_shadow_combustion_legacy_hrr_kw")
            ),
            "cfast_hrr_kw": _number(cfast_room.get("hrr_kw")),
            "off_o2_ref": _number(
                off_row.get("phase3_shadow_combustion_canonical_o2_ref")
            ),
            "off_o2_hrr_factor": _number(
                off_row.get(
                    "phase3_shadow_combustion_canonical_o2_hrr_factor"
                )
            ),
            "off_accepted_hrr_kw": _number(
                off_row.get("phase3_shadow_combustion_accepted_hrr_kw")
            ),
            "ledger_pass": all(
                abs(decomposition[field]) <= LEDGER_TOLERANCE_KJ
                for field in (
                    "requested_closure_kj",
                    "accepted_closure_kj",
                    "decomposition_residual_kj",
                )
            ),
        }

    final = snapshots[str(max(checkpoint_values))]
    source = final["source"]
    routing_total_residual = sum(final["routing_delta_kj"].values())
    return {
        "checkpoints": snapshots,
        "legacy_invariance": f33r2c.compare_legacy_cells(
            off_rows, candidate_rows
        ),
        "final_diagnosis": {
            "dominant_source_cause": source["dominant_cause"],
            "source_shortfall_kj": source["cfast_shortfall_kj"],
            "routing_redistribution_kj": final[
                "routing_redistribution_kj"
            ],
            "routing_total_residual_kj": routing_total_residual,
            "all_source_ledgers_pass": all(
                snapshot["ledger_pass"] for snapshot in snapshots.values()
            ),
            "all_gas_surface_splits_pass": all(
                abs(snapshot["gas_surface_split_residual_kj"])
                <= LEDGER_TOLERANCE_KJ
                for snapshot in snapshots.values()
            ),
            "all_decisions_match_o2_factor": all(
                snapshot["decision_matches_o2_factor"]
                for snapshot in snapshots.values()
            ),
            "max_abs_decision_o2_factor_delta": max(
                abs(snapshot["decision_o2_factor_delta"])
                for snapshot in snapshots.values()
            ),
        },
    }


def _print_audit(audit: dict[str, Any]) -> None:
    print("F3.3r2d source/interface/routing attribution")
    print("time  CFAST MJ  requested  routed  upstream  decision  atomic")
    for checkpoint, snapshot in audit["checkpoints"].items():
        source = snapshot["source"]
        print(
            f"{checkpoint:>4} "
            f"{snapshot['cfast_radiation_kj'] / 1000:>9.3f} "
            f"{snapshot['requested_radiation_kj'] / 1000:>10.3f} "
            f"{snapshot['routed_radiation_kj'] / 1000:>7.3f} "
            f"{source['upstream_source_trajectory_kj'] / 1000:>8.3f} "
            f"{source['decision_rejected_kj'] / 1000:>8.3f} "
            f"{source['atomic_rejected_kj'] / 1000:>7.3f}"
        )
    final = audit["final_diagnosis"]
    print(f"\ndominant source cause: {final['dominant_source_cause']}")
    print(
        "routing redistribution at 180 s: "
        f"{final['routing_redistribution_kj'] / 1000:.3f} MJ"
    )
    print(
        "source ledgers: "
        f"{'PASS' if final['all_source_ledgers_pass'] else 'FAIL'}"
    )
    print(
        "decision fraction == canonical O2 factor: "
        f"{'PASS' if final['all_decisions_match_o2_factor'] else 'FAIL'}"
    )
    print(
        "gas/surface upper+lower split: "
        f"{'PASS' if final['all_gas_surface_splits_pass'] else 'FAIL'}"
    )
    legacy = audit["legacy_invariance"]
    print(
        "legacy invariance: "
        f"{legacy['different_cells']} differences / "
        f"{legacy['compared_cells']} compared cells"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--off-csv",
        type=Path,
        default=Path("runs/phase3_f33r2d/180_corridor_off/sim_log.csv"),
    )
    parser.add_argument(
        "--candidate-csv",
        type=Path,
        default=Path(
            "runs/phase3_f33r2d/180_corridor_cfast/sim_log.csv"
        ),
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()
    audit = build_audit(
        off_csv=args.off_csv,
        candidate_csv=args.candidate_csv,
    )
    _print_audit(audit)
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    diagnosis = audit["final_diagnosis"]
    return 0 if (
        diagnosis["all_source_ledgers_pass"]
        and diagnosis["all_gas_surface_splits_pass"]
        and diagnosis["all_decisions_match_o2_factor"]
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())
