"""Stage M1 of the oxygen authority: room inventory and transit as state, switch off.

Offline. The record was produced by ``scripts/simulation/run_g3_o2_room_inventory.py``
on the real engine through the monitored launcher; here it is read, bound to the code
it speaks of and checked against what this stage promised:

* the tests of M0 fail on the engine before the stage, for the missing behaviour;
* every budget closes within 1e-9 kg in every step of every declared case;
* every declared mutant dies where it was declared it would;
* the historical route, switch off, gives the figures it gave before;
* the code keeps the contract: one owner, no clamp, no layer number, no gas mass.

Nothing here judges fire behaviour, CO, FED or SVV.
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
RECORD = ROOT / "docs" / "validation" / "G3_O2_ROOM_INVENTORY_M1_2026-10-10.json"
REPORT = ROOT / "docs" / "validation" / "G3_O2_ROOM_INVENTORY_M0_M1_2026-10-10.md"
FIXTURE = ROOT / "tests" / "fixtures" / "g3_o2_room_inventory.gd"
OWNER = ROOT / "sim" / "core" / "RoomOxygenInventory.gd"
OXYGEN = ROOT / "sim" / "core" / "OxygenExchangeSystem.gd"
GAS = ROOT / "sim" / "core" / "GasExchangeSystem.gd"
ENGINE = ROOT / "sim" / "core" / "SimulationEngine.gd"
ROOM = ROOT / "sim" / "building" / "RoomModel.gd"
RUNNER = ROOT / "scripts" / "simulation" / "run_g3_o2_room_inventory.py"
MUTATIONS = ROOT / "scripts" / "simulation" / "run_g3_o2_room_inventory_mutations.py"
GAP_KG = 1.0e-9
GROUPS = 14
MEASURED_CASES = (
    "rest", "controlled_demand_dt_0.5", "controlled_demand_dt_0.25", "real_fire_dt_0.25", "real_fire_dt_0.125",
    "transport", "exterior_dt_0.5", "exterior_dt_0.25", "open_and_close", "two_layers", "collapse", "cap",
)
# Left as they were: the isolated source of the bench and the combustion system.
PROTECTED = {
    "sim/fire/PrescribedObjectHrrSource.gd": "f8a39d8312a6ef0117ea37eeec3df7fb7858f212d6c32539ac3d41e850d6c3c4",
    "sim/fire/CombustionSystem.gd": "241398b06ac898dbe131ab53ccb023353382c01144298a365ec4ea4b43aff035",
}


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


@pytest.fixture(scope="module")
def mutation_runner():
    return _load(MUTATIONS)


# ---------------------------------------------------------------- the record

def test_the_record_belongs_to_the_code_it_speaks_of(record):
    for relative, digest in record["sources_sha256"].items():
        current = hashlib.sha256((ROOT / relative).read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        assert current == digest, f"{relative} changed after the record was written: run the stage again"


def test_the_two_protected_files_are_the_ones_of_before(record):
    for relative, digest in PROTECTED.items():
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest, relative
        assert record["untouched_sha256"][relative] == digest
    assert all(record["untouched_equal_to_before_m1"].values())


def test_the_tests_of_m0_fail_before_the_stage_for_the_missing_behaviour(record):
    before = record["before_m1"]
    assert before["script_errors"] == 0, "a harness error is not a failed test"
    assert before["returncode"] == 1 and before["pass_marker"] is False
    assert before["restored_byte_for_byte"] is True
    assert len(before["groups"]) == GROUPS
    assert sorted(before["failures_by_group"]) == [f"B{index:02d}" for index in range(1, GROUPS + 1)], \
        "every group must fail on an engine without the mode"
    assert before["failure_count"] > 100
    assert any("the engine has the switch" in item for item in before["first_failures"])


def test_the_acceptance_passes_on_the_real_engine(record):
    acceptance = record["acceptance"]
    assert acceptance["failure_count"] == 0 and acceptance["failures_by_group"] == {}
    assert acceptance["returncode"] == 0 and acceptance["pass_marker"] is True
    assert acceptance["script_errors"] == 0
    assert len(acceptance["groups"]) == GROUPS and acceptance["checks"] >= 280
    assert set(MEASURED_CASES) <= set(acceptance["observations"])


@pytest.mark.parametrize("case", MEASURED_CASES)
def test_every_budget_closes_in_every_step(record, case):
    """Three budgets, the worst step of the case: by operations room by room, of the
    building with its transit, and by closed form with no operation read."""
    measured = record["acceptance"]["observations"][case]
    assert measured["inventory_read"] is True
    for key in ("room_gap_kg", "building_gap_kg", "oracle_gap_kg"):
        assert 0.0 <= measured[key] <= GAP_KG, (case, key, measured[key])
    assert record["budget_gap_accepted_kg"] == GAP_KG


def test_the_debit_is_the_demand_of_the_heat(record):
    observations = record["acceptance"]["observations"]
    for step in ("0.5", "0.25"):
        measured = observations[f"controlled_demand_dt_{step}"]
        # 20 kW for 120 s at 0.076 kg/MJ.
        assert measured["consumed_kg"] == pytest.approx(0.1824, abs=GAP_KG)
        assert measured["clipped_kg"] == 0.0 and measured["largest_debit_error_kg"] <= GAP_KG
    for step in ("0.25", "0.125"):
        measured = observations[f"real_fire_dt_{step}"]
        assert measured["heat_MJ"] > 5.0
        assert measured["consumed_kg"] == pytest.approx(0.076 * measured["heat_MJ"], abs=GAP_KG)
        assert measured["largest_transit_kg"] > 1.0e-4 and measured["delayed"] > 0, "the transit must have been exercised"
        assert measured["entries_well_formed"] is True


def test_no_number_ends_richer_than_its_source(record):
    observations = record["acceptance"]["observations"]
    for case in MEASURED_CASES:
        assert observations[case]["highest_x"] <= 0.209 + 1.0e-12, case
        assert observations[case]["lowest_inventory_kg"] >= 0.0, case
    # The layers moved in these two and the inventory did not: no operation at all.
    assert observations["two_layers"]["operations"] == 0 and observations["collapse"]["operations"] == 0


def test_what_the_cap_clips_is_recorded(record):
    measured = record["acceptance"]["observations"]["cap"]
    requested = 10 * 20000.0 / 1000.0 * 0.076 * 0.5
    assert measured["clipped_kg"] > 0.5
    assert measured["consumed_kg"] + measured["clipped_kg"] == pytest.approx(requested, abs=GAP_KG)
    assert measured["consumed_kg"] == pytest.approx(measured["expected_consumed_kg"], abs=GAP_KG)


def test_a_reset_gives_the_same_run_again(record):
    measured = record["acceptance"]["observations"]["reset_and_reuse"]
    assert measured["first_digest"] == measured["second_digest"] == measured["fifth_digest"]
    assert len(measured["first_digest"]) == 64 and measured["largest_transit_kg"] > 0.0


def test_what_m1_does_not_cover_is_refused_by_name(record):
    observations = record["acceptance"]["observations"]
    sealed = observations["refused sealed room on fire"]["rejection"]
    assert sealed["reason"] == "route_not_supported_in_m1" and sealed["route"] == "fire_sink_outside_the_room_inventory"
    exterior = observations["refused exterior door with a fire"]["rejection"]
    assert exterior["route"] == "exterior_opening_with_temperature_difference"
    # The sealed room is refused when it burns, not for being sealed: at rest it is a supported case.
    assert observations["rest"]["steps"] == 240 and observations["rest"]["operations"] > 0


def test_the_historical_route_gives_the_figures_it_gave(record):
    historical = record["historical_route"]
    assert historical["identical_figure_by_figure"] is True and historical["differing"] == {}
    assert historical["published_record_rewritten"] is False
    assert len(historical["hypotheses_compared"]) >= 13


# ---------------------------------------------------------------- the mutations

def test_the_record_carries_the_mutations_of_the_runner_unchanged(record, mutation_runner):
    declared = mutation_runner.plan()
    ran = {item["name"]: item for item in record["mutations"]["results"] if item["name"] != "control"}
    assert set(ran) == set(declared)
    for name, item in declared.items():
        for key in ("file", "defect", "expected_in", "declared_with_the_plan"):
            assert ran[name][key] == item[key], (name, key)
    assert sum(item["declared_with_the_plan"] for item in declared.values()) == 8


def test_the_mutation_anchors_still_exist(mutation_runner):
    mutation_runner.prepared()


def test_every_mutant_dies_where_it_was_declared(record):
    summary = record["mutations"]
    assert summary["control"] == "pass" and summary["originals_intact"] is True
    assert summary["survivors"] == [] and summary["invalid"] == [] and summary["killed_elsewhere"] == []
    assert summary["declared"] == summary["executed"] == summary["killed"] == summary["killed_where_expected"]
    for item in summary["results"]:
        if item["name"] == "control":
            continue
        assert item["verdict"] == "killed" and item["seen_where_expected"] is True, item["name"]
        assert item["expected_in"] in item["groups_with_failures"], item["name"]
        assert item["reason"] == "", f"{item['name']}: a script or monitor error is not a kill"


# ---------------------------------------------------------------- the contract in the code

def test_the_switch_is_off_not_exported_and_named_nowhere_else():
    engine = _text(ENGINE)
    assert "\nvar o2_room_inventory_enabled: bool = false\n" in engine
    assert "@export var o2_room_inventory" not in engine
    users = set()
    for folder in ("sim", "editor", "ui", "view", "scenarios", "scenes", "tools", "addons", "assets", "config"):
        for path in (ROOT / folder).rglob("*"):
            if path.is_file() and path.suffix in {".gd", ".tscn", ".tres", ".json", ".cfg"}:
                if "o2_room_inventory" in path.read_text(encoding="utf-8", errors="ignore"):
                    users.add(path.relative_to(ROOT).as_posix())
    assert users == {"sim/core/SimulationEngine.gd"}
    for path in (ROOT / "project.godot", ROOT / "Main.gd", ROOT / "scripts/check_product.py", ROOT / "scripts/run_scenario.py"):
        if path.is_file():
            assert "o2_room_inventory" not in path.read_text(encoding="utf-8", errors="ignore"), path.name


def test_only_the_owner_commits_the_inventory():
    callers = sorted(path.relative_to(ROOT).as_posix() for path in (ROOT / "sim").rglob("*.gd")
                     if "commit_o2_inventory(" in _code(path))
    assert callers == ["sim/building/RoomModel.gd", "sim/core/RoomOxygenInventory.gd"]
    assert _code(ROOM).count("commit_o2_inventory(") == 1, "the room only declares it"
    assert _code(OWNER).count("room.commit_o2_inventory(") == 1, "the owner writes through one place"
    writers = sorted(path.relative_to(ROOT).as_posix() for path in (ROOT / "sim").rglob("*.gd")
                     if re.search(r"\bo2_inventory_kg\s*=[^=]", _code(path)))
    assert writers == ["sim/building/RoomModel.gd"]


def test_the_room_refuses_a_write_that_is_not_the_owners():
    room = _text(ROOM)
    guard = ("\t\tif o2_inventory_authority and not _o2_inventory_commit_open:\n\t\t\to2_unauthorized_write_count += 1\n"
             "\t\t\to2_unauthorized_write_last = value\n\t\t\treturn\n")
    assert room.count(guard) == 2, "the room number and the inventory, both"
    assert "\trelease_o2_inventory()\n\ttemp_upper_c = ambient_temp_c\n" in room, "a reset of the room releases it first"


def test_the_owner_reads_no_layer_number_and_no_gas_mass_and_clamps_nothing():
    owner = _code(OWNER)
    for forbidden in ("o2_upper", "o2_lower", "upper_gas_kg", "lower_gas_kg", "clampf(", "o2_nominal", "class_name", "@export"):
        assert forbidden not in owner, forbidden
    assert "const M_O2_KG_PER_MOL: float = 0.031998" in owner
    assert "const M_DRY_AIR_KG_PER_MOL: float = 0.0289647" in owner
    assert "const REFERENCE_GAS_DENSITY_KG_M3: float = 1.2" in owner
    assert "return mole_fraction * (gas_kg / M_DRY_AIR_KG_PER_MOL) * M_O2_KG_PER_MOL" in owner
    # The transit names both ends and its run, and belongs to the owner.
    for key in ('"donor": donor.id', '"receiver": receiver.id', '"generation": _generation', '"state": ENTRY_IN_TRANSIT'):
        assert key in owner, key


def test_the_conversion_is_the_one_of_dry_air():
    """Independent arithmetic: 0.209 by volume is 0.2309 by mass, and 48 m3 hold 13.299 kg."""
    mass_fraction = 0.209 * 31.998 / 28.9647
    assert mass_fraction == pytest.approx(0.2309, abs=5.0e-5)
    inventory = 0.209 * (48.0 * 1.2 / 0.0289647) * 0.031998
    assert inventory == pytest.approx(48.0 * 1.2 * mass_fraction, rel=1.0e-12)
    assert inventory == pytest.approx(13.2991, abs=1.0e-4)
    assert inventory - 0.209 * 48.0 * 1.2 > 1.0, "not the mole fraction times the mass of gas"


def test_the_law_of_the_sink_is_the_same_and_only_its_owner_changes():
    oxygen = _text(OXYGEN)
    owned = oxygen.split("func _step_owned_room_inventory(", 1)[1].split("\nfunc ", 1)[0]
    assert "var requested: float = (room.hrr_kw / 1000.0) * _fire_sink_kg_per_MJ(room) * dt" in owned
    assert "return float(room.fire.o2_consumption_kg_per_MJ) if room.fire != null else 0.076" in oxygen
    assert "room_o2_inventory.inventory_kg(room) * FIRE_SINK_BULK_CAP_FRACTION" in owned
    assert "const FIRE_SINK_BULK_CAP_FRACTION: float = 0.05" in oxygen
    assert "room.volume_m3() * (ach_infiltration / 3600.0) * air_density_kg_m3 * dt" in owned
    # The historical block is still there, whole, behind the else.
    for line in ("consumed = minf(consumed, o2_mass_kg * FIRE_SINK_BULK_CAP_FRACTION)",
                 "room.o2 = clampf(o2_mass_kg / air_mass_kg, 0.0, o2_nominal)",
                 "_release_pending_o2_deliveries(building, dt, air_density_kg_m3)",
                 "_apply_room_o2_mass_delta(hot_room, hot_room_delta_o2_kg, air_density_kg_m3)"):
        assert oxygen.count(line) == 1, line
    # The route of the sink is decided where it was; M1 refuses the one that is not its own.
    assert 'room_o2_inventory.refuse_route(room, "fire_sink_outside_the_room_inventory", room.hrr_kw)' in owned
    assert "fire_o2_mode_used" not in owned and "o2_lower" not in owned and "o2_upper" not in owned


def test_every_new_branch_is_behind_the_owner_and_null_is_the_historical_route():
    oxygen = _text(OXYGEN)
    assert "\nvar room_o2_inventory = null\n" in oxygen and "\nvar room_o2_inventory = null\n" in _text(GAS)
    assert oxygen.count("if room_o2_inventory != null") == 9
    assert oxygen.count("room_o2_inventory == null") == 1
    assert _text(GAS).count("if room_o2_inventory != null:") == 4
    engine = _text(ENGINE)
    assert engine.count("if _o2_room_inventory != null:") == 3
    assert "\t\tif not room.o2_inventory_authority:\n\t\t\troom.o2 = clampf(room.o2, 0.0, o2_nominal)\n" in engine
    assert "load(O2_ROOM_INVENTORY_PATH).new()" in engine and "preload(\"res://sim/core/RoomOxygenInventory.gd\")" not in engine


def test_the_routes_m1_does_not_own_are_refused_by_name():
    refused = set(re.findall(r'refuse_route\(\w+, "(\w+)"', _text(OXYGEN) + _text(GAS)))
    assert refused == {"fire_sink_outside_the_room_inventory", "exterior_opening_with_temperature_difference",
                       "pressure_venting", "gas_exchange_room_transport", "gas_exchange_parcel_delivery", "ppv"}
    owner = _text(OWNER)
    environment = owner.split("const REQUIRED_ENVIRONMENT: Dictionary = {", 1)[1].split("}", 1)[0]
    assert set(re.findall(r'"(\w+)":', environment)) == {
        "pressure_network_enabled", "diagnostic_bench_enabled", "balance_ledger_enabled", "oxygen_step_runs_after_the_fire",
        "fire_oxygen_mode", "sink_takes_oxygen_from_the_lower_number", "phase2b_canonical_combustion_enabled",
        "fire_o2_canonical_enabled", "fire_o2_mass_tracking_enabled"}


def test_the_life_cycle_retires_above_the_guards():
    engine = _text(ENGINE)
    reset = engine.split("func reset_simulation(", 1)[1].split("\nfunc ", 1)[0]
    assert reset.index("_o2_room_inventory_discard()") < reset.index("if building == null or not is_ready_for_validation():")
    assert reset.index("_o2_room_inventory_arm()") > reset.index("_reset_room_state(room)")
    step = engine.split("\nfunc step(delta: float) -> void:", 1)[1].split("\nfunc ", 1)[0]
    assert step.index("if not o2_room_inventory_failure.is_empty():") < step.index("if building == null or is_finished:")
    assert step.index("_o2_room_inventory.audit_room_numbers()") > step.index("_clamp_rooms(dt)")


# ---------------------------------------------------------------- the fixture

ALLOWED_ENGINE_SETTINGS = {
    "building", "auto_ignite_on_ready", "auto_finish_on_extinction", "enable_logging", "enable_csv_log", "sim_fixed_dt",
    "ach_infiltration", "pressure_network_solver_enabled", "g3_prescribed_thermal_source_enabled", "fire_o2_mode",
    "hvac_system", "_opening_flow_cache",
}


def test_the_fixture_sets_only_what_it_declares_and_takes_its_oracle_from_itself():
    fixture = _text(FIXTURE)
    assert set(re.findall(r"\bengine\.(\w+)\s*=[^=]", fixture)) <= ALLOWED_ENGINE_SETTINGS
    assert fixture.count('engine.set("o2_room_inventory_enabled", value)') == 1
    for forbidden in ("two_zone_solver_enabled", "fire_o2_canonical_enabled", "FileAccess.open", "RoomOxygenInventory.gd",
                      "PrescribedThermalSourceCoupling", "g3_prescribed_thermal_source_case"):
        assert forbidden not in fixture, forbidden
    assert "const O_M_O2_KG_PER_MOL: float = 2.0 * 15.999 / 1000.0" in fixture
    assert "const O_M_DRY_AIR_KG_PER_MOL: float = 28.9647 / 1000.0" in fixture
    assert "const GAP_KG: float = 1.0e-9" in fixture
    oracle = fixture.split("# ---------------------------------------------------------------- oracle", 1)[1].split("# -----", 1)[0]
    assert "inv." not in oracle and "_inv(" not in oracle, "the oracle never calls the owner"
    assert 'print("G3_O2_ROOM_INVENTORY_PASS")' in fixture and "quit(1)" in fixture


# ---------------------------------------------------------------- documents

REQUIRED = (
    "kg de O₂", "fracción molar", "en tránsito", "con signo", "apagado por defecto", "sin `@export`",
    "No se reconcilia", "auxiliares históricos", "M2", "M3", "M4", "CO y FED siguen OFF/NO-GO",
    "G3_O2_ROOM_INVENTORY_M1_2026-10-10.json", "G3_O2_AUTHORITY_2026-10-09.md", "Qué significa «sin tocar el sumidero»",
    "Escritores", "Configuraciones rechazadas", "Aproximaciones", "Lo que no se ha ejecutado",
)


def test_the_report_says_what_was_built_and_what_was_not(record):
    report = _text(REPORT)
    for phrase in REQUIRED:
        assert phrase in report, phrase
    acceptance = record["acceptance"]
    assert f"{acceptance['checks']} comprobaciones" in report
    assert f"{record['before_m1']['failure_count']} fallos" in report
    assert f"{record['mutations']['declared']} mutantes" in report
    for name in ("D01", "T01", "W01", "C01", "R01", "M01", "L01", "K01"):
        assert name in report, name
    assert "@@" not in report, "a placeholder was left in the report"


@pytest.mark.parametrize("relative", [
    "docs/HANDOFF_CURRENT_STATE.md", "docs/validation/G3_O2_AUTHORITY_2026-10-09.md",
    "docs/planning/G3_CO_END_TO_END_CLOSURE_PLAN_2026-09-27.md", "docs/validation/CONTRATO_O2_2026-09-24.md",
])
def test_the_report_is_linked_from_the_documents_that_must_know(relative):
    assert "G3_O2_ROOM_INVENTORY_M0_M1_2026-10-10.md" in _text(ROOT / relative), relative


def test_the_published_diagnosis_is_not_rewritten():
    """The record of 2026-10-09 is evidence of its checkpoint; this stage adds its own."""
    blob = subprocess.run(["git", "show", "7b2e12d9:docs/validation/G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json"],
                          cwd=ROOT, capture_output=True)
    if blob.returncode != 0:
        pytest.skip("the history of the repository is not available")
    current = (ROOT / "docs/validation/G3_O2_AUTHORITY_DIAGNOSIS_2026-10-09.json").read_bytes()
    assert current.replace(b"\r\n", b"\n") == blob.stdout.replace(b"\r\n", b"\n")
