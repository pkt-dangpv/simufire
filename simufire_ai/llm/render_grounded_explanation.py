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
    values = {
        "certain": 1.0,
        "high": 0.9,
        "moderate": 0.7,
        "limited": 0.5
    }

    return values[certainty]


def main():

    facts = load_facts()
    selection = load_json(SELECTION_PATH)
    schema = load_json(SCHEMA_PATH)

    selected_facts = []

    for fact_id in selection["fact_ids"]:

        if fact_id not in facts:
            print(
                f"ERROR: el hecho {fact_id} "
                "no existe."
            )
            sys.exit(1)

        selected_facts.append(
            facts[fact_id]
        )

    scenario_id = selection["scenario_id"]

    observations = [
        fact
        for fact in selected_facts
        if fact["fact_type"] == "observation"
    ]

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

    limitations = [
        fact
        for fact in selected_facts
        if fact["fact_type"] == "limitation"
    ]

    main_facts = (
        actions
        + associations
        + observations
    )

    if not main_facts:
        print("ERROR: no hay hechos explicables.")
        sys.exit(1)

    summary_parts = [
        fact["statement"]
        for fact in main_facts
    ]

    summary = " ".join(summary_parts)

    explanation_parts = []

    for fact in main_facts:
        explanation_parts.append(
            fact["statement"]
        )

    if limitations:
        explanation_parts.append(
            "Limitaciones de interpretación:"
        )

        for fact in limitations:
            explanation_parts.append(
                fact["statement"]
            )

    explanation_text = " ".join(
        explanation_parts
    )

    confidence_values = [
        certainty_to_confidence(
            fact["certainty"]
        )
        for fact in main_facts
    ]

    confidence = min(
        confidence_values
    )

    event_ids = []

    for fact in selected_facts:
        for event_id in fact["event_ids"]:
            if event_id not in event_ids:
                event_ids.append(event_id)

    output = {
        "schema_version": "0.1",
        "scenario_id": scenario_id,
        "explanation_id":
            "grounded_explanation_001",
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

    validator = Draft202012Validator(
        schema
    )

    errors = list(
        validator.iter_errors(output)
    )

    if errors:

        print(
            "ERROR: la explicacion generada "
            "no cumple el schema."
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
        / "basic_room_001_grounded_explanation.json"
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
        "OK: explicacion grounded "
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
        f"Confianza: "
        f"{output['confidence']}"
    )


if __name__ == "__main__":
    main()