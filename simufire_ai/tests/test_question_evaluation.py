"""Offline corpus and failure handling. This file never calls Ollama."""
import copy
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import URLError

BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(BASE_DIR))
import evaluate_questions as evaluation
import pipeline
from llm.plan_question import create_question_plan
from llm.render_question_answer import render_question_answer


class EvaluationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.corpus, cls.digest = evaluation.load_corpus(evaluation.LEGACY_CORPUS_DIR)
        cls.cases = cls.corpus['cases']
        cls.contexts = evaluation.build_contexts(cls.cases,evaluation.LEGACY_CORPUS_DIR)

    def setUp(self):
        network = patch('urllib.request.urlopen',side_effect=AssertionError('Unexpected network access'))
        network.start(); self.addCleanup(network.stop)

    def test_all_frozen_contracts_without_network(self):
        report = evaluation.run_evaluation(directory=evaluation.LEGACY_CORPUS_DIR)
        authored = pipeline.read_json(evaluation.CORPUS_DIR / 'expectation_changes.json')
        revised = {'dev_033', 'holdout_012'}
        self.assertEqual({r['case_id'] for r in report['results'] if not r['passed']}, revised)
        for result in report['results']:
            with self.subTest(case=result['case_id']):
                if result['case_id'] in revised:
                    change = authored[result['case_id']]
                    self.assertEqual(change['before'], result['expected'])
                    self.assertEqual(result['answer']['answer_status'], change['after']['answer_status'])
                    self.assertEqual(result['answer']['response_status'], change['after']['response_status'])
                    self.assertEqual({k for k, v in result['checks'].items() if v is False}, {'answer_status'})
                    self.assertEqual(result['answer']['fact_ids'], [])
                else:
                    self.assertTrue(result['passed'],result)
        self.assertEqual(report['summary']['total'],60)
        self.assertEqual(report['summary']['grounding_violations'],0)
        self.assertIsNone(report['model'])

    def test_coverage_and_separated_splits(self):
        self.assertGreaterEqual(len(self.cases),50)
        self.assertEqual({case['expected']['intent'] for case in self.cases},
            {'condition','observation','concept','timeline','causality','uncertainty','general'})
        self.assertEqual(len({case['fixture'] for case in self.cases}),9)
        dev = {case['question'] for case in self.cases if case['split']=='dev'}
        held = {case['question'] for case in self.cases if case['split']=='holdout'}
        self.assertFalse(dev & held)
        self.assertEqual(len(held),16)

    def test_frozen_input_change_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            shutil.copytree(evaluation.CORPUS_DIR,Path(directory)/'corpus')
            path=Path(directory)/'corpus/corpus.json'
            changed=pipeline.read_json(path); changed['cases'][0]['question']='changed'
            pipeline.write_json(path,changed)
            with self.assertRaisesRegex(ValueError,'input changed'):
                evaluation.load_corpus(path.parent)

    def test_holdout_must_be_explicit_for_model(self):
        with self.assertRaisesRegex(ValueError,'separately'):
            evaluation.run_evaluation(mode='ollama',split='all')

    def test_invalid_json_rejected_and_reported(self):
        result=evaluation.evaluate_case(self.cases[0],self.contexts['positive'],lambda p,s:'not JSON')
        self.assertFalse(result['passed'])
        self.assertEqual(result['error']['type'],'ValueError')
        self.assertNotIn('answer',result)

    def test_fabricated_topic_rejected(self):
        value=copy.deepcopy(self.cases[0]['classification']); value['topics']=['invented_fire']
        result=evaluation.evaluate_case(self.cases[0],self.contexts['positive'],lambda p,s:json.dumps(value))
        self.assertFalse(result['passed'])
        self.assertEqual(result['error']['type'],'ValueError')
        self.assertNotIn('answer',result)

    def test_timeout_and_unavailability_reported_without_answer(self):
        for error in (TimeoutError('model timeout'),URLError('model unavailable')):
            with self.subTest(error=type(error).__name__):
                def fail(prompt,schema): raise error
                result=evaluation.evaluate_case(self.cases[0],self.contexts['positive'],fail)
                self.assertFalse(result['passed'])
                self.assertNotIn('answer',result)
                self.assertIsNotNone(result['classifier_duration_s'])

    def test_model_failures_leave_no_published_question(self):
        fixture=pipeline.read_json(evaluation.CORPUS_DIR/'positive.json')
        with tempfile.TemporaryDirectory() as directory:
            pipeline.analyze_run(fixture['scenario'],fixture['states'],'failure_run',directory)
            run=Path(directory)/'failure_run'
            for error in (TimeoutError('timeout'),URLError('offline'),ValueError('bad model JSON')):
                def fail(prompt,schema): raise error
                with self.assertRaises(type(error)):
                    pipeline.ask_run(run,question='¿Hay limitación por ventilación?',question_id='failure_question',classifier=fail)
                self.assertFalse((run/'questions/failure_question').exists())
                self.assertFalse(list(run.glob('questions/.simufire-*')))
            pipeline.load_run(run,replay=True)

    def test_stale_context_rejected_before_render(self):
        case=self.cases[0]; context=copy.deepcopy(self.contexts['positive'])
        plan=create_question_plan(context,case['question'],case['id'],classifier=lambda p,s:json.dumps(case['classification']))
        context['technical_knowledge'][0]['content']+=' Changed.'
        with self.assertRaises(ValueError): render_question_answer(context,plan)

    def test_metrics_distinguish_model_error_and_grounding(self):
        case=self.cases[0]; wrong=copy.deepcopy(case['classification']); wrong['intent']='concept'
        result=evaluation.evaluate_case(case,self.contexts['positive'],lambda p,s:json.dumps(wrong))
        self.assertFalse(result['checks']['model_intent'])
        self.assertFalse(result['checks']['fact_selection'])
        self.assertFalse(result['passed'])
        self.assertEqual(result['grounding_errors'],[])

    def test_grounding_audit_detects_metadata_provenance_and_source_changes(self):
        case=self.cases[0]; context=self.contexts['positive']
        result=evaluation.evaluate_case(case,context,lambda p,s:json.dumps(case['classification']))
        mutations = [('certainty_or_causal_changed',lambda a:a['fact_metadata'][0].update(causal=True)),
            ('provenance_changed',lambda a:a['fact_provenance'][0].update(time_s=190)),
            ('foreign_source',lambda a:a['source_ids'].append('OTHER_SOURCE')),
            ('context_identity:run_id',lambda a:a.update(run_id='other'))]
        for expected, mutate in mutations:
            answer=copy.deepcopy(result['answer']); mutate(answer)
            with self.subTest(expected=expected):
                self.assertIn(expected,evaluation.grounding_errors(context,result['plan'],answer))

    def test_causal_clarification_is_not_an_unsupported_causal_assertion(self):
        context=self.contexts['repeated']
        classification=copy.deepcopy(self.cases[17]['classification'])
        plan=create_question_plan(context,'¿La apertura de door_01 causó el aumento del HRR?',
            'ambiguous_cause',classifier=lambda p,s:json.dumps(classification))
        answer=render_question_answer(context,plan)
        self.assertEqual(answer['answer_status'],'clarification_required')
        self.assertEqual(evaluation.grounding_errors(context,plan,answer),[])

    def test_invalid_http_model_envelopes_fail(self):
        from llm.plan_question import call_ollama
        for body in (b'{}',b'{"response":42}',b'[]',b'broken'):
            class Response:
                def __enter__(self): return self
                def __exit__(self,*args): return False
                def read(self): return body
            with self.subTest(body=body),patch('urllib.request.urlopen',return_value=Response()):
                with self.assertRaises(ValueError):call_ollama('prompt',{})


if __name__=='__main__':unittest.main()
