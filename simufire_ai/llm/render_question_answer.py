import argparse
import json
import sys
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
sys.path.insert(0, str(BASE_DIR))

from llm.measurement_text import evidence_for_question, measurement_text, criterion_text, geometry_text, comparison_text, concurrent_changes, recovery_comparison, response_status, hrr_increase_summary

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


def render_condition(facts, include_observations=False):

    condition_facts = [
        fact
        for fact in facts
        if (
            fact["fact_type"]
            in (("association", "observation") if include_observations else ("association",))
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




TOPIC_LABELS = {
    "hrr": "un aumento del HRR", "temperature": "un aumento de temperatura",
    "smoke_layer": "un descenso de la interfaz entre capas", "oxygen": "un aumento de oxígeno",
    "ventilation": "un aumento de ventilación", "ventilation_limited": "un incendio limitado por ventilación",
    "flashover": "flashover", "backdraft": "backdraft", "rollover": "rollover",
}


def render_assessment(assessment):
    label = TOPIC_LABELS.get(assessment["topic"], assessment["topic"])
    status = assessment["status"]
    if status == "not_detected":
        return f"No se detectó {label} en las ventanas evaluables del ámbito solicitado. Esto no demuestra su ausencia."
    if status == "insufficient_data":
        if assessment["reason"] == "measurement_crosses_time_boundary":
            return f"Las mediciones de {label} cruzan el límite temporal solicitado y no permiten aislar ese periodo. No se puede concluir que esté ausente."
        return f"Los datos disponibles no permiten evaluar {label} en el ámbito solicitado. No se puede concluir que esté ausente."
    if status == "unsupported":
        return f"La evaluación de {label} para esta pregunta no está disponible en el analizador. No se puede confirmar ni descartar este fenómeno."
    if status == "knowledge_unavailable":
        return f"No hay conocimiento técnico disponible sobre {label} en esta ejecución."
    return None


def render_question_answer(context, plan):
    """Render only the bound context, without I/O or a language model call."""
    validate_context(context)
    validate_plan_context(plan, context, plan.get('question_id') if isinstance(plan, dict) else None)
    facts_by_id = {fact['fact_id']: fact for fact in context['scenario_facts']}
    knowledge_by_id = {item['knowledge_id']: item for item in context['technical_knowledge']}
    events_by_id = {event['event_id']: event for event in context.get('source_events', [])}
    selected_facts = []
    scoped = plan["schema_version"] == "0.4"
    primary_ids = plan["primary_fact_ids"] if scoped else plan["resolved_fact_ids"]
    for fact_id in primary_ids:
        if fact_id not in facts_by_id:
            raise ValueError(f'No existe {fact_id} en el contexto seleccionado')
        selected_facts.append(facts_by_id[fact_id])
    selected_knowledge = []
    for knowledge_id in plan['resolved_knowledge_ids']:
        if knowledge_id not in knowledge_by_id:
            raise ValueError(f'No existe {knowledge_id} en el contexto seleccionado')
        selected_knowledge.append(knowledge_by_id[knowledge_id])
    if scoped:
        if __package__:
            from .question_scope import available_rooms, fact_rooms
        else:
            from question_scope import available_rooms, fact_rooms
        if len(available_rooms(context)) > 1:
            selected_facts = [dict(fact, statement="En " + (plan["scope"]["compartment_id"] or ", ".join(sorted(fact_rooms(context, fact)))) + ": " + fact["statement"])
                              if fact_rooms(context, fact) else fact for fact in selected_facts]
    actions = [fact for fact in selected_facts if fact['fact_type'] == 'action']
    associations = [fact for fact in selected_facts if fact['fact_type'] == 'association']
    observations = [fact for fact in selected_facts if fact['fact_type'] == 'observation']
    limitations = [fact for fact in selected_facts if fact['fact_type'] == 'limitation']
    intent = plan['intent']
    answer_parts = []
    measured_changes, comparison = evidence_for_question(context, plan)
    from llm.teaching_context import teaching_context, teaching_text
    teaching = teaching_context(context, plan, measured_changes) if scoped else None
    mechanism_explanation = (intent == "causality" and "smoke_layer" in plan["topics"]
                             and measured_changes and any("penacho" in item["content"] for item in selected_knowledge))
    concurrent = []
    if mechanism_explanation:
        concurrent = concurrent_changes(context, measured_changes, ["hrr", "temperature"])
    elif intent in ("condition", "observation") and plan["topics"] == ["hrr"] and plan.get("answer_status") == "not_detected":
        concurrent = concurrent_changes(context, measured_changes, ["temperature", "smoke_layer"])
    clarification = scoped and plan["answer_status"] == "clarification_required"
    empty_scoped = scoped and not primary_ids and intent != "concept"
    if clarification:
        prompts = {
            "action": "¿A qué apertura te refieres? Indica el elemento y el instante.",
            "compartment": "¿Qué compartimento quieres analizar? Indica su nombre o identificador.",
            "time": "¿Qué periodo quieres analizar? Indica un intervalo o un instante concreto.",
            "topic": "¿Qué variable o fenómeno quieres consultar?",
        }
        answer_parts.append(prompts[plan["clarification_needed"]])
    elif empty_scoped:
        if intent == "timeline":
            answer_parts.append("No hay hechos registrados que permitan responder en el ámbito solicitado. No se puede reconstruir lo ocurrido con estos datos.")
    elif intent == 'concept':
        if not selected_knowledge:
            answer_parts.append('No hay conocimiento técnico disponible para responder a esta pregunta.')
        else:
            for item in selected_knowledge:
                prefix = "Como marco teórico general: " if scoped else ""
                answer_parts.append(prefix + item['content'])
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
        answer_parts.append(render_condition(selected_facts, include_observations=scoped))
    elif intent == 'timeline':
        timeline_facts = [fact for fact in selected_facts if fact['fact_type'] != 'limitation']
        if not timeline_facts:
            answer_parts.append('No hay hechos temporales disponibles para responder.')
        else:
            answer_parts.append(render_timeline(timeline_facts))
    elif intent == 'causality':
        if (limitations or scoped) and not (measured_changes and 'smoke_layer' in plan['topics']):
            answer_parts.append('Con los datos disponibles no puede afirmarse esa relación causal.')
        evidence = actions + associations + observations
        if evidence:
            evidence_text = ' '.join((fact['statement'] for fact in evidence))
            answer_parts.append('Lo que sí muestra la simulación es lo siguiente: ' + evidence_text)
        if limitations and not mechanism_explanation:
            limitation_text = ' '.join((fact['statement'] for fact in limitations))
            answer_parts.append('Limitación del análisis: ' + limitation_text)
    elif intent == 'uncertainty':
        if limitations:
            answer_parts.append(' '.join((fact['statement'] for fact in limitations)))
        else:
            answer_parts.append('No hay una limitación específica registrada para esta pregunta.')
            if scoped:
                answer_parts.append("Esto no autoriza a establecer una relación causal con los datos disponibles.")
    else:
        evidence = actions + associations + observations
        if evidence:
            answer_parts.append(' '.join((fact['statement'] for fact in evidence)))
        if limitations:
            answer_parts.append(' '.join((fact['statement'] for fact in limitations)))
    if scoped and not clarification:
        if intent == "causality" and empty_scoped:
            answer_parts.insert(0, "Con los datos disponibles no puede afirmarse esa relación causal.")
        for assessment in plan["topic_assessments"]:
            numeric = [change for change in measured_changes if change["topic"] == assessment["topic"]
                       and change["compartment_id"] == assessment.get("compartment_id")]
            # 'not_detected' remains the detector status. Endpoint measurements
            # answer the physical-change question independently of that status.
            if numeric and assessment["status"] == "not_detected" and any(change["delta"] != 0 for change in numeric):
                # Actual values have answered the change question. No absence
                # disclaimer: the criterion note already explains the alert.
                note = None
            elif numeric and assessment["status"] == "not_detected":
                note = ("El detector no activó su regla. Esto no demuestra su ausencia en todo el periodo; "
                        "las muestras mostradas tienen los mismos valores.")
            elif (assessment["topic"] == "ventilation_limited" and intent in ("condition", "general")
                  and recovery_comparison(comparison)):
                note = "Queda por determinar cuánto dura esta recuperación y cuál es el régimen posterior."
            elif assessment['topic'] == 'ventilation_limited' and teaching['preopening_observations']:
                note = None  # Numeric prehistory and the repeated-action limitation explain coverage.
            else:
                note = render_assessment(assessment)
            if note:
                if len(available_rooms(context)) > 1 and assessment.get("compartment_id"):
                    note = "En " + assessment["compartment_id"] + ": " + note
                answer_parts.append(note)
    if measured_changes:
        paragraphs = []
        for change in measured_changes:
            paragraphs.append(measurement_text(change))
            if intent in ("condition", "observation"):
                note = criterion_text(change)
                if note: paragraphs.append(note)
            if intent == "causality" and change["topic"] == "smoke_layer":
                paragraphs.append(geometry_text(change))
        if concurrent:
            paragraphs.append("En los mismos pares de muestras se observan además estos cambios, sin atribuir causalidad entre ellos: "
                              + " ".join(measurement_text(change) for change in concurrent))
        answer_parts = paragraphs + answer_parts
    summary = hrr_increase_summary(plan, measured_changes) if scoped else None
    if summary:
        answer_parts.insert(0, summary)
    if comparison:
        answer_parts.insert(0, comparison_text(comparison))
    if teaching:
        answer_parts.extend(teaching_text(teaching))
    knowledge_was_used = False
    if intent in ['condition', 'causality', 'uncertainty', 'general'] and selected_knowledge:
        theory_parts = []
        for item in selected_knowledge:
            theory_parts.append(item['content'])
        answer_parts.append('Como marco teórico general: ' + ' '.join(theory_parts))
        knowledge_was_used = True
    if intent == 'concept':
        knowledge_was_used = bool(selected_knowledge)
    if mechanism_explanation and any(change["topic"] == "smoke_layer" and change["delta"] < 0 for change in measured_changes):
        answer_parts.append("Conclusión en la representación de dos zonas: el descenso corresponde al llenado de la capa superior, "
                            "alimentada por los gases del incendio y el aire arrastrado por el penacho térmico, "
                            "con una contribución adicional posible de la expansión por calentamiento. "
                            "La limitación pendiente es cuantitativa: no puede afirmarse cuánto aporta cada término "
                            "del balance con estas muestras. Esta explicación del modelo no atribuye por sí sola "
                            "todo el descenso al aumento del HRR.")
    elif measured_changes and intent == "causality" and "smoke_layer" in plan["topics"]:
        answer_parts.append("El cambio de interfaz permite calcular una variación geométrica neta. "
                            "Con los datos disponibles no puede afirmarse una relación causal específica "
                            "ni desglosar los términos del balance.")
    answer = '\n\n'.join(answer_parts)
    source_ids = []
    if knowledge_was_used:
        for item in selected_knowledge:
            source_id = item['source']['source_id']
            if source_id not in source_ids:
                source_ids.append(source_id)
    result = {'schema_version': plan['schema_version'], 'scenario_id': plan['scenario_id'], 'question_id': plan['question_id'], 'intent': intent, 'topics': plan['topics'], 'fact_ids': primary_ids, 'knowledge_ids': plan['resolved_knowledge_ids'], 'answer': answer, 'source_ids': source_ids}
    if "measurement_snapshot" in context and scoped:
        result["measured_changes"] = measured_changes
        result["concurrent_measurements"] = concurrent
        result["detector_assessment_status"] = plan["answer_status"]
        result["response_status"] = response_status(plan, measured_changes, comparison, teaching)
        result['teaching_context'] = teaching
        result["opening_comparison"] = comparison
    result['source_context_sha256'] = context_fingerprint(context)
    result['fact_metadata'] = [{key: fact[key] for key in ('fact_id', 'certainty', 'causal') if key in fact} for fact in selected_facts]
    if scoped:
        for key in ("answer_status", "topic_assessments", "scope", "supporting_fact_ids"):
            result[key] = plan[key]
        result["supporting_fact_metadata"] = [
            {key: facts_by_id[fact_id][key] for key in ("fact_id", "certainty", "causal")}
            for fact_id in plan["supporting_fact_ids"]
        ]
        result["fact_provenance"] = [
            {key: fact[key] for key in ("fact_id", "time_s", "compartment_id", "compartment_ids", "event_ids", "evidence_interval_s") if key in fact}
            for fact in selected_facts
        ]
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
