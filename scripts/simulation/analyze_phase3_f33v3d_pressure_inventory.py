#!/usr/bin/env python3
"""Attribute canonical R0 pressure to mass and enthalpy owners.

This read-only F3.3v3d audit reconstructs the ideal-gas pressure published by
the Phase 3 shadow ledger. It compares the unfiltered and filtered fire-growth
candidates with committed CFAST pressure checkpoints and identifies whether
the pressure solvers create or correct each sign reversal.
"""

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


CFAST_DIR = ROOT / "sim" / "validation" / "cfast"
CHECKPOINTS = tuple(range(10, 181, 10))
AIR_PRESSURE_REF_PA = 101325.0
AIR_DENSITY_REF_KG_M3 = 1.2
AIR_CP_KJ_KG_K = 1.0
REFERENCE_TEMP_C = 20.0
R0_VOLUME_M3 = 48.0
PRESSURE_TOLERANCE_PA = 1.0e-3
MULTISURFACE_TOLERANCE_KJ = 1.0e-5
SIGN_EPS_PA = 1.0e-6

MASS_FAMILIES = (
    "combustion",
    "plume",
    "interzone",
    "wall",
    "ambient",
    "exterior",
    "exterior_counterflow",
    "interior_opening",
    "interior_pressure",
    "parcel",
    "doorway_jet",
    "legacy",
    "zone_collapse",
    "reconcile",
    "other",
)
ENTHALPY_FAMILIES = tuple(
    family for family in MASS_FAMILIES if family != "reconcile"
)


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def gas_constant_model(reference_temp_c: float = REFERENCE_TEMP_C) -> float:
    reference_temp_k = reference_temp_c + 273.15
    return AIR_PRESSURE_REF_PA / (
        AIR_DENSITY_REF_KG_M3 * reference_temp_k
    )


def pressure_gauge_from_inventory(
    mass_kg: float,
    energy_kj: float,
    *,
    volume_m3: float = R0_VOLUME_M3,
    reference_temp_c: float = REFERENCE_TEMP_C,
) -> float:
    reference_temp_k = reference_temp_c + 273.15
    pressure_abs_pa = gas_constant_model(reference_temp_c) / volume_m3 * (
        reference_temp_k * mass_kg + energy_kj / AIR_CP_KJ_KG_K
    )
    return pressure_abs_pa - AIR_PRESSURE_REF_PA


def pressure_delta_from_inventory(
    mass_kg: float,
    energy_kj: float,
    *,
    volume_m3: float = R0_VOLUME_M3,
    reference_temp_c: float = REFERENCE_TEMP_C,
) -> float:
    reference_temp_k = reference_temp_c + 273.15
    return gas_constant_model(reference_temp_c) / volume_m3 * (
        reference_temp_k * mass_kg + energy_kj / AIR_CP_KJ_KG_K
    )


def _family_net(
    row: dict[str, str],
    family: str,
    *,
    ledger: str,
    unit: str,
) -> float:
    return sum(
        _number(
            row.get(
                f"phase3_shadow_{ledger}_{family}_{zone}_in_{unit}_total"
            )
        )
        - _number(
            row.get(
                f"phase3_shadow_{ledger}_{family}_{zone}_out_{unit}_total"
            )
        )
        for zone in ("upper", "lower")
    )


def family_inventory(row: dict[str, str], family: str) -> dict[str, float]:
    mass_kg = (
        _family_net(
            row, family, ledger="mass_residence", unit="kg"
        )
        if family in MASS_FAMILIES
        else 0.0
    )
    energy_kj = (
        _family_net(row, family, ledger="enthalpy", unit="kj")
        if family in ENTHALPY_FAMILIES
        else 0.0
    )
    return {
        "mass_kg": mass_kg,
        "energy_kj": energy_kj,
        "pressure_pa": pressure_delta_from_inventory(mass_kg, energy_kj),
    }


def _initial_inventory(row: dict[str, str]) -> tuple[float, float]:
    mass_kg = _number(
        row.get("phase3_shadow_mass_residence_initial_upper_kg")
    ) + _number(row.get("phase3_shadow_mass_residence_initial_lower_kg"))
    energy_kj = _number(
        row.get("phase3_shadow_enthalpy_initial_upper_kj")
    ) + _number(row.get("phase3_shadow_enthalpy_initial_lower_kj"))
    return mass_kg, energy_kj


def _observed_inventory(row: dict[str, str]) -> tuple[float, float]:
    mass_kg = _number(
        row.get("phase3_shadow_mass_residence_observed_upper_kg")
    ) + _number(row.get("phase3_shadow_mass_residence_observed_lower_kg"))
    energy_kj = _number(
        row.get("phase3_shadow_enthalpy_observed_upper_kj")
    ) + _number(row.get("phase3_shadow_enthalpy_observed_lower_kj"))
    return mass_kg, energy_kj


def pressure_snapshot(row: dict[str, str]) -> dict[str, Any]:
    initial_mass, initial_energy = _initial_inventory(row)
    observed_mass, observed_energy = _observed_inventory(row)
    raw_owners = {
        family: family_inventory(row, family) for family in MASS_FAMILIES
    }
    initial_pressure = pressure_gauge_from_inventory(
        initial_mass, initial_energy
    )
    reconstructed_pressure = initial_pressure + sum(
        owner["pressure_pa"] for owner in raw_owners.values()
    )
    observed_pressure = pressure_gauge_from_inventory(
        observed_mass, observed_energy
    )
    reported_pressure = _number(
        row.get("phase3_shadow_thermo_pressure_gauge_pa")
    )

    other = raw_owners["other"]
    multisurface_gas_exchange = _number(
        row.get("phase3_shadow_multisurface_cumulative_gas_exchange_kj")
    )
    other_is_multisurface = (
        abs(other["mass_kg"]) <= 1.0e-9
        and abs(other["energy_kj"] + multisurface_gas_exchange)
        <= MULTISURFACE_TOLERANCE_KJ
    )
    owners = {
        ("multisurface" if family == "other" and other_is_multisurface else family):
        values
        for family, values in raw_owners.items()
    }
    return {
        "initial_mass_kg": initial_mass,
        "initial_energy_kj": initial_energy,
        "observed_mass_kg": observed_mass,
        "observed_energy_kj": observed_energy,
        "initial_pressure_gauge_pa": initial_pressure,
        "observed_eos_pressure_gauge_pa": observed_pressure,
        "reported_pressure_gauge_pa": reported_pressure,
        "reconstructed_pressure_gauge_pa": reconstructed_pressure,
        "observed_eos_residual_pa": reported_pressure - observed_pressure,
        "owner_reconstruction_residual_pa": (
            reported_pressure - reconstructed_pressure
        ),
        "other_is_exact_multisurface": other_is_multisurface,
        "multisurface_cumulative_gas_exchange_kj": (
            multisurface_gas_exchange
        ),
        "owners": owners,
    }


def _window_contributions(
    current: dict[str, Any],
    previous: dict[str, Any] | None,
) -> dict[str, float]:
    previous_owners = previous["owners"] if previous is not None else {}
    result: dict[str, float] = {}
    for owner, values in current["owners"].items():
        result[owner] = values["pressure_pa"] - _number(
            previous_owners.get(owner, {}).get("pressure_pa")
        )
    return result


def build_candidate_audit(
    *,
    candidate_csv: Path,
    cfast_compartments_path: Path,
    label: str,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    sim_rows = f33v3b.read_sim_rows(candidate_csv)
    cfast_rows = f33m.read_cfast_compartments(cfast_compartments_path)
    snapshots: dict[str, Any] = {}
    previous_inventory: dict[str, Any] | None = None
    previous_reported_pressure = 0.0
    mismatch_checkpoints: list[int] = []

    for checkpoint in checkpoints:
        row = f33v3b.sim_row_at(sim_rows, 0, checkpoint)
        cfast_row = min(
            cfast_rows,
            key=lambda candidate: abs(
                _number(candidate.get("Time")) - checkpoint
            ),
        )
        inventory = pressure_snapshot(row)
        window = _window_contributions(inventory, previous_inventory)
        cfast_pressure = _number(cfast_row.get("PRS_1"))
        exterior_pre = _number(
            row.get("phase3_shadow_exterior_pressure_pre_pa")
        )
        mismatch = (
            abs(cfast_pressure) > SIGN_EPS_PA
            and abs(exterior_pre) > SIGN_EPS_PA
            and cfast_pressure * exterior_pre < 0.0
        )
        if mismatch:
            mismatch_checkpoints.append(checkpoint)
        interior_pre = _number(
            row.get("phase3_shadow_interior_pressure_pre_pa")
        )
        interior_post = _number(
            row.get("phase3_shadow_interior_pressure_predicted_post_pa")
        )
        exterior_post = _number(
            row.get("phase3_shadow_exterior_pressure_predicted_post_pa")
        )
        snapshots[str(checkpoint)] = {
            **inventory,
            "cfast_pressure_pa": cfast_pressure,
            "interior_pressure_pre_pa": interior_pre,
            "interior_pressure_predicted_post_pa": interior_post,
            "exterior_pressure_pre_pa": exterior_pre,
            "exterior_pressure_predicted_post_pa": exterior_post,
            "reported_window_delta_pa": (
                inventory["reported_pressure_gauge_pa"]
                - previous_reported_pressure
            ),
            "window_owner_pressure_pa": window,
            "pressure_sign_mismatch": mismatch,
        }
        previous_inventory = inventory
        previous_reported_pressure = inventory[
            "reported_pressure_gauge_pa"
        ]

    first_mismatch = (
        snapshots[str(mismatch_checkpoints[0])]
        if mismatch_checkpoints
        else None
    )
    first_details: dict[str, Any] | None = None
    if first_mismatch is not None:
        negative = {
            owner: value
            for owner, value in first_mismatch[
                "window_owner_pressure_pa"
            ].items()
            if value < 0.0
        }
        primary_negative = min(negative, key=negative.get)
        mass_routing = {
            owner: value
            for owner, value in negative.items()
            if owner
            in {
                "exterior",
                "exterior_counterflow",
                "interior_opening",
                "interior_pressure",
                "parcel",
                "doorway_jet",
            }
        }
        primary_mass_routing = (
            min(mass_routing, key=mass_routing.get)
            if mass_routing
            else None
        )
        interior_correction = (
            first_mismatch["interior_pressure_predicted_post_pa"]
            - first_mismatch["interior_pressure_pre_pa"]
        )
        exterior_correction = (
            first_mismatch["reported_pressure_gauge_pa"]
            - first_mismatch["exterior_pressure_pre_pa"]
        )
        first_details = {
            "checkpoint_s": mismatch_checkpoints[0],
            "primary_negative_window_owner": primary_negative,
            "primary_mass_routing_window_owner": primary_mass_routing,
            "interior_pressure_correction_pa": interior_correction,
            "exterior_pressure_correction_pa": exterior_correction,
            "sign_is_negative_before_interior_pressure": (
                first_mismatch["interior_pressure_pre_pa"] < 0.0
            ),
            "interior_pressure_is_restorative": interior_correction > 0.0,
            "exterior_pressure_is_restorative": exterior_correction > 0.0,
            "pressure_solver_created_negative_sign": not (
                first_mismatch["interior_pressure_pre_pa"] < 0.0
            ),
        }

    max_reconstruction_residual = max(
        abs(snapshot["owner_reconstruction_residual_pa"])
        for snapshot in snapshots.values()
    )
    max_observed_residual = max(
        abs(snapshot["observed_eos_residual_pa"])
        for snapshot in snapshots.values()
    )
    return {
        "label": label,
        "candidate_csv": str(candidate_csv),
        "checkpoints": snapshots,
        "verdict": {
            "pressure_eos_closes": (
                max_reconstruction_residual <= PRESSURE_TOLERANCE_PA
                and max_observed_residual <= PRESSURE_TOLERANCE_PA
            ),
            "max_owner_reconstruction_residual_pa": (
                max_reconstruction_residual
            ),
            "max_observed_eos_residual_pa": max_observed_residual,
            "other_is_exact_multisurface_at_all_checkpoints": all(
                snapshot["other_is_exact_multisurface"]
                for snapshot in snapshots.values()
            ),
            "pressure_sign_mismatch_checkpoints": mismatch_checkpoints,
            "first_pressure_sign_mismatch": first_details,
        },
    }


def build_audit(
    *,
    unfiltered_csv: Path,
    filtered_csv: Path,
    cfast_compartments_path: Path,
) -> dict[str, Any]:
    unfiltered = build_candidate_audit(
        candidate_csv=unfiltered_csv,
        cfast_compartments_path=cfast_compartments_path,
        label="unfiltered",
    )
    filtered = build_candidate_audit(
        candidate_csv=filtered_csv,
        cfast_compartments_path=cfast_compartments_path,
        label="filtered",
    )
    first_u = unfiltered["verdict"]["first_pressure_sign_mismatch"]
    first_f = filtered["verdict"]["first_pressure_sign_mismatch"]
    owner_order_consistent = (
        first_u is not None
        and first_f is not None
        and first_u["primary_negative_window_owner"]
        == first_f["primary_negative_window_owner"]
        and first_u["primary_mass_routing_window_owner"]
        == first_f["primary_mass_routing_window_owner"]
    )
    sign_is_upstream_in_both = all(
        first is not None
        and first["sign_is_negative_before_interior_pressure"]
        and not first["pressure_solver_created_negative_sign"]
        for first in (first_u, first_f)
    )
    return {
        "unfiltered": unfiltered,
        "filtered": filtered,
        "verdict": {
            "both_candidates_close_eos": all(
                candidate["verdict"]["pressure_eos_closes"]
                for candidate in (unfiltered, filtered)
            ),
            "owner_order_consistent": owner_order_consistent,
            "negative_sign_is_upstream_of_pressure_solver_in_both": (
                sign_is_upstream_in_both
            ),
            "unfiltered_pressure_corrections_restorative": (
                first_u is not None
                and first_u["interior_pressure_is_restorative"]
                and first_u["exterior_pressure_is_restorative"]
            ),
            "filtered_pressure_feedback_is_state_sensitive": (
                first_f is not None
                and not first_f["interior_pressure_is_restorative"]
            ),
            "pressure_or_leakage_tuning_allowed": False,
            "root_cause_class": (
                "near-cancellation of combustion input by multisurface "
                "energy loss and interior-opening inventory outflow"
            ),
            "next_gate": (
                "compare canonical multisurface energy loss and interior "
                "opening enthalpy authority with CFAST before a motor patch"
            ),
        },
    }


def _print_candidate(candidate: dict[str, Any]) -> None:
    verdict = candidate["verdict"]
    print(f"\n{candidate['label']}")
    print(
        "time  CFAST  SF-pre  SF-final  dP-window  "
        "combustion  multisurface  int-opening  int-pressure  exterior"
    )
    for checkpoint, snapshot in candidate["checkpoints"].items():
        owners = snapshot["window_owner_pressure_pa"]
        print(
            f"{checkpoint:>4} "
            f"{snapshot['cfast_pressure_pa']:>7.1f} "
            f"{snapshot['exterior_pressure_pre_pa']:>7.1f} "
            f"{snapshot['reported_pressure_gauge_pa']:>8.1f} "
            f"{snapshot['reported_window_delta_pa']:>9.1f} "
            f"{owners.get('combustion', 0.0):>11.1f} "
            f"{owners.get('multisurface', 0.0):>12.1f} "
            f"{owners.get('interior_opening', 0.0):>11.1f} "
            f"{owners.get('interior_pressure', 0.0):>12.1f} "
            f"{owners.get('exterior', 0.0):>8.1f}"
        )
    print(
        "sign mismatches:",
        verdict["pressure_sign_mismatch_checkpoints"],
    )
    print(
        "max owner residual:",
        f"{verdict['max_owner_reconstruction_residual_pa']:.3e} Pa",
    )
    print("first mismatch:", verdict["first_pressure_sign_mismatch"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--unfiltered-csv",
        type=Path,
        default=Path("runs/phase3_f33v3a/180_on/sim_log.csv"),
    )
    parser.add_argument(
        "--filtered-csv",
        type=Path,
        default=Path("runs/phase3_f33v3/180_full/sim_log.csv"),
    )
    parser.add_argument(
        "--cfast-compartments",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain_compartments.csv",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)
    audit = build_audit(
        unfiltered_csv=args.unfiltered_csv,
        filtered_csv=args.filtered_csv,
        cfast_compartments_path=args.cfast_compartments,
    )
    _print_candidate(audit["unfiltered"])
    _print_candidate(audit["filtered"])
    print("\nverdict:", audit["verdict"])
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    verdict = audit["verdict"]
    return (
        0
        if verdict["both_candidates_close_eos"]
        and verdict["owner_order_consistent"]
        and verdict[
            "negative_sign_is_upstream_of_pressure_solver_in_both"
        ]
        and not verdict["pressure_or_leakage_tuning_allowed"]
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
