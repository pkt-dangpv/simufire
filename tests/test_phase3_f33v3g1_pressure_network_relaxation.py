from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim" / "core" / "Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
FIXTURE = (
    ROOT
    / "tests"
    / "fixtures"
    / "phase3_f33v3g1_pressure_network_relaxation.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_primitive_exists_without_runtime_call_site():
    name = "compute_fixed_gross_pressure_network_relaxation"
    assert f"func {name}(" in SYSTEM
    assert SYSTEM.count(name) == 1


def test_primitive_is_pure_and_fails_closed():
    body = _function(
        SYSTEM, "compute_fixed_gross_pressure_network_relaxation"
    )
    assert "_snapshots" not in body
    assert "_canonical_" not in body
    assert 'result["failure_code"]' in body
    assert "not is_finite" in body


def test_objective_descent_crossing_and_inventory_are_separate():
    body = _function(
        SYSTEM, "compute_fixed_gross_pressure_network_relaxation"
    )
    for field in (
        '"optimal_fraction"',
        '"crossing_fraction"',
        '"inventory_fraction"',
        '"objective_pre_pa2"',
        '"objective_post_pa2"',
        '"directional_derivative_pa2"',
    ):
        assert field in body
    assert "numerator >= -1.0e-12" in body
    assert "objective_post_pa2 >" in body


def test_runtime_fixture_covers_required_g1_contracts():
    assert "PHASE3_F33V3G1_PRESSURE_NETWORK_RELAXATION_PASS" in FIXTURE
    for test_name in (
        "_test_single_connection",
        "_test_chain",
        "_test_non_descent",
        "_test_inventory_bound",
        "_test_disconnected_independence",
        "_test_order_independence",
        "_test_zero_response",
        "_test_malformed_fails_closed",
    ):
        assert test_name in FIXTURE
