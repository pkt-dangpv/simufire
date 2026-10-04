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
    / "analysis_context"
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

    states = sorted(
        states,
        key=lambda state: state["time_s"]
    )

    events = analyze_timeline(
        states,
        scenario
    )

    events = sorted(
        events,
        key=lambda event: event["time_s"]
    )

    first_state = states[0]
    final_state = states[-1]

    context = {
        "schema_version": "0.1",

        "scenario": {
            "scenario_id": scenario_id,
            "name": scenario["name"],
            "description": scenario.get(
                "description",
                ""
            )
        },

        "timeline": {
            "start_time_s": first_state["time_s"],
            "end_time_s": final_state["time_s"],
            "states_available": len(states)
        },

        "actions": scenario.get(
            "actions",
            []
        ),

        "detected_events": events,

        "final_state": final_state,

        "analysis_rules": {
            "physical_engine_is_authoritative": True,
            "do_not_invent_missing_data": True,
            "uncertain_phenomena_must_be_qualified": True
        }
    }

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    output_path = (
        OUTPUT_DIR
        / f"{scenario_id}_context.json"
    )

    with output_path.open(
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            context,
            f,
            indent=2,
            ensure_ascii=False
        )

    print(
        f"Contexto generado: {output_path.name}"
    )

    print(
        f"Estados utilizados: {len(states)}"
    )

    print(
        f"Eventos incluidos: {len(events)}"
    )

    for event in events:
        print(
            f"- {event['event_type']} "
            f"(t={event['time_s']} s)"
        )


if __name__ == "__main__":
    main()