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

SELECTION_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "fact_selections"
    / "basic_room_001_selection.json"
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
    selection = load_json(SELECTION_PATH)
    schema = load_json(SCHEMA_PATH)

    selected = []

    for fact_id in selection["fact_ids"]:

        if fact_id not in facts:
            print(
                f"ERROR: el hecho {fact_id} no existe."
            )
            sys.exit(1)

        selected.append(facts[fact_id])

    actions = [
        f for f in selected
        if f["fact_type"] == "action"
    ]

    associations = [
        f for f in selected
        if f["fact_type"] == "association"
    ]

    observations = [
        f for f in selected
        if f["fact_type"] == "observation"
    ]

    limitations = [
        f for f in selected
        if f["fact_type"] == "limitation"
    ]

    factual_facts = (
        actions
        + associations
        + observations
    )

    if not factual_facts:
        print("ERROR: no hay hechos para explicar.")
        sys.exit(1)

    # ---------------------------------------------
    # RESUMEN
    # ---------------------------------------------

    summary_parts = []

    if actions:
        summary_parts.append(
            join_statements(actions)
        )

    if associations:
        summary_parts.append(
            join_statements(associations)
        )

    if observations:
        summary_parts.append(
            "Durante el intervalo analizado se observaron "
            "también los siguientes cambios: "
            + join_statements(observations)
        )

    summary = " ".join(summary_parts)

    # ---------------------------------------------
    # EXPLICACION
    # ---------------------------------------------

    paragraphs = []

    if actions or associations:

        paragraph = []

        if actions:
            paragraph.append(
                join_statements(actions)
            )

        if associations:
            paragraph.append(
                join_statements(associations)
            )

        paragraphs.append(
            " ".join(paragraph)
        )

    if observations:

        paragraphs.append(
            "En la evolución posterior registrada por la "
            "simulación, "
            + join_statements(observations)
        )

    if limitations:

        paragraphs.append(
            "Estos cambios deben interpretarse con cautela. "
            + join_statements(limitations)
        )

    explanation_text = "\n\n".join(paragraphs)

    confidence = min(
        certainty_to_confidence(
            fact["certainty"]
        )
        for fact in factual_facts
    )

    event_ids = []

    for fact in selected:

        for event_id in fact["event_ids"]:

            if event_id not in event_ids:
                event_ids.append(event_id)

    output = {
        "schema_version": "0.1",
        "scenario_id": selection["scenario_id"],
        "explanation_id":
            "grounded_explanation_v2_001",
        "language": "es",
        "audience_level": "firefighter",
        "summary": summary,
        "explanation": explanation_text,
        "confidence": confidence,
        "event_ids": event_ids,
        "source_ids": [],
        "limitations": [
            fact["statement"]
            for fact in limitations
        ]
    }

    validator = Draft202012Validator(schema)

    errors = list(
        validator.iter_errors(output)
    )

    if errors:

        print(
            "ERROR: la explicación no cumple el schema."
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
        / "basic_room_001_grounded_explanation_v2.json"
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
        "OK: explicación grounded v2 "
        "generada y validada"
    )

    print()
    print("RESUMEN:")
    print(output["summary"])

    print()
    print("EXPLICACION:")
    print(output["explanation"])

    print()
    print(
        f"Confianza: {output['confidence']}"
    )


if __name__ == "__main__":
    main()