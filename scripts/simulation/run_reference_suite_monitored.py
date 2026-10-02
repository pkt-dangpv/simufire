#!/usr/bin/env python3
"""R2-1 reference suite through the safe Godot monitor (tools.mutation_audit).

Same steps as ``sim/validation/run_reference_checks.ps1``, which launches Godot
directly: for every runtime case of ``validate_reference_cases.py`` the exact
``run_case.ps1`` command (``--headless --path <repo> --log-file <log> --
--validation-case=<case>``), then the comparator and the guardrails. The only
difference is the launcher: one Godot at a time under ``_run_monitored``
(no pre-existing error dialog, Windows error UI suppressed, residual-process
check), >= 6 GiB available before each case, stop at the first unhealthy run.

Exit handling copies ``run_case.ps1 -AllowBaselineFailure``: exit 0, or exit 2
with a report written during this run, is accepted; anything else fails.

    python scripts/simulation/run_reference_suite_monitored.py
"""

from __future__ import annotations

import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import run_scenario  # noqa: E402
from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from tools import mutation_audit  # noqa: E402


TIMEOUT_S = 3600
MIN_AVAILABLE_GIB = 6.0


def main() -> int:
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot executable not found")
    cases = subprocess.run(
        [sys.executable, str(ROOT / "scripts/simulation/validate_reference_cases.py"),
         "--list-runtime-cases"], capture_output=True, text=True, cwd=ROOT, check=True,
    ).stdout.split()
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out_root = ROOT / "runs" / f"reference_suite_monitored_{stamp}"
    out_root.mkdir(parents=True)
    log = {"cases": [], "godot": str(godot)}
    for case in cases:
        if mutation_audit._godot_processes():
            raise RuntimeError(f"Godot not quiescent before {case}")
        free = baseline.available_gib()
        if free < MIN_AVAILABLE_GIB:
            raise RuntimeError(f"memory gate before {case}: {free:.2f} GiB")
        report = ROOT / "sim/validation/reports" / f"{case}.json"
        started = time.time()
        command = [str(godot), "--headless", "--path", str(ROOT),
                   "--log-file", str(out_root / f"{case}.log"), "--",
                   f"--validation-case={case}"]
        completed, health = mutation_audit._run_monitored(command, TIMEOUT_S, os.environ.copy())
        errors = mutation_audit._runtime_health_errors(health)
        fresh = report.exists() and report.stat().st_mtime >= started - 2.0
        code = completed.returncode
        if code not in (0, 2) or (code == 2 and not fresh):
            errors.append(f"exit {code}, fresh report {fresh}")
        entry = {"case": case, "exit": code, "fresh_report": fresh, "wall_s": round(time.time() - started, 1),
                 "available_gib_before": round(free, 2), "errors": errors}
        log["cases"].append(entry)
        (out_root / "suite_log.json").write_text(json.dumps(log, indent=2), encoding="utf-8")
        print(json.dumps(entry), flush=True)
        if errors:
            raise RuntimeError(f"{case}: " + "; ".join(errors))
    comparator = subprocess.run(
        [sys.executable, str(ROOT / "scripts/simulation/validate_reference_cases.py")],
        capture_output=True, text=True, cwd=ROOT,
    )
    (out_root / "comparator.stdout.log").write_text(comparator.stdout, encoding="utf-8")
    (out_root / "comparator.stderr.log").write_text(comparator.stderr, encoding="utf-8")
    print(f"[comparator] exit {comparator.returncode}", flush=True)
    if comparator.returncode not in (0, 1):
        return 1
    guard = subprocess.run(
        [sys.executable, str(ROOT / "scripts/simulation/validation_guardrails.py"),
         "--json", str(ROOT / "sim/validation/reports/reference_checks.json")],
        capture_output=True, text=True, cwd=ROOT,
    )
    (out_root / "guardrails.stdout.log").write_text(guard.stdout, encoding="utf-8")
    (out_root / "guardrails.stderr.log").write_text(guard.stderr, encoding="utf-8")
    print(f"[guardrails] exit {guard.returncode}", flush=True)
    print(guard.stdout[-3000:], flush=True)
    return 0 if guard.returncode == 0 else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"REFERENCE SUITE MONITORED FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
