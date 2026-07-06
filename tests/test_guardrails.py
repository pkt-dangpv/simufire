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


def _failed_required_check(name: str) -> dict:
    """A required check fixture with pass=False."""
    return {
        "name": name,
        "actual": 0.0,
        "expected": 1.0,
        "tolerance": 0.1,
        "minimum": None,
        "maximum": None,
        "required": True,
        "pass": False,
        "note": "",
    }


# Any one of the documented VALID_GAP required failures.
A_VALID_GAP_NAME = sorted(gap_inventory_check.KNOWN_VALID_GAP_REQUIRED_FAILURES)[0]


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
        """exit 1 when JSON reports all_required_pass=False (corrupt: no failing
        required check present in checks — consistency guard)."""
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

    def test_exit1_unexpected_required_failure(self):
        """exit 1 when a required check fails and is NOT in the VALID_GAP allowlist."""
        with _temporary_directory() as tmp:
            data = _json_data(
                all_required_pass=False,
                failed_required_count=1,
                known_gap_count=0,
                checks=[_failed_required_check("brand_new_regression_check")],
            )
            jp = _write_json(tmp, data)
            ip = _write_inventory(tmp, 0)
            rc, out = _run_main(
                gap_inventory_check.main,
                ["--json", str(jp), "--inventory", str(ip)],
            )
            self.assertEqual(rc, 1)
            self.assertIn("brand_new_regression_check", out)

    def test_exit0_valid_gap_required_failures_allowed(self):
        """exit 0 when the only failing required checks are documented VALID_GAPs."""
        with _temporary_directory() as tmp:
            data = _json_data(
                all_required_pass=False,
                failed_required_count=1,
                known_gap_count=0,
                checks=[_failed_required_check(A_VALID_GAP_NAME)],
            )
            jp = _write_json(tmp, data)
            ip = _write_inventory(tmp, 0)
            rc, out = _run_main(
                gap_inventory_check.main,
                ["--json", str(jp), "--inventory", str(ip)],
            )
            self.assertEqual(rc, 0)
            self.assertIn("VALID_GAP", out)

    def test_exit1_valid_gap_plus_unexpected(self):
        """exit 1 when an unexpected required failure accompanies a VALID_GAP one."""
        with _temporary_directory() as tmp:
            data = _json_data(
                all_required_pass=False,
                failed_required_count=2,
                known_gap_count=0,
                checks=[
                    _failed_required_check(A_VALID_GAP_NAME),
                    _failed_required_check("brand_new_regression_check"),
                ],
            )
            jp = _write_json(tmp, data)
            ip = _write_inventory(tmp, 0)
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

    def test_exit0_non_required_sentinel_fails(self):
        """exit 0 when a failing sentinel is non-required (known gap, non-gating)."""
        with _temporary_directory() as tmp:
            checks = [_sentinel_check(n) for n in SENTINEL_NAMES]
            checks[0]["pass"] = False
            checks[0]["required"] = False
            data = _json_data(checks=checks)
            jp = _write_json(tmp, data)
            rc, out = _run_main(phase2e_preflight.main, ["--json", str(jp)])
            self.assertEqual(rc, 0)
            self.assertIn("GAP (non-gating)", out)


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

    def test_exit1_unexpected_required_failure(self):
        """exit 1 when a required check outside the VALID_GAP allowlist fails."""
        with _temporary_directory() as tmp:
            checks = [_sentinel_check(n) for n in SENTINEL_NAMES]
            checks.append(_failed_required_check("brand_new_regression_check"))
            data = _json_data(
                all_required_pass=False,
                failed_required_count=1,
                known_gap_count=0,
                checks=checks,
            )
            jp = _write_json(tmp, data)
            rc, out = _run_main(validation_guardrails.main, ["--json", str(jp)])
            self.assertEqual(rc, 1)
            self.assertIn("brand_new_regression_check", out)


# ---------------------------------------------------------------------------
# 6. Physics override linter (R1-3)
# ---------------------------------------------------------------------------

class TestPhysicsOverrideLinter(unittest.TestCase):

    def _write_case(self, root: Path, stem: str, overrides: dict) -> None:
        cases_dir = root / "sim" / "validation" / "cases"
        cases_dir.mkdir(parents=True, exist_ok=True)
        (cases_dir / f"{stem}.json").write_text(
            json.dumps({"engine_overrides": overrides}), encoding="utf-8"
        )

    def test_exit1_non_exempt_override(self):
        """rc 1 when a validation case carries a physics override with no exemption."""
        with _temporary_directory() as tmp:
            root = Path(tmp) / "lint_violation"
            self._write_case(root, "some_case", {"fire_hrr_global_multiplier": 2.0})
            rc, out = validation_guardrails._check_physics_overrides(root)
            self.assertEqual(rc, 1)
            self.assertIn("some_case", out)

    def test_exit0_exempted_override(self):
        """rc 0 when the only override present is a documented exemption."""
        with _temporary_directory() as tmp:
            root = Path(tmp) / "lint_exempt"
            self._write_case(
                root, "cfast_pool_fire_open", {"vent_bernoulli_flow_multiplier": 0.45}
            )
            rc, out = validation_guardrails._check_physics_overrides(root)
            self.assertEqual(rc, 0)
            self.assertIn("Exenciones activas", out)

    def test_exemption_is_key_scoped(self):
        """rc 1 when the exempted case carries a DIFFERENT physics override key."""
        with _temporary_directory() as tmp:
            root = Path(tmp) / "lint_scoped"
            self._write_case(
                root, "cfast_pool_fire_open", {"fire_hrr_global_multiplier": 2.0}
            )
            rc, _ = validation_guardrails._check_physics_overrides(root)
            self.assertEqual(rc, 1)


# ---------------------------------------------------------------------------
# 7. Reports freshness (R2-1)
# ---------------------------------------------------------------------------

import shutil      # noqa: E402
import subprocess  # noqa: E402

_GIT_AVAILABLE = shutil.which("git") is not None


@unittest.skipUnless(_GIT_AVAILABLE, "git not available")
class TestReportsFreshness(unittest.TestCase):

    def _git(self, root: Path, *args: str, date: str = "2026-01-01T00:00:00") -> None:
        env = dict(os.environ,
                   GIT_COMMITTER_DATE=date, GIT_AUTHOR_DATE=date,
                   GIT_CONFIG_NOSYSTEM="1")
        subprocess.run(["git", *args], cwd=root, capture_output=True,
                       text=True, env=env, check=True)

    def _make_repo(self, name: str) -> tuple[Path, Path, Path]:
        """Fresh git repo with engine .gd + reports json committed together."""
        root = _TEST_TMP_ROOT / name
        if root.exists():
            shutil.rmtree(root, ignore_errors=True)
        engine = root / "sim" / "core" / "engine.gd"
        engine.parent.mkdir(parents=True)
        engine.write_text("# engine v1\n", encoding="utf-8")
        report = root / "sim" / "validation" / "reports" / "reference_checks.json"
        report.parent.mkdir(parents=True)
        report.write_text("{}", encoding="utf-8")
        self._git(root, "init", "-q")
        self._git(root, "config", "user.email", "t@t")
        self._git(root, "config", "user.name", "t")
        self._git(root, "add", "-A")
        self._git(root, "commit", "-q", "-m", "init")
        return root, engine, report

    def test_rc0_engine_and_report_in_sync(self):
        root, _, report = self._make_repo("fresh_sync")
        rc, out = validation_guardrails._check_reports_freshness(root, report)
        self.assertEqual(rc, 0, out)

    def test_rc1_uncommitted_engine_change_without_regeneration(self):
        root, engine, report = self._make_repo("fresh_dirty")
        engine.write_text("# engine v2\n", encoding="utf-8")
        rc, out = validation_guardrails._check_reports_freshness(root, report)
        self.assertEqual(rc, 1)
        self.assertIn("sin commitear", out)

    def test_rc0_uncommitted_engine_change_with_regenerated_report(self):
        root, engine, report = self._make_repo("fresh_both")
        engine.write_text("# engine v2\n", encoding="utf-8")
        report.write_text('{"regenerated": true}', encoding="utf-8")
        rc, out = validation_guardrails._check_reports_freshness(root, report)
        self.assertEqual(rc, 0, out)

    def test_rc1_engine_committed_after_report(self):
        root, engine, report = self._make_repo("fresh_stale")
        engine.write_text("# engine v2\n", encoding="utf-8")
        self._git(root, "add", "-A")
        self._git(root, "commit", "-q", "-m", "engine change",
                  date="2026-01-02T00:00:00")
        rc, out = validation_guardrails._check_reports_freshness(root, report)
        self.assertEqual(rc, 1)
        self.assertIn("DESPUÉS", out)

    def test_rc0_skipped_outside_git_repo(self):
        root = _TEST_TMP_ROOT / "fresh_norepo"
        report = root / "sim" / "validation" / "reports" / "reference_checks.json"
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text("{}", encoding="utf-8")
        rc, out = validation_guardrails._check_reports_freshness(root, report)
        self.assertEqual(rc, 0)
        self.assertIn("omitido", out)


# ---------------------------------------------------------------------------
# 8. Metric plausibility (PHY-P1)
# ---------------------------------------------------------------------------

class TestMetricPlausibility(unittest.TestCase):

    def _write_report(self, root: Path, stem: str, metrics: dict) -> None:
        reports = root / "sim" / "validation" / "reports"
        reports.mkdir(parents=True, exist_ok=True)
        (reports / f"{stem}.json").write_text(
            json.dumps({"metrics": metrics}), encoding="utf-8"
        )

    def test_rc0_plausible_metrics(self):
        root = _TEST_TMP_ROOT / "plaus_clean"
        self._write_report(root, "some_case", {"room_0_peak_co2_ppm": 88000.0})
        rc, out = validation_guardrails._check_metric_plausibility(root)
        self.assertEqual(rc, 0, out)

    def test_rc1_new_impossible_ppm(self):
        """A ppm metric above 1e6 (100% of the mixture) in an unregistered case gates."""
        root = _TEST_TMP_ROOT / "plaus_new"
        self._write_report(root, "some_case", {"room_1_peak_co2_ppm": 1_500_000.0})
        rc, out = validation_guardrails._check_metric_plausibility(root)
        self.assertEqual(rc, 1)
        self.assertIn("some_case", out)

    def test_rc0_known_violation_reported_as_note(self):
        """Registered (stem, metric) pairs pass with an explicit debt note."""
        root = _TEST_TMP_ROOT / "plaus_known"
        self._write_report(
            root, "v3_hallway_fed_exposure", {"room_1_peak_co2_ppm": 1_099_282.0}
        )
        rc, out = validation_guardrails._check_metric_plausibility(root)
        self.assertEqual(rc, 0)
        self.assertIn("Violaciones conocidas", out)

    def test_rc1_known_stem_new_metric(self):
        """The allowlist is metric-scoped: a NEW metric in a known stem gates."""
        root = _TEST_TMP_ROOT / "plaus_scoped"
        self._write_report(
            root, "v3_hallway_fed_exposure",
            {"room_1_peak_co2_ppm": 1_099_282.0, "room_1_peak_co_ppm": 2_000_000.0},
        )
        rc, out = validation_guardrails._check_metric_plausibility(root)
        self.assertEqual(rc, 1)
        self.assertIn("room_1_peak_co_ppm", out)

    def test_tmp_reports_ignored(self):
        root = _TEST_TMP_ROOT / "plaus_tmp"
        self._write_report(root, "tmp_experiment", {"room_1_peak_co2_ppm": 9e9})
        rc, _ = validation_guardrails._check_metric_plausibility(root)
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
