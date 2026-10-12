"""Historical diagnosis and offline contract of stage M3 of the oxygen authority.

Three kinds of test, none of which launches anything:

* the ROUTE: the order in which the engine proposes a power, filters it, debits fuel,
  generates products and debits oxygen, at ENGINE_OF, before M3. Live integration is judged separately by
  test_g3_m3_integration_contract.py and its Godot fixture;
* the DIAGNOSIS: the record written by ``scripts/simulation/run_g3_o2_m3_diagnosis.py``
  on the real engine with the room oxygen inventory on, with what it measured;
* the CONTRACT: its offline oracle, ``scripts/simulation/g3_m3_contract_model.py``. The
  reference transaction breaks none of the invariants and every declared defect breaks
  the one it was declared against. That is not a validation of the engine: it shows the
  invariants are written without ambiguity and can be failed.

Closing the oxygen and the heat validates neither the distribution of the oxygen nor
CO nor FED, and nothing here says it does.
"""

from __future__ import annotations

from functools import lru_cache
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]
RECORD = ROOT / "docs" / "validation" / "G3_O2_M3_CONTRACT_DIAGNOSIS_2026-10-11.json"
REPORT = ROOT / "docs" / "validation" / "G3_O2_M3_CONTRACT_2026-10-11.md"
FIXTURE = ROOT / "tests" / "fixtures" / "g3_o2_m3_diagnosis.gd"
RUNNER = ROOT / "scripts" / "simulation" / "run_g3_o2_m3_diagnosis.py"
MODEL = ROOT / "scripts" / "simulation" / "g3_m3_contract_model.py"
COMBUSTION = ROOT / "sim" / "fire" / "CombustionSystem.gd"
ENGINE = ROOT / "sim" / "core" / "SimulationEngine.gd"
OXYGEN = ROOT / "sim" / "core" / "OxygenExchangeSystem.gd"
THERMAL = ROOT / "sim" / "core" / "ThermalSystem.gd"
OWNER = ROOT / "sim" / "core" / "RoomOxygenInventory.gd"
# The commit whose engine the diagnosis measured. Stage M3 will change these files; this
# contract is of the engine before it.
ENGINE_OF = "cefae4ec"
K = 0.076


def _load(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[path.stem] = module
    spec.loader.exec_module(module)
    return module


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _prose(path: Path) -> str:
    """A document with its line breaks taken out: a phrase may be wrapped anywhere."""
    return " ".join(_text(path).split())


def _body(path: Path, name: str) -> str:
    return _text(path).split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


@lru_cache(maxsize=None)
def _historical_text(path: Path) -> str:
    """The route measured by the published diagnosis, not today's M3 branch."""
    relative = path.relative_to(ROOT).as_posix()
    result = subprocess.run(["git", "show", f"{ENGINE_OF}:{relative}"],
                            cwd=ROOT, capture_output=True, check=True)
    return result.stdout.decode("utf-8").replace("\r\n", "\n")


def _historical_body(path: Path, name: str) -> str:
    return _historical_text(path).split(f"func {name}(", 1)[1].split("\nfunc ", 1)[0]


def _in_order(text: str, anchors: list[str]) -> None:
    position = -1
    for anchor in anchors:
        assert text.count(anchor) >= 1, f"not found: {anchor}"
        found = text.index(anchor, position + 1) if anchor in text[position + 1:] else -1
        assert found > position, f"out of order, or only earlier: {anchor}"
        position = found


@pytest.fixture(scope="module")
def record() -> dict:
    return json.loads(RECORD.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def model():
    return _load(MODEL)


# ---------------------------------------------------------------- the route, as the contract describes it

def test_the_step_of_the_engine_runs_in_the_order_the_contract_describes():
    step = _historical_body(ENGINE, "step")
    _in_order(step, [
        "_o2_room_inventory.begin_step(_o2_room_inventory_environment())",
        "\t_step_pool_fires(dt)",
        "\t_step_fire(dt)",
        "\t_step_co_oxidation(dt)",
        "\tif not pre_hrr_o2_step:\n\t\t_step_oxygen(dt)",
        "\tthermal_system.step(building, dt, {",
        "\t_step_suppression(dt)",
        "\t_step_gas_exchange(dt)",
        "\t_clamp_rooms(dt)",
        "\t\t_o2_room_inventory.audit_room_numbers()",
    ])


def test_the_flashover_multiplies_the_power_after_the_fire_step_has_debited_fuel():
    fire_step = _historical_body(ENGINE, "_step_fire")
    _in_order(fire_step, ["combustion_system.step_room_fire(", "_try_trigger_flashover(room)"])
    assert _historical_text(ENGINE).count("room.hrr_kw *= room.fire.flashover_hrr_multiplier") == 1
    # And the suppression scales it after the thermal step has read it.
    assert _historical_text(ENGINE).count("\troom.hrr_kw *= hrr_factor\n") == 1


def test_the_fire_filters_its_power_before_it_debits_fuel_and_after_it_proposes():
    fire = _historical_body(COMBUSTION, "step_room_fire")
    _in_order(fire, [
        "var o2_selection: Dictionary = _resolve_fire_o2_selection(room, fire, context)",
        "room.o2_hrr_factor = _smooth_state_value(",
        "var solid_fuel_demand_MJ: float = solid_pyrolysis_kw * dt / 1000.0",
        # The pool is credited before the power of the step is known.
        "room.retained_unburned_MJ = minf(\n\t\tpool_capacity_MJ,",
        "room.hrr_target_kw = fresh_flame_target_kw + smolder_target_kw + pool_release_target_kw",
        "room.hrr_kw = _smooth_state_value(\n\t\tprevious_hrr_kw,\n\t\troom.hrr_target_kw,",
        "room.hrr_kw = maxf(room.hrr_kw, bd_hrr_kw)",
        "_apply_selected_o2_extinction_guard(room)",
        "var actual_pool_burn_kw: float = room.hrr_kw * pool_release_target_kw / total_target_kw",
        "room.smoke_prod_kg_s = _compute_smoke_production_kg_s(smoke_basis_kw, smoke_yield_kg_per_MJ)",
        # A step can end here, extinguished, after the power was set and before anything below is written.
        "return _extinguish_room_fire(room, fire)",
        "var generated_co_kg: float = co_yield * co_basis_MJ",
        "_apply_species_generation_result(room, species_generation_result)",
        "fire.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ - solid_fuel_demand_MJ)",
        "room.hrr_kj_total += maxf(0.0, room.hrr_kw) * dt",
    ])


def test_heat_fuel_and_products_are_not_written_from_one_quantity():
    """Why one fraction has to be imposed on the step: today each follows something else."""
    fire = _historical_body(COMBUSTION, "step_room_fire")
    # Fuel: the pyrolysis the fire aims at in this step. Not the power it kept.
    assert "fire.remaining_fuel_MJ = maxf(0.0, fire.remaining_fuel_MJ - solid_fuel_demand_MJ)" in fire
    assert "solid_fuel_demand_MJ = solid_pyrolysis_kw * dt / 1000.0" in fire
    # Smoke: the larger of the power kept and the targets.
    assert "var smoke_basis_kw: float = maxf(\n\t\tactual_solid_burn_kw,\n\t\t(fresh_flame_target_kw + smolder_target_kw) * smoke_basis_multiplier\n\t)" in fire
    # CO: the power kept, plus terms of the pool.
    assert "var co_basis_kw: float = actual_solid_burn_kw + pool_co_basis_kw + retained_co_basis_kw" in fire
    # CO2: the larger of the heat and a share of the smoke basis.
    assert "var generated_co2_kg: float = co2_yield * maxf(heat_release_MJ, smoke_basis_MJ * 0.60)" in fire
    # The carbon ceiling: the fuel debited.
    assert "var c_avail_kg: float = solid_fuel_demand_MJ * c_per_MJ" in fire
    # The pool: what the fire aims at and does not burn, credited before the filter.
    assert "var retained_generation_kw: float = maxf(\n\t\t0.0,\n\t\tsolid_pyrolysis_kw - fresh_flame_target_kw - smolder_target_kw\n\t) * float(context.get(\"fire_unburned_generation_fraction\", 0.30))" in fire


def test_the_sink_debits_after_the_arrivals_and_before_the_exchange_between_rooms_and_clips_at_five_percent():
    step = _historical_body(OXYGEN, "step")
    _in_order(step, ["_deliver_owned_o2_transit(building, dt)",
                     "_step_owned_room_inventory(building, room, dt, air_density_kg_m3)",
                     "\tfor op in building.get_openings():"])
    sink = _historical_body(OXYGEN, "_step_owned_room_inventory")
    assert "var requested: float = (room.hrr_kw / 1000.0) * _fire_sink_kg_per_MJ(room) * dt" in sink
    assert "requested, room_o2_inventory.inventory_kg(room) * FIRE_SINK_BULK_CAP_FRACTION" in sink
    assert "const FIRE_SINK_BULK_CAP_FRACTION: float = 0.05" in _historical_text(OXYGEN)
    # Nothing in the sink looks at the power again: what it clips stays accepted.
    after_the_cap = sink.split("FIRE_SINK_BULK_CAP_FRACTION", 1)[1]
    assert "hrr_kw =" not in after_the_cap and "hrr_kw *=" not in after_the_cap


def test_the_heat_the_thermal_step_deposits_is_the_power_of_the_room_at_that_moment():
    thermal = _historical_text(THERMAL)
    assert "var convective_energy_kj: float = room.hrr_kw * conv_fraction * dt" in thermal
    assert "var q_rad_fire_kj: float = room.hrr_kw * chi_rad * dt" in thermal


def test_the_selection_says_what_is_available_and_nothing_acts_on_it_yet():
    owner = _historical_text(OWNER)
    assert '"available_kg": maxf(0.0, held_kg - owed_kg)' in owner
    consume = _historical_body(OWNER, "consume")
    assert "available" not in consume.split("_commit(room, after_kg)", 1)[0].replace("available_at_selection_kg", ""), \
        "stage M3 is not implemented: the debit does not look at what is available"
    assert "if applied > before_kg:" in consume


def test_stage_m3_was_not_in_the_diagnosed_engine(record):
    assert all(record["engine"]["files_equal_to_that_commit"].values())
    assert record["engine"]["commit"] == ENGINE_OF
    for relative, digest in record["engine"]["sha256"].items():
        blob = subprocess.run(["git", "show", f"{ENGINE_OF}:{relative}"], cwd=ROOT, capture_output=True)
        if blob.returncode != 0:
            pytest.skip("the history of the repository is not available")
        assert hashlib.sha256(blob.stdout.replace(b"\r\n", b"\n")).hexdigest() == digest, relative


# ---------------------------------------------------------------- the offline oracle

def test_the_reference_transaction_breaks_no_invariant(model):
    assert model.broken_by() == {}
    assert set(model.scenarios()) == {"fits", "runs_out", "drop_with_power_high", "pending_arrival", "obligation", "refused", "coarse_step"}


def test_the_reference_limits_only_where_the_oxygen_runs_short(model):
    fits = model.run(model.scenarios()["fits"])
    assert all(record["fraction"] == 1.0 for record in fits)
    short = model.run(model.scenarios()["runs_out"])
    assert any(0.0 < record["fraction"] < 1.0 for record in short) and short[-1]["heat_MJ"] == 0.0
    # All the oxygen of the room was burned and none that was not there.
    assert sum(record["heat_MJ"] for record in short) == pytest.approx(0.6 / K, abs=1.0e-9)
    assert short[-1]["inventory_kg"] == pytest.approx(0.0, abs=1.0e-12)


def test_every_declared_defect_breaks_the_invariant_it_was_declared_against(model):
    assert len(model.DECLARED_DEFECTS) == 11
    for defect, invariant in model.DECLARED_DEFECTS.items():
        broken = model.broken_by(defect)
        assert invariant in model.INVARIANTS, invariant
        assert invariant in broken, f"{defect} was declared against {invariant} and breaks {sorted(broken)}"


def test_the_nine_families_asked_for_are_among_the_declared_defects(model):
    asked = ("limit_only_before_the_filter", "heat_accepted_above_the_backed", "fuel_and_products_from_the_refused_proposal",
             "pending_arrival_spent", "obligation_ignored", "second_decision_on_the_same_oxygen", "late_debit_clipped",
             "stale_selection", "partial_write_on_refusal")
    assert tuple(name.split("_", 1)[1] for name in list(model.DECLARED_DEFECTS)[:9]) == asked


def test_every_invariant_can_be_failed(model):
    """An invariant no defect breaks would be a sentence, not a check."""
    reachable = set()
    for defect in model.DECLARED_DEFECTS:
        reachable |= set(model.broken_by(defect))
    # The budget of the building has no declared defect of its own: a record that loses oxygen is made by hand.
    record = model.run(model.scenarios()["fits"])[10]
    record["inventory_kg"] -= 0.001
    assert "I8_building_budget_with_transit" in model.violated(record)
    assert reachable | {"I8_building_budget_with_transit"} == set(model.INVARIANTS)


def test_a_pending_arrival_is_not_spent_and_an_obligation_is_kept(model):
    pending = model.run(model.scenarios()["pending_arrival"])
    # Before the kilogram arrives the room burns what it holds and no more; afterwards it burns again.
    before = [record for record in pending if record["index"] < 40]
    assert sum(sum(item["kg"] for item in record["debits"]) for record in before) == pytest.approx(0.05, abs=1.0e-12)
    assert pending[45]["heat_MJ"] > 0.0
    owing = model.run(model.scenarios()["obligation"])
    assert min(record["lowest_inventory_kg"] for record in owing) >= -1.0e-12
    assert sum(sum(item["kg"] for item in record["debits"]) for record in owing if record["index"] < 120) == pytest.approx(0.1, abs=1.0e-9)


def test_the_five_percent_per_step_depends_on_the_time_step_and_availability_alone_does_not(model):
    """Algebra, not a run of the engine: a demand larger than the inventory, 10 s."""
    inventory, seconds = 13.3, 10.0
    with_cap = {dt: model.burned_until_it_runs_out(inventory, 1.0e6, dt, seconds, cap=True) for dt in (2.0, 1.0, 0.5, 0.25)}
    for dt, heat in with_cap.items():
        assert heat == pytest.approx(model.cap_closed_form(inventory, dt, seconds), rel=1.0e-12)
    # The same fire, the same ten seconds: 23 % of the oxygen at 2 s per step, 87 % at 0.25 s.
    assert with_cap[2.0] * K / inventory == pytest.approx(1.0 - 0.95 ** 5, rel=1.0e-12)
    assert with_cap[0.25] * K / inventory == pytest.approx(1.0 - 0.95 ** 40, rel=1.0e-12)
    assert with_cap[0.25] > 3.8 * with_cap[2.0]
    alone = {dt: model.burned_until_it_runs_out(inventory, 1.0e6, dt, seconds, cap=False) for dt in (2.0, 1.0, 0.5, 0.25)}
    for heat in alone.values():
        assert heat == pytest.approx(inventory / K, rel=1.0e-12)


def test_the_model_takes_nothing_from_the_engine():
    source = _text(MODEL)
    for word in ("godot", "sim/", "res://", "import subprocess", "RoomOxygenInventory"):
        assert word not in source, word
    assert "K_KG_PER_MJ = 0.076" in source and "TOL_KG = 1.0e-9" in source


# ---------------------------------------------------------------- the diagnosis, as it came out

PLAIN = ("fits", "stress dt 2.0", "stress dt 1.0", "stress dt 0.5", "stress dt 0.25", "small room dt 2.0", "small room dt 1.0",
         "small room dt 0.5", "small room dt 0.25", "prescribed", "end of fuel")
WITH_AN_OPERATION = ("drop to below the flame limit", "drop that keeps the flame", "pending arrival", "obligation",
                     "obligation with the door closed")


def test_the_fixture_measures_and_does_not_judge(record):
    fixture = _text(FIXTURE)
    assert "_PASS" not in fixture and "quit(1)" not in fixture and "_check(" not in fixture
    assert record["fixture"]["judges"] is False and record["fixture"]["script_errors"] == 0 and record["fixture"]["returncode"] == 0
    assert hashlib.sha256(FIXTURE.read_bytes().replace(b"\r\n", b"\n")).hexdigest() == record["fixture"]["sha256"], \
        "the fixture changed after the record was written: run the diagnosis again"
    # It raises the mode and, in one case, the engine's own switch of the prescribed fire. Nothing else of the fire.
    assert fixture.count('engine.set("o2_room_inventory_enabled", true)') == 1
    assert fixture.count("engine.fire_o2_independent = true") == 1
    assert set(record["controls"]) == set(PLAIN) | set(WITH_AN_OPERATION)


def test_with_the_mode_on_no_control_left_heat_without_its_debit(record):
    """Not what the controls were designed to show: the cap of the sink never acted through the route of the fire."""
    for name, item in record["controls"].items():
        assert item["heat"]["not_backed_MJ"] == 0.0 and item["oxygen"]["clipped_by_the_cap_kg"] == 0.0, name
        assert item["oxygen"]["steps_with_a_clip"] == 0 and item["oxygen"]["more_than_one_debit_in_a_step"] == 0, name
        assert item["heat"]["backed_by_the_debit_MJ"] == pytest.approx(item["heat"]["the_sink_was_asked_to_back_MJ"], abs=1.0e-9), name
        assert item["flashover"] is False, f"{name}: no control was expected to reach flashover; the report says none did"
    for name in PLAIN:
        item = record["controls"][name]
        assert item["failure"] == "" and item["injected"] == {}, name
        assert item["availability_at_the_opening_of_the_step"]["debited_above_it_kg"] == 0, name
        # The largest part of what was available that one step asked for stays under the 5 % of the cap.
        assert 0.0 < item["largest_share_of_the_available_asked_in_a_step"] < 0.05, name
    assert 0.04 < record["controls"]["small room dt 2.0"]["largest_share_of_the_available_asked_in_a_step"] < 0.05


def test_the_tail_of_the_filter_is_heat_above_the_target_and_above_the_fuel(record):
    fits = record["controls"]["fits"]
    assert fits["filter"]["steps_with_power_above_the_target"] > 100 and fits["filter"]["heat_above_the_target_MJ"] > 5.0
    assert fits["fuel_and_products"]["heat_above_the_fuel_of_its_step_MJ"] > 5.0
    # With the fuel gone the heat released is more than the fuel had.
    burnout = record["controls"]["end of fuel"]
    assert burnout["fuel_and_products"]["fuel_debited_MJ"] == pytest.approx(40.0, abs=1.0e-3)
    assert burnout["heat"]["the_sink_was_asked_to_back_MJ"] > burnout["fuel_and_products"]["fuel_debited_MJ"] + 5.0


def test_heat_fuel_and_products_of_a_step_are_not_proportional(record):
    per = record["controls"]["fits"]["fuel_and_products"]["per_step"]
    assert per["fuel_MJ_per_MJ_of_heat"]["highest"] > 2.0 * per["fuel_MJ_per_MJ_of_heat"]["lowest"]
    assert per["smoke_g_per_MJ_of_heat"]["highest"] > 2.0 * per["smoke_g_per_MJ_of_heat"]["lowest"]


def test_the_prescribed_fire_is_not_independent_of_the_oxygen(record):
    prescribed, fits = record["controls"]["prescribed"], record["controls"]["fits"]
    assert prescribed["heat"]["the_sink_was_asked_to_back_MJ"] < 100.0, "a fire of 700 kW that ignored the oxygen would release far more in 600 s"
    assert prescribed["fuel_and_products"]["fuel_minus_heat_MJ"] > 150.0 > fits["fuel_and_products"]["fuel_minus_heat_MJ"]
    assert prescribed["oxygen"]["lowest_mole_fraction_of_the_room"] < 0.122 < record["controls"]["fits"]["oxygen"]["lowest_mole_fraction_of_the_room"]


def test_an_obligation_the_fire_does_not_see_stops_the_run(record):
    """The one failure the real route produced: the room burns oxygen it owes, and what it owes arrives."""
    closed = record["controls"]["obligation with the door closed"]
    rule = closed["availability_at_the_opening_of_the_step"]
    assert closed["failure"] == "o2_room_inventory_failed" and len(closed["rejections"]) == 1
    assert closed["rejections"][0]["reason"] == "arrival_leaves_a_negative_inventory" and closed["time_s"] == pytest.approx(101.0)
    assert closed["injected"]["answer"]["applied"] is True and closed["injected"]["answer"]["delayed"] is True
    assert rule["steps_debited_above_it"] == 1 and rule["debited_above_it_kg"] > 0.0
    assert rule["debited_while_the_room_owed_kg"] == pytest.approx(0.0211, abs=0.0005)
    # The fire read a concentration that held a flame while there was not oxygen to spend.
    assert rule["steps_in_which_the_fire_reads_enough_oxygen_for_a_flame_and_the_rule_would_refuse"] == 1
    assert closed["mole_fraction_the_fire_read_in_its_last_step_with_a_debit"] > 0.19
    # With the door open the neighbour gives the oxygen back before it is due: nothing breaks.
    opened = record["controls"]["obligation"]
    assert opened["failure"] == "" and opened["availability_at_the_opening_of_the_step"]["debited_above_it_kg"] == 0
    assert opened["availability_at_the_opening_of_the_step"]["debited_while_the_room_owed_kg"] > 1.0


def test_leaving_the_arrivals_of_the_step_out_cost_nothing_in_what_was_measured(record):
    pending = record["controls"]["pending arrival"]
    assert pending["oxygen"]["largest_pending_arrival_kg"] == pytest.approx(1.0)
    for name, item in record["controls"].items():
        assert item["availability_at_the_opening_of_the_step"]["what_leaving_those_arrivals_out_costs_kg"] == 0.0, name


def test_the_fire_depends_on_the_time_step_without_the_cap(record):
    table = record["two_rooms_against_the_time_step"]
    assert set(table) == {"2.0", "1.0", "0.5", "0.25"} == set(record["small_room_against_the_time_step"])
    assert all(item["clipped_kg"] == 0.0 for item in table.values())
    assert abs(table["2.0"]["heat_MJ"] - table["0.25"]["heat_MJ"]) > 0.04 * table["0.25"]["heat_MJ"]


@pytest.mark.parametrize("case", ["o2_closed", "o2_reopen_300"])
def test_in_the_houses_the_room_that_burns_is_clean_and_m3_would_change_nothing(record, case):
    house = record["house"][case]
    room = house["room_that_burns"]
    assert house["whole"] is True and house["steps"] == 10800 and house["refused"] is None
    assert room["clipped_by_the_cap_kg"] == 0.0 and room["a_rule_without_cap_would_refuse_kg"] == 0.0
    assert room["steps_in_which_it_is_richer_than_the_outside"] == 0 and room["steps_in_which_it_owes_in_transit"] == 0
    assert room["steps_with_a_positive_arrival_due"] == 0 and room["steps_debited_above_the_available"] == 0
    assert room["largest_share_of_the_available_asked_in_a_step"] < 0.001


def test_the_stress_case_runs_whole_with_the_mode_on_and_is_not_simplified(record):
    stress = record["stress"]
    assert stress["run"] is True and stress["whole"] is True and stress["refused"] is None and stress["launch_error"] == ""
    assert stress["switch_in_the_scenario"] is True and stress["step_s"] == 2.0 and stress["steps"] == 300
    room = stress["room_that_burns"]
    assert room["clipped_by_the_cap_kg"] == 0.0 and room["applied_kg"] == pytest.approx(room["requested_kg"], abs=1.0e-9)
    assert room["steps_in_which_it_owes_in_transit"] == 0 and room["steps_in_which_it_is_richer_than_the_outside"] == 0
    assert room["largest_share_of_the_available_asked_in_a_step"] < 0.05
    # The object is of 3 MW; reading the oxygen it debits, the fire does not get there.
    assert stress["fire"]["peak_kw"] < 1500.0


def test_o2_3_is_still_open():
    contract = _text(ROOT / "tests" / "test_oxygen_contract.py")
    marker = '@pytest.mark.xfail(strict=True, reason="O2-3: el tope recorta el sumidero sin tocar el HRR")\n' \
             "def test_the_bulk_cap_reduces_the_accepted_combustion_in_the_same_transaction():"
    assert marker in contract, "stage M3 is not implemented: the expected failure of O2-3 must stay"


# ---------------------------------------------------------------- documents

REQUIRED = (
    "M3 no está implementado", "Ruta real", "Diagnóstico de O2-3", "Atribución", "Contrato de disponibilidad",
    "Calor, filtros y transacción", "Decisión sobre el tope del 5 %", "Alcance físico y transporte pendiente",
    "Contrato verificable", "Mutantes que tendrá que matar la implementación", "Decisión para implementar",
    "GO, acotado", "NO-GO", "reserva", "disponible = máx(0, M − obligaciones)", "0,076 kg/MJ", "regla histórica",
    "No es una validación del motor", "CO y FED siguen OFF/NO-GO", "Lo que no se ha ejecutado",
    "G3_O2_M3_CONTRACT_DIAGNOSIS_2026-10-11.json", "g3_m3_contract_model.py",
)


def test_the_contract_says_where_the_decision_is_what_was_measured_and_what_is_not_authorised(record, model):
    report = _prose(REPORT)
    for phrase in REQUIRED:
        assert phrase in report, phrase
    assert f"{len(record['controls'])} controles" in report
    for defect in model.DECLARED_DEFECTS:
        assert f"| {defect.split('_')[0]} |" in report, defect
    for number in range(1, 14):
        assert f"| I{number} |" in report, number
    assert "@@" not in report, "a figure of the verification is still to be written"


@pytest.mark.parametrize("relative", [
    "docs/HANDOFF_CURRENT_STATE.md", "docs/planning/G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md",
    "docs/validation/CONTRATO_O2_2026-09-24.md",
])
def test_the_contract_is_linked_from_the_documents_that_must_know(relative):
    assert "G3_O2_M3_CONTRACT_2026-10-11.md" in _text(ROOT / relative), relative
