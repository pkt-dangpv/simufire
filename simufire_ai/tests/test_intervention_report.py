"""Integrated evidence cutoff, source separation, criteria and publication checks."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BASE=Path(__file__).resolve().parents[1];sys.path.insert(0,str(BASE));sys.path.insert(0,str(BASE/'tests'))
from tactics.intervention import build_intervention_report
from tactics.intervention_presentation import render_html,render_markdown
from tactics.hydraulics import digest,read_profile
from tactics.flow_context import evaluate_flow_profile
from tactics.catalogue import load_catalog
from test_flow_context import FlowContextTests


class InterventionTests(unittest.TestCase):
    def setUp(self):
        helper=FlowContextTests();helper.setUp();self.addCleanup(helper.doCleanups)
        self.profile=helper.profile;self.declared=helper.context
        self.fixture=read_profile(BASE/'tests/data/question_evaluation_v9/positive.json')
        self.request=read_profile(BASE/'tests/data/intervention_request_synthetic.json')
        self.assertEqual(self.request['hydraulic_profile_sha256'],digest(self.profile))

    def build(self):return build_intervention_report(self.fixture,self.profile,self.declared,self.request)

    def test_cutoff_excludes_future_observations_actions_and_retrospective_detector(self):
        report=self.build()
        self.assertEqual([r['time_s'] for r in report['observations']],[150,160,170,179])
        self.assertEqual(report['recorded_actions'],[])
        self.assertFalse(any('ventilation_limited' in f['knowledge_topics'] for f in report['physical_facts']))
        self.fixture['states'][-1]['compartments'][0]['hrr_kw']=2500
        self.fixture['scenario']['actions'][0]['time_s']=190
        changed=self.build()
        for field in ('observations','changes','physical_facts','recorded_actions','options'):
            self.assertEqual(report[field],changed[field])
        self.assertEqual(report['provenance']['effective_inputs_sha256'],changed['provenance']['effective_inputs_sha256'])
        self.assertNotEqual(report['provenance']['fixture_sha256'],changed['provenance']['fixture_sha256'])

    def test_retrospective_report_preserves_fact_certainty_causal_flags_and_zone_units(self):
        self.request['decision_time_s']=195
        report=self.build()
        facts=[f for f in report['physical_facts'] if 'ventilation_limited' in f['knowledge_topics']]
        self.assertEqual(len(facts),1);self.assertEqual(facts[0]['certainty'],'moderate');self.assertFalse(facts[0]['causal'])
        self.assertEqual(report['recorded_actions'][0]['time_s'],180)
        before=report['observations'][-2]
        self.assertEqual(before['lower_co_ppm'],800)
        self.assertEqual(before['lower_temperature_c'],65)
        self.assertIsNone(report['survivability']['survival_probability']);self.assertIsNone(report['survivability']['fed'])

    def test_hydraulic_result_is_exact_existing_result_and_catalog_does_not_supply_curves(self):
        report=self.build();self.assertEqual(report['hydraulic'],evaluate_flow_profile(self.profile,self.declared))
        self.assertAlmostEqual(report['hydraulic']['operating_point']['flow_l_min'],444.4444444444)
        self.assertAlmostEqual(report['hydraulic']['water_at_predicted_operating_point']['minutes_to_reserve'],3.6)
        self.assertEqual(report['operational_reference']['simplified_opening_references'][0]['reference_flow_l_min'],80)
        catalog=load_catalog();catalog['equipment'][0]['facts'][0]['value']=999999
        other=build_intervention_report(self.fixture,self.profile,self.declared,self.request,catalog=catalog)
        self.assertEqual(report['hydraulic'],other['hydraulic'])
        self.assertFalse(report['equipment_inventory_verified']);self.assertFalse(report['operational_reference']['fire_extinction_sufficiency_confirmed'])

    def test_strict_flow_reference_and_pressure_limit_do_not_become_extinction_guarantee(self):
        self.assertTrue(self.build()['operational_reference']['predicted_point_meets_numeric_reference'])
        for p in self.profile['pump']['curve']:p['pressure_bar']-=1.2
        self.request['hydraulic_profile_sha256']=digest(self.profile);self.declared['profile_sha256']=digest(self.profile)
        report=self.build();self.assertAlmostEqual(report['hydraulic']['operating_point']['flow_l_min'],400)
        self.assertFalse(report['operational_reference']['predicted_point_meets_numeric_reference'])
        self.assertFalse(report['operational_reference']['fire_extinction_sufficiency_confirmed'])

    def test_missing_conditions_block_inference_and_all_true_declarations_never_authorize(self):
        report=self.build();option=next(o for o in report['options'] if o['id']=='ventilation')
        self.assertIn('suppression_coordinated',option['unfulfilled_fields'])
        self.assertIn('wind_assessed',option['missing_fields'])
        self.assertFalse(report['automatic_tactical_decision'])
        for key in self.request['resources']:
            if key!='crew_count':self.request['resources'][key]=True
        complete=self.build()
        self.assertTrue(all(not o['authorized_operation'] for o in complete['options']))
        self.assertFalse(complete['survivability']['survival_probability'] is not None)

    def test_pressure_goal_conflict_and_local_limit_are_visible_without_claiming_local_exceedance(self):
        self.declared['target_nozzle_pressure_bar']=6
        report=self.build()
        self.assertIn('Presión objetivo incompatible',render_markdown(report))
        self.assertEqual(next(o for o in report['options'] if o['id']=='direct')['status'],'hydraulic_review_required')
        self.declared['target_nozzle_pressure_bar']=5
        self.declared['connected_elements'][0]['max_working_pressure_bar']=6
        report=self.build()
        self.assertTrue(report['operational_reference']['predicted_point_meets_numeric_reference'])
        self.assertIn('no demuestra una superación local',render_html(report))
        self.assertTrue(next(o for o in report['options'] if o['id']=='direct')['hydraulic_review_required'])

    def test_bound_scope_future_resource_record_and_nonwater_requests_rejected(self):
        mutations=[lambda r:r.update(scenario_id='other'),lambda r:r.update(compartment_id='room_02'),
            lambda r:r.update(hydraulic_profile_sha256='0'*64),lambda r:r.update(resources_recorded_at_s=180),
            lambda r:r.update(decision_time_s=100),lambda r:r.update(compare_full_opening_ids=['unknown']),
            lambda r:r.update(decision_time_s=float('nan'))]
        original=copy.deepcopy(self.request)
        for mutate in mutations:
            self.request=copy.deepcopy(original);mutate(self.request)
            with self.assertRaises(ValueError):self.build()
        self.request=original;self.declared['agent']='CAFS'
        with patch('tactics.intervention.evaluate_flow_profile',side_effect=AssertionError('Nonwater invoked')):
            with self.assertRaises(ValueError):self.build()

    def test_presentations_keep_room_time_layers_units_and_escape_injected_markup(self):
        report=self.build();text=render_markdown(report);html=render_html(report)
        for token in ('179','444.444','8.556','5.444','3.600','800','No aportado','CO inferior (ppm)'):
            self.assertIn(token,text);self.assertIn(token,html)
        self.assertLess(text.index('45 mm'),text.index('Pérdida de manguera'))
        self.assertIn('444,444',render_markdown(report,number_format='es'))
        report['room']['name']='<script>alert(1)</script>'
        self.assertNotIn('<script>',render_html(report));self.assertIn('&lt;script&gt;',render_html(report))

    def test_cli_publishes_complete_report_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name,value in [('case',self.fixture),('profile',self.profile),('context',self.declared),('request',self.request)]:
                (root/(name+'.json')).write_text(json.dumps(value),encoding='utf-8')
            args=[sys.executable,str(BASE/'intervention.py'),'--case',str(root/'case.json'),'--profile',str(root/'profile.json'),
                  '--installation-context',str(root/'context.json'),'--request',str(root/'request.json'),'--output-dir',str(root/'report')]
            run=subprocess.run(args,capture_output=True,text=True);self.assertEqual(run.returncode,0,run.stderr)
            expected={'case.json','profile.json','request.json','report.json','installation_context.json','informe.md','informe.html'}
            self.assertEqual({p.name for p in (root/'report').iterdir()},expected)
            before=(root/'report/informe.html').read_bytes()
            repeat=subprocess.run(args,capture_output=True,text=True);self.assertNotEqual(repeat.returncode,0)
            self.assertEqual((root/'report/informe.html').read_bytes(),before)
            self.assertFalse(any(p.name.startswith('.') for p in root.iterdir()))


if __name__=='__main__':unittest.main(verbosity=2)
