"""Evidence for the current M3 engine, not historical M1/M2 records."""
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.simulation.detmath_routing import strip_detmath_routing  # noqa: E402
RECORD = ROOT / "docs/validation/G3_O2_M3_CURRENT_TECHNICAL_EVIDENCE_2026-10-11.json"


def record():
    return json.loads(RECORD.read_text(encoding="utf-8"))


def test_current_sources_and_judged_harness_match_the_recorded_bytes():
    data = record()
    for section in ("sources_sha256_lf", "judged_harness_sha256_lf"):
        for relative, digest in data[section].items():
            raw = (ROOT / relative).read_bytes().replace(b"\r\n", b"\n")
            if relative.startswith("sim/"):
                # 2026-10-15: undo only the DetMath routing; the rest must be
                # the exact bytes these campaigns judged.
                raw = strip_detmath_routing(raw.decode("utf-8")).encode("utf-8")
            assert hashlib.sha256(raw).hexdigest() == digest, relative


def test_both_falsification_campaigns_are_valid_and_restore_the_measured_sources():
    data = record()
    for name, count in (("integration", 477), ("owner", 126)):
        campaign = data["campaigns"][name]
        assert campaign["control_checks"] == count and campaign["control_verdict"] == "pass"
        assert campaign["declared"] == campaign["executed"] == campaign["killed_where_expected"] == 14
        assert campaign["clean_launches"] == 15 and campaign["originals_intact"]
        assert campaign["sources_before"] == campaign["sources_after"]
        assert all(data["sources_sha256_raw"][key] == value
                   for key, value in campaign["sources_after"].items())
        assert len(campaign["assertions"]) == 14
        assert all(row["verdict"] == "killed" and row["seen_where_expected"]
                   and row["failed_checks"] > 0 for row in campaign["assertions"])


def test_unlimited_identity_is_bounded_and_does_not_claim_physical_validation():
    data = record()
    unlimited = data["unlimited"]
    assert unlimited["identical_controls"] == 4 and unlimited["restored_byte_for_byte"]
    assert unlimited["checks"] == {"base": 675, "current": 675}
    assert len(unlimited["row_sha256"]["base"]) == 4
    assert unlimited["row_sha256"]["base"] == unlimited["row_sha256"]["current"]
    assert data["implemented"] and not data["product_activation"]
    assert not data["physical_validation"] and data["CO_FED"] == "OFF/NO-GO"


def test_all_nine_off_controls_are_identical_and_the_original_wrapper_fault_is_visible():
    off = record()["off"]
    assert off["identical_cases"] == off["total_cases"] == off["clean_launches"] == 9
    assert len(off["cases"]) == 9 and off["verified_without_rerunning"]
    assert "godot.health.jsonl" in off["original_wrapper_error"]
    for case in off["cases"].values():
        assert case["identical"] and case["ledger_absent"]
        assert len(case["files"]) == 7 and all(case["files"].values())
