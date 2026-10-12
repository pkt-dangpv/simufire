"""Offline corruption witnesses for passive M4-B2 trace analysis; no Godot launch."""
import copy
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.simulation import run_g3_o2_m4_route_capture as runner


def _rows():
    k = runner.KAPPA
    previous = [{"id": 0, "o2_inventory_kg": 1, "room_reference_fraction": .1},
                {"id": 1, "o2_inventory_kg": 2, "room_reference_fraction": .2}]
    final = copy.deepcopy(previous)
    final[0]["o2_inventory_kg"] += .1 * k
    final[1]["o2_inventory_kg"] -= .1 * k
    operation = {"kind": "interior", "law": "symmetric_reference_gas_immediate",
                 "donor": 0, "receiver": 1, "gas_kg": 1,
                 "to_receiver_kg": .1 * k, "to_donor_kg": .2 * k}
    return [{"route": "interior_active", "tick": 0, "event_id": "tick0:call1", "opening_index": 0,
             "before": previous, "after": final,
             "data": {"accepted_reference_gas_kg": 1, "precap_request": None},
             "owner_operations": [operation]},
            {"route": "tick_summary", "tick": 0, "before": previous, "after": final,
             "owner_operations": [copy.deepcopy(operation)]}]


def test_trace_sample_has_reference_conversion_but_no_zonal_eligibility():
    result = runner.analyze_rows(_rows(), expected_ticks=1)
    assert result["max_tick_o2_gap_kg"] <= 1e-9
    assert result["max_reference_conversion_gap_kg"] == 0
    assert result["live_adapter_eligible"] is False
    assert result["zonal_o2_donor_observed"] is False


@pytest.mark.parametrize("defect", ["identity", "ticks", "opening", "conversion", "quantity", "balance", "operation"])
def test_corrupted_trace_cannot_pass_by_aggregate_budget_alone(defect):
    rows = _rows()
    if defect == "identity":
        rows.insert(0, copy.deepcopy(rows[0]))
    elif defect == "ticks":
        rows[-1]["tick"] = 1
    elif defect == "opening":
        rows[0]["opening_index"] = -1
    elif defect == "conversion":
        rows[0]["owner_operations"][0]["to_receiver_kg"] = .1
    elif defect == "quantity":
        rows[0]["data"]["accepted_reference_gas_kg"] = float("nan")
    elif defect == "balance":
        rows[-1]["after"][0]["o2_inventory_kg"] += .01
    else:
        rows[0]["owner_operations"] = []
    with pytest.raises(RuntimeError):
        runner.analyze_rows(rows, expected_ticks=1)


def test_container_operations_are_not_counted_as_extra_physical_transfers():
    rows = _rows()
    container = copy.deepcopy(rows[0])
    container.update({"route": "oxygen_stage_container", "event_id": "tick0:container"})
    rows.insert(0, container)
    result = runner.analyze_rows(rows, expected_ticks=1)
    assert result["interior_reference_gas_kg"] == 1
    assert result["max_tick_o2_gap_kg"] <= 1e-9


def test_fixture_observers_forward_parent_calls_and_do_not_import_partition():
    source = (ROOT / runner.FIXTURE).read_text(encoding="utf-8")
    for method in ("_exchange_room_o2_immediate", "_exchange_room_o2_active_flow",
                   "preview_lower_to_upper_transfer", "apply_lower_to_upper_transfer",
                   "step_pressure_venting", "sync_room_upper_layer"):
        assert source.count("super." + method + "(") == 1
    assert "OxygenReferencePartition" not in source
    assert "o2_inventory_kg =" not in source and "o2_upper =" not in source
    assert "_physics_state(plain) != _physics_state(observed)" in source
    assert '"precap_request": null' in source
    assert '"nonfinite_float": label' in source
    assert "super._ensure_minimal_upper_gas(room, ambient_c)" in source


def test_runner_uses_existing_safe_monitor_and_external_environment():
    source = (ROOT / "scripts/simulation/run_g3_o2_m4_route_capture.py").read_text(encoding="utf-8")
    assert "godot_monitored_launch.run(" in source and "prepare_environment(work)" in source
    assert "subprocess.Popen" not in source and "shell=True" not in source
    assert "physical_validation\": False" in source


def test_analyzer_checks_real_paired_gas_donation_not_auxiliary_oxygen():
    before = {"id": 0, "upper_gas_kg_not_reference_base": 1,
              "lower_gas_kg_not_reference_base": 9, "o2_inventory_kg": 1}
    after = {"id": 0, "upper_gas_kg_not_reference_base": 2,
             "lower_gas_kg_not_reference_base": 8, "o2_inventory_kg": 1}
    event = {"route": "zone_apply", "event_id": "plume", "mechanism": "thermal_plume",
             "before": [before], "after": [after], "data": {"transfer": {"mass_kg": 1}}}
    rows = [event, {"route": "tick_summary", "tick": 0, "before": [before],
                    "after": [after], "owner_operations": []}]
    assert runner.analyze_rows(rows, expected_ticks=1)["physical_plume_gas_kg"] == 1
    rows[0]["after"][0]["lower_gas_kg_not_reference_base"] = 9
    with pytest.raises(RuntimeError):
        runner.analyze_rows(rows, expected_ticks=1)


@pytest.mark.parametrize("corruption", [None, "incoming", "outgoing"])
def test_pressure_dilution_conversion_is_checked_even_when_total_budget_closes(corruption):
    # 1 m3, M=.2 kg O2, q=.1 kg reference gas, outside x=.209.
    # Independent high-precision decimal calculation, not the owner/runner.
    incoming, outgoing = .023088732146371273, .017160671703567021
    if corruption == "incoming":
        incoming += .01
    elif corruption == "outgoing":
        outgoing += .01
    before = [{"id": 0, "volume_m3": 1, "o2_inventory_kg": .2}]
    after = [{"id": 0, "volume_m3": 1, "o2_inventory_kg": .2 + incoming - outgoing}]
    operation = {"kind": "outside", "cause": "pressure_venting", "room": 0,
                 "gas_kg": .1, "in_kg": incoming, "out_kg": outgoing}
    rows = [{"route": "pressure_venting", "event_id": "vent0", "before": before, "after": after,
             "owner_operations": [operation], "data": {"outside_fraction": .209}},
            {"route": "tick_summary", "tick": 0, "before": before, "after": after,
             "owner_operations": [operation]}]
    if corruption is None:
        assert runner.analyze_rows(rows, expected_ticks=1)["dilution_reference_gas_kg"] == .1
    else:
        with pytest.raises(RuntimeError):
            runner.analyze_rows(rows, expected_ticks=1)
