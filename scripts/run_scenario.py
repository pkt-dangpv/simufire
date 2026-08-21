"""Run a SimuFire scenario JSON headlessly and export technical artifacts.

Usage:
    python scripts/run_scenario.py sim/validation/cases/victim_fed_incapacitation.json
    python scripts/run_scenario.py scenario.json --duration 120 --out-dir runs/smoke
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_GODOT_CANDIDATES = [
    Path("C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe"),
]
_RUNNER_SCENE = "res://tools/run_scenario_headless.tscn"
_FATAL_GODOT_PATTERNS = (
    "SCRIPT ERROR:",
    "Parse Error:",
    "Failed to load script",
    "Can't load the script",
    "doesn't inherit from SceneTree or MainLoop",
)
# F3.3v3h2.5h: selectable capture modes, kept in step with
# Phase3ZoneMassSystem.CAPTURE_SELECTABLE_FAILURE_MODES. Validated here so an
# unknown value fails before Godot is launched rather than after a full run.
_CAPTURE_FAILURE_MODES = frozenset(
    {"iteration_cap", "damping_exhausted", "singular_jacobian",
     "counterflow_violation", "iteration_cap_after_rescue"}
)

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
        "--phase3-runtime-ownership-ledger",
        action="store_true",
        help="Enable the passive H3.1 runtime ownership ledger.",
    )
    parser.add_argument(
        "--phase3-physical-owner-ledger",
        action="store_true",
        help="Enable the passive H3.2-S0b thermal physical-owner events.",
    )
    parser.add_argument(
        "--phase3-co2-zonal-transport-consistency",
        action="store_true",
        help=(
            "H3.2-S0d5b experiment: cap the declared lower-to-lower CO2 "
            "transfers at the source's real lower stock. Changes physics; "
            "never used by official cases."
        ),
    )
    parser.add_argument(
        "--phase3-co-first-violation-trace",
        action="store_true",
        help=(
            "H3.2-S0d5a2 diagnostic: trace the first valid->invalid crossing of "
            "co_upper <= co_kg per room, per writer. No physics or CSV change."
        ),
    )
    parser.add_argument(
        "--phase3-co-zonal-transport-consistency",
        action="store_true",
        help=(
            "H3.2-S0d5a experiment: debit CO's upper stock together with its "
            "bulk stock in immediate and delayed transport. Changes physics; "
            "never used by official cases."
        ),
    )
    parser.add_argument(
        "--phase3-species-attribution-diagnostics",
        action="store_true",
        help=(
            "H3.2-S0d3 passive measurement: report whether the aggregate "
            "species/O2 clamp binds. No physics or CSV change."
        ),
    )
    parser.add_argument(
        "--phase3-zone-transition-diagnostics",
        action="store_true",
        help=(
            "H3.2b1b persistent zone transition ledger: births, deaths, stable "
            "presence and stable absence measured across observation boundaries "
            "rather than within a single projection call, under four presence "
            "predicates at once. Opt-in summary block only; no CSV column."
        ),
    )
    parser.add_argument(
        "--phase3-residual-projection-shadow",
        action="store_true",
        help=(
            "H3.2b3 read-only shadow comparison: evaluates the H3.2b2 pure "
            "primitive from each projection call's pre-state and compares it "
            "against the legacy post-state. The primitive's output is never "
            "applied, never written to a room and never used as a fallback. "
            "Adds an opt-in summary block only; no CSV column."
        ),
    )
    parser.add_argument(
        "--phase3-projection-causal-diagnostics",
        action="store_true",
        help=(
            "H3.2b1 passive causal accumulator for two-zone projection: "
            "cumulative call counts per cause, signed and gross mass/energy "
            "corrections, thermal cap requested/accepted/rejected, both "
            "residuals and a completeness mask. No physics or CSV change."
        ),
    )
    parser.add_argument(
        "--phase3-o2-attribution-diagnostics",
        action="store_true",
        help=(
            "H3.2-S0d6 passive measurement: report requested vs accepted O2 per "
            "owner and zone at each OxygenExchangeSystem mutation site, with an "
            "explicit reason code when kg attribution is not derivable. "
            "No physics or CSV change."
        ),
    )
    parser.add_argument(
        "--phase3-suppression-lower-energy-sink",
        action="store_true",
        help=(
            "H3.2-S0d2 experiment: apply the suppression lower-zone cooling to "
            "lower_energy_kj under two-zone instead of a temperature the "
            "projection discards. Changes physics; never used by official cases."
        ),
    )
    parser.add_argument(
        "--phase3-canonical-shadow",
        action="store_true",
        help="Enable the passive F3.0 canonical two-zone shadow transaction.",
    )
    parser.add_argument(
        "--phase3-canonical-exterior-shadow",
        action="store_true",
        help="Enable passive F3.2a canonical pressure/leakage exterior bundles.",
    )
    parser.add_argument(
        "--phase3-canonical-persistence-shadow",
        action="store_true",
        help="Enable passive F3.2b0 persistent canonical step continuity.",
    )
    parser.add_argument(
        "--phase3-canonical-combustion-shadow",
        action="store_true",
        help="Enable passive F3.2b1 closed canonical combustion/plume transactions.",
    )
    parser.add_argument(
        "--phase3-canonical-fire-proposal-shadow",
        action="store_true",
        help="Enable passive F3.3v1 pre-throttle canonical fire proposal telemetry.",
    )
    parser.add_argument(
        "--phase3-canonical-unfiltered-fire-growth-shadow",
        action="store_true",
        help="Use the unfiltered canonical t-squared target inside the F3.3v stack.",
    )
    parser.add_argument(
        "--phase3-canonical-fire-products-shadow",
        action="store_true",
        help="Enable passive F3.3v2 canonical fuel/species/energy products.",
    )
    parser.add_argument(
        "--phase3-canonical-fire-products-routing-shadow",
        action="store_true",
        help="Route F3.3v2 products through the persistent canonical shadow transaction.",
    )
    parser.add_argument(
        "--phase3-canonical-fuel-object-sync-shadow",
        action="store_true",
        help="Synchronize canonical aggregate fuel with a persistent per-object shadow ledger.",
    )
    parser.add_argument(
        "--phase3-canonical-pressure-relaxation-shadow",
        action="store_true",
        help="Enable passive F3.2b2 exterior pressure relaxation and lower-zone reseed.",
    )
    parser.add_argument(
        "--phase3-canonical-plume-shadow",
        action="store_true",
        help="Enable passive F3.2b3 plume evaluation from canonical pre-step geometry.",
    )
    parser.add_argument(
        "--phase3-canonical-interzone-heat-shadow",
        action="store_true",
        help="Enable passive F3.2b5a inter-zone heat transfer from canonical state.",
    )
    parser.add_argument(
        "--phase3-canonical-wall-ambient-shadow",
        action="store_true",
        help="Enable passive F3.2b5b canonical wall/ambient energy ownership.",
    )
    parser.add_argument(
        "--phase3-canonical-exterior-counterflow-shadow",
        action="store_true",
        help="Enable passive F3.2b6 bidirectional exterior-opening counterflow.",
    )
    parser.add_argument(
        "--phase3-canonical-post-opening-coupling-shadow",
        action="store_true",
        help="Enable passive F3.2b7 lower-O2 combustion coupling during exterior counterflow.",
    )
    parser.add_argument(
        "--phase3-canonical-interior-opening-shadow",
        action="store_true",
        help="Enable passive F3.3a atomic horizontal interior-opening transport.",
    )
    parser.add_argument(
        "--phase3-canonical-interior-pressure-shadow",
        action="store_true",
        help="Enable passive F3.3b signed canonical interior-pressure transport.",
    )
    parser.add_argument(
        "--phase3-canonical-fixed-gross-pressure-skew-shadow",
        action="store_true",
        help="Enable passive F3.3v3f1 fixed-gross opening/pressure preview.",
    )
    parser.add_argument(
        "--phase3-canonical-fixed-gross-pressure-network-shadow",
        action="store_true",
        help="Enable passive F3.3v3g2 interior pressure-network preview.",
    )
    parser.add_argument(
        "--phase3-coupled-pressure-solver-shadow",
        action="store_true",
        help="Enable the passive F3.3v3h2 coupled pressure solver preview.",
    )
    parser.add_argument(
        "--phase3-coupled-interior-bundle-shadow",
        action="store_true",
        help="Enable the passive H3.2-M coupled atomic-bundle shadow.",
    )
    parser.add_argument(
        "--phase3-coupled-pressure-solver-capture",
        default="",
        help=(
            "F3.3v3h2.5a diagnostic: write the first failing coupled solve to "
            "this path. Empty disables capture entirely."
        ),
    )
    parser.add_argument(
        "--phase3-coupled-pressure-solver-capture-mode",
        default="",
        help=(
            "F3.3v3h2.5h diagnostic: only capture this failure mode, e.g. "
            "iteration_cap. Empty captures the first failure of any kind."
        ),
    )
    parser.add_argument(
        "--phase3-cfast-buoyancy-destination-shadow",
        action="store_true",
        help="Enable experimental F3.3n CFAST flogo receiver routing in shadow.",
    )
    parser.add_argument(
        "--phase3-enthalpy-residence-diagnostics",
        action="store_true",
        help="Enable passive F3.3c1 cumulative accepted-route enthalpy ledger.",
    )
    parser.add_argument(
        "--phase3-mass-residence-diagnostics",
        action="store_true",
        help="Enable passive F3.3d1 cumulative accepted-route mass ledger.",
    )
    parser.add_argument(
        "--phase3-connection-residence-diagnostics",
        action="store_true",
        help="Export passive F3.3k accepted mass/enthalpy totals per connection.",
    )
    return parser.parse_args(argv)


def _load_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _load_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _fatal_godot_errors(output: str) -> list[str]:
    return [
        pattern
        for pattern in _FATAL_GODOT_PATTERNS
        if pattern.casefold() in output.casefold()
    ]


def _same_path(left: object, right: Path) -> bool:
    try:
        return Path(str(left)).resolve() == right.resolve()
    except (OSError, TypeError, ValueError):
        return False


def _validate_outputs(
    out_dir: Path,
    *,
    run_token: str,
    scenario: Path,
    expected_duration_s: float | None,
) -> list[str]:
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
    else:
        if manifest.get("schema_version") != "simufire_run_scenario_manifest_v1":
            failures.append("run_manifest.json schema_version mismatch")
        if manifest.get("status") != "completed":
            failures.append("run_manifest.json is not a completed run")
        if manifest.get("run_token") != run_token:
            failures.append("run_manifest.json is stale or belongs to another run")
        if manifest.get("runner_entrypoint") != _RUNNER_SCENE:
            failures.append("run_manifest.json runner_entrypoint mismatch")
        if not _same_path(manifest.get("scenario_path"), scenario):
            failures.append("run_manifest.json scenario_path mismatch")
        try:
            manifest_duration = float(manifest.get("duration_s"))
            sim_time_s = float(manifest.get("sim_time_s"))
        except (TypeError, ValueError):
            failures.append("run_manifest.json has invalid duration/sim_time")
        else:
            if expected_duration_s is not None and abs(
                manifest_duration - expected_duration_s
            ) > 1e-9:
                failures.append("run_manifest.json duration_s mismatch")
            if sim_time_s + 1e-9 < manifest_duration:
                failures.append(
                    "run_manifest.json records a truncated simulation "
                    f"({sim_time_s} < {manifest_duration})"
                )

    return failures


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    scenario = Path(args.scenario).expanduser()
    if not scenario.is_absolute():
        scenario = (_REPO_ROOT / scenario).resolve()
    if not scenario.exists():
        print(f"ERROR: scenario not found: {scenario}", file=sys.stderr)
        return 1
    scenario_data = _load_json(scenario)
    if scenario_data is None:
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
    run_token = secrets.token_hex(16)
    expected_duration_s = (
        args.duration
        if args.duration is not None
        else (
            float(scenario_data["duration_s"])
            if "duration_s" in scenario_data
            else None
        )
    )

    cmd = [
        str(godot),
        "--headless",
        "--path",
        str(_REPO_ROOT),
        "--log-file",
        str(out_dir / "godot.log"),
        _RUNNER_SCENE,
        "--",
        f"--run-scenario={scenario}",
        f"--out-dir={out_dir}",
        f"--run-token={run_token}",
    ]
    if args.duration is not None:
        cmd.append(f"--duration={args.duration}")
    if args.step is not None:
        cmd.append(f"--step={args.step}")
    if args.no_ignite:
        cmd.append("--no-ignite")
    if args.phase3_zone_diagnostics:
        cmd.append("--phase3-zone-diagnostics")
    if args.phase3_runtime_ownership_ledger:
        cmd.append("--phase3-runtime-ownership-ledger")
    if args.phase3_physical_owner_ledger:
        cmd.append("--phase3-physical-owner-ledger")
    if args.phase3_suppression_lower_energy_sink:
        cmd.append("--phase3-suppression-lower-energy-sink")
    if args.phase3_species_attribution_diagnostics:
        cmd.append("--phase3-species-attribution-diagnostics")
    if args.phase3_o2_attribution_diagnostics:
        cmd.append("--phase3-o2-attribution-diagnostics")
    if args.phase3_projection_causal_diagnostics:
        cmd.append("--phase3-projection-causal-diagnostics")
    if args.phase3_residual_projection_shadow:
        cmd.append("--phase3-residual-projection-shadow")
    if args.phase3_zone_transition_diagnostics:
        cmd.append("--phase3-zone-transition-diagnostics")
    if args.phase3_co_zonal_transport_consistency:
        cmd.append("--phase3-co-zonal-transport-consistency")
    if args.phase3_co_first_violation_trace:
        cmd.append("--phase3-co-first-violation-trace")
    if args.phase3_co2_zonal_transport_consistency:
        cmd.append("--phase3-co2-zonal-transport-consistency")
    if args.phase3_canonical_shadow:
        cmd.append("--phase3-canonical-shadow")
    if args.phase3_canonical_exterior_shadow:
        if not args.phase3_canonical_shadow:
            cmd.append("--phase3-canonical-shadow")
        cmd.append("--phase3-canonical-exterior-shadow")
    if args.phase3_canonical_persistence_shadow:
        if not args.phase3_canonical_shadow:
            cmd.append("--phase3-canonical-shadow")
        if not args.phase3_canonical_exterior_shadow:
            cmd.append("--phase3-canonical-exterior-shadow")
        cmd.append("--phase3-canonical-persistence-shadow")
    if args.phase3_canonical_combustion_shadow:
        if "--phase3-canonical-shadow" not in cmd:
            cmd.append("--phase3-canonical-shadow")
        if "--phase3-canonical-exterior-shadow" not in cmd:
            cmd.append("--phase3-canonical-exterior-shadow")
        if "--phase3-canonical-persistence-shadow" not in cmd:
            cmd.append("--phase3-canonical-persistence-shadow")
        cmd.append("--phase3-canonical-combustion-shadow")
    if args.phase3_canonical_fire_proposal_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-fire-proposal-shadow")
    if args.phase3_canonical_unfiltered_fire_growth_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-fire-proposal-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-unfiltered-fire-growth-shadow")
    if args.phase3_canonical_fire_products_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-fire-proposal-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-fire-products-shadow")
    if args.phase3_canonical_fire_products_routing_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-fire-proposal-shadow",
            "--phase3-canonical-fire-products-shadow",
            "--phase3-canonical-plume-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-fire-products-routing-shadow")
    if args.phase3_canonical_fuel_object_sync_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-fire-proposal-shadow",
            "--phase3-canonical-fire-products-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-fire-products-routing-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-fuel-object-sync-shadow")
    if args.phase3_canonical_pressure_relaxation_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-pressure-relaxation-shadow")
    if args.phase3_canonical_plume_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-plume-shadow")
    if args.phase3_canonical_interzone_heat_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-interzone-heat-shadow")
    if args.phase3_canonical_wall_ambient_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-wall-ambient-shadow")
    if args.phase3_canonical_exterior_counterflow_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-exterior-counterflow-shadow")
    if args.phase3_canonical_post_opening_coupling_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-post-opening-coupling-shadow")
    if args.phase3_canonical_interior_opening_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-interior-opening-shadow")
    if args.phase3_canonical_interior_pressure_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
            "--phase3-canonical-interior-opening-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-interior-pressure-shadow")
    if args.phase3_canonical_fixed_gross_pressure_skew_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
            "--phase3-canonical-interior-opening-shadow",
            "--phase3-canonical-interior-pressure-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-fixed-gross-pressure-skew-shadow")
    if args.phase3_canonical_fixed_gross_pressure_network_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
            "--phase3-canonical-interior-opening-shadow",
            "--phase3-canonical-interior-pressure-shadow",
            "--phase3-canonical-fixed-gross-pressure-skew-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-canonical-fixed-gross-pressure-network-shadow")
    if args.phase3_coupled_pressure_solver_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
            "--phase3-canonical-interior-opening-shadow",
            "--phase3-canonical-interior-pressure-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-coupled-pressure-solver-shadow")
        if args.phase3_coupled_pressure_solver_capture:
            cmd.append(
                "--phase3-coupled-pressure-solver-capture="
                + args.phase3_coupled_pressure_solver_capture
            )
        if args.phase3_coupled_pressure_solver_capture_mode:
            mode = args.phase3_coupled_pressure_solver_capture_mode.strip().lower()
            if mode not in _CAPTURE_FAILURE_MODES:
                raise SystemExit(
                    "[run_scenario] error: "
                    "--phase3-coupled-pressure-solver-capture-mode: unknown "
                    f"mode {args.phase3_coupled_pressure_solver_capture_mode!r}; "
                    f"expected one of {sorted(_CAPTURE_FAILURE_MODES)} or omit "
                    "it to capture the first failure of any kind"
                )
            cmd.append("--phase3-coupled-pressure-solver-capture-mode=" + mode)
    if args.phase3_coupled_interior_bundle_shadow:
        if "--phase3-coupled-pressure-solver-shadow" not in cmd:
            for parent_flag in [
                "--phase3-canonical-shadow",
                "--phase3-canonical-exterior-shadow",
                "--phase3-canonical-persistence-shadow",
                "--phase3-canonical-combustion-shadow",
                "--phase3-canonical-pressure-relaxation-shadow",
                "--phase3-canonical-plume-shadow",
                "--phase3-canonical-interzone-heat-shadow",
                "--phase3-canonical-wall-ambient-shadow",
                "--phase3-canonical-exterior-counterflow-shadow",
                "--phase3-canonical-post-opening-coupling-shadow",
                "--phase3-canonical-interior-opening-shadow",
                "--phase3-canonical-interior-pressure-shadow",
                "--phase3-coupled-pressure-solver-shadow",
            ]:
                if parent_flag not in cmd:
                    cmd.append(parent_flag)
        cmd.append("--phase3-coupled-interior-bundle-shadow")
    if args.phase3_enthalpy_residence_diagnostics:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
            "--phase3-canonical-interior-opening-shadow",
            "--phase3-canonical-interior-pressure-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-enthalpy-residence-diagnostics")
    if args.phase3_mass_residence_diagnostics:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
            "--phase3-canonical-interior-opening-shadow",
            "--phase3-canonical-interior-pressure-shadow",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-mass-residence-diagnostics")
    if args.phase3_connection_residence_diagnostics:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
            "--phase3-canonical-interior-opening-shadow",
            "--phase3-canonical-interior-pressure-shadow",
            "--phase3-enthalpy-residence-diagnostics",
            "--phase3-mass-residence-diagnostics",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-connection-residence-diagnostics")
    if args.phase3_cfast_buoyancy_destination_shadow:
        for parent_flag in [
            "--phase3-canonical-shadow",
            "--phase3-canonical-exterior-shadow",
            "--phase3-canonical-persistence-shadow",
            "--phase3-canonical-combustion-shadow",
            "--phase3-canonical-pressure-relaxation-shadow",
            "--phase3-canonical-plume-shadow",
            "--phase3-canonical-interzone-heat-shadow",
            "--phase3-canonical-wall-ambient-shadow",
            "--phase3-canonical-exterior-counterflow-shadow",
            "--phase3-canonical-post-opening-coupling-shadow",
            "--phase3-canonical-interior-opening-shadow",
            "--phase3-canonical-interior-pressure-shadow",
            "--phase3-enthalpy-residence-diagnostics",
            "--phase3-mass-residence-diagnostics",
            "--phase3-connection-residence-diagnostics",
        ]:
            if parent_flag not in cmd:
                cmd.append(parent_flag)
        cmd.append("--phase3-cfast-buoyancy-destination-shadow")
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
        for pattern in _fatal_godot_errors(_load_text(out_dir / "godot.log")):
            print(f"  - fatal Godot error: {pattern}", file=sys.stderr)
        return 1

    if result.stdout:
        print(result.stdout.rstrip())
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)

    combined = (result.stdout or "") + (result.stderr or "")
    diagnostic_output = combined + _load_text(out_dir / "godot.log")
    expected_pass_marker = f"RUN_SCENARIO PASS token={run_token}"
    output_failures = _validate_outputs(
        out_dir,
        run_token=run_token,
        scenario=scenario,
        expected_duration_s=expected_duration_s,
    )
    fatal_errors = _fatal_godot_errors(diagnostic_output)
    if (
        result.returncode != 0
        or expected_pass_marker not in combined
        or fatal_errors
        or output_failures
    ):
        print("ERROR: run_scenario failed", file=sys.stderr)
        if result.returncode != 0:
            print(f"  - Godot exited with code {result.returncode}", file=sys.stderr)
        if expected_pass_marker not in combined:
            print("  - completion marker missing or stale", file=sys.stderr)
        for pattern in fatal_errors:
            print(f"  - fatal Godot error: {pattern}", file=sys.stderr)
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
