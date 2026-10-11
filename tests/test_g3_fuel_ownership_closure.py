"""G3-1 closure: ownership analyzer, proposed contract and decision matrix."""

from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

from scripts.simulation.analyze_g3_fuel_ownership import (
    analyze_rows,
    classify,
    contract_violations,
)
from scripts.simulation.build_g3_fuel_ownership_matrix import (
    OUTPUT,
    TEMPLATE,
    build,
    template_rooms,
)


def _obj(object_id, before, burn, hrr, co=0.0004, proxy=False):
    return {
        "id": object_id, "is_proxy": proxy, "remaining_before_MJ": before,
        "remaining_after_MJ": before - burn, "burn_MJ": burn, "hrr_after_kw": hrr,
        "state_after": "flaming" if burn > 0 else "heating", "co_yield_kg_per_MJ": co,
    }


def _row(t, consumed, objects, co=0.0, smoke=0.0, hrr=0.0):
    explicit = sum(o["burn_MJ"] for o in objects if not o["is_proxy"])
    return {
        "schema_version": "g3_fuel_source_step_v2", "time_s": t, "room_id": 0,
        "hrr_after_kw": hrr, "room_fuel_consumed_delta_MJ": consumed,
        "explicit_object_burn_delta_MJ": explicit,
        "nominal_explicit_co_from_burn_kg": sum(o["burn_MJ"] * o["co_yield_kg_per_MJ"] for o in objects),
        "room_co_generated_delta_kg": co, "room_smoke_generated_kg_total_delta": smoke,
        "objects": objects,
    }


def _single(extra_after=0.0):
    rows = [_row(1.0, 0.5, [_obj("sofa", 1.0, 0.5, 50.0)], co=2e-4, smoke=6e-3, hrr=50.0),
            _row(2.0, 0.5, [_obj("sofa", 0.5, 0.5, 50.0)], co=2e-4, smoke=6e-3, hrr=50.0)]
    if extra_after:
        rows.append(_row(3.0, extra_after, [_obj("sofa", 0.0, 0.0, 0.0)], co=3e-4, smoke=9e-3, hrr=40.0))
    return rows


def test_single_object_has_one_owner_and_no_findings() -> None:
    result = analyze_rows(_single())
    assert result["net_gap_MJ"] == pytest.approx(0.0)
    assert not any(classify(result).values())


def test_energy_burned_after_the_object_is_exhausted_is_unowned() -> None:
    result = analyze_rows(_single(extra_after=2.0))
    assert result["unowned_MJ"] == pytest.approx(2.0)
    assert result["co_generated_unowned_kg"] == pytest.approx(3e-4)
    assert classify(result)["ownerless_fuel"]
    violations = contract_violations({"object_exhausted_room_residual": result})
    assert violations["object_exhausted_room_residual"] == [
        "C2_every_consumed_MJ_has_an_explicit_owner", "C3_no_species_from_unowned_energy"]


def test_double_counting_mutations_are_detected() -> None:
    doubled = _single()
    for row in doubled:
        row["explicit_object_burn_delta_MJ"] *= 2.0  # same MJ charged twice
    assert classify(analyze_rows(doubled))["double_count"]
    power = _single()
    power[0]["objects"].append(_obj("ghost", 1.0, 0.0, 50.0))  # HRR without room HRR
    assert classify(analyze_rows(power))["double_count"]


def test_proxy_is_not_an_owner_and_inactive_objects_are_listed() -> None:
    rows = _single()
    for row in rows:
        row["objects"].append(_obj("room_proxy_0", 5.0, row["room_fuel_consumed_delta_MJ"], 50.0, proxy=True))
        row["objects"].append(_obj("cold_chair", 3.0, 0.0, 0.0, co=0.004))
    result = analyze_rows(rows)
    assert result["explicit_burn_MJ"] == pytest.approx(1.0)
    assert result["inactive_objects"] == ["cold_chair"]
    assert "room_proxy_0" not in result["objects"]


def test_cross_case_contract_flags_inactive_object_species_and_room_cap() -> None:
    single = analyze_rows(_single())
    cold_rows = copy.deepcopy(_single())
    for row in cold_rows:
        row["room_co_generated_delta_kg"] *= 2.9
        row["objects"].append(_obj("cold_chair", 3.0, 0.0, 0.0, co=0.004))
    below_rows = [_row(1.0, 1.0, [_obj("sofa", 3.0, 1.0, 50.0)], co=2e-4, hrr=50.0)]
    violations = contract_violations({
        "single_object": single,
        "second_object_cold": analyze_rows(cold_rows),
        "room_below_objects": analyze_rows(below_rows),
        "empty_room": analyze_rows([_row(1.0, 0.0, [])]),
    })
    assert violations == {
        "second_object_cold": ["C6_inactive_object_does_not_change_species"],
        "room_below_objects": ["C5_room_total_does_not_cap_explicit_inventory"],
    }


DYNAMIC = Path(__file__).resolve().parents[1] / "docs/validation/G3_FUEL_OWNERSHIP_DYNAMIC_CLOSURE_2026-09-29.json"
EXPECTED_VIOLATIONS = {
    "two_objects_burning": ["C9_object_hrr_within_its_declared_max"],
    "second_object_cold": [
        "C2_every_consumed_MJ_has_an_explicit_owner",
        "C3_no_species_from_unowned_energy",
        "C8_burned_plus_remaining_equals_initial_inventory",
        "C9_object_hrr_within_its_declared_max",
        "C6_inactive_object_does_not_change_species",
        "C7_inactive_object_energy_is_not_burned",
    ],
    "object_exhausted_room_residual": [
        "C2_every_consumed_MJ_has_an_explicit_owner",
        "C3_no_species_from_unowned_energy",
    ],
    "room_below_objects": ["C5_room_total_does_not_cap_explicit_inventory"],
}


def test_inventory_conservation_and_object_cap_clauses() -> None:
    rows = _single(extra_after=1.0)  # 1 MJ burned while the object is empty
    for row in rows:
        row["objects"].append(_obj("cold", 1.0, 0.0, 0.0))
    result = analyze_rows(rows)
    assert result["inventory_excess_MJ"] == pytest.approx(1.0)
    violations = contract_violations(
        {"case": result}, {"case": {"room_MJ": 0.0, "object_max_hrr_kw": {"sofa": 40.0}}})
    assert "C8_burned_plus_remaining_equals_initial_inventory" in violations["case"]
    assert "C9_object_hrr_within_its_declared_max" in violations["case"]
    # A declared room aggregate owns its own MJ: C8 does not apply to it.
    lumped = contract_violations({"case": result}, {"case": {"room_MJ": 3.0}})
    assert "C8_burned_plus_remaining_equals_initial_inventory" not in lumped.get("case", [])


def test_dynamic_batch_is_healthy_and_its_contract_result_is_pinned() -> None:
    data = json.loads(DYNAMIC.read_text(encoding="utf-8"))
    assert data["run"] == "g3_fuel_ownership_matrix_20260929_085916"
    names = [case["name"] for case in data["cases"]]
    assert len(names) == 9 and names[0] == "empty_room"
    results, declared = {}, {}
    for case in data["cases"]:
        assert case["health"] == {"timed_out": False, "error_dialogs": [],
                                  "residual_godot_processes": [], "process_quiescent": True}
        assert case["csv_last_time_s"] == pytest.approx(90.1)
        results[case["name"]] = {**case["result"], "objects": case["objects"]}
        declared[case["name"]] = case["declared"]
    assert contract_violations(results, declared) == data["contract_violations"] == EXPECTED_VIOLATIONS
    cold = results["second_object_cold"]
    assert cold["inactive_objects"] == ["g3_cold_chair"]
    assert cold["objects"]["g3_cold_chair"]["final_remaining_MJ"] == pytest.approx(3.0)
    assert cold["room_consumed_MJ"] == pytest.approx(5.996351, abs=1e-6)
    assert results["object_exhausted_room_residual"]["unowned_MJ"] == pytest.approx(1.998060, abs=1e-6)
    # The real salon burned all four objects within 90 s: no inactive object
    # and no unowned MJ yet, so its 1680 MJ ambiguity is not exercised.
    real = results["ambiguous_real_compact_salon"]
    assert real["inactive_objects"] == [] and real["unowned_MJ"] == 0.0


def test_matrix_is_regenerated_exactly_and_follows_the_policy() -> None:
    stored = json.loads(OUTPUT.read_text(encoding="utf-8"))
    assert stored == build()
    mismatches, presets = stored["mismatches"], stored["presets_without_objects"]
    assert len(mismatches) == 23 and len(presets) == 7
    assert {m["classification"] for m in mismatches} == {"legacy_unknown"}
    assert {m["decision"] for m in mismatches} == {"bloquear_procedencia_desconocida"}
    assert {p["classification"] for p in presets} == {"legacy_lumped"}
    assert {p["decision"] for p in presets} == {"mantener_agregado_explicito"}
    # No case is promoted without a recorded source for the full inventory.
    assert all(m["classification"] != "explicit_objects" for m in mismatches)
    assert all(m["energy_difference_MJ"] > 0 for m in mismatches)
    two_storey = [m for m in mismatches if m["file"] == "preset_two_storey_house.json"]
    assert len(two_storey) == 6 and all(m["template_literal_verified"] for m in two_storey)
    assert all(m["validation_cases_using_template"] == ["cfast_two_floor_stairwell.json", "two_storey_smoke.json"]
               for m in two_storey)


def test_template_literal_check_detects_a_changed_room_load() -> None:
    source = TEMPLATE.read_text(encoding="utf-8")
    original = template_rooms("create_uk_bungalow", source)
    mutated = source.replace('"Lounge",         "salon",      r_lounge,  H, 10500.0', '"Lounge",         "salon",      r_lounge,  H, 10400.0')
    assert mutated != source
    assert template_rooms("create_uk_bungalow", mutated)[0]["fuel_energy_MJ"] != original[0]["fuel_energy_MJ"]
    assert template_rooms("create_two_storey_house", source)[0]["object_energy_MJ"] == 3220.0
