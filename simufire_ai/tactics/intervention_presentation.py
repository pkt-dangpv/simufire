"""Readable report sections shared by Markdown and self-contained HTML."""
from html import escape
from tactics.intervention import RESOURCE_LABELS
from tactics.presentation import resolve_number_format


def sections(report, *, number_format='en', language='es'):
    style = resolve_number_format(number_format=number_format,language=language)
    def n(value, spec='g'):
        if value is None: return 'No aportado'
        text = format(value,spec)
        return text.replace('.',',') if style=='es' else text
    def boolean(value): return 'Sí, declarado' if value is True else 'No, declarado' if value is False else 'No aportado'
    def section(title, paragraphs=(), headers=(), rows=(), details=False):
        return {'title':title,'paragraphs':list(paragraphs),'headers':list(headers),'rows':[list(r) for r in rows],'details':details}
    states=report['observations'];first,last=states[0],states[-1]
    h=report['hydraulic'];c=h['installation_context'];data=c['declarations'];point=h.get('operating_point');balance=h.get('target_balance')
    ref=report['operational_reference'];water=h.get('water_at_predicted_operating_point')
    stage={'low':'Baja','high':'Alta'}.get(data.get('pump_stage'),'No aportada')
    notices=['Caso docente '+('ficticio' if report['data_kind']=='synthetic' else 'de simulación')+
             '. La instalación hidráulica es '+('ficticia' if report['hydraulic_data_kind']=='synthetic' else 'documentada en el perfil')+'.',
             'Instante evaluado: '+n(report['decision_time_s'])+' s. Última muestra: '+n(report['last_observation_time_s'])+
             ' s. No se usan observaciones posteriores para formular la valoración.']
    trend='Se observa la evolución de HRR y oxígeno en las muestras disponibles.'
    if report['changes']['hrr_kw']<0 and report['changes']['upper_o2_percent']<0:
        trend='Se observa una caída conjunta de HRR y oxígeno en la capa superior; la temperatura de esa capa cambia según la tabla.'
    summary=[trend+' Entre '+n(first['time_s'])+' s y '+n(last['time_s'])+' s: HRR '+n(first['hrr_kw'])+' → '+n(last['hrr_kw'])+
             ' kW; O₂ '+n(first['upper_o2_percent'])+' → '+n(last['upper_o2_percent'])+' %.',
             'La capacidad hidráulica se calcula con las curvas del perfil. La decisión táctica requiere además agua operativa, acceso, recursos y coordinación.']
    assessment={
        'declared_metadata_and_pressure_checks_available':'Datos declarados disponibles para las comprobaciones hidráulicas; no acredita seguridad integral.',
        'incomplete_installation_metadata':'Faltan datos y trazabilidad de la instalación; un punto matemático calculable no valida sus componentes.',
        'target_pressure_incompatible_with_nozzle_curve':'Presión objetivo incompatible con la curva de lanza al caudal objetivo; hay que revisar el diseño declarado.',
        'component_limits_need_local_pressure_evaluation':'Algún límite de componente requiere evaluar la presión local. La cota conservadora no verifica ese elemento y no demuestra una superación local.',
        'curve_domain_does_not_support_complete_result':'Las curvas no cubren el resultado completo; no se extrapolan.',
        'insufficient_head_at_target':'La bomba no aporta presión suficiente al caudal objetivo con esta curva fija.',
        'no_usable_water':'No queda agua utilizable por encima de la reserva declarada.'}
    summary.append('Comprobación de instalación: '+assessment[c['assessment']])
    if point:
        summary.append('La instalación predice '+n(point['flow_l_min'],'.3f')+' L/min, con '+n(point['available_pump_pressure_bar'],'.3f')+
                       ' bar en bomba y '+n(point['nozzle_pressure_bar'],'.3f')+' bar en lanza. Es un cálculo, no una medición.')
    if report['resources'].get('line_water_ready') is False:
        summary.append('En este caso la línea de agua se declara todavía no operativa. La lectura docente prioriza su preparación y el control de aperturas; añadir ventilación requiere revisar la coordinación con el agua. [FSRI_COORD / NIST_PPV]')
    result=[section('Lectura rápida',notices+summary)]
    result.append(section('1. Situación del incendio',
        ['Recinto: '+report['room']['name']+'; '+n(report['room']['width_m'])+' × '+n(report['room']['length_m'])+' m, altura '+n(report['room']['height_m'])+' m.',
         'HRR es la potencia del incendio. O₂ y temperatura de esta tabla corresponden a la capa superior; la interfaz es la altura que separa las dos zonas.'],
        ['Tiempo (s)','HRR (kW)','Temperatura superior (°C)','O₂ superior (%)','Interfaz (m)'],
        [[n(s['time_s']),n(s['hrr_kw']),n(s['upper_temperature_c']),n(s['upper_o2_percent']),n(s['interface_height_m'])] for s in states]))
    actions=report['recorded_actions']
    result.append(section('Acciones y detecciones',
        ['No hay aperturas registradas dentro de la ventana observada.' if not actions else
         'Aperturas/acciones registradas: '+'; '.join(a['type']+' '+a['target']+' en '+n(a['time_s'])+' s' for a in actions)+'.',
         'Los hechos de la tabla proceden del analizador existente; se conserva su certeza y su indicador causal.'],
        ['Hecho del analizador','Certeza','Afirma causalidad'],
        [[f.get('statement',f.get('text',f['fact_id'])),{'high':'Alta','moderate':'Moderada','low':'Baja'}.get(f['certainty'],f['certainty']),
          'Sí' if f['causal'] else 'No'] for f in report['physical_facts']],details=True))
    result.append(section('2. Equipos de la instalación calculada',
        ['Estos componentes son los del perfil hidráulico del ejercicio. Las fichas comerciales aparecen separadas al final.',
         'Etapa, régimen, diámetro, tipo y longitud se declaran antes de presentar pérdidas de carga.'],
        ['Dato','Valor'],[
            ['Bomba / curva',c['pump']['id']+' — '+c['pump']['configuration']],
            ['Etapa / salida',stage+' / '+data.get('pump_outlet_id','No aportada')],
            ['Régimen de la curva',n(data.get('pump_curve_speed_rpm'))+' rpm'],
            ['Manguera',n(c['hose'].get('inside_diameter_mm'))+' mm; '+data.get('hose_type','tipo no aportado')],
            ['Longitud / desnivel',n(c['installation']['hose_length_m'])+' m / '+n(c['installation']['elevation_m'],'+g')+' m'],
            ['Lanza',c['nozzle']['id']+' — '+c['nozzle']['configuration']],
            ['Accesorios',', '.join(e['id']+' ('+e['type']+')' for e in data.get('connected_elements',[])) or 'Desglose no aportado'],
            ['Presión de salida declarada',n(data.get('declared_pump_outlet_pressure_bar'))+' bar; no se simula regulación'],
            ['Caudal objetivo',n(c['target_flow_l_min'])+' L/min; dato del ejercicio'],
            ['Presión objetivo en la lanza',n(c['target_nozzle_pressure_bar'])+' bar'],
            ['Límite global de la línea',n(c['installation']['max_line_pressure_bar'])+' bar'],
            ['Límites individuales','; '.join(check['component']+': '+n(check['limit_bar'])+' bar' for check in c['component_limit_checks'])],
        ]))
    if balance:
        result.append(section('3. Caudal y presiones calculados',
            ['El balance siguiente se evalúa al caudal objetivo de '+n(c['target_flow_l_min'])+' L/min, con la manguera, longitud y desnivel declarados arriba.',
             'La comprobación de límites es conservadora. No calcula la presión local de cada elemento ni certifica la instalación.'],
            ['Magnitud','Valor (bar)'],[
                ['Presión que requiere la lanza',n(balance['nozzle_pressure_bar'],'.3f')],
                ['Pérdida de manguera',n(balance['hose_loss_bar'],'.3f')],
                ['Pérdida de accesorios',n(balance['accessory_loss_bar'],'.3f')],
                ['Efecto del desnivel',n(balance['elevation_pressure_bar'],'+.3f')],
                ['Presión total requerida en bomba',n(balance['required_pump_pressure_bar'],'.3f')],
                ['Presión disponible según curva',n(balance['available_pump_pressure_bar'],'.3f')],
            ]))
    else:
        result.append(section('3. Caudal y presiones calculados',['No hay un balance de agua calculable para esta solicitud. No se sustituye por una predicción de espuma/CAFS.']))
    if point:
        result.append(section('Punto de funcionamiento',
            ['La intersección de las curvas fijas predice '+n(point['flow_l_min'],'.3f')+' L/min y '+n(point['available_pump_pressure_bar'],'.3f')+
             ' bar en bomba. La presión calculada en la lanza es '+n(point['nozzle_pressure_bar'],'.3f')+' bar.',
             'No se infiere que la bomba vaya a mantener el caudal objetivo por un ajuste de acelerador no modelado.']))
    result.append(section('4. Qué caudal estamos comparando',
        ['Perfil docente de referencia: GIE, febrero de 2026, páginas impresas 34–36. Su adopción por un servicio concreto no está verificada.',
         'El criterio operativo citado es disponer de más de '+n(ref['minimum_flow_l_min'])+' L/min con no más de '+n(ref['maximum_nozzle_pressure_bar'])+
         ' bar en lanza. Comparación numérica del punto calculado: '+('cumple esos dos valores' if ref['predicted_point_meets_numeric_reference'] is True else
         'no cumple al menos uno de esos valores' if ref['predicted_point_meets_numeric_reference'] is False else 'no evaluable')+
         '. No acredita capacidad de extinción, manejabilidad ni seguridad integral. [GIE_FLOW]',
         'La aproximación de 50 L/min por m² de hueco se ilustra solo para la hipótesis de apertura completa indicada. Presupone un ILV y geometrías habituales; no predice el HRR ni sustituye el criterio operativo o la doctrina del servicio. [GIE_FLOW]'],
        ['Hipótesis de apertura completa','Dimensiones (m)','Área (m²)','Referencia simplificada (L/min)'],
        [[o['opening_id'],n(o['width_m'])+' × '+n(o['height_m']),n(o['area_m2']),n(o['reference_flow_l_min'])] for o in ref['simplified_opening_references']]))
    if water:
        result.append(section('5. Agua disponible y autonomía',
            ['El cálculo supone una sola línea en descarga continua, aporte constante y alimentación adecuada de bomba. No incluye otros consumos.'],
            ['Dato','Valor'],[
                ['Depósito declarado',n(report['declared_water_supply']['tank_l'])+' L'],
                ['Reserva declarada',n(report['declared_water_supply']['reserve_l'])+' L'],
                ['Agua utilizable sobre la reserva',n(water['usable_tank_l'])+' L'],
                ['Aporte constante declarado',n(water['constant_inflow_l_min'])+' L/min'],
                ['Caudal neto de vaciado',n(water['net_draw_l_min'],'.3f')+' L/min'],
                ['Tiempo hasta reserva',n(water['minutes_to_reserve'],'.3f')+' min' if water['minutes_to_reserve'] is not None else 'Sin vaciado neto calculado; no equivale a autonomía ilimitada'],
            ]))
    else: result.append(section('5. Agua disponible y autonomía',['No hay autonomía calculada para esta configuración.']))
    result.append(section('6. Recursos declarados',
        [report['resources_source'],'Registro de recursos: '+n(report['resources_recorded_at_s'])+' s. Son declaraciones; no verificaciones del estado real del equipo.'],
        ['Recurso o condición','Estado'],
        [['Personal',n(report['resources'].get('crew_count'))+' personas; su número por sí solo no verifica la dotación necesaria']]+
        [[label,boolean(report['resources'].get(key))] for key,label in RESOURCE_LABELS.items()]))
    status={'declared_prerequisites_not_met':'Hay requisitos declarados sin cumplir',
            'conditional_on_missing_data':'Condicionada a datos pendientes',
            'declared_prerequisites_available':'Requisitos declarados disponibles; requiere valoración del mando',
            'hydraulic_review_required':'Requiere revisar la instalación hidráulica'}
    option_rows=[]
    for option in report['options']:
        gaps=['Sin cumplir: '+', '.join(RESOURCE_LABELS[f] for f in option['unfulfilled_fields'])] if option['unfulfilled_fields'] else []
        if option['missing_fields']:gaps.append('Por confirmar: '+', '.join(RESOURCE_LABELS[f] for f in option['missing_fields']))
        if option.get('hydraulic_review_required'):gaps.append(assessment[c['assessment']])
        option_rows.append([option['title'],option['purpose'],status[option['status']],'; '.join(gaps) or 'Revisar evolución y protocolo del servicio'])
    result.append(section('7. Ventilación y técnicas que valorar',
        ['Las opciones se relacionan con objetivos y condiciones declaradas. No autorizan entrada, apertura ni uso de un ventilador.',
         'En los ensayos residenciales de FSRI, la coordinación entre agua y ventilación y el alcance del agua sobre superficies influyeron en el resultado. El patrón de chorro también modifica el transporte de aire: seleccionar la técnica exige revisar el recorrido de gases. [FSRI_COORD / NIST_JET]'],
        ['Opción','Objetivo','Valoración con estos datos','Qué falta'],option_rows))
    result.append(section('8. Condiciones para las víctimas',
        ['La capa superior no representa toda la habitación. Se muestran por separado los valores de la zona inferior.',
         'No se estima porcentaje de supervivencia ni FED: faltan ubicación, trayectoria, exposición previa, flujo térmico y caracterización toxicológica suficiente. Estos promedios de zona no son mediciones personales. [FSRI_RESCUE]',
         'La presencia de CO y el calentamiento requieren valorar exposición y acceso al rescate. No permiten declarar que no quedan personas con posibilidad de supervivencia.'],
        ['Tiempo (s)','Temperatura inferior (°C)','O₂ inferior (%)','CO inferior (ppm)','CO₂ inferior (%)'],
        [[n(s['time_s']),n(s['lower_temperature_c']),n(s['lower_o2_percent']),n(s['lower_co_ppm']),n(s['lower_co2_percent'])] for s in states]))
    equipment_rows=[]
    names={'rated_flow':'Caudal nominal','rated_pressure':'Presión nominal','selectable_flows':'Selectores de caudal',
           'reference_pressure':'Presión de referencia','inside_diameter':'Diámetro','working_pressure':'Presión de trabajo de la manguera sin racores',
           'free_air_flow':'Caudal en aire libre','amca_240_flow':'Caudal AMCA 240'}
    for e in report['equipment_reference_only']:
        facts=[]
        for f in e['facts']:
            if f['name'] not in names:continue
            value=' / '.join(n(v) for v in f['value']) if isinstance(f['value'],list) else n(f['value'])
            facts.append(names[f['name']]+': '+value+' '+f['unit'])
        equipment_rows.append([e['manufacturer']+' '+e['model'],'; '.join(facts),
            'Disponibilidad no declarada. Faltan datos para calcular una instalación con esta ficha.'+(' Existen discrepancias documentadas.' if e['conflicts'] else '')])
    result.append(section('9. Referencias comerciales consultadas',
        ['Estas fichas reales proceden del catálogo y sus ediciones documentadas. No se han usado para construir las curvas ficticias del ejercicio ni se han declarado como dotación disponible.',
         'Los selectores de una lanza son ajustes distintos, no una curva única. Las presiones y caudales nominales de bomba y ventilador tampoco garantizan su entrega en esta instalación.'],
        ['Modelo','Datos de ficha','Límite de uso en este informe'],equipment_rows,details=True))
    curve_rows=[]
    for name,label in [('pump','Bomba'),('nozzle','Lanza'),('hose','Manguera por '+n(c['hose']['reference_length_m'])+' m'),('aggregate_accessories','Accesorios')]:
        for p in c[name]['curve']:curve_rows.append([label,n(p['flow_l_min']),n(p['pressure_bar'],'.3f')])
    for e in data.get('connected_elements',[]):
        for p in e['curve']:curve_rows.append(['Accesorio '+e['id'],n(p['flow_l_min']),n(p['pressure_bar'],'.3f')])
    for p in c['resistant_curve'] or []:curve_rows.append(['Resistencia total',n(p['flow_l_min']),n(p['required_pressure_bar'],'.3f')])
    result.append(section('Curvas del ejercicio',[],['Elemento','Caudal (L/min)','Presión o pérdida (bar)'],curve_rows,details=True))
    source_rows=[]
    for source in report['sources']:
        source_rows.append([source['id'],source['title'],source['edition'],source['locator'],source.get('url') or 'Ejemplar local incluido en el proyecto'])
    for source in report['equipment_sources']:
        source_rows.append([source['source_id'],source['title'],source['edition'],source['locator'],source['url']])
    result.append(section('Fuentes y alcance',
        ['Los criterios tácticos de esta primera versión están pendientes de revisión experta. No constituyen una doctrina adoptada por un servicio.',
         'Las condiciones experimentales y los límites de cada fuente se conservan. La referencia GIE se interpreta y atribuye conforme a CC BY-NC-SA 4.0.'],
        ['Referencia','Documento','Edición','Apartado / alcance','Ubicación'],source_rows,details=True))
    return result


def render_markdown(report, **preferences):
    output=['# SimuFire · Informe docente de intervención','']
    for section in sections(report,**preferences):
        output+=['## '+section['title'],'']
        for p in section['paragraphs']:output += [p,'']
        if section['headers']:
            clean=lambda v:str(v).replace('|','\\|').replace('\n',' ')
            output+=['| '+' | '.join(section['headers'])+' |','| '+' | '.join('---' for h in section['headers'])+' |']
            output+=['| '+' | '.join(clean(v) for v in row)+' |' for row in section['rows']]
            output+=['']
    return '\n'.join(output)


def render_html(report, **preferences):
    blocks=[]
    for section in sections(report,**preferences):
        title=escape(section['title']);body=''.join('<p>'+escape(p)+'</p>' for p in section['paragraphs'])
        if section['headers']:
            body+='<div class="table-wrap"><table><thead><tr>'+''.join('<th scope="col">'+escape(h)+'</th>' for h in section['headers'])+'</tr></thead><tbody>'
            for row in section['rows']:
                cells=[]
                for value in row:
                    shown=escape(str(value))
                    if section['title']=='Fuentes y alcance' and str(value).startswith('https://'):
                        shown='<a href="'+escape(str(value),quote=True)+'" target="_blank" rel="noopener">Abrir fuente</a>'
                    cells.append('<td>'+shown+'</td>')
                body+='<tr>'+''.join(cells)+'</tr>'
            body+='</tbody></table></div>'
        blocks.append('<details><summary>'+title+'</summary>'+body+'</details>' if section['details'] else '<section><h2>'+title+'</h2>'+body+'</section>')
    css='''body{font:16px/1.55 system-ui,sans-serif;color:#1b2a38;background:#edf1f5;margin:0}main{max-width:1100px;margin:32px auto;padding:0 24px 48px}header{background:#17374a;color:white;padding:30px;border-radius:14px}h1{margin:0;font-size:30px}header p{margin:8px 0 0;color:#d7e5ec}section,details{background:white;border:1px solid #d8e0e7;border-radius:12px;margin:20px 0;padding:22px}h2,summary{font-size:21px;font-weight:650;margin:0 0 14px}summary{cursor:pointer}p{max-width:95ch}table{border-collapse:collapse;width:100%;font-size:14px}th{text-align:left;background:#eaf0f5;color:#17374a}th,td{padding:11px;border-bottom:1px solid #d8e0e7;vertical-align:top}th{white-space:normal}tr:last-child td{border-bottom:0}.table-wrap{overflow-x:auto}section:first-of-type{border-left:5px solid #cf9626}footer{color:#526371;font-size:13px}@media(max-width:650px){main{padding:0 12px}header,section,details{padding:16px}h1{font-size:24px}h2,summary{font-size:19px}table{min-width:600px}}@media print{body{background:white}main{max-width:none;margin:0;padding:0}header{color:black;background:white;border-bottom:2px solid #17374a}header p{color:#333}section,details{break-inside:avoid;border:0;padding:12px 0}.table-wrap{overflow:visible}table{min-width:0}}'''
    return '<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>SimuFire · Informe de intervención</title><style>'+css+'</style></head><body><main><header><h1>SimuFire · Informe de intervención</h1><p>Observaciones · capacidad hidráulica · valoración docente</p></header>'+''.join(blocks)+'<footer>Datos observados, cálculos y referencias se presentan por separado. No hay decisiones operativas automáticas.</footer></main></body></html>'
