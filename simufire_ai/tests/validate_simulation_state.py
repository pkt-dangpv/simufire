import json
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]

SCHEMA_PATH = (
    BASE_DIR
    / "schemas"
    / "simulation_state.schema.json"
)

STATES_DIR = (
    BASE_DIR
    / "tests"
    / "data"
    / "simulation_states"
)


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_state(validator, state_path: Path) -> bool:
    state = load_json(state_path)

    errors = sorted(
        validator.iter_errors(state),
        key=lambda e: list(e.absolute_path)
    )

    if not errors:
        print(f"OK: {state_path.name}")
        return True

    print(f"ERROR: {state_path.name}")

    for error in errors:
        path = ".".join(str(x) for x in error.absolute_path)

        if not path:
            path = "<root>"

        print(f"  - {path}: {error.message}")

    return False


def main():
    schema = load_json(SCHEMA_PATH)
    validator = Draft202012Validator(schema)

    state_files = sorted(STATES_DIR.glob("*.json"))

    if not state_files:
        print("No hay estados para validar.")
        return

    valid_count = 0

    for state_path in state_files:
        if validate_state(validator, state_path):
            valid_count += 1

    print()
    print(
        f"Resultado: "
        f"{valid_count}/{len(state_files)} estados validos"
    )


if __name__ == "__main__":
    main()