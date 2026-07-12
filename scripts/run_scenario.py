"""Run a SimuFire scenario JSON headlessly and export technical artifacts.

Usage:
    python scripts/run_scenario.py sim/validation/cases/victim_fed_incapacitation.json
    python scripts/run_scenario.py scenario.json --duration 120 --out-dir runs/smoke
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_GODOT_CANDIDATES = [
    Path("C:/Users/dangp/Desktop/Godot_v4.6.3-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.6.3-stable_win64_console.exe"),
]
_RUNNER_SCENE = "res://tools/run_scenario_headless.tscn"

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def _find_godot(explicit_path: str | None = None) -> Path | None:
    if explicit_path:
        candidate = Path(explicit_path)
        if candidate.exists():
            return candidate

    env_path = os.environ.get("GODOT_EXE")
    if env_path:
        candidate = Path(env_path)
        if candidate.exists():
            return candidate

    for candidate in _GODOT_CANDIDATES:
        if candidate.exists():
            return candidate

    path_hit = shutil.which("godot")
    if path_hit:
        return Path(path_hit)
    return None


def _default_out_dir(scenario: Path) -> Path:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_stem = "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in scenario.stem)
    return _REPO_ROOT / "runs" / f"{safe_stem}_{stamp}"


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a SimuFire scenario JSON headlessly and export summary/events/logs.",
    )
    parser.add_argument("scenario", help="Path to a runtime template JSON or validation-case JSON.")
    parser.add_argument(
        "--out-dir",
        default=None,
        help="Output directory. Defaults to runs/<scenario>_<timestamp> under the repo.",
    )
    parser.add_argument("--duration", type=float, default=None, help="Override scenario duration in seconds.")
    parser.add_argument("--step", type=float, default=None, help="Override fixed run step in seconds.")
    parser.add_argument("--godot", default=None, help="Path to Godot console executable.")
    parser.add_argument("--timeout", type=int, default=120, help="Godot process timeout in seconds.")
    parser.add_argument("--no-ignite", action="store_true", help="Load the scenario without initial ignition.")
    parser.add_argument(
        "--phase3-zone-diagnostics",
        action="store_true",
        help="Enable passive Phase 3+ two-zone diagnostic columns in the CSV.",
    )
    parser.add_argument(
        "--phase3-canonical-shadow",
        action="store_true",
        help="Enable the passive F3.0 canonical two-zone shadow transaction.",
    )
    return parser.parse_args(argv)


def _load_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _validate_outputs(out_dir: Path) -> list[str]:
    failures: list[str] = []
    expected_files = [
        "summary.json",
        "events.json",
        "sim_log.txt",
        "sim_log.csv",
        "run_manifest.json",
    ]
    for filename in expected_files:
        if not (out_dir / filename).exists():
            failures.append(f"missing {filename}")

    summary = _load_json(out_dir / "summary.json")
    if not isinstance(summary, dict):
        failures.append("summary.json is not valid JSON")
    elif summary.get("schema_version") != "simufire_technical_summary_v1":
        failures.append("summary.json schema_version mismatch")

    manifest = _load_json(out_dir / "run_manifest.json")
    if not isinstance(manifest, dict):
        failures.append("run_manifest.json is not valid JSON")
    elif manifest.get("schema_version") != "simufire_run_scenario_manifest_v1":
        failures.append("run_manifest.json schema_version mismatch")

    return failures


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    scenario = Path(args.scenario).expanduser()
    if not scenario.is_absolute():
        scenario = (_REPO_ROOT / scenario).resolve()
    if not scenario.exists():
        print(f"ERROR: scenario not found: {scenario}", file=sys.stderr)
        return 1
    if _load_json(scenario) is None:
        print(f"ERROR: scenario is not valid JSON: {scenario}", file=sys.stderr)
        return 1

    godot = _find_godot(args.godot)
    if godot is None:
        print("ERROR: Godot not found. Set GODOT_EXE, use --godot, or add godot to PATH.", file=sys.stderr)
        return 1

    out_dir = Path(args.out_dir).expanduser() if args.out_dir else _default_out_dir(scenario)
    if not out_dir.is_absolute():
        out_dir = (_REPO_ROOT / out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        str(godot),
        "--headless",
        "--path",
        str(_REPO_ROOT),
        _RUNNER_SCENE,
        "--",
        f"--run-scenario={scenario}",
        f"--out-dir={out_dir}",
    ]
    if args.duration is not None:
        cmd.append(f"--duration={args.duration}")
    if args.step is not None:
        cmd.append(f"--step={args.step}")
    if args.no_ignite:
        cmd.append("--no-ignite")
    if args.phase3_zone_diagnostics:
        cmd.append("--phase3-zone-diagnostics")
    if args.phase3_canonical_shadow:
        cmd.append("--phase3-canonical-shadow")

    print(f"[run_scenario] scenario: {scenario}")
    print(f"[run_scenario] output:   {out_dir}")
    print(f"[run_scenario] godot:    {godot}")

    try:
        result = subprocess.run(
            cmd,
            cwd=str(_REPO_ROOT),
            capture_output=True,
            text=True,
            timeout=args.timeout,
        )
    except subprocess.TimeoutExpired:
        print(f"ERROR: Godot run timed out after {args.timeout}s", file=sys.stderr)
        return 1

    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)

    combined = (result.stdout or "") + (result.stderr or "")
    output_failures = _validate_outputs(out_dir)
    if result.returncode != 0 or "RUN_SCENARIO PASS" not in combined or output_failures:
        print("ERROR: run_scenario failed", file=sys.stderr)
        for failure in output_failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print("[run_scenario] PASS")
    print(f"[run_scenario] summary:  {out_dir / 'summary.json'}")
    print(f"[run_scenario] events:   {out_dir / 'events.json'}")
    print(f"[run_scenario] manifest: {out_dir / 'run_manifest.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
