#!/usr/bin/env python3
"""Attribute canonical room pressure to each physical owner, exactly.

The canonical EOS in `Phase3ZoneMassSystem.derive_canonical_thermodynamic_state`
is

    p_r = (R / V_r) * (m_u * T_u + m_l * T_l),   T_z = T_ref + E_z / (m_z * cp)

and substituting `m_z * T_z = m_z * T_ref + E_z / cp` collapses it to

    p_r = (R / V_r) * (M_r * T_ref + E_r / cp),  R = P_ref / (rho_ref * T_ref)

which is **exactly affine** in room total mass and room total energy. Pressure
therefore superposes over owners with no cross terms:

    dp_{r,f} = (R / V_r) * (dM_{r,f} * T_ref + dE_{r,f} / cp)

Two consequences drive the F3.3v3h0 design:

1. an owner that only moves mass or energy *between zones of the same room*
   (plume, inter-zone heat) contributes exactly zero to `p_r`;
2. any solve that reduces a residual built from a *subset* of owners is wrong
   by the whole neglected sum, which is what F3.3v3g3 measured as runaway.

This script is read-only. It consumes the committed F3.3c1 enthalpy-residence
and F3.3d1 mass-residence columns and closes against the exported EOS pressure.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CSV = ROOT / "runs" / "phase3_f33v3h0" / "180_owners" / "sim_log.csv"

AIR_PRESSURE_REF_PA = 101325.0
AIR_DENSITY_REF_KG_M3 = 1.2
AIR_CP_KJ_KG_K = 1.0

# Same list as Phase3ZoneMassSystem.MASS_RESIDENCE_FAMILIES.
FAMILIES = (
    "combustion", "plume", "interzone", "wall", "ambient", "exterior",
    "exterior_counterflow", "interior_opening", "interior_pressure",
    "parcel", "doorway_jet", "legacy", "zone_collapse", "reconcile", "other",
)

# Owners that can only move mass/energy between zones of one room. Their exact
# pressure contribution is zero; a non-zero measurement means the ledger or the
# EOS assumption changed and the design premise must be re-derived.
INTRA_ROOM_FAMILIES = ("plume", "interzone")

# The attribution differences cumulative residence totals that the CSV prints
# with `%.8f`. Those totals reach ~1e4 kJ by 180 s, so the print quantisation
# alone is ~1e-4 Pa once converted through R/V. This tolerance is CSV precision,
# not a physical allowance: the underlying identity is exact.
CLOSURE_TOLERANCE_PA = 1.0e-3


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def family_totals(row: dict[str, str], family: str) -> tuple[float, float]:
    """Net (mass, energy) delivered to a room by one family, both zones."""
    mass_kg = 0.0
    energy_kj = 0.0
    for zone in ("upper", "lower"):
        mass_kg += float(
            row.get(f"phase3_shadow_mass_residence_{family}_{zone}_in_kg_total", 0.0)
            or 0.0
        ) - float(
            row.get(f"phase3_shadow_mass_residence_{family}_{zone}_out_kg_total", 0.0)
            or 0.0
        )
        energy_kj += float(
            row.get(f"phase3_shadow_enthalpy_{family}_{zone}_in_kj_total", 0.0)
            or 0.0
        ) - float(
            row.get(f"phase3_shadow_enthalpy_{family}_{zone}_out_kj_total", 0.0)
            or 0.0
        )
    return mass_kg, energy_kj


def owner_pressure_delta_pa(
    mass_kg: float, energy_kj: float, volume_m3: float, reference_temp_c: float
) -> float:
    reference_temp_k = reference_temp_c + 273.15
    gas_constant = AIR_PRESSURE_REF_PA / (AIR_DENSITY_REF_KG_M3 * reference_temp_k)
    return (gas_constant / volume_m3) * (
        mass_kg * reference_temp_k + energy_kj / AIR_CP_KJ_KG_K
    )


def attribute_room(
    rows: list[dict[str, str]], room_id: int, reference_temp_c: float
) -> dict[str, Any]:
    room_rows = [r for r in rows if int(float(r["room_id"])) == room_id]
    if len(room_rows) < 2:
        raise ValueError(f"room {room_id} has fewer than two samples")
    intervals: list[dict[str, Any]] = []
    peak_abs: dict[str, float] = {f: 0.0 for f in FAMILIES}
    gross_abs_pa = 0.0
    net_pa = 0.0
    worst_closure_pa = 0.0
    previous = None
    previous_gauge_pa = 0.0
    for row in room_rows:
        volume_m3 = float(row["volume_m3"])
        gauge_pa = float(row["phase3_shadow_thermo_pressure_gauge_pa"])
        current = {f: family_totals(row, f) for f in FAMILIES}
        if previous is not None:
            deltas: dict[str, float] = {}
            for family in FAMILIES:
                mass_kg = current[family][0] - previous[family][0]
                energy_kj = current[family][1] - previous[family][1]
                delta_pa = owner_pressure_delta_pa(
                    mass_kg, energy_kj, volume_m3, reference_temp_c
                )
                deltas[family] = delta_pa
                peak_abs[family] = max(peak_abs[family], abs(delta_pa))
            attributed_pa = sum(deltas.values())
            observed_pa = gauge_pa - previous_gauge_pa
            closure_pa = attributed_pa - observed_pa
            worst_closure_pa = max(worst_closure_pa, abs(closure_pa))
            gross_abs_pa += sum(abs(v) for v in deltas.values())
            net_pa += attributed_pa
            intervals.append(
                {
                    "time_s": float(row["time_s"]),
                    "owner_delta_pa": deltas,
                    "attributed_delta_pa": attributed_pa,
                    "observed_delta_pa": observed_pa,
                    "closure_residual_pa": closure_pa,
                }
            )
        previous = current
        previous_gauge_pa = gauge_pa
    ranked = sorted(
        ((f, peak_abs[f]) for f in FAMILIES if peak_abs[f] > 1.0e-9),
        key=lambda item: -item[1],
    )
    intra_room_max_pa = max(
        (peak_abs[f] for f in INTRA_ROOM_FAMILIES), default=0.0
    )
    return {
        "room_id": room_id,
        "interval_count": len(intervals),
        "intervals": intervals,
        "peak_abs_delta_pa": dict(ranked),
        "ranked_owners": [f for f, _ in ranked],
        "gross_abs_delta_pa": gross_abs_pa,
        "net_delta_pa": net_pa,
        # The defining stiffness number: individual owners are this many times
        # larger than the net pressure change they produce together.
        "cancellation_ratio": (
            gross_abs_pa / abs(net_pa) if abs(net_pa) > 1.0e-12 else float("inf")
        ),
        "worst_closure_residual_pa": worst_closure_pa,
        "intra_room_max_abs_delta_pa": intra_room_max_pa,
    }


def build_audit(
    *, csv_path: Path, room_ids: list[int], reference_temp_c: float
) -> dict[str, Any]:
    rows = read_csv(csv_path)
    required = "phase3_shadow_mass_residence_combustion_upper_in_kg_total"
    if not rows or required not in rows[0]:
        raise ValueError(
            "CSV lacks residence columns; rerun with "
            "--phase3-enthalpy-residence-diagnostics and "
            "--phase3-mass-residence-diagnostics"
        )
    per_room = [attribute_room(rows, room_id, reference_temp_c) for room_id in room_ids]
    worst_closure_pa = max(r["worst_closure_residual_pa"] for r in per_room)
    worst_intra_room_pa = max(r["intra_room_max_abs_delta_pa"] for r in per_room)
    min_cancellation = min(r["cancellation_ratio"] for r in per_room)
    unlabeled_pa = max(
        r["peak_abs_delta_pa"].get("other", 0.0) for r in per_room
    )
    largest_pa = max(
        max(r["peak_abs_delta_pa"].values(), default=0.0) for r in per_room
    )
    verdict = {
        # Proves the affine-superposition premise the H0 design rests on.
        "attribution_closes_against_eos": worst_closure_pa <= CLOSURE_TOLERANCE_PA,
        # Proves plume and inter-zone heat are not pressure owners.
        # Intra-room owners must be identically zero, not merely small.
        "intra_room_owners_are_pressure_neutral": worst_intra_room_pa == 0.0,
        # Proves a subset solve cannot be correct: owners cancel to this ratio.
        "owners_cancel_by_more_than_10x": min_cancellation >= 10.0,
        # Every material owner must be labelled before a solver can include it.
        "no_material_unlabeled_owner": (
            unlabeled_pa <= 0.01 * largest_pa if largest_pa > 0.0 else True
        ),
    }
    return {
        "csv": str(csv_path),
        "reference_temp_c": reference_temp_c,
        "rooms": per_room,
        "summary": {
            "worst_closure_residual_pa": worst_closure_pa,
            "worst_intra_room_abs_delta_pa": worst_intra_room_pa,
            "min_cancellation_ratio": min_cancellation,
            "peak_unlabeled_other_delta_pa": unlabeled_pa,
            "peak_owner_delta_pa": largest_pa,
        },
        "verdict": verdict,
    }


REQUIRED_VERDICTS = (
    "attribution_closes_against_eos",
    "intra_room_owners_are_pressure_neutral",
    "owners_cancel_by_more_than_10x",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--rooms", default="0,1,2")
    parser.add_argument("--reference-temp-c", type=float, default=20.0)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument(
        "--summary-only", action="store_true", help="Omit per-interval detail."
    )
    args = parser.parse_args()
    result = build_audit(
        csv_path=args.csv,
        room_ids=[int(v) for v in args.rooms.split(",") if v.strip()],
        reference_temp_c=args.reference_temp_c,
    )
    printable = result
    if args.summary_only:
        printable = {
            **result,
            "rooms": [
                {k: v for k, v in room.items() if k != "intervals"}
                for room in result["rooms"]
            ],
        }
    rendered = json.dumps(printable, indent=2, sort_keys=True)
    print(rendered)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    return 0 if all(result["verdict"][k] for k in REQUIRED_VERDICTS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
