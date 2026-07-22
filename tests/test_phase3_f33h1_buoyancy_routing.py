from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (ROOT / "tests/fixtures/phase3_f33h1_buoyancy_routing.gd").read_text(
    encoding="utf-8"
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_cfast_constant_and_exact_tanhsmooth_formula_are_present():
    assert "CFAST_DESTINATION_DELTA_TEMP_K: float = 1.0" in SYSTEM
    body = _function(SYSTEM, "_cfast_tanhsmooth")
    assert "0.5 + 0.5025 * tanh(" in body
    assert "6.0 / (xmax - xmin) * (x - xmin) - 3.0" in body


def test_preview_uses_effective_lower_temperature_and_returns_both_fractions():
    body = _function(SYSTEM, "preview_cfast_buoyancy_destination_split")
    assert "minf(" in body
    assert "destination_lower_temp_c, destination_upper_temp_c" in body
    assert "destination_upper_temp_c + CFAST_DESTINATION_DELTA_TEMP_K" in body
    assert "effective_lower_temp_c - CFAST_DESTINATION_DELTA_TEMP_K" in body
    assert "ZONE_LOWER: 1.0 - upper_fraction" in body
    assert "ZONE_UPPER: upper_fraction" in body


def test_interval_keeps_source_geometry_and_adds_optional_destination_split():
    body = _function(SYSTEM, "_canonical_interior_interval_flow")
    assert "buoyancy_destination_enabled: bool = false" in body
    assert "source_zone: String = _canonical_zone_at_height" in body
    assert "preview_cfast_buoyancy_destination_split(" in body
    assert 'result["destination_fractions"] = destination_fractions' in body


def test_split_is_consumed_by_common_route_accumulator():
    body = _function(SYSTEM, "_accumulate_canonical_interior_route")
    assert '"destination_fractions", {}' in body
    assert "interval_flow.get(" in body
    assert "mass_flow_kg_s * fraction" in body
    assert "for destination_zone in [ZONE_LOWER, ZONE_UPPER]" in body


def test_opening_pressure_and_internal_queue_share_candidate_contract():
    for name in (
        "preview_canonical_interior_opening",
        "preview_canonical_interior_pressure_flow",
        "_integrate_canonical_interior_opening",
        "queue_canonical_interior_opening_requests",
    ):
        assert "buoyancy_destination_enabled" in _function(SYSTEM, name)


def test_design_gate_has_no_public_runtime_surface():
    public_flag = "phase3_buoyancy_destination"
    for source in (ENGINE, STATE, LOG, RUNNER, HEADLESS):
        assert public_flag not in source


def test_fixture_covers_formula_split_conservation_and_order():
    assert "PHASE3_F33H1_BUOYANCY_ROUTING_PASS" in FIXTURE
    for test_name in (
        "_test_exact_cfast_tanhsmooth_contract",
        "_test_interval_uses_temperature_not_geometry_or_source_identity",
        "_test_opening_and_pressure_preserve_total_flow",
        "_test_atomic_direct_and_poreh_bundles_remain_separate",
        "_test_opening_order_is_equivalent",
    ):
        assert test_name in FIXTURE
