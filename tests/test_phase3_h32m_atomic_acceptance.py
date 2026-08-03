"""Contracts for the H3.2-M pure donor-acceptance extraction."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_h32m_atomic_acceptance.gd"
).read_text(encoding="utf-8")


def _function(name: str) -> str:
    body = SYSTEM.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


def test_evaluator_is_separate_from_legacy_accounting():
    body = _function("_evaluate_atomic_bundle_acceptance")
    for forbidden in (
        "_atomic_bundle_count",
        "_atomic_route_count",
        "_atomic_min_accepted_fraction",
        "_atomic_rejected_",
        "_duplicate_owner_count",
        "_apply_atomic_route",
        "_record_atomic_bundle_result",
    ):
        assert forbidden not in body


def test_legacy_path_delegates_to_the_pure_evaluator_once():
    body = _function("_apply_atomic_bundle")
    assert body.count("_evaluate_atomic_bundle_acceptance(") == 1
    assert 'var source_demands: Dictionary = evaluation["source_demands"]' in body


def test_all_quantities_share_one_fraction():
    evaluator = _function("_evaluate_atomic_bundle_acceptance")
    for quantity in (
        'zone + "_gas_kg"',
        'zone + "_energy_kj"',
        'zone + "_o2_kg"',
        "source_species.get(species_name",
    ):
        assert quantity in evaluator
    scaled = _function("_scaled_atomic_routes")
    for quantity in ("gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"):
        assert quantity in scaled
    assert "* accepted_fraction" in scaled


def test_fixture_is_fail_closed_and_checks_purity():
    assert "if _failed:" in FIXTURE
    assert "quit(1)" in FIXTURE
    assert "return" in FIXTURE.split("if _failed:", 1)[1].split("quit(0)", 1)[0]
    assert "evaluation never mutates shadow" in FIXTURE
    assert "legacy path consumes the extracted fraction" in FIXTURE
