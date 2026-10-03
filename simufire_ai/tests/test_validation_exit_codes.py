"""Ensure schema failures are visible to the deterministic suite."""

import importlib
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))

import run_all_tests


VALIDATORS = (
    ("validate_scenario", "SCENARIOS_DIR"),
    ("validate_simulation_state", "STATES_DIR"),
    ("validate_fire_event", "EVENT_DIRS"),
    ("validate_explanation", "EXPLANATIONS_DIR"),
    ("validate_analysis_context", "CONTEXT_DIR"),
    ("validate_grounded_fact", "FACTS_DIR"),
    ("validate_knowledge_entry", "KNOWLEDGE_DIR"),
    ("validate_instructor_context", "CONTEXT_DIR"),
)


class ValidationExitTests(unittest.TestCase):
    def test_invalid_missing_and_valid_data(self):
        for name, setting in VALIDATORS:
            module = importlib.import_module(name)
            original = getattr(module, setting)
            directories = original if isinstance(original, list) else [original]
            fixture = next(directories[0].glob("*.json")).read_bytes()
            with tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                target = folder / "fixture.json"
                replacement = [folder] if isinstance(original, list) else folder
                with patch.object(module, setting, replacement), redirect_stdout(io.StringIO()):
                    with self.subTest(validator=name, state="missing"):
                        self.assertEqual(module.main(), 1)
                    with self.subTest(validator=name, state="invalid"):
                        target.write_text("{}", encoding="utf-8")
                        self.assertEqual(module.main(), 1)
                    with self.subTest(validator=name, state="valid"):
                        target.write_bytes(fixture)
                        self.assertEqual(module.main(), 0)

    def test_runner_propagates_real_schema_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "invalid.json").write_text("{}", encoding="utf-8")
            script = folder / "invalid_context_test.py"
            script.write_text(
                "import sys\nfrom pathlib import Path\n"
                f"sys.path.insert(0, {str(Path(__file__).resolve().parent)!r})\n"
                "import validate_instructor_context as validator\n"
                f"validator.CONTEXT_DIR = Path({str(folder)!r})\n"
                "raise SystemExit(validator.main())\n",
                encoding="utf-8",
            )
            with (
                patch.object(run_all_tests, "TESTS", [str(script)]),
                redirect_stdout(io.StringIO()) as output,
                self.assertRaises(SystemExit) as error,
            ):
                run_all_tests.main()
            self.assertEqual(error.exception.code, 1)
            self.assertIn("Fallidos: 1", output.getvalue())
            self.assertNotIn("TODO OK", output.getvalue())

    def test_instructor_validator_checks_nested_facts(self):
        module = importlib.import_module("validate_instructor_context")
        context = json.loads(next(module.CONTEXT_DIR.glob("*.json")).read_text(encoding="utf-8"))
        context["scenario_facts"][0]["certainty"] = "invented"
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "invalid.json").write_text(json.dumps(context), encoding="utf-8")
            with patch.object(module, "CONTEXT_DIR", folder), redirect_stdout(io.StringIO()):
                self.assertEqual(module.main(), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
