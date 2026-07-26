from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
COMBUSTION = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
FIXTURE = (
    ROOT / "tests/fixtures/phase3_f33v1_fire_proposal.gd"
).read_text(encoding="utf-8")


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_wired_to_state_and_csv():
    flag = "phase3_canonical_fire_proposal_shadow_enabled"
    assert f"@export var {flag}: bool = false" in ENGINE
    assert f'"{flag}"' in STATE
    assert "configure_phase3_canonical_fire_proposal_shadow" in ENGINE
    assert "phase3_canonical_fire_proposal_shadow_enabled: bool = false" in LOG
    direct_flag = "phase3_canonical_unfiltered_fire_growth_shadow_enabled"
    assert f"@export var {direct_flag}: bool = false" in ENGINE
    assert f'"{direct_flag}"' in STATE


def test_runner_exposes_opt_in_flag_with_required_parents():
    cli_flag = "--phase3-canonical-fire-proposal-shadow"
    assert cli_flag in RUNNER
    assert cli_flag in HEADLESS
    block = RUNNER[RUNNER.index("if args.phase3_canonical_fire_proposal_shadow") :]
    assert "--phase3-canonical-combustion-shadow" in block
    assert "--phase3-canonical-unfiltered-fire-growth-shadow" in RUNNER
    assert "--phase3-canonical-unfiltered-fire-growth-shadow" in HEADLESS


def test_solver_is_dictionary_only_and_does_not_touch_room_model():
    proposal = _function(
        COMBUSTION, "evaluate_phase3_canonical_fire_proposal"
    )
    assert "room: RoomModel" not in proposal
    assert "room." not in proposal
    assert "legacy_hrr" not in proposal
    assert "legacy_target" not in proposal
    assert "proposal_age_s += dt" in proposal
    assert "o2_inventory_cap_kw" in proposal
    assert "kawagoe_limit_kw" in proposal
    assert "fuel_cap_kw" in proposal


def test_proposal_bootstrap_does_not_seed_from_post_throttle_legacy_state():
    snapshot = _function(COMBUSTION, "_snapshot_phase3_fire_state")
    assert '"proposal_age_s": 0.0' in snapshot
    assert '"proposal_hrr_kw": 0.0' in snapshot
    assert '"proposal_target_kw": 0.0' in snapshot
    assert (
        '"proposal_remaining_fuel_MJ": maxf(0.0, fire.fuel_energy_MJ)'
        in snapshot
    )
    proposal = _function(
        COMBUSTION, "evaluate_phase3_canonical_fire_proposal"
    )
    assert 'state_before.get("fire_time_s"' not in proposal
    assert 'state_before.get("hrr_kw"' not in proposal
    assert 'state_before.get("remaining_fuel_MJ"' not in proposal


def test_existing_combustion_transaction_remains_the_runtime_shadow_source():
    evaluate = _function(
        COMBUSTION, "evaluate_phase3_canonical_combustion_step"
    )
    assert "var legacy_hrr_kw: float = maxf(0.0, room.hrr_kw)" in evaluate
    assert "var accepted_hrr_kw: float = legacy_hrr_kw * accepted_fraction" in evaluate
    assert "canonical_fire_proposal_accepted_hrr_kw" not in evaluate
    assert '"persistent_updates"' in evaluate


def test_candidate_state_is_persisted_without_replacing_legacy_state():
    interpolate = _function(SYSTEM, "_interpolate_combustion_state")
    for field in [
        "proposal_age_s",
        "proposal_hrr_kw",
        "proposal_target_kw",
        "proposal_remaining_fuel_MJ",
    ]:
        assert f'"{field}"' in interpolate
    assert '"remaining_fuel_MJ"' in interpolate


def test_telemetry_is_schema_gated_by_the_new_flag():
    header = _function(LOG, "_build_csv_header")
    assert "if phase3_canonical_fire_proposal_shadow_enabled:" in header
    fields = _function(LOG, "_phase3_fire_proposal_fields")
    for field in [
        "phase3_shadow_fire_proposal_supported_flag",
        "phase3_shadow_fire_proposal_unsupported_reason_mask",
        "phase3_shadow_fire_proposal_hrr_kw",
        "phase3_shadow_fire_proposal_unfiltered_growth_flag",
        "phase3_shadow_fire_proposal_accepted_hrr_kw",
        "phase3_shadow_fire_proposal_zero_o2_flame_flag",
    ]:
        assert field in fields


def test_runtime_fixture_covers_proposal_limits_and_unsupported_scope():
    assert "PHASE3_F33V1_FIRE_PROPOSAL_PASS" in FIXTURE
    assert "_test_nominal_and_moderate_o2_keep_the_same_proposal" in FIXTURE
    assert "_test_zero_o2_rejects_without_advancing_age" in FIXTURE
    assert "_test_inventory_and_ventilation_caps_are_explicit" in FIXTURE
    assert "_test_intraroom_capability_without_active_spread_is_supported" in FIXTURE
    assert "_test_unsupported_mode_is_not_silently_accepted" in FIXTURE
