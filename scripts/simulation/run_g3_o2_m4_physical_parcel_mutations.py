"""Named M4-P1 real GD mutants through unchanged owned-process harness."""

import argparse
import json
from pathlib import Path

from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness
from scripts.simulation import run_g3_o2_m4_physical_parcels as fixture

MODEL = fixture.MODEL

# Replay has TWO independent barriers (preflight and final seen validation).
# Removing only the first is equivalent and survived the first campaign.
# This declared variant disables both; it must genuinely allow replay.
_propose = (fixture.ROOT / MODEL).read_text(encoding="utf-8").split(
    "static func propose", 1)[1].split("\n\n\nstatic func _room_reason", 1)[0]
_replay = _propose.replace('if book["seen"].has(event["id"]):', 'if false:').replace(
    'after["seen"].append(event["id"])',
    'if not after["seen"].has(event["id"]):\n\t\tafter["seen"].append(event["id"])')


def mutant(old, new, defect, expected):
    return MODEL, old, new, defect, expected


MUTATIONS = {
    "P01_gas_debit": mutant('debit["mass"] -= q', 'debit["mass"] -= 0.0',
                           "omit source gas", "paired gas"),
    "P02_oxygen_debit": mutant('debit["oxygen"] -= carried_oxygen', 'debit["oxygen"] -= 0.0',
                              "omit source oxygen", "paired oxygen"),
    "P03_energy_debit": mutant('debit["energy"] -= carried_energy', 'debit["energy"] -= 0.0',
                              "omit source energy", "paired energy"),
    "P04_room_average": mutant('carried_oxygen = q * (_oxygen(donor, zone) / donor_mass)',
                              'carried_oxygen = q * (float(donor["O_total"]) / (float(donor["m_upper"]) + float(donor["m_lower"])))',
                              "sample whole room", "donor oxygen"),
    "P05_molar_conversion": mutant('carried_oxygen = q * (_oxygen(donor, zone) / donor_mass)',
                                  'carried_oxygen = q * (_oxygen(donor, zone) / donor_mass) * (0.031998 / 0.0289647)',
                                  "apply molar factor to mass fraction", "donor oxygen"),
    "P06_wrong_energy": mutant('carried_energy = q * (float(donor["E_" + zone]) / donor_mass)',
                               'carried_energy = 0.0', "gas travels without energy", "donor energy"),
    "P07_incoming_funds": mutant('if float(delta["donated_mass"]) > float(room["m_" + zone]):',
                                'if false:', "gas arrivals finance outgoing", "gross gas independent"),
    "P08_cooling_funds": mutant('if float(delta["donated_energy"]) > float(room["E_" + zone]):',
                               'if false:', "heat arrivals finance cooling", "heat credit not funding"),
    "P09_capacity": mutant('if oxygen > gas:', 'if false:',
                           "accept oxygen exceeding gas", "invalid physical state"),
    "P10_absent_energy": mutant('if gas == 0.0 and (oxygen != 0.0 or float(room["E_" + zone]) != 0.0):',
                                'if false:', "energy exists without carrier", "invalid physical state"),
    "P11_bool_number": mutant('(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))',
                              '(typeof(value) == TYPE_BOOL or typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))',
                              "boolean treated as mass", "invalid number"),
    "P12_nonfinite_number": mutant('(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))',
                                   '(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)',
                                   "infinite reference accepted", "invalid number"),
    "P13_context": mutant('if not _whole(event[key]) or event[key] != book[key]:', 'if false:',
                          "accept other revision/run/tick", "context mismatch"),
    "P14_stale_snapshot": mutant('if event["expected_rooms"] != book["rooms"]:', 'if false:',
                                 "accept altered expected inventory", "stale snapshot"),
    "P15_event_replay": mutant(_propose, _replay,
                               "disable both independent replay barriers", "duplicate event"),
    "P16_result_alias": mutant('"book": after.duplicate(true),\n'
                               '\t\t"receipt": {"before": book.duplicate(true), "after": after.duplicate(true),',
                               '"book": after,\n'
                               '\t\t"receipt": {"before": book.duplicate(true), "after": after,',
                               "alias returned book and receipt", "receipt isolated"),
    "P17_packet_alias": mutant('"event": event.duplicate(true), "parcels": parcels.duplicate(true)',
                                '"event": event, "parcels": parcels',
                                "alias event and carried endpoints", "parcel snapshot isolated"),
    "P18_absent_zero": mutant('_oxygen(room, zone) / mass if mass > 0.0 else null',
                              '_oxygen(room, zone) / mass if mass > 0.0 else 0.0',
                              "absent zone reports zero oxygen", "absent observable"),
    "P19_fraction_context": mutant('return typeof(value) == TYPE_INT and int(value) >= 0',
                                    'return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and int(value) >= 0',
                                    "accept fractional type context", "integer context"),
    "P20_negative_lower": mutant('if lower_oxygen < 0.0:\n\t\treturn "room_oxygen"',
                                  'if false:\n\t\treturn "room_oxygen"',
                                  "negative derived lower accepted", "invalid physical state"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    originals, variants = harness.machinery.prepared(MUTATIONS, (MODEL,))
    declared = harness.machinery.plan(MUTATIONS, tuple(MUTATIONS))
    if args.plan_only:
        print(json.dumps(declared, indent=2))
        return
    hashes = fixture.current_hashes()
    try:
        harness.execute(args.work.resolve(), originals, variants, declared,
                        fixture=fixture.FIXTURE, prefix=fixture.PREFIX,
                        schema="g3_m4_physical_parcel_mutations_v1", integration=False)
    finally:
        path = args.work.resolve() / "results.json"
        if path.exists():
            record = json.loads(path.read_text(encoding="utf-8"))
            record["source_sha256_raw"] = hashes
            record["all_sources_restored"] = hashes == fixture.current_hashes()
            path.write_text(json.dumps(record, indent=2), encoding="utf-8")
        if hashes != fixture.current_hashes():
            raise RuntimeError("fixture/auditor/model not restored exactly")


if __name__ == "__main__":
    main()
