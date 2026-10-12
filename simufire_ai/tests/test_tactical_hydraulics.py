"""Independent analytical balances, domain guards, provenance and CLI behavior."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BASE_DIR=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(BASE_DIR))
from tactics.hydraulics import analyze_profile, pressure, read_profile, render_result


class HydraulicTests(unittest.TestCase):
    def setUp(self):
        self.profile=read_profile(BASE_DIR/'tests/data/hydraulic_profile_synthetic.json')
        network=patch('urllib.request.urlopen',side_effect=AssertionError('Unexpected network'))
        network.start();self.addCleanup(network.stop)

    def test_analytical_flat_line_and_pump_intersection(self):
        # Independently: pump P=13-.01Q; line P=1+.017Q.
        original=copy.deepcopy(self.profile)
        result=analyze_profile(self.profile)
        b=result['target_balance']
        self.assertEqual(result['target_status'],'sufficient_head_at_target')
        self.assertAlmostEqual(b['required_pump_pressure_bar'],7.8)
        self.assertAlmostEqual(b['available_pump_pressure_bar'],9)
        self.assertAlmostEqual(b['pressure_margin_bar'],1.2)
        point=result['operating_point']
        self.assertAlmostEqual(point['flow_l_min'],12/.027,places=7)
        self.assertAlmostEqual(point['available_pump_pressure_bar'],13-.01*(12/.027))
        self.assertAlmostEqual(result['water_at_predicted_operating_point']['minutes_to_reserve'],3.6)
        self.assertEqual(self.profile,original)
        self.assertEqual(result['tactical_sufficiency'],'not_evaluated')
        self.assertEqual(result['data_kind'],'synthetic')

    def test_ascent_changes_capacity_and_pressure_balance(self):
        self.profile['installation']['elevation_m']=20
        result=analyze_profile(self.profile)
        self.assertEqual(result['target_status'],'insufficient_head_at_target')
        self.assertAlmostEqual(result['target_balance']['elevation_pressure_bar'],1.96133)
        self.assertAlmostEqual(result['target_balance']['required_pump_pressure_bar'],9.76133)
        self.assertAlmostEqual(result['operating_point']['flow_l_min'],(12-1.96133)/.027)

    def test_longer_hose_reduces_operating_flow(self):
        self.profile['installation']['hose_length_m']=100
        result=analyze_profile(self.profile)
        self.assertEqual(result['target_status'],'insufficient_head_at_target')
        # At 400 L/min: nozzle 5 bar + (100/20)*.8 hose + .4 accessories.
        self.assertAlmostEqual(result['target_balance']['hose_loss_bar'],4)
        self.assertAlmostEqual(result['target_balance']['required_pump_pressure_bar'],9.4)
        self.assertAlmostEqual(result['operating_point']['flow_l_min'],12/.031)

    def test_constant_inflow_credits_only_net_consumption(self):
        self.profile['water_supply']['inflow_l_min']=400
        water=analyze_profile(self.profile)['water_at_predicted_operating_point']
        self.assertAlmostEqual(water['net_draw_l_min'],12/.027-400)
        self.assertAlmostEqual(water['minutes_to_reserve'],36)

    def test_non_depleting_balance_is_not_unlimited_equipment_autonomy(self):
        self.profile['water_supply']['inflow_l_min']=500
        result=analyze_profile(self.profile)
        self.assertIsNone(result['water_at_predicted_operating_point']['minutes_to_reserve'])
        self.assertIn('no acredita autonomía ilimitada',render_result(result))
        json.dumps(result,allow_nan=False)

    def test_no_usable_water_does_not_invent_endurance(self):
        self.profile['water_supply']['reserve_l']=2000
        result=analyze_profile(self.profile)
        self.assertEqual(result['water_at_predicted_operating_point']['status'],'no_usable_water')
        self.assertEqual(result['water_at_predicted_operating_point']['minutes_to_reserve'],0)
        self.assertIn('No hay agua utilizable',render_result(result))

    def test_curve_domain_excludes_extrapolated_flow_and_autonomy(self):
        self.profile['nozzle']['curve'][-1]={'flow_l_min':300,'pressure_bar':4}
        result=analyze_profile(self.profile)
        self.assertEqual(result['target_status'],'target_outside_curve_domain')
        self.assertEqual(result['operating_point_status'],'operating_point_above_curve_domain')
        self.assertIsNone(result['operating_point'])
        self.assertIsNone(result['water_at_predicted_operating_point'])
        self.assertIn('no se extrapola',render_result(result))

    def test_insufficient_pressure_below_validated_domain(self):
        self.profile['pump']['curve'][0]['pressure_bar']=.5
        self.profile['pump']['curve'][-1]['pressure_bar']=.1
        result=analyze_profile(self.profile)
        self.assertEqual(result['operating_point_status'],'operating_point_below_curve_domain')
        self.assertIsNone(result['operating_point'])
        self.assertIsNone(result['water_at_predicted_operating_point'])

    def test_exact_endpoint_operating_point_is_retained(self):
        self.profile['pump']['curve'][-1]['pressure_bar']=9.5
        self.assertAlmostEqual(analyze_profile(self.profile)['operating_point']['flow_l_min'],500)

    def test_equal_pressure_roundoff_and_real_deficit_are_distinct(self):
        for p in self.profile['pump']['curve']:p['pressure_bar']=7.8
        self.assertEqual(analyze_profile(self.profile)['target_status'],'sufficient_head_at_target')
        for p in self.profile['pump']['curve']:p['pressure_bar']=7.799
        self.assertEqual(analyze_profile(self.profile)['target_status'],'insufficient_head_at_target')

    def test_pressure_capacity_does_not_override_equipment_limit(self):
        self.profile['installation']['max_line_pressure_bar']=6
        result=analyze_profile(self.profile)
        self.assertEqual(result['target_status'],'sufficient_head_at_target')
        self.assertFalse(result['target_balance']['line_pressure_within_declared_limit'])
        self.assertFalse(result['operating_point']['line_pressure_within_declared_limit'])
        self.assertIn('esta configuración requiere revisión',render_result(result))

    def test_unknown_equipment_limit_remains_unassessed(self):
        self.profile['installation']['max_line_pressure_bar']=None
        result=analyze_profile(self.profile)
        self.assertIsNone(result['target_balance']['line_pressure_within_declared_limit'])
        self.assertIn('ese control queda sin evaluar',render_result(result))

    def test_downhill_pressure_and_gravity_excess_are_not_negative_pump_settings(self):
        self.profile['installation']['elevation_m']=-10
        result=analyze_profile(self.profile)
        self.assertAlmostEqual(result['target_balance']['required_pump_pressure_bar'],7.8-.980665)
        self.assertAlmostEqual(result['target_balance']['conservative_line_pressure_bar'],9+.980665)
        self.profile['installation']['elevation_m']=-100
        result=analyze_profile(self.profile)
        self.assertEqual(result['target_status'],'gravity_exceeds_target_requirement')
        self.assertIn('no se propone ese ajuste',render_result(result))

    def test_interpolation_supports_actual_knots_without_extrapolation(self):
        curve=[{'flow_l_min':100,'pressure_bar':1},{'flow_l_min':200,'pressure_bar':2},
               {'flow_l_min':500,'pressure_bar':8}]
        self.assertEqual(pressure(curve,200),2)
        self.assertEqual(pressure(curve,350),5)
        for q in (99,501):
            with self.assertRaises(ValueError):pressure(curve,q)

    def test_missing_duplicate_nonfinite_and_unsupported_inputs_fail_closed(self):
        invalid=[]
        p=copy.deepcopy(self.profile);del p['pump'];invalid.append(p)
        p=copy.deepcopy(self.profile);p['installation']['topology']='branched';invalid.append(p)
        p=copy.deepcopy(self.profile);p['pump']['source_id']='invented';invalid.append(p)
        p=copy.deepcopy(self.profile);p['sources'].append(p['sources'][0]);invalid.append(p)
        p=copy.deepcopy(self.profile);p['water_supply']['reserve_l']=2001;invalid.append(p)
        p=copy.deepcopy(self.profile);p['nozzle']['curve'][1]['flow_l_min']=100;invalid.append(p)
        p=copy.deepcopy(self.profile);p['nozzle']['curve'][1]['pressure_bar']=1;invalid.append(p)
        p=copy.deepcopy(self.profile);p['pump']['curve'][1]['pressure_bar']=13;invalid.append(p)
        p=copy.deepcopy(self.profile);p['objective']['flow_l_min']=True;invalid.append(p)
        p=copy.deepcopy(self.profile);p['installation']['elevation_m']=float('nan');invalid.append(p)
        p=copy.deepcopy(self.profile);p['pump']['curve'][0]['pressure_bar']=float('inf');invalid.append(p)
        p=copy.deepcopy(self.profile);p['objective']['flow_l_min']=10**400;invalid.append(p)
        p=copy.deepcopy(self.profile);p['installation']['hose_length_m']=1e308;p['hose']['reference_length_m']=1e-308;invalid.append(p)
        p=copy.deepcopy(self.profile);p['nozzle']['curve']=[{'flow_l_min':600,'pressure_bar':2},{'flow_l_min':700,'pressure_bar':3}];invalid.append(p)
        for p in invalid:
            with self.subTest(profile=p):
                with self.assertRaises(ValueError):analyze_profile(p)

    def test_input_and_method_fingerprints_bind_every_result(self):
        first=analyze_profile(self.profile)
        self.assertEqual(first,analyze_profile(self.profile))
        self.profile['objective']['flow_l_min']=300
        self.assertNotEqual(first['input_sha256'],analyze_profile(self.profile)['input_sha256'])
        self.assertEqual(first['method_sha256'],analyze_profile(self.profile)['method_sha256'])
        self.assertEqual(first['equipment_sources'],self.profile['sources'])
        self.profile['sources'][0]['title']='Changed after calculation'
        self.assertNotEqual(first['equipment_sources'],self.profile['sources'])

    def test_cli_reproducible_report_rejects_overwrite_and_duplicate_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp);output=folder/'answer.json'
            cmd=[sys.executable,str(BASE_DIR/'hydraulics.py'),'--profile',str(BASE_DIR/'tests/data/hydraulic_profile_synthetic.json'),'--output',str(output)]
            result=subprocess.run(cmd,capture_output=True,text=True,encoding='utf-8')
            self.assertEqual(result.returncode,0,result.stderr)
            report=read_profile(output);old=output.read_bytes()
            self.assertIn('400 L/min',report['answer'])
            self.assertEqual(report['tactical_sufficiency'],'not_evaluated')
            self.assertNotEqual(subprocess.run(cmd,capture_output=True).returncode,0)
            self.assertEqual(old,output.read_bytes())
            bad=folder/'bad.json';bad.write_text('{"schema_version":"0.1","schema_version":"0.2"}',encoding='utf-8')
            missing=folder/'must_not_exist.json'
            cmd[cmd.index('--profile')+1]=str(bad);cmd[cmd.index('--output')+1]=str(missing)
            self.assertNotEqual(subprocess.run(cmd,capture_output=True).returncode,0)
            self.assertFalse(missing.exists())

    def test_diameter_length_and_flow_precede_pressure_and_loss(self):
        self.profile['hose']['inside_diameter_mm']=45
        self.profile['hose']['curve_inside_diameter_mm']=45
        self.profile['installation']['hose_length_m']=100
        result=analyze_profile(self.profile);text=render_result(result)
        self.assertLess(text.index('diámetro interior declarado 45 mm'),text.index('9.000 bar'))
        self.assertLess(text.index('longitud 100 m'),text.index('9.000 bar'))
        self.assertLess(text.index('400 L/min'),text.index('9.000 bar'))
        self.assertIn('manguera 4.000',text)
        self.assertIn('caudal 387.097 L/min; pérdida de manguera 3.871 bar',text)
        self.assertEqual(result['hose_context']['source_id'],self.profile['hose']['source_id'])
        self.assertAlmostEqual(result['operating_point']['hose_loss_bar'],(12/.031)*.002*100/20)

    def test_legacy_diameter_is_unknown_and_never_inferred(self):
        result=analyze_profile(self.profile)
        self.assertIsNone(result['hose_context']['inside_diameter_mm'])
        self.assertEqual(result['hose_context']['diameter_status'],'not_provided')
        self.assertIn('diámetro interior no aportado, longitud 60 m',render_result(result))
        self.assertIn('No se transfiere a otro diámetro',render_result(result))
        legacy=copy.deepcopy(result);del legacy['hose_context']
        self.assertIn('diámetro interior y longitud no incluidos',render_result(legacy))

    def test_diameter_is_provenance_not_an_invented_loss_scaling_law(self):
        original=analyze_profile(self.profile)
        self.profile['hose']['inside_diameter_mm']=70
        self.profile['hose']['curve_inside_diameter_mm']=70
        declared=analyze_profile(self.profile)
        self.assertNotEqual(original['input_sha256'],declared['input_sha256'])
        for key in ('target_balance','operating_point','water_at_predicted_operating_point'):
            self.assertEqual(original[key],declared[key])
        self.assertTrue(declared['hose_context']['other_diameters_require_their_own_curves'])
        self.profile['hose']['curve']=[{'flow_l_min':100,'pressure_bar':.1},{'flow_l_min':500,'pressure_bar':.5}]
        lower_loss=analyze_profile(self.profile)
        self.assertLess(lower_loss['target_balance']['hose_loss_bar'],declared['target_balance']['hose_loss_bar'])
        self.assertGreater(lower_loss['operating_point']['flow_l_min'],declared['operating_point']['flow_l_min'])

    def test_invalid_diameter_rejected(self):
        self.profile['hose']['curve_inside_diameter_mm']=45
        for diameter in (0,-1,None,True,'45',float('nan'),float('inf'),10**400):
            self.profile['hose']['inside_diameter_mm']=diameter
            with self.subTest(diameter=diameter),self.assertRaises(ValueError):analyze_profile(self.profile)

    def test_changing_hose_diameter_requires_matching_curve_conditions(self):
        self.profile['hose'].update(inside_diameter_mm=45,curve_inside_diameter_mm=45)
        analyze_profile(self.profile)
        self.profile['hose']['inside_diameter_mm']=70
        with self.assertRaisesRegex(ValueError,'no corresponde'):analyze_profile(self.profile)
        del self.profile['hose']['curve_inside_diameter_mm']
        with self.assertRaises(ValueError):analyze_profile(self.profile)
        self.profile['hose'].update(curve_inside_diameter_mm=70)
        del self.profile['hose']['inside_diameter_mm']
        with self.assertRaises(ValueError):analyze_profile(self.profile)


if __name__=='__main__':unittest.main(verbosity=2)
