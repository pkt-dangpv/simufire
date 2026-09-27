import json
import sys
import urllib.request
from pathlib import Path

from jsonschema import Draft202012Validator


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
    / "instructor_selection.schema.json"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_selections"
)

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "qwen3:1.7b"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
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

    context = load_json(CONTEXT_PATH)
    schema = load_json(SCHEMA_PATH)

    allowed_fact_ids = [
        fact["fact_id"]
        for fact in context["scenario_facts"]
    ]

    allowed_knowledge_ids = [
        entry["knowledge_id"]
        for entry in context["technical_knowledge"]
    ]

    compact_facts = [
        {
            "fact_id": fact["fact_id"],
            "fact_type": fact["fact_type"],
            "statement": fact["statement"],
            "knowledge_topics": fact.get(
                "knowledge_topics",
                []
            )
        }
        for fact in context["scenario_facts"]
    ]

    compact_knowledge = [
        {
            "knowledge_id": entry["knowledge_id"],
            "topic": entry["topic"],
            "title": entry["title"],
            "matched_fact_ids":
                entry["matched_fact_ids"]
        }
        for entry in context["technical_knowledge"]
    ]

    prompt = f"""
Eres el selector de material del modo Instructor
de SimuFire AI.

NO debes explicar el incendio.
NO debes redactar teoría.
NO debes inventar información.

Tu única tarea es seleccionar:

1. Los fact_id necesarios para explicar lo ocurrido.
2. Los knowledge_id necesarios para enseñar la teoría
   relacionada con esos hechos.

REGLAS:

- Solo puedes utilizar IDs proporcionados.
- Debes conservar las limitaciones relevantes.
- No conviertas asociaciones en causalidad.
- Selecciona conocimiento solamente cuando esté
  relacionado con un hecho seleccionado.
- No inventes fenómenos.
- No inventes fact_id.
- No inventes knowledge_id.
- Devuelve exclusivamente el JSON solicitado.

schema_version = "0.1"
scenario_id = "{context["scenario_id"]}"
selection_id = "instructor_selection_001"

FACT_IDS PERMITIDOS:

{json.dumps(allowed_fact_ids, ensure_ascii=False)}

KNOWLEDGE_IDS PERMITIDOS:

{json.dumps(allowed_knowledge_ids, ensure_ascii=False)}

HECHOS:

{json.dumps(compact_facts, indent=2, ensure_ascii=False)}

CONOCIMIENTO DISPONIBLE:

{json.dumps(compact_knowledge, indent=2, ensure_ascii=False)}
"""

    print("Seleccionando material de instructor...")

    raw = call_ollama(
        prompt,
        schema
    )

    try:
        selection = json.loads(raw)

    except json.JSONDecodeError:
        print("ERROR: Qwen no devolvió JSON válido.")
        print(raw)
        sys.exit(1)

    validator = Draft202012Validator(schema)

    errors = list(
        validator.iter_errors(selection)
    )

    if errors:

        print(
            "ERROR: la selección no cumple el schema."
        )

        for error in errors:
            print(
                f"- {error.json_path}: "
                f"{error.message}"
            )

        sys.exit(1)

    invalid_fact_ids = [
        fact_id
        for fact_id in selection["fact_ids"]
        if fact_id not in allowed_fact_ids
    ]

    invalid_knowledge_ids = [
        knowledge_id
        for knowledge_id in selection["knowledge_ids"]
        if knowledge_id not in allowed_knowledge_ids
    ]

    if invalid_fact_ids:

        print("ERROR: fact_ids inexistentes:")

        for fact_id in invalid_fact_ids:
            print(f"- {fact_id}")

        sys.exit(1)

    if invalid_knowledge_ids:

        print("ERROR: knowledge_ids inexistentes:")

        for knowledge_id in invalid_knowledge_ids:
            print(f"- {knowledge_id}")

        sys.exit(1)

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    output_path = (
        OUTPUT_DIR
        / "basic_room_001_instructor_selection.json"
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

    print("OK: selección de instructor válida")
    print()

    print("HECHOS:")

    for fact_id in selection["fact_ids"]:
        print(f"- {fact_id}")

    print()
    print("CONOCIMIENTO:")

    for knowledge_id in selection["knowledge_ids"]:
        print(f"- {knowledge_id}")


if __name__ == "__main__":
    main()