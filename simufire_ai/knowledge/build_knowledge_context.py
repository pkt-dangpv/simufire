import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

sys.path.insert(
    0,
    str(BASE_DIR)
)

from knowledge.retriever import retrieve_by_topics


FACTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "grounded_facts"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "knowledge_context"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_facts():

    facts = []

    for path in sorted(
        FACTS_DIR.glob("*.json")
    ):
        facts.append(
            load_json(path)
        )

    return facts


def main():

    facts = load_facts()

    if not facts:
        print(
            "ERROR: no hay grounded facts."
        )
        sys.exit(1)

    scenario_id = facts[0]["scenario_id"]

    matches = {}

    for fact in facts:

        # Las limitaciones no necesitan
        # recuperar teoría por ahora.
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

            entry = result["entry"]

            knowledge_id = (
                entry["knowledge_id"]
            )

            if knowledge_id not in matches:

                matches[knowledge_id] = {
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
                        result["matched_topic"],

                    "matched_fact_ids": [
                        fact["fact_id"]
                    ]
                }

            else:

                if (
                    fact["fact_id"]
                    not in matches[
                        knowledge_id
                    ]["matched_fact_ids"]
                ):

                    matches[
                        knowledge_id
                    ]["matched_fact_ids"].append(
                        fact["fact_id"]
                    )

    knowledge_matches = sorted(
        matches.values(),
        key=lambda item:
            item["knowledge_id"]
    )

    output = {
        "schema_version": "0.1",
        "scenario_id": scenario_id,
        "knowledge_matches":
            knowledge_matches
    }

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    output_path = (
        OUTPUT_DIR
        / f"{scenario_id}_knowledge.json"
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
        f"Entradas recuperadas: "
        f"{len(knowledge_matches)}"
    )

    for item in knowledge_matches:

        print(
            f"- {item['knowledge_id']} "
            f"[{item['matched_topic']}] "
            f"<- {item['matched_fact_ids']}"
        )


if __name__ == "__main__":
    main()