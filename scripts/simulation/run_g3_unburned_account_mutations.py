#!/usr/bin/env python3
"""Engine mutation audit of the G3-4A energy account.

Each mutant changes the ENGINE by exact text replacement (every anchor must
occur exactly once), runs one control with the account ON through the monitored
launcher, evaluates ``analyze_g3_balance_ledger`` on the engine ledger and
restores the original bytes (SHA-256 verified) before the next mutant, also
after an error. The unmutated control is run first and must have none of the
target findings.

The control is ``o2_closed`` with one suppression event at 400 s, so that the
pool loses energy by decay and by suppression. It is a diagnostic scenario
written inside the run directory; no distributed scenario is touched.

    python scripts/simulation/run_g3_unburned_account_mutations.py --env-root D:/g34a_env
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts" / "simulation"))

from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402
from scripts.simulation import run_g3_optd_controls as optd  # noqa: E402
from scripts.simulation import run_g3_unburned_account_controls as controls  # noqa: E402
import analyze_g3_balance_ledger as bal  # noqa: E402

COMBUSTION = "sim/fire/CombustionSystem.gd"
ENGINE = "sim/core/SimulationEngine.gd"
CASE = "o2_closed_suppressed"
SUPPRESSION = {"time_s": 400.0, "room_id": 0, "duration_s": 2.0, "flow_lpm": 60.0, "effectiveness": 0.5}

MUTANTS = {
    # The object keeps only 70 % of what its debit left without burning or storing.
    "MA1_object_account_short": {
        "file": COMBUSTION,
        "edits": [(
            "\t\t\tobj.g3_unburned_energy_account_MJ += burn_MJ * unburned_account_fraction\n",
            "\t\t\tobj.g3_unburned_energy_account_MJ += burn_MJ * unburned_account_fraction * 0.7\n",
        )],
        "target": "A_object_account_write",
    },
    # The pool still decays but the decay no longer reaches its account.
    "MA2_decay_not_credited": {
        "file": COMBUSTION,
        "edits": [(
            "\tif g3_account:\n"
            "\t\troom.g3_pool_account_decay_MJ += maxf(\n"
            "\t\t\t0.0, g3_account_pool_mark_MJ - room.retained_unburned_MJ\n"
            "\t\t)\n",
            "",
        )],
        "target": "A_pool_account_write",
    },
    # Suppression still cuts the pool but nothing is credited.
    "MA3_suppression_not_credited": {
        "file": ENGINE,
        "edits": [(
            "\t\troom.g3_pool_account_suppression_MJ += maxf(\n"
            "\t\t\t0.0, g3_account_pool_before_MJ - room.retained_unburned_MJ\n"
            "\t\t)\n",
            "\t\tpass\n",
        )],
        "target": "A_pool_account_write",
    },
    # The share sent to the pool is also credited to the object: counted twice.
    "MA4_pool_share_counted_twice": {
        "file": COMBUSTION,
        "edits": [(
            "\t\t\t\tsolid_pyrolysis_kw - fresh_flame_target_kw - smolder_target_kw - retained_generation_kw\n"
            "\t\t\t) / solid_pyrolysis_kw\n",
            "\t\t\t\tsolid_pyrolysis_kw - fresh_flame_target_kw - smolder_target_kw\n"
            "\t\t\t) / solid_pyrolysis_kw\n",
        )],
        "target": "A_object_account_write",
    },
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def scenario() -> dict:
    data = copy.deepcopy(optd.cases()["o2_closed"])
    data["engine_overrides"][batch.SWITCH] = True
    data["engine_overrides"][controls.ACCOUNT_SWITCH] = True
    data["suppression_events"] = [dict(SUPPRESSION)]
    return data


def launch(label: str) -> Path:
    baseline.TIMEOUT_S = 900
    baseline.run(
        case_scenarios={CASE: scenario()}, output_label=label, report_schema=f"{label}_v1",
        extra_runner_args=[batch.LEDGER_ARG],
    )
    return sorted((ROOT / "runs").glob(f"{label}_*"))[-1] / CASE


def findings(case_dir: Path) -> dict:
    report = bal.analyze_case(case_dir)
    return {item["code"]: {"steps": item["steps"], "amount": item["amount"], "details": item["details"]}
            for item in report["findings"]}


def run(env_root: Path, selected: list[str] | None) -> int:
    names = selected or list(MUTANTS)
    originals = {}
    for name in names:
        spec = MUTANTS[name]
        originals.setdefault(spec["file"], (ROOT / spec["file"]).read_bytes())
        text = originals[spec["file"]].decode("utf-8")
        for old, _new in spec["edits"]:
            if text.count(old) != 1:
                raise RuntimeError(f"{name}: mutation anchor found {text.count(old)} times")
    shas = {relative: _sha(data) for relative, data in originals.items()}
    controls.isolate_environment(env_root)
    base_dir = launch("g3_unburned_account_mut_baseline")
    base_report = bal.analyze_case(base_dir)
    base = findings(base_dir)
    results = {"baseline": {
        "case_dir": str(base_dir), "findings": base,
        "pool_account_decay_MJ": base_report["terms"].get("pool_account_decay_MJ", 0.0),
        "pool_account_suppression_MJ": base_report["terms"].get("pool_account_suppression_MJ", 0.0),
        "object_account_MJ": base_report["terms"].get("object_account_change_MJ", 0.0),
    }}
    targets = {MUTANTS[name]["target"] for name in names}
    if targets & set(base):
        raise RuntimeError(f"the unmutated control already has target findings: {sorted(targets & set(base))}")
    if min(results["baseline"][key] for key in
           ("pool_account_decay_MJ", "pool_account_suppression_MJ", "object_account_MJ")) <= 0.0:
        raise RuntimeError("the control does not exercise every account")
    try:
        for name in names:
            spec = MUTANTS[name]
            path = ROOT / spec["file"]
            mutated = originals[spec["file"]].decode("utf-8")
            for old, new in spec["edits"]:
                mutated = mutated.replace(old, new)
            path.write_bytes(mutated.encode("utf-8"))
            try:
                case_dir = launch(f"g3_unburned_account_mut_{name}")
            finally:
                path.write_bytes(originals[spec["file"]])
                if _sha(path.read_bytes()) != shas[spec["file"]]:
                    raise RuntimeError(f"{spec['file']} not restored byte for byte")
            found = findings(case_dir)
            outcome = {
                "case_dir": str(case_dir), "target": spec["target"],
                "caught": spec["target"] in found, "target_finding": found.get(spec["target"]),
                "new_findings": sorted(code for code in found if code not in base),
                # A mutant of the account alone must leave the physical trajectory untouched.
                "physics_unchanged": all(
                    controls._sha(case_dir / item) == controls._sha(base_dir / item)
                    for item in controls.IDENTICAL_FILES
                ),
            }
            results[name] = outcome
            print(json.dumps({name: outcome}, ensure_ascii=False), flush=True)
    finally:
        for relative, data in originals.items():
            if _sha((ROOT / relative).read_bytes()) != shas[relative]:
                (ROOT / relative).write_bytes(data)
    report = ROOT / "runs" / "g3_unburned_account_mutations_report.json"
    report.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0 if all(results[name]["caught"] for name in names) else 3


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env-root", type=Path, required=True, help="APPDATA/TEMP/TMP root, outside the checkout")
    parser.add_argument("--mutant", action="append", dest="mutants", choices=sorted(MUTANTS))
    args = parser.parse_args()
    try:
        raise SystemExit(run(args.env_root, args.mutants))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 UNBURNED ACCOUNT MUTATIONS FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
