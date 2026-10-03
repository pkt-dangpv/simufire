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


if __package__:
    from .question_scope import interpret_explicit_scope, resolve_question, available_rooms
else:
    from question_scope import interpret_explicit_scope, resolve_question, available_rooms


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
    schema = load_json(BASE_DIR / "schemas/question_classification.schema.json")
    scenario_facts = context['scenario_facts']
    available_topics = schema['properties']['topics']['items']['enum']
    compartments = context.get('analysis_coverage', {}).get('compartments', [{'id': room, 'name': room} for room in sorted(available_rooms(context))])
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
-> scope.time_relation = "before"
-> scope.anchor_fact_id = acción de apertura disponible

"¿Qué ocurrió antes de abrir la puerta?"
-> intent = timeline
-> topics = []

REGLAS:

- Para observation selecciona solamente
  el topic de la variable preguntada.
  observation se refiere a valores o cambios de HRR, temperatura, oxígeno
  o altura de interfaz. La presencia de un fenómeno no es observation.

- Para condition selecciona solamente
  el topic de la condición preguntada.
  "¿Hubo backdraft?", "¿Se produjo flashover?" y "¿Se detectó rollover?"
  son condition, aunque el analizador no pueda evaluarlos.
  Ejemplo: "¿Hubo backdraft?" -> intent="condition", topics=["backdraft"],
  scope all sin ancla, clarification_needed="none".

- Una condition detectada debe conservar
  el grado de certeza del Grounded Fact.
  No conviertas "patrón compatible con"
  en una afirmación absoluta.

- Para concept selecciona solamente
  el topic del concepto preguntado.
  "¿Qué significa incendio limitado por ventilación?" -> intent="concept",
  topics=["ventilation_limited"], scope all sin ancla y sin compartimento.

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

CONTRATO DE ÁMBITO:

- Devuelve scope con compartment_id, time_relation, anchor_fact_id,
  start_time_s y end_time_s. Incluye clarification_needed siempre.
- Sin límites pedidos: time_relation="all", ancla y tiempos=null.
- Antes/después de una acción: time_relation="before"/"after",
  scope.anchor_fact_id=acción; start_time_s=end_time_s=null.
  Esto también se aplica a condition, observation, uncertainty y general.
- Antes/después de segundos explícitos: ancla=null y solo end_time_s/start_time_s.
- Entre dos instantes: time_relation="between", ancla=null, inicio y fin.
- En un instante: time_relation="at", ancla=null, inicio=fin.
- compartment_id solo puede ser uno de los compartimentos disponibles;
  null significa todos los compartimentos, sin elegir una habitación arbitraria.
- Para concept no hay afirmación sobre la simulación: usa scope all sin ancla.
- Para timeline copia la relación y ancla del scope en timeline_relation y
  anchor_fact_id; para between/at usa timeline_relation="all".
- Para causality el anchor_fact_id principal representa la causa propuesta;
  el scope.anchor_fact_id solo representa el límite temporal de la pregunta.
- Si falta identificar puerta, apertura repetida, habitación o tema, usa
  clarification_needed="action", "compartment" o "topic"; "time" para un
  periodo ambiguo. Usa "none" si la pregunta es resoluble.
- Una variable explícita y un intervalo numérico no necesitan aclaración.
  "¿Cómo cambió la temperatura entre 179 y 195 segundos?" -> observation,
  topics=["temperature"], scope between 179 y 195, ancla=null,
  clarification_needed="none".
- No elijas la primera de varias aperturas si el usuario no la distingue.
- Los temas de la lista se pueden preguntar aunque no haya detección: el código
  distingue evidencia, cobertura insuficiente y capacidades no disponibles.

COMPARTIMENTOS DISPONIBLES:
{json.dumps(compartments, ensure_ascii=False)}

schema_version = "0.4"
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
    plan['schema_version'] = '0.4'
    plan['scenario_id'] = context['scenario_id']
    plan['question_id'] = question_id
    context_fingerprint(plan)
    validator = Draft202012Validator(schema)
    errors = list(validator.iter_errors(plan))
    if errors:
        raise ValueError(f'El plan no cumple el schema: {errors[0].message}')
    interpreted = interpret_explicit_scope(context, question, plan)
    resolution = resolve_question(context, interpreted)
    result = {
        "schema_version": "0.4", "scenario_id": context["scenario_id"],
        "question_id": question_id, "question": question,
        "intent": interpreted["intent"],
        "timeline_relation": interpreted["timeline_relation"],
        "anchor_fact_id": interpreted["anchor_fact_id"],
        **resolution, "source_context_sha256": context_fingerprint(context),
    }
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
