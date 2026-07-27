from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim" / "core" / "Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
SOLVER = (ROOT / "sim" / "core" / "Phase3CoupledPressureSolver.gd").read_text(
    encoding="utf-8"
)
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(
    encoding="utf-8"
)
LOGGER = (ROOT / "sim" / "core" / "SimulationLogWriter.gd").read_text(
    encoding="utf-8"
)
RUNNER = (ROOT / "scripts" / "run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools" / "run_scenario_headless.gd").read_text(encoding="utf-8")

FLAG = "phase3_coupled_pressure_solver_shadow_enabled"
PREFIX = "phase3_shadow_coupled_solver_"
RECORDER = "_record_coupled_pressure_solver_preview"


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


# 1. flag is opt-in and default OFF
def test_flag_is_default_off_and_requires_the_interior_opening_stack():
    assert f"@export var {FLAG}: bool = false" in ENGINE
    helper = ENGINE.split(
        "func _phase3_coupled_pressure_solver_active() -> bool:", 1
    )[1].split("\n\n", 1)[0]
    for prerequisite in (
        "phase3_canonical_zone_shadow_enabled",
        "phase3_canonical_persistence_shadow_enabled",
        "phase3_canonical_interior_opening_shadow_enabled",
        FLAG,
    ):
        assert prerequisite in helper, prerequisite


def test_flag_is_propagated_through_every_surface():
    assert FLAG in STATE
    assert f"var {FLAG}: bool = false" in LOGGER
    for module in (ENGINE, LOGGER):
        assert "configure_phase3_coupled_pressure_solver_shadow" in module
    assert "configure_coupled_pressure_solver_shadow" in SYSTEM
    assert "configure_coupled_pressure_solver_shadow" in ENGINE
    assert "--phase3-coupled-pressure-solver-shadow" in RUNNER
    assert "phase3_coupled_pressure_solver_shadow" in HEADLESS


# 2. the preview writes no physical state
def test_preview_emits_no_route_bundle_or_state():
    body = _function(SYSTEM, RECORDER)
    for forbidden in (
        "add_atomic_bundle",
        "make_atomic_bundle",
        "make_atomic_route",
        "network_routes",
        "_transactions",
        "_persistent_zone_state",
        "_requests.append",
    ):
        assert forbidden not in body, forbidden
    # it may only write its own two ledgers
    written = {
        line.split("[")[0].strip()
        for line in body.splitlines()
        if line.strip().startswith("_") and "] = " in line
    }
    assert written <= {
        "_coupled_pressure_solver_by_room",
        "_coupled_pressure_solver_cumulative_by_room",
    }, written


def test_preview_does_not_mutate_the_resolved_shadow():
    body = _function(SYSTEM, RECORDER)
    # `shadow` is the resolved canonical state; the preview may only read it
    assert "shadow[" not in body
    assert "shadow.get(" in body


def test_solver_is_instantiated_fresh_and_holds_no_state():
    body = _function(SYSTEM, RECORDER)
    assert "Phase3CoupledPressureSolverScript.new()" in body
    assert "solve_coupled_pressure(" in body
    # the H1 primitive still owns no member state
    for line in SOLVER.splitlines():
        assert not line.startswith("var "), f"solver holds state: {line}"


# 3. owner sources are complete
def test_owner_sources_are_recovered_from_the_full_step_delta():
    body = _function(SYSTEM, RECORDER)
    # owner_source = (post - pre) - interior_network_accepted
    assert '"mass_kg": (post_mass_kg - pre_mass_kg) - interior_net_mass_kg,' in body
    assert (
        '"energy_kj": (post_energy_kj - pre_energy_kj) - interior_net_energy_kj,'
        in body
    )
    assert "accepted_in_gas_kg" in body and "accepted_out_gas_kg" in body
    assert "accepted_in_energy_kj" in body and "accepted_out_energy_kj" in body


def test_preview_runs_after_every_owner_has_been_applied():
    finalize = _function(SYSTEM, "finalize_step")
    apply_index = finalize.index("_apply_canonical_exterior_boundary_requests(")
    preview_index = finalize.index(RECORDER + "(")
    assert apply_index < preview_index, (
        "the preview must run after the exterior boundary is applied, or the "
        "recovered owner sources would be incomplete"
    )


def test_preview_reuses_the_geometry_the_legacy_path_used():
    body = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "if coupled_pressure_solver_shadow_enabled:" in body
    assert "_coupled_pressure_solver_context = {" in body
    assert "for descriptor in descriptors:" in body


# 4. telemetry
def test_columns_are_emitted_only_when_the_flag_is_on():
    assert LOGGER.count(f"if {FLAG}:") == 2
    fields = LOGGER.split("func _phase3_coupled_solver_fields()", 1)[1].split(
        "\n\n", 1
    )[0]
    for field in (
        "converged_flag",
        "iterations",
        "normalized_residual",
        "solved_pressure_gauge_pa",
        "observed_pressure_gauge_pa",
        "coupled_vs_legacy_pressure_delta_pa",
        "predicted_net_mass_kg",
        "legacy_net_mass_kg",
        "net_mass_difference_kg",
        "predicted_net_energy_kj",
        "legacy_net_energy_kj",
        "net_energy_difference_kj",
        "owner_source_mass_kg",
        "owner_source_energy_kj",
        "counterflow_connection_count",
        "counterflow_violation_count",
        "regularization_active_count",
        "iteration_cap_flag",
        "damping_exhausted_flag",
    ):
        assert f"{PREFIX}{field}" in fields, field
    for field in (
        "step_count_total",
        "converged_step_count_total",
        "failed_step_count_total",
        "iteration_cap_step_count_total",
        "damping_exhausted_step_count_total",
        "max_iterations_total",
        "max_normalized_residual_total",
        "max_abs_coupled_vs_legacy_pressure_delta_pa_total",
        "max_abs_net_mass_difference_kg_total",
        "counterflow_violation_count_total",
    ):
        assert f"{PREFIX}{field}" in fields, field


def test_new_columns_never_collide_with_an_existing_family():
    coupled = LOGGER.split("func _phase3_coupled_solver_fields()", 1)[1].split(
        "\n\n", 1
    )[0]
    names = {
        line.strip().strip('",')
        for line in coupled.splitlines()
        if line.strip().startswith('"')
    }
    assert names
    for other in ("_phase3_pressure_network_fields", "_phase3_fixed_gross_pressure_skew_fields"):
        block = LOGGER.split(f"func {other}()", 1)[1].split("\n\n", 1)[0]
        existing = {
            line.strip().strip('",')
            for line in block.splitlines()
            if line.strip().startswith('"')
        }
        assert not (names & existing), other


def test_both_non_convergence_modes_are_reported_separately():
    body = _function(SYSTEM, RECORDER)
    assert 'limiting_reason == "iteration_cap"' in body
    assert 'limiting_reason == "damping_exhausted"' in body
    assert "iteration_cap_step_count" in body
    assert "damping_exhausted_step_count" in body


def test_divergence_column_is_not_named_as_solver_error():
    # the gap measures coupled-versus-legacy transport, not solver accuracy;
    # naming it "prediction error" invited exactly that misreading
    assert "pressure_prediction_error" not in LOGGER
    assert "pressure_prediction_error" not in SYSTEM


def test_step_and_cumulative_ledgers_have_explicit_reset_contracts():
    assert "_coupled_pressure_solver_by_room.clear()" in SYSTEM
    assert SYSTEM.count("_coupled_pressure_solver_cumulative_by_room.clear()") >= 2
    assert "_coupled_pressure_solver_context.clear()" in SYSTEM
