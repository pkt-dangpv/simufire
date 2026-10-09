"""Oxygen authority: the diagnosis record, the code facts it rests on and its documents.

Offline. The record was produced by ``scripts/simulation/run_g3_o2_authority_diagnosis.py``
on the real engine; here its verdicts are evaluated again from its own figures, the code
facts the report states are read from the code, and the documents are checked. Nothing
here approves a migration: the report proposes one and stops.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
RECORD = ROOT / "docs" / "validation" / "G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json"
REPORT = ROOT / "docs" / "validation" / "G3_O2_AUTHORITY_2026-10-09.md"
FIXTURE = ROOT / "tests" / "fixtures" / "g3_o2_authority_diagnosis.gd"
RUNNER = ROOT / "scripts" / "simulation" / "run_g3_o2_authority_diagnosis.py"
ROUNDING_KG = 1.0e-9


def _load(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def runner():
    return _load(RUNNER)


@pytest.fixture(scope="module")
def record() -> dict:
    return json.loads(RECORD.read_text(encoding="utf-8"))


def _text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def _evidence(record: dict, name: str) -> dict:
    return record["hypotheses"][name]["evidence"]


# ---------------------------------------------------------------- the record

def test_the_record_carries_the_hypotheses_of_the_runner_unchanged(runner, record):
    assert set(record["hypotheses"]) == set(runner.HYPOTHESES)
    for name, declared in runner.HYPOTHESES.items():
        for key in ("statement", "predicted", "decides"):
            assert record["hypotheses"][name][key] == declared[key], (name, key)


def test_the_record_belongs_to_the_code_it_speaks_of(record):
    for relative, digest in record["sources_sha256"].items():
        current = hashlib.sha256((ROOT / relative).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        assert current == digest, f"{relative} changed after the record was written: run the diagnosis again"


def test_every_verdict_is_the_conjunction_of_its_claims(record):
    for name, item in record["hypotheses"].items():
        if item["exercised"]:
            assert item["holds"] == all(item["claims"].values()), name
        else:
            assert item["holds"] is None, name


def test_what_did_not_come_out_as_predicted_is_said(record):
    assert record["not_as_predicted"] == ["H13_house_cases_already_run", "H14_network_mode_has_no_oxygen_inventory_either"]
    assert record["all_as_predicted"] is False
    house = record["hypotheses"]["H13_house_cases_already_run"]
    assert [claim for claim, met in house["claims"].items() if not met] == ["reopened_house_closes_within_0.01_kg"]
    bench = record["hypotheses"]["H14_network_mode_has_no_oxygen_inventory_either"]
    assert bench["exercised"] is False and "authoritative_transport_enabled" in str(bench["evidence"]["bench_failure"])
    assert record["launches"]["count"] == 3


def test_the_room_number_closes_where_the_sink_debits_the_room(record):
    controlled = _evidence(record, "H04_controlled_demand_closes_on_the_room_number")
    assert controlled["largest_closure_gap_kg"] <= ROUNDING_KG
    assert controlled["debit_room_inventory_kg"] == pytest.approx(0.076 * controlled["accepted_MJ"], rel=1e-9)
    fire = _evidence(record, "H12_fire_and_sink_use_different_deposits")
    assert fire["largest_closure_gap_kg"] <= ROUNDING_KG
    assert fire["debit_room_inventory_kg"] == pytest.approx(0.076 * fire["heat_accepted_MJ"], rel=1e-9)
    assert fire["largest_transport_accumulators_plus_transit_kg"] <= ROUNDING_KG
    # Part of what the rooms hold is on its way between them: without it the sum does not close.
    assert abs(fire["in_transit_at_the_end_kg"]) > 0.1
    transport = _evidence(record, "H05_interior_transport_conserves_the_room_numbers")
    assert transport["largest_closure_gap_kg"] <= ROUNDING_KG
    assert sum(transport["room_changes_kg"]) == pytest.approx(0.0, abs=ROUNDING_KG)


def test_the_second_write_is_as_large_as_the_debit_and_reaches_no_inventory(record):
    for name in ("H04_controlled_demand_closes_on_the_room_number", "H12_fire_and_sink_use_different_deposits"):
        evidence = _evidence(record, name)
        assert evidence["second_write_kg"] == pytest.approx(evidence["debit_room_inventory_kg"], rel=1e-9), name
        assert evidence["largest_closure_gap_kg"] <= ROUNDING_KG, name


def test_fire_and_sink_do_not_use_the_same_deposit(record):
    fire = _evidence(record, "H12_fire_and_sink_use_different_deposits")
    assert fire["fire_deposits_seen"] == ["plume_lower"]
    assert fire["steps_with_fire_reading_a_layer_apart_from_the_room"] > 0
    assert fire["largest_fire_reads_minus_room_number"] > 0.02
    assert fire["lowest_upper_number"] < 0.5 * fire["lowest_room_number"] < fire["lowest_lower_number"]


def test_the_layer_numbers_have_no_conservation_of_their_own(record):
    mixing = _evidence(record, "H08_layer_mixing_is_a_relaxation_not_an_exchange")
    assert mixing["room_number"][0] == mixing["room_number"][1]
    assert mixing["layers_on_shares_change_kg"] > 0.1 and mixing["largest_accumulator_kg"] == 0.0
    collapse = _evidence(record, "H09_collapse_rewrites_both_layers")
    assert collapse["jump_on_shares_kg"] > 1.0 and collapse["largest_accumulator_kg"] == 0.0
    assert collapse["numbers_end"] == [0.209, 0.209, 0.209]


def test_the_layer_gas_masses_are_no_base_in_either_mode(record):
    heated = _evidence(record, "H02_heating_changes_the_gas_base_not_the_numbers")
    assert heated["gas_kg"][1] < heated["gas_kg"][0] - 5.0 and heated["boundary_gas_kg"][0] < -5.0
    assert heated["layer_numbers_on_gas_change_kg"] == pytest.approx(0.209 * heated["gas_change_kg"], abs=ROUNDING_KG)
    assert heated["largest_accumulator_kg"] == 0.0
    network = _evidence(record, "H03_network_keeps_the_gas_base")
    assert network["gas_span_kg"] <= ROUNDING_KG
    fire = _evidence(record, "H15_network_mode_with_a_real_fire")
    assert fire["gas_span_kg"] <= ROUNDING_KG and fire["room_number_minus_layers_on_gas"] <= 1e-12
    assert abs(fire["unexplained_over_debit"]) > 0.1


def test_the_house_cases_show_the_other_route_and_the_silent_cap(record):
    house = _evidence(record, "H13_house_cases_already_run")
    closed = house["o2_closed"]
    assert closed["debit_room_inventory_kg"] == 0.0 and closed["debit_primary_kg"] > 6.0
    assert closed["unexplained_kg"] < -5.0 and closed["zone_sync_kg"] == 0.0
    reopened = house["o2_reopen_300"]["after_300_s"]
    assert reopened["largest_room_change_minus_its_own_accumulators_kg"] < 1e-3
    assert reopened["house_closure_gap_kg"] == pytest.approx(reopened["house_transport_accumulators_kg"], abs=1e-3)
    stress = house["o2_stress_cap"]
    assert stress["never_debited_kg"] == pytest.approx(0.076 * stress["heat_accepted_MJ"] - stress["debit_primary_kg"], abs=1e-9)
    assert stress["never_debited_kg"] > 8.0


def test_the_fraction_of_the_engine_is_molar_and_its_inventory_is_short(runner, record):
    basis = record["basis_of_the_fraction"]
    assert basis == runner.basis()
    assert basis["mass_fraction_that_corresponds"] == pytest.approx(0.209 * 31.998 / 28.9647)
    assert 0.09 < basis["inventory_short_by_fraction"] < 0.10
    assert "dry air" in basis["assumption"]


# ---------------------------------------------------------------- the evaluator is not a rubber stamp

def _row(room: int, o2: float, debit: float = 0.0, transit: float = 0.0) -> dict:
    return {"room": room, "o2": o2, "ref_kg": 57.6 * o2, "in_transit_kg": transit, "debit_room_inventory_kg": debit,
            "exterior_kg": 0.0}


def test_the_closure_sees_a_debit_that_did_not_reach_the_room_number(runner):
    start = [_row(0, 0.209)]
    honest = [[_row(0, 0.209 - 0.1 / 57.6, debit=0.1)]]
    missing = [[_row(0, 0.209, debit=0.1)]]
    twice = [[_row(0, 0.209 - 0.2 / 57.6, debit=0.1)]]
    assert runner._closure(start, honest) <= ROUNDING_KG
    assert runner._closure(start, missing) == pytest.approx(0.1)
    assert runner._closure(start, twice) == pytest.approx(0.1)


def test_the_closure_needs_what_is_in_transit(runner):
    start = [_row(0, 0.209), _row(1, 0.15)]
    rows = [[_row(0, 0.209 + 0.05 / 57.6), _row(1, 0.15, transit=-0.05)]]
    assert runner._closure(start, rows) <= ROUNDING_KG
    rows[0][1]["in_transit_kg"] = 0.0
    assert runner._closure(start, rows) == pytest.approx(0.05)


def test_a_verdict_falls_with_any_of_its_claims(runner):
    assert runner._verdict({"a": True, "b": True}, {})["holds"] is True
    assert runner._verdict({"a": True, "b": False}, {})["holds"] is False
    assert runner._verdict({"a": True}, {}, exercised=False)["holds"] is None


# ---------------------------------------------------------------- the code facts the report states

WRITE = re.compile(r"\b[a-z_]+\.(o2|o2_upper|o2_lower|upper_o2_mass_tracked)\s*(=|\+=|-=|\*=)[^=]")


def test_the_writers_of_the_oxygen_numbers_are_the_ones_the_report_counts():
    counted: dict = {}
    for path in sorted((ROOT / "sim").rglob("*.gd")):
        hits = [line for line in path.read_text(encoding="utf-8").splitlines()
                if WRITE.search(line) and not line.lstrip().startswith("#")]
        if hits:
            counted[path.relative_to(ROOT).as_posix()] = len(hits)
    assert counted == {
        "sim/core/GasExchangeSystem.gd": 4, "sim/core/HVACSystem.gd": 5, "sim/core/OxygenExchangeSystem.gd": 29,
        "sim/core/PressureNetworkTransportSystem.gd": 3, "sim/core/SimulationEngine.gd": 1, "sim/core/ThermalSystem.gd": 11,
    }
    assert sum(counted.values()) == 53


def test_the_room_number_lives_on_a_constant_mass():
    oxygen = _text("sim/core/OxygenExchangeSystem.gd")
    body = oxygen.split("func _compute_room_air_mass_kg(", 1)[1].split("\nfunc ", 1)[0]
    assert "return maxf(0.1, room.volume_m3()) * air_density_kg_m3" in body
    assert "upper_gas_kg" not in oxygen and "lower_gas_kg" not in oxygen
    assert "var air_density_kg_m3: float = 1.2" in oxygen


def test_the_layer_gas_mass_is_rewritten_outside_the_network_mode():
    solver = _text("sim/core/ZoneFireSolver.gd")
    assert "if canonical_mass_conservation_enabled else lower_volume_m3 * lower_density_kg_m3" in solver
    assert "room.two_zone_boundary_mass_kg += room.lower_gas_kg - lower_mass_before_kg" in solver


def test_the_network_multiplies_the_molar_number_by_the_gas_mass():
    network = _text("sim/core/PressureNetworkTransportSystem.gd")
    assert 'entry["o2_mass_upper_kg"] = float(room.o2_upper) * upper_gas_kg' in network
    assert 'room.o2 = _fraction(float(final_state["total_o2_kg"]), total_gas_kg)' in network
    assert "M_O2" not in network and "molar" not in network.lower()


def test_the_room_number_is_rewritten_from_the_layers_without_being_booked():
    oxygen = _text("sim/core/OxygenExchangeSystem.gd")
    assert "room.o2 = clampf(room.o2_upper * upper_frac + room.o2_lower * lower_frac, 0.0, o2_nominal)" in oxygen
    # The only writer of the accumulator meant for that is the doorway blend of the thermal
    # system, behind switches that are off; the oxygen system never books its own rewrite.
    written = sorted(path.name for path in (ROOT / "sim").rglob("*.gd")
                     if re.search(r"o2_zone_sync_kg_(step|total)\s*\+=", path.read_text(encoding="utf-8")))
    assert written == ["ThermalSystem.gd"], written
    assert "o2_zone_sync_kg" not in oxygen


def test_the_fire_reads_a_layer_number_and_the_sink_decides_its_route_alone():
    combustion = _text("sim/fire/CombustionSystem.gd")
    selection = combustion.split("func _resolve_fire_o2_selection(", 1)[1].split("\nfunc ", 1)[0]
    assert 'o2_ref = room.o2_lower\n\t\t\t\tmode = "plume_lower"' in selection
    oxygen = _text("sim/core/OxygenExchangeSystem.gd")
    route = oxygen.split("var plume_lower_mode: bool = (", 1)[1].split(")\n", 1)[0]
    assert "_estimate_room_interior_open_factor(building, room) <= 0.01" in route
    assert "fire_o2_mode_used" not in route


def test_what_is_in_transit_is_private_state_of_the_oxygen_system():
    oxygen = _text("sim/core/OxygenExchangeSystem.gd")
    assert "var _pending_o2_deliveries: Array[Dictionary] = []" in oxygen
    reset = oxygen.split("func reset() -> void:", 1)[1].split("\nfunc ", 1)[0]
    assert "_pending_o2_deliveries.clear()" in reset and "_reserved_transport_o2_delta_kg.clear()" in reset
    assert "_pending_o2_deliveries" not in _text("sim/core/SimulationLogWriter.gd")


# ---------------------------------------------------------------- the fixture changes no law

ALLOWED_ENGINE_SETTINGS = {
    "building", "auto_ignite_on_ready", "auto_finish_on_extinction", "enable_logging", "enable_csv_log", "sim_fixed_dt",
    "ach_infiltration", "pressure_network_solver_enabled", "energy_budget_enabled", "energy_budget_warn_fraction",
    "g3_prescribed_thermal_source_enabled", "g3_prescribed_thermal_source_case", "phase3_o2_attribution_diagnostics_enabled",
    "_opening_flow_cache",
}


def test_the_fixture_sets_only_what_it_declares():
    fixture = FIXTURE.read_text(encoding="utf-8")
    assert set(re.findall(r"\bengine\.(\w+)\s*=[^=]", fixture)) <= ALLOWED_ENGINE_SETTINGS
    for forbidden in ("two_zone_solver_enabled =", "fire_o2_mode =", "fire_o2_canonical_enabled", "FileAccess.open",
                      "plume_upper_o2_displacement_frac", "_PASS"):
        assert forbidden not in fixture, forbidden
    assert 'print("G3_O2_AUTHORITY_DIAGNOSIS_DONE")' in fixture


def test_the_diagnosis_declares_its_isolations(record):
    for name, setup in record["setups"].items():
        declared = " ".join(setup["declared_changes"])
        assert "passive ledger" in declared, name
        if setup["engine"]["pressure_network_solver_enabled"]:
            assert "not the product route" in declared, name
        if setup["engine"]["ach_infiltration"] == 0.0:
            assert "isolation" in declared, name
        assert setup["engine"]["oxygen_system_sees_two_zones"] is False, name
        assert setup["engine"]["fire_o2_mode"] == "legacy", name


# ---------------------------------------------------------------- documents

REQUIRED = (
    "Inventario único de oxígeno por recinto", "NO-GO", "No se migra nada en esta entrega",
    "Vigente y demostrado", "Corregido y demostrado", "No comprobado todavía",
    "demanda equivalente", "fracción molar", "0,2309", "en tránsito",
    "NIST TN 1889v1", "CO y FED siguen OFF/NO-GO", "Siguiente encargo",
    "G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json", "CONTRATO_O2_2026-09-24.md", "E1_O2_BASE_DE_MASA_2026-09-25.md",
)
COMPONENTS = ("Inicialización", "Base de masa", "Consumo único", "Transporte", "Mezcla y movimiento de capas",
              "Disponibilidad y aceptación de calor", "Ciclo de vida", "Migración desde las rutas históricas")


def test_the_report_says_what_it_decides():
    report = REPORT.read_text(encoding="utf-8")
    for phrase in REQUIRED + COMPONENTS:
        assert phrase in report, phrase
    for forbidden in ("@@", "validado contra", "elige qué número manda"):
        assert forbidden not in report, forbidden


def test_the_report_quotes_the_figures_of_the_record(record):
    report = REPORT.read_text(encoding="utf-8")
    fire = _evidence(record, "H12_fire_and_sink_use_different_deposits")
    house = _evidence(record, "H13_house_cases_already_run")
    quoted = {
        f"{fire['debit_room_inventory_kg']:.4f}".replace(".", ","),
        f"{_evidence(record, 'H09_collapse_rewrites_both_layers')['jump_on_shares_kg']:.2f}".replace(".", ","),
        f"{house['o2_stress_cap']['never_debited_kg']:.2f}".replace(".", ","),
        f"{abs(house['o2_closed']['unexplained_kg']):.2f}".replace(".", ","),
        f"{_evidence(record, 'H15_network_mode_with_a_real_fire')['unexplained_kg']:.3f}".replace(".", ","),
    }
    for figure in quoted:
        assert figure in report, figure


@pytest.mark.parametrize("relative", [
    "docs/HANDOFF_CURRENT_STATE.md", "docs/validation/CONTRATO_O2_2026-09-24.md",
    "docs/validation/E1_O2_BASE_DE_MASA_2026-09-25.md", "docs/validation/G3_OBJECT_HRR_OXYGEN_LIMITS_2026-10-09.md",
    "docs/planning/G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md",
])
def test_the_report_is_linked_from_where_it_matters(relative):
    assert "G3_O2_AUTHORITY_2026-10-09.md" in _text(relative), relative


def test_e1_keeps_its_evidence_and_gains_a_note_of_validity():
    e1 = _text("docs/validation/E1_O2_BASE_DE_MASA_2026-09-25.md")
    assert "Nota de vigencia (2026-10-09)" in e1
    for kept in ("+22,60 kg", "−5,10 kg", "201,600000 kg", "8,74 kg"):
        assert kept in e1, kept
