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

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_events"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main():

    scenario = load_json(SCENARIO_PATH)

    scenario_id = scenario["scenario_id"]

    state_files = sorted(
        STATES_DIR.glob(
            f"{scenario_id}_t*.json"
        )
    )

    if not state_files:
        print("ERROR: no se encontraron estados.")
        sys.exit(1)

    states = [
        load_json(path)
        for path in state_files
    ]

    events = analyze_timeline(
        states,
        scenario
    )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    # Elimina eventos generados anteriormente
    # para evitar resultados obsoletos.
    for old_file in OUTPUT_DIR.glob("*.json"):
        old_file.unlink()

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
        f"Estados procesados: {len(states)}"
    )

    print(
        f"Eventos generados: {len(events)}"
    )

    for event in events:
        print(
            f"- {event['event_type']} "
            f"(t={event['time_s']} s)"
        )


if __name__ == "__main__":
    main()