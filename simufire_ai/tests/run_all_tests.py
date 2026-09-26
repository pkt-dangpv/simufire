import subprocess
import sys
from pathlib import Path


TESTS_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = TESTS_DIR.parents[1]


TESTS = [
    "validate_scenario.py",
    "validate_simulation_state.py",
    "validate_fire_event.py",
    "validate_explanation.py",
    "test_fire_event_analyzer.py",
    "test_fire_event_analyzer_no_false_positives.py",
    "test_fire_event_timeline.py"
]


def main():

    print("=== SimuFire AI Test Suite ===")
    print()

    failed = []

    for test in TESTS:

        test_path = TESTS_DIR / test

        print(f"> {test}")

        result = subprocess.run(
            [sys.executable, str(test_path)],
            cwd=PROJECT_ROOT
        )

        if result.returncode != 0:
            failed.append(test)

        print()

    print("=" * 40)

    if failed:
        print("RESULTADO: ERROR")
        print("Tests fallidos:")

        for test in failed:
            print(f"- {test}")

        sys.exit(1)

    print("RESULTADO: TODO OK")
    print(f"{len(TESTS)}/{len(TESTS)} tests superados")


if __name__ == "__main__":
    main()