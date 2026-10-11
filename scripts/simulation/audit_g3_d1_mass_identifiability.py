"""Audit declared object mass inputs, not runtime physics or data eligibility.

Print deterministic JSON to stdout. No files are written, no Godot is launched,
and template-expanded objects are deliberately excluded. Field presence is not
evidence of a measurement, valid units, or a supported loader contract.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FIELDS = (
    "fuel_energy_MJ", "heat_of_gasification_kj_kg",
    "heat_of_combustion_kj_kg", "alpha_kw_s2", "hrr_curve",
    "char_growth_rate_m_per_kg", "co_yield_kg_per_MJ",
    "initial_fuel_mass_kg", "remaining_fuel_mass_kg", "char_mass_kg",
    "mass_loss_curve", "elemental_composition", "heat_of_combustion_basis",
)
CODE_FILES = (
    "sim/fire/FuelObjectModel.gd", "sim/fire/CombustionSystem.gd",
    "sim/BuildingModel.gd", "sim/core/SimulationStateBuilder.gd",
    "sim/core/Phase3ZoneMassSystem.gd",
)


def declarations(value: object, pointer: str = ""):
    """Yield each explicit fuel_objects entry once, including room_overrides."""
    if isinstance(value, dict):
        for key, child in sorted(value.items()):
            escaped = key.replace("~", "~0").replace("/", "~1")
            location = f"{pointer}/{escaped}"
            if key == "fuel_objects":
                if not isinstance(child, list):
                    raise ValueError(f"{location}: expected a list")
                for index, item in enumerate(child):
                    if not isinstance(item, dict):
                        raise ValueError(f"{location}/{index}: expected an object")
                    yield f"{location}/{index}", item
            else:
                yield from declarations(child, location)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from declarations(child, f"{pointer}/{index}")


def audit_paths(paths: list[Path], root: Path) -> dict:
    files = []
    totals = dict.fromkeys(FIELDS, 0)
    for path in sorted(paths):
        raw = path.read_bytes()
        objects = []
        for pointer, obj in declarations(json.loads(raw)):
            present = [field for field in FIELDS if field in obj]
            for field in present:
                totals[field] += 1
            objects.append({
                "pointer": pointer, "id": obj.get("id"),
                "declared_fields": present,
                "heat_of_combustion_kj_kg": obj.get("heat_of_combustion_kj_kg"),
            })
        files.append({
            "file": path.relative_to(root).as_posix(),
            "sha256_raw": hashlib.sha256(raw).hexdigest(),
            "objects": objects,
        })
    return {
        "json_file_count": len(files),
        "files_with_objects": sum(bool(item["objects"]) for item in files),
        "declared_object_count": sum(len(item["objects"]) for item in files),
        "field_presence_counts": totals,
        "files": files,
    }


def audit_repository(root: Path) -> dict:
    return {
        "schema": "g3_d1_declared_mass_inputs_v1",
        "scope": "declared JSON only; no template expansion; presence is not validity",
        "scopes": {
            folder: audit_paths(list((root / folder).glob("*.json")), root)
            for folder in ("scenarios", "sim/validation/cases")
        },
        "code_sha256_raw": {
            name: hashlib.sha256((root / name).read_bytes()).hexdigest()
            for name in CODE_FILES
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    report = audit_repository(args.root)
    if args.summary:
        for scope in report["scopes"].values():
            scope.pop("files")
    print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
