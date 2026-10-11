"""The two oxygen limits of the Test016 thermal coupling bench: diagnosis and correction.

1. The second write on the upper-layer oxygen number: the same equivalent demand written
   again on an overlapping number, not a second consumption. It is traced apart and never
   added to the contracted debit.
2. A rejected interval: the bench asks the engine sink which inventory it would debit BEFORE
   it writes the power, so a rejected interval leaves no oxygen write of the source.

These tests are offline. They read the two recorded diagnostic runs, the one of the bench
as published in 1a39332a and the one of the corrected bench, and the code. The behaviour
on the real engine is judged by the fixture of tests/test_g3_object_hrr_thermal_coupling.py.
The bench stays a diagnostic bench: energy and an equivalent oxygen demand, no combustion
of the object, no species, CO and FED not evaluated.
"""

from __future__ import annotations

import json
from pathlib import Path
import re

from scripts.simulation import run_g3_object_hrr_oxygen_diagnosis as diagnosis

ROOT = Path(__file__).resolve().parents[1]
VALIDATION = ROOT / "docs" / "validation"
BEFORE = json.loads((VALIDATION / "G3_OBJECT_HRR_OXYGEN_DIAGNOSIS_BEFORE_2026-10-09.json").read_text(encoding="utf-8"))
AFTER = json.loads((VALIDATION / "G3_OBJECT_HRR_OXYGEN_DIAGNOSIS_AFTER_2026-10-09.json").read_text(encoding="utf-8"))
OXYGEN = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
ENGINE = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
COUPLING = (ROOT / "sim/fire/PrescribedThermalSourceCoupling.gd").read_text(encoding="utf-8")
REPORT = VALIDATION / "G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md"
CONTRACTED_KG = 115093.655 / 1000.0 * 0.076


def _code(text: str) -> str:
    return "\n".join(line.split("#")[0] for line in text.splitlines())


def _body(text: str, signature: str) -> str:
    start = text.index(signature)
    following = text.find("\nfunc ", start + 1)
    return text[start:following if following > 0 else len(text)]


def _flat(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("\\\n", " "))


def _holds(record: dict) -> dict[str, bool]:
    return {name: bool(item["holds"]) for name, item in record["hypotheses"].items()}


# ---------------------------------------------------------------- the causal campaign

def test_every_hypothesis_was_written_with_what_confirms_and_what_refutes_it() -> None:
    assert len(diagnosis.HYPOTHESES) == 11
    for name, item in diagnosis.HYPOTHESES.items():
        assert set(item) == {"discriminates", "confirms", "refutes"}, name
        assert all(len(item[key]) > 10 for key in item), name
    assert set(diagnosis.EXPECTED) == {"before", "after"}
    for label in diagnosis.EXPECTED:
        assert set(diagnosis.EXPECTED[label]) == set(diagnosis.HYPOTHESES)
    # The same predicates judge both runs; what must change is declared, and it is only this.
    changed = sorted(name[:2] for name in diagnosis.HYPOTHESES
                     if diagnosis.EXPECTED["before"][name] != diagnosis.EXPECTED["after"][name])
    assert changed == ["B2", "B3", "B4"]


def test_the_recorded_runs_are_the_published_bench_and_the_corrected_one() -> None:
    assert BEFORE["label"] == "before" and BEFORE["head"] == "1a39332a"
    assert AFTER["label"] == "after" and AFTER["as_expected"] is True
    assert _holds(BEFORE) == diagnosis.EXPECTED["before"]
    assert _holds(AFTER) == diagnosis.EXPECTED["after"]
    # The recorded verdicts are the ones the committed predicates give on the recorded cases.
    for record in (BEFORE, AFTER):
        again = diagnosis.evaluate(record["cases"])
        assert {name: bool(item["holds"]) for name, item in again.items()} == _holds(record)
    coupling = "sim/fire/PrescribedThermalSourceCoupling.gd"
    assert BEFORE["sources_sha256"][coupling] != AFTER["sources_sha256"][coupling]


def test_before_the_correction_a_rejected_interval_left_oxygen_written() -> None:
    """The defect, on the published bench: a behaviour, not an order of calls."""
    for name in ("sealed_dt_2.5", "sealed_dt_1.0"):
        case = BEFORE["cases"][name]
        assert case["state"] == "outside_declared_regime" and case["accepted_kj"] == 0.0 and case["to_the_gas_kj"] == 0.0
        assert case["steps_whose_oxygen_numbers_differ_from_the_twin"] == case["steps"] == 40
        first = case["rows"][0]
        assert first["consumed_room_inventory_step_kg"] == 0.0 and first["consumed_all_step_kg"] > 0.0
        assert all(first["minus_the_twin_without_source"][key] < 0.0 for key in ("o2", "o2_upper", "o2_lower"))
        assert all(case["rows"][-1]["minus_the_twin_without_source"][key] < 0.0 for key in ("o2", "o2_upper", "o2_lower"))
    # What the published bench called "debited without heat" was a sum of two overlapping writes.
    first = BEFORE["cases"]["sealed_dt_2.5"]["rows"][0]
    lower, upper = first["sinks"]["plume_lower"]["applied_kg"], first["sinks"]["upper"]["applied_kg"]
    assert abs(BEFORE["cases"]["sealed_dt_2.5"]["bench_reports_debited_without_heat_kg"] - (lower + upper)) < 1.0e-18


def test_after_the_correction_a_rejected_interval_leaves_nothing_of_the_source() -> None:
    for name in ("sealed_dt_2.5", "sealed_dt_1.0"):
        case = AFTER["cases"][name]
        assert case["state"] == "outside_declared_regime" and case["exit"]["step"] == 0
        assert case["exit"]["cause"] == "the_oxygen_sink_would_not_debit_the_room_inventory"
        assert case["exit"]["route"] == "lower_layer_number_by_the_plume"
        assert case["accepted_kj"] == 0.0 and case["to_the_gas_kj"] == 0.0
        assert case["steps_whose_oxygen_numbers_differ_from_the_twin"] == 0 and case["last_step_that_differs"] == -1
        totals = case["totals"]
        assert totals["accumulator_all_sinks_kg"] == 0.0 and totals["accumulator_primary_kg"] == 0.0
        assert totals["steps_with_power"] == 0 and totals["steps_with_plume_lower_route"] == 0
        for row in case["rows"]:
            assert row["minus_the_twin_without_source"] == {"o2": 0.0, "o2_upper": 0.0, "o2_lower": 0.0}
            assert row["sinks"] == {} or all(float(item.get("applied_kg", 0.0)) == 0.0 for item in row["sinks"].values())


def test_ventilation_and_mixing_keep_their_own_changes() -> None:
    """Not a frozen room: with the source rejected the room still moves, exactly as its twin does."""
    crack = AFTER["cases"]["crack_and_recovery"]
    assert crack["state_after_recovery"] == "outside_declared_regime"
    assert crack["from_the_exit_step_on"]["accumulator_all_sinks_kg"] == 0.0
    assert crack["after_the_oxygen_was_restored"]["accumulator_all_sinks_kg"] == 0.0
    assert crack["accepted_kj"] == crack["accepted_kj_after_recovery"] > 0.0
    # The open room is replenished through its opening while the source runs.
    assert AFTER["cases"]["open_dt_2.5"]["totals"]["exterior_net_kg"] > 0.0
    assert AFTER["cases"]["open_dt_2.5"]["totals"]["ach_on_the_room_number_kg"] > 0.0


def test_a_whole_accepted_run_keeps_its_energy_and_its_contracted_debit() -> None:
    for record in (BEFORE, AFTER):
        for name in ("open_dt_2.5", "open_dt_1.0"):
            case = record["cases"][name]
            assert case["state"] == "completed" and abs(case["accepted_kj"] - 115093.655) < 1.0e-6
            assert abs(case["bench_oxygen_debited_kg"] - CONTRACTED_KG) < 1.0e-9
    # The correction did not move one bit of the accepted run.
    for name in ("open_dt_2.5", "open_dt_1.0", "open_dt_2.5_other_upper_branch"):
        for key in ("room_o2_sha256", "power_sha256", "accepted_kj", "bench_oxygen_debited_kg"):
            assert BEFORE["cases"][name][key] == AFTER["cases"][name][key], (name, key)


def test_the_second_write_is_the_same_demand_on_an_overlapping_number() -> None:
    for record in (BEFORE, AFTER):
        verdicts = record["hypotheses"]
        a1 = verdicts["A1_upper_write_is_the_full_demand_because_the_sink_never_learns_of_two_zones"]
        assert list(a1["branches"]) == ["full_thornton"] and list(a1["branches_with_the_flag_set"]) == ["displacement"]
        assert abs(a1["second_over_first_with_the_flag_set"] - 0.09) < 1.0e-12
        a5 = verdicts["A5_the_all_sinks_counter_is_a_sum_of_overlapping_writes"]["by_case"]
        # The engine counter of "all sinks" is twice ONE consumption: it is not an inventory.
        assert abs(a5["open_dt_2.5"]["all_sinks_over_contracted"] - 2.0) < 1.0e-9
        assert abs(a5["open_dt_2.5"]["upper_number_applied_kg"] - CONTRACTED_KG) < 1.0e-8
        assert abs(a5["open_dt_2.5_other_upper_branch"]["all_sinks_over_contracted"] - 1.09) < 1.0e-9
        # It does not reach the room inventory or the energy ...
        a3 = verdicts["A3_upper_write_does_not_reach_the_room_inventory_or_the_energy"]
        assert a3["room_number_series_identical"] and a3["power_series_identical"]
        # ... and it does reach the regime rule, through the lower-layer number, on the cautious side.
        a4 = verdicts["A4_upper_write_reaches_the_regime_indicator_through_the_lower_number"]
        assert a4["lowest_lower_number"][0] < a4["lowest_lower_number"][1]
        assert a4["lowest_room_number"][0] == a4["lowest_room_number"][1]
        # The three numbers are not a partition of one inventory.
        a2 = verdicts["A2_upper_and_room_numbers_overlap_and_are_not_a_partition"]
        assert abs(a2["largest_room_number_minus_weighted_layers"]) > 1.0e-4
    # The bench publishes the second number apart and under a name that claims no displacement.
    assert abs(AFTER["cases"]["open_dt_2.5"]["bench_second_number_kg"] - CONTRACTED_KG) < 1.0e-8


# ---------------------------------------------------------------- the code

CONDITIONS = [
    'fire_o2_mode == "legacy" and',
    "lower_frac >= FIRE_SINK_MIN_LOWER_FRACTION and",
    "hot_h_upper >= 0.3 and",
    "not fire_uses_lower_o2",
    "_estimate_room_outside_open_factor(building, room) <= 0.01",
    "_estimate_room_interior_open_factor(building, room) <= 0.01",
    "fire_o2_canonical_enabled and",
    '(room.fire_o2_mode_used == "plume_lower" or room.fire_o2_mode_used == "plume_blend") and',
    'phase2b_canonical_combustion_enabled and fire_o2_mode == "upper"',
    "not two_zone_solver_enabled and not effective_plume_lower",
    "plume_upper_o2_displacement_frac > 0.0",
    "LayerInterfaceModel.get_flow_interface_height_m(room, null, building.outside_temp_c)",
    "maxf(0.01, (room.height_m - hot_h_upper) / maxf(0.01, room.height_m))",
    "hot_h_upper = clampf(hot_h_upper, 0.0, room.height_m)",
    "plume_lower_mode or canonical_plume_lower",
]


def test_the_question_to_the_sink_repeats_the_conditions_of_the_sink() -> None:
    step = _flat(_code(_body(OXYGEN, "func step(building: BuildingModel, dt: float, hooks: Dictionary) -> void:")))
    plan = _flat(_code(_body(OXYGEN, "func fire_sink_plan(")).replace("plan_", ""))
    for condition in CONDITIONS:
        assert condition in step, "step: " + condition
        assert condition in plan, "plan: " + condition
    # The step asks for power as well; the question is what the sink WOULD do with it.
    assert "room.hrr_kw" not in plan
    assert '"hooks.get(' not in plan and 'hooks.get("effective_hot_layer_height_callable", Callable())' in plan


def test_the_question_to_the_sink_writes_nothing() -> None:
    plan = _code(_body(OXYGEN, "func fire_sink_plan("))
    assert not re.search(r"\b(room|building)\.[\w.]+\s*[-+*/]?=[^=]", plan)
    # Every assignment is to a variable declared inside the function: no member of the system is written.
    local = set(re.findall(r"^\t+var (\w+)", plan, re.M))
    assigned = set(re.findall(r"^\t+([a-z_]\w*)\s*[-+*/]?=[^=]", plan, re.M))
    assert assigned and assigned <= local, assigned - local
    for word in ("_record_", "_pending_o2_deliveries", ".append(", ".erase(", "push_", "phase3_o2_ledger"):
        assert word not in plan, word
    assert plan.count("return {") == 2


def test_only_the_bench_asks_and_the_historical_step_does_not() -> None:
    users = sorted(path.relative_to(ROOT).as_posix() for path in (ROOT / "sim").rglob("*.gd")
                   if "fire_sink_plan" in path.read_text(encoding="utf-8"))
    assert users == ["sim/core/OxygenExchangeSystem.gd", "sim/core/SimulationEngine.gd"]
    assert OXYGEN.count("fire_sink_plan") == 1  # its definition: step() never calls it
    assert ENGINE.count("fire_sink_plan(") == 1
    hook = _body(ENGINE, "func _g3_prescribed_thermal_oxygen_sink_plan(room: RoomModel) -> Dictionary:")
    assert "oxygen_exchange_system.fire_sink_plan(building, room, _build_oxygen_exchange_hooks())" in hook
    # The engine names the hook where it is defined and where it is handed to the bench, and nowhere else.
    assert ENGINE.count("_g3_prescribed_thermal_oxygen_sink_plan") == 2
    arm = _body(ENGINE, "func _g3_prescribed_thermal_arm() -> void:")
    assert arm.index("if not g3_prescribed_thermal_source_enabled:") < arm.index("_g3_prescribed_thermal_oxygen_sink_plan")
    # The two-zone flag is still not handed to the oxygen system: that is the historical route, untouched.
    configure = ENGINE[ENGINE.index("oxygen_exchange_system.configure({"):]
    assert "two_zone_solver_enabled" not in configure[:configure.index("})")]


def test_the_bench_asks_before_the_power_and_fails_if_the_sink_did_otherwise() -> None:
    code = _code(COUPLING)
    begin = _body(code, "func begin_step(dt: float) -> void:")
    assert begin.index("_regime_failure(energy_kj, dt)") < begin.index("_write_room_power(energy_kj / dt)")
    regime = _body(code, "func _regime_failure(energy_kj: float, dt: float) -> Dictionary:")
    order = ['_hooks["oxygen_sink_plan"].call(_room)', 'if plan["primary_route"] != ROOM_INVENTORY_ROUTE:',
             '"the_oxygen_sink_would_not_debit_the_room_inventory"',
             '"the_declared_coefficient_is_not_the_one_of_the_sink"', '_hooks["oxygen_floor_MJ"].call(']
    positions = [regime.index(item) for item in order]
    assert positions == sorted(positions)
    assert not re.search(r"_room\.\w+\s*[-+*/]?=[^=]", regime)
    settle = _body(code, "func settle_oxygen() -> void:")
    assert settle.index("_withdraw_room_power()") < settle.index("_fail([reason])")
    # A sink that did otherwise is a failure, never an ordinary rejected interval.
    assert "_leave_regime(" not in settle and settle.count("_settle(") == 1
    assert 'const ROOM_INVENTORY_ROUTE: String = "room_inventory"' in code


def test_no_counter_adds_overlapping_numbers() -> None:
    code = _code(COUPLING)
    for gone in ("oxygen_debited_without_heat_kg", "oxygen_zone_displacement_kg", "oxygen_debit_is_not_the_committed_one"):
        assert gone not in code, gone
    # all_kg is the engine sum of every sink write. It is only ever used as a difference.
    uses = [line.strip() for line in code.splitlines() if "all_kg" in line and "var all_kg" not in line]
    assert uses and all("all_kg - primary_kg" in line for line in uses), uses
    assert '"never_add": ["oxygen_debited_kg", "upper_layer_number_written_kg"]' in code
    assert "not a second consumption" in code and '"authoritative_inventory": "none in the engine' in code
    assert "prescribed_thermal_source_coupling_v2" in code and "g3_prescribed_thermal_source_report_v2" in code


# ---------------------------------------------------------------- what is said

def test_the_report_gives_the_three_decisions_and_promises_nothing_more() -> None:
    text = REPORT.read_text(encoding="utf-8")
    flat = _flat(text)
    for needed in ("Decisión A: GO", "Decisión B: GO", "Decisión C: NO-GO", "demanda equivalente prescrita",
                   "CONTRATO_O2_2026-09-24.md", "No existe un inventario autoritativo", "CO y FED siguen OFF/NO-GO",
                   "no es el consumo experimental exacto ni una estequiometría validada"):
        assert needed in flat, needed
    # The correction is a restriction and it is named as one, with the case it leaves out.
    assert "Restricción explícita" in flat and "recinto estanco" in flat
    # The limit that remains is said: the bench cannot undo a write of the engine.
    assert "no puede deshacer" in flat
    for promise in ("rechazo atómico", "sin doble consumo", "ausencia de doble"):
        assert promise not in flat.lower(), promise
    for relative in re.findall(r"\]\((\.\./\.\./[^)#]+|[A-Z0-9_./-]+\.(?:md|json))\)", text):
        assert (REPORT.parent / relative).resolve().exists(), relative


def test_the_earlier_documents_no_longer_say_what_the_evidence_does_not_hold() -> None:
    bench = (VALIDATION / "G3_OBJECT_HRR_SOURCE_COUPLING_BENCH_2026-10-08.md").read_text(encoding="utf-8")
    design = (VALIDATION / "G3_OBJECT_HRR_SOURCE_COUPLING_DESIGN_2026-10-08.md").read_text(encoding="utf-8")
    for text in (bench, design):
        assert "G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md" in text
    assert "Corregido el 2026-10-09" in bench
    handoff = (ROOT / "docs/HANDOFF_CURRENT_STATE.md").read_text(encoding="utf-8")
    plan = (ROOT / "docs/planning/G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md").read_text(encoding="utf-8")
    assert "G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md" in handoff and "G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md" in plan
