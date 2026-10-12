"""Explicit operating inputs, matching losses/curves and blocked foam predictions."""
import copy,json,subprocess,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
BASE=Path(__file__).resolve().parents[1];sys.path.insert(0,str(BASE))
from tactics.hydraulics import analyze_profile,digest,read_profile
from tactics.flow_context import evaluate_flow_profile,validate_context
from tactics.presentation import render_hydraulic_answer


class FlowContextTests(unittest.TestCase):
    def setUp(self):
        self.profile=read_profile(BASE/'tests/data/hydraulic_profile_synthetic.json')
        self.profile['hose'].update(inside_diameter_mm=45,curve_inside_diameter_mm=45)
        self.context={'schema_version':'0.1','profile_sha256':digest(self.profile),'source_id':'DEMO',
            'sources':[{'source_id':'DEMO','title':'Declaraciones ficticias de entrenamiento','locator':'Synthetic context fixture'}],
            'agent':'water','pump_stage':'low','pump_curve_stage':'low','pump_speed_rpm':2800,'pump_curve_speed_rpm':2800,
            'pump_outlet_id':'LP_01','declared_pump_outlet_pressure_bar':9,'target_nozzle_pressure_bar':5,
            'hose_type':'textil ficticia','component_limits_bar':dict(pump=16,hose=16,nozzle=16,accessories=16),
            'connected_elements':[
                {'id':'valve','type':'válvula','configuration':'En serie','source_id':'DEMO','max_working_pressure_bar':16,
                 'curve':[{'flow_l_min':100,'pressure_bar':.06},{'flow_l_min':500,'pressure_bar':.3}]},
                {'id':'connector','type':'racor','configuration':'En serie','source_id':'DEMO','max_working_pressure_bar':16,
                 'curve':[{'flow_l_min':100,'pressure_bar':.04},{'flow_l_min':500,'pressure_bar':.2}]}]}
        network=patch('socket.getaddrinfo',side_effect=AssertionError('Unexpected network'));network.start();self.addCleanup(network.stop)

    def test_water_results_unchanged_and_all_requested_context_present(self):
        baseline=analyze_profile(self.profile);result=evaluate_flow_profile(self.profile,self.context)
        for k,v in baseline.items():self.assertEqual(result[k],v)
        c=result['installation_context'];self.assertEqual(c['missing_fields'],[])
        self.assertEqual(c['assessment'],'declared_metadata_and_pressure_checks_available')
        self.assertEqual(c['target_nozzle_pressure_bar'],5)
        self.assertEqual(c['available_pump_pressure_at_target_bar'],9)
        self.assertAlmostEqual(c['predicted_pump_pressure_at_operating_point_bar'],8.55555555555)
        text=render_hydraulic_answer(result)
        for wording in ('etapa de bomba: baja','salida: LP_01','tipo textil ficticia','régimen 2800 rpm',
                        'Curva resistente total','Elemento valve','Límites por componente'):
            self.assertIn(wording,text)
        self.assertLess(text.index('diámetro interior 45 mm'),text.index('5 bar'))
        self.assertFalse(c['whole_installation_safety_assessed'])

    def test_legacy_inputs_keep_predictions_and_expose_missing_data(self):
        self.profile['hose'].pop('inside_diameter_mm');self.profile['hose'].pop('curve_inside_diameter_mm')
        result=evaluate_flow_profile(self.profile);c=result['installation_context']
        self.assertEqual(c['assessment'],'incomplete_installation_metadata')
        for field in ('pump_stage','target_nozzle_pressure_bar','hose_type','connected_elements','hose.inside_diameter_mm'):
            self.assertIn(field,c['missing_fields'])
        before=copy.deepcopy(result)
        text=render_hydraulic_answer(result)
        self.assertIn('no aportado',text)
        self.assertLess(text.index('Datos pendientes:'),text.index('Aunque faltan datos'))
        self.assertLess(text.index('Aunque faltan datos'),text.index('444.444 L/min'))
        self.assertIn('no acredita la seguridad estructural',text)
        self.assertIn('8.556 bar',text)
        self.assertIn('3.600 min',text)
        self.assertEqual(result,before)
        self.assertIn('444,444 L/min',render_hydraulic_answer(result,number_format='es'))

    def test_curve_explanation_does_not_claim_missing_or_unsupported_results(self):
        complete=evaluate_flow_profile(self.profile,self.context)
        self.assertNotIn('Aunque faltan datos',render_hydraulic_answer(complete))
        legacy=analyze_profile(self.profile)
        from tactics.hydraulics import render_result
        self.assertEqual(render_hydraulic_answer(legacy),render_result(legacy))
        for point in self.profile['pump']['curve']:point['pressure_bar']+=100
        outside=evaluate_flow_profile(self.profile)
        self.assertIsNone(outside['operating_point'])
        self.assertNotIn('Aunque faltan datos',render_hydraulic_answer(outside))
        for agent in ('foam_solution','CAFS'):
            declared=self.foam_context(agent)
            declared['profile_sha256']=digest(self.profile)
            foam=evaluate_flow_profile(self.profile,declared)
            self.assertNotIn('Aunque faltan datos',render_hydraulic_answer(foam))

    def test_context_is_bound_to_profile_and_source(self):
        for change in (lambda c:c.update(profile_sha256='0'*64),lambda c:c.update(source_id='missing'),
                       lambda c:c['connected_elements'][0].update(source_id='missing')):
            context=copy.deepcopy(self.context);change(context)
            with self.assertRaises(ValueError):validate_context(self.profile,context)

    def test_stage_and_rpm_cannot_be_combined_with_wrong_curve(self):
        for key,value in [('pump_stage','high'),('pump_speed_rpm',3000)]:
            context=copy.deepcopy(self.context);context[key]=value
            with self.assertRaises(ValueError):evaluate_flow_profile(self.profile,context)

    def test_target_pressure_is_separate_and_mismatch_does_not_rewrite_curve(self):
        self.context['target_nozzle_pressure_bar']=6
        result=evaluate_flow_profile(self.profile,self.context)
        self.assertEqual(result['target_balance']['nozzle_pressure_bar'],5)
        self.assertEqual(result['installation_context']['assessment'],'target_pressure_incompatible_with_nozzle_curve')
        self.assertIn('no coincide',render_hydraulic_answer(result))

    def test_component_limit_is_checked_even_when_global_limit_passes(self):
        self.context['connected_elements'][0]['max_working_pressure_bar']=6
        result=evaluate_flow_profile(self.profile,self.context)
        self.assertTrue(result['target_balance']['line_pressure_within_declared_limit'])
        self.assertEqual(result['installation_context']['assessment'],'component_limits_need_local_pressure_evaluation')
        check=next(c for c in result['installation_context']['component_limit_checks'] if c['component']=='valve')
        self.assertFalse(check['within_limit_at_target'])
        self.assertFalse(check['actual_local_pressure_assessed'])
        self.assertIn('No demuestra una superación local',render_hydraulic_answer(result))

    def test_element_loss_sum_must_match_aggregate_at_intermediate_knots(self):
        self.context['connected_elements'][0]['curve'].insert(1,{'flow_l_min':300,'pressure_bar':.25})
        # Endpoints still match the aggregate, but this knot does not.
        with self.assertRaisesRegex(ValueError,'no coinciden'):evaluate_flow_profile(self.profile,self.context)

    def test_explicit_empty_element_list_requires_zero_accessory_loss(self):
        self.context['connected_elements']=[]
        with self.assertRaisesRegex(ValueError,'no coinciden'):evaluate_flow_profile(self.profile,self.context)
        for p in self.profile['accessories']['curve']:p['pressure_bar']=0
        self.context['component_limits_bar'].pop('accessories')
        self.context['profile_sha256']=digest(self.profile)
        result=evaluate_flow_profile(self.profile,self.context)
        self.assertEqual(result['installation_context']['missing_fields'],[])
        self.assertEqual(result['target_balance']['accessory_loss_bar'],0)

    def test_pressure_domain_and_water_shortage_do_not_become_metadata_success(self):
        self.profile['objective']['flow_l_min']=600;self.context['profile_sha256']=digest(self.profile)
        result=evaluate_flow_profile(self.profile,self.context)
        self.assertEqual(result['installation_context']['assessment'],'curve_domain_does_not_support_complete_result')
        self.profile['objective']['flow_l_min']=400;self.profile['water_supply']['reserve_l']=2000
        self.context['profile_sha256']=digest(self.profile)
        self.assertEqual(evaluate_flow_profile(self.profile,self.context)['installation_context']['assessment'],'no_usable_water')

    def foam_context(self,agent='foam_solution'):
        context=copy.deepcopy(self.context);context['agent']=agent;context['target_flow_medium']='foam_solution'
        context['foam_system']={'system_type':'CAFS' if agent=='CAFS' else 'inline_inductor',
            'system_model':'Demo','concentrate_model':'Ficticio','concentration_percent_of_solution':3,
            'solution_flow_l_min':400,'water_flow_l_min':388,'concentrate_flow_l_min':12,
            'flow_range_l_min':[400,400],'compatibility_reference':'https://example.test/manual/v1.2'}
        return context

    def test_foam_and_cafs_never_call_water_analysis_or_report_water_autonomy(self):
        for agent in ('foam_solution','CAFS'):
            with patch('tactics.flow_context.analyze_profile',side_effect=AssertionError('Water model used for foam')):
                result=evaluate_flow_profile(self.profile,self.foam_context(agent))
            self.assertEqual(result['target_status'],'unsupported_foam_hydraulics')
            for key in ('target_balance','operating_point','water_at_predicted_operating_point'):self.assertIsNone(result[key])
            self.assertIsNone(result['installation_context']['resistant_curve'])
            text=render_hydraulic_answer(result,number_format='es')
            self.assertIn('No se calcula caudal',text)
            self.assertIn('https://example.test/manual/v1.2',text)
            if agent=='CAFS':self.assertIn('foam_system.air_flow_l_min',result['installation_context']['missing_fields'])

    def test_incoherent_foam_rates_and_invalid_numbers_are_rejected(self):
        mutations=[lambda c:c['foam_system'].update(concentrate_flow_l_min=15),
            lambda c:c['foam_system'].update(concentration_percent_of_solution=6),
            lambda c:c['foam_system'].update(flow_range_l_min=[500,100]),
            lambda c:c['foam_system'].update(concentrate_tank_l=5,concentrate_reserve_l=6),
            lambda c:c['foam_system'].update(concentration_percent_of_solution=float('nan')),
            lambda c:c.update(pump_speed_rpm=10**400),
            lambda c:c.update(agent='water')]
        for mutate in mutations:
            c=self.foam_context();mutate(c)
            with self.assertRaises(ValueError):evaluate_flow_profile(self.profile,c)

    def test_cli_uses_declared_context_and_keeps_foam_block_explicit(self):
        with tempfile.TemporaryDirectory() as d:
            folder=Path(d);profile=folder/'profile.json';context=folder/'context.json';output=folder/'answer.json'
            profile.write_text(json.dumps(self.profile),encoding='utf-8');context.write_text(json.dumps(self.foam_context()),encoding='utf-8')
            args=[sys.executable,str(BASE/'hydraulics.py'),'--profile',str(profile),'--installation-context',str(context),'--output',str(output)]
            result=subprocess.run(args,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(read_profile(output)['target_status'],'unsupported_foam_hydraulics')


if __name__=='__main__':unittest.main(verbosity=2)
