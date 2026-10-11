"""Generated blocks that bind GDScript to the profiles approved by the offline gates.

Two blocks are produced from the reviewed auditors, never typed by hand:

* the approved content of sim/fire/HeptaneRealCpProfiles.gd, taken from the
  contract previews of the 2026-10-05 (gas) and 2026-10-06 (liquid) gates;
* the expectations of tests/fixtures/g3_heptane_real_cp.gd, computed here in
  Python with the auditors' restatement of the canonical integral.

Neither block is computed by the GDScript it checks. `--check` fails when a
file no longer carries the block this script would write; `--write` replaces
only the text between the markers. Nothing here starts Godot.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.simulation import audit_g3_heptane_liquid_profile as liquid  # noqa: E402
from scripts.simulation import audit_g3_heptane_real_profile as real  # noqa: E402

MODEL = ROOT / "sim/fire/HeptaneRealCpProfiles.gd"
FIXTURE = ROOT / "tests/fixtures/g3_heptane_real_cp.gd"
BEGIN = "# BEGIN GENERATED {name} (scripts/simulation/build_g3_heptane_real_cp_profiles.py)\n"
END = "# END GENERATED {name}\n"
REFERENCE_K = real.REFERENCE_K


def _floats(value):
    """Every number becomes a float: the GDScript contract compares types strictly."""
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, dict):
        return {key: _floats(item) for key, item in value.items()}
    return [_floats(item) for item in value]


def approved_content(root=ROOT):
    """Schema name -> approved profile, exactly as the two gates preview it."""
    profiles = [liquid.contract_preview(None, root), real.contract_preview(None, root)]
    return {profile["schema"]: _floats(profile) for profile in profiles}


def _literal(value, depth):
    tabs = "\t" * depth
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("nonfinite value in approved content")
        return repr(value)
    if isinstance(value, str):
        if '"' in value or "\\" in value or not value.isascii():
            raise ValueError("string needs escaping: " + value)
        return '"' + value + '"'
    if isinstance(value, dict):
        if all(not isinstance(item, (dict, list)) for item in value.values()) and len(value) <= 2:
            return "{" + ", ".join('"%s": %s' % (k, _literal(v, depth)) for k, v in value.items()) + "}"
        rows = ['%s\t"%s": %s,' % (tabs, key, _literal(item, depth + 1)) for key, item in value.items()]
        return "{\n" + "\n".join(rows) + "\n" + tabs + "}"
    if all(not isinstance(item, (dict, list)) for item in value):
        return "[" + ", ".join(_literal(item, depth) for item in value) + "]"
    rows = ["%s\t%s," % (tabs, _literal(item, depth + 1)) for item in value]
    return "[\n" + "\n".join(rows) + "\n" + tabs + "]"


def approved_block(root=ROOT):
    return "const APPROVED: Dictionary = " + _literal(approved_content(root), 0) + "\n"


def _cp(samples, temperature):
    for left, right in zip(samples, samples[1:]):
        t0, t1 = left["temperature_k"], right["temperature_k"]
        if t0 <= temperature <= t1:
            fraction = (temperature - t0) / (t1 - t0)
            return left["cp_kj_kg_k"] + fraction * (right["cp_kj_kg_k"] - left["cp_kj_kg_k"])
    raise ValueError("outside support")


def _kinds(profile, low, high):
    """Evidence kinds whose ITS-90 range overlaps [low, high]; a point takes every tier it touches."""
    kinds = []
    for tier in profile["evidence_tiers"]:
        start, end = tier["its90_range_k"]
        overlap = min(end, high) - max(start, low)
        if overlap > 0 or (low == high and start <= low <= end):
            kinds.append(tier["evidence_kind"])
    return kinds


def _phase_expectations(profile, extra):
    samples = profile["samples"]
    knots = [sample["temperature_k"] for sample in samples]
    queries = list(knots) + [0.5 * a + 0.5 * b for a, b in zip(knots, knots[1:])]
    queries += [REFERENCE_K] + [knots[0] + fraction * (knots[-1] - knots[0])
                                for fraction in (0.013, 0.237, 0.5, 0.771, 0.994)]
    points = [[t, _cp(samples, t), real.canonical_enthalpy(samples, t)] for t in sorted(set(queries))]
    low, high = knots[0], knots[-1]
    middle = knots[len(knots) // 2]
    pairs = [(low, high), (high, low), (REFERENCE_K, high), (low, REFERENCE_K),
             (knots[1], knots[2]), (middle, high), (0.5 * knots[-2] + 0.5 * high, high),
             (middle, middle), (low, low), (high, high)] + extra
    intervals = []
    for start, end in pairs:
        delta = real.canonical_enthalpy(samples, end) - real.canonical_enthalpy(samples, start)
        intervals.append([start, end, delta, _kinds(profile, min(start, end), max(start, end))])
    point_kinds = [[t, _kinds(profile, min(REFERENCE_K, t), max(REFERENCE_K, t))]
                   for t in (low, REFERENCE_K, middle, high)]
    return {"schema": profile["schema"], "knots": float(len(knots)), "support": [low, high],
            "points": points, "intervals": intervals, "point_kinds": point_kinds,
            "tier_kinds": [tier["evidence_kind"] for tier in profile["evidence_tiers"]]}


def expectations(root=ROOT):
    """Oracles of the Godot fixture, computed in Python from the approved previews."""
    content = approved_content(root)
    liquid_profile = content[liquid.REAL_FIXED["schema"]]
    gas_profile = content[real.REAL_FIXED["schema"]]
    ctx = liquid.context(None, root)
    csat_only = [float((knot["csat_j_mol_k"] * knot["scale_factor"] / ctx["molar_mass"]))
                 for knot in liquid._knots(ctx)]
    tiers = liquid_profile["evidence_tiers"]
    result = {
        "liquid": _phase_expectations(liquid_profile, [(tiers[0]["its90_range_k"][0] + 1.0,
                                                         tiers[0]["its90_range_k"][1] - 1.0)]),
        "gas": _phase_expectations(gas_profile, [(gas_profile["evidence_tiers"][1]["its90_range_k"][0] + 1.0,
                                                  gas_profile["evidence_tiers"][1]["its90_range_k"][1] - 1.0)]),
    }
    result["liquid"]["csat_only_cp_kj_kg_k"] = csat_only
    return _floats(result)


def expectations_block(root=ROOT):
    return "const EXPECTED: Dictionary = " + _literal(expectations(root), 0) + "\n"


def spliced(text, name, block):
    begin, end = BEGIN.format(name=name), END.format(name=name)
    if text.count(begin) != 1 or text.count(end) != 1:
        raise ValueError("generated markers missing or repeated: " + name)
    head, rest = text.split(begin)
    _, tail = rest.split(end)
    return head + begin + block + end + tail


def targets(root=ROOT):
    return [(MODEL, "APPROVED CONTENT", approved_block(root)),
            (FIXTURE, "EXPECTATIONS", expectations_block(root))]


def stale(root=ROOT):
    """Files whose generated block differs from what the auditors produce now."""
    result = []
    for path, name, block in targets(root):
        text = path.read_text(encoding="utf-8")
        if spliced(text, name, block) != text:
            result.append(path.relative_to(ROOT).as_posix())
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    if args.write:
        for path, name, block in targets():
            text = path.read_text(encoding="utf-8")
            path.write_text(spliced(text, name, block), encoding="utf-8", newline="\n")
    outdated = stale()
    print({"stale": outdated, "written": args.write})
    return 1 if outdated else 0


if __name__ == "__main__":
    raise SystemExit(main())
