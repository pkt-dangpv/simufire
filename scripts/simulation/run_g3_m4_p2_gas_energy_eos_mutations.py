"""The 16 M4-P2 GD mutants predeclared in the plan, through the unchanged owned-process harness.

Each mutant must fail its declared fixture assertion; a script, parse, native or
infrastructure error is never a kill. Sources are restored and checked by SHA-256.
"""

import argparse
import json
from pathlib import Path

from scripts.simulation import run_g3_m4_p2_gas_energy_eos as fixture
from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness

MODEL = fixture.MODEL
_TEXT = (fixture.ROOT / MODEL).read_text(encoding="utf-8")

# Replay has two barriers (preflight seen check and final unique-seen validation);
# the mutant removes both, as M4-P1 learned with P15.
_PROPOSE = _TEXT.split("static func propose", 1)[1].split("\n\n\nstatic func _gas_reason", 1)[0]
_REPLAY = _PROPOSE.replace('\tif book["seen"].has(event["id"]):\n\t\treturn _refuse("duplicate_event_or_parcel")\n',
                           '\tif false:\n\t\treturn _refuse("duplicate_event_or_parcel")\n').replace(
    '\tafter["seen"].append(event["id"])\n',
    '\tif not after["seen"].has(event["id"]):\n\t\tafter["seen"].append(event["id"])\n')

# Depletion has two barriers too (retained == 0 with r != 1, and energy left without mass).
_DEPLETION = ('\t\t\telse:\n'
              '\t\t\t\tif m0 > 0.0 and retained == 0.0:\n'
              '\t\t\t\t\treturn _refuse("layer_depleted_while_pressure_changes")\n'
              '\t\t\t\tu_z1 = rk * u_z0 + f * (gained - lost)\n'
              '\t\t\tif m1 == 0.0:\n'
              '\t\t\t\tif u_z1 != 0.0:\n'
              '\t\t\t\t\treturn _refuse("layer_depleted_while_pressure_changes")\n')
_DEPLETION_ZEROED = ('\t\t\telse:\n'
                     '\t\t\t\tu_z1 = rk * u_z0 + f * (gained - lost)\n'
                     '\t\t\tif m1 == 0.0:\n'
                     '\t\t\t\tu_z1 = 0.0\n')

_SPLIT = "u_z1 = rk * u_z0 + f * (gained - lost)\n\t\t\tif m1"
_DONOR_H = 'carried_h = q * gamma * float(donor["U_" + zone]) / donor_mass'


def mutant(old, new, defect, expected):
    return MODEL, old, new, defect, expected


MUTATIONS = {
    "M01_heat_to_enthalpy_without_vdp": mutant(
        'external[target["room"]] += float(heat["energy_kj"])',
        'external[target["room"]] += float(heat["energy_kj"]) / gamma',
        "heat raises cp-sensible enthalpy without V dp (F2.2A)", "C1 p"),
    "M02_cv_replaced_by_cp_in_temperature": mutant(
        '"T_k": u / (m * float(gas["cv"])),', '"T_k": u / (m * float(gas["cp"])),',
        "temperature derived with cp", "C1 T"),
    "M03_R_from_reference_temperature": mutant(
        'var R: float = float(book["gas"]["R_kj_kg_k"])',
        'var R: float = float(book["exterior_pressure_abs_pa"]) / (1.2 * float(book["reference_temp_k"])) / 1000.0',
        "gas constant from the scenario temperature", "C11 R"),
    "M04_gamma_constant_1_4": mutant(
        '"gamma": cp / cv, "k": R / cp}', '"gamma": 1.4, "k": 0.4 / 1.4}',
        "literal gamma instead of cp/cv", "C1 p"),
    "M05_proportional_rescale_split": mutant(
        _SPLIT, "u_z1 = (u_z0 + (gained - lost) / gamma) * (u1 / (u0 + float(external[room_id]) / gamma))\n\t\t\tif m1",
        "layer split by a common rescale", "C2 isentrope"),
    "M06_passive_layer_not_compressed": mutant(
        _SPLIT, "u_z1 = u_z0 + f * (gained - lost)\n\t\t\tif m1",
        "no compression work on a layer without inputs", "C2 isentrope"),
    "M07_outflow_debits_u_not_h": mutant(
        _DONOR_H, 'carried_h = q * float(donor["U_" + zone]) / donor_mass',
        "outflow carries internal energy instead of enthalpy", "C9"),
    "M08_inflow_uses_sensible_not_absolute_enthalpy": mutant(
        'carried_h = q * float(gas["cp"]) * float(outside["T_k"])',
        'carried_h = q * float(gas["cp"]) * (float(outside["T_k"]) - float(book["reference_temp_k"]))',
        "exterior inflow carries sensible enthalpy in the absolute basis", "C8 U"),
    "M09_negative_energy_clamped_to_zero": mutant(
        '\t\t\t\treturn _refuse("layer_energy_negative_after_step")\n', '\t\t\t\tu_z1 = 1.0e-9\n',
        "clamp a non-positive layer energy", "R layer_energy_negative_after_step"),
    "M10_depletion_residual_silently_zeroed": mutant(
        _DEPLETION, _DEPLETION_ZEROED, "zero the depletion residual instead of rejecting", "C10c"),
    "M11_gauge_pressure_clipped_non_negative": mutant(
        '"p_gauge_pa": p_abs - float(book["exterior_pressure_abs_pa"]),',
        '"p_gauge_pa": maxf(0.0, p_abs - float(book["exterior_pressure_abs_pa"])),',
        "gauge pressure clipped at zero", "C4 gauge negative"),
    "M12_work_not_antisymmetric": mutant(
        _SPLIT, 'u_z1 = (u_z0 + gained - lost) if zone == "upper" else rk * u_z0 + f * (gained - lost)\n\t\t\tif m1',
        "upper layer pays no compression work", "energy closure"),
    "M13_donation_from_candidate_not_snapshot": mutant(
        _DONOR_H, 'carried_h = q * gamma * float(donor["U_" + zone]) / (donor_mass - float(acc[source["room"]][zone]["out_kg"]))',
        "donor enthalpy from the running candidate", "parcel snapshot"),
    "M14_building_receipt_omits_boundary_energy": mutant(
        'boundary["H_in_kj"] += carried_h', 'boundary["H_in_kj"] += 0.0',
        "receipt drops boundary inflow enthalpy", "building balance"),
    "M15_receipt_aliases_input": mutant(
        '"receipt": {"before": book.duplicate(true), "after": after.duplicate(true),',
        '"receipt": {"before": book, "after": after,',
        "receipt aliases the caller's book", "receipt isolated"),
    "M16_duplicate_event_guard_removed": mutant(
        _PROPOSE, _REPLAY, "disable both replay barriers", "duplicate event"),
}


class _FixtureTimeoutMonitor:
    """The harness bytes are frozen by M3 evidence and its launch timeout is 180 s;
    this fixture needs ~132 s clean, so only the timeout is raised to the control's.
    Everything else goes to the unchanged monitor."""

    def __init__(self, monitor):
        self._monitor = monitor

    def __getattr__(self, name):
        return getattr(self._monitor, name)

    def run(self, command, *, timeout_s, **options):
        return self._monitor.run(command, timeout_s=max(timeout_s, fixture.TIMEOUT_S), **options)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    originals, variants = harness.machinery.prepared(MUTATIONS, (MODEL,))
    declared = harness.machinery.plan(MUTATIONS, tuple(MUTATIONS))
    hashes = fixture.current_hashes()
    monitor = harness.godot_monitored_launch
    harness.godot_monitored_launch = _FixtureTimeoutMonitor(monitor)
    try:
        harness.execute(args.work.resolve(), originals, variants, declared,
                        fixture=fixture.FIXTURE, prefix=fixture.PREFIX,
                        schema="g3_m4_p2_gas_energy_eos_mutations_v1", integration=False)
    finally:
        harness.godot_monitored_launch = monitor
        path = args.work.resolve() / "results.json"
        if path.exists():
            record = json.loads(path.read_text(encoding="utf-8"))
            record["source_sha256_raw"] = hashes
            record["all_sources_restored"] = hashes == fixture.current_hashes()
            path.write_text(json.dumps(record, indent=2), encoding="utf-8")
        if hashes != fixture.current_hashes():
            raise RuntimeError("fixture/auditor/oracle/plan/model not restored exactly")


if __name__ == "__main__":
    main()
