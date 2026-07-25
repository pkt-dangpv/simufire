"""Prepare scratch-only F3.3r2c correspondence cases.

The generated cases keep official validation inputs untouched. They apply the
already documented CFAST source pair and explicit enclosure topology needed by
the default-OFF canonical multi-surface shadow.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CASE_DIR = ROOT / "sim" / "validation" / "cases"
DEFAULT_OUT = ROOT / "runs" / "phase3_f33r2c" / "cases"

CONCRETE = {
    "wall_k_kw_m_k": 0.00175,
    "wall_rho_kg_m3": 2200.0,
    "wall_cp_kj_kg_k": 1.0,
    "wall_thickness_m": 0.15,
}

PHYSICAL_WALL_FRACTIONS = {
    0: (0.5, 0.5),
    1: (3.0 / 17.0, 14.0 / 17.0),
    2: (0.5, 0.5),
    3: (2.0 / 11.0, 9.0 / 11.0),
    4: (0.5, 0.5),
    5: (0.5, 0.5),
}


def _surface(exterior: float, inter_room: float, adiabatic: float) -> dict[str, float]:
    return {
        "exterior_fraction": exterior,
        "inter_room_fraction": inter_room,
        "adiabatic_fraction": adiabatic,
    }


def _topology(kind: str, room_id: int) -> dict[str, dict[str, float]]:
    if kind == "cfast":
        # CFAST compartments own independent concrete ceiling, wall and floor
        # slabs whose remote boundary is ambient.
        if room_id in (0, 1, 2):
            boundary = _surface(1.0, 0.0, 0.0)
        else:
            boundary = _surface(0.0, 0.0, 1.0)
        return {
            name: copy.deepcopy(boundary)
            for name in ("ceiling", "upper_wall", "lower_wall", "floor")
        }
    if kind == "physical":
        wall_exterior, wall_inter = PHYSICAL_WALL_FRACTIONS[room_id]
        return {
            "ceiling": _surface(1.0, 0.0, 0.0),
            "upper_wall": _surface(wall_exterior, wall_inter, 0.0),
            "lower_wall": _surface(wall_exterior, wall_inter, 0.0),
            "floor": _surface(1.0, 0.0, 0.0),
        }
    if kind == "sealed_fixture":
        if room_id == 0:
            boundary = _surface(1.0, 0.0, 0.0)
        else:
            boundary = _surface(0.0, 0.0, 1.0)
        return {
            name: copy.deepcopy(boundary)
            for name in ("ceiling", "upper_wall", "lower_wall", "floor")
        }
    raise ValueError(f"unknown topology kind: {kind}")


def _load_case(name: str) -> dict[str, Any]:
    return json.loads((CASE_DIR / name).read_text(encoding="utf-8-sig"))


def _merge_room_overrides(
    case: dict[str, Any], topology_kind: str
) -> None:
    overrides = {
        int(entry["id"]): copy.deepcopy(entry)
        for entry in case.get("room_overrides", [])
    }
    for room_id in range(6):
        room = overrides.setdefault(room_id, {"id": room_id})
        room.update(CONCRETE)
        room["phase3_surface_boundaries"] = _topology(topology_kind, room_id)
    case["room_overrides"] = [overrides[room_id] for room_id in sorted(overrides)]


def _apply_common_shadow_inputs(case: dict[str, Any], enabled: bool) -> None:
    case["duration_s"] = 180.0
    engine = case.setdefault("engine_overrides", {})
    engine.update(
        {
            "log_interval_s": 10.0,
            "hrr_chi_rad_normal": 0.35,
            "hrr_chi_rad_low_o2": 0.35,
            "plume_fire_diameter_m": 0.6196,
            "phase3_canonical_multisurface_shadow_enabled": enabled,
        }
    )
    engine.pop("log_file_path", None)
    engine.pop("csv_log_file_path", None)


def build_cases() -> dict[str, dict[str, Any]]:
    corridor_base = _load_case("cfast_corridor_chain.json")

    corridor_off = copy.deepcopy(corridor_base)
    _apply_common_shadow_inputs(corridor_off, False)
    _merge_room_overrides(corridor_off, "cfast")

    corridor_cfast = copy.deepcopy(corridor_base)
    _apply_common_shadow_inputs(corridor_cfast, True)
    _merge_room_overrides(corridor_cfast, "cfast")

    corridor_physical = copy.deepcopy(corridor_base)
    _apply_common_shadow_inputs(corridor_physical, True)
    _merge_room_overrides(corridor_physical, "physical")

    corridor_closed = copy.deepcopy(corridor_cfast)
    for opening in corridor_closed.get("opening_overrides", []):
        if int(opening.get("b", -1)) >= 0:
            opening["open_fraction"] = 0.0

    sealed = _load_case("cfast_r0_window_360.json")
    sealed["opening_events"] = []
    _apply_common_shadow_inputs(sealed, True)
    _merge_room_overrides(sealed, "sealed_fixture")

    return {
        "corridor_off.json": corridor_off,
        "corridor_cfast_boundary.json": corridor_cfast,
        "corridor_physical_boundary.json": corridor_physical,
        "corridor_no_opening.json": corridor_closed,
        "sealed_material_fixture.json": sealed,
    }


def write_cases(out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for name, payload in build_cases().items():
        path = out_dir / name
        path.write_text(
            json.dumps(payload, indent=2, ensure_ascii=True) + "\n",
            encoding="utf-8",
        )
        written.append(path)
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    for path in write_cases(args.out_dir.resolve()):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
