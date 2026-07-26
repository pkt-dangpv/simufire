from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim" / "core" / "SimulationEngine.gd").read_text(
    encoding="utf-8"
)
SYSTEM = (ROOT / "sim" / "core" / "Phase3ZoneMassSystem.gd").read_text(
    encoding="utf-8"
)
STATE = (ROOT / "sim" / "core" / "SimulationStateBuilder.gd").read_text(
    encoding="utf-8"
)
LOGGER = (ROOT / "sim" / "core" / "SimulationLogWriter.gd").read_text(
    encoding="utf-8"
)
RUNNER = (ROOT / "scripts" / "run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools" / "run_scenario_headless.gd").read_text(
    encoding="utf-8"
)
FIXTURE = (
    ROOT / "tests" / "fixtures" / "phase3_f33v3g2_pressure_network_preview.gd"
).read_text(encoding="utf-8")


FLAG = "phase3_canonical_fixed_gross_pressure_network_shadow_enabled"
PREVIEW = "preview_fixed_gross_interior_pressure_network"
RECORDER = "_record_fixed_gross_interior_pressure_network_preview"


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def _preview_block() -> str:
    start = SYSTEM.index("if fixed_gross_pressure_network_preview_enabled:")
    end = SYSTEM.index("for raw_pressure_route in pressure_routes_raw:", start)
    return SYSTEM[start:end]


# 1. flag default OFF and wiring
def test_flag_is_opt_in_and_requires_the_previous_canonical_stack():
    assert f"@export var {FLAG}: bool = false" in ENGINE
    helper = ENGINE.split(
        "func _phase3_canonical_fixed_gross_pressure_network_active() -> bool:",
        1,
    )[1].split("\n\n", 1)[0]
    assert "_phase3_canonical_fixed_gross_pressure_skew_active()" in helper
    assert FLAG in helper


def test_flag_is_separate_from_the_f33v3f1_flag():
    old_flag = "phase3_canonical_fixed_gross_pressure_skew_shadow_enabled"
    assert f"@export var {old_flag}: bool = false" in ENGINE
    old_helper = ENGINE.split(
        "func _phase3_canonical_fixed_gross_pressure_skew_active() -> bool:", 1
    )[1].split("\n\n", 1)[0]
    assert FLAG not in old_helper


def test_state_csv_runner_and_headless_wiring_are_opt_in():
    assert FLAG in STATE
    assert f"var {FLAG}: bool = false" in LOGGER
    assert (
        "configure_phase3_canonical_fixed_gross_pressure_network_shadow"
        in ENGINE
    )
    assert (
        "configure_phase3_canonical_fixed_gross_pressure_network_shadow"
        in LOGGER
    )
    assert "--phase3-canonical-fixed-gross-pressure-network-shadow" in RUNNER
    assert "phase3_canonical_fixed_gross_pressure_network_shadow" in HEADLESS


# 2. no caller applies the preview routes
def test_preview_never_reaches_bundles_transactions_or_state():
    for name in (PREVIEW, "_preview_fixed_gross_pressure_component", RECORDER):
        body = _function(SYSTEM, name)
        assert "add_atomic_bundle" not in body
        assert "make_atomic_bundle" not in body
        assert "_transactions" not in body
        assert "_atomic_bundles" not in body
        assert "network_routes.append" not in body
        assert "_persistent_zone_state" not in body


def test_preview_block_appends_nothing_to_the_canonical_bundle():
    block = _preview_block()
    assert "network_routes.append" not in block
    assert "add_atomic_bundle" not in block
    assert RECORDER in block
    assert block.index(PREVIEW) < block.index(RECORDER)
    assert SYSTEM.index(RECORDER + "(\n", SYSTEM.index(block)) < SYSTEM.index(
        "network_routes.append(pressure_route)"
    )


def test_component_solver_is_the_only_new_primitive_call_site():
    name = "compute_fixed_gross_pressure_network_relaxation"
    component_body = _function(SYSTEM, "_preview_fixed_gross_pressure_component")
    assert f"{name}(" in component_body
    assert SYSTEM.count(f"{name}(") == 2


# 3. connected components
def test_connected_component_contracts_are_covered_by_the_runtime_fixture():
    assert "PHASE3_F33V3G2_PRESSURE_NETWORK_PREVIEW_PASS" in FIXTURE
    for test_name in (
        "_test_components_single_connection",
        "_test_components_three_room_chain",
        "_test_components_two_disconnected",
        "_test_components_reversed_opening_order",
        "_test_disconnected_components_do_not_influence_each_other",
        "_test_opening_order_invariance",
    ):
        assert test_name in FIXTURE


def test_component_identity_is_independent_of_opening_order():
    body = _function(SYSTEM, "compute_interior_pressure_network_components")
    assert "sort_custom" in body
    assert "members.sort()" in body
    assert 'mini(room_a_id, room_b_id)' in body
    assert '"|".join(id_parts)' in body


# 4. the full candidate is built from the raw pressure demand
def test_full_candidate_uses_raw_pressure_demand():
    block = _preview_block()
    assert "network_routes, pressure_routes_raw" in block
    assert "pressure_routes" not in block.replace("pressure_routes_raw", "")


def test_base_routes_are_the_interior_opening_routes():
    block = _preview_block()
    call = block.split(PREVIEW + "(", 1)[1]
    arguments = [
        line.strip().rstrip(",")
        for line in call.splitlines()
        if line.strip()
    ][:7]
    assert arguments[0] == "network_routes"
    assert arguments[1] == "network_full_routes"
    assert arguments[2] == "pressure_by_room"
    assert arguments[3] == "pressure_base_delta_by_room"
    assert arguments[4] == "network_full_delta_by_room"
    assert arguments[5] == "pressure_connection_pairs"
    assert arguments[6] == "_snapshots"


# 5. inventory bounds
def test_inventory_bound_covers_every_payload_and_fails_closed():
    body = _function(SYSTEM, "_fixed_gross_pressure_network_inventory_bound")
    assert '"gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"' in body
    assert "for species_name in PARCEL_SPECIES:" in body
    assert "inventory < 0.0" in body
    assert "base_out > inventory + 1.0e-9" in body
    assert '(inventory - base_out) / increment' in body
    # the bound never repairs or mutates an inventory
    assert "_snapshots" not in body
    assert "source_inventory_by_room[" not in body


def test_inventory_contracts_are_covered_by_the_runtime_fixture():
    for test_name in (
        "_test_gas_inventory_limits",
        "_test_energy_inventory_limits",
        "_test_o2_inventory_limits",
        "_test_species_inventory_limits",
        "_test_invalid_base_inventory_fails_closed",
    ):
        assert test_name in FIXTURE


# 6. payload interpolation with one common alpha
def test_every_payload_uses_the_same_component_alpha():
    body = _function(SYSTEM, "_preview_fixed_gross_pressure_component")
    assert body.count("base_value + alpha * (full_value - base_value)") == 2
    assert '"gas_mass_kg", "sensible_enthalpy_kj", "o2_kg"' in body
    assert "for species_name in PARCEL_SPECIES:" in body
    assert "alpha: float = clampf(" in body
    assert "if component_valid else 0.0" in body
    assert "negative_quantity_count" in body


def test_component_reports_atomic_closure_and_gross_preservation():
    body = _function(SYSTEM, "_preview_fixed_gross_pressure_component")
    for field in (
        '"gross_mass_residual_kg"',
        '"mass_residual_kg"',
        '"energy_residual_kj"',
        '"o2_residual_kg"',
        '"species_residual_kg"',
        '"predicted_min_upper_gas_kg"',
        '"predicted_min_lower_gas_kg"',
        '"predicted_collapse_count"',
        '"degenerate_zone_count"',
    ):
        assert field in body
    # an already-empty zone is degenerate, not a preview-caused collapse
    assert "if pre_gas_kg <= THERMO_MASS_EPS_KG:" in body


# 7/8. descent contracts
def test_objective_and_descent_bounds_come_from_the_pure_primitive():
    primitive = _function(
        SYSTEM, "compute_fixed_gross_pressure_network_relaxation"
    )
    assert "objective_post_pa2 >" in primitive
    assert "numerator >= -1.0e-12" in primitive
    assert "_test_non_descent_is_dormant" in FIXTURE
    assert "blend objective descends" in FIXTURE


# 9. OFF leaves the legacy schema untouched
def test_csv_columns_are_emitted_only_when_the_flag_is_on():
    assert LOGGER.count(f"if {FLAG}:") == 2
    header = LOGGER.split("func _phase3_pressure_network_fields()", 1)[0]
    assert "phase3_shadow_pressure_network_" not in header
    fields = LOGGER.split("func _phase3_pressure_network_fields()", 1)[1].split(
        "\n\n", 1
    )[0]
    for field in (
        "phase3_shadow_pressure_network_enabled_flag",
        "phase3_shadow_pressure_network_valid_flag",
        "phase3_shadow_pressure_network_component_count",
        "phase3_shadow_pressure_network_component_index",
        "phase3_shadow_pressure_network_connection_count",
        "phase3_shadow_pressure_network_alpha_optimal",
        "phase3_shadow_pressure_network_alpha_crossing",
        "phase3_shadow_pressure_network_alpha_inventory",
        "phase3_shadow_pressure_network_alpha_accepted",
        "phase3_shadow_pressure_network_limiting_reason_code",
        "phase3_shadow_pressure_network_objective_pre_pa2",
        "phase3_shadow_pressure_network_objective_post_pa2",
        "phase3_shadow_pressure_network_directional_derivative_pa2",
        "phase3_shadow_pressure_network_worsening_connection_count",
        "phase3_shadow_pressure_network_predicted_min_upper_gas_kg",
        "phase3_shadow_pressure_network_predicted_min_lower_gas_kg",
        "phase3_shadow_pressure_network_predicted_collapse_count_step",
        "phase3_shadow_pressure_network_degenerate_zone_count_step",
        "phase3_shadow_pressure_network_predicted_collapse_count_total",
        "phase3_shadow_pressure_network_degenerate_zone_count_total",
        "phase3_shadow_pressure_network_max_objective_increase_pa2_total",
        "phase3_shadow_pressure_network_max_abs_mass_residual_kg_total",
        "phase3_shadow_pressure_network_max_abs_energy_residual_kj_total",
        "phase3_shadow_pressure_network_max_abs_o2_residual_kg_total",
        "phase3_shadow_pressure_network_max_abs_species_residual_kg_total",
        "phase3_shadow_pressure_network_gross_mass_residual_kg",
        "phase3_shadow_pressure_network_mass_residual_kg",
        "phase3_shadow_pressure_network_energy_residual_kj",
        "phase3_shadow_pressure_network_o2_residual_kg",
        "phase3_shadow_pressure_network_species_residual_kg",
        "phase3_shadow_pressure_network_accepted_positive_net_kg_total",
        "phase3_shadow_pressure_network_accepted_negative_net_abs_kg_total",
        "phase3_shadow_pressure_network_invalid_count_total",
        "phase3_shadow_pressure_network_non_descent_count_total",
        "phase3_shadow_pressure_network_inventory_limited_count_total",
        "phase3_shadow_pressure_network_crossing_limited_count_total",
    ):
        assert field in fields, field
        assert field in SYSTEM, field


def test_new_columns_never_collide_with_the_f33v3f1_family():
    fields = LOGGER.split("func _phase3_pressure_network_fields()", 1)[1].split(
        "\n\n", 1
    )[0]
    assert "phase3_shadow_fixed_gross_" not in fields
    skew_fields = LOGGER.split(
        "func _phase3_fixed_gross_pressure_skew_fields()", 1
    )[1].split("\n\n", 1)[0]
    assert "phase3_shadow_pressure_network_" not in skew_fields


def test_step_and_cumulative_ledgers_have_explicit_reset_contracts():
    assert "_canonical_fixed_gross_pressure_network_by_room.clear()" in SYSTEM
    assert (
        SYSTEM.count(
            "_canonical_fixed_gross_pressure_network_cumulative_by_room.clear()"
        )
        >= 2
    )
