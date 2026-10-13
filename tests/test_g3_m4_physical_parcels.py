"""Independent receipt corruption controls and isolation, no native launches."""

import copy
from pathlib import Path

import pytest

from scripts.simulation import audit_g3_m4_physical_parcels as audit
from scripts.simulation import run_g3_o2_m4_physical_parcels as runner

ROOT = Path(__file__).resolve().parents[1]


def receipt():
    # Hand-calculated 2 kg lower->upper: carries .4 kg O2 and 40 kJ.
    before = {"generation": 3, "step": 7, "revision": 0, "reference_temp_k": 300.,
              "basis": audit.BASIS, "seen": [], "rooms": {"a": {
                  "m_upper": 10., "m_lower": 20., "E_upper": 100., "E_lower": 400.,
                  "O_total": 5., "O_upper": 1.}}}
    source, target = {"room": "a", "zone": "lower"}, {"room": "a", "zone": "upper"}
    packet = {"id": "p", "kind": "transfer", "source": source, "target": target,
              "gas_kg": 2., "boundary": None}
    event = {"id": "plume", "cause": "imposed", "generation": 3, "step": 7, "revision": 0,
             "basis": audit.BASIS, "expected_rooms": copy.deepcopy(before["rooms"]),
             "packets": [packet], "heat": []}
    after = copy.deepcopy(before)
    after.update(revision=1, seen=["plume"])
    after["rooms"]["a"].update(m_upper=12., m_lower=18., E_upper=140., E_lower=360., O_upper=1.4)
    return {"before": before, "after": after, "event": event,
            "parcels": [{"id": "p", "kind": "transfer", "source": copy.deepcopy(source),
                         "target": copy.deepcopy(target), "gas_kg": 2., "oxygen_kg": .4, "energy_kj": 40.}],
            "deltas": {"a": {
                "upper": {"mass": 2., "oxygen": .4, "energy": 40., "donated_mass": 0.,
                          "donated_oxygen": 0., "donated_energy": 0.},
                "lower": {"mass": -2., "oxygen": -.4, "energy": -40., "donated_mass": 2.,
                          "donated_oxygen": .4, "donated_energy": 40.}}}}


def test_hand_computed_receipt_is_accepted_without_calling_propose():
    r = receipt()
    before = copy.deepcopy(r)
    assert audit.audit_receipt(r) == {"rooms": 1, "parcels": 1,
                                      "physical_flow_validation": False, "coupled_engine": False}
    assert r == before


@pytest.mark.parametrize("defect", ["donor", "gas", "energy", "oxygen_pair", "gas_pair", "energy_pair",
                                   "receipt_gross", "capacity", "absent", "basis", "reference", "clock",
                                   "revision", "identity", "seen", "snapshot", "parcel_id", "missing", "extra"])
def test_auditor_rejects_forged_receipt_even_when_total_oxygen_can_close(defect):
    r = receipt()
    if defect == "donor":
        # Keep room O2 total unchanged; change both U and parcel to a wrong donor.
        r["parcels"][0]["oxygen_kg"] = .2
        r["after"]["rooms"]["a"]["O_upper"] = 1.2
        r["deltas"]["a"]["upper"]["oxygen"] = .2
        r["deltas"]["a"]["lower"]["oxygen"] = -.2
    elif defect in ("gas", "energy"):
        r["parcels"][0]["gas_kg" if defect == "gas" else "energy_kj"] += 1
    elif defect == "oxygen_pair":
        r["after"]["rooms"]["a"]["O_total"] += .01
    elif defect in ("gas_pair", "energy_pair"):
        r["after"]["rooms"]["a"]["m_lower" if defect == "gas_pair" else "E_lower"] += .01
    elif defect == "receipt_gross":
        r["deltas"]["a"]["lower"]["donated_mass"] = 0
    elif defect == "capacity":
        r["after"]["rooms"]["a"].update(O_upper=13, O_total=14)
    elif defect == "absent":
        r["after"]["rooms"]["a"].update(m_upper=0, O_upper=0)
    elif defect == "basis":
        r["event"]["basis"] = "reference_dry_air_v1"
    elif defect == "reference":
        r["after"]["reference_temp_k"] = 299.
    elif defect == "clock":
        r["event"]["generation"] += 1
    elif defect == "revision":
        r["after"]["revision"] = 0
    elif defect == "identity":
        r["before"]["seen"] = ["plume"]
    elif defect == "seen":
        r["after"]["seen"] = []
    elif defect == "snapshot":
        r["event"]["expected_rooms"]["a"]["O_total"] = 4
    elif defect == "parcel_id":
        r["parcels"][0]["id"] = "other"
    elif defect == "missing":
        r["parcels"].clear()
    else:
        r["before"]["rooms"]["a"]["oxygen_lower_authority"] = 4
    with pytest.raises(RuntimeError):
        audit.audit_receipt(r)


@pytest.mark.parametrize("bad", [True, None, "1", float("inf"), float("-inf"), float("nan"), -1e-12])
def test_auditor_refuses_invalid_physical_amount(bad):
    r = receipt()
    r["before"]["rooms"]["a"]["m_upper"] = bad
    with pytest.raises(RuntimeError):
        audit.audit_receipt(r)


def test_gross_donation_is_checked_independently_of_valid_net_state():
    r = receipt()
    # 2+19 kg would exhaust donor; incoming credits must not legitimise it.
    p = copy.deepcopy(r["event"]["packets"][0])
    p.update(id="second", gas_kg=19.)
    r["event"]["packets"].append(p)
    c = copy.deepcopy(r["parcels"][0])
    c.update(id="second", gas_kg=19., oxygen_kg=3.8, energy_kj=380.)
    r["parcels"].append(c)
    # Compensating exterior inflow keeps every final mass/fraction legal.
    incoming = {"id": "outside", "kind": "boundary_in", "source": None,
                "target": {"room": "a", "zone": "lower"}, "gas_kg": 2.,
                "boundary": {"Y": .2, "e_kj_kg": 20.}}
    r["event"]["packets"].append(incoming)
    r["parcels"].append({k: copy.deepcopy(incoming[k]) for k in
                         ("id", "kind", "source", "target", "gas_kg")} | {
                             "oxygen_kg": .4, "energy_kj": 40.})
    r["after"]["rooms"]["a"].update(m_upper=31., m_lower=1., E_upper=520.,
                                     E_lower=20., O_upper=5.2, O_total=5.4)
    r["deltas"]["a"]["upper"].update(mass=21., oxygen=4.2, energy=420.)
    r["deltas"]["a"]["lower"].update(mass=-19., oxygen=-3.8, energy=-380.,
                                      donated_mass=21., donated_oxygen=4.2, donated_energy=420.)
    with pytest.raises(RuntimeError, match="gross gas"):
        audit.audit_receipt(r)


@pytest.mark.parametrize("defect", ["checks", "iterations", "failures", "count", "samples", "name", "units", "observable"])
def test_payload_requires_complete_named_cross_language_samples(defect):
    names = ("plume", "heat only", "door", "in", "out", "zero", "collapse", "reverse", "birth", "rich no ceiling")
    samples = [{"name": name, "receipt": receipt(), "observables": {"valid": True,
               "units": "oxygen_mass_fraction", "rooms": {"a": {"upper": 1.4 / 12, "lower": 3.6 / 18}}}}
               for name in names]
    payload = {"checks": 5920, "iterations": 256, "failure_count": 0, "failures": [], "samples": samples}
    if defect in ("checks", "iterations", "count"):
        payload[{"count": "failure_count"}.get(defect, defect)] = -1
    elif defect == "failures":
        payload["failures"] = ["wrong"]
    elif defect == "samples":
        samples.pop()
    elif defect == "name":
        samples[0]["name"] = "wrong"
    elif defect == "units":
        samples[0]["observables"]["units"] = "mole_fraction"
    else:
        samples[0]["observables"]["rooms"]["a"]["upper"] += .01
    with pytest.raises(RuntimeError):
        audit.audit_payload(payload)


def test_pure_module_is_not_loaded_by_simulation_or_reference_core():
    path = ROOT / runner.MODEL
    code = "\n".join(line for line in path.read_text(encoding="utf-8").splitlines()
                     if not line.lstrip().startswith("#"))
    for token in ("class_name ", "@export", "preload(", "RoomModel", "SimulationEngine", "clampf(", "maxf(0.0, lower"):
        assert token not in code
    assert all(path == p or "PhysicalGasOxygenParcelModel.gd" not in p.read_text(encoding="utf-8")
               for p in (ROOT / "sim").rglob("*.gd"))
    assert "reference_dry_air_v1" not in code


def test_runner_uses_safe_monitor_and_no_direct_process_launch():
    source = (ROOT / "scripts/simulation/run_g3_o2_m4_physical_parcels.py").read_text(encoding="utf-8")
    assert "godot_monitored_launch.run(" in source and "prepare_environment(work)" in source
    assert "subprocess.Popen" not in source and "shell=True" not in source
    assert "audit.audit_payload(payload)" in source and "current_hashes()" in source
