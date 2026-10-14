"""Display never rescales units; standards never substitute model-specific pressure."""
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BASE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(BASE))
from tactics.catalogue import load_catalog
from tactics.hydraulics import analyze_profile, read_profile, render_result
from tactics.presentation import render_hydraulic_answer, resolve_number_format
from tactics.standards import load_registry, lookup_standards, nozzle_reference_pressure, validate_registry


class PresentationAndStandardsTests(unittest.TestCase):
    def setUp(self):
        self.network=patch('socket.getaddrinfo',side_effect=AssertionError('Unexpected internet'))
        self.network.start();self.addCleanup(self.network.stop)
        self.profile=read_profile(BASE/'tests/data/hydraulic_profile_synthetic.json')

    def test_accepted_h01_english_text_and_numeric_values_are_preserved(self):
        result=analyze_profile(self.profile);before=copy.deepcopy(result)
        text=render_hydraulic_answer(result)
        self.assertEqual(text,render_result(result))
        self.assertIn('9.000 bar disponibles frente a 7.800 bar requeridos',text)
        self.assertIn('444.444 L/min y 8.556 bar',text)
        self.assertIn('3.600 min',text)
        self.assertEqual(result,before)
        self.assertEqual(result['target_balance']['available_pump_pressure_bar'],9)

    def test_spanish_auto_changes_decimal_display_only(self):
        result=analyze_profile(self.profile);before=copy.deepcopy(result)
        text=render_hydraulic_answer(result,language='es-ES',number_format='auto')
        self.assertIn('9,000 bar disponibles frente a 7,800 bar requeridos',text)
        self.assertIn('444,444 L/min y 8,556 bar',text)
        self.assertIn('3,600 min',text)
        self.assertIn('1600 L',text)
        self.assertEqual(result,before)
        self.assertEqual(json.loads(json.dumps(result))['target_balance']['available_pump_pressure_bar'],9)

    def test_explicit_session_preference_overrides_language(self):
        result=analyze_profile(self.profile)
        self.assertEqual(render_hydraulic_answer(result,language='es',number_format='en'),render_result(result))
        self.assertEqual(resolve_number_format(language='en_US',number_format='auto'),'en')
        self.assertEqual(resolve_number_format(language='es_MX',number_format='auto'),'es')
        for style,language in [('de','es'),('auto','fr')]:
            with self.assertRaises(ValueError):resolve_number_format(language=language,number_format=style)

    def test_signs_and_fractional_targets_are_localized_without_thousands_scaling(self):
        self.profile['objective']['flow_l_min']=400.5
        for point in self.profile['pump']['curve']:point['pressure_bar']=9000
        result=analyze_profile(self.profile)
        text=render_hydraulic_answer(result,number_format='es')
        self.assertIn('400,5 L/min',text)
        self.assertIn('9000,000 bar disponibles',text)
        self.assertEqual(result['target_balance']['available_pump_pressure_bar'],9000)
        # Deliberately high input verifies that display does not divide by 1000.
        self.profile['installation']['elevation_m']=-10
        self.profile['pump']['curve'][0]['pressure_bar']=12
        self.profile['pump']['curve'][-1]['pressure_bar']=8
        text=render_hydraulic_answer(analyze_profile(self.profile),number_format='es')
        self.assertIn('desnivel -0,981 bar',text)

    def test_target_flow_and_predicted_flow_have_distinct_autonomy(self):
        result=analyze_profile(self.profile)
        usable=result['water_at_predicted_operating_point']['usable_tank_l']
        self.assertAlmostEqual(result['water_at_predicted_operating_point']['minutes_to_reserve'],3.6)
        self.assertAlmostEqual(usable/result['objective']['flow_l_min'],4)

    def test_current_nfpa_entries_keep_legacy_aliases_and_scope(self):
        self.assertEqual(lookup_standards('NFPA 1964')['matches'][0]['standard_id'],'NFPA_1960_2024')
        self.assertEqual(lookup_standards('NFPA 1962')['matches'][0]['edition'],'2025')
        self.assertEqual(lookup_standards('NFPA 1901')['matches'][0]['standard_id'],'NFPA_1900_2024')
        for entry in load_registry()['standards']:
            self.assertEqual(entry['normative_clauses_reviewed'],[])
            self.assertFalse(entry['equipment_compliance_assessed'])
            self.assertFalse(entry['automatic_tactical_rule'])
            self.assertEqual(entry['legal_applicability'],'not_assessed')

    def test_en_nozzle_scope_separates_reference_nominal_and_flow(self):
        entry=lookup_standards('15182 2 2020')['matches'][0]
        facts={f['name']:f for f in entry['scope_facts']}
        self.assertEqual(facts['reference_pressure']['value'],6)
        self.assertEqual(facts['nominal_pressure_class']['value'],16)
        self.assertEqual(facts['scope_maximum_flow']['value'],1000)
        self.assertIn('no presión universal',facts['reference_pressure']['scope'])
        self.assertEqual(len(lookup_standards('bomba')['matches']),3)

    def test_manufacturer_pressure_is_not_replaced_by_region_or_language(self):
        self.assertEqual(nozzle_reference_pressure('awg_turbo_2400_standard')['reference_pressure_bar'],6)
        catalog=load_catalog()
        # AWG M1003B10 section 3.4 also lists standard Turbo 2475 at 7/16 bar.
        nozzle=copy.deepcopy(next(e for e in catalog['equipment'] if e['equipment_id']=='awg_turbo_2400_standard'))
        nozzle.update(equipment_id='awg_turbo_2475_standard',model='Turbo 2475')
        for fact in nozzle['facts']:
            if fact['name']=='reference_pressure':fact.update(value=7,conditions='AWG Turbo 2475, manufacturer reference pressure')
            elif fact['name']=='selectable_flows':fact.update(value=[115,230,360,475],conditions='Distinct selectors at 7 bar')
            elif fact['name']=='spray_angle_range':fact.update(value=[0,160])
        catalog['equipment'].append(nozzle)
        result=nozzle_reference_pressure('awg_turbo_2475_standard',catalog=catalog)
        self.assertEqual(result['reference_pressure_bar'],7)
        self.assertFalse(result['curve_synthesized'])
        self.assertFalse(result['normative_compliance_assessed'])

    def test_missing_reference_pressure_is_not_filled_from_standard(self):
        catalog=load_catalog();nozzle=next(e for e in catalog['equipment'] if e['equipment_id']=='awg_turbo_2400_standard')
        fact=next(f for f in nozzle['facts'] if f['name']=='reference_pressure')
        for invalid in (0,-1):
            fact['value']=invalid
            with self.assertRaisesRegex(ValueError,'no positiva'):nozzle_reference_pressure(nozzle['equipment_id'],catalog=catalog)
        nozzle['facts']=[f for f in nozzle['facts'] if f['name']!='reference_pressure']
        with self.assertRaisesRegex(ValueError,'ausente'):nozzle_reference_pressure(nozzle['equipment_id'],catalog=catalog)

    def test_registry_rejects_unbacked_facts_and_compliance_promotion(self):
        original=load_registry()
        mutations=[lambda d:d['standards'][0].update(automatic_tactical_rule=True),
            lambda d:d['standards'][0].update(equipment_compliance_assessed=True),
            lambda d:d['standards'][0].update(normative_clauses_reviewed=['fake clause']),
            lambda d:d['standards'][0]['source_ids'].append('NFPA_1960'),
            lambda d:d['standards'][1]['scope_facts'][0].update(value=float('inf')),
            lambda d:d['standards'][1]['scope_facts'][0].update(source_id='NFPA_1900'),
            lambda d:d['standards'].append(copy.deepcopy(d['standards'][0]))]
        for mutate in mutations:
            changed=copy.deepcopy(original);mutate(changed)
            with self.subTest(mutation=mutate),self.assertRaises(ValueError):validate_registry(changed)

    def test_cli_formats_preserve_json_numbers_and_reject_unknown_format(self):
        with tempfile.TemporaryDirectory() as d:
            folder=Path(d)
            common=[sys.executable,str(BASE/'hydraulics.py'),'--profile',str(BASE/'tests/data/hydraulic_profile_synthetic.json')]
            reports=[]
            for style in ('en','es','auto'):
                path=folder/(style+'.json')
                proc=subprocess.run(common+['--output',str(path),'--number-format',style,'--language','es'],capture_output=True,text=True)
                self.assertEqual(proc.returncode,0,proc.stderr)
                report=read_profile(path);reports.append(report)
                self.assertIn('9.000 bar' if style=='en' else '9,000 bar',report['answer'])
                self.assertEqual(report['target_balance']['available_pump_pressure_bar'],9)
            numerics=[{k:v for k,v in report.items() if k not in ('answer','presentation')} for report in reports]
            self.assertEqual(numerics[0],numerics[1]);self.assertEqual(numerics[0],numerics[2])
            invalid=folder/'invalid.json'
            self.assertNotEqual(subprocess.run(common+['--output',str(invalid),'--number-format','bad'],capture_output=True).returncode,0)
            self.assertFalse(invalid.exists())

    def test_cli_standards_lookup_and_detached_results(self):
        original=load_registry();saved=copy.deepcopy(original)
        result=lookup_standards('NFPA',registry=original);result['matches'][0]['edition']='modified'
        self.assertEqual(original,saved)
        proc=subprocess.run([sys.executable,str(BASE/'equipment_catalog.py'),'--query','NFPA 1964','--category','standards'],capture_output=True,text=True,encoding='utf-8')
        self.assertEqual(proc.returncode,0,proc.stderr)
        self.assertEqual(json.loads(proc.stdout)['matches'][0]['standard_id'],'NFPA_1960_2024')


if __name__=='__main__':unittest.main(verbosity=2)
