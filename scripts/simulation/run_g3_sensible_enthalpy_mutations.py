"""Predeclared isolated GDScript mutations, never on working engine sources."""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation.run_g3_fuel_mass_budget_mutations import changed_source, classify  # noqa: E402

MODEL = ROOT / "sim/fire/SensibleEnthalpyModel.gd"
FIXTURE = ROOT / "tests/fixtures/g3_sensible_enthalpy.gd"
PREFIX = "G3_SENSIBLE_ENTHALPY"
MUTATIONS = {
    "S01_omit_reference_subtraction": (
        "var lower: float = minf(REFERENCE_K, temperature)",
        "var lower: float = minf(minimum, temperature)"),
    "S02_lose_sign": (
        "var signed_integral: float = -integral if temperature < REFERENCE_K else integral",
        "var signed_integral: float = integral"),
    "S03_endpoint_cp_not_integral": (
        "var signed_integral: float = -integral if temperature < REFERENCE_K else integral",
        "var signed_integral: float = query_cp * (temperature - REFERENCE_K)"),
    "S04_omit_partial": (
        "if b <= a:", "if b <= a or a != t0 or b != t1:"),
    "S05_omit_intermediate": (
        "integral += area", "integral += area if index == 0 else 0.0"),
    "S06_clamp_outside_domain": (
        "if temperature < minimum or temperature > maximum:",
        "temperature = clampf(temperature, minimum, maximum)\n\tif temperature < minimum or temperature > maximum:"),
    "S07_allow_zero_cp": ("if cp <= 0.0:", "if cp < 0.0:"),
    "S08_allow_negative_cp": ("if cp <= 0.0:", "if false:"),
    "S09_allow_bool": (
        "typeof(value) in [TYPE_INT, TYPE_FLOAT]", "typeof(value) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]"),
    "S10_allow_nan": (
        " and not is_nan(float(value))", ""),
    "S11_allow_duplicates": (
        "temperature <= previous", "temperature < previous"),
    "S12_sort_bad_input": (
        'var previous: float = -1.0',
        'if samples.all(func(s: Variant) -> bool: return typeof(s) == TYPE_DICTIONARY and _number(s.get("temperature_k"))):\n\t\tsamples.sort_custom(func(a: Variant, b: Variant) -> bool: return float(a["temperature_k"]) < float(b["temperature_k"]))\n\tvar previous: float = -1.0'),
    "S13_ignore_units": (
        "for key: String in FIXED:", 'for key: String in FIXED:\n\t\tif key == "quantity_unit":\n\t\t\tcontinue'),
    "S14_admit_csat": (
        "for key: String in FIXED:", 'for key: String in FIXED:\n\t\tif key == "quantity":\n\t\t\tcontinue'),
    "S15_alias_profile": (
        "return _success(profile.duplicate(true))", "return _success(profile)"),
    "S16_add_latent_heat": (
        '"specific_sensible_enthalpy_kj_kg": signed_integral,',
        '"specific_sensible_enthalpy_kj_kg": signed_integral + 1000.0,'),
    "S17_allow_reference_change": (
        'elif float(profile["reference_temperature_k"]) != REFERENCE_K:',
        'elif float(profile["reference_temperature_k"]) not in [REFERENCE_K, 298.16]:'),
    "S18_approve_product": (
        '"physical_approval": false, "integration_enabled": false, "product_activation": false}',
        '"physical_approval": false, "integration_enabled": false, "product_activation": true}'),
    "S19_allow_integral_overflow": (
        'if not _number(area) or not _number(integral):', 'if false:'),
}


def prepared_variants(source: str) -> dict[str, str]:
    variants = {}
    for name, (old, new) in MUTATIONS.items():
        if name == "S18_approve_product":
            # Both success and rejection reports intentionally share this declaration.
            if source.count(old) != 2:
                raise ValueError("scope mutation must cover exactly two report constructors")
            variants[name] = source.replace(old, new)
        else:
            variants[name] = changed_source(source, old, new)
    return variants


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    originals = {p: p.read_bytes() for p in [MODEL, FIXTURE]}
    source = originals[MODEL].decode("utf-8")
    variants = prepared_variants(source)
    if args.plan_only:
        print(json.dumps({"mutations_prepared": list(variants), "executed": False}))
        return 0
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot missing")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    evidence = ROOT / "runs" / (
        "g3_sensible_mutations_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    evidence.mkdir(parents=True, exist_ok=False)
    results = []
    try:
        for name, candidate in {"control": source, **variants}.items():
            project = evidence / name
            for path, raw in originals.items():
                target = project / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(candidate.encode("utf-8") if path == MODEL else raw)
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="Isolated sensible property"\n',
                encoding="utf-8")
            run = godot_monitored_launch.run(
                [godot, "--headless", "--path", project, "--script", project / FIXTURE.relative_to(ROOT)],
                timeout_s=120, environment=os.environ.copy())
            (project / "health.json").write_text(json.dumps(run.health, indent=2), encoding="utf-8")
            (project / "stdout.log").write_text(run.stdout, encoding="utf-8")
            (project / "stderr.log").write_text(run.stderr, encoding="utf-8")
            if not run.launched or run.faults or run.preexisting:
                raise RuntimeError(f"{name}: monitor failure {run.faults or run.preexisting}")
            verdict, payload = classify(run.stdout, run.stderr, run.returncode, PREFIX)
            results.append({"name": name, "verdict": verdict, "fixture": payload})
            print(json.dumps({"name": name, "verdict": verdict}), flush=True)
            if verdict != ("pass" if name == "control" else "killed"):
                raise RuntimeError(f"{name}: failed control or surviving mutant")
    finally:
        intact = all(path.read_bytes() == raw for path, raw in originals.items())
        (evidence / "results.json").write_text(json.dumps({
            "results": results, "originals_intact": intact,
            "original_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest()
                                for p, raw in originals.items()},
        }, indent=2), encoding="utf-8")
        if not intact:
            raise RuntimeError("working sources altered")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
