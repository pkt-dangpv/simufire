from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
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


def test_poreh_constants_match_current_cfast_source():
    assert "POREH_AIR_DENSITY_TEMPERATURE_KG_K_M3: float = 352.981915" in SYSTEM
    assert "POREH_ENTRAINMENT_COEFFICIENT: float = 0.44" in SYSTEM
    assert "POREH_COOL_JET_MIXING_FACTOR: float = 0.25" in SYSTEM


def test_preview_is_pure_and_has_no_runtime_surface():
    for runtime_flag in (
        "phase3_doorway_jet_entrainment_enabled",
        "phase3_doorway_jet_entrainment_shadow_enabled",
        "--phase3-doorway-jet-entrainment-shadow",
    ):
        assert runtime_flag not in ENGINE
        assert runtime_flag not in RUNNER
        assert runtime_flag not in HEADLESS
    body = _function(SYSTEM, "preview_canonical_doorway_jet_entrainment")
    assert "RoomModel" not in body
    assert "_snapshots" not in body
    assert "add_atomic_bundle" not in body


def test_preview_implements_both_cfast_receiver_mixing_families():
    body = _function(SYSTEM, "preview_canonical_doorway_jet_entrainment")
    assert 'source_zone == ZONE_UPPER and destination_zone == ZONE_LOWER' in body
    assert 'source_zone == ZONE_LOWER and destination_zone == ZONE_UPPER' in body
    assert '"hot_jet_lower_to_upper"' in body
    assert '"cool_jet_upper_to_lower"' in body
    assert "POREH_COOL_JET_MIXING_FACTOR" in body


def test_preview_uses_current_poreh_formula_and_cfast_depths():
    body = _function(SYSTEM, "preview_canonical_doorway_jet_entrainment")
    for term in (
        "destination_interface_m - maxf(vent_bottom_m, source_interface_m)",
        "minf(vent_top_m, source_interface_m)",
        "maxf(destination_interface_m, vent_bottom_m)",
        "pow(lower_temp_k / upper_temp_k, 2.0 / 3.0)",
        "pow(heat_flow_w, 1.0 / 3.0)",
        "pow(opening_width_m, 2.0 / 3.0)",
    ):
        assert term in body


def test_route_uses_receiver_snapshot_and_one_atomic_payload():
    body = _function(SYSTEM, "make_canonical_doorway_jet_entrainment_route")
    assert "_snapshots[room_key]" in body
    assert 'destination_room_id,\n\t\tdestination_room_id' in body
    assert 'source_zone + "_energy_kj"' in body
    assert 'source_zone + "_o2_kg"' in body
    assert 'source_zone + "_species_kg"' in body
    assert "make_atomic_route(" in body


def test_doorway_jet_is_classified_as_interior_opening_residence():
    body = _function(SYSTEM, "_enthalpy_cause_family")
    assert '"canonical_doorway_jet_entrainment"' in body
    assert 'return "interior_opening"' in body


def test_runtime_fixture_covers_formula_activation_scaling_and_conservation():
    assert "PHASE3_F33G_DOORWAY_JET_ENTRAINMENT_PASS" in FIXTURE
    for test_name in (
        "_test_hot_jet_uses_full_poreh_entrainment",
        "_test_cool_jet_uses_quarter_poreh_entrainment",
        "_test_same_zone_and_wrong_temperature_are_inactive",
        "_test_poreh_scaling_contract",
        "_test_atomic_receiver_route_conserves_all_payloads",
    ):
        assert test_name in FIXTURE
