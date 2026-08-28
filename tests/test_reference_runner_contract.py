from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = (ROOT / "sim/validation/run_reference_checks.ps1").read_text(
    encoding="utf-8-sig"
)
VALIDATOR = (ROOT / "scripts/simulation/validate_reference_cases.py").read_text(
    encoding="utf-8"
)


def test_reference_runner_delegates_valid_gap_policy_to_guardrails() -> None:
    assert "[int]$TimeoutSeconds = 900" in RUNNER
    assert "measured 658.089 s" in RUNNER
    assert "$referenceExitCode -notin @(0, 1)" in RUNNER
    assert '"scripts\\simulation\\validation_guardrails.py"' in RUNNER
    assert "& $PythonExe $guardrailsScript --json $referenceReport" in RUNNER
    assert "if ($guardrailsExitCode -ne 0)" in RUNNER


def test_reference_runner_never_declares_pass_before_guardrails() -> None:
    guardrails = RUNNER.index("& $PythonExe $guardrailsScript --json $referenceReport")
    pass_marker = RUNNER.index('Write-Host "[Reference Suite] Resultado final: PASS"')
    assert guardrails < pass_marker
    assert "VALID_GAP documentados" in RUNNER[guardrails:pass_marker]


def test_reference_validator_uses_timezone_aware_utc_timestamp() -> None:
    assert "datetime.datetime.utcnow()" not in VALIDATOR
    assert "datetime.datetime.now(datetime.UTC)" in VALIDATOR
