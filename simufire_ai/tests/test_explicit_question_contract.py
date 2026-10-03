"""Replay recorded model mistakes and verify narrow language constraints."""
import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

BASE_DIR=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(BASE_DIR))
import evaluate_questions as evaluation
from llm.plan_question import create_question_plan
from llm.render_question_answer import render_question_answer
from llm.question_scope import explicit_request_contract


class ExplicitQuestionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.records=json.loads((BASE_DIR/'tests/data/question_model_regressions.json').read_text(encoding='utf-8'))
        cls.contexts=evaluation.build_contexts(cls.records)
        cls.corpus=evaluation.load_corpus()[0]

    def setUp(self):
        network=patch('urllib.request.urlopen',side_effect=AssertionError('Unexpected network'))
        network.start(); self.addCleanup(network.stop)

    def test_replay_all_recorded_model_failures(self):
        for record in self.records:
            with self.subTest(case=record['case_id']):
                original=next(c for c in self.corpus['cases'] if c['id']==record['case_id'])
                raw=json.dumps(record['raw_classification'])
                result=evaluation.evaluate_case(original,self.contexts[record['fixture']],lambda p,s:raw)
                self.assertTrue(result['answer_passed'],result)
                self.assertEqual(result['raw_model_response'],raw)
                self.assertEqual(result['grounding_errors'],[])
                if record['case_id']!='holdout_009':
                    self.assertFalse(result['checks']['model_intent'])

    def test_successor_contract_corpus_and_scope_expectations(self):
        report=evaluation.run_evaluation()
        self.assertEqual(report['corpus_version'],'2')
        self.assertEqual(report['summary']['total'],76)
        self.assertEqual(report['summary']['passed'],76)
        self.assertEqual(report['summary']['answer_passed'],76)
        scoped=sum('scope' in case['expected'] for case in self.corpus['cases'])
        self.assertEqual(report['summary']['checks']['scope'],{'passed':scoped,'evaluated':scoped})

    def test_retired_holdout_is_regression_and_new_holdout_is_distinct(self):
        old=evaluation.load_corpus(evaluation.LEGACY_CORPUS_DIR)[0]
        old_questions={c['question'] for c in old['cases']}
        fresh=[c for c in self.corpus['cases'] if c['split']=='holdout']
        self.assertEqual(len(fresh),16)
        self.assertFalse(old_questions & {c['question'] for c in fresh})
        self.assertTrue(all(c['split']=='dev' and c['evaluation_role']=='regression'
            for c in self.corpus['cases'] if c['question'] in old_questions))
        self.assertEqual(self.corpus['parent_corpus_sha256'],
            evaluation.load_corpus(evaluation.LEGACY_CORPUS_DIR)[1])

    def test_definition_negation_and_unrelated_words_do_not_override(self):
        classification=copy.deepcopy(self.corpus['cases'][0]['classification'])
        for question in ('que significan las limitaciones del modelo', 'que es incertidumbre',
                         'no resumas el hrr', 'como cambio la situacion',
                         'se detecto un limite de temperatura', 'el resumen menciona temperatura'):
            with self.subTest(question=question):
                value=copy.deepcopy(classification); explicit_request_contract(question,value)
                self.assertEqual(value,classification)

    def query(self,question,classification,fixture='positive'):
        context=self.contexts[fixture]
        plan=create_question_plan(context,question,'explicit',classifier=lambda p,s:json.dumps(classification))
        return plan,render_question_answer(context,plan)

    def test_aliases_numeric_bounds_do_not_select_the_opening(self):
        classification=copy.deepcopy(self.corpus['cases'][0]['classification'])
        for question,relation,bound in (('¿Estaba limitado por ventilación previo a 170 s?','before',170),
            ('¿Estaba limitado por ventilación posterior a 180 s?','after',180),
            ('¿Estaba limitado por ventilación tras 180 s?','after',180),
            ('¿Estaba limitado por ventilación con anterioridad a 170 s?','before',170)):
            with self.subTest(question=question):
                plan,answer=self.query(question,classification)
                self.assertEqual(plan['scope']['time_relation'],relation)
                self.assertIsNone(plan['scope']['anchor_fact_id'])
                self.assertEqual(plan['scope']['end_time_s' if relation=='before' else 'start_time_s'],bound)
                self.assertEqual(answer['answer_status'],'insufficient_data')

    def test_summaries_preserve_classified_definition_or_causal_request(self):
        for intent,text in (('concept','resume la definicion de hrr'),
                            ('causality','resume que causo el aumento del hrr')):
            value=copy.deepcopy(self.corpus['cases'][0]['classification']);value['intent']=intent
            original=copy.deepcopy(value);explicit_request_contract(text,value)
            self.assertEqual(value,original)

    def test_missing_topic_requires_unique_literal_variable(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification']); source['topics']=[]
        for text,topics in (('que limitaciones tiene el aumento de temperatura',['temperature']),
                            ('resume el hrr',['hrr']),
                            ('que limitaciones tiene el incendio',[]),
                            ('que limitaciones tienen el hrr y la temperatura',[])):
            value=copy.deepcopy(source);explicit_request_contract(text,value)
            self.assertEqual(value['topics'],topics)

    def test_before_and_after_aliases_remain_ambiguous(self):
        classification=copy.deepcopy(self.corpus['cases'][0]['classification'])
        _,answer=self.query('¿Estaba limitado por ventilación antes y posterior a abrir door_01?',classification)
        self.assertEqual(answer['answer_status'],'clarification_required')
        self.assertEqual(answer['fact_ids'],[])

    def test_repeated_action_is_never_resolved_by_alias_alone(self):
        classification=copy.deepcopy(self.corpus['cases'][0]['classification'])
        context=evaluation.build_contexts([{'fixture':'repeated'}])['repeated']
        plan=create_question_plan(context,'¿Estaba limitado por ventilación previo a abrir door_01?','repeat',
            classifier=lambda p,s:json.dumps(classification))
        self.assertEqual(plan['answer_status'],'clarification_required')
        self.assertEqual(plan['clarification_needed'],'action')

    def test_uncertainty_keeps_causal_limitation_and_metadata(self):
        record=self.records[0]
        _,answer=self.query(record['question'],record['raw_classification'])
        self.assertEqual(answer['fact_ids'],['FACT_005','FACT_007'])
        self.assertIn('no son suficientes',answer['answer'])
        self.assertTrue(all(not item['causal'] for item in answer['fact_metadata']))


if __name__=='__main__':unittest.main(verbosity=2)
