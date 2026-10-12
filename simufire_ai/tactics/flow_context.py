"""Declared installation context, consistency checks and explicit foam blocking.

This supplements the single-line water model. It does not simulate pressure
regulation, branching, multiple hose types, proportioning or CAFS.
"""
import copy
import hashlib
import math
from pathlib import Path

from jsonschema import Draft202012Validator
from tactics.hydraulics import analyze_profile, balance, digest, pressure, read_profile, validate_profile

SCHEMA=Path(__file__).with_name('flow_context.schema.json')
FOAM_FIELDS=tuple(read_profile(SCHEMA)['properties']['foam_system']['properties'])
PICKUP_FIELDS=('concentrate_pickup_lift_m','pickup_hose_length_m','pickup_hose_inside_diameter_mm')
AIR_FIELDS=('air_flow_l_min','air_pressure_bar','air_to_solution_ratio')


def foam_requirements(foam,agent):
    # This classifies documentation gaps, not physical capabilities. Injection
    # systems can also draw concentrate by suction; do not declare N/A by type.
    pickup_required=foam.get('system_type')=='inline_inductor'
    required=[f for f in FOAM_FIELDS if (f not in AIR_FIELDS or agent=='CAFS')
              and (f not in PICKUP_FIELDS or pickup_required)]
    conditional=[] if pickup_required else list(PICKUP_FIELDS)
    return required,conditional

LABELS={'pump_stage':'etapa seleccionada de bomba','pump_curve_stage':'etapa a la que corresponde la curva',
 'pump_speed_rpm':'RPM seleccionadas','pump_curve_speed_rpm':'RPM de la curva','pump_outlet_id':'salida de bomba',
 'declared_pump_outlet_pressure_bar':'presión de salida declarada','target_nozzle_pressure_bar':'presión objetivo en la lanza',
 'hose_type':'tipo de manguera','connected_elements':'elementos conectados y sus curvas','hose.inside_diameter_mm':'diámetro interior de la manguera',
 'target_flow_medium':'medio al que corresponde el caudal objetivo',
 'system_model':'modelo del sistema de espuma','system_type':'tipo de dosificador',
 'concentrate_model':'modelo de espumógeno','concentrate_type':'tipo de espumógeno','fuel':'combustible',
 'water_quality':'calidad del agua','concentration_percent_of_solution':'dosificación (% del volumen de solución)',
 'solution_flow_l_min':'caudal de solución (L/min)','water_flow_l_min':'caudal de agua (L/min)','concentrate_flow_l_min':'caudal de espumógeno (L/min)',
 'nominal_flow_l_min':'caudal nominal del equipo (L/min)','max_working_pressure_bar':'presión máxima de trabajo del sistema (bar)',
 'flow_range_l_min':'rango de caudal (L/min)','inlet_pressure_bar':'presión de entrada del dosificador (bar)',
 'max_backpressure_bar':'contrapresión máxima (bar)','pressure_loss_curve':'curva de pérdidas del sistema',
 'concentrate_temperature_c':'temperatura de espumógeno (°C)','concentrate_viscosity_mpa_s':'viscosidad (mPa·s)',
 'concentrate_pickup_lift_m':'altura de aspiración del espumógeno (m)','pickup_hose_length_m':'longitud de tubo de aspiración (m)',
 'pickup_hose_inside_diameter_mm':'diámetro de tubo de aspiración (mm)','concentrate_tank_l':'depósito de espumógeno (L)',
 'concentrate_reserve_l':'reserva de espumógeno (L)','discharge_device':'lanza/generador de espuma',
 'aspiration_type':'aspiración de aire','expansion_ratio':'relación de expansión','drainage_time_min':'tiempo de drenaje (min)',
 'application_rate_l_min_m2':'tasa de aplicación (L/min/m²)','protected_area_m2':'superficie protegida (m²)',
 'application_duration_min':'duración de aplicación (min)','application_method':'método de aplicación',
 'compatibility_reference':'fuente de compatibilidad equipo/producto/combustible/agua',
 'certification_reference':'documentación de ensayo/certificación','environmental_constraints':'condiciones ambientales y de uso',
 'flush_procedure':'procedimiento de lavado','air_flow_l_min':'caudal de aire CAFS (L/min)',
 'air_pressure_bar':'presión de aire CAFS (bar)','air_to_solution_ratio':'relación aire/solución CAFS'}


def validate_context(profile,context):
    validate_profile(profile)
    digest(context)
    errors=list(Draft202012Validator(read_profile(SCHEMA)).iter_errors(context))
    if errors:raise ValueError('Contexto de instalación: '+errors[0].message)
    def finite(value):
        if isinstance(value,dict):
            for v in value.values():finite(v)
        elif isinstance(value,list):
            for v in value:finite(v)
        elif isinstance(value,(float,int)) and not isinstance(value,bool):
            try:ok=math.isfinite(value)
            except OverflowError:ok=False
            if not ok:raise ValueError('Número no finito en contexto')
    finite(context)
    if context['profile_sha256']!=digest(profile):raise ValueError('Contexto asociado a otro perfil hidráulico')
    sources=[s['source_id'] for s in context['sources']]
    if len(set(sources))!=len(sources) or context['source_id'] not in sources:raise ValueError('Fuente de contexto ausente o duplicada')
    if context.get('pump_stage')!=context.get('pump_curve_stage'):raise ValueError('Etapa seleccionada incompatible con curva de bomba')
    if context.get('pump_speed_rpm')!=context.get('pump_curve_speed_rpm'):raise ValueError('RPM seleccionadas incompatibles con curva de bomba')
    elements=context.get('connected_elements',[])
    ids=[e['id'] for e in elements]
    if len(set(ids))!=len(ids) or set(ids)&{profile[n]['id'] for n in ('pump','hose','nozzle')}:
        raise ValueError('Identificador de elemento repetido')
    for e in elements:
        if e['source_id'] not in sources:raise ValueError('Elemento sin fuente del contexto')
        for a,b in zip(e['curve'],e['curve'][1:]):
            if a['flow_l_min']>=b['flow_l_min'] or a['pressure_bar']>b['pressure_bar']:raise ValueError('Curva de elemento inválida')
    if 'connected_elements' in context:
        aggregate=profile['accessories']['curve'];lo=aggregate[0]['flow_l_min'];hi=aggregate[-1]['flow_l_min']
        if any(e['curve'][0]['flow_l_min']>lo or e['curve'][-1]['flow_l_min']<hi for e in elements):
            raise ValueError('Elementos sin cobertura de la curva agregada de accesorios')
        knots={lo,hi}|{p['flow_l_min'] for p in aggregate}
        knots|={p['flow_l_min'] for e in elements for p in e['curve'] if lo<=p['flow_l_min']<=hi}
        for flow in knots:
            if not math.isclose(sum(pressure(e['curve'],flow) for e in elements),pressure(aggregate,flow),abs_tol=1e-9,rel_tol=1e-12):
                raise ValueError('Pérdidas de elementos no coinciden con la curva agregada de accesorios')
    foam=context.get('foam_system',{})
    if context['agent']=='water' and context.get('target_flow_medium','water')!='water':raise ValueError('El modelo de agua exige caudal objetivo de agua')
    if context['agent']=='CAFS' and foam.get('system_type','CAFS')!='CAFS':raise ValueError('Agente CAFS incompatible con tipo de sistema')
    if context['agent']=='foam_solution' and foam.get('system_type')=='CAFS':raise ValueError('Seleccionar CAFS para un sistema de aire comprimido')
    if 'pressure_loss_curve' in foam:
        for a,b in zip(foam['pressure_loss_curve'],foam['pressure_loss_curve'][1:]):
            if a['flow_l_min']>=b['flow_l_min'] or a['pressure_bar']>b['pressure_bar']:raise ValueError('Curva de pérdidas de espuma inválida')
    if 'flow_range_l_min' in foam and foam['flow_range_l_min'][0]>foam['flow_range_l_min'][1]:raise ValueError('Rango de espuma sin orden')
    if foam.get('concentrate_reserve_l',0)>foam.get('concentrate_tank_l',float('inf')):raise ValueError('Reserva de espumógeno superior al depósito')
    if {'solution_flow_l_min','water_flow_l_min','concentrate_flow_l_min'}<=foam.keys():
        if not math.isclose(foam['solution_flow_l_min'],foam['water_flow_l_min']+foam['concentrate_flow_l_min'],abs_tol=1e-8,rel_tol=1e-10):
            raise ValueError('Caudales declarados de agua, espumógeno y solución incoherentes')
    if {'solution_flow_l_min','concentration_percent_of_solution','concentrate_flow_l_min'}<=foam.keys():
        if not math.isclose(foam['concentrate_flow_l_min'],foam['solution_flow_l_min']*foam['concentration_percent_of_solution']/100,abs_tol=1e-8,rel_tol=1e-10):
            raise ValueError('Porcentaje declarado no corresponde al caudal de espumógeno')
    return context


def make_context(profile,result,declared=None):
    data=copy.deepcopy(declared or {})
    flow=profile['objective']['flow_l_min'];b=result.get('target_balance');point=result.get('operating_point')
    base={'agent':data.get('agent','water'),'profile_sha256':digest(profile),
        'context_method_sha256':digest({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__),SCHEMA)}),
        'target_flow_medium':data.get('target_flow_medium','water' if data.get('agent','water')=='water' else None),
        'declarations':data,'declarations_sha256':digest(data) if data else None,
        'pump':copy.deepcopy(profile['pump']),'hose':copy.deepcopy(profile['hose']),
        'nozzle':copy.deepcopy(profile['nozzle']),'aggregate_accessories':copy.deepcopy(profile['accessories']),
        'installation':copy.deepcopy(profile['installation']),'target_flow_l_min':flow,
        'target_nozzle_pressure_bar':data.get('target_nozzle_pressure_bar'),
        'nozzle_pressure_from_curve_at_target_bar':b['nozzle_pressure_bar'] if b else None,
        'required_pump_pressure_at_target_bar':b['required_pump_pressure_bar'] if b else None,
        'available_pump_pressure_at_target_bar':b['available_pump_pressure_bar'] if b else None,
        'predicted_pump_pressure_at_operating_point_bar':point['available_pump_pressure_bar'] if point else None,
        'component_limit_checks':[],'target_pressure_matches_curve':None,'missing_fields':[],
        'whole_installation_safety_assessed':False,'pressure_regulation_simulated':False,
        'declared_sources':copy.deepcopy(data.get('sources',[])),
        'hydraulic_sources':copy.deepcopy(profile['sources'])}
    required=('pump_stage','pump_curve_stage','pump_speed_rpm','pump_curve_speed_rpm','pump_outlet_id',
              'declared_pump_outlet_pressure_bar','target_nozzle_pressure_bar','hose_type','connected_elements')
    base['missing_fields']=[n for n in required if n not in data]
    if 'inside_diameter_mm' not in profile['hose']:base['missing_fields'].append('hose.inside_diameter_mm')
    ratings=data.get('component_limits_bar',{})
    for name in ('pump','hose','nozzle','accessories'):
        if name=='accessories' and data.get('connected_elements')==[] and all(p['pressure_bar']==0 for p in profile['accessories']['curve']):continue
        if name not in ratings:base['missing_fields'].append('component_limits_bar.'+name)
        upper=b['conservative_line_pressure_bar'] if b else None
        at_point=point['conservative_line_pressure_bar'] if point else None
        base['component_limit_checks'].append({'component':name,'limit_bar':ratings.get(name),
            'basis':'conservative_line_bound_not_local_pressure','actual_local_pressure_assessed':False,
            'conservative_pressure_at_target_bar':upper,'conservative_pressure_at_point_bar':at_point,
            'within_limit_at_target':None if name not in ratings or upper is None else upper<=ratings[name]+1e-9,
            'within_limit_at_point':None if name not in ratings or at_point is None else at_point<=ratings[name]+1e-9})
    for item in data.get('connected_elements',[]):
        rating=item.get('max_working_pressure_bar')
        if rating is None:base['missing_fields'].append('connected_elements.'+item['id']+'.max_working_pressure_bar')
        base['component_limit_checks'].append({'component':item['id'],'limit_bar':rating,
            'basis':'conservative_line_bound_not_local_pressure','actual_local_pressure_assessed':False,
            'within_limit_at_target':None if b is None or rating is None else b['conservative_line_pressure_bar']<=rating+1e-9,
            'within_limit_at_point':None if point is None or rating is None else point['conservative_line_pressure_bar']<=rating+1e-9})
    if b is not None and 'target_nozzle_pressure_bar' in data:
        base['target_pressure_matches_curve']=math.isclose(b['nozzle_pressure_bar'],data['target_nozzle_pressure_bar'],rel_tol=1e-9,abs_tol=1e-9)
    if base['agent']!='water':
        foam=data.get('foam_system',{})
        mandatory,conditional=foam_requirements(foam,base['agent'])
        base['missing_fields']+=['foam_system.'+f for f in mandatory if f not in foam]
        base['conditional_fields']=['foam_system.'+f for f in conditional if f not in foam]
        base['foam_requirement_scope']={
            'pickup_geometry':'required_for_inline_inductor' if not conditional else 'depends_on_concentrate_feed',
            'manufacturer_configuration_verified':False}
        if base['target_flow_medium'] is None:base['missing_fields'].append('target_flow_medium')
        base['assessment']='foam_model_not_implemented'
        base['resistant_curve']=None
    else:
        low,high=validate_profile(profile)
        knots={low,high}|{p['flow_l_min'] for n in ('pump','nozzle','hose','accessories') for p in profile[n]['curve'] if low<=p['flow_l_min']<=high}
        base['resistant_curve']=[{'flow_l_min':q,'required_pressure_bar':balance(profile,q)['required_pump_pressure_bar']} for q in sorted(knots)]
        if base['target_pressure_matches_curve'] is False:base['assessment']='target_pressure_incompatible_with_nozzle_curve'
        elif any(c['within_limit_at_target'] is False or c['within_limit_at_point'] is False for c in base['component_limit_checks']):base['assessment']='component_limits_need_local_pressure_evaluation'
        elif b is None or point is None:base['assessment']='curve_domain_does_not_support_complete_result'
        elif result['target_status']=='insufficient_head_at_target':base['assessment']='insufficient_head_at_target'
        elif result['water_at_predicted_operating_point']['status']=='no_usable_water':base['assessment']='no_usable_water'
        elif base['missing_fields']:base['assessment']='incomplete_installation_metadata'
        else:base['assessment']='declared_metadata_and_pressure_checks_available'
    return base


def evaluate_flow_profile(profile,declared=None):
    if declared is not None:validate_context(profile,declared)
    if declared is not None and declared['agent']!='water':
        # No water balance, operating point or water-tank autonomy for foam/CAFS.
        result={'profile_id':profile['profile_id'],'data_kind':profile['data_kind'],'input_sha256':digest(profile),
            'objective':copy.deepcopy(profile['objective']),'target_balance':None,'operating_point':None,
            'water_at_predicted_operating_point':None,'target_status':'unsupported_foam_hydraulics',
            'tactical_sufficiency':'not_evaluated'}
        result['installation_context']=make_context(profile,result,declared)
        return result
    result=analyze_profile(profile)
    result['installation_context']=make_context(profile,result,declared)
    return result


def render_installation_context(context,number_format='en'):
    data=context['declarations'];p=context['pump'];h=context['hose'];n=context['nozzle'];a=context['aggregate_accessories'];i=context['installation']
    def fmt(v,spec='g'):
        text=format(v,spec)
        return text.replace('.',',') if number_format=='es' else text
    def number(v,unit):return 'no aportado' if v is None else fmt(v)+' '+unit
    def curve(points):return '; '.join(fmt(x['flow_l_min'])+' L/min → '+fmt(x['pressure_bar'],'.3f')+' bar' for x in points)
    def stage(value):return {'low':'baja','high':'alta'}.get(value,'no aportada')
    def missing_label(key):
        if key.startswith('component_limits_bar.'):return 'límite de '+{'pump':'bomba','hose':'manguera','nozzle':'lanza','accessories':'accesorios'}[key.split('.')[-1]]
        if key.startswith('connected_elements.'):return 'límite de '+key.split('.')[1]
        return LABELS.get(key.removeprefix('foam_system.'),key)
    assessments={'foam_model_not_implemented':'requiere un modelo específico de espuma/CAFS',
        'target_pressure_incompatible_with_nozzle_curve':'presión objetivo incompatible con la curva de lanza',
        'component_limits_need_local_pressure_evaluation':'algún límite requiere comprobar la presión local del componente',
        'incomplete_installation_metadata':'faltan datos de la instalación',
        'declared_metadata_and_pressure_checks_available':'datos declarados disponibles para estas comprobaciones',
        'curve_domain_does_not_support_complete_result':'las curvas no permiten completar este cálculo',
        'insufficient_head_at_target':'presión insuficiente para el objetivo','no_usable_water':'sin agua utilizable por encima de la reserva'}
    medium={'water':'agua','foam_solution':'solución espumante','finished_foam':'espuma expandida','air':'aire'}.get(context['target_flow_medium'],'medio no aportado')
    lines=[f'Objetivo: {fmt(context["target_flow_l_min"])} L/min de {medium}; etapa de bomba: {stage(data.get("pump_stage"))}; salida: {data.get("pump_outlet_id","no aportada")}.',
        f'Manguera: diámetro interior {number(h.get("inside_diameter_mm"),"mm")}; tipo {data.get("hose_type","no aportado")}; longitud {fmt(i["hose_length_m"])} m; desnivel {fmt(i["elevation_m"],"+g")} m.',
        f'Presión objetivo en entrada de lanza: {number(context["target_nozzle_pressure_bar"],"bar")}. Presión de salida de bomba declarada: {number(data.get("declared_pump_outlet_pressure_bar"),"bar")}; no se simula regulación de presión.',
        f'Curva de bomba {p["id"]}: {p["configuration"]}; etapa de curva {stage(data.get("pump_curve_stage"))}; régimen {number(data.get("pump_curve_speed_rpm"),"rpm")}; '+curve(p['curve'])+'.',
        f'Elementos de la línea: bomba {p["id"]}, manguera {h["id"]}, lanza {n["id"]} y accesorios '+a['configuration']+'.',
        f'Curva de lanza ({n["configuration"]}): '+curve(n['curve'])+'.',
        f'Pérdidas de manguera para el diámetro/tipo indicado, por {fmt(h["reference_length_m"])} m: '+curve(h['curve'])+'.',
        'Curva agregada de accesorios: '+curve(a['curve'])+'.']
    for element in data.get('connected_elements',[]):
        lines.append('Elemento '+element['id']+' ('+element['type']+', '+element['configuration']+'): '+curve(element['curve'])+'; límite '+number(element.get('max_working_pressure_bar'),'bar')+'.')
    if 'connected_elements' not in data:lines.append('Desglose individual de accesorios: no aportado; solo hay una curva agregada.')
    if context['resistant_curve'] is not None:
        lines.append('Curva resistente total (lanza, manguera, accesorios y desnivel): '+
            '; '.join(fmt(p['flow_l_min'])+' L/min → '+fmt(p['required_pressure_bar'],'.3f')+' bar' for p in context['resistant_curve'])+'.')
    lines.append('Límite global declarado: '+number(i['max_line_pressure_bar'],'bar')+'. Límites por componente: '+
        '; '.join(c['component']+' '+number(c['limit_bar'],'bar') for c in context['component_limit_checks'])+'.')
    lines.append('Evaluación del contexto: '+assessments[context['assessment']]+'. No acredita seguridad integral de la instalación.')
    if context['target_pressure_matches_curve'] is False:lines.append('La presión objetivo en la lanza no coincide con su curva al caudal objetivo; no se cambia la curva ni se propone un ajuste de bomba.')
    if any(c['within_limit_at_target'] is False or c['within_limit_at_point'] is False for c in context['component_limit_checks']):
        lines.append('La cota conservadora supera algún límite declarado: no se verifica ese componente con esta cota. No demuestra una superación local; hay que evaluar la presión en su ubicación. Este control no calcula presiones locales a lo largo de la línea.')
    if context['missing_fields']:lines.append('Datos pendientes: '+', '.join(missing_label(f) for f in context['missing_fields'])+'.')
    if context['agent']!='water':
        lines.insert(0,'Los datos de curva del perfil base corresponden al modelo de agua; no representan prestaciones calculadas de espuma o CAFS.')
        if 'foam_requirement_scope' in context:
            if context['foam_requirement_scope']['pickup_geometry']=='required_for_inline_inductor':
                lines.append('En el proporcionador en línea declarado, comprobar altura de aspiración, '
                             'longitud y diámetro del tubo de toma, junto con la presión de entrada, '
                             'contrapresión y pérdidas indicadas por el fabricante.')
            else:
                conditional=context.get('conditional_fields',[])
                if conditional:
                    lines.append('Datos cuya aplicabilidad debe determinarse según la alimentación '
                                 'del espumógeno: '+', '.join(missing_label(f) for f in conditional)+'.')
                lines.append('El tipo de dosificador por sí solo no describe su alimentación de '
                             'espumógeno: un sistema de inyección también puede tener aspiración. '
                             'Comprobar el circuito y los requisitos del fabricante; no se da por '
                             'descartada la geometría de toma. Para inyección directa o presión '
                             'equilibrada, documentar la presión en el punto de inyección, las '
                             'pérdidas del mezclador y el rango de caudal de agua admitido. '
                             'Esta clasificación no verifica la dosificación ni la compatibilidad.')
        for field,value in data.get('foam_system',{}).items():
            shown=curve(value) if field=='pressure_loss_curve' else (' / '.join(fmt(v) for v in value) if isinstance(value,list) else (fmt(value) if isinstance(value,(int,float)) else str(value)))
            if field=='system_type':shown={'inline_inductor':'proporcionador en línea','around_the_pump':'dosificación alrededor de la bomba','direct_injection':'inyección directa','balanced_pressure':'dosificación a presión equilibrada','CAFS':'CAFS','other':'otro'}.get(value,str(value))
            lines.append(LABELS[field]+': '+shown+'.')
        lines.append('No se calcula caudal, presión de equilibrio ni autonomía de espuma/CAFS con el modelo de agua. Faltan un modelo específico y validación de dosificación, pérdidas y compatibilidad. No se selecciona automáticamente un sistema o concentración.')
    return '\n\n'.join(lines)
