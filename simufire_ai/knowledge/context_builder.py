"""Build an instructor context from this analysis and a knowledge snapshot."""

import copy

from llm.question_context import validate_context, validate_schema, load_schema, unique_index
from knowledge.retriever import load_entries


RULES = {
    "scenario_facts_are_authoritative": True,
    "knowledge_is_general_theory": True,
    "do_not_convert_association_into_causation": True,
    "do_not_invent_missing_variables": True,
    "do_not_invent_phenomena": True,
    "distinguish_scenario_from_general_theory": True,
}


def build_knowledge_matches(facts, entries=None):
    entries = load_entries() if entries is None else entries
    unique_index(entries, "knowledge_id")
    schema = load_schema("knowledge_entry.schema.json")
    for entry in entries:
        validate_schema(entry, schema, "Entrada de conocimiento")
    entries = sorted(entries, key=lambda item: item["knowledge_id"])
    matches = {}
    for fact in facts:
        if fact["fact_type"] not in ("observation", "association"):
            continue
        topics = fact.get("knowledge_topics", [])
        for entry in [item for item in entries if item["topic"] in topics][:10]:
            knowledge_id = entry["knowledge_id"]
            if knowledge_id not in matches:
                matches[knowledge_id] = {
                    key: copy.deepcopy(entry[key])
                    for key in ("knowledge_id", "topic", "title", "content", "source", "confidence")
                }
                matches[knowledge_id].update(matched_topic=entry["topic"], matched_fact_ids=[])
            matched = matches[knowledge_id]["matched_fact_ids"]
            if fact["fact_id"] not in matched:
                matched.append(fact["fact_id"])
    return sorted(matches.values(), key=lambda item: item["knowledge_id"])


def build_context(scenario_id, facts, events, entries=None, *, run_id=None):
    context = {
        "schema_version": "0.1", "scenario_id": scenario_id,
        "scenario_facts": copy.deepcopy(facts), "source_events": copy.deepcopy(events),
        "technical_knowledge": build_knowledge_matches(facts, entries),
        "rules": dict(RULES),
    }
    if run_id is not None:
        context["run_id"] = run_id
    validate_context(context)
    return context
