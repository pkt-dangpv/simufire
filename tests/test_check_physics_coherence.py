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

    def test_known_intentional_controls_is_frozenset(self):
        self.assertIsInstance(suite.KNOWN_INTENTIONAL_CONTROLS, frozenset)


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
    fuel_remaining_MJ="50.0",
    fuel_consumed_MJ_total="0.0",
) -> dict[str, str]:
    return {
        "time_s": time_s, "room_id": room_id,
        "fuel_remaining_MJ": fuel_remaining_MJ,
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
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="0.5"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_no_fire_no_finding(self):
        """No consumption and no change in remaining → trivially balanced."""
        rows = [
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_fuel_depleted_to_zero_no_finding(self):
        """Fuel reaches zero and stays there — balance holds."""
        rows = [
            _row_e1(time_s="0.0",  fuel_remaining_MJ="1.0",  fuel_consumed_MJ_total="49.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="0.0",  fuel_consumed_MJ_total="50.0"),
            _row_e1(time_s="20.0", fuel_remaining_MJ="0.0",  fuel_consumed_MJ_total="50.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_small_residual_within_relative_tolerance_no_finding(self):
        """Residual of 0.5 % of expected is within the 1 % tolerance."""
        # delta_remaining=-1.0, delta_consumed=1.0, expected=-1.0
        # residual = |(-1.0) - (-1.0)| = 0 — use a tiny imprecision instead
        # residual = 0.005 MJ on expected = 1.0 → 0.5 % < 1 % → clean
        rows = [
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.000", fuel_consumed_MJ_total="0.000"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="48.995", fuel_consumed_MJ_total="1.000"),
        ]
        # delta_remaining = -1.005, expected = -1.000, residual = 0.005 < 0.01 (1%)
        self.assertEqual(len(self._run(rows)), 0)

    # ── Flagged cases ─────────────────────────────────────────────────────────

    def test_large_balance_residual_flagged(self):
        """Residual much larger than tolerance raises E1 finding."""
        # delta_remaining=-0.5, delta_consumed=1.0, expected=-1.0, residual=0.5 >> 0.01
        rows = [
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="1.0"),
        ]
        findings = self._run(rows)
        self.assertGreater(len(findings), 0)
        self.assertTrue(any(f.metric == "fuel_balance_residual_MJ" for f in findings))

    def test_fuel_increased_flagged(self):
        """fuel_remaining_MJ increasing is physically impossible — must flag."""
        # delta_remaining = +2.0 (fuel appeared from nowhere)
        rows = [
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="5.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="52.0", fuel_consumed_MJ_total="5.0"),
        ]
        findings = self._run(rows)
        self.assertGreater(len(findings), 0)
        self.assertTrue(any(f.metric == "fuel_remaining_increased_MJ" for f in findings))

    def test_consumed_without_remaining_decrease_flagged(self):
        """Consumed increased but remaining didn't decrease → balance residual."""
        rows = [
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="2.0"),
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
            _row_e1(time_s="0.0",  room_id="0", fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", room_id="0", fuel_remaining_MJ="49.0", fuel_consumed_MJ_total="1.0"),
            # Room 1: imbalanced
            _row_e1(time_s="0.0",  room_id="1", fuel_remaining_MJ="30.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", room_id="1", fuel_remaining_MJ="29.0", fuel_consumed_MJ_total="5.0"),
        ]
        findings = self._run(rows)
        room_ids = {f.room_id for f in findings}
        self.assertIn("1", room_ids)
        self.assertNotIn("0", room_ids)

    def test_rows_sorted_by_time_before_diff(self):
        """Out-of-order rows must be sorted before computing deltas."""
        rows = [
            _row_e1(time_s="10.0", fuel_remaining_MJ="49.0", fuel_consumed_MJ_total="1.0"),
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_first_row_per_room_is_baseline_no_finding(self):
        """The first row sets the baseline; no finding is generated for it."""
        rows = [
            _row_e1(time_s="5.0", fuel_remaining_MJ="48.0", fuel_consumed_MJ_total="2.0"),
        ]
        self.assertEqual(len(self._run(rows)), 0)

    # ── Schema / graceful skip ─────────────────────────────────────────────────

    def test_missing_fuel_consumed_column_skips_rule(self):
        """E1 skips gracefully when fuel_consumed_MJ_total is absent."""
        rows = [
            {"time_s": "0.0",  "room_id": "0", "fuel_remaining_MJ": "50.0"},
            {"time_s": "10.0", "room_id": "0", "fuel_remaining_MJ": "45.0"},
        ]
        self.assertEqual(len(self._run(rows)), 0)

    def test_missing_fuel_remaining_column_skips_rule(self):
        """E1 skips gracefully when fuel_remaining_MJ is absent (old schema)."""
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
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="5.0"),
        ]
        findings = self._run(rows)
        self.assertTrue(all(f.rule_id == "E1" for f in findings))

    def test_finding_severity_is_warn(self):
        """E1 is WARN until validated clean on the full reference suite."""
        rows = [
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="5.0"),
        ]
        findings = self._run(rows)
        self.assertTrue(len(findings) > 0)
        self.assertTrue(all(f.severity == "WARN" for f in findings))

    def test_finding_reason_contains_delta_and_expected(self):
        """Finding reason must contain delta_remaining and expected for diagnostics."""
        rows = [
            _row_e1(time_s="0.0",  fuel_remaining_MJ="50.0", fuel_consumed_MJ_total="0.0"),
            _row_e1(time_s="10.0", fuel_remaining_MJ="49.5", fuel_consumed_MJ_total="5.0"),
        ]
        reason = self._run(rows)[0].reason
        self.assertIn("delta_remaining", reason)
        self.assertIn("expected", reason)


if __name__ == "__main__":
    unittest.main()
