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
    / "analysis_context"
    / "basic_room_001_context.json"
)

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "explanation.schema.json"
)

OUTPUT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "generated_explanations"
)

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "qwen3:1.7b"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def call_ollama(prompt: str, output_schema: dict):

    payload = {
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "think": False,

        # IMPORTANTE:
        # Ollama recibe directamente nuestro JSON Schema.
        "format": output_schema,

        "options": {
            "temperature": 0
        }
    }

    data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(
        OLLAMA_URL,
        data=data,
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

    event_ids = [
        event["event_id"]
        for event in context["detected_events"]
    ]

    prompt = f"""
Eres SimuFire AI.

Tu única función es explicar hechos ya detectados
por el motor físico y por Fire Event Analyzer.

NO eres el motor físico.

REGLAS OBLIGATORIAS:

1. No inventes hechos, variables ni fenómenos.

2. No establezcas una causa física que no aparezca
   respaldada por los eventos y sus evidencias.

3. No uses expresiones como:
   - incendio muy intenso
   - incendio severo
   - situación crítica
   salvo que exista un evento que lo determine.

4. No expliques cambios de presión salvo que exista
   un evento específico relacionado con presión.

5. No expliques por qué desciende la capa de humo
   salvo que los datos proporcionados permitan
   establecer esa causa.

6. Puedes describir que una variable aumentó o
   disminuyó si aparece en detected_events.

7. Una acción seguida de un cambio no demuestra
   automáticamente causalidad.

8. En el evento ventilation_increase sí puedes indicar
   que la apertura está asociada al aumento de ventilación,
   porque Fire Event Analyzer ya ha establecido esa relación.

9. No afirmes flashover, backdraft o rollover si no existe
   explícitamente el evento correspondiente.

10. Si no tienes información suficiente para explicar
    una causa, dilo claramente.

11. La explicación debe estar dirigida a un bombero.

12. source_ids debe ser [] por ahora.

13. limitations debe ser siempre una lista de textos.

DATOS FIJOS:

schema_version = "0.1"
scenario_id = "{context["scenario"]["scenario_id"]}"
explanation_id = "ai_explanation_001"
language = "es"
audience_level = "firefighter"

EVENTOS PERMITIDOS:

{json.dumps(event_ids, ensure_ascii=False)}

CONTEXTO:

{json.dumps(context, indent=2, ensure_ascii=False)}
"""

    print("Consultando SimuFire AI...")

    raw_response = call_ollama(
        prompt,
        schema
    )

    try:
        explanation = json.loads(raw_response)

    except json.JSONDecodeError:

        print("ERROR: Qwen no devolvio JSON valido.")
        print()
        print(raw_response)
        sys.exit(1)

    validator = Draft202012Validator(schema)

    errors = list(
        validator.iter_errors(explanation)
    )

    if errors:

        print("ERROR: la respuesta no cumple el schema.")

        for error in errors:
            print(
                f"- {error.json_path}: "
                f"{error.message}"
            )

        print()
        print(
            json.dumps(
                explanation,
                indent=2,
                ensure_ascii=False
            )
        )

        sys.exit(1)

    invalid_event_ids = [
        event_id
        for event_id in explanation["event_ids"]
        if event_id not in event_ids
    ]

    if invalid_event_ids:

        print(
            "ERROR: la IA ha utilizado event_ids "
            "que no existen:"
        )

        for event_id in invalid_event_ids:
            print(f"- {event_id}")

        sys.exit(1)

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    output_path = (
        OUTPUT_DIR
        / "basic_room_001_ai_explanation.json"
    )

    with output_path.open(
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            explanation,
            f,
            indent=2,
            ensure_ascii=False
        )

    print("OK: explicacion generada y validada")
    print()

    print("RESUMEN:")
    print(explanation["summary"])

    print()
    print("EXPLICACION:")
    print(explanation["explanation"])

    print()
    print(
        f"Confianza: "
        f"{explanation['confidence']}"
    )

    print()

    print("LIMITACIONES:")

    for limitation in explanation["limitations"]:
        print(f"- {limitation}")


if __name__ == "__main__":
    main()