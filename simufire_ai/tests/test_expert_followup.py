"""E05/E06/E08 teaching context with room, time, source and causal boundaries."""
import copy
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE_DIR))
import evaluate_questions as evaluation
import pipeline
from llm.plan_question import create_question_plan
from llm.render_question_answer import render_question_answer
from test_analysis_pipeline import classification


class ExpertFollowupTests(unittest.TestCase):
    def setUp(self):
        network = patch('urllib.request.urlopen', side_effect=AssertionError('Deterministic test reached network'))
        network.start(); self.addCleanup(network.stop)

    def fixture(self, name):
        return pipeline.read_json(BASE_DIR / f'tests/data/question_evaluation_v8/{name}.json')

    def context(self, value, entries=None):
        return pipeline.build_analysis(value['scenario'], value['states'], 'review', entries=entries)['context.json']

    def query(self, context, question, topic, intent='condition'):
        plan = create_question_plan(context, question, 'followup',
            classifier=lambda p, s: json.dumps(classification(intent, [topic])))
        return plan, render_question_answer(context, plan)

    def test_e05_temperature_history_actions_and_room_boundary(self):
        context = self.context(self.fixture('two_rooms'))
        plan, answer = self.query(context, '¿Cómo cambió la temperatura en Cocina?', 'temperature', 'observation')
        self.assertIn('entre 179 s y 195 s', answer['answer'])
        self.assertIn('530 a 490 °C', answer['answer'])
        self.assertIn('entre 150 s y 179 s', answer['answer'])
        self.assertIn('apertura de window_02 en t=180 s', answer['answer'])
        self.assertNotIn('Nota sobre el criterio de detección', answer['answer'])
        self.assertNotIn('door_01', answer['answer'])
        self.assertTrue(all(c['compartment_id'] == 'room_02' for c in answer['measured_changes']))
        self.assertTrue(all(not c['causal'] for c in answer['fact_metadata']))
        self.assertEqual(evaluation.grounding_errors(context, plan, answer), [])

    def test_explicit_temperature_range_does_not_fetch_prior_history(self):
        _, answer = self.query(self.context(self.fixture('two_rooms')),
            '¿Cómo cambió la temperatura en Cocina entre 179 y 195 s?', 'temperature', 'observation')
        self.assertIsNone(answer['teaching_context']['temperature_reversal'])
        self.assertNotIn('530', answer['answer'])
        self.assertIn('window_02', answer['answer'])

    def test_e06_observations_are_not_a_backdraft_diagnosis(self):
        context = self.context(self.fixture('positive'))
        plan, answer = self.query(context, '¿Hubo backdraft?', 'backdraft')
        self.assertEqual(answer['answer_status'], 'unsupported')
        self.assertEqual(answer['fact_ids'], [])
        self.assertEqual(answer['knowledge_ids'], ['BACKDRAFT_001'])
        self.assertEqual(answer['source_ids'], ['NIST_BACKDRAFT_2022'])
        for term in ('t=179 s', '14.1 %', '390 °C', 'no se adopta aquí como requisito universal'):
            self.assertIn(term, answer['answer'])
        self.assertFalse(answer['teaching_context']['backdraft_sample']['diagnostic'])
        self.assertEqual(evaluation.grounding_errors(context, plan, answer), [])

    def test_backdraft_concept_does_not_include_simulation_measurements(self):
        _, answer = self.query(self.context(self.fixture('positive')), '¿Qué es backdraft?', 'backdraft', 'concept')
        self.assertEqual(answer['answer_status'], 'theory_only')
        self.assertIsNone(answer['teaching_context']['backdraft_sample'])
        self.assertNotIn('14.1', answer['answer'])

    def test_backdraft_knowledge_is_not_loaded_from_normal_context(self):
        entries = pipeline.read_json(BASE_DIR / 'tests/data/question_evaluation_v8/knowledge.json')
        _, answer = self.query(self.context(self.fixture('positive'), entries), '¿Hubo backdraft?', 'backdraft')
        self.assertEqual(answer['knowledge_ids'], [])
        self.assertEqual(answer['source_ids'], [])
        self.assertNotIn('Como marco teórico general', answer['answer'])

    def test_backdraft_sample_respects_exact_room_and_time(self):
        _, answer = self.query(self.context(self.fixture('two_rooms')), '¿Hubo backdraft en Cocina en t=160 s?', 'backdraft')
        sample = answer['teaching_context']['backdraft_sample']
        self.assertEqual((sample['compartment_id'], sample['time_s'], sample['temperature_c']), ('room_02', 160, 515))
        self.assertNotIn('390', answer['answer'])
        _, missing = self.query(self.context(self.fixture('positive')), '¿Hubo backdraft en t=181 s?', 'backdraft')
        self.assertIsNone(missing['teaching_context']['backdraft_sample'])

    def test_oxygen_values_do_not_create_backdraft_risk_or_detection_flags(self):
        for oxygen in (9.8, 14.1):
            with self.subTest(oxygen=oxygen):
                value = self.fixture('positive')
                value['states'][-2]['compartments'][0]['upper_layer']['o2_percent'] = oxygen
                _, answer = self.query(self.context(value), '¿Hubo backdraft?', 'backdraft')
                self.assertEqual(answer['response_status'], 'unsupported')
                self.assertEqual(answer['fact_ids'], [])
                self.assertFalse(answer['teaching_context']['backdraft_sample']['diagnostic'])
                self.assertNotIn('bajo riesgo', answer['answer'])

    def test_e08_common_preperiod_and_repetition_without_new_detection(self):
        context = self.context(self.fixture('repeated'))
        plan, answer = self.query(context, '¿Estaba limitado por ventilación antes de abrir la puerta?', 'ventilation_limited')
        self.assertEqual(plan['scope']['end_time_s'], 180)
        self.assertEqual(plan['clarification_needed'], 'none')
        self.assertEqual(answer['answer_status'], 'insufficient_data')
        self.assertEqual(answer['response_status'], 'preopening_observations')
        self.assertEqual(answer['fact_ids'], [])
        for term in ('150–179 s', '17 a 14.1 %', '950 a 720 kW', '430 a 390 °C', '180 s, 190 s', 'no confirman por sí solas'):
            self.assertIn(term, answer['answer'])
        self.assertNotIn('¿A qué apertura', answer['answer'])
        self.assertEqual(evaluation.grounding_errors(context, plan, answer), [])

    def test_repeated_opens_after_or_causal_still_require_disambiguation(self):
        context = self.context(self.fixture('repeated'))
        _, answer = self.query(context, '¿Estaba limitado por ventilación después de abrir la puerta?', 'ventilation_limited')
        self.assertEqual(answer['answer_status'], 'clarification_required')
        self.assertIsNone(answer['teaching_context']['preopening_observations'])

    def test_close_reopen_different_openings_and_initially_open_do_not_use_common_period(self):
        for variant in ('close_reopen', 'other_opening', 'initial_open'):
            with self.subTest(variant=variant):
                value = self.fixture('repeated')
                scenario = value['scenario']
                if variant == 'close_reopen':
                    scenario['actions'].insert(1, {'time_s': 185, 'type': 'close', 'target': 'door_01'})
                elif variant == 'other_opening':
                    scenario['openings'].append({**scenario['openings'][0], 'id': 'window_01', 'type': 'window'})
                    scenario['actions'][1]['target'] = 'window_01'
                else:
                    scenario['openings'][0]['state'] = 'open'
                _, answer = self.query(self.context(value), '¿Estaba limitado por ventilación antes de abrir?', 'ventilation_limited')
                self.assertEqual(answer['answer_status'], 'clarification_required')

    def test_explicit_second_opening_preserves_user_boundary(self):
        plan, _ = self.query(self.context(self.fixture('repeated')),
            '¿Estaba limitado por ventilación antes de abrir door_01 en t=190 s?', 'ventilation_limited')
        self.assertEqual(plan['scope']['end_time_s'], 190)

    def test_teaching_metadata_tampering_is_reported(self):
        context = self.context(self.fixture('two_rooms'))
        plan, answer = self.query(context, '¿Cómo cambió la temperatura en Cocina?', 'temperature', 'observation')
        changed = copy.deepcopy(answer)
        changed['teaching_context']['temperature_actions'][0]['target'] = 'door_01'
        self.assertIn('teaching_context_changed', evaluation.grounding_errors(context, plan, changed))


if __name__ == '__main__':
    unittest.main(verbosity=2)
