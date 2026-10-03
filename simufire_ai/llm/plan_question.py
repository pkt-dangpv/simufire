import argparse
import json
import sys
import urllib.request
from pathlib import Path

from jsonschema import Draft202012Validator

if __package__:
    from .question_context import (
        context_fingerprint, validate_context, validate_plan_context,
    )
else:
    from question_context import (
        context_fingerprint, validate_context, validate_plan_context,
    )


BASE_DIR = Path(__file__).resolve().parents[1]

CONTEXT_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_context"
    / "basic_room_001_instructor.json"
)

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "question_plan.schema.json"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "question_plans"
)

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "qwen3:1.7b"


def load_json(path: Path):
    with path.open(
        "r",
        encoding="utf-8"
    ) as f:
        return json.load(f)


def call_ollama(prompt, schema):

    payload = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "think": False,
        "format": schema,
        "options": {
            "temperature": 0
        }
    }

    request = urllib.request.Request(
        OLLAMA_URL,
        data=json.dumps(
            payload
        ).encode("utf-8"),
        headers={
            "Content-Type": "application/json"
        }
    )

    with urllib.request.urlopen(
        request,
        timeout=120
    ) as response:

        result = json.loads(
            response.read().decode(
                "utf-8"
            )
        )

    if not isinstance(result, dict) or not isinstance(result.get("response"), str):
        raise ValueError("Ollama no devolvió un campo response de texto")
    return result["response"]


def resolve_fact_dependencies(
    fact_id,
    facts_by_id,
    selected_ids,
    visiting
):

    if fact_id in selected_ids:
        return

    if fact_id in visiting:
        raise RuntimeError(
            f"Dependencia circular detectada "
            f"en {fact_id}"
        )

    if fact_id not in facts_by_id:
        raise KeyError(
            f"No existe el hecho requerido "
            f"{fact_id}"
        )

    visiting.add(
        fact_id
    )

    fact = facts_by_id[
        fact_id
    ]

    for required_id in fact.get(
        "requires_fact_ids",
        []
    ):
        resolve_fact_dependencies(
            required_id,
            facts_by_id,
            selected_ids,
            visiting
        )

    visiting.remove(
        fact_id
    )

    if fact_id not in selected_ids:
        selected_ids.append(
            fact_id
        )


def fact_depends_on(
    fact_id,
    target_fact_id,
    facts_by_id,
    visiting=None
):

    if visiting is None:
        visiting = set()

    if fact_id in visiting:
        return False

    visiting.add(
        fact_id
    )

    fact = facts_by_id.get(
        fact_id
    )

    if not fact:
        return False

    required_ids = fact.get(
        "requires_fact_ids",
        []
    )

    if target_fact_id in required_ids:
        return True

    for required_id in required_ids:

        if fact_depends_on(
            required_id,
            target_fact_id,
            facts_by_id,
            visiting
        ):
            return True

    return False


def derive_topics_from_action(
    facts,
    action_fact_id
):

    if not action_fact_id:
        return []

    facts_by_id = {
        fact["fact_id"]: fact
        for fact in facts
    }

    topics = []

    for fact in facts:

        if (
            fact["fact_type"]
            != "association"
        ):
            continue

        if not fact_depends_on(
            fact["fact_id"],
            action_fact_id,
            facts_by_id
        ):
            continue

        for topic in fact.get(
            "knowledge_topics",
            []
        ):
            if topic not in topics:
                topics.append(
                    topic
                )

    return topics


def select_topic_facts(
    facts,
    topics,
    include_limitations,
    intent
):

    if intent == "concept":
        return []

    requested_topics = set(
        topics
    )

    facts_by_id = {
        fact["fact_id"]: fact
        for fact in facts
    }

    initial_ids = []

    for fact in facts:

        fact_topics = set(
            fact.get(
                "knowledge_topics",
                []
            )
        )

        fact_type = fact[
            "fact_type"
        ]

        if fact_type == "limitation":

            if not include_limitations:
                continue

            if (
                fact_topics
                and fact_topics.issubset(
                    requested_topics
                )
            ):
                initial_ids.append(
                    fact["fact_id"]
                )

            continue

        if (
            fact_topics
            & requested_topics
        ):
            initial_ids.append(
                fact["fact_id"]
            )

    selected_ids = []

    for fact_id in initial_ids:

        resolve_fact_dependencies(
            fact_id,
            facts_by_id,
            selected_ids,
            set()
        )

    return selected_ids


def select_timeline_facts(
    facts,
    relation,
    anchor_fact_id
):

    facts_by_id = {
        fact["fact_id"]: fact
        for fact in facts
    }

    if relation == "all":

        selected = [
            fact
            for fact in facts
            if (
                fact["fact_type"]
                != "limitation"
            )
        ]

    else:

        if not anchor_fact_id:
            raise ValueError(
                "Una pregunta temporal "
                "before/after necesita "
                "anchor_fact_id."
            )

        if (
            anchor_fact_id
            not in facts_by_id
        ):
            raise ValueError(
                f"El anchor "
                f"{anchor_fact_id} "
                f"no existe."
            )

        anchor = facts_by_id[
            anchor_fact_id
        ]

        if (
            anchor["fact_type"]
            != "action"
        ):
            raise ValueError(
                "El anchor temporal debe "
                "ser un hecho de tipo action."
            )

        anchor_time = anchor[
            "time_s"
        ]

        selected = []

        for fact in facts:

            if (
                fact["fact_type"]
                == "limitation"
            ):
                continue

            if relation == "after":

                if (
                    fact["time_s"]
                    >= anchor_time
                ):
                    selected.append(
                        fact
                    )

            elif relation == "before":

                if (
                    fact["time_s"]
                    <= anchor_time
                ):
                    selected.append(
                        fact
                    )

            else:
                raise ValueError(
                    "Relación temporal "
                    f"no válida: {relation}"
                )

    selected.sort(
        key=lambda fact: (
            fact["time_s"],
            fact["fact_id"]
        )
    )

    return [
        fact["fact_id"]
        for fact in selected
    ]


def derive_topics(
    facts,
    fact_ids
):

    facts_by_id = {
        fact["fact_id"]: fact
        for fact in facts
    }

    topics = []

    for fact_id in fact_ids:

        fact = facts_by_id[
            fact_id
        ]

        for topic in fact.get(
            "knowledge_topics",
            []
        ):

            if topic not in topics:
                topics.append(
                    topic
                )

    return topics


def select_knowledge(
    knowledge,
    topics
):

    requested_topics = set(
        topics
    )

    selected_ids = []

    for entry in knowledge:

        if (
            entry["topic"]
            in requested_topics
        ):
            selected_ids.append(
                entry["knowledge_id"]
            )

    return selected_ids


def create_question_plan(context, question, question_id, *, classifier=None):
    """Classify with Qwen, then resolve evidence deterministically in this context."""
    question, question_id = question.strip(), question_id.strip()
    if not question or not question_id:
        raise ValueError("La pregunta y question_id no pueden estar vacíos.")
    validate_context(context)
    schema = load_json(SCHEMA_PATH)
    scenario_facts = context['scenario_facts']
    available_topics = sorted({topic for fact in scenario_facts for topic in fact.get('knowledge_topics', [])})
    action_candidates = [{'fact_id': fact['fact_id'], 'time_s': fact['time_s'], 'statement': fact['statement']} for fact in scenario_facts if fact['fact_type'] == 'action']
    prompt = f"""
Eres el planificador de preguntas de SimuFire AI.

NO respondas la pregunta.
NO expliques el incendio.
NO inventes datos.
NO establezcas causalidad.

Tu tarea es únicamente clasificar la pregunta.

INTENCIONES:

timeline:
preguntas sobre qué ocurrió antes o después
de una acción o durante la evolución temporal.

causality:
preguntas sobre si una acción o fenómeno
produjo, provocó o causó otro.

concept:
preguntas sobre qué significa un concepto.

observation:
preguntas sobre valores o cambios medidos.

condition:
preguntas sobre si una condición o fenómeno
ha sido detectado o estaba presente en la
simulación.

uncertainty:
preguntas sobre qué puede o no concluirse.

general:
combinación de varios tipos.

PRIORIDAD ENTRE INTENCIONES:

- condition tiene prioridad sobre timeline cuando
  la pregunta principal es si una condición o
  fenómeno estaba presente, aunque incluya
  expresiones temporales como "antes de",
  "después de" o "en ese momento".

- timeline se usa cuando la pregunta principal es
  qué ocurrió, qué cambió o qué sucedió antes o
  después de una acción.

Ejemplos:

"¿El incendio estaba limitado por ventilación
antes de abrir la puerta?"
-> intent = condition
-> topics = ["ventilation_limited"]

"¿Qué ocurrió antes de abrir la puerta?"
-> intent = timeline
-> topics = []

REGLAS:

- Para observation selecciona solamente
  el topic de la variable preguntada.

- Para condition selecciona solamente
  el topic de la condición preguntada.

- Una condition detectada debe conservar
  el grado de certeza del Grounded Fact.
  No conviertas "patrón compatible con"
  en una afirmación absoluta.

- Para concept selecciona solamente
  el topic del concepto preguntado.

- Para causality:
    * topics debe contener el fenómeno EFECTO
      sobre el que se pregunta.
    * Si la causa propuesta corresponde a una
      acción disponible, selecciona esa acción
      como anchor_fact_id.
    * No añadas manualmente topics derivados
      de la acción. El código lo hará.

- Para timeline:
    * topics debe ser [].
    * timeline_relation debe ser
      before, after o all.
    * Si es before o after, selecciona
      la acción correspondiente como
      anchor_fact_id.

- Para intent que no sea timeline ni causality:
    timeline_relation = "not_applicable"
    anchor_fact_id = null.

- Para causality:
    timeline_relation = "not_applicable".

- No añadas temas relacionados solo porque
  puedan tener interés general.

- Devuelve exclusivamente el JSON solicitado.

schema_version = "0.3"
scenario_id = "{context["scenario_id"]}"
question_id = "{question_id}"

TEMAS DISPONIBLES:

{json.dumps(
    available_topics,
    ensure_ascii=False
)}

ACCIONES DISPONIBLES:

{json.dumps(
    action_candidates,
    indent=2,
    ensure_ascii=False
)}

PREGUNTA:

{question}
"""
    raw = (classifier or call_ollama)(prompt, schema)
    try:
        plan = json.loads(raw)
    except json.JSONDecodeError:
        raise ValueError('Qwen no devolvió JSON válido.')
    if not isinstance(plan, dict):
        raise ValueError('Qwen debe devolver un objeto JSON.')
    plan['schema_version'] = '0.3'
    plan['scenario_id'] = context['scenario_id']
    plan['question_id'] = question_id
    validator = Draft202012Validator(schema)
    errors = list(validator.iter_errors(plan))
    if errors:
        raise ValueError(f'El plan no cumple el schema: {errors[0].message}')
    intent = plan['intent']
    include_limitations = intent in ['causality', 'uncertainty']
    action_ids = {item['fact_id'] for item in action_candidates}
    try:
        if intent == 'timeline':
            if plan['timeline_relation'] not in ['before', 'after', 'all']:
                raise ValueError('Una pregunta timeline necesita una relación temporal válida.')
            if plan['timeline_relation'] in ['before', 'after'] and plan['anchor_fact_id'] not in action_ids:
                raise ValueError('anchor_fact_id no corresponde a una acción disponible.')
            fact_ids = select_timeline_facts(scenario_facts, plan['timeline_relation'], plan['anchor_fact_id'])
            topics = derive_topics(scenario_facts, fact_ids)
        else:
            if not plan['topics']:
                raise ValueError('La pregunta necesita al menos un topic.')
            topics = list(plan['topics'])
            if intent == 'causality':
                anchor_fact_id = plan.get('anchor_fact_id')
                if anchor_fact_id is not None:
                    if anchor_fact_id not in action_ids:
                        raise ValueError('El anchor causal no corresponde a una acción disponible.')
                    action_topics = derive_topics_from_action(scenario_facts, anchor_fact_id)
                    for topic in action_topics:
                        if topic not in topics:
                            topics.append(topic)
            fact_ids = select_topic_facts(scenario_facts, topics, include_limitations, intent)
    except (ValueError, KeyError, RuntimeError) as error:
        raise ValueError(str(error)) from error
    knowledge_ids = select_knowledge(context['technical_knowledge'], topics)
    result = {'schema_version': '0.3', 'scenario_id': context['scenario_id'], 'question_id': question_id, 'intent': intent, 'topics': topics, 'include_limitations': include_limitations, 'timeline_relation': plan['timeline_relation'], 'anchor_fact_id': plan['anchor_fact_id'], 'resolved_fact_ids': fact_ids, 'resolved_knowledge_ids': knowledge_ids}
    result['source_context_sha256'] = context_fingerprint(context)
    if 'run_id' in context:
        result['run_id'] = context['run_id']
    validate_plan_context(result, context, question_id)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--question', required=True)
    parser.add_argument('--question-id', default='question_001')
    parser.add_argument('--context', type=Path, default=CONTEXT_PATH)
    parser.add_argument('--output-dir', type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()
    try:
        context = load_json(args.context)
        result = create_question_plan(context, args.question, args.question_id)
        args.output_dir.mkdir(parents=True, exist_ok=True)
        output_path = args.output_dir / f"{context['scenario_id']}_{result['question_id']}.json"
        output_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    except (OSError, ValueError, TimeoutError) as error:
        parser.exit(1, f'ERROR: {error}\n')
    print(f"OK: plan de pregunta válido ({result['intent']})")
    print(f"Hechos: {', '.join(result['resolved_fact_ids']) or '-'}")
    print(f"Conocimiento: {', '.join(result['resolved_knowledge_ids']) or '-'}")
    print(f'Guardado en: {output_path}')


if __name__ == '__main__':
    main()
