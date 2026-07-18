from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_thermo_valid_flag",
    "phase3_shadow_thermo_failure_code",
    "phase3_shadow_thermo_temp_upper_c",
    "phase3_shadow_thermo_temp_lower_c",
    "phase3_shadow_thermo_pressure_abs_pa",
    "phase3_shadow_thermo_pressure_gauge_pa",
    "phase3_shadow_thermo_upper_volume_m3",
    "phase3_shadow_thermo_lower_volume_m3",
    "phase3_shadow_thermo_volume_closure_error_m3",
    "phase3_shadow_thermo_interface_m",
    "phase3_shadow_thermo_mass_invariance_residual_kg",
    "phase3_shadow_thermo_energy_invariance_residual_kj",
    "phase3_shadow_canonical_transaction_closure_flag",
    "phase3_shadow_legacy_state_mass_divergence_kg",
    "phase3_shadow_legacy_state_energy_divergence_kj",
    "phase3_shadow_legacy_interface_divergence_m",
    "phase3_shadow_legacy_pressure_divergence_pa",
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_closure_is_owned_by_passive_shadow_component():
    assert "func derive_canonical_thermodynamic_state(" in SYSTEM
    assert "phase3_zone_mass_system.finalize_step(" in ENGINE
    assert "thermal_system.ambient_temp_c()" in ENGINE


def test_closure_is_pure_and_does_not_write_room_model():
    body = _function(SYSTEM, "derive_canonical_thermodynamic_state")
    assert "RoomModel" not in body
    assert "room." not in body
    assert "upper_gas_kg =" not in body
    assert "lower_gas_kg =" not in body
    assert "upper_energy_kj =" not in body
    assert "lower_energy_kj =" not in body


def test_mass_and_energy_are_inputs_to_derived_temperature():
    body = _function(SYSTEM, "derive_canonical_thermodynamic_state")
    assert "upper_energy_kj / (upper_gas_kg * AIR_CP_KJ_KG_K)" in body
    assert "lower_energy_kj / (lower_gas_kg * AIR_CP_KJ_KG_K)" in body
    assert "upper_gas_kg * upper_temp_k + lower_gas_kg * lower_temp_k" in body


def test_shared_pressure_derives_both_zone_volumes():
    body = _function(SYSTEM, "derive_canonical_thermodynamic_state")
    assert "pressure_abs_pa" in body
    assert "upper_volume_m3" in body
    assert "lower_volume_m3" in body
    assert "volume_closure_error_m3" in body
    assert "lower_volume_m3 / floor_area_m2" in body


def test_invalid_inventory_is_rejected_without_clamping_it():
    body = _function(SYSTEM, "derive_canonical_thermodynamic_state")
    assert "upper_gas_kg < 0.0" in body
    assert "lower_gas_kg < 0.0" in body
    assert "failure_code" in body
    assert "maxf(0.0, upper_gas_kg)" not in body
    assert "maxf(0.0, lower_gas_kg)" not in body


def test_legacy_divergence_remains_separate_from_closure():
    finalize = _function(SYSTEM, "finalize_step")
    assert '"phase3_shadow_canonical_transaction_closure_flag"' in finalize
    assert '"phase3_shadow_legacy_state_mass_divergence_kg"' in finalize
    assert '"phase3_shadow_legacy_state_energy_divergence_kj"' in finalize
    assert '"phase3_shadow_needs_flux_owner_flag"' in finalize


def test_shadow_csv_exposes_fields_only_in_shadow_block():
    shadow_header = LOG.split("if phase3_canonical_zone_shadow_enabled:", 1)[1]
    for field in FIELDS:
        assert field in shadow_header
        assert LOG.count(field) == 2


def test_no_new_authority_flag_was_added():
    assert "phase3_f31e" not in ENGINE.lower()
    assert "thermodynamic_closure_authority" not in ENGINE


def test_refunded_atomic_payload_header_and_row_remain_aligned():
    for field in (
        "phase3_shadow_parcel_atomic_refunded_energy_kj_total",
        "phase3_shadow_parcel_atomic_refunded_o2_kg_total",
    ):
        assert LOG.count(field) == 2
        assert field in SYSTEM
