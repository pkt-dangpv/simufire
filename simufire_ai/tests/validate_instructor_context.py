import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE_DIR))

from llm.question_context import validate_context

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "instructor_context.schema.json"
)

CONTEXT_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "instructor_context"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main():

    schema = load_json(SCHEMA_PATH)
    validator = Draft202012Validator(schema)

    files = sorted(
        CONTEXT_DIR.glob("*.json")
    )

    if not files:
        print("No hay contextos de instructor.")
        return 1

    valid_count = 0

    for path in files:

        data = load_json(path)

        errors = sorted(
            validator.iter_errors(data),
            key=lambda e: list(e.absolute_path)
        )

        if not errors:
            try:
                validate_context(data)
            except ValueError as error:
                print(f"ERROR: {path.name}: {error}")
                continue
            print(f"OK: {path.name}")
            valid_count += 1
            continue

        print(f"ERROR: {path.name}")

        for error in errors:
            print(
                f"- {error.json_path}: "
                f"{error.message}"
            )

    print()

    print(
        f"Resultado: "
        f"{valid_count}/{len(files)} "
        f"contextos validos"
    )

    return int(valid_count != len(files))


if __name__ == "__main__":
    raise SystemExit(main())
