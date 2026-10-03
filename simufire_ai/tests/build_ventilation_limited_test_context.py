import argparse
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator


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

from knowledge.retriever import (
    retrieve_by_topics
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

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "instructor_context.schema.json"
)

OUTPUT_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_context"
    / "basic_room_001_vl_test_instructor.json"
)


def load_json(path: Path):

    with path.open(
        "r",
        encoding="utf-8"
    ) as f:

        return json.load(f)


def build_knowledge_matches(facts):

    matches = {}

    for fact in facts:

        if fact["fact_type"] not in [
            "observation",
            "association"
        ]:
            continue

        topics = fact.get(
            "knowledge_topics",
            []
        )

        if not topics:
            continue

        results = retrieve_by_topics(
            topics
        )

        for result in results:

            entry = result[
                "entry"
            ]

            knowledge_id = entry[
                "knowledge_id"
            ]

            if knowledge_id not in matches:

                matches[
                    knowledge_id
                ] = {
                    "knowledge_id":
                        knowledge_id,

                    "topic":
                        entry["topic"],

                    "title":
                        entry["title"],

                    "content":
                        entry["content"],

                    "source":
                        entry["source"],

                    "confidence":
                        entry["confidence"],

                    "matched_topic":
                        result[
                            "matched_topic"
                        ],

                    "matched_fact_ids": [
                        fact["fact_id"]
                    ]
                }

            else:

                fact_ids = (
                    matches[
                        knowledge_id
                    ][
                        "matched_fact_ids"
                    ]
                )

                if (
                    fact["fact_id"]
                    not in fact_ids
                ):
                    fact_ids.append(
                        fact["fact_id"]
                    )

    return sorted(
        matches.values(),
        key=lambda item:
            item["knowledge_id"]
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=OUTPUT_PATH)
    args = parser.parse_args()

    scenario = load_json(
        SCENARIO_PATH
    )

    # ---------------------------------------------
    # ESTADOS DEL FIXTURE
    # ---------------------------------------------

    state_files = sorted(
        STATES_DIR.glob(
            "vl_case_t*.json"
        )
    )

    if len(state_files) != 5:

        print(
            "ERROR: se esperaban "
            "5 estados del fixture "
            "ventilation_limited."
        )

        print(
            f"Encontrados: "
            f"{len(state_files)}"
        )

        sys.exit(1)

    states = [
        load_json(path)
        for path in state_files
    ]

    # ---------------------------------------------
    # EVENTOS
    # ---------------------------------------------

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

    if (
        len(
            ventilation_limited_events
        )
        != 1
    ):

        print(
            "ERROR: el fixture debe "
            "producir exactamente un "
            "evento ventilation_limited."
        )

        sys.exit(1)

    # ---------------------------------------------
    # GROUNDED FACTS
    # ---------------------------------------------

    facts = build_facts(
        scenario,
        events
    )

    facts_by_id = {
        fact["fact_id"]: fact
        for fact in facts
    }

    if "FACT_010" not in facts_by_id:

        print(
            "ERROR: no se generó "
            "FACT_010."
        )

        sys.exit(1)

    fact_010 = facts_by_id[
        "FACT_010"
    ]

    if (
        "ventilation_limited"
        not in fact_010.get(
            "knowledge_topics",
            []
        )
    ):

        print(
            "ERROR: FACT_010 no tiene "
            "el topic ventilation_limited."
        )

        sys.exit(1)

    # ---------------------------------------------
    # CONOCIMIENTO
    # ---------------------------------------------

    knowledge_matches = (
        build_knowledge_matches(
            facts
        )
    )

    knowledge_ids = {
        item["knowledge_id"]
        for item
        in knowledge_matches
    }

    if (
        "VENTILATION_LIMITED_001"
        not in knowledge_ids
    ):

        print(
            "ERROR: no se recuperó "
            "VENTILATION_LIMITED_001."
        )

        sys.exit(1)

    # ---------------------------------------------
    # CONTEXTO
    # ---------------------------------------------

    context = {
        "schema_version": "0.1",

        "scenario_id":
            scenario["scenario_id"],

        "scenario_facts":
            facts,

        "source_events": events,

        "technical_knowledge":
            knowledge_matches,

        "rules": {
            "scenario_facts_are_authoritative":
                True,

            "knowledge_is_general_theory":
                True,

            "do_not_convert_association_into_causation":
                True,

            "do_not_invent_missing_variables":
                True,

            "do_not_invent_phenomena":
                True,

            "distinguish_scenario_from_general_theory":
                True
        }
    }

    # ---------------------------------------------
    # VALIDACIÓN
    # ---------------------------------------------

    schema = load_json(
        SCHEMA_PATH
    )

    validator = (
        Draft202012Validator(
            schema
        )
    )

    errors = list(
        validator.iter_errors(
            context
        )
    )

    if errors:

        print(
            "ERROR: el contexto generado "
            "no cumple el schema."
        )

        for error in errors:

            print(
                f"- {error.json_path}: "
                f"{error.message}"
            )

        sys.exit(1)

    # ---------------------------------------------
    # GUARDADO
    # ---------------------------------------------

    args.output.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    with args.output.open(
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            context,
            f,
            indent=2,
            ensure_ascii=False
        )

    # ---------------------------------------------
    # RESULTADO
    # ---------------------------------------------

    print(
        "OK: contexto ventilation_limited "
        "de prueba generado"
    )

    print()

    print(
        f"Hechos: {len(facts)}"
    )

    print(
        f"Conocimiento: "
        f"{len(knowledge_matches)}"
    )

    print()

    print(
        "FACT_010:"
    )

    print(
        f"- {fact_010['statement']}"
    )

    print(
        f"- certeza: "
        f"{fact_010['certainty']}"
    )

    print(
        f"- causal: "
        f"{fact_010['causal']}"
    )

    print()

    print(
        "Conocimiento "
        "ventilation_limited:"
    )

    print(
        "- VENTILATION_LIMITED_001"
    )

    print()

    print(
        f"Guardado en: "
        f"{args.output.name}"
    )


if __name__ == "__main__":
    main()