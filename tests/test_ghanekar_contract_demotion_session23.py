"""Session 23 — Ghanekar provisional contract demotion.

STATIC CONTRACT TESTS ONLY.

These tests inspect **text and declared contract values**. They do not parse the
runtime, do not run Godot, do not open per-case measurement reports and do not
recompute any metric. Parser/runtime behaviour is covered elsewhere; mixing the
two here would make a text assertion look like physical evidence.

What they pin:

* the three Ghanekar checks are demoted to non-gating, and stay demoted;
* their historical ``expected``/``tolerance`` are preserved byte-for-byte, so the
  demotion cannot be used to smuggle in a re-baseline;
* the original demotion reason remains recorded and P1R5 gives it a final disposition;
* the two materially false documentation claims stay corrected;
* nothing re-baselines an expected value onto runtime output.
"""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = (ROOT / "scripts/simulation/validate_reference_cases.py").read_text(
    encoding="utf-8")
INVENTORY = (ROOT / "docs/validation/GAPS_INVENTORY.md").read_text(encoding="utf-8")
EMPIRICAL = (ROOT / "sim/validation/EMPIRICAL_REFERENCE_GHANEKAR_2026.md").read_text(
    encoding="utf-8")

DEMOTED = (
    "ghanekar_far_hall_o2_response_time_s",
    "ghanekar_kitchen_far_hall_fed_0_3_s",
    "ghanekar_kitchen_far_hall_fed_1_0_s",
)

# The historical contract values, which this session must NOT change.
FROZEN_CONTRACT = {
    "ghanekar_far_hall_o2_response_time_s": ("expected=198.0", "tolerance=30.0"),
    "ghanekar_kitchen_far_hall_fed_0_3_s": ("expected=546.0", "tolerance=515.0"),
    "ghanekar_kitchen_far_hall_fed_1_0_s": ("expected=812.75", "tolerance=126.0"),
}


def _check_block(name: str) -> str:
    """The Check(...) literal for one check, from the validator source."""
    start = VALIDATOR.index('"%s",' % name)
    return VALIDATOR[start:VALIDATOR.index("        Check(", start + 1)]


def _note_string(name: str) -> str:
    """Only the published note= text, with source comments excluded.

    A correction comment legitimately QUOTES the false claim it replaces. That
    quotation must not be mistaken for the claim still being made, so assertions
    about what the report publishes are scoped to the note itself.
    """
    block = _check_block(name)
    return block.split("note=", 1)[1]


# --------------------------------------------------------------------------
# The demotion itself
# --------------------------------------------------------------------------

def test_all_three_are_declared_non_gating():
    for name in DEMOTED:
        assert "required=False" in _check_block(name), name


def test_none_of_the_three_is_still_required():
    for name in DEMOTED:
        assert "required=True" not in _check_block(name), name


def test_historical_expected_and_tolerance_are_preserved_exactly():
    # The whole point of a demotion is that it does NOT touch the numbers.
    for name, (expected, tolerance) in FROZEN_CONTRACT.items():
        block = _check_block(name)
        assert expected in block, (name, expected)
        assert tolerance in block, (name, tolerance)


def test_the_demotion_has_a_final_disposition_with_its_original_reason():
    for name in DEMOTED:
        block = _check_block(name)
        assert "VERIFIED MODEL LIMITATION" in block, name
        assert "session 23" in block, name


def test_the_o2_reason_names_the_observable_and_the_definition():
    block = _check_block("ghanekar_far_hall_o2_response_time_s")
    assert "0.9 m" in block
    assert "bulk room.o2" in block
    assert "initial response" in block.lower()
    # The measured consequence must be recorded, not just asserted.
    assert "1.200 m" in block
    assert "33/43" in block


def test_the_fed_reasons_name_the_transport_signal_and_the_hazard_gap():
    """UPDATED in session 26.

    The original version of this test asserted that the fed_0_3 block carried the
    flashover comparison (495.3 s vs 894 s) and framed it as fire growth being
    "44.6 % too fast". Session 26 verified the primary source and found that
    framing unsupported: the published 894 s belongs to the COMBINED
    kitchen-living room compartment reached after fire spread, whereas the case
    ignites R3 directly with fire_spread_enabled=false. The flashover discussion
    therefore moved to the flashover check, where the control-volume and
    criterion problems are recorded. This test now pins where each claim lives.
    """
    block = _check_block("ghanekar_kitchen_far_hall_fed_0_3_s")
    assert "405.75" in block           # the far-hall O2 transport check that PASSES
    assert "0.2368" in block           # the FED peak that never reaches 0.3
    # The PUBLISHED note must not restate the flashover claim as a settled
    # fire-growth fact. The source comment above it may still quote "44.6 %" --
    # retracting a claim in public beats deleting it -- but only while retracting.
    note = _note_string("ghanekar_kitchen_far_hall_fed_0_3_s")
    assert "44.6" not in note, "the retracted fire-growth framing must not be republished"
    if "44.6" in block:
        assert "outruns the" in block, (
            "the block may quote the retracted figure only while retracting it")
    assert "ghanekar_kitchen_fire_room_flashover_s" in block, (
        "fed_0_3 must point at the check that actually owns the flashover question")
    # ... and the fed_1_0 block must cross-reference fed_0_3 rather than restate it.
    other = _check_block("ghanekar_kitchen_far_hall_fed_1_0_s")
    assert "fed_0_3" in other
    assert "redesign" in other


def test_the_fed_1_0_block_states_it_lost_provenance():
    block = _check_block("ghanekar_kitchen_far_hall_fed_1_0_s")
    assert "re-baselined" in block.lower()
    assert "a4b5e8f5" in block
    assert "624" in block, "the published value must be named"
    assert "excludes" in block.lower()


# --------------------------------------------------------------------------
# The fresh results must stay visible
# --------------------------------------------------------------------------

def test_the_fresh_failing_results_are_not_hidden():
    o2 = _check_block("ghanekar_far_hall_o2_response_time_s")
    assert "232.5" in o2, "the failing O2 time must remain on the record"
    for name in ("ghanekar_kitchen_far_hall_fed_0_3_s",
                 "ghanekar_kitchen_far_hall_fed_1_0_s"):
        block = _check_block(name)
        assert "NOT REACHED" in block, name


def test_no_expected_value_is_rebaselined_onto_runtime():
    # 232.5 s is the fresh runtime result. It must appear only as reported
    # evidence, never as an expected value.
    for name in DEMOTED:
        block = _check_block(name)
        assert "expected=232" not in block, name
        assert "expected=None" not in block, name


# --------------------------------------------------------------------------
# Materially false documentation, corrected
# --------------------------------------------------------------------------

def test_the_co_idlh_note_no_longer_claims_it_is_unreached():
    note = _note_string("ghanekar_kitchen_far_hall_idlh_co_s")
    assert "866.58" in note, "the frozen arrival time must be stated"
    # It must ASSERT arrival. It may still mention the retracted claim, but only
    # while marking it as wrong -- retracting in public is better than deleting.
    assert "IS reached" in note
    if "no longer reached" in note:
        assert "factually wrong" in note, (
            "the note may quote the retracted claim only while retracting it")
    # The correction comment above it SHOULD still quote what it replaced.
    block = _check_block("ghanekar_kitchen_far_hall_idlh_co_s")
    assert "NOTE CORRECTED" in block
    assert "FALSE against the frozen" in block


def test_the_empirical_reference_no_longer_denies_hcn():
    assert "todavia no modela `HCN`" not in EMPIRICAL
    assert "No existe `HCN`" not in EMPIRICAL
    assert "si modela `HCN`" in EMPIRICAL
    assert "56.96" in EMPIRICAL, "the measured HCN peak must be cited"


def test_the_empirical_reference_declares_its_provenance():
    """UPDATED in session 26 — the session-23 provenance claims were FALSE.

    Session 23 asserted that the primary PDF was not in the repository and that
    the transcription had not been contrasted against the article. Both were
    false: the article has been tracked in git at docs/literature/ since
    2026-04-19, and session 25 contrasted the transcription against it. This test
    now pins the corrected provenance and the retraction, so the false claims
    cannot silently return.
    """
    # The falsified claims must be gone as live assertions.
    assert "NO esta en el repositorio" not in EMPIRICAL
    assert "todavia no ha sido contrastada" not in EMPIRICAL
    # The verified provenance must be recorded.
    assert "PROCEDENCIA VERIFICADA" in EMPIRICAL
    assert "d91a0b8b54e33111b582e7aa0f2f779a7767f752" in EMPIRICAL
    assert "1B2A1B00EE4ADECEA86771694260AAF8233637E69679B794C8BA1A6B44675030" in EMPIRICAL
    assert "10.1016/j.firesaf.2026.104724" in EMPIRICAL
    assert "CC BY-NC-ND 4.0" in EMPIRICAL
    # The retraction must be explicit, not a silent deletion.
    assert "RETRACTACION" in EMPIRICAL
    # The historical F: path survives, but only as obsolete provenance.
    assert "OBSOLETA" in EMPIRICAL
    # The genuinely open uncertainty must still be named.
    assert "16-23 s" in EMPIRICAL


def test_the_stale_calibration_claim_is_annotated_not_deleted():
    # The obsolete numbers stay on the record, marked obsolete, next to the
    # fresh ones. Deleting them would erase the provenance trail.
    assert "176.7 s" in EMPIRICAL
    assert "OBSOLETO" in EMPIRICAL
    assert "232.5 s" in EMPIRICAL


# --------------------------------------------------------------------------
# The gap inventory must agree, and must not claim closure
# --------------------------------------------------------------------------

def test_inventory_documents_the_new_gap_count():
    m = re.search(r"(\d+)\s+gaps?\s+non-gating", INVENTORY, re.IGNORECASE)
    assert m is not None
    assert int(m.group(1)) == 76, m.group(1)


def test_inventory_reports_zero_disallowed_blockers():
    assert "0 required failures no permitidos" in INVENTORY
    assert "Required failures no permitidos (0 checks" in INVENTORY


def test_inventory_keeps_the_three_visible_with_final_disposition():
    for name in DEMOTED:
        assert name in INVENTORY, name
    assert "VERIFIED_MODEL_LIMITATION" in INVENTORY
    assert "no se presenta como validado" in INVENTORY


def test_inventory_records_the_published_values_beside_the_retained_ones():
    # The divergence between contract and paper is the finding; it must be
    # readable without opening the session reports.
    assert "198±**18**" in INVENTORY or "198±18" in INVENTORY
    assert "546±**120**" in INVENTORY or "546±120" in INVENTORY
    assert "**624**±126" in INVENTORY or "624±126" in INVENTORY
