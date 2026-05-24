"""
tests/test_guardrails.py — Unit tests for validation guardrail scripts.

Covers:
  - gap_inventory_check.extract_documented_gap_count()
  - gap_inventory_check.main() exit codes
  - phase2e_preflight._compute_margin()
  - phase2e_preflight.main() exit codes
  - validation_guardrails.main() exit codes

No external dependencies — stdlib only (unittest, tempfile, json, etc.).
No Godot, no simulation suite, no modification of real reference_checks.json.
"""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

# ---------------------------------------------------------------------------
# Resolve scripts/simulation and add to sys.path so imports work both when
# running from the repo root and from the tests/ directory.
# ---------------------------------------------------------------------------
_SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts" / "simulation"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))
_TEST_TMP_ROOT = Path(__file__).resolve().parent.parent / ".tmp_guardrail_tests"
_TEST_TMP_ROOT.mkdir(parents=True, exist_ok=True)

import gap_inventory_check       # noqa: E402
import phase2e_preflight         # noqa: E402
import validation_guardrails     # noqa: E402


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _run_main(fn, argv: list) -> tuple:
    """
    Run a main() function with the given sys.argv, capturing stdout.
    Returns (exit_code: int, stdout: str).
    """
    old_argv = sys.argv[:]
    sys.argv = ["test"] + list(argv)
    buf = io.StringIO()
    rc = 1
    try:
        with contextlib.redirect_stdout(buf):
            rc = fn()
    except SystemExit as exc:
        rc = exc.code if isinstance(exc.code, int) else 1
    finally:
        sys.argv = old_argv
    return rc, buf.getvalue()


@contextlib.contextmanager
def _temporary_directory():
    """
    Use a workspace-local temp root. Some Windows sandbox/OneDrive setups deny
    cleanup/delete in temp folders, so tests overwrite stable fixture files and
    leave the directory in place.
    """
    _TEST_TMP_ROOT.mkdir(parents=True, exist_ok=True)
    yield str(_TEST_TMP_ROOT)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

INVENTORY_TEMPLATE = """\
# GAPS_INVENTORY — SimuFire

> **Estado validación**: 289/289 PASS required, {n} gaps non-gating

## Lista de gaps
"""

# Must match SENTINELS list in phase2e_preflight.py (order irrelevant for tests)
SENTINEL_NAMES = [
    "g4_gie_delayed_entry_hazard_time_room_1_fed_above_0_1_s",
    "g4_gie_delayed_entry_hazard_time_room_1_co_upper_above_1200_s",
    "g4_gie_delayed_entry_hazard_room_1_peak_co_upper_ppm",
    "v3_hallway_fed_exposure_time_room_1_fed_above_0_1_s",
    "v3_hallway_fed_exposure_room_1_max_fed",
    "victim_fed_incapacitation_victim_v0_final_fed",
    "victim_fed_incapacitation_peak_co_ppm_global",
]


def _sentinel_check(name: str, pass_: bool = True) -> dict:
    """A required check fixture for sentinel tests."""
    return {
        "name": name,
        "actual": 1.0,
        "expected": None,
        "tolerance": None,
        "minimum": 0.5,
        "maximum": None,
        "required": True,
        "pass": pass_,
        "note": "",
    }


def _gap_check(name: str) -> dict:
    """A non-required failing check fixture (counts as a known gap)."""
    return {
        "name": name,
        "actual": 0.0,
        "expected": 1.0,
        "tolerance": 0.1,
        "minimum": None,
        "maximum": None,
        "required": False,
        "pass": False,
        "note": "gap",
    }


def _json_data(
    all_required_pass: bool = True,
    required_count: int = 0,
    failed_required_count: int = 0,
    known_gap_count: int = 0,
    checks: list = None,
) -> dict:
    return {
        "all_required_pass": all_required_pass,
        "required_count": required_count,
        "failed_required_count": failed_required_count,
        "known_gap_count": known_gap_count,
        "checks": checks or [],
    }


def _write_json(directory: str, data: dict) -> Path:
    p = Path(directory) / "reference_checks.json"
    p.write_text(json.dumps(data), encoding="utf-8")
    return p


def _write_inventory(directory: str, n: int) -> Path:
    p = Path(directory) / "GAPS_INVENTORY.md"
    p.write_text(INVENTORY_TEMPLATE.format(n=n), encoding="utf-8")
    return p


# ---------------------------------------------------------------------------
# 1. extract_documented_gap_count
# ---------------------------------------------------------------------------

class TestExtractDocumentedGapCount(unittest.TestCase):

    def test_parses_standard_header(self):
        """Extracts the correct integer from the expected markdown pattern."""
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".md", delete=False, encoding="utf-8",
            dir=_TEST_TMP_ROOT
        ) as f:
            f.write(INVENTORY_TEMPLATE.format(n=73))
            fname = f.name
        try:
            result = gap_inventory_check.extract_documented_gap_count(Path(fname))
            self.assertEqual(result, 73)
        finally:
            try:
                os.unlink(fname)
            except PermissionError:
                pass

    def test_returns_none_when_pattern_absent(self):
        """Returns None when the file contains no 'N gaps non-gating' line."""
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".md", delete=False, encoding="utf-8",
            dir=_TEST_TMP_ROOT
        ) as f:
            f.write("# No gap count here\n")
            fname = f.name
        try:
            result = gap_inventory_check.extract_documented_gap_count(Path(fname))
            self.assertIsNone(result)
        finally:
            try:
                os.unlink(fname)
            except PermissionError:
                pass


# ---------------------------------------------------------------------------
# 2. gap_inventory_check.main()
# ---------------------------------------------------------------------------

class TestGapInventoryCheckMain(unittest.TestCase):

    def test_exit0_counts_match(self):
        """exit 0 when documented gap count equals JSON and all required pass."""
        with _temporary_directory() as tmp:
            data = _json_data(
                all_required_pass=True,
                known_gap_count=2,
                checks=[_gap_check("gap_a"), _gap_check("gap_b")],
            )
            jp = _write_json(tmp, data)
            ip = _write_inventory(tmp, 2)
            rc, _ = _run_main(
                gap_inventory_check.main,
                ["--json", str(jp), "--inventory", str(ip)],
            )
            self.assertEqual(rc, 0)

    def test_exit1_inventory_mismatch(self):
        """exit 1 when GAPS_INVENTORY.md documents a different count than JSON."""
        with _temporary_directory() as tmp:
            data = _json_data(
                all_required_pass=True,
                known_gap_count=2,
                checks=[_gap_check("gap_a"), _gap_check("gap_b")],
            )
            jp = _write_json(tmp, data)
            ip = _write_inventory(tmp, 5)   # inventory says 5, JSON says 2
            rc, _ = _run_main(
                gap_inventory_check.main,
                ["--json", str(jp), "--inventory", str(ip)],
            )
            self.assertEqual(rc, 1)

    def test_exit1_required_failure(self):
        """exit 1 when JSON reports all_required_pass=False."""
        with _temporary_directory() as tmp:
            data = _json_data(
                all_required_pass=False,
                failed_required_count=1,
                known_gap_count=2,
                checks=[_gap_check("gap_a"), _gap_check("gap_b")],
            )
            jp = _write_json(tmp, data)
            ip = _write_inventory(tmp, 2)
            rc, _ = _run_main(
                gap_inventory_check.main,
                ["--json", str(jp), "--inventory", str(ip)],
            )
            self.assertEqual(rc, 1)


# ---------------------------------------------------------------------------
# 3. _compute_margin
# ---------------------------------------------------------------------------

class TestComputeMargin(unittest.TestCase):

    def test_minimum_only(self):
        """margin = actual - minimum for min-only checks."""
        c = {
            "actual": 1.5, "expected": None, "tolerance": None,
            "minimum": 0.5, "maximum": None,
        }
        margin, desc = phase2e_preflight._compute_margin(c)
        self.assertAlmostEqual(margin, 1.0)
        self.assertIn("min=0.5", desc)

    def test_tolerance_check(self):
        """margin = tolerance - |actual - expected| for ±tolerance checks."""
        c = {
            "actual": 9.0, "expected": 10.0, "tolerance": 2.0,
            "minimum": None, "maximum": None,
        }
        margin, desc = phase2e_preflight._compute_margin(c)
        self.assertAlmostEqual(margin, 1.0)   # 2.0 - |9.0 - 10.0| = 1.0
        self.assertIn("exp=10.0", desc)

    def test_maximum_only(self):
        """margin = maximum - actual for max-only checks."""
        c = {
            "actual": 3.0, "expected": None, "tolerance": None,
            "minimum": None, "maximum": 5.0,
        }
        margin, desc = phase2e_preflight._compute_margin(c)
        self.assertAlmostEqual(margin, 2.0)   # 5.0 - 3.0
        self.assertIn("max=5.0", desc)


# ---------------------------------------------------------------------------
# 4. phase2e_preflight.main()
# ---------------------------------------------------------------------------

class TestPhase2EPreflightMain(unittest.TestCase):

    def test_exit0_all_sentinels_pass(self):
        """exit 0 when all 7 sentinels are present and PASS."""
        with _temporary_directory() as tmp:
            data = _json_data(
                checks=[_sentinel_check(n) for n in SENTINEL_NAMES],
            )
            jp = _write_json(tmp, data)
            rc, _ = _run_main(phase2e_preflight.main, ["--json", str(jp)])
            self.assertEqual(rc, 0)

    def test_exit1_one_sentinel_fails(self):
        """exit 1 when one sentinel has pass=False."""
        with _temporary_directory() as tmp:
            checks = [_sentinel_check(n) for n in SENTINEL_NAMES]
            checks[0]["pass"] = False
            data = _json_data(checks=checks)
            jp = _write_json(tmp, data)
            rc, _ = _run_main(phase2e_preflight.main, ["--json", str(jp)])
            self.assertEqual(rc, 1)

    def test_exit1_sentinel_missing(self):
        """exit 1 when a sentinel name is absent from the JSON checks list."""
        with _temporary_directory() as tmp:
            # All sentinels except the first
            data = _json_data(
                checks=[_sentinel_check(n) for n in SENTINEL_NAMES[1:]],
            )
            jp = _write_json(tmp, data)
            rc, _ = _run_main(phase2e_preflight.main, ["--json", str(jp)])
            self.assertEqual(rc, 1)


# ---------------------------------------------------------------------------
# 5. validation_guardrails.main()
# ---------------------------------------------------------------------------

class TestValidationGuardrails(unittest.TestCase):

    def test_exit0_real_json(self):
        """exit 0 using the real reference_checks.json (integration smoke test)."""
        real_json = (
            Path(__file__).resolve().parent.parent
            / "sim/validation/reports/reference_checks.json"
        )
        if not real_json.exists():
            self.skipTest("reference_checks.json not available in this environment")
        rc, out = _run_main(validation_guardrails.main, ["--json", str(real_json)])
        self.assertEqual(rc, 0)
        self.assertIn("ALL GUARDRAILS PASS", out)

    def test_exit1_when_required_checks_fail(self):
        """exit 1 when JSON reports all_required_pass=False."""
        with _temporary_directory() as tmp:
            data = _json_data(
                all_required_pass=False,
                failed_required_count=1,
                known_gap_count=0,
                checks=[_sentinel_check(n) for n in SENTINEL_NAMES],
            )
            jp = _write_json(tmp, data)
            rc, _ = _run_main(validation_guardrails.main, ["--json", str(jp)])
            self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main()
