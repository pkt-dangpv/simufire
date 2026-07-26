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


FLAG = "phase3_canonical_fixed_gross_pressure_skew_shadow_enabled"


def test_flag_is_opt_in_and_requires_opening_pressure_stack():
    assert f"@export var {FLAG}: bool = false" in ENGINE
    helper = ENGINE.split(
        "func _phase3_canonical_fixed_gross_pressure_skew_active() -> bool:", 1
    )[1].split("\n\n", 1)[0]
    for prerequisite in (
        "phase3_canonical_zone_shadow_enabled",
        "phase3_canonical_persistence_shadow_enabled",
        "phase3_canonical_interior_opening_shadow_enabled",
        "phase3_canonical_interior_pressure_shadow_enabled",
        FLAG,
    ):
        assert prerequisite in helper


def test_preview_is_recorded_before_authoritative_pressure_routes_are_appended():
    call = SYSTEM.index("preview_fixed_gross_interior_pressure_skew(")
    call = SYSTEM.index("preview_fixed_gross_interior_pressure_skew(", call + 1)
    record = SYSTEM.index(
        "_record_fixed_gross_interior_pressure_skew_preview(", call
    )
    apply_site = SYSTEM.index("network_routes.append(pressure_route)", record)
    assert call < record < apply_site


def test_preview_routes_never_enter_atomic_bundles():
    recorder = SYSTEM.split(
        "func _record_fixed_gross_interior_pressure_skew_preview(", 1
    )[1].split("\n\n## F3.2a:", 1)[0]
    assert "add_atomic_bundle" not in recorder
    assert "_transactions" not in recorder
    assert "_atomic_bundles" not in recorder


def test_step_and_cumulative_ledgers_have_explicit_reset_contracts():
    assert "_canonical_fixed_gross_pressure_skew_by_room.clear()" in SYSTEM
    assert (
        SYSTEM.count(
            "_canonical_fixed_gross_pressure_skew_cumulative_by_room.clear()"
        )
        >= 2
    )


def test_state_and_csv_wiring_are_opt_in():
    assert FLAG in STATE
    assert f"var {FLAG}: bool = false" in LOGGER
    assert (
        "configure_phase3_canonical_fixed_gross_pressure_skew_shadow"
        in ENGINE
    )
    assert (
        "configure_phase3_canonical_fixed_gross_pressure_skew_shadow"
        in LOGGER
    )
    assert "if phase3_canonical_fixed_gross_pressure_skew_shadow_enabled:" in LOGGER
    assert "--phase3-canonical-fixed-gross-pressure-skew-shadow" in RUNNER
    assert "phase3_canonical_fixed_gross_pressure_skew_shadow" in HEADLESS


def test_csv_telemetry_covers_step_cumulative_and_closure():
    fields = (
        "phase3_shadow_fixed_gross_preview_out_mass_kg_step",
        "phase3_shadow_fixed_gross_preview_in_mass_kg_step",
        "phase3_shadow_fixed_gross_pressure_requested_net_out_kg_step",
        "phase3_shadow_fixed_gross_pressure_accepted_net_out_kg_step",
        "phase3_shadow_fixed_gross_preview_net_enthalpy_out_kj_total",
        "phase3_shadow_fixed_gross_mass_residual_kg",
        "phase3_shadow_fixed_gross_energy_residual_kj",
        "phase3_shadow_fixed_gross_o2_residual_kg",
        "phase3_shadow_fixed_gross_species_residual_kg",
    )
    for field in fields:
        assert field in SYSTEM
        assert field in LOGGER
