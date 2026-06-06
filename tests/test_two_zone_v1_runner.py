"""Structural checks for the dedicated TwoZoneV1 validation runner."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
RUNNER_PATH = ROOT / "sim" / "validation" / "run_two_zone_v1_checks.ps1"
RUNNER = RUNNER_PATH.read_text(encoding="utf-8")


class TestTwoZoneV1Runner(unittest.TestCase):
    def test_runner_exists(self):
        self.assertTrue(RUNNER_PATH.exists())

    def test_runner_executes_specific_unit_modules(self):
        for module in (
            "tests.test_two_zone_energy_core",
            "tests.test_two_zone_opening_flow",
            "tests.test_fire_o2_mode",
            "tests.test_legacy_two_zone_compare",
        ):
            self.assertIn(module, RUNNER)
        self.assertIn("-m unittest @unitModules -v", RUNNER)

    def test_runner_uses_strict_two_zone_v1_contract(self):
        self.assertIn("run_legacy_two_zone_compare.ps1", RUNNER)
        self.assertIn("-Action compare", RUNNER)
        self.assertIn("-CandidateMode two-zone", RUNNER)
        self.assertIn("-TwoZoneV1", RUNNER)
        self.assertNotIn("-AllowContractFailure", RUNNER)

    def test_runner_audits_candidate_reports(self):
        self.assertIn("two-zone-opening-flow-canonical-pressure", RUNNER)
        self.assertIn("function Get-ManifestCaseNames", RUNNER)
        self.assertIn("function Assert-ExactCaseSet", RUNNER)
        self.assertIn('Assert-ExactCaseSet $reportNames $caseNames "reportes candidato"', RUNNER)
        self.assertIn('$report.engine_mode -ne "two-zone"', RUNNER)
        self.assertIn("$report.two_zone_v1_profile -ne $true", RUNNER)
        for flag in (
            "two_zone_solver_enabled",
            "two_zone_opening_flow_enabled",
            "phase3_pressure_canonical_enabled",
        ):
            self.assertIn(flag, RUNNER)

    def test_runner_checks_carbon_residual(self):
        self.assertIn("peak_global_carbon_transport_residual_kg_abs", RUNNER)
        self.assertIn("-gt 0.02", RUNNER)

    def test_runner_checks_fresh_reports_after_runtime(self):
        self.assertIn("$freshAfter = $null", RUNNER)
        self.assertIn("function Assert-ReportFreshness", RUNNER)
        self.assertIn("$script:freshAfter = Get-Date", RUNNER)
        self.assertIn("LastWriteTime -lt $script:freshAfter.AddSeconds(-2)", RUNNER)
        self.assertIn('Assert-ReportFreshness $comparisonPath "contrato"', RUNNER)
        self.assertIn('Assert-ReportFreshness $reportPath "candidato $caseName"', RUNNER)

    def test_runner_audits_contract_report(self):
        self.assertIn("function Assert-TwoZoneComparisonReport", RUNNER)
        self.assertIn('Assert-ExactCaseSet $comparisonCaseNames $caseNames "contrato"', RUNNER)
        self.assertIn('$comparison.candidate_mode -ne "two-zone"', RUNNER)
        self.assertIn("$comparison.all_required_pass -ne $true", RUNNER)
        self.assertIn("$comparison.required_count -ne 18", RUNNER)
        self.assertIn("$comparison.failed_required_count -ne 0", RUNNER)
        self.assertIn("@($comparison.contract_errors).Count -ne 0", RUNNER)

    def test_runner_preserves_stable_contract_artifact(self):
        self.assertIn("legacy_two_zone_comparison.json", RUNNER)
        self.assertIn("legacy_two_zone_comparison_two_zone_v1_pass.json", RUNNER)
        self.assertIn("Copy-Item -LiteralPath $comparisonPath", RUNNER)
        self.assertLess(
            RUNNER.index("Assert-TwoZoneCandidateReports"),
            RUNNER.index("Copy-Item -LiteralPath $comparisonPath"),
        )

    def test_runner_finishes_with_global_guardrails(self):
        self.assertIn("validation_guardrails.py", RUNNER)
        self.assertIn("& $PythonExe $guardrailsScript", RUNNER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
