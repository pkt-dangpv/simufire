import json
import sys
from pathlib import Path

if __package__:
    from .action_context import (
        action_key, action_compartments, matched_open_action, room_actions_between, sorted_actions,
    )
else:
    from action_context import (
        action_key, action_compartments, matched_open_action, room_actions_between, sorted_actions,
    )


BASE_DIR = Path(__file__).resolve().parents[1]

SCENARIO_PATH = (
    BASE_DIR
    / "scenarios"
    / "basic_room_001.json"
)

EVENTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_events"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "grounded_facts"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_events():
    events = []

    for path in sorted(EVENTS_DIR.glob("*.json")):
        events.append(load_json(path))

    return sorted(
        events,
        key=lambda event: event["time_s"]
    )


def find_evidence(event, variable):
    for item in event.get("evidence", []):
        if item["variable"] == variable:
            return item

    return None


def make_fact(
    scenario_id, fact_id, time_s, fact_type, statement, certainty, event_ids,
    source_variables=None, knowledge_topics=None, requires_fact_ids=None,
    causal=False, compartment_id=None, compartment_ids=None, action_target=None,
    action_time_s=None, evidence_interval_s=None,
):
    fact = {
        "schema_version": "0.1", "scenario_id": scenario_id, "fact_id": fact_id,
        "time_s": time_s, "fact_type": fact_type, "statement": statement,
        "certainty": certainty, "event_ids": list(event_ids),
        "source_variables": list(source_variables or []),
        "knowledge_topics": list(knowledge_topics or []),
        "requires_fact_ids": list(requires_fact_ids or []), "causal": causal,
    }
    for key, value in (
        ("compartment_id", compartment_id), ("compartment_ids", compartment_ids),
        ("action_target", action_target), ("action_time_s", action_time_s),
        ("evidence_interval_s", evidence_interval_s),
    ):
        if value is not None:
            fact[key] = value
    return fact


def build_facts(scenario, events):
    """Resolve dependencies from actual source objects, never FACT numbers.

    Keep the historical ordering of categories for the basic-room example.
    Limitations link observations in the same room and measurement interval;
    historical events without intervals stop at the next local action.
    """
    scenario_id = scenario["scenario_id"]
    rooms = {room["id"] for room in scenario.get("compartments", [])}
    event_priority = {
        "ventilation_increase": 10, "hrr_increase": 20, "smoke_layer_descent": 30,
        "temperature_increase": 40, "ventilation_limited": 50,
    }
    events = sorted(events, key=lambda e: (
        e["time_s"], event_priority.get(e["event_type"], 999), e["event_id"],
    ))
    seen = set()
    for event in events:
        if event["scenario_id"] != scenario_id:
            raise ValueError(f"Evento de otro escenario: {event['event_id']}")
        if event["event_id"] in seen:
            raise ValueError(f"Evento duplicado: {event['event_id']}")
        seen.add(event["event_id"])
        if "compartment_id" in event and event["compartment_id"] not in rooms:
            raise ValueError(f"Compartimento desconocido: {event['compartment_id']}")
        interval = event.get("evidence_interval_s")
        if interval is not None and not (
            interval["start"] < interval["end"]
            and interval["start"] <= event["time_s"] <= interval["end"]
        ):
            raise ValueError(f"Intervalo de evidencia no válido: {event['event_id']}")

    facts = []
    actions = sorted_actions(scenario)
    action_facts = {}
    ventilation = []
    observations = []

    def add_fact(**values):
        fact = make_fact(
            scenario_id=scenario_id, fact_id=f"FACT_{len(facts) + 1:03d}", **values,
        )
        facts.append(fact)
        return fact

    def provenance(event, action=None):
        result = {}
        if "compartment_id" in event:
            result["compartment_id"] = event["compartment_id"]
        if "evidence_interval_s" in event:
            result["evidence_interval_s"] = dict(event["evidence_interval_s"])
        if action is not None:
            result.update(action_target=action["target"], action_time_s=action["time_s"])
        return result

    for action in actions:
        if action["type"] != "open":
            continue
        compartments = action_compartments(scenario, action)
        if not compartments:
            raise ValueError(f"Apertura sin compartimento conocido: {action['target']}")
        action_facts[action_key(action)] = add_fact(
            time_s=action["time_s"], fact_type="action",
            statement=f"El elemento {action['target']} se abrió en t={action['time_s']} s.",
            certainty="certain", event_ids=[], compartment_ids=list(compartments),
            action_target=action["target"], action_time_s=action["time_s"],
        )

    # Emit observed changes before limitations, oxygen and conditions to keep
    # FACT_001...FACT_010 compatible for the existing single-room example.
    measured = {
        "hrr_increase": ("hrr_kw", "hrr", "El HRR aumentó de {previous} a {value} kW."),
        "temperature_increase": (
            "upper_layer.temperature_c", "temperature",
            "La temperatura de la capa superior aumentó de {previous} a {value} °C.",
        ),
        "smoke_layer_descent": (
            "interface_height_m", "smoke_layer",
            "La interfaz entre capas descendió de {previous} a {value} m.",
        ),
    }
    for event in events:
        event_type = event["event_type"]
        if event_type in measured:
            variable, topic, template = measured[event_type]
            evidence = find_evidence(event, variable)
            if evidence is None or "previous_value" not in evidence:
                continue
            fact = add_fact(
                time_s=event["time_s"], fact_type="observation",
                statement=template.format(previous=evidence["previous_value"], value=evidence["value"]),
                certainty="high", event_ids=[event["event_id"]],
                source_variables=[variable], knowledge_topics=[topic], **provenance(event),
            )
            observations.append((event, fact))
        elif event_type == "ventilation_increase":
            action = matched_open_action(scenario, event)
            statement = "El Fire Event Analyzer detectó un aumento de ventilación"
            if action is not None:
                statement += f" asociado a la apertura de {action['target']}"
            dependency = action_facts[action_key(action)] if action is not None else None
            fact = add_fact(
                time_s=event["time_s"], fact_type="association", statement=statement + ".",
                certainty="high", event_ids=[event["event_id"]],
                source_variables=[item["variable"] for item in event.get("evidence", [])],
                knowledge_topics=["ventilation"],
                requires_fact_ids=[dependency["fact_id"]] if dependency else [],
                **provenance(event, action),
            )
            ventilation.append((event, fact, action))

    def preceding_ventilation(effect):
        room_id = effect.get("compartment_id")
        if room_id is None:
            return None
        candidates = []
        for event, fact, action in ventilation:
            if action is None or event.get("compartment_id") != room_id:
                continue
            if action["time_s"] > effect["time_s"]:
                continue
            interval = effect.get("evidence_interval_s")
            if interval and not interval["start"] < action["time_s"] <= interval["end"]:
                continue
            if room_actions_between(scenario, room_id, action["time_s"], effect["time_s"]):
                continue
            candidates.append((event, fact, action))
        if not candidates:
            return None
        latest_time = max(item[2]["time_s"] for item in candidates)
        latest = [item for item in candidates if item[2]["time_s"] == latest_time]
        return latest[0] if len(latest) == 1 else None

    # Causal limitations are paired per observation, not by a global set of
    # event types. References retain the actual action/association/observation.
    for effect_type in ("hrr_increase", "temperature_increase"):
        for effect, observation in observations:
            if effect["event_type"] != effect_type:
                continue
            matched = preceding_ventilation(effect)
            if matched is None:
                continue
            event, association, action = matched
            opening = next(o for o in scenario["openings"] if o["id"] == action["target"])
            label = {"door": "la puerta", "window": "la ventana"}.get(
                opening["type"], f"{action['target']}",
            )
            if effect_type == "hrr_increase":
                statement = (
                    "Los datos disponibles no son suficientes para afirmar que "
                    f"la apertura de {label} causó por sí sola el aumento del HRR."
                )
            else:
                statement = (
                    "Los datos disponibles no son suficientes para afirmar una "
                    f"relación causal directa entre la apertura de {label} y el aumento de temperatura."
                )
            add_fact(
                time_s=effect["time_s"], fact_type="limitation", statement=statement,
                certainty="certain", event_ids=[event["event_id"], effect["event_id"]],
                source_variables=list(dict.fromkeys(
                    association["source_variables"] + observation["source_variables"],
                )), knowledge_topics=["ventilation", observation["knowledge_topics"][0]],
                requires_fact_ids=[
                    action_facts[action_key(action)]["fact_id"], association["fact_id"], observation["fact_id"],
                ], **provenance(effect, action),
            )

    for event, observation in observations:
        if event["event_type"] == "smoke_layer_descent":
            add_fact(
                time_s=event["time_s"], fact_type="limitation",
                statement=(
                    "Se ha detectado un descenso de la interfaz entre capas, "
                    "pero los datos disponibles no permiten atribuirle una causa física concreta."
                ), certainty="certain", event_ids=[event["event_id"]],
                source_variables=observation["source_variables"], knowledge_topics=["smoke_layer"],
                requires_fact_ids=[observation["fact_id"]], **provenance(event),
            )

    # Every ventilation event keeps its own oxygen observation and dependency.
    for event, association, action in ventilation:
        evidence = find_evidence(event, "upper_layer.o2_percent")
        if evidence is None or "previous_value" not in evidence:
            continue
        add_fact(
            time_s=event["time_s"], fact_type="observation",
            statement=(f"El O₂ de la capa superior aumentó de {evidence['previous_value']} "
                       f"a {evidence['value']} %."), certainty="high",
            event_ids=[event["event_id"]], source_variables=["upper_layer.o2_percent"],
            knowledge_topics=["oxygen"], requires_fact_ids=[association["fact_id"]],
            **provenance(event, action),
        )

    for event in events:
        if event["event_type"] != "ventilation_limited":
            continue
        action = matched_open_action(scenario, event)
        statement = (
            "El Fire Event Analyzer detectó un patrón temporal compatible con "
            "una condición de incendio limitado por ventilación"
        )
        if action is not None:
            statement += f" antes de la apertura de {action['target']}"
        add_fact(
            time_s=event["time_s"], fact_type="association", statement=statement + ".",
            certainty="moderate", event_ids=[event["event_id"]],
            source_variables=[item["variable"] for item in event.get("evidence", [])],
            knowledge_topics=["ventilation_limited"], **provenance(event, action),
        )
    return facts


def main():

    scenario = load_json(
        SCENARIO_PATH
    )

    events = load_events()

    if not events:
        print(
            "ERROR: no hay eventos generados."
        )
        sys.exit(1)

    facts = build_facts(
        scenario,
        events
    )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    for old_file in OUTPUT_DIR.glob(
        "*.json"
    ):
        old_file.unlink()

    for fact in facts:

        output_path = (
            OUTPUT_DIR
            / f"{fact['fact_id']}.json"
        )

        with output_path.open(
            "w",
            encoding="utf-8"
        ) as f:

            json.dump(
                fact,
                f,
                indent=2,
                ensure_ascii=False
            )

    print(
        f"Hechos generados: {len(facts)}"
    )

    for fact in facts:

        topics = ", ".join(
            fact["knowledge_topics"]
        )

        if not topics:
            topics = "-"

        print(
            f"- {fact['fact_id']} "
            f"[{fact['fact_type']}] "
            f"[{topics}]: "
            f"{fact['statement']}"
        )


if __name__ == "__main__":
    main()
