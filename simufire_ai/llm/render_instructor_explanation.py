import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]

FACTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "grounded_facts"
)

CONTEXT_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_context"
    / "basic_room_001_instructor.json"
)

SELECTION_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_selections"
    / "basic_room_001_instructor_selection_normalized.json"
)

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "explanation.schema.json"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_explanations"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_facts():
    facts = {}

    for path in sorted(FACTS_DIR.glob("*.json")):
        fact = load_json(path)
        facts[fact["fact_id"]] = fact

    return facts


def certainty_to_confidence(certainty):
    return {
        "certain": 1.0,
        "high": 0.9,
        "moderate": 0.7,
        "limited": 0.5
    }[certainty]


def join_statements(facts):
    return " ".join(
        fact["statement"]
        for fact in facts
    )


def main():

    facts = load_facts()
    context = load_json(CONTEXT_PATH)
    selection = load_json(SELECTION_PATH)
    schema = load_json(SCHEMA_PATH)

    selected_facts = []

    for fact_id in selection["fact_ids"]:

        if fact_id not in facts:
            print(
                f"ERROR: no existe el hecho {fact_id}"
            )
            sys.exit(1)

        selected_facts.append(
            facts[fact_id]
        )

    knowledge_by_id = {
        item["knowledge_id"]: item
        for item in context["technical_knowledge"]
    }

    selected_knowledge = []

    for knowledge_id in selection["knowledge_ids"]:

        if knowledge_id not in knowledge_by_id:
            print(
                f"ERROR: no existe el conocimiento "
                f"{knowledge_id}"
            )
            sys.exit(1)

        selected_knowledge.append(
            knowledge_by_id[knowledge_id]
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

    # -------------------------------------------------
    # RESUMEN
    # -------------------------------------------------

    summary = (
        "Durante la simulación se registró la siguiente "
        "secuencia: "
        + join_statements(
            actions
            + associations
            + observations
        )
    )

    # -------------------------------------------------
    # EXPLICACION
    # -------------------------------------------------

    sections = []

    sections.append(
        "QUÉ OCURRIÓ EN LA SIMULACIÓN:\n"
        + join_statements(
            actions
            + associations
            + observations
        )
    )

    if selected_knowledge:

        theory_parts = []

        for entry in selected_knowledge:

            theory_parts.append(
                f"{entry['title']}: "
                f"{entry['content']}"
            )

        sections.append(
            "CONCEPTOS RELACIONADOS:\n"
            + "\n\n".join(theory_parts)
        )

    if limitations:

        sections.append(
            "QUÉ NO PODEMOS CONCLUIR:\n"
            + join_statements(limitations)
        )

    explanation_text = "\n\n".join(
        sections
    )

    # -------------------------------------------------
    # CONFIANZA
    # -------------------------------------------------

    factual_facts = (
        actions
        + associations
        + observations
    )

    confidence = min(
        certainty_to_confidence(
            fact["certainty"]
        )
        for fact in factual_facts
    )

    # -------------------------------------------------
    # EVENTOS
    # -------------------------------------------------

    event_ids = []

    for fact in selected_facts:

        for event_id in fact["event_ids"]:

            if event_id not in event_ids:
                event_ids.append(event_id)

    # -------------------------------------------------
    # FUENTES
    # -------------------------------------------------

    source_ids = []

    for entry in selected_knowledge:

        source_id = (
            entry["source"]["source_id"]
        )

        if source_id not in source_ids:
            source_ids.append(source_id)

    # -------------------------------------------------
    # SALIDA
    # -------------------------------------------------

    output = {
        "schema_version": "0.1",
        "scenario_id": selection["scenario_id"],
        "explanation_id":
            "instructor_explanation_001",
        "language": "es",
        "audience_level": "instructor",
        "summary": summary,
        "explanation": explanation_text,
        "confidence": confidence,
        "event_ids": event_ids,
        "source_ids": source_ids,
        "limitations": [
            fact["statement"]
            for fact in limitations
        ]
    }

    validator = Draft202012Validator(
        schema
    )

    errors = list(
        validator.iter_errors(output)
    )

    if errors:

        print(
            "ERROR: la explicación no cumple "
            "el schema."
        )

        for error in errors:
            print(
                f"- {error.json_path}: "
                f"{error.message}"
            )

        sys.exit(1)

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    output_path = (
        OUTPUT_DIR
        / "basic_room_001_instructor_explanation.json"
    )

    with output_path.open(
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            output,
            f,
            indent=2,
            ensure_ascii=False
        )

    print(
        "OK: explicación de instructor "
        "generada y validada"
    )

    print()
    print(output["explanation"])

    print()
    print(
        f"Confianza: {output['confidence']}"
    )

    print()

    print("FUENTES:")

    for source_id in source_ids:
        print(f"- {source_id}")


if __name__ == "__main__":
    main()