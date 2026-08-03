"""Structural contracts for the H3.2a zonal decomposition.

H3.2a is purely additive: it decomposes aggregates that are already final. The
contracts below pin that it stays additive - the aggregates are never rebuilt
from the routes, no numerical constant moved, the exterior is never labelled
with a layer it does not have, and nothing writes room state.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOLVER_PATH = ROOT / "sim/core/Phase3CoupledPressureSolver.gd"
SOLVER = SOLVER_PATH.read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33v3h32a_zonal_decomposition.gd"
).read_text(encoding="utf-8")
PROBE = (
    ROOT / "tools/diagnostics/phase3_h32a_zonal_probe.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    body = source.split(f"func {name}(", 1)[1]
    return body.split("\nfunc ", 1)[0]


# -------------------------------------------------------------------
# scope: one file, no state, no new knobs
# -------------------------------------------------------------------

def test_only_the_solver_gained_zonal_code():
    """H3.2a was authorised for the solver alone."""
    for other in (
        "sim/core/Phase3ZoneMassSystem.gd",
        "sim/core/SimulationEngine.gd",
        "sim/core/ThermalSystem.gd",
        "sim/core/GasExchangeSystem.gd",
        "sim/core/ZoneFireSolver.gd",
        "sim/building/RoomModel.gd",
    ):
        text = (ROOT / other).read_text(encoding="utf-8")
        assert "zonal_routes" not in text, other
        assert "zonal_decomposition" not in text, other


def test_no_room_state_is_written_by_the_solver():
    for pattern in (
        r"room\.(upper|lower)_(gas_kg|energy_kj)\s*[-+]?=",
        r"\.o2_(upper|lower)\s*[-+]?=",
        r"\.temp_(upper|lower)_c\s*[-+]?=",
    ):
        assert not re.search(pattern, SOLVER), pattern


def test_no_new_tunable_constant_was_added():
    consts = set(re.findall(r"^const (\w+)", SOLVER, re.M))
    # The only new constants are the two reporting labels.
    assert "ZONE_UPPER" in consts and "ZONE_LOWER" in consts
    assert not [c for c in consts if "ZONAL" in c or "H32A" in c]


def test_numerical_constants_h1_to_h210_are_intact():
    expected = {
        "DEFAULT_MAX_ITERATIONS": "24",
        "DEFAULT_RESIDUAL_TOLERANCE": "1.0e-12",
        "DEFAULT_DP_REGULARIZATION_PA": "0.01",
        "DEFAULT_JACOBIAN_STEP_PA": "1.0e-3",
        "DEFAULT_BAND_SEGMENTS": "16",
        "DEFAULT_MAX_DAMPING_HALVINGS": "12",
        "LM_RESCUE_MAX_ACCEPTED_STEPS": "1",
        "LM_RESCUE_ARMIJO_C": "1.0e-4",
        "CYCLE_GUARD_MIN_MODEL_GAIN_RATIO": "0.05",
        "CYCLE_GUARD_MAX_STEP_COSINE": "-0.99",
        "CYCLE_ANALYTIC_HALF_STEP": "0.5",
    }
    for name, value in expected.items():
        assert re.search(
            rf"const {name}: \w+ = {re.escape(value)}\b", SOLVER
        ), name


# -------------------------------------------------------------------
# additivity: aggregates are never rebuilt from routes
# -------------------------------------------------------------------

def test_aggregates_are_never_recomputed_from_zonal_routes():
    """The decisive structural guarantee of H3.2a.

    `a_to_b_kg` and friends must only ever be accumulated from the integration
    itself. If a route total were ever assigned back into an aggregate, the
    decomposition would stop being a report and start being the source of
    truth.
    """
    integrate = _function(SOLVER, "_integrate_opening")
    for aggregate in ("a_to_b_kg", "b_to_a_kg", "a_to_b_kj", "b_to_a_kj"):
        for line in integrate.splitlines():
            stripped = line.strip()
            if not stripped.startswith(f"{aggregate} "):
                continue
            # Only `+= mass_kg` / `+= mass_kg * specific_kj_kg` are allowed.
            assert "zonal" not in stripped, stripped
            assert "entry" not in stripped, stripped
    attach = _function(SOLVER, "_attach_zonal_decomposition")
    for aggregate in ("a_to_b_kg", "b_to_a_kg", "a_to_b_kj", "b_to_a_kj"):
        assert f'connection["{aggregate}"] =' not in attach, aggregate


def test_zonal_accumulation_mirrors_the_aggregate_branch():
    """Same dp sign decides both, so a route can never disagree in direction."""
    integrate = _function(SOLVER, "_integrate_opening")
    assert 'var direction: String = "a_to_b" if dp_pa >= 0.0 else "b_to_a"' \
        in integrate
    assert "if dp_pa >= 0.0:" in integrate


def test_zonal_block_is_guarded_by_band_zoning():
    integrate = _function(SOLVER, "_integrate_opening")
    assert "if band_zoned:" in integrate


# -------------------------------------------------------------------
# the zone label is a read, not a new derivation
# -------------------------------------------------------------------

def test_zone_convention_mirrors_the_density_convention():
    zone = _function(SOLVER, "_zone_at")
    density = _function(SOLVER, "_density_at")
    assert "height_m <= interface_m" in zone
    assert "height_m <= interface_m" in density
    assert "ZONE_LOWER if height_m <= interface_m else ZONE_UPPER" in zone


def test_zone_is_read_at_the_same_midpoint_as_the_density():
    build = _function(SOLVER, "_build_opening")
    assert '"density_a_kg_m3": _density_at(side_a, 0.5 * (z0 + z1))' in build
    assert '"zone_a": _zone_at(side_a, 0.5 * (z0 + z1))' in build
    assert '"zone_b": _zone_at(side_b, 0.5 * (z0 + z1))' in build


def test_bands_are_still_split_at_both_interfaces():
    """The whole decomposition rests on this pre-existing invariant."""
    build = _function(SOLVER, "_build_opening")
    assert 'float(side_a["interface_m"]), float(side_b["interface_m"])' in build
    assert "boundaries.append(interface_m)" in build
    assert "boundaries.sort()" in build


# -------------------------------------------------------------------
# exterior
# -------------------------------------------------------------------

def test_exterior_is_never_labelled_with_a_layer():
    zone = _function(SOLVER, "_zone_at")
    assert 'if bool(side.get("exterior", false)):' in zone
    assert 'return ""' in zone
    # And a non-finite interface also yields no label rather than lower.
    assert "if not is_finite(interface_m):" in zone


def test_exterior_connections_are_counted_separately():
    attach = _function(SOLVER, "_attach_zonal_decomposition")
    assert 'connection["zonal_decomposition_applicable"] = interior' in attach
    assert 'connection["exterior_unzoned_band_count"]' in attach
    summarize = _function(SOLVER, "_summarize_zonal_decomposition")
    assert "exterior_skipped += 1" in summarize
    assert "continue" in summarize


def test_exterior_never_invalidates_the_interior_network():
    summarize = _function(SOLVER, "_summarize_zonal_decomposition")
    # Validity is decided by interior bands only.
    assert 'result["zonal_decomposition_valid"] = ' \
        "unclassified_interior_bands == 0" in summarize
    assert "exterior_unzoned_bands" in summarize


def test_opening_interiority_requires_both_sides_to_be_rooms():
    build = _function(SOLVER, "_build_opening")
    assert '"interior": not bool(side_a.get("exterior", false))' in build
    assert 'not bool(side_b.get("exterior", false))' in build


# -------------------------------------------------------------------
# determinism and identity
# -------------------------------------------------------------------

def test_routes_are_sorted_deterministically():
    attach = _function(SOLVER, "_attach_zonal_decomposition")
    assert "routes.sort_custom(" in attach
    for key in ("connection_id", "direction", "source_zone", "destination_zone"):
        assert key in attach, key


def test_both_directions_share_one_connection_id():
    attach = _function(SOLVER, "_attach_zonal_decomposition")
    assert 'var connection_id: String = "opening:%d"' in attach
    # connection_id is computed once, before any direction is considered.
    assert attach.index("var connection_id") < attach.index('"direction"')


def test_route_payload_carries_every_mandated_field():
    attach = _function(SOLVER, "_attach_zonal_decomposition")
    for field in (
        "connection_id", "direction", "source_room_id", "destination_room_id",
        "source_zone", "destination_zone", "gas_mass_kg",
        "sensible_energy_kj", "band_count",
    ):
        assert f'"{field}"' in attach, field


def test_residual_is_reported_not_corrected():
    attach = _function(SOLVER, "_attach_zonal_decomposition")
    assert 'connection["zonal_mass_residual_kg"]' in attach
    assert 'connection["zonal_energy_residual_kj"]' in attach
    # No route or aggregate is adjusted to make the residual vanish.
    assert "gas_mass_kg\"] =" not in attach.split("var routes")[1].split(
        "routes.sort_custom"
    )[0].replace('"gas_mass_kg": float(entry["gas_mass_kg"]),', "")


def test_no_atomic_route_or_bundle_is_created_yet():
    """H3.2a stops at reporting; H3.2 is what registers bundles."""
    assert "make_atomic_route" not in SOLVER
    assert "add_atomic_bundle" not in SOLVER
    assert "make_atomic_bundle" not in SOLVER


# -------------------------------------------------------------------
# fixture coverage and negative controls
# -------------------------------------------------------------------

def test_fixture_covers_all_four_zone_combinations():
    for combo in (
        "upper->upper", "upper->lower", "lower->upper", "lower->lower",
    ):
        assert combo in FIXTURE, combo


def test_fixture_pins_the_exterior_contract():
    assert "_check_exterior_is_not_zoned" in FIXTURE
    assert "exterior connection is inapplicable" in FIXTURE
    assert "interior zones are real layers" in FIXTURE
    assert "exterior presence does not invalidate" in FIXTURE


def test_fixture_states_the_numeric_bound_and_its_measured_maximum():
    """The bound is a floating-point agreement limit, not a physical tolerance,
    and the summation order was deliberately NOT changed to force an exact
    zero."""
    assert "ZONAL_ENERGY_RESIDUAL_BOUND_KJ := 1.0e-12" in FIXTURE
    assert "ZONAL_MASS_RESIDUAL_BOUND_KG := 1.0e-12" in FIXTURE
    assert "1e-14" in FIXTURE
    assert "aggregate order is frozen" in FIXTURE


def test_fixture_checks_determinism_and_sort_order():
    assert "deterministic " in FIXTURE
    assert "routes are emitted in sorted order" in FIXTURE


def test_fixture_is_fail_closed():
    assert "_failed = true" in FIXTURE
    assert FIXTURE.index("if _failed:") < FIXTURE.index(
        "PHASE3_F33V3H32A_ZONAL_DECOMPOSITION_PASS"
    )


def test_probe_is_read_only():
    assert "extends SceneTree" in PROBE
    assert "FileAccess.WRITE" not in PROBE
    assert "SimulationEngine" not in PROBE
    assert "run_scenario" not in PROBE


# -------------------------------------------------------------------
# negative controls
# -------------------------------------------------------------------

def test_mutation_labelling_the_exterior_lower_is_detectable():
    zone = _function(SOLVER, "_zone_at")
    mutated = zone.replace('return ""', "return ZONE_LOWER")
    assert mutated != zone
    assert 'return ""' in zone, "the shipped code must not label the exterior"


def test_mutation_dropping_an_interface_invalidates_the_split():
    """Removing an interface from the boundary list would let a band cross it."""
    build = _function(SOLVER, "_build_opening")
    anchor = 'float(side_a["interface_m"]), float(side_b["interface_m"])'
    assert anchor in build
    mutated = build.replace(anchor, 'float(side_a["interface_m"])', 1)
    assert 'float(side_b["interface_m"])' not in mutated.split(
        "boundaries.sort()"
    )[0]


def test_unclassifiable_interior_band_is_counted_not_invented():
    integrate = _function(SOLVER, "_integrate_opening")
    assert "unclassified_interior_band_count += 1" in integrate
    # A band without both labels contributes no route.
    assert "if band_zoned:" in integrate
    attach = _function(SOLVER, "_attach_zonal_decomposition")
    assert "unclassified == 0" in attach
