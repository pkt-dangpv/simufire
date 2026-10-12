"""The trace checker is falsified offline; no Godot launch."""
import copy
import json

import pytest

from scripts.simulation import run_g3_o2_m3_checks as runner


def row():
    return {"state": "armed", "failure": "", "rooms": {"0": {"heat_kj": 1000.0}},
            "selections": {"0": {"id": 1, "available_kg": 0.08}},
            "operations": [
                {"kind": "combustion_reservation", "room": 0, "selection_id": 1,
                 "fraction": 0.5, "accepted_heat_MJ": 1.0, "reserved_kg": 0.076,
                 "requested_kg": 0.152},
                {"kind": "consume", "room": 0, "cause": "accepted_combustion",
                 "applied_kg": 0.076, "clipped_kg": 0.0}]}


def test_heat_trace_accepts_exact_backing_and_a_no_fire_tick(tmp_path):
    data = row()
    idle = copy.deepcopy(data)
    idle["operations"] = []
    path = tmp_path / "trace.jsonl"
    path.write_text(json.dumps(data) + "\n" + json.dumps(idle) + "\n", encoding="utf-8")
    result = runner.heat_budget(path)
    assert result["steps"] == 2 and result["limited_steps"] == 1
    assert result["heat_MJ"] == 1.0 and result["consumed_kg"] == 0.076
    assert result["largest_step_gap_kg"] == 0.0


@pytest.mark.parametrize("defect", ["refusal", "heat", "clip", "fraction", "nan", "unavailable",
                                   "other_selection", "double_reserve", "double_debit", "no_debit", "old_sink"])
def test_heat_trace_rejects_declared_accounting_defects(tmp_path, defect):
    data = row()
    reserve, debit = data["operations"]
    if defect == "refusal":
        data["state"] = "rejected"
    elif defect == "heat":
        data["rooms"]["0"]["heat_kj"] *= 2
    elif defect == "clip":
        debit["clipped_kg"] = 0.01
    elif defect == "fraction":
        reserve["fraction"] = 1.01
    elif defect == "nan":
        reserve["accepted_heat_MJ"] = float("nan")
    elif defect == "unavailable":
        data["selections"]["0"]["available_kg"] = 0.001
    elif defect == "other_selection":
        reserve["selection_id"] = 2
    elif defect == "double_reserve":
        data["operations"].append(copy.deepcopy(reserve))
    elif defect == "double_debit":
        data["operations"].append(copy.deepcopy(debit))
    elif defect == "no_debit":
        data["operations"].pop()
    else:
        debit["cause"] = "fire_sink_room_inventory"
    path = tmp_path / "trace.jsonl"
    path.write_text(json.dumps(data) + "\n", encoding="utf-8")
    with pytest.raises(RuntimeError):
        runner.heat_budget(path)


def test_empty_trace_cannot_pass(tmp_path):
    path = tmp_path / "trace.jsonl"
    path.write_text("", encoding="utf-8")
    with pytest.raises(RuntimeError, match="empty"):
        runner.heat_budget(path)


def test_new_sink_oracle_is_explicit_and_historical_cap_remains_the_default():
    data = row()
    volume = 48.0
    conversion = 1.2 * 0.031998 / 0.0289647
    before = 1.0
    after = before - 0.076
    data.update({"time_s": 1.0, "step": 1, "transit_kg": 0.0,
                 "transit_entries": 0, "transit_to": {},
                 "before": {"inventory_kg": {"0": before}, "transit_kg": 0.0, "due": {}}})
    data["rooms"]["0"].update({"volume_m3": volume, "inventory_kg": after,
                               "power_kw": 1000.0, "transport_kg": 0.0,
                               "o2": after / (volume * conversion), "debit_room_kg": 0.076,
                               "exterior_kg": 0.0, "oxygen_the_fire_read": before / (volume * conversion),
                               "fire_reads": "room_inventory"})
    data["operations"][1]["selection_id"] = 1
    data["selections"]["0"].update({"deposit": "room_inventory", "served_to": ["fire", "sink"],
                                    "mole_fraction": before / (volume * conversion), "available_kg": before})
    scenario = {"engine_overrides": {"ach_infiltration": 0.0}}
    old = runner.house.evaluate_on([data], scenario)
    current = runner.house.evaluate_on([data], scenario, sink_policy="accepted")
    assert old["budget"]["oracle_gap_kg"] == pytest.approx(0.026)
    assert not old["budget"]["closes_in_every_step"]
    assert current["budget"]["closes_in_every_step"]
    assert current["budget"]["oracle_gap_kg"] < 1e-9
    with pytest.raises(ValueError, match="unknown sink policy"):
        runner.house.evaluate_on([data], scenario, sink_policy="anything")


@pytest.mark.parametrize("defect", [None, "timeout", "dialog", "residual", "cleanup",
                                   "wrapper", "no_child", "native", "script"])
def test_case_health_uses_actual_outer_monitor_and_rejects_unhealthy_runs(tmp_path, defect):
    health = {"wrapper_exit_code": 0, "timed_out": False, "error_dialogs": [],
              "windows_error_ui_suppressed": True, "post_exit_observation_s": 2.5,
              "residual_godot_processes": [], "process_quiescent": True,
              "cleanup_terminated_pids": [], "observed_godot_processes": [{"exit_code": 0}]}
    if defect == "timeout":
        health["timed_out"] = True
    elif defect == "dialog":
        health["error_dialogs"] = [{"pid": 7}]
    elif defect == "residual":
        health["residual_godot_processes"] = [{"pid": 7}]
        health["process_quiescent"] = False
    elif defect == "cleanup":
        health["cleanup_terminated_pids"] = [7]
    elif defect == "wrapper":
        health["wrapper_exit_code"] = 1
    elif defect == "no_child":
        health["observed_godot_processes"] = []
    elif defect == "native":
        health["observed_godot_processes"][0]["exit_code"] = 0xC0000005
    (tmp_path / "monitor.health.json").write_text(json.dumps(health), encoding="utf-8")
    (tmp_path / "monitor.stdout.log").write_text("", encoding="utf-8")
    (tmp_path / "monitor.stderr.log").write_text("SCRIPT ERROR" if defect == "script" else "", encoding="utf-8")
    if defect is None:
        assert runner.verified_case_health(tmp_path) == health
    else:
        with pytest.raises(RuntimeError):
            runner.verified_case_health(tmp_path)
