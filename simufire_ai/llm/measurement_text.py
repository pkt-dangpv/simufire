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
    if change["topic"] == "hrr":
        threshold = (criterion["threshold"] - 1) * 100
        return (f"Nota sobre el criterio de detección: la regla exige un incremento estrictamente superior al {number(threshold)} % "
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


def comparison_text(comparison):
    changes = comparison["changes"]
    start, end = changes[0]["start_time_s"], changes[0]["end_time_s"]
    text = (f"Como comparación alrededor de la apertura de {comparison['action_target']} en t={number(comparison['action_time_s'])} s "
            f"(intervalo {number(start)}–{number(end)} s, que incluye una muestra anterior y otra posterior): ")
    for change in changes:
        text += f"{LABELS[change['topic']]} pasa de {number(change['previous'])} a {number(change['current'])} {change['unit']}; "
    text = text.rstrip("; ") + "."
    text += (" Estos datos describen la respuesta alrededor de la apertura, no un intervalo completamente posterior. "
             "Si oxígeno, HRR y temperatura aumentan, eso es compatible con una respuesta a la nueva ventilación; "
             "no basta para demostrar que dejó de estar limitado por ventilación, que pasó a estar limitado por combustible "
             "o que ocurrió flashover. El régimen posterior requiere más datos sobre suministro de oxígeno y demanda de combustible.")
    return text
