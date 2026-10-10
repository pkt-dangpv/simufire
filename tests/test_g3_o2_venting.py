"""Stage M2-V of the oxygen authority: pressure venting as an operation of the owner.

These tests read the record written by ``scripts/simulation/run_g3_o2_venting.py`` and
the code of the stage. They launch nothing: the fixture, the mutations and the house
cases run through the monitored launcher from their own runners.

What the record has to show:

* before the stage the acceptance fixture fails for what that engine does, with no
  script error: the first venting event with a quantity refuses the run;
* on this engine every venting event is one operation of the owner with the entry, the
  exit and what is left that the contract says, by an oracle that calls nothing of it;
* the inventory and its transit close within 1e-9 kg in every step, in the fixture and
  in the two whole house cases;
* the historical gap of the house is what one write discards at its ceiling, and taking
  that ceiling out, in a diagnostic copy, closes it;
* with the mode on that same credit is not discarded: a room is richer than the outside
  air for a while, and the record says so;
* every declared mutant dies where it was declared.

A budget that closes does not show that the distribution of the gas is realistic, and
nothing here says it does.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
RECORD = ROOT / "docs" / "validation" / "G3_O2_PRESSURE_VENTING_M2V_2026-10-10.json"
REPORT = ROOT / "docs" / "validation" / "G3_O2_PRESSURE_VENTING_M2V_2026-10-10.md"
CONTRACT = ROOT / "docs" / "validation" / "G3_O2_PRESSURE_VENTING_M2V_CONTRACT_2026-10-10.md"
FIXTURE = ROOT / "tests" / "fixtures" / "g3_o2_venting.gd"
OWNER = ROOT / "sim" / "core" / "RoomOxygenInventory.gd"
GAS = ROOT / "sim" / "core" / "GasExchangeSystem.gd"
OXYGEN = ROOT / "sim" / "core" / "OxygenExchangeSystem.gd"
RUNNER_TOOL = ROOT / "tools" / "run_scenario_headless.gd"
HOUSE_RUNNER = ROOT / "scripts" / "simulation" / "run_g3_o2_venting_house.py"
MUTATION_RUNNERS = {
    "venting_mutations": ROOT / "scripts" / "simulation" / "run_g3_o2_venting_mutations.py",
    "selection_mutations": ROOT / "scripts" / "simulation" / "run_g3_o2_selection_mutations.py",
    "inventory_mutations": ROOT / "scripts" / "simulation" / "run_g3_o2_room_inventory_mutations.py",
}
GAP_KG = 1.0e-9
OPERATION_TOL_KG = 1.0e-12
GROUPS = 10
HOUSE_CASES = ("o2_closed", "o2_reopen_300")
WHOLE_STEPS = 10800
STILL_FROZEN = {
    "sim/fire/PrescribedObjectHrrSource.gd": "f8a39d8312a6ef0117ea37eeec3df7fb7858f212d6c32539ac3d41e850d6c3c4",
}
# The combustion system as stage M2 left it. This stage does not touch it.
COMBUSTION_AFTER_M2 = "621535487530b23fb14be11159c998c52978cdf8dc5d4ae909e4a447aa920ea6"
# The ten families of defects asked for with the stage.
ASKED_FOR = ("venting_left_out_of_the_inventory", "wrong_sign", "entry_counted_twice", "exit_counted_twice",
             "mole_fraction_taken_for_a_mass_fraction", "clipped_to_the_ceiling_in_silence", "applied_twice",
             "transit_left_out_of_the_budget", "room_number_written_directly", "old_refusal_kept")


def _load(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _code(path: Path) -> str:
    """The file without its comment lines."""
    return "\n".join(line for line in _text(path).splitlines() if not line.lstrip().startswith("#"))


def _prose(path: Path) -> str:
    """A document with its line breaks taken out: a phrase may be wrapped anywhere."""
    return " ".join(_text(path).split())


def _venting_law() -> str:
    return _text(GAS).split("func step_pressure_venting(", 1)[1].split("\nfunc ", 1)[0]


@pytest.fixture(scope="module")
def record() -> dict:
    return json.loads(RECORD.read_text(encoding="utf-8"))


# ---------------------------------------------------------------- the record

def test_the_record_belongs_to_the_code_it_speaks_of(record):
    for relative, digest in record["sources_sha256"].items():
        current = hashlib.sha256((ROOT / relative).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        assert current == digest, f"{relative} changed after the record was written: run the stage again"


def test_what_the_stage_does_not_touch_is_as_it_was(record):
    assert all(record["untouched_equal_to_before_m2v"].values()), record["untouched_equal_to_before_m2v"]
    for relative, digest in STILL_FROZEN.items():
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest, relative
    assert record["untouched_sha256"]["sim/fire/CombustionSystem.gd"] == COMBUSTION_AFTER_M2
    assert hashlib.sha256((ROOT / "sim/fire/CombustionSystem.gd").read_bytes()).hexdigest() == COMBUSTION_AFTER_M2


def test_before_the_stage_the_fixture_fails_for_what_that_engine_does(record):
    before = record["before_m2v"]
    assert before["script_errors"] == 0, "a harness error is not a failed test"
    assert before["returncode"] == 1 and before["pass_marker"] is False and before["restored_byte_for_byte"] is True
    assert before["failure_count"] > 20
    # The groups that ask for the operation fail; the one that asks for no venting does not.
    for group in ("V02", "V03", "V04", "V05", "V06", "V08", "V09"):
        assert before["failures_by_group"].get(group, 0) > 0, group
    assert "V01" not in before["failures_by_group"]
    defect = before["the_defect_measured"]
    assert defect["venting_operations"] == 0 and 0 < defect["steps_before_the_run_was_refused"] < defect["steps_asked"]


def test_the_acceptance_passes_on_the_real_engine(record):
    acceptance = record["acceptance"]
    assert acceptance["pass_marker"] is True and acceptance["returncode"] == 0
    assert acceptance["failure_count"] == 0 and acceptance["script_errors"] == 0
    assert len(acceptance["groups"]) == GROUPS and acceptance["checks"] > 100
    assert [group[:3] for group in acceptance["groups"]] == [f"V{index:02d}" for index in (1, 2, 3, 6, 7, 4, 5, 8, 9, 10)]


@pytest.mark.parametrize("case", ["room_that_vents", "two_rooms dt 0.25", "two_rooms dt 0.125"])
def test_every_venting_event_is_the_closed_form_and_the_budgets_close(record, case):
    measured = record["acceptance"]["observations"][case]
    assert measured["events"] > 50 and measured["events"] == measured["steps_with_smoke_retired"]
    assert measured["steps_before_a_refusal"] == measured["steps"]
    assert measured["gas_is_the_law"] is True and measured["leaving_is_the_mixture"] is True
    assert measured["worst_operation_kg"] <= OPERATION_TOL_KG
    assert measured["every_event_has_an_entry_and_an_exit"] is True and measured["events_per_room_and_step_at_most_one"] is True
    assert measured["venting_in_kg"] > measured["venting_out_kg"] > 0.0
    assert measured["venting_net_kg"] == pytest.approx(measured["venting_in_kg"] - measured["venting_out_kg"], abs=GAP_KG)
    for key in ("room_gap_kg", "building_gap_kg", "oracle_gap_kg"):
        assert measured[key] <= GAP_KG, (case, key)
    assert measured["worst_accumulator_kg"] <= OPERATION_TOL_KG
    assert measured["selection_ids_consecutive"] is True and measured["selection_keeps_the_opening"] == measured["steps"]
    if case != "room_that_vents":
        assert measured["largest_transit_kg"] > 1.0e-4 and measured["delayed"] > 0


def test_the_sign_follows_the_room_and_nothing_is_clipped(record):
    observations = record["acceptance"]["observations"]
    equal, depleted, enriched = (observations["sign " + name] for name in ("equal to the outside", "depleted", "enriched"))
    assert equal["events"] == depleted["events"] == enriched["events"] == 3
    assert abs(equal["net_kg"]) <= 1.0e-15 and equal["mole_fraction_at_the_end"] == pytest.approx(0.209, abs=1.0e-12)
    assert depleted["net_kg"] > 1.0e-6 and 0.15 < depleted["mole_fraction_at_the_end"] < 0.209
    # A room above the outside loses oxygen and stays above 0.209: the historical write would cut it there.
    assert enriched["net_kg"] < -1.0e-7 and 0.229 < enriched["mole_fraction_at_the_end"] < 0.23
    for item in (equal, depleted, enriched):
        assert item["worst_kg"] <= OPERATION_TOL_KG


def test_the_effect_on_the_fire_is_recorded_and_not_hidden(record):
    effect = record["acceptance"]["observations"]["effect room_that_vents"]
    assert effect["on"]["failure"] == "" and effect["on"]["steps"] == effect["off"]["steps"] == 1200
    assert effect["on"]["venting_events"] > 100 and effect["off"]["venting_events"] is None
    assert effect["on"]["venting_in_kg"] > effect["on"]["venting_out_kg"] > 0.0
    assert effect["off"]["heat_MJ"] > 5.0 and effect["on"]["heat_MJ"] > 5.0


@pytest.mark.parametrize("stage", ["stage_m1_again", "stage_m2_again"])
def test_the_earlier_stages_still_pass_on_this_engine(record, stage):
    again = record[stage]
    assert again["pass_marker"] is True and again["failure_count"] == 0 and again["script_errors"] == 0
    assert again["checks"] == {"stage_m1_again": 281, "stage_m2_again": 102}[stage]


def test_the_historical_route_gives_the_figures_it_gave(record):
    historical = record["historical_route"]
    assert historical["identical_figure_by_figure"] is True and historical["differing"] == {}
    assert len(historical["hypotheses_compared"]) == 13 and historical["published_record_rewritten"] is False


# ---------------------------------------------------------------- mutations

@pytest.mark.parametrize("key", sorted(MUTATION_RUNNERS))
def test_every_mutant_dies_where_it_was_declared(record, key):
    mutations = record[key]
    plan = _load(MUTATION_RUNNERS[key]).plan()
    assert mutations["control"] == "pass" and mutations["originals_intact"] is True
    assert mutations["declared"] == mutations["executed"] == mutations["killed"] == mutations["killed_where_expected"] == len(plan)
    assert mutations["survivors"] == [] and mutations["invalid"] == [] and mutations["killed_elsewhere"] == []
    for item in mutations["results"]:
        if item["name"] == "control":
            continue
        assert item["verdict"] == "killed" and item["seen_where_expected"] is True, item["name"]
        assert item["expected_in"] == plan[item["name"]]["expected_in"] and item["failed_checks"] > 0, item["name"]
        # Killed by a check that fails, never by a script that does not parse.
        assert item["reason"] == "", item["name"]


def test_the_mutation_anchors_still_exist():
    for runner in MUTATION_RUNNERS.values():
        originals, variants = _load(runner).prepared()
        assert len(variants) >= 15 and all(text for _relative, text in variants.values())


def test_the_families_asked_for_are_among_the_mutants():
    module = _load(MUTATION_RUNNERS["venting_mutations"])
    declared = module.DECLARED_WITH_THE_STAGE
    assert tuple(name.split("_", 1)[1] for name in declared) == ASKED_FOR
    plan = module.plan()
    assert all(plan[name]["declared_with_the_plan"] for name in declared) and len(plan) == 16
    assert {item["expected_in"] for item in plan.values()} == {"V02", "V03", "V04", "V05", "V06", "V07", "V08"}
    # The transit left out of the state itself is the mutant of stage M1, run here on a room that vents.
    assert module.MUTATIONS["W08_transit_left_out_of_the_budget"][1] == \
        _load(MUTATION_RUNNERS["inventory_mutations"]).MUTATIONS["T01_transit_omitted"][1]


# ---------------------------------------------------------------- the house cases

@pytest.mark.parametrize("case", HOUSE_CASES)
def test_the_house_runs_whole_with_the_mode_on_and_closes_in_every_step(record, case):
    on = record["house"]["cases"][case]["on"]
    budget = on["budget"]
    assert on["mode"] == "on" and on["switch_in_the_scenario"] is True
    assert budget["refused"] is None and on["whole"] is True, "a run that was cut must not be said to be whole"
    assert budget["steps"] == on["trace_rows"] == WHOLE_STEPS and on["last_time_s"] == pytest.approx(900.0, abs=1.0e-6)
    assert on["launch_error"] == ""
    for key in ("room_gap_kg", "building_gap_kg", "oracle_gap_kg"):
        assert budget[key] <= GAP_KG, (case, key)
    assert budget["closes_in_every_step"] is True and budget["lowest_inventory_kg"] > 0.0
    assert abs(budget["house"]["residual_with_transit_kg"]) <= GAP_KG
    for room, item in budget["by_room"].items():
        assert abs(item["residual_kg"]) <= 1.0e-8, (case, room)
    assert budget["rooms_where_the_fire_read_its_selection"] == budget["rooms_consulted"] == 6 * WHOLE_STEPS
    assert budget["debits"] > 0 and budget["debits_on_the_selection_the_fire_read"] == budget["debits"]
    assert budget["more_than_one_debit_in_a_step"] == 0 and budget["selections_missing"] == 0
    assert budget["debits_above_what_was_available"] == 0


@pytest.mark.parametrize("case", HOUSE_CASES)
def test_the_venting_of_the_house_is_recorded_with_its_entry_and_its_exit(record, case):
    venting = record["house"]["cases"][case]["on"]["venting"]
    assert venting["events"] > 1000 and venting["more_than_one_event_of_a_room_in_a_step"] == 0
    assert venting["in_kg"] > venting["out_kg"] > 0.0 and venting["net_is_in_minus_out"] is True
    assert venting["worst_operation_kg"] <= OPERATION_TOL_KG
    # Only the Salon vents, and from the moment in which stage M2 refused the run.
    assert list(venting["by_room"]) == ["0"] and venting["first_at_s"] == pytest.approx(74.4167, abs=0.01)
    assert venting["events_with_a_negative_net"] == 0


@pytest.mark.parametrize("case", HOUSE_CASES)
def test_c1_and_c2_hold_on_the_whole_traces(record, case):
    contracts = record["house"]["cases"][case]["on"]["contracts"]
    assert contracts["c1"] is True and contracts["c2"] is True
    assert contracts["inventory_from"] == "the oxygen trace, kg of O2"
    assert abs(contracts["c1_worst_residual_kg"]) <= 1.0e-6 and abs(contracts["c2_heat_minus_debit_kg"]) <= 1.0e-6


@pytest.mark.parametrize("case", HOUSE_CASES)
def test_what_the_cap_clips_is_measured_and_stage_m3_is_not_said_to_be_done(record, case):
    unbacked = record["house"]["cases"][case]["on"]["heat_the_debit_does_not_back"]
    # In these two cases the cap never acted. That closes nothing: see the report.
    assert unbacked["clipped_by_the_cap_kg"] == 0.0 and unbacked["steps_with_a_clip"] == 0
    assert abs(unbacked["not_debited_kg"]) <= GAP_KG
    assert "M3" in unbacked["what"]


@pytest.mark.parametrize("case", HOUSE_CASES)
def test_the_traces_of_the_historical_route_are_passive(record, case):
    for kind in ("off", "gap_passive"):
        run = record["house"]["cases"][case][kind]
        assert run["mode"] == "off" and run["switch_in_the_scenario"] is False
        assert len(run["identical_to_the_identity_run"]) == 6 and all(run["identical_to_the_identity_run"].values()), (case, kind)


# ---------------------------------------------------------------- the historical gap

def test_the_historical_gap_is_what_one_write_discards_at_its_ceiling(record):
    """The diagnostic copy that only counts: same outputs, and every kilogram of the gap accounted for."""
    reopened = record["house"]["cases"]["o2_reopen_300"]["gap_passive"]
    copy = reopened["budget"]["diagnostic_copy"]
    assert copy["variant"] == "passive"
    assert reopened["budget"]["transit_at_the_end_kg"] == 0.0
    assert copy["gap_at_the_end_kg"] == pytest.approx(-0.3778, abs=0.0001)
    assert copy["discarded_at_the_ceiling_kg"] == pytest.approx(-copy["gap_at_the_end_kg"], abs=1.0e-9)
    assert copy["discarded_at_the_floor_kg"] == 0.0 and copy["dropped_below_the_threshold_kg"] == 0.0
    # In every step, not only at the end: the gap is the discard, within the rounding of the other writes.
    assert copy["largest_gap_plus_what_the_writes_discarded_kg"] <= 1.0e-9
    assert abs(copy["rounding_of_the_writes_that_were_not_clipped_kg"]) <= 1.0e-9
    discarded = copy["by_category"]["discarded_at_the_ceiling"]
    at_once = discarded["by_site"]["credit_to_the_hot_room_at_once"]
    # Not the deferred deliveries: the credit given at once to the hot room of an exchange.
    assert at_once == pytest.approx(copy["discarded_at_the_ceiling_kg"], abs=1.0e-9)
    assert "deferred_delivery" not in discarded["by_site"]
    assert discarded["by_room"]["1"] == pytest.approx(copy["discarded_at_the_ceiling_kg"], abs=1.0e-9)
    assert copy["steps_with_a_discard_at_the_ceiling"] == reopened["budget"]["steps_in_which_the_gap_grows"] == 160
    assert 307.0 < copy["discards_at_the_ceiling_from_s"] < copy["discards_at_the_ceiling_until_s"] < 321.0


def test_with_the_door_closed_nothing_is_discarded(record):
    copy = record["house"]["cases"]["o2_closed"]["gap_passive"]["budget"]["diagnostic_copy"]
    # Rooms that sit exactly at 0.209 round a hair over it: that is all the copy counts here.
    assert abs(copy["discarded_at_the_ceiling_kg"]) <= 1.0e-9 and copy["steps_with_a_discard_at_the_ceiling"] == 0
    assert abs(copy["gap_at_the_end_kg"]) <= 1.0e-9 and copy["largest_gap_plus_what_the_writes_discarded_kg"] <= 1.0e-9


def test_taking_that_ceiling_out_closes_the_gap_and_is_not_published_as_a_fix(record):
    control = record["house"]["cases"]["o2_reopen_300"]["gap_control"]
    copy = control["budget"]["diagnostic_copy"]
    assert copy["variant"] == "ceiling_taken_out"
    assert copy["largest_gap_kg"] <= 1.0e-9 and control["budget"]["steps_in_which_the_gap_grows"] == 0
    assert abs(copy["discarded_at_the_ceiling_kg"]) <= 1.0e-9 and copy["left_above_the_ceiling_by_these_writes_kg"] > 0.3
    # The oxygen is then cut by another writer, later in the same step: no room number ends a step above 0.209.
    assert copy["steps_in_which_a_room_number_ends_above_the_outside"] == 0
    writers = control["writers"]["room_number"]
    assert abs(writers["ges_room_loop_transport"]["change_of_the_number_summed"]) > 1.0e-3
    assert writers["engine_final_tick_clamp"]["change_of_the_number_summed"] == 0.0
    assert "identical_to_the_identity_run" not in control, "the control is not the historical route"
    # The copies were taken out of the tree, and the distributed oxygen system has none of it.
    for kind in ("gap_passive", "gap_control"):
        described = record["house"]["cases"]["o2_reopen_300"][kind]["diagnostic_copy_of_the_oxygen_system"]
        assert described["restored"] is True and described["original_sha256"] == described["restored_sha256"] != described["copy_sha256"]
        assert described["original_sha256"] == hashlib.sha256(OXYGEN.read_bytes()).hexdigest()
    assert "g3_o2_diagnostic_counters" not in _text(OXYGEN) and "_g3_count" not in _text(OXYGEN)


def test_with_the_mode_on_a_room_is_richer_than_the_outside_for_a_while_and_the_record_says_so(record):
    reopened = record["house"]["cases"]["o2_reopen_300"]["on"]["richer_than_the_outside"]
    closed = record["house"]["cases"]["o2_closed"]["on"]["richer_than_the_outside"]
    assert closed["any_room_richer_than_the_outside"] is False and closed["rooms"] == {}
    assert reopened["any_room_richer_than_the_outside"] is True
    # The room that burns is never among them.
    assert "0" not in reopened["rooms"] and "1" in reopened["rooms"]
    next_room = reopened["rooms"]["1"]
    assert 0.3 < next_room["largest_excess_kg"] < 0.4 and 0.005 < next_room["largest_excess_of_the_fraction"] < 0.02
    assert 300.0 < next_room["first_at_s"] < next_room["last_at_s"] < 340.0
    # Its reading with what travels to it never is: the credit came at once and its debit is still on its way.
    assert reopened["explained_by_the_transit_alone"] is True
    assert all(item["steps_in_which_the_effective_reading_is_richer_too"] == 0 for item in reopened["rooms"].values())
    credits = reopened["credits_to_a_room_at_or_above_the_outside"]
    assert list(credits) == ["credit to the donor of an exchange, at once"]
    assert credits["credit to the donor of an exchange, at once"]["kg"] > 1.0


# ---------------------------------------------------------------- the contract in the code

def test_the_venting_asks_the_owner_before_it_writes_anything_of_the_event():
    law = _venting_law()
    asked = law.index("room_o2_inventory.outside_dilution_would_apply(")
    for write in ("room.smoke_kg = maxf(0.0, room.smoke_kg - smoke_out_kg)", "_record_smoke_vented(room, smoke_out_kg)",
                  "room.co2_kg = maxf(0.0", "room.overpressure_pa = maxf(0.0, room.overpressure_pa * (1.0 - frac_out * 0.9))"):
        assert law.count(write) == 1 and asked < law.index(write), write
    refused = law[asked:].split("\n\n", 1)[0]
    assert refused.rstrip().endswith("continue") and "dilute_with_outside(" in refused


def test_with_the_mode_on_the_venting_writes_the_inventory_through_the_owner_and_nothing_else():
    law = _venting_law()
    assert law.count("room_o2_inventory.dilute_with_outside(") == 2 and "refuse_route" not in law
    assert law.count("room.o2 = ") == 1, "one write of the room number: the historical one"
    historical = law.split("room.o2 = clampf(", 1)[0].rsplit("if room_o2_inventory != null:", 1)[1]
    assert "else:" in historical, "the historical write is the branch with no owner"
    assert law.count("var air_in_kg: float = smoke_out_kg * 0.40\n") == 1, "the law of the entering air is written once"
    assert '_pv_o2_delta = float(owned_dilution.get("net_kg", 0.0))' in law
    # The conversions are the owner's: the gas exchange holds none of its constants.
    gas = _code(GAS)
    for word in ("M_O2_KG_PER_MOL", "M_DRY_AIR_KG_PER_MOL", "0.031998", "0.0289647", "o2_kg_in_reference_gas"):
        assert word not in gas, word


def test_the_dilution_of_the_owner_validates_first_and_clips_nothing():
    owner = _text(OWNER)
    body = owner.split("func dilute_with_outside(", 1)[1].split("\nfunc ", 1)[0]
    assert body.index("_dilution_error(") < body.index("_commit(room, after_kg)")
    for word in ("clampf", "minf", "maxf", "0.209", "o2_nominal"):
        assert word not in body, word
    assert "o2_kg_in_reference_gas(float(outside_mole_fraction), entering_kg)" in body
    assert "reference_gas_kg(room.volume_m3()) + entering_kg" in body
    for total in ("outside_in_kg", "outside_out_kg", "dilution_events", "dilution_gas_kg", "dilution_in_kg", "dilution_out_kg"):
        assert body.count(f'totals["{total}"] +=') == 1, total
    asking = owner.split("func outside_dilution_would_apply(", 1)[1].split("\nfunc ", 1)[0]
    assert "_reject" not in asking and "_commit" not in asking, "asking writes nothing and refuses nothing"
    error = owner.split("func _dilution_error(", 1)[1].split("\nfunc ", 1)[0]
    assert "_reject" not in error and "_commit" not in error
    assert '"pressure_venting"' in owner.split("const SUPPORTED_ROUTES: Array[String] = [", 1)[1].split("]", 1)[0]


def test_the_routes_this_stage_does_not_own_are_still_refused():
    refused = set(re.findall(r'refuse_route\(\w+, "(\w+)"', _text(OXYGEN) + _text(GAS)))
    assert refused == {"exterior_opening_with_temperature_difference", "gas_exchange_room_transport",
                       "gas_exchange_parcel_delivery", "ppv"}


def test_the_trace_of_the_runner_is_still_passive():
    tool = _text(RUNNER_TOOL)
    trace = tool.split("func _o2_inventory_trace_before(", 1)[1]
    assert ".set(" not in trace and "o2_room_inventory_enabled" not in trace
    assert 'engine.oxygen_exchange_system.get("g3_o2_diagnostic_counters")' in trace
    assert '"transit_to": after["to_receiver"]' in trace


def test_a_diagnostic_copy_is_built_from_the_distributed_system_and_only_counts():
    house = _load(HOUSE_RUNNER)
    original = _text(OXYGEN)
    passive = house.diagnostic_source("gap_passive", original)
    control = house.diagnostic_source("gap_control", original)
    assert passive != original and control != passive
    # The copy that only counts keeps every write of the room number as it was.
    assert passive.count("room.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)") == 1
    assert control.count("room.o2 = clampf(room_o2_mass_kg / room_air_mass_kg, 0.0, o2_nominal)") == 0
    assert control.count("room.o2 = maxf(0.0, room_o2_mass_kg / room_air_mass_kg)") == 1
    removed = [line for line in original.splitlines() if line not in passive.splitlines()]
    assert removed == [], "the passive copy removes no line of the distributed system"


def test_the_fixture_sets_only_what_it_declares_and_takes_its_oracle_from_itself():
    fixture = _text(FIXTURE)
    assert "const GAP_KG: float = 1.0e-9" in fixture and "const OPERATION_TOL_KG: float = 1.0e-12" in fixture
    oracle = fixture.split("# ---------------------------------------------------------------- oracle", 1)[1].split("# -----", 1)[0]
    assert "inv." not in oracle and "_inv(" not in oracle and "_report(" not in oracle, "the oracle never calls the owner"
    assert 'print("G3_O2_VENTING_PASS")' in fixture and "quit(1)" in fixture
    assert 'OS.get_environment("G3_O2_VENTING_JUDGED_ONLY") != "1"' in fixture
    # The switches it raises: the mode, and the passive counter of the venting law.
    raised = set(re.findall(r"engine\.(\w+) = true", fixture))
    assert raised == {"phase3_zone_diagnostics_enabled"}, raised
    assert fixture.count('engine.set("o2_room_inventory_enabled", value)') == 1


# ---------------------------------------------------------------- documents

REQUIRED = (
    "dilución equivalente", "No es una conservación de la masa de gas", "fracción molar", "sin recorte",
    "Integración técnica", "Conservación contable", "Control causal", "Límites físicos", "Casos de casa",
    "enriquec", "crédito inmediato", "copia diagnóstica", "O2-3", "M3", "M4", "CO y FED siguen OFF/NO-GO",
    "G3_O2_PRESSURE_VENTING_M2V_2026-10-10.json", "G3_O2_PRESSURE_VENTING_M2V_CONTRACT_2026-10-10.md",
    "Lo que no se ha ejecutado", "Predicciones", "Un balance que cierra no demuestra",
)


def test_the_contract_was_written_with_its_predictions(record):
    contract = _prose(CONTRACT)
    for phrase in ("escritos antes de programar", "dilución equivalente", "No es una conservación de la masa de gas",
                   "Se valida antes de mutar", "P1", "P12", "(m + a)"):
        assert phrase in contract, phrase


def test_the_report_says_what_was_built_what_was_measured_and_what_is_still_open(record):
    report = _prose(REPORT)
    for phrase in REQUIRED:
        assert phrase in report, phrase
    assert f"{record['acceptance']['checks']} comprobaciones" in report
    assert "@@" not in report, "a figure of the verification is still to be written"


@pytest.mark.parametrize("relative", [
    "docs/HANDOFF_CURRENT_STATE.md", "docs/planning/G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md",
    "docs/validation/CONTRATO_O2_2026-09-24.md", "docs/validation/G3_O2_SELECTION_M2_2026-10-10.md",
    "docs/validation/G3_O2_AUTHORITY_2026-10-09.md",
])
def test_the_report_is_linked_from_the_documents_that_must_know(relative):
    assert "G3_O2_PRESSURE_VENTING_M2V_2026-10-10.md" in _text(ROOT / relative), relative
