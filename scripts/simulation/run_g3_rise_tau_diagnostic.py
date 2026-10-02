#!/usr/bin/env python3
"""Monitored diagnostic run of ``o2_closed`` with diagnostic engine overrides.

Design section 11.7, experiment 1: the same O2-limited control as
``run_g3_energy_controls.py`` (switch ON), with ``fire_hrr_rise_tau_s`` set in
the scenario's ``engine_overrides`` and nothing else touched. It writes a
diagnostic scenario copy inside the output directory; it changes no file of
``sim/``, no distributed scenario and no product setting.

``--override KEY=NUMBER`` adds further diagnostic overrides to that scenario
copy (design section 13: ``fire_diag_flame_target_window`` and
``fire_diag_flame_target_jump_fraction``).

``--project`` runs the same scenario on another Godot project directory, e.g.
a diagnostic copy of this one that carries the engine as it was before option
D. One Godot at a time through ``scripts/godot_monitored_launch`` (no
pre-existing popup or Godot, >= 6 GiB available, only the launched tree is
ever terminated).

    python scripts/simulation/run_g3_rise_tau_diagnostic.py --label optd_tau3 \
        --rise-tau-s 3 --out runs/g3_rise_tau_diagnostic_20261001
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation import run_g3_energy_controls as energy  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402


CASE = "o2_closed"
OVERRIDE = "fire_hrr_rise_tau_s"
ENGINE_DEFAULT_RISE_TAU_S = 6.0
MIN_AVAILABLE_GIB = "6"
TIMEOUT_S = energy.TIMEOUT_S


def scenario(rise_tau_s: float, extra_overrides: dict | None = None) -> dict:
    data = energy.cases()[CASE]
    data["engine_overrides"][batch.SWITCH] = True
    if rise_tau_s != ENGINE_DEFAULT_RISE_TAU_S:
        # The engine default stays implicit so the control scenario is reproduced verbatim.
        data["engine_overrides"][OVERRIDE] = rise_tau_s
    data["engine_overrides"].update(extra_overrides or {})
    return data


def run(label: str, rise_tau_s: float, out_root: Path, project: Path,
        extra_overrides: dict | None = None) -> int:
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot executable not found")
    if not (project / "project.godot").is_file():
        raise RuntimeError(f"not a Godot project: {project}")
    out_dir = out_root / label / CASE
    if out_dir.exists():
        raise RuntimeError(f"output already exists: {out_dir}")
    out_dir.mkdir(parents=True)
    appdata, temp = out_root / label / "appdata", out_root / label / "temp"
    appdata.mkdir()
    temp.mkdir()
    environment = os.environ.copy()
    environment.update({"APPDATA": str(appdata), "TEMP": str(temp), "TMP": str(temp)})
    os.environ.setdefault(godot_monitored_launch.MIN_AVAILABLE_GIB_ENV, MIN_AVAILABLE_GIB)

    data = scenario(rise_tau_s, extra_overrides)
    scenario_path = out_dir / "scenario.json"
    scenario_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    token = secrets.token_hex(16)
    command = [
        str(godot), "--headless", "--path", str(project),
        "--log-file", str(out_dir / "godot.log"),
        run_scenario._RUNNER_SCENE, "--",
        f"--run-scenario={scenario_path}", f"--out-dir={out_dir}", f"--run-token={token}",
        "--co-inventory-trace", "--fuel-object-state-snapshot", "--fuel-source-ledger",
        batch.LEDGER_ARG,
    ]
    result = godot_monitored_launch.run(command, TIMEOUT_S, environment)
    (out_dir / "monitor.stdout.log").write_text(result.stdout, encoding="utf-8")
    (out_dir / "monitor.stderr.log").write_text(result.stderr, encoding="utf-8")
    if result.health is not None:
        (out_dir / "monitor.health.json").write_text(json.dumps(result.health, indent=2), encoding="utf-8")

    errors = [*result.preexisting, *result.faults]
    if result.launched:
        if result.returncode != 0:
            errors.append(f"Godot exit {result.returncode}")
        if f"RUN_SCENARIO PASS token={token}" not in result.stdout + result.stderr:
            errors.append("fresh completion marker missing")
        errors.extend(run_scenario._validate_outputs(
            out_dir, run_token=token, scenario=scenario_path, expected_duration_s=float(data["duration_s"]),
        ))
    summary = {
        "label": label, "case": CASE, "project": str(project), OVERRIDE: rise_tau_s,
        "engine_overrides": data["engine_overrides"], "launched": result.launched,
        "returncode": result.returncode, "errors": errors, "out_dir": str(out_dir),
    }
    (out_root / label / "run.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2), flush=True)
    return 1 if errors or not result.launched else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--label", required=True, help="sub-directory of --out for this run")
    parser.add_argument("--rise-tau-s", type=float, required=True, help=f"value of {OVERRIDE} (engine default 6)")
    parser.add_argument("--out", type=Path, required=True, help="evidence directory")
    parser.add_argument("--project", type=Path, default=ROOT, help="Godot project to run (default: this worktree)")
    parser.add_argument("--override", action="append", default=[], metavar="KEY=NUMBER",
                        help="further diagnostic engine override of the scenario copy (repeatable)")
    args = parser.parse_args()
    extra = {key: float(value) for key, value in (item.split("=", 1) for item in args.override)}
    try:
        raise SystemExit(run(args.label, args.rise_tau_s, args.out.resolve(), args.project.resolve(), extra))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 RISE TAU DIAGNOSTIC FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
