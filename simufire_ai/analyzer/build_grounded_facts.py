import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

SCENARIO_PATH = (
    BASE_DIR
    / "scenarios"
    / "basic_room_001.json"
)

EVENTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_events"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "grounded_facts"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_events():
    events = []

    for path in sorted(EVENTS_DIR.glob("*.json")):
        events.append(load_json(path))

    return sorted(
        events,
        key=lambda event: event["time_s"]
    )


def find_evidence(event, variable):
    for item in event.get("evidence", []):
        if item["variable"] == variable:
            return item

    return None


def make_fact(
    scenario_id,
    fact_id,
    time_s,
    fact_type,
    statement,
    certainty,
    event_ids,
    source_variables=None,
    knowledge_topics=None,
    requires_fact_ids=None,
    causal=False
):
    return {
        "schema_version": "0.1",
        "scenario_id": scenario_id,
        "fact_id": fact_id,
        "time_s": time_s,
        "fact_type": fact_type,
        "statement": statement,
        "certainty": certainty,
        "event_ids": event_ids,
        "source_variables": source_variables or [],
        "knowledge_topics": knowledge_topics or [],
        "requires_fact_ids": requires_fact_ids or [],
        "causal": causal
    }


def build_facts(scenario, events):

    scenario_id = scenario["scenario_id"]

    facts = []
    fact_number = 1

    def next_id():
        nonlocal fact_number

        fact_id = f"FACT_{fact_number:03d}"
        fact_number += 1

        return fact_id

    # -------------------------------------------------
    # ACCIONES DEL ESCENARIO
    # -------------------------------------------------

    for action in scenario.get("actions", []):

        if action["type"] == "open":

            facts.append(
                make_fact(
                    scenario_id=scenario_id,
                    fact_id=next_id(),
                    time_s=action["time_s"],
                    fact_type="action",
                    statement=(
                        f"El elemento {action['target']} "
                        f"se abrió en t={action['time_s']} s."
                    ),
                    certainty="certain",
                    event_ids=[],
                    source_variables=[],
                    knowledge_topics=[],
                    causal=False
                )
            )

    # -------------------------------------------------
    # EVENTOS DETECTADOS
    # -------------------------------------------------

    for event in events:

        event_type = event["event_type"]
        event_id = event["event_id"]
        time_s = event["time_s"]

        # ---------------------------------------------
        # HRR
        # ---------------------------------------------

        if event_type == "hrr_increase":

            evidence = find_evidence(
                event,
                "hrr_kw"
            )

            if evidence:

                facts.append(
                    make_fact(
                        scenario_id=scenario_id,
                        fact_id=next_id(),
                        time_s=time_s,
                        fact_type="observation",
                        statement=(
                            "El HRR aumentó de "
                            f"{evidence['previous_value']} "
                            f"a {evidence['value']} kW."
                        ),
                        certainty="high",
                        event_ids=[event_id],
                        source_variables=[
                            "hrr_kw"
                        ],
                        knowledge_topics=[
                            "hrr"
                        ],
                        causal=False
                    )
                )

        # ---------------------------------------------
        # TEMPERATURA
        # ---------------------------------------------

        elif event_type == "temperature_increase":

            evidence = find_evidence(
                event,
                "upper_layer.temperature_c"
            )

            if evidence:

                facts.append(
                    make_fact(
                        scenario_id=scenario_id,
                        fact_id=next_id(),
                        time_s=time_s,
                        fact_type="observation",
                        statement=(
                            "La temperatura de la capa superior "
                            f"aumentó de {evidence['previous_value']} "
                            f"a {evidence['value']} °C."
                        ),
                        certainty="high",
                        event_ids=[event_id],
                        source_variables=[
                            "upper_layer.temperature_c"
                        ],
                        knowledge_topics=[
                            "temperature"
                        ],
                        causal=False
                    )
                )

        # ---------------------------------------------
        # CAPA DE HUMO
        # ---------------------------------------------

        elif event_type == "smoke_layer_descent":

            evidence = find_evidence(
                event,
                "interface_height_m"
            )

            if evidence:

                facts.append(
                    make_fact(
                        scenario_id=scenario_id,
                        fact_id=next_id(),
                        time_s=time_s,
                        fact_type="observation",
                        statement=(
                            "La interfaz entre capas descendió "
                            f"de {evidence['previous_value']} "
                            f"a {evidence['value']} m."
                        ),
                        certainty="high",
                        event_ids=[event_id],
                        source_variables=[
                            "interface_height_m"
                        ],
                        knowledge_topics=[
                            "smoke_layer"
                        ],
                        causal=False
                    )
                )

        # ---------------------------------------------
        # VENTILACION
        # ---------------------------------------------

        elif event_type == "ventilation_increase":

            cause = event.get(
                "cause",
                "una apertura"
            )

            target = cause.replace(
                "_opened",
                ""
            )

            facts.append(
                make_fact(
                    scenario_id=scenario_id,
                    fact_id=next_id(),
                    time_s=time_s,
                    fact_type="association",
                    statement=(
                        "El Fire Event Analyzer detectó "
                        "un aumento de ventilación asociado "
                        f"a la apertura de {target}."
                    ),
                    certainty="high",
                    event_ids=[event_id],
                    source_variables=[
                        item["variable"]
                        for item in event.get(
                            "evidence",
                            []
                        )
                    ],
                    knowledge_topics=[
                        "ventilation"
                    ],
                    causal=False
                )
            )

    # -------------------------------------------------
    # LIMITACIONES DE CAUSALIDAD
    # -------------------------------------------------

    event_types = {
        event["event_type"]
        for event in events
    }

    # Ventilación + HRR

    if (
        "ventilation_increase" in event_types
        and "hrr_increase" in event_types
    ):

        facts.append(
            make_fact(
                scenario_id=scenario_id,
                fact_id=next_id(),
                time_s=max(
                    event["time_s"]
                    for event in events
                ),
                fact_type="limitation",
                statement=(
                    "Los datos disponibles no son suficientes "
                    "para afirmar que la apertura de la puerta "
                    "causó por sí sola el aumento del HRR."
                ),
                certainty="certain",
                event_ids=[],
                source_variables=[],
                knowledge_topics=[
                    "ventilation",
                    "hrr"
                ],
                causal=False
            )
        )

    # Ventilación + temperatura

    if (
        "ventilation_increase" in event_types
        and "temperature_increase" in event_types
    ):

        facts.append(
            make_fact(
                scenario_id=scenario_id,
                fact_id=next_id(),
                time_s=max(
                    event["time_s"]
                    for event in events
                ),
                fact_type="limitation",
                statement=(
                    "Los datos disponibles no son suficientes "
                    "para afirmar una relación causal directa "
                    "entre la apertura de la puerta y el aumento "
                    "de temperatura."
                ),
                certainty="certain",
                event_ids=[],
                source_variables=[],
                knowledge_topics=[
                    "ventilation",
                    "temperature"
                ],
                causal=False
            )
        )

    # Descenso de la capa de humo

    if "smoke_layer_descent" in event_types:

        facts.append(
            make_fact(
                scenario_id=scenario_id,
                fact_id=next_id(),
                time_s=max(
                    event["time_s"]
                    for event in events
                ),
                fact_type="limitation",
                statement=(
                    "Se ha detectado un descenso de la interfaz "
                    "entre capas, pero los datos disponibles no "
                    "permiten atribuirle una causa física concreta."
                ),
                certainty="certain",
                event_ids=[],
                source_variables=[],
                knowledge_topics=[
                    "smoke_layer"
                ],
                causal=False
            )
        )

    # -------------------------------------------------
    # OXIGENO
    #
    # Se añade DESPUÉS de FACT_001...FACT_008 para
    # conservar los IDs históricos y no romper tests.
    # -------------------------------------------------

    ventilation_event = next(
        (
            event
            for event in events
            if event["event_type"]
            == "ventilation_increase"
        ),
        None
    )

    if ventilation_event:

        oxygen_evidence = find_evidence(
            ventilation_event,
            "upper_layer.o2_percent"
        )

        if oxygen_evidence:

            facts.append(
                make_fact(
                    scenario_id=scenario_id,
                    fact_id=next_id(),
                    time_s=ventilation_event["time_s"],
                    fact_type="observation",
                    statement=(
                        "El O₂ de la capa superior aumentó de "
                        f"{oxygen_evidence['previous_value']} "
                        f"a {oxygen_evidence['value']} %."
                    ),
                    certainty="high",
                    event_ids=[
                        ventilation_event["event_id"]
                    ],
                    source_variables=[
                        "upper_layer.o2_percent"
                    ],
                    knowledge_topics=[
                        "oxygen"
                    ],
                    causal=False
                )
            )

    # -------------------------------------------------
    # DEPENDENCIAS ENTRE HECHOS
    # -------------------------------------------------

    dependencies = {
        "FACT_002": [
            "FACT_001"
        ],

        "FACT_006": [
            "FACT_001",
            "FACT_002",
            "FACT_003"
        ],

        "FACT_007": [
            "FACT_001",
            "FACT_002",
            "FACT_005"
        ],

        "FACT_008": [
            "FACT_004"
        ],

        "FACT_009": [
            "FACT_002"
        ]
    }

    for fact in facts:
        fact["requires_fact_ids"] = dependencies.get(
            fact["fact_id"],
            []
        )

    return facts


def main():

    scenario = load_json(
        SCENARIO_PATH
    )

    events = load_events()

    if not events:
        print(
            "ERROR: no hay eventos generados."
        )
        sys.exit(1)

    facts = build_facts(
        scenario,
        events
    )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    for old_file in OUTPUT_DIR.glob(
        "*.json"
    ):
        old_file.unlink()

    for fact in facts:

        output_path = (
            OUTPUT_DIR
            / f"{fact['fact_id']}.json"
        )

        with output_path.open(
            "w",
            encoding="utf-8"
        ) as f:

            json.dump(
                fact,
                f,
                indent=2,
                ensure_ascii=False
            )

    print(
        f"Hechos generados: {len(facts)}"
    )

    for fact in facts:

        topics = ", ".join(
            fact["knowledge_topics"]
        )

        if not topics:
            topics = "-"

        print(
            f"- {fact['fact_id']} "
            f"[{fact['fact_type']}] "
            f"[{topics}]: "
            f"{fact['statement']}"
        )


if __name__ == "__main__":
    main()