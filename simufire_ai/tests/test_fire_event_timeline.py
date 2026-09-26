import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(BASE_DIR))

from analyzer.fire_event_analyzer import analyze_timeline


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

    state_files = sorted(
        STATES_DIR.glob("basic_room_001_t*.json")
    )

    states = [
        load_json(path)
        for path in state_files
    ]

    events = analyze_timeline(
        states,
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
        f"Se esperaban 4 eventos y se detectaron "
        f"{len(events)}: "
        f"{[e['event_type'] for e in events]}"
    )

    assert event_types == expected_types, (
        f"Eventos incorrectos.\n"
        f"Esperados: {expected_types}\n"
        f"Detectados: {event_types}"
    )

    print("OK: análisis temporal completo")
    print()

    for event in events:
        print(
            f"- {event['event_type']} "
            f"(t={event['time_s']} s)"
        )


if __name__ == "__main__":
    main()