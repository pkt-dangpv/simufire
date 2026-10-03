"""G3-4A: energy account (MJ) of the pyrolysate that today has no inventory.

Design section 16. The account is bookkeeping with state in the engine, not a
physical correction: it has no mass, zone, transport or ignition, and no engine
condition reads it. These tests pin that on the real engine (one monitored
Godot fixture) and statically on the sources:

- with the switch ON every MJ debited from an object ends in fresh heat, the R
  balance, the pool request or the object's account, step by step;
- with it OFF (the previous behaviour) the same identity stays open;
- what leaves the pool without burning reaches a room account, by route;
- ON and OFF give the same physical trajectory;
- the switch is OFF by default and absent from every distributed file.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path

import pytest

from scripts.simulation.audit_default_off_flags import RUNTIME_ACTIVATIONS
from tests.godot_runtime_launcher import run_godot


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/g3_unburned_energy_account.gd"
SWITCH = "fire_unburned_energy_account_enabled"
OBJECT_ACCOUNT = "g3_unburned_energy_account_MJ"
POOL_ACCOUNTS = ("g3_pool_account_capacity_MJ", "g3_pool_account_decay_MJ",
                 "g3_pool_account_suppression_MJ", "g3_pool_account_burnout_MJ")
ACCOUNT_NAME = re.compile(r"g3_unburned_energy_account_MJ|g3_pool_account_\w+_MJ")
WRITERS = {"step_room_fire", "_g3_apply_owned", "_apply_suppression_to_room"}
RESETTERS = {"reset_dynamic_state"}
REPORTERS = {"_g3_ledger_begin", "g3_drain_fuel_ledger", "_g3_account_room_state",
             "_write_fuel_object_state_snapshot"}
GODOT_CANDIDATES = (
    Path(os.environ["GODOT_EXE"]) if os.environ.get("GODOT_EXE") else None,
    Path(r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"),
)


def _godot() -> Path | None:
    return next((path for path in GODOT_CANDIDATES if path is not None and path.exists()), None)


@pytest.fixture(scope="module")
def runs() -> dict:
    godot = _godot()
    if godot is None:
        pytest.skip("Godot 4.7.1 console executable not found")
    completed = run_godot(
        [str(godot), "--headless", "--path", str(ROOT), "--script", str(FIXTURE)],
        timeout_s=600, allowed_exit_codes=(0,),
    )
    assert "G3_UNBURNED_ENERGY_ACCOUNT_PASS" in completed.stdout
    line = next(item for item in completed.stdout.splitlines() if item.startswith("G3_UNBURNED_ENERGY_ACCOUNT {"))
    payload = json.loads(line.split(" ", 1)[1])
    assert payload["failures"] == []
    return payload


# ------------------------------------------------------------------ engine behaviour

def test_with_the_account_every_debited_mj_has_a_place(runs):
    on = runs["account_on"]
    assert on["committed_steps"] > 3000
    assert on["steps_with_unburned"] > 100
    assert on["steps_identity_open"] == 0
    assert on["worst_object_residual_MJ"] <= 1e-12
    assert on["object_account_MJ"] == pytest.approx(on["unburned_rule_MJ"], abs=1e-9)
    assert on["object_account_MJ"] > 0.1


def test_the_previous_behaviour_fails_the_same_identity(runs):
    off, on = runs["account_off"], runs["account_on"]
    assert off["object_account_MJ"] == 0.0
    assert off["steps_identity_open"] == on["steps_with_unburned"] > 100
    assert off["open_identity_MJ"] == pytest.approx(on["object_account_MJ"], abs=1e-9)
    assert off["pool_lost_without_account_MJ"] == pytest.approx(on["pool_account_total_MJ"], abs=1e-12)
    assert off["pool_account_total_MJ"] == 0.0


def test_pool_exits_reach_the_account_of_their_route(runs):
    on, capped = runs["account_on"], runs["capped"]
    assert on["worst_pool_residual_MJ"] <= 1e-12
    assert on["pool_account_decay_MJ"] > 0.0
    assert on["suppression_applied"] and on["pool_account_suppression_MJ"] > 0.0
    assert on["pool_account_capacity_MJ"] == 0.0 and on["pool_account_burnout_MJ"] == 0.0
    assert capped["pool_account_capacity_MJ"] > 0.0
    assert capped["worst_pool_residual_MJ"] <= 1e-12 and capped["steps_identity_open"] == 0
    assert on["pool_account_total_MJ"] == pytest.approx(
        on["pool_account_decay_MJ"] + on["pool_account_suppression_MJ"])


def test_the_account_changes_no_physical_result(runs):
    on, off = runs["account_on"], runs["account_off"]
    for key in ("fuel_debited_MJ", "r_balance_MJ", "pool_end_MJ", "committed_steps", "sim_time_s"):
        assert on[key] == off[key], key
    # The fixture also compares the whole trajectory step by step (11 state values).


def test_accounts_only_grow_reset_with_the_scenario_and_need_an_owned_room(runs):
    for label in ("account_on", "account_off", "capped", "not_owned"):
        assert runs[label]["monotonic"] is True, label
        assert runs[label]["reset_clears"] is True, label
    not_owned = runs["not_owned"]
    assert not_owned["object_account_MJ"] == 0.0 and not_owned["pool_account_total_MJ"] == 0.0
    assert not_owned["pool_lost_without_account_MJ"] > 0.0


# ------------------------------------------------------------------------- sources

def _occurrences(relative: str):
    lines = (ROOT / relative).read_text(encoding="utf-8").split("\n")
    function = ""
    for number, line in enumerate(lines, start=1):
        match = re.match(r"^(?:static )?func (\w+)\(", line)
        if match:
            function = match.group(1)
        stripped = line.strip()
        if stripped.startswith("#") or not ACCOUNT_NAME.search(stripped):
            continue
        yield number, function, stripped


SOURCES = ("sim/fire/CombustionSystem.gd", "sim/core/SimulationEngine.gd", "sim/building/RoomModel.gd",
           "sim/fire/FuelObjectModel.gd", "tools/run_scenario_headless.gd")


def test_no_engine_condition_reads_the_account():
    seen = 0
    for relative in SOURCES:
        for number, function, line in _occurrences(relative):
            seen += 1
            where = f"{relative}:{number} in {function}: {line}"
            if re.match(r"^var g3_\w+_MJ: float = 0\.0$", line):
                continue
            if re.match(r"^g3_\w+_MJ = 0\.0$", line):
                assert function in RESETTERS, where
                continue
            if re.match(r"^(room|obj)\.g3_\w+_MJ \+= ", line):
                assert function in WRITERS, where
                continue
            assert function in REPORTERS, where
            assert not re.search(r"\bif\b|\band\b|\bor\b|[<>]|==|!=|minf\(|maxf\(|\*|/", line), where
    assert seen >= 20


def test_the_account_is_written_nowhere_else_in_the_project():
    allowed = set(SOURCES)
    for folder in ("sim", "editor", "ui", "view", "tools", "scenes"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.suffix not in (".gd", ".tscn", ".json", ".tres") or not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            text = path.read_text(encoding="utf-8", errors="ignore")
            if ACCOUNT_NAME.search(text):
                assert relative in allowed, relative


def test_switch_is_off_by_default_and_only_reaches_the_context_when_on():
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert f"@export var {SWITCH}: bool = false\n" in engine
    assert engine.count(f'context["{SWITCH}"] = true') == 1
    assert f"\tif {SWITCH}:\n\t\tcontext[\"{SWITCH}\"] = true\n" in engine
    combustion = (ROOT / "sim/fire/CombustionSystem.gd").read_text(encoding="utf-8")
    assert f'const G3_UNBURNED_ACCOUNT_SWITCH: String = "{SWITCH}"\n' in combustion
    assert ("var g3_account: bool = g3_owned and bool(context.get(G3_UNBURNED_ACCOUNT_SWITCH, false))\n"
            in combustion)


def test_no_distributed_or_product_file_sets_the_switch():
    # The files that declare, read or document the switch. None of them turns it on.
    engine_side = set(SOURCES)
    turned_on = re.compile(SWITCH + r"\"?\s*[:=]\s*true")
    for folder in ("sim", "editor", "ui", "view", "scenes", "scenarios", "tools"):
        base = ROOT / folder
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if not path.is_file() or path.suffix not in (".gd", ".tscn", ".json", ".tres", ".cfg"):
                continue
            relative = path.relative_to(ROOT).as_posix()
            text = path.read_text(encoding="utf-8", errors="ignore")
            if relative in engine_side:
                assert not turned_on.search(text.replace(f'context["{SWITCH}"] = true', "")), relative
                continue
            assert SWITCH not in text, relative
    assert SWITCH not in (ROOT / "project.godot").read_text(encoding="utf-8", errors="ignore")


def test_the_account_is_not_saved_in_scenarios_or_exported_as_state():
    for relative in ("sim/BuildingModel.gd", "sim/core/SimulationStateBuilder.gd", "sim/core/SimulationLogWriter.gd"):
        text = (ROOT / relative).read_text(encoding="utf-8")
        assert not ACCOUNT_NAME.search(text), relative
        assert SWITCH not in text, relative


def test_sources_say_it_is_an_account_and_not_gas():
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    block = engine.split(f"@export var {SWITCH}")[0].rsplit("@export var", 1)[1]
    assert "ES CONTABILIDAD, NO FÍSICA" in block and "no es gas" in block
    fuel_object = (ROOT / "sim/fire/FuelObjectModel.gd").read_text(encoding="utf-8")
    assert "NO es gas ni inventario físico" in fuel_object.split(f"var {OBJECT_ACCOUNT}")[0][-400:]
    room = (ROOT / "sim/building/RoomModel.gd").read_text(encoding="utf-8")
    for name in POOL_ACCOUNTS:
        assert f"var {name}: float = 0.0\n" in room


def test_the_auditor_backs_the_switch_with_this_fixture():
    assert RUNTIME_ACTIVATIONS[SWITCH] == (
        "tests/fixtures/g3_unburned_energy_account.gd", "G3_UNBURNED_ENERGY_ACCOUNT_PASS")
    assert "G3_UNBURNED_ENERGY_ACCOUNT_PASS" in FIXTURE.read_text(encoding="utf-8")


def test_the_headless_snapshot_adds_the_account_only_with_the_switch():
    runner = (ROOT / "tools/run_scenario_headless.gd").read_text(encoding="utf-8")
    assert runner.count(f"if engine.{SWITCH}:") == 2
    snapshot = runner.split("func _write_fuel_object_state_snapshot")[1].split("\nfunc ")[0]
    for line in snapshot.split("\n"):
        if ACCOUNT_NAME.search(line) or "g3_pool_account_MJ" in line or 'last_room["retained_unburned_MJ"]' in line:
            assert line.startswith("\t\t\t"), line
