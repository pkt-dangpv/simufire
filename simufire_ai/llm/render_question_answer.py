import argparse
import json
from pathlib import Path

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

QUESTION_PLANS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "question_plans"
)



OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "question_answers"
)


TOPIC_EVIDENCE_KEYWORDS = {
    "hrr": [
        "hrr"
    ],
    "temperature": [
        "temperature",
        "temp"
    ],
    "smoke_layer": [
        "interface",
        "smoke_layer"
    ],
    "oxygen": [
        "oxygen",
        "o2"
    ]
}


def load_json(path: Path):

    with path.open(
        "r",
        encoding="utf-8"
    ) as f:

        return json.load(f)






def format_number(value):

    if isinstance(
        value,
        int
    ):
        return str(
            value
        )

    if isinstance(
        value,
        float
    ):

        if value.is_integer():

            return str(
                int(value)
            )

        return (
            f"{value:.3f}"
            .rstrip("0")
            .rstrip(".")
        )

    return str(
        value
    )


def evidence_matches_topic(
    variable,
    topic
):

    variable_lower = (
        variable.lower()
    )

    keywords = (
        TOPIC_EVIDENCE_KEYWORDS
        .get(
            topic,
            []
        )
    )

    return any(
        keyword
        in variable_lower
        for keyword
        in keywords
    )


def find_numeric_change(
    fact,
    topics,
    events_by_id
):

    for event_id in fact.get(
        "event_ids",
        []
    ):

        event = events_by_id.get(
            event_id
        )

        if not event:
            continue

        for evidence in event.get(
            "evidence",
            []
        ):

            if (
                "previous_value"
                not in evidence
            ):
                continue

            if (
                "value"
                not in evidence
            ):
                continue

            previous = evidence[
                "previous_value"
            ]

            current = evidence[
                "value"
            ]

            if not isinstance(
                previous,
                (int, float)
            ):
                continue

            if not isinstance(
                current,
                (int, float)
            ):
                continue

            variable = evidence.get(
                "variable",
                ""
            )

            matched_topic = None

            for topic in topics:

                if evidence_matches_topic(
                    variable,
                    topic
                ):

                    matched_topic = (
                        topic
                    )

                    break

            if matched_topic is None:
                continue

            return {
                "topic":
                    matched_topic,

                "previous":
                    previous,

                "current":
                    current,

                "delta":
                    current
                    - previous,

                "unit":
                    evidence.get(
                        "unit",
                        ""
                    ),

                "variable":
                    variable
            }

    return None


def render_change(change):

    delta = change[
        "delta"
    ]

    unit = change[
        "unit"
    ]

    topic = change.get(
        "topic"
    )

    magnitude = abs(
        delta
    )

    # -----------------------------------------------
    # TEMPERATURA
    # -----------------------------------------------

    if topic == "temperature":

        if unit.lower() in [
            "c",
            "°c",
            "celsius",
            "degc"
        ]:

            unit = "°C"

        value_text = (
            f"{format_number(magnitude)} "
            f"{unit}"
        ).strip()

    # -----------------------------------------------
    # OXÍGENO
    #
    # 14.1 % -> 16.8 % = 2.7 puntos porcentuales.
    # -----------------------------------------------

    elif (
        topic == "oxygen"
        and unit == "%"
    ):

        value_text = (
            f"{format_number(magnitude)} "
            "puntos porcentuales"
        )

    # -----------------------------------------------
    # RESTO
    # -----------------------------------------------

    else:

        value_text = (
            format_number(
                magnitude
            )
        )

        if unit:

            value_text += (
                f" {unit}"
            )

    if delta > 0:

        return (
            "Esto supone un aumento "
            f"de {value_text}."
        )

    if delta < 0:

        return (
            "Esto supone una disminución "
            f"de {value_text}."
        )

    return (
        "No se produjo variación."
    )


def render_timeline(facts):

    facts = sorted(
        facts,
        key=lambda fact: (
            fact["time_s"],
            fact["fact_id"]
        )
    )

    groups = {}

    for fact in facts:

        time_s = fact[
            "time_s"
        ]

        groups.setdefault(
            time_s,
            []
        )

        groups[
            time_s
        ].append(
            fact
        )

    paragraphs = []

    for time_s in sorted(
        groups
    ):

        statements = []

        time_text = (
            f" en t="
            f"{format_number(time_s)} s"
        )

        for fact in groups[
            time_s
        ]:

            statement = fact[
                "statement"
            ]

            statement = (
                statement.replace(
                    time_text,
                    ""
                )
            )

            statements.append(
                statement
            )

        paragraphs.append(
            f"En t="
            f"{format_number(time_s)} s: "
            + " ".join(
                statements
            )
        )

    return "\n\n".join(
        paragraphs
    )


def render_condition(facts):

    condition_facts = [
        fact
        for fact in facts
        if (
            fact["fact_type"]
            == "association"
        )
    ]

    if not condition_facts:

        return (
            "No hay una condición "
            "detectada que permita "
            "responder a esta pregunta."
        )

    certainty_labels = {
        "certain":
            "cierta",

        "high":
            "alta",

        "moderate":
            "moderada",

        "limited":
            "limitada"
    }

    paragraphs = []

    for fact in condition_facts:

        paragraph = fact[
            "statement"
        ]

        certainty = fact.get(
            "certainty"
        )

        if certainty:

            label = (
                certainty_labels.get(
                    certainty,
                    certainty
                )
            )

            paragraph += (
                " La certeza asignada "
                "a esta detección es "
                f"{label}."
            )

        paragraphs.append(
            paragraph
        )

    return "\n\n".join(
        paragraphs
    )




def render_question_answer(context, plan):
    """Render only the bound context, without I/O or a language model call."""
    validate_context(context)
    validate_plan_context(plan, context, plan.get('question_id'))
    facts_by_id = {fact['fact_id']: fact for fact in context['scenario_facts']}
    knowledge_by_id = {item['knowledge_id']: item for item in context['technical_knowledge']}
    events_by_id = {event['event_id']: event for event in context.get('source_events', [])}
    selected_facts = []
    for fact_id in plan['resolved_fact_ids']:
        if fact_id not in facts_by_id:
            raise ValueError(f'No existe {fact_id} en el contexto seleccionado')
        selected_facts.append(facts_by_id[fact_id])
    selected_knowledge = []
    for knowledge_id in plan['resolved_knowledge_ids']:
        if knowledge_id not in knowledge_by_id:
            raise ValueError(f'No existe {knowledge_id} en el contexto seleccionado')
        selected_knowledge.append(knowledge_by_id[knowledge_id])
    actions = [fact for fact in selected_facts if fact['fact_type'] == 'action']
    associations = [fact for fact in selected_facts if fact['fact_type'] == 'association']
    observations = [fact for fact in selected_facts if fact['fact_type'] == 'observation']
    limitations = [fact for fact in selected_facts if fact['fact_type'] == 'limitation']
    intent = plan['intent']
    answer_parts = []
    if intent == 'concept':
        if not selected_knowledge:
            answer_parts.append('No hay conocimiento técnico disponible para responder a esta pregunta.')
        else:
            for item in selected_knowledge:
                answer_parts.append(item['content'])
    elif intent == 'observation':
        if not observations:
            answer_parts.append('No hay una observación disponible para responder a esta pregunta.')
        else:
            for fact in observations:
                paragraph = fact['statement']
                change = find_numeric_change(fact, plan['topics'], events_by_id)
                if change:
                    paragraph += ' ' + render_change(change)
                answer_parts.append(paragraph)
    elif intent == 'condition':
        answer_parts.append(render_condition(selected_facts))
    elif intent == 'timeline':
        timeline_facts = [fact for fact in selected_facts if fact['fact_type'] != 'limitation']
        if not timeline_facts:
            answer_parts.append('No hay hechos temporales disponibles para responder.')
        else:
            answer_parts.append(render_timeline(timeline_facts))
    elif intent == 'causality':
        if limitations:
            answer_parts.append('Con los datos disponibles no puede afirmarse esa relación causal.')
        evidence = actions + associations + observations
        if evidence:
            evidence_text = ' '.join((fact['statement'] for fact in evidence))
            answer_parts.append('Lo que sí muestra la simulación es lo siguiente: ' + evidence_text)
        if limitations:
            limitation_text = ' '.join((fact['statement'] for fact in limitations))
            answer_parts.append('Limitación del análisis: ' + limitation_text)
    elif intent == 'uncertainty':
        if limitations:
            answer_parts.append(' '.join((fact['statement'] for fact in limitations)))
        else:
            answer_parts.append('No hay una limitación específica registrada para esta pregunta.')
    else:
        evidence = actions + associations + observations
        if evidence:
            answer_parts.append(' '.join((fact['statement'] for fact in evidence)))
        if limitations:
            answer_parts.append(' '.join((fact['statement'] for fact in limitations)))
    knowledge_was_used = False
    if intent in ['condition', 'causality', 'uncertainty', 'general'] and selected_knowledge:
        theory_parts = []
        for item in selected_knowledge:
            theory_parts.append(item['content'])
        answer_parts.append('Como marco teórico general: ' + ' '.join(theory_parts))
        knowledge_was_used = True
    if intent == 'concept':
        knowledge_was_used = bool(selected_knowledge)
    answer = '\n\n'.join(answer_parts)
    source_ids = []
    if knowledge_was_used:
        for item in selected_knowledge:
            source_id = item['source']['source_id']
            if source_id not in source_ids:
                source_ids.append(source_id)
    result = {'schema_version': '0.3', 'scenario_id': plan['scenario_id'], 'question_id': plan['question_id'], 'intent': intent, 'topics': plan['topics'], 'fact_ids': plan['resolved_fact_ids'], 'knowledge_ids': plan['resolved_knowledge_ids'], 'answer': answer, 'source_ids': source_ids}
    result['source_context_sha256'] = context_fingerprint(context)
    result['fact_metadata'] = [{key: fact[key] for key in ('fact_id', 'certainty', 'causal') if key in fact} for fact in selected_facts]
    if 'run_id' in context:
        result['run_id'] = context['run_id']
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--question-id', default='question_001')
    parser.add_argument('--context', type=Path, default=CONTEXT_PATH)
    parser.add_argument('--output-dir', type=Path, default=OUTPUT_DIR)
    parser.add_argument('--plan-dir', type=Path, default=QUESTION_PLANS_DIR)
    args = parser.parse_args()
    try:
        context = load_json(args.context)
        validate_context(context)
        question_id = args.question_id.strip()
        plan = load_json(args.plan_dir / f"{context['scenario_id']}_{question_id}.json")
        validate_plan_context(plan, context, question_id)
        result = render_question_answer(context, plan)
        args.output_dir.mkdir(parents=True, exist_ok=True)
        output_path = args.output_dir / f"{context['scenario_id']}_{question_id}_answer.json"
        output_path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
    except (OSError, ValueError) as error:
        parser.exit(1, f'ERROR: {error}\n')
    print('OK: respuesta generada')
    print(result['answer'])
    if result['source_ids']:
        print('FUENTES: ' + ', '.join(result['source_ids']))
    print(f'Guardado en: {output_path}')


if __name__ == '__main__':
    main()
