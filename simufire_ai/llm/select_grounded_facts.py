import json
import sys
import urllib.request
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]

FACTS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "grounded_facts"
)

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "fact_selection.schema.json"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "fact_selections"
)

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "qwen3:1.7b"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def load_facts():
    facts = []

    for path in sorted(FACTS_DIR.glob("*.json")):
        facts.append(load_json(path))

    return facts


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
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json"
        }
    )

    with urllib.request.urlopen(
        request,
        timeout=120
    ) as response:

        result = json.loads(
            response.read().decode("utf-8")
        )

    return result["response"]


def main():

    facts = load_facts()

    if not facts:
        print("ERROR: no hay grounded facts.")
        sys.exit(1)

    schema = load_json(SCHEMA_PATH)

    scenario_id = facts[0]["scenario_id"]

    allowed_ids = [
        fact["fact_id"]
        for fact in facts
    ]

    compact_facts = [
        {
            "fact_id": fact["fact_id"],
            "type": fact["fact_type"],
            "statement": fact["statement"]
        }
        for fact in facts
    ]

    prompt = f"""
Eres un selector de hechos para SimuFire AI.

NO debes explicar el incendio.
NO debes generar texto técnico.
NO debes añadir información.
NO debes modificar los hechos.

Tu única tarea es seleccionar y ordenar los fact_id
que deben aparecer en una explicación para un bombero.

REGLAS:

- Solo puedes utilizar fact_id existentes.
- Incluye las observaciones relevantes.
- Incluye las acciones relevantes.
- Incluye las asociaciones relevantes.
- Incluye las limitaciones necesarias para evitar
  interpretar correlaciones como causalidad.
- Coloca primero los acontecimientos y observaciones.
- Coloca después las limitaciones correspondientes.
- No inventes fact_id.
- Devuelve exclusivamente el JSON solicitado.

schema_version = "0.1"
scenario_id = "{scenario_id}"
selection_id = "selection_001"

FACT_IDS PERMITIDOS:

{json.dumps(allowed_ids, ensure_ascii=False)}

HECHOS:

{json.dumps(compact_facts, indent=2, ensure_ascii=False)}
"""

    print("Seleccionando hechos...")

    raw = call_ollama(
        prompt,
        schema
    )

    try:
        selection = json.loads(raw)

    except json.JSONDecodeError:
        print("ERROR: respuesta JSON no valida.")
        print(raw)
        sys.exit(1)

    validator = Draft202012Validator(schema)

    errors = list(
        validator.iter_errors(selection)
    )

    if errors:
        print("ERROR: la seleccion no cumple el schema.")

        for error in errors:
            print(
                f"- {error.json_path}: "
                f"{error.message}"
            )

        sys.exit(1)

    invalid_ids = [
        fact_id
        for fact_id in selection["fact_ids"]
        if fact_id not in allowed_ids
    ]

    if invalid_ids:
        print("ERROR: fact_ids inexistentes:")

        for fact_id in invalid_ids:
            print(f"- {fact_id}")

        sys.exit(1)

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    output_path = (
        OUTPUT_DIR
        / "basic_room_001_selection.json"
    )

    with output_path.open(
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            selection,
            f,
            indent=2,
            ensure_ascii=False
        )

    print("OK: seleccion valida")
    print()

    for fact_id in selection["fact_ids"]:

        fact = next(
            item
            for item in facts
            if item["fact_id"] == fact_id
        )

        print(
            f"- {fact_id}: "
            f"{fact['statement']}"
        )


if __name__ == "__main__":
    main()