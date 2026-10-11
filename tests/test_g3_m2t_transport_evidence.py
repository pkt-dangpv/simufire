"""Executed M2-T records, not planned checks; no new Godot launch here."""

import hashlib
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
RECORDS = ROOT / "docs/validation"
DATE = "2026-10-11"
SOURCES = ("sim/core/RoomOxygenInventory.gd", "sim/core/OxygenExchangeSystem.gd")


def record(label):
    return json.loads((RECORDS / f"G3_O2_TRANSPORT_M2T_{label}_{DATE}.json").read_text(encoding="utf-8"))


def sha_lf(path):
    return hashlib.sha256((ROOT / path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def healthy(health):
    assert health["timed_out"] is False
    assert health["error_dialogs"] == []
    assert health["residual_godot_processes"] == []
    assert health["process_quiescent"] is True
    assert health["cleanup_terminated_pids"] == []
    assert health["foreign_godot_processes"] == []


def test_same_real_fixture_fails_on_base_without_script_errors_and_passes_now():
    accepted = record("ACCEPTANCE")
    assert accepted["before"]["failure_count"] == 712
    assert accepted["before"]["returncode"] == 1
    assert accepted["before"]["restored_byte_for_byte"] is True
    assert accepted["fixture"]["checks"] == 3650
    assert accepted["fixture"]["failure_count"] == 0
    assert accepted["fixture"]["returncode"] == 0
    healthy(accepted["before"]["health"])
    healthy(accepted["fixture"]["health"])
    for path, expected in accepted["harness_sha256_lf"].items():
        assert sha_lf(path) == expected


@pytest.mark.parametrize("label", ["ACCEPTANCE", "REGRESSIONS", "CLOSURE"])
def test_executed_records_bind_the_current_two_engine_files(label):
    data = record(label)
    for path in SOURCES:
        assert sha_lf(path) == data["sources"][path]["normalized_sha256"]


@pytest.mark.parametrize("name", ["o2_closed", "o2_reopen_300"])
def test_whole_house_has_no_debt_or_oxygen_enrichment_and_balances_per_step(name):
    case = record("ACCEPTANCE")["houses"][name]
    assert case["evaluation"]["whole"] is True
    assert case["trace"]["steps"] == case["evaluation"]["budget"]["steps"] == 10800
    assert abs(case["trace"]["last_time_s"] - 900.0) < 1.0e-7
    assert case["trace"]["max_building_balance_kg"] < 1.0e-9
    assert case["evaluation"]["budget"]["closes_in_every_step"] is True
    assert case["evaluation"]["budget"]["largest_number_of_entries"] == 0
    assert case["evaluation"]["budget"]["delayed_exchanges"] == 0
    assert all(room["rich_steps"] == 0 and room["max_x"] <= 0.209 + 1.0e-12
               for room in case["trace"]["rooms"].values())
    healthy(case["health"])


def test_all_declared_mutants_die_where_expected_and_restore_originals():
    mutations = record("CLOSURE")["mutations"]
    assert mutations["executed"] == mutations["killed_where_expected"] == 12
    assert mutations["survivors"] == mutations["invalid"] == []
    assert mutations["originals_intact"] is True
    assert mutations["sha256_before"] == mutations["sha256_after"]
    assert sum(item["verdict"] == "killed" for item in mutations["results"]) == 12
    assert len(mutations["health"]) == 13
    for health in mutations["health"].values():
        healthy(health)
    for path, expected in mutations["sha256_after"].items():
        assert sha_lf(path) == expected


def test_historical_fixtures_and_all_nine_off_cases_remain_judged():
    regressions = record("REGRESSIONS")
    assert {key: value["checks"] for key, value in regressions["fixtures"].items()} == {
        "M1": 281, "M2": 102, "M2-V": 126}
    assert all(value["failure_count"] == 0 for value in regressions["fixtures"].values())
    identity = regressions["off_identity"]
    assert identity["identical_cases"] == identity["total_cases"] == 9
    assert all(case["identical"] and all(case["files"].values()) and case["ledger_absent"]
               for case in identity["cases"].values())
    for launch in regressions["launch_health"]:
        assert launch["returncode"] == 0 and launch["faults"] == []
        healthy(launch["health"])
