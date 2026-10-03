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


def validate_time_provenance(item):
    interval = item.get("evidence_interval_s")
    if interval is not None and not (
        interval["start"] < interval["end"]
        and interval["start"] <= item["time_s"] <= interval["end"]
    ):
        raise ValueError("Intervalo de evidencia no válido")
    if ("action_target" in item) != ("action_time_s" in item):
        raise ValueError("La procedencia de una acción necesita target y tiempo")


def validate_context(context):
    context_fingerprint(context)  # Reject non-finite numbers in all nested data.
    validate_schema(
        context, load_schema("instructor_context.schema.json"), "Contexto",
    )
    fact_schema = load_schema("grounded_fact.schema.json")
    for fact in context["scenario_facts"]:
        validate_schema(fact, fact_schema, "Hecho del contexto")
        if fact["scenario_id"] != context["scenario_id"]:
            raise ValueError(f"{fact['fact_id']} pertenece a otro escenario")
        validate_time_provenance(fact)
    facts = unique_index(context["scenario_facts"], "fact_id")
    for fact in facts.values():
        for dependency in fact["requires_fact_ids"]:
            if dependency not in facts:
                raise ValueError(f"No existe el hecho requerido {dependency}")
            dependency_fact = facts[dependency]
            room_id = fact.get("compartment_id")
            dependency_rooms = dependency_fact.get("compartment_ids", [])
            if "compartment_id" in dependency_fact:
                dependency_rooms = [dependency_fact["compartment_id"]]
            if room_id is not None and dependency_rooms and room_id not in dependency_rooms:
                raise ValueError(f"Dependencia entre compartimentos distintos: {dependency}")

    visiting, visited = set(), set()

    def visit(fact_id):
        if fact_id in visiting:
            raise ValueError(f"Dependencia circular detectada en {fact_id}")
        if fact_id in visited:
            return
        visiting.add(fact_id)
        for dependency in facts[fact_id]["requires_fact_ids"]:
            visit(dependency)
        visiting.remove(fact_id)
        visited.add(fact_id)

    for fact_id in facts:
        visit(fact_id)

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
        validate_time_provenance(event)
    events = unique_index(context.get("source_events", []), "event_id")
    if "source_events" in context:
        for fact in facts.values():
            for event_id in fact["event_ids"]:
                if event_id not in events:
                    raise ValueError(f"No existe el evento de origen {event_id}")
                room_id = fact.get("compartment_id")
                if room_id is not None and events[event_id].get("compartment_id") != room_id:
                    raise ValueError(f"Evento de otro compartimento: {event_id}")
    coverage = context.get("analysis_coverage")
    if coverage is not None:
        rooms = unique_index(coverage["compartments"], "id")
        for fact in facts.values():
            declared = fact.get("compartment_ids", [])
            if "compartment_id" in fact:
                declared = [fact["compartment_id"]]
            if any(room not in rooms for room in declared):
                raise ValueError("Hecho de un compartimento ajeno a la cobertura")
        if any(event.get("compartment_id") not in rooms for event in events.values()):
            raise ValueError("Evento de un compartimento ajeno a la cobertura")
        times = coverage["state_times_s"]
        if times != sorted(set(times)):
            raise ValueError("Los tiempos de cobertura deben ser únicos y ordenados")
        for window in coverage["windows"]:
            if window["compartment_id"] not in rooms:
                raise ValueError("Ventana de cobertura de otro compartimento")
            if not (times[0] <= window["start_time_s"] <= window["end_time_s"] <= times[-1]):
                raise ValueError("Intervalo de cobertura fuera de los datos registrados")
            if not window["start_time_s"] <= window["reference_time_s"] <= window["end_time_s"]:
                # An unevaluable opening can sit beyond the recorded time span.
                if window["evaluable"] or window["reason"] != "missing_pre_or_post_samples":
                    raise ValueError("Intervalo de cobertura inválido")
            if window["evaluable"] != (window["reason"] == "requirements_met"):
                raise ValueError("Estado y motivo de cobertura contradictorios")


def validate_plan_context(plan, context, question_id):
    """Reject stale/cross-context plans before resolving IDs or writing output."""
    context_fingerprint(plan)
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
    schema["properties"]["run_id"] = {
        "type": "string", "minLength": 1,
    }
    validate_schema(plan, schema, "Plan resuelto")
    if plan["scenario_id"] != context["scenario_id"]:
        raise ValueError("El plan pertenece a otro escenario")
    if plan["question_id"] != question_id:
        raise ValueError("El question_id del plan no coincide con el solicitado")
    if plan.get("run_id") != context.get("run_id"):
        raise ValueError("El plan pertenece a otra ejecución (run_id)")

    fingerprint = plan.get("source_context_sha256")
    if fingerprint is None:
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
    if plan["schema_version"] == "0.4":
        if __package__:
            from .question_scope import interpret_explicit_scope, resolve_question
        else:
            from question_scope import interpret_explicit_scope, resolve_question
        classification = {key: plan[key] for key in (
            "intent", "topics", "timeline_relation", "anchor_fact_id", "clarification_needed",
        )}
        classification["scope"] = plan["requested_scope"]
        interpreted = interpret_explicit_scope(context, plan["question"], classification)
        expected = resolve_question(context, interpreted)
        for key, value in expected.items():
            if plan[key] != value:
                raise ValueError(f"Plan resuelto no coincide con su ámbito/evidencia: {key}")
