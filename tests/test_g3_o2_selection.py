"""Stage M2 of the oxygen authority: one oxygen selection per room and step.

Offline. The record was produced by ``scripts/simulation/run_g3_o2_selection.py`` on the
real engine through the monitored launcher; here it is read, bound to the code it
speaks of and checked against what the stage promised:

* before the stage the fire read one deposit and the sink debited another, the
  consumption was declared twice and a sealed room that burns was refused;
* with it there is one selection per room and step, one debit, declared once;
* the inventory and its transit close within 1e-9 kg in every step;
* every declared mutant dies where it was declared it would;
* the acceptance of stage M1 still passes and the historical route is unchanged;
* the house cases are reported as they came out, refused included.

The effect on the fire is recorded, not judged. Nothing here validates fire behaviour,
CO, FED or SVV, and the heat is not fitted to the oxygen: that is stage M3.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

import pytest

ROOT = Path(__file__).resolve().parent.parent
RECORD = ROOT / "docs" / "validation" / "G3_O2_SELECTION_M2_2026-10-10.json"
REPORT = ROOT / "docs" / "validation" / "G3_O2_SELECTION_M2_2026-10-10.md"
FIXTURE = ROOT / "tests" / "fixtures" / "g3_o2_selection.gd"
OWNER = ROOT / "sim" / "core" / "RoomOxygenInventory.gd"
OXYGEN = ROOT / "sim" / "core" / "OxygenExchangeSystem.gd"
ENGINE = ROOT / "sim" / "core" / "SimulationEngine.gd"
COMBUSTION = ROOT / "sim" / "fire" / "CombustionSystem.gd"
RUNNER_TOOL = ROOT / "tools" / "run_scenario_headless.gd"
SELECTION_MUTATIONS = ROOT / "scripts" / "simulation" / "run_g3_o2_selection_mutations.py"
INVENTORY_MUTATIONS = ROOT / "scripts" / "simulation" / "run_g3_o2_room_inventory_mutations.py"
GAP_KG = 1.0e-9
GROUPS = 10
# The commit that published the record of stage M2.
PUBLISHED_IN = "461fa9c0"
# The combustion system before this stage: the hash stage M1 kept frozen.
COMBUSTION_BEFORE = "241398b06ac898dbe131ab53ccb023353382c01144298a365ec4ea4b43aff035"
STILL_FROZEN = {
    "sim/fire/PrescribedObjectHrrSource.gd": "f8a39d8312a6ef0117ea37eeec3df7fb7858f212d6c32539ac3d41e850d6c3c4",
}
HOUSE_CASES = ("o2_closed", "o2_reopen_300")


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


@pytest.fixture(scope="module")
def record() -> dict:
    return json.loads(RECORD.read_text(encoding="utf-8"))


# ---------------------------------------------------------------- the record

def test_the_record_belongs_to_the_code_it_speaks_of(record):
    # The record is evidence of the commit that published it. Later stages change some of
    # these files, and run the acceptance of this one again on their own engine.
    for relative, digest in record["sources_sha256"].items():
        blob = subprocess.run(["git", "show", f"{PUBLISHED_IN}:{relative}"], cwd=ROOT, capture_output=True)
        if blob.returncode != 0:
            pytest.skip("the history of the repository is not available")
        assert hashlib.sha256(blob.stdout.replace(b"\r\n", b"\n")).hexdigest() == digest, \
            f"{relative}: the record does not belong to the code of {PUBLISHED_IN}"


def test_the_combustion_system_changed_for_this_stage_and_the_record_says_from_what_to_what(record):
    combustion = record["combustion_system"]
    assert combustion["sha256_before"] == COMBUSTION_BEFORE and combustion["before_is_the_commit"] == "718061f7"
    assert combustion["sha256_after"] == hashlib.sha256(COMBUSTION.read_bytes()).hexdigest() != COMBUSTION_BEFORE
    for relative, digest in STILL_FROZEN.items():
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest, relative
        assert record["untouched_sha256"][relative] == digest
    assert all(record["untouched_equal_to_before_m2"].values())


def test_before_the_stage_the_fixture_fails_for_what_that_engine_does(record):
    before = record["before_m2"]
    assert before["script_errors"] == 0, "a harness error is not a failed test"
    assert before["returncode"] == 1 and before["pass_marker"] is False and before["restored_byte_for_byte"] is True
    assert {"C01", "C02", "C03", "C04", "C06", "C07", "C08", "C09"} <= set(before["failures_by_group"])
    defect = before["the_defect_measured"]
    # The fire read the lower-layer number in every step in which it was another number,
    # while the sink debited the room inventory.
    assert defect["steps"] == 480 and defect["steps_in_which_the_fire_read_the_inventory"] <= 2
    assert defect["steps_in_which_the_lower_number_was_another_number"] > 100
    assert defect["of_those_the_fire_read_the_lower_number_in"] == defect["steps_in_which_the_lower_number_was_another_number"]
    assert defect["debit_of_the_inventory_kg"] > 1.0
    failures = " | ".join(before["first_failures"])
    assert "declared as consumed is the debit, once" in failures, "the double declaration must be among the failures"
    assert "a sealed room that burns is a supported route" in failures


def test_the_acceptance_passes_on_the_real_engine(record):
    acceptance = record["acceptance"]
    assert acceptance["failure_count"] == 0 and acceptance["failures_by_group"] == {}
    assert acceptance["returncode"] == 0 and acceptance["pass_marker"] is True and acceptance["script_errors"] == 0
    assert len(acceptance["groups"]) == GROUPS and acceptance["checks"] >= 100


@pytest.mark.parametrize("case", ["real_fire", "sealed_room"])
def test_one_selection_one_debit_and_the_budgets_close(record, case):
    measured = record["acceptance"]["observations"][case]
    steps = measured["steps"]
    assert steps == 480 and measured["steps_before_a_refusal"] == steps
    # One selection, the same for both consumers, read from the inventory.
    assert measured["selections_read"] and measured["one_per_room_and_step"] and measured["ids_never_repeat"]
    assert measured["fire_was_served"] == steps and measured["fire_reads_the_selection"] == steps
    assert measured["selection_is_the_inventory"] == steps and measured["fire_reads_the_inventory"] == steps
    assert measured["fire_deposit_is_the_room_inventory"] == steps
    assert measured["lower_number_apart"] > 100 and measured["fire_reads_the_lower_number"] == 0
    assert measured["sink_steps"] > 400
    assert measured["sink_was_served_the_same"] == measured["debit_names_the_selection"] == measured["sink_steps"]
    # One debit, the demand of the heat, within what was available.
    assert measured["debits_per_step_at_most_one"] and measured["debit_within_available"] and measured["available_is_the_oracle"]
    assert measured["consumed_kg"] + measured["clipped_kg"] == pytest.approx(0.076 * measured["heat_MJ"], abs=GAP_KG)
    # The three budgets of stage M1, the worst step.
    for key in ("room_gap_kg", "building_gap_kg", "oracle_gap_kg"):
        assert 0.0 <= measured[key] <= GAP_KG, (case, key, measured[key])
    assert measured["lowest_inventory_kg"] >= 0.0 and measured["highest_x"] <= 0.209 + 1.0e-12
    assert measured["number_is_derived"] == steps and measured["blend_apart"] > 100
    assert record["budget_gap_accepted_kg"] == GAP_KG


def test_the_transit_was_exercised_with_the_selection(record):
    measured = record["acceptance"]["observations"]["real_fire"]
    assert measured["largest_transit_kg"] > 1.0e-4 and measured["delayed"] > 0


def test_the_effect_on_the_fire_is_recorded_and_not_hidden(record):
    """Measured against the historical route on the same engine. No criterion of the fire."""
    observations = record["acceptance"]["observations"]
    for case in ("effect two_rooms", "effect sealed_room"):
        off, on = observations[case]["off"], observations[case]["on"]
        assert off["fire_reads"] == "plume_lower" and on["fire_reads"] == "room_inventory"
        assert on["failure"] == "" and on["steps"] == off["steps"] == 1200
        # The historical route declares more than it debits; the mode declares what it debits.
        assert off["declared_as_consumed_kg"] > off["debit_of_the_room_kg"] * 1.2
        assert on["declared_as_consumed_kg"] == pytest.approx(on["debit_of_the_room_kg"], abs=GAP_KG)
        assert on["debit_of_the_room_kg"] + on["clipped_by_the_cap_kg"] == pytest.approx(on["demand_of_the_heat_kg"], abs=1.0e-6)
        assert on["lowest_oxygen_the_fire_read"] == pytest.approx(on["lowest_room_number"], abs=1.0e-12)
    # The change is not small: with one deposit the fire of the two-room case burns less.
    two = observations["effect two_rooms"]
    assert two["on"]["heat_MJ"] < 0.8 * two["off"]["heat_MJ"]
    assert record["against_stage_m1"]["stage_m2"]["heat_MJ"] < record["against_stage_m1"]["stage_m1"]["heat_MJ"]


def test_stage_m1_still_passes_on_this_engine(record):
    again = record["stage_m1_again"]
    assert again["failure_count"] == 0 and again["pass_marker"] is True and again["script_errors"] == 0
    assert len(again["groups"]) == 14 and again["checks"] >= 270
    for case, measured in again["observations"].items():
        for key in ("room_gap_kg", "building_gap_kg", "oracle_gap_kg"):
            if key in measured:
                assert measured[key] <= GAP_KG, (case, key)


def test_the_historical_route_gives_the_figures_it_gave(record):
    historical = record["historical_route"]
    assert historical["identical_figure_by_figure"] is True and historical["differing"] == {}
    assert historical["published_record_rewritten"] is False and len(historical["hypotheses_compared"]) >= 13


# ---------------------------------------------------------------- the mutations

@pytest.mark.parametrize("key,runner,declared_with_the_stage", [
    ("selection_mutations", SELECTION_MUTATIONS, 8), ("inventory_mutations", INVENTORY_MUTATIONS, 8)])
def test_every_mutant_dies_where_it_was_declared(record, key, runner, declared_with_the_stage):
    declared = _load(runner).plan()
    summary = record[key]
    ran = {item["name"]: item for item in summary["results"] if item["name"] != "control"}
    assert set(ran) == set(declared)
    for name, item in declared.items():
        for field in ("file", "defect", "expected_in", "declared_with_the_plan"):
            assert ran[name][field] == item[field], (name, field)
    assert sum(item["declared_with_the_plan"] for item in declared.values()) == declared_with_the_stage
    assert summary["control"] == "pass" and summary["originals_intact"] is True
    assert summary["survivors"] == [] and summary["invalid"] == [] and summary["killed_elsewhere"] == []
    assert summary["declared"] == summary["executed"] == summary["killed"] == summary["killed_where_expected"] == len(declared)
    for item in ran.values():
        assert item["verdict"] == "killed" and item["seen_where_expected"] is True and item["reason"] == "", item["name"]


def test_the_mutation_anchors_still_exist():
    _load(SELECTION_MUTATIONS).prepared()
    _load(INVENTORY_MUTATIONS).prepared()


def test_the_eight_families_asked_for_are_among_the_mutants():
    names = set(_load(SELECTION_MUTATIONS).plan())
    for family in ("sink_rebuilds_the_selection", "fire_is_handed_the_lower_number", "another_deposit_is_debited",
                   "second_declaration_of_consumption", "inventory_rewritten_from_the_layers_in_a_sealed_room",
                   "selection_of_the_previous_step_kept", "selection_of_another_run_accepted", "selection_ignores_the_transit",
                   "historical_route_when_the_selection_is_refused"):
        assert any(family in name for name in names), family
    # The transit left out of the state itself is a mutant of stage M1, still run.
    assert "T01_transit_omitted" in _load(INVENTORY_MUTATIONS).plan()


# ---------------------------------------------------------------- the house cases

@pytest.mark.parametrize("case", HOUSE_CASES)
def test_the_trace_of_the_house_is_passive(record, case):
    off = record["house"]["cases"][case]["off"]
    assert off["mode"] == "off" and off["switch_in_the_scenario"] is False
    assert all(off["identical_to_the_identity_run"].values()), "the oxygen trace must not change any other output"
    assert len(off["identical_to_the_identity_run"]) == 6


@pytest.mark.parametrize("case", HOUSE_CASES)
def test_the_house_with_the_mode_on_is_reported_as_it_came_out(record, case):
    """Refused by the pressure venting of the sealed Salon: not hidden, not simplified."""
    on = record["house"]["cases"][case]["on"]
    budget = on["budget"]
    assert on["mode"] == "on" and on["switch_in_the_scenario"] is True
    refused = budget["refused"]
    assert refused is not None, "if the house runs whole, this test and the report have to say so"
    assert refused["failure"] == "o2_room_inventory_failed" and len(refused["rejections"]) == 1
    assert refused["rejections"][0]["reason"] == "route_not_supported_in_m1"
    assert refused["rejections"][0]["route"] == "pressure_venting"
    assert 60.0 < refused["time_s"] < 120.0 and budget["steps"] > 700
    # Until it was refused: one selection, one debit, and every budget within the gap.
    for key in ("room_gap_kg", "building_gap_kg", "oracle_gap_kg"):
        assert budget[key] <= GAP_KG, (case, key)
    assert budget["rooms_where_the_fire_read_its_selection"] == budget["rooms_consulted"] == 6 * budget["steps"]
    assert budget["debits"] > 0 and budget["debits_on_the_selection_the_fire_read"] == budget["debits"]
    assert budget["more_than_one_debit_in_a_step"] == 0 and budget["selections_missing"] == 0
    assert "contracts" not in on, "C1 and C2 are not judged on a run that did not reach its end"


def test_the_historical_gap_of_the_house_is_measured_and_is_not_its_transit(record):
    """After the door opens the historical house loses oxygen, and its transit does not explain it.

    The queue of pending deliveries, which no other record writes, is measured here. It was
    used and it ends empty: the transport accumulators of the six rooms do not add up to
    zero, and counting the transit leaves the same gap. What was published on 2026-10-09,
    that the gap was compatible with the transit, is refuted by this measurement.
    """
    reopened = record["house"]["cases"]["o2_reopen_300"]["off"]["budget"]
    closed = record["house"]["cases"]["o2_closed"]["off"]["budget"]
    assert closed["largest_number_of_entries"] == 0 and abs(closed["transport_accumulators_of_the_house_kg"]) < 1.0e-6
    assert reopened["largest_number_of_entries"] > 0 and reopened["largest_transit_kg"] > 1.0
    assert reopened["transit_at_the_end_kg"] == 0.0
    assert reopened["transport_accumulators_of_the_house_kg"] == pytest.approx(-0.378, abs=0.001)
    assert reopened["transport_plus_transit_kg"] == reopened["transport_accumulators_of_the_house_kg"]


# ---------------------------------------------------------------- the contract in the code

def test_the_fire_reads_the_selection_before_any_layer_number():
    combustion = _text(COMBUSTION)
    body = combustion.split("func _resolve_fire_o2_selection(", 1)[1].split("\nfunc ", 1)[0]
    asks = body.index('context.get("o2_room_inventory", null)')
    assert asks < body.index("room.o2_upper") and asks < body.index("room.o2_lower")
    branch = body[asks:body.index("\tvar o2_ref: float = room.o2\n")]
    assert 'o2_room_inventory.selection_for(room, "fire")' in branch
    assert '"o2_ref": float(selected["mole_fraction"])' in branch and '"mode": String(selected["deposit"])' in branch
    # Every path of the branch returns: with the mode on nothing falls to the historical route.
    assert branch.rstrip().endswith('return {"mode": "o2_selection_refused", "o2_ref": 0.0, "o2_min_ref": o2_min_ref}')
    assert "o2_lower" not in branch and "o2_upper" not in branch and "room.o2" not in branch
    assert combustion.count("o2_room_inventory") == 4, "the selection is consulted in one place"
    assert _code(COMBUSTION).count("selection_for(") == 1


def test_only_the_owner_builds_a_selection_and_the_sink_presents_the_one_it_was_served():
    owner = _code(OWNER)
    assert owner.count("_select_for_step()") == 4, "defined, and called when arming, when a start is declared and when a step opens"
    for path in (OXYGEN, COMBUSTION, ENGINE, ROOT / "sim/core/GasExchangeSystem.gd", ROOT / "sim/building/RoomModel.gd"):
        assert "_select_for_step" not in _text(path), path.name
        assert "_selections" not in _text(path), path.name
    oxygen = _text(OXYGEN)
    owned = oxygen.split("func _step_owned_room_inventory(", 1)[1].split("\nfunc ", 1)[0]
    assert owned.count('room_o2_inventory.selection_for(room, "sink")') == 1
    assert owned.index("selection_for(room") < owned.index("room_o2_inventory.consume(")
    assert 'room, selection, requested, consumed, "fire_sink_room_inventory"' in owned
    assert "sink_leaves_the_room_inventory" not in oxygen and "fire_sink_outside_the_room_inventory" not in oxygen
    # The selection comes from the inventory and names the only deposit there is.
    build = _text(OWNER).split("func _select_for_step() -> void:", 1)[1].split("\nfunc ", 1)[0]
    assert "var held_kg: float = room.o2_inventory_kg" in build and '"deposit": DEPOSIT_ROOM_INVENTORY' in build
    assert '"mole_fraction": mole_fraction_from_o2_kg(held_kg, room.volume_m3())' in build
    assert '"available_kg": maxf(0.0, held_kg - owed_kg)' in build


def test_a_debit_is_refused_unless_it_names_the_selection_of_its_room_step_and_run():
    owner = _text(OWNER)
    check = owner.split("func _selection_error(", 1)[1].split("\nfunc ", 1)[0]
    for reason in ("debit_without_a_selection", "selection_of_another_run", "selection_of_another_room",
                   "no_selection_for_this_step", "selection_of_another_step", "selection_of_another_deposit",
                   "selection_already_debited"):
        assert f'return "{reason}"' in check, reason
    consume = owner.split("func consume(", 1)[1].split("\nfunc ", 1)[0]
    assert consume.index("_selection_error(room, selection)") < consume.index("_commit(room, after_kg)")


def test_the_writes_on_the_layer_numbers_are_not_declared_as_consumption_with_the_mode_on():
    oxygen = _text(OXYGEN)
    assert ("\t\t\tif room_o2_inventory == null:\n\t\t\t\troom.o2_consumed_kg_step_all += upper_consumed\n"
            "\t\t\t\troom.o2_consumed_kg_total_all += upper_consumed\n") in oxygen
    assert ("\t\t\t\tif room_o2_inventory == null:\n\t\t\t\t\troom.o2_consumed_kg_step_all += plume_consumed\n"
            "\t\t\t\t\troom.o2_consumed_kg_total_all += plume_consumed\n") in oxygen
    assert "\t\t\t\t\t_o2_fire_primary = plume_consumed\n" in oxygen
    # And no layer number rewrites the room: the guard of stage M1 is still there.
    assert "if (effective_plume_lower or _phase2b_upper_active) and room_o2_inventory == null:" in oxygen
    # The word the stage was told not to use for what is left of that write.
    for path in (OXYGEN, OWNER, COMBUSTION):
        added = [line for line in _text(path).splitlines() if "G3 M2" in line or "M2:" in line]
        assert not any("desplazamiento" in line.lower() or "displacement" in line.lower() for line in added), path.name


def test_the_engine_hands_the_owner_to_the_fire_only_with_the_mode_armed():
    engine = _text(ENGINE)
    assert ('\tif oxygen_exchange_system.room_o2_inventory != null:\n'
            '\t\tcontext["o2_room_inventory"] = oxygen_exchange_system.room_o2_inventory\n') in engine
    assert engine.count('context["o2_room_inventory"]') == 1
    assert "\nvar o2_room_inventory_enabled: bool = false\n" in engine and "@export var o2_room_inventory" not in engine


def test_the_trace_of_the_runner_is_passive_and_raises_no_switch():
    tool = _text(RUNNER_TOOL)
    assert 'if not bool(_cli_args.get("o2_inventory_trace", false)):\n\t\treturn {}' in tool
    assert "o2_room_inventory_enabled" not in tool
    trace = tool.split("func _o2_inventory_trace_before(", 1)[1].split("\nfunc _open_fuel_source_ledger", 1)[0]
    assert not re.search(r"\bengine\.\w+\s*=[^=]", trace), "the trace sets nothing on the engine"
    assert not re.search(r"\broom\.\w+\s*(=|\+=|-=)[^=]", trace), "nor on a room"


# ---------------------------------------------------------------- the fixture

ALLOWED_ENGINE_SETTINGS = {
    "building", "auto_ignite_on_ready", "auto_finish_on_extinction", "enable_logging", "enable_csv_log", "sim_fixed_dt",
    "pressure_network_solver_enabled", "g3_prescribed_thermal_source_enabled", "fire_o2_mode",
    "fire_o2_upper_hrr_blend", "fire_o2_upper_throttle_enabled",
}


def test_the_fixture_sets_only_what_it_declares_and_takes_its_oracle_from_itself():
    fixture = _text(FIXTURE)
    assert set(re.findall(r"\bengine\.(\w+)\s*=[^=]", fixture)) <= ALLOWED_ENGINE_SETTINGS
    assert fixture.count('engine.set("o2_room_inventory_enabled", value)') == 1
    for forbidden in ("two_zone_solver_enabled", "FileAccess.open", "RoomOxygenInventory.gd", "PrescribedThermalSourceCoupling",
                      "g3_prescribed_thermal_source_case", "ach_infiltration ="):
        assert forbidden not in fixture, forbidden
    assert "const GAP_KG: float = 1.0e-9" in fixture
    oracle = fixture.split("# ---------------------------------------------------------------- oracle", 1)[1].split("# -----", 1)[0]
    assert "inv." not in oracle and "_inv(" not in oracle, "the oracle never calls the owner"
    assert 'print("G3_O2_SELECTION_PASS")' in fixture and "quit(1)" in fixture
    assert 'OS.get_environment("G3_O2_SELECTION_JUDGED_ONLY") != "1"' in fixture


# ---------------------------------------------------------------- documents

REQUIRED = (
    "una selección por recinto y paso", "kg de O₂", "fracción molar", "inventario de sala", "disponible",
    "auxiliares históricos", "no se declara", "pressure_venting", "No se ha desactivado", "M3", "M4",
    "CO y FED siguen OFF/NO-GO", "G3_O2_SELECTION_M2_2026-10-10.json", "G3_O2_ROOM_INVENTORY_M0_M1_2026-10-10.md",
    "Orden real", "Efecto físico", "Lo que no se ha ejecutado", "Alcance mínimo adicional",
)


def test_the_report_says_what_was_built_what_it_changes_and_what_stopped_it(record):
    report = _text(REPORT)
    for phrase in REQUIRED:
        assert phrase in report, phrase
    assert f"{record['acceptance']['checks']} comprobaciones" in report
    assert f"{record['before_m2']['failure_count']} fallos" in report
    assert f"{record['selection_mutations']['declared']} mutantes" in report
    for name in ("S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08"):
        assert name in report, name
    assert "@@" not in report, "a placeholder was left in the report"


@pytest.mark.parametrize("relative", [
    "docs/HANDOFF_CURRENT_STATE.md", "docs/validation/G3_O2_AUTHORITY_2026-10-09.md",
    "docs/validation/G3_O2_ROOM_INVENTORY_M0_M1_2026-10-10.md",
    "docs/planning/G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md", "docs/validation/CONTRATO_O2_2026-09-24.md",
])
def test_the_report_is_linked_from_the_documents_that_must_know(relative):
    assert "G3_O2_SELECTION_M2_2026-10-10.md" in _text(ROOT / relative), relative
