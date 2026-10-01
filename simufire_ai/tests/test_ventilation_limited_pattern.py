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
    / "ventilation_limited_states"
)


def load_json(path: Path):
    with path.open(
        "r",
        encoding="utf-8"
    ) as f:
        return json.load(f)


def main():

    scenario = load_json(
        SCENARIO_PATH
    )

    state_files = sorted(
        STATES_DIR.glob("vl_case_t*.json")
    )

    states = [
        load_json(path)
        for path in state_files
    ]

    assert len(states) == 5, (
        "Se esperaban 5 estados para "
        "el caso ventilation_limited y "
        f"se encontraron {len(states)}"
    )

    events = analyze_timeline(
        states,
        scenario
    )

    ventilation_limited_events = [
        event
        for event in events
        if (
            event["event_type"]
            == "ventilation_limited"
        )
    ]

    assert len(
        ventilation_limited_events
    ) == 1, (
        "Se esperaba exactamente un evento "
        "ventilation_limited y se detectaron "
        f"{len(ventilation_limited_events)}.\n"
        "Eventos detectados: "
        f"{[e['event_type'] for e in events]}"
    )

    event = ventilation_limited_events[0]

    # La condición se considera presente
    # justo antes de introducir ventilación.
    assert event["time_s"] == 179, (
        "El evento ventilation_limited "
        "debe situarse en t=179 s, "
        "último estado previo a la apertura."
    )

    assert (
        event["compartment_id"]
        == "room_01"
    )

    # No queremos que el detector afirme
    # una causa física directa.
    assert (
        event.get("cause")
        == "temporal_pattern"
    ), (
        "El evento debe describirse como "
        "un patrón temporal, no como una "
        "relación causal demostrada."
    )

    evidence = event["evidence"]

    variables = [
        item["variable"]
        for item in evidence
    ]

    required_variables = {
        "pre_open.upper_layer.o2_percent",
        "pre_open.hrr_kw",
        "pre_open.upper_layer.temperature_c",
        "post_open.upper_layer.o2_percent",
        "post_open.hrr_kw"
    }

    assert required_variables.issubset(
        set(variables)
    ), (
        "Faltan variables necesarias "
        "para justificar la detección.\n"
        f"Esperadas: {sorted(required_variables)}\n"
        f"Detectadas: {sorted(set(variables))}"
    )

    print(
        "OK: patrón ventilation_limited "
        "detectado correctamente"
    )

    print(
        f"- tiempo: {event['time_s']} s"
    )

    print(
        f"- compartimento: "
        f"{event['compartment_id']}"
    )

    print(
        f"- confianza: "
        f"{event['confidence']}"
    )


if __name__ == "__main__":
    main()