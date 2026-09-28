import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

PLANS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "question_plans"
)

ANSWERS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "question_answers"
)

SCENARIO_ID = "basic_room_001"


def load_json(path: Path):
    with path.open(
        "r",
        encoding="utf-8"
    ) as f:
        return json.load(f)


def fail(message):
    print(f"ERROR: {message}")
    sys.exit(1)


def load_case(question_id):

    plan_path = (
        PLANS_DIR
        / f"{SCENARIO_ID}_{question_id}.json"
    )

    answer_path = (
        ANSWERS_DIR
        / f"{SCENARIO_ID}_{question_id}_answer.json"
    )

    if not plan_path.exists():
        fail(
            f"No existe el plan {plan_path.name}"
        )

    if not answer_path.exists():
        fail(
            f"No existe la respuesta {answer_path.name}"
        )

    return (
        load_json(plan_path),
        load_json(answer_path)
    )


def assert_exact_set(
    actual,
    expected,
    label
):
    actual_set = set(actual)
    expected_set = set(expected)

    if actual_set != expected_set:
        fail(
            f"{label} incorrecto.\n"
            f"Esperado: {sorted(expected_set)}\n"
            f"Obtenido: {sorted(actual_set)}"
        )


def test_concept():

    plan, answer = load_case(
        "question_concept_001"
    )

    if plan["intent"] != "concept":
        fail(
            "concept: intent incorrecto"
        )

    assert_exact_set(
        plan["topics"],
        ["hrr"],
        "concept topics"
    )

    if plan["resolved_fact_ids"]:
        fail(
            "concept: no debe usar hechos "
            "del escenario"
        )

    assert_exact_set(
        plan["resolved_knowledge_ids"],
        ["HRR_001"],
        "concept knowledge"
    )

    if answer["fact_ids"]:
        fail(
            "concept: la respuesta contiene "
            "hechos del escenario"
        )

    if (
        "tasa de liberación de calor"
        not in answer["answer"].lower()
    ):
        fail(
            "concept: falta la definición de HRR"
        )

    if not answer["source_ids"]:
        fail(
            "concept: debe mostrar fuente"
        )

    print("OK: concept")


def test_observation():

    plan, answer = load_case(
        "question_observation_001"
    )

    if plan["intent"] != "observation":
        fail(
            "observation: intent incorrecto"
        )

    if plan["include_limitations"]:
        fail(
            "observation: no debe incluir "
            "limitaciones"
        )

    assert_exact_set(
        plan["topics"],
        ["temperature"],
        "observation topics"
    )

    assert_exact_set(
        plan["resolved_fact_ids"],
        ["FACT_005"],
        "observation facts"
    )

    assert_exact_set(
        plan["resolved_knowledge_ids"],
        ["TEMPERATURE_001"],
        "observation knowledge"
    )

    text = answer["answer"]

    if "390" not in text:
        fail(
            "observation: falta valor inicial"
        )

    if "475" not in text:
        fail(
            "observation: falta valor final"
        )

    if "85 °C" not in text:
        fail(
            "observation: falta cálculo "
            "determinista de 85 °C"
        )

    if answer["source_ids"]:
        fail(
            "observation: no debe mostrar "
            "fuentes de teoría no utilizada"
        )

    print("OK: observation")


def test_timeline():

    plan, answer = load_case(
        "question_timeline_001"
    )

    if plan["intent"] != "timeline":
        fail(
            "timeline: intent incorrecto"
        )

    if plan["include_limitations"]:
        fail(
            "timeline: no debe incluir "
            "limitaciones causales"
        )

    if plan["timeline_relation"] != "after":
        fail(
            "timeline: relación temporal "
            "incorrecta"
        )

    if plan["anchor_fact_id"] != "FACT_001":
        fail(
            "timeline: ancla incorrecta"
        )

    assert_exact_set(
        plan["resolved_fact_ids"],
        [
            "FACT_001",
            "FACT_002",
            "FACT_003",
            "FACT_004",
            "FACT_005"
        ],
        "timeline facts"
    )

    forbidden_facts = {
        "FACT_006",
        "FACT_007",
        "FACT_008"
    }

    if (
        forbidden_facts
        & set(plan["resolved_fact_ids"])
    ):
        fail(
            "timeline: contiene "
            "limitaciones causales"
        )

    text = answer["answer"]

    if "En t=180 s:" not in text:
        fail(
            "timeline: falta t=180 s"
        )

    if "En t=195 s:" not in text:
        fail(
            "timeline: falta t=195 s"
        )

    if answer["source_ids"]:
        fail(
            "timeline: no debe mostrar "
            "fuentes de teoría no utilizada"
        )

    print("OK: timeline")


def test_causality():

    plan, answer = load_case(
        "question_causality_001"
    )

    if plan["intent"] != "causality":
        fail(
            "causality: intent incorrecto"
        )

    if not plan["include_limitations"]:
        fail(
            "causality: debe incluir "
            "limitaciones"
        )

    if plan["anchor_fact_id"] != "FACT_001":
        fail(
            "causality: ancla causal incorrecta"
        )

    assert_exact_set(
        plan["topics"],
        [
            "hrr",
            "ventilation"
        ],
        "causality topics"
    )

    assert_exact_set(
        plan["resolved_fact_ids"],
        [
            "FACT_001",
            "FACT_002",
            "FACT_003",
            "FACT_006"
        ],
        "causality facts"
    )

    assert_exact_set(
        plan["resolved_knowledge_ids"],
        [
            "HRR_001",
            "VENTILATION_001"
        ],
        "causality knowledge"
    )

    text = answer["answer"].lower()

    required_text = (
        "no puede afirmarse esa relación causal"
    )

    if required_text not in text:
        fail(
            "causality: falta la barrera "
            "causal principal"
        )

    limitation_text = (
        "los datos disponibles no son "
        "suficientes para afirmar"
    )

    if limitation_text not in text:
        fail(
            "causality: falta la limitación "
            "del análisis"
        )

    if not answer["source_ids"]:
        fail(
            "causality: falta la fuente "
            "del conocimiento utilizado"
        )

    print("OK: causality")


def main():

    print(
        "SIMUFIRE AI - QUESTION MODES"
    )
    print()

    test_concept()
    test_observation()
    test_timeline()
    test_causality()

    print()
    print(
        "RESULTADO: 4/4 modos "
        "de pregunta correctos"
    )


if __name__ == "__main__":
    main()