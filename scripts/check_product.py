"""check_product.py — Product/editor guardrails for SimuFire.

Runs the editor and product test suites without Godot or the scientific
simulation suite.  This script is intentionally SEPARATE from the scientific
validation pipeline:

  Product/editor checks:   python scripts/check_product.py        ← this file
  Scientific guardrails:   python scripts/simulation/validation_guardrails.py
  Scientific full suite:   python scripts/simulation/validate_reference_cases.py

The separation ensures that failures in editor tooling are visible and
tracked without polluting the scientific validation signal.

Exit codes:
    0 — all product tests PASS
    1 — one or more product tests FAIL
"""

import re
import subprocess
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent.parent

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
        ),
        (
            "Guardrail script unit tests",
            _REPO_ROOT / "tests" / "test_guardrails.py",
        ),
    ]

    rows = []
    for label, path in suites:
        rc, count, fails = _run_test(path)
        rows.append((label, rc, count, fails))

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
        print("    python tests/test_editor_scenarios.py")
        print("    python tests/test_guardrails.py")
    print("=" * W)
    print()

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
