"""Offline D1 input contract; NOT an engine provider or scientific approval.

No inferred kg, HRR conversion, network, file writes, or Godot. External
provenance must point to checksummed local evidence, but semantic attribution
and validity outside that experiment always require scientific review.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCHEMA = "g3_mass_material_profile_v1"
MASS_ABS_TOL_KG = 1e-12
REL_TOL = 1e-12


def _object(value, keys, label, errors):
    if not isinstance(value, dict):
        errors.append(f"{label}: expected object")
        return {}
    if set(value) != set(keys):
        errors.append(f"{label}: missing or unsupported fields")
    return value


def _text(value, label, errors):
    if not isinstance(value, str) or not value.strip():
        errors.append(f"{label}: expected nonempty string")
        return ""
    return value


def _number(value, label, errors, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        errors.append(f"{label}: expected finite number, not bool/string")
        return 0.0
    try:
        result = float(value)
    except OverflowError:
        result = math.inf
    if not math.isfinite(result) or result < 0 or (positive and result == 0):
        errors.append(f"{label}: invalid numeric value")
        return 0.0
    return result


def _exact(value, expected, label, errors):
    if value != expected:
        errors.append(f"{label}: must be {expected}")


def _provenance(value, kind, label, root, errors):
    common = {"type", "reference", "locator", "uncertainty", "regime", "scale"}
    external = {"artifact", "sha256", "version"}
    data = _object(value, common | (external if kind == "external_candidate" else set()), label, errors)
    for key in common - {"type"}:
        _text(data.get(key), f"{label}.{key}", errors)
    if kind == "synthetic_control":
        _exact(data.get("type"), "synthetic", f"{label}.type", errors)
        if not str(data.get("reference", "")).startswith("synthetic:"):
            errors.append(f"{label}: synthetic reference must be explicitly labelled")
        return
    if kind != "external_candidate":
        return
    if not isinstance(data.get("type"), str) or data.get("type") not in {"measured", "declared_model"}:
        errors.append(f"{label}: external evidence type must be measured or declared_model")
    _text(data.get("version"), f"{label}.version", errors)
    reference = _text(data.get("reference"), f"{label}.reference", errors)
    if not reference.startswith("https://"):
        errors.append(f"{label}: external reference must be an HTTPS source")
    relative = _text(data.get("artifact"), f"{label}.artifact", errors)
    checksum = data.get("sha256")
    if not isinstance(checksum, str) or not re.fullmatch(r"[0-9a-f]{64}", checksum):
        errors.append(f"{label}: invalid SHA-256")
        return
    try:
        path = (root / relative).resolve()
        if Path(relative).is_absolute() or not path.is_relative_to(root.resolve()):
            raise ValueError("artifact must stay inside the declared root")
        if not path.is_file():
            raise ValueError("local artifact missing")
        if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            raise ValueError("artifact SHA-256 mismatch")
    except (OSError, ValueError) as exc:
        errors.append(f"{label}: {exc}")


def validate_profile(value, root=ROOT):
    """Return a diagnostic only. Never supply a request to FuelMassBudgetModel."""
    errors = []
    data = _object(value, {
        "schema", "id", "kind", "component_id", "scope", "initial_mass",
        "material", "release",
    }, "profile", errors)
    _exact(data.get("schema"), SCHEMA, "schema", errors)
    _text(data.get("id"), "id", errors)
    kind = data.get("kind")
    if not isinstance(kind, str) or kind not in {"synthetic_control", "external_candidate"}:
        errors.append("kind: unsupported, no production profiles in this contract")
    component = _text(data.get("component_id"), "component_id", errors)
    _exact(data.get("scope"), "single_CHO_no_residue", "scope", errors)

    initial = _object(data.get("initial_mass"), {
        "value", "unit", "basis", "component_id", "provenance",
    }, "initial_mass", errors)
    mass = _number(initial.get("value"), "initial_mass.value", errors)
    _exact(initial.get("unit"), "kg", "initial_mass.unit", errors)
    _exact(initial.get("basis"), "modeled_component_mass", "initial_mass.basis", errors)
    _exact(initial.get("component_id"), component, "initial_mass.component_id", errors)
    _provenance(initial.get("provenance"), kind, "initial_mass.provenance", Path(root), errors)

    material = _object(data.get("material"), {
        "component_id", "mass_fractions", "composition_provenance", "chemical_heat",
    }, "material", errors)
    _exact(material.get("component_id"), component, "material.component_id", errors)
    fractions = _object(material.get("mass_fractions"), {"C", "H", "O"}, "mass_fractions", errors)
    values = [_number(fractions.get(key), f"mass_fractions.{key}", errors) for key in ("C", "H", "O")]
    if abs(sum(values) - 1.0) > REL_TOL:
        errors.append("mass_fractions: CHO fractions must sum to 1")
    _provenance(material.get("composition_provenance"), kind, "composition_provenance", Path(root), errors)
    heat = _object(material.get("chemical_heat"), {
        "value", "unit", "basis", "component_id", "provenance",
    }, "chemical_heat", errors)
    _number(heat.get("value"), "chemical_heat.value", errors, positive=True)
    _exact(heat.get("unit"), "kJ/kg", "chemical_heat.unit", errors)
    _exact(heat.get("basis"), "complete_oxidation_net", "chemical_heat.basis", errors)
    _exact(heat.get("component_id"), component, "chemical_heat.component_id", errors)
    _provenance(heat.get("provenance"), kind, "chemical_heat.provenance", Path(root), errors)

    release = _object(data.get("release"), {
        "mode", "quantity", "unit", "component_id", "time_origin",
        "interpolation", "outside_domain", "samples", "provenance",
    }, "release", errors)
    _exact(release.get("mode"), "prescribed", "release.mode", errors)
    _exact(release.get("quantity"), "modeled_component_emission", "release.quantity", errors)
    _exact(release.get("unit"), "kg/s", "release.unit", errors)
    _exact(release.get("component_id"), component, "release.component_id", errors)
    _text(release.get("time_origin"), "release.time_origin", errors)
    _exact(release.get("interpolation"), "piecewise_linear", "release.interpolation", errors)
    _exact(release.get("outside_domain"), "reject", "release.outside_domain", errors)
    _provenance(release.get("provenance"), kind, "release.provenance", Path(root), errors)
    samples = release.get("samples")
    parsed = []
    if not isinstance(samples, list) or len(samples) < 2:
        errors.append("release.samples: at least two samples required")
    else:
        for index, sample in enumerate(samples):
            sample = _object(sample, {"time_s", "rate_kg_s"}, f"sample[{index}]", errors)
            time = _number(sample.get("time_s"), f"sample[{index}].time_s", errors)
            rate = _number(sample.get("rate_kg_s"), f"sample[{index}].rate_kg_s", errors)
            if parsed and time <= parsed[-1][0]:
                errors.append("release.samples: times must strictly increase")
            parsed.append((time, rate))
        if parsed and parsed[0][0] != 0.0:
            errors.append("release.samples: domain must start at explicit time zero")
    emitted = 0.0
    if not errors:
        for (t0, r0), (t1, r1) in zip(parsed, parsed[1:]):
            emitted += (t1 - t0) * (0.5 * r0 + 0.5 * r1)
        if not math.isfinite(emitted):
            errors.append("release: integrated mass overflow")
        elif emitted > mass + MASS_ABS_TOL_KG + REL_TOL * max(mass, emitted):
            errors.append("release: integral exceeds declared initial component mass")
    valid = not errors
    return {
        "schema": SCHEMA, "valid": valid, "errors": errors,
        "decision": ("synthetic_contract_complete" if kind == "synthetic_control"
                     else "external_contract_complete_pending_scientific_review") if valid else "rejected",
        "declared_initial_mass_kg": mass if valid else None,
        "prescribed_emission_integral_kg": emitted if valid else None,
        "production_activation": False, "engine_integration": False,
        "scientific_approval": False,
    }


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def prepare_prescribed_program(value, root=ROOT):
    """Explicit isolated adapter. Evidence eligibility is NEVER upgraded."""
    report = validate_profile(value, root)
    if not report["valid"]:
        return {**report, "program": {}}
    release = value["release"]
    program = {key: copy.deepcopy(release[key]) for key in (
        "mode", "quantity", "unit", "component_id", "time_origin",
        "interpolation", "outside_domain", "samples",
    )}
    program.update({"profile_id": value["id"], "initial_mass_kg": value["initial_mass"]["value"]})
    return {**report, "program": program}


def _invalid_constant(value):
    raise ValueError(f"nonfinite JSON token: {value}")


def load_profile(path):
    return json.loads(Path(path).read_text(encoding="utf-8"),
                      object_pairs_hook=_unique_pairs, parse_constant=_invalid_constant)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", type=Path)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        report = validate_profile(load_profile(args.profile), args.root)
    except (OSError, ValueError) as exc:
        report = {"valid": False, "errors": [str(exc)], "decision": "rejected",
                  "production_activation": False, "engine_integration": False,
                  "scientific_approval": False}
    print(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False))
    return 0 if report["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
