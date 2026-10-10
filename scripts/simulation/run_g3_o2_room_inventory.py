#!/usr/bin/env python3
"""Record of stage M1 of the oxygen authority: room inventory and transit.

Four things, each through the monitored launcher, one Godot at a time:

1. BEFORE M1. The tracked engine files this stage changes are put back, byte for byte,
   to the commit before it; the acceptance fixture runs; the files are restored and
   their SHA-256 verified. The fixture must reach its end with failed checks in every
   group and with no script error: the tests of M0 fail for the missing behaviour.
2. ACCEPTANCE. The fixture on the working tree. It must pass.
3. HISTORICAL ROUTE. The diagnosis published on 2026-10-09 is measured again on the
   working tree, with the new switch off, and every figure of its evidence is compared
   with the published record. Nothing of that record is rewritten.
4. The mutation results and the trace contracts are read from where they were run.

    python scripts/simulation/run_g3_o2_room_inventory.py \
        --mutations runs/g3_o2_room_inventory_mutations_<stamp>/results.json \
        --identity-run runs/g3_balance_identity_off_ledgeroff_<stamp>

``--plan-only`` prints what would run and launches nothing.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch, run_scenario  # noqa: E402

SCHEMA = "g3_o2_room_inventory_m1_record_v1"
RECORD = "docs/validation/G3_O2_ROOM_INVENTORY_M1_2026-10-10.json"
FIXTURE = "tests/fixtures/g3_o2_room_inventory.gd"
PREFIX = "G3_O2_ROOM_INVENTORY"
# The commit before this stage. Its engine has no inventory mode.
BEFORE_M1 = "7b2e12d9"
# Tracked engine files this stage changes; the owner is a new file and is not among them.
CHANGED_BY_M1 = ("sim/building/RoomModel.gd", "sim/core/OxygenExchangeSystem.gd",
                 "sim/core/GasExchangeSystem.gd", "sim/core/SimulationEngine.gd")
SOURCES = CHANGED_BY_M1 + ("sim/core/RoomOxygenInventory.gd", FIXTURE)
# Left as they were, by content.
UNTOUCHED = ("sim/fire/PrescribedObjectHrrSource.gd", "sim/fire/CombustionSystem.gd",
             "sim/fire/PrescribedThermalSourceCoupling.gd")
DIAGNOSIS_RUNNER = "scripts/simulation/run_g3_o2_authority_diagnosis.py"
DIAGNOSIS_RECORD = "docs/validation/G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json"
HOUSE_CASES = ("sofa_vent", "o2_closed", "o2_reopen_300", "o2_stress_cap")
O2_KG_PER_KJ = 0.076 / 1000.0
TOL_ABS_KG, TOL_REL = 1.0e-3, 1.0e-4


def _sha(data: bytes) -> str:
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def _git(*args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def _launch() -> dict:
    """One launch of the acceptance fixture; what it printed and how it ended."""
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    run = godot_monitored_launch.run([godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
                                     timeout_s=900, environment=os.environ.copy())
    if not run.launched or run.faults or run.preexisting:
        raise RuntimeError(f"not a healthy run: {run.faults or run.preexisting}")
    text = (run.stdout or "") + (run.stderr or "")
    line = next((line for line in (run.stdout or "").splitlines() if line.startswith(PREFIX + " {")), None)
    if line is None:
        raise RuntimeError("the fixture did not reach its end:\n" + text[-3000:])
    payload = json.loads(line.split(" ", 1)[1])
    return {
        "returncode": run.returncode, "pass_marker": PREFIX + "_PASS" in (run.stdout or ""),
        "script_errors": text.count("SCRIPT ERROR") + text.count("Parse Error"),
        "checks": payload["checks"], "failure_count": payload["failure_count"],
        "failures_by_group": payload["failures_by_group"], "groups": payload["groups"],
        "first_failures": payload["failures"][:12], "observations": payload["observations"],
    }


def before_m1() -> dict:
    """The fixture on the engine of the commit before this stage. Restores and verifies."""
    current = {relative: (ROOT / relative).read_bytes() for relative in CHANGED_BY_M1}
    earlier = {relative: _git("show", f"{BEFORE_M1}:{relative}") for relative in CHANGED_BY_M1}
    try:
        for relative, data in earlier.items():
            (ROOT / relative).write_bytes(data)
        result = _launch()
    finally:
        for relative, data in current.items():
            (ROOT / relative).write_bytes(data)
            if (ROOT / relative).read_bytes() != data:
                raise RuntimeError(f"{relative} not restored byte for byte")
    result.pop("observations")
    result["engine"] = f"tracked engine files of {BEFORE_M1}, byte for byte"
    result["engine_sha256"] = {relative: _sha(data) for relative, data in earlier.items()}
    result["restored_byte_for_byte"] = True
    return result


def historical_route() -> dict:
    """The published diagnosis measured again on this tree, switch off, against its record."""
    spec = importlib.util.spec_from_file_location("diagnosis", ROOT / DIAGNOSIS_RUNNER)
    diagnosis = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(diagnosis)
    published = json.loads((ROOT / DIAGNOSIS_RECORD).read_text(encoding="utf-8"))["hypotheses"]
    measured = diagnosis.evaluate(diagnosis.run_fixture()["cases"])
    compared, differing = [], {}
    for name, verdict in measured.items():
        if name not in published or not verdict.get("exercised", True):
            continue
        compared.append(name)
        for key in ("holds", "claims", "evidence"):
            if json.dumps(verdict.get(key), sort_keys=True) != json.dumps(published[name].get(key), sort_keys=True):
                differing.setdefault(name, []).append(key)
    return {"what": "the diagnosis of 2026-10-09 measured again on this tree with the new switch off",
            "published_record": DIAGNOSIS_RECORD, "published_record_rewritten": False,
            "hypotheses_compared": sorted(compared), "identical_figure_by_figure": not differing, "differing": differing}


def _rooms(run: Path) -> dict:
    per: dict = {}
    with (run / "sim_log.csv").open(encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            per.setdefault(row["room_name"], []).append(row)
    return per


def trace_contracts(identity_run: Path) -> dict:
    """C1, C2 and C4 in their corrected form, on the house traces of a switch-off run.

    The same expressions as tests/test_oxygen_contract.py. They are contracts: on the
    historical route they fail where the defect exists, and that is what is recorded.
    """
    out = {}
    for case in HOUSE_CASES:
        folder = identity_run / case
        if not (folder / "sim_log.csv").is_file():
            continue
        worst = {"c1_residual_kg": 0.0, "c2_heat_minus_debit_kg": 0.0, "c2_primary_minus_debit_kg": 0.0, "c4_missing_kg": 0.0}
        holds = {"c1": True, "c2": True, "c4": True}
        for rows in _rooms(folder).values():
            first, last = rows[0], rows[-1]
            air = float(last["air_mass_kg"])
            initial = float(first["o2"]) * air
            tolerance = max(TOL_ABS_KG, TOL_REL * initial)
            debit = float(last["o2_consumed_bulk_kg_total"])
            residual = float(last["o2"]) * air - (initial - debit + float(last["o2_net_transport_kg_total"])
                                                  + float(last["o2_exterior_net_kg_total"]) + float(last["o2_zone_sync_kg_total"]))
            if abs(residual) > abs(worst["c1_residual_kg"]):
                worst["c1_residual_kg"] = residual
            holds["c1"] = holds["c1"] and abs(residual) <= tolerance
            demand = float(last["hrr_kj_total"]) * O2_KG_PER_KJ
            if demand <= 0.0:
                continue
            primary = float(last["o2_consumed_fire_kg_total"])
            worst["c2_heat_minus_debit_kg"] = max(worst["c2_heat_minus_debit_kg"], demand - debit, key=abs)
            worst["c2_primary_minus_debit_kg"] = max(worst["c2_primary_minus_debit_kg"], primary - debit, key=abs)
            holds["c2"] = holds["c2"] and abs(demand - debit) <= tolerance and abs(primary - debit) <= tolerance
            supply = initial + max(0.0, float(last["o2_net_transport_kg_total"])) + max(0.0, float(last["o2_exterior_net_kg_total"]))
            worst["c4_missing_kg"] = max(worst["c4_missing_kg"], demand - supply)
            holds["c4"] = holds["c4"] and demand <= supply + tolerance
        out[case] = {"holds": holds, **worst}
    return {"what": "corrected C1, C2 and C4 on the historical route, switch off; contracts, not regressions",
            "run": identity_run.as_posix(), "cases": out}


def mutations(results: Path) -> dict:
    summary = json.loads(results.read_text(encoding="utf-8"))
    keep = ("name", "verdict", "reason", "file", "defect", "expected_in", "declared_with_the_plan", "seen_where_expected",
            "checks", "failed_checks", "groups_with_failures", "mutant_sha256")
    return {
        "evidence": results.parent.relative_to(ROOT).as_posix() if results.is_relative_to(ROOT) else results.parent.as_posix(),
        **{key: summary[key] for key in ("control", "control_checks", "declared", "executed", "killed", "killed_where_expected",
                                         "survivors", "invalid", "killed_elsewhere", "originals_intact",
                                         "launches_refused_by_the_memory_gate_and_repeated")},
        "results": [{key: item.get(key) for key in keep} for item in summary["results"]],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--mutations", type=Path, help="results.json of the mutation runner")
    parser.add_argument("--identity-run", type=Path, help="switch-off identity run of this tree, with the house cases")
    args = parser.parse_args()
    if args.plan_only:
        print(json.dumps({"executed": False, "before_m1": BEFORE_M1, "restored_from_git": list(CHANGED_BY_M1),
                          "fixture": FIXTURE, "record": RECORD}, indent=1))
        return 0
    record = {
        "schema": SCHEMA, "head": _git("rev-parse", "--short=8", "HEAD").decode().strip(),
        "scope": "stage M1 of the oxygen authority: room inventory and transit as state behind a switch that is off; "
                 "conservation and ownership only; no fire behaviour, no CO, FED or SVV",
        "sources_sha256": {relative: _sha((ROOT / relative).read_bytes()) for relative in SOURCES},
        "untouched_sha256": {relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() for relative in UNTOUCHED},
        "untouched_equal_to_before_m1": {
            relative: (ROOT / relative).read_bytes().replace(b"\r\n", b"\n") == _git("show", f"{BEFORE_M1}:{relative}").replace(b"\r\n", b"\n")
            for relative in UNTOUCHED},
        "budget_gap_accepted_kg": 1.0e-9,
    }
    record["before_m1"] = before_m1()
    record["acceptance"] = _launch()
    record["historical_route"] = historical_route()
    if args.mutations:
        record["mutations"] = mutations(args.mutations.resolve())
    if args.identity_run:
        record["trace_contracts"] = trace_contracts(args.identity_run)
    saved = ROOT / RECORD
    saved.write_bytes((json.dumps(record, indent=1, ensure_ascii=False) + "\n").encode("utf-8"))
    print("before M1: checks", record["before_m1"]["checks"], "failed", record["before_m1"]["failure_count"],
          "script errors", record["before_m1"]["script_errors"])
    print("acceptance: checks", record["acceptance"]["checks"], "failed", record["acceptance"]["failure_count"],
          "pass", record["acceptance"]["pass_marker"])
    print("historical route identical:", record["historical_route"]["identical_figure_by_figure"],
          record["historical_route"]["differing"])
    print(saved.relative_to(ROOT).as_posix())
    return 0 if record["acceptance"]["failure_count"] == 0 and record["acceptance"]["pass_marker"] \
        and record["historical_route"]["identical_figure_by_figure"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
