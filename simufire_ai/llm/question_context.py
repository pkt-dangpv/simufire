"""Validation and provenance shared by question planning and rendering."""

import hashlib
import json
from pathlib import Path

from jsonschema import Draft202012Validator


SCHEMAS_DIR = Path(__file__).resolve().parents[1] / "schemas"


def load_schema(name):
    return json.loads((SCHEMAS_DIR / name).read_text(encoding="utf-8"))


def validate_schema(value, schema, label):
    error = next(Draft202012Validator(schema).iter_errors(value), None)
    if error is not None:
        raise ValueError(f"{label}: {error.json_path}: {error.message}")


def context_fingerprint(context):
    """Bind a plan to JSON content, independently of file path/formatting."""
    encoded = json.dumps(
        context, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def unique_index(items, key):
    result = {}
    for item in items:
        identifier = item[key]
        if identifier in result:
            raise ValueError(f"Identificador duplicado: {identifier}")
        result[identifier] = item
    return result


def validate_context(context):
    validate_schema(
        context, load_schema("instructor_context.schema.json"), "Contexto",
    )
    fact_schema = load_schema("grounded_fact.schema.json")
    for fact in context["scenario_facts"]:
        validate_schema(fact, fact_schema, "Hecho del contexto")
        if fact["scenario_id"] != context["scenario_id"]:
            raise ValueError(f"{fact['fact_id']} pertenece a otro escenario")
    facts = unique_index(context["scenario_facts"], "fact_id")
    for fact in facts.values():
        for dependency in fact["requires_fact_ids"]:
            if dependency not in facts:
                raise ValueError(f"No existe el hecho requerido {dependency}")

    # Instructor knowledge is a projection of an entry plus match provenance.
    entry_schema = load_schema("knowledge_entry.schema.json")
    keys = ("knowledge_id", "topic", "title", "content", "source", "confidence")
    knowledge_schema = {
        "type": "object",
        "required": list(keys),
        "properties": {
            **{key: entry_schema["properties"][key] for key in keys},
            "matched_topic": entry_schema["properties"]["topic"],
            "matched_fact_ids": {
                "type": "array", "uniqueItems": True,
                "items": {"type": "string", "minLength": 1},
            },
        },
    }
    for entry in context["technical_knowledge"]:
        validate_schema(entry, knowledge_schema, "Conocimiento del contexto")
        for fact_id in entry.get("matched_fact_ids", []):
            if fact_id not in facts:
                raise ValueError(f"Conocimiento vinculado a un hecho inexistente: {fact_id}")
    unique_index(context["technical_knowledge"], "knowledge_id")

    event_schema = load_schema("fire_event.schema.json")
    for event in context.get("source_events", []):
        validate_schema(event, event_schema, "Evento del contexto")
        if event["scenario_id"] != context["scenario_id"]:
            raise ValueError(f"{event['event_id']} pertenece a otro escenario")
    unique_index(context.get("source_events", []), "event_id")


def validate_plan_context(plan, context, question_id, *, allow_legacy=False):
    """Reject stale/cross-context plans before resolving IDs or writing output."""
    schema = load_schema("question_plan.schema.json")
    for key in ("resolved_fact_ids", "resolved_knowledge_ids"):
        schema["required"].append(key)
        schema["properties"][key] = {
            "type": "array", "uniqueItems": True,
            "items": {"type": "string", "minLength": 1},
        }
    schema["properties"]["source_context_sha256"] = {
        "type": "string", "pattern": "^[0-9a-f]{64}$",
    }
    validate_schema(plan, schema, "Plan resuelto")
    if plan["scenario_id"] != context["scenario_id"]:
        raise ValueError("El plan pertenece a otro escenario")
    if plan["question_id"] != question_id:
        raise ValueError("El question_id del plan no coincide con el solicitado")

    fingerprint = plan.get("source_context_sha256")
    if fingerprint is None:
        if not allow_legacy:
            raise ValueError(
                "El plan no identifica su contexto. Regenera el plan con --context."
            )
    elif fingerprint != context_fingerprint(context):
        raise ValueError(
            "El plan no corresponde al contenido del contexto seleccionado. "
            "Regenera el plan con --context."
        )

    facts = unique_index(context["scenario_facts"], "fact_id")
    knowledge = unique_index(context["technical_knowledge"], "knowledge_id")
    for ids, available in (
        (plan["resolved_fact_ids"], facts),
        (plan["resolved_knowledge_ids"], knowledge),
    ):
        for identifier in ids:
            if identifier not in available:
                raise ValueError(f"No existe {identifier} en el contexto seleccionado")
    for fact_id in plan["resolved_fact_ids"]:
        for dependency in facts[fact_id]["requires_fact_ids"]:
            if dependency not in plan["resolved_fact_ids"]:
                raise ValueError(f"Falta el hecho requerido {dependency} en el plan")
    anchor = plan["anchor_fact_id"]
    if anchor is not None and (
        anchor not in facts or facts[anchor]["fact_type"] != "action"
    ):
        raise ValueError("El anchor no corresponde a una acción del contexto")
