"""M4-P2-GD offline guards: isolation, monitor-only launches, predeclared mutants and
an auditor that refuses corrupted receipts. No Godot launch, no engine run."""

import copy
import json
from pathlib import Path

import pytest

from scripts.simulation import audit_g3_m4_p2_gas_energy_eos as audit
from scripts.simulation import g3_m4_p2_gas_energy_eos_oracle as oracle
from scripts.simulation import run_g3_m4_p2_gas_energy_eos as runner
from scripts.simulation import run_g3_m4_p2_gas_energy_eos_closure as closure
from scripts.simulation import run_g3_m4_p2_gas_energy_eos_mutations as mutations

ROOT = Path(__file__).resolve().parents[1]
PLAN = audit.load_plan()


def test_module_is_pure_and_not_loaded_by_the_simulation():
    path = ROOT / runner.MODEL
    code = "\n".join(line for line in path.read_text(encoding="utf-8").splitlines()
                     if not line.lstrip().startswith("#"))
    for token in ("class_name ", "@export", "RoomModel", "SimulationEngine", "clampf(", "Node", "FileAccess"):
        assert token not in code
    assert code.count("preload(") == 1 and 'preload("res://sim/core/DetMath.gd")' in code
    for other in (ROOT / "sim").rglob("*.gd"):
        if other != path:
            assert "PhysicalGasEnergyEosModel" not in other.read_text(encoding="utf-8")


def test_product_properties_are_inputs_not_constants():
    code = (ROOT / runner.MODEL).read_text(encoding="utf-8")
    for literal in ("1.012", "0.28914", "0.288", "1.4", "293.15", "101325"):
        assert literal not in code
    assert 'book["gas"]["cp_kj_kg_k"]' in code and 'book["gas"]["R_kj_kg_k"]' in code


def test_runner_uses_safe_monitor_and_checks_the_plan_hash():
    source = (ROOT / "scripts/simulation/run_g3_m4_p2_gas_energy_eos.py").read_text(encoding="utf-8")
    assert "godot_monitored_launch.run(" in source and "prepare_environment(work)" in source
    assert "subprocess" not in source and "shell=True" not in source
    assert "audit.load_plan()" in source and "audit.audit_payload(payload, plan)" in source
    assert runner.PLAN in runner.current_hashes()


def test_mutants_are_exactly_the_sixteen_of_the_plan_and_anchor_once():
    names = [name.split("_", 1)[1] for name in mutations.MUTATIONS]
    assert names == PLAN["gd_mutants_for_p2_implementation"]
    _, variants = mutations.harness.machinery.prepared(mutations.MUTATIONS, (mutations.MODEL,))
    assert len(variants) == 16
    declared = mutations.harness.machinery.plan(mutations.MUTATIONS, tuple(mutations.MUTATIONS))
    fixture = (ROOT / runner.FIXTURE).read_text(encoding="utf-8")
    for item in declared.values():
        label = item["expected_in"]
        # Labels are literal ("C2 isentrope") or built as case_id + " p".
        head, _, tail = label.partition(" ")
        assert f'"{label}' in fixture or (tail and f'" {tail}"' in fixture) or f'"{head} ' in fixture, label


def test_campaign_raises_only_the_launch_timeout_without_touching_the_shared_harness():
    # M3 evidence freezes the harness bytes; the timeout is raised by a wrapper here.
    assert "timeout_s=180, environment=os.environ.copy()" in Path(mutations.harness.__file__).read_text(encoding="utf-8")
    calls = []

    class Monitor:
        marker = "delegated"

        def run(self, command, *, timeout_s, **options):
            calls.append((command, timeout_s, options))

    wrapped = mutations._FixtureTimeoutMonitor(Monitor())
    wrapped.run(["godot"], timeout_s=180, environment={})
    assert calls == [(["godot"], runner.TIMEOUT_S, {"environment": {}})]
    assert wrapped.marker == "delegated"


def _gd_book(rooms: dict, gas: oracle.Gas) -> dict:
    return {"generation": 1, "step": 0, "revision": 0, "basis": "physical_gas_energy_eos_v1",
            "gas": {"cp_kj_kg_k": gas.cp, "R_kj_kg_k": gas.R}, "reference_temp_k": 293.15,
            "exterior_pressure_abs_pa": 101325.0, "seen": [],
            "rooms": {rid: {"floor_area_m2": r["floor_area_m2"], "height_m": r["height_m"],
                            **{f"{f}_{z}": r["layers"][z][f] for z in oracle.LAYERS for f in ("m", "U", "O")}}
                      for rid, r in rooms.items()}}


def _oracle_receipt():
    props = PLAN["property_sets"]["engine_equivalent_293_15"]
    gas = oracle.Gas(cp=props["cp"], R=props["R"])
    rooms = {"A": oracle.make_room(gas, 20.0, 2.5, 101325.0, {"upper": {"T_k": 400.0, "volume_m3": 20.0},
                                                              "lower": {"T_k": 293.15, "volume_m3": 30.0}})}
    before = _gd_book(rooms, gas)
    event = {"id": "e", "packets": [{"id": "p", "kind": "transfer", "source": {"room": "A", "zone": "lower"},
                                     "target": {"room": "A", "zone": "upper"}, "gas_kg": 0.5, "boundary": None}],
             "heat": [{"id": "h", "target": {"room": "A", "zone": "upper"}, "energy_kj": 10.0}]}
    heat, parcels, exterior = audit.to_inputs(event)
    after_rooms, rec = oracle.step(gas, rooms, heat, parcels, exterior)
    after = _gd_book(after_rooms, gas)
    layers = {z: {"W_kj": rec["work_kj"][("A", z)]} for z in oracle.LAYERS}
    boundary = {"H_in_kj": 0.0, "H_out_kj": 0.0, "mass_in_kg": 0.0, "mass_out_kg": 0.0}
    return {"before": before, "after": after, "event": event, "rooms": {"A": {"layers": layers}}, "boundary": boundary}


def test_auditor_accepts_an_oracle_consistent_receipt():
    assert audit.audit_receipt(_oracle_receipt(), PLAN) <= 1e-15


@pytest.mark.parametrize("field", ["U_upper", "U_lower", "m_upper", "O_lower"])
def test_auditor_refuses_a_corrupted_receipt_even_by_one_part_in_a_billion(field):
    receipt = _oracle_receipt()
    receipt["after"]["rooms"]["A"][field] *= 1.0 + 1e-9
    with pytest.raises(RuntimeError):
        audit.audit_receipt(receipt, PLAN)


def test_auditor_refuses_corrupted_work_and_boundary():
    receipt = _oracle_receipt()
    receipt["rooms"]["A"]["layers"]["lower"]["W_kj"] += 1.0
    with pytest.raises(RuntimeError):
        audit.audit_receipt(receipt, PLAN)
    receipt = _oracle_receipt()
    receipt["boundary"]["H_in_kj"] = 1.0
    with pytest.raises(RuntimeError):
        audit.audit_receipt(receipt, PLAN)


def test_auditor_maps_only_the_documented_rejection_spellings():
    receipt = _oracle_receipt()
    item = {"name": "x", "book": receipt["before"], "event": {"id": "x", "heat": [], "packets": [
        {"id": "o", "kind": "boundary_out", "source": {"room": "A", "zone": "lower"}, "target": None,
         "gas_kg": 1e9, "boundary": None}]}}
    for reason in ("overdraft_of_donor", "inflow_financing_outflow"):
        audit.audit_rejection({**item, "reason": reason})
    with pytest.raises(RuntimeError):
        audit.audit_rejection({**item, "reason": "negative_mass"})
    with pytest.raises(RuntimeError):
        audit.audit_rejection({**item, "event": receipt["event"], "reason": "overdraft_of_donor"})


def test_auditor_compares_convergence_temperatures_on_the_plan_exact_class():
    reference = audit._oracle_c7_c9(PLAN)
    convergence = {cid: {"rel_err": {str(dt): err for dt, (err, _) in table.items()},
                         "T_final_k": {str(dt): t for dt, (_, t) in table.items()}}
                   for cid, table in reference.items()}
    audit.audit_convergence(convergence, PLAN)
    key = next(iter(convergence["C9"]["T_final_k"]))
    convergence["C9"]["T_final_k"][key] *= 1.0 + 3.0 * PLAN["tolerances"]["exact_relative"]
    with pytest.raises(RuntimeError):
        audit.audit_convergence(convergence, PLAN)


def test_auditor_requires_every_final_of_the_plan():
    with pytest.raises(RuntimeError):
        audit.audit_finals([], PLAN)


def test_auditor_refuses_failed_or_empty_payloads():
    for payload in ({"checks": 0}, {"checks": 5, "failure_count": 1, "failures": ["x"]},
                    {"checks": 5, "failure_count": 0, "failures": [], "samples": []}):
        with pytest.raises(RuntimeError):
            audit.audit_payload(payload, PLAN)


def test_closure_requires_the_full_campaign():
    current = runner.current_hashes()
    control = {"state": "passed", "source_sha256_raw": current, "integration_validated": False,
               "product_properties_chosen": False, "engine_timestep_sensitivity_resolved": False}
    with pytest.raises(Exception):
        closure.prerequisites(control, {"error": None}, current, ROOT / "nonexistent")
    source = (ROOT / "scripts/simulation/run_g3_m4_p2_gas_energy_eos_closure.py").read_text(encoding="utf-8")
    assert "changes beyond generated_at" in source and "(346, 0, 78)" in source
