"""Deterministic endpoint comparisons, distinct from thresholded detections.

No interpolation, causal inference, or new fire-phenomenon detector. Every
comparison retains its room and both sample times in the bound context.
"""
import copy


VARIABLES = {
    "hrr": ("hrr_kw", "kW"),
    "temperature": ("temperature_c", "°C"),
    "smoke_layer": ("interface_height_m", "m"),
    "oxygen": ("o2_percent", "%"),
}


def snapshot(scenario, states, thresholds):
    return copy.deepcopy({"scenario": scenario, "states": states, "thresholds": thresholds})


def validate_measurements(context, validate_schema, load_schema, unique_index):
    data = context["measurement_snapshot"]
    scenario, states, thresholds = (data[key] for key in ("scenario", "states", "thresholds"))
    validate_schema(scenario, load_schema("scenario.schema.json"), "Escenario de mediciones")
    validate_schema(thresholds, load_schema("analyzer_thresholds.schema.json"), "Umbrales de mediciones")
    if scenario["scenario_id"] != context["scenario_id"] or scenario["schema_version"] != "0.1":
        raise ValueError("Mediciones de otro escenario o versión")
    rooms = unique_index(scenario["compartments"], "id")
    unique_index(scenario["openings"], "id")
    unique_index(scenario["fires"], "id")
    times = []
    for state in states:
        validate_schema(state, load_schema("simulation_state.schema.json"), "Estado de mediciones")
        if state["scenario_id"] != context["scenario_id"] or state["schema_version"] != "0.1":
            raise ValueError("Estado de mediciones de otro escenario o versión")
        indexed = unique_index(state["compartments"], "id")
        if set(indexed) != set(rooms):
            raise ValueError("Compartimentos mezclados en mediciones")
        if any(value["interface_height_m"] > rooms[key]["height_m"] for key, value in indexed.items()):
            raise ValueError("Interfaz de mediciones fuera del recinto")
        times.append(state["time_s"])
    if times != sorted(set(times)) or times[-1] > scenario["simulation"]["duration_s"]:
        raise ValueError("Tiempos de mediciones inválidos")
    # Recompute existing deterministic events/coverage from the same snapshot;
    # a structurally valid snapshot from another analysis must not be mixed in.
    from .fire_event_analyzer import analyze_timeline
    from .assessment_coverage import build_assessment_coverage
    if analyze_timeline(states, scenario, thresholds) != context.get("source_events"):
        raise ValueError("Eventos y mediciones de distintos análisis")
    if build_assessment_coverage(scenario, states, thresholds) != context.get("analysis_coverage"):
        raise ValueError("Cobertura y mediciones de distintos análisis")


def value(room, topic):
    key = VARIABLES[topic][0]
    return room["upper_layer"][key] if topic in ("temperature", "oxygen") else room[key]


def compare(data, before, after, room_id, topic, role="requested_scope"):
    first = next(room for room in before["compartments"] if room["id"] == room_id)
    last = next(room for room in after["compartments"] if room["id"] == room_id)
    previous, current = value(first, topic), value(last, topic)
    delta = current - previous
    duration = after["time_s"] - before["time_s"]
    result = {
        "topic": topic, "compartment_id": room_id, "role": role,
        "start_time_s": before["time_s"], "end_time_s": after["time_s"],
        "previous": previous, "current": current, "delta": delta,
        "unit": VARIABLES[topic][1], "mean_rate": delta / duration,
        "relative_change_percent": delta / previous * 100 if topic == "hrr" and previous > 0 else None,
        "causal": False, "basis": "recorded_endpoints",
        "sampling_gap": duration > data["thresholds"]["timeline"]["max_gap_s"],
    }
    limits = data["thresholds"]
    if topic == "hrr":
        result["criterion"] = {"quantity": "ratio", "operator": ">", "threshold": limits["hrr"]["increase_ratio"],
                               "met": current > previous * limits["hrr"]["increase_ratio"]}
    elif topic == "temperature":
        result["criterion"] = {"quantity": "delta", "operator": ">=", "threshold": limits["temperature"]["upper_layer_increase_c"],
                               "met": delta >= limits["temperature"]["upper_layer_increase_c"]}
    elif topic == "smoke_layer":
        result["criterion"] = {"quantity": "descent", "operator": ">=", "threshold": limits["smoke_layer"]["descent_m"],
                               "met": -delta >= limits["smoke_layer"]["descent_m"]}
        geometry = next(room for room in data["scenario"]["compartments"] if room["id"] == room_id)
        area = geometry["width_m"] * geometry["length_m"]
        result.update(floor_area_m2=area, upper_layer_volume_change_m3=-delta * area,
                      mean_net_volume_change_m3_s=-delta * area / duration)
    return result


def scoped_changes(context, scope, topics):
    data = context.get("measurement_snapshot")
    if data is None:
        return []
    from llm.question_scope import time_matches
    rooms = [room["id"] for room in data["scenario"]["compartments"]
             if scope["compartment_id"] in (None, room["id"])]
    result = []
    # Adjacent original samples only: filtering first would bridge excluded data.
    for before, after in zip(data["states"], data["states"][1:]):
        if not all(time_matches(state["time_s"], scope) for state in (before, after)):
            continue
        for room_id in rooms:
            for topic in topics:
                if topic in VARIABLES:
                    result.append(compare(data, before, after, room_id, topic))
    return result


def opening_comparison(context, scope):
    """Supplementary cross-opening evidence, never primary after-opening evidence."""
    data = context.get("measurement_snapshot")
    if data is None or scope["time_relation"] != "after" or scope["anchor_fact_id"] is None:
        return None
    facts = {fact["fact_id"]: fact for fact in context["scenario_facts"]}
    action = facts[scope["anchor_fact_id"]]
    related = [fact for fact in facts.values() if "ventilation_limited" in fact["knowledge_topics"]
               and fact.get("action_target") == action.get("action_target")
               and fact.get("action_time_s") == action["time_s"]
               and scope["compartment_id"] in (None, fact.get("compartment_id"))]
    if len(related) != 1:
        return None
    fact = related[0]
    before = [s for s in data["states"] if s["time_s"] < action["time_s"]]
    after = [s for s in data["states"] if s["time_s"] > action["time_s"]]
    if not before or not after:
        return None
    from .action_context import room_actions_between
    local = room_actions_between(data["scenario"], fact["compartment_id"], before[-1]["time_s"], after[0]["time_s"])
    if len(local) != 1 or local[0]["type"] != "open":
        return None
    changes = [compare(data, before[-1], after[0], fact["compartment_id"], topic, "opening_comparison")
               for topic in ("hrr", "temperature", "oxygen")]
    if any(change["sampling_gap"] for change in changes):
        return None
    return {"action_time_s": action["time_s"], "action_target": fact["action_target"],
            "related_fact_id": fact["fact_id"], "certainty": fact["certainty"], "causal": fact["causal"],
            "changes": changes}
