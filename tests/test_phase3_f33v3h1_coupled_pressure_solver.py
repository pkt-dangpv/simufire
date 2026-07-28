from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER_PATH = ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd"
SOLVER = SOLVER_PATH.read_text(encoding="utf-8")
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(
    encoding="utf-8"
)
SYSTEM = (ROOT / "sim" / "core" / "Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
LOGGER = (ROOT / "sim" / "core" / "SimulationLogWriter.gd").read_text(
    encoding="utf-8"
)
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(
    encoding="utf-8"
)
RUNNER = (ROOT / "scripts" / "run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools" / "run_scenario_headless.gd").read_text(
    encoding="utf-8"
)
FIXTURE = (
    ROOT / "tests" / "fixtures" / "phase3_f33v3h1_coupled_pressure_solver.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def _code_only(source: str) -> str:
    """Strip GDScript comments.

    The header deliberately names the types the solver must NOT reach and the
    failure mode it must NOT reproduce, so a forbidden-identifier scan has to
    look at code rather than prose.
    """
    lines = []
    for line in source.splitlines():
        quote_count = 0
        cut = len(line)
        for index, char in enumerate(line):
            if char == '"':
                quote_count += 1
            elif char == "#" and quote_count % 2 == 0:
                cut = index
                break
        lines.append(line[:cut])
    return "\n".join(lines)


SOLVER_CODE = _code_only(SOLVER)


# ---------------------------------------------------------------------------
# H1 scope: pure primitive, no runtime reach
# ---------------------------------------------------------------------------

def test_solver_has_exactly_one_passive_call_site():
    """H1 had no caller at all. F3.3v3h2 adds exactly one, and it is passive.

    The primitive itself is unchanged: the contract that matters is that the
    only thing calling it is the read-only preview recorder, never a route
    builder or a state writer.
    """
    assert SOLVER_PATH.exists()
    assert "class_name Phase3CoupledPressureSolver" in SOLVER
    # nothing outside Phase3ZoneMassSystem may reach the solver
    for module in (ENGINE, LOGGER, STATE):
        assert "Phase3CoupledPressureSolver" not in module
        assert "solve_coupled_pressure" not in module
    assert SYSTEM.count("solve_coupled_pressure(") == 1
    caller = _function(SYSTEM, "_record_coupled_pressure_solver_preview")
    assert "solve_coupled_pressure(" in caller
    for forbidden in ("add_atomic_bundle", "make_atomic_route", "network_routes"):
        assert forbidden not in caller, forbidden


def test_solver_declares_no_flag_and_no_persistent_state():
    assert "@export" not in SOLVER_CODE
    # no member state at all: every `var` must be function-local
    for line in SOLVER_CODE.splitlines():
        if line.startswith("var "):
            raise AssertionError(f"solver holds member state: {line}")


def test_solver_never_reaches_engine_or_model_types():
    for forbidden in (
        "RoomModel",
        "BuildingModel",
        "SimulationEngine",
        "Phase3ZoneMassSystem",
        "preload(",
        "get_room",
        "_snapshots",
        "_persistent",
        "add_atomic_bundle",
        "make_atomic_bundle",
    ):
        assert forbidden not in SOLVER_CODE, forbidden


def test_solver_is_side_effect_free():
    # a pure library emits no signals, spawns no nodes and writes no files
    for forbidden in ("emit_signal", "FileAccess", "add_child", "set_meta"):
        assert forbidden not in SOLVER_CODE, forbidden


# ---------------------------------------------------------------------------
# one pressure unknown per room
# ---------------------------------------------------------------------------

def test_state_vector_is_one_pressure_per_room():
    body = _function(SOLVER, "solve_coupled_pressure")
    assert "var pressure: Array[float] = []" in body
    assert 'for room_key in room_keys:' in body
    # F3.3v3h2.5e: still exactly one unknown per room, now a gauge pressure.
    # The seed is read straight from the derived room rather than formed as
    # `pressure_abs_pa - exterior`, so it carries no cancellation either.
    assert 'pressure.append(float(context["rooms"][room_key]["gauge_pressure_pa"]))' \
        in body
    # the Jacobian is square in the room count, i.e. one unknown per room
    assert "for column in range(room_count):" in body


def test_species_and_o2_are_deliberately_absent():
    # they do not appear in the EOS, so including them would be noise
    for absent in ("species", "o2_kg", "PARCEL_SPECIES"):
        assert absent not in SOLVER_CODE, absent


# ---------------------------------------------------------------------------
# every owner inside the residual
# ---------------------------------------------------------------------------

def test_residual_contains_openings_and_owner_sources():
    body = _function(SOLVER, "_evaluate")
    # opening transport
    assert "net_mass_kg[index]" in body
    assert "net_energy_kj[index]" in body
    # owner sources, which is exactly what F3.3v3g3 left out
    assert 'float(room["source_mass_kg"])' in body
    assert 'float(room["source_energy_kj"])' in body
    # residual is the EOS of the complete balance minus the iterate
    assert "implied_pressure_pa - float(pressure[index])" in body


def test_sources_are_validated_rather_than_coerced():
    body = _function(SOLVER, "_build_context")
    assert "FAILURE_BAD_SOURCE" in body
    assert "is_finite(source_mass_kg)" in body
    assert "is_finite(source_energy_kj)" in body


# ---------------------------------------------------------------------------
# damped Newton
# ---------------------------------------------------------------------------

def test_newton_is_damped_and_only_accepts_improving_steps():
    body = _function(SOLVER, "solve_coupled_pressure")
    assert "var damping: float = 1.0" in body
    assert "damping *= 0.5" in body
    assert 'float(trial_evaluation["normalized_residual"]) < norm' in body
    # exhausting the damping is a failure, never a silent accept
    assert 'result["limiting_reason"] = "damping_exhausted"' in body
    assert "FAILURE_NOT_CONVERGED" in body


def test_convergence_measure_is_independent_of_the_pressure_iterate():
    # the F3.3v3h1 line-search bug: normalising by gross throughput makes the
    # merit function incomparable between iterates because the throughput
    # collapses as the solve approaches equilibrium
    body = _function(SOLVER, "_evaluate")
    assert 'absf(residual_kg) / maxf(MASS_EPS_KG, float(room["mass_kg"]))' in body
    assert "throughput_normalized_residual" in body
    assert "telemetry only" in body


def test_singular_jacobian_and_iteration_cap_fail_closed():
    body = _function(SOLVER, "solve_coupled_pressure")
    assert "FAILURE_SINGULAR_JACOBIAN" in body
    assert 'result["limiting_reason"] = "iteration_cap"' in body
    solve = _function(SOLVER, "_solve_linear_system")
    assert "return []" in solve
    assert "best_magnitude <= 1.0e-14" in solve
    # partial pivoting, not naive elimination
    assert "best_row" in solve


# ---------------------------------------------------------------------------
# regularisation
# ---------------------------------------------------------------------------

def test_flux_law_is_regularized_below_a_global_threshold():
    body = _function(SOLVER, "_regularized_flux_factor")
    assert "magnitude_pa >= dp_regularization_pa" in body
    assert "(magnitude_pa / dp_regularization_pa)" in body
    assert '"regularized": true' in body
    # the constant is global and explicitly not a per-case knob
    assert "DEFAULT_DP_REGULARIZATION_PA" in SOLVER
    assert "never a per-case knob" in SOLVER


def test_regularization_activity_is_reported():
    assert "regularization_active_count" in SOLVER
    body = _function(SOLVER, "_integrate_opening")
    assert "regularization_active_count += 1.0" in body


# ---------------------------------------------------------------------------
# structural counterflow
# ---------------------------------------------------------------------------

def test_counterflow_comes_from_the_neutral_plane_not_from_a_factor():
    body = _function(SOLVER, "_integrate_opening")
    # the band is split at the sign change of dp(z)
    assert "if dp0 * dp1 < 0.0:" in body
    assert "crossing_m" in body
    assert 'sub_bands.append({"z0": z0, "z1": crossing_m' in body
    assert 'sub_bands.append({"z0": crossing_m, "z1": z1' in body
    # direction follows the sign of dp, it is never a free variable
    assert "if dp_pa >= 0.0:" in body


def test_no_alpha_or_blend_factor_anywhere():
    # the F3.3v3g3 failure shape must be structurally impossible here
    for forbidden in ("alpha", "blend", "skew", "relaxation_fraction"):
        assert forbidden not in SOLVER_CODE.lower(), forbidden


def test_unphysical_one_way_solution_is_rejected():
    body = _function(SOLVER, "solve_coupled_pressure")
    assert 'bool(connection.get("neutral_plane_inside", false))' in body
    assert 'float(connection.get("a_to_b_kg", 0.0)) <= 0.0' in body
    assert 'float(connection.get("b_to_a_kg", 0.0)) <= 0.0' in body
    assert "FAILURE_COUNTERFLOW_VIOLATION" in body


# ---------------------------------------------------------------------------
# conservation and determinism
# ---------------------------------------------------------------------------

def test_antisymmetry_is_structural():
    body = _function(SOLVER, "_evaluate")
    # one integration feeds both endpoints with opposite sign
    assert "net_mass_kg[index_a] += b_to_a_kg - a_to_b_kg" in body
    assert "net_mass_kg[index_b] += a_to_b_kg - b_to_a_kg" in body
    assert "net_energy_kj[index_a] += b_to_a_kj - a_to_b_kj" in body
    assert "net_energy_kj[index_b] += a_to_b_kj - b_to_a_kj" in body


def test_room_and_opening_order_are_normalised():
    build = _function(SOLVER, "_build_context")
    assert "room_keys.sort()" in build
    assert "sort_custom" in build
    opening = _function(SOLVER, "_build_opening")
    assert '"sort_key": "%010d|%010d|%010d"' in opening
    assert "mini(room_a_id, room_b_id)" in opening


def test_eos_matches_the_canonical_affine_form():
    body = _function(SOLVER, "_derive_room")
    assert "gas_constant * (\n\t\ttotal_mass_kg * reference_temp_k" in body
    assert "total_energy_kj / AIR_CP_KJ_KG_K\n\t) / volume_m3" in body
    assert "AIR_PRESSURE_REF_PA \\\n\t\t\t/ (AIR_DENSITY_REF_KG_M3 * reference_temp_k)" \
        in _function(SOLVER, "_build_context")


# ---------------------------------------------------------------------------
# fail-closed input contracts
# ---------------------------------------------------------------------------

def test_invalid_geometry_and_inventory_fail_closed():
    body = _function(SOLVER, "_derive_room")
    assert "volume_m3 <= VOLUME_EPS_M3 or floor_area_m2 <= 0.0 or height_m <= 0.0" \
        in body
    assert "upper_gas_kg < 0.0 or lower_gas_kg < 0.0" in body
    assert "total_mass_kg <= MASS_EPS_KG" in body
    # a zone with energy but no mass has no defined temperature
    assert "upper_gas_kg <= MASS_EPS_KG and upper_energy_kj > 0.0" in body


def test_invalid_opening_fails_closed_and_shut_opening_is_skipped():
    body = _function(SOLVER, "_build_opening")
    assert "top_m <= bottom_m or width_m <= 0.0 or discharge_coeff <= 0.0" in body
    assert "room_a_id == room_b_id" in body
    # a shut opening is well formed and simply carries nothing
    assert '{"valid": true, "skip": true}' in body


def test_every_failure_path_returns_a_distinct_code():
    codes = [
        "FAILURE_BAD_ARGUMENTS",
        "FAILURE_BAD_ROOM_STATE",
        "FAILURE_BAD_OPENING",
        "FAILURE_BAD_SOURCE",
        "FAILURE_SINGULAR_JACOBIAN",
        "FAILURE_NOT_CONVERGED",
        "FAILURE_NON_FINITE_STATE",
        "FAILURE_COUNTERFLOW_VIOLATION",
    ]
    values = set()
    for name in codes:
        assert f"const {name}: float = " in SOLVER, name
        value = SOLVER.split(f"const {name}: float = ", 1)[1].split("\n", 1)[0]
        values.add(value)
    assert len(values) == len(codes), "failure codes must be distinct"


def test_failed_solve_emits_no_connection():
    body = _function(SOLVER, "solve_coupled_pressure")
    # connections are only attached to the result on the success path
    success_index = body.index('result["valid"] = true')
    assert body.index('result["connections"] = evaluation["connections"]') \
        > success_index


# ---------------------------------------------------------------------------
# fixture
# ---------------------------------------------------------------------------

def test_runtime_fixture_covers_the_required_h1_contracts():
    assert "PHASE3_F33V3H1_COUPLED_PRESSURE_SOLVER_PASS" in FIXTURE
    for test_name in (
        "_test_sealed_pair_is_already_converged",
        "_test_single_opening_equalizes_pressure",
        "_test_conservation_mass_and_energy",
        "_test_three_room_chain_converges",
        "_test_room_order_invariance",
        "_test_opening_order_invariance",
        "_test_antisymmetry_of_every_connection",
        "_test_counterflow_preserved_when_neutral_plane_is_inside",
        "_test_neutral_plane_matches_analytic_height",
        "_test_one_way_flow_when_neutral_plane_is_outside",
        "_test_regularization_bounds_the_near_zero_derivative",
        "_test_every_owner_is_inside_the_residual",
        "_test_source_only_room_reaches_eos_consistency",
        "_test_exterior_opening_relieves_pressure",
        "_test_malformed_input_fails_closed",
        "_test_negative_inventory_fails_closed",
        "_test_degenerate_geometry_fails_closed",
        "_test_iteration_cap_fails_closed",
    ):
        assert test_name in FIXTURE, test_name


def test_fixture_reports_failure_instead_of_falling_through_to_pass():
    # SceneTree.quit() only requests a shutdown, so a bare quit(1) would be
    # overwritten by the later quit(0) and the fixture would print PASS anyway.
    body = FIXTURE.split("func _init() -> void:", 1)[1].split("\n\n", 1)[0]
    assert "quit(1)\n\t\treturn" in body
