#!/usr/bin/env python3
"""Build the G3-1 fuel-ownership decision matrix (23 mismatches + 7 presets).

Static and read-only. Exact values come from ``audit_g3_fuel_sources``; the
creation path of preset rooms is *verified* by parsing the literal
``_make_room`` calls and ``fuel_objects`` blocks of ``BuildingTemplate.gd``.
Classification follows a written policy over provenance evidence only; no
fuel is inferred from a room name or type, and nothing is migrated.

    python scripts/simulation/build_g3_fuel_ownership_matrix.py          # print
    python scripts/simulation/build_g3_fuel_ownership_matrix.py --write  # docs
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation.audit_g3_fuel_sources import DEFAULT_SCENARIOS, audit_directory  # noqa: E402


TEMPLATE = ROOT / "sim/templates/BuildingTemplate.gd"
CASES_DIR = ROOT / "sim/validation/cases"
OUTPUT = ROOT / "docs/validation/G3_FUEL_OWNERSHIP_CLOSURE_MATRIX_2026-09-29.json"

REFERENCE_FILES = {
    "compact_apartment_reference.json",
    "long_hallway_reference.json",
    "two_storey_reference.json",
}
PRESET_TEMPLATE = {
    "preset_compact_apartment.json": ("compact_apartment", "create_compact_apartment"),
    "preset_piso_mediterraneo.json": ("piso_mediterraneo", "create_piso_mediterraneo"),
    "preset_ranch_family_house.json": ("ranch_family_house", "create_ranch_family_house"),
    "preset_row_house_ground_floor.json": ("row_house_ground_floor", "create_row_house_ground_floor"),
    "preset_three_bed_apartment.json": ("three_bed_apartment", "create_three_bed_apartment"),
    "preset_two_bed_apartment.json": ("two_bed_apartment", "create_two_bed_apartment"),
    "preset_uk_bungalow.json": ("uk_bungalow", "create_uk_bungalow"),
    "preset_two_storey_house.json": ("two_storey_house", "create_two_storey_house"),
}
# Only comments that state how a room load was derived; quoted, not trusted.
DERIVATION_NOTES = {
    "row_house_ground_floor": "BuildingTemplate comment: 'Cargas de combustible (EN 1991-1-2)' with "
        "per-area densities (salon 300, cocina 220, despacho 280, vestibulo 80 MJ/m2); "
        "densities not checked against the standard.",
    "uk_bungalow": "BuildingTemplate comment: carpet (+130 MJ/m2), wallpaper (+25 MJ/m2) and timber "
        "structure (+40 MJ/m2) versus masonry; no per-room computation or source is given.",
}

ENGINE_OWNER_MISMATCH = {
    "energy_cap": "room.fuel_energy_MJ (CombustionSystem._resolve_room_fuel_energy_MJ prefers a positive room value)",
    "hrr_cap": "room.max_hrr_kw (_resolve_room_max_hrr_kw prefers a positive room value)",
    "object_role": "explicit objects receive weighted shares of the room fire demand (_sync_explicit_objects_from_active_fire)",
    "species_yields": "weighted mean over explicit objects that still hold fuel, burning or not; "
        "engine fallback once every explicit object is exhausted",
    "after_objects_exhausted": "fire keeps consuming the room total with fallback yields: energy without an object owner",
    "room_proxy": "room_proxy_<id> mirrors the fire and is excluded from explicit sums",
}
ENGINE_OWNER_LUMPED = {
    "energy_cap": "room.fuel_energy_MJ",
    "hrr_cap": "room.max_hrr_kw",
    "object_role": "none: only the room_proxy_<id> created by ensure_room_fuel_objects",
    "species_yields": "engine fallback (context co_base_yield_kg_per_MJ, fire smoke yield)",
    "after_objects_exhausted": "not applicable",
    "room_proxy": "sole object; carries the aggregate",
}


def _function_body(source: str, name: str) -> str:
    start = source.index(f"func {name}(")
    following = re.search(r"\n(?:static )?func ", source[start + 1:])
    return source[start: start + 1 + following.start()] if following else source[start:]


def template_rooms(function: str, source: str | None = None) -> dict[int, dict]:
    """Literal room loads and object sums declared by one template function."""
    source = TEMPLATE.read_text(encoding="utf-8") if source is None else source
    body = _function_body(source, function)
    rooms: dict[int, dict] = {}
    pattern = r"_make_room\(\s*(\d+)\s*,\s*\"([^\"]*)\"\s*,[^,]+,[^,]+,[^,]+,\s*([\d.]+)\s*,\s*([\d.]+)\s*\)"
    for room_id, name, energy, power in re.findall(pattern, body):
        rooms[int(room_id)] = {
            "name": name, "fuel_energy_MJ": float(energy), "max_hrr_kw": float(power),
            "object_energy_MJ": 0.0, "object_count": 0,
        }
    for match in re.finditer(r"rooms_data\[(\d+)\]\[\"fuel_objects\"\]\s*=\s*\[", body):
        depth, index = 1, match.end()
        while depth:
            depth += {"[": 1, "]": -1}.get(body[index], 0)
            index += 1
        block = body[match.end(): index]
        energies = [float(v) for v in re.findall(r"\"fuel_energy_MJ\":\s*([\d.]+)", block)]
        room = rooms[int(match.group(1))]
        room["object_energy_MJ"] = sum(energies)
        room["object_count"] = len(energies)
    if not rooms:
        raise ValueError(f"{function}: no _make_room literals found")
    return rooms


def validation_cases_by_template() -> dict[str, list[str]]:
    found: dict[str, list[str]] = {}
    for path in sorted(CASES_DIR.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        found.setdefault(str(data.get("template", "")), []).append(path.name)
    return found


def build() -> dict:
    inventory = audit_directory(DEFAULT_SCENARIOS)
    source = TEMPLATE.read_text(encoding="utf-8")
    cases = validation_cases_by_template()
    mismatches, presets = [], []
    for scenario in inventory["scenarios"]:
        name = scenario["file"]
        template = PRESET_TEMPLATE.get(name)
        literal = template_rooms(template[1], source) if template else None
        if literal is not None:
            for room in scenario["rooms"]:
                expected = literal[room["room_id"]]
                if (expected["fuel_energy_MJ"], expected["max_hrr_kw"], expected["object_energy_MJ"]) != (
                        room["declared_room_energy_MJ"], room["declared_room_max_hrr_kw"], room["object_energy_MJ"]):
                    raise ValueError(f"{name} room {room['room_id']} does not match {template[1]}")
        for room in scenario["rooms"]:
            if room["shape"] != "both_mismatch_unclassified":
                continue
            if name in REFERENCE_FILES:
                path = "literal rooms_data in the distributed JSON; added in b3457e94 (2026-06-02), no later change, no generator found"
                references = []
            else:
                path = (f"BuildingTemplate.{template[1]}() -> create_product_preset -> "
                        "tools/export_presets_to_scenarios.gd (7f1a609f, 2026-07-21); "
                        "room loads and objects first appear together in 12d31cfb (2026-05-17)")
                references = cases.get(template[0], [])
            mismatches.append({
                "case_id": f"{name}#room{room['room_id']}",
                "file": name,
                "scenario_sha256": scenario["sha256"],
                "room_id": room["room_id"],
                "room_name": room["room_name"],
                "creation_path": path,
                "template_literal_verified": literal is not None,
                "room_energy_MJ": room["declared_room_energy_MJ"],
                "room_max_hrr_kw": room["declared_room_max_hrr_kw"],
                "object_energy_MJ": room["object_energy_MJ"],
                "object_max_hrr_kw": room["object_max_hrr_kw"],
                "energy_difference_MJ": room["energy_difference_MJ"],
                "power_difference_kw": room["power_difference_kw"],
                "objects": [{"id": o["id"], "fuel_energy_MJ": o["fuel_energy_MJ"],
                             "max_hrr_kw": o["max_hrr_kw"]} for o in room["objects"]],
                "engine_owner": ENGINE_OWNER_MISMATCH,
                "represented_fuel": "not declared: no field or comment says whether the room total "
                    "includes the drawn objects, undrawn contents, finishes or a prescribed limit",
                "evidence": "values located; meaning of the difference undocumented",
                "classification": "legacy_unknown",
                "decision": "bloquear_procedencia_desconocida",
                "validation_cases_using_template": references,
            })
        if name in PRESET_TEMPLATE and name != "preset_two_storey_house.json":
            rooms = scenario["rooms"]
            if any(room["object_count"] for room in rooms):
                raise ValueError(f"{name}: preset unexpectedly has objects")
            presets.append({
                "case_id": name,
                "file": name,
                "scenario_sha256": scenario["sha256"],
                "creation_path": (f"BuildingTemplate.{template[1]}() via _make_room -> create_product_preset -> "
                                  "tools/export_presets_to_scenarios.gd (7f1a609f, 2026-07-21)"),
                "template_literal_verified": True,
                "rooms": [{"room_id": r["room_id"], "room_name": r["room_name"],
                           "room_energy_MJ": r["declared_room_energy_MJ"],
                           "room_max_hrr_kw": r["declared_room_max_hrr_kw"]} for r in rooms],
                "total_room_energy_MJ": sum(r["declared_room_energy_MJ"] for r in rooms),
                "engine_owner": ENGINE_OWNER_LUMPED,
                "represented_fuel": "aggregate room load; materials and items not declared",
                "evidence": DERIVATION_NOTES.get(template[0], "no derivation, source or comment for the loads"),
                "classification": "legacy_lumped",
                "decision": "mantener_agregado_explicito",
                "validation_cases_using_template": cases.get(template[0], []),
            })
    if len(mismatches) != 23 or len(presets) != 7:
        raise ValueError(f"expected 23 mismatches and 7 presets, got {len(mismatches)} and {len(presets)}")
    return {
        "schema": "g3_fuel_ownership_closure_matrix_v1",
        "status": "diagnostic_no_scenario_or_engine_change",
        "classification_values": ["explicit_objects", "legacy_lumped", "legacy_unknown"],
        "decision_values": ["migrable", "mantener_agregado_explicito", "bloquear_procedencia_desconocida"],
        "policy": {
            "explicit_objects": "only if a recorded source states the objects are the complete inventory",
            "legacy_lumped": "the room aggregate is the only declared fuel: one owner, materials unknown",
            "legacy_unknown": "room total and objects both positive and different, with no recorded meaning",
            "no_name_inference": True,
        },
        "mismatches": mismatches,
        "presets_without_objects": presets,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    text = json.dumps(build(), ensure_ascii=False, indent=2) + "\n"
    if args.write:
        OUTPUT.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
