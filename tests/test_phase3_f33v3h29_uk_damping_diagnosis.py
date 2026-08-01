from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "diagnostics" / "phase3_h29_uk_damping_anatomy.gd"
SOLVER = ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd"
DOC = ROOT / "docs" / "validation" / "PHASE3_F33V3H29_UK_DAMPING_EXHAUSTED_DIAGNOSIS.md"


class TestPhase3H29UkDampingDiagnosis(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tool = TOOL.read_text(encoding="utf-8")
        cls.solver = SOLVER.read_text(encoding="utf-8")
        cls.doc = DOC.read_text(encoding="utf-8")

    def test_tool_is_scene_tree_fixture(self):
        self.assertTrue(self.tool.startswith("extends SceneTree"))

    def test_tool_uses_exact_versioned_uk_capture(self):
        self.assertIn(
            "tests/fixtures/data/coupled_solver_damping_exhausted_uk_bungalow.json",
            self.tool,
        )

    def test_all_nine_versioned_captures_are_pinned(self):
        self.assertEqual(self.tool.count("tests/fixtures/data/coupled_solver_"), 10)
        self.assertIn("CAPTURE_PATHS.size()", self.tool)

    def test_harness_only_writes_under_ignored_runs(self):
        self.assertIn('const OUT_PATH := "res://runs/h29/', self.tool)
        self.assertEqual(self.tool.count("FileAccess.WRITE"), 1)

    def test_json_output_sanitizes_non_finite_diagnostics(self):
        self.assertIn("JSON.stringify(_json_safe(report)", self.tool)
        self.assertIn("is_finite(float(value))", self.tool)

    def test_harness_imports_but_does_not_duplicate_solver(self):
        self.assertIn('preload("res://sim/core/Phase3CoupledPressureSolver.gd")', self.tool)
        self.assertNotIn("class_name Phase3CoupledPressureSolver", self.tool)

    def test_exact_replay_compares_lm_budgets(self):
        for token in ('"lm_budget_2"', '"lm_budget_4"', "rescue_budget"):
            self.assertIn(token, self.tool)

    def test_exact_replay_compares_forward_widths(self):
        for token in ('"forward_h_1e4"', '"forward_h_1e5"', '"forward_h_1e6"'):
            self.assertIn(token, self.tool)

    def test_branch_preserving_candidate_uses_both_sides(self):
        self.assertIn("_jacobian_branch_preserving", self.tool)
        self.assertIn("forward_pressure[column] += h", self.tool)
        self.assertIn("backward_pressure[column] -= h", self.tool)

    def test_branch_comparison_observes_physical_switches(self):
        for token in (
            "delta_p_pa",
            "neutral_plane_inside",
            "a_to_b_kg",
            "b_to_a_kg",
            "regularization_active_count",
        ):
            self.assertIn(token, self.tool)

    def test_candidate_does_not_change_solver_options(self):
        self.assertNotIn("LM_RESCUE_MAX_ACCEPTED_STEPS =", self.tool)
        self.assertNotIn("DEFAULT_MAX_ITERATIONS =", self.tool)
        self.assertNotIn("DEFAULT_RESIDUAL_TOLERANCE =", self.tool)

    def test_neighbourhood_is_deterministic_and_topology_preserving(self):
        self.assertIn("for variant in range(21)", self.tool)
        self.assertIn("_perturb_inputs", self.tool)
        self.assertNotIn('opening["width_m"] =', self.tool)
        self.assertNotIn('opening["open_fraction"] =', self.tool)

    def test_document_records_lm_budget_no_go(self):
        self.assertIn("LM budget is not the cause", self.doc)
        self.assertIn("NO-GO", self.doc)

    def test_document_records_branch_crossing_root_cause(self):
        self.assertIn("crosses zero and changes the donor", self.doc)
        self.assertIn("piecewise differentiable", self.doc)

    def test_document_keeps_h2_open_and_h3_blocked(self):
        self.assertIn("H2 remains open. H3 remains blocked.", self.doc)

    def test_solver_constants_remain_at_h28_values(self):
        self.assertIn("const DEFAULT_MAX_ITERATIONS: int = 24", self.solver)
        self.assertIn("const DEFAULT_JACOBIAN_STEP_PA: float = 1.0e-3", self.solver)
        self.assertIn("const LM_RESCUE_MAX_ACCEPTED_STEPS: int = 1", self.solver)


if __name__ == "__main__":
    unittest.main()
