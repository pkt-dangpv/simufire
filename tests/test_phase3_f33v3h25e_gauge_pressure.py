"""Contracts for the F3.3v3h2.5e gauge-pressure formulation.

H2.5c captured a solve that reached 1.147e-12 against a 1e-12 tolerance and
could not finish: the remaining correction was 0.38 ulp of an absolute-pressure
iterate near 101325 Pa. H2.5d measured that a gauge unknown closes that capture
and never regresses a case the absolute form solved.

These tests pin the change to a change of VARIABLE. Everything H2.5d measured
as a dead end - centred differences, a different merit, a retuned Jacobian step,
a relaxed tolerance - must stay out.
"""
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER_PATH = ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd"
SOLVER = SOLVER_PATH.read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests" / "fixtures" / "phase3_f33v3h25e_gauge_pressure.gd"
).read_text(encoding="utf-8")


def _code_only(text: str) -> str:
    return "\n".join(
        "" if line.lstrip().startswith("#") else line
        for line in text.splitlines()
    )


CODE = _code_only(SOLVER)


def _function(name: str) -> str:
    body = CODE.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


# ---------------------------------------------------------------------------
# the reference is an input, not a constant
# ---------------------------------------------------------------------------

def test_gauge_reference_comes_from_the_solve_not_a_global_constant():
    build = _function("_build_context")
    assert 'options.get(\n\t\t"exterior_pressure_abs_pa", AIR_PRESSURE_REF_PA\n\t)' \
        in build or '"exterior_pressure_abs_pa", AIR_PRESSURE_REF_PA' in build
    assert 'context["exterior_pressure_abs_pa"] = exterior_pressure_abs_pa' in build
    # the exterior air density must follow the same reference
    assert "var exterior_density_kg_m3: float = exterior_pressure_abs_pa" in build


def test_reference_is_validated():
    build = _function("_build_context")
    assert "not is_finite(exterior_pressure_abs_pa)" in build
    assert "exterior_pressure_abs_pa <= 0.0" in build


def test_evaluate_reads_the_reference_from_the_context():
    body = _function("_evaluate")
    assert 'context["exterior_pressure_abs_pa"]' in body
    # validity is on the absolute pressure the gauge iterate represents
    assert "+ exterior_pressure_abs_pa <= 0.0" in body


# ---------------------------------------------------------------------------
# dp is a gauge difference; the EOS avoids the cancellation
# ---------------------------------------------------------------------------

def test_opening_difference_is_a_direct_gauge_subtraction():
    body = _function("_evaluate")
    # the exterior side is exactly zero in gauge, never the ambient constant
    assert "float(pressure[index_a]) if index_a >= 0 else 0.0" in body
    assert "float(pressure[index_b]) if index_b >= 0 else 0.0" in body
    assert "pressure_a_pa - pressure_b_pa," in body


def test_residual_is_built_around_a_reference_mass():
    """Requirement: never form `implied_abs - reference_abs`.

    Subtracting two numbers near 101325 Pa discards about four significant
    digits, which is the very defect this phase removes. The EOS is instead
    expanded about the mass that would sit at the reference pressure.
    """
    body = _function("_evaluate")
    assert '(balance_mass_kg - float(room["reference_mass_kg"]))' in body
    # the forbidden shape, in any spacing
    assert not re.search(r"implied_pressure_pa\s*-\s*\w*exterior", body)
    assert not re.search(r"implied_\w*\s*-\s*AIR_PRESSURE_REF_PA", body)


def test_reference_mass_is_derived_from_the_supplied_reference():
    body = _function("_derive_room")
    assert "var reference_mass_kg: float = exterior_pressure_abs_pa * volume_m3" in body
    assert "gas_constant * reference_temp_k" in body
    assert '"reference_mass_kg": reference_mass_kg,' in body


def test_seed_is_a_gauge_pressure_without_a_subtraction():
    derive = _function("_derive_room")
    assert "var gauge_pressure_pa: float = gas_constant * (" in derive
    assert "(total_mass_kg - reference_mass_kg) * reference_temp_k" in derive
    solve = _function("solve_coupled_pressure")
    assert 'context["rooms"][room_key]["gauge_pressure_pa"]' in solve
    assert 'pressure_abs_pa"]))' not in solve


# ---------------------------------------------------------------------------
# absolute is rebuilt only on the way out
# ---------------------------------------------------------------------------

def test_absolute_pressure_is_reconstructed_only_in_the_output():
    body = _function("_pressure_map")
    assert "value + exterior_pressure_abs_pa" in body
    assert "AIR_PRESSURE_REF_PA" not in body
    # exactly one place rebuilds it
    assert CODE.count("value + exterior_pressure_abs_pa") == 1


def test_gas_constant_still_uses_the_canonical_reference():
    # R = P_ref / (rho_ref * T_ref) is the canonical EOS constant and is NOT the
    # exterior boundary. Tying it to the boundary would change the physics.
    assert "var gas_constant: float = AIR_PRESSURE_REF_PA \\" in SOLVER
    assert "/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)" in SOLVER


# ---------------------------------------------------------------------------
# nothing else moved
# ---------------------------------------------------------------------------

def test_every_numerical_constant_is_unchanged():
    expected = {
        "DEFAULT_MAX_ITERATIONS": "24",
        "DEFAULT_RESIDUAL_TOLERANCE": "1.0e-12",
        "DEFAULT_DP_REGULARIZATION_PA": "0.01",
        "DEFAULT_JACOBIAN_STEP_PA": "1.0e-3",
        "DEFAULT_BAND_SEGMENTS": "16",
        "DEFAULT_MAX_DAMPING_HALVINGS": "12",
    }
    for name, value in expected.items():
        assert re.search(rf"const {name}: \w+ = {re.escape(value)}\b", SOLVER), name


def test_jacobian_merit_damping_and_flux_law_are_untouched():
    solve = _function("solve_coupled_pressure")
    assert ") / jacobian_step_pa" in solve          # forward difference
    assert "/ (2.0 * jacobian_step_pa)" not in solve
    assert "damping *= 0.5" in solve
    evaluate = _function("_evaluate")
    assert 'float(room["mass_kg"])' in evaluate     # L-infinity, room inventory
    assert "sqrt(2.0 * density * magnitude_pa)" in SOLVER
    assert "sqrt(2.0 * density * dp_regularization_pa)" in SOLVER


def test_no_new_tuning_knob():
    # H2.5g's LM_RESCUE_ARMIJO_C is a documented global constant, not a knob:
    # it is never read from `options` and never varies per case. What must stay
    # absent is anything selectable.
    for forbidden in (
        "jacobian_mode", "merit_mode", "cycle_ratio", "nonmonotone",
        "seed_pressure_by_room", "flux_regularization_mode",
    ):
        assert forbidden not in CODE.lower(), forbidden
    for constant in ("LM_RESCUE_ARMIJO_C", "LM_RESCUE_LAMBDA_LADDER",
                     "LM_RESCUE_MAX_ACCEPTED_STEPS"):
        assert f"const {constant}" in SOLVER, constant
        assert f'options.get("{constant.lower()}"' not in SOLVER


def test_no_alpha_blend_or_skew():
    for forbidden in ("alpha", "blend", "skew", "fixed_gross", "relaxation"):
        assert forbidden not in CODE.lower(), forbidden


# ---------------------------------------------------------------------------
# the fixture states the properties, not just the outcome
# ---------------------------------------------------------------------------

def test_fixture_covers_the_mandatory_properties():
    assert "PHASE3_F33V3H25E_GAUGE_PRESSURE_PASS" in FIXTURE
    for test_name in (
        "_test_shift_invariance",
        "_test_non_default_exterior_reference",
        "_test_absolute_output_is_gauge_plus_reference",
        "_test_conservation_and_counterflow",
        "_test_determinism",
        "_test_gauge_iterate_is_small",
    ):
        assert test_name in FIXTURE, test_name
    # a reference away from ambient is actually exercised
    assert "90000.0" in FIXTURE


def test_corridor_capture_was_closed_by_the_h25g_recovery():
    """H2.5e fixed the numerical-floor mode only and left corridor open.

    H2.5g closed it with a bounded recovery, so this contract now records that
    handover rather than asserting a failure that no longer exists.
    """
    corridor = (
        ROOT / "tests" / "fixtures"
        / "phase3_f33v3h25a_captured_solver_failure.gd"
    ).read_text(encoding="utf-8")
    assert 'bool(result["converged"]),' in corridor
    assert "F3.3v3h2.5g" in corridor
    # the gauge change itself is still what fixed r0, and must stay
    assert "gauge_pressure_pa" in SOLVER
