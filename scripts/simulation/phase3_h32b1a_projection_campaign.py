"""H3.2b1a: read-only analyser for the passive projection causal campaign.

It reads run artefacts that already exist on disk and prints a report. It runs
nothing, writes nothing, imports no engine module, and never touches the repo.
Every number it prints is either read verbatim from the ledger export or is an
exact arithmetic combination of ledger totals. Where a quantity cannot be
computed from a boundary the ledger actually knows, this analyser declares the
coverage ABSENT rather than approximating it.

Expected layout, one directory per (case, variant):

    <root>/<case>__base/        no phase 3 flags
    <root>/<case>__causal/      --phase3-projection-causal-diagnostics only
    <root>/<case>__zone/        --phase3-zone-diagnostics only
    <root>/<case>__on/          both flags; this is the measurement run

Usage:
    python scripts/simulation/phase3_h32b1a_projection_campaign.py <root>
    python scripts/simulation/phase3_h32b1a_projection_campaign.py <root> --json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import statistics
import sys


# --------------------------------------------------------------------------
# Corpus. Committed case files only. Scratch definitions are never evidence.
# --------------------------------------------------------------------------

CORPUS = (
    "cfast_corridor_chain",
    "cfast_r0_window_360",
    "cfast_two_floor_stairwell",
    "two_storey_smoke",
    "ghanekar_bedroom_hallway",
    "piso_mediterraneo_smoke",
    "uk_bungalow_smoke",
    "compact_apartment_smoke",
    "three_bed_apartment_smoke",
    "flashover_simple_house",
)

CASE_DIR = "sim/validation/cases"

## The official duration for this corpus, fixed by H3.2a's runtime matrix.
OFFICIAL_DURATION_S = 120

VARIANTS = ("base", "causal", "zone", "on")

## Coverage this analyser cannot provide, declared instead of approximated.
ABSENT_FULL_HISTOGRAM = "calls_per_room_step_full_histogram"
ABSENT_PER_ROOM_DENOMINATOR = "per_room_room_step_denominator"
ABSENT_TRANSITIONS_OUTSIDE_PROJECTION = "zone_transitions_outside_a_projection_call"

## The zone-mass epsilon below which a zone is treated as absent. It is
## ZoneFireSolver's own constant, mirrored by the ledger, not a new tunable.
ZONE_MASS_EPS_KG = 1.0e-6


# --------------------------------------------------------------------------
# Reading
# --------------------------------------------------------------------------

def _sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_json(path: pathlib.Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _csv_shape(path: pathlib.Path) -> dict:
    ## `rows` counts data rows; `lines` counts them plus the header. Both are
    ## reported because the two conventions differ by one and mixing them
    ## silently turns an exact match into an off-by-one disagreement.
    if not path.exists():
        return {"exists": False, "rows": 0, "lines": 0, "columns": 0,
                "sha256": None, "header": []}
    with path.open(encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").rstrip("\r")
        rows = sum(1 for _ in handle)
    cols = header.split(",") if header else []
    return {
        "exists": True,
        "rows": rows,
        "lines": rows + (1 if header else 0),
        "columns": len(cols),
        "sha256": _sha256(path),
        "header": cols,
    }


def _variant_dir(root: pathlib.Path, case: str, variant: str) -> pathlib.Path:
    return root / ("%s__%s" % (case, variant))


# --------------------------------------------------------------------------
# Derived quantities. Exact combinations of ledger totals only.
# --------------------------------------------------------------------------

def churn_ratio(gross: float, net: float) -> dict:
    """Gross over net, with net == 0 reported explicitly rather than as inf.

    Gross is projection churn, not a physical contribution. A net of exactly
    zero means the rewrites cancelled completely; it does not mean the ratio is
    infinite or undefined, it means the ratio is not the right question.
    """
    if net == 0.0:
        return {"ratio": None, "status": "net_exactly_zero", "gross": gross}
    return {"ratio": gross / abs(net), "status": "defined", "gross": gross}


def multiplicity(ledger: dict) -> dict:
    totals = ledger.get("totals", {})
    rooms = ledger.get("by_room", {})
    room_steps = int(totals.get("room_steps_total", 0))
    calls = int(totals.get("projection_call_count_total", 0))
    per_room_max = sorted(
        int(r.get("projection_calls_per_room_step_max", 0)) for r in rooms.values()
    )
    multi = int(totals.get("room_steps_with_multiple_projection_calls_total", 0))
    return {
        # Exact.
        "timesteps_total": int(totals.get("timesteps_total", 0)),
        "room_steps_total": room_steps,
        "projection_call_count_total": calls,
        "mean_calls_per_room_step": (calls / room_steps) if room_steps else None,
        "max_calls_per_room_step": int(
            totals.get("projection_calls_per_room_step_max", 0)),
        "max_calls_per_timestep": int(
            totals.get("projection_calls_per_timestep_max", 0)),
        "room_steps_with_multiple_calls": multi,
        "fraction_room_steps_with_multiple_calls": (
            (multi / room_steps) if room_steps else None),
        "timesteps_with_multiple_calls": int(
            totals.get("timesteps_with_multiple_projection_calls_total", 0)),
        "timesteps_with_any_call": int(
            totals.get("timesteps_with_any_projection_call_total", 0)),
        # Exact across rooms: the distribution of each room's own maximum.
        "per_room_max_min": per_room_max[0] if per_room_max else None,
        "per_room_max_median": (
            statistics.median(per_room_max) if per_room_max else None),
        "per_room_max_max": per_room_max[-1] if per_room_max else None,
        "rooms": len(rooms),
        # Declared absent, never approximated.
        "absent_coverage": [ABSENT_FULL_HISTOGRAM, ABSENT_PER_ROOM_DENOMINATOR],
    }


def causes(ledger: dict) -> list:
    out = []
    for entry in ledger.get("by_cause", {}).values():
        mass_gross = float(entry.get("mass_gross_absolute_kg_total", 0.0))
        mass_net = float(entry.get("mass_signed_net_kg_total", 0.0))
        energy_gross = float(entry.get("energy_gross_absolute_kj_total", 0.0))
        energy_net = float(entry.get("energy_signed_net_kj_total", 0.0))
        out.append({
            "cause": entry.get("cause"),
            "call_count_total": int(entry.get("call_count_total", 0)),
            "mass_gross_absolute_kg_total": mass_gross,
            "mass_signed_net_kg_total": mass_net,
            "mass_churn": churn_ratio(mass_gross, mass_net),
            "energy_gross_absolute_kj_total": energy_gross,
            "energy_signed_net_kj_total": energy_net,
            "energy_churn": churn_ratio(energy_gross, energy_net),
        })
    out.sort(key=lambda d: -d["call_count_total"])
    return out


def cap_and_states(ledger: dict) -> dict:
    requested = accepted = rejected = 0.0
    binds = births = deaths = without_mass = nonfinite = 0
    upper_gross = upper_net = lower_gross = lower_net = 0.0
    for room in ledger.get("by_room", {}).values():
        requested += float(room.get("thermal_cap_requested_kj_total", 0.0))
        accepted += float(room.get("thermal_cap_accepted_kj_total", 0.0))
        rejected += float(room.get("thermal_cap_rejected_kj_total", 0.0))
        binds += int(room.get("thermal_cap_bind_count_total", 0))
        births += int(room.get("upper_zone_birth_count_total", 0))
        deaths += int(room.get("upper_zone_death_count_total", 0))
        without_mass += int(room.get("energy_without_mass_count_total", 0))
        nonfinite += int(room.get("nonfinite_state_count_total", 0))
        upper_gross += float(room.get("upper_mass_correction_gross_absolute_kg_total", 0.0))
        upper_net += float(room.get("upper_mass_correction_signed_net_kg_total", 0.0))
        lower_gross += float(room.get("lower_mass_correction_gross_absolute_kg_total", 0.0))
        lower_net += float(room.get("lower_mass_correction_signed_net_kg_total", 0.0))
    return {
        "thermal_cap_requested_kj_total": requested,
        "thermal_cap_accepted_kj_total": accepted,
        "thermal_cap_rejected_kj_total": rejected,
        "thermal_cap_bind_count_total": binds,
        "upper_mass_correction_gross_absolute_kg_total": upper_gross,
        "upper_mass_correction_signed_net_kg_total": upper_net,
        "lower_mass_correction_gross_absolute_kg_total": lower_gross,
        "lower_mass_correction_signed_net_kg_total": lower_net,
        "upper_zone_birth_count_total": births,
        "upper_zone_death_count_total": deaths,
        "energy_without_mass_count_total": without_mass,
        "nonfinite_state_count_total": nonfinite,
    }


def zone_regime_from_csv(path: pathlib.Path) -> dict:
    """One-zone versus two-zone regime, read from the logged state column.

    This is an INDEPENDENT observation, and it is needed because the ledger's
    birth and death counters only compare the `pre` and `post` of a single
    projection call. A transition produced between two calls, by any other
    subsystem, is invisible to them. This function instead classifies the logged
    `upper_gas_kg` state per room.

    It is INTERVAL-SAMPLED: the committed cases log every 10 s, so a transition
    that happens and reverses inside one interval is not seen. The transition
    count is therefore a LOWER BOUND and is labelled as one. No per-step delta
    column is read here and nothing is differenced against one -- only a state
    column is classified.
    """
    if not path.exists():
        return {"available": False, "reason": "csv_absent"}
    with path.open(encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").rstrip("\r").split(",")
        if "upper_gas_kg" not in header or "room_id" not in header:
            return {"available": False, "reason": "upper_gas_kg_column_absent"}
        i_room = header.index("room_id")
        i_upper = header.index("upper_gas_kg")
        last: dict = {}
        one_zone = two_zone = 0
        births = deaths = 0
        rooms_ever_one_zone: set = set()
        rooms_ever_two_zone: set = set()
        rooms: set = set()
        for line in handle:
            fields = line.rstrip("\n").rstrip("\r").split(",")
            if len(fields) <= max(i_room, i_upper):
                continue
            try:
                upper = float(fields[i_upper])
            except ValueError:
                continue
            room = fields[i_room]
            rooms.add(room)
            present = upper > ZONE_MASS_EPS_KG
            if present:
                two_zone += 1
                rooms_ever_two_zone.add(room)
            else:
                one_zone += 1
                rooms_ever_one_zone.add(room)
            if room in last and last[room] != present:
                if present:
                    births += 1
                else:
                    deaths += 1
            last[room] = present
    return {
        "available": True,
        "rooms": len(rooms),
        "sampled_rows_two_zone": two_zone,
        "sampled_rows_one_zone": one_zone,
        "rooms_ever_one_zone": len(rooms_ever_one_zone),
        "rooms_always_one_zone": len(rooms - rooms_ever_two_zone),
        "rooms_always_two_zone": len(rooms - rooms_ever_one_zone),
        "sampled_births_lower_bound": births,
        "sampled_deaths_lower_bound": deaths,
        "sampled_transitions_lower_bound": births + deaths,
        "sampling": "interval_sampled_lower_bound",
    }


def transition_instrumentation_check(ledger_states: dict, regime: dict) -> dict:
    """Compare the ledger's transition counters against the state column.

    The ledger counts a birth or death only when it happens BETWEEN the `pre`
    and `post` of one projection call. If the transition is produced by another
    subsystem, both snapshots already show the new regime and the counter never
    moves. This check makes that blindness measurable instead of assumed: the
    state column is a LOWER bound on real transitions, so a ledger count below
    it is a definite miss, never a rounding difference.
    """
    if not regime.get("available"):
        return {"comparable": False}
    ledger_births = int(ledger_states.get("upper_zone_birth_count_total", 0))
    ledger_deaths = int(ledger_states.get("upper_zone_death_count_total", 0))
    state_births = int(regime.get("sampled_births_lower_bound", 0))
    state_deaths = int(regime.get("sampled_deaths_lower_bound", 0))
    return {
        "comparable": True,
        "ledger_births": ledger_births,
        "ledger_deaths": ledger_deaths,
        "state_births_lower_bound": state_births,
        "state_deaths_lower_bound": state_deaths,
        "missed_births_at_least": max(0, state_births - ledger_births),
        "missed_deaths_at_least": max(0, state_deaths - ledger_deaths),
        "ledger_sees_transitions": (ledger_births + ledger_deaths) > 0,
    }


def residuals(ledger: dict) -> dict:
    totals = ledger.get("totals", {})
    return {
        # The ledger owns validity. This analyser reports its verdict; it never
        # relaxes it, and it never calls an invalid residual a physical one.
        "data_available": bool(ledger.get("data_available", False)),
        "unavailable_reason_codes": list(ledger.get("unavailable_reason_codes", [])),
        "static_instrumentation_gap_reason_codes": list(
            ledger.get("static_instrumentation_gap_reason_codes", [])),
        "observed_active_gap_reason_codes": list(
            ledger.get("observed_active_gap_reason_codes", [])),
        "observed_active_gap_counts": dict(
            ledger.get("observed_active_gap_counts", {})),
        "structural_coverage_complete": bool(
            ledger.get("structural_coverage_complete", False)),
        "residual_physical_valid": bool(ledger.get("residual_physical_valid", False)),
        "physical_residual_label": ledger.get("physical_residual_label"),
        "candidate_physical_residual_mass_kg_total": float(
            totals.get("candidate_physical_residual_mass_kg_total", 0.0)),
        "candidate_physical_residual_mass_gross_absolute_kg_total": float(
            totals.get("candidate_physical_residual_mass_gross_absolute_kg_total", 0.0)),
        "candidate_physical_residual_energy_kj_total": float(
            totals.get("candidate_physical_residual_energy_kj_total", 0.0)),
        "closure_inclusive_residual_mass_kg_total": float(
            totals.get("closure_inclusive_residual_mass_kg_total", 0.0)),
        "closure_inclusive_residual_energy_kj_total": float(
            totals.get("closure_inclusive_residual_energy_kj_total", 0.0)),
        "numerical_correction_mass_kg_total": float(
            totals.get("numerical_correction_mass_kg_total", 0.0)),
        "numerical_correction_energy_kj_total": float(
            totals.get("numerical_correction_energy_kj_total", 0.0)),
        "residual_relation_mass_error_kg": float(
            ledger.get("residual_relation_mass_error_kg", 0.0)),
        "residual_relation_energy_error_kj": float(
            ledger.get("residual_relation_energy_error_kj", 0.0)),
    }


# --------------------------------------------------------------------------
# Gates
# --------------------------------------------------------------------------

def gates(shapes: dict, summaries: dict) -> dict:
    """Every gate is a comparison between artefacts, never a tolerance."""
    base, causal = shapes.get("base"), shapes.get("causal")
    zone, on = shapes.get("zone"), shapes.get("on")
    result = {}

    result["off_byte_identical"] = (
        bool(base and causal and base["exists"] and causal["exists"]
             and base["sha256"] == causal["sha256"]))

    result["on_changes_no_legacy_column"] = (
        bool(zone and on and zone["exists"] and on["exists"]
             and zone["sha256"] == on["sha256"]))

    # The ON header must be the zone-diagnostics header exactly: the causal flag
    # adds no CSV column of its own.
    result["no_new_csv_column"] = bool(
        zone and on and zone["header"] == on["header"])

    # Legacy columns are the baseline header, and they must survive unchanged as
    # a prefix of the diagnostics header.
    if base and zone and base["exists"] and zone["exists"]:
        result["legacy_columns_preserved"] = (
            zone["header"][:len(base["header"])] == base["header"])
    else:
        result["legacy_columns_preserved"] = False

    zone_summary = summaries.get("zone")
    on_summary = summaries.get("on")
    if isinstance(zone_summary, dict) and isinstance(on_summary, dict):
        only_on = sorted(set(on_summary) - set(zone_summary))
        only_zone = sorted(set(zone_summary) - set(on_summary))
        changed = sorted(
            k for k in set(on_summary) & set(zone_summary)
            if on_summary[k] != zone_summary[k] and k != "output_dir")
        result["summary_delta_is_opt_in_block_only"] = (
            only_on == ["phase3_projection_causal"] and not only_zone and not changed)
        result["summary_only_on_keys"] = only_on
        result["summary_changed_keys"] = changed
    else:
        result["summary_delta_is_opt_in_block_only"] = False
        result["summary_only_on_keys"] = []
        result["summary_changed_keys"] = []

    result["rows_match_across_variants"] = len({
        s["rows"] for s in shapes.values() if s and s["exists"]
    }) == 1
    result["all_variants_present"] = all(
        shapes.get(v) and shapes[v]["exists"] for v in VARIANTS)
    return result


MANIFEST_SCHEMA = "simufire_run_scenario_manifest_v1"


def manifest_state(path: pathlib.Path) -> dict:
    """Manifest validity and whether the run actually reached its duration.

    A truncated run would still produce a CSV and a summary, and every total in
    this report is cumulative, so a short run reads as a small number rather
    than as a failure. The duration is therefore checked, not assumed.
    """
    if not path.exists():
        return {"present": False, "valid": False, "duration_reached": False}
    try:
        data = _read_json(path)
    except (ValueError, OSError):
        return {"present": True, "parses": False, "valid": False,
                "duration_reached": False}
    requested = data.get("duration_s")
    reached = data.get("sim_time_s")
    step = data.get("step_s")
    valid = (data.get("schema_version") == MANIFEST_SCHEMA
             and data.get("status") == "completed"
             and isinstance(requested, (int, float))
             and isinstance(reached, (int, float)))
    duration_reached = bool(
        valid and reached >= requested
        and (not isinstance(step, (int, float)) or reached - requested <= abs(step) * 2))
    return {
        "present": True,
        "parses": True,
        "valid": bool(valid),
        "status": data.get("status"),
        "schema_version": data.get("schema_version"),
        "duration_s": requested,
        "sim_time_s": reached,
        "step_s": step,
        "duration_reached": duration_reached,
        "matches_official_duration": requested == OFFICIAL_DURATION_S,
    }


# --------------------------------------------------------------------------
# Per-case analysis
# --------------------------------------------------------------------------

def analyse_case(root: pathlib.Path, case: str) -> dict:
    shapes, summaries = {}, {}
    for variant in VARIANTS:
        directory = _variant_dir(root, case, variant)
        shapes[variant] = _csv_shape(directory / "sim_log.csv")
        summary_path = directory / "summary.json"
        summaries[variant] = _read_json(summary_path) if summary_path.exists() else None

    on_summary = summaries.get("on") or {}
    ledger = on_summary.get("phase3_projection_causal")
    record = {
        "case": case,
        "official_duration_s": OFFICIAL_DURATION_S,
        "variants_present": sorted(v for v in VARIANTS if shapes[v]["exists"]),
        "csv": {v: {k: shapes[v][k]
                    for k in ("exists", "rows", "lines", "columns", "sha256")}
                for v in VARIANTS},
        "manifest": {v: manifest_state(_variant_dir(root, case, v) / "run_manifest.json")
                     for v in VARIANTS},
        "gates": gates(shapes, summaries),
    }
    record["gates"]["manifests_valid"] = all(
        record["manifest"][v].get("valid") for v in VARIANTS)
    record["gates"]["duration_reached"] = all(
        record["manifest"][v].get("duration_reached") for v in VARIANTS)
    record["gates"]["official_duration_used"] = all(
        record["manifest"][v].get("matches_official_duration") for v in VARIANTS)
    if ledger is None:
        record["ledger_present"] = False
        record["completeness"] = "LEDGER_ABSENT"
        return record

    record["ledger_present"] = True
    record["multiplicity"] = multiplicity(ledger)
    record["causes"] = causes(ledger)
    record["cap_and_states"] = cap_and_states(ledger)
    record["residuals"] = residuals(ledger)
    record["zone_regime"] = zone_regime_from_csv(
        _variant_dir(root, case, "on") / "sim_log.csv")
    record["transition_instrumentation"] = transition_instrumentation_check(
        record["cap_and_states"], record["zone_regime"])
    record["completeness"] = completeness_verdict(record)
    return record


def completeness_verdict(record: dict) -> str:
    """What this scenario actually establishes, in the ledger's own terms."""
    res = record["residuals"]
    if not res["data_available"]:
        return "UNAVAILABLE"
    if res["observed_active_gap_reason_codes"]:
        return "OBSERVABLY_CONTAMINATED"
    if not res["structural_coverage_complete"]:
        return "STRUCTURALLY_INCOMPLETE"
    if res["residual_physical_valid"]:
        return "VALID"
    return "INCOMPLETE"


def analyse(root: pathlib.Path) -> dict:
    cases = [analyse_case(root, case) for case in CORPUS]
    all_gates = {}
    for name in ("all_variants_present", "off_byte_identical",
                 "on_changes_no_legacy_column", "no_new_csv_column",
                 "legacy_columns_preserved", "summary_delta_is_opt_in_block_only",
                 "rows_match_across_variants", "manifests_valid",
                 "duration_reached", "official_duration_used"):
        all_gates[name] = {
            "pass": sum(1 for c in cases if c["gates"].get(name)),
            "of": len(cases),
            "failed_cases": [c["case"] for c in cases if not c["gates"].get(name)],
        }
    return {"corpus": list(CORPUS), "cases": cases, "gates": all_gates}


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

def _fmt(value, spec="%.3f"):
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return spec % value
    return str(value)


def render(report: dict) -> str:
    lines = []
    lines.append("H3.2b1a projection causal campaign -- read-only analysis")
    lines.append("corpus: %d committed cases, official duration %d s (H3.2a)"
                 % (len(report["corpus"]), OFFICIAL_DURATION_S))
    lines.append("")
    lines.append("GATES")
    for name, info in report["gates"].items():
        mark = "PASS" if info["pass"] == info["of"] else "FAIL"
        lines.append("  %-40s %2d/%2d  %s%s" % (
            name, info["pass"], info["of"], mark,
            ("  failed: " + ", ".join(info["failed_cases"])) if info["failed_cases"] else ""))
    lines.append("")
    lines.append("PER SCENARIO")
    header = ("%-28s %7s %8s %10s %6s %6s %8s %14s %14s %10s" % (
        "case", "steps", "roomSt", "calls", "mxRS", "mxTS", "causes",
        "candResid_kg", "closResid_kg", "relErr"))
    lines.append(header)
    for case in report["cases"]:
        if not case.get("ledger_present"):
            lines.append("%-28s  LEDGER ABSENT" % case["case"])
            continue
        m, r = case["multiplicity"], case["residuals"]
        lines.append("%-28s %7d %8d %10d %6d %6d %8d %14.4f %14.4f %10.2e" % (
            case["case"], m["timesteps_total"], m["room_steps_total"],
            m["projection_call_count_total"], m["max_calls_per_room_step"],
            m["max_calls_per_timestep"], len(case["causes"]),
            r["candidate_physical_residual_mass_kg_total"],
            r["closure_inclusive_residual_mass_kg_total"],
            r["residual_relation_mass_error_kg"]))
    lines.append("")
    lines.append("COMPLETENESS AND GAPS")
    for case in report["cases"]:
        if not case.get("ledger_present"):
            continue
        r = case["residuals"]
        lines.append("  %-28s %-24s valid=%s static=%d active=%d %s" % (
            case["case"], case["completeness"], r["residual_physical_valid"],
            len(r["static_instrumentation_gap_reason_codes"]),
            len(r["observed_active_gap_reason_codes"]),
            r["physical_residual_label"]))
    lines.append("")
    lines.append("CAP AND INVALID STATES")
    for case in report["cases"]:
        if not case.get("ledger_present"):
            continue
        c = case["cap_and_states"]
        lines.append("  %-28s binds=%d rejected_kj=%s upperGross=%s lowerGross=%s "
                     "births=%d deaths=%d ewm=%d nonfinite=%d" % (
            case["case"], c["thermal_cap_bind_count_total"],
            _fmt(c["thermal_cap_rejected_kj_total"]),
            _fmt(c["upper_mass_correction_gross_absolute_kg_total"]),
            _fmt(c["lower_mass_correction_gross_absolute_kg_total"]),
            c["upper_zone_birth_count_total"], c["upper_zone_death_count_total"],
            c["energy_without_mass_count_total"], c["nonfinite_state_count_total"]))
    lines.append("")
    lines.append("ZONE REGIME (independent, interval-sampled state column)")
    for case in report["cases"]:
        regime = case.get("zone_regime") or {}
        if not regime.get("available"):
            lines.append("  %-28s UNAVAILABLE (%s)"
                         % (case["case"], regime.get("reason", "unknown")))
            continue
        check = case.get("transition_instrumentation") or {}
        lines.append("  %-28s rooms=%d alwaysOneZone=%d alwaysTwoZone=%d "
                     "births>=%d deaths>=%d | ledger births=%d deaths=%d "
                     "MISSED>=%d" % (
            case["case"], regime["rooms"], regime["rooms_always_one_zone"],
            regime["rooms_always_two_zone"],
            regime["sampled_births_lower_bound"],
            regime["sampled_deaths_lower_bound"],
            check.get("ledger_births", 0), check.get("ledger_deaths", 0),
            check.get("missed_births_at_least", 0)
            + check.get("missed_deaths_at_least", 0)))
    lines.append("")
    lines.append("DECLARED ABSENT COVERAGE (not approximated)")
    lines.append("  %s: the ledger exports a maximum and a multi-call count per"
                 " room-step, not a full histogram." % ABSENT_FULL_HISTOGRAM)
    lines.append("  %s: per-room room-step denominators are not exported, so a"
                 " per-room mean is not computable exactly."
                 % ABSENT_PER_ROOM_DENOMINATOR)
    lines.append("  %s: the ledger's birth and death counters compare the pre and"
                 " post of one projection call, so a transition produced between"
                 " calls is invisible to them; the regime block above is the"
                 " independent check and is itself a lower bound."
                 % ABSENT_TRANSITIONS_OUTSIDE_PROJECTION)
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", help="directory holding <case>__<variant> run outputs")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of text")
    parser.add_argument("--case", help="restrict the report to one case")
    args = parser.parse_args(argv)

    root = pathlib.Path(args.root)
    if not root.is_dir():
        sys.stderr.write("not a directory: %s\n" % root)
        return 2
    report = analyse(root)
    if args.case:
        report["cases"] = [c for c in report["cases"] if c["case"] == args.case]
    if args.json:
        sys.stdout.write(json.dumps(report, indent=2, default=str))
        sys.stdout.write("\n")
    else:
        sys.stdout.write(render(report))
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
