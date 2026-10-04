"""Deterministic scope resolution and response status for question contract 0.4."""

import copy
import re
import unicodedata

DEFAULT_SCOPE = {
    "compartment_id": None, "time_relation": "all", "anchor_fact_id": None,
    "start_time_s": None, "end_time_s": None,
}
SUPPORTED_TOPICS = {"hrr", "temperature", "smoke_layer", "oxygen", "ventilation", "ventilation_limited"}
TOPIC_LITERALS = {
    "hrr": ("hrr",), "temperature": ("temperatura", "temperature"),
    "oxygen": ("oxigeno", "oxygen"), "smoke_layer": ("interfaz", "capa de humo"),
    "ventilation": ("ventilacion",),
    "ventilation_limited": ("limitado por ventilacion", "limitada por ventilacion", "ventilacion limitada"),
    "flashover": ("flashover",), "backdraft": ("backdraft",), "rollover": ("rollover",),
}
BEFORE_CUE = r"(?:antes(?:\s+de)?|previ[oa]s?\s+a|anterior(?:es)?\s+a|con\s+anterioridad\s+a)"
AFTER_CUE = r"(?:despues(?:\s+de)?|posterior(?:es)?\s+a|tras|luego\s+de)"


def explicit_causal_effect(text):
    """Identify the requested effect in a narrow active causal question.

    This only chooses a topic. It establishes neither the proposed cause nor
    any causal relationship, and does not manufacture facts or action anchors.
    Negations, alternatives and multiple clauses stay with the classifier.
    """
    match = re.fullmatch(
        r"(?P<cause>(?:el|la)\s+(?:aumento|incremento|crecimiento|descenso|reduccion)\s+[^?!.,;:]+?)"
        r"\s+(?:causo|provoco)\s+(?P<effect>[^?!.,;:]+?)[?!.]*", text)
    if not match or re.search(r"\b(?:no|nunca|ni|o|si|aunque|segun|y)\b", text):
        return None
    if len(re.findall(r"\b(?:causo|provoco)\b", text)) != 1:
        return None
    parts = []
    for clause in (match['cause'], match['effect']):
        topics = {topic for topic, terms in TOPIC_LITERALS.items()
                  if any(re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", clause)
                         for term in terms)}
        if len(topics) != 1 or not topics <= {"hrr", "temperature", "oxygen", "smoke_layer"}:
            return None
        parts.append(next(iter(topics)))
    return parts[1]


def explicit_explanation_effect(text):
    """Constrain direct why/due requests, without supplying a physical cause."""
    why = re.fullmatch(r"por\s+que\s+(?:aumento|descendio|cambio|vario|subio|bajo)\s+"
                       r"(?P<effect>[^?!.,;:]+?)[?!]*", text)
    due = re.fullmatch(r"(?P<effect>(?:el|la)\s+[^?!.,;:]+?)\s+debido\s+a(?:l)?\s+"
                       r"(?P<cause>[^?!.,;:]+?)[?!]*", text)
    match = why or due
    if not match or re.search(r"\b(?:no|nunca|ni|o|si|aunque|segun|concepto|definicion|significa)\b", text):
        return None
    if due and not re.search(r"\b(?:aumento|descendio|cambio|vario|subio|bajo)\b", due['effect']):
        return None
    # A numerical interval can contain 'y'; it does not introduce a second effect.
    clauses = [match['effect']] + ([due['cause']] if due else [])
    for clause in clauses:
        without_interval = re.sub(r"\bentre\s+\d+(?:[.,]\d+)?\s+(?:y|a)\s+\d+(?:[.,]\d+)?", "", clause)
        if re.search(r"\by\b", without_interval):
            return None
    topics_by_clause = []
    for clause in clauses:
        topics = {topic for topic, terms in TOPIC_LITERALS.items()
                  if any(re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", clause) for term in terms)}
        if len(topics) != 1 or not topics <= {"hrr", "temperature", "oxygen", "smoke_layer"}:
            return None
        topics_by_clause.append(next(iter(topics)))
    return topics_by_clause[0]


def explicit_request_contract(text, classification):
    """Constrain unmistakable requests; leave general language to Qwen.

    These rules describe the requested response, never fire physics. In
    particular an explicit request for limitations must not become a bare
    measurement because the classifier chose observation.
    """
    start = text.lstrip("¿¡ \t\n")
    limits = re.match(r"^(?:(?:que|cuales)(?:\s+son)?\s+(?:(?:las?|los?)\s+)?|"
                      r"(?:explica|describe)\s+(?:(?:las?|los?)\s+)?)"
                      r"(?:limitaciones|incertidumbre|limites)\b", start)
    summary = re.match(r"^(?:resume\b|(?:ofrece|dame|haz|presenta|elabora)\s+(?:un\s+)?resumen\b)", start)
    presence = re.match(r"^(?:(?:se\s+(?:ha\s+)?(?:detecto|registro|detectado|registrado)|"
                        r"quedo\s+(?:detectado|registrado))\s+(?:un|una)\s+|"
                        r"hubo\s+(?:(?:un|una)\s+)?)"
                        r"(?:aumento|incremento|crecimiento|descenso|reduccion)\b", start)
    enumeration = re.match(r"^(?:enumera|lista|ordena)\s+(?:todos\s+)?(?:los\s+)?hechos\s+registrados\b", start)
    definition = re.match(r"^(?:define\b|que\s+(?:es|significa)\b|"
                          r"explica\s+(?:el\s+)?(?:concepto|significado)\b)", start)
    magnitude = re.match(r"^(?:(?:indica|describe|muestra)\s+)?(?:cuant[oa]s?\s+(?:ha\s+)?"
                         r"(?:aumento|aumentado|descendio|descendido|cambio|cambiado|vario|variado|"
                         r"subio|subido|bajo|bajado)\b|"
                         r"como\s+(?:cambio|ha\s+cambiado|vario)\b)", start)
    measured_topics = [topic for topic in ("hrr", "temperature", "oxygen", "smoke_layer")
        if any(re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", text)
               for term in TOPIC_LITERALS[topic])]
    causal_request = re.search(r"\b(?:caus\w*|provoc\w*|porque)\b|"
                              r"\b(?:por\s+que|debido\s+a(?:l)?)\b", text)
    # A magnitude or causal question can mention detection without asking
    # whether it occurred. Do not erase that request or a named variable filter.
    other_request = re.search(r"\b(?:cuant[oa]s?|valor|magnitud|caus\w*|provoc\w*|porque|significa)\b|"
                              r"\b(?:por\s+que|debido\s+a(?:l)?|que\s+es)\b", text)
    literal_topics = {topic for topic, terms in TOPIC_LITERALS.items()
                      if any(re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", text) for term in terms)}
    single_measured_topic = len(measured_topics) == 1 and literal_topics == set(measured_topics)
    causal_effect = explicit_causal_effect(start) if classification['intent'] == 'causality' else None
    explanation_effect = explicit_explanation_effect(start)
    constrained = False
    if limits:
        classification["intent"] = "uncertainty"
        constrained = True
    elif explanation_effect:
        classification["intent"] = "causality"
        classification["topics"] = [explanation_effect]
        if explicit_variable_cause(start):
            # A proposed measured-variable cause is not a recorded action.
            # Temporal action bounds, if requested, are resolved separately.
            classification['anchor_fact_id'] = None
            if classification['clarification_needed'] == 'action':
                classification['clarification_needed'] = 'none'
    elif causal_effect:
        classification["topics"] = [causal_effect]
    elif definition and single_measured_topic and not causal_request:
        classification["intent"] = "concept"
        classification["topics"] = measured_topics
        constrained = True
    elif magnitude and single_measured_topic and not causal_request:
        # The named measured variable is authoritative for a direct magnitude
        # request. This supplies no values or facts and does not split windows.
        classification["intent"] = "observation"
        classification["topics"] = measured_topics
    elif summary and classification["intent"] not in ("concept", "causality"):
        classification["intent"] = "general"
        constrained = True
    elif presence and not other_request and literal_topics and classification["intent"] not in ("concept", "causality", "uncertainty"):
        classification["intent"] = "condition"
        constrained = True
    elif enumeration and not other_request and not literal_topics and classification["intent"] not in ("concept", "causality"):
        classification["intent"] = "timeline"
        classification["topics"] = []
        if classification["clarification_needed"] == "topic":
            classification["clarification_needed"] = "none"
    elif classification["intent"] == "timeline" and re.match(
            r"^como\s+(?:cambio|ha\s+cambiado|vario)\b", start):
        if measured_topics:
            classification["intent"] = "observation"
            classification["topics"] = measured_topics
    if constrained:
        mentioned = set(measured_topics)
        # A literal variable in a direct request overrides a generic topic guess.
        # Keep conflicting specific topics or multiple variables for clarification.
        generic_topics = {"fire_dynamics"}
        if len(mentioned) == 1 and set(classification["topics"]) <= generic_topics:
            classification["topics"] = sorted(mentioned)


def explicit_variable_cause(text):
    """Narrow due-to variable clause; neither identifies nor confirms a cause."""
    if explicit_explanation_effect(text) is None:
        return False
    due = re.fullmatch(r"(?:el|la)\s+[^?!.,;:]+?\s+debido\s+a(?:l)?\s+(?P<cause>[^?!.,;:]+?)[?!]*", text)
    if due is None:
        return False
    # Before/after describes the requested period, not the proposed cause.
    cause = re.split(r"\b(?:" + BEFORE_CUE + "|" + AFTER_CUE + r"|entre)\b", due['cause'], maxsplit=1)[0]
    variable = any(re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", cause)
                   for topic in ('hrr', 'temperature', 'oxygen', 'smoke_layer') for term in TOPIC_LITERALS[topic])
    action = re.search(r"\b(?:abr\w*|apertur\w*|cerr\w*|puertas?|ventanas?|door\w*|window\w*|"
                       r"accion\w*|action\w*|extingu\w*|apag\w*|ignicion|encend\w*|agua|water)\b", cause)
    return variable and action is None


def candidate_actions(context, scope, text):
    actions = [fact for fact in context["scenario_facts"] if fact["fact_type"] == "action"
               and (scope["compartment_id"] is None or scope["compartment_id"] in fact_rooms(context, fact))]
    targets = [fact for fact in actions if fact.get("action_target") and re.search(
        r"(?<!\w)" + re.escape(fact["action_target"].lower()) + r"(?!\w)", text)]
    if targets: actions = targets
    times = {float(value.replace(',', '.')) for value in re.findall(r"(?<!\w)\d+(?:[.,]\d+)?(?!\w)", text)}
    timed = [fact for fact in actions if fact["time_s"] in times]
    if timed: actions = timed
    if actions and re.search(r"\b(?:primera|primer)\b", text):
        earliest = min(fact["time_s"] for fact in actions)
        actions = [fact for fact in actions if fact["time_s"] == earliest]
    elif actions and re.search(r"\b(?:ultima|ultimo)\b", text):
        latest = max(fact["time_s"] for fact in actions)
        actions = [fact for fact in actions if fact["time_s"] == latest]
    return actions


def literal_rooms(context, question):
    metadata = context.get("analysis_coverage", {})
    rooms = metadata.get("compartments", [{"id": room, "name": room} for room in available_rooms(context)])
    return {room["id"] for room in rooms if any(
        re.search(r"(?<!\w)" + re.escape(label.lower()) + r"(?!\w)", question.lower())
        for label in {room["id"], room["name"]} if label)}


def interpret_explicit_scope(context, question, classification, *, model_proposal=False):
    """Check explicit IDs, seconds and ambiguous openings against model choices.

    This is conservative semantic validation, not a second physical detector.
    Qwen handles general language; literal identifiers/ranges never get guessed.
    """
    result = copy.deepcopy(classification)
    text = ''.join(ch for ch in unicodedata.normalize("NFD", question.lower()) if not unicodedata.combining(ch))
    explicit_request_contract(text, result)
    scope = result["scope"]
    # Header fields are retained for legacy plans; only timeline uses them as
    # temporal bounds. The 0.4 scope owns temporal semantics for other intents.
    if result["intent"] != "timeline":
        result["timeline_relation"] = "not_applicable"
        if result["intent"] != "causality":
            result["anchor_fact_id"] = None
    if result["clarification_needed"] == "topic" and result["topics"] and all(
        any(re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", text) for term in TOPIC_LITERALS.get(topic, (topic,)))
        for topic in result["topics"]
    ):
        result["clarification_needed"] = "none"
    if result["intent"] == "concept":
        result["scope"] = dict(DEFAULT_SCOPE)
        return result
    metadata = context.get("analysis_coverage", {})
    room_candidates = metadata.get("compartments", [{"id": room, "name": room} for room in available_rooms(context)])
    mentioned = literal_rooms(context, question)
    if len(mentioned) == 1:
        explicit_room = next(iter(mentioned))
        if scope["compartment_id"] not in (None, explicit_room):
            # Only a fresh model proposal may be corrected from an unambiguous
            # literal. Persisted plans remain strict, and invented IDs fail closed.
            known_rooms = {room["id"] for room in room_candidates}
            if not model_proposal or scope["compartment_id"] not in known_rooms:
                raise ValueError("El compartimento clasificado contradice el indicado en la pregunta")
        scope["compartment_id"] = explicit_room
        if result["clarification_needed"] == "compartment": result["clarification_needed"] = "none"
    elif len(mentioned) > 1:
        result["clarification_needed"] = "compartment"
        scope["compartment_id"] = None
    elif scope["compartment_id"] is not None and len(room_candidates) > 1:
        if re.search(r"\b(?:habitacion|compartimento|estancia|room)\b", text):
            result["clarification_needed"] = "compartment"
        # No literal room distinguishes this model choice; never silently narrow
        # a global query to whichever room the model happened to choose.
        scope["compartment_id"] = None
    numeric = r"(?:t\s*=\s*)?(\d+(?:[.,]\d+)?)\s*(?:s\b|segundos?\b)?"
    interval = re.search(r"\bentre\s+" + numeric + r"\s+y\s+" + numeric, text)
    before = bool(re.search(r"\b" + BEFORE_CUE + r"\b", text))
    after = bool(re.search(r"\b" + AFTER_CUE + r"\b", text))
    if interval:
        scope.update(time_relation="between", anchor_fact_id=None,
                     start_time_s=float(interval[1].replace(',', '.')), end_time_s=float(interval[2].replace(',', '.')))
        if result["clarification_needed"] in ("action", "time"): result["clarification_needed"] = "none"
    elif before and after:
        result["clarification_needed"] = "time"
        scope.update(DEFAULT_SCOPE, compartment_id=scope["compartment_id"])
    elif before or after:
        relation = "before" if before else "after"
        if scope["time_relation"] not in ("all", relation):
            raise ValueError("La relación temporal clasificada contradice la pregunta")
        scope["time_relation"] = relation
        explicit_seconds = re.search(r"\b(?:" + BEFORE_CUE + "|" + AFTER_CUE + r")\s+" + numeric + r"(?:\s|$|[?.])", text)
        if explicit_seconds:
            value = float(explicit_seconds[1].replace(',', '.'))
            scope.update(anchor_fact_id=None, start_time_s=value if after else None, end_time_s=value if before else None)
            if result["clarification_needed"] in ("action", "time"): result["clarification_needed"] = "none"
        else:
            actions = candidate_actions(context, scope, text)
            if before and result['intent'] == 'condition' and result['topics'] == ['ventilation_limited']:
                from llm.teaching_context import redundant_openings
                repetition = redundant_openings(context, actions)
                if repetition:
                    # Explicitly use the common period preceding every repeated
                    # open, never an arbitrary model anchor or post-opening span.
                    earliest = min(actions, key=lambda a: a['time_s'])
                    if model_proposal and scope['anchor_fact_id'] in {a['fact_id'] for a in actions}:
                        scope['anchor_fact_id'] = None
                    actions = [earliest]
            if len(actions) == 1:
                if scope["anchor_fact_id"] not in (None, actions[0]["fact_id"]):
                    raise ValueError("El ancla temporal contradice la acción indicada en la pregunta")
                scope.update(anchor_fact_id=actions[0]["fact_id"], start_time_s=None, end_time_s=None)
                if result["clarification_needed"] in ("action", "time"): result["clarification_needed"] = "none"
            else:
                scope.update(anchor_fact_id=None, start_time_s=None, end_time_s=None)
                result["clarification_needed"] = "action"
    else:
        point = re.search(r"\b(?:en\s+)?t\s*=\s*(\d+(?:[.,]\d+)?)", text)
        if point:
            value = float(point[1].replace(',', '.'))
            scope.update(time_relation="at", anchor_fact_id=None, start_time_s=value, end_time_s=value)
            if result["clarification_needed"] in ("action", "time"):
                result["clarification_needed"] = "none"
        elif any(value is not None for value in (scope["start_time_s"], scope["end_time_s"])):
            literals = {float(value.replace(',', '.')) for value in re.findall(r"(?<!\w)\d+(?:[.,]\d+)?(?!\w)", text)}
            if any(value is not None and value not in literals for value in (scope["start_time_s"], scope["end_time_s"])):
                result["clarification_needed"] = "time"
                scope.update(DEFAULT_SCOPE, compartment_id=scope["compartment_id"])
    if result["intent"] == "causality" and result["anchor_fact_id"] is not None:
        actions = candidate_actions(context, scope, text)
        if len(actions) != 1:
            result["clarification_needed"] = "action"
        elif result["anchor_fact_id"] != actions[0]["fact_id"]:
            raise ValueError("El ancla causal contradice la acción indicada en la pregunta")
        elif result["clarification_needed"] == "action":
            result["clarification_needed"] = "none"
    if result["intent"] == "timeline":
        result["timeline_relation"] = scope["time_relation"] if scope["time_relation"] in ("before", "after") else "all"
        result["anchor_fact_id"] = scope["anchor_fact_id"]
    if scope["time_relation"] == "all":
        scope["anchor_fact_id"] = None
    return result


def fact_rooms(context, fact):
    if "compartment_id" in fact:
        return {fact["compartment_id"]}
    if "compartment_ids" in fact:
        return set(fact["compartment_ids"])
    ids = set(fact["event_ids"])
    return {event["compartment_id"] for event in context.get("source_events", [])
            if event["event_id"] in ids and "compartment_id" in event}


def available_rooms(context):
    metadata = context.get("analysis_coverage")
    if metadata is not None:
        return {room["id"] for room in metadata["compartments"]}
    return set().union(*(fact_rooms(context, fact) for fact in context["scenario_facts"])) if context["scenario_facts"] else set()


def dependency_closure(ids, facts):
    resolved = []
    def visit(fact_id):
        for dependency in facts[fact_id]["requires_fact_ids"]:
            if dependency not in resolved:
                visit(dependency)
        if fact_id not in resolved:
            resolved.append(fact_id)
    for fact_id in ids:
        visit(fact_id)
    return resolved


def resolve_scope(context, classification):
    scope = dict(classification["scope"])
    clarification = classification["clarification_needed"]
    facts = {fact["fact_id"]: fact for fact in context["scenario_facts"]}
    room = scope["compartment_id"]
    if room is not None and room not in available_rooms(context):
        raise ValueError("El compartimento solicitado no existe en el contexto")
    relation = scope["time_relation"]
    anchor_id = scope["anchor_fact_id"]
    if anchor_id is not None:
        if anchor_id not in facts or facts[anchor_id]["fact_type"] != "action":
            raise ValueError("El ancla del ámbito no corresponde a una acción")
        if room is not None and room not in fact_rooms(context, facts[anchor_id]):
            raise ValueError("La acción del ámbito pertenece a otro compartimento")
    start, end = scope["start_time_s"], scope["end_time_s"]
    if relation == "all":
        if anchor_id is not None or start is not None or end is not None:
            raise ValueError("Un ámbito all no admite ancla ni límites temporales")
    elif relation in ("before", "after"):
        numeric = end if relation == "before" else start
        other = start if relation == "before" else end
        if other is not None or (anchor_id is not None and numeric is not None):
            raise ValueError("Ámbito before/after contradictorio")
        if anchor_id is not None:
            if relation == "before": scope["end_time_s"] = facts[anchor_id]["time_s"]
            else: scope["start_time_s"] = facts[anchor_id]["time_s"]
        elif numeric is None:
            clarification = "action"
    elif relation == "between":
        if anchor_id is not None or start is None or end is None or start >= end:
            raise ValueError("El intervalo necesita inicio < fin y no admite ancla")
    elif relation == "at":
        if anchor_id is not None or start is None or end != start:
            raise ValueError("Un instante exige inicio = fin y no admite ancla")
    if classification["intent"] == "timeline":
        legacy_relation = classification["timeline_relation"]
        if legacy_relation != relation or relation not in ("all", "before", "after"):
            # Explicit numeric ranges are expressed by the scope, with timeline all.
            if not (legacy_relation == "all" and relation in ("between", "at")):
                raise ValueError("La relación timeline no coincide con el ámbito")
        if classification["anchor_fact_id"] != anchor_id:
            raise ValueError("El ancla timeline no coincide con la del ámbito")
    elif classification["intent"] != "causality":
        if classification["timeline_relation"] != "not_applicable" or classification["anchor_fact_id"] is not None:
            raise ValueError("Ancla o relación timeline inválida para esta intención")
    if classification["intent"] != "timeline" and not classification["topics"]:
        clarification = "topic"
    return scope, clarification


def time_matches(time_s, scope):
    relation, start, end = scope["time_relation"], scope["start_time_s"], scope["end_time_s"]
    if relation == "before": return end is not None and time_s < end
    if relation == "after": return start is not None and time_s > start
    if relation in ("between", "at"): return start <= time_s <= end
    return True


def in_scope(context, fact, scope):
    room = scope["compartment_id"]
    if (scope["time_relation"] != "all" and fact["fact_type"] != "action"
            and "ventilation_limited" not in fact["knowledge_topics"]
            and "evidence_interval_s" not in fact):
        # A legacy timestamp does not prove where a measured change began.
        return False
    return ((room is None or room in fact_rooms(context, fact))
            and time_matches(fact["time_s"], scope)
            and interval_matches(fact.get("evidence_interval_s"), scope,
                                 "ventilation_limited" in fact["knowledge_topics"]))


def interval_matches(interval, scope, retrospective_pattern=False):
    # The ventilation-limited detector assigns its pattern to the pre-opening
    # reference time while using post-opening confirmation. Do not relocate it.
    if interval is None or retrospective_pattern or scope["time_relation"] == "all":
        return True
    start, end = scope["start_time_s"], scope["end_time_s"]
    return ((start is None or interval["start"] >= start)
            and (end is None or interval["end"] <= end))


def coverage_status(context, topic, scope):
    metadata = context.get("analysis_coverage")
    if metadata is None:
        return "insufficient_data", "coverage_unavailable"
    times = metadata["state_times_s"]
    if not times:
        return "insufficient_data", "no_samples"
    for bound in (scope["start_time_s"], scope["end_time_s"]):
        if bound is not None and not times[0] <= bound <= times[-1]:
            return "insufficient_data", "outside_recorded_time"
    rooms = {scope["compartment_id"]} if scope["compartment_id"] else available_rooms(context)
    for room in sorted(rooms):
        windows = [window for window in metadata["windows"]
                   if window["topic"] == topic and window["compartment_id"] == room
                   and time_matches(window["reference_time_s"], scope)]
        if not windows:
            return "insufficient_data", "no_evaluable_window"
        invalid = next((window for window in windows if not window["evaluable"]), None)
        if invalid is not None:
            return "insufficient_data", invalid["reason"]
        if any(not interval_matches({"start": window["start_time_s"], "end": window["end_time_s"]},
                                    scope, topic == "ventilation_limited") for window in windows):
            return "insufficient_data", "measurement_crosses_time_boundary"
    return "not_detected", "no_matching_detection"


def resolve_question(context, classification):
    scope, clarification = resolve_scope(context, classification)
    intent = classification["intent"]
    topics = list(classification["topics"])
    facts = {fact["fact_id"]: fact for fact in context["scenario_facts"]}
    causal_anchor = classification["anchor_fact_id"] if intent == "causality" else None
    if causal_anchor is not None and (causal_anchor not in facts or facts[causal_anchor]["fact_type"] != "action"):
        raise ValueError("El ancla causal no corresponde a una acción")
    if causal_anchor is not None and scope["compartment_id"] is not None and scope["compartment_id"] not in fact_rooms(context, facts[causal_anchor]):
        raise ValueError("El ancla causal pertenece a otro compartimento")
    candidates = [fact for fact in facts.values() if in_scope(context, fact, scope)]
    primary = []
    if not clarification or clarification == "none":
        if intent == "timeline":
            primary = [fact for fact in candidates if fact["fact_type"] != "limitation"]
            topics = list(dict.fromkeys(topic for fact in primary for topic in fact["knowledge_topics"]))
        elif intent != "concept":
            for fact in candidates:
                matched = set(fact["knowledge_topics"]) & set(topics) & SUPPORTED_TOPICS
                if not matched:
                    continue
                if intent == "observation" and fact["fact_type"] != "observation":
                    continue
                if intent == "condition" and fact["fact_type"] not in ("observation", "association"):
                    continue
                if fact["fact_type"] == "limitation" and intent not in ("causality", "uncertainty"):
                    continue
                if causal_anchor is not None:
                    anchor = facts[causal_anchor]
                    interval = fact.get("evidence_interval_s")
                    linked = causal_anchor in dependency_closure([fact["fact_id"]], facts)
                    if not linked and not (interval and interval["start"] < anchor["time_s"] <= interval["end"]
                            and fact_rooms(context, fact) & fact_rooms(context, anchor)):
                        continue
                primary.append(fact)
    if intent == "timeline":
        primary.sort(key=lambda fact: (fact["time_s"], fact["fact_id"]))
    ids = [fact["fact_id"] for fact in primary]
    resolved = dependency_closure(ids, facts)
    knowledge = context["technical_knowledge"]
    assessments = []
    if clarification != "none":
        status = "clarification_required"
        ids, resolved = [], []
    elif intent == "concept":
        for topic in topics:
            present = any(entry["topic"] == topic for entry in knowledge)
            assessments.append({"topic": topic, "status": "theory_only" if present else "knowledge_unavailable",
                                "reason": "general_theory" if present else "no_knowledge_entry"})
        status = assessments[0]["status"] if len({item["status"] for item in assessments}) == 1 else "partial"
    elif intent == "timeline":
        status = "evidence_found" if ids else "insufficient_data"
    else:
        rooms = [scope["compartment_id"]] if scope["compartment_id"] else sorted(available_rooms(context)) or [None]
        for topic in topics:
            for room in rooms:
                if topic not in SUPPORTED_TOPICS or (intent == "observation" and topic in ("ventilation", "ventilation_limited")):
                    state, reason = "unsupported", "no_detector_for_request"
                elif any(topic in fact["knowledge_topics"] and fact["fact_type"] in ("observation", "association", "limitation")
                         and (room is None or room in fact_rooms(context, fact)) for fact in primary):
                    state, reason = "evidence_found", "scoped_evidence"
                else:
                    state, reason = coverage_status(context, topic, {**scope, "compartment_id": room})
                if intent == "causality" and state == "evidence_found":
                    state, reason = "causal_not_established", "temporal_association_is_not_causation"
                assessments.append({"topic": topic, "compartment_id": room, "status": state, "reason": reason})
        status = assessments[0]["status"] if len({item["status"] for item in assessments}) == 1 else "partial"
    knowledge_ids = [entry["knowledge_id"] for entry in knowledge if entry["topic"] in topics
                     and (intent == "concept" or any(item["topic"] == entry["topic"]
                          and (item["status"] in ("evidence_found", "causal_not_established")
                               or (entry['topic'] == 'backdraft' and intent == 'condition'
                                   and item['status'] == 'unsupported')) for item in assessments))]
    if clarification != "none": knowledge_ids = []
    return {
        "timeline_relation": classification["timeline_relation"],
        "anchor_fact_id": classification["anchor_fact_id"],
        "requested_scope": dict(classification["scope"]),
        "scope": scope, "clarification_needed": clarification,
        "answer_status": status, "topic_assessments": assessments, "topics": topics,
        "include_limitations": intent in ("causality", "uncertainty"),
        "primary_fact_ids": ids, "supporting_fact_ids": [fact_id for fact_id in resolved if fact_id not in ids],
        "resolved_fact_ids": resolved, "resolved_knowledge_ids": knowledge_ids,
    }
