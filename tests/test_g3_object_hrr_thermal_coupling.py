"""Thermal coupling bench of the prescribed HRR source: oracle, contract and the real engine.

A diagnostic bench: energy and an equivalent oxygen debit of one room. It validates no
temperature, no combustion of the furniture, no CO, FED or SVV.

The offline tests pin the independent oracle and the two corrections recorded before any
coupled run (what a finite step returns, and what the oxygen debit is). The engine test
launches Godot through the monitor and judges the bench again outside GDScript.
"""

from __future__ import annotations

import bisect
import json
import math
import os
from pathlib import Path

import pytest

from scripts.simulation import build_g3_object_hrr_coupling_oracle as oracle_builder
from scripts.simulation import build_g3_object_hrr_source as source_builder

ROOT = Path(__file__).resolve().parents[1]
ORACLE = json.loads(oracle_builder.ORACLE.read_text(encoding="ascii"))
SOURCE = json.loads(source_builder.FIXTURE.read_text(encoding="utf-8"))
TIMES = [float(item["time_s"]) for item in SOURCE["source"]["samples"]]
VALUES = [float(item["hrr_kw"]) for item in SOURCE["source"]["samples"]]
ENERGY_KJ = 115093.655
DESIGN = ROOT / "docs" / "validation" / "G3_OBJECT_HRR_SOURCE_COUPLING_DESIGN_2026-10-08.md"
FROZEN = {
    "sim/fire/PrescribedObjectHrrSource.gd": "f8a39d8312a6ef0117ea37eeec3df7fb7858f212d6c32539ac3d41e850d6c3c4",
    "tests/fixtures/g3_object_hrr_source_test016.json": "13d7cd65a34186a57564f6de6db670b768e0815a18fb3b5b0c6d382e12a07b57",
}


def _prefix() -> list[float]:
    out = [0.0]
    for index in range(1, len(TIMES)):
        out.append(out[-1] + 0.5 * (VALUES[index - 1] + VALUES[index]) * (TIMES[index] - TIMES[index - 1]))
    return out


PREFIX = _prefix()


def _cumulative(time_s: float) -> float:
    """Energy from the ignition, by another route than the builder: prefix sums and one partial trapezoid."""
    low = min(bisect.bisect_right(TIMES, time_s) - 1, len(TIMES) - 2)
    span = time_s - TIMES[low]
    slope = (VALUES[low + 1] - VALUES[low]) / (TIMES[low + 1] - TIMES[low])
    return PREFIX[low] + span * (VALUES[low] + 0.5 * slope * span)


def _near(actual: float, expected: float) -> bool:
    tolerance = ORACLE["numerical_tolerance"]
    return abs(actual - expected) <= tolerance["abs_kj"] + tolerance["rel"] * max(abs(actual), abs(expected))


# ---------------------------------------------------------------- frozen inputs and oracle

def test_the_isolated_owner_and_its_data_are_the_approved_bytes() -> None:
    import hashlib
    for relative, digest in FROZEN.items():
        assert hashlib.sha256((ROOT / relative).read_bytes().replace(b"\r\n", b"\n")).hexdigest() == digest, relative
    assert ORACLE["source_identity"] == SOURCE["expected_identity"]
    assert ORACLE["run"] == "Test016" and ORACLE["reserved_runs_not_used"] == ["Test021"]


def test_the_oracle_is_rebuilt_byte_for_byte() -> None:
    text = oracle_builder.render(oracle_builder.build())
    assert text == oracle_builder.ORACLE.read_bytes().replace(b"\r\n", b"\n").decode("ascii")
    assert ORACLE["schema"] == oracle_builder.SCHEMA
    code = Path(oracle_builder.__file__).read_text(encoding="utf-8")
    for word in ("PrescribedObjectHrrSource", "godot", "Godot", "subprocess"):
        assert word not in code, word  # shares the table with the owner and nothing else


def test_the_steps_were_declared_and_one_does_not_divide_the_support() -> None:
    assert oracle_builder.STEPS_S == (1.0, 0.7, 2.5) and set(ORACLE["steps"]) == {"1.0", "0.7", "2.5"}
    assert [ORACLE["steps"][key]["divides_the_support"] for key in ("1.0", "0.7", "2.5")] == [True, False, False]
    assert [ORACLE["steps"][key]["steps"] for key in ("1.0", "0.7", "2.5")] == [3768, 5383, 1508]
    assert ORACLE["steps"]["2.5"]["last_interval_s"] == 0.5
    assert 0.0 < ORACLE["steps"]["0.7"]["last_interval_s"] < 0.7


@pytest.mark.parametrize("key", ["1.0", "0.7", "2.5"])
def test_every_step_energy_is_the_integral_by_another_route(key: str) -> None:
    item = ORACLE["steps"][key]
    dt, clock, total = item["dt_s"], 0.0, 0.0
    assert len(item["step_energy_kj"]) == item["steps"]
    for energy in item["step_energy_kj"]:
        end = min(clock + dt, ORACLE["support_end_s"])
        assert _near(energy, _cumulative(end) - _cumulative(clock)) or abs(
            energy - (_cumulative(end) - _cumulative(clock))) < 1.0e-7  # a difference of two large sums
        total += energy
        clock = end
    assert clock == ORACLE["support_end_s"] == 3768.0
    assert abs(total - ENERGY_KJ) < 1.0e-6 and item["total_kj"] == pytest.approx(ENERGY_KJ, abs=1.0e-9)
    assert item["end_of_the_last_step_s"] == 3768.0


@pytest.mark.parametrize("key", ["1.0", "0.7", "2.5"])
def test_the_last_step_neither_loses_nor_doubles_energy(key: str) -> None:
    item = ORACLE["steps"][key]
    # The last interval may be shorter than the step; its energy is spread over the whole step.
    assert item["last_step_power_kw"] * item["dt_s"] == pytest.approx(item["last_step_energy_kj"], rel=1.0e-12)
    assert item["last_step_energy_kj"] == item["step_energy_kj"][-1]
    if not item["divides_the_support"]:
        mean_over_the_interval = item["last_step_energy_kj"] / item["last_interval_s"]
        assert item["last_step_power_kw"] < mean_over_the_interval


# ---------------------------------------------------------------- peak and finite step

def test_a_finite_step_does_not_return_the_instantaneous_peak_closed_form() -> None:
    triangle = ORACLE["peak_and_step"]["synthetic_triangle"]
    assert triangle["instantaneous_peak_kw"] == 100.0
    by_step = {row["dt_s"]: row for row in triangle["steps"]}
    # Written here by hand: slopes of 10 kW/s around a peak of 100 kW at 10 s.
    assert by_step[4.0]["largest_step_power_kw"] == 90.0 and not by_step[4.0]["peak_on_a_step_end"]
    assert by_step[1.0]["largest_step_power_kw"] == 95.0 and by_step[1.0]["peak_on_a_step_end"]
    assert by_step[0.5]["largest_step_power_kw"] == 97.5 and by_step[0.5]["peak_on_a_step_end"]
    for row in triangle["steps"]:
        assert row["largest_step_power_kw"] == row["closed_form_kw"] < 100.0
        assert row["total_kj"] == 1000.0  # the energy does not depend on the step


def test_the_peak_criterion_is_per_step_and_the_instantaneous_peak_is_the_datum() -> None:
    assert ORACLE["instantaneous_peak"] == {"time_s": 1143.0, "hrr_kw": 621.46}
    assert max(VALUES) == 621.46 and VALUES.index(621.46) == 1143
    for key, item in ORACLE["steps"].items():
        assert item["largest_step_power_kw"] < 621.46, key
        assert item["largest_step_power_minus_instantaneous_peak_kw"] == pytest.approx(
            item["largest_step_power_kw"] - 621.46, abs=1.0e-9)
        low, high = item["largest_step_interval_s"]
        assert item["largest_step_power_kw"] == pytest.approx((_cumulative(high) - _cumulative(low)) / item["dt_s"], rel=1.0e-9)
        # No delay: the step that holds 1143 s is the one where the step power is largest in this run.
        assert item["step_holding_the_instantaneous_peak"] == item["largest_step_index"]
        assert low < 1143.0 <= high or low <= 1143.0 < high
    one = ORACLE["steps"]["1.0"]
    assert one["largest_step_power_kw"] == pytest.approx(0.5 * (VALUES[1142] + VALUES[1143]))
    assert one["largest_step_index"] == 1142
    assert ORACLE["steps"]["2.5"]["largest_step_power_kw"] < ORACLE["steps"]["0.7"]["largest_step_power_kw"]


def test_the_oracle_names_the_largest_step_independently() -> None:
    for key, item in ORACLE["steps"].items():
        powers = [energy / item["dt_s"] for energy in item["step_energy_kj"]]
        assert powers.index(max(powers)) == item["largest_step_index"], key
        assert max(powers) == pytest.approx(item["largest_step_power_kw"], rel=1.0e-12)


# ---------------------------------------------------------------- oxygen and radiation of the bench

def test_the_oxygen_debit_is_a_declared_coefficient_not_a_measurement() -> None:
    oxygen = ORACLE["oxygen"]
    sink = (ROOT / "sim/core/OxygenExchangeSystem.gd").read_text(encoding="utf-8")
    assert oxygen["kg_per_MJ"] == 0.076 == oracle_builder.OXYGEN_KG_PER_MJ
    assert "if room.fire != null else 0.076" in sink  # the constant the engine sink already uses
    assert oxygen["whole_run_kg"] == pytest.approx(ENERGY_KJ / 1000.0 * 0.076, rel=1.0e-12)
    assert "not a stoichiometry" in oxygen["what_it_is"] and "not a" in oxygen["what_it_is"]
    # It is not fitted to the oxygen total of the database (8.168 kg) nor to energy over 13.1 MJ/kg (8.786 kg).
    assert abs(oxygen["whole_run_kg"] - 8.168419518) > 0.5 and abs(oxygen["whole_run_kg"] - ENERGY_KJ / 13100.0) > 0.03


def test_the_radiative_fraction_belongs_to_the_case_and_keeps_its_class() -> None:
    rows = ORACLE["radiative_fractions"]
    assert [row["value"] for row in rows] == [0.35, 0.52, 0.4264, 0.6136]
    assert [row["class"] for row in rows] == ["assumed", "open_air_whole_test_estimate", "sensitivity", "sensitivity"]
    assert rows[2]["value"] == pytest.approx(0.52 * 0.82) and rows[3]["value"] == pytest.approx(0.52 * 1.18)
    for row in rows:
        assert row["to_the_gas_kj"] + row["radiative_term_kj"] == pytest.approx(ENERGY_KJ, abs=1.0e-6)
        assert row["radiative_term_kj"] == pytest.approx(ENERGY_KJ * row["value"], rel=1.0e-12)
    assert "never of the source" in ORACLE["radiative_fraction_is"]
    assert SOURCE["source"]["unknown"]["radiative_fraction"] is None


def test_the_corrections_were_written_in_the_design_before_the_bench() -> None:
    text = DESIGN.read_text(encoding="utf-8")
    for needle in ("Correcciones del 08-10, registradas antes de ejecutar el acoplamiento",
                   "demanda equivalente prescrita", "no es una reconstrucción exacta", "A4a", "A4b", "A4c",
                   "621,125 kW", "621,274 kW", "619,663 kW", "0,076 kg/MJ"):
        assert needle in text, needle
    assert "| A4 | Pico 621,46 kW en el paso que contiene los 1143 s" not in text


# ---------------------------------------------------------------- the bounded engine change

import re  # noqa: E402

ENGINE_PATH = ROOT / "sim/core/SimulationEngine.gd"
OXYGEN_PATH = ROOT / "sim/core/OxygenExchangeSystem.gd"
COUPLING_PATH = ROOT / "sim/fire/PrescribedThermalSourceCoupling.gd"
FIXTURE_PATH = ROOT / "tests/fixtures/g3_object_hrr_thermal_coupling.gd"
ENGINE = ENGINE_PATH.read_text(encoding="utf-8")
COUPLING = COUPLING_PATH.read_text(encoding="utf-8")
COMBUSTION_SHA256 = "241398b06ac898dbe131ab53ccb023353382c01144298a365ec4ea4b43aff035"
MARKER = "G3_OBJECT_HRR_THERMAL_COUPLING"
GROUPS = 11
CHECKS = 179327  # of the green run on the final code; a different count means the fixture changed


def _code(text: str) -> str:
    """GDScript without its comments."""
    return "\n".join(line.split("#")[0] for line in text.splitlines())


def _body(text: str, signature: str) -> str:
    start = text.index(signature)
    following = text.find("\nfunc ", start + 1)
    return text[start:following if following > 0 else len(text)]


def test_the_switch_is_not_exported_and_is_off_by_default() -> None:
    for line in ("var g3_prescribed_thermal_source_enabled: bool = false",
                 "var g3_prescribed_thermal_source_case: Dictionary = {}",
                 'var g3_prescribed_thermal_source_failure: String = ""',
                 "var _g3_prescribed_thermal_source = null"):
        assert ("\n" + line + "\n") in ENGINE, line
    assert "@export var g3_prescribed_thermal" not in ENGINE and "@export var _g3_prescribed_thermal" not in ENGINE
    # Loaded by path and only when the switch is on: with it off the module is never read.
    assert ENGINE.count("load(G3_PRESCRIBED_THERMAL_COUPLING_PATH)") == 1
    assert 'preload("res://sim/fire/PrescribedThermalSourceCoupling.gd")' not in ENGINE
    arm = _body(ENGINE, "func _g3_prescribed_thermal_arm() -> void:")
    assert arm.index("if not g3_prescribed_thermal_source_enabled:") < arm.index("load(G3_PRESCRIBED_THERMAL_COUPLING_PATH)")
    assert "class_name" not in _code(COUPLING) and "@export" not in _code(COUPLING)


def test_nothing_of_the_product_reaches_the_bench() -> None:
    allowed = {"sim/core/SimulationEngine.gd", "sim/core/OxygenExchangeSystem.gd", "sim/fire/PrescribedThermalSourceCoupling.gd"}
    users = set()
    for folder in ("sim", "editor", "ui", "view", "scenarios", "scenes", "tools", "addons", "assets"):
        for path in (ROOT / folder).rglob("*"):
            if path.is_file() and path.suffix in {".gd", ".tscn", ".tres", ".json", ".cfg"}:
                text = path.read_text(encoding="utf-8", errors="ignore")
                if "g3_prescribed_thermal" in text or "PrescribedThermalSourceCoupling" in text:
                    users.add(path.relative_to(ROOT).as_posix())
    for path in (ROOT / "project.godot", ROOT / "Main.gd", ROOT / "scripts/check_product.py", ROOT / "scripts/run_scenario.py"):
        if path.is_file() and "g3_prescribed_thermal" in path.read_text(encoding="utf-8", errors="ignore"):
            users.add(path.name)
    assert users == allowed
    oxygen = OXYGEN_PATH.read_text(encoding="utf-8")
    assert oxygen.count("g3_prescribed_thermal_room_ids") == 3  # declared and read from the hooks, used once
    loaders = sorted(path.name for path in (ROOT / "tests/fixtures").glob("*.gd")
                     if "g3_prescribed_thermal" in path.read_text(encoding="utf-8"))
    # The acceptance fixture and the diagnosis of the oxygen writes, which judges nothing.
    assert loaders == ["g3_object_hrr_oxygen_writes_diagnosis.gd", "g3_object_hrr_thermal_coupling.gd"]


def test_the_protected_modules_were_not_touched() -> None:
    import hashlib
    combustion = (ROOT / "sim/fire/CombustionSystem.gd").read_bytes().replace(b"\r\n", b"\n")
    assert hashlib.sha256(combustion).hexdigest() == COMBUSTION_SHA256
    assert "g3_prescribed_thermal" not in combustion.decode("utf-8")


def test_the_coupling_integrates_nothing_and_restores_nothing() -> None:
    code = _code(COUPLING)
    assert "_source.propose(" in code and "_source.confirm(" in code
    # The energy of a step is the integral of the isolated owner; no second law lives here.
    for word in ("lerp", "bsearch", "prefix", "samples", "hrr_curve", "compute_hrr_kw", "_smooth", "fire_time_s"):
        assert word not in code, word
    assert ".restore(" not in code and ".reset(" not in code
    assert not re.search(r"retained_unburned_MJ\s*[-+*/]?=[^=]", code)
    assert not re.search(r"\.(fire|fuel_objects|fuel_energy_MJ|max_hrr_kw|co_kg|co2_kg|hcn_kg|smoke_kg)\s*[-+*/]?=[^=]", code)
    written = sorted(set(re.findall(r"_room\.(\w+)\s*=[^=]", code)))
    assert written == ["burned_hrr_kw", "chi_rad_normal", "combustion_regime", "hrr_kw"]
    assert "energy_kj / dt" in code  # over the whole step


def test_the_hooks_sit_where_the_design_says() -> None:
    step = _body(ENGINE, "func step(delta: float) -> void:")
    order = ["if not g3_prescribed_thermal_source_failure.is_empty():", "_step_fire(dt)",
             "_g3_prescribed_thermal_source.begin_step(dt)", "if not pre_hrr_o2_step:",
             "_g3_prescribed_thermal_source.settle_oxygen()", "thermal_system.step(building, dt, {",
             "_g3_prescribed_thermal_source.settle_heat()", "_step_suppression(dt)",
             'fire_spread_system.step(dt, Callable(self, "ignite_room"))', "_g3_prescribed_thermal_source.end_step()",
             "_clamp_rooms(dt)"]
    positions = [step.index(item) for item in order]
    assert positions == sorted(positions) and all(step.count(item) == 1 for item in order)
    reset = _body(ENGINE, "func reset_simulation(")
    order = ["_g3_prescribed_thermal_discard()", "if building == null or not is_ready_for_validation():",
             "_reset_room_state(room)", "combustion_system.bootstrap_building(building)",
             "_g3_prescribed_thermal_arm()", "ignite_room(start_ignition_room_id)"]
    positions = [reset.index(item) for item in order]
    assert positions == sorted(positions)
    ignite = _body(ENGINE, "func ignite_room(room_id: int) -> void:")
    assert ignite.index("_g3_prescribed_thermal_source.ignite(sim_time_s)") < ignite.index("create_legacy_room_fire(")


def test_the_mutation_plan_is_declared_before_running() -> None:
    from scripts.simulation import run_g3_object_hrr_thermal_coupling_mutations as campaign
    originals, variants = campaign.prepared()  # raises if an anchor is absent or repeated
    assert len(campaign.MUTATIONS) == len(variants) == 43
    assert sorted(originals) == sorted([campaign.COUPLING, campaign.ENGINE, campaign.OXYGEN])
    groups = {line.split('"')[1][:3] for line in FIXTURE_PATH.read_text(encoding="utf-8").splitlines()
              if line.strip().startswith('_group("B')}
    for name, (_relative, old, new, defect, where) in campaign.MUTATIONS.items():
        assert old != new and len(defect) > 20, name
        assert where in groups or where in {"B02", "B03", "B04"}, name
    families = sorted({name[0] for name in campaign.MUTATIONS})
    assert families == ["A", "H", "L", "O", "P", "R", "S"]
    code = Path(campaign.__file__).read_text(encoding="utf-8")
    assert "not restored byte for byte" in code and "sha256_before" in code


def test_the_real_engine_runs_the_bench_against_the_oracle() -> None:
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot

    godot = Path(os.environ.get("GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0, "Godot requires >=6 GiB"
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script", FIXTURE_PATH],
                          timeout_s=900, allowed_exit_codes=(0,))
    output = completed.stdout + completed.stderr
    assert "SCRIPT ERROR" not in output and "Parse Error" not in output
    line = next(line for line in completed.stdout.splitlines() if line.startswith(MARKER + " {"))
    report = json.loads(line.split(" ", 1)[1])
    assert report["failures"] == [] and report["failure_count"] == 0 and MARKER + "_PASS" in completed.stdout
    assert [name[:3] for name in report["groups"]] == ["B%02d" % index for index in range(GROUPS)]
    assert report["checks"] == CHECKS
    seen = report["observations"]
    total, coefficient = ORACLE["total_energy_kj"], ORACLE["oxygen"]["kg_per_MJ"]
    # Judged again here, outside GDScript.
    for key, expected in ORACLE["steps"].items():
        run = seen["whole_run_" + key]
        assert run["state"] == "completed" and run["steps"] == expected["steps"] and run["rejected_kj"] == 0.0
        assert _near(run["accepted_kj"], total), key
        assert abs(run["oxygen_debited_kg"] - total / 1000.0 * coefficient) < 1.0e-10, key
        assert _near(run["to_the_gas_kj"] + run["radiative_term_kj"], run["accepted_kj"]), key
        assert _near(run["largest_step_power_kw"], expected["largest_step_power_kw"]), key
        assert run["largest_step_index"] == expected["largest_step_index"] == expected["step_holding_the_instantaneous_peak"]
        assert run["largest_step_power_kw"] < ORACLE["instantaneous_peak"]["hrr_kw"]
        # The declared regime held with margin; these are diagnostics, not validated values.
        assert 0.209 - run["lowest_room_oxygen"] < 0.01 and run["lowest_layer_interface_m"] > 0.3
        assert abs(run["carbon_dioxide_tracer_highest"] - run["carbon_dioxide_tracer_start"]) < 1.0e-12
    rows = seen["radiative_fractions"]
    assert [row["radiative_fraction"] for row in rows] == [item["value"] for item in ORACLE["radiative_fractions"]]
    assert [row["class"] for row in rows] == [item["class"] for item in ORACLE["radiative_fractions"]]
    for row, expected in zip(rows, ORACLE["radiative_fractions"]):
        assert row["state"] == "completed" and row["accepted_kj"] == rows[0]["accepted_kj"]
        assert row["oxygen_debited_kg"] == rows[0]["oxygen_debited_kg"]
        assert _near(row["to_the_gas_kj"], expected["to_the_gas_kj"]) and _near(row["radiative_term_kj"], expected["radiative_term_kj"])
    crack = seen["small_room_with_a_crack"]
    assert crack["state"] == "outside_declared_regime" and 0.0 < crack["accepted_share"] < 1.0
    assert crack["exit"]["cause"] in ("oxygen_below_the_declared_tolerance", "hot_layer_below_the_declared_height")
    assert crack["exit"]["source_time_s"] < ORACLE["instantaneous_peak"]["time_s"]
    assert _near(crack["accepted_kj"] + crack["rejected_kj"], total)
    by_oxygen = seen["small_room_with_a_crack_oxygen_only"]
    assert by_oxygen["state"] == "outside_declared_regime" and by_oxygen["exit"]["cause"] == "oxygen_below_the_declared_tolerance"
    # The second write: the same demand again, traced apart and never added.
    for key in ORACLE["steps"]:
        run = seen["whole_run_" + key]
        assert abs(run["upper_layer_number_written_kg"] - run["oxygen_debited_kg"]) < 1.0e-10, key
        assert list(run["upper_layer_number_writes_seen"]) == ["full_demand"], key
    # A rejected interval leaves nothing of the source: no oxygen write of the sink, no heat.
    sealed = seen["small_sealed_room"]
    assert sealed["state"] == "outside_declared_regime" and sealed["exit"]["step"] == 0
    assert sealed["exit"]["cause"] == "the_oxygen_sink_would_not_debit_the_room_inventory"
    assert sealed["exit"]["route"] == "lower_layer_number_by_the_plume"
    assert sealed["oxygen_written_by_the_sink_kg"] == 0.0 and sealed["same_as_the_twin_with_the_switch_off"] is True
    assert _near(sealed["rejected_kj"], ORACLE["steps"]["2.5"]["step_energy_kj"][0])
    # A sink that does not do what it said: a failure, with the writes listed apart.
    forged = seen["forged_sink_plan"]
    assert forged["state"] == "failed" and forged["broken_sink_plan"]["room_inventory_debit_kg"] == 0.0
    assert forged["broken_sink_plan"]["primary_sink_debit_kg"] > 0.0
    assert forged["broken_sink_plan"]["upper_layer_number_written_kg"] > 0.0
