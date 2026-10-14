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
    "simufire_ai/tests/test_grounded_fact_ventilation_limited.py",
    "simufire_ai/tests/test_grounded_fact_dependencies.py",
    "simufire_ai/tests/test_question_ventilation_limited.py",
    "simufire_ai/tests/test_question_answer_safety.py",
    "simufire_ai/tests/test_question_vl_e2e.py",
    "simufire_ai/tests/test_analysis_pipeline.py",
    "simufire_ai/tests/test_question_scope.py",
    "simufire_ai/tests/test_validation_exit_codes.py",
    "simufire_ai/tests/test_question_evaluation.py",
    "simufire_ai/tests/test_explicit_question_contract.py",
    "simufire_ai/tests/test_measurement_evidence.py",
    "simufire_ai/tests/test_expert_followup.py",
    "simufire_ai/tests/test_tactical_hydraulics.py",
    "simufire_ai/tests/test_equipment_catalog.py",
    "simufire_ai/tests/test_online_sources.py",
    "simufire_ai/tests/test_presentation_and_standards.py",
    "simufire_ai/tests/test_flow_context.py",
    "simufire_ai/tests/test_intervention_report.py"
]


def main():

    passed = 0
    failed = 0

    print("=" * 60)
    print("SIMUFIRE AI - TEST SUITE DETERMINISTA (SIN OLLAMA)", flush=True)
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
                "-u",
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
