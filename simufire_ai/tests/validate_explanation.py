import json
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "explanation.schema.json"
)

EXPLANATIONS_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "explanations"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_explanation(
    validator,
    explanation_path: Path
) -> bool:

    explanation = load_json(explanation_path)

    errors = sorted(
        validator.iter_errors(explanation),
        key=lambda e: list(e.absolute_path)
    )

    if not errors:
        print(f"OK: {explanation_path.name}")
        return True

    print(f"ERROR: {explanation_path.name}")

    for error in errors:
        path = ".".join(
            str(x) for x in error.absolute_path
        )

        if not path:
            path = "<root>"

        print(f"  - {path}: {error.message}")

    return False


def main():
    schema = load_json(SCHEMA_PATH)
    validator = Draft202012Validator(schema)

    explanation_files = sorted(
        EXPLANATIONS_DIR.glob("*.json")
    )

    if not explanation_files:
        print("No hay explicaciones para validar.")
        return

    valid_count = 0

    for explanation_path in explanation_files:
        if validate_explanation(
            validator,
            explanation_path
        ):
            valid_count += 1

    print()
    print(
        f"Resultado: "
        f"{valid_count}/"
        f"{len(explanation_files)} "
        f"explicaciones validas"
    )


if __name__ == "__main__":
    main()