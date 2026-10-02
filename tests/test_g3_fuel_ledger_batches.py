"""Pins the measured G3-3 batches: ledger inertness, OFF identity and ON ownership."""

from __future__ import annotations

import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
BATCHES = ROOT / "docs/validation/G3_FUEL_LEDGER_BATCHES_2026-09-29.json"
MUTATIONS = ROOT / "docs/validation/G3_FUEL_OWNERSHIP_MUTATIONS_2026-09-29.json"
EXPLICIT = ["single_object", "sofa_plus_cold_chair", "two_active_objects",
            "low_power_object", "named_aggregate_source"]
LEGACY = ["empty_room", "room_load_above_objects", "room_load_below_objects", "room_aggregate_only"]


def _data() -> dict:
    return json.loads(BATCHES.read_text(encoding="utf-8"))


def test_every_run_is_healthy_and_ledger_and_off_are_byte_identical() -> None:
    data = _data()
    assert set(data["phases"]) == {"before", "ledger", "off", "on"}
    for phase in data["phases"].values():
        assert len(phase["cases"]) == 9
        for case in phase["cases"].values():
            assert case["health"] == {"timed_out": False, "error_dialogs": [],
                                      "residual_godot_processes": [], "process_quiescent": True}
            assert case["csv_last_time_s"] == pytest.approx(90.1)
    for comparison in ("before_vs_ledger", "before_vs_off"):
        assert data["byte_identity"][comparison] == {name: True for name in EXPLICIT + LEGACY} \
            or all(data["byte_identity"][comparison].values())
        assert len(data["byte_identity"][comparison]) == 9


def test_ledger_closes_numerically_in_every_phase() -> None:
    for phase in ("ledger", "off", "on"):
        for name, case in _data()["phases"][phase]["cases"].items():
            assert case["ledger_closure_failures"] == [], (phase, name)


def test_legacy_defects_are_measured_before_the_fix() -> None:
    ledger = _data()["phases"]["ledger"]
    assert ledger["behaviour_contract_C1_C9"] == {
        "sofa_plus_cold_chair": ["C2_every_consumed_MJ_has_an_explicit_owner",
                                 "C3_no_species_from_unowned_energy",
                                 "C8_burned_plus_remaining_equals_initial_inventory",
                                 "C9_object_hrr_within_its_declared_max"],
        "two_active_objects": ["C9_object_hrr_within_its_declared_max"],
        "room_load_above_objects": ["C2_every_consumed_MJ_has_an_explicit_owner",
                                    "C3_no_species_from_unowned_energy"],
        "low_power_object": ["C9_object_hrr_within_its_declared_max"],
    }
    cold = ledger["cases"]["sofa_plus_cold_chair"]["ledger_v3"]
    assert cold["owners_MJ"]["unowned"] == pytest.approx(2.996351, abs=1e-6)
    assert cold["objects_final_MJ"]["g3_cold_chair"] == 3.0
    single = ledger["cases"]["single_object"]
    assert single["ownership_contract_on_ledger"] == [
        "O1_unowned_MJ", "O2_discarded_MJ", "O4_power_cap", "O5_heat_without_fuel_owner"]
    assert single["ledger_v3"]["solid_released_MJ"] == pytest.approx(3.405765, abs=1e-6)
    assert single["ledger_v3"]["consumed_MJ"] == pytest.approx(2.999863, abs=1e-6)
    above = ledger["cases"]["room_load_above_objects"]["ledger_v3"]
    assert above["room_load_MJ"] == pytest.approx(1.999863, abs=1e-6)


def test_switch_on_gives_one_owner_per_MJ_in_explicit_rooms_only() -> None:
    data = _data()
    off, on = data["phases"]["off"]["cases"], data["phases"]["on"]["cases"]
    for name in EXPLICIT:
        assert on[name]["ledger_v3"]["mode"] == ["explicit_owned"], name
        assert on[name]["explicit_owned_failures"] == [], name
        assert set(on[name]["ledger_v3"]["owners_MJ"]) <= {f"object:{o}" for o in on[name]["ledger_v3"]["objects_initial_MJ"]}
    for name in LEGACY:
        assert on[name]["artifact_sha256"] == off[name]["artifact_sha256"], name
    assert data["phases"]["on"]["behaviour_contract_C1_C9"] == {
        "room_load_above_objects": ["C2_every_consumed_MJ_has_an_explicit_owner",
                                    "C3_no_species_from_unowned_energy"]}
    assert on["sofa_plus_cold_chair"]["ledger_v3"]["objects_final_MJ"]["g3_cold_chair"] == 3.0
    assert on["low_power_object"]["ledger_v3"]["objects_over_own_cap"] == []


def test_chemistry_is_left_untouched_and_still_fails_c6() -> None:
    on = _data()["phases"]["on"]["c6_cold_chair_chemistry"]
    # Same fuel consumed with and without the cold chair ...
    assert on["consumed_ratio_cold_over_single"] == pytest.approx(1.0, rel=1e-5)
    # ... yet generated CO still depends on it: yield weighting is G3-4 work.
    assert on["co_ratio_cold_over_single"] > 2.5


def test_every_mutant_reintroducing_a_defect_is_detected() -> None:
    data = json.loads(MUTATIONS.read_text(encoding="utf-8"))
    assert data["restored_sha256"] == data["original_sha256"]
    assert set(data["mutants"]) == {"M1_inactive_object_counted", "M2_no_object_power_cap",
                                    "M3_heat_release_not_bounded_by_pyrolysis",
                                    "M4_tiny_demand_not_debited"}
    assert all(item["detected"] for item in data["mutants"].values())
