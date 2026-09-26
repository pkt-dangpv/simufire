import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(BASE_DIR))

from analyzer.fire_event_analyzer import analyze


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


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main():

    scenario = load_json(SCENARIO_PATH)

    before = load_json(
        STATES_DIR / "basic_room_001_t179.json"
    )

    after = load_json(
        STATES_DIR / "basic_room_001_t195.json"
    )

    events = analyze(
        before,
        after,
        scenario
    )

    event_types = {
        event["event_type"]
        for event in events
    }

    expected_types = {
        "hrr_increase",
        "temperature_increase",
        "smoke_layer_descent",
        "ventilation_increase"
    }

    assert len(events) == 4, (
        f"Se esperaban 4 eventos y se detectaron {len(events)}"
    )

    assert event_types == expected_types, (
        f"Eventos incorrectos.\n"
        f"Esperados: {expected_types}\n"
        f"Detectados: {event_types}"
    )

    ventilation_event = next(
        event
        for event in events
        if event["event_type"] == "ventilation_increase"
    )

    assert ventilation_event["time_s"] == 180

    assert ventilation_event["cause"] == "door_01_opened"

    print("OK: Fire Event Analyzer")
    print("Eventos detectados correctamente:")

    for event in events:
        print(
            f"- {event['event_type']} "
            f"(t={event['time_s']} s)"
        )


if __name__ == "__main__":
    main()