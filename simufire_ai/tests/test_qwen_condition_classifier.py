import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]

sys.path.insert(
    0,
    str(BASE_DIR)
)

from llm.plan_question import (
    call_ollama
)


SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "question_plan.schema.json"
)


def load_json(path: Path):
    with path.open(
        "r",
        encoding="utf-8"
    ) as f:
        return json.load(f)


def main():

    schema = load_json(
        SCHEMA_PATH
    )

    # Usamos el vocabulario permitido por
    # el schema, no hechos del escenario.
    available_topics = (
        schema[
            "properties"
        ][
            "topics"
        ][
            "items"
        ][
            "enum"
        ]
    )

    question = (
        "¿El incendio estaba limitado "
        "por ventilación antes de abrir "
        "la puerta?"
    )

    prompt = f"""
Eres el clasificador de preguntas de SimuFire AI.

NO respondas la pregunta.
NO determines si la condición ocurrió.
NO interpretes físicamente la simulación.
NO inventes datos.
NO establezcas causalidad.

Tu única tarea es clasificar
lingüísticamente la pregunta.

INTENCIONES:

timeline:
preguntas sobre qué ocurrió antes o después
de una acción.

causality:
preguntas sobre si una acción produjo,
provocó o causó otro fenómeno.

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

- Si se pregunta si el incendio estaba
  limitado por ventilación, la intención
  es condition.

- Para esa condición, el topic es:
  ventilation_limited

- No decidas si realmente estaba limitado
  por ventilación. Eso corresponde al
  Fire Event Analyzer.

- Para condition:
  timeline_relation = "not_applicable"
  anchor_fact_id = null

- Devuelve exclusivamente JSON válido.

schema_version = "0.3"
scenario_id = "basic_room_001"
question_id = "question_vl_classifier_001"

TEMAS PERMITIDOS:

{json.dumps(
    available_topics,
    ensure_ascii=False
)}

PREGUNTA:

{question}
"""

    print(
        "Consultando Qwen..."
    )

    raw = call_ollama(
        prompt,
        schema
    )

    try:
        plan = json.loads(
            raw
        )

    except json.JSONDecodeError:

        print(
            "ERROR: Qwen no devolvió "
            "JSON válido."
        )

        print(raw)
        sys.exit(1)

    validator = (
        Draft202012Validator(
            schema
        )
    )

    errors = list(
        validator.iter_errors(
            plan
        )
    )

    if errors:

        print(
            "ERROR: la salida no cumple "
            "question_plan.schema.json"
        )

        for error in errors:
            print(
                f"- {error.json_path}: "
                f"{error.message}"
            )

        sys.exit(1)

    assert (
        plan["intent"]
        == "condition"
    ), (
        "Qwen no clasificó la pregunta "
        "como condition.\n"
        f"Intent obtenido: "
        f"{plan['intent']}"
    )

    assert (
        plan["topics"]
        == [
            "ventilation_limited"
        ]
    ), (
        "Qwen no seleccionó exactamente "
        "ventilation_limited.\n"
        f"Topics obtenidos: "
        f"{plan['topics']}"
    )

    assert (
        plan["timeline_relation"]
        == "not_applicable"
    )

    assert (
        plan["anchor_fact_id"]
        is None
    )

    print()
    print(
        "OK: Qwen clasificó "
        "correctamente la pregunta"
    )

    print(
        f"- intent: "
        f"{plan['intent']}"
    )

    print(
        "- topics: "
        + ", ".join(
            plan["topics"]
        )
    )

    print(
        "- timeline_relation: "
        f"{plan['timeline_relation']}"
    )

    print(
        "- anchor_fact_id: "
        f"{plan['anchor_fact_id']}"
    )

    print()
    print(
        "Qwen solo ha clasificado "
        "la pregunta; no ha decidido "
        "si la condición ocurrió."
    )


if __name__ == "__main__":
    main()