"""Primary provenance, variant separation and refusal of incomplete calculations."""
import copy
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(BASE))
from tactics.catalogue import CATALOG_PATH, hydraulic_data_gaps, load_catalog, lookup, to_hydraulic_component, validate_catalog


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.network = patch('socket.getaddrinfo',side_effect=AssertionError('Unexpected network'))
        self.network.start(); self.addCleanup(self.network.stop)
        self.catalog = load_catalog()

    def test_four_equipment_categories_and_primary_sources(self):
        self.assertEqual({r['category'] for r in self.catalog['equipment']},{'pump','hose','nozzle','fan'})
        self.assertEqual(len(self.catalog['equipment']),7)
        for record in self.catalog['equipment']:
            self.assertFalse(record['usable_for_hydraulic_profile'])
            self.assertEqual(record['simulation_availability'],'not_declared')
        self.assertEqual(len(self.catalog['tactical_references']),3)
        self.assertTrue(all(not r['automatic_tactical_rule'] for r in self.catalog['tactical_references']))

    def test_pump_nominal_point_is_not_a_curve(self):
        pump = lookup('N25')['matches'][0]
        self.assertEqual(pump['curve_documents'],[])
        self.assertTrue(hydraulic_data_gaps(pump['equipment_id'])['reasons'])
        with self.assertRaisesRegex(ValueError,'no apto'): to_hydraulic_component(pump['equipment_id'])

    def test_nozzle_selector_values_are_separate_settings(self):
        nozzle = lookup('2400',category='nozzle')['matches'][0]
        facts = {f['name']:f for f in nozzle['facts']}
        self.assertEqual(facts['selectable_flows']['value'],[130,235,400])
        self.assertEqual(facts['reference_pressure']['value'],6)
        self.assertIn('NOT points',facts['selectable_flows']['conditions'])
        with self.assertRaises(ValueError): to_hydraulic_component(nozzle['equipment_id'])

    def test_graphs_keep_rpm_and_suction_conditions_separate(self):
        pump = lookup('Prima')['matches'][0]
        self.assertEqual([c['source_id'] for c in pump['curve_documents']],['godiva_lp','godiva_hp'])
        self.assertTrue(all(c['status']=='digitization_pending' for c in pump['curve_documents']))
        self.assertIn('100 mm',pump['curve_documents'][0]['conditions'])
        self.assertIn('HP only',pump['curve_documents'][1]['conditions'])
        with self.assertRaises(ValueError): to_hydraulic_component(pump['equipment_id'])

    def test_hose_burst_pressure_not_line_working_pressure(self):
        hose = lookup('Titan 45')['matches'][0]
        facts = {f['name']:f for f in hose['facts']}
        self.assertEqual(facts['working_pressure']['value'],16)
        self.assertEqual(facts['burst_pressure']['value'],60)
        self.assertIn('20 °C',facts['working_pressure']['conditions'])
        self.assertIn('assembly',facts['working_pressure']['conditions'])

    def test_fan_rating_definitions_and_source_conflicts_remain_visible(self):
        fan = lookup('MT236')['matches'][0]
        flow = {f['name']:f for f in fan['facts'] if 'flow' in f['name']}
        self.assertEqual(flow['free_air_flow']['value'],68300)
        self.assertEqual(flow['amca_240_flow']['value'],36280)
        masses = [f for f in fan['facts'] if f['name']=='mass']
        self.assertEqual({f['value'] for f in masses},{37.5,40.5})
        self.assertTrue(all(f['status']=='conflicting' for f in masses))
        self.assertTrue(hydraulic_data_gaps(fan['equipment_id'])['conflicts'])

    def test_spanish_queries_and_scope(self):
        self.assertEqual(len(lookup('bombas')['matches']),2)
        self.assertEqual(len(lookup('ventilación',category='tactical')['matches']),2)
        self.assertEqual(lookup('equipo inexistente')['status'],'missing_from_catalog')
        self.assertFalse(lookup('bomba')['simulation_equipment_available'])

    def test_query_results_are_detached_from_catalog(self):
        original = copy.deepcopy(self.catalog)
        result = lookup('bomba',catalog=self.catalog)
        result['matches'][0]['facts'][0]['value'] = 9999
        self.assertEqual(self.catalog,original)

    def test_invalid_provenance_variants_and_automatic_use_rejected(self):
        mutations = [
            lambda c:c['equipment'][0]['facts'][0].update(source_id='unknown'),
            lambda c:c['equipment'][0]['facts'][0].update(source_id='gh'),
            lambda c:c['equipment'][0].update(usable_for_hydraulic_profile=True),
            lambda c:c['equipment'][0].update(simulation_availability='available'),
            lambda c:c['tactical_references'][0].update(automatic_tactical_rule=True),
            lambda c:c['sources'][0].update(url='https://example.com/fake'),
            lambda c:c['sources'][0].update(accessed_on='invalid'),
            lambda c:c['equipment'][0]['facts'][0].update(value=float('nan')),
            lambda c:c['equipment'][0]['facts'][0].update(value=10**500),
            lambda c:c['equipment'][0]['facts'][0].update(value=True),
            lambda c:c['equipment'].append(copy.deepcopy(c['equipment'][0])),
            lambda c:c['equipment'][0]['facts'].append(copy.deepcopy(c['equipment'][0]['facts'][0])),
            lambda c:c['equipment'][-1]['facts'][-1].update(status='transcribed'),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(self.catalog); mutate(changed)
            with self.subTest(mutation=mutate),self.assertRaises(ValueError): validate_catalog(changed)

    def test_missing_component_is_not_inferred(self):
        with self.assertRaisesRegex(ValueError,'no encontrado'): hydraulic_data_gaps('unknown')
        for query in ('','!','a'*161):
            with self.assertRaises(ValueError): lookup(query)

    def test_cli_offline_and_exclusive_output(self):
        before = hashlib.sha256(CATALOG_PATH.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as d:
            output = Path(d)/'answer.json'
            command = [sys.executable,str(BASE/'equipment_catalog.py'),'--query','lanza','--output',str(output)]
            first = subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(first.returncode,0,first.stderr)
            result = json.loads(output.read_text(encoding='utf-8'))
            self.assertEqual(len(result['matches']),2)
            self.assertIsNone(result['online_candidates'])
            content = output.read_bytes()
            second = subprocess.run(command,capture_output=True,text=True)
            self.assertNotEqual(second.returncode,0)
            self.assertEqual(output.read_bytes(),content)
        self.assertEqual(hashlib.sha256(CATALOG_PATH.read_bytes()).hexdigest(),before)


if __name__=='__main__': unittest.main()
