import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]

TESTS = [
    "simufire_ai/tests/validate_scenario.py",
    "simufire_ai/tests/validate_simulation_state.py",
    "simufire_ai/tests/validate_fire_event.py",
    "simufire_ai/tests/validate_explanation.py",
    "simufire_ai/tests/validate_analysis_context.py",
    "simufire_ai/tests/validate_grounded_fact.py",

    "simufire_ai/tests/validate_knowledge_entry.py",
    "simufire_ai/tests/validate_instructor_context.py",

    "simufire_ai/tests/test_fire_event_analyzer.py",
    "simufire_ai/tests/test_fire_event_analyzer_no_false_positives.py",
    "simufire_ai/tests/test_fire_event_timeline.py",
    "simufire_ai/tests/test_ventilation_limited_pattern.py",

    "simufire_ai/tests/test_grounded_explanation_safety.py",
    "simufire_ai/tests/test_knowledge_retriever.py",
    "simufire_ai/tests/test_instructor_explanation_safety.py",
    "simufire_ai/tests/test_question_modes.py",
    "simufire_ai/tests/test_question_answer_safety.py"
]


def main():

    passed = 0
    failed = 0

    print("=" * 60)
    print("SIMUFIRE AI - TEST SUITE")
    print("=" * 60)

    for test in TESTS:

        print()
        print("-" * 60)
        print(f"EJECUTANDO: {test}")
        print("-" * 60)

        test_path = REPO_ROOT / test

        result = subprocess.run(
            [
                sys.executable,
                str(test_path)
            ],
            cwd=REPO_ROOT
        )

        if result.returncode == 0:

            print()
            print(f"OK: {test}")
            passed += 1

        else:

            print()
            print(f"FALLO: {test}")
            failed += 1

    print()
    print("=" * 60)
    print("RESULTADO FINAL")
    print("=" * 60)

    print(f"Superados: {passed}")
    print(f"Fallidos: {failed}")
    print(f"Total: {len(TESTS)}")

    print()

    if failed == 0:

        print("RESULTADO: TODO OK")
        print(
            f"{passed}/{len(TESTS)} tests superados"
        )
        sys.exit(0)

    print("RESULTADO: HAY ERRORES")
    sys.exit(1)


if __name__ == "__main__":
    main()
