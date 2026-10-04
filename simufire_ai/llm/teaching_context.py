"""Scoped teaching context from recorded inputs; never a phenomenon detector."""
from analyzer.action_context import action_compartments, sorted_actions
from analyzer.measurement_evidence import compare


def redundant_openings(context, actions):
    """Only repeated opens of one initially closed opening, without intervening actions."""
    data = context.get('measurement_snapshot')
    if data is None or len(actions) < 2:
        return None
    target = actions[0].get('action_target')
    if not target or any(a.get('action_target') != target for a in actions):
        return None
    scenario = data['scenario']
    opening = next((o for o in scenario['openings'] if o['id'] == target), None)
    if opening is None or opening['state'] != 'closed':
        return None
    times = sorted(a['time_s'] for a in actions)
    room_ids = set(action_compartments(scenario, {'target': target}))
    if len(room_ids) != 1:
        return None
    local = [a for a in sorted_actions(scenario) if a['time_s'] <= times[-1]
             and room_ids.intersection(action_compartments(scenario, a))]
    if len(local) != len(actions) or any(a['type'] != 'open' or a['target'] != target for a in local):
        return None
    if [a['time_s'] for a in local] != times or len(set(times)) != len(times):
        return None
    return {'target': target, 'times_s': times, 'causal': False,
            'basis': 'repeated_open_without_recorded_close'}


def teaching_context(context, plan, changes):
    result = {'temperature_actions': [], 'temperature_reversal': None,
              'preopening_observations': None, 'backdraft_sample': None}
    data = context.get('measurement_snapshot')
    if data is None or plan['schema_version'] != '0.4' or plan['clarification_needed'] != 'none':
        return result
    scenario, scope = data['scenario'], plan['scope']
    if plan['topics'] == ['temperature'] and plan['intent'] in ('condition', 'observation'):
        from analyzer.action_context import room_actions_between
        for change in changes:
            for action in room_actions_between(scenario, change['compartment_id'], change['start_time_s'], change['end_time_s']):
                if action['type'] == 'open':
                    result['temperature_actions'].append({**action, 'compartment_id': change['compartment_id'],
                        'start_time_s': change['start_time_s'], 'end_time_s': change['end_time_s'], 'causal': False})
        # Summarize only an uninterrupted decline followed by a rise, in the
        # same scoped adjacent sample pairs. Never fetch an out-of-scope past.
        for room in sorted({c['compartment_id'] for c in changes}):
            local = [c for c in changes if c['compartment_id'] == room]
            falling = []
            for c in local:
                if c['sampling_gap']:
                    falling = []
                elif c['delta'] < 0:
                    falling.append(c)
                elif c['delta'] > 0 and falling:
                    result['temperature_reversal'] = {'compartment_id': room,
                        'start_time_s': falling[0]['start_time_s'], 'end_time_s': falling[-1]['end_time_s'],
                        'previous': falling[0]['previous'], 'current': falling[-1]['current'],
                        'delta': falling[-1]['current'] - falling[0]['previous'], 'causal': False}
                    break
                else:
                    falling = []
    if (plan['topics'] == ['ventilation_limited'] and plan['intent'] == 'condition'
            and scope['time_relation'] == 'before' and scope['anchor_fact_id']):
        anchor = next(f for f in context['scenario_facts'] if f['fact_id'] == scope['anchor_fact_id'])
        actions = [f for f in context['scenario_facts'] if f['fact_type'] == 'action'
                   and f.get('action_target') == anchor.get('action_target')]
        repetition = redundant_openings(context, actions)
        if repetition and scope['end_time_s'] == repetition['times_s'][0]:
            rooms = action_compartments(scenario, {'target': repetition['target']})
            if scope['compartment_id']:
                rooms = tuple(r for r in rooms if r == scope['compartment_id'])
            if len(rooms) == 1:
                before = [s for s in data['states'] if s['time_s'] < scope['end_time_s']]
                # Break at sampling gaps; don't imply continuous prehistory.
                contiguous = []
                for state in before:
                    if contiguous and state['time_s'] - contiguous[-1]['time_s'] > data['thresholds']['timeline']['max_gap_s']:
                        contiguous = []
                    contiguous.append(state)
                if (len(contiguous) >= 2 and scope['end_time_s'] - contiguous[-1]['time_s']
                        <= data['thresholds']['timeline']['max_gap_s']):
                    values = [compare(data, contiguous[0], contiguous[-1], rooms[0], topic, 'preopening_context')
                              for topic in ('oxygen', 'hrr', 'temperature')]
                    result['preopening_observations'] = {'repetition': repetition, 'changes': values,
                        'diagnostic': False, 'causal': False, 'basis': 'recorded_preopening_endpoints'}
    if plan['topics'] == ['backdraft'] and plan['intent'] == 'condition':
        # Observations support teaching, not a yes/no backdraft or risk score.
        rooms = [r['id'] for r in scenario['compartments'] if scope['compartment_id'] in (None, r['id'])]
        if len(rooms) == 1:
            from llm.question_scope import time_matches
            room = rooms[0]
            eligible = [s for s in data['states'] if time_matches(s['time_s'], scope)]
            recorded_times = {f['time_s'] for f in context['scenario_facts'] if f['fact_type'] == 'action'}
            openings = [a for a in sorted_actions(scenario) if a['type'] == 'open'
                        and a['time_s'] in recorded_times and room in action_compartments(scenario, a)]
            action = openings[0] if len(openings) == 1 else None
            if action and scope['time_relation'] == 'all':
                eligible = [s for s in eligible if s['time_s'] < action['time_s']]
                if eligible and action['time_s'] - eligible[-1]['time_s'] > data['thresholds']['timeline']['max_gap_s']:
                    eligible = []
            if eligible:
                state = eligible[-1]
                value = next(c for c in state['compartments'] if c['id'] == room)
                result['backdraft_sample'] = {'compartment_id': room, 'time_s': state['time_s'],
                    'oxygen_percent': value['upper_layer']['o2_percent'],
                    'temperature_c': value['upper_layer']['temperature_c'], 'hrr_kw': value['hrr_kw'],
                    'before_opening': action if action and state['time_s'] < action['time_s'] else None,
                    'diagnostic': False, 'causal': False, 'basis': 'recorded_sample'}
    return result


def teaching_text(details):
    from llm.measurement_text import number
    paragraphs = []
    reversal = details['temperature_reversal']
    if reversal:
        paragraphs.append(f"Tendencia previa en {reversal['compartment_id']}: entre {number(reversal['start_time_s'])} s y "
            f"{number(reversal['end_time_s'])} s, la temperatura superior descendió de {number(reversal['previous'])} "
            f"a {number(reversal['current'])} °C ({reversal['delta']:+.1f} °C), antes del aumento mostrado. "
            "La causa de esa caída no queda establecida por las temperaturas solas.")
    for action in details['temperature_actions']:
        paragraphs.append(f"En el mismo recinto, {action['compartment_id']}, se registró la apertura de {action['target']} "
            f"en t={number(action['time_s'])} s, dentro del intervalo {number(action['start_time_s'])}–{number(action['end_time_s'])} s. "
            "Es una asociación temporal, no una atribución causal del incremento de temperatura.")
    previous = details['preopening_observations']
    if previous:
        repetition, changes = previous['repetition'], previous['changes']
        paragraphs.append(f"Analizo el tramo común anterior a la primera apertura registrada de {repetition['target']} "
            f"en t={number(repetition['times_s'][0])} s: {number(changes[0]['start_time_s'])}–{number(changes[0]['end_time_s'])} s.")
        paragraphs.append(' '.join(f"{ {'oxygen': 'El oxígeno superior', 'hrr': 'El HRR', 'temperature': 'La temperatura superior'}[c['topic']] } "
            f"pasa de {number(c['previous'])} a {number(c['current'])} {c['unit']}." for c in changes))
        if all(c['delta'] < 0 for c in changes):
            paragraphs.append("El decaimiento conjunto es compatible con una combustión condicionada por la ventilación, "
                "pero estas observaciones no confirman por sí solas un incendio limitado por ventilación.")
        times = ', '.join(number(t) + ' s' for t in repetition['times_s'])
        paragraphs.append(f"El registro repite la apertura de {repetition['target']} en {times}, sin cierre intermedio registrado. "
            "Se señala esta posible anomalía y se conservan ambas acciones. Impide una confirmación retrospectiva inequívoca "
            "con la regla actual; no se ha generado una detección nueva de ILV.")
    sample = details['backdraft_sample']
    if sample:
        paragraphs.append(f"Como observación para orientar la interpretación, en {sample['compartment_id']} a t={number(sample['time_s'])} s "
            f"el oxígeno superior es {number(sample['oxygen_percent'])} %, la temperatura superior es {number(sample['temperature_c'])} °C "
            f"y el HRR es {number(sample['hrr_kw'])} kW. "
            "Estos valores no miden la cantidad de combustible gaseoso sin quemar ni identifican llama o combustión latente. "
            "Un aumento de HRR tras ventilar no identifica por sí solo una deflagración. Para evaluar backdraft faltan "
            "la composición y distribución del combustible gaseoso, las condiciones de mezcla e ignición y datos que resuelvan el evento transitorio.")
    return paragraphs
