import argparse
import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

CONTEXT_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_context"
    / "basic_room_001_instructor.json"
)

QUESTION_PLANS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "question_plans"
)

FACTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "grounded_facts"
)

MANUAL_EVENTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "fire_events"
)

GENERATED_EVENTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_events"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "question_answers"
)


TOPIC_EVIDENCE_KEYWORDS = {
    "hrr": [
        "hrr"
    ],
    "temperature": [
        "temperature",
        "temp"
    ],
    "smoke_layer": [
        "interface",
        "smoke_layer"
    ],
    "oxygen": [
        "oxygen",
        "o2"
    ]
}


def load_json(path: Path):
    with path.open(
        "r",
        encoding="utf-8"
    ) as f:
        return json.load(f)


def load_json_directory(path: Path):
    items = {}

    if not path.exists():
        return items

    for file_path in sorted(
        path.glob("*.json")
    ):
        data = load_json(file_path)

        if "event_id" in data:
            items[data["event_id"]] = data

    return items


def load_facts():
    facts = {}

    for path in sorted(
        FACTS_DIR.glob("*.json")
    ):
        fact = load_json(path)

        facts[fact["fact_id"]] = fact

    return facts


def load_events():
    events = {}

    events.update(
        load_json_directory(
            MANUAL_EVENTS_DIR
        )
    )

    events.update(
        load_json_directory(
            GENERATED_EVENTS_DIR
        )
    )

    return events


def format_number(value):
    if isinstance(value, int):
        return str(value)

    if isinstance(value, float):
        if value.is_integer():
            return str(int(value))

        return (
            f"{value:.3f}"
            .rstrip("0")
            .rstrip(".")
        )

    return str(value)


def evidence_matches_topic(
    variable,
    topic
):
    variable_lower = variable.lower()

    keywords = (
        TOPIC_EVIDENCE_KEYWORDS
        .get(topic, [])
    )

    return any(
        keyword in variable_lower
        for keyword in keywords
    )


def find_numeric_change(
    fact,
    topics,
    events_by_id
):
    for event_id in fact.get(
        "event_ids",
        []
    ):
        event = events_by_id.get(
            event_id
        )

        if not event:
            continue

        for evidence in event.get(
            "evidence",
            []
        ):
            if (
                "previous_value"
                not in evidence
            ):
                continue

            if "value" not in evidence:
                continue

            previous = evidence[
                "previous_value"
            ]

            current = evidence[
                "value"
            ]

            if not isinstance(
                previous,
                (int, float)
            ):
                continue

            if not isinstance(
                current,
                (int, float)
            ):
                continue

            variable = evidence.get(
                "variable",
                ""
            )

            matched_topic = None

            for topic in topics:
                if evidence_matches_topic(
                    variable,
                    topic
                ):
                    matched_topic = topic
                    break

            if matched_topic is None:
                continue

            return {
                "topic": matched_topic,
                "previous": previous,
                "current": current,
                "delta": current - previous,
                "unit": evidence.get(
                    "unit",
                    ""
                ),
                "variable": variable
            }

    return None


def render_change(change):
    delta = change["delta"]
    unit = change["unit"]
    topic = change.get("topic")

    if topic == "temperature":
        if unit.lower() in [
            "c",
            "°c",
            "celsius",
            "degc"
        ]:
            unit = "°C"

    magnitude = abs(delta)

    value_text = format_number(
        magnitude
    )

    if unit:
        value_text += f" {unit}"

    if delta > 0:
        return (
            f"Esto supone un aumento "
            f"de {value_text}."
        )

    if delta < 0:
        return (
            f"Esto supone una disminución "
            f"de {value_text}."
        )

    return "No se produjo variación."


def render_timeline(facts):
    facts = sorted(
        facts,
        key=lambda fact: (
            fact["time_s"],
            fact["fact_id"]
        )
    )

    groups = {}

    for fact in facts:
        time_s = fact["time_s"]

        groups.setdefault(
            time_s,
            []
        )

        groups[time_s].append(
            fact
        )

    paragraphs = []

    for time_s in sorted(groups):
        statements = []

        time_text = (
            f" en t={format_number(time_s)} s"
        )

        for fact in groups[time_s]:
            statement = fact[
                "statement"
            ]

            statement = statement.replace(
                time_text,
                ""
            )

            statements.append(
                statement
            )

        paragraphs.append(
            f"En t={format_number(time_s)} s: "
            + " ".join(statements)
        )

    return "\n\n".join(
        paragraphs
    )


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--question-id",
        default="question_001",
        help="Identificador de la pregunta a responder"
    )

    args = parser.parse_args()

    question_id = (
        args.question_id.strip()
    )

    if not question_id:
        print(
            "ERROR: question_id está vacío."
        )
        sys.exit(1)

    context = load_json(
        CONTEXT_PATH
    )

    scenario_id = context[
        "scenario_id"
    ]

    plan_path = (
        QUESTION_PLANS_DIR
        / f"{scenario_id}_{question_id}.json"
    )

    if not plan_path.exists():
        print(
            "ERROR: no existe el plan:"
        )
        print(
            f"- {plan_path}"
        )
        sys.exit(1)

    plan = load_json(
        plan_path
    )

    facts_by_id = load_facts()
    events_by_id = load_events()

    knowledge_by_id = {
        item["knowledge_id"]: item
        for item in context[
            "technical_knowledge"
        ]
    }

    selected_facts = []

    for fact_id in plan[
        "resolved_fact_ids"
    ]:
        if fact_id not in facts_by_id:
            print(
                f"ERROR: no existe {fact_id}"
            )
            sys.exit(1)

        selected_facts.append(
            facts_by_id[fact_id]
        )

    selected_knowledge = []

    for knowledge_id in plan[
        "resolved_knowledge_ids"
    ]:
        if (
            knowledge_id
            not in knowledge_by_id
        ):
            print(
                f"ERROR: no existe "
                f"{knowledge_id}"
            )
            sys.exit(1)

        selected_knowledge.append(
            knowledge_by_id[
                knowledge_id
            ]
        )

    actions = [
        fact
        for fact in selected_facts
        if fact["fact_type"] == "action"
    ]

    associations = [
        fact
        for fact in selected_facts
        if fact["fact_type"] == "association"
    ]

    observations = [
        fact
        for fact in selected_facts
        if fact["fact_type"] == "observation"
    ]

    limitations = [
        fact
        for fact in selected_facts
        if fact["fact_type"] == "limitation"
    ]

    intent = plan["intent"]

    answer_parts = []

    # ================================================
    # CONCEPT
    # ================================================

    if intent == "concept":
        if not selected_knowledge:
            answer_parts.append(
                "No hay conocimiento técnico "
                "disponible para responder "
                "a esta pregunta."
            )

        else:
            for item in selected_knowledge:
                answer_parts.append(
                    item["content"]
                )

    # ================================================
    # OBSERVATION
    # ================================================

    elif intent == "observation":
        if not observations:
            answer_parts.append(
                "No hay una observación "
                "disponible para responder "
                "a esta pregunta."
            )

        else:
            for fact in observations:
                paragraph = fact[
                    "statement"
                ]

                change = find_numeric_change(
                    fact,
                    plan["topics"],
                    events_by_id
                )

                if change:
                    paragraph += (
                        " "
                        + render_change(
                            change
                        )
                    )

                answer_parts.append(
                    paragraph
                )

    # ================================================
    # TIMELINE
    # ================================================

    elif intent == "timeline":
        timeline_facts = [
            fact
            for fact in selected_facts
            if fact["fact_type"]
            != "limitation"
        ]

        if not timeline_facts:
            answer_parts.append(
                "No hay hechos temporales "
                "disponibles para responder."
            )

        else:
            answer_parts.append(
                render_timeline(
                    timeline_facts
                )
            )

    # ================================================
    # CAUSALITY
    # ================================================

    elif intent == "causality":
        if limitations:
            answer_parts.append(
                "Con los datos disponibles "
                "no puede afirmarse esa "
                "relación causal."
            )

        evidence = (
            actions
            + associations
            + observations
        )

        if evidence:
            evidence_text = " ".join(
                fact["statement"]
                for fact in evidence
            )

            answer_parts.append(
                "Lo que sí muestra la "
                "simulación es lo siguiente: "
                + evidence_text
            )

        if limitations:
            limitation_text = " ".join(
                fact["statement"]
                for fact in limitations
            )

            answer_parts.append(
                "Limitación del análisis: "
                + limitation_text
            )

    # ================================================
    # UNCERTAINTY
    # ================================================

    elif intent == "uncertainty":
        if limitations:
            answer_parts.append(
                " ".join(
                    fact["statement"]
                    for fact in limitations
                )
            )

        else:
            answer_parts.append(
                "No hay una limitación "
                "específica registrada para "
                "esta pregunta."
            )

    # ================================================
    # GENERAL
    # ================================================

    else:
        evidence = (
            actions
            + associations
            + observations
        )

        if evidence:
            answer_parts.append(
                " ".join(
                    fact["statement"]
                    for fact in evidence
                )
            )

        if limitations:
            answer_parts.append(
                " ".join(
                    fact["statement"]
                    for fact in limitations
                )
            )

    # ================================================
    # TEORÍA COMPLEMENTARIA
    # ================================================

    knowledge_was_used = False

    if (
        intent in [
            "causality",
            "uncertainty",
            "general"
        ]
        and selected_knowledge
    ):
        theory_parts = []

        for item in selected_knowledge:
            theory_parts.append(
                item["content"]
            )

        answer_parts.append(
            "Como marco teórico general: "
            + " ".join(
                theory_parts
            )
        )

        knowledge_was_used = True

    if intent == "concept":
        knowledge_was_used = bool(
            selected_knowledge
        )

    answer = "\n\n".join(
        answer_parts
    )

    # ================================================
    # FUENTES
    # ================================================

    source_ids = []

    if knowledge_was_used:
        for item in selected_knowledge:
            source_id = (
                item["source"][
                    "source_id"
                ]
            )

            if source_id not in source_ids:
                source_ids.append(
                    source_id
                )

    # ================================================
    # RESULTADO
    # ================================================

    result = {
        "schema_version": "0.2",
        "scenario_id":
            plan["scenario_id"],
        "question_id":
            plan["question_id"],
        "intent":
            intent,
        "topics":
            plan["topics"],
        "fact_ids":
            plan[
                "resolved_fact_ids"
            ],
        "knowledge_ids":
            plan[
                "resolved_knowledge_ids"
            ],
        "answer":
            answer,
        "source_ids":
            source_ids
    }

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    output_path = (
        OUTPUT_DIR
        / (
            f"{scenario_id}_"
            f"{question_id}_answer.json"
        )
    )

    with output_path.open(
        "w",
        encoding="utf-8"
    ) as f:
        json.dump(
            result,
            f,
            indent=2,
            ensure_ascii=False
        )

    print(
        "OK: respuesta generada"
    )

    print()
    print(
        f"Question ID: {question_id}"
    )

    print()
    print(answer)

    if source_ids:
        print()
        print("FUENTES:")

        for source_id in source_ids:
            print(
                f"- {source_id}"
            )

    print()
    print(
        f"Guardado en: "
        f"{output_path.name}"
    )


if __name__ == "__main__":
    main()