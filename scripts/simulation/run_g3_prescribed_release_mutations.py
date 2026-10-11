"""Prescribed-rate mutants on isolated copies; original files stay untouched."""

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
from scripts.simulation.run_g3_fuel_mass_budget_mutations import changed_source  # noqa: E402


MODEL = ROOT / "sim/fire/PrescribedFuelReleaseModel.gd"
FIXTURE = ROOT / "tests/fixtures/g3_prescribed_fuel_release.gd"
ASSETS = [MODEL, FIXTURE, ROOT / "sim/fire/FuelMassBudgetModel.gd",
          ROOT / "sim/fire/SensibleEnthalpyModel.gd",
          ROOT / "sim/fire/HeptaneRealCpProfiles.gd",  # preloaded by the ledger since 2026-10-06
          ROOT / "tests/fixtures/g3_mass_material_profile_synthetic.json"]
MUTATIONS = {
    "M01_do_not_advance_clock": ('"time_s": float(preview["end_time_s"]),', '"time_s": float(progress["time_s"]),'),
    "M02_retry_rejected_demand": ('var request: float = _integral(samples, start, end, interpolation)',
                                  'var request: float = _integral(samples, start, end, interpolation) + rejected'),
    "M03_accept_above_request": ('if accepted > requested:', 'if false:'),
    "M04_ignore_program_identity": (
        'if typeof(p.get("fingerprint")) not in [TYPE_STRING, TYPE_STRING_NAME] or p.get("fingerprint") != checked["fingerprint"]:',
        'if false:'),
    "M05_ignore_rate_unit": (
        'if typeof(data.get(key)) not in [TYPE_STRING, TYPE_STRING_NAME] or data.get(key) != PROGRAM_LITERALS[key]:',
        'if key != "unit" and (typeof(data.get(key)) not in [TYPE_STRING, TYPE_STRING_NAME] or data.get(key) != PROGRAM_LITERALS[key]):'),
    "M06_extrapolate_past_domain": ('if start > domain_end or end > domain_end or end < start:',
                                   'if start > domain_end or end < start:'),
    "M07_left_rectangle": ('0.5 * left + 0.5 * right', 'left'),
    "M08_admit_boolean": ('typeof(value) not in [TYPE_FLOAT, TYPE_INT]',
                          'typeof(value) not in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]'),
    "M09_replay_prefix_each_step": ('var request: float = _integral(samples, start, end, interpolation)',
                                   'var request: float = _integral(samples, 0.0, end, interpolation)'),
    "M10_ignore_progress_counters": ('if not _near(scheduled, expected) or not _near(accepted + rejected, scheduled):', 'if false:'),
    "M11_ignore_initial_mass_cap": ('if not _finite(total) or total > mass + MASS_ABS_TOL_KG + REL_TOL * maxf(mass, total):',
                                    'if not _finite(total):'),
}
MEASURED_MUTATIONS = {
    "R01_right_rectangle": ('total += (hi - lo) * r0',
                            'total += (hi - lo) * float(samples[i + 1]["rate_kg_s"])'),
    "R02_trapezoid_instead_of_interval_mean": (
        'if interpolation == "piecewise_constant_left":', 'if false:'),
    "R03_charge_whole_interval_on_partial_step": ('total += (hi - lo) * r0',
                                                  'total += (t1 - t0) * r0'),
    "R04_omit_first_interval": ('for i in range(samples.size() - 1):',
                                'for i in range(1, samples.size() - 1):'),
    "R05_duplicate_measured_demand": ('total += (hi - lo) * r0',
                                     'total += 2.0 * (hi - lo) * r0'),
    "R06_ignore_terminal_convention": (
        'if measured and samples[-1]["rate_kg_s"] != 0.0:', 'if false:'),
    "R07_relabel_measured_depletion_as_emission": ('if not linear and not measured:', 'if false:'),
    "R08_ignore_program_identity": MUTATIONS["M04_ignore_program_identity"],
    "R09_retry_rejected_demand": MUTATIONS["M02_retry_rejected_demand"],
    "R10_do_not_advance_clock": MUTATIONS["M01_do_not_advance_clock"],
    "R11_extrapolate_into_unreviewed_tail": MUTATIONS["M06_extrapolate_past_domain"],
}


def classify(stdout, stderr, code, measured=False):
    prefix = "G3_MEASURED_MASS_REPLAY" if measured else "G3_PRESCRIBED_RELEASE"
    lines = [line for line in stdout.splitlines() if line.startswith(prefix + " {")]
    if not lines or "Parse Error" in stdout + stderr or "SCRIPT ERROR" in stdout + stderr:
        raise RuntimeError("fixture missing, syntax error or script runtime error")
    payload = json.loads(lines[-1].split(" ", 1)[1])
    if code == 0 and not payload["failures"] and prefix + "_PASS" in stdout:
        return "pass", payload
    if code == 1 and payload["failures"]:
        return "killed", payload
    raise RuntimeError("inconsistent fixture/exit")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--measured-replay", action="store_true")
    args = parser.parse_args()
    fixture = ROOT / "tests/fixtures/g3_measured_mass_replay.gd" if args.measured_replay else FIXTURE
    assets = [MODEL, fixture, ROOT / "tests/fixtures/g3_isohept9_measured_replay.json"] if args.measured_replay else ASSETS
    mutations = MEASURED_MUTATIONS if args.measured_replay else MUTATIONS
    original = {path: path.read_bytes() for path in assets}
    source = original[MODEL].decode("utf-8")
    variants = {name: changed_source(source, *change) for name, change in mutations.items()}
    if args.plan_only:
        print(json.dumps({"mutations_prepared": list(variants), "executed": False}))
        return 0
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot not found")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    environment = os.environ.copy()
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    kind = "measured" if args.measured_replay else "prescribed"
    evidence = ROOT / "runs" / f"g3_d1_{kind}_mutations_{stamp}"
    evidence.mkdir(parents=True, exist_ok=False)
    results = []
    try:
        for name, candidate in {"control": source, **variants}.items():
            project = evidence / name
            for path, raw in original.items():
                destination = project / path.relative_to(ROOT)
                destination.parent.mkdir(parents=True, exist_ok=True)
                if path == MODEL:
                    destination.write_text(candidate, encoding="utf-8", newline="\n")
                else:
                    destination.write_bytes(raw)
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="D1 isolated prescribed rate"\n', encoding="utf-8")
            launched = godot_monitored_launch.run(
                [str(godot), "--headless", "--path", str(project), "--script",
                 str(project / fixture.relative_to(ROOT))], timeout_s=120, environment=environment,
            )
            for filename, data in [("health.json", json.dumps(launched.health, indent=2)),
                                   ("stdout.log", launched.stdout), ("stderr.log", launched.stderr)]:
                (project / filename).write_text(data, encoding="utf-8")
            if not launched.launched or launched.faults:
                raise RuntimeError(f"{name}: infrastructure fault: {launched.faults}")
            verdict, payload = classify(launched.stdout, launched.stderr, launched.returncode, args.measured_replay)
            expected = "pass" if name == "control" else "killed"
            results.append({"name": name, "verdict": verdict, "expected": expected, "fixture": payload})
            print(json.dumps({"name": name, "verdict": verdict}), flush=True)
            if verdict != expected:
                raise RuntimeError(f"{name}: failed control or survivor")
    finally:
        intact = all(path.read_bytes() == raw for path, raw in original.items())
        (evidence / "results.json").write_text(json.dumps({
            "results": results, "working_sources_intact": intact,
            "working_sha256": {path.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest()
                               for path, raw in original.items()},
        }, indent=2), encoding="utf-8")
        if not intact:
            raise RuntimeError("working source changed during isolated campaign")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
