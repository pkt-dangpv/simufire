#!/usr/bin/env python3
"""Identity of the option-D controls before and after the balance instrumentation.

Runs the option-D control set (the same scenarios as
``run_g3_optd_controls.py``) on the current engine and compares every case,
byte for byte, with a reference run made BEFORE the ``g3_balance_v1``
instrumentation:

- ``--ledger off`` (instrumentation OFF, as in product): no ledger v3 is
  written; logs, traces, snapshots and events must equal the reference;
- ``--ledger on`` (instrumentation ON): the same files must equal the
  reference too, and every ledger v3 row must equal the reference row once
  the new ``bal_*`` blocks are removed. That proves the observables read
  without changing anything.

``--existing DIR`` compares an already finished run instead of launching.
One Godot at a time through the monitored launcher (>= 6 GiB free, no
pre-existing Godot process or error dialog).

    python scripts/simulation/run_g3_balance_identity.py --phase off \
        --ledger off --reference runs/g3_optd_diagkey_off_20261001_202705
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

IDENTICAL_FILES = (
    "sim_log.csv", "sim_log.txt", "fuel_source_ledger.jsonl", "co_inventory_trace.jsonl",
    "fuel_object_state_snapshot.json", "events.json", "scenario.json",
)
LEDGER = "g3_fuel_ledger_v3.jsonl"


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compare_ledger(new: Path, reference: Path) -> dict:
    rows = different = with_balance = 0
    with new.open(encoding="utf-8") as a, reference.open(encoding="utf-8") as b:
        for line_a, line_b in zip(a, b, strict=True):
            rows += 1
            row = json.loads(line_a)
            if any(key.startswith("bal_") for key in row):
                with_balance += 1
            stripped = {key: value for key, value in row.items() if not key.startswith("bal_")}
            if stripped != json.loads(line_b):
                different += 1
    return {"rows": rows, "rows_with_balance_blocks": with_balance, "rows_differing_without_balance": different}


def compare_case(new: Path, reference: Path, ledger_on: bool) -> dict:
    result = {"files": {}, "identical": True}
    for name in IDENTICAL_FILES:
        same = _sha(new / name) == _sha(reference / name)
        result["files"][name] = same
        result["identical"] = result["identical"] and same
    if ledger_on:
        result["ledger"] = compare_ledger(new / LEDGER, reference / LEDGER)
        result["identical"] = result["identical"] and result["ledger"]["rows_differing_without_balance"] == 0 \
            and result["ledger"]["rows_with_balance_blocks"] == result["ledger"]["rows"]
    else:
        result["ledger_absent"] = not (new / LEDGER).exists()
        result["identical"] = result["identical"] and result["ledger_absent"]
    return result


def run(phase: str, ledger_on: bool, reference: Path, selected: list[str] | None, existing: Path | None) -> int:
    scenarios = optd.cases()
    if selected:
        scenarios = {name: scenarios[name] for name in selected}
    if existing is None:
        for data in scenarios.values():
            data["engine_overrides"][batch.SWITCH] = energy.PHASES[phase]
        baseline.TIMEOUT_S = energy.TIMEOUT_S
        label = f"g3_balance_identity_{phase}_ledger{'on' if ledger_on else 'off'}"
        baseline.run(
            case_scenarios=copy.deepcopy(scenarios), output_label=label,
            report_schema=f"{label}_v1", extra_runner_args=[batch.LEDGER_ARG] if ledger_on else [],
        )
        existing = sorted((ROOT / "runs").glob(f"{label}_*"))[-1]
    report = {"phase": phase, "ledger": "on" if ledger_on else "off", "run": str(existing),
              "reference": str(reference), "cases": {}}
    for name in scenarios:
        report["cases"][name] = compare_case(existing / name, reference / name, ledger_on)
    report["identical_cases"] = sum(1 for case in report["cases"].values() if case["identical"])
    report["total_cases"] = len(report["cases"])
    (existing / "identity_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({key: report[key] for key in ("phase", "ledger", "run", "identical_cases", "total_cases")}))
    for name, case in report["cases"].items():
        if not case["identical"]:
            print(json.dumps({name: case}))
    return 0 if report["identical_cases"] == report["total_cases"] else 3


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--phase", choices=sorted(energy.PHASES), required=True, help="option-D switch")
    parser.add_argument("--ledger", choices=("on", "off"), required=True, help="balance instrumentation")
    parser.add_argument("--reference", type=Path, required=True, help="run made before the instrumentation")
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--existing", type=Path, help="compare this finished run instead of launching")
    args = parser.parse_args()
    try:
        raise SystemExit(run(args.phase, args.ledger == "on", args.reference.resolve(), args.cases,
                             args.existing.resolve() if args.existing else None))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 BALANCE IDENTITY FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
