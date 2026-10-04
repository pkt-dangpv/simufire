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
from llm.question_scope import explicit_request_contract, explicit_variable_cause


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

    def test_replay_three_v4_failures_preserves_raw_metrics(self):
        records=json.loads((BASE_DIR/'tests/data/question_model_regressions_v4.json').read_text(encoding='utf-8'))
        contexts=evaluation.build_contexts(records)
        self.assertEqual(len(records),3)
        for record in records:
            with self.subTest(case=record['case_id']):
                case=next(c for c in self.corpus['cases'] if c['id']==record['case_id'])
                raw=json.dumps(record['raw_classification'])
                result=evaluation.evaluate_case(case,contexts[record['fixture']],lambda p,s:raw)
                self.assertTrue(result['answer_passed'],result)
                self.assertFalse(result['passed'])
                self.assertEqual(result['raw_model_response'],raw)
                self.assertEqual(result['grounding_errors'],[])
                if record['case_id']=='holdout_v4_007':
                    self.assertEqual(result['answer']['fact_ids'],[])
                    self.assertEqual(result['answer']['source_ids'],['NIST_CFAST_V7_TECHNICAL_REFERENCE'])
                if record['case_id']=='holdout_v4_012':
                    self.assertNotIn('temperatura',result['answer']['answer'])
                    self.assertEqual(result['answer']['fact_ids'],[])

    def test_replay_v5_causal_effect_preserves_raw_error(self):
        record=json.loads((BASE_DIR/'tests/data/question_model_regressions_v5.json').read_text(encoding='utf-8'))[0]
        context=evaluation.build_contexts([record])[record['fixture']]
        case=next(c for c in self.corpus['cases'] if c['id']==record['case_id'])
        raw=json.dumps(record['raw_classification'])
        result=evaluation.evaluate_case(case,context,lambda p,s:raw)
        self.assertTrue(result['answer_passed'],result)
        self.assertFalse(result['checks']['model_topics'])
        self.assertEqual(result['raw_model_response'],raw)
        self.assertEqual(result['answer']['answer_status'],'causal_not_established')
        self.assertEqual(result['answer']['fact_ids'],['FACT_002','FACT_004'])
        self.assertEqual(result['grounding_errors'],[])
        self.assertTrue(all(not f['causal'] for f in result['answer']['fact_metadata']))

    def test_replay_v6_why_and_due_keeps_causal_limitations_and_raw_errors(self):
        records=json.loads((BASE_DIR/'tests/data/question_model_regressions_v6.json').read_text(encoding='utf-8'))
        contexts=evaluation.build_contexts(records)
        self.assertEqual(len(records),2)
        for record in records:
            with self.subTest(case=record['case_id']):
                case=next(c for c in self.corpus['cases'] if c['id']==record['case_id'])
                raw=json.dumps(record['raw_classification'])
                result=evaluation.evaluate_case(case,contexts[record['fixture']],lambda p,s:raw)
                self.assertTrue(result['answer_passed'],result)
                self.assertFalse(result['checks']['model_intent'])
                self.assertEqual(result['raw_model_response'],raw)
                self.assertEqual(result['answer']['fact_ids'],['FACT_002','FACT_004'])
                self.assertEqual(result['answer']['answer_status'],'causal_not_established')
                self.assertIn('no puede afirmarse',result['answer']['answer'])
                self.assertNotIn('temperatura',result['answer']['answer'])
                self.assertTrue(all(not f['causal'] for f in result['answer']['fact_metadata']))

    def test_why_and_due_preserve_effect_room_and_complete_window(self):
        context=evaluation.build_contexts([{'fixture':'lab_growth'}])['lab_growth']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='observation',topics=['temperature'],clarification_needed='none')
        for question,status,ids in (
            ('¿Por qué descendió la capa de humo en Laboratorio entre 12 y 36 s?',
             'causal_not_established',['FACT_002','FACT_004']),
            ('¿La capa de humo descendió debido al incremento del HRR en Laboratorio antes de 36 s?',
             'insufficient_data',[])):
            plan=create_question_plan(context,question,'explanation',classifier=lambda p,s:json.dumps(source))
            answer=render_question_answer(context,plan)
            self.assertEqual(plan['intent'],'causality')
            self.assertEqual(plan['topics'],['smoke_layer'])
            self.assertEqual(answer['scope']['compartment_id'],'lab')
            self.assertEqual(answer['answer_status'],status)
            self.assertEqual(answer['fact_ids'],ids)
            self.assertTrue(all(not f['causal'] for f in answer['fact_metadata']))
            changed=copy.deepcopy(plan);changed['intent']='observation'
            with self.assertRaises(ValueError):render_question_answer(context,changed)

    def test_replay_v7_variable_cause_preserves_original_raw_error_and_boundary(self):
        record=json.loads((BASE_DIR/'tests/data/question_model_regressions_v7.json').read_text(encoding='utf-8'))[0]
        case=next(c for c in self.corpus['cases'] if c['id']==record['case_id'])
        context=evaluation.build_contexts([record])[record['fixture']]
        raw=record['raw_model_response']
        self.assertEqual(json.loads(raw),record['raw_classification'])
        result=evaluation.evaluate_case(case,context,lambda p,s:raw)
        self.assertTrue(result['answer_passed'],result)
        self.assertFalse(result['passed'])
        self.assertFalse(result['checks']['model_intent'])
        self.assertFalse(result['checks']['model_topics'])
        self.assertEqual(result['raw_model_response'],raw)
        self.assertIsNone(result['plan']['anchor_fact_id'])
        self.assertEqual(result['answer']['answer_status'],'insufficient_data')
        self.assertEqual(result['answer']['scope']['end_time_s'],36)
        self.assertEqual(result['answer']['fact_ids'],[])
        self.assertEqual(result['answer']['measured_changes'],[])
        self.assertEqual(result['answer']['concurrent_measurements'],[])
        self.assertIn('no puede afirmarse',result['answer']['answer'])
        self.assertEqual(result['grounding_errors'],[])

    def test_variable_cause_never_uses_fake_or_real_action_as_causal_anchor(self):
        context=evaluation.build_contexts([{'fixture':'positive'}])['positive']
        for anchor in ('action','FACT_001'):
            source=copy.deepcopy(self.corpus['cases'][0]['classification'])
            source.update(intent='causality',topics=['smoke_layer'],anchor_fact_id=anchor,
                          clarification_needed='action')
            plan=create_question_plan(context,'¿La interfaz descendió debido al incremento del HRR?',
                'variable_cause',classifier=lambda p,s:json.dumps(source))
            answer=render_question_answer(context,plan)
            self.assertIsNone(plan['anchor_fact_id'])
            self.assertEqual(plan['clarification_needed'],'none')
            self.assertEqual(answer['answer_status'],'causal_not_established')
            self.assertIn('no puede afirmarse',answer['answer'])
            self.assertTrue(all(not f['causal'] for f in answer['fact_metadata']))

    def test_variable_cause_keeps_temporal_opening_anchor_separate(self):
        context=evaluation.build_contexts([{'fixture':'positive'}])['positive']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='causality',topics=['smoke_layer'],anchor_fact_id='action')
        plan=create_question_plan(context,
            '¿La interfaz descendió debido al incremento del HRR antes de abrir door_01?',
            'temporal_action',classifier=lambda p,s:json.dumps(source))
        answer=render_question_answer(context,plan)
        self.assertIsNone(plan['anchor_fact_id'])
        self.assertEqual(plan['scope']['anchor_fact_id'],'FACT_001')
        self.assertEqual(plan['scope']['end_time_s'],180)
        self.assertEqual(plan['scope']['time_relation'],'before')
        self.assertNotEqual(answer['answer_status'],'clarification_required')
        self.assertIn('no puede afirmarse',answer['answer'])
        self.assertTrue(all(not f['causal'] for f in answer['fact_metadata']))

    def test_actual_action_cause_keeps_strict_action_validation(self):
        context=evaluation.build_contexts([{'fixture':'positive'}])['positive']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='causality',topics=['hrr'],anchor_fact_id='FACT_001')
        question='¿La apertura de door_01 causó el aumento del HRR?'
        plan=create_question_plan(context,question,'real_action',classifier=lambda p,s:json.dumps(source))
        self.assertEqual(plan['anchor_fact_id'],'FACT_001')
        self.assertEqual(render_question_answer(context,plan)['answer_status'],'causal_not_established')
        source['anchor_fact_id']='action'
        with self.assertRaises(ValueError):
            create_question_plan(context,question,'invalid_action',classifier=lambda p,s:json.dumps(source))

    def test_persisted_variable_cause_plan_rejects_injected_real_action_anchor(self):
        context=evaluation.build_contexts([{'fixture':'positive'}])['positive']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='causality',topics=['smoke_layer'],anchor_fact_id=None)
        plan=create_question_plan(context,'¿La interfaz descendió debido al incremento del HRR?',
            'tampering',classifier=lambda p,s:json.dumps(source))
        changed=copy.deepcopy(plan);changed['anchor_fact_id']='FACT_001'
        with self.assertRaises(ValueError):render_question_answer(context,changed)

    def test_variable_cause_guard_leaves_complex_or_action_causes_untouched(self):
        for text in ('por que descendio la interfaz',
                     'la interfaz no descendio debido al incremento del hrr',
                     'la interfaz descendio debido al hrr o la temperatura',
                     'la interfaz descendio debido a una causa desconocida',
                     'la interfaz descendio debido a la apertura de door_01',
                     'la interfaz descendio debido al hrr de la apertura de door_01',
                     'la interfaz descendio debido al hrr y al oxigeno'):
            with self.subTest(text=text):self.assertFalse(explicit_variable_cause(text))

    def test_explanation_repair_does_not_erase_negation_ambiguity_or_other_requests(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='observation',topics=['temperature'])
        for text in ('por que no descendio la capa de humo',
                     'por que descendio la capa de humo y aumento la temperatura',
                     'por que descendio la interfaz o el hrr',
                     'por que descendio el backdraft',
                     'por que descendio la variable desconocida',
                     'por que el concepto de hrr significa potencia',
                     'define por que descendio la capa de humo',
                     'cuanto descendio la capa de humo debido al incremento del hrr',
                     'la capa de humo no descendio debido al incremento del hrr',
                     'la capa de humo descendio debido al incremento del hrr o la temperatura',
                     'la definicion de la capa de humo cambio debido al concepto de hrr',
                     'segun el informe la capa de humo descendio debido al incremento del hrr',
                     'la capa de humo descendio debido al backdraft',
                     'la capa de humo descendio debido a una causa desconocida'):
            value=copy.deepcopy(source);explicit_request_contract(text,value)
            self.assertEqual(value,source,text)
        value=copy.deepcopy(source)
        explicit_request_contract('se detecto un aumento del hrr debido al oxigeno',value)
        self.assertEqual(value,source)

    def test_causal_roles_reverse_without_establishing_a_cause(self):
        context=evaluation.build_contexts([{'fixture':'lab_growth'}])['lab_growth']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='causality',topics=['hrr'],clarification_needed='topic')
        for question,topics,ids,knowledge in (
            ('¿El incremento del HRR causó el descenso de la interfaz de la capa de humo?',
             ['smoke_layer'],['FACT_002','FACT_004'],['SMOKE_LAYER_001']),
            ('¿El descenso de la interfaz de la capa de humo provocó el aumento del HRR?',
             ['hrr'],['FACT_001'],['HRR_001'])):
            source['topics']=['hrr' if topics==['smoke_layer'] else 'smoke_layer']
            plan=create_question_plan(context,question,'roles',classifier=lambda p,s:json.dumps(source))
            answer=render_question_answer(context,plan)
            self.assertEqual(plan['intent'],'causality')
            self.assertEqual(plan['topics'],topics)
            self.assertIsNone(plan['anchor_fact_id'])
            self.assertEqual(answer['fact_ids'],ids)
            self.assertEqual(answer['knowledge_ids'],knowledge)
            self.assertEqual(answer['answer_status'],'causal_not_established')
            self.assertIn('no puede afirmarse',answer['answer'])
            self.assertTrue(all(not f['causal'] for f in answer['fact_metadata']))

    def test_causal_effect_repair_preserves_room_time_and_saved_plan_validation(self):
        context=evaluation.build_contexts([{'fixture':'lab_growth'}])['lab_growth']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='causality',topics=['hrr'])
        plan=create_question_plan(context,
            '¿El incremento del HRR causó el descenso de la capa de humo en Laboratorio antes de 36 s?',
            'scoped_effect',classifier=lambda p,s:json.dumps(source))
        answer=render_question_answer(context,plan)
        self.assertEqual(plan['topics'],['smoke_layer'])
        self.assertEqual(answer['scope']['compartment_id'],'lab')
        self.assertEqual(answer['scope']['end_time_s'],36)
        self.assertEqual(answer['answer_status'],'insufficient_data')
        self.assertEqual(answer['fact_ids'],[])
        changed=copy.deepcopy(plan);changed['topics']=['hrr']
        with self.assertRaises(ValueError):render_question_answer(context,changed)

    def test_causal_effect_ambiguous_unsupported_and_other_requests_are_not_rewritten(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='causality',topics=['hrr'])
        for text in ('el incremento del hrr no causo el descenso de la capa de humo',
                     'el incremento del hrr causo el descenso de la capa de humo y el aumento de temperatura',
                     'el incremento del hrr o la temperatura causo el descenso de la capa de humo',
                     'el incremento del hrr causo backdraft',
                     'el incremento del hrr causo un cambio desconocido',
                     'el incremento del hrr causo el descenso de humo, segun el informe',
                     'si el incremento del hrr causo el descenso de la capa de humo',
                     'resume si el incremento del hrr causo el descenso de la capa de humo',
                     'la capa de humo fue causada por el incremento del hrr',
                     'el incremento del hrr causo que la temperatura causo el descenso de la capa de humo'):
            value=copy.deepcopy(source);explicit_request_contract(text,value)
            self.assertEqual(value,source,text)
        for intent in ('concept','general','observation','uncertainty','condition','timeline'):
            value=copy.deepcopy(source);value['intent']=intent
            original=copy.deepcopy(value)
            explicit_request_contract('el incremento del hrr causo el descenso de la capa de humo',value)
            self.assertEqual(value,original,intent)

    def test_direct_requests_preserve_cause_negation_and_multiple_variables(self):
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='general',topics=['fire_dynamics'])
        for text in ('hubo crecimiento del hrr causado por la puerta',
                     'no hubo crecimiento del hrr', 'no define la capa de humo',
                     'define que causo el descenso de la capa de humo',
                     'define temperatura y oxigeno',
                     'define temperatura y backdraft',
                     'cuanto cambio la temperatura y la ventilacion',
                     'cuanto vale la temperatura',
                     'cuanto representa el hrr como concepto',
                     'indica cuanto aumento la temperatura y el hrr',
                     'cuanto aumento la temperatura debido a la puerta',
                     'el informe define la capa de humo'):
            value=copy.deepcopy(source);explicit_request_contract(text,value)
            self.assertEqual(value,source,text)

    def test_definition_has_theory_only_even_when_model_proposes_measurement(self):
        context=evaluation.build_contexts([{'fixture':'lab_growth'}])['lab_growth']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='observation',topics=['fire_dynamics'],clarification_needed='topic')
        plan=create_question_plan(context,'Define la capa de humo como concepto.','concept_only',
            classifier=lambda p,s:json.dumps(source))
        answer=render_question_answer(context,plan)
        self.assertEqual(plan['intent'],'concept')
        self.assertEqual(answer['answer_status'],'theory_only')
        self.assertEqual(answer['fact_ids'],[])
        self.assertNotIn('2.8',answer['answer'])
        self.assertEqual(answer['knowledge_ids'],['SMOKE_LAYER_001'])

    def test_magnitude_uses_literal_variable_without_bypassing_time_coverage(self):
        context=evaluation.build_contexts([{'fixture':'positive'}])['positive']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='observation',topics=['temperature'])
        for question,status,ids in (
            ('Indica cuánto descendió la capa de humo entre 179 y 195 s.','evidence_found',['FACT_004']),
            ('Indica cuánto descendió la capa de humo posterior a 180 s.','insufficient_data',[])):
            plan=create_question_plan(context,question,'literal_measure',classifier=lambda p,s:json.dumps(source))
            answer=render_question_answer(context,plan)
            self.assertEqual(plan['topics'],['smoke_layer'])
            self.assertEqual(answer['answer_status'],status)
            self.assertEqual(answer['fact_ids'],ids)
            self.assertNotIn('temperatura',answer['answer'])
            self.assertTrue(all(not f['causal'] for f in answer['fact_metadata']))

    def test_saved_explicit_intent_cannot_be_changed_after_resolution(self):
        context=evaluation.build_contexts([{'fixture':'lab_growth'}])['lab_growth']
        source=copy.deepcopy(self.corpus['cases'][0]['classification'])
        source.update(intent='observation',topics=['hrr'])
        plan=create_question_plan(context,'Indica cuánto aumentó el HRR entre 12 y 36 s.','intent_bound',
            classifier=lambda p,s:json.dumps(source))
        changed=copy.deepcopy(plan);changed['intent']='concept'
        with self.assertRaises(ValueError):render_question_answer(context,changed)

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
        for text in ('como se registro el descenso de la capa de humo',
                     'se registro un aumento de temperatura de cuanto',
                     'se detecto un aumento de temperatura causado por la apertura',
                     'se detecto un aumento de temperatura debido a abrir la puerta',
                     'se detecto un aumento de temperatura de cuantos grados',
                     'se registro un descenso de la capa de humo, que significa',
                     'no se ha detectado un aumento de temperatura',
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
        for text,intent,topics in (
            ('cuanto subio la temperatura detectada','observation',['temperature']),
            ('que significa un aumento detectado de hrr','concept',['hrr'])):
            value=copy.deepcopy(source);explicit_request_contract(text,value)
            self.assertEqual(value['intent'],intent)
            self.assertEqual(value['topics'],topics)

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
        self.assertEqual(report['corpus_version'],'9')
        self.assertEqual(report['summary']['total'],160)
        self.assertEqual(report['summary']['passed'],160)
        self.assertEqual(report['summary']['answer_passed'],160)
        scoped=sum('scope' in case['expected'] for case in self.corpus['cases'])
        self.assertEqual(report['summary']['checks']['scope'],{'passed':scoped,'evaluated':scoped})

    def test_expert_successor_preserves_inputs_and_declares_all_cases_as_regressions(self):
        old=evaluation.load_corpus(evaluation.PREVIOUS_CORPUS_DIR)[0]
        authored=json.loads((evaluation.CORPUS_DIR/'expectation_changes.json').read_text(encoding='utf-8'))
        self.assertEqual(set(authored),{'holdout_v6_016', 'holdout_v2_016', 'holdout_v3_013', 'holdout_012', 'dev_033', 'holdout_v5_019'})
        self.assertTrue(all(c['split']=='dev' and c['evaluation_role']=='regression' for c in self.corpus['cases']))
        self.assertEqual(self.corpus['parent_corpus_sha256'],evaluation.load_corpus(evaluation.PREVIOUS_CORPUS_DIR)[1])
        inherited={c['id']:c for c in self.corpus['cases']}
        self.assertEqual(set(inherited),{c['id'] for c in old['cases']})
        for previous in old['cases']:
            current=inherited[previous['id']]
            for field in ('question','fixture','classification'):
                self.assertEqual(current[field],previous[field])
            if previous['id'] in authored:
                change=authored[previous['id']]
                self.assertEqual(change['before'],previous['expected'])
                self.assertEqual(change['after'],current['expected'])
                for field in ('intent','topics','fact_ids','knowledge_ids'):
                    self.assertEqual(current['expected'][field],previous['expected'][field])
            else:
                self.assertEqual(current['expected'],previous['expected'])
        for path in evaluation.PREVIOUS_CORPUS_DIR.glob('*.json'):
            if path.name not in ('corpus.json','freeze.json','expectation_changes.json'):
                self.assertEqual(path.read_bytes(),(evaluation.CORPUS_DIR/path.name).read_bytes())

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

    def test_repeated_opening_alias_uses_common_preperiod_without_diagnosis(self):
        classification=copy.deepcopy(self.corpus['cases'][0]['classification'])
        context=evaluation.build_contexts([{'fixture':'repeated'}])['repeated']
        plan=create_question_plan(context,'¿Estaba limitado por ventilación previo a abrir door_01?','repeat',
            classifier=lambda p,s:json.dumps(classification))
        self.assertEqual(plan['answer_status'],'insufficient_data')
        self.assertEqual(plan['clarification_needed'],'none')
        self.assertEqual(plan['scope']['end_time_s'],180)

    def test_uncertainty_keeps_causal_limitation_and_metadata(self):
        record=self.records[0]
        _,answer=self.query(record['question'],record['raw_classification'])
        self.assertEqual(answer['fact_ids'],['FACT_005','FACT_007'])
        self.assertIn('no son suficientes',answer['answer'])
        self.assertTrue(all(not item['causal'] for item in answer['fact_metadata']))


if __name__=='__main__':unittest.main(verbosity=2)
