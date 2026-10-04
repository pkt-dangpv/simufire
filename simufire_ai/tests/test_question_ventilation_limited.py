import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

sys.path.insert(
    0,
    str(BASE_DIR)
)

from analyzer.fire_event_analyzer import (
    analyze_timeline
)

from analyzer.build_grounded_facts import (
    build_facts
)

from llm.plan_question import (
    select_topic_facts,
    select_knowledge
)

from llm.render_question_answer import (
    render_condition
)

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

KNOWLEDGE_PATH = (
    BASE_DIR
    / "knowledge"
    / "entries"
    / "VENTILATION_LIMITED_001.json"
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

    assert len(states) == 5

    events = analyze_timeline(
        states,
        scenario
    )

    facts = build_facts(
        scenario,
        events
    )

    # ---------------------------------------------
    # Simulación de una pregunta tipo CONDITION
    # ---------------------------------------------

    topics = [
        "ventilation_limited"
    ]

    fact_ids = select_topic_facts(
        facts=facts,
        topics=topics,
        include_limitations=False,
        intent="condition"
    )

    assert fact_ids == [
        "FACT_010"
    ], (
        "La pregunta sobre una condición "
        "ventilation_limited debe resolver "
        "exactamente FACT_010.\n"
        f"Obtenido: {fact_ids}"
    )

    facts_by_id = {
        fact["fact_id"]: fact
        for fact in facts
    }

    fact = facts_by_id[
        "FACT_010"
    ]

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
        fact["knowledge_topics"]
        == [
            "ventilation_limited"
        ]
    )

    # ---------------------------------------------
    # Recuperación de conocimiento
    # ---------------------------------------------

    knowledge_entry = load_json(
        KNOWLEDGE_PATH
    )

    knowledge_ids = select_knowledge(
        knowledge=[
            knowledge_entry
        ],
        topics=topics
    )

    assert knowledge_ids == [
        "VENTILATION_LIMITED_001"
    ], (
        "La condición debe recuperar "
        "VENTILATION_LIMITED_001.\n"
        f"Obtenido: {knowledge_ids}"
    )
    answer = render_condition(
        [fact]
    )

    answer_lower = (
        answer.lower()
    )

    assert (
        "evolución registrada es compatible"
        in answer_lower
    )

    assert (
        "limitado por ventilación"
        in answer_lower
    )

    assert (
        "certeza asignada "
        "a esta detección es moderada"
        in answer_lower
    )

    assert (
        "sí, el incendio estaba"
        not in answer_lower
    )

    assert (
        "demostrado"
        not in answer_lower
    )
    print(
        "OK: pregunta condition "
        "ventilation_limited"
    )

    print(
        "- intent: condition"
    )

    print(
        "- topic: ventilation_limited"
    )

    print(
        "- fact: FACT_010"
    )

    print(
        "- knowledge: "
        "VENTILATION_LIMITED_001"
    )

    print(
        "- certainty: moderate"
    )

    print(
        "- causal: False"
    )


if __name__ == "__main__":
    main()