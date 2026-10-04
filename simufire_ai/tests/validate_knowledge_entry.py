import json
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "knowledge_entry.schema.json"
)

KNOWLEDGE_DIR = (
    BASE_DIR
    / "knowledge"
    / "entries"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def main():

    schema = load_json(SCHEMA_PATH)
    validator = Draft202012Validator(schema)

    files = sorted(
        KNOWLEDGE_DIR.glob("*.json")
    )

    if not files:
        print("No hay entradas de conocimiento.")
        return

    valid_count = 0

    for path in files:

        entry = load_json(path)

        errors = sorted(
            validator.iter_errors(entry),
            key=lambda e: list(e.absolute_path)
        )

        if not errors:
            print(f"OK: {path.name}")
            valid_count += 1
            continue

        print(f"ERROR: {path.name}")

        for error in errors:

            location = ".".join(
                str(x)
                for x in error.absolute_path
            )

            if not location:
                location = "<root>"

            print(
                f"  - {location}: "
                f"{error.message}"
            )

    print()

    print(
        f"Resultado: "
        f"{valid_count}/{len(files)} "
        f"entradas validas"
    )


if __name__ == "__main__":
    main()