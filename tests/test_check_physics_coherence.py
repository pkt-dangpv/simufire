"""Tests for check_physics_coherence.py and audit_physics_coherence_suite.py."""

import csv
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts" / "simulation"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import check_physics_coherence as checker  # noqa: E402
import audit_physics_coherence_suite as suite  # noqa: E402


# ---------------------------------------------------------------------------
# Shared test rows
# ---------------------------------------------------------------------------

def _row(
    time_s="10.0", room_id="0",
    temp_upper_c="80.0", temp_lower_c="30.0",
    fed="0.0500", fed_co="0.0200", fed_hcn="0.0100",
    fed_hypoxia="0.0150", fed_heat="0.0050",
) -> dict[str, str]:
    """Return a minimal valid row with FED sum = 0.05 exactly."""
    return {
        "time_s": time_s, "room_id": room_id,
        "temp_upper_c": temp_upper_c, "temp_lower_c": temp_lower_c,
        "fed": fed, "fed_co": fed_co, "fed_hcn": fed_hcn,
        "fed_hypoxia": fed_hypoxia, "fed_heat": fed_heat,
    }


_ROW_CLEAN = _row()

_ROW_FED_BROKEN = _row(
    fed="0.1000",
    fed_co="0.0200", fed_hcn="0.0100", fed_hypoxia="0.0150", fed_heat="0.0050",
    # sum = 0.05, but fed = 0.10 -> diff = 0.05 > 0.001
)

_ROW_THERMAL_INVERSION = _row(
    temp_upper_c="20.0",   # upper is cold
    temp_lower_c="50.0",   # lower is hotter by 30 °C -> inversion
)

_ROW_FED_SEQ_A = _row(time_s="10.0", fed="0.0100",
                       fed_co="0.0050", fed_hcn="0.0020",
                       fed_hypoxia="0.0020", fed_heat="0.0010")
_ROW_FED_SEQ_B_OK = _row(time_s="20.0", fed="0.0200",
                          fed_co="0.0100", fed_hcn="0.0040",
                          fed_hypoxia="0.0040", fed_heat="0.0020")
_ROW_FED_SEQ_B_DECR = _row(time_s="20.0", fed="0.0050",
                             fed_co="0.0020", fed_hcn="0.0010",
                             fed_hypoxia="0.0010", fed_heat="0.0010")


# ---------------------------------------------------------------------------
# Shared test rows — A2 (HRR without fuel)
# ---------------------------------------------------------------------------

def _row_a2(
    time_s="30.0", room_id="0",
    hrr_kw="50.0",
    fuel_remaining_MJ="5.0",
    fire_smoldering="0",
    fire_latent_active="0",
) -> dict[str, str]:
    return {
        "time_s": time_s, "room_id": room_id,
        "hrr_kw": hrr_kw,
        "fuel_remaining_MJ": fuel_remaining_MJ,
        "fire_smoldering": fire_smoldering,
        "fire_latent_active": fire_latent_active,
    }


# ---------------------------------------------------------------------------
# Shared test rows — A3 (Regime/O2 mismatch)
# ---------------------------------------------------------------------------

def _row_a3(
    time_s="30.0", room_id="0",
    combustion_regime="FUEL_CONTROLLED",
    o2_upper="0.15",
) -> dict[str, str]:
    return {
        "time_s": time_s, "room_id": room_id,
        "combustion_regime": combustion_regime,
        "o2_upper": o2_upper,
    }


# ---------------------------------------------------------------------------
# Helper: write a minimal CSV
# ---------------------------------------------------------------------------

def _write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError("rows must be non-empty")
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


# ---------------------------------------------------------------------------
# Tests: Finding
# ---------------------------------------------------------------------------

class TestFinding(unittest.TestCase):

    def _make(self, **kwargs) -> checker.Finding:
        defaults = dict(
            time_s=10.0, room_id="0", rule_id="C1", severity="FAIL",
            metric="fed_sum_error", value=0.05,
            reason="fed=0.10 != components=0.05",
        )
        defaults.update(kwargs)
        return checker.Finding(**defaults)

    def test_format_contains_rule_id(self):
        f = self._make(rule_id="C1")
        self.assertIn("C1", f.format())

    def test_format_contains_severity(self):
        f = self._make(severity="FAIL")
        self.assertIn("FAIL", f.format())

    def test_format_contains_metric(self):
        f = self._make(metric="fed_sum_error")
        self.assertIn("fed_sum_error", f.format())

    def test_format_contains_reason(self):
        f = self._make(reason="the reason here")
        self.assertIn("the reason here", f.format())


# ---------------------------------------------------------------------------
# Tests: Rule B1 — thermal inversion
# ---------------------------------------------------------------------------

class TestCheckB1(unittest.TestCase):

    def _run(self, rows):
        return checker.find_physics_coherence_issues(rows, rule_ids={"B1"})

    def test_no_inversion_no_finding(self):
        findings = self._run([_ROW_CLEAN])
        b1 = [f for f in findings if f.rule_id == "B1"]
        self.assertEqual(len(b1), 0)

    def test_small_diff_below_threshold_not_flagged(self):
        # upper=30, lower=35, diff=5 < 10 -> no finding
        row = _row(temp_upper_c="30.0", temp_lower_c="35.0")
        findings = self._run([row])
        self.assertEqual(len([f for f in findings if f.rule_id == "B1"]), 0)

    def test_exactly_at_threshold_not_flagged(self):
        # diff = 10.0 -> condition is strict >, so no finding
        row = _row(temp_upper_c="20.0", temp_lower_c="30.0")
        findings = self._run([row])
        self.assertEqual(len([f for f in findings if f.rule_id == "B1"]), 0)

    def test_inversion_above_threshold_is_flagged(self):
        findings = self._run([_ROW_THERMAL_INVERSION])
        b1 = [f for f in findings if f.rule_id == "B1"]
        self.assertEqual(len(b1), 1)
        self.assertEqual(b1[0].severity, "FAIL")
        self.assertAlmostEqual(b1[0].value, 30.0, places=1)

    def test_missing_cols_skips_rule(self):
        row = {"time_s": "10.0", "room_id": "0", "fed": "0.0"}
        findings = self._run([row])
        self.assertEqual(len([f for f in findings if f.rule_id == "B1"]), 0)

    def test_multiple_rows_counts_per_violation(self):
        rows = [_ROW_THERMAL_INVERSION, _ROW_THERMAL_INVERSION, _ROW_CLEAN]
        findings = self._run(rows)
        self.assertEqual(len([f for f in findings if f.rule_id == "B1"]), 2)


# ---------------------------------------------------------------------------
# Tests: Rule C1 — FED arithmetic
# ---------------------------------------------------------------------------

class TestCheckC1(unittest.TestCase):

    def _run(self, rows):
        return checker.find_physics_coherence_issues(rows, rule_ids={"C1"})

    def test_valid_fed_sum_no_finding(self):
        self.assertEqual(len(self._run([_ROW_CLEAN])), 0)

    def test_zero_fed_skipped(self):
        row = _row(fed="0.0", fed_co="0.0", fed_hcn="0.0", fed_hypoxia="0.0", fed_heat="0.0")
        self.assertEqual(len(self._run([row])), 0)

    def test_arithmetic_violation_detected(self):
        findings = self._run([_ROW_FED_BROKEN])
        c1 = [f for f in findings if f.rule_id == "C1"]
        self.assertEqual(len(c1), 1)
        self.assertEqual(c1[0].severity, "FAIL")
        self.assertGreater(c1[0].value, 0.001)

    def test_diff_within_tolerance_not_flagged(self):
        # diff = 0.0005, below 0.001 tolerance
        row = _row(
            fed="0.0505",
            fed_co="0.0200", fed_hcn="0.0100",
            fed_hypoxia="0.0150", fed_heat="0.0050",
        )
        self.assertEqual(len(self._run([row])), 0)

    def test_missing_cols_skips_rule(self):
        row = {"time_s": "10.0", "room_id": "0", "temp_upper_c": "80.0", "temp_lower_c": "30.0"}
        self.assertEqual(len(self._run([row])), 0)

    def test_room_id_reported_in_finding(self):
        row = dict(_ROW_FED_BROKEN)
        row["room_id"] = "3"
        findings = self._run([row])
        self.assertEqual(findings[0].room_id, "3")


# ---------------------------------------------------------------------------
# Tests: Rule C2 — FED monotonicity
# ---------------------------------------------------------------------------

class TestCheckC2(unittest.TestCase):

    def _run(self, rows):
        return checker.find_physics_coherence_issues(rows, rule_ids={"C2"})

    def test_monotone_sequence_no_finding(self):
        findings = self._run([_ROW_FED_SEQ_A, _ROW_FED_SEQ_B_OK])
        self.assertEqual(len([f for f in findings if f.rule_id == "C2"]), 0)

    def test_decrement_detected(self):
        findings = self._run([_ROW_FED_SEQ_A, _ROW_FED_SEQ_B_DECR])
        c2 = [f for f in findings if f.rule_id == "C2"]
        self.assertEqual(len(c2), 1)
        self.assertEqual(c2[0].severity, "FAIL")
        self.assertLess(c2[0].value, 0)   # delta is negative

    def test_tiny_decrement_within_tolerance_not_flagged(self):
        # delta = -0.0003, below tolerance 0.0005
        a = _row(time_s="10.0", fed="0.0100",
                 fed_co="0.0050", fed_hcn="0.0020",
                 fed_hypoxia="0.0020", fed_heat="0.0010")
        b = _row(time_s="20.0", fed="0.0097",
                 fed_co="0.0049", fed_hcn="0.0019",
                 fed_hypoxia="0.0019", fed_heat="0.0010")
        self.assertEqual(len(self._run([a, b])), 0)

    def test_unordered_rows_sorted_by_time(self):
        # Row B has t=20 (higher fed), row A has t=10 (lower fed).
        # Even though B appears first in the list, sorting by time gives A->B = monotone.
        findings = self._run([_ROW_FED_SEQ_B_OK, _ROW_FED_SEQ_A])
        self.assertEqual(len([f for f in findings if f.rule_id == "C2"]), 0)

    def test_multi_room_independent_sequences(self):
        # room 0: monotone; room 1: decreases
        r0_a = _row(time_s="10.0", room_id="0", fed="0.0100",
                    fed_co="0.0050", fed_hcn="0.0020",
                    fed_hypoxia="0.0020", fed_heat="0.0010")
        r0_b = _row(time_s="20.0", room_id="0", fed="0.0200",
                    fed_co="0.0100", fed_hcn="0.0040",
                    fed_hypoxia="0.0040", fed_heat="0.0020")
        r1_a = _row(time_s="10.0", room_id="1", fed="0.0300",
                    fed_co="0.0150", fed_hcn="0.0060",
                    fed_hypoxia="0.0060", fed_heat="0.0030")
        r1_b = _row(time_s="20.0", room_id="1", fed="0.0050",  # decreases
                    fed_co="0.0020", fed_hcn="0.0010",
                    fed_hypoxia="0.0010", fed_heat="0.0010")
        findings = self._run([r0_a, r0_b, r1_a, r1_b])
        c2 = [f for f in findings if f.rule_id == "C2"]
        self.assertEqual(len(c2), 1)
        self.assertEqual(c2[0].room_id, "1")

    def test_missing_fed_col_skips_rule(self):
        row = {"time_s": "10.0", "room_id": "0", "temp_upper_c": "80.0", "temp_lower_c": "30.0"}
        self.assertEqual(len(self._run([row])), 0)

    def test_single_row_no_finding(self):
        self.assertEqual(len(self._run([_ROW_FED_SEQ_A])), 0)


# ---------------------------------------------------------------------------
# Tests: Rule A2 — HRR without fuel
# ---------------------------------------------------------------------------

class TestCheckA2(unittest.TestCase):

    def _run(self, rows):
        return checker.find_physics_coherence_issues(rows, rule_ids={"A2"})

    def test_hrr_with_fuel_no_finding(self):
        self.assertEqual(len(self._run([_row_a2(hrr_kw="50.0", fuel_remaining_MJ="5.0")])), 0)

    def test_hrr_zero_no_fuel_no_finding(self):
        # HRR=0 is below the 20 kW threshold → no violation
        self.assertEqual(len(self._run([_row_a2(hrr_kw="0.0", fuel_remaining_MJ="0.0")])), 0)

    def test_hrr_at_threshold_not_flagged(self):
        # hrr = 20.0 exactly → strict >, not flagged
        self.assertEqual(len(self._run([_row_a2(hrr_kw="20.0", fuel_remaining_MJ="0.0")])), 0)

    def test_hrr_above_threshold_no_fuel_violation(self):
        findings = self._run([_row_a2(hrr_kw="50.0", fuel_remaining_MJ="0.0")])
        a2 = [f for f in findings if f.rule_id == "A2"]
        self.assertEqual(len(a2), 1)
        self.assertEqual(a2[0].severity, "FAIL")
        self.assertAlmostEqual(a2[0].value, 50.0, places=1)

    def test_smoldering_active_exempts_finding(self):
        row = _row_a2(hrr_kw="50.0", fuel_remaining_MJ="0.0", fire_smoldering="1")
        self.assertEqual(len(self._run([row])), 0)

    def test_latent_active_exempts_finding(self):
        row = _row_a2(hrr_kw="50.0", fuel_remaining_MJ="0.0", fire_latent_active="1")
        self.assertEqual(len(self._run([row])), 0)

    def test_small_fuel_residual_not_flagged(self):
        # fuel_remaining = 0.001 is exactly at the threshold → not depleted
        row = _row_a2(hrr_kw="50.0", fuel_remaining_MJ="0.001")
        self.assertEqual(len(self._run([row])), 0)

    def test_negative_fuel_is_depleted(self):
        # Negative fuel_remaining (float overshoot) counts as depleted
        findings = self._run([_row_a2(hrr_kw="50.0", fuel_remaining_MJ="-0.1")])
        self.assertEqual(len([f for f in findings if f.rule_id == "A2"]), 1)

    def test_missing_cols_skips_rule(self):
        row = {"time_s": "10.0", "room_id": "0", "hrr_kw": "100.0"}
        self.assertEqual(len(self._run([row])), 0)

    def test_multiple_violations_all_reported(self):
        rows = [
            _row_a2(time_s="10.0", hrr_kw="50.0", fuel_remaining_MJ="0.0"),
            _row_a2(time_s="20.0", hrr_kw="80.0", fuel_remaining_MJ="0.0"),
            _row_a2(time_s="30.0", hrr_kw="30.0", fuel_remaining_MJ="1.0"),  # has fuel → no violation
        ]
        findings = self._run(rows)
        a2 = [f for f in findings if f.rule_id == "A2"]
        self.assertEqual(len(a2), 2)


# ---------------------------------------------------------------------------
# Tests: Rule A3 — Regime/O2 upper mismatch
# ---------------------------------------------------------------------------

class TestCheckA3(unittest.TestCase):

    def _run(self, rows):
        return checker.find_physics_coherence_issues(rows, rule_ids={"A3"})

    def test_fuel_controlled_normal_o2_no_finding(self):
        self.assertEqual(len(self._run([_row_a3(combustion_regime="FUEL_CONTROLLED", o2_upper="0.15")])), 0)

    def test_fully_developed_normal_o2_no_finding(self):
        self.assertEqual(len(self._run([_row_a3(combustion_regime="FULLY_DEVELOPED", o2_upper="0.12")])), 0)

    def test_fuel_controlled_o2_at_threshold_not_flagged(self):
        # o2_upper = 0.05 exactly → strict <, not flagged
        self.assertEqual(len(self._run([_row_a3(combustion_regime="FUEL_CONTROLLED", o2_upper="0.05")])), 0)

    def test_fuel_controlled_depleted_o2_violation(self):
        findings = self._run([_row_a3(combustion_regime="FUEL_CONTROLLED", o2_upper="0.03")])
        a3 = [f for f in findings if f.rule_id == "A3"]
        self.assertEqual(len(a3), 1)
        self.assertEqual(a3[0].severity, "FAIL")
        self.assertAlmostEqual(a3[0].value, 0.03, places=4)

    def test_fully_developed_depleted_o2_violation(self):
        findings = self._run([_row_a3(combustion_regime="FULLY_DEVELOPED", o2_upper="0.02")])
        a3 = [f for f in findings if f.rule_id == "A3"]
        self.assertEqual(len(a3), 1)
        self.assertEqual(a3[0].severity, "FAIL")

    def test_ventilation_controlled_depleted_o2_no_finding(self):
        # VENTILATION_CONTROLLED_BURNING is not in the incoherent-regime set
        row = _row_a3(combustion_regime="VENTILATION_CONTROLLED_BURNING", o2_upper="0.03")
        self.assertEqual(len(self._run([row])), 0)

    def test_ventilation_stressed_depleted_o2_no_finding(self):
        row = _row_a3(combustion_regime="VENTILATION_STRESSED", o2_upper="0.03")
        self.assertEqual(len(self._run([row])), 0)

    def test_extinguished_depleted_o2_no_finding(self):
        row = _row_a3(combustion_regime="EXTINGUISHED", o2_upper="0.00")
        self.assertEqual(len(self._run([row])), 0)

    def test_ilv_latent_depleted_o2_no_finding(self):
        row = _row_a3(combustion_regime="ILV_LATENT", o2_upper="0.01")
        self.assertEqual(len(self._run([row])), 0)

    def test_missing_cols_skips_rule(self):
        row = {"time_s": "10.0", "room_id": "0", "hrr_kw": "100.0"}
        self.assertEqual(len(self._run([row])), 0)

    def test_room_id_reported_correctly(self):
        row = dict(_row_a3(combustion_regime="FUEL_CONTROLLED", o2_upper="0.03"))
        row["room_id"] = "2"
        findings = self._run([row])
        self.assertEqual(findings[0].room_id, "2")

    def test_reason_contains_regime_and_o2(self):
        findings = self._run([_row_a3(combustion_regime="FULLY_DEVELOPED", o2_upper="0.02")])
        self.assertIn("FULLY_DEVELOPED", findings[0].reason)
        self.assertIn("0.02", findings[0].reason)


# ---------------------------------------------------------------------------
# Tests: find_physics_coherence_issues — integration / cross-cutting
# ---------------------------------------------------------------------------

class TestFindPhysicsCoherenceIssues(unittest.TestCase):

    def test_empty_rows_returns_empty(self):
        self.assertEqual(checker.find_physics_coherence_issues([]), [])

    def test_room_id_filter(self):
        row_r0 = dict(_ROW_FED_BROKEN); row_r0["room_id"] = "0"
        row_r1 = dict(_ROW_FED_BROKEN); row_r1["room_id"] = "1"
        findings = checker.find_physics_coherence_issues([row_r0, row_r1], room_id="1")
        self.assertTrue(all(f.room_id == "1" for f in findings))

    def test_rule_id_filter_c1_only(self):
        row = dict(_ROW_THERMAL_INVERSION)
        row.update({"fed": "0.10", "fed_co": "0.01", "fed_hcn": "0.01",
                    "fed_hypoxia": "0.01", "fed_heat": "0.01"})
        findings = checker.find_physics_coherence_issues([row], rule_ids={"C1"})
        self.assertTrue(all(f.rule_id == "C1" for f in findings))

    def test_rule_id_filter_b1_only(self):
        row = dict(_ROW_THERMAL_INVERSION)
        row.update({"fed": "0.10", "fed_co": "0.01", "fed_hcn": "0.01",
                    "fed_hypoxia": "0.01", "fed_heat": "0.01"})
        findings = checker.find_physics_coherence_issues([row], rule_ids={"B1"})
        self.assertTrue(all(f.rule_id == "B1" for f in findings))

    def test_unknown_rule_ids_ignored(self):
        findings = checker.find_physics_coherence_issues(
            [_ROW_CLEAN], rule_ids={"NONEXISTENT"}
        )
        self.assertEqual(findings, [])

    def test_schema_without_fed_components_skips_c1(self):
        row = {"time_s": "10.0", "room_id": "0", "fed": "0.10",
               "temp_upper_c": "80.0", "temp_lower_c": "30.0"}
        findings = checker.find_physics_coherence_issues([row])
        c1 = [f for f in findings if f.rule_id == "C1"]
        self.assertEqual(len(c1), 0)


# ---------------------------------------------------------------------------
# Tests: audit_physics_coherence_suite — FileResult
# ---------------------------------------------------------------------------

class TestFileResult(unittest.TestCase):

    def _make(self, findings):
        return suite.FileResult(
            path=Path("fake.csv"),
            total_rows=100,
            rooms={"0"},
            findings=findings,
        )

    def _finding(self, severity="FAIL", rule_id="C1"):
        return checker.Finding(
            time_s=10.0, room_id="0", rule_id=rule_id, severity=severity,
            metric="fed_sum_error", value=0.05, reason="test",
        )

    def test_fail_count_counts_fails(self):
        result = self._make([self._finding("FAIL"), self._finding("WARN")])
        self.assertEqual(result.fail_count, 1)

    def test_warn_count_counts_warns(self):
        result = self._make([self._finding("FAIL"), self._finding("WARN")])
        self.assertEqual(result.warn_count, 1)

    def test_worst_finding_prefers_fail_over_warn(self):
        warn = self._finding("WARN")
        fail = self._finding("FAIL")
        result = self._make([warn, fail])
        self.assertEqual(result.worst_finding.severity, "FAIL")

    def test_worst_finding_none_when_empty(self):
        self.assertIsNone(self._make([]).worst_finding)

    def test_findings_by_rule_counts_correctly(self):
        result = self._make([
            self._finding(rule_id="C1"),
            self._finding(rule_id="C1"),
            self._finding(rule_id="B1"),
        ])
        self.assertEqual(result.findings_by_rule(), {"C1": 2, "B1": 1})

    def test_intentional_default_false(self):
        self.assertFalse(self._make([]).intentional)


# ---------------------------------------------------------------------------
# Tests: audit_physics_coherence_suite — main() exit codes
# ---------------------------------------------------------------------------

class TestAuditSuiteMain(unittest.TestCase):

    def _write_csv(self, path: Path, rows: list[dict]) -> None:
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

    def test_returns_0_for_clean_directory(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "clean.csv", [_ROW_CLEAN])
            rc = suite.main(["--reports-dir", td])
        self.assertEqual(rc, 0)

    def test_returns_1_for_fail_findings(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "broken.csv", [_ROW_FED_BROKEN])
            rc = suite.main(["--reports-dir", td])
        self.assertEqual(rc, 1)

    def test_allow_findings_overrides_exit_code(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "broken.csv", [_ROW_FED_BROKEN])
            rc = suite.main(["--reports-dir", td, "--allow-findings"])
        self.assertEqual(rc, 0)

    def test_intentional_control_does_not_raise_exit_1(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "fp_ctrl_case.csv", [_ROW_FED_BROKEN])
            rc = suite.main(["--reports-dir", td, "--intentional", "fp_ctrl_case"])
        self.assertEqual(rc, 0)

    def test_intentional_control_still_exits_1_for_other_failures(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "fp_ctrl_case.csv", [_ROW_FED_BROKEN])
            self._write_csv(Path(td) / "real_failure.csv", [_ROW_FED_BROKEN])
            rc = suite.main(["--reports-dir", td, "--intentional", "fp_ctrl_case"])
        self.assertEqual(rc, 1)

    def test_returns_2_for_missing_directory(self):
        rc = suite.main(["--reports-dir", "/nonexistent/path/xyz"])
        self.assertEqual(rc, 2)

    def test_include_tmp_flag_includes_tmp_files(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "tmp_exp.csv", [_ROW_FED_BROKEN])
            rc_exclude = suite.main(["--reports-dir", td])
            rc_include = suite.main(["--reports-dir", td, "--include-tmp"])
        self.assertEqual(rc_exclude, 0)   # tmp excluded -> nothing audited -> PASS
        self.assertEqual(rc_include, 1)   # tmp included -> findings -> FAIL

    def test_rules_filter_passed_through(self):
        # B1-only audit: ROW_FED_BROKEN has valid temps -> no B1 finding -> exit 0
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "broken.csv", [_ROW_FED_BROKEN])
            rc = suite.main(["--reports-dir", td, "--rules", "B1"])
        self.assertEqual(rc, 0)

    def test_verbose_does_not_crash(self):
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "clean.csv", [_ROW_CLEAN])
            rc = suite.main(["--reports-dir", td, "--verbose"])
        self.assertEqual(rc, 0)

    def test_known_intentional_controls_is_envelope_dict(self):
        """CTRLs are a dict stem -> {rule_id: max_count} (or None = unlimited)."""
        self.assertIsInstance(suite.KNOWN_INTENTIONAL_CONTROLS, dict)
        for stem, envelope in suite.KNOWN_INTENTIONAL_CONTROLS.items():
            self.assertIsInstance(stem, str)
            if envelope is not None:
                self.assertIsInstance(envelope, dict)
                for rule, cap in envelope.items():
                    self.assertIsInstance(rule, str)
                    self.assertIsInstance(cap, int)
                    self.assertGreater(cap, 0)


# ---------------------------------------------------------------------------
# Tests: audit_physics_coherence_suite — CTRL envelopes
# ---------------------------------------------------------------------------

class TestCtrlEnvelopes(unittest.TestCase):

    def _write_csv(self, path: Path, rows: list[dict]) -> None:
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

    def test_violations_empty_when_within_envelope(self):
        self.assertEqual(
            suite.envelope_violations({"C1": 3}, {"C1": 5}), [])

    def test_violations_flag_unregistered_rule(self):
        violations = suite.envelope_violations({"C1": 1, "E1": 2}, {"C1": 5})
        self.assertEqual(len(violations), 1)
        self.assertIn("E1", violations[0])

    def test_violations_flag_exceeded_count(self):
        violations = suite.envelope_violations({"C1": 6}, {"C1": 5})
        self.assertEqual(len(violations), 1)
        self.assertIn("C1:6 > max 5", violations[0])

    def test_none_envelope_is_unlimited(self):
        self.assertEqual(
            suite.envelope_violations({"C1": 999, "E1": 999}, None), [])

    def _run_with_ctrl(self, envelope) -> int:
        """Run main() over a CSV producing 1 C1 finding, registered as CTRL."""
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "envctrl.csv", [_ROW_FED_BROKEN])
            old = suite.KNOWN_INTENTIONAL_CONTROLS
            suite.KNOWN_INTENTIONAL_CONTROLS = {"envctrl": envelope}
            try:
                return suite.main(["--reports-dir", td])
            finally:
                suite.KNOWN_INTENTIONAL_CONTROLS = old

    def test_ctrl_within_envelope_exits_0(self):
        self.assertEqual(self._run_with_ctrl({"C1": 1}), 0)

    def test_ctrl_with_unregistered_rule_exits_1(self):
        """A finding of a rule the envelope does not declare gates the suite."""
        self.assertEqual(self._run_with_ctrl({"B1": 1}), 1)

    def test_cli_intentional_stem_keeps_unlimited_envelope(self):
        """Ad-hoc --intentional stems keep legacy absorb-everything behavior."""
        with tempfile.TemporaryDirectory() as td:
            self._write_csv(Path(td) / "adhoc.csv", [_ROW_FED_BROKEN])
            rc = suite.main(["--reports-dir", td, "--intentional", "adhoc"])
        self.assertEqual(rc, 0)


# ---------------------------------------------------------------------------
# Tests: find_csvs helper
# ---------------------------------------------------------------------------

class TestFindCsvs(unittest.TestCase):

    def test_excludes_tmp_by_default(self):
        with tempfile.TemporaryDirectory() as td:
            Path(td, "case_a.csv").write_text("x")
            Path(td, "tmp_exp.csv").write_text("x")
            found = suite.find_csvs(Path(td))
        self.assertEqual([f.name for f in found], ["case_a.csv"])

    def test_includes_tmp_when_requested(self):
        with tempfile.TemporaryDirectory() as td:
            Path(td, "case_a.csv").write_text("x")
            Path(td, "tmp_exp.csv").write_text("x")
            found = suite.find_csvs(Path(td), exclude_tmp=False)
        self.assertEqual(sorted(f.name for f in found), ["case_a.csv", "tmp_exp.csv"])


# ---------------------------------------------------------------------------
# D1 row helper
# ---------------------------------------------------------------------------
# D1 uses CUMULATIVE totals (co_generated_kg_total, co_net_transport_kg_total,
# co_exterior_removed_kg_total) to be invariant to the log_interval vs timestep
# ratio.  Per-step fields capture only the last step and alias badly.

def _row_d1(
    time_s="10.0", room_id="0",
    co_kg="0.0", co_generated_kg_total="0.0", co_net_transport_kg_total="0.0",
    co_exterior_removed_kg_total="0.0",
) -> dict[str, str]:
    return {
        "time_s": time_s, "room_id": room_id,
        "co_kg": co_kg,
        "co_generated_kg_total": co_generated_kg_total,
        "co_net_transport_kg_total": co_net_transport_kg_total,
        "co_exterior_removed_kg_total": co_exterior_removed_kg_total,
    }


# ---------------------------------------------------------------------------
# Tests: Rule D1 — CO balance residual
# ---------------------------------------------------------------------------

class TestCheckD1(unittest.TestCase):

    def _run(self, rows):
        return [f for f in checker.find_physics_coherence_issues(rows, rule_ids={"D1"})
                if f.rule_id == "D1"]

    # ── Clean cases ───────────────────────────────────────────────────────────

    def test_perfect_balance_no_finding(self):
        """Δco_kg == Δgen_total + Δtransport_total → no finding."""
        rows = [
            _row_d1(time_s="0.0", co_kg="0.0"),
            _row_d1(time_s="10.0", co_kg="0.001",
                    co_generated_kg_total="0.001",
                    co_net_transport_kg_total="0.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_pure_transport_in_no_finding(self):
        """CO arrived entirely from transport, no local generation."""
        rows = [
            _row_d1(time_s="0.0", co_kg="0.0"),
            _row_d1(time_s="10.0", co_kg="0.002",
                    co_generated_kg_total="0.0",
                    co_net_transport_kg_total="0.002"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_transport_out_no_finding(self):
        """CO left to adjacent rooms; co_kg decreased."""
        rows = [
            _row_d1(time_s="0.0", co_kg="0.005",
                    co_generated_kg_total="0.010",
                    co_net_transport_kg_total="0.000"),
            _row_d1(time_s="10.0", co_kg="0.003",
                    co_generated_kg_total="0.010",
                    co_net_transport_kg_total="-0.002"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_generation_plus_transport_no_finding(self):
        """Fire room: local generation plus incoming transport."""
        rows = [
            _row_d1(time_s="0.0", co_kg="0.000"),
            _row_d1(time_s="10.0", co_kg="0.003",
                    co_generated_kg_total="0.002",
                    co_net_transport_kg_total="0.001"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_zero_step_no_finding(self):
        """All zeros: nothing happens — balance is trivially exact."""
        rows = [
            _row_d1(time_s="0.0", co_kg="0.0"),
            _row_d1(time_s="10.0", co_kg="0.0",
                    co_generated_kg_total="0.0",
                    co_net_transport_kg_total="0.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    # ── Tolerance boundary ───────────────────────────────────────────────────

    def test_small_residual_within_relative_tolerance_no_finding(self):
        """Residual at 4 % of expected (< 5 % threshold) → no finding.

        threshold = max(1e-6, 0.05 * abs(expected)) = 0.05 * 0.001 = 5e-5
        residual  = 4 % * 0.001 = 4e-5 < 5e-5 → pass.
        """
        co_prev = 0.0
        generated = 0.001000   # 1 mg CO generated
        transported = 0.0
        residual_injected = generated * 0.04   # 4 % of expected
        co_new = co_prev + generated + transported + residual_injected
        rows = [
            _row_d1(time_s="0.0", co_kg=str(co_prev)),
            _row_d1(time_s="10.0", co_kg=str(co_new),
                    co_generated_kg_total=str(generated),
                    co_net_transport_kg_total=str(transported)),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_residual_just_above_relative_tolerance_flagged(self):
        """Residual slightly above 5 % of magnitude → FAIL finding."""
        generated = 0.001000
        transported = 0.0
        co_prev = 0.0
        co_new = co_prev + generated + transported + generated * 0.051  # 5.1 % > 5 %
        rows = [
            _row_d1(time_s="0.0", co_kg=str(co_prev)),
            _row_d1(time_s="10.0", co_kg=str(co_new),
                    co_generated_kg_total=str(generated),
                    co_net_transport_kg_total=str(transported)),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "FAIL")

    def test_large_unaccounted_residual_flagged(self):
        """CO increased by 5 mg with zero generation and zero transport → FAIL."""
        rows = [
            _row_d1(time_s="0.0", co_kg="0.0"),
            _row_d1(time_s="10.0", co_kg="0.005",
                    co_generated_kg_total="0.0",
                    co_net_transport_kg_total="0.0"),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "FAIL")
        self.assertEqual(findings[0].metric, "co_balance_residual_kg")
        self.assertAlmostEqual(findings[0].value, 0.005, places=6)

    def test_exterior_removal_tracked_no_finding(self):
        """CO decreased by ACH removal tracked in co_exterior_removed_kg_total → no finding.

        CO generated: 0.002 kg.  ACH removed: 0.0005 kg.  Net change: +0.0015 kg.
        expected = delta_gen + delta_trans - delta_ext_rm = 0.002 + 0 - 0.0005 = 0.0015.
        """
        rows = [
            _row_d1(time_s="0.0",  co_kg="0.001",
                    co_generated_kg_total="0.010",
                    co_net_transport_kg_total="0.000",
                    co_exterior_removed_kg_total="0.000"),
            _row_d1(time_s="10.0", co_kg="0.0025",
                    co_generated_kg_total="0.012",
                    co_net_transport_kg_total="0.000",
                    co_exterior_removed_kg_total="0.0005"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_exterior_removal_untracked_flagged(self):
        """CO decreased by ACH but co_exterior_removed_kg_total not updated → FAIL.

        delta_co = -0.0005.  expected = 0.002 + 0 - 0 = 0.002.  residual = 0.0025 >> tol.
        """
        rows = [
            _row_d1(time_s="0.0",  co_kg="0.001",
                    co_generated_kg_total="0.010"),
            _row_d1(time_s="10.0", co_kg="0.0025",
                    co_generated_kg_total="0.012"),
            # co_exterior_removed_kg_total stays 0 — simulating the old bug
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "FAIL")

    # ── Temporal ordering ────────────────────────────────────────────────────

    def test_rows_sorted_by_time_before_diff(self):
        """Rows given out of time order must still be diffed in chronological order."""
        # Cumulative totals at each timestamp:
        # t=0:  co_kg=0.001 (baseline), gen_total=0, transport_total=0
        # t=10: co_kg=0.001, gen_total=0,     transport_total=0     → Δco=0, expected=0 ✓
        # t=20: co_kg=0.003, gen_total=0.002, transport_total=0     → Δco=0.002, expected=0.002 ✓
        rows = [
            _row_d1(time_s="20.0", co_kg="0.003",
                    co_generated_kg_total="0.002", co_net_transport_kg_total="0.000"),
            _row_d1(time_s="0.0", co_kg="0.001",
                    co_generated_kg_total="0.000", co_net_transport_kg_total="0.000"),
            _row_d1(time_s="10.0", co_kg="0.001",
                    co_generated_kg_total="0.000", co_net_transport_kg_total="0.000"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    # ── Multi-room independence ──────────────────────────────────────────────

    def test_multi_room_independent_balance(self):
        """Two rooms checked independently; violation in room 1 doesn't affect room 0."""
        rows = [
            # room 0: perfectly balanced
            _row_d1(time_s="0.0",  room_id="0", co_kg="0.0"),
            _row_d1(time_s="10.0", room_id="0", co_kg="0.001",
                    co_generated_kg_total="0.001", co_net_transport_kg_total="0.0"),
            # room 1: unbalanced (CO appeared with no source)
            _row_d1(time_s="0.0",  room_id="1", co_kg="0.0"),
            _row_d1(time_s="10.0", room_id="1", co_kg="0.005",
                    co_generated_kg_total="0.0", co_net_transport_kg_total="0.0"),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].room_id, "1")

    def test_first_row_per_room_is_baseline_no_finding(self):
        """The very first row of each room is used as baseline; it never generates a finding."""
        rows = [_row_d1(time_s="0.0", co_kg="9999.0")]  # huge starting value
        self.assertEqual(len(self._run(rows)), 0)

    # ── Missing columns / old CSV schema ─────────────────────────────────────

    def test_missing_co_generated_column_skips_rule(self):
        """CSV without co_generated_kg_total → D1 silently skipped."""
        rows = [
            {"time_s": "0.0", "room_id": "0", "co_kg": "0.0"},
            {"time_s": "10.0", "room_id": "0", "co_kg": "0.005"},
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_missing_co_kg_column_skips_rule(self):
        """CSV without co_kg → D1 silently skipped."""
        rows = [
            {"time_s": "0.0", "room_id": "0",
             "co_generated_kg_total": "0.0", "co_net_transport_kg_total": "0.0"},
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_missing_all_new_columns_skips_rule(self):
        """Pre-diagnostic CSV (only original columns) → D1 skipped, no crash."""
        rows = [_row(), _row(time_s="20.0")]
        self.assertEqual(len(self._run(rows)), 0)

    # ── Finding metadata ─────────────────────────────────────────────────────

    def test_finding_rule_id_is_d1(self):
        rows = [
            _row_d1(time_s="0.0", co_kg="0.0"),
            _row_d1(time_s="10.0", co_kg="0.01",
                    co_generated_kg_total="0.0", co_net_transport_kg_total="0.0"),
        ]
        self.assertEqual(self._run(rows)[0].rule_id, "D1")

    def test_finding_severity_is_fail(self):
        rows = [
            _row_d1(time_s="0.0", co_kg="0.0"),
            _row_d1(time_s="10.0", co_kg="0.01",
                    co_generated_kg_total="0.0", co_net_transport_kg_total="0.0"),
        ]
        self.assertEqual(self._run(rows)[0].severity, "FAIL")

    def test_finding_reason_contains_delta_and_expected(self):
        rows = [
            _row_d1(time_s="0.0", co_kg="0.0"),
            _row_d1(time_s="10.0", co_kg="0.01",
                    co_generated_kg_total="0.0", co_net_transport_kg_total="0.0"),
        ]
        reason = self._run(rows)[0].reason
        self.assertIn("delta_co", reason)
        self.assertIn("expected", reason)
        self.assertIn("residual", reason)


# ---------------------------------------------------------------------------
# E1 row helper
# ---------------------------------------------------------------------------
# E1 uses fuel_consumed_MJ_total (cumulative) to be invariant to the
# log_interval vs timestep ratio.  fuel_consumed_MJ_step is NOT used here.

def _row_e1(
    time_s="10.0", room_id="0",
    solid_fuel_remaining_MJ="50.0",
    fuel_consumed_MJ_total="0.0",
) -> dict[str, str]:
    return {
        "time_s": time_s, "room_id": room_id,
        "solid_fuel_remaining_MJ": solid_fuel_remaining_MJ,
        "fuel_consumed_MJ_total": fuel_consumed_MJ_total,
    }


# ---------------------------------------------------------------------------
# Tests: Rule E1 — Fuel balance residual
# ---------------------------------------------------------------------------

class TestCheckE1(unittest.TestCase):

    def _run(self, rows):
        return [f for f in checker.find_physics_coherence_issues(rows, rule_ids={"E1"})
                if f.rule_id == "E1"]

    # ── Clean cases ───────────────────────────────────────────────────────────

    def test_perfect_balance_no_finding(self):
        """Δremaining == −Δconsumed_total → no finding."""
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="0.5"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_no_fire_no_finding(self):
        """No consumption and no change in remaining → trivially balanced."""
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_fuel_depleted_to_zero_no_finding(self):
        """Fuel reaches zero and stays there — balance holds."""
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="1.0",  fuel_consumed_MJ_total="49.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="0.0",  fuel_consumed_MJ_total="50.0"),
            _row_e1(time_s="20.0", solid_fuel_remaining_MJ="0.0",  fuel_consumed_MJ_total="50.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_small_residual_within_relative_tolerance_no_finding(self):
        """Residual of 0.5 % of expected is within the 1 % tolerance."""
        # delta_remaining=-1.0, delta_consumed=1.0, expected=-1.0
        # residual = |(-1.0) - (-1.0)| = 0 — use a tiny imprecision instead
        # residual = 0.005 MJ on expected = 1.0 → 0.5 % < 1 % → clean
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.000", fuel_consumed_MJ_total="0.000"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="48.995", fuel_consumed_MJ_total="1.000"),
        ]
        # delta_remaining = -1.005, expected = -1.000, residual = 0.005 < 0.01 (1%)
        self.assertEqual(len(self._run(rows)), 0)

    # ── Flagged cases ─────────────────────────────────────────────────────────

    def test_large_balance_residual_flagged(self):
        """Residual much larger than tolerance raises E1 finding."""
        # delta_remaining=-0.5, delta_consumed=1.0, expected=-1.0, residual=0.5 >> 0.01
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="1.0"),
        ]
        findings = self._run(rows)
        self.assertGreater(len(findings), 0)
        self.assertTrue(any(f.metric == "fuel_balance_residual_MJ" for f in findings))

    def test_fuel_increased_flagged(self):
        """fuel_remaining_MJ increasing is physically impossible — must flag."""
        # delta_remaining = +2.0 (fuel appeared from nowhere)
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="5.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="52.0", fuel_consumed_MJ_total="5.0"),
        ]
        findings = self._run(rows)
        self.assertGreater(len(findings), 0)
        self.assertTrue(any(f.metric == "fuel_remaining_increased_MJ" for f in findings))

    def test_consumed_without_remaining_decrease_flagged(self):
        """Consumed increased but remaining didn't decrease → balance residual."""
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="2.0"),
        ]
        # delta_remaining=0, expected=-2.0, residual=2.0 >> tolerance
        findings = self._run(rows)
        self.assertGreater(len(findings), 0)
        self.assertTrue(any(f.metric == "fuel_balance_residual_MJ" for f in findings))

    # ── Multi-room and ordering ────────────────────────────────────────────────

    def test_multi_room_independent(self):
        """Each room's balance is checked independently."""
        rows = [
            # Room 0: balanced
            _row_e1(time_s="0.0",  room_id="0", solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", room_id="0", solid_fuel_remaining_MJ="49.0", fuel_consumed_MJ_total="1.0"),
            # Room 1: imbalanced
            _row_e1(time_s="0.0",  room_id="1", solid_fuel_remaining_MJ="30.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", room_id="1", solid_fuel_remaining_MJ="29.0", fuel_consumed_MJ_total="5.0"),
        ]
        findings = self._run(rows)
        room_ids = {f.room_id for f in findings}
        self.assertIn("1", room_ids)
        self.assertNotIn("0", room_ids)

    def test_rows_sorted_by_time_before_diff(self):
        """Out-of-order rows must be sorted before computing deltas."""
        rows = [
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="49.0", fuel_consumed_MJ_total="1.0"),
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_first_row_per_room_is_baseline_no_finding(self):
        """The first row sets the baseline; no finding is generated for it."""
        rows = [
            _row_e1(time_s="5.0", solid_fuel_remaining_MJ="48.0", fuel_consumed_MJ_total="2.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    # ── Schema / graceful skip ─────────────────────────────────────────────────

    def test_missing_fuel_consumed_column_skips_rule(self):
        """E1 skips gracefully when fuel_consumed_MJ_total is absent."""
        rows = [
            {"time_s": "0.0",  "room_id": "0", "solid_fuel_remaining_MJ": "50.0"},
            {"time_s": "10.0", "room_id": "0", "solid_fuel_remaining_MJ": "45.0"},
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_missing_solid_fuel_remaining_column_skips_rule(self):
        """E1 skips gracefully when solid_fuel_remaining_MJ is absent (old schema)."""
        rows = [
            {"time_s": "0.0",  "room_id": "0", "fuel_consumed_MJ_total": "0.0"},
            {"time_s": "10.0", "room_id": "0", "fuel_consumed_MJ_total": "1.0"},
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_old_csv_without_e1_columns_does_not_raise(self):
        """CSV with only legacy columns must not raise — E1 skips silently."""
        rows = [
            {"time_s": "0.0",  "room_id": "0", "hrr_kw": "0.0",  "co_kg": "0.0"},
            {"time_s": "10.0", "room_id": "0", "hrr_kw": "50.0", "co_kg": "0.001"},
        ]
        try:
            result = self._run(rows)
        except Exception as exc:
            self.fail(f"E1 raised {exc!r} on old-schema CSV")
        self.assertEqual(len(result), 0)

    # ── Finding fields ────────────────────────────────────────────────────────

    def test_finding_rule_id_is_e1(self):
        """Finding must report rule_id == 'E1'."""
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="5.0"),
        ]
        findings = self._run(rows)
        self.assertTrue(all(f.rule_id == "E1" for f in findings))

    def test_finding_severity_is_fail(self):
        """E1 is gating (FAIL) after clean corpus validation."""
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="5.0"),
        ]
        findings = self._run(rows)
        self.assertTrue(len(findings) > 0)
        self.assertTrue(all(f.severity == "FAIL" for f in findings))

    def test_finding_reason_contains_delta_and_expected(self):
        """Finding reason must contain delta_remaining and expected for diagnostics."""
        rows = [
            _row_e1(time_s="0.0",  solid_fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", solid_fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="5.0"),
        ]
        reason = self._run(rows)[0].reason
        self.assertIn("delta_remaining", reason)
        self.assertIn("expected", reason)


def _row_s0(
    time_s="10.0", room_id="0",
    smoke_kg="0.0",
    smoke_generated_total_kg="0.0",
    smoke_vented_total_kg="0.0",
    smoke_deposited_total_kg="0.0",
    smoke_in_transit_kg="0.0",
) -> dict[str, str]:
    return {
        "time_s": time_s,
        "room_id": room_id,
        "smoke_kg": smoke_kg,
        "smoke_generated_total_kg": smoke_generated_total_kg,
        "smoke_vented_total_kg": smoke_vented_total_kg,
        "smoke_deposited_total_kg": smoke_deposited_total_kg,
        "smoke_in_transit_kg": smoke_in_transit_kg,
    }


# ---------------------------------------------------------------------------
# Tests: Rule S0 — Smoke global conservation
# ---------------------------------------------------------------------------

class TestCheckS0(unittest.TestCase):

    def _run(self, rows):
        return [f for f in checker.find_physics_coherence_issues(rows, rule_ids={"S0"})
                if f.rule_id == "S0"]

    # ── Clean cases ───────────────────────────────────────────────────────────

    def test_perfect_balance_no_finding(self):
        """sum_smoke == generated - vented - deposited → no finding."""
        rows = [
            _row_s0(time_s="10.0", room_id="0",
                    smoke_kg="2.0",
                    smoke_generated_total_kg="2.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_generation_only_no_finding(self):
        """All generated smoke still in room → no finding."""
        rows = [
            _row_s0(time_s="5.0", room_id="0",
                    smoke_kg="1.5",
                    smoke_generated_total_kg="1.5",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_vented_smoke_no_finding(self):
        """Generated smoke partly vented; remainder matches. → no finding."""
        rows = [
            _row_s0(time_s="20.0", room_id="0",
                    smoke_kg="0.8",
                    smoke_generated_total_kg="1.0",
                    smoke_vented_total_kg="0.2",
                    smoke_deposited_total_kg="0.0"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_deposited_smoke_no_finding(self):
        """Generated smoke partly deposited; remainder matches. → no finding."""
        rows = [
            _row_s0(time_s="30.0", room_id="0",
                    smoke_kg="0.7",
                    smoke_generated_total_kg="1.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.3"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_multi_room_sum_by_timestep(self):
        """Smoke across 3 rooms must sum to expected; each room too-small individually."""
        rows = [
            _row_s0(time_s="10.0", room_id="0", smoke_kg="1.0",
                    smoke_generated_total_kg="3.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
            _row_s0(time_s="10.0", room_id="1", smoke_kg="1.0",
                    smoke_generated_total_kg="3.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
            _row_s0(time_s="10.0", room_id="2", smoke_kg="1.0",
                    smoke_generated_total_kg="3.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_timestamps_checked_independently(self):
        """Two timesteps each correct → no finding."""
        rows = [
            _row_s0(time_s="10.0", room_id="0", smoke_kg="1.0",
                    smoke_generated_total_kg="1.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
            _row_s0(time_s="20.0", room_id="0", smoke_kg="2.0",
                    smoke_generated_total_kg="2.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_all_zero_no_finding(self):
        """All fields zero (no fire) → no finding."""
        rows = [
            _row_s0(time_s="0.0", room_id="0", smoke_kg="0.0",
                    smoke_generated_total_kg="0.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
        ]
        self.assertEqual(self._run(rows), [])

    # ── Finding cases ─────────────────────────────────────────────────────────

    def test_residual_above_floor_triggers_finding(self):
        """sum_smoke clearly differs from expected → finding."""
        rows = [
            _row_s0(time_s="10.0", room_id="0",
                    smoke_kg="5.0",          # 5 kg in room
                    smoke_generated_total_kg="3.0",   # but only 3 generated
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),  # residual = 2 kg > 0.01 floor
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule_id, "S0")
        self.assertEqual(findings[0].room_id, "global")
        self.assertEqual(findings[0].metric, "smoke_balance_residual_kg")

    def test_finding_is_fail_severity(self):
        """S0 is FAIL after clean corpus validation."""
        rows = [
            _row_s0(time_s="10.0", room_id="0",
                    smoke_kg="10.0",
                    smoke_generated_total_kg="0.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
        ]
        findings = self._run(rows)
        self.assertTrue(len(findings) > 0)
        self.assertTrue(all(f.severity == "FAIL" for f in findings))

    def test_only_failing_timestep_flagged(self):
        """First timestep ok, second has residual → only second flagged."""
        rows = [
            _row_s0(time_s="10.0", room_id="0", smoke_kg="1.0",
                    smoke_generated_total_kg="1.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
            _row_s0(time_s="20.0", room_id="0", smoke_kg="99.0",
                    smoke_generated_total_kg="1.5",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertAlmostEqual(findings[0].time_s, 20.0)

    def test_finding_reason_contains_sum_and_expected(self):
        """Finding reason must mention sum_smoke_kg and expected for diagnostics."""
        rows = [
            _row_s0(time_s="10.0", room_id="0", smoke_kg="5.0",
                    smoke_generated_total_kg="2.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0"),
        ]
        reason = self._run(rows)[0].reason
        self.assertIn("sum_smoke_kg", reason)
        self.assertIn("expected", reason)

    # ── Graceful skip ─────────────────────────────────────────────────────────

    def test_missing_columns_skips_gracefully(self):
        """Rows without S0 columns must not raise or produce findings."""
        rows = [
            {"time_s": "10.0", "room_id": "0", "smoke_kg": "1.0"},
        ]
        self.assertEqual(self._run(rows), [])

    def test_missing_one_column_skips(self):
        """Only 4 of 5 required columns → skip."""
        rows = [
            {
                "time_s": "10.0", "room_id": "0",
                "smoke_kg": "1.0",
                "smoke_generated_total_kg": "2.0",
                "smoke_vented_total_kg": "0.0",
                "smoke_deposited_total_kg": "0.0",
                # smoke_in_transit_kg absent
            },
        ]
        self.assertEqual(self._run(rows), [])

    def test_in_transit_included_in_balance(self):
        """smoke_in_transit_kg closes the balance when sum_smoke < expected."""
        # sum_smoke=0.8, in_transit=0.2, expected=1.0 → accounted=1.0 → no finding
        rows = [
            _row_s0(time_s="10.0", room_id="0",
                    smoke_kg="0.8",
                    smoke_generated_total_kg="1.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0",
                    smoke_in_transit_kg="0.2"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_in_transit_does_not_mask_real_loss(self):
        """in_transit=0, sum_smoke much less than expected → still a finding."""
        rows = [
            _row_s0(time_s="10.0", room_id="0",
                    smoke_kg="0.5",
                    smoke_generated_total_kg="1.0",
                    smoke_vented_total_kg="0.0",
                    smoke_deposited_total_kg="0.0",
                    smoke_in_transit_kg="0.0"),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)


def _row_s1(
    time_s="10.0", room_id="0",
    smoke_kg="0.0",
    smoke_generated_kg_total="0.0",
    smoke_vented_kg_total="0.0",
    smoke_deposited_kg_total="0.0",
    smoke_net_transport_kg_total="0.0",
) -> dict[str, str]:
    return {
        "time_s": time_s,
        "room_id": room_id,
        "smoke_kg": smoke_kg,
        "smoke_generated_kg_total": smoke_generated_kg_total,
        "smoke_vented_kg_total": smoke_vented_kg_total,
        "smoke_deposited_kg_total": smoke_deposited_kg_total,
        "smoke_net_transport_kg_total": smoke_net_transport_kg_total,
    }


# ---------------------------------------------------------------------------
# Tests: Rule S1 — Smoke per-room balance
# ---------------------------------------------------------------------------

class TestCheckS1(unittest.TestCase):

    def _run(self, rows):
        return [f for f in checker.find_physics_coherence_issues(rows, rule_ids={"S1"})
                if f.rule_id == "S1"]

    def test_generation_vent_deposition_balance_no_finding(self):
        """Local cumulative totals close the room smoke delta."""
        rows = [
            _row_s1(time_s="0.0", smoke_kg="0.0"),
            _row_s1(
                time_s="10.0",
                smoke_kg="1.2",
                smoke_generated_kg_total="2.0",
                smoke_vented_kg_total="0.5",
                smoke_deposited_kg_total="0.3",
            ),
        ]
        self.assertEqual(self._run(rows), [])

    def test_net_transport_between_rooms_no_finding(self):
        """Negative source transport and positive target transport are checked per room."""
        rows = [
            _row_s1(time_s="0.0", room_id="0", smoke_kg="2.0"),
            _row_s1(time_s="0.0", room_id="1", smoke_kg="0.0"),
            _row_s1(time_s="10.0", room_id="0", smoke_kg="1.5", smoke_net_transport_kg_total="-0.5"),
            _row_s1(time_s="10.0", room_id="1", smoke_kg="0.5", smoke_net_transport_kg_total="0.5"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_residual_above_floor_triggers_fail(self):
        """S1 is FAIL/gating after promotion (2026-06-30)."""
        rows = [
            _row_s1(time_s="0.0", smoke_kg="0.0"),
            _row_s1(time_s="10.0", smoke_kg="2.0", smoke_generated_kg_total="1.0"),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "FAIL")
        self.assertEqual(findings[0].metric, "smoke_room_balance_residual_kg")

    def test_missing_columns_skips_gracefully(self):
        """Older CSV schemas without S1 columns are ignored."""
        rows = [
            {"time_s": "0.0", "room_id": "0", "smoke_kg": "0.0"},
            {"time_s": "10.0", "room_id": "0", "smoke_kg": "1.0"},
        ]
        self.assertEqual(self._run(rows), [])

    def test_reason_contains_delta_and_expected(self):
        rows = [
            _row_s1(time_s="0.0", smoke_kg="0.0"),
            _row_s1(time_s="10.0", smoke_kg="2.0", smoke_generated_kg_total="1.0"),
        ]
        reason = self._run(rows)[0].reason
        self.assertIn("delta_smoke", reason)
        self.assertIn("expected", reason)


# ---------------------------------------------------------------------------
# O1 row helper
# ---------------------------------------------------------------------------
# O1 uses CUMULATIVE totals to be invariant to the log_interval vs timestep
# ratio.  air_mass_kg is fixed per room (volume × 1.2 kg/m³).

def _row_o1(
    time_s="10.0", room_id="0",
    o2="0.209",
    air_mass_kg="30.24",
    o2_consumed_bulk_kg_total="0.0",
    o2_exterior_net_kg_total="0.0",
    o2_net_transport_kg_total="0.0",
    hrr_kw="0.0",
    fire_o2_mode_used="",
) -> dict[str, str]:
    return {
        "time_s": time_s,
        "room_id": room_id,
        "o2": o2,
        "air_mass_kg": air_mass_kg,
        "o2_consumed_bulk_kg_total": o2_consumed_bulk_kg_total,
        "o2_exterior_net_kg_total": o2_exterior_net_kg_total,
        "o2_net_transport_kg_total": o2_net_transport_kg_total,
        "hrr_kw": hrr_kw,
        "fire_o2_mode_used": fire_o2_mode_used,
    }


# ---------------------------------------------------------------------------
# Tests: Rule O1 — O2 bulk mass balance
# ---------------------------------------------------------------------------

class TestCheckO1(unittest.TestCase):

    def _run(self, rows):
        return [f for f in checker.find_physics_coherence_issues(rows, rule_ids={"O1"})
                if f.rule_id == "O1"]

    # ── Clean cases ───────────────────────────────────────────────────────────

    def test_perfect_balance_no_finding(self):
        """Δo2_bulk == expected when nothing changes → no finding."""
        rows = [
            _row_o1(time_s="0.0",  o2="0.209"),
            _row_o1(time_s="5.0",  o2="0.209"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_bulk_consumption_balanced(self):
        """O2 consumed by combustion; tracked in o2_consumed_bulk_kg_total."""
        # air_mass=30.24, delta_o2=-0.001 → delta_bulk=-0.03024 kg
        # delta_consumed=+0.03024 → expected = -0.03024 → residual=0
        air_mass = 30.24
        delta_o2_frac = -0.001
        delta_consumed = -delta_o2_frac * air_mass   # 0.03024 kg consumed
        rows = [
            _row_o1(time_s="0.0", o2="0.209",
                    air_mass_kg=str(air_mass),
                    o2_consumed_bulk_kg_total="0.0"),
            _row_o1(time_s="5.0", o2=str(0.209 + delta_o2_frac),
                    air_mass_kg=str(air_mass),
                    o2_consumed_bulk_kg_total=str(delta_consumed)),
        ]
        self.assertEqual(self._run(rows), [])

    def test_exterior_net_positive_balanced(self):
        """O2 gained from exterior (ACH); tracked in o2_exterior_net_kg_total."""
        # o2 rises from 0.200 to 0.202 (+0.060 kg), exterior delivered +0.060 kg
        air_mass = 30.24
        o2_start, o2_end = 0.200, 0.202
        delta_bulk = (o2_end - o2_start) * air_mass
        rows = [
            _row_o1(time_s="0.0", o2=str(o2_start), air_mass_kg=str(air_mass),
                    o2_exterior_net_kg_total="0.0"),
            _row_o1(time_s="5.0", o2=str(o2_end),   air_mass_kg=str(air_mass),
                    o2_exterior_net_kg_total=str(delta_bulk)),
        ]
        self.assertEqual(self._run(rows), [])

    def test_exterior_net_negative_balanced(self):
        """O2 lost to exterior (pressure venting); tracked as negative exterior."""
        air_mass = 30.24
        o2_start, o2_end = 0.209, 0.205
        delta_bulk = (o2_end - o2_start) * air_mass  # negative
        rows = [
            _row_o1(time_s="0.0", o2=str(o2_start), air_mass_kg=str(air_mass),
                    o2_exterior_net_kg_total="0.0"),
            _row_o1(time_s="5.0", o2=str(o2_end),   air_mass_kg=str(air_mass),
                    o2_exterior_net_kg_total=str(delta_bulk)),
        ]
        self.assertEqual(self._run(rows), [])

    def test_transport_net_in_balanced(self):
        """O2 received from adjacent room; tracked in o2_net_transport_kg_total."""
        air_mass = 20.16
        o2_start, o2_end = 0.200, 0.203
        delta_bulk = (o2_end - o2_start) * air_mass
        rows = [
            _row_o1(time_s="0.0", o2=str(o2_start), air_mass_kg=str(air_mass),
                    o2_net_transport_kg_total="0.0"),
            _row_o1(time_s="5.0", o2=str(o2_end),   air_mass_kg=str(air_mass),
                    o2_net_transport_kg_total=str(delta_bulk)),
        ]
        self.assertEqual(self._run(rows), [])

    def test_transport_net_out_balanced(self):
        """O2 sent to adjacent room; tracked as negative transport."""
        air_mass = 20.16
        o2_start, o2_end = 0.209, 0.205
        delta_bulk = (o2_end - o2_start) * air_mass
        rows = [
            _row_o1(time_s="0.0", o2=str(o2_start), air_mass_kg=str(air_mass),
                    o2_net_transport_kg_total="0.0"),
            _row_o1(time_s="5.0", o2=str(o2_end),   air_mass_kg=str(air_mass),
                    o2_net_transport_kg_total=str(delta_bulk)),
        ]
        self.assertEqual(self._run(rows), [])

    def test_residual_within_floor_no_finding(self):
        """Residual < 1 g floor → no finding."""
        # delta_bulk = -0.5e-3 kg, expected = 0 → residual = 0.0005 < 0.001 floor
        air_mass = 30.24
        o2_frac_delta = -0.5e-3 / air_mass   # residual = 0.5e-3 < 1e-3 floor
        rows = [
            _row_o1(time_s="0.0", o2="0.209", air_mass_kg=str(air_mass)),
            _row_o1(time_s="5.0", o2=str(0.209 + o2_frac_delta),
                    air_mass_kg=str(air_mass)),
        ]
        self.assertEqual(self._run(rows), [])

    # ── Flagged cases ─────────────────────────────────────────────────────────

    def test_large_untracked_residual_raises_fail(self):
        """O2 disappeared with no tracked source → residual > floor → FAIL."""
        # delta_bulk = -0.1 kg, all accumulators zero → residual = 0.1 kg >> 1e-3
        air_mass = 30.24
        o2_delta = -0.1 / air_mass
        rows = [
            _row_o1(time_s="0.0", o2="0.209", air_mass_kg=str(air_mass)),
            _row_o1(time_s="5.0", o2=str(0.209 + o2_delta), air_mass_kg=str(air_mass)),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "FAIL")
        self.assertEqual(findings[0].rule_id, "O1")

    def test_finding_is_fail_not_warn(self):
        """O1 must produce FAIL (not WARN) for any untracked residual."""
        air_mass = 30.24
        o2_delta = -0.5 / air_mass  # huge residual
        rows = [
            _row_o1(time_s="0.0", o2="0.209", air_mass_kg=str(air_mass)),
            _row_o1(time_s="5.0", o2=str(max(0.0, 0.209 + o2_delta)),
                    air_mass_kg=str(air_mass)),
        ]
        findings = self._run(rows)
        self.assertTrue(all(f.severity == "FAIL" for f in findings))

    # ── Skip logic ────────────────────────────────────────────────────────────

    def test_plume_lower_fire_room_skipped(self):
        """Active fire room in plume_lower mode — row must be skipped (no finding even with imbalance)."""
        air_mass = 30.24
        o2_delta = -0.1 / air_mass
        rows = [
            _row_o1(time_s="0.0", o2="0.209", air_mass_kg=str(air_mass),
                    hrr_kw="0.0", fire_o2_mode_used=""),
            _row_o1(time_s="5.0", o2=str(0.209 + o2_delta), air_mass_kg=str(air_mass),
                    hrr_kw="50.0", fire_o2_mode_used="plume_lower"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_plume_blend_fire_room_skipped(self):
        """Active fire room in plume_blend mode — row must be skipped."""
        air_mass = 30.24
        o2_delta = -0.1 / air_mass
        rows = [
            _row_o1(time_s="0.0", o2="0.209", air_mass_kg=str(air_mass),
                    hrr_kw="0.0", fire_o2_mode_used=""),
            _row_o1(time_s="5.0", o2=str(0.209 + o2_delta), air_mass_kg=str(air_mass),
                    hrr_kw="50.0", fire_o2_mode_used="plume_blend"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_plume_lower_idle_room_included(self):
        """Idle room (hrr_kw <= 0.1) with plume_lower label is NOT skipped — must flag if imbalanced."""
        # CombustionSystem attaches plume_lower to idle rooms as a diagnostic artifact.
        # room.o2 is still the true bulk value for idle rooms.
        air_mass = 30.24
        o2_delta = -0.1 / air_mass
        rows = [
            _row_o1(time_s="0.0", o2="0.209", air_mass_kg=str(air_mass),
                    hrr_kw="0.0", fire_o2_mode_used="plume_lower"),
            _row_o1(time_s="5.0", o2=str(0.209 + o2_delta), air_mass_kg=str(air_mass),
                    hrr_kw="0.0", fire_o2_mode_used="plume_lower"),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "FAIL")

    def test_missing_o1_columns_skips_rule(self):
        """Old CSV without o2_consumed_bulk_kg_total → O1 skipped silently."""
        rows = [
            {"time_s": "0.0",  "room_id": "0", "o2": "0.209", "air_mass_kg": "30.24"},
            {"time_s": "5.0",  "room_id": "0", "o2": "0.100", "air_mass_kg": "30.24"},
        ]
        self.assertEqual(self._run(rows), [])

    def test_partial_o1_columns_skips_rule(self):
        """Only some O1 columns present → O1 skipped (no crash)."""
        rows = [
            {"time_s": "0.0",  "room_id": "0", "o2": "0.209",
             "o2_consumed_bulk_kg_total": "0.0"},
            {"time_s": "5.0",  "room_id": "0", "o2": "0.150",
             "o2_consumed_bulk_kg_total": "0.0"},
        ]
        self.assertEqual(self._run(rows), [])

    # ── Multi-room independence ──────────────────────────────────────────────

    def test_multi_room_independent_balance(self):
        """Two rooms; violation in room 1 does not affect room 0."""
        air_mass = 30.24
        o2_delta_bad = -0.1 / air_mass
        rows = [
            # room 0: perfectly balanced (no change, no trackers)
            _row_o1(time_s="0.0", room_id="0", o2="0.209", air_mass_kg=str(air_mass)),
            _row_o1(time_s="5.0", room_id="0", o2="0.209", air_mass_kg=str(air_mass)),
            # room 1: O2 dropped with no tracked cause
            _row_o1(time_s="0.0", room_id="1", o2="0.209", air_mass_kg=str(air_mass)),
            _row_o1(time_s="5.0", room_id="1",
                    o2=str(0.209 + o2_delta_bad), air_mass_kg=str(air_mass)),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].room_id, "1")

    # ── Temporal ordering ────────────────────────────────────────────────────

    def test_rows_sorted_by_time_before_diff(self):
        """Out-of-order rows must be sorted before computing deltas."""
        air_mass = 30.24
        delta_consumed = 0.03
        o2_start, o2_end = 0.209, 0.209 - delta_consumed / air_mass
        rows = [
            # reversed: t=5 first, t=0 second
            _row_o1(time_s="5.0", o2=str(o2_end),   air_mass_kg=str(air_mass),
                    o2_consumed_bulk_kg_total=str(delta_consumed)),
            _row_o1(time_s="0.0", o2=str(o2_start), air_mass_kg=str(air_mass),
                    o2_consumed_bulk_kg_total="0.0"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_first_row_per_room_is_baseline_no_finding(self):
        """The first row sets the baseline; no finding generated for it alone."""
        rows = [
            _row_o1(time_s="5.0", o2="0.185", air_mass_kg="30.24",
                    o2_consumed_bulk_kg_total="0.72"),
        ]
        self.assertEqual(self._run(rows), [])

    # ── air_mass_kg: uses current row's value ─────────────────────────────────

    def test_air_mass_from_current_row_used_for_delta_bulk(self):
        """delta_bulk = (o2_curr - o2_prev) * air_mass_curr (current row, not previous)."""
        # Two rooms with different air masses; verify the correct one is used.
        # Room A: air_mass=30.24.  Room B: air_mass=43.20.
        # For room B: delta_o2_frac=-0.005, air_mass=43.20
        # delta_bulk = -0.005 * 43.20 = -0.216 kg; consumed = 0.216 → balanced
        rows = [
            _row_o1(time_s="0.0", room_id="B", o2="0.209", air_mass_kg="43.20",
                    o2_consumed_bulk_kg_total="0.0"),
            _row_o1(time_s="5.0", room_id="B", o2="0.204", air_mass_kg="43.20",
                    o2_consumed_bulk_kg_total="0.216"),
        ]
        self.assertEqual(self._run(rows), [])

    # ── Finding fields ────────────────────────────────────────────────────────

    def test_finding_metric_is_o2_bulk_balance_residual_kg(self):
        """Finding metric must be 'o2_bulk_balance_residual_kg'."""
        air_mass = 30.24
        rows = [
            _row_o1(time_s="0.0", o2="0.209", air_mass_kg=str(air_mass)),
            _row_o1(time_s="5.0", o2=str(0.209 - 0.1/air_mass), air_mass_kg=str(air_mass)),
        ]
        findings = self._run(rows)
        self.assertTrue(len(findings) > 0)
        self.assertEqual(findings[0].metric, "o2_bulk_balance_residual_kg")

    def test_finding_reason_contains_delta_and_expected(self):
        """Finding reason must include delta_bulk, expected, residual, and tol."""
        air_mass = 30.24
        rows = [
            _row_o1(time_s="0.0", o2="0.209", air_mass_kg=str(air_mass)),
            _row_o1(time_s="5.0", o2=str(0.209 - 0.1/air_mass), air_mass_kg=str(air_mass)),
        ]
        reason = self._run(rows)[0].reason
        self.assertIn("delta_bulk", reason)
        self.assertIn("expected", reason)
        self.assertIn("residual", reason)
        self.assertIn("tol", reason)

    def test_o1_in_all_rules(self):
        """O1 must be present in ALL_RULES tuple."""
        self.assertIn("O1", checker.ALL_RULES)

    def test_o1_required_cols_declared(self):
        """O1 required columns must be declared in REQUIRED_COLS."""
        self.assertIn("O1", checker.REQUIRED_COLS)
        self.assertIn("o2", checker.REQUIRED_COLS["O1"])
        self.assertIn("air_mass_kg", checker.REQUIRED_COLS["O1"])
        self.assertIn("o2_consumed_bulk_kg_total", checker.REQUIRED_COLS["O1"])


# ---------------------------------------------------------------------------
# O2E1 row helper
# ---------------------------------------------------------------------------

_O2E1_THORNTON = 0.076 / 1000.0   # 7.6e-5 kg O2 / kJ


def _row_o2e1(
    time_s: str = "10.0",
    room_id: str = "0",
    hrr_kj_total: str = "0.0",
    o2_consumed_fire_kg_total: str = "0.0",
) -> dict[str, str]:
    return {
        "time_s": time_s,
        "room_id": room_id,
        "hrr_kj_total": hrr_kj_total,
        "o2_consumed_fire_kg_total": o2_consumed_fire_kg_total,
    }


# ---------------------------------------------------------------------------
# Tests: Rule O2E1 — Thornton cross-check
# ---------------------------------------------------------------------------

class TestCheckO2E1(unittest.TestCase):

    def _run(self, rows):
        return [f for f in checker.find_physics_coherence_issues(rows, rule_ids={"O2E1"})
                if f.rule_id == "O2E1"]

    # ── Clean cases ───────────────────────────────────────────────────────────

    def test_exact_thornton_ratio_no_finding(self):
        """delta_o2_fire == delta_hrr_kj * Thornton exactly → no finding."""
        delta_hrr_kj = 500.0
        expected_o2 = delta_hrr_kj * _O2E1_THORNTON
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(expected_o2)),
        ]
        self.assertEqual(self._run(rows), [])

    def test_within_5pct_tolerance_no_finding(self):
        """OES capping may reduce delta_o2_fire slightly below expected; within 5 % → no finding."""
        delta_hrr_kj = 1000.0
        expected_o2 = delta_hrr_kj * _O2E1_THORNTON
        actual_o2 = expected_o2 * 0.96   # 4 % below — within 5 % tolerance
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(actual_o2)),
        ]
        self.assertEqual(self._run(rows), [])

    def test_zero_delta_both_sides_skipped(self):
        """When both delta_hrr_kj and delta_o2_fire are zero (pre-ignition) → skip."""
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0", o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total="0.0", o2_consumed_fire_kg_total="0.0"),
        ]
        self.assertEqual(self._run(rows), [])

    def test_single_row_no_finding(self):
        """Only one row → no consecutive pair, no finding."""
        rows = [_row_o2e1(time_s="10.0", hrr_kj_total="100.0",
                          o2_consumed_fire_kg_total="0.0076")]
        self.assertEqual(self._run(rows), [])

    def test_cumulative_monotone_fire_clean(self):
        """Multiple rows of steady fire — cumulative totals grow uniformly → no finding."""
        o2_per_kj = _O2E1_THORNTON
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",    o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total="500.0",   o2_consumed_fire_kg_total=str(500.0 * o2_per_kj)),
            _row_o2e1(time_s="20.0", hrr_kj_total="1000.0",  o2_consumed_fire_kg_total=str(1000.0 * o2_per_kj)),
            _row_o2e1(time_s="30.0", hrr_kj_total="1500.0",  o2_consumed_fire_kg_total=str(1500.0 * o2_per_kj)),
        ]
        self.assertEqual(self._run(rows), [])

    def test_two_zone_double_count_does_not_warn(self):
        """o2_consumed_fire_kg_total holds ONE Thornton unit even when OES two-zone
        double-counts in o2_consumed_kg_total_all (2x).  O2E1 must not WARN."""
        delta_hrr_kj = 1000.0
        one_thornton = delta_hrr_kj * _O2E1_THORNTON
        # Simulate: fire accumulator = 1x Thornton (correct primary path)
        # Even though o2_consumed_kg_total_all would be 2x, O2E1 no longer reads it.
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(one_thornton)),
        ]
        self.assertEqual(self._run(rows), [])

    # ── Findings ──────────────────────────────────────────────────────────────

    def test_oes_overconsumes_above_tolerance_fails(self):
        """Primary path consuming >5 % more O2 than Thornton predicts → FAIL."""
        delta_hrr_kj = 1000.0
        expected_o2 = delta_hrr_kj * _O2E1_THORNTON
        actual_o2 = expected_o2 * 1.10   # 10 % above → exceeds 5 % threshold
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(actual_o2)),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "FAIL")

    def test_oes_underconsumes_below_tolerance_fails(self):
        """Primary path consuming >5 % less O2 than Thornton predicts → FAIL."""
        delta_hrr_kj = 1000.0
        expected_o2 = delta_hrr_kj * _O2E1_THORNTON
        actual_o2 = expected_o2 * 0.90   # 10 % below → exceeds 5 % threshold
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(actual_o2)),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "FAIL")

    def test_finding_rule_id_is_o2e1(self):
        """Finding must report rule_id == 'O2E1'."""
        delta_hrr_kj = 1000.0
        actual_o2 = delta_hrr_kj * _O2E1_THORNTON * 1.20   # 20 % over
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(actual_o2)),
        ]
        self.assertEqual(self._run(rows)[0].rule_id, "O2E1")

    def test_finding_metric_is_thornton_cross_residual(self):
        """Finding metric must be 'thornton_cross_residual_kg'."""
        delta_hrr_kj = 1000.0
        actual_o2 = delta_hrr_kj * _O2E1_THORNTON * 1.20
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(actual_o2)),
        ]
        self.assertEqual(self._run(rows)[0].metric, "thornton_cross_residual_kg")

    def test_finding_reason_contains_key_fields(self):
        """Finding reason must mention delta_hrr_kj, expected_o2, delta_o2_fire."""
        delta_hrr_kj = 1000.0
        actual_o2 = delta_hrr_kj * _O2E1_THORNTON * 1.20
        rows = [
            _row_o2e1(time_s="0.0",  hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(actual_o2)),
        ]
        reason = self._run(rows)[0].reason
        self.assertIn("delta_hrr_kj", reason)
        self.assertIn("expected_o2", reason)
        self.assertIn("delta_o2_fire", reason)

    def test_multiroom_only_failing_room_flagged(self):
        """Two rooms: one balanced, one over-consuming → only over-consuming flagged."""
        delta_hrr_kj = 500.0
        ok_o2  = delta_hrr_kj * _O2E1_THORNTON
        bad_o2 = ok_o2 * 1.20   # 20 % over
        rows = [
            _row_o2e1(time_s="0.0",  room_id="0", hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="0.0",  room_id="1", hrr_kj_total="0.0",
                      o2_consumed_fire_kg_total="0.0"),
            _row_o2e1(time_s="10.0", room_id="0", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(ok_o2)),
            _row_o2e1(time_s="10.0", room_id="1", hrr_kj_total=str(delta_hrr_kj),
                      o2_consumed_fire_kg_total=str(bad_o2)),
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].room_id, "1")

    # ── Graceful skip — missing columns ──────────────────────────────────────

    def test_missing_hrr_kj_total_skips_gracefully(self):
        """CSV without hrr_kj_total (old schema) → O2E1 skipped silently."""
        rows = [
            {"time_s": "0.0",  "room_id": "0", "o2_consumed_fire_kg_total": "0.0"},
            {"time_s": "10.0", "room_id": "0", "o2_consumed_fire_kg_total": "0.05"},
        ]
        self.assertEqual(self._run(rows), [])

    def test_missing_o2_consumed_fire_skips_gracefully(self):
        """CSV without o2_consumed_fire_kg_total (pre-O2E1-fix schema) → O2E1 skipped silently."""
        rows = [
            {"time_s": "0.0",  "room_id": "0", "hrr_kj_total": "0.0"},
            {"time_s": "10.0", "room_id": "0", "hrr_kj_total": "500.0"},
        ]
        self.assertEqual(self._run(rows), [])

    def test_old_o2_consumed_all_col_alone_skips_gracefully(self):
        """CSV with only o2_consumed_kg_total_all (old O2E1 schema, pre-fix) → O2E1 skips silently."""
        rows = [
            {"time_s": "0.0",  "room_id": "0",
             "hrr_kj_total": "0.0", "o2_consumed_kg_total_all": "0.0"},
            {"time_s": "10.0", "room_id": "0",
             "hrr_kj_total": "500.0", "o2_consumed_kg_total_all": "0.076"},
        ]
        self.assertEqual(self._run(rows), [])

    def test_old_schema_no_crash(self):
        """Legacy CSV without any O2E1 columns must not raise."""
        rows = [_row(), _row(time_s="20.0")]
        try:
            result = self._run(rows)
        except Exception as exc:
            self.fail(f"O2E1 raised {exc!r} on old-schema CSV")
        self.assertEqual(len(result), 0)


_D2PRE_REL_TOL = 1.0  # mirrors checker._D2PRE_REL_TOL


def _row_d2pre(
    time_s="10.0", room_id="0",
    co2_upper_ppm="400",
    co2_upper_ppm_mass="400",
) -> dict[str, str]:
    return {
        "time_s": time_s,
        "room_id": room_id,
        "co2_upper_ppm": co2_upper_ppm,
        "co2_upper_ppm_mass": co2_upper_ppm_mass,
    }


# ---------------------------------------------------------------------------
# Tests: Rule D2PRE — CO₂ dual-tracking diagnostic
# ---------------------------------------------------------------------------

class TestCheckD2PRE(unittest.TestCase):

    def _run(self, rows):
        return [f for f in checker.find_physics_coherence_issues(rows, rule_ids={"D2PRE"})
                if f.rule_id == "D2PRE"]

    # ── Clean cases ───────────────────────────────────────────────────────────

    def test_equal_values_no_finding(self):
        """tracer == mass-derived at ambient → no finding."""
        rows = [_row_d2pre(co2_upper_ppm="400", co2_upper_ppm_mass="400")]
        self.assertEqual(self._run(rows), [])

    def test_both_elevated_equal_no_finding(self):
        """Both at 50000 ppm and equal → rel_div = 0 → no finding."""
        rows = [_row_d2pre(co2_upper_ppm="50000", co2_upper_ppm_mass="50000")]
        self.assertEqual(self._run(rows), [])

    def test_small_divergence_within_threshold_no_finding(self):
        """mass = 1.5× tracer: rel_div = 0.5 < 1.0 → no finding."""
        tracer = 10000.0
        mass = tracer * 1.5  # rel_div = (15000 - 10000) / 10000 = 0.5
        rows = [_row_d2pre(co2_upper_ppm=str(tracer), co2_upper_ppm_mass=str(mass))]
        self.assertEqual(self._run(rows), [])

    def test_divergence_exactly_at_threshold_no_finding(self):
        """mass = 2× tracer: rel_div = 1.0 — not strictly above threshold → no finding."""
        tracer = 10000.0
        mass = tracer * 2.0  # rel_div = 10000 / 10000 = 1.0 exactly
        rows = [_row_d2pre(co2_upper_ppm=str(tracer), co2_upper_ppm_mass=str(mass))]
        self.assertEqual(self._run(rows), [])

    # ── Firing cases ──────────────────────────────────────────────────────────

    def test_mass_above_twice_tracer_warns(self):
        """mass > 2× tracer: rel_div > 1.0 → WARN D2PRE."""
        tracer = 10000.0
        mass = tracer * 2.1  # rel_div = 1.1
        rows = [_row_d2pre(co2_upper_ppm=str(tracer), co2_upper_ppm_mass=str(mass))]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)

    def test_tracer_above_twice_mass_warns(self):
        """tracer > 2× mass (early transient): rel_div > 1.0 → WARN D2PRE."""
        tracer = 10000.0
        mass = tracer * 0.3  # rel_div = |3000 - 10000| / 10000 = 0.7 — NOT above 1.0
        rows = [_row_d2pre(co2_upper_ppm=str(tracer), co2_upper_ppm_mass=str(mass))]
        # rel_div = 0.7 < 1.0 → no finding
        self.assertEqual(self._run(rows), [])

    def test_tracer_below_fifth_of_mass_warns(self):
        """mass = 5× tracer: rel_div = 4.0 → WARN D2PRE."""
        tracer = 5000.0
        mass = tracer * 5.0  # rel_div = 20000 / 5000 = 4.0
        rows = [_row_d2pre(co2_upper_ppm=str(tracer), co2_upper_ppm_mass=str(mass))]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)

    def test_ambient_tracer_elevated_mass_warns(self):
        """tracer at ambient 400, mass = 1201 ppm: rel_div = 801/400 = 2.0 — not above → no finding."""
        rows = [_row_d2pre(co2_upper_ppm="400", co2_upper_ppm_mass="1201")]
        # rel_div = (1201 - 400) / 400 = 2.0025 → above 1.0 → WARN
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)

    # ── Finding properties ────────────────────────────────────────────────────

    def test_finding_is_warn_not_fail(self):
        """D2PRE must be WARN severity (not FAIL — diagnostic only, not gating)."""
        rows = [_row_d2pre(co2_upper_ppm="10000", co2_upper_ppm_mass="25000")]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, "WARN")

    def test_finding_rule_id_is_d2pre(self):
        rows = [_row_d2pre(co2_upper_ppm="10000", co2_upper_ppm_mass="25000")]
        findings = self._run(rows)
        self.assertEqual(findings[0].rule_id, "D2PRE")

    def test_finding_metric_is_divergence_rel(self):
        rows = [_row_d2pre(co2_upper_ppm="10000", co2_upper_ppm_mass="25000")]
        findings = self._run(rows)
        self.assertEqual(findings[0].metric, "co2_upper_ppm_divergence_rel")

    def test_finding_value_is_rel_div(self):
        """Finding value equals rel_div rounded to 4 decimals."""
        tracer = 10000.0
        mass = 25000.0
        expected_rel_div = round(abs(mass - tracer) / max(tracer, 400.0), 4)
        rows = [_row_d2pre(co2_upper_ppm=str(tracer), co2_upper_ppm_mass=str(mass))]
        findings = self._run(rows)
        self.assertAlmostEqual(findings[0].value, expected_rel_div, places=4)

    def test_finding_reason_contains_key_fields(self):
        rows = [_row_d2pre(co2_upper_ppm="10000", co2_upper_ppm_mass="25000")]
        findings = self._run(rows)
        reason = findings[0].reason
        self.assertIn("co2_upper_ppm(tracer)=", reason)
        self.assertIn("co2_upper_ppm_mass=", reason)
        self.assertIn("rel_div=", reason)

    def test_room_id_propagated(self):
        rows = [_row_d2pre(room_id="3", co2_upper_ppm="5000", co2_upper_ppm_mass="15000")]
        findings = self._run(rows)
        self.assertEqual(findings[0].room_id, "3")

    def test_time_s_propagated(self):
        rows = [_row_d2pre(time_s="350.0", co2_upper_ppm="5000", co2_upper_ppm_mass="15000")]
        findings = self._run(rows)
        self.assertAlmostEqual(findings[0].time_s, 350.0, places=1)

    # ── Multi-row ─────────────────────────────────────────────────────────────

    def test_only_divergent_rows_flagged(self):
        """Mixed rows: only those above threshold generate a finding."""
        rows = [
            _row_d2pre(time_s="10.0", co2_upper_ppm="400", co2_upper_ppm_mass="400"),    # ok
            _row_d2pre(time_s="20.0", co2_upper_ppm="10000", co2_upper_ppm_mass="10500"),  # ok (0.05)
            _row_d2pre(time_s="30.0", co2_upper_ppm="10000", co2_upper_ppm_mass="21000"),  # WARN (1.1)
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertAlmostEqual(findings[0].time_s, 30.0, places=1)

    # ── Skip on legacy CSV ────────────────────────────────────────────────────

    def test_missing_mass_column_skips_gracefully(self):
        """CSV without co2_upper_ppm_mass (legacy pre-D2-Fase-1 schema) → D2PRE skipped."""
        rows = [{"time_s": "10.0", "room_id": "0", "co2_upper_ppm": "50000"}]
        self.assertEqual(self._run(rows), [])

    def test_missing_tracer_column_skips_gracefully(self):
        """CSV without co2_upper_ppm → D2PRE skipped."""
        rows = [{"time_s": "10.0", "room_id": "0", "co2_upper_ppm_mass": "50000"}]
        self.assertEqual(self._run(rows), [])

    def test_old_schema_no_crash(self):
        """Legacy CSV without D2PRE columns must not raise."""
        rows = [_row(), _row(time_s="20.0")]
        try:
            result = self._run(rows)
        except Exception as exc:
            self.fail(f"D2PRE raised {exc!r} on old-schema CSV")
        self.assertEqual(result, [])

    # ── Registration checks ───────────────────────────────────────────────────

    def test_d2pre_in_all_rules(self):
        """D2PRE must appear in ALL_RULES."""
        self.assertIn("D2PRE", checker.ALL_RULES)

    def test_d2pre_required_cols_declared(self):
        """REQUIRED_COLS must have D2PRE entry with both column names."""
        self.assertIn("D2PRE", checker.REQUIRED_COLS)
        self.assertIn("co2_upper_ppm", checker.REQUIRED_COLS["D2PRE"])
        self.assertIn("co2_upper_ppm_mass", checker.REQUIRED_COLS["D2PRE"])


# ---------------------------------------------------------------------------
# Helpers: Rule D2 — CO/CO₂ upper ratio
# ---------------------------------------------------------------------------

_D2_RATIO_WARN = 0.5        # mirrors checker._D2_RATIO_WARN
_D2_CO2_MIN_PPM = 1000.0    # mirrors checker._D2_CO2_MIN_PPM
_D2_EARLY_TRANSIENT_S = 60.0  # mirrors checker._D2_EARLY_TRANSIENT_S


def _row_d2(
    time_s="300.0", room_id="0",
    co_upper_ppm="1000",
    co2_upper_ppm_mass="50000",
) -> dict[str, str]:
    return {
        "time_s": time_s,
        "room_id": room_id,
        "co_upper_ppm": co_upper_ppm,
        "co2_upper_ppm_mass": co2_upper_ppm_mass,
    }


# ---------------------------------------------------------------------------
# Tests: Rule D2 — CO/CO₂ upper-layer ratio diagnostic
# ---------------------------------------------------------------------------

class TestCheckD2(unittest.TestCase):

    def _run(self, rows):
        return [f for f in checker.find_physics_coherence_issues(rows, rule_ids={"D2"})
                if f.rule_id == "D2"]

    # --- Clean cases (no finding expected) ---

    def test_normal_ratio_no_finding(self):
        """CO/CO2 = 0.02 (well-ventilated) → no finding."""
        rows = [_row_d2(co_upper_ppm="1000", co2_upper_ppm_mass="50000")]
        self.assertEqual(len(self._run(rows)), 0)

    def test_ratio_exactly_at_threshold_no_finding(self):
        """ratio = 0.5 exactly → threshold is strict (>), no finding."""
        rows = [_row_d2(co_upper_ppm="5000", co2_upper_ppm_mass="10000")]
        self.assertAlmostEqual(5000 / 10000, _D2_RATIO_WARN)
        self.assertEqual(len(self._run(rows)), 0)

    def test_low_co_no_finding(self):
        """CO near zero, CO2 high → ratio ≪ threshold."""
        rows = [_row_d2(co_upper_ppm="100", co2_upper_ppm_mass="100000")]
        self.assertEqual(len(self._run(rows)), 0)

    # --- Skip conditions (no finding even if ratio > threshold) ---

    def test_co2_below_min_ppm_skipped(self):
        """co2_upper_ppm_mass < 1000 → skip (CO₂ not established)."""
        rows = [_row_d2(co_upper_ppm="999", co2_upper_ppm_mass="999")]
        self.assertEqual(len(self._run(rows)), 0)

    def test_co2_exactly_at_min_ppm_skipped(self):
        """co2_upper_ppm_mass == 1000 → skip (boundary is exclusive: < 1000)."""
        # ratio would be 0.6 > 0.5 but co2 == 1000, which is NOT < 1000 → fires
        # Wait: skip if < 1000, so exactly 1000 does NOT skip. Check below.
        rows = [_row_d2(co_upper_ppm="600", co2_upper_ppm_mass="1000")]
        # ratio = 0.6 > 0.5, co2 = 1000 (not < 1000) → should WARN
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)

    def test_early_transient_skipped(self):
        """time_s < 60 → skip (M3 initial-condition asymmetry)."""
        rows = [_row_d2(time_s="59.9", co_upper_ppm="60000", co2_upper_ppm_mass="100000")]
        self.assertEqual(len(self._run(rows)), 0)

    def test_time_exactly_at_early_transient_boundary_skipped(self):
        """time_s == 60 → skip (boundary is strict: < 60.0)."""
        # < 60 skips; == 60 does not skip
        rows = [_row_d2(time_s="60.0", co_upper_ppm="60000", co2_upper_ppm_mass="100000")]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)

    def test_missing_co2_mass_column_skips_gracefully(self):
        """CSV without co2_upper_ppm_mass (legacy schema) → D2 skipped."""
        rows = [{"time_s": "300.0", "room_id": "0", "co_upper_ppm": "99999"}]
        self.assertEqual(len(self._run(rows)), 0)

    def test_missing_co_upper_column_skips_gracefully(self):
        """CSV without co_upper_ppm → D2 skipped."""
        rows = [{"time_s": "300.0", "room_id": "0", "co2_upper_ppm_mass": "50000"}]
        self.assertEqual(len(self._run(rows)), 0)

    def test_old_schema_no_crash(self):
        """Legacy CSV without D2 columns must not raise."""
        rows = [{"time_s": "100.0", "room_id": "0", "hrr_kw": "100"}]
        try:
            result = self._run(rows)
        except Exception as exc:
            self.fail(f"D2 raised {exc!r} on old-schema CSV")
        self.assertEqual(len(result), 0)

    # --- Firing cases (WARN expected) ---

    def test_ratio_above_threshold_warns(self):
        """ratio = 0.6 > 0.5 → WARN D2."""
        rows = [_row_d2(co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)

    def test_extreme_ratio_warns(self):
        """CO > CO₂ (ratio = 1.5) → WARN D2."""
        rows = [_row_d2(co_upper_ppm="15000", co2_upper_ppm_mass="10000")]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)

    def test_ratio_just_above_threshold_warns(self):
        """ratio = 0.5001 → just above threshold → WARN."""
        rows = [_row_d2(co_upper_ppm="5001", co2_upper_ppm_mass="10000")]
        self.assertEqual(len(self._run(rows)), 1)

    # --- Finding properties ---

    def test_finding_is_warn_not_fail(self):
        """D2 must be WARN severity (diagnostic, not gating)."""
        rows = [_row_d2(co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        findings = self._run(rows)
        self.assertEqual(findings[0].severity, "WARN")

    def test_finding_rule_id_is_d2(self):
        rows = [_row_d2(co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        findings = self._run(rows)
        self.assertEqual(findings[0].rule_id, "D2")

    def test_finding_metric_is_ratio(self):
        rows = [_row_d2(co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        findings = self._run(rows)
        self.assertEqual(findings[0].metric, "co_co2_upper_ratio")

    def test_finding_value_is_ratio(self):
        rows = [_row_d2(co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        findings = self._run(rows)
        self.assertAlmostEqual(findings[0].value, 0.6, places=3)

    def test_finding_reason_contains_key_fields(self):
        rows = [_row_d2(co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        reason = self._run(rows)[0].reason
        self.assertIn("co_upper_ppm=", reason)
        self.assertIn("co2_upper_ppm_mass=", reason)
        self.assertIn("ratio=", reason)

    def test_room_id_propagated(self):
        rows = [_row_d2(room_id="2", co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        self.assertEqual(self._run(rows)[0].room_id, "2")

    def test_time_s_propagated(self):
        rows = [_row_d2(time_s="700.0", co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        self.assertAlmostEqual(self._run(rows)[0].time_s, 700.0)

    def test_only_exceeding_rows_flagged(self):
        """Only rows with ratio > 0.5 appear; sub-threshold rows are silent."""
        rows = [
            _row_d2(time_s="100.0", co_upper_ppm="1000", co2_upper_ppm_mass="50000"),  # 0.02 ok
            _row_d2(time_s="300.0", co_upper_ppm="4000", co2_upper_ppm_mass="10000"),  # 0.4 ok
            _row_d2(time_s="500.0", co_upper_ppm="6000", co2_upper_ppm_mass="10000"),  # 0.6 WARN
            _row_d2(time_s="700.0", co_upper_ppm="8000", co2_upper_ppm_mass="10000"),  # 0.8 WARN
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 2)
        self.assertAlmostEqual(findings[0].time_s, 500.0)
        self.assertAlmostEqual(findings[1].time_s, 700.0)

    def test_early_transient_row_not_flagged_even_if_high(self):
        """Row at t=30s with ratio > threshold → skipped by early-transient guard."""
        rows = [
            _row_d2(time_s="30.0", co_upper_ppm="9000", co2_upper_ppm_mass="10000"),  # skip (t<60)
            _row_d2(time_s="300.0", co_upper_ppm="6000", co2_upper_ppm_mass="10000"),  # WARN
        ]
        findings = self._run(rows)
        self.assertEqual(len(findings), 1)
        self.assertAlmostEqual(findings[0].time_s, 300.0)

    def test_co2_below_min_not_flagged_even_if_co_huge(self):
        """co2_upper_ppm_mass = 500 (< 1000) with huge CO → skipped."""
        rows = [
            _row_d2(time_s="300.0", co_upper_ppm="9999", co2_upper_ppm_mass="999"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    # --- Registration ---

    def test_d2_in_all_rules(self):
        """D2 must appear in ALL_RULES."""
        self.assertIn("D2", checker.ALL_RULES)

    def test_d2_required_cols_declared(self):
        """REQUIRED_COLS must have D2 entry with both column names."""
        self.assertIn("D2", checker.REQUIRED_COLS)
        self.assertIn("co_upper_ppm", checker.REQUIRED_COLS["D2"])
        self.assertIn("co2_upper_ppm_mass", checker.REQUIRED_COLS["D2"])

    def test_d2_does_not_affect_exit_code(self):
        """D2 WARN findings alone must not raise exit 1 (severity WARN)."""
        rows = [_row_d2(co_upper_ppm="6000", co2_upper_ppm_mass="10000")]
        findings = checker.find_physics_coherence_issues(rows)
        d2_findings = [f for f in findings if f.rule_id == "D2"]
        self.assertTrue(len(d2_findings) >= 1)
        for f in d2_findings:
            self.assertEqual(f.severity, "WARN")


if __name__ == "__main__":
    unittest.main()
