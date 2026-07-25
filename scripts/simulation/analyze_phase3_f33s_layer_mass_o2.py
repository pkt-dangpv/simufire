#!/usr/bin/env python3
"""Audit the early Phase 3 layer-mass/interface/O2 causal chain.

This is a passive, read-only comparison between the F3.3r2d corridor
candidate and committed CFAST exports. It locates the first exported
checkpoint where layer mass or interface diverges, then attributes the
SimuFire mass balance to explicit residence-ledger owners.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.simulation import analyze_phase3_f33m_source_correspondence as f33m
from scripts.simulation import analyze_phase3_f33r2c_correspondence as f33r2c


CHECKPOINTS = tuple(range(10, 181, 10))
CFAST_DIR = ROOT / "sim" / "validation" / "cfast"
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
    "legacy",
    "zone_collapse",
    "reconcile",
    "other",
)
PROJECTION_FAMILIES = ("legacy", "zone_collapse", "reconcile", "other")
MASS_ABS_THRESHOLD_KG = 1.0
MASS_REL_THRESHOLD = 0.10
INTERFACE_THRESHOLD_M = 0.10
O2_FRACTION_THRESHOLD = 0.01
NEAR_INTERFACE_Z_EFF_M = 0.11
LEDGER_TOLERANCE_KG = 1.0e-6


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def read_cfast_masses(path: Path) -> list[dict[str, str]]:
    """Read a CFAST mass export with its five metadata rows."""
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    if len(lines) < 6:
        raise ValueError(f"invalid CFAST mass export: {path}")
    header = next(csv.reader([lines[0]]))
    rows: list[dict[str, str]] = []
    for values in csv.reader(lines[5:]):
        if values and values[0].strip():
            rows.append(dict(zip(header, values)))
    if not rows:
        raise ValueError(f"empty CFAST mass export: {path}")
    return rows


def cfast_row_at(
    rows: Iterable[dict[str, str]], checkpoint_s: float
) -> dict[str, str]:
    candidates = list(rows)
    if not candidates:
        raise ValueError("empty CFAST time series")
    row = min(
        candidates,
        key=lambda candidate: abs(
            _number(candidate.get("Time")) - checkpoint_s
        ),
    )
    if abs(_number(row.get("Time")) - checkpoint_s) > 0.11:
        raise ValueError(f"CFAST checkpoint {checkpoint_s:g}s is missing")
    return row


def residence_family_net(
    row: dict[str, str], family: str
) -> dict[str, float]:
    prefix = f"phase3_shadow_mass_residence_{family}_"
    upper_in = _number(row.get(prefix + "upper_in_kg_total"))
    upper_out = _number(row.get(prefix + "upper_out_kg_total"))
    lower_in = _number(row.get(prefix + "lower_in_kg_total"))
    lower_out = _number(row.get(prefix + "lower_out_kg_total"))
    upper = upper_in - upper_out
    lower = lower_in - lower_out
    return {
        "upper_kg": upper,
        "lower_kg": lower,
        "room_kg": upper + lower,
        "gross_kg": upper_in + upper_out + lower_in + lower_out,
    }


def residence_owners(row: dict[str, str]) -> dict[str, dict[str, float]]:
    return {
        family: residence_family_net(row, family)
        for family in MASS_FAMILIES
    }


def plume_geometry(
    *,
    hrr_kw: float,
    interface_m: float,
    room_height_m: float,
    fire_diameter_m: float,
    convective_fraction: float,
    confined_flame_enabled: bool = True,
    confined_z_eff_fraction: float = 1.0,
) -> dict[str, float | bool]:
    qc_kw = max(0.0, hrr_kw * convective_fraction)
    flame_length_m = max(
        0.0,
        0.235 * math.pow(max(0.0, hrr_kw), 0.4)
        - 1.02 * fire_diameter_m,
    )
    flame_reaches_interface = flame_length_m >= interface_m
    if confined_flame_enabled and flame_length_m >= room_height_m:
        z_eff_m = max(0.1, room_height_m * confined_z_eff_fraction)
        branch = "confined_room"
    else:
        z_eff_m = max(0.1, interface_m - flame_length_m)
        branch = (
            "interface_clamp"
            if flame_reaches_interface
            else "far_field"
        )
    height_term_rate_kg_s = (
        0.071
        * math.pow(qc_kw, 1.0 / 3.0)
        * math.pow(z_eff_m, 5.0 / 3.0)
        if qc_kw > 0.0
        else 0.0
    )
    return {
        "qc_kw": qc_kw,
        "flame_length_m": flame_length_m,
        "flame_reaches_interface": flame_reaches_interface,
        "z_eff_m": z_eff_m,
        "branch": branch,
        "height_term_rate_kg_s": height_term_rate_kg_s,
    }


def exceeds_mass_threshold(error_kg: float, reference_kg: float) -> bool:
    threshold = max(MASS_ABS_THRESHOLD_KG, MASS_REL_THRESHOLD * reference_kg)
    return abs(error_kg) > threshold


def first_checkpoint(
    snapshots: dict[str, dict[str, Any]], key: str
) -> int | None:
    for checkpoint in sorted(int(value) for value in snapshots):
        if bool(snapshots[str(checkpoint)].get(key, False)):
            return checkpoint
    return None


def causal_verdict(
    snapshots: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    first_mass = first_checkpoint(snapshots, "mass_or_interface_diverged")
    first_o2 = first_checkpoint(snapshots, "o2_diverged")
    first_crossing = first_checkpoint(
        snapshots, "flame_reaches_interface"
    )
    first_near_interface = first_checkpoint(
        snapshots, "near_interface_pinch"
    )
    first_cfast_crossing = first_checkpoint(
        snapshots, "cfast_flame_reaches_interface"
    )
    if first_mass is None:
        primary = "no_early_layer_divergence"
    else:
        snapshot = snapshots[str(first_mass)]
        projection_net = snapshot["projection_net_kg"]
        doorway_gross = snapshot["doorway_gross_kg"]
        plume_shortfall = snapshot["plume_cumulative_shortfall_kg"]
        if (
            snapshot["mass_ledger_pass"]
            and abs(projection_net) <= LEDGER_TOLERANCE_KG
            and plume_shortfall > MASS_ABS_THRESHOLD_KG
            and doorway_gross < abs(snapshot["upper_mass_error_kg"])
        ):
            primary = "plume_request_source_path"
        else:
            primary = "unresolved_mass_owner"
    return {
        "first_mass_or_interface_divergence_s": first_mass,
        "first_o2_divergence_s": first_o2,
        "first_flame_interface_crossing_s": first_crossing,
        "first_near_interface_pinch_s": first_near_interface,
        "first_cfast_flame_interface_crossing_s": first_cfast_crossing,
        "primary_owner": primary,
        "o2_is_downstream": (
            first_mass is not None
            and (first_o2 is None or first_o2 > first_mass)
        ),
        "projection_is_primary": False
        if first_mass is not None
        and abs(snapshots[str(first_mass)]["projection_net_kg"])
        <= LEDGER_TOLERANCE_KG
        else None,
        "next_experiment": (
            "region-aware plume-to-interface transition plus an aligned "
            "early HRR source; do not retry source-term-only F3.3d2"
            if primary == "plume_request_source_path"
            else "extend passive owner telemetry before changing physics"
        ),
    }


def _case_settings(manifest_path: Path) -> tuple[float, dict[str, Any]]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    scenario_path = Path(manifest["scenario_path"])
    scenario = json.loads(scenario_path.read_text(encoding="utf-8"))
    settings = scenario.get("engine_overrides", {})
    return _number(manifest.get("step_s")), settings


def build_audit(
    *,
    candidate_csv: Path,
    manifest_path: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    cfast_masses_path: Path,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    checkpoint_values = tuple(checkpoints)
    if not checkpoint_values:
        raise ValueError("at least one checkpoint is required")
    sim_rows = f33r2c.read_rows(candidate_csv)
    zone_rows = f33m.read_cfast_zone(cfast_zone_path)
    compartment_rows = f33m.read_cfast_compartments(
        cfast_compartments_path
    )
    mass_rows = read_cfast_masses(cfast_masses_path)
    step_s, settings = _case_settings(manifest_path)
    if step_s <= 0.0:
        raise ValueError("run manifest has no positive step_s")

    fire_diameter_m = _number(settings.get("plume_fire_diameter_m"), 0.5)
    convective_fraction = _number(
        settings.get("plume_mccaffrey_qc_fraction"), 0.7
    )
    confined_enabled = bool(
        settings.get("plume_confined_flame_enabled", True)
    )
    confined_fraction = _number(
        settings.get("plume_confined_z_eff_fraction"), 1.0
    )
    room_height_m = 2.4

    snapshots: dict[str, dict[str, Any]] = {}
    for checkpoint in checkpoint_values:
        row = f33r2c.row_at(sim_rows, 0, checkpoint)
        cfast = f33m.build_cfast_checkpoint(
            checkpoint, zone_rows, compartment_rows
        )
        cfast_room = cfast["rooms"]["0"]
        cfast_mass_row = cfast_row_at(mass_rows, checkpoint)
        cfast_compartment_row = cfast_row_at(
            compartment_rows, checkpoint
        )
        owners = residence_owners(row)
        sim_upper_mass = _number(
            row.get("phase3_shadow_mass_residence_observed_upper_kg")
        )
        sim_lower_mass = _number(
            row.get("phase3_shadow_mass_residence_observed_lower_kg")
        )
        sim_interface = _number(
            row.get("phase3_shadow_thermo_interface_m")
        )
        upper_mass_error = sim_upper_mass - cfast_room["upper_mass_kg"]
        lower_mass_error = sim_lower_mass - cfast_room["lower_mass_kg"]
        interface_error = sim_interface - cfast_room["interface_m"]
        upper_o2_error = _number(row.get("o2_upper")) - cfast_room[
            "upper_o2_fraction"
        ]
        lower_o2_error = _number(row.get("o2_lower")) - cfast_room[
            "lower_o2_fraction"
        ]
        geometry = plume_geometry(
            hrr_kw=_number(row.get("hrr_kw")),
            interface_m=sim_interface,
            room_height_m=room_height_m,
            fire_diameter_m=fire_diameter_m,
            convective_fraction=convective_fraction,
            confined_flame_enabled=confined_enabled,
            confined_z_eff_fraction=confined_fraction,
        )
        cfast_plume_kg = f33m.integrate_scalar(
            compartment_rows, checkpoint, "PLUM_1"
        )
        sim_plume_kg = owners["plume"]["upper_kg"]
        cfast_forward = cfast["routes"]["0->1"]["mass_kg"]
        cfast_reverse = cfast["routes"]["1->0"]["mass_kg"]
        doorway_gross = sum(
            owners[family]["gross_kg"]
            for family in ("interior_opening", "interior_pressure")
        )
        projection_net = sum(
            owners[family]["room_kg"] for family in PROJECTION_FAMILIES
        )
        expected_upper = _number(
            row.get("phase3_shadow_mass_residence_expected_upper_kg")
        )
        expected_lower = _number(
            row.get("phase3_shadow_mass_residence_expected_lower_kg")
        )
        ledger_residual = max(
            abs(expected_upper - sim_upper_mass),
            abs(expected_lower - sim_lower_mass),
            abs(
                _number(
                    row.get("phase3_shadow_mass_residence_room_residual_kg")
                )
            ),
        )
        snapshots[str(checkpoint)] = {
            "sim_upper_mass_kg": sim_upper_mass,
            "cfast_upper_mass_kg": cfast_room["upper_mass_kg"],
            "upper_mass_error_kg": upper_mass_error,
            "sim_lower_mass_kg": sim_lower_mass,
            "cfast_lower_mass_kg": cfast_room["lower_mass_kg"],
            "lower_mass_error_kg": lower_mass_error,
            "sim_interface_m": sim_interface,
            "cfast_interface_m": cfast_room["interface_m"],
            "interface_error_m": interface_error,
            "sim_upper_o2_fraction": _number(row.get("o2_upper")),
            "cfast_upper_o2_fraction": cfast_room["upper_o2_fraction"],
            "upper_o2_fraction_error": upper_o2_error,
            "sim_lower_o2_fraction": _number(row.get("o2_lower")),
            "cfast_lower_o2_fraction": cfast_room["lower_o2_fraction"],
            "lower_o2_fraction_error": lower_o2_error,
            "sim_upper_o2_inventory_proxy_kg": (
                sim_upper_mass * _number(row.get("o2_upper"))
            ),
            "cfast_upper_o2_kg": _number(cfast_mass_row.get("ULMO2_1")),
            "sim_lower_o2_inventory_proxy_kg": (
                sim_lower_mass * _number(row.get("o2_lower"))
            ),
            "cfast_lower_o2_kg": _number(cfast_mass_row.get("LLMO2_1")),
            "sim_hrr_kw": _number(row.get("hrr_kw")),
            "sim_accepted_hrr_kw": _number(
                row.get("phase3_shadow_combustion_accepted_hrr_kw")
            ),
            "cfast_hrr_kw": cfast_room["hrr_kw"],
            "canonical_o2_hrr_factor": _number(
                row.get("phase3_shadow_combustion_canonical_o2_hrr_factor")
            ),
            "requested_plume_rate_kg_s": _number(
                row.get("phase3_shadow_combustion_requested_plume_mass_kg")
            )
            / step_s,
            "accepted_plume_rate_kg_s": _number(
                row.get("phase3_shadow_combustion_accepted_plume_mass_kg")
            )
            / step_s,
            "cfast_plume_rate_kg_s": _number(
                cfast_compartment_row.get("PLUM_1")
            ),
            "sim_cumulative_plume_kg": sim_plume_kg,
            "cfast_cumulative_plume_kg": cfast_plume_kg,
            "plume_cumulative_shortfall_kg": cfast_plume_kg - sim_plume_kg,
            "cfast_door_forward_kg": cfast_forward,
            "cfast_door_reverse_kg": cfast_reverse,
            "doorway_gross_kg": doorway_gross,
            "projection_net_kg": projection_net,
            "mass_owners": owners,
            "mass_ledger_max_residual_kg": ledger_residual,
            "mass_ledger_pass": ledger_residual <= LEDGER_TOLERANCE_KG,
            "mass_or_interface_diverged": (
                exceeds_mass_threshold(
                    upper_mass_error, cfast_room["upper_mass_kg"]
                )
                or exceeds_mass_threshold(
                    lower_mass_error, cfast_room["lower_mass_kg"]
                )
                or abs(interface_error) > INTERFACE_THRESHOLD_M
            ),
            "o2_diverged": max(
                abs(upper_o2_error), abs(lower_o2_error)
            )
            > O2_FRACTION_THRESHOLD,
            "cfast_flame_height_m": _number(
                cfast_compartment_row.get("FLHGT_1")
            ),
            "cfast_flame_reaches_interface": _number(
                cfast_compartment_row.get("FLHGT_1")
            )
            >= cfast_room["interface_m"],
            **geometry,
        }
        snapshots[str(checkpoint)]["near_interface_pinch"] = (
            snapshots[str(checkpoint)]["z_eff_m"]
            <= NEAR_INTERFACE_Z_EFF_M
            and snapshots[str(checkpoint)]["branch"] == "far_field"
        )

    verdict = causal_verdict(snapshots)
    return {
        "candidate_csv": str(candidate_csv),
        "checkpoints": snapshots,
        "thresholds": {
            "mass_absolute_kg": MASS_ABS_THRESHOLD_KG,
            "mass_relative": MASS_REL_THRESHOLD,
            "interface_m": INTERFACE_THRESHOLD_M,
            "o2_fraction": O2_FRACTION_THRESHOLD,
            "near_interface_z_eff_m": NEAR_INTERFACE_Z_EFF_M,
        },
        "settings": {
            "step_s": step_s,
            "plume_fire_diameter_m": fire_diameter_m,
            "plume_mccaffrey_qc_fraction": convective_fraction,
            "plume_confined_flame_enabled": confined_enabled,
            "plume_confined_z_eff_fraction": confined_fraction,
        },
        "verdict": verdict,
    }


def _print_audit(audit: dict[str, Any]) -> None:
    print("F3.3s layer-mass/interface/O2 causal audit")
    print(
        "time  dMupper  dMlower  dZ    dO2u  "
        "SF/CFAST plume  z_eff  branch"
    )
    for checkpoint, snapshot in audit["checkpoints"].items():
        print(
            f"{checkpoint:>4} "
            f"{snapshot['upper_mass_error_kg']:>8.2f} "
            f"{snapshot['lower_mass_error_kg']:>8.2f} "
            f"{snapshot['interface_error_m']:>5.2f} "
            f"{snapshot['upper_o2_fraction_error']:>6.3f} "
            f"{snapshot['sim_cumulative_plume_kg']:>6.1f}/"
            f"{snapshot['cfast_cumulative_plume_kg']:<6.1f} "
            f"{snapshot['z_eff_m']:>5.2f} "
            f"{snapshot['branch']}"
        )
    verdict = audit["verdict"]
    print(f"\nprimary owner: {verdict['primary_owner']}")
    print(
        "first mass/interface divergence: "
        f"{verdict['first_mass_or_interface_divergence_s']} s"
    )
    print(f"first O2 divergence: {verdict['first_o2_divergence_s']} s")
    print(
        "first flame/interface crossing: "
        f"{verdict['first_flame_interface_crossing_s']} s"
    )
    print(
        "first near-interface pinch: "
        f"{verdict['first_near_interface_pinch_s']} s"
    )
    print(
        "first CFAST flame/interface crossing: "
        f"{verdict['first_cfast_flame_interface_crossing_s']} s"
    )
    print(f"next experiment: {verdict['next_experiment']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    run_dir = Path("runs/phase3_f33r2d/180_corridor_cfast")
    parser.add_argument(
        "--candidate-csv",
        type=Path,
        default=run_dir / "sim_log.csv",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=run_dir / "run_manifest.json",
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
        "--cfast-masses",
        type=Path,
        default=CFAST_DIR / "cfast_corridor_chain_masses.csv",
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)
    audit = build_audit(
        candidate_csv=args.candidate_csv,
        manifest_path=args.manifest,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
        cfast_masses_path=args.cfast_masses,
    )
    _print_audit(audit)
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return (
        0
        if audit["verdict"]["primary_owner"]
        == "plume_request_source_path"
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
