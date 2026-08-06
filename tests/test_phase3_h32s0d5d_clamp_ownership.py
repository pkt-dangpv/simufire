"""Structural contracts for the H3.2-S0d5d species-clamp ownership diagnostic.

S0d5d makes the species clamps visible as `numerical_correction`: it measures
the mass each clamp rewrites, splits it by family and by application site, and
exports it behind the existing species-diagnostics flag. It changes no physics.
The clamps themselves are neither removed nor relaxed -- these contracts pin
that too, because the whole point of the phase is to keep the invariant and
stop it from being invisible.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
GAS = (ROOT / "sim/core/GasExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")


def _strip_comments(text: str) -> str:
    return "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )


def _func(text: str, name: str) -> str:
    body = text.split("func %s(" % name, 1)[1]
    return body.split("\nfunc ", 1)[0]


def test_no_new_flag_is_introduced():
    # S0d5d reuses the species diagnostics flag: the measurement lives exactly
    # where the other clamp measurements already live.
    assert "phase3_clamp_correction_diagnostics_enabled" not in GAS
    assert "phase3_clamp_correction_diagnostics_enabled" not in ENGINE
    assert "phase3_clamp_ownership_enabled" not in GAS
    # The full flag surface of the component, pinned so a later phase cannot
    # add one without a deliberate edit here.
    assert set(re.findall(r"phase3_\w+_enabled", GAS)) == {
        "phase3_canonical_zone_shadow_enabled",
        "phase3_co_first_violation_trace_enabled",
        "phase3_co_zonal_transport_consistency_enabled",
        "phase3_co2_zonal_transport_consistency_enabled",
        "phase3_physical_owner_ledger_enabled",
        "phase3_pressure_canonical_enabled",
        "phase3_pressure_component_equalization_enabled",
        "phase3_runtime_ownership_ledger_enabled",
        "phase3_species_attribution_diagnostics_enabled",
        "phase3_thermodynamic_pressure_enabled",
        "phase3_zone_diagnostics_enabled",
    }


def test_recording_is_gated_off_by_default():
    body = _func(GAS, "_record_clamp_correction")
    first = [line.strip() for line in body.splitlines() if line.strip()]
    # The gate must be the first executable statement of the recorder.
    gate = next(line for line in first if line.startswith("if "))
    assert gate == "if not phase3_species_attribution_diagnostics_enabled:"
    assert "return" in body.split(gate, 1)[1].splitlines()[1]
    # The engine only exports the block when the same flag is on: the export
    # sits inside the species-diagnostics branch, with no branch of its own.
    export = ENGINE.split('summary["phase3_clamp_corrections"]', 1)[0]
    guard = [
        line.strip()
        for line in export.splitlines()
        if line.strip().startswith("if phase3_")
    ][-1]
    assert guard == "if phase3_species_attribution_diagnostics_enabled:"


def test_three_clamp_families_are_named_and_distinct():
    kinds = re.findall(r'const CLAMP_KIND_\w+: String = "(\w+)"', GAS)
    assert sorted(kinds) == [
        "bulk_non_negative",
        "upper_le_bulk",
        "upper_non_negative",
    ]
    assert len(set(kinds)) == 3


def test_every_correction_is_classified_numerical_correction():
    entry = _func(GAS, "_clamp_correction_entry")
    assert (
        '"classification": Phase3PhysicalOwnerLedger.CLASS_NUMERICAL_CORRECTION,'
        in entry
    )
    # No other classification may appear in the clamp ledger: a clamp has no
    # donor, so it can never be a source or a transport.
    for forbidden in (
        "CLASS_LOCAL_SOURCE",
        "CLASS_EXTERIOR_BOUNDARY",
        "CLASS_INTERIOR_TRANSPORT",
        "CLASS_INTERZONE_REDISTRIBUTION",
        "CLASS_DELAYED_PARCEL",
    ):
        assert forbidden not in entry, forbidden


def test_both_application_sites_of_the_zonal_clamp_are_observed():
    # Family C is applied at exactly two sites. Until S0d5d only the room loop
    # was measured, and only as a count.
    assert GAS.count("room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)") == 1
    assert (
        GAS.count("target.co_upper_kg = clampf(target.co_upper_kg, 0.0, target.co_kg)")
        == 1
    )
    for species in ("co", "co2", "hcn"):
        assert (
            '"%s", target.%s_kg, target.%s_upper_kg, "parcel_delivery", target'
            % (species, species, species) in GAS
        ), species
        assert (
            '_record_zonal_guard("%s", room.%s_kg, room.%s_upper_kg, "room_loop", room)'
            % (species, species, species) in GAS
        ), species
    assert '"accumulator_application"' in GAS


def test_sample_detail_covers_every_required_field():
    # The audit asks for a per room/species/step record; these are the fields
    # that make a clamp reconstructable without re-running the simulation.
    body = GAS.split("func _record_clamp_correction(", 1)[1].split("\nfunc _append", 1)[0]
    for key in (
        '"step"',
        '"room_id"',
        '"species"',
        '"clamp_kind"',
        '"site"',
        '"strict_bound"',
        '"material_bound"',
        '"material_epsilon_kg"',
        '"writer_before_clamp"',
        '"flags"',
    ):
        assert key in body, key
    zonal = _func(GAS, "_record_zonal_clamp_correction")
    accumulator = _func(GAS, "_record_species_attribution")
    for key in (
        '"pre_bulk_kg"',
        '"pre_upper_kg"',
        '"requested_bulk_kg"',
        '"requested_upper_kg"',
        '"post_bulk_kg"',
        '"post_upper_kg"',
        '"correction_bulk_kg"',
        '"correction_upper_kg"',
        '"lower_derived_before_kg"',
        '"lower_derived_after_kg"',
        '"cause"',
    ):
        assert key in zonal, "zonal: %s" % key
        assert key in accumulator, "accumulator: %s" % key
    # The sample list must be bounded and must say what it dropped.
    assert "const CLAMP_SAMPLE_MAX: int = " in GAS
    assert "_phase3_clamp_sample_overflow += 1" in GAS


def test_unpaired_species_report_unknown_not_zero():
    paired = _func(GAS, "_paired_stock_kg")
    assert paired.count("return NAN") == 2
    writer = _func(GAS, "_last_writer_for")
    assert 'return "unknown"' in writer
    assert '_phase3_last_writer.get(key, "unknown")' in writer


def test_parcel_site_does_not_inflate_the_zonal_guard_counters():
    # The guard counters are the room-loop population reported by S0d5a2,
    # S0d5b and S0d5c. Adding a second site must not silently change them.
    correction = _func(GAS, "_record_zonal_clamp_correction")
    assert "zonal_guard" not in correction
    assert "_species_attribution_entry" not in correction
    guard = _func(GAS, "_record_zonal_guard")
    assert 'site: String = "room_loop"' in guard
    # The guard's own counters must not read the site: they are single-site.
    counter_lines = [
        line for line in guard.splitlines() if "zonal_guard_" in line
    ]
    assert counter_lines
    assert not any("site" in line for line in counter_lines)


def test_correction_is_measured_not_repaired():
    correction = _strip_comments(_func(GAS, "_record_zonal_clamp_correction"))
    # It computes what the clamp will do without writing it anywhere: the only
    # assignments are to a local, never to a room or a delta accumulator.
    assigned = set(re.findall(r"^\s*(?:var )?([\w.\[\]]+) *=[^=]", correction, re.M))
    assert assigned == {"corrected_kg"}, assigned
    recorder = _strip_comments(_func(GAS, "_record_clamp_correction"))
    for text in (correction, recorder):
        assert "_delta_kg[" not in text
        assert "target." not in text
    # The recorder may read `room.id` to label the observation, but must never
    # write to a room.
    assert not re.search(r"\broom\.\w+ *=[^=]", recorder)
    assert not re.search(r"\broom\.", correction)
    assert set(re.findall(r"\broom\.(\w+)", recorder)) == {"id"}


def test_strict_and_material_are_always_reported_together():
    recorder = _func(GAS, "_record_clamp_correction")
    assert '"strict_count"' in recorder
    assert '"material_count"' in recorder
    entry = _func(GAS, "_clamp_correction_entry")
    for key in (
        '"applications"',
        '"strict_count"',
        '"material_count"',
        '"corrected_mass_abs_kg"',
        '"corrected_mass_signed_kg"',
        '"max_correction_kg"',
        '"material_epsilon_kg"',
    ):
        assert key in entry, key


def test_material_threshold_is_never_inherited():
    entry = _func(GAS, "_clamp_correction_entry")
    assert '"material_epsilon_kg": _material_eps_for(species),' in entry
    recorder = _func(GAS, "_record_clamp_correction")
    assert "_material_eps_for(species)" in recorder
    # No literal threshold may be hard-coded inside the clamp ledger.
    assert not re.search(r"1\.0e-\d+", recorder)
    assert not re.search(r"1\.0e-\d+", entry)


def test_threshold_never_governs_physics():
    # The material epsilon may only appear in counters, never in a clamp bound
    # or in a transport expression.
    for line in GAS.splitlines():
        if "_material_eps_for(" not in line and "MATERIAL_EPS" not in line:
            continue
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("##"):
            continue
        if stripped.startswith("const ZONAL_GUARD_MATERIAL_EPS"):
            continue
        assert "clampf(" not in stripped, stripped
        assert "_delta_kg[" not in stripped, stripped


def test_summary_is_read_only_and_exported_opt_in():
    getter = _func(GAS, "get_phase3_clamp_correction_summary")
    assert 'summary["totals"] = _phase3_clamp_corrections.duplicate(true)' in getter
    assert 'summary["samples"] = _phase3_clamp_samples.duplicate(true)' in getter
    # With nothing observed the export stays completely empty, so an OFF run
    # adds no key at all to the technical summary.
    assert "return summary" in getter.split("is_empty()", 1)[1]
    reset = _func(GAS, "reset")
    for member in (
        "_phase3_clamp_corrections",
        "_phase3_clamp_samples",
        "_phase3_last_writer",
    ):
        assert "%s.clear()" % member in reset, member
    assert "_phase3_clamp_sample_overflow = 0" in reset
    assert "var _phase3_clamp_corrections: Dictionary = {}" in GAS
    assert "var _phase3_clamp_samples: Array[Dictionary] = []" in GAS
    assert 'summary["phase3_clamp_corrections"]' in ENGINE


def test_the_clamps_themselves_are_unchanged():
    # Removing or relaxing the invariant is explicitly out of scope.
    for line in (
        "room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)",
        "room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)",
        "room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)",
        "target.co_upper_kg = clampf(target.co_upper_kg, 0.0, target.co_kg)",
        "target.co2_upper_kg = clampf(target.co2_upper_kg, 0.0, target.co2_kg)",
        "target.hcn_upper_kg = clampf(target.hcn_upper_kg, 0.0, target.hcn_kg)",
    ):
        assert line in GAS, line
    # The bulk non-negative family stays a plain maxf on the accumulator.
    for species in ("smoke", "co", "co2", "hcn", "hcl", "acrolein", "formaldehyde"):
        assert "room.%s_kg = maxf(0.0, room.%s_kg" % (species, species) in GAS, species


def test_untouched_subsystems():
    hvac = (ROOT / "sim/core/HVACSystem.gd").read_text(encoding="utf-8")
    oes = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
    for text in (hvac, oes):
        assert "clamp_correction" not in text
        assert "CLAMP_KIND" not in text
    assert not (ROOT / "sim/core/Phase3PhysicalSourceIntegrator.gd").exists()
    solver = (ROOT / "sim/core/Phase3CoupledPressureSolver.gd").read_text(encoding="utf-8")
    assert "clamp_correction" not in solver


def test_no_new_csv_columns():
    for name in ("sim/core/SimulationLogWriter.gd", "sim/core/SimulationStateBuilder.gd"):
        text = (ROOT / name).read_text(encoding="utf-8")
        assert "clamp_correction" not in text
        assert "CLAMP_KIND" not in text
