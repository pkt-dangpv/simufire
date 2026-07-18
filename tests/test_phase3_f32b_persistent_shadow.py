"""Structural checks for F3.2b0 passive persistent canonical continuity."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SYSTEM = (ROOT / "sim/core/Phase3ZoneMassSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
STATE = (ROOT / "sim/core/SimulationStateBuilder.gd").read_text(encoding="utf-8")
LOG = (ROOT / "sim/core/SimulationLogWriter.gd").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts/run_scenario.py").read_text(encoding="utf-8")
HEADLESS = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")


FIELDS = (
    "phase3_shadow_persistent_step_index",
    "phase3_shadow_persistent_seeded_from_legacy_flag",
    "phase3_shadow_persistent_continuity_mass_residual_kg",
    "phase3_shadow_persistent_continuity_energy_residual_kj",
    "phase3_shadow_persistent_continuity_o2_residual_kg",
    "phase3_shadow_persistent_continuity_species_residual_kg",
    "phase3_shadow_persistent_pre_upper_o2_fraction",
    "phase3_shadow_persistent_pre_lower_o2_fraction",
    "phase3_shadow_persistent_post_upper_o2_fraction",
    "phase3_shadow_persistent_post_lower_o2_fraction",
    "phase3_shadow_persistent_combustion_o2_ref",
    "phase3_shadow_persistent_legacy_combustion_o2_ref",
    "phase3_shadow_persistent_combustion_o2_delta",
    "phase3_shadow_persistent_combustion_zone_code",
    "phase3_shadow_persistent_combustion_o2_requested_kg",
    "phase3_shadow_persistent_combustion_o2_accepted_kg",
    "phase3_shadow_persistent_combustion_o2_rejected_kg",
    "phase3_shadow_persistent_combustion_o2_accepted_fraction",
    "phase3_shadow_persistent_combustion_would_limit_flag",
    "phase3_shadow_persistent_zone_collapse_count",
    "phase3_shadow_persistent_zone_collapse_source_code",
    "phase3_shadow_persistent_zone_collapse_mass_residual_kg",
    "phase3_shadow_persistent_zone_collapse_energy_residual_kj",
    "phase3_shadow_persistent_zone_collapse_o2_residual_kg",
    "phase3_shadow_persistent_zone_collapse_species_residual_kg",
)


def _function(source: str, name: str) -> str:
    marker = f"func {name}"
    start = source.index(marker)
    next_func = source.find("\nfunc ", start + len(marker))
    return source[start:] if next_func < 0 else source[start:next_func]


def test_flag_is_default_off_and_has_no_authority_flag():
    assert "@export var phase3_canonical_persistence_shadow_enabled: bool = false" in ENGINE
    assert '"phase3_canonical_persistence_shadow_enabled"' in STATE
    assert "phase3_canonical_persistence_authority" not in ENGINE


def test_reset_clears_persistent_state_but_step_reset_does_not():
    reset = _function(SYSTEM, "reset")
    step_reset = _function(SYSTEM, "_reset_step_state")
    assert "_persistent_zone_state.clear()" in reset
    assert "_persistent_step_index = 0" in reset
    assert "_persistent_zone_state.clear()" not in step_reset


def test_begin_step_reuses_persistent_state_instead_of_legacy_snapshot():
    body = _function(SYSTEM, "begin_step")
    persistent = body.index("_persistent_zone_state.has(room_key)")
    reuse = body.index("_persistent_zone_state[room_key].duplicate(true)")
    legacy = body.index("_snapshot_room(room)")
    assert legacy < persistent < reuse
    assert "_snapshots[room_key] = persisted" in body


def test_finalize_commits_shadow_only_to_internal_persistent_state():
    body = _function(SYSTEM, "finalize_step")
    assert "_persistent_zone_state = shadow.duplicate(true)" in body
    assert not re.search(r"\broom\.\w+\s*[+\-*/]?=", body)


def test_probe_uses_combustion_selected_mode_without_changing_room():
    body = _function(SYSTEM, "record_combustion_o2_probe")
    assert "room.fire_o2_mode_used" in body
    assert "room.fire_o2_ref" in body
    assert "_canonical_o2_for_selected_mode(" in body
    assert '"upper", upper_o2, lower_o2, room' in body
    assert not re.search(r"\broom\.\w+\s*[+\-*/]?=", body)


def test_probe_runs_after_combustion_and_before_o2_collection_finishes():
    step = _function(ENGINE, "step")
    fire = step.index("_step_fire(dt)")
    probe = step.index("record_combustion_o2_probe(building)")
    species = step.index("_phase3_shadow_collect_species_requests(dt)")
    assert fire < probe < species


def test_continuity_tracks_mass_energy_o2_and_species():
    helper = _function(SYSTEM, "_state_delta_summary")
    for token in ("_state_mass", "_state_energy", "_state_o2", "_state_species"):
        assert token in helper


def test_persistent_shadow_replaces_legacy_o2_sinks_with_one_upper_demand():
    collector = _function(ENGINE, "_phase3_shadow_collect_oxygen_requests")
    assert 'cause.begins_with("combustion_o2_")' in collector
    assert 'cause: String = "combustion_o2_canonical_upper_sink"' in collector
    assert 'room.o2_consumed_fire_kg_step' in collector
    assert '"source_zone": "upper"' in collector


def test_degenerate_zone_collapse_is_conservative_and_shadow_only():
    body = _function(SYSTEM, "_collapse_degenerate_zones")
    assert "_state_delta_summary(state, before)" in body
    assert "_empty_species_inventory()" in body
    assert not re.search(r"\broom\.\w+\s*[+\-*/]?=", body)


def test_csv_fields_are_separately_gated_and_unique():
    assert "if phase3_canonical_persistence_shadow_enabled:" in LOG
    for field in FIELDS:
        assert LOG.count(field) == 2, field


def test_runner_flag_implies_parent_and_exterior_contracts():
    block = RUNNER.split("if args.phase3_canonical_persistence_shadow:", 1)[1]
    assert 'cmd.append("--phase3-canonical-shadow")' in block
    assert 'cmd.append("--phase3-canonical-exterior-shadow")' in block
    assert 'cmd.append("--phase3-canonical-persistence-shadow")' in block
    assert "engine.phase3_canonical_persistence_shadow_enabled = true" in HEADLESS


def test_default_shadow_begin_call_is_explicitly_gated():
    step = _function(ENGINE, "step")
    assert "building, phase3_canonical_persistence_shadow_enabled" in step


def test_persistence_does_not_write_roommodel_or_combustion_hrr():
    assert "room.hrr_kw =" not in _function(SYSTEM, "record_combustion_o2_probe")
    assert 'preload("res://sim/fire/CombustionSystem.gd")' not in SYSTEM
    assert "phase3_canonical_persistence_shadow_enabled" not in (
        ROOT / "sim/fire/CombustionSystem.gd"
    ).read_text(encoding="utf-8")


def test_direct_runtime_fixture_exists():
    fixture = ROOT / "tests/fixtures/phase3_f32b_persistent_shadow.gd"
    source = fixture.read_text(encoding="utf-8")
    assert "PHASE3_F32B_PERSISTENT_SHADOW_PASS" in source
    assert "system.begin_step(building, true)" in source
    assert "system.reset()" in source
