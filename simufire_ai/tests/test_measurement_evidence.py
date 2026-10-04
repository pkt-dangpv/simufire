"""Expert-review regressions: measured values versus detector decisions, offline."""
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
from analyzer.measurement_evidence import scoped_changes
from llm.plan_question import create_question_plan
from llm.question_context import validate_context, context_fingerprint
from llm.render_question_answer import render_question_answer
from test_analysis_pipeline import classification


class MeasurementTests(unittest.TestCase):
    def setUp(self):
        network = patch('urllib.request.urlopen', side_effect=AssertionError('Offline test reached network'))
        network.start()
        self.addCleanup(network.stop)

    def context(self, fixture):
        value = pipeline.read_json(BASE_DIR / f'tests/data/question_evaluation_v7/{fixture}.json')
        return pipeline.build_analysis(value['scenario'], value['states'], 'expert_' + fixture)['context.json']

    def answer(self, context, question, topic, intent='condition'):
        plan = create_question_plan(context, question, 'review',
            classifier=lambda p, s: json.dumps(classification(intent, [topic])))
        return render_question_answer(context, plan)

    def test_e04_real_twenty_percent_is_not_reported_as_no_increase(self):
        answer = self.answer(self.context('garage_below'), '¿Hubo un incremento del HRR en Garaje?', 'hrr')
        self.assertTrue(answer['answer'].startswith('Sí hubo un incremento real del HRR del 20.0 % (+20 kW)'))
        self.assertIn('el HRR aumentó de 100 a 120 kW', answer['answer'])
        self.assertEqual(answer['response_status'], 'measured_change')
        self.assertNotIn('no demuestra su ausencia', answer['answer'])
        self.assertIn('+20.0 %', answer['answer'])
        self.assertIn('estrictamente superior al 20 %', answer['answer'])
        self.assertIn('tasa media entre las dos muestras es 1 kW/s', answer['answer'])
        self.assertNotIn('No se detectó un aumento del HRR', answer['answer'])
        self.assertEqual(answer['detector_assessment_status'], 'not_detected')
        self.assertEqual(answer['fact_ids'], [])
        change = answer['measured_changes'][0]
        self.assertEqual((change['previous'], change['current'], change['delta']), (100, 120, 20))
        self.assertFalse(change['criterion']['met'])
        self.assertFalse(change['causal'])
        self.assertEqual({c['topic'] for c in answer['concurrent_measurements']},{'temperature','smoke_layer'})
        self.assertTrue(all(c['role']=='concurrent_context' and not c['causal'] for c in answer['concurrent_measurements']))
        self.assertEqual((change['start_time_s'], change['end_time_s']), (10, 30))

    def test_exact_threshold_temperature_and_smoke_values_still_reported(self):
        context = self.context('garage_below')
        temperature = self.answer(context, '¿Cambió la temperatura en Garaje?', 'temperature', 'observation')
        smoke = self.answer(context, '¿Cambió la interfaz en Garaje?', 'smoke_layer', 'observation')
        self.assertIn('40 a 89.9 °C', temperature['answer'])
        self.assertIn('+49.9 °C', temperature['answer'])
        self.assertIn('2.5 a 2.351 m', smoke['answer'])
        self.assertAlmostEqual(smoke['measured_changes'][0]['delta'], -.149)

    def test_e01_plain_wording_conditional_flashover_and_flags(self):
        answer = self.answer(self.context('positive'), '¿Estaba limitado por ventilación antes de abrir la puerta?', 'ventilation_limited')
        self.assertIn('La evolución registrada es compatible con un incendio limitado por ventilación', answer['answer'])
        self.assertNotIn('patrón temporal compatible con una condición', answer['answer'])
        self.assertIn('flashover inducido por ventilación', answer['answer'])
        self.assertIn('no una detección de flashover', answer['answer'])
        self.assertEqual(answer['fact_metadata'], [{'fact_id':'FACT_010','certainty':'moderate','causal':False}])

    def test_e02_comparison_is_explicitly_outside_after_scope(self):
        answer = self.answer(self.context('positive'), '¿Estaba limitado por ventilación después de abrir la puerta?', 'ventilation_limited')
        self.assertEqual(answer['answer_status'], 'insufficient_data')
        self.assertEqual(answer['fact_ids'], [])
        self.assertEqual(answer['measured_changes'], [])
        comparison = answer['opening_comparison']
        self.assertEqual((comparison['action_time_s'], comparison['related_fact_id']), (180, 'FACT_010'))
        self.assertFalse(comparison['causal'])
        self.assertIn('incluye una muestra anterior y otra posterior', answer['answer'])
        self.assertEqual(answer['response_status'], 'ventilation_response_compatible')
        self.assertIn('recuperación del oxígeno y del HRR', answer['answer'])
        self.assertIn('+77.8 %', answer['answer'])
        self.assertNotIn('Los datos disponibles no permiten evaluar', answer['answer'])
        self.assertIn('no es un intervalo completamente posterior', answer['answer'])
        self.assertTrue(all(c['role'] == 'opening_comparison' for c in comparison['changes']))

    def test_e03_geometry_and_positive_theory_without_invented_causes(self):
        answer = self.answer(self.context('lab_growth'), '¿Por qué descendió la interfaz en Laboratorio?', 'smoke_layer', 'causality')
        change = answer['measured_changes'][0]
        self.assertAlmostEqual(change['upper_layer_volume_change_m3'], 7.2)
        self.assertAlmostEqual(change['mean_net_volume_change_m3_s'], .3)
        self.assertIn('7.2 m³', answer['answer'])
        self.assertIn('0.3 m³/s', answer['answer'])
        self.assertIn('penacho transporta productos de combustión y arrastra aire', answer['answer'])
        self.assertIn('PV = mRT', answer['answer'])
        self.assertIn('alimentada por los gases del incendio y el aire arrastrado por el penacho térmico', answer['answer'])
        self.assertIn('La limitación pendiente es cuantitativa', answer['answer'])
        self.assertNotIn('no puede afirmarse una causa única', answer['answer'])
        self.assertIn('no demuestra retención del 100 %', answer['answer'])
        self.assertTrue(all(not m['causal'] for m in answer['fact_metadata']))
        self.assertFalse(answer['answer'].startswith('Con los datos disponibles no puede afirmarse'))

    def test_room_and_strict_bounds_do_not_bridge_or_interpolate_samples(self):
        context = self.context('lab_growth')
        scope = {'compartment_id':'lab','time_relation':'before','anchor_fact_id':None,'start_time_s':None,'end_time_s':36}
        self.assertEqual(scoped_changes(context, scope, ['smoke_layer']), [])
        scope.update(time_relation='between', start_time_s=12, end_time_s=36)
        self.assertEqual(len(scoped_changes(context, scope, ['smoke_layer'])), 1)
        scope.update(start_time_s=13)
        self.assertEqual(scoped_changes(context, scope, ['smoke_layer']), [])
        context = self.context('two_rooms')
        scope.update(compartment_id='room_02',time_relation='all',start_time_s=None,end_time_s=None)
        room_changes = scoped_changes(context,scope,['temperature'])
        self.assertGreater(len(room_changes),0)
        self.assertTrue(all(c['compartment_id']=='room_02' for c in room_changes))

    def test_single_sample_and_zero_baseline_are_not_invented(self):
        fixture=pipeline.read_json(BASE_DIR/'tests/data/question_evaluation_v7/garage_below.json')
        fixture['states'][0]['compartments'][0]['hrr_kw']=0
        context=pipeline.build_analysis(fixture['scenario'],fixture['states'],'zero')['context.json']
        answer=self.answer(context,'¿Cambió el HRR en Garaje?', 'hrr','observation')
        self.assertIsNone(answer['measured_changes'][0]['relative_change_percent'])
        self.assertIn('valor inicial es cero',answer['answer'])
        context=pipeline.build_analysis(fixture['scenario'],fixture['states'][:1],'single')['context.json']
        self.assertEqual(self.answer(context,'¿Hubo un aumento del HRR en Garaje?', 'hrr')['measured_changes'],[])

    def test_snapshot_bound_to_context_and_run_not_current_files(self):
        context=self.context('garage_below')
        plan=create_question_plan(context,'¿Hubo un incremento del HRR en Garaje?', 'bound',
            classifier=lambda p,s:json.dumps(classification('condition',['hrr'])))
        changed=copy.deepcopy(context)
        changed['measurement_snapshot']['states'][-1]['compartments'][0]['hrr_kw']=119
        self.assertNotEqual(context_fingerprint(changed),context_fingerprint(context))
        with self.assertRaisesRegex(ValueError,'no corresponde'):
            render_question_answer(changed,plan)
        changed=copy.deepcopy(context)
        changed['measurement_snapshot']['states'][0]['scenario_id']='other'
        with self.assertRaisesRegex(ValueError,'otro escenario'):
            validate_context(changed)
        changed=copy.deepcopy(context)
        changed['measurement_snapshot']['states'][-1]['compartments'][0]['hrr_kw']=140
        with self.assertRaisesRegex(ValueError,'distintos análisis'):
            validate_context(changed)
        with tempfile.TemporaryDirectory() as directory:
            data=context['measurement_snapshot']
            run=pipeline.analyze_run(data['scenario'],data['states'],'tamper',directory)
            artifacts=pipeline.load_run(run)
            artifacts['context.json']['measurement_snapshot']['states'][-1]['compartments'][0]['hrr_kw']=119
            artifacts['manifest.json']['artifact_sha256']['context.json']=context_fingerprint(artifacts['context.json'])
            pipeline.write_json(run/'context.json',artifacts['context.json'])
            pipeline.write_json(run/'manifest.json',artifacts['manifest.json'])
            with self.assertRaisesRegex(ValueError,'Mediciones mezcladas'):
                pipeline.load_run(run)

    def test_sampling_gap_is_endpoint_change_not_intermediate_evidence(self):
        fixture=pipeline.read_json(BASE_DIR/'tests/data/question_evaluation_v7/garage_below.json')
        fixture['states'][-1]['time_s']=100
        context=pipeline.build_analysis(fixture['scenario'],fixture['states'],'gap')['context.json']
        answer=self.answer(context,'¿Hubo un incremento del HRR en Garaje?', 'hrr')
        self.assertEqual(answer['answer_status'],'insufficient_data')
        self.assertTrue(answer['measured_changes'][0]['sampling_gap'])
        self.assertIn('no describe la evolución intermedia',answer['answer'])

    def test_real_subthreshold_change_does_not_confirm_its_cause(self):
        answer=self.answer(self.context('garage_below'),'¿Por qué aumentó la temperatura en Garaje?', 'temperature','causality')
        self.assertEqual(answer['response_status'],'causal_not_established')
        self.assertEqual(answer['detector_assessment_status'],'not_detected')
        self.assertIn('+49.9 °C',answer['answer'])
        self.assertNotIn('no demuestra su ausencia',answer['answer'])
        self.assertTrue(all(not change['causal'] for change in answer['measured_changes']))

    def test_evaluation_detects_altered_measurement_and_comparison_metadata(self):
        import evaluate_questions as evaluation
        for fixture, question, topic in (
            ('garage_below','¿Hubo un incremento del HRR en Garaje?','hrr'),
            ('positive','¿Estaba limitado por ventilación después de abrir la puerta?','ventilation_limited'),
        ):
            context=self.context(fixture)
            plan=create_question_plan(context,question,'audit',
                classifier=lambda p,s:json.dumps(classification('condition',[topic])))
            answer=render_question_answer(context,plan)
            self.assertEqual(evaluation.grounding_errors(context,plan,answer),[])
            changed=copy.deepcopy(answer)
            changed['response_status']='fuel_limited_confirmed'
            self.assertIn('response_status_changed',evaluation.grounding_errors(context,plan,changed))
            if fixture=='garage_below':
                for field, value in (('current',999),('delta',0),('causal',True),('compartment_id','other'),('start_time_s',0)):
                    changed=copy.deepcopy(answer)
                    changed['measured_changes'][0][field]=value
                    self.assertIn('measurement_evidence_changed',evaluation.grounding_errors(context,plan,changed))
                changed=copy.deepcopy(answer)
                changed['concurrent_measurements'][0]['role']='requested_scope'
                self.assertIn('concurrent_measurements_changed',evaluation.grounding_errors(context,plan,changed))
            else:
                changed=copy.deepcopy(answer)
                changed['opening_comparison']['changes'][0]['role']='requested_scope'
                self.assertIn('opening_comparison_changed',evaluation.grounding_errors(context,plan,changed))


if __name__ == '__main__':
    unittest.main(verbosity=2)
