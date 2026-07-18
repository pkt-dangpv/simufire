from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
OXYGEN = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
ZONE_MASS = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_shadow_energy_transfer_is_default_off():
    body = _function(THERMAL, "_record_phase3_shadow_energy_transfer")
    assert "not phase3_canonical_zone_shadow_enabled" in body
    assert "energy_kj <= 0.0" in body


def test_combustion_heat_owner_does_not_depend_on_doorway_scope():
    step = _function(THERMAL, "step")
    marker = '"cause": "combustion_convective_heat"'
    prefix = step[: step.index(marker)]
    guard = prefix[prefix.rfind("\n\t\tif ") :]
    assert "phase3_canonical_zone_shadow_enabled" in guard
    assert "_phase3_shadow_sealed_room_scope" not in guard


def test_plume_owner_does_not_depend_on_doorway_scope():
    body = _function(THERMAL, "_step_two_zone_plume_entrainment")
    assert "if phase3_canonical_zone_shadow_enabled:" in body
    assert "_phase3_shadow_sealed_room_scope" not in body


def test_all_local_thermal_energy_causes_are_explicit():
    for cause in (
        "thermal_upper_radiative_loss",
        "thermal_upper_to_lower",
        "thermal_upper_to_ambient",
        "thermal_wall_absorption",
        "thermal_wall_emission",
        "thermal_lower_decay",
        "thermal_lower_fresh_air_cooling",
    ):
        assert f'"{cause}"' in THERMAL


def test_lower_decay_records_exact_accepted_energy():
    step = _function(THERMAL, "step")
    assert "var lower_decay_kj: float = _zone_fire_solver.remove_lower_energy_fraction" in step
    assert '"thermal_lower_decay", room.id, -1' in step
    assert '"lower", "lower", lower_decay_kj' in step


def test_upper_to_lower_is_internal_not_an_exterior_sink():
    step = _function(THERMAL, "step")
    assert '"thermal_upper_to_lower", room.id, room.id' in step
    assert '"upper", "lower", energy_to_lower_kj' in step


def test_wall_emission_direction_is_reservoir_to_room():
    step = _function(THERMAL, "step")
    assert '"thermal_wall_emission", -1, room.id' in step


def test_bulk_o2_owner_is_only_added_for_invalid_two_zone_homogenization():
    step = _function(OXYGEN, "step")
    invalid = step.index("if lower_frac < 0.15:")
    upper_sink = step.index('"combustion_o2_bulk_upper_sink"')
    assert invalid < upper_sink
    assert "if _o2_fire_primary > 0.0:" in step[invalid:upper_sink]


def test_bulk_o2_owner_preserves_total_debit_by_geometric_split():
    step = _function(OXYGEN, "step")
    assert "_o2_fire_primary * upper_frac" in step
    assert "_o2_fire_primary * lower_frac" in step


def test_bulk_o2_owner_uses_combustion_prefix_for_mask():
    assert '"combustion_o2_bulk_upper_sink"' in OXYGEN
    assert '"combustion_o2_bulk_lower_sink"' in OXYGEN
    mask = _function(ZONE_MASS, "_combustion_owned_mask")
    assert '_room_has_cause_prefix(room_id, "combustion_o2_")' in mask


def test_thermal_reservoir_has_an_explicit_semantic_owner():
    owner = _function(ZONE_MASS, "_semantic_owner_for_claim")
    assert '"thermal_reservoir":' in owner
    assert 'return "ThermalSystem" if quantity == "enthalpy" else ""' in owner


def test_engine_classifies_only_non_internal_local_energy_as_reservoir():
    collect = _function(ENGINE, "_phase3_shadow_collect_thermal_requests") + _function(
        ENGINE, "_phase3_shadow_add_thermal_request"
    )
    assert 'cause != "plume_entrainment" and cause != "thermal_upper_to_lower"' in collect
    assert 'thermal_boundary_kind = "thermal_reservoir"' in collect


def test_patch_does_not_add_a_new_authority_flag():
    assert "phase3_f31c" not in ENGINE.lower()
    assert "single_room_thermal_authority" not in ENGINE
