"""check_product.py — Product/editor guardrails for SimuFire.

Runs editor/product tests plus lightweight Godot geometry checks. This script
is intentionally SEPARATE from the scientific validation pipeline:

  Product/editor checks:   python scripts/check_product.py        ← this file
  Scientific guardrails:   python scripts/simulation/validation_guardrails.py
  Scientific full suite:   python scripts/simulation/validate_reference_cases.py

The separation ensures that failures in editor tooling are visible and
tracked without polluting the scientific validation signal.

Exit codes:
    0 — all product tests PASS
    1 — one or more product tests FAIL
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_GODOT_CANDIDATES = [
    Path("C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe"),
]

# En Windows, piped stdout puede usar cp1252; reconfigure para UTF-8 si disponible
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _run_test(module_path: Path) -> tuple[int, int, int]:
    """
    Run a stdlib unittest module as a subprocess.
    Returns (exit_code, tests_run, failures+errors).
    """
    result = subprocess.run(
        [sys.executable, str(module_path)],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
    )
    combined = result.stderr + result.stdout
    tests_run = 0
    fails = 0
    for line in combined.splitlines():
        m = re.match(r"Ran (\d+) test", line)
        if m:
            tests_run = int(m.group(1))
        m = re.search(r"failures=(\d+)", line)
        if m:
            fails += int(m.group(1))
        m = re.search(r"errors=(\d+)", line)
        if m:
            fails += int(m.group(1))
    return result.returncode, tests_run, fails


def _find_godot() -> Path | None:
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


def _run_godot_scene(scene_path: str, success_token: str, timeout_s: int = 60) -> tuple[int, int, int, str]:
    """
    Run a small Godot headless product check scene.
    Returns (exit_code, checks_run, failures, diagnostic).
    """
    godot = _find_godot()
    if godot is None:
        return 1, 1, 1, "Godot not found. Set GODOT_EXE or add godot to PATH."

    result = subprocess.run(
        [
            str(godot),
            "--headless",
            "--path",
            str(_REPO_ROOT),
            scene_path,
        ],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
        timeout=timeout_s,
    )
    combined = (result.stdout or "") + (result.stderr or "")
    passed = result.returncode == 0 and success_token in combined
    diagnostic = "" if passed else combined.strip()
    return result.returncode, 1, 0 if passed else 1, diagnostic


def _run_godot_script(script_path: str, success_token: str, timeout_s: int = 60) -> tuple[int, int, int, str]:
    """
    Run a headless Godot SceneTree script (--script) product check.
    Returns (exit_code, checks_run, failures, diagnostic).
    """
    godot = _find_godot()
    if godot is None:
        return 1, 1, 1, "Godot not found. Set GODOT_EXE or add godot to PATH."

    result = subprocess.run(
        [
            str(godot),
            "--headless",
            "--path",
            str(_REPO_ROOT),
            "--script",
            script_path,
        ],
        capture_output=True,
        text=True,
        cwd=str(_REPO_ROOT),
        timeout=timeout_s,
    )
    combined = (result.stdout or "") + (result.stderr or "")
    passed = result.returncode == 0 and success_token in combined
    diagnostic = "" if passed else combined.strip()
    return result.returncode, 1, 0 if passed else 1, diagnostic


def _run_run_scenario_smoke() -> tuple[int, int, int, str]:
    """
    Exercise scripts/run_scenario.py end-to-end with a short headless run.
    Returns (exit_code, checks_run, failures, diagnostic).
    """
    scenario_path = _REPO_ROOT / "sim" / "validation" / "cases" / "victim_fed_incapacitation.json"
    with tempfile.TemporaryDirectory(prefix="simufire_run_scenario_") as tmpdir:
        result = subprocess.run(
            [
                sys.executable,
                str(_REPO_ROOT / "scripts" / "run_scenario.py"),
                str(scenario_path),
                "--duration",
                "5",
                "--out-dir",
                tmpdir,
                "--timeout",
                "90",
            ],
            capture_output=True,
            text=True,
            cwd=str(_REPO_ROOT),
            timeout=120,
        )
        combined = (result.stdout or "") + (result.stderr or "")
        passed = result.returncode == 0 and "[run_scenario] PASS" in combined
        diagnostic = "" if passed else combined.strip()
        return result.returncode, 1, 0 if passed else 1, diagnostic


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    W = 72
    print()
    print("=" * W)
    print("  Product Guardrails — SimuFire")
    print("  (Editor + product checks — independent of physics simulation)")
    print("=" * W)
    print()

    suites = [
        (
            "Editor/scenario JSON tests",
            _REPO_ROOT / "tests" / "test_editor_scenarios.py",
            "python tests/test_editor_scenarios.py",
        ),
        (
            "Guardrail script unit tests",
            _REPO_ROOT / "tests" / "test_guardrails.py",
            "python tests/test_guardrails.py",
        ),
        (
            "UI localization tests",
            _REPO_ROOT / "tests" / "test_ui_localization.py",
            "python tests/test_ui_localization.py",
        ),
        (
            "Godot editability tests",
            _REPO_ROOT / "tests" / "test_godot_editability.py",
            "python tests/test_godot_editability.py",
        ),
        (
            "ILV layer coherence unit tests",
            _REPO_ROOT / "tests" / "test_ilv_layer_coherence.py",
            "python tests/test_ilv_layer_coherence.py",
        ),
    ]

    rows = []
    diagnostics = []
    for label, path, command in suites:
        rc, count, fails = _run_test(path)
        rows.append((label, rc, count, fails))
        if rc != 0:
            diagnostics.append(command)

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_stairs_geometry.tscn",
        "STAIR GEOMETRY VALIDATION PASS",
    )
    rows.append(("Stair geometry Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot stair geometry: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_view_geometry_parity.tscn",
        "VIEW GEOMETRY PARITY VALIDATION PASS",
    )
    rows.append(("View geometry parity Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot view geometry parity: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_landing_surfaces.tscn",
        "LANDING SURFACES VALIDATION PASS",
    )
    rows.append(("Landing surfaces Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot landing surfaces: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_landing_stairs.tscn",
        "FP LANDING STAIRS VALIDATION PASS",
    )
    rows.append(("FP landing stairs Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP landing stairs: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_exterior_context.tscn",
        "FP EXTERIOR CONTEXT VALIDATION PASS",
    )
    rows.append(("FP exterior context Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP exterior context: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_technical_summary.tscn",
        "TECHNICAL SUMMARY VALIDATION PASS",
    )
    rows.append(("Technical summary Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot technical summary: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_furniture_runtime.tscn",
        "FURNITURE RUNTIME VALIDATION PASS",
    )
    rows.append(("Furniture runtime Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot furniture runtime: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_furniture_layout.tscn",
        "FURNITURE LAYOUT VALIDATION PASS",
    )
    rows.append(("Furniture layout Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot furniture layout: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_3d_door_opening_visuals.tscn",
        "3D DOOR OPENING VISUALS VALIDATION PASS",
    )
    rows.append(("3D door opening visuals Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot 3D door opening visuals: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_3d_technical_overlays.tscn",
        "3D TECHNICAL OVERLAYS VALIDATION PASS",
    )
    rows.append(("3D technical overlays Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot 3D technical overlays: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_3d_screenshot_export.tscn",
        "3D SCREENSHOT EXPORT VALIDATION PASS",
    )
    rows.append(("3D screenshot export Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot 3D screenshot export: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_runtime_template_schema.tscn",
        "RUNTIME TEMPLATE SCHEMA VALIDATION PASS",
    )
    rows.append(("Runtime template schema Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot runtime template schema: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_load_error_dialog.tscn",
        "EDITOR LOAD ERROR DIALOG VALIDATION PASS",
    )
    rows.append(("Editor load error dialog Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor load error dialog: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_main_menu_scene.gd",
        "[validate_main_menu] PASS",
    )
    rows.append(("Menu principal en escena Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot main menu scene: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_script(
        "res://tools/validate_editor_scene_complete.gd",
        "[validate_editor_scene] PASS",
    )
    rows.append(("UI del editor 100% en escena Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor scene complete: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_fire_visuals.tscn",
        "FP FIRE VISUALS VALIDATION PASS",
    )
    rows.append(("FP fire visuals Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP fire visuals: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_3d_smoke_opening_curtain.tscn",
        "3D SMOKE OPENING CURTAIN VALIDATION PASS",
        timeout_s=180,
    )
    rows.append(("3D smoke opening curtain Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot 3D smoke opening curtain: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_interstitial_seal.tscn",
        "FP INTERSTITIAL SEAL VALIDATION PASS",
    )
    rows.append(("FP interstitial seal Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP interstitial seal: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_party_walls.tscn",
        "FP PARTY WALLS VALIDATION PASS",
    )
    rows.append(("FP party walls Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP party walls: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_surface_shading.tscn",
        "FP SURFACE SHADING VALIDATION PASS",
    )
    rows.append(("FP surface shading Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP surface shading: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_smoke_lighting.tscn",
        "FP SMOKE LIGHTING VALIDATION PASS",
    )
    rows.append(("FP smoke lighting Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP smoke lighting: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_technical_hud.tscn",
        "FP TECHNICAL HUD VALIDATION PASS",
    )
    rows.append(("FP technical HUD Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP technical HUD: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_victim_states.tscn",
        "FP VICTIM STATES VALIDATION PASS",
    )
    rows.append(("FP victim states Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP victim states: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_player_start.tscn",
        "FP PLAYER START VALIDATION PASS",
    )
    rows.append(("FP player start Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP player start: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_detector_alarm.tscn",
        "FP DETECTOR ALARM VALIDATION PASS",
    )
    rows.append(("FP detector alarm Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP detector alarm: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_fp_stance_easing.tscn",
        "FP STANCE EASING VALIDATION PASS",
    )
    rows.append(("FP stance easing Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot FP stance easing: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_combustion_regime.tscn",
        "COMBUSTION REGIME VALIDATION PASS",
    )
    rows.append(("Combustion regime Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot combustion regime: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_godot_scene(
        "res://tools/validate_editor_to_sim_flow.tscn",
        "EDITOR TO SIM FLOW VALIDATION PASS",
    )
    rows.append(("Editor to sim flow Godot", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot editor to sim flow: " + (diagnostic or "failed"))

    rc, count, fails, diagnostic = _run_run_scenario_smoke()
    rows.append(("Run scenario reproducibility", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("run_scenario smoke: " + (diagnostic or "failed"))

    print(f"  {'Suite':<38}  {'Resultado':>12}")
    print(f"  {'-'*38}  {'-'*12}")
    for label, rc, count, fails in rows:
        if rc == 0:
            tag = f"{count}/{count} OK"
            icon = "OK"
        else:
            tag = f"FAIL ({fails} fallo(s))"
            icon = "!!"
        print(f"  {label:<38}  {tag:>12}  [{icon}]")

    all_ok = all(rc == 0 for _, rc, _, _ in rows)
    total = sum(c for _, _, c, _ in rows)

    print()
    print("-" * W)
    print()
    if all_ok:
        print(f"  ALL PRODUCT CHECKS PASS  ({total} tests)")
    else:
        print("  PRODUCT CHECK(S) FAILED:")
        for label, rc, _, fails in rows:
            if rc != 0:
                print(f"    - {label}: {fails} fallo(s)")
        print()
        print("  Para diagnóstico:")
        for diagnostic in diagnostics:
            print(f"    {diagnostic}")
    print("=" * W)
    print()

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
