import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

ANSWER_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "question_answers"
    / "basic_room_001_question_001_answer.json"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def fail(message):
    print(f"ERROR: {message}")
    sys.exit(1)


def main():

    answer = load_json(ANSWER_PATH)

    text = answer["answer"].lower()

    # -------------------------------------------------
    # 1. DEBE SER UNA PREGUNTA CAUSAL
    # -------------------------------------------------

    if answer["intent"] != "causality":
        fail(
            "la respuesta no corresponde "
            "a una pregunta causal"
        )

    # -------------------------------------------------
    # 2. TEMAS CORRECTOS
    # -------------------------------------------------

    expected_topics = {
        "hrr",
        "ventilation"
    }

    actual_topics = set(
        answer["topics"]
    )

    if actual_topics != expected_topics:
        fail(
            f"topics incorrectos: {actual_topics}"
        )

    # -------------------------------------------------
    # 3. HECHOS OBLIGATORIOS
    # -------------------------------------------------

    required_facts = {
        "FACT_001",
        "FACT_002",
        "FACT_003",
        "FACT_006"
    }

    actual_facts = set(
        answer["fact_ids"]
    )

    missing_facts = (
        required_facts - actual_facts
    )

    if missing_facts:
        fail(
            "faltan hechos obligatorios: "
            + ", ".join(
                sorted(missing_facts)
            )
        )

    # -------------------------------------------------
    # 4. NO DEBE METER HECHOS IRRELEVANTES
    # -------------------------------------------------

    forbidden_facts = {
        "FACT_004",
        "FACT_005",
        "FACT_007",
        "FACT_008"
    }

    unexpected_facts = (
        forbidden_facts & actual_facts
    )

    if unexpected_facts:
        fail(
            "se han incluido hechos irrelevantes: "
            + ", ".join(
                sorted(unexpected_facts)
            )
        )

    # -------------------------------------------------
    # 5. CONOCIMIENTO CORRECTO
    # -------------------------------------------------

    expected_knowledge = {
        "HRR_001",
        "VENTILATION_001"
    }

    actual_knowledge = set(
        answer["knowledge_ids"]
    )

    if actual_knowledge != expected_knowledge:
        fail(
            "conocimiento incorrecto: "
            + ", ".join(
                sorted(actual_knowledge)
            )
        )

    # -------------------------------------------------
    # 6. CAUSALIDAD NO AUTORIZADA
    # -------------------------------------------------

    forbidden_phrases = [
        "la apertura de la puerta causó el aumento del hrr",
        "la apertura de la puerta provocó el aumento del hrr",
        "la puerta causó el aumento del hrr",
        "la puerta provocó el aumento del hrr",
        "el aumento del hrr fue causado por la apertura",
        "el aumento del hrr fue provocado por la apertura"
    ]

    for phrase in forbidden_phrases:

        if phrase in text:
            fail(
                "causalidad no autorizada: "
                + phrase
            )

    # -------------------------------------------------
    # 7. DEBE EXPRESAR LA LIMITACIÓN
    # -------------------------------------------------

    required_limitation = (
        "no puede afirmarse esa relación causal"
    )

    if required_limitation not in text:
        fail(
            "la respuesta no expresa "
            "la limitación causal principal"
        )

    # -------------------------------------------------
    # 8. DEBE TENER FUENTE
    # -------------------------------------------------

    if not answer.get("source_ids"):
        fail(
            "la respuesta no contiene fuentes"
        )

    print(
        "OK: respuesta causal segura"
    )

    print(
        "- Hechos relevantes verificados"
    )

    print(
        "- Conocimiento relevante verificado"
    )

    print(
        "- No se detectó causalidad no autorizada"
    )

    print(
        "- Limitación causal presente"
    )


if __name__ == "__main__":
    main()