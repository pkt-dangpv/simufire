"""Isolated sensible atomic owner: predeclared oracles, real GDScript, isolation.

The oracles are exact rational algebra written from the contract in
docs/validation/G3_D1_SENSIBLE_OWNER_2026-10-05.md. They never call a .gd
function and are synthetic: not measured properties of any fuel or fire.
"""
from fractions import Fraction as F
import hashlib
import json
import os
from pathlib import Path
import re

import pytest

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "sim/fire/PrescribedSensiblePhaseController.gd"
FIXTURE = ROOT / "tests/fixtures/g3_sensible_phase_controller.gd"
PREFIX = "G3_SENSIBLE_PHASE_CONTROLLER"
NAME = "PrescribedSensiblePhaseController"
CHECKS = 4663  # Measured on the real fixture; never anticipated.
MUTANTS = 40

# Predeclared pins, fixed before the GDScript owner existed.
ORACLES = {
    "hot1_liquid": 0.9, "hot1_vapour": 0.1, "hot1_budget": 872.0, "hot1_sl": 18.0,
    "hot1_sv": 10.0, "hot1_cost": 108.0,
    "hot2_liquid": 0.8, "hot2_vapour": 0.15, "hot2_o2": 9.8, "hot2_co2": 0.1375,
    "hot2_water": 0.1125, "hot2_budget": 764.0, "hot2_q": 1005.0, "hot2_sl": 16.0,
    "hot2_sv": 15.0, "hot2_heating_l": 20.0, "hot2_heating_v": 5.0, "hot2_cost": 211.0,
    "hot2_emitted": 15.0, "hot2_released": 4.0, "hot2_oxidized_sensible": 5.0,
    "hot2_chemical": 1000.0, "hot2_total": 20000.0,
    "ref2_liquid": 0.8, "ref2_vapour": 0.15, "ref2_o2": 9.8, "ref2_co2": 0.1375,
    "ref2_water": 0.1125, "ref2_budget": 800.0, "ref2_q": 1000.0, "ref2_sl": 0.0,
    "ref2_sv": 0.0, "ref2_cost": 200.0, "ref2_total": 20000.0,
    "hot3_q": 4020.0, "hot3_budget": 764.0, "hot3_sl": 16.0, "hot3_sv": 0.0,
    "ref3_q": 4000.0, "ref3_budget": 800.0, "ref3_sl": 0.0, "ref3_sv": 0.0,
    "first_liquid": 0.8, "first_heating_l": 20.0, "first_sl": 16.0, "first_budget": 784.0,
    "first_cost": 196.0, "first_released": 4.0,
    "later_liquid": 0.8, "later_heating_l": 20.0, "later_sl": 160.0 / 9.0,
    "later_budget": 7040.0 / 9.0, "later_cost": 1780.0 / 9.0, "later_released": 20.0 / 9.0,
    "cold_cost": 102.5, "cold_budget": 897.5, "cold_sl": -45.0, "cold_sv": 0.0,
    "cold_q": 1997.5, "cold_oxidized_sensible": -2.5, "cold_released": -5.0,
    "cold_emitted": -2.5, "cold_total": 19950.0,
    "cap_accepted": 0.05, "cap_rejected": 0.05, "cap_deficit": 54.0, "cap_budget": 0.0,
    "cap_sl": 19.0, "cap_q": 1005.0, "cap_total": 19074.0, "cap_next_accepted": 0.0,
    "cap_rejected_total": 0.15,
    "o2_oxidized": 0.05, "o2_vapour": 0.05, "o2_left": 0.0,
    "exh_liquid": 0.0, "exh_sl": 0.0, "exh_budget": 808.0, "exh_released": 8.0,
    "exh_total": 4808.0, "exh_heated_sv": 10.0, "exh_heated_budget": 798.0,
    "cross_demand": 0.05, "cross_physical_dt": 1.0, "cross_source_dt": 0.5,
    "cross_cursor": 2.0, "cross_time": 2.5,
}

QL, QV, LREF = F(19000), F(20000), F(1000)
CP_L, CP_V, T_REF = F(2), F(1), F("298.15")
O2_PER_KG, CO2_PER_KG, WATER_PER_KG = F(4), F(11, 4), F(9, 4)


def _start(mass="1", o2="10", budget="1000", sl="0"):
    zero = F(0)
    return {"liquid": F(mass), "vapour": zero, "o2": F(o2), "B": F(budget), "Q": zero,
            "Sl": F(sl), "Sv": zero, "heating_l": zero, "heating_v": zero, "cost": zero,
            "released": zero, "emitted": zero, "oxidized_sensible": zero, "chemical": zero,
            "co2": zero, "water": zero, "accepted": zero, "rejected": zero}


def _step(state, demand, oxidation, heat_l="0", heat_v="0", emitted_k="298.15"):
    """Contract algebra: heat, release, mix, oxidize. Exact rationals only."""
    s = dict(state)
    demand, oxidation, heat_l, heat_v = F(demand), F(oxidation), F(heat_l), F(heat_v)
    assert heat_l + heat_v <= s["B"], "prescribed heating may not exceed B"
    assert (heat_l == 0 or s["liquid"] > 0) and (heat_v == 0 or s["vapour"] > 0)
    s["B"] -= heat_l + heat_v
    s["Sl"] += heat_l
    s["Sv"] += heat_v
    s["heating_l"] += heat_l
    s["heating_v"] += heat_v
    liquid_specific = s["Sl"] / s["liquid"] if s["liquid"] else F(0)
    emitted_specific = CP_V * (F(emitted_k) - T_REF)
    cost_per_kg = LREF + emitted_specific - liquid_specific if s["liquid"] else LREF
    assert cost_per_kg > 0
    release = min(demand, s["liquid"], s["B"] / cost_per_kg)
    deficit = max(F(0), min(demand, s["liquid"]) * cost_per_kg - s["B"])
    s["B"] -= release * cost_per_kg
    s["cost"] += release * cost_per_kg
    s["released"] += release * liquid_specific
    s["emitted"] += release * emitted_specific
    s["liquid"] -= release
    s["Sl"] = s["liquid"] * liquid_specific
    mixed_mass = s["vapour"] + release
    mixed_sensible = s["Sv"] + release * emitted_specific
    mixed_specific = mixed_sensible / mixed_mass if mixed_mass else F(0)
    burned = min(oxidation, mixed_mass, s["o2"] / O2_PER_KG)
    s["vapour"] = mixed_mass - burned
    s["Sv"] = s["vapour"] * mixed_specific
    s["o2"] -= burned * O2_PER_KG
    s["co2"] += burned * CO2_PER_KG
    s["water"] += burned * WATER_PER_KG
    s["oxidized_sensible"] += burned * mixed_specific
    s["chemical"] += burned * QV
    s["Q"] += burned * (QV + mixed_specific)
    s["accepted"] += release
    s["rejected"] += demand - release
    s["last"] = {"release": release, "rejected": demand - release, "deficit": deficit,
                 "cost": release * cost_per_kg, "burned": burned}
    return s


def _total(s):
    return s["liquid"] * QL + s["vapour"] * QV + s["Sl"] + s["Sv"] + s["B"] + s["Q"]


def _closes(s, start):
    """The owner identities of the contract, on the independent algebra."""
    assert s["B"] + s["heating_l"] + s["heating_v"] + s["cost"] == start["B"]
    assert s["Sl"] + s["released"] == start["Sl"] + s["heating_l"]
    assert s["Sv"] + s["oxidized_sensible"] == s["heating_v"] + s["emitted"]
    assert s["Q"] == s["chemical"] + s["oxidized_sensible"]
    assert s["cost"] + s["released"] == s["accepted"] * LREF + s["emitted"]
    assert _total(s) == _total(start)


def _pin(prefix, s, mapping):
    for key, field in mapping.items():
        expected = F(ORACLES[prefix + key]).limit_denominator(10 ** 9)
        assert s[field] == expected, (prefix + key, s[field])


def test_predeclared_independent_history_oracles():
    start = _start()
    hot1 = _step(start, ".1", "0", heat_l="20", emitted_k="398.15")
    _pin("hot1_", hot1, {"liquid": "liquid", "vapour": "vapour", "budget": "B",
                         "sl": "Sl", "sv": "Sv", "cost": "cost"})
    hot2 = _step(hot1, ".1", ".05", heat_v="5", emitted_k="348.15")
    ref2 = _step(_step(start, ".1", "0"), ".1", ".05")
    masses = {"liquid": "liquid", "vapour": "vapour", "o2": "o2", "co2": "co2", "water": "water"}
    _pin("hot2_", hot2, {**masses, "budget": "B", "q": "Q", "sl": "Sl", "sv": "Sv",
                         "heating_l": "heating_l", "heating_v": "heating_v", "cost": "cost",
                         "emitted": "emitted", "released": "released",
                         "oxidized_sensible": "oxidized_sensible", "chemical": "chemical"})
    _pin("ref2_", ref2, {**masses, "budget": "B", "q": "Q", "sl": "Sl", "sv": "Sv", "cost": "cost"})
    # Equal masses, different thermal history: mass alone cannot rebuild the state.
    assert all(hot2[field] == ref2[field] for field in [*masses.values(), "accepted", "rejected"])
    assert all(hot2[field] != ref2[field] for field in ["B", "Q", "Sl", "Sv", "cost", "heating_l"])
    assert _total(hot2) == _total(ref2) == ORACLES["hot2_total"] == ORACLES["ref2_total"]
    hot3, ref3 = _step(hot2, "0", ".15"), _step(ref2, "0", ".15")
    for prefix, state in [("hot3_", hot3), ("ref3_", ref3)]:
        _pin(prefix, state, {"q": "Q", "budget": "B", "sl": "Sl", "sv": "Sv"})
        _closes(state, start)
    assert hot3["Q"] - ref3["Q"] == 20 and hot3["vapour"] == ref3["vapour"] == 0


def test_predeclared_order_cold_cap_and_exhaustion_oracles():
    start = _start()
    order = {"liquid": "liquid", "heating_l": "heating_l", "sl": "Sl", "budget": "B",
             "cost": "cost", "released": "released"}
    first = _step(_step(start, ".1", "0", heat_l="20"), ".1", "0")
    later = _step(_step(start, ".1", "0"), ".1", "0", heat_l="20")
    _pin("first_", first, order)
    _pin("later_", later, order)
    # Same masses AND same total heating; the order still changes the accounts.
    assert first["heating_l"] == later["heating_l"] and first["accepted"] == later["accepted"]
    assert first["Sl"] != later["Sl"] and first["B"] != later["B"]
    for state in [first, later]:
        _closes(state, start)

    cold_start = _start(sl="-50")
    cold = _step(cold_start, ".1", ".1", emitted_k="273.15")
    _pin("cold_", cold, {"cost": "cost", "budget": "B", "sl": "Sl", "sv": "Sv", "q": "Q",
                         "oxidized_sensible": "oxidized_sensible", "released": "released",
                         "emitted": "emitted"})
    assert _total(cold) == _total(cold_start) == ORACLES["cold_total"]
    _closes(cold, cold_start)

    cap_start = _start(budget="74")
    cap = _step(cap_start, ".1", ".05", heat_l="20", emitted_k="398.15")
    _pin("cap_", cap, {"budget": "B", "sl": "Sl", "q": "Q"})
    assert cap["last"]["release"] == F(ORACLES["cap_accepted"]).limit_denominator(100)
    assert cap["last"]["rejected"] == F(ORACLES["cap_rejected"]).limit_denominator(100)
    assert cap["last"]["deficit"] == ORACLES["cap_deficit"]
    assert _total(cap) == ORACLES["cap_total"]
    after = _step(cap, ".1", "1")
    # Deposited heat is never thermal budget, in this step or a later one.
    assert after["last"]["release"] == ORACLES["cap_next_accepted"] and after["Q"] == cap["Q"]
    assert after["rejected"] == F(ORACLES["cap_rejected_total"]).limit_denominator(100)
    with pytest.raises(AssertionError):
        _step(cap, ".1", "0", heat_l="1")

    limited = _step(_start(o2=".2"), ".1", ".1")
    assert [limited["last"]["burned"], limited["vapour"], limited["o2"]] == [
        F(1, 20), F(1, 20), ORACLES["o2_left"]]

    exhausted_start = _start(mass=".2", sl="8")
    exhausted = _step(_step(exhausted_start, ".1", "0"), ".1", "0")
    _pin("exh_", exhausted, {"liquid": "liquid", "sl": "Sl", "budget": "B", "released": "released"})
    assert _total(exhausted) == _total(exhausted_start) == ORACLES["exh_total"]
    with pytest.raises(AssertionError):
        _step(exhausted, "0", "0", heat_l="1")
    heated = _step(exhausted, "0", "0", heat_v="10")
    assert [heated["Sv"], heated["B"]] == [ORACLES["exh_heated_sv"], ORACLES["exh_heated_budget"]]
    # Crossing the source end: 0.1 kg/s over [1.5, 2] only; clocks stay separate.
    assert F(1, 10) * (2 - F(3, 2)) == F(ORACLES["cross_demand"]).limit_denominator(100)
    assert F(5, 2) - F(3, 2) == ORACLES["cross_physical_dt"]
    assert 2 - F(3, 2) == ORACLES["cross_source_dt"]


def _fixture_expected():
    text = FIXTURE.read_text(encoding="utf-8")
    block = re.search(r"const EXPECTED: Dictionary = \{\n(.*?)\n\}\n", text, re.S).group(1)
    table = {}
    for key, expression in re.findall(r'"([a-z0-9_]+)": ([^,]+),', block):
        numerator, _, denominator = expression.partition(" / ")
        table[key] = float(numerator) / float(denominator) if denominator else float(numerator)
    return table


def test_fixture_embeds_exactly_the_predeclared_oracles():
    assert _fixture_expected() == ORACLES


def test_actual_sensible_owner_w01_w22():
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot
    godot = Path(os.environ.get(
        "GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot executable not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script", FIXTURE],
                          timeout_s=180, allowed_exit_codes=(0,))
    payload = json.loads(next(line.split(" ", 1)[1] for line in completed.stdout.splitlines()
                              if line.startswith(PREFIX + " {")))
    assert payload["failures"] == []
    assert payload["groups"] == [f"W{i:02}" for i in range(1, 23)]
    assert payload["checks"] == CHECKS
    assert set(payload["observations"]) == set(ORACLES)
    assert payload["observations"] == pytest.approx(ORACLES, rel=1e-12, abs=1e-9)
    assert PREFIX + "_PASS" in completed.stdout


def _product_resources():
    for folder in ["sim", "editor", "ui", "view", "scenes", "scenarios", "tools", "addons"]:
        for path in (ROOT / folder).rglob("*"):
            if path.is_file() and path.suffix in {".gd", ".tscn", ".tres", ".json", ".cfg"}:
                yield path
    yield ROOT / "Main.gd"
    yield ROOT / "project.godot"


def test_owner_composes_canonical_owners_without_a_second_physics():
    source = MODEL.read_text(encoding="utf-8")
    assert source.startswith("extends RefCounted\n")
    assert re.findall(r'preload\("([^"]+)"\)', source) == [
        "res://sim/fire/PrescribedFuelReleaseModel.gd", "res://sim/fire/FuelMassBudgetModel.gd"]
    for call in ["Release.initial_progress(", "Release.propose(", "Release.acknowledge(",
                 "Budget.propose_phase_sensible(", "Budget.propose_phase_reference("]:
        assert call in source
    # No integral, stoichiometry, Cp access or private helper of the canonical owners.
    for forbidden in ["SensibleEnthalpyModel", ".evaluate(", ".validate_profile(", "cp_kj_kg_k",
                      "_oxygen_required", "_accepted_masses", "_oxidation_quantities", "_integral(",
                      "8.0 / 3.0", "11.0 / 3.0", "mass_fractions", "liquid_heat_kj_kg",
                      "vapour_heat_kj_kg", "FileAccess", "@export", "await ", "signal ",
                      "extends Node", "get_tree", "_enabled"]:
        assert forbidden not in source
    assert re.findall(r"(?<!pre)load\(", source) == []
    assert source.count("SimulationEngine") == 1  # Scope comment only.
    assert source.count(".SensibleProperties.") == 1  # Reference temperature, via the ledger.


def test_owner_has_one_aggregate_root_and_a_closed_api():
    source = MODEL.read_text(encoding="utf-8")
    assert re.findall(r"^var (\w+)", source, re.M) == ["_context", "_owned"]
    # The root is replaced whole, exactly at initialize, commit and restore.
    assert len(re.findall(r"^\t+_owned = ", source, re.M)) == 3
    assert re.search(r"_owned(\[[^\]]+\])+ *[-+*/]?=(?!=)", source) is None
    assert len(re.findall(r"^\t+_context = ", source, re.M)) == 1
    assert re.search(r"_context(\[[^\]]+\])+ *[-+*/]?=(?!=)", source) is None
    public = [name for name in re.findall(r"^(?:static )?func (\w+)\(", source, re.M)
              if not name.startswith("_")]
    assert public == ["initialize", "snapshot", "preview_step", "commit_step", "restore"]
    # Commit takes an intent and a generation, never a candidate.
    assert "func commit_step(request: Variant, expected_generation: Variant)" in source
    flags = re.findall(r'"(\w*(?:approval|activation|integration)\w*)": (\w+)', source)
    assert len(flags) == 4 and all(value == "false" for _, value in flags)
    for schema in ["g3_prescribed_sensible_context_v1", "g3_prescribed_sensible_seed_v1",
                   "g3_prescribed_sensible_request_v1", "g3_prescribed_sensible_snapshot_v1",
                   "prescribed_sensible_phase_controller_v1"]:
        assert source.count('"' + schema + '"') == 1


def test_owner_is_not_loaded_by_product():
    for path in _product_resources():
        if path != MODEL:
            assert NAME not in path.read_text(encoding="utf-8", errors="replace"), path.relative_to(ROOT)


def test_canonical_owners_have_only_the_isolated_consumers():
    fire = ROOT / "sim/fire"
    reference_caller = fire / "PrescribedPhaseBudgetController.gd"
    allowed = {
        "FuelMassBudgetModel": {fire / "FuelMassBudgetModel.gd", reference_caller, MODEL},
        "PrescribedFuelReleaseModel": {fire / "PrescribedFuelReleaseModel.gd", reference_caller, MODEL},
        "propose_phase_sensible": {fire / "FuelMassBudgetModel.gd", MODEL},
        "PrescribedPhaseBudgetController": {reference_caller},
    }
    texts = {path: path.read_text(encoding="utf-8", errors="replace") for path in _product_resources()}
    for token, files in allowed.items():
        users = {path for path, text in texts.items() if token in text}
        assert users <= files, (token, sorted(str(path.relative_to(ROOT)) for path in users - files))


@pytest.mark.parametrize("name, expected", [
    ("PrescribedFuelReleaseModel", "db58278f2fff141d31148301095d41234f3732a66fa4140f74abfbaff483897d"),
    ("PrescribedPhaseBudgetController", "41e6e36768eb386f5b9c6f9e9cb5b1e002227526cfef5d013926f8a595e4e6c6"),
    ("FuelMassBudgetModel", "7ab01e1628441c048d55a45a512fc85aed8347dbd8140a29c98160e82fcd3f12"),
    # Helper pin moved on 2026-10-06: its loop became the shared `integrate`; synthetic results are bit-identical.
    ("SensibleEnthalpyModel", "272de43f4a2b9fb1801c3924b08489c4b9d4d8c89026e576e3b4a8e62e796750"),
])
def test_previous_owners_remain_frozen(name, expected):
    raw = (ROOT / f"sim/fire/{name}.gd").read_bytes().replace(b"\r\n", b"\n")
    assert hashlib.sha256(raw).hexdigest() == expected


def test_previous_budget_functions_remain_byte_frozen():
    from tests.test_g3_sensible_phase_budget import test_old_budget_functions_remain_byte_frozen
    test_old_budget_functions_remain_byte_frozen()


def test_predeclared_mutants_have_one_real_anchor_each():
    from scripts.simulation.run_g3_sensible_owner_mutations import MUTATIONS, prepared_variants
    source = MODEL.read_text(encoding="utf-8")
    variants = prepared_variants(source)
    assert len(variants) == len(MUTATIONS) == MUTANTS
    assert [name[:3] for name in variants] == [f"O{i:02}" for i in range(1, MUTANTS + 1)]
    assert all(mutant != source for mutant in variants.values())
    assert len(set(variants.values())) == MUTANTS
    assert MODEL.read_text(encoding="utf-8") == source


def test_isolated_mutation_projects_copy_every_dependency():
    from scripts.simulation import run_g3_sensible_owner_mutations as campaign
    source = MODEL.read_text(encoding="utf-8")
    needed = {ROOT / path.removeprefix("res://") for path in re.findall(r'preload\("([^"]+)"\)', source)}
    needed.add(ROOT / "sim/fire/SensibleEnthalpyModel.gd")  # Preloaded by the ledger.
    assert needed == set(campaign.DEPENDENCIES)
    assert campaign.MODEL == MODEL and campaign.FIXTURE == FIXTURE and campaign.PREFIX == PREFIX


@pytest.mark.parametrize("stdout, stderr, code", [
    ("", "", 1),
    (PREFIX + ' {"failures":["behavioural"]}', "Parse Error", 1),
    (PREFIX + ' {"failures":["behavioural"]}', "SCRIPT ERROR", 1),
    (PREFIX + ' {"failures":["behavioural"]}', "", -1),
    (PREFIX + ' {"failures":["behavioural"]}', "", 0),
    (PREFIX + ' {"failures":[]}', "", 1),
    (PREFIX + " {not json", "", 1),
])
def test_infrastructure_faults_are_invalid_never_kills(stdout, stderr, code):
    from scripts.simulation.run_g3_sensible_owner_mutations import verdict_of
    verdict, payload, reason = verdict_of(stdout, stderr, code)
    assert verdict == "invalid" and payload == {} and reason


def test_only_a_behavioural_failure_is_a_kill():
    from scripts.simulation.run_g3_sensible_owner_mutations import verdict_of
    assert verdict_of(PREFIX + ' {"failures":["oracle"]}', "", 1)[0] == "killed"
    assert verdict_of(PREFIX + ' {"failures":[]}\n' + PREFIX + "_PASS", "", 0)[0] == "pass"
