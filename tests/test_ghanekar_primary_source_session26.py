"""Session 26 — documentary and contractual correction against the PRIMARY SOURCE.

STATIC TEXT / CONTRACT TESTS ONLY.
=================================

Scope boundary, stated explicitly because sessions 22-24 blurred it:

* These tests inspect **text and declared contract values** in the validator
  source, in two markdown documents, and in the *already-generated* aggregate
  report read as data. They assert what the repository CLAIMS.
* They do **not** run Godot, do **not** execute the engine, do **not** parse or
  recompute any physical metric, and do **not** open the per-case measurement
  reports to re-derive anything.
* Parser and runtime behaviour is covered elsewhere. Mixing the two here would
  let a text assertion masquerade as physical evidence — which is precisely the
  failure mode this audit exists to prevent.

The one exception is deliberate and narrow: the aggregate report is loaded as
JSON to assert that the frozen contract fields did **not** move. That is a
data-integrity assertion over a static artefact, not a runtime test.

What these tests pin
--------------------
Session 25 verified the article in-repo. Session 26 corrected the documentary
record against it. These tests prevent the corrected claims from regressing:

* the provenance retraction (the PDF *is* in the repository, and always was);
* the real definition of the initial response — an estimator, not a threshold —
  and the prohibition on inventing a vol% cut;
* the CO IDLH species misattribution (642 s is oxygen-driven, not CO);
* the FED observable mismatch (the paper's FED has no thermal term);
* the kitchen control-volume caveat that blocks using 894 s as a target;
* the article's own errata, recorded rather than silently "fixed".
"""

from pathlib import Path
import json
import re


ROOT = Path(__file__).resolve().parents[1]

VALIDATOR = (ROOT / "scripts/simulation/validate_reference_cases.py").read_text(
    encoding="utf-8")
INVENTORY = (ROOT / "docs/validation/GAPS_INVENTORY.md").read_text(encoding="utf-8")
EMPIRICAL = (ROOT / "sim/validation/EMPIRICAL_REFERENCE_GHANEKAR_2026.md").read_text(
    encoding="utf-8")
AGGREGATE = json.loads(
    (ROOT / "sim/validation/reports/reference_checks.json").read_text(encoding="utf-8"))

PDF_REL = "docs/literature/Evolution of combustion gas concentrations in full-scale residential fire.pdf"
PDF_SHA256 = "1B2A1B00EE4ADECEA86771694260AAF8233637E69679B794C8BA1A6B44675030"
PDF_BLOB = "d91a0b8b54e33111b582e7aa0f2f779a7767f752"
DOI = "10.1016/j.firesaf.2026.104724"

DEMOTED = (
    "ghanekar_far_hall_o2_response_time_s",
    "ghanekar_kitchen_far_hall_fed_0_3_s",
    "ghanekar_kitchen_far_hall_fed_1_0_s",
)

# Frozen contract values. Session 26 must not move any of them.
FROZEN = {
    "ghanekar_far_hall_o2_response_time_s":      (198.0, 30.0),
    "ghanekar_kitchen_far_hall_fed_0_3_s":       (546.0, 515.0),
    "ghanekar_kitchen_far_hall_fed_1_0_s":       (812.75, 126.0),
    "ghanekar_kitchen_far_hall_idlh_co_s":       (642.0, 102.0),
    "ghanekar_kitchen_fire_room_flashover_s":    (894.0, 30.0),
    "ghanekar_kitchen_far_hall_o2_response_s":   (402.0, 84.0),
    "ghanekar_flashover_0_9m_known_gap":         (186.0, 30.0),
    "ghanekar_far_hall_co_known_gap":            (204.0, 45.0),
}


def _check_block(name: str) -> str:
    """The Check(...) literal for one check, from the validator source.

    The last Check in a list has no following ``Check(`` to bound it, so fall
    back to the end of the enclosing list literal. Getting this wrong silently
    returns the rest of the file and makes every assertion vacuously pass, so
    the fallback is explicit rather than a bare slice to the end.
    """
    start = VALIDATOR.index('"%s",' % name)
    ends = [VALIDATOR.find("        Check(", start + 1),
            VALIDATOR.find("\n    ]", start + 1)]
    ends = [e for e in ends if e != -1]
    assert ends, "could not bound the Check block for %r" % name
    return VALIDATOR[start:min(ends)]


def _note(name: str) -> str:
    """Only the published note= text, excluding the source comments above it.

    A correction comment legitimately QUOTES the claim it retracts. That
    quotation must not be mistaken for the claim still being made.
    """
    return _check_block(name).split("note=", 1)[1]


def _aggregate_check(name: str) -> dict:
    for c in AGGREGATE["checks"]:
        if c["name"] == name:
            return c
    raise AssertionError("check %r absent from the aggregate" % name)


# --------------------------------------------------------------------------
# The frozen contract must not have moved (static data-integrity assertion)
# --------------------------------------------------------------------------

def test_no_frozen_contract_field_moved_in_the_aggregate():
    for name, (expected, tolerance) in FROZEN.items():
        c = _aggregate_check(name)
        assert c["expected"] == expected, (name, c["expected"], expected)
        assert c["tolerance"] == tolerance, (name, c["tolerance"], tolerance)


def test_the_three_demotions_are_still_non_gating_and_still_failing():
    for name in DEMOTED:
        c = _aggregate_check(name)
        assert c["required"] is False, name
        assert c["pass"] is False, name


def test_the_aggregate_counters_are_unchanged():
    assert AGGREGATE["required_count"] == 350
    assert AGGREGATE["failed_required_count"] == 6
    assert AGGREGATE["known_gap_count"] == 76
    assert len(AGGREGATE["checks"]) == 530


def test_no_expected_value_was_rebaselined_onto_runtime():
    """The frozen runtime figures must appear only as evidence, never as targets."""
    runtime_values = ("232.5", "405.75", "866.58", "495.3", "0.2368")
    for name in FROZEN:
        c = _aggregate_check(name)
        for v in runtime_values:
            assert str(c["expected"]) != v, (name, v)


# --------------------------------------------------------------------------
# 1. Provenance of the article
# --------------------------------------------------------------------------

def test_the_pdf_is_present_and_tracked_where_the_docs_say_it_is():
    assert (ROOT / PDF_REL).is_file(), "the primary source must be in the repository"


def test_the_empirical_reference_records_the_verified_provenance():
    for token in (PDF_BLOB, PDF_SHA256, DOI, "CC BY-NC-ND 4.0", "Version of Record"):
        assert token in EMPIRICAL, token
    assert "PROCEDENCIA VERIFICADA" in EMPIRICAL


def test_the_false_provenance_claims_are_retracted_not_silently_deleted():
    # The false claims must be gone as live assertions ...
    assert "NO esta en el repositorio" not in EMPIRICAL
    assert "todavia no ha sido contrastada" not in EMPIRICAL
    assert "no está en el\nrepositorio" not in INVENTORY
    # ... and the retraction must be on the record in both documents.
    assert "RETRACTACION" in EMPIRICAL
    assert "RETRACTADA" in INVENTORY
    assert "falsas" in INVENTORY


def test_the_historical_f_drive_path_survives_only_as_obsolete_provenance():
    assert "F:\\OneDrive" in EMPIRICAL, "the historical path must remain as a trail"
    assert "OBSOLETA" in EMPIRICAL
    assert "no es la fuente" in EMPIRICAL


# --------------------------------------------------------------------------
# 2. O2 and the definition of t-delta
# --------------------------------------------------------------------------

def test_the_o2_block_no_longer_claims_a_missing_detection_threshold():
    block = _check_block("ghanekar_far_hall_o2_response_time_s")
    assert "premise is FALSE" in block
    # It may quote the retracted claim only while retracting it.
    if "detection threshold" in _note("ghanekar_far_hall_o2_response_time_s"):
        assert "wrong" in _note("ghanekar_far_hall_o2_response_time_s")


def test_the_o2_block_documents_the_real_estimator():
    block = _check_block("ghanekar_far_hall_o2_response_time_s")
    for token in ("average background concentration", "LINEAR baseline",
                  "ITERATIVE POLYNOMIAL FIT", "LAST time index", "p.4 s2.3"):
        assert token in block, token


def test_the_o2_block_lists_what_the_article_never_published():
    block = _check_block("ghanekar_far_hall_o2_response_time_s")
    for token in ("polynomial degree", "convergence", "background averaging window"):
        assert token in block, token


def test_the_delay_is_stated_as_neither_corrected_nor_uncorrected():
    block = _check_block("ghanekar_far_hall_o2_response_time_s")
    assert "16-23 s" in block
    assert "NEITHER states" in block and "NOR that they were not" in block
    assert "END-TO-END" in block
    # The document must take the same line.
    assert "NO DECLARADO" in EMPIRICAL


def test_no_invented_o2_threshold_is_promoted_into_a_contract():
    block = _check_block("ghanekar_far_hall_o2_response_time_s")
    assert "must NOT substitute an" in block and "invented vol% threshold" in block
    assert "0.10-0.15 vol%" in block, "the session-22 coincidence must be named as such"
    assert "coincidence" in block
    # And the retained expected must still be the published central value.
    assert _aggregate_check("ghanekar_far_hall_o2_response_time_s")["expected"] == 198.0


# --------------------------------------------------------------------------
# 3. CO IDLH
# --------------------------------------------------------------------------

def test_the_co_idlh_species_attribution_is_corrected():
    block = _check_block("ghanekar_kitchen_far_hall_idlh_co_s")
    assert "LOW OXYGEN" in block
    assert "IT IS NOT" in block
    # The three places the article states the attribution.
    assert "p.1 Abstract" in block and "p.7 s3.4" in block and "p.8 s5" in block


def test_the_co_idlh_block_shows_the_derivation_and_the_runtime_agreement():
    block = _check_block("ghanekar_kitchen_far_hall_idlh_co_s")
    assert "16.8 - 2.2" in block
    assert "876" in block
    assert "866.58" in block
    assert "1.07 %" in block


def test_no_co_tolerance_is_invented():
    block = _check_block("ghanekar_kitchen_far_hall_idlh_co_s")
    assert "NO TOLERANCE IS DERIVABLE" in block
    assert "covariance is not" in block
    assert "PAIRED" in block
    # The historical contract survives untouched and clearly labelled.
    c = _aggregate_check("ghanekar_kitchen_far_hall_idlh_co_s")
    assert (c["expected"], c["tolerance"]) == (642.0, 102.0)
    assert c["required"] is False and c["pass"] is False
    assert "HISTORICAL DEFECTIVE CONTRACT" in _note("ghanekar_kitchen_far_hall_idlh_co_s")


def test_the_co_saturation_and_unit_erratum_are_recorded():
    block = _check_block("ghanekar_kitchen_far_hall_idlh_co_s")
    assert "SATURATED" in block
    assert "LOWER" in block and "BOUND" in block
    assert "0.12 vol%" in block


# --------------------------------------------------------------------------
# 4. FED
# --------------------------------------------------------------------------

def test_the_fed_block_records_the_asphyxiant_versus_thermal_mismatch():
    block = _check_block("ghanekar_kitchen_far_hall_fed_0_3_s")
    assert "PURSER" in block
    assert "NO thermal term" in block
    assert "fed_heat" in block
    # The exact decomposition from the frozen report.
    assert "0.2368004" in block
    assert "0.2152582" in block
    assert "9.10 %" in block


def test_the_fed_block_states_the_mismatch_makes_the_gap_worse():
    block = _check_block("ghanekar_kitchen_far_hall_fed_0_3_s")
    assert "FURTHER from 0.3" in block
    assert "not closer" in block


def test_the_fed_peak_is_not_claimed_comparable_to_the_published_fed():
    note = _note("ghanekar_kitchen_far_hall_fed_0_3_s")
    assert "OBSERVABLE MISMATCH" in note
    # Both FED checks stay visibly failing/non-gating with a final P1R5 disposition.
    for name in ("ghanekar_kitchen_far_hall_fed_0_3_s",
                 "ghanekar_kitchen_far_hall_fed_1_0_s"):
        c = _aggregate_check(name)
        assert c["required"] is False and c["pass"] is False
        assert c["disposition"] == "VERIFIED_MODEL_LIMITATION"
        assert "VERIFIED MODEL LIMITATION" in c["note"]


def test_the_fed_1_0_published_value_is_verified_not_rebaselined():
    block = _check_block("ghanekar_kitchen_far_hall_fed_1_0_s")
    assert "624" in block
    assert "10.4 +/- 2.1 min" in block
    assert "must NOT re-baseline" in block
    assert _aggregate_check("ghanekar_kitchen_far_hall_fed_1_0_s")["expected"] == 812.75


# --------------------------------------------------------------------------
# 5. Kitchen and flashover
# --------------------------------------------------------------------------

def test_the_flashover_block_records_the_control_volume_problem():
    block = _check_block("ghanekar_kitchen_fire_room_flashover_s")
    assert "CONTROL VOLUME" in block
    assert "fire_spread_enabled=false" in block
    assert "NOT COMPARABLE" in block
    assert "5.4x" in block


def test_the_flashover_block_records_the_criterion_and_clock_problems():
    block = _check_block("ghanekar_kitchen_fire_room_flashover_s")
    assert "temp_upper_c" in block and "T at 0.9 m" in block
    assert "EARLY BY CONSTRUCTION" in block
    assert "AUTO-IGNITION OF" in block


def test_894_is_not_to_be_used_as_a_calibration_target_yet():
    block = _check_block("ghanekar_kitchen_fire_room_flashover_s")
    assert "MUST NOT be used as a calibration target" in block
    assert "846" in block and "948" in block          # per-experiment range
    assert "NOT authorized" in block                  # kitchen redesign stays NO-GO


def test_the_missing_fire_size_observables_are_recorded():
    block = _check_block("ghanekar_kitchen_fire_room_flashover_s")
    assert "NO heat release rate" in block
    assert "NO calorimetry" in block
    assert "ACCELERATED" in block


def test_the_inventory_carries_the_same_kitchen_caveats():
    assert "Volumen de control" in INVENTORY
    assert "fire_spread_enabled=false" in INVENTORY
    assert "846" in INVENTORY and "948" in INVENTORY
    assert "no debe usarse como objetivo de calibraci" in INVENTORY


# --------------------------------------------------------------------------
# 6. The article's own errors, recorded rather than silently corrected
# --------------------------------------------------------------------------

def test_the_article_unit_errata_are_recorded_without_inferring_the_applied_rule():
    assert "Erratas e inconsistencias del propio articulo" in EMPIRICAL
    assert "4 vol%" in EMPIRICAL and "0.12 vol%" in EMPIRICAL
    # The document must refuse to guess which criterion was applied.
    assert "no se puede determinar" in EMPIRICAL


def test_the_ventilation_inconsistency_is_recorded():
    assert "0.69 m2" in EMPIRICAL and "0.27 m2" in EMPIRICAL
    assert "0.9 x 2.1 m" in EMPIRICAL
    assert "Al menos uno de los cuatro numeros impresos es incorrecto" in EMPIRICAL


def test_the_post_flashover_factor_discrepancy_is_recorded():
    assert "1.52" in EMPIRICAL
    assert "3.94" in EMPIRICAL


def test_the_uncertainty_semantics_are_recorded_as_k_equals_1():
    assert "k = 1" in EMPIRICAL
    assert "68 %" in EMPIRICAL
    assert "no una banda del 95 %" in EMPIRICAL or "no** una banda del 95 %" in EMPIRICAL


# --------------------------------------------------------------------------
# Citation hygiene
# --------------------------------------------------------------------------

def test_the_nonexistent_section_5_3_citation_is_corrected_everywhere():
    """The article has no section 5.3; section 5 has no subsections at all."""
    # The validator must no longer assert it as a live citation.
    kitchen_note = _note("ghanekar_kitchen_far_hall_o2_response_s")
    assert "p.5 Table 2" in kitchen_note
    assert "does not exist" in kitchen_note
    # And the aggregate must carry the corrected note.
    assert "does not exist" in _aggregate_check(
        "ghanekar_kitchen_far_hall_o2_response_s")["note"]
    # The inventory records the correction too.
    assert "no existe" in INVENTORY


def test_untraceable_tolerances_are_labelled_in_the_bedroom_checks():
    for name in ("ghanekar_flashover_0_9m_known_gap", "ghanekar_far_hall_co_known_gap"):
        block = _check_block(name)
        assert "not traceable" in block, name
        assert "+/- 18 s" in block, name


def test_the_stale_all_five_required_claim_is_corrected():
    """The docstring claimed all five kitchen checks were required=True.

    Asserted against the AGGREGATE note rather than the source, because the note
    is built from adjacent string literals and the sentence does not appear
    contiguously in the source text.
    """
    assert "That is NO LONGER the state" in VALIDATOR
    note = _aggregate_check("ghanekar_kitchen_fire_room_flashover_s")["note"]
    assert "remain required and pass" in note
    assert "false since session 23" in note
    # And the aggregate itself must agree: only o2_response is required.
    assert _aggregate_check("ghanekar_kitchen_far_hall_o2_response_s")["required"] is True
    for name in ("ghanekar_kitchen_far_hall_fed_0_3_s",
                 "ghanekar_kitchen_far_hall_fed_1_0_s",
                 "ghanekar_kitchen_far_hall_idlh_co_s",
                 "ghanekar_kitchen_fire_room_flashover_s"):
        assert _aggregate_check(name)["required"] is False, name
