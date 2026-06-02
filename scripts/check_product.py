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
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent
_GODOT_CANDIDATES = [
    Path("C:/Users/dangp/Desktop/Godot_v4.6.3-stable_win64_console.exe"),
    Path("F:/OneDrive/Escritorio/Godot_v4.6.3-stable_win64_console.exe"),
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
        "res://tools/validate_technical_summary.tscn",
        "TECHNICAL SUMMARY VALIDATION PASS",
    )
    rows.append(("Technical summary Godot headless", rc, count, fails))
    if rc != 0 or fails != 0:
        diagnostics.append("Godot technical summary: " + (diagnostic or "failed"))

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
