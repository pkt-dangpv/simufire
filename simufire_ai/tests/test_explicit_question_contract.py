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

    def test_replay_four_v2_failures_preserves_raw_model_errors(self):
        records=json.loads((BASE_DIR/'tests/data/question_model_regressions_v2.json').read_text(encoding='utf-8'))
        contexts=evaluation.build_contexts(records)
        self.assertEqual(len(records),4)
        for record in records:
            with self.subTest(case=record['case_id']):
                original=next(c for c in self.corpus['cases'] if c['id']==record['case_id'])
                raw=json.dumps(record['raw_classification'])
                result=evaluation.evaluate_case(original,contexts[record['fixture']],lambda p,s:raw)
                self.assertTrue(result['answer_passed'],result)
                self.assertFalse(result['checks']['model_intent'])
                self.assertEqual(result['raw_model_response'],raw)
                self.assertEqual(result['grounding_errors'],[])

    def test_replay_four_v3_failures_with_raw_metrics_intact(self):
        records=json.loads((BASE_DIR/'tests/data/question_model_regressions_v3.json').read_text(encoding='utf-8'))
        contexts=evaluation.build_contexts(records)
        self.assertEqual(len(records),4)
        for record in records:
            with self.subTest(case=record['case_id']):
                case=next(c for c in self.corpus['cases'] if c['id']==record['case_id'])
                raw=json.dumps(record['raw_classification'])
                result=evaluation.evaluate_case(case,contexts[record['fixture']],lambda p,s:raw)
                self.assertTrue(result['answer_passed'],result)
                self.assertFalse(result['passed'])
                self.assertEqual(result['raw_model_response'],raw)
                self.assertEqual(result['grounding_errors'],[])
                if record['case_id']=='dev_036':
                    self.assertFalse(result['checks']['model_room_consistency'])
                    self.assertEqual(result['answer']['scope']['compartment_id'],'room_02')
                    self.assertNotIn('475',result['answer']['answer'])

    def test_generic_topic_repair_requires_unique_explicit_measured_variable(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='condition',topics=['fire_dynamics'],clarification_needed='topic')
        for text,topics in (
            ('que limites tiene el descenso de la capa de humo',['smoke_layer']),
            ('resume los datos de temperatura',['temperature']),
            ('que limites tiene el incendio',['fire_dynamics']),
            ('que limites tienen el hrr y la temperatura',['fire_dynamics'])):
            value=copy.deepcopy(source);explicit_request_contract(text,value)
            self.assertEqual(value['topics'],topics)
        for topic in ('oxygen','backdraft'):
            value=copy.deepcopy(source);value['topics']=[topic]
            explicit_request_contract('que limites tiene el descenso de la capa de humo',value)
            self.assertEqual(value['topics'],[topic])

    def test_new_presence_and_enumeration_forms_do_not_erase_other_requests(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        for text in ('quedo registrado un aumento de temperatura debido a la puerta',
                     'quedo registrado un aumento de temperatura de cuantos grados',
                     'lista todos los hechos registrados que causaron el aumento',
                     'lista todos los hechos registrados sobre temperatura',
                     'no lista todos los hechos registrados'):
            value=copy.deepcopy(source);explicit_request_contract(text,value)
            self.assertEqual(value,source)

    def test_saved_plan_room_cannot_be_repaired_like_a_model_proposal(self):
        record=json.loads((BASE_DIR/'tests/data/question_model_regressions_v3.json').read_text(encoding='utf-8'))[0]
        context=evaluation.build_contexts([record])[record['fixture']]
        plan=create_question_plan(context,record['question'],'saved_room',
            classifier=lambda p,s:json.dumps(record['raw_classification']))
        for field in ('scope','requested_scope'):
            value=copy.deepcopy(plan);value[field]['compartment_id']='room_01'
            with self.assertRaises(ValueError):render_question_answer(context,value)

    def test_mentions_of_detection_do_not_erase_magnitude_cause_or_definition(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        for text in ('cuanto subio la temperatura detectada', 'como se registro el descenso de la capa de humo',
                     'se registro un aumento de temperatura de cuanto',
                     'se detecto un aumento de temperatura causado por la apertura',
                     'se detecto un aumento de temperatura debido a abrir la puerta',
                     'se detecto un aumento de temperatura de cuantos grados',
                     'se registro un descenso de la capa de humo, que significa',
                     'que significa un aumento detectado de hrr', 'no se ha detectado un aumento de temperatura',
                     'enumera los hechos registrados sobre temperatura',
                     'enumera los hechos registrados que causaron el aumento', 'enumera las temperaturas'):
            with self.subTest(text=text):
                value=copy.deepcopy(source);explicit_request_contract(text,value)
                self.assertEqual(value,source)
        for intent in ('concept','causality','uncertainty'):
            value=copy.deepcopy(source);value['intent']=intent
            original=copy.deepcopy(value)
            explicit_request_contract('se ha detectado un aumento de temperatura',value)
            self.assertEqual(value,original)

    def test_enumeration_preserves_non_topic_ambiguity_and_physical_metadata(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='general',topics=[],clarification_needed='topic')
        context=evaluation.build_contexts([{'fixture':'warehouse_growth'}])['warehouse_growth']
        plan=create_question_plan(context,'Enumera los hechos registrados en Almacén.','list_facts',
            classifier=lambda p,s:json.dumps(source))
        answer=render_question_answer(context,plan)
        self.assertEqual(answer['fact_ids'],['FACT_001','FACT_002','FACT_003'])
        self.assertEqual(answer['knowledge_ids'],[])
        self.assertEqual(answer['source_ids'],[])
        self.assertEqual(answer['fact_metadata'],[
            {'fact_id':f['fact_id'],'certainty':f['certainty'],'causal':f['causal']}
            for f in context['scenario_facts'] if f['fact_type']!='limitation'])
        for ambiguity in ('action','compartment','time'):
            value=copy.deepcopy(source);value['clarification_needed']=ambiguity
            explicit_request_contract('enumera los hechos registrados',value)
            self.assertEqual(value['clarification_needed'],ambiguity)
        repeated=evaluation.build_contexts([{'fixture':'repeated'}])['repeated']
        plan=create_question_plan(repeated,'Enumera los hechos registrados antes de abrir door_01.','repeat_list',
            classifier=lambda p,s:json.dumps(source))
        self.assertEqual(plan['answer_status'],'clarification_required')
        self.assertEqual(plan['clarification_needed'],'action')

    def test_detection_request_never_fills_physical_facts_or_negative_coverage(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='observation',topics=['temperature'])
        contexts=evaluation.build_contexts([{'fixture':f} for f in ('warehouse_growth','warehouse_flat','gap')])
        for fixture,status,facts in (('warehouse_growth','evidence_found',['FACT_003']),
                                    ('warehouse_flat','not_detected',[]),('gap','insufficient_data',[])):
            with self.subTest(fixture=fixture):
                plan=create_question_plan(contexts[fixture],'¿Se ha detectado un aumento de temperatura?','detect',
                    classifier=lambda p,s:json.dumps(source))
                answer=render_question_answer(contexts[fixture],plan)
                self.assertEqual(plan['intent'],'condition')
                self.assertEqual(answer['answer_status'],status)
                self.assertEqual(answer['fact_ids'],facts)
                self.assertTrue(all(not f['causal'] for f in answer['fact_metadata']))

    def test_successor_contract_corpus_and_scope_expectations(self):
        report=evaluation.run_evaluation()
        self.assertEqual(report['corpus_version'],'4')
        self.assertEqual(report['summary']['total'],108)
        self.assertEqual(report['summary']['passed'],108)
        self.assertEqual(report['summary']['answer_passed'],108)
        scoped=sum('scope' in case['expected'] for case in self.corpus['cases'])
        self.assertEqual(report['summary']['checks']['scope'],{'passed':scoped,'evaluated':scoped})

    def test_retired_holdout_is_regression_and_new_holdout_is_distinct(self):
        old=evaluation.load_corpus(evaluation.PREVIOUS_CORPUS_DIR)[0]
        old_questions={c['question'] for c in old['cases']}
        fresh=[c for c in self.corpus['cases'] if c['split']=='holdout']
        self.assertEqual(len(fresh),16)
        self.assertFalse(old_questions & {c['question'] for c in fresh})
        self.assertTrue(all(c['split']=='dev' and c['evaluation_role']=='regression'
            for c in self.corpus['cases'] if c['question'] in old_questions))
        self.assertEqual(self.corpus['parent_corpus_sha256'],
            evaluation.load_corpus(evaluation.PREVIOUS_CORPUS_DIR)[1])
        inherited={c['id']:c for c in self.corpus['cases'] if c['split']=='dev'}
        self.assertEqual(set(inherited),{c['id'] for c in old['cases']})
        for previous in old['cases']:
            for field in ('question','fixture','classification','expected'):
                self.assertEqual(inherited[previous['id']][field],previous[field])

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
