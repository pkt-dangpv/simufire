from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33g_doorway_jet_entrainment.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_no_go_candidate_has_no_public_runtime_surface():
    for flag in (
        "phase3_doorway_jet_entrainment_enabled",
        "phase3_doorway_jet_entrainment_shadow_enabled",
        "--phase3-doorway-jet-entrainment-shadow",
    ):
        assert flag not in ENGINE
        assert flag not in STATE
        assert flag not in LOG
        assert flag not in RUNNER
        assert flag not in HEADLESS


def test_slabs_preserve_geometry_direction_and_both_zone_views():
    interval = _function(SYSTEM, "_canonical_interior_interval_flow")
    for field in (
        '"bottom_m": bottom_m',
        '"top_m": top_m',
        '"source_side"',
        '"destination_side"',
        '"source_zone"',
        '"geometric_destination_zone"',
        '"destination_zone"',
    ):
        assert field in interval
    integrate = _function(SYSTEM, "_integrate_canonical_interior_opening")
    assert '"slabs": slabs' in integrate
    assert "_append_canonical_interior_slab" in integrate


def test_opening_and_pressure_previews_export_mass_equivalent_slabs():
    opening = _function(SYSTEM, "preview_canonical_interior_opening")
    pressure = _function(SYSTEM, "preview_canonical_interior_pressure_flow")
    assert 'result["slabs"] = slabs' in opening
    assert 'result["slabs"] = slabs' in pressure
    assert "signed_scale" in pressure


def test_direct_and_mixing_routes_are_separate_atomic_bundles():
    queue = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert '"f33a_interior_network"' in queue
    assert '"f33g_doorway_jet_network"' in queue
    assert "add_atomic_bundle(bundle)" in queue
    assert "add_atomic_bundle(mixing_bundle)" in queue
    assert queue.index("add_atomic_bundle(bundle)") < queue.index(
        "add_atomic_bundle(mixing_bundle)"
    )


def test_candidate_implies_source_preserving_direct_transport():
    queue = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "direct_source_preserving" in queue
    assert "or doorway_jet_entrainment_enabled" in queue


def test_pressure_mixing_uses_relaxed_slab_flow():
    queue = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    build_pos = queue.index("_scaled_canonical_interior_slabs(")
    relaxation_pos = queue.index("compute_interior_network_pressure_relaxation(")
    assert relaxation_pos < build_pos
    assert "pressure_fraction" in queue[relaxation_pos:build_pos + 500]


def test_internal_candidate_remains_explicit_and_default_off():
    queue = _function(SYSTEM, "queue_canonical_interior_opening_requests")
    assert "doorway_jet_entrainment_enabled: bool = false" in queue
    assert "if doorway_jet_entrainment_enabled:" in queue


def test_internal_candidate_keeps_separate_residence_family():
    assert '"canonical_doorway_jet_entrainment":' in SYSTEM
    assert 'return "doorway_jet"' in SYSTEM
    assert '"doorway_jet"' in SYSTEM


def test_fixture_covers_slabs_pairing_conservation_and_order():
    for test_name in (
        "_test_slab_decomposition_preserves_aggregates",
        "_test_network_pair_is_conservative_and_order_independent",
    ):
        assert test_name in FIXTURE
