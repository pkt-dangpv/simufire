import argparse
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

PROFILES_PATH = (
    BASE_DIR
    / "config"
    / "audience_profiles.json"
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


def join_facts(facts):
    return " ".join(
        fact["statement"]
        for fact in facts
    )


def build_text(
    level,
    actions,
    associations,
    observations,
    limitations
):

    if level == "student":

        summary = (
            "Durante la simulación ocurrieron varios cambios. "
            + join_facts(actions + associations + observations)
        )

        explanation = (
            "Primero, "
            + join_facts(actions + associations)
            + "\n\nDespués se observaron estos cambios: "
            + join_facts(observations)
        )

    elif level == "firefighter":

        summary = (
            join_facts(actions + associations)
            + " Durante la evolución del incendio se registraron: "
            + join_facts(observations)
        )

        explanation = (
            join_facts(actions + associations)
            + "\n\n"
            + "En la evolución posterior registrada por la simulación, "
            + join_facts(observations)
        )

    elif level == "instructor":

        summary = (
            "Secuencia observada: "
            + join_facts(actions + associations + observations)
        )

        explanation = (
            "La secuencia temporal registrada es la siguiente: "
            + join_facts(actions + associations)
            + "\n\n"
            + "Los cambios físicos observados fueron: "
            + join_facts(observations)
        )

    elif level == "technical":

        summary = (
            "Hechos estructurados detectados: "
            + join_facts(actions + associations + observations)
        )

        explanation = (
            "Acciones registradas: "
            + join_facts(actions)
            + "\n\n"
            + "Asociaciones detectadas: "
            + join_facts(associations)
            + "\n\n"
            + "Observaciones físicas: "
            + join_facts(observations)
        )

    else:
        raise ValueError(
            f"Nivel no soportado: {level}"
        )

    if limitations:

        explanation += (
            "\n\nLimitaciones de interpretación: "
            + join_facts(limitations)
        )

    return summary, explanation


def main():

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--level",
        choices=[
            "student",
            "firefighter",
            "instructor",
            "technical"
        ],
        default="firefighter"
    )

    args = parser.parse_args()

    level = args.level

    profiles = load_json(PROFILES_PATH)

    if level not in profiles:
        print(
            f"ERROR: perfil {level} no existe."
        )
        sys.exit(1)

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

        selected.append(
            facts[fact_id]
        )

    actions = [
        fact for fact in selected
        if fact["fact_type"] == "action"
    ]

    associations = [
        fact for fact in selected
        if fact["fact_type"] == "association"
    ]

    observations = [
        fact for fact in selected
        if fact["fact_type"] == "observation"
    ]

    limitations = [
        fact for fact in selected
        if fact["fact_type"] == "limitation"
    ]

    factual_facts = (
        actions
        + associations
        + observations
    )

    if not factual_facts:
        print("ERROR: no hay hechos para explicar.")
        sys.exit(1)

    summary, explanation_text = build_text(
        level,
        actions,
        associations,
        observations,
        limitations
    )

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
            f"grounded_explanation_v3_{level}",
        "language": "es",
        "audience_level": level,
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
        / f"basic_room_001_grounded_{level}.json"
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
        f"OK: explicación para perfil '{level}' "
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