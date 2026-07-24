#!/usr/bin/env python3
"""Build the Phase 3 F3.3m R0-Hall source-correspondence audit.

The script compares opt-in SimuFire connection-residence checkpoints with the
committed CFAST zone/slab exports. It is diagnostic only: it reads run
artifacts and never changes simulation state or validation baselines.

Example:
  python scripts/simulation/analyze_phase3_f33m_source_correspondence.py \
    --runs-root runs --json-out runs/phase3_f33m_correspondence.json
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any, Iterable


CHECKPOINTS = (60, 120, 180, 300, 600)
AMBIENT_C = 20.0
AIR_CP_KJ_KG_K = 1.0
CFAST_ROOM_VOLUMES_M3 = {0: 48.0, 1: 25.2, 2: 25.2}

CONNECTIONS = {
    "r0_hall": {
        "opening_id": 0,
        "cfast_vent": 1,
        "forward": (0, 1),
        "reverse": (1, 0),
    },
    "hall_r2": {
        "opening_id": 2,
        "cfast_vent": 2,
        "forward": (1, 2),
        "reverse": (2, 1),
    },
}

ENTHALPY_RESIDENCE_FAMILIES = (
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
    "other",
)


def _number(value: Any, default: float = 0.0) -> float:
    if value in (None, ""):
        return default
    return float(value)


def _read_csv_rows(
    path: Path, *, header_line: int, data_line: int
) -> list[dict[str, str]]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    header = next(csv.reader([lines[header_line]]))
    rows: list[dict[str, str]] = []
    for values in csv.reader(lines[data_line:]):
        if not values or not values[0].strip():
            continue
        rows.append(dict(zip(header, values)))
    return rows


def read_cfast_zone(path: Path) -> list[dict[str, str]]:
    return _read_csv_rows(path, header_line=1, data_line=2)


def read_cfast_compartments(path: Path) -> list[dict[str, str]]:
    return _read_csv_rows(path, header_line=0, data_line=4)


def _row_at(rows: Iterable[dict[str, str]], checkpoint_s: float) -> dict[str, str]:
    candidates = list(rows)
    if not candidates:
        raise ValueError("empty time series")
    return min(candidates, key=lambda row: abs(_number(row["Time"]) - checkpoint_s))


def _sim_row_at(
    rows: Iterable[dict[str, str]], room_id: int, checkpoint_s: float
) -> dict[str, str]:
    candidates = [
        row for row in rows if int(_number(row.get("room_id"))) == room_id
    ]
    if not candidates:
        raise ValueError(f"room {room_id} is absent from SimuFire CSV")
    return min(
        candidates,
        key=lambda row: abs(_number(row["time_s"]) - checkpoint_s),
    )


def cfast_tanhsmooth_upper_fraction(
    source_temp_c: float,
    destination_upper_temp_c: float,
    destination_lower_temp_c: float,
) -> float:
    """Mirror Phase3ZoneMassSystem.preview_cfast_buoyancy_destination_split."""
    effective_lower = min(destination_lower_temp_c, destination_upper_temp_c)
    xmax = destination_upper_temp_c + 1.0
    xmin = effective_lower - 1.0
    if xmax <= xmin:
        return 1.0 if source_temp_c >= xmax else 0.0
    value = 0.5 + 0.5025 * math.tanh(
        6.0 / (xmax - xmin) * (source_temp_c - xmin) - 3.0
    )
    return min(1.0, max(0.0, value))


def _cfast_endpoint_rate(
    row: dict[str, str],
    *,
    vent: int,
    slab: int,
    sign: int,
    destination_compartment: int,
) -> dict[str, float]:
    signed_flow = _number(row.get(f"HSLABF_{vent}_{slab}"))
    mass_rate = max(0.0, signed_flow if sign > 0 else -signed_flow)
    source_temp_c = _number(row.get(f"HSLABT_{vent}_{slab}")) - 273.15
    destination_upper = _number(row.get(f"ULT_{destination_compartment}"))
    destination_lower = _number(row.get(f"LLT_{destination_compartment}"))
    upper_fraction = cfast_tanhsmooth_upper_fraction(
        source_temp_c, destination_upper, destination_lower
    )
    return {
        "mass": mass_rate,
        "enthalpy": mass_rate
        * AIR_CP_KJ_KG_K
        * (source_temp_c - AMBIENT_C),
        "destination_upper": mass_rate * upper_fraction,
    }


def integrate_cfast_connection(
    rows: list[dict[str, str]],
    *,
    checkpoint_s: float,
    vent: int,
    sign: int,
    destination_compartment: int,
) -> dict[str, float]:
    """Trapezoid-integrate one signed CFAST vent direction."""
    mass = 0.0
    enthalpy = 0.0
    destination_upper = 0.0
    ordered = sorted(rows, key=lambda row: _number(row["Time"]))
    for previous, current in zip(ordered, ordered[1:]):
        t0 = _number(previous["Time"])
        t1 = _number(current["Time"])
        if t0 >= checkpoint_s:
            break
        if t1 > checkpoint_s:
            raise ValueError(
                f"checkpoint {checkpoint_s:g}s is not present in CFAST export"
            )
        dt = t1 - t0
        for slab in range(1, 11):
            a = _cfast_endpoint_rate(
                previous,
                vent=vent,
                slab=slab,
                sign=sign,
                destination_compartment=destination_compartment,
            )
            b = _cfast_endpoint_rate(
                current,
                vent=vent,
                slab=slab,
                sign=sign,
                destination_compartment=destination_compartment,
            )
            mass += 0.5 * (a["mass"] + b["mass"]) * dt
            enthalpy += 0.5 * (a["enthalpy"] + b["enthalpy"]) * dt
            destination_upper += (
                0.5
                * (a["destination_upper"] + b["destination_upper"])
                * dt
            )
    destination_lower = mass - destination_upper
    return {
        "mass_kg": mass,
        "enthalpy_kj": enthalpy,
        "source_temp_c": (
            AMBIENT_C + enthalpy / (mass * AIR_CP_KJ_KG_K)
            if mass > 0.0
            else AMBIENT_C
        ),
        "destination_upper_kg": destination_upper,
        "destination_lower_kg": destination_lower,
        "destination_upper_fraction": (
            destination_upper / mass if mass > 0.0 else 0.0
        ),
    }


def integrate_scalar(
    rows: list[dict[str, str]], checkpoint_s: float, column: str
) -> float:
    total = 0.0
    ordered = sorted(rows, key=lambda row: _number(row["Time"]))
    for previous, current in zip(ordered, ordered[1:]):
        t0 = _number(previous["Time"])
        t1 = _number(current["Time"])
        if t0 >= checkpoint_s:
            break
        if t1 > checkpoint_s:
            raise ValueError(
                f"checkpoint {checkpoint_s:g}s is not present in CFAST export"
            )
        total += (
            0.5
            * (_number(previous[column]) + _number(current[column]))
            * (t1 - t0)
        )
    return total


def aggregate_sim_connection(
    records: list[dict[str, Any]],
    *,
    opening_id: int,
    source_room_id: int,
    destination_room_id: int,
) -> dict[str, Any]:
    selected = [
        record
        for record in records
        if int(record.get("opening_id", -1)) == opening_id
        and int(record.get("source_room_id", -1)) == source_room_id
        and int(record.get("destination_room_id", -1)) == destination_room_id
    ]
    families: dict[str, float] = {}
    totals = {
        "mass_kg": 0.0,
        "enthalpy_kj": 0.0,
        "source_upper_kg": 0.0,
        "source_lower_kg": 0.0,
        "destination_upper_kg": 0.0,
        "destination_lower_kg": 0.0,
        "route_count": 0,
    }
    for record in selected:
        mass = _number(record.get("accepted_mass_kg"))
        family = str(record.get("family", "unknown"))
        families[family] = families.get(family, 0.0) + mass
        totals["mass_kg"] += mass
        totals["enthalpy_kj"] += _number(record.get("accepted_enthalpy_kj"))
        totals["source_upper_kg"] += _number(
            record.get("source_upper_mass_kg")
        )
        totals["source_lower_kg"] += _number(
            record.get("source_lower_mass_kg")
        )
        totals["destination_upper_kg"] += _number(
            record.get("destination_upper_mass_kg")
        )
        totals["destination_lower_kg"] += _number(
            record.get("destination_lower_mass_kg")
        )
        totals["route_count"] += int(record.get("accepted_route_count", 0))
    mass = totals["mass_kg"]
    totals["source_temp_c"] = (
        AMBIENT_C + totals["enthalpy_kj"] / (mass * AIR_CP_KJ_KG_K)
        if mass > 0.0
        else AMBIENT_C
    )
    totals["source_upper_fraction"] = (
        totals["source_upper_kg"] / mass if mass > 0.0 else 0.0
    )
    totals["destination_upper_fraction"] = (
        totals["destination_upper_kg"] / mass if mass > 0.0 else 0.0
    )
    totals["families_kg"] = families
    return totals


def _canonical_temp(mass_kg: float, energy_kj: float) -> float:
    if mass_kg <= 0.0:
        return AMBIENT_C
    return AMBIENT_C + energy_kj / (mass_kg * AIR_CP_KJ_KG_K)


def _sim_enthalpy_residence(room: dict[str, str]) -> dict[str, float]:
    result: dict[str, float] = {}
    for family in ENTHALPY_RESIDENCE_FAMILIES:
        prefix = f"phase3_shadow_enthalpy_{family}_"
        incoming = _number(room.get(prefix + "upper_in_kj_total")) + _number(
            room.get(prefix + "lower_in_kj_total")
        )
        outgoing = _number(
            room.get(prefix + "upper_out_kj_total")
        ) + _number(room.get(prefix + "lower_out_kj_total"))
        result[family] = incoming - outgoing
    result["observed"] = _number(
        room.get("phase3_shadow_enthalpy_observed_upper_kj")
    ) + _number(room.get("phase3_shadow_enthalpy_observed_lower_kj"))
    return result


def build_cfast_checkpoint(
    checkpoint_s: int,
    zone_rows: list[dict[str, str]],
    compartment_rows: list[dict[str, str]],
) -> dict[str, Any]:
    zone = _row_at(zone_rows, checkpoint_s)
    compartment = _row_at(compartment_rows, checkpoint_s)
    routes: dict[str, Any] = {}
    for name, spec in CONNECTIONS.items():
        vent = int(spec["cfast_vent"])
        forward = spec["forward"]
        reverse = spec["reverse"]
        routes[f"{forward[0]}->{forward[1]}"] = integrate_cfast_connection(
            zone_rows,
            checkpoint_s=checkpoint_s,
            vent=vent,
            sign=1,
            destination_compartment=forward[1] + 1,
        )
        routes[f"{reverse[0]}->{reverse[1]}"] = integrate_cfast_connection(
            zone_rows,
            checkpoint_s=checkpoint_s,
            vent=vent,
            sign=-1,
            destination_compartment=reverse[1] + 1,
        )

    room_states: dict[str, Any] = {}
    for room_id in (0, 1, 2):
        compartment_index = room_id + 1
        upper_volume = _number(compartment[f"VOL_{compartment_index}"])
        upper_mass = (
            _number(zone[f"RHOU_{compartment_index}"]) * upper_volume
        )
        lower_mass = _number(zone[f"RHOL_{compartment_index}"]) * (
            CFAST_ROOM_VOLUMES_M3[room_id] - upper_volume
        )
        room_states[str(room_id)] = {
            "upper_temp_c": _number(
                compartment[f"ULT_{compartment_index}"]
            ),
            "lower_temp_c": _number(
                compartment[f"LLT_{compartment_index}"]
            ),
            "interface_m": _number(
                compartment[f"HGT_{compartment_index}"]
            ),
            "upper_mass_kg": upper_mass,
            "lower_mass_kg": lower_mass,
            "upper_o2_fraction": _number(
                compartment[f"ULO2_{compartment_index}"]
            )
            / 100.0,
            "lower_o2_fraction": _number(
                compartment[f"LLO2_{compartment_index}"]
            )
            / 100.0,
            "sensible_energy_kj": (
                upper_mass
                * AIR_CP_KJ_KG_K
                * (_number(compartment[f"ULT_{compartment_index}"]) - AMBIENT_C)
                + lower_mass
                * AIR_CP_KJ_KG_K
                * (
                    _number(compartment[f"LLT_{compartment_index}"])
                    - AMBIENT_C
                )
            ),
        }
    room_states["0"].update(
        {
            "hrr_kw": _number(compartment["HRR_1"]) / 1000.0,
            "hrr_energy_kj": integrate_scalar(
                compartment_rows, checkpoint_s, "HRR_1"
            )
            / 1000.0,
            "convective_energy_kj": integrate_scalar(
                compartment_rows, checkpoint_s, "HRRC_1"
            )
            / 1000.0,
        }
    )
    return {
        "checkpoint_s": checkpoint_s,
        "rooms": room_states,
        "r0": room_states["0"],
        "routes": routes,
    }


def build_sim_checkpoint(checkpoint_s: int, run_dir: Path) -> dict[str, Any]:
    summary = json.loads((run_dir / "summary.json").read_text(encoding="utf-8"))
    with (run_dir / "sim_log.csv").open(
        newline="", encoding="utf-8-sig"
    ) as handle:
        rows = list(csv.DictReader(handle))
    records = summary.get("phase3_connection_residence", [])
    routes: dict[str, Any] = {}
    for spec in CONNECTIONS.values():
        opening_id = int(spec["opening_id"])
        for direction_name in ("forward", "reverse"):
            source, destination = spec[direction_name]
            routes[f"{source}->{destination}"] = aggregate_sim_connection(
                records,
                opening_id=opening_id,
                source_room_id=source,
                destination_room_id=destination,
            )

    room_states: dict[str, Any] = {}
    for room_id in (0, 1, 2):
        room = _sim_row_at(rows, room_id, checkpoint_s)
        shadow_upper_mass = _number(
            room.get("phase3_shadow_upper_gas_kg")
        )
        shadow_upper_energy = _number(
            room.get("phase3_shadow_upper_energy_kj")
        )
        room_states[str(room_id)] = {
            "legacy_upper_temp_c": _number(room.get("temp_upper_c")),
            "legacy_lower_temp_c": _number(room.get("temp_lower_c")),
            "legacy_interface_m": _number(room.get("thermal_layer_m")),
            "legacy_upper_mass_kg": _number(room.get("upper_gas_kg")),
            "legacy_lower_mass_kg": _number(room.get("lower_gas_kg")),
            "shadow_upper_temp_c": _canonical_temp(
                shadow_upper_mass, shadow_upper_energy
            ),
            "shadow_lower_temp_c": _canonical_temp(
                _number(room.get("phase3_shadow_lower_gas_kg")),
                _number(room.get("phase3_shadow_lower_energy_kj")),
            ),
            "shadow_upper_mass_kg": shadow_upper_mass,
            "shadow_lower_mass_kg": _number(
                room.get("phase3_shadow_lower_gas_kg")
            ),
            "sensible_energy_kj": shadow_upper_energy
            + _number(room.get("phase3_shadow_lower_energy_kj")),
            "upper_o2_fraction": _number(room.get("o2_upper")),
            "lower_o2_fraction": _number(room.get("o2_lower")),
        }
    room = _sim_row_at(rows, 0, checkpoint_s)
    room_states["0"].update(
        {
            "hrr_kw": _number(room.get("hrr_kw")),
            "hrr_target_kw": _number(room.get("flame_hrr_target_kw")),
            "o2_hrr_factor": _number(room.get("o2_hrr_factor"), 1.0),
            "canonical_o2_ref": _number(
                room.get("phase3_shadow_combustion_canonical_o2_ref")
            ),
            "canonical_o2_hrr_factor": _number(
                room.get("phase3_shadow_combustion_canonical_o2_hrr_factor"),
                1.0,
            ),
            "canonical_accepted_hrr_kw": _number(
                room.get("phase3_shadow_combustion_accepted_hrr_kw")
            ),
            "hrr_energy_kj": _number(room.get("hrr_kj_total")),
            "enthalpy_residence_kj": _sim_enthalpy_residence(room),
        }
    )
    room_states["0"]["convective_energy_kj"] = room_states["0"][
        "enthalpy_residence_kj"
    ]["combustion"]
    return {
        "checkpoint_s": checkpoint_s,
        "run_dir": str(run_dir),
        "rooms": room_states,
        "r0": room_states["0"],
        "routes": routes,
    }


def _route_delta(current: dict[str, Any], previous: dict[str, Any]) -> dict[str, Any]:
    numeric = (
        "mass_kg",
        "enthalpy_kj",
        "source_upper_kg",
        "source_lower_kg",
        "destination_upper_kg",
        "destination_lower_kg",
    )
    result = {
        key: _number(current.get(key)) - _number(previous.get(key))
        for key in numeric
    }
    mass = result["mass_kg"]
    result["source_temp_c"] = (
        AMBIENT_C + result["enthalpy_kj"] / mass if mass > 0.0 else AMBIENT_C
    )
    result["source_upper_fraction"] = (
        result["source_upper_kg"] / mass if mass > 0.0 else 0.0
    )
    result["destination_upper_fraction"] = (
        result["destination_upper_kg"] / mass if mass > 0.0 else 0.0
    )
    current_families = current.get("families_kg", {})
    previous_families = previous.get("families_kg", {})
    result["families_kg"] = {
        family: _number(current_families.get(family))
        - _number(previous_families.get(family))
        for family in set(current_families) | set(previous_families)
    }
    return result


def add_windows(checkpoints: list[dict[str, Any]]) -> list[dict[str, Any]]:
    windows: list[dict[str, Any]] = []
    previous: dict[str, Any] | None = None
    for current in checkpoints:
        start_s = 0 if previous is None else previous["checkpoint_s"]
        window = {
            "start_s": start_s,
            "end_s": current["checkpoint_s"],
            "sim_routes": {},
            "cfast_routes": {},
            "sim_r0_enthalpy_residence_kj": {},
            "fire_energy_kj": {},
        }
        for route_name, route in current["sim"]["routes"].items():
            baseline = (
                {}
                if previous is None
                else previous["sim"]["routes"][route_name]
            )
            window["sim_routes"][route_name] = _route_delta(route, baseline)
        for route_name, route in current["cfast"]["routes"].items():
            baseline = (
                {}
                if previous is None
                else previous["cfast"]["routes"][route_name]
            )
            window["cfast_routes"][route_name] = _route_delta(route, baseline)
        current_residence = (
            current["sim"]
            .get("r0", {})
            .get("enthalpy_residence_kj", {})
        )
        previous_residence = (
            {}
            if previous is None
            else (
                previous["sim"]
                .get("r0", {})
                .get("enthalpy_residence_kj", {})
            )
        )
        window["sim_r0_enthalpy_residence_kj"] = {
            family: _number(current_residence.get(family))
            - _number(previous_residence.get(family))
            for family in current_residence
        }
        current_sim_r0 = current["sim"].get("r0", {})
        current_cfast_r0 = current["cfast"].get("r0", {})
        previous_sim_r0 = (
            {} if previous is None else previous["sim"].get("r0", {})
        )
        previous_cfast_r0 = (
            {} if previous is None else previous["cfast"].get("r0", {})
        )
        window["fire_energy_kj"] = {
            "sim_total": _number(current_sim_r0.get("hrr_energy_kj"))
            - _number(previous_sim_r0.get("hrr_energy_kj")),
            "cfast_total": _number(current_cfast_r0.get("hrr_energy_kj"))
            - _number(previous_cfast_r0.get("hrr_energy_kj")),
            "sim_convective": _number(
                current_sim_r0.get("convective_energy_kj")
            )
            - _number(previous_sim_r0.get("convective_energy_kj")),
            "cfast_convective": _number(
                current_cfast_r0.get("convective_energy_kj")
            )
            - _number(previous_cfast_r0.get("convective_energy_kj")),
        }
        windows.append(window)
        previous = current
    return windows


def build_audit(
    *,
    runs_root: Path,
    cfast_zone_path: Path,
    cfast_compartments_path: Path,
    checkpoints: Iterable[int] = CHECKPOINTS,
) -> dict[str, Any]:
    zone_rows = read_cfast_zone(cfast_zone_path)
    compartment_rows = read_cfast_compartments(cfast_compartments_path)
    results: list[dict[str, Any]] = []
    for checkpoint in checkpoints:
        run_dir = runs_root / f"phase3_f33m_{checkpoint}"
        if checkpoint == 180 and not run_dir.exists():
            run_dir = runs_root / "phase3_f33l_connection_proof"
        results.append(
            {
                "checkpoint_s": checkpoint,
                "sim": build_sim_checkpoint(checkpoint, run_dir),
                "cfast": build_cfast_checkpoint(
                    checkpoint, zone_rows, compartment_rows
                ),
            }
        )
    return {
        "checkpoints": results,
        "windows": add_windows(results),
        "conventions": {
            "enthalpy_reference_c": AMBIENT_C,
            "air_cp_kj_kg_k": AIR_CP_KJ_KG_K,
            "cfast_positive_vent_direction": {
                "1": "0->1",
                "2": "1->2",
            },
        },
    }


def _print_summary(audit: dict[str, Any]) -> None:
    print("F3.3m R0-Hall source correspondence")
    print(
        "time  SF/CFAST upper mass  SF/CFAST upper temp  "
        "R0->Hall mass  R0->Hall enthalpy  HRR SF/CFAST"
    )
    for checkpoint in audit["checkpoints"]:
        sim = checkpoint["sim"]
        cfast = checkpoint["cfast"]
        sim_route = sim["routes"]["0->1"]
        cfast_route = cfast["routes"]["0->1"]
        print(
            f"{checkpoint['checkpoint_s']:>4}s "
            f"{sim['r0']['shadow_upper_mass_kg']:7.2f}/"
            f"{cfast['r0']['upper_mass_kg']:7.2f} kg  "
            f"{sim['r0']['shadow_upper_temp_c']:7.2f}/"
            f"{cfast['r0']['upper_temp_c']:7.2f} C  "
            f"{sim_route['mass_kg']:7.2f}/{cfast_route['mass_kg']:7.2f} kg  "
            f"{sim_route['enthalpy_kj']:8.1f}/"
            f"{cfast_route['enthalpy_kj']:8.1f} kJ  "
            f"{sim['r0']['hrr_kw']:6.1f}/{cfast['r0']['hrr_kw']:6.1f} kW"
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs-root", type=Path, default=Path("runs"))
    parser.add_argument(
        "--cfast-zone",
        type=Path,
        default=Path(
            "sim/validation/cfast/cfast_corridor_chain_zone.csv"
        ),
    )
    parser.add_argument(
        "--cfast-compartments",
        type=Path,
        default=Path(
            "sim/validation/cfast/cfast_corridor_chain_compartments.csv"
        ),
    )
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args(argv)

    audit = build_audit(
        runs_root=args.runs_root,
        cfast_zone_path=args.cfast_zone,
        cfast_compartments_path=args.cfast_compartments,
    )
    _print_summary(audit)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"json={args.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
