#!/usr/bin/env python3
"""G3-4A controls: the energy account (MJ) on the option-D control set.

Runs the controls of ``run_g3_optd_controls.py`` (plus ``o2_closed_continuous``,
the diagnostic continuous-target variant of design section 13) with
``fire_unburned_energy_account_enabled`` OFF or ON, and compares every case
with a reference run, byte for byte:

- ``--account off``: the run must equal the reference in every file, including
  the whole ledger v3 when it is written. That is the identity with the switch
  OFF.
- ``--account on``: logs, traces and events must equal the reference; the
  ledger must equal it row by row once the account fields are removed, and the
  object snapshot once its account fields are removed. That proves the account
  changes no physical result.

``--env-root`` is the directory for APPDATA, TEMP and TMP of every Godot
launch. It must lie outside this checkout. One Godot at a time through the
monitored launcher (>= 6 GiB free, no pre-existing Godot process or dialog).

    python scripts/simulation/run_g3_unburned_account_controls.py --phase on \
        --ledger on --account on --env-root D:/g34a_env --reference <run dir>
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

from scripts.simulation import run_g3_energy_controls as energy  # noqa: E402
from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402
from scripts.simulation import run_g3_optd_controls as optd  # noqa: E402

ACCOUNT_SWITCH = "fire_unburned_energy_account_enabled"
CONTINUOUS = "o2_closed_continuous"
LEDGER = "g3_fuel_ledger_v3.jsonl"
SNAPSHOT = "fuel_object_state_snapshot.json"
IDENTICAL_FILES = (
    "sim_log.csv", "sim_log.txt", "fuel_source_ledger.jsonl", "co_inventory_trace.jsonl", "events.json",
)
OBJECT_ACCOUNT_KEYS = ("unburned_account_before_MJ", "unburned_account_after_MJ")
SNAPSHOT_OBJECT_KEY = "g3_unburned_energy_account_MJ"
SNAPSHOT_ROOM_KEYS = ("g3_pool_account_MJ", "retained_unburned_MJ")


def cases() -> dict[str, dict]:
    selected = optd.cases()
    continuous = copy.deepcopy(selected["o2_closed"])
    continuous["engine_overrides"].update({
        "fire_diag_flame_target_window": 0.01, "fire_diag_flame_target_jump_fraction": 0.0,
    })
    selected[CONTINUOUS] = continuous
    return selected


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def strip_account(row: dict) -> dict:
    """The ledger row as the engine wrote it before G3-4A."""
    stripped = {key: value for key, value in row.items() if key != "bal_account"}
    stripped["objects"] = [
        {key: value for key, value in entry.items() if key not in OBJECT_ACCOUNT_KEYS}
        for entry in row.get("objects", [])
    ]
    return stripped


def compare_ledger(new: Path, reference: Path) -> dict:
    rows = different = with_account = 0
    with new.open(encoding="utf-8") as a, reference.open(encoding="utf-8") as b:
        for line_a, line_b in zip(a, b, strict=True):
            rows += 1
            row = json.loads(line_a)
            if "bal_account" in row:
                with_account += 1
            if strip_account(row) != json.loads(line_b):
                different += 1
    return {"rows": rows, "rows_with_account": with_account, "rows_differing_without_account": different}


def strip_snapshot(payload: dict) -> dict:
    stripped = copy.deepcopy(payload)
    for room in stripped.get("rooms", []):
        for key in SNAPSHOT_ROOM_KEYS:
            room.pop(key, None)
        for entry in room.get("objects", []):
            entry.pop(SNAPSHOT_OBJECT_KEY, None)
    return stripped


def compare_case(new: Path, reference: Path, ledger_on: bool, account_on: bool, scenario_identical: bool) -> dict:
    result = {"files": {}, "identical": True}
    names = IDENTICAL_FILES + (("scenario.json",) if scenario_identical else ())
    for name in names:
        result["files"][name] = _sha(new / name) == _sha(reference / name)
    if account_on:
        new_snapshot = json.loads((new / SNAPSHOT).read_text(encoding="utf-8"))
        result["files"][SNAPSHOT + " (sin la cuenta)"] = strip_snapshot(new_snapshot) == json.loads(
            (reference / SNAPSHOT).read_text(encoding="utf-8"))
        result["snapshot_carries_account"] = new_snapshot != strip_snapshot(new_snapshot)
    else:
        result["files"][SNAPSHOT] = _sha(new / SNAPSHOT) == _sha(reference / SNAPSHOT)
    result["identical"] = all(result["files"].values())
    if not ledger_on:
        result["ledger_absent"] = not (new / LEDGER).exists()
        result["identical"] = result["identical"] and result["ledger_absent"]
    elif account_on:
        result["ledger"] = compare_ledger(new / LEDGER, reference / LEDGER)
        result["identical"] = result["identical"] and result["ledger"]["rows_differing_without_account"] == 0 \
            and result["ledger"]["rows_with_account"] == result["ledger"]["rows"] \
            and result["snapshot_carries_account"]
    else:
        result["ledger_sha256_equal"] = _sha(new / LEDGER) == _sha(reference / LEDGER)
        result["identical"] = result["identical"] and result["ledger_sha256_equal"]
    return result


def isolate_environment(env_root: Path) -> None:
    """Send APPDATA, TEMP and TMP of every monitored launch outside the checkout."""
    env_root = env_root.resolve()
    if env_root == ROOT or ROOT in env_root.parents:
        raise ValueError(f"--env-root must lie outside the checkout: {env_root}")
    appdata, temp = env_root / "appdata", env_root / "temp"
    appdata.mkdir(parents=True, exist_ok=True)
    temp.mkdir(parents=True, exist_ok=True)
    monitored = baseline.mutation_audit._run_monitored

    def run(command, timeout_s, environment=None):
        isolated = dict(environment or {})
        isolated.update({"APPDATA": str(appdata), "TEMP": str(temp), "TMP": str(temp)})
        return monitored(command, timeout_s, isolated)

    baseline.mutation_audit._run_monitored = run


def reference_case_dir(reference: Path, continuous_reference: Path | None, name: str) -> Path:
    if name == CONTINUOUS:
        if continuous_reference is None:
            raise ValueError(f"{CONTINUOUS} needs --continuous-reference")
        return continuous_reference
    return reference / name


def run(phase: str, ledger_on: bool, account_on: bool, reference: Path, continuous_reference: Path | None,
        selected: list[str] | None, existing: Path | None, env_root: Path | None) -> int:
    scenarios = cases()
    names = selected or [name for name in scenarios if name != CONTINUOUS]
    unknown = sorted(set(names) - scenarios.keys())
    if unknown:
        raise ValueError(f"unknown controls: {unknown}")
    scenarios = {name: scenarios[name] for name in names}
    label = (f"g3_unburned_account_{'on' if account_on else 'off'}"
             f"_optd{phase}_ledger{'on' if ledger_on else 'off'}")
    if existing is None:
        if env_root is None:
            raise ValueError("--env-root is required to launch Godot")
        isolate_environment(env_root)
        for data in scenarios.values():
            data["engine_overrides"][batch.SWITCH] = energy.PHASES[phase]
            if account_on:
                data["engine_overrides"][ACCOUNT_SWITCH] = True
        baseline.TIMEOUT_S = energy.TIMEOUT_S
        baseline.run(
            case_scenarios=copy.deepcopy(scenarios), output_label=label, report_schema=f"{label}_v1",
            extra_runner_args=[batch.LEDGER_ARG] if ledger_on else [],
        )
        existing = sorted((ROOT / "runs").glob(f"{label}_*"))[-1]
    report = {"phase": phase, "ledger": "on" if ledger_on else "off", "account": "on" if account_on else "off",
              "run": str(existing), "reference": str(reference), "cases": {}}
    for name in scenarios:
        # With the account ON the scenario copy carries the switch, so it differs by design.
        report["cases"][name] = compare_case(
            existing / name, reference_case_dir(reference, continuous_reference, name), ledger_on, account_on,
            scenario_identical=not account_on and name != CONTINUOUS,
        )
    report["identical_cases"] = sum(1 for case in report["cases"].values() if case["identical"])
    report["total_cases"] = len(report["cases"])
    (existing / "account_identity_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({key: report[key] for key in
                      ("phase", "ledger", "account", "run", "identical_cases", "total_cases")}))
    for name, case in report["cases"].items():
        if not case["identical"]:
            print(json.dumps({name: case}))
    return 0 if report["identical_cases"] == report["total_cases"] else 3


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--phase", choices=sorted(energy.PHASES), required=True, help="option-D switch")
    parser.add_argument("--ledger", choices=("on", "off"), required=True, help="ledger v3 and balance blocks")
    parser.add_argument("--account", choices=("on", "off"), required=True, help="G3-4A energy account")
    parser.add_argument("--reference", type=Path, required=True, help="run made before G3-4A")
    parser.add_argument("--continuous-reference", type=Path, help=f"case directory for {CONTINUOUS}")
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--existing", type=Path, help="compare this finished run instead of launching")
    parser.add_argument("--env-root", type=Path, help="APPDATA/TEMP/TMP root, outside the checkout")
    args = parser.parse_args()
    try:
        raise SystemExit(run(
            args.phase, args.ledger == "on", args.account == "on", args.reference.resolve(),
            args.continuous_reference.resolve() if args.continuous_reference else None, args.cases,
            args.existing.resolve() if args.existing else None, args.env_root,
        ))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 UNBURNED ACCOUNT CONTROLS FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
