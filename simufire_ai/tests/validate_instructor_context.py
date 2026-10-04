import json
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]

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
        return

    valid_count = 0

    for path in files:

        data = load_json(path)

        errors = sorted(
            validator.iter_errors(data),
            key=lambda e: list(e.absolute_path)
        )

        if not errors:
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


if __name__ == "__main__":
    main()