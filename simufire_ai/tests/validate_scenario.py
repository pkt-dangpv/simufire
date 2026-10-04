import json
from pathlib import Path

from jsonschema import Draft202012Validator


BASE_DIR = Path(__file__).resolve().parents[1]
SCHEMA_PATH = BASE_DIR / "schemas" / "scenario.schema.json"
SCENARIOS_DIR = BASE_DIR / "scenarios"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_scenario(validator, scenario_path: Path) -> bool:
    scenario = load_json(scenario_path)

    errors = sorted(
        validator.iter_errors(scenario),
        key=lambda e: list(e.absolute_path)
    )

    if not errors:
        print(f"OK: {scenario_path.name}")
        return True

    print(f"ERROR: {scenario_path.name}")

    for error in errors:
        path = ".".join(str(x) for x in error.absolute_path)
        if not path:
            path = "<root>"

        print(f"  - {path}: {error.message}")

    return False


def main():
    schema = load_json(SCHEMA_PATH)
    validator = Draft202012Validator(schema)

    scenario_files = sorted(SCENARIOS_DIR.glob("*.json"))

    if not scenario_files:
        print("No hay escenarios para validar.")
        return

    valid_count = 0

    for scenario_path in scenario_files:
        if validate_scenario(validator, scenario_path):
            valid_count += 1

    print()
    print(f"Resultado: {valid_count}/{len(scenario_files)} escenarios validos")


if __name__ == "__main__":
    main()