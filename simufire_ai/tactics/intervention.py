"""Bounded teaching report joining observed states, hydraulics and references.

No new fire detector, suppression solver, survival model or operational command.
The observation cutoff is applied before the existing deterministic analysis.
"""
import copy
import hashlib
import math
from pathlib import Path

from pipeline import build_analysis, normalize_inputs, validate_identifier
from knowledge.retriever import load_entries
from llm.question_context import load_schema, validate_schema
from tactics.catalogue import load_catalog
from tactics.flow_context import evaluate_flow_profile
from tactics.hydraulics import digest, read_profile

BASE = Path(__file__).resolve().parents[1]
REFERENCES = Path(__file__).with_name('intervention_references.json')
REQUEST_SCHEMA = Path(__file__).with_name('intervention_request.schema.json')
RESOURCE_LABELS = {
    'door_control_possible': 'posibilidad de controlar la apertura',
    'line_water_ready': 'línea de agua operativa',
    'interior_team_ready': 'equipo interior preparado',
    'breathing_apparatus_ready': 'ERA preparado',
    'structural_assessment_ready': 'evaluación estructural disponible',
    'fuel_access_verified': 'acceso al combustible comprobado',
    'exterior_access_verified': 'posición exterior de aplicación comprobada',
    'water_reaches_fire_verified': 'alcance del agua al recinto comprobado',
    'suppression_coordinated': 'coordinación con la aplicación de agua',
    'exhaust_path_verified': 'salida y recorrido de gases comprobados',
    'wind_assessed': 'viento evaluado',
    'fan_available': 'ventilador disponible',
    'victim_location_known': 'localización de víctimas conocida',
}


def _finite(data):
    if isinstance(data, dict):
        for value in data.values(): _finite(value)
    elif isinstance(data, list):
        for value in data: _finite(value)
    elif isinstance(data, (int, float)) and not isinstance(data, bool):
        try: valid = math.isfinite(data)
        except OverflowError: valid = False
        if not valid: raise ValueError('Número no finito en la solicitud')


def _option(key, title, purpose, required, resources, source_ids):
    missing = [field for field in required if resources.get(field) is None]
    unfulfilled = [field for field in required if resources.get(field) is False]
    status = ('declared_prerequisites_not_met' if unfulfilled else
              'conditional_on_missing_data' if missing else 'declared_prerequisites_available')
    return {'id': key, 'title': title, 'purpose': purpose, 'required_fields': required,
            'missing_fields': missing, 'unfulfilled_fields': unfulfilled, 'status': status,
            'source_ids': source_ids, 'declarations_only': True, 'authorized_operation': False}


def build_intervention_report(fixture, profile, declared, request, *, catalog=None):
    """Bind the inputs and use only original measurements at/before decision time."""
    _finite(request); digest(request)
    validate_schema(request, read_profile(REQUEST_SCHEMA), 'Solicitud de intervención')
    validate_identifier(request['report_id'])
    if declared is not None and declared.get('agent','water')!='water':
        raise ValueError('El primer informe integrado está limitado a agua; espuma/CAFS requiere otro modelo')
    if set(fixture) != {'scenario', 'states'}: raise ValueError('Caso: se requieren escenario y estados')
    if request['hydraulic_profile_sha256'] != digest(profile): raise ValueError('Solicitud asociada a otro perfil hidráulico')
    thresholds = read_profile(BASE/'config/analyzer_thresholds.json')
    scenario, states, thresholds, entries = normalize_inputs(
        fixture['scenario'], fixture['states'], thresholds, load_entries())
    if request['scenario_id'] != scenario['scenario_id']: raise ValueError('Solicitud de otro escenario')
    room = next((r for r in scenario['compartments'] if r['id'] == request['compartment_id']), None)
    if room is None: raise ValueError('Habitación consultada inexistente')
    cutoff = request['decision_time_s']
    if cutoff > scenario['simulation']['duration_s']: raise ValueError('Instante fuera del escenario')
    if request['resources_recorded_at_s'] > cutoff: raise ValueError('Recursos declarados después del instante evaluado')
    recorded = [s for s in states if s['time_s'] <= cutoff]
    if not recorded: raise ValueError('Sin mediciones anteriores al instante evaluado')
    effective_scenario = copy.deepcopy(scenario)
    effective_scenario['actions'] = [a for a in scenario['actions'] if recorded[0]['time_s'] <= a['time_s'] <= recorded[-1]['time_s']]
    artifacts = build_analysis(effective_scenario, recorded, request['report_id'], thresholds=thresholds, entries=entries)
    context = artifacts['context.json']
    snapshots = []
    for state in recorded:
        r = next(r for r in state['compartments'] if r['id'] == room['id'])
        snapshots.append({'time_s': state['time_s'], 'hrr_kw': r['hrr_kw'],
            'interface_height_m': r['interface_height_m'],
            'upper_temperature_c': r['upper_layer']['temperature_c'], 'upper_o2_percent': r['upper_layer']['o2_percent'],
            'lower_temperature_c': r['lower_layer']['temperature_c'], 'lower_o2_percent': r['lower_layer']['o2_percent'],
            'lower_co_ppm': r['lower_layer']['co_percent'] * 10000,
            'lower_co2_percent': r['lower_layer']['co2_percent']})
    first, last = snapshots[0], snapshots[-1]
    changes = {key: last[key]-first[key] for key in ('hrr_kw','upper_temperature_c','upper_o2_percent','interface_height_m')}
    if first['hrr_kw'] > 0: changes['hrr_relative_change_percent'] = changes['hrr_kw']/first['hrr_kw']*100
    openings = {o['id']: o for o in scenario['openings']}
    hypothetical_openings = []
    refs = read_profile(REFERENCES)
    for oid in request['compare_full_opening_ids']:
        if oid not in openings: raise ValueError('Apertura hipotética inexistente')
        o = openings[oid]
        if {o['from'],o['to']} != {room['id'],'outside'}: raise ValueError('La referencia geométrica exige apertura directa al exterior del recinto')
        area = o['width_m']*o['height_m']
        hypothetical_openings.append({'opening_id': oid, 'width_m': o['width_m'], 'height_m': o['height_m'],
            'area_m2': area, 'reference_flow_l_min': area*refs['opening_reference_l_min_m2'],
            'assumptions': ['Hypothetical full opening; ventilation-limited fire; usual opening geometry.'],
            'source_id': 'GIE_FLOW', 'causal': False, 'predicted_fire_hrr_kw': None})
    hydraulic = evaluate_flow_profile(profile, declared)
    point = hydraulic.get('operating_point')
    reference_met = None
    if point is not None and hydraulic['installation_context']['agent'] == 'water':
        # Do not claim a strict flow boundary from roundoff in the root solver.
        reference_met = point['flow_l_min']-refs['flow_floor_l_min'] > 1e-6 and point['nozzle_pressure_bar'] <= refs['maximum_nozzle_pressure_bar']+1e-9
    resources = request['resources']
    common = ['line_water_ready','breathing_apparatus_ready','structural_assessment_ready']
    options = [
        _option('opening_control','Control de aperturas','Limitar entradas de aire y recorridos de gases mientras se prepara la intervención.',
                ['door_control_possible'],resources,['FSRI_COORD','NIST_PPV']),
        _option('direct','Aplicación al combustible','Enfriar superficies y mojar combustible; confirmar que el agua llega a su objetivo.',
                common+['interior_team_ready','fuel_access_verified'],resources,['FSRI_COORD']),
        _option('gas_cooling','Enfriamiento de gases','Reducir la carga térmica de los gases durante la progresión; revisar también el combustible.',
                common+['interior_team_ready'],resources,['FSRI_COORD']),
        _option('exterior','Aplicación exterior inicial','Valorar una posición que permita llevar agua al recinto y continuidad hacia la extinción.',
                ['line_water_ready','exterior_access_verified','water_reaches_fire_verified','structural_assessment_ready'],resources,['FSRI_COORD','NIST_JET']),
        _option('ventilation','Ventilación coordinada','Valorar extracción de gases junto al control con agua, considerando entrada, salida y ocupantes.',
                ['line_water_ready','suppression_coordinated','exhaust_path_verified','wind_assessed'],resources,['FSRI_COORD','NIST_PPV']),
        _option('ppv','Ventilación con ventilador','Revisar la ruta de gases y el aporte de aire; el caudal de catálogo no predice el caudal en el edificio.',
                ['line_water_ready','suppression_coordinated','exhaust_path_verified','wind_assessed','fan_available'],resources,['NIST_PPV']),
    ]
    for option in options:
        option['hydraulic_review_required'] = option['id']!='opening_control' and hydraulic['installation_context']['assessment']!='declared_metadata_and_pressure_checks_available'
        if option['hydraulic_review_required']:option['status']='hydraulic_review_required'
    catalog = load_catalog() if catalog is None else catalog
    from tactics.catalogue import validate_catalog
    validate_catalog(catalog)
    equipment_index = {e['equipment_id']:e for e in catalog['equipment']}
    equipment = []
    for eid in request['reference_equipment_ids']:
        if eid not in equipment_index: raise ValueError('Equipo de referencia inexistente')
        equipment.append(copy.deepcopy(equipment_index[eid]))
    referenced_sources = {f['source_id'] for e in equipment for f in e['facts']+e['curve_documents']}
    facts = [copy.deepcopy(f) for f in context['scenario_facts'] if f.get('compartment_id') == room['id']]
    local_openings = {o['id'] for o in scenario['openings'] if room['id'] in (o['from'],o['to'])}
    actions = [copy.deepcopy(a) for a in effective_scenario['actions'] if a['target'] in local_openings]
    return {'schema_version':'0.1','report_id':request['report_id'],'scenario_id':scenario['scenario_id'],
        'data_kind':request['data_kind'],'hydraulic_data_kind':profile['data_kind'],
        'decision_time_s':cutoff,'last_observation_time_s':last['time_s'],
        'future_observations_used':False,'automatic_tactical_decision':False,
        'room':copy.deepcopy(room),'observations':snapshots,'changes':changes,
        'observed_interval_s':[first['time_s'],last['time_s']],'recorded_actions':actions,'physical_facts':facts,
        'hydraulic':hydraulic,'declared_water_supply':copy.deepcopy(profile['water_supply']),'operational_reference':{
            'profile_id':refs['profile_id'],'source_id':'GIE_FLOW','service_adoption_verified':False,
            'expert_review':refs['expert_review'],'minimum_flow_l_min':refs['flow_floor_l_min'],'flow_operator':'>',
            'maximum_nozzle_pressure_bar':refs['maximum_nozzle_pressure_bar'],
            'numerical_flow_tolerance_l_min':1e-6,'numerical_pressure_tolerance_bar':1e-9,
            'predicted_point_meets_numeric_reference':reference_met,'fire_extinction_sufficiency_confirmed':False,
            'simplified_opening_references':hypothetical_openings},
        'resources':copy.deepcopy(resources),'resources_source':request['resources_source'],
        'resources_recorded_at_s':request['resources_recorded_at_s'],'options':options,
        'survivability':{'status':'not_estimated','survival_probability':None,'fed':None,
            'basis':'Zone averages are not individual breathing-zone exposures.',
            'missing_data':['Ubicación y trayectoria de las víctimas','Exposición desde antes de la primera muestra',
                            'Flujo térmico y exposición corporal','HCN y caracterización toxicológica completa'],
            'source_ids':['FSRI_RESCUE','FSRI_COORD']},
        'equipment_reference_only':equipment,'equipment_sources':[copy.deepcopy(s) for s in catalog['sources'] if s['source_id'] in referenced_sources],
        'equipment_inventory_verified':False,'sources':copy.deepcopy(refs['sources']),
        'provenance':{'fixture_sha256':digest(fixture),'request_sha256':digest(request),
            'effective_inputs_sha256':digest({'scenario':effective_scenario,'states':recorded}),
            'hydraulic_profile_sha256':digest(profile),'analysis_engine_sha256':artifacts['manifest.json']['engine_sha256'],
            'analysis_context_sha256':digest(context),'references_sha256':hashlib.sha256(REFERENCES.read_bytes()).hexdigest(),
            'equipment_catalog_sha256':digest(catalog),
            'report_method_sha256':digest({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in
                (Path(__file__),Path(__file__).with_name('intervention_presentation.py'),REQUEST_SCHEMA,REFERENCES)})}}
