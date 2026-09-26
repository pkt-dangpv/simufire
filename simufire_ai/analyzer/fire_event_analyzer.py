import json
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

SCENARIO_PATH = (
    BASE_DIR
    / "scenarios"
    / "basic_room_001.json"
)

STATES_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "simulation_states"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_events"
)

CONFIG_PATH = (
    BASE_DIR
    / "config"
    / "analyzer_thresholds.json"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def find_action_between(scenario, start_time, end_time):
    actions = []

    for action in scenario.get("actions", []):
        if start_time < action["time_s"] <= end_time:
            actions.append(action)

    return actions


def get_compartment(state, compartment_id):
    for compartment in state["compartments"]:
        if compartment["id"] == compartment_id:
            return compartment

    return None


def analyze(before, after, scenario, thresholds=None):

    if thresholds is None:
        thresholds = load_json(CONFIG_PATH)

    events = []

    start_time = before["time_s"]
    end_time = after["time_s"]

    actions = find_action_between(
        scenario,
        start_time,
        end_time
    )

    hrr_increase_ratio = (
        thresholds["hrr"]["increase_ratio"]
    )

    temperature_increase_c = (
        thresholds["temperature"]
        ["upper_layer_increase_c"]
    )

    smoke_descent_m = (
        thresholds["smoke_layer"]["descent_m"]
    )

    minimum_o2_increase = (
        thresholds["ventilation"]
        ["minimum_o2_increase_percent"]
    )

    for before_room in before["compartments"]:

        room_id = before_room["id"]

        after_room = get_compartment(
            after,
            room_id
        )

        if after_room is None:
            continue

        hrr_before = before_room["hrr_kw"]
        hrr_after = after_room["hrr_kw"]

        temp_before = (
            before_room["upper_layer"]
            ["temperature_c"]
        )

        temp_after = (
            after_room["upper_layer"]
            ["temperature_c"]
        )

        o2_before = (
            before_room["upper_layer"]
            ["o2_percent"]
        )

        o2_after = (
            after_room["upper_layer"]
            ["o2_percent"]
        )

        interface_before = (
            before_room["interface_height_m"]
        )

        interface_after = (
            after_room["interface_height_m"]
        )

        # -------------------------------------------------
        # 1. Aumento significativo de HRR
        # -------------------------------------------------

        if hrr_after > hrr_before * hrr_increase_ratio:

            events.append({
                "schema_version": "0.1",
                "scenario_id": scenario["scenario_id"],
                "event_id": (
                    f"hrr_increase_{int(end_time)}_{room_id}"
                ),
                "time_s": end_time,
                "event_type": "hrr_increase",
                "compartment_id": room_id,
                "cause": "detected_change",
                "confidence": 0.95,
                "evidence": [
                    {
                        "variable": "hrr_kw",
                        "previous_value": hrr_before,
                        "value": hrr_after,
                        "unit": "kW",
                        "description":
                            "Aumento significativo del HRR"
                    }
                ]
            })

        # -------------------------------------------------
        # 2. Aumento significativo de temperatura
        # -------------------------------------------------

        if temp_after - temp_before >= temperature_increase_c:

            events.append({
                "schema_version": "0.1",
                "scenario_id": scenario["scenario_id"],
                "event_id": (
                    f"temperature_increase_"
                    f"{int(end_time)}_{room_id}"
                ),
                "time_s": end_time,
                "event_type": "temperature_increase",
                "compartment_id": room_id,
                "cause": "detected_change",
                "confidence": 0.90,
                "evidence": [
                    {
                        "variable":
                            "upper_layer.temperature_c",
                        "previous_value": temp_before,
                        "value": temp_after,
                        "unit": "C",
                        "description":
                            "Aumento de temperatura "
                            "de la capa superior"
                    }
                ]
            })

        # -------------------------------------------------
        # 3. Descenso de la interfaz de humo
        # -------------------------------------------------

        if (
            interface_before - interface_after
            >= smoke_descent_m
        ):

            events.append({
                "schema_version": "0.1",
                "scenario_id": scenario["scenario_id"],
                "event_id": (
                    f"smoke_layer_descent_"
                    f"{int(end_time)}_{room_id}"
                ),
                "time_s": end_time,
                "event_type": "smoke_layer_descent",
                "compartment_id": room_id,
                "cause": "detected_change",
                "confidence": 0.95,
                "evidence": [
                    {
                        "variable": "interface_height_m",
                        "previous_value": interface_before,
                        "value": interface_after,
                        "unit": "m",
                        "description":
                            "Descenso de la interfaz "
                            "entre capas"
                    }
                ]
            })

        # -------------------------------------------------
        # 4. Aumento de ventilacion tras una apertura
        # -------------------------------------------------

        for action in actions:

            if (
                action["type"] == "open"
                and (
                    o2_after - o2_before
                    >= minimum_o2_increase
                )
            ):

                events.append({
                    "schema_version": "0.1",
                    "scenario_id": scenario["scenario_id"],
                    "event_id": (
                        f"ventilation_increase_"
                        f"{int(action['time_s'])}_{room_id}"
                    ),
                    "time_s": action["time_s"],
                    "event_type": "ventilation_increase",
                    "compartment_id": room_id,
                    "cause": (
                        f"{action['target']}_opened"
                    ),
                    "confidence": 0.95,
                    "evidence": [
                        {
                            "variable":
                                "upper_layer.o2_percent",
                            "previous_value": o2_before,
                            "value": o2_after,
                            "unit": "%",
                            "description":
                                "Aumento de oxigeno "
                                "tras la apertura"
                        },
                        {
                            "variable": "hrr_kw",
                            "previous_value": hrr_before,
                            "value": hrr_after,
                            "unit": "kW",
                            "description":
                                "Cambio del HRR "
                                "tras la apertura"
                        }
                    ]
                })

    return events

def analyze_timeline(states, scenario, thresholds=None):

    if thresholds is None:
        thresholds = load_json(CONFIG_PATH)

    if len(states) < 2:
        return []

    states = sorted(
        states,
        key=lambda state: state["time_s"]
    )

    max_gap_s = (
        thresholds["timeline"]["max_gap_s"]
    )

    all_events = []

    for index in range(len(states) - 1):

        before = states[index]
        after = states[index + 1]

        gap_s = (
            after["time_s"]
            - before["time_s"]
        )

        if gap_s <= 0:
            continue

        if gap_s > max_gap_s:
            continue

        events = analyze(
            before,
            after,
            scenario,
            thresholds
        )

        all_events.extend(events)

    return all_events

def main():

    scenario = load_json(SCENARIO_PATH)

    before = load_json(
        STATES_DIR / "basic_room_001_t179.json"
    )

    after = load_json(
        STATES_DIR / "basic_room_001_t195.json"
    )

    thresholds = load_json(CONFIG_PATH)

    events = analyze(
        before,
        after,
        scenario,
        thresholds
    )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    print(
        f"Eventos detectados: {len(events)}"
    )

    for event in events:

        output_path = (
            OUTPUT_DIR
            / f"{event['event_id']}.json"
        )

        with output_path.open(
            "w",
            encoding="utf-8"
        ) as f:

            json.dump(
                event,
                f,
                indent=2,
                ensure_ascii=False
            )

        print(
            f"- {event['event_type']}"
            f" -> {output_path.name}"
        )


if __name__ == "__main__":
    main()