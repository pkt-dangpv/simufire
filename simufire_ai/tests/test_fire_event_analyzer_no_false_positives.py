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
        STATES_DIR / "basic_room_001_t200.json"
    )

    after = load_json(
        STATES_DIR / "basic_room_001_t210.json"
    )

    events = analyze(
        before,
        after,
        scenario
    )

    assert len(events) == 0, (
        f"Se esperaban 0 eventos y se detectaron {len(events)}: "
        f"{[event['event_type'] for event in events]}"
    )

    print("OK: no se detectaron falsos positivos")


if __name__ == "__main__":
    main()