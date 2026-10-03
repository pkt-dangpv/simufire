"""Scenario topology and action identity, without physical inference."""


def action_key(action):
    return action["time_s"], action["type"], action["target"]


def sorted_actions(scenario):
    actions = sorted(scenario.get("actions", []), key=action_key)
    keys = [action_key(action) for action in actions]
    if len(set(keys)) != len(keys):
        raise ValueError("Acción duplicada en el escenario")
    return actions


def action_compartments(scenario, action):
    rooms = {room["id"] for room in scenario.get("compartments", [])}
    openings = [o for o in scenario.get("openings", []) if o["id"] == action["target"]]
    if len(openings) > 1:
        raise ValueError(f"Apertura duplicada: {action['target']}")
    if openings:
        opening = openings[0]
        endpoints = {opening["from"], opening["to"]}
        if endpoints - rooms - {"outside"}:
            raise ValueError(f"Compartimento desconocido en {opening['id']}")
        return tuple(sorted(endpoints & rooms))
    fires = [f for f in scenario.get("fires", []) if f["id"] == action["target"]]
    if fires:
        return tuple(sorted({f["compartment"] for f in fires} & rooms))
    return ()


def room_actions_between(scenario, room_id, start_time, end_time):
    return [
        action for action in sorted_actions(scenario)
        if start_time < action["time_s"] <= end_time
        and room_id in action_compartments(scenario, action)
    ]


def matched_open_action(scenario, event):
    """Resolve explicit provenance or conservatively read historical events."""
    room_id = event.get("compartment_id")
    if room_id is None:
        return None
    candidates = [
        action for action in sorted_actions(scenario)
        if action["type"] == "open"
        and room_id in action_compartments(scenario, action)
    ]
    explicit = "action_target" in event or "action_time_s" in event
    if explicit:
        candidates = [
            action for action in candidates
            if action["target"] == event.get("action_target")
            and action["time_s"] == event.get("action_time_s")
        ]
    elif event["event_type"] == "ventilation_increase":
        cause = event.get("cause", "")
        target = cause[:-len("_opened")] if cause.endswith("_opened") else None
        candidates = [
            action for action in candidates
            if action["target"] == target and action["time_s"] == event["time_s"]
        ]
    else:
        candidates = [a for a in candidates if a["time_s"] > event["time_s"]]
        if candidates:
            earliest = candidates[0]["time_s"]
            candidates = [a for a in candidates if a["time_s"] == earliest]

    if len(candidates) != 1:
        if explicit:
            raise ValueError(f"Acción de origen no válida para {event['event_id']}")
        return None
    action = candidates[0]
    interval = event.get("evidence_interval_s")
    valid_time = (
        action["time_s"] == event["time_s"]
        if event["event_type"] == "ventilation_increase"
        else action["time_s"] > event["time_s"]
    )
    if interval:
        valid_time = valid_time and interval["start"] < action["time_s"] <= interval["end"]
    if not valid_time:
        if explicit:
            raise ValueError(f"Intervalo de acción no válido para {event['event_id']}")
        return None
    return action
