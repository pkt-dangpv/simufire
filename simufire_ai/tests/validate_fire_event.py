import json
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "fire_event.schema.json"
)

EVENT_DIRS = [
    BASE_DIR / "tests" / "data" / "fire_events",
    BASE_DIR / "tests" / "data" / "generated_events"
]


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_event(validator, event_path: Path) -> bool:
    event = load_json(event_path)

    errors = sorted(
        validator.iter_errors(event),
        key=lambda e: list(e.absolute_path)
    )

    if not errors:
        print(f"OK: {event_path.name}")
        return True

    print(f"ERROR: {event_path.name}")

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

    event_files = []

    for directory in EVENT_DIRS:
        if directory.exists():
            event_files.extend(
                sorted(directory.glob("*.json"))
            )

    if not event_files:
        print("No hay eventos para validar.")
        return

    valid_count = 0

    for event_path in event_files:
        if validate_event(validator, event_path):
            valid_count += 1

    print()
    print(
        f"Resultado: "
        f"{valid_count}/{len(event_files)} eventos validos"
    )


if __name__ == "__main__":
    main()