import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

sys.path.insert(0, str(BASE_DIR))

from analyzer.fire_event_analyzer import analyze_timeline
from analyzer.build_grounded_facts import build_facts


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
        STATES_DIR.glob(
            "vl_case_t*.json"
        )
    )

    states = [
        load_json(path)
        for path in state_files
    ]

    assert len(states) == 5, (
        "Se esperaban 5 estados "
        "del fixture ventilation_limited."
    )

    events = analyze_timeline(
        states,
        scenario
    )

    pattern_events = [
        event
        for event in events
        if (
            event["event_type"]
            == "ventilation_limited"
        )
    ]

    assert len(pattern_events) == 1, (
        "El fixture debe producir "
        "exactamente un evento "
        "ventilation_limited."
    )

    facts = build_facts(
        scenario,
        events
    )

    ventilation_limited_facts = [
        fact
        for fact in facts
        if (
            "ventilation_limited"
            in fact[
                "knowledge_topics"
            ]
        )
    ]

    assert (
        len(
            ventilation_limited_facts
        )
        == 1
    ), (
        "Se esperaba exactamente un "
        "Grounded Fact para "
        "ventilation_limited y se "
        f"obtuvieron "
        f"{len(ventilation_limited_facts)}."
    )

    fact = (
        ventilation_limited_facts[0]
    )

    assert (
        fact["fact_id"]
        == "FACT_010"
    ), (
        "El nuevo hecho debe conservar "
        "los FACT_001...FACT_009 "
        "existentes y usar FACT_010."
    )

    assert (
        fact["fact_type"]
        == "association"
    )

    assert (
        fact["certainty"]
        == "moderate"
    )

    assert fact["causal"] is False

    assert (
        "ventilation_limited"
        in fact["knowledge_topics"]
    )

    assert (
        pattern_events[0][
            "event_id"
        ]
        in fact["event_ids"]
    )

    statement = (
        fact["statement"].lower()
    )

    assert "evolución registrada" in statement

    assert "compatible" in statement

    assert (
        "limitado por ventilación"
        in statement
    )

    assert "causó" not in statement

    required_variables = {
        "pre_open.upper_layer.o2_percent",
        "pre_open.hrr_kw",
        "pre_open.upper_layer.temperature_c",
        "post_open.upper_layer.o2_percent",
        "post_open.hrr_kw"
    }

    assert (
        required_variables
        .issubset(
            set(
                fact[
                    "source_variables"
                ]
            )
        )
    ), (
        "El Grounded Fact no conserva "
        "todas las variables que sustentan "
        "el patrón temporal."
    )

    print(
        "OK: ventilation_limited "
        "se convierte en Grounded Fact"
    )

    print(
        f"- {fact['fact_id']}"
    )

    print(
        f"- tipo: {fact['fact_type']}"
    )

    print(
        f"- certeza: {fact['certainty']}"
    )

    print(
        f"- causal: {fact['causal']}"
    )

    print(
        f"- {fact['statement']}"
    )


if __name__ == "__main__":
    main()