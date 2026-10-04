import json
import sys
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parents[1]

EXPLANATION_PATH = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_explanations"
    / "basic_room_001_instructor_explanation.json"
)

FACTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "grounded_facts"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def fail(message):
    print(f"ERROR: {message}")
    sys.exit(1)


def main():

    explanation = load_json(EXPLANATION_PATH)

    text = explanation["explanation"].lower()

    # -------------------------------------------------
    # 1. ESTRUCTURA OBLIGATORIA
    # -------------------------------------------------

    required_sections = [
        "qué ocurrió en la simulación",
        "conceptos relacionados",
        "qué no podemos concluir"
    ]

    for section in required_sections:

        if section not in text:
            fail(
                f"falta la sección obligatoria: "
                f"{section}"
            )

    # -------------------------------------------------
    # 2. FRASES CAUSALES NO PERMITIDAS
    # -------------------------------------------------

    forbidden_phrases = [
        "la apertura de la puerta causó el aumento del hrr",
        "la apertura de la puerta provocó el aumento del hrr",
        "la apertura de la puerta causó el aumento de temperatura",
        "la apertura de la puerta provocó el aumento de temperatura",
        "la presión disminuyó",
        "debido a la gravedad",
        "el descenso de la interfaz fue causado por",
        "el descenso de la capa fue causado por"
    ]

    for phrase in forbidden_phrases:

        if phrase in text:
            fail(
                f"se detectó una afirmación no permitida: "
                f"{phrase}"
            )

    # -------------------------------------------------
    # 3. LAS LIMITACIONES DEBEN ESTAR PRESENTES
    # -------------------------------------------------

    limitation_files = sorted(
        FACTS_DIR.glob("*.json")
    )

    limitations = []

    for path in limitation_files:

        fact = load_json(path)

        if fact["fact_type"] == "limitation":
            limitations.append(
                fact["statement"]
            )

    if not limitations:
        fail(
            "no existen hechos de tipo limitation"
        )

    for limitation in limitations:

        if limitation.lower() not in text:
            fail(
                "la explicación ha omitido una "
                f"limitación: {limitation}"
            )

    # -------------------------------------------------
    # 4. DEBE TENER FUENTES
    # -------------------------------------------------

    source_ids = explanation.get(
        "source_ids",
        []
    )

    if not source_ids:
        fail(
            "la explicación de instructor "
            "no contiene fuentes"
        )

    # -------------------------------------------------
    # 5. NIVEL CORRECTO
    # -------------------------------------------------

    if explanation.get(
        "audience_level"
    ) != "instructor":

        fail(
            "audience_level no es instructor"
        )

    print(
        "OK: explicación de instructor segura"
    )

    print(
        f"- Limitaciones verificadas: "
        f"{len(limitations)}"
    )

    print(
        f"- Fuentes: "
        f"{len(source_ids)}"
    )

    print(
        "- No se detectaron relaciones "
        "causales prohibidas"
    )


if __name__ == "__main__":
    main()