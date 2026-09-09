"""Fail-closed contracts for independently reviewable P1R8 dispositions."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "sim/validation/gap_dispositions.json"
EVIDENCE_PATH = ROOT / "sim/validation/evidence/p1r8_gap_disposition_evidence.json"
AGGREGATE_PATH = ROOT / "sim/validation/reports/reference_checks.json"
VALIDATOR = (ROOT / "scripts/simulation/validate_reference_cases.py").read_text(
    encoding="utf-8"
)

BEHAVIORAL_LIMITATIONS = {
    "g2_gie_transitional_attack_time_room_0_hrr_below_100_post_attack_s",
    "secondary_ignition_demo_room_1_max_fuel_objects_flaming_count",
    "secondary_ignition_demo_room_1_peak_hrr_kw",
    "secondary_ignition_demo_time_room_1_hrr_above_20_s",
    "two_storey_smoke_room_7_final_temp_upper_raw_c",
    "two_storey_smoke_time_room_7_temp_above_40_s",
}

V7_FALSE_POSITIVES = {
    "v7_underventilated_co_peak_time_room_0_co_upper_above_5000_s",
    "v7_underventilated_co_peak_time_room_0_o2_below_15pct_s",
}

REQUIRED_LIMITATIONS = {
    "cfast_t240_o2_depleted",
    "cfast_t350_o2",
    "cfast_t360_o2",
    "cfast_chain_r0_t300_temp_upper_c",
    "cfast_chain_r0_t600_temp_upper_c",
    "cfast_chain_r0_o2_t600_o2",
}

V7_RELATIONAL_CHECKS = {
    "v7_underventilated_co_peak_order_co5000_before_peak_hrr_s",
    "v7_underventilated_co_peak_order_o2_15pct_before_peak_hrr_s",
}

FINAL_GHANEKAR_LIMITATIONS = {
    "ghanekar_far_hall_o2_response_time_s",
}

REQUALIFIED_GHANEKAR_PASSES = {
    "ghanekar_kitchen_far_hall_fed_0_3_s",
    "ghanekar_kitchen_far_hall_fed_1_0_s",
}


def _registry() -> dict:
    return json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))


def test_registry_contains_only_evidenced_final_dispositions() -> None:
    data = _registry()
    assert data["schema_version"] == 1
    assert data["checkpoint"] == "edc61f4e50d290b70e3ef26f5867343e7d784a4f"
    entries = data["checks"]
    assert len(entries) == 78
    for name, entry in entries.items():
        assert name
        assert entry["disposition"] in {
            "FALSE_POSITIVE",
            "USER_EXCLUDED_HVAC",
            "VERIFIED_MODEL_LIMITATION",
        }
        assert entry["owner"]
        assert entry["evidence"]
        assert entry["basis"]


def test_registry_exactly_covers_current_failed_non_gating_checks() -> None:
    entries = _registry()["checks"]
    report = json.loads(AGGREGATE_PATH.read_text(encoding="utf-8"))
    failed_non_gating = {
        check["name"]
        for check in report["checks"]
        if not check["required"] and not check["pass"]
    }

    assert set(entries) == failed_non_gating


def test_dispositions_use_current_versionable_row_evidence() -> None:
    registry = _registry()["checks"]
    evidence = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
    aggregate = json.loads(AGGREGATE_PATH.read_text(encoding="utf-8"))
    checks = {check["name"]: check for check in aggregate["checks"]}

    assert evidence["contract"] == "p1r8-current-gap-disposition-evidence-v1"
    assert evidence["check_count"] == len(registry)
    assert set(evidence["checks"]) == set(registry)
    for name, entry in registry.items():
        assert entry["owner"] != "P1R8 independent closure reviewer"
        assert entry["evidence"] == (
            f"sim/validation/evidence/p1r8_gap_disposition_evidence.json#{name}"
        )
        row = evidence["checks"][name]
        current = checks[name]
        for field in (
            "actual",
            "expected",
            "tolerance",
            "minimum",
            "maximum",
            "required",
            "pass",
            "disposition",
        ):
            assert row.get(field) == current.get(field), (name, field)
        assert row["basis"] == entry["basis"]
        assert row["source_artifacts"] == current["provenance"]["artifacts"]


def test_newly_authorized_rows_have_exact_final_dispositions() -> None:
    entries = _registry()["checks"]
    for name in BEHAVIORAL_LIMITATIONS | REQUIRED_LIMITATIONS:
        assert entries[name]["disposition"] == "VERIFIED_MODEL_LIMITATION"
    for name in V7_FALSE_POSITIVES:
        assert entries[name]["disposition"] == "FALSE_POSITIVE"


def test_required_limitations_are_non_gating_without_contract_rewrites() -> None:
    report = json.loads(AGGREGATE_PATH.read_text(encoding="utf-8"))
    checks = {check["name"]: check for check in report["checks"]}
    for name in REQUIRED_LIMITATIONS:
        check = checks[name]
        assert check["required"] is False
        assert check["pass"] is False
        assert check["disposition"] == "VERIFIED_MODEL_LIMITATION"


def test_v7_snapshots_are_replaced_by_required_relational_contracts() -> None:
    report = json.loads(AGGREGATE_PATH.read_text(encoding="utf-8"))
    checks = {check["name"]: check for check in report["checks"]}
    for name in V7_FALSE_POSITIVES:
        assert checks[name]["pass"] is False
        assert checks[name]["required"] is False
        assert checks[name]["disposition"] == "FALSE_POSITIVE"
    for name in V7_RELATIONAL_CHECKS:
        assert checks[name]["pass"] is True
        assert checks[name]["required"] is True
        assert checks[name]["actual"] >= checks[name]["minimum"]


def test_final_aggregate_has_no_required_failures_or_undisposed_gaps() -> None:
    report = json.loads(AGGREGATE_PATH.read_text(encoding="utf-8"))
    assert len(report["checks"]) == 532
    assert report["required_count"] == 346
    assert report["failed_required_count"] == 0
    assert report["known_gap_count"] == 78
    assert report["all_required_pass"] is True
    failed_non_gating = [
        check for check in report["checks"]
        if not check["required"] and not check["pass"]
    ]
    assert len(failed_non_gating) == 78
    assert all(check.get("disposition") for check in failed_non_gating)


def test_fresh_ghanekar_passes_are_not_mislabeled_as_limitations() -> None:
    report = json.loads(AGGREGATE_PATH.read_text(encoding="utf-8"))
    checks = {check["name"]: check for check in report["checks"]}
    for name in FINAL_GHANEKAR_LIMITATIONS:
        assert checks[name]["required"] is False
        assert checks[name]["pass"] is False
        assert checks[name]["disposition"] == "VERIFIED_MODEL_LIMITATION"
    for name in REQUALIFIED_GHANEKAR_PASSES:
        assert checks[name]["required"] is False
        assert checks[name]["pass"] is True
        assert checks[name].get("disposition") is None


def test_v7_relational_checks_are_implemented_from_versioned_evidence() -> None:
    assert "V7_EVENT_ORDER_PATH" in VALIDATOR
    assert "build_v7_event_order_checks" in VALIDATOR
    assert "+ build_v7_event_order_checks()" in VALIDATOR


def test_o2_limitation_accounts_for_fourteen_previously_blocked_rows() -> None:
    entries = _registry()["checks"]
    o2_rows = [
        name
        for name, entry in entries.items()
        if entry["owner"] == "O2-OWNER-001"
    ]
    assert len(o2_rows) == 14
    assert all(
        entries[name]["disposition"] == "VERIFIED_MODEL_LIMITATION"
        for name in o2_rows
    )


def test_validator_applies_registry_without_changing_contract_fields() -> None:
    assert "GAP_DISPOSITIONS_PATH" in VALIDATOR
    assert "_load_gap_dispositions" in VALIDATOR
    assert "verify_gap_evidence: bool = True" in VALIDATOR
    assert (
        "_apply_gap_dispositions(\n"
        "        all_checks, verify_evidence=verify_gap_evidence\n"
        "    )"
    ) in VALIDATOR
    assert "check.disposition = entry[\"disposition\"]" in VALIDATOR
