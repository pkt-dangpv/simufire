"""Real builder/planner/renderer flow; only Qwen classification is stubbed.

Run with --ollama to exercise the same flow with the actual local model.
All generated files live in temporary directories.
"""

import copy
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE_DIR))

from llm import plan_question
from llm.question_context import context_fingerprint


QUESTION_ID = "question_vl_001"
QUESTION = "¿El incendio estaba limitado por ventilación antes de abrir la puerta?"
CLASSIFICATION = {
    "schema_version": "0.4",
    "scenario_id": "basic_room_001",
    "question_id": QUESTION_ID,
    "intent": "condition",
    "topics": ["ventilation_limited"],
    "include_limitations": False,
    "timeline_relation": "not_applicable",
    "anchor_fact_id": None,
    "scope": {"compartment_id": None, "time_relation": "all", "anchor_fact_id": None, "start_time_s": None, "end_time_s": None},
    "clarification_needed": "none",
}


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def run_script(script, *arguments, timeout=30):
    return subprocess.run(
        [sys.executable, str(BASE_DIR / script), *map(str, arguments)],
        cwd=BASE_DIR.parent, capture_output=True, text=True, encoding="utf-8",
        env={**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONDONTWRITEBYTECODE": "1"},
        timeout=timeout,
    )


class QuestionFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "context.json"
            result = run_script(
                "tests/build_ventilation_limited_test_context.py", "--output", path,
            )
            if result.returncode:
                raise AssertionError(result.stdout + result.stderr)
            cls.fixture = load_json(path)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.context_path = self.root / "context.json"
        self.context = copy.deepcopy(self.fixture)
        save_json(self.context_path, self.context)
        self.plan_dir = self.root / "plans"
        self.answer_dir = self.root / "answers"
        self.plan_path = self.plan_dir / f"basic_room_001_{QUESTION_ID}.json"
        self.answer_path = self.answer_dir / f"basic_room_001_{QUESTION_ID}_answer.json"

    def plan(self, classification=None, use_ollama=False, question=QUESTION):
        args = [
            "--context", str(self.context_path), "--question-id", QUESTION_ID,
            "--question", question, "--output-dir", str(self.plan_dir),
        ]
        if use_ollama:
            result = run_script("llm/plan_question.py", *args, timeout=150)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            with (
                patch.object(sys, "argv", ["plan_question.py", *args]),
                patch.object(plan_question, "call_ollama", return_value=json.dumps(
                    classification or CLASSIFICATION,
                )) as classifier,
                patch("urllib.request.urlopen", side_effect=AssertionError("Unexpected network")),
                redirect_stdout(io.StringIO()),
            ):
                plan_question.main()
                classifier.assert_called_once()
        return load_json(self.plan_path)

    def render(self, context_path=None, question_id=QUESTION_ID, plan_dir=None):
        return run_script(
            "llm/render_question_answer.py",
            "--context", context_path or self.context_path,
            "--question-id", question_id,
            "--plan-dir", plan_dir or self.plan_dir,
            "--output-dir", self.answer_dir,
        )

    def assert_rejected(self, expected, context_path=None):
        # A rejected request must not overwrite an existing valid answer.
        self.answer_dir.mkdir(exist_ok=True)
        self.answer_path.write_text("previous answer", encoding="utf-8")
        result = self.render(context_path)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(expected, result.stdout + result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertEqual(self.answer_path.read_text(encoding="utf-8"), "previous answer")

    def check_pipeline(self, use_ollama=False):
        plan = self.plan(use_ollama=use_ollama)
        self.assertEqual(plan["intent"], "condition")
        self.assertEqual(plan["topics"], ["ventilation_limited"])
        self.assertEqual(plan["resolved_fact_ids"], ["FACT_010"])
        self.assertEqual(plan["resolved_knowledge_ids"], ["VENTILATION_LIMITED_001"])
        self.assertFalse(plan["include_limitations"])
        self.assertEqual(plan["source_context_sha256"], context_fingerprint(self.context))
        before = self.context_path.read_bytes()
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        answer = load_json(self.answer_path)
        fact = next(f for f in self.context["scenario_facts"] if f["fact_id"] == "FACT_010")
        knowledge = next(k for k in self.context["technical_knowledge"]
                         if k["knowledge_id"] == "VENTILATION_LIMITED_001")
        self.assertEqual(answer["answer"], (
            fact["statement"] + " La certeza asignada a esta detección es moderada."
            + "\n\nComo marco teórico general: " + knowledge["content"]
        ))
        self.assertEqual(answer["fact_ids"], ["FACT_010"])
        self.assertEqual(answer["knowledge_ids"], ["VENTILATION_LIMITED_001"])
        self.assertEqual(answer["source_ids"], ["NIST_FIRE_DYNAMICS"])
        self.assertEqual(answer["fact_metadata"], [
            {"fact_id": "FACT_010", "certainty": "moderate", "causal": False},
        ])
        self.assertEqual(answer["source_context_sha256"], plan["source_context_sha256"])
        self.assertEqual(self.context_path.read_bytes(), before)

    def test_question_vl_001_pipeline(self):
        self.check_pipeline()

    def test_fixture_is_reproducible(self):
        second = self.root / "second.json"
        result = run_script("tests/build_ventilation_limited_test_context.py", "--output", second)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(load_json(second), self.fixture)

    def test_rejects_normal_context(self):
        self.plan()
        self.assert_rejected("no corresponde", plan_question.CONTEXT_PATH)

    def test_rejects_changed_content_with_same_ids(self):
        self.plan()
        for section, key, value in (
            ("scenario_facts", "statement", "Contenido de otro análisis"),
            ("scenario_facts", "certainty", "limited"),
            ("scenario_facts", "causal", True),
            ("technical_knowledge", "content", "Teoría de otro contexto"),
        ):
            with self.subTest(section=section, key=key):
                context = copy.deepcopy(self.context)
                context[section][0][key] = value
                save_json(self.context_path, context)
                self.assert_rejected("no corresponde")

    def test_rejects_unbound_alternate_plan(self):
        plan = self.plan()
        del plan["source_context_sha256"]
        save_json(self.plan_path, plan)
        self.assert_rejected("no identifica su contexto")

    def test_rejects_unbound_default_plan(self):
        # Migration removes the former exception for the default context path.
        self.plan_dir.mkdir()
        plan = load_json(BASE_DIR / "tests/data/question_plans/basic_room_001_question_oxygen_001.json")
        del plan["source_context_sha256"]
        save_json(self.plan_dir / "basic_room_001_question_oxygen_001.json", plan)
        result = self.render(plan_question.CONTEXT_PATH, "question_oxygen_001", self.plan_dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no identifica su contexto", result.stderr)
        self.assertFalse((self.answer_dir / "basic_room_001_question_oxygen_001_answer.json").exists())

    def test_accepts_reformatted_relocated_identical_context(self):
        self.plan()
        relocated = self.root / "relocated.json"
        relocated.write_text(json.dumps(self.context, sort_keys=True), encoding="utf-8")
        result = self.render(relocated)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejects_wrong_plan_identity(self):
        plan = self.plan()
        for key, expected in (("scenario_id", "otro escenario"), ("question_id", "question_id")):
            with self.subTest(key=key):
                changed = {**plan, key: "other"}
                save_json(self.plan_path, changed)
                self.assert_rejected(expected)

    def test_rejects_missing_references(self):
        plan = self.plan()
        for key in ("resolved_fact_ids", "resolved_knowledge_ids"):
            with self.subTest(key=key):
                save_json(self.plan_path, {**plan, key: ["MISSING"]})
                self.assert_rejected("No existe MISSING")

    def test_rejects_malformed_plan(self):
        self.plan()
        for value in ({}, [], {**CLASSIFICATION, "intent": "invented"}):
            with self.subTest(value=value):
                save_json(self.plan_path, value)
                self.assert_rejected("Plan resuelto")

    def test_rejects_duplicate_context_ids(self):
        self.plan()
        for section in ("scenario_facts", "technical_knowledge", "source_events"):
            with self.subTest(section=section):
                context = copy.deepcopy(self.context)
                context[section].append(copy.deepcopy(context[section][0]))
                save_json(self.context_path, context)
                self.assert_rejected("Identificador duplicado")

    def test_rejects_foreign_scenario_fact_and_event(self):
        self.plan()
        for section in ("scenario_facts", "source_events"):
            with self.subTest(section=section):
                context = copy.deepcopy(self.context)
                context[section][0]["scenario_id"] = "other"
                save_json(self.context_path, context)
                self.assert_rejected("otro escenario")

    def test_invalid_context_rejected_before_calling_qwen(self):
        self.context["rules"]["do_not_invent_phenomena"] = False
        save_json(self.context_path, self.context)
        with (
            patch.object(sys, "argv", ["plan_question.py", "--question", QUESTION,
                                      "--context", str(self.context_path)]),
            patch.object(plan_question, "call_ollama") as classifier,
            self.assertRaises(SystemExit) as error,
            patch("sys.stderr", new_callable=io.StringIO),
        ):
            plan_question.main()
        self.assertEqual(error.exception.code, 1)
        classifier.assert_not_called()
        self.assertFalse(self.plan_path.exists())

    def test_absent_condition_not_invented(self):
        self.context = load_json(plan_question.CONTEXT_PATH)
        save_json(self.context_path, self.context)
        plan = self.plan()
        self.assertEqual(plan["resolved_fact_ids"], [])
        self.assertEqual(plan["resolved_knowledge_ids"], [])
        result = self.render()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        answer = load_json(self.answer_path)
        self.assertEqual(answer["answer"],
                         "Los datos disponibles no permiten evaluar un incendio limitado por ventilación en el ámbito solicitado. No se puede concluir que esté ausente.")
        self.assertEqual(answer["source_ids"], [])

    def test_alternate_numeric_evidence_never_uses_normal_events(self):
        for with_events in (False, True):
            with self.subTest(with_events=with_events):
                context = copy.deepcopy(self.fixture)
                fact = next(f for f in context["scenario_facts"] if f["fact_id"] == "FACT_005")
                fact["statement"] = "La temperatura de la capa superior aumentó de 10 a 40 °C."
                if with_events:
                    event = next(e for e in context["source_events"]
                                 if e["event_id"] == fact["event_ids"][0])
                    event["evidence"][0].update(previous_value=10, value=40)
                else:
                    del context["source_events"]
                save_json(self.context_path, context)
                self.plan({**CLASSIFICATION, "intent": "observation", "topics": ["temperature"]}, question="¿Cómo cambió la temperatura?")
                result = self.render()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                answer = load_json(self.answer_path)
                expected = fact["statement"]
                if with_events:
                    expected += " Esto supone un aumento de 30 °C."
                self.assertEqual(answer["answer"], expected)
                self.assertEqual(answer["source_ids"], [])

    def test_existing_modes_render_fresh(self):
        # Existing tests only inspect cached answers; exercise the current renderer too.
        for question_id in ("question_concept_001", "question_observation_001",
                            "question_oxygen_001", "question_timeline_001", "question_causality_001"):
            with self.subTest(question_id=question_id):
                result = self.render(
                    plan_question.CONTEXT_PATH, question_id,
                    BASE_DIR / "tests/data/question_plans",
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                name = f"basic_room_001_{question_id}_answer.json"
                answer = load_json(self.answer_dir / name)
                expected = load_json(BASE_DIR / "tests/data/question_answers" / name)
                for key in ("answer", "fact_ids", "knowledge_ids", "source_ids"):
                    self.assertEqual(answer[key], expected[key], key)


if __name__ == "__main__":
    if sys.argv[1:] == ["--ollama"]:
        # Explicit integration mode; never enabled by run_all_tests.py.
        QuestionFlowTests.setUpClass()
        case = QuestionFlowTests()
        case.setUp()
        try:
            case.check_pipeline(use_ollama=True)
            print("OK: Q&A ventilation_limited end-to-end con Ollama")
        finally:
            case.doCleanups()
    else:
        unittest.main(verbosity=2)
