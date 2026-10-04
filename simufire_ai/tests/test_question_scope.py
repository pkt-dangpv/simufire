"""Question 0.4 scope, assessment and rendering; explicit --ollama integration."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE_DIR))

import pipeline
from llm.plan_question import create_question_plan
from llm.question_context import validate_context, validate_plan_context
from llm.question_scope import DEFAULT_SCOPE, fact_rooms
from llm.render_question_answer import render_question_answer


def classify(intent="condition", topics=None, scope=None, *, anchor=None, clarification="none"):
    return {
        "schema_version": "0.4", "scenario_id": "model_guess", "question_id": "model_guess",
        "intent": intent, "topics": ["ventilation_limited"] if topics is None else topics,
        "include_limitations": False, "timeline_relation": "all" if intent == "timeline" else "not_applicable",
        "anchor_fact_id": anchor, "scope": {**DEFAULT_SCOPE, **(scope or {})},
        "clarification_needed": clarification,
    }


class QuestionScopeTests(unittest.TestCase):
    def setUp(self):
        self.scenario = pipeline.read_json(BASE_DIR / "scenarios/basic_room_001.json")
        self.states = [pipeline.read_json(path) for path in sorted(
            (BASE_DIR / "tests/data/ventilation_limited_states").glob("*.json"))]
        self.network = patch("urllib.request.urlopen", side_effect=AssertionError("Unexpected network"))
        self.network.start()
        self.addCleanup(self.network.stop)
        self.context = self.build()

    def build(self):
        return pipeline.build_analysis(self.scenario, self.states, "scope_test")["context.json"]

    def query(self, question, classification=None, context=None):
        context = self.context if context is None else context
        result = create_question_plan(context, question, "query", classifier=lambda prompt, schema:
                                      json.dumps(classification or classify()))
        return result, render_question_answer(context, result)

    def two_rooms(self, *, same_opening=False):
        self.scenario["compartments"].append({**self.scenario["compartments"][0], "id": "room_02", "name": "Cocina"})
        if same_opening:
            self.scenario["openings"][0]["to"] = "room_02"
        else:
            self.scenario["openings"].append({**self.scenario["openings"][0], "id": "window_02", "from": "room_02", "type": "window"})
            self.scenario["actions"].append({"type": "open", "target": "window_02", "time_s": 180})
        for state in self.states:
            second = copy.deepcopy(state["compartments"][0]); second["id"] = "room_02"
            second["upper_layer"]["temperature_c"] += 100
            state["compartments"].append(second)
        self.context = self.build()

    def repeated_opening(self):
        self.scenario["actions"].append({"time_s": 190, "type": "open", "target": "door_01"})
        self.context = self.build()

    def test_before_opening_is_applied_to_condition(self):
        plan, answer = self.query("¿Estaba limitado por ventilación antes de abrir la puerta?")
        self.assertEqual(plan["scope"]["time_relation"], "before")
        self.assertEqual(plan["scope"]["end_time_s"], 180)
        self.assertEqual(answer["answer_status"], "evidence_found")
        self.assertEqual(answer["fact_ids"], ["FACT_010"])
        self.assertEqual(answer["fact_metadata"], [{"fact_id": "FACT_010", "certainty": "moderate", "causal": False}])
        self.assertEqual(answer["fact_provenance"][0]["time_s"], 179)
        self.assertEqual(answer["fact_provenance"][0]["evidence_interval_s"]["end"], 195)
        self.assertEqual(answer["source_ids"], ["NIST_FIRE_DYNAMICS"])

    def test_redundant_model_headers_are_normalized_by_code(self):
        classification = classify(scope={"anchor_fact_id": "FACT_001"}, clarification="action")
        classification.update(anchor_fact_id="FACT_001", timeline_relation="before", include_limitations=True)
        plan, answer = self.query("¿Estaba limitado por ventilación antes de abrir la puerta?", classification)
        self.assertEqual(plan["timeline_relation"], "not_applicable")
        self.assertIsNone(plan["anchor_fact_id"])
        self.assertFalse(plan["include_limitations"])
        self.assertEqual(plan["scope"]["anchor_fact_id"], "FACT_001")
        self.assertEqual(answer["fact_ids"], ["FACT_010"])

    def test_post_opening_never_relocates_pre_opening_pattern(self):
        _, answer = self.query("¿Estaba limitado por ventilación después de abrir la puerta?")
        self.assertEqual(answer["fact_ids"], [])
        self.assertEqual(answer["answer_status"], "insufficient_data")
        self.assertNotIn("detectó un patrón", answer["answer"])
        self.assertEqual(answer["response_status"], "ventilation_response_compatible")
        self.assertIn("Queda por determinar", answer["answer"])
        self.assertNotIn("Los datos disponibles no permiten evaluar", answer["answer"])

    def test_numeric_before_boundary_and_at_reference(self):
        _, before = self.query("¿Estaba limitado por ventilación antes de 170 s?")
        self.assertEqual(before["answer_status"], "insufficient_data")
        self.assertEqual(before["fact_ids"], [])
        plan, at = self.query("¿Estaba limitado por ventilación en t=179 s?")
        self.assertEqual(plan["scope"]["time_relation"], "at")
        self.assertEqual(at["fact_ids"], ["FACT_010"])

    def test_range_contains_reference_and_retains_retrospective_support(self):
        plan, answer = self.query("¿Estaba limitado por ventilación entre 170 s y 179 s?")
        self.assertEqual(plan["scope"]["start_time_s"], 170)
        self.assertEqual(answer["fact_ids"], ["FACT_010"])

    def test_explicit_point_clears_unneeded_action_or_time_clarification(self):
        for ambiguity in ("action", "time"):
            with self.subTest(ambiguity=ambiguity):
                _, answer = self.query("¿Estaba limitado por ventilación en t=179 s?",
                    classify(clarification=ambiguity))
                self.assertEqual(answer["answer_status"], "evidence_found")
                self.assertEqual(answer["fact_ids"], ["FACT_010"])

    def test_unique_causal_action_clears_unneeded_clarification(self):
        _, answer = self.query("¿La apertura de door_01 causó el aumento del HRR?",
            classify("causality", ["hrr"], anchor="FACT_001", clarification="action"))
        self.assertEqual(answer["answer_status"], "causal_not_established")
        self.assertIn("no puede afirmarse", answer["answer"])

    def test_unique_temporal_action_supplies_an_unambiguous_time_boundary(self):
        _, answer = self.query("¿Estaba limitado por ventilación antes de abrir la puerta?",
            classify(clarification="time"))
        self.assertEqual(answer["answer_status"], "evidence_found")
        self.assertEqual(answer["scope"]["end_time_s"],180)

    def test_measured_change_crossing_boundary_is_not_reported(self):
        _, answer = self.query("¿Cómo cambió la temperatura después de 180 s?", classify("observation", ["temperature"]))
        self.assertEqual(answer["fact_ids"], [])
        self.assertEqual(answer["answer_status"], "insufficient_data")
        self.assertEqual(answer["topic_assessments"][0]["reason"], "measurement_crosses_time_boundary")
        self.assertIn("cruzan el límite", answer["answer"])
        self.assertNotIn("475", answer["answer"])

    def test_closed_range_can_include_the_whole_measured_change(self):
        plan, answer = self.query("¿Cómo cambió la temperatura entre 179 y 195 s?", classify("observation", ["temperature"]))
        self.assertEqual(answer["answer_status"], "evidence_found")
        self.assertEqual(answer["fact_ids"], ["FACT_005"])
        self.assertIn("85 °C", answer["answer"])
        self.assertEqual(plan["scope"]["time_relation"], "between")

    def test_explicit_variable_and_range_resolve_unnecessary_clarification(self):
        for ambiguity in ("topic", "time", "action"):
            with self.subTest(ambiguity=ambiguity):
                _, answer = self.query("¿Cómo cambió la temperatura entre 179 y 195 s?",
                    classify("observation", ["temperature"], clarification=ambiguity))
                self.assertEqual(answer["answer_status"], "evidence_found")
                self.assertIn("85 °C", answer["answer"])

    def test_strict_before_after_exclude_action_at_boundary(self):
        for relation in ("antes", "después"):
            with self.subTest(relation=relation):
                plan, answer = self.query(f"¿Qué ocurrió {relation} de abrir la puerta?", classify("timeline", []))
                self.assertNotIn("FACT_001", answer["fact_ids"])
                for fact_id in answer["fact_ids"]:
                    fact = next(f for f in self.context["scenario_facts"] if f["fact_id"] == fact_id)
                    self.assertTrue(fact["time_s"] < 180 if relation == "antes" else fact["time_s"] > 180)

    def test_condition_can_render_a_measured_increase(self):
        _, answer = self.query("¿Hubo un aumento de temperatura?", classify("condition", ["temperature"]))
        self.assertEqual(answer["answer_status"], "evidence_found")
        self.assertIn("390 a 475", answer["answer"])
        self.assertIn("certeza", answer["answer"])

    def test_not_detected_requires_an_evaluable_window(self):
        self.states[2]["compartments"][0]["upper_layer"]["o2_percent"] = 19
        self.context = self.build()
        _, answer = self.query("¿Estaba limitado por ventilación antes de abrir la puerta?")
        self.assertEqual(answer["answer_status"], "not_detected")
        self.assertEqual(answer["fact_ids"], [])
        self.assertIn("Esto no demuestra su ausencia", answer["answer"])

    def test_short_history_is_insufficient_not_negative(self):
        self.states = self.states[-2:]
        self.context = self.build()
        _, answer = self.query("¿Estaba limitado por ventilación antes de abrir la puerta?")
        self.assertEqual(answer["answer_status"], "insufficient_data")
        self.assertEqual(answer["topic_assessments"][0]["reason"], "insufficient_pre_history")

    def test_sampling_gap_is_insufficient_not_negative(self):
        self.states = [self.states[0], self.states[-1]]
        self.context = self.build()
        _, answer = self.query("¿Se detectó un aumento de temperatura?", classify("condition", ["temperature"]))
        self.assertEqual(answer["answer_status"], "insufficient_data")
        self.assertEqual(answer["topic_assessments"][0]["reason"], "sampling_gap")

    def test_no_opening_is_not_a_negative_vl_diagnosis(self):
        self.scenario["actions"] = []
        self.context = self.build()
        _, answer = self.query("¿Se detectó un incendio limitado por ventilación?")
        self.assertEqual(answer["answer_status"], "insufficient_data")

    def test_zero_baseline_uses_actual_hrr_predicate(self):
        self.states = self.states[-2:]
        self.states[0]["compartments"][0]["hrr_kw"] = 0
        self.context = self.build()
        _, answer = self.query("¿Aumentó el HRR?", classify("condition", ["hrr"]))
        self.assertEqual(answer["answer_status"], "evidence_found")
        self.assertIn("0 a 1280", answer["answer"])
        self.states[-1]["compartments"][0]["hrr_kw"] = 0
        self.context = self.build()
        _, answer = self.query("¿Aumentó el HRR?", classify("condition", ["hrr"]))
        self.assertEqual(answer["answer_status"], "not_detected")

    def test_ventilation_coverage_does_not_require_positive_hrr(self):
        self.states = self.states[-2:]
        self.states[0]["compartments"][0]["hrr_kw"] = 0
        self.context = self.build()
        _, answer = self.query("¿Aumentó la ventilación?", classify("condition", ["ventilation"]))
        self.assertEqual(answer["answer_status"], "evidence_found")
        self.states[-1]["compartments"][0]["upper_layer"]["o2_percent"] = self.states[0]["compartments"][0]["upper_layer"]["o2_percent"]
        self.context = self.build()
        _, answer = self.query("¿Aumentó la ventilación?", classify("condition", ["ventilation"]))
        self.assertEqual(answer["answer_status"], "not_detected")

    def test_unsupported_phenomena_cannot_be_confirmed_or_denied(self):
        for topic in ("flashover", "backdraft", "rollover", "suppression"):
            with self.subTest(topic=topic):
                _, answer = self.query(f"¿Se produjo {topic}?", classify("condition", [topic]))
                self.assertEqual(answer["answer_status"], "unsupported")
                self.assertEqual(answer["fact_ids"], [])
                self.assertEqual(answer["source_ids"], [])
                self.assertIn("No se puede confirmar ni descartar", answer["answer"])

    def test_concept_available_without_detection(self):
        self.scenario["actions"] = []
        self.states = [self.states[0]]
        self.context = self.build()
        _, answer = self.query("¿Qué significa incendio limitado por ventilación?", classify("concept"))
        self.assertEqual(answer["answer_status"], "theory_only")
        self.assertEqual(answer["fact_ids"], [])
        self.assertTrue(answer["answer"].startswith("Como marco teórico general:"))
        self.assertEqual(answer["source_ids"], ["NIST_FIRE_DYNAMICS"])

    def test_missing_concept_is_explicit(self):
        _, answer = self.query("¿Qué es backdraft?", classify("concept", ["backdraft"]))
        self.assertEqual(answer["answer_status"], "knowledge_unavailable")
        self.assertEqual(answer["source_ids"], [])

    def test_room_id_and_name_are_resolved_without_leaking_other_room(self):
        self.two_rooms()
        for room in ("room_02", "Cocina"):
            with self.subTest(room=room):
                plan, answer = self.query(f"¿Cómo cambió la temperatura en {room}?", classify("observation", ["temperature"]))
                self.assertEqual(plan["scope"]["compartment_id"], "room_02")
                self.assertIn("490 a 575", answer["answer"])
                self.assertNotIn("390 a 475", answer["answer"])
                for fact_id in answer["fact_ids"]:
                    fact = next(f for f in self.context["scenario_facts"] if f["fact_id"] == fact_id)
                    self.assertEqual(fact_rooms(self.context, fact), {"room_02"})

    def test_unrequested_model_room_does_not_narrow_global_query(self):
        self.two_rooms(same_opening=True)
        plan, answer = self.query("¿Se detectó un incendio limitado por ventilación?",
                                  classify(scope={"compartment_id": "room_01"}))
        self.assertIsNone(plan["scope"]["compartment_id"])
        self.assertEqual({item["compartment_id"] for item in answer["topic_assessments"]}, {"room_01", "room_02"})
        self.assertEqual(len(answer["fact_ids"]), 2)

    def test_partial_coverage_keeps_room_assessments_separate(self):
        self.two_rooms(same_opening=True)
        self.states[2]["compartments"][1]["upper_layer"]["o2_percent"] = 19
        self.context = self.build()
        _, answer = self.query("¿Se detectó un incendio limitado por ventilación?")
        self.assertEqual(answer["answer_status"], "partial")
        self.assertEqual({item["compartment_id"]: item["status"] for item in answer["topic_assessments"]},
                         {"room_01": "evidence_found", "room_02": "not_detected"})
        self.assertIn("En room_01:", answer["answer"])
        self.assertIn("En room_02:", answer["answer"])

    def test_unknown_or_contradictory_room_rejected(self):
        self.two_rooms()
        with self.assertRaises(ValueError):
            self.query("¿Cómo cambió la temperatura en room_02?", classify("observation", ["temperature"], {"compartment_id": "missing"}))
        plan,answer=self.query("¿Cómo cambió la temperatura en room_02?",
            classify("observation", ["temperature"], {"compartment_id": "room_01"}))
        self.assertEqual(plan['scope']['compartment_id'],'room_02')
        facts={fact['fact_id']:fact for fact in self.context['scenario_facts']}
        self.assertTrue(all(fact_rooms(self.context,facts[fid])=={'room_02'} for fid in answer['fact_ids']))
        changed=copy.deepcopy(plan);changed['requested_scope']['compartment_id']='room_01'
        with self.assertRaises(ValueError):render_question_answer(self.context,changed)

    def test_two_explicit_rooms_require_clarification(self):
        self.two_rooms()
        _, answer = self.query("¿Cómo cambió la temperatura en room_01 y room_02?", classify("observation", ["temperature"]))
        self.assertEqual(answer["answer_status"], "clarification_required")
        self.assertEqual(answer["fact_ids"], [])

    def test_action_in_another_room_rejected(self):
        self.two_rooms()
        first_action = next(fact for fact in self.context["scenario_facts"] if fact.get("action_target") == "door_01" and fact["fact_type"] == "action")
        with self.assertRaises(ValueError):
            self.query("¿Se detectó un incendio limitado por ventilación en room_02?", classify(scope={
                "compartment_id": "room_02", "time_relation": "before", "anchor_fact_id": first_action["fact_id"]}))

    def test_repeated_opening_does_not_silently_choose_first(self):
        self.repeated_opening()
        guessed = classify(scope={"time_relation": "before", "anchor_fact_id": "FACT_001"})
        plan, answer = self.query("¿Estaba limitado por ventilación antes de abrir door_01?", guessed)
        self.assertEqual(plan["clarification_needed"], "action")
        self.assertEqual(answer["answer_status"], "clarification_required")
        self.assertEqual(answer["fact_ids"], [])
        self.assertIn("elemento y el instante", answer["answer"])

    def test_ordinal_and_explicit_action_time_disambiguate(self):
        self.repeated_opening()
        for question, expected in (("¿Estaba limitado por ventilación antes de la primera apertura?", 180),
                                   ("¿Estaba limitado por ventilación antes de la última apertura?", 190),
                                   ("¿Estaba limitado por ventilación antes de abrir door_01 en t=190 s?", 190)):
            with self.subTest(question=question):
                plan, answer = self.query(question)
                self.assertEqual(plan["scope"]["end_time_s"], expected)
                self.assertNotEqual(answer["answer_status"], "clarification_required")

    def test_ambiguous_cause_also_requires_clarification(self):
        self.repeated_opening()
        _, answer = self.query("¿La apertura de la puerta causó el aumento del HRR?", classify("causality", ["hrr"], anchor="FACT_001"))
        self.assertEqual(answer["answer_status"], "clarification_required")

    def test_causal_answer_is_cautious_without_registered_limitation(self):
        context = copy.deepcopy(self.context)
        context["scenario_facts"] = [fact for fact in context["scenario_facts"] if fact["fact_type"] != "limitation"]
        _, answer = self.query("¿La apertura de door_01 causó el aumento del HRR?", classify("causality", ["hrr"], anchor="FACT_001"), context)
        self.assertEqual(answer["answer_status"], "causal_not_established")
        self.assertIn("no puede afirmarse esa relación causal", answer["answer"])
        self.assertTrue(all(not fact["causal"] for fact in answer["fact_metadata"]))

    def test_dependencies_outside_scope_are_metadata_only(self):
        # Oxygen measurement is in [179,195], but its supporting opening is at 180.
        plan, answer = self.query("¿Cómo cambió el oxígeno entre 179 y 195 s?", classify("observation", ["oxygen"]))
        self.assertEqual(answer["fact_ids"], ["FACT_009"])
        self.assertEqual(plan["supporting_fact_ids"], ["FACT_001", "FACT_002"])
        self.assertNotIn("El elemento door_01 se abrió", answer["answer"])
        self.assertEqual(len(answer["supporting_fact_metadata"]), 2)

    def test_invented_time_and_contradictory_direction_do_not_get_answers(self):
        _, answer = self.query("¿Se detectó un incendio limitado por ventilación?", classify(scope={
            "time_relation": "between", "start_time_s": 1, "end_time_s": 3}))
        self.assertEqual(answer["answer_status"], "clarification_required")
        with self.assertRaises(ValueError):
            self.query("¿Estaba limitado por ventilación después de abrir la puerta?", classify(scope={"time_relation": "before"}))

    def test_invalid_and_outside_recorded_intervals(self):
        for question in ("¿Se detectó un incendio limitado por ventilación entre 195 y 179 s?",):
            with self.assertRaises(ValueError): self.query(question)
        _, answer = self.query("¿Se detectó un aumento de temperatura entre 0 y 600 s?", classify("condition", ["temperature"]))
        # Detection still describes an observed change; it does not certify coverage of the full interval.
        self.assertEqual(answer["answer_status"], "evidence_found")
        _, answer = self.query("¿Se detectó un aumento de temperatura entre 0 y 100 s?", classify("condition", ["temperature"]))
        self.assertEqual(answer["answer_status"], "insufficient_data")

    def test_before_and_after_combined_require_time_clarification(self):
        _, answer = self.query("¿Se detectó antes y después de abrir la puerta?")
        self.assertEqual(answer["answer_status"], "clarification_required")
        self.assertEqual(answer["fact_ids"], [])

    def test_topic_clarification_is_a_nonempty_product_answer(self):
        _, answer = self.query("¿Qué pasó?", classify("general", []))
        self.assertEqual(answer["answer_status"], "clarification_required")
        self.assertTrue(answer["answer"])

    def test_plan_cannot_change_ids_scope_or_status(self):
        plan, answer = self.query("¿Estaba limitado por ventilación antes de abrir la puerta?")
        for key, value in (("primary_fact_ids", ["FACT_005"]), ("answer_status", "not_detected"),
                           ("topic_assessments", []), ("supporting_fact_ids", ["FACT_001"]),
                           ("scope", {**plan["scope"], "time_relation": "after"})):
            with self.subTest(key=key):
                changed = {**plan, key: value}
                with self.assertRaisesRegex(ValueError, "ámbito/evidencia"):
                    validate_plan_context(changed, self.context, "query")

    def test_context_without_coverage_never_claims_a_negative(self):
        context = copy.deepcopy(self.context)
        context.pop("analysis_coverage")
        context.pop("measurement_snapshot", None)
        context["scenario_facts"] = [fact for fact in context["scenario_facts"] if "ventilation_limited" not in fact["knowledge_topics"]]
        for entry in context["technical_knowledge"]:
            entry["matched_fact_ids"] = [fact_id for fact_id in entry["matched_fact_ids"] if fact_id != "FACT_010"]
        _, answer = self.query("¿Se detectó un incendio limitado por ventilación?", context=context)
        self.assertEqual(answer["answer_status"], "insufficient_data")

    def test_legacy_measurement_without_interval_cannot_fill_a_scoped_range(self):
        context = copy.deepcopy(self.context)
        fact = next(f for f in context["scenario_facts"] if f["fact_id"] == "FACT_005")
        fact.pop("evidence_interval_s")
        plan, answer = self.query("¿Cómo cambió la temperatura entre 180 y 195 s?", classify("observation", ["temperature"]), context)
        self.assertEqual(answer["fact_ids"], [])
        self.assertEqual(answer["answer_status"], "insufficient_data")

    def test_nonfinite_model_time_is_rejected(self):
        with self.assertRaises(ValueError):
            self.query("¿Se detectó un incendio limitado por ventilación?", classify(scope={
                "time_relation": "before", "end_time_s": float("nan")}))

    def test_invalid_coverage_rejected_before_model(self):
        for mutation in ("room", "reason", "interval"):
            with self.subTest(mutation=mutation):
                context = copy.deepcopy(self.context)
                window = context["analysis_coverage"]["windows"][0]
                if mutation == "room": window["compartment_id"] = "other"
                if mutation == "reason": window["evaluable"] = not window["evaluable"]
                if mutation == "interval": window["end_time_s"] = 999
                with self.assertRaises(ValueError): validate_context(context)

    def test_scheduled_future_actions_are_not_recorded_facts(self):
        self.states = [self.states[0]]
        self.context = self.build()
        self.assertEqual(self.context["scenario_facts"], [])
        _, answer = self.query("¿Qué ocurrió?", classify("timeline", []))
        self.assertEqual(answer["answer_status"], "insufficient_data")
        self.assertNotIn("se abrió", answer["answer"])

    def test_multi_topic_partial_result_does_not_invent_unsupported_phenomenon(self):
        _, answer = self.query("¿Se detectaron ventilación limitada y backdraft?", classify(topics=["ventilation_limited", "backdraft"]))
        self.assertEqual(answer["answer_status"], "partial")
        self.assertEqual(answer["fact_ids"], ["FACT_010"])
        self.assertIn("No se puede confirmar ni descartar", answer["answer"])

    def test_pipeline_persists_clarification_without_partial_evidence(self):
        self.repeated_opening()
        with tempfile.TemporaryDirectory() as directory:
            run = pipeline.analyze_run(self.scenario, self.states, "ambiguous", directory)
            answer = pipeline.ask_run(run, "¿Estaba limitado por ventilación antes de abrir la puerta?", "clarify",
                                      classifier=lambda prompt, schema: json.dumps(classify()))
            self.assertEqual(answer["answer_status"], "clarification_required")
            self.assertEqual(pipeline.read_json(run / "questions/clarify/answer.json"), answer)
            pipeline.load_run(run, replay=True)


def integration():
    case = QuestionScopeTests()
    case.setUp()
    case.network.stop()
    try:
        # Real classifications are deliberately kept outside the deterministic suite.
        cases = [
            ("¿El incendio estaba limitado por ventilación antes de abrir la puerta?", "evidence_found", "condition"),
            ("¿El incendio estaba limitado por ventilación después de abrir la puerta?", "insufficient_data", "condition"),
            ("¿Hubo backdraft?", "unsupported", "condition"),
            ("¿Cómo cambió la temperatura entre 179 y 195 segundos?", "evidence_found", "observation"),
            ("¿Cómo cambió la temperatura después de 180 segundos?", "insufficient_data", "observation"),
        ]
        for question, status, intent in cases:
            plan = create_question_plan(case.context, question, "real_qwen")
            answer = render_question_answer(case.context, plan)
            assert plan["intent"] == intent, (question, plan)
            assert answer["answer_status"] == status, (question, answer)
            print("OK:", question, "->", status)
        case.scenario["actions"] = []; case.states = [case.states[0]]
        case.context = case.build()
        plan = create_question_plan(case.context, "¿Qué significa incendio limitado por ventilación?", "concept")
        answer = render_question_answer(case.context, plan)
        assert answer["answer_status"] == "theory_only", answer
        print("OK: concepto sin detección -> theory_only")
        case.scenario = pipeline.read_json(BASE_DIR / "scenarios/basic_room_001.json")
        case.states = [pipeline.read_json(path) for path in sorted((BASE_DIR / "tests/data/ventilation_limited_states").glob("*.json"))]
        case.repeated_opening()
        plan = create_question_plan(case.context, "¿Estaba limitado por ventilación antes de abrir la puerta?", "ambiguous")
        answer = render_question_answer(case.context, plan)
        assert answer["answer_status"] == "clarification_required", answer
        print("OK: apertura repetida -> clarification_required")
    finally:
        case.doCleanups()


if __name__ == "__main__":
    if sys.argv[1:] == ["--ollama"]:
        integration()
    else:
        unittest.main(verbosity=2)
