"""F3.3r2a pure surface-energy solver contract."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER_PATH = ROOT / "sim/core/Phase3SurfaceEnergySolver.gd"
FIXTURE_PATH = ROOT / "tests/fixtures/phase3_f33r2a_surface_energy_solver.gd"
SOLVER = SOLVER_PATH.read_text(encoding="utf-8")
FIXTURE = FIXTURE_PATH.read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"static func {name}"
    start = source.index(marker)
    next_func = source.find("\nstatic func ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_solver_is_pure_and_has_no_runtime_authority():
    assert "extends RefCounted" in SOLVER
    assert "class_name Phase3SurfaceEnergySolver" in SOLVER
    assert "preload(" not in SOLVER
    assert "room." not in SOLVER
    assert "building." not in SOLVER


def test_solver_uses_five_explicit_nodes():
    assert "const NODE_COUNT: int = 5" in SOLVER
    assert "DEFAULT_NODE_DEPTH_FRACTIONS" in SOLVER
    assert "nodes_c must contain five temperatures" in SOLVER


def test_state_is_duplicated_before_post_step_write():
    body = _function(SOLVER, "step_surface")
    assert "var post_state: Dictionary = pre_state.duplicate(true)" in body
    assert 'post_state["nodes_c"] = nodes_post' in body
    assert 'pre_state["nodes_c"] =' not in body


def test_solver_uses_implicit_finite_volume_capacities():
    body = _function(SOLVER, "step_surface")
    assert "capacity_rate_kw_m2_k" in body
    assert "conductance_kw_m2_k" in body
    assert "diagonal[edge] += conductance_kw_m2_k" in body
    assert "diagonal[edge + 1] += conductance_kw_m2_k" in body


def test_energy_ledger_keeps_fire_and_gas_radiation_separate():
    body = _function(SOLVER, "step_surface")
    assert 'boundary.get("gas_radiation_energy_kj", 0.0)' in body
    assert 'boundary.get("fire_radiation_energy_kj", 0.0)' in body
    assert '"gas_radiation_energy_kj": gas_radiation_energy_kj' in body
    assert '"fire_radiation_energy_kj": fire_radiation_energy_kj' in body


def test_energy_residual_includes_storage_convection_radiation_and_exterior():
    body = _function(SOLVER, "step_surface")
    for term in (
        "stored_energy_delta_kj",
        "interior_convection_energy_kj",
        "gas_radiation_energy_kj",
        "fire_radiation_energy_kj",
        "exterior_energy_removed_kj",
        "energy_residual_kj",
    ):
        assert term in body


def test_no_temperature_or_energy_clamp_hides_residual():
    body = _function(SOLVER, "step_surface")
    assert "clampf(" not in body
    assert "maxf(" not in body
    assert "minf(" not in body


def test_invalid_inputs_fail_closed():
    assert "static func _validate_state" in SOLVER
    assert "static func _validate_boundary" in SOLVER
    assert "singular tridiagonal system" in SOLVER
    assert "non-finite post-step temperature" in SOLVER


def test_fixture_covers_all_f33r2a_stop_gates():
    for test_name in (
        "_test_constant_ambient_is_noop",
        "_test_radiation_only_closes_energy",
        "_test_early_convection_matches_semi_infinite_reference",
        "_test_long_run_conserves_energy",
        "_test_input_state_is_immutable",
        "_test_invalid_state_fails_closed",
    ):
        assert test_name in FIXTURE
    assert "range(10000)" in FIXTURE
    assert "relative_rise_error <= 0.05" in FIXTURE
    assert "PHASE3_F33R2A_SURFACE_ENERGY_SOLVER_PASS" in FIXTURE


def test_solver_runtime_wiring_is_only_the_opt_in_f33r2b_owner():
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    system = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
    room_model = (ROOT / "sim/building/RoomModel.gd").read_text(encoding="utf-8")
    assert "Phase3SurfaceEnergySolver" not in engine
    assert "Phase3SurfaceEnergySolver" not in room_model
    assert system.count("Phase3SurfaceEnergySolver.gd") == 1
    assert (
        "@export var phase3_canonical_multisurface_shadow_enabled: bool = false"
        in engine
    )
    assert "commit_canonical_multisurface_combustion_radiation" in system
