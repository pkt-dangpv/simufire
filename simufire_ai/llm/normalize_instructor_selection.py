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
    / "instructor_selections"
    / "basic_room_001_instructor_selection.json"
)

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "instructor_selection.schema.json"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_selections"
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


def resolve_fact(
    fact_id,
    facts,
    result,
    added,
    visiting
):

    if fact_id in added:
        return

    if fact_id in visiting:
        raise RuntimeError(
            f"Dependencia circular detectada en {fact_id}"
        )

    if fact_id not in facts:
        raise KeyError(
            f"El hecho {fact_id} no existe."
        )

    visiting.add(fact_id)

    fact = facts[fact_id]

    for required_id in fact.get(
        "requires_fact_ids",
        []
    ):
        resolve_fact(
            required_id,
            facts,
            result,
            added,
            visiting
        )

    visiting.remove(fact_id)

    if fact_id not in added:
        result.append(fact_id)
        added.add(fact_id)


def main():

    facts = load_facts()
    selection = load_json(SELECTION_PATH)
    schema = load_json(SCHEMA_PATH)

    normalized_fact_ids = []
    added = set()

    try:

        for fact_id in selection["fact_ids"]:

            resolve_fact(
                fact_id,
                facts,
                normalized_fact_ids,
                added,
                set()
            )

    except (KeyError, RuntimeError) as error:

        print(f"ERROR: {error}")
        sys.exit(1)

    normalized = {
        "schema_version":
            selection["schema_version"],

        "scenario_id":
            selection["scenario_id"],

        "selection_id":
            "instructor_selection_001_normalized",

        "fact_ids":
            normalized_fact_ids,

        "knowledge_ids":
            selection["knowledge_ids"]
    }

    validator = Draft202012Validator(schema)

    errors = list(
        validator.iter_errors(normalized)
    )

    if errors:

        print(
            "ERROR: la selección normalizada "
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
        / "basic_room_001_instructor_selection_normalized.json"
    )

    with output_path.open(
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            normalized,
            f,
            indent=2,
            ensure_ascii=False
        )

    print("OK: selección normalizada")
    print()

    print("HECHOS FINALES:")

    for fact_id in normalized_fact_ids:

        marker = ""

        if fact_id not in selection["fact_ids"]:
            marker = "  [añadido por dependencia]"

        print(
            f"- {fact_id}{marker}"
        )

    print()
    print("CONOCIMIENTO:")

    for knowledge_id in normalized["knowledge_ids"]:
        print(f"- {knowledge_id}")


if __name__ == "__main__":
    main()
    