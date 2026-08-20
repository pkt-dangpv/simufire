"""Contracts for the H3.2b1a read-only projection campaign analyser.

The analyser is evidence tooling, so the contracts here are about what it is
allowed to claim, not only about what it computes:

* the corpus is the ten committed case files at the official H3.2a duration;
  scratch definitions are never binding evidence;
* it is strictly read-only -- it runs nothing and writes nothing;
* gross churn and signed net stay separate, and a net of exactly zero is
  reported as such rather than divided by;
* static instrumentation gaps and observed active gaps stay separate;
* validity belongs to the ledger: the analyser reports that verdict and can
  never upgrade an invalid residual into a physical one;
* coverage that cannot be computed from a known boundary is declared absent
  rather than approximated;
* it never differences a per-step column against an interval-sampled row, the
  error this programme has already made twice.
"""

from pathlib import Path
import json
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/simulation/phase3_h32b1a_projection_campaign.py"
SOURCE = MODULE_PATH.read_text(encoding="utf-8")

sys.path.insert(0, str(ROOT / "scripts/simulation"))
import phase3_h32b1a_projection_campaign as campaign  # noqa: E402


EXPECTED_CORPUS = (
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


# --------------------------------------------------------------------------
# Corpus provenance
# --------------------------------------------------------------------------

def test_corpus_is_exactly_the_ten_named_cases():
    assert campaign.CORPUS == EXPECTED_CORPUS


def test_every_corpus_case_file_exists_on_disk():
    for case in campaign.CORPUS:
        path = ROOT / campaign.CASE_DIR / ("%s.json" % case)
        assert path.exists(), case


def test_every_corpus_case_file_is_tracked_by_git_not_scratch():
    # Filesystem presence is not provenance. A committed case file is one git
    # has a blob for; a scratch file next to it would pass the check above.
    rels = ["%s/%s.json" % (campaign.CASE_DIR, case) for case in campaign.CORPUS]
    proc = subprocess.run(
        ["git", "ls-files", "--"] + rels,
        cwd=ROOT, capture_output=True, text=True,
    )
    if proc.returncode != 0:
        pytest.skip("git unavailable in this environment")
    tracked = {line.strip().replace("\\", "/") for line in proc.stdout.splitlines()}
    for rel in rels:
        assert rel in tracked, rel


def test_official_duration_is_the_h32a_value():
    assert campaign.OFFICIAL_DURATION_S == 120
    assert "H3.2a" in SOURCE


# --------------------------------------------------------------------------
# Read-only
# --------------------------------------------------------------------------

def test_analyser_never_writes():
    for forbidden in ('"w"', "'w'", '"a"', "'a'", "write_text", "write_bytes",
                      "os.remove", "shutil.", "mkdir", "unlink"):
        assert forbidden not in SOURCE, forbidden


def test_analyser_runs_nothing():
    for forbidden in ("subprocess", "os.system", "popen", "import godot"):
        assert forbidden not in SOURCE.lower(), forbidden


def test_analyser_imports_no_engine_module():
    assert "sim.core" not in SOURCE
    assert "SimulationEngine" not in SOURCE


# --------------------------------------------------------------------------
# Gross churn versus signed net
# --------------------------------------------------------------------------

def test_zero_net_is_reported_explicitly_not_divided_by():
    out = campaign.churn_ratio(12.0, 0.0)
    assert out["status"] == "net_exactly_zero"
    assert out["ratio"] is None
    assert out["gross"] == 12.0


def test_churn_ratio_uses_absolute_net_so_sign_never_flips_it():
    positive = campaign.churn_ratio(10.0, 2.0)
    negative = campaign.churn_ratio(10.0, -2.0)
    assert positive["ratio"] == negative["ratio"] == 5.0


def test_cause_rows_keep_gross_net_and_call_count_separate():
    ledger = {"by_cause": {"x": {
        "cause": "x", "call_count_total": 3,
        "mass_gross_absolute_kg_total": 9.0, "mass_signed_net_kg_total": 1.0,
        "energy_gross_absolute_kj_total": 4.0, "energy_signed_net_kj_total": -2.0,
    }}}
    row = campaign.causes(ledger)[0]
    assert row["call_count_total"] == 3
    assert row["mass_gross_absolute_kg_total"] == 9.0
    assert row["mass_signed_net_kg_total"] == 1.0
    assert row["mass_churn"]["ratio"] == 9.0
    assert row["energy_churn"]["ratio"] == 2.0


def test_gross_is_never_summed_into_a_net_field():
    # No line may add a gross_absolute term into a signed_net accumulator.
    for line in SOURCE.splitlines():
        if "signed_net" in line and "gross_absolute" in line:
            assert "+=" not in line, line


# --------------------------------------------------------------------------
# Static coverage versus observed activity
# --------------------------------------------------------------------------

def test_static_and_active_gaps_are_reported_separately():
    ledger = {
        "data_available": True,
        "static_instrumentation_gap_reason_codes": ["a", "b"],
        "observed_active_gap_reason_codes": ["b_observed_active"],
        "observed_active_gap_counts": {"b_observed_active": 7},
        "structural_coverage_complete": False,
        "residual_physical_valid": False,
        "physical_residual_label": "candidate_incomplete_physical_residual",
        "totals": {},
    }
    out = campaign.residuals(ledger)
    assert out["static_instrumentation_gap_reason_codes"] == ["a", "b"]
    assert out["observed_active_gap_reason_codes"] == ["b_observed_active"]
    assert out["observed_active_gap_counts"] == {"b_observed_active": 7}


def test_a_static_gap_alone_is_not_reported_as_contamination():
    record = {"residuals": {
        "data_available": True,
        "observed_active_gap_reason_codes": [],
        "structural_coverage_complete": False,
        "residual_physical_valid": False,
    }}
    assert campaign.completeness_verdict(record) == "STRUCTURALLY_INCOMPLETE"


def test_an_observed_active_gap_is_reported_as_contamination():
    record = {"residuals": {
        "data_available": True,
        "observed_active_gap_reason_codes": ["hvac_mass_energy_unowned_observed_active"],
        "structural_coverage_complete": False,
        "residual_physical_valid": False,
    }}
    assert campaign.completeness_verdict(record) == "OBSERVABLY_CONTAMINATED"


def test_absent_telemetry_is_never_reported_as_a_result():
    record = {"residuals": {
        "data_available": False,
        "observed_active_gap_reason_codes": [],
        "structural_coverage_complete": True,
        "residual_physical_valid": False,
    }}
    assert campaign.completeness_verdict(record) == "UNAVAILABLE"


# --------------------------------------------------------------------------
# Validity belongs to the ledger
# --------------------------------------------------------------------------

def test_validity_is_read_from_the_ledger_never_recomputed_permissively():
    ledger = {
        "data_available": True,
        "static_instrumentation_gap_reason_codes": [],
        "observed_active_gap_reason_codes": [],
        "observed_active_gap_counts": {},
        "structural_coverage_complete": True,
        "residual_physical_valid": False,   # ledger says no
        "physical_residual_label": "candidate_incomplete_physical_residual",
        "totals": {},
    }
    out = campaign.residuals(ledger)
    assert out["residual_physical_valid"] is False
    assert out["physical_residual_label"] == "candidate_incomplete_physical_residual"
    assert campaign.completeness_verdict({"residuals": out}) != "VALID"


def test_valid_is_only_reachable_when_the_ledger_says_valid():
    record = {"residuals": {
        "data_available": True,
        "observed_active_gap_reason_codes": [],
        "structural_coverage_complete": True,
        "residual_physical_valid": True,
    }}
    assert campaign.completeness_verdict(record) == "VALID"


def test_both_residuals_and_the_relation_error_are_all_reported():
    ledger = {"totals": {
        "candidate_physical_residual_mass_kg_total": 3.0,
        "closure_inclusive_residual_mass_kg_total": 1.0,
        "numerical_correction_mass_kg_total": 2.0,
    }, "residual_relation_mass_error_kg": 0.0}
    out = campaign.residuals(ledger)
    assert out["candidate_physical_residual_mass_kg_total"] == 3.0
    assert out["closure_inclusive_residual_mass_kg_total"] == 1.0
    assert out["numerical_correction_mass_kg_total"] == 2.0
    assert out["residual_relation_mass_error_kg"] == 0.0


# --------------------------------------------------------------------------
# Units and declared-absent coverage
# --------------------------------------------------------------------------

def test_multiplicity_reports_room_steps_and_timesteps_as_distinct_units():
    ledger = {
        "totals": {
            "timesteps_total": 10, "room_steps_total": 30,
            "projection_call_count_total": 90,
            "projection_calls_per_room_step_max": 7,
            "projection_calls_per_timestep_max": 15,
            "room_steps_with_multiple_projection_calls_total": 21,
            "timesteps_with_multiple_projection_calls_total": 10,
            "timesteps_with_any_projection_call_total": 10,
        },
        "by_room": {"0": {"projection_calls_per_room_step_max": 7},
                    "1": {"projection_calls_per_room_step_max": 3},
                    "2": {"projection_calls_per_room_step_max": 5}},
    }
    out = campaign.multiplicity(ledger)
    assert out["timesteps_total"] == 10
    assert out["room_steps_total"] == 30
    assert out["max_calls_per_room_step"] == 7
    assert out["max_calls_per_timestep"] == 15
    assert out["mean_calls_per_room_step"] == 3.0
    assert out["fraction_room_steps_with_multiple_calls"] == 0.7
    assert out["per_room_max_median"] == 5


def test_absent_coverage_is_declared_not_approximated():
    out = campaign.multiplicity({"totals": {}, "by_room": {}})
    assert campaign.ABSENT_FULL_HISTOGRAM in out["absent_coverage"]
    assert campaign.ABSENT_PER_ROOM_DENOMINATOR in out["absent_coverage"]
    # And the report says so in plain words.
    assert "DECLARED ABSENT COVERAGE" in SOURCE
    assert "not approximated" in SOURCE


def test_zone_regime_is_labelled_as_an_interval_sampled_lower_bound(tmp_path):
    csv = tmp_path / "sim_log.csv"
    csv.write_text(
        "time_s,room_id,upper_gas_kg\n"
        "0,0,0.0\n"        # one zone
        "10,0,5.0\n"       # transition up
        "20,0,0.0\n"       # transition down
        "0,1,7.0\n"
        "10,1,7.0\n",
        encoding="utf-8",
    )
    out = campaign.zone_regime_from_csv(csv)
    assert out["available"] is True
    assert out["sampled_rows_one_zone"] == 2
    assert out["sampled_rows_two_zone"] == 3
    assert out["sampled_births_lower_bound"] == 1
    assert out["sampled_deaths_lower_bound"] == 1
    assert out["sampled_transitions_lower_bound"] == 2
    assert out["rooms_ever_one_zone"] == 1
    assert out["rooms_always_two_zone"] == 1
    assert out["rooms_always_one_zone"] == 0
    assert out["sampling"] == "interval_sampled_lower_bound"


def test_a_ledger_transition_count_below_the_state_column_is_a_definite_miss():
    # The state column is itself a lower bound, so a ledger count below it
    # cannot be explained away as sampling.
    regime = {"available": True, "sampled_births_lower_bound": 29,
              "sampled_deaths_lower_bound": 0}
    check = campaign.transition_instrumentation_check(
        {"upper_zone_birth_count_total": 0, "upper_zone_death_count_total": 0},
        regime)
    assert check["comparable"] is True
    assert check["missed_births_at_least"] == 29
    assert check["ledger_sees_transitions"] is False


def test_a_ledger_count_above_the_sampled_bound_is_not_reported_as_negative():
    # The ledger sees every step, so exceeding the sampled bound is expected and
    # must never be rendered as a negative miss.
    check = campaign.transition_instrumentation_check(
        {"upper_zone_birth_count_total": 40, "upper_zone_death_count_total": 3},
        {"available": True, "sampled_births_lower_bound": 29,
         "sampled_deaths_lower_bound": 0})
    assert check["missed_births_at_least"] == 0
    assert check["missed_deaths_at_least"] == 0
    assert check["ledger_sees_transitions"] is True


def test_transition_check_is_skipped_rather_than_faked_without_data():
    assert campaign.transition_instrumentation_check(
        {}, {"available": False})["comparable"] is False


def test_zone_regime_uses_the_solver_epsilon_not_a_new_tunable():
    assert campaign.ZONE_MASS_EPS_KG == 1.0e-6
    assert "ZoneFireSolver" in SOURCE


def test_zone_regime_reports_absence_instead_of_zero(tmp_path):
    missing = campaign.zone_regime_from_csv(tmp_path / "nope.csv")
    assert missing["available"] is False
    assert missing["reason"] == "csv_absent"
    csv = tmp_path / "sim_log.csv"
    csv.write_text("time_s,room_id\n0,0\n", encoding="utf-8")
    no_column = campaign.zone_regime_from_csv(csv)
    assert no_column["available"] is False
    assert no_column["reason"] == "upper_gas_kg_column_absent"


def test_transitions_outside_a_projection_call_are_declared_absent():
    assert campaign.ABSENT_TRANSITIONS_OUTSIDE_PROJECTION in SOURCE
    assert "invisible to them" in SOURCE


def test_no_per_step_column_is_differenced_against_an_interval_row():
    # The committed cases log every 10 s while *_step columns cover one sub-step.
    # The analyser must never read those columns at all.
    assert "_kg_step" not in SOURCE
    assert "_kj_step" not in SOURCE
    assert "diff(" not in SOURCE


# --------------------------------------------------------------------------
# Gates
# --------------------------------------------------------------------------

def _shape(sha, rows=5, header=("a", "b")):
    return {"exists": True, "rows": rows, "columns": len(header),
            "sha256": sha, "header": list(header)}


def test_off_byte_identity_gate_needs_equal_hashes():
    same = campaign.gates(
        {"base": _shape("x"), "causal": _shape("x"),
         "zone": _shape("y"), "on": _shape("y")}, {})
    assert same["off_byte_identical"] is True
    differing = campaign.gates(
        {"base": _shape("x"), "causal": _shape("z"),
         "zone": _shape("y"), "on": _shape("y")}, {})
    assert differing["off_byte_identical"] is False


def test_on_must_not_change_a_legacy_column():
    changed = campaign.gates(
        {"base": _shape("x"), "causal": _shape("x"),
         "zone": _shape("y"), "on": _shape("w")}, {})
    assert changed["on_changes_no_legacy_column"] is False


def test_legacy_columns_must_survive_as_a_prefix():
    ok = campaign.gates({
        "base": _shape("x", header=("a", "b")),
        "causal": _shape("x", header=("a", "b")),
        "zone": _shape("y", header=("a", "b", "extra")),
        "on": _shape("y", header=("a", "b", "extra")),
    }, {})
    assert ok["legacy_columns_preserved"] is True
    reordered = campaign.gates({
        "base": _shape("x", header=("a", "b")),
        "causal": _shape("x", header=("a", "b")),
        "zone": _shape("y", header=("b", "a", "extra")),
        "on": _shape("y", header=("b", "a", "extra")),
    }, {})
    assert reordered["legacy_columns_preserved"] is False


def test_summary_delta_must_be_the_opt_in_block_only():
    zone = {"a": 1, "output_dir": "one"}
    on = {"a": 1, "output_dir": "two", "phase3_projection_causal": {}}
    good = campaign.gates({}, {"zone": zone, "on": on})
    assert good["summary_delta_is_opt_in_block_only"] is True
    on_changed = {"a": 2, "output_dir": "two", "phase3_projection_causal": {}}
    bad = campaign.gates({}, {"zone": zone, "on": on_changed})
    assert bad["summary_delta_is_opt_in_block_only"] is False
    assert bad["summary_changed_keys"] == ["a"]


def test_manifest_must_be_valid_and_the_duration_actually_reached(tmp_path):
    good = tmp_path / "good.json"
    good.write_text(json.dumps({
        "schema_version": campaign.MANIFEST_SCHEMA, "status": "completed",
        "duration_s": 120.0, "sim_time_s": 120.0833, "step_s": 0.08333,
    }), encoding="utf-8")
    state = campaign.manifest_state(good)
    assert state["valid"] is True
    assert state["duration_reached"] is True
    assert state["matches_official_duration"] is True


def test_a_truncated_run_is_caught_rather_than_read_as_a_small_number(tmp_path):
    # Every total here is cumulative, so a short run looks like a small result
    # instead of a failure unless the duration is checked.
    short = tmp_path / "short.json"
    short.write_text(json.dumps({
        "schema_version": campaign.MANIFEST_SCHEMA, "status": "completed",
        "duration_s": 120.0, "sim_time_s": 41.5, "step_s": 0.08333,
    }), encoding="utf-8")
    assert campaign.manifest_state(short)["duration_reached"] is False

    aborted = tmp_path / "aborted.json"
    aborted.write_text(json.dumps({
        "schema_version": campaign.MANIFEST_SCHEMA, "status": "timeout",
        "duration_s": 120.0, "sim_time_s": 120.5, "step_s": 0.08333,
    }), encoding="utf-8")
    assert campaign.manifest_state(aborted)["valid"] is False

    missing = campaign.manifest_state(tmp_path / "nope.json")
    assert missing["present"] is False
    assert missing["valid"] is False
    assert missing["duration_reached"] is False


def test_missing_ledger_is_reported_not_silently_zeroed(tmp_path):
    for variant in campaign.VARIANTS:
        directory = tmp_path / ("cfast_corridor_chain__%s" % variant)
        directory.mkdir()
        (directory / "sim_log.csv").write_text("a,b\n1,2\n", encoding="utf-8")
    (tmp_path / "cfast_corridor_chain__on" / "summary.json").write_text(
        json.dumps({"a": 1}), encoding="utf-8")
    record = campaign.analyse_case(tmp_path, "cfast_corridor_chain")
    assert record["ledger_present"] is False
    assert record["completeness"] == "LEDGER_ABSENT"
    assert "multiplicity" not in record
