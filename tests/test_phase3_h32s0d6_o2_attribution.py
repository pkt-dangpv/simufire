"""Structural contracts for the H3.2-S0d6 O2 acceptance measurement.

S0d6 is an audit with a passive instrument. It measures requested vs accepted O2
at the exact mutation site and refuses to emit kg unless that site capped and
applied against the same mass base. These contracts pin that refusal, because the
whole verdict of the phase rests on it: an attribution that silently invented a
mass base would look like success and be wrong.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
LEDGER = (ROOT / "sim/core/Phase3O2AcceptanceLedger.gd").read_text(encoding="utf-8")
OES = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
THERMAL = (ROOT / "sim/core/ThermalSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
WRITERS = OES + GAS + THERMAL + ENGINE


def _func(text: str, name: str) -> str:
    return text.split("func %s(" % name, 1)[1].split("\nfunc ", 1)[0]


def _strip_comments(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


# --------------------------------------------------------------------------
# Flag surface
# --------------------------------------------------------------------------

def test_flag_is_new_defaults_off_and_governs_every_ledger():
    # OxygenExchangeSystem had no diagnostics flag to reuse: its only phase3 flag
    # gates a physics shadow ledger, a different export.
    assert "var phase3_o2_attribution_diagnostics_enabled: bool = false" in OES
    assert "@export var phase3_o2_attribution_diagnostics_enabled: bool = false" in ENGINE
    assert "var phase3_canonical_zone_shadow_enabled: bool = false" in OES
    # One flag drives all four ledgers, and the experimental flag snapshot is set
    # once rather than rebuilt per call: `record` runs in hot per-room loops.
    configure = ENGINE.split("oxygen_exchange_system.configure({", 1)[0]
    for line in (
        "_phase3_o2_ledger,",
        "gas_exchange_system.phase3_o2_ledger,",
        "thermal_system.phase3_o2_ledger,",
        "_o2d6_ledger.enabled = phase3_o2_attribution_diagnostics_enabled",
        "_o2d6_ledger.flags = _o2d6_flags",
    ):
        assert line in configure, line
    assert "phase3_o2_ledger.flags = _phase3_o2_flag_state()" in OES


def test_flags_are_not_rebuilt_per_record_call():
    # A dictionary allocation per record call is not affordable: `record` runs
    # once per site, per room, per step. The ledger holds the snapshot instead.
    assert "var flags: Dictionary = {}" in LEDGER
    record = _func(LEDGER, "record")
    assert "flags.duplicate(" not in record
    assert '"flags": flags,' in record
    # No record call site may pass a freshly built flag dictionary as an
    # argument: that is the allocation this contract exists to prevent.
    for match in re.finditer(
        r"(?:_record_o2_acceptance|phase3_o2_ledger\.record)\((.*?)\n\t*\)",
        WRITERS, re.S,
    ):
        assert "_flag_state()" not in match.group(1), match.group(1)[:120]
    assert "_phase3_o2_flag_state()" not in _func(OES, "_record_o2_acceptance")


def test_recorder_is_gated_off_first():
    body = _func(LEDGER, "record")
    statements = [
        line.strip()
        for line in body.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    guard = next(line for line in statements if line.startswith("if "))
    assert guard == "if not enabled:"
    assert "var enabled: bool = false" in LEDGER


def test_export_is_opt_in_and_empty_when_off():
    summary = _func(LEDGER, "summary")
    assert "if _totals.is_empty() and _samples.is_empty():" in summary
    assert "return out" in summary.split("is_empty()", 1)[1]
    combined = _func(ENGINE, "_phase3_o2_attribution_combined")
    assert "if totals.is_empty() and samples.is_empty():" in combined
    assert "return {}" in combined
    export = ENGINE.split('summary["phase3_o2_attribution"]', 1)[0]
    guard = [
        line.strip() for line in export.splitlines() if line.strip().startswith("if phase3_")
    ][-1]
    assert guard == "if phase3_o2_attribution_diagnostics_enabled:"


# --------------------------------------------------------------------------
# Reason codes and completeness
# --------------------------------------------------------------------------

def test_reason_codes_are_declared_and_the_conflict_marker_is_internal():
    codes = re.findall(r'const REASON_\w+: String = "(\w+)"', LEDGER)
    assert sorted(codes) == [
        "aggregate_clamp_multi_owner",
        "complete",
        "no_zonal_invariant",
        # Fail-closed marker the ledger sets itself; never passed by a caller.
        "reason_code_conflict",
        "sink_truncated_unowned",
        "unit_not_mass_ambiguous_base",
    ]
    assert len(set(codes)) == 6
    for text, name in ((OES, "OES"), (GAS, "GAS"), (THERMAL, "THERMAL"), (ENGINE, "ENGINE")):
        assert "REASON_CONFLICT" not in text, name
    # The valid list a caller may use excludes the conflict marker.
    valid = LEDGER.split("const VALID_REASONS", 1)[1].split("]", 1)[0]
    assert "REASON_CONFLICT" not in valid


def test_kg_requires_completeness():
    body = _func(LEDGER, "record")
    assert (
        "var complete: bool = bool(entry[EntryField.KG_AVAILABLE]) "
        "and not is_nan(mass_base_kg)" in body
    )
    kg_line = next(
        line for line in body.splitlines()
        if "entry[EntryField.ACCEPTED_KG_TOTAL] =" in line
    )
    preceding = body.split(kg_line, 1)[0].rstrip().splitlines()[-1].strip()
    assert preceding == "if complete:"
    assert '"accepted_kg": (accepted_fraction - pre_fraction) * mass_base_kg if complete else null' in body
    assert '"mass_base_kg": mass_base_kg if complete else null' in body


def test_reason_conflict_is_fail_closed():
    entry = _func(LEDGER, "_entry")
    guard = "if String(entry[EntryField.REASON_CODE]) != reason:"
    assert guard in entry
    downgrade = entry.split(guard, 1)[1]
    for line in (
        "entry[EntryField.REASON_CODE] = REASON_CONFLICT",
        "entry[EntryField.COMPLETENESS] = false",
        "entry[EntryField.KG_AVAILABLE] = false",
        "entry[EntryField.ACCEPTED_KG_TOTAL] = 0.0",
    ):
        assert line in downgrade, line
    # An unknown reason code must never be treated as complete.
    assert "var known: bool = VALID_REASONS.has(reason)" in entry
    assert "entry[EntryField.COMPLETENESS] = known and reason == REASON_COMPLETE" in entry
    assert "entry[EntryField.KG_AVAILABLE] = known and reason == REASON_COMPLETE" in entry


def test_merge_is_conjunctive_on_completeness():
    merge = _func(LEDGER, "merge_totals_into")
    assert 'dst["reason_code"] = REASON_CONFLICT' in merge
    assert 'dst["completeness"] = bool(dst.get("completeness", false)) \\' in merge
    assert 'and bool(src.get("completeness", false))' in merge


def test_only_the_upper_combustion_sink_claims_completeness():
    # Exactly one call site in the whole engine may pass REASON_COMPLETE, and it
    # must hand over the zone mass it also capped against.
    calls = re.findall(r"REASON_COMPLETE, (\w+), \"(\w+)\"", WRITERS)
    assert calls == [("upper_air_mass", "upper_zone_air_mass")]


def test_incomplete_sites_pass_nan():
    for reason in (
        "REASON_AMBIGUOUS_MASS_BASE",
        "REASON_SINK_TRUNCATED",
        "REASON_NO_ZONAL_INVARIANT",
        "REASON_AGGREGATE_MULTI_OWNER",
    ):
        for match in re.finditer(reason + r",\s*\n?\s*(\w+),", WRITERS):
            assert match.group(1) == "NAN", (reason, match.group(1))


# --------------------------------------------------------------------------
# Threshold
# --------------------------------------------------------------------------

def test_material_threshold_is_derived_from_fed_and_is_a_fraction():
    assert "const MATERIAL_EPS_FRACTION: float = 1.0e-9" in LEDGER
    block = LEDGER.split("## Material threshold", 1)[1].split("const MATERIAL_EPS", 1)[0]
    for token in ("FED", "fed_hypoxia_b", "0.54", "1.85e-4", "fraction"):
        assert token in block, token
    # The anchor must match the engine's actual FED constant, so the derivation
    # cannot rot silently.
    assert "@export var fed_hypoxia_b: float = 0.54" in ENGINE
    assert "exp(fed_hypoxia_a - fed_hypoxia_b * o2_deficit)" in THERMAL
    # O2 state is a fraction: no kg-named threshold may exist, and none may be
    # borrowed from a species.
    assert "MATERIAL_EPS_KG" not in LEDGER
    assert "ZONAL_GUARD_MATERIAL_EPS" not in LEDGER


def test_threshold_never_governs_physics():
    for line in LEDGER.splitlines():
        if "MATERIAL_EPS_FRACTION" not in line:
            continue
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("const "):
            continue
        assert "clampf(" not in stripped, stripped
        assert "room." not in stripped, stripped


# --------------------------------------------------------------------------
# The instrument observes and nothing more
# --------------------------------------------------------------------------

def test_no_forbidden_reconstruction_in_the_ledger():
    body = _strip_comments(LEDGER)
    for forbidden in ("hrr_kw", "o2_consumption_kg_per_MJ",
                      "o2_net_transport", "o2_exterior_net"):
        assert forbidden not in body, forbidden
    record = _strip_comments(_func(LEDGER, "record")).lower()
    for forbidden in ("proportional", "fifo", "priority", "share", "split"):
        assert forbidden not in record, forbidden


def test_measurement_writes_no_o2_state():
    for name in ("record", "_entry", "summary", "merge_totals_into"):
        body = _strip_comments(_func(LEDGER, name))
        assert not re.search(r"\broom\.\w+ *=[^=]", body), name
    # The ledger may read room.id to label an observation, nothing else.
    assert set(re.findall(r"\broom\.(\w+)", _strip_comments(LEDGER))) == {"id"}


def test_sample_is_bounded_and_declares_overflow():
    assert "const SAMPLE_MAX: int = 256" in LEDGER
    assert "_overflow += 1" in LEDGER
    summary = _func(LEDGER, "summary")
    assert 'out["sample_overflow"]' in summary
    assert 'out["sample_limit"]' in summary
    combined = _func(ENGINE, "_phase3_o2_attribution_combined")
    assert 'overflow += ledger.sample_overflow()' in combined


def test_clear_resets_everything():
    body = _func(LEDGER, "clear")
    for line in ("_totals.clear()", "_samples.clear()",
                 "_overflow = 0", "_step = 0"):
        assert line in body, line
    assert "phase3_o2_ledger.clear()" in _func(OES, "reset")


def test_owner_and_zone_are_the_key():
    entry = _func(LEDGER, "_entry")
    assert 'var key: String = "%s|%s" % [owner, zone]' in entry
    assert "entry[EntryField.OWNER] = owner" in entry
    assert "entry[EntryField.ZONE] = zone" in entry
    exported = _func(LEDGER, "_entry_dictionary")
    for field in ('"owner"', '"zone"', '"reason_code"', '"completeness"',
                  '"kg_available"', '"applications"', '"strict_count"',
                  '"material_count"', '"conflict_count"',
                  '"requested_fraction_total"', '"accepted_fraction_total"',
                  '"unit"', '"rooms"'):
        assert field in exported, field


# --------------------------------------------------------------------------
# Coverage
# --------------------------------------------------------------------------

def test_every_o2_mutating_subsystem_has_a_ledger():
    for text, name in ((OES, "OES"), (GAS, "GAS"), (THERMAL, "THERMAL")):
        assert "var phase3_o2_ledger = Phase3O2AcceptanceLedger.new()" in text, name
    assert "var _phase3_o2_ledger = Phase3O2AcceptanceLedgerScript.new()" in ENGINE


def test_coverage_is_declared_and_never_claimed_complete():
    hvac = (ROOT / "sim/core/HVACSystem.gd").read_text(encoding="utf-8")
    assert "phase3_o2_ledger" not in hvac
    assert "REASON_" not in hvac
    # HVAC keeps its unowned O2 writes exactly as they were.
    assert "room.o2 = lerpf(room.o2, clampf(float(supply_mix.get(\"o2\"" in hvac
    # The export must declare what it does NOT cover, so no reader can mistake
    # the table for full coverage.
    assert '"uninstrumented_writers": [' in ENGINE
    block = ENGINE.split('"uninstrumented_writers": [', 1)[1].split("\n\t\t],", 1)[0]
    # All five HVAC writes, including the one the first pass missed.
    for site in ("HVACSystem.gd:213", "HVACSystem.gd:302", "HVACSystem.gd:306",
                 "HVACSystem.gd:308", "HVACSystem.gd:314"):
        assert site in block, site
    # The OES writes that are not clamps and stay out of scope, including the
    # second bulk-from-zones recomposition.
    for site in ("OxygenExchangeSystem.gd:666", "OxygenExchangeSystem.gd:1290",
                 "OxygenExchangeSystem.gd:1128", "OxygenExchangeSystem.gd:470"):
        assert site in block, site
    coverage = ENGINE.split('"writer_coverage": {', 1)[1].split("},", 1)[0]
    assert '"production_writes_found": 45' in coverage
    assert '"instrumented": 23' in coverage
    assert '"uninstrumented": 22' in coverage
    assert "adversarial per-writer verification incomplete" in coverage
    # The declared list must have exactly as many entries as the count claims,
    # so the two can never drift apart.
    assert len(re.findall(r'^\s*"[^"]+",\s*$', block, re.M)) == 22


def test_every_document_states_the_coverage_limit():
    # The instrument covers 16 sites found in one static pass. Every document
    # that reports the phase must say so, so a later reader cannot mistake the
    # measured tables for full coverage of O2 writes.
    for name in (
        "docs/validation/PHASE3_H32S0D6_O2_OWNERSHIP_AUDIT.md",
        "CHANGELOG.md",
        "docs/HANDOFF_CURRENT_STATE.md",
        "docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md",
    ):
        # Collapse whitespace: these are wrapped Markdown, so a required phrase
        # may straddle a line break.
        text = " ".join((ROOT / name).read_text(encoding="utf-8").lower().split())
        assert "s0d6" in text, name
        assert "one static pass" in text, name
        assert "not a complete inventory" in text, name
        # The counts must appear so the limit is quantified, not just asserted.
        assert "45" in text and "22" in text, name


def test_all_non_hvac_o2_write_sites_are_observed():
    owners = set(re.findall(
        r'(?:_record_o2_acceptance|phase3_o2_ledger\.record|_phase3_o2_ledger\.record)'
        r'\(\s*\n?\s*"([a-z0-9_]+)"',
        WRITERS,
    ))
    expected = {
        "oes_bulk_combustion_and_ach",
        "oes_combustion_upper_sink",
        "oes_combustion_lower_sink",
        "oes_combustion_plume_lower_sink",
        "oes_final_zone_clamp",
        "oes_exterior_opening",
        "oes_exterior_opening_lower_replenish",
        "ges_pressure_vent",
        "ges_room_loop_transport",
        "ges_parcel_delivery",
        "ges_ppv_inlet",
        "thermal_counterflow_return",
        "thermal_counterflow_donor",
        "thermal_zone_sync_blend",
        "thermal_canonical_doorway",
        "engine_final_tick_clamp",
    }
    assert expected <= owners, expected - owners


def test_the_s0d3_clamp_keeps_its_old_counter_and_gains_an_owner():
    # S0d3 counted this clamp 1798 times through one counter at a single call
    # site. That measurement stays; S0d6 adds owner and zone next to it.
    assert "_record_species_attribution_o2(" in GAS
    assert '"ges_room_loop_transport", "bulk", room' in GAS


def test_every_observed_site_still_clamps():
    for line in (
        "room.o2 = clampf(o2_mass_kg / air_mass_kg, 0.0, o2_nominal)",
        "room.o2_upper = clampf(room.o2_upper, 0.0, o2_nominal)",
        "room.o2_lower = clampf(room.o2_lower, 0.0, _o2_lower_final_ceil)",
        "room.o2_upper = upper_o2_after",
        "room.o2_lower = lower_o2_after",
        "room.o2_lower = plume_o2_after",
    ):
        assert line in OES, line
    assert "room.o2 = clampf(room.o2, 0.0, o2_nominal)" in ENGINE
    assert "room.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)" in GAS


def test_untouched_subsystems_and_no_csv_change():
    combustion = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
    assert "phase3_o2_ledger" not in combustion
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()
    solver = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")
    assert "phase3_o2_ledger" not in solver
    for name in ("sim/core/SimulationLogWriter.gd", "sim/core/SimulationStateBuilder.gd"):
        text = (ROOT / name).read_text(encoding="utf-8")
        assert "phase3_o2_attribution" not in text
        assert "phase3_o2_ledger" not in text
