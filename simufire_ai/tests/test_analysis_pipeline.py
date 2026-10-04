"""Production pipeline regressions; --ollama explicitly enables real integration."""

import copy
from concurrent.futures import ThreadPoolExecutor
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE_DIR))

import pipeline
from llm.question_context import validate_plan_context
from llm.render_question_answer import render_question_answer

QUESTION = "¿El incendio estaba limitado por ventilación antes de abrir la puerta?"


def classification(intent="condition", topics=None):
    # Deliberately wrong model identities: the code must assign actual identities.
    return {
        "schema_version": "0.4", "scenario_id": "model_guess", "question_id": "model_guess",
        "intent": intent, "topics": topics or ["ventilation_limited"],
        "include_limitations": False, "timeline_relation": "not_applicable", "anchor_fact_id": None,
        "scope": {"compartment_id": None, "time_relation": "all", "anchor_fact_id": None, "start_time_s": None, "end_time_s": None},
        "clarification_needed": "none",
    }


class AnalysisPipelineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.scenario = pipeline.read_json(BASE_DIR / "scenarios/basic_room_001.json")
        self.states = [pipeline.read_json(path) for path in sorted(
            (BASE_DIR / "tests/data/ventilation_limited_states").glob("*.json"))]
        self.entries = pipeline.load_entries()
        self.classifier = lambda prompt, schema: json.dumps(classification())
        self.network = patch("urllib.request.urlopen", side_effect=AssertionError("Unexpected network"))
        self.network.start()
        self.addCleanup(self.network.stop)

    def build(self, run_id="run_a", **kwargs):
        return pipeline.analyze_run(self.scenario, self.states, run_id, self.root, **kwargs)

    def cli(self, *arguments):
        return subprocess.run(
            [sys.executable, str(BASE_DIR / "pipeline.py"), *map(str, arguments)],
            capture_output=True, text=True, encoding="utf-8", timeout=30,
            env={**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONDONTWRITEBYTECODE": "1"},
        )

    def test_reproducible_from_frozen_inputs_in_any_order(self):
        first = pipeline.build_analysis(self.scenario, self.states, "repro", entries=self.entries)
        second = pipeline.build_analysis(self.scenario, self.states[::-1], "repro", entries=self.entries[::-1])
        self.assertEqual(first, second)
        original = copy.deepcopy(first)
        self.scenario["name"] = "Changed by caller"
        self.states[0]["time_s"] = 20
        self.entries[0]["content"] = "Changed theory"
        self.assertEqual(first, original)

    def test_other_scenario_and_room_names_are_not_hardcoded(self):
        self.scenario["scenario_id"] = "kitchen_case"
        self.scenario["compartments"][0]["id"] = "kitchen"
        self.scenario["openings"][0].update(id="window", type="window", **{"from": "kitchen"})
        self.scenario["fires"][0]["compartment"] = "kitchen"
        self.scenario["actions"][0]["target"] = "window"
        for state in self.states:
            state["scenario_id"] = "kitchen_case"
            state["compartments"][0]["id"] = "kitchen"
        run = self.build("kitchen_run")
        answer = pipeline.ask_run(run, QUESTION, "question", classifier=self.classifier)
        self.assertEqual(answer["scenario_id"], "kitchen_case")
        self.assertIn("window", answer["answer"])
        self.assertNotIn("door_01", answer["answer"])
        pipeline.load_run(run, replay=True)

    def test_complete_vl_flow_preserves_physical_flags(self):
        run = self.build()
        answer = pipeline.ask_run(run, QUESTION, "question_vl_001", classifier=self.classifier)
        self.assertEqual(answer["run_id"], "run_a")
        self.assertEqual(answer["fact_ids"], ["FACT_010"])
        self.assertEqual(answer["source_ids"], ["NIST_FIRE_DYNAMICS"])
        self.assertEqual(answer["fact_metadata"], [{"fact_id": "FACT_010", "certainty": "moderate", "causal": False}])
        question_dir = run / "questions/question_vl_001"
        self.assertEqual({path.name for path in question_dir.iterdir()}, {"question.json", "plan.json", "answer.json"})
        self.assertEqual(pipeline.read_json(question_dir / "answer.json"), answer)
        context = pipeline.load_run(run, replay=True)["context.json"]
        fact = next(fact for fact in context["scenario_facts"] if fact["fact_id"] == "FACT_010")
        self.assertTrue(answer["answer"].startswith(fact["statement"] + " La certeza asignada"))

    def test_identical_scenario_runs_reject_swapped_plans(self):
        first, second = self.build("one"), self.build("two")
        pipeline.ask_run(first, QUESTION, "same_question", classifier=self.classifier)
        plan = pipeline.read_json(first / "questions/same_question/plan.json")
        context = pipeline.load_run(second)["context.json"]
        with self.assertRaisesRegex(ValueError, "run_id"):
            render_question_answer(context, plan)
        plan["run_id"] = "two"
        with self.assertRaisesRegex(ValueError, "no corresponde"):
            validate_plan_context(plan, context, "same_question")
        del plan["run_id"]
        with self.assertRaisesRegex(ValueError, "run_id"):
            validate_plan_context(plan, context, "same_question")

    def test_numeric_evidence_isolated_between_runs(self):
        first = self.build("original")
        self.states[-1]["compartments"][0]["upper_layer"]["temperature_c"] += 100
        second = self.build("changed")
        classifier = lambda prompt, schema: json.dumps(classification("observation", ["temperature"]))
        a = pipeline.ask_run(first, "Temperatura", "temperature", classifier=classifier)
        b = pipeline.ask_run(second, "Temperatura", "temperature", classifier=classifier)
        self.assertNotEqual(a["answer"], b["answer"])
        self.assertEqual(a["fact_ids"], b["fact_ids"])
        self.assertNotEqual(a["source_context_sha256"], b["source_context_sha256"])
        self.assertEqual(pipeline.read_json(first / "questions/temperature/answer.json"), a)

    def test_multiple_questions_keep_analysis_unchanged_and_refuse_overwrites(self):
        run = self.build()
        before = {name: (run / name).read_bytes() for name in (*pipeline.ARTIFACTS, "manifest.json")}
        pipeline.ask_run(run, QUESTION, "first", classifier=self.classifier)
        pipeline.ask_run(run, "Otra pregunta", "second", classifier=self.classifier)
        with patch("pipeline.create_question_plan") as planner:
            with self.assertRaises(FileExistsError):
                pipeline.ask_run(run, "Reemplazar", "first")
            planner.assert_not_called()
        with self.assertRaises(FileExistsError):
            self.build()
        self.assertEqual(before, {name: (run / name).read_bytes() for name in before})

    def test_snapshot_replay_does_not_read_current_config_or_knowledge(self):
        run = self.build()
        with patch("pipeline.load_entries", side_effect=AssertionError("Live knowledge read")):
            artifacts = pipeline.load_run(run, replay=True)
        self.assertEqual(artifacts["manifest.json"]["pipeline_version"], "0.3")
        relocated = self.root / "renamed"
        run.rename(relocated)
        self.assertEqual(pipeline.load_run(relocated, replay=True), artifacts)

    def test_tampered_artifact_rejected_before_model_call(self):
        for name in pipeline.ARTIFACTS:
            with self.subTest(name=name):
                run = self.build("tamper_" + name.replace(".", "_"))
                path = run / name
                value = pipeline.read_json(path)
                if isinstance(value, list):
                    value.append({"changed": True})
                else:
                    value["changed"] = True
                pipeline.write_json(path, value)
                with patch("pipeline.create_question_plan") as planner:
                    with self.assertRaisesRegex(ValueError, "Contenido modificado"):
                        pipeline.ask_run(run, QUESTION, "question")
                    planner.assert_not_called()
                self.assertFalse((run / "questions").exists())

    def test_unknown_manifest_versions_and_replay_engine_rejected(self):
        run = self.build()
        path = run / "manifest.json"
        original = pipeline.read_json(path)
        for key in ("schema_version", "pipeline_version", "engine_sha256"):
            with self.subTest(key=key):
                value = {**original, key: "0" * 64 if key == "engine_sha256" else "future"}
                pipeline.write_json(path, value)
                with self.assertRaises(ValueError):
                    pipeline.load_run(run, replay=True)

    def test_no_measurement_change_produces_no_invented_condition(self):
        self.scenario["actions"] = []
        self.states = [self.states[0]]
        run = self.build()
        artifacts = pipeline.load_run(run, replay=True)
        self.assertEqual(artifacts["events.json"], [])
        self.assertEqual(artifacts["facts.json"], [])
        answer = pipeline.ask_run(run, "¿Se detectó un incendio limitado por ventilación?", "question", classifier=self.classifier)
        self.assertEqual(answer["fact_ids"], [])
        self.assertEqual(answer["source_ids"], [])
        self.assertEqual(answer["answer"], "Los datos disponibles no permiten evaluar un incendio limitado por ventilación en el ámbito solicitado. No se puede concluir que esté ausente.")

    def test_rejects_invalid_inputs_without_creating_run(self):
        cases = []
        def add(label, scenario=None, states=None, thresholds=None):
            cases.append((label, scenario or copy.deepcopy(self.scenario),
                          copy.deepcopy(self.states) if states is None else states, thresholds))
        add("empty", states=[])
        add("duplicate_time", states=self.states + [self.states[0]])
        states = copy.deepcopy(self.states); states[0]["scenario_id"] = "other"; add("foreign", states=states)
        states = copy.deepcopy(self.states); states[0]["compartments"].append(states[0]["compartments"][0]); add("duplicate_room", states=states)
        states = copy.deepcopy(self.states); states[0]["compartments"][0]["id"] = "missing"; add("missing_room", states=states)
        states = copy.deepcopy(self.states); states[0]["compartments"][0]["hrr_kw"] = float("nan"); add("nan", states=states)
        states = copy.deepcopy(self.states); states[0]["compartments"][0]["interface_height_m"] = 99; add("height", states=states)
        states = copy.deepcopy(self.states); states[0]["schema_version"] = "future"; add("state_version", states=states)
        scenario = copy.deepcopy(self.scenario); scenario["openings"][0]["to"] = "missing"; add("topology", scenario=scenario)
        scenario = copy.deepcopy(self.scenario); scenario["actions"][0]["target"] = "missing"; add("action_target", scenario=scenario)
        scenario = copy.deepcopy(self.scenario); scenario["fires"][0]["compartment"] = "missing"; add("fire_room", scenario=scenario)
        scenario = copy.deepcopy(self.scenario); scenario["compartments"].append(scenario["compartments"][0]); add("duplicate_scenario_room", scenario=scenario)
        scenario = copy.deepcopy(self.scenario); scenario["schema_version"] = "future"; add("scenario_version", scenario=scenario)
        add("thresholds", thresholds={})
        for label, scenario, states, thresholds in cases:
            with self.subTest(label=label), self.assertRaises(ValueError):
                pipeline.analyze_run(scenario, states, label, self.root, thresholds=thresholds)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_bad_identifiers_rejected_for_runs_and_questions(self):
        run = self.build()
        for value in ("../other", "a/b", "a\\b", "CON", "nul", "LPT1", "", "x" * 81):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    self.build(value)
                with self.assertRaises(ValueError):
                    pipeline.ask_run(run, QUESTION, value, classifier=self.classifier)
        self.assertFalse((run / "questions").exists())

    def test_failed_classifier_leaves_no_partial_question(self):
        run = self.build()
        for raw in ("not json", "[]", "null", json.dumps({"intent": "invented"})):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                pipeline.ask_run(run, QUESTION, "failed", classifier=lambda prompt, schema: raw)
        with patch("pipeline.create_question_plan", side_effect=OSError("Ollama unavailable")):
            with self.assertRaises(OSError):
                pipeline.ask_run(run, QUESTION, "failed")
        self.assertFalse((run / "questions").exists())

    def test_failed_publication_cleans_only_temporary_files(self):
        run = self.build()
        original_write = pipeline.write_json
        def failing_write(path, value):
            if Path(path).name == "plan.json":
                raise OSError("Disk failure")
            original_write(path, value)
        with patch("pipeline.write_json", side_effect=failing_write), self.assertRaises(OSError):
            pipeline.ask_run(run, QUESTION, "failed", classifier=self.classifier)
        self.assertFalse((run / "questions/failed").exists())
        self.assertEqual(list((run / "questions").iterdir()), [])
        pipeline.load_run(run, replay=True)

    def test_concurrent_publication_keeps_exactly_one_complete_result(self):
        destination = self.root / "concurrent"
        def publish(marker):
            try:
                pipeline.publish_directory(destination, {"result.json": {"marker": marker}})
                return marker
            except FileExistsError:
                return None
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(publish, ("first", "second")))
        winners = [result for result in results if result is not None]
        self.assertEqual(len(winners), 1)
        self.assertEqual(pipeline.read_json(destination / "result.json"), {"marker": winners[0]})
        self.assertEqual([path.name for path in self.root.iterdir()], ["concurrent"])

    def test_ollama_transport_payload_errors_do_not_publish_questions(self):
        run = self.build()
        for payload in ({"error": "unavailable"}, [], {"response": {}}, {"response": "null"}):
            with self.subTest(payload=payload):
                with patch("urllib.request.urlopen") as urlopen:
                    urlopen.return_value.__enter__.return_value.read.return_value = json.dumps(payload).encode()
                    with self.assertRaises(ValueError):
                        pipeline.ask_run(run, QUESTION, "failed")
        self.assertFalse((run / "questions").exists())

    def test_analysis_change_during_classifier_rejected(self):
        run = self.build()
        def changing_classifier(prompt, schema):
            path = run / "context.json"
            context = pipeline.read_json(path); context["run_id"] = "other"
            pipeline.write_json(path, context)
            return self.classifier(prompt, schema)
        with self.assertRaisesRegex(ValueError, "Contenido modificado"):
            pipeline.ask_run(run, QUESTION, "question", classifier=changing_classifier)
        self.assertFalse((run / "questions").exists())

    def test_cli_analyze_verify_and_failures(self):
        root = self.root / "cli"
        result = self.cli("analyze", "--scenario", BASE_DIR / "scenarios/basic_room_001.json",
                          "--states-dir", BASE_DIR / "tests/data/ventilation_limited_states",
                          "--run-id", "cli_run", "--output-root", root)
        self.assertEqual(result.returncode, 0, result.stderr)
        run = root / "cli_run"
        result = self.cli("verify", "--run-dir", run, "--replay")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.cli("ask", "--run-dir", run, "--question-id", "../escape", "--question", QUESTION)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Traceback", result.stderr)
        bad = self.root / "bad.json"; bad.write_text('{"scenario_id":1,"scenario_id":2}')
        with self.assertRaisesRegex(ValueError, "duplicada"):
            pipeline.read_json(bad)


def ollama_integration():
    with tempfile.TemporaryDirectory() as directory:
        scenario = pipeline.read_json(BASE_DIR / "scenarios/basic_room_001.json")
        states = [pipeline.read_json(path) for path in sorted(
            (BASE_DIR / "tests/data/ventilation_limited_states").glob("*.json"))]
        run = pipeline.analyze_run(scenario, states, "ollama_vl", directory)
        answer = pipeline.ask_run(run, QUESTION, "question_vl_001")
        assert answer["fact_ids"] == ["FACT_010"], answer
        assert answer["knowledge_ids"] == ["VENTILATION_LIMITED_001"], answer
        assert answer["source_ids"] == ["NIST_FIRE_DYNAMICS"], answer
        assert answer["fact_metadata"] == [{"fact_id": "FACT_010", "certainty": "moderate", "causal": False}]
        pipeline.load_run(run, replay=True)
        print("OK: pipeline completo y reproducción con Qwen real")


if __name__ == "__main__":
    if sys.argv[1:] == ["--ollama"]:
        ollama_integration()
    else:
        unittest.main(verbosity=2)
