"""Describe opportunities to run existing detectors, without new physical rules.

An evaluable window means input requirements were met, not that the phenomenon
was absent. Predicate/threshold decisions remain in fire_event_analyzer.
"""

from .action_context import action_compartments, action_key, room_actions_between, sorted_actions
from .fire_event_analyzer import get_contiguous_history


SUPPORTED_TOPICS = ("hrr", "temperature", "smoke_layer", "oxygen", "ventilation", "ventilation_limited")


def build_assessment_coverage(scenario, states, thresholds):
    states = sorted(states, key=lambda state: state["time_s"])
    max_gap = thresholds["timeline"]["max_gap_s"]
    windows = []

    def add(topic, room, reference, start, end, reason=None):
        windows.append({
            "topic": topic, "compartment_id": room, "reference_time_s": reference,
            "start_time_s": start, "end_time_s": end,
            "evaluable": reason is None, "reason": reason or "requirements_met",
        })

    for before, after in zip(states, states[1:]):
        for room in before["compartments"]:
            room_id = room["id"]
            start, end = before["time_s"], after["time_s"]
            gap_reason = "sampling_gap" if end - start > max_gap else None
            for topic in ("temperature", "smoke_layer", "hrr"):
                reason = gap_reason
                add(topic, room_id, end, start, end, reason)
            actions = room_actions_between(scenario, room_id, start, end)
            action = actions[0] if len(actions) == 1 and actions[0]["type"] == "open" else None
            reason = gap_reason
            if action is None:
                reason = reason or ("ambiguous_interventions" if len(actions) > 1 else "no_opening_window")
            # Oxygen observations are generated only from ventilation events.
            for topic in ("ventilation", "oxygen"):
                reference = action["time_s"] if topic == "ventilation" and action else end
                add(topic, room_id, reference, start, end, reason)

    for action in sorted_actions(scenario):
        if action["type"] != "open":
            continue
        before_indices = [i for i, state in enumerate(states) if state["time_s"] < action["time_s"]]
        post_states = [state for state in states if state["time_s"] > action["time_s"]]
        for room_id in action_compartments(scenario, action):
            if not before_indices or not post_states:
                # This window cannot be assessed; reference it to the requested opening.
                add("ventilation_limited", room_id, action["time_s"], states[0]["time_s"],
                    states[-1]["time_s"], "missing_pre_or_post_samples")
                continue
            pre_index = before_indices[-1]
            pre, post = states[pre_index], post_states[0]
            history = get_contiguous_history(states, pre_index,
                thresholds["ventilation_limited"]["minimum_pre_states"], max_gap)
            local = room_actions_between(scenario, room_id, pre["time_s"], post["time_s"])
            reason = None
            if post["time_s"] - pre["time_s"] > max_gap:
                reason = "sampling_gap"
            elif not history:
                reason = "insufficient_pre_history"
            elif len(local) != 1 or action_key(local[0]) != action_key(action):
                reason = "ambiguous_interventions"
            elif next(room for room in history[0]["compartments"] if room["id"] == room_id)["hrr_kw"] <= 0:
                reason = "zero_hrr_baseline"
            elif next(room for room in pre["compartments"] if room["id"] == room_id)["hrr_kw"] <= 0:
                reason = "zero_hrr_baseline"
            add("ventilation_limited", room_id, pre["time_s"],
                history[0]["time_s"] if history else pre["time_s"], post["time_s"], reason)

    return {
        "schema_version": "0.1",
        "compartments": [{"id": room["id"], "name": room.get("name", room["id"])}
                         for room in scenario["compartments"]],
        "state_times_s": [state["time_s"] for state in states],
        "supported_topics": list(SUPPORTED_TOPICS),
        "windows": windows,
    }
