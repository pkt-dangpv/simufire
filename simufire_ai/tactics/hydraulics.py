"""Bounded steady-state hydraulic calculations; no fire-suppression inference."""
import hashlib
import json
import math
from pathlib import Path

from jsonschema import Draft202012Validator

SCHEMA_PATH = Path(__file__).with_name('hydraulic_profile.schema.json')
STATIC_BAR_PER_M = 1000 * 9.80665 / 100000
METHOD_VERSION = '0.1'
PRESSURE_TOLERANCE_BAR = 1e-9
REFERENCE = {
    'source_id': 'CEIS_GUADALAJARA_HYDRAULICS_2015',
    'title': 'Manual de incendios, parte 2: Hidráulica',
    'edition': '2015.10.05', 'pages': '77–79',
    'url': 'https://ceis.antiun.net/docus/pdfsonline/m1/M1_Incendios_v6_02_hidraulica/M1-Incendios-v6-02-hidraulica.pdf',
    'role': 'Pressure balance and pump/system operating point; not equipment data or a tactical flow criterion',
}


def digest(value):
    try:
        raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)
    except (ValueError, TypeError) as error:
        raise ValueError('El perfil contiene datos no JSON o números no finitos') from error
    return hashlib.sha256(raw.encode('utf-8')).hexdigest()


def read_profile(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Clave duplicada: ' + key)
            result[key] = value
        return result
    def constant(value):
        raise ValueError('Número no finito: ' + value)
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=pairs, parse_constant=constant)


def validate_profile(profile):
    digest(profile)
    def representable(value):
        if isinstance(value, dict):
            for item in value.values(): representable(item)
        elif isinstance(value, list):
            for item in value: representable(item)
        elif isinstance(value, (int, float)) and not isinstance(value, bool):
            try:
                finite = math.isfinite(value)
            except OverflowError:
                finite = False
            if not finite:
                raise ValueError('Número fuera del rango finito de cálculo')
    representable(profile)
    schema = json.loads(SCHEMA_PATH.read_text(encoding='utf-8'))
    errors = list(Draft202012Validator(schema).iter_errors(profile))
    if errors:
        error = errors[0]
        raise ValueError('Perfil hidráulico: ' + '/'.join(map(str, error.absolute_path)) + ': ' + error.message)
    sources = [s['source_id'] for s in profile['sources']]
    if len(set(sources)) != len(sources):
        raise ValueError('Fuentes duplicadas')
    for name in ('pump', 'nozzle', 'hose', 'accessories', 'objective'):
        if profile[name]['source_id'] not in sources:
            raise ValueError('Fuente inexistente: ' + name)
    ids = [profile[name]['id'] for name in ('pump', 'nozzle', 'hose')]
    if len(set(ids)) != len(ids):
        raise ValueError('Identificadores de equipo duplicados')
    for name in ('pump', 'nozzle', 'hose', 'accessories'):
        points = profile[name]['curve']
        for a, b in zip(points, points[1:]):
            if b['flow_l_min'] <= a['flow_l_min']:
                raise ValueError('Caudales sin orden estricto: ' + name)
            delta = b['pressure_bar'] - a['pressure_bar']
            if ((name == 'pump' and delta > 0) or (name == 'nozzle' and delta <= 0)
                    or (name in ('hose', 'accessories') and delta < 0)):
                raise ValueError('Curva no monótona para el modelo: ' + name)
        if name in ('pump', 'nozzle') and any(p['pressure_bar'] <= 0 for p in points):
            raise ValueError('Presión no positiva: ' + name)
    supply = profile['water_supply']
    if supply['reserve_l'] > supply['tank_l']:
        raise ValueError('La reserva supera el depósito')
    low = max(profile[n]['curve'][0]['flow_l_min'] for n in ('pump', 'nozzle', 'hose', 'accessories'))
    high = min(profile[n]['curve'][-1]['flow_l_min'] for n in ('pump', 'nozzle', 'hose', 'accessories'))
    if low >= high:
        raise ValueError('Las curvas no tienen un intervalo común de caudal')
    return low, high


def pressure(curve, flow):
    if not curve[0]['flow_l_min'] <= flow <= curve[-1]['flow_l_min']:
        raise ValueError('Caudal fuera del rango de la curva; no se extrapola')
    for a, b in zip(curve, curve[1:]):
        if a['flow_l_min'] <= flow <= b['flow_l_min']:
            fraction = (flow - a['flow_l_min']) / (b['flow_l_min'] - a['flow_l_min'])
            return a['pressure_bar'] + fraction * (b['pressure_bar'] - a['pressure_bar'])
    raise ValueError('No hay segmento para el caudal')


def balance(profile, flow):
    installation = profile['installation']
    nozzle = pressure(profile['nozzle']['curve'], flow)
    hose = pressure(profile['hose']['curve'], flow) * installation['hose_length_m'] / profile['hose']['reference_length_m']
    accessories = pressure(profile['accessories']['curve'], flow)
    elevation = installation['elevation_m'] * STATIC_BAR_PER_M
    required = nozzle + hose + accessories + elevation
    available = pressure(profile['pump']['curve'], flow)
    # Conservative pressure bound for a line with monotonic elevation. It is
    # not a spatial pressure solution for arbitrary up/down hose routes.
    upper = available + max(0, -elevation)
    limit = installation['max_line_pressure_bar']
    values = {'flow_l_min': flow, 'nozzle_pressure_bar': nozzle, 'hose_loss_bar': hose,
        'accessory_loss_bar': accessories, 'elevation_pressure_bar': elevation,
        'required_pump_pressure_bar': required, 'available_pump_pressure_bar': available,
        'pressure_margin_bar': available - required, 'conservative_line_pressure_bar': upper}
    if not all(math.isfinite(value) for value in values.values()):
        raise ValueError('El cálculo excede el rango numérico finito')
    values['line_pressure_within_declared_limit'] = None if limit is None else upper <= limit + PRESSURE_TOLERANCE_BAR
    return values


def autonomy(profile, flow):
    supply = profile['water_supply']
    usable = supply['tank_l'] - supply['reserve_l']
    net = flow - supply['inflow_l_min']
    if usable == 0 and net > 0:
        status, minutes = 'no_usable_water', 0.0
    elif net <= 0:
        status, minutes = 'no_tank_depletion_under_constant_inflow', None
    else:
        status, minutes = 'tank_depletion', usable / net
    if minutes is not None and not math.isfinite(minutes):
        raise ValueError('Autonomía fuera del rango numérico finito')
    return {'status': status, 'usable_tank_l': usable, 'constant_inflow_l_min': supply['inflow_l_min'],
        'consumption_l_min': flow, 'net_draw_l_min': net, 'minutes_to_reserve': minutes,
        'basis': 'Constant calculated flow and supplied inflow; not guaranteed endurance'}


def analyze_profile(profile):
    low, high = validate_profile(profile)
    target = profile['objective']['flow_l_min']
    target_balance = balance(profile, target) if low <= target <= high else None
    if target_balance is None:
        status = 'target_outside_curve_domain'
    elif target_balance['required_pump_pressure_bar'] < 0:
        status = 'gravity_exceeds_target_requirement'
    elif target_balance['pressure_margin_bar'] < -PRESSURE_TOLERANCE_BAR:
        status = 'insufficient_head_at_target'
    else:
        status = 'sufficient_head_at_target'
    left, right = balance(profile, low), balance(profile, high)
    if left['pressure_margin_bar'] < 0:
        point, point_status = None, 'operating_point_below_curve_domain'
    elif right['pressure_margin_bar'] > 0:
        point, point_status = None, 'operating_point_above_curve_domain'
    else:
        # Monotone pump and strictly increasing nozzle curves give a unique
        # intersection of their piecewise-linear models in the common domain.
        for _ in range(80):
            mid = low + (high - low) / 2
            if balance(profile, mid)['pressure_margin_bar'] > 0:
                low = mid
            else:
                high = mid
        point = balance(profile, low + (high - low) / 2)
        point_status = 'operating_point_in_curve_domain'
    result = {'schema_version': '0.1', 'profile_id': profile['profile_id'], 'data_kind': profile['data_kind'],
        'input_sha256': digest(profile), 'method_version': METHOD_VERSION,
        'numerical_pressure_tolerance_bar': PRESSURE_TOLERANCE_BAR,
        'method_sha256': digest({p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (Path(__file__), SCHEMA_PATH)}),
        'objective': dict(profile['objective']), 'target_status': status, 'target_balance': target_balance,
        'curve_domain_l_min': list(validate_profile(profile)),
        'operating_point_status': point_status, 'operating_point': point,
        'water_at_predicted_operating_point': autonomy(profile, point['flow_l_min']) if point else None,
        'equipment_sources': json.loads(json.dumps(profile['sources'])), 'method_reference': dict(REFERENCE),
        'tactical_sufficiency': 'not_evaluated', 'assumptions': [
            'One steady-state line, one fixed pump/nozzle configuration and monotonic elevation; no branches or other consumers.',
            'Piecewise-linear interpolation of supplied curves only, within their common range.',
            'Water density 1000 kg/m³; standard gravity 9.80665 m/s².',
            'Pump curve assumes suitable suction/feed; cavitation and feed pressure are not assessed.',
            'Inflow is constant as specified; pressure regulation and its effect on pump curves are not simulated.',
            'Pressure at target checks available head; it does not select a pump setting or predict fire suppression.',
        ]}
    digest(result)
    return result


def render_result(result):
    target = result['objective']['flow_l_min']
    parts = ['Perfil ficticio de entrenamiento.' if result['data_kind'] == 'synthetic' else 'Perfil de referencia aportado.']
    b = result['target_balance']
    if b is None:
        parts.append(f'El objetivo de {target:g} L/min queda fuera del intervalo común de las curvas; no se extrapola.')
    elif result['target_status'] == 'gravity_exceeds_target_requirement':
        parts.append('El desnivel descendente aporta más presión que la requerida por el objetivo; '
            'el balance algebraico daría presión negativa en bomba. Hace falta evaluar regulación o disipación; no se propone ese ajuste.')
    else:
        verdict = 'aporta presión suficiente' if result['target_status'] == 'sufficient_head_at_target' else 'no aporta presión suficiente'
        parts.append(f'Para el objetivo de {target:g} L/min, la curva de bomba {verdict}: '
            f'{b["available_pump_pressure_bar"]:.3f} bar disponibles frente a '
            f'{b["required_pump_pressure_bar"]:.3f} bar requeridos (margen {b["pressure_margin_bar"]:+.3f} bar).')
        parts.append(f'Balance: lanza {b["nozzle_pressure_bar"]:.3f} + manguera {b["hose_loss_bar"]:.3f} '
            f'+ accesorios {b["accessory_loss_bar"]:.3f} + desnivel {b["elevation_pressure_bar"]:+.3f} bar.')
        check = b['line_pressure_within_declared_limit']
        if check is False:
            parts.append('El límite de presión declarado no se cumple con la cota conservadora; esta configuración requiere revisión.')
        elif check is None:
            parts.append('Falta el límite de presión de la instalación; ese control queda sin evaluar.')
        else:
            parts.append('La cota conservadora está dentro del límite de presión declarado.')
    point = result['operating_point']
    if point:
        parts.append(f'Con estas curvas fijas, el punto de funcionamiento calculado es '
            f'{point["flow_l_min"]:.3f} L/min y {point["available_pump_pressure_bar"]:.3f} bar en bomba. '
            'Es una predicción del modelo hidráulico, no un caudal medido.')
        if point['line_pressure_within_declared_limit'] is False:
            parts.append('En ese punto tampoco se cumple el límite de presión declarado.')
        water = result['water_at_predicted_operating_point']
        if water['status'] == 'no_usable_water':
            parts.append('No hay agua utilizable por encima de la reserva para sostener ese consumo con el aporte declarado.')
        elif water['minutes_to_reserve'] is None:
            parts.append('El aporte constante declarado evita el vaciado del depósito en este balance; no acredita autonomía ilimitada del equipo.')
        else:
            parts.append(f'Con ese consumo y el aporte declarado, se alcanza la reserva en '
                f'{water["minutes_to_reserve"]:.3f} min; agua utilizable: {water["usable_tank_l"]:g} L.')
    else:
        parts.append('La intersección bomba–instalación queda fuera del rango común; el caudal de funcionamiento y su autonomía no se calculan.')
    parts.append('El objetivo de caudal procede del perfil. La suficiencia para extinguir o enfriar el incendio sigue sin evaluar. '
        'El modelo representa una sola línea en régimen estacionario y desnivel monotónico; presupone alimentación adecuada de la bomba.')
    return '\n\n'.join(parts)
