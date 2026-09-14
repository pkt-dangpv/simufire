"""Contracts for the final non-authoritative O2 ownership disposition."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DISPOSITION = ROOT / "docs/validation/P1R8_O2_OWNER_001_DISPOSITION.md"
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
CASE_RUNNER = (ROOT / "sim/validation/CaseRunner.gd").read_text(encoding="utf-8")


def test_o2_owner_has_a_final_evidenced_disposition() -> None:
    text = DISPOSITION.read_text(encoding="utf-8")
    assert "O2-OWNER-001" in text
    assert "VERIFIED_MODEL_LIMITATION" in text
    assert "Candidates A, B and C" in text
    assert "sessions 114-123" in text


def test_disposition_does_not_claim_runtime_authority() -> None:
    text = DISPOSITION.read_text(encoding="utf-8")
    assert "Runtime authority: NO-GO" in text
    assert "H3.2b4: NO-GO" in text
    assert "H3.3: NO-GO" in text
    assert "HVAC: excluded" in text


def test_withdrawn_z0_z1_has_no_runtime_surface() -> None:
    combined = "\n".join((ENGINE, COMBUSTION, CASE_RUNNER))
    assert "evaluate_phase3_conservative_two_zone_o2" not in combined
    assert "phase3_conservative_two_zone_o2_shadow_enabled" not in combined
    assert "--validation-p1r-z1-two-zone-o2-shadow" not in combined
