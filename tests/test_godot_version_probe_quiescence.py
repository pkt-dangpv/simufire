"""Fail-first contract for an uncontaminated Godot version probe."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "tools/mutation_audit.py").read_text(encoding="utf-8")


def _function(name: str) -> str:
    marker = f"def {name}("
    start = SOURCE.index(marker)
    end = SOURCE.find("\ndef ", start + len(marker))
    return SOURCE[start:] if end < 0 else SOURCE[start:end]


def test_version_probe_requires_a_continuous_quiet_period_before_launch() -> None:
    gate = _function("_require_godot_quiet_period")
    probe = _function("_verify_godot_version")

    assert "quiet_s: float = 15.0" in gate
    assert "timeout_s: float = 120.0" in gate
    assert "_godot_processes()" in gate
    assert "quiet_started = None" in gate
    assert "Godot process state did not remain quiet" in gate
    assert "_require_godot_quiet_period()" in probe
    assert probe.index("_require_godot_quiet_period()") < probe.index(
        "_run_monitored("
    )
