"""Wording for deterministic measurements; no new physical diagnoses."""
from analyzer.measurement_evidence import scoped_changes, opening_comparison


def number(value):
    return f"{value:.3f}".rstrip("0").rstrip(".")


LABELS = {"hrr": "el HRR", "temperature": "la temperatura de la capa superior",
          "smoke_layer": "la interfaz", "oxygen": "el oxígeno de la capa superior"}


def measurement_text(change):
    previous, current, delta = (change[key] for key in ("previous", "current", "delta"))
    verb = "aumentó" if delta > 0 else "descendió" if delta < 0 else "se mantuvo"
    label = LABELS[change["topic"]]
    prefix = f"En {change['compartment_id']}, entre {number(change['start_time_s'])} s y {number(change['end_time_s'])} s, "
    text = (prefix + f"{label} se mantuvo en {number(current)} {change['unit']}." if delta == 0 else
            prefix + f"{label} {verb} de {number(previous)} a {number(current)} {change['unit']}.")
    if delta != 0:
        unit = "puntos porcentuales" if change["topic"] == "oxygen" else change["unit"]
        text += f" El cambio medido es {delta:+.3f}".rstrip("0").rstrip(".") + f" {unit}."
    if change["topic"] == "hrr":
        percent = change["relative_change_percent"]
        if percent is not None:
            text += f" El cambio relativo es {percent:+.1f} %."
        else:
            text += " El porcentaje relativo no está definido porque el valor inicial es cero."
        text += f" La tasa media entre las dos muestras es {number(change['mean_rate'])} kW/s; no demuestra crecimiento continuo ni una ley t²."
    if change["sampling_gap"]:
        text += " La separación entre muestras supera el máximo del detector; este cambio entre extremos no describe la evolución intermedia."
    return text


def criterion_text(change):
    criterion = change.get("criterion")
    if criterion is None or criterion["met"] or change["sampling_gap"]:
        return None
    # A falling temperature is not a subthreshold rise. Discuss the alert
    # only when the measured change has the direction assessed by its rule.
    if (change['topic'] in ('hrr', 'temperature') and change['delta'] <= 0
            or change['topic'] == 'smoke_layer' and change['delta'] >= 0):
        return None
    if change["topic"] == "hrr":
        threshold = (criterion["threshold"] - 1) * 100
        return (f"Nota sobre la alerta del software: no se disparó para este par de muestras porque exige un incremento estrictamente superior al {number(threshold)} % "
                f"(HRR final > HRR inicial × {number(criterion['threshold'])}). Este par de muestras no cumple el criterio. "
                "Esto distingue la activación del detector del cambio físico medido.")
    label = "aumento de temperatura" if change["topic"] == "temperature" else "descenso de interfaz"
    return (f"Nota sobre el criterio de detección: la regla exige un {label} de al menos "
            f"{number(criterion['threshold'])} {change['unit']}; este par de muestras no cumple el criterio.")


def geometry_text(change):
    return (f"Bajo la representación de dos capas horizontales del recinto rectangular, el área de planta es "
            f"{number(change['floor_area_m2'])} m². El cambio de altura implica un cambio de volumen de la capa superior "
            f"de {number(change['upper_layer_volume_change_m3'])} m³, con una tasa media neta de "
            f"{number(change['mean_net_volume_change_m3_s'])} m³/s. Es una variación geométrica neta, "
            "no una medición del caudal del penacho ni del volumen de productos de combustión puros.")


def evidence_for_question(context, plan):
    if plan["schema_version"] != "0.4" or plan["intent"] in ("concept", "timeline") or plan["clarification_needed"] != "none":
        return [], None
    changes = scoped_changes(context, plan["scope"], plan["topics"])
    comparison = opening_comparison(context, plan["scope"]) if "ventilation_limited" in plan["topics"] else None
    return changes, comparison


def concurrent_changes(context, changes, topics):
    """Additional variables from the exact same sample pair and room."""
    from analyzer.measurement_evidence import compare
    data = context.get("measurement_snapshot")
    if data is None:
        return []
    states = {state["time_s"]: state for state in data["states"]}
    result = []
    seen = set()
    for change in changes:
        for topic in topics:
            key = (change["compartment_id"], change["start_time_s"], change["end_time_s"], topic)
            if key not in seen:
                seen.add(key)
                result.append(compare(data, states[key[1]], states[key[2]], key[0], topic, "concurrent_context"))
    return result


def recovery_comparison(comparison):
    """An observed reversal, not a mass-flow balance or regime detector."""
    changes = {change['topic']: change for change in comparison['changes']} if comparison else {}
    return all(topic in changes and changes[topic]['delta'] > 0 for topic in ('hrr', 'oxygen'))


def response_status(plan, changes, comparison, teaching=None):
    """Presentation status; preserves separate detector/certainty contracts."""
    if plan['clarification_needed'] != 'none':
        return plan['answer_status']
    if teaching and teaching['preopening_observations']:
        return 'preopening_observations'
    if plan['intent'] in ('condition', 'general') and recovery_comparison(comparison):
        return 'ventilation_response_compatible'
    if changes and plan['intent'] in ('condition', 'observation'):
        return 'measured_change' if any(change['delta'] != 0 for change in changes) else 'unchanged_endpoints'
    if changes and plan['intent'] == 'causality':
        return 'causal_not_established'
    return plan['answer_status']


def hrr_increase_summary(plan, changes):
    if plan['intent'] not in ('condition', 'observation') or plan['topics'] != ['hrr']:
        return None
    increases = [change for change in changes if change['delta'] > 0]
    if not increases:
        return None
    change = increases[0]
    percent = change['relative_change_percent']
    magnitude = (f"del {percent:.1f} % (+{number(change['delta'])} kW)" if percent is not None
                 else f"de +{number(change['delta'])} kW")
    return (f"Sí hubo un incremento real del HRR {magnitude}: de {number(change['previous'])} "
            f"a {number(change['current'])} kW en {change['compartment_id']}, entre "
            f"{number(change['start_time_s'])} s y {number(change['end_time_s'])} s.")


def comparison_text(comparison):
    changes = comparison["changes"]
    start, end = changes[0]["start_time_s"], changes[0]["end_time_s"]
    text = ("Se observa una recuperación del oxígeno y del HRR alrededor de la apertura. " if recovery_comparison(comparison) else "")
    text += (f"Como comparación alrededor de la apertura de {comparison['action_target']} en t={number(comparison['action_time_s'])} s "
            f"(intervalo {number(start)}–{number(end)} s, que incluye una muestra anterior y otra posterior): ")
    for change in changes:
        text += f"{LABELS[change['topic']]} pasa de {number(change['previous'])} a {number(change['current'])} {change['unit']}; "
    text = text.rstrip("; ") + "."
    hrr = next(change for change in changes if change['topic'] == 'hrr')
    if hrr['relative_change_percent'] is not None:
        text += f" El cambio relativo del HRR es {hrr['relative_change_percent']:+.1f} %."
    if recovery_comparison(comparison):
        text += (" La caída previa del oxígeno y del HRR da paso a un aumento en este par de muestras. "
                 "La evolución es compatible con una reactivación de la combustión acoplada a la nueva ventilación. "
                 "Se describe una recuperación observada; no se está anticipando un régimen permanente limitado por combustible ni confirmando flashover.")
    else:
        text += " Este par no muestra una recuperación conjunta del oxígeno y del HRR."
    text += " El intervalo rodea la apertura; no es un intervalo completamente posterior."
    return text
