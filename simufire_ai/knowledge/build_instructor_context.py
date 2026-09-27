import json
import sys
from pathlib import Path


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

KNOWLEDGE_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "knowledge_context"
    / "basic_room_001_knowledge.json"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_context"
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


def main():

    facts = load_facts()
    selection = load_json(SELECTION_PATH)
    knowledge = load_json(KNOWLEDGE_PATH)

    selected_facts = []

    for fact_id in selection["fact_ids"]:

        if fact_id not in facts:
            print(
                f"ERROR: no existe {fact_id}"
            )
            sys.exit(1)

        selected_facts.append(
            facts[fact_id]
        )

    context = {
        "schema_version": "0.1",

        "scenario_id": selection["scenario_id"],

        "scenario_facts": selected_facts,

        "technical_knowledge":
            knowledge["knowledge_matches"],

        "rules": {
            "scenario_facts_are_authoritative": True,
            "knowledge_is_general_theory": True,
            "do_not_convert_association_into_causation": True,
            "do_not_invent_missing_variables": True,
            "do_not_invent_phenomena": True,
            "distinguish_scenario_from_general_theory": True
        }
    }

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    output_path = (
        OUTPUT_DIR
        / f"{selection['scenario_id']}_instructor.json"
    )

    with output_path.open(
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            context,
            f,
            indent=2,
            ensure_ascii=False
        )

    print("OK: contexto de instructor generado")
    print()

    print(
        f"Hechos del escenario: "
        f"{len(selected_facts)}"
    )

    print(
        f"Entradas de conocimiento: "
        f"{len(knowledge['knowledge_matches'])}"
    )

    print()

    for item in knowledge["knowledge_matches"]:
        print(
            f"- {item['knowledge_id']} "
            f"[{item['topic']}]"
        )


if __name__ == "__main__":
    main()