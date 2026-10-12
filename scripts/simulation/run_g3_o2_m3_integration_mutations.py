"""Predeclared M3 live-coupling defects, sequential safe monitor, exact restoration.

This is technical engine falsation, not validation of material yields, CO or FED.
Only a named assertion at its declared site counts; script/native errors do not.
"""
import argparse
from pathlib import Path

from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness

FIRE = "sim/fire/CombustionSystem.gd"
OWNER = harness.OWNER
ENGINE = "sim/core/SimulationEngine.gd"
FIXTURE = "tests/fixtures/g3_o2_m3_integration.gd"
PREFIX = "G3_O2_M3_INTEGRATION"
MUTATIONS = {
    "I01_limit_target_not_filter": (
        FIRE,
        'room, o2_selection["selection"], proposed_hrr_kw * dt / 1000.0,',
        'room, o2_selection["selection"], room.hrr_target_kw * dt / 1000.0,',
        "back the target instead of the accepted filter output", "real sink settles reservation"),
    "I02_power_not_scaled": (
        FIRE, "room.hrr_kw = proposed_hrr_kw * accepted_fraction",
        "room.hrr_kw = proposed_hrr_kw",
        "retain unbacked power", "accepted power uses one fraction"),
    "I03_products_not_scaled": (
        FIRE, "\tgenerated_co_kg *= accepted_fraction\n", "",
        "CO commits the refused proposal", "common fraction co_kg"),
    "I04_pool_not_scaled": (
        FIRE, "(proposed_pool_MJ - pool_before_MJ) * accepted_fraction",
        "(proposed_pool_MJ - pool_before_MJ)",
        "pool commits refused generation or losses", "pool change uses one fraction"),
    "I05_fuel_not_scaled": (
        FIRE, "\tsolid_fuel_demand_MJ *= accepted_fraction\n", "",
        "fuel follows refused proposal", "fuel uses one fraction"),
    "I06_late_debit_capped": (
        OWNER,
        '\treturn _apply_consumption(room, current, reserved_kg, reserved_kg, "accepted_combustion")\n',
        '\treturn _apply_consumption(room, current, reserved_kg, minf(reserved_kg, room.o2_inventory_kg * 0.05), "accepted_combustion")\n',
        "restore five-percent clipping after heat was accepted", "live sink has no five percent cap"),
    "I07_rejection_writes_pool": (
        FIRE, '\t\tif not bool(accepted["applied"]):\n\t\t\treturn false\n',
        '\t\tif not bool(accepted["applied"]):\n\t\t\troom.retained_unburned_MJ = proposed_pool_MJ\n\t\t\treturn false\n',
        "write pool despite refusal", "refusal writes no pool"),
    "I08_flashover_changes_current_heat": (
        ENGINE, '\t\t\t_o2_room_inventory.schedule_flashover_proposal(room, boosted_hrr_kw)\n',
        '\t\t\troom.hrr_kw = boosted_hrr_kw\n\t\t\t_o2_room_inventory.schedule_flashover_proposal(room, boosted_hrr_kw)\n',
        "flashover mutates a power already reserved", "flashover cannot mutate accepted power"),
    "I09_late_extinction_erases_heat": (
        FIRE, "if not m3_acceptance and fire.remaining_fuel_MJ <= 0.0 and room.retained_unburned_MJ <= 0.01:",
        "if fire.remaining_fuel_MJ <= 0.0 and room.retained_unburned_MJ <= 0.01:",
        "erase power after fuel and products have committed", "last accepted fuel tick not erased"),
    "I10_deferred_power_survives_reset": (
        OWNER, "\t_next_flashover_power_kw.clear()\n", "",
        "pending flashover survives reset", "reset removes pending flashover"),
    "I11_same_tick_spends_flashover": (
        OWNER, '\tif int(_next_flashover_step.get(room.id, _step_index)) > _step_index:\n\t\treturn 0.0\n',
        "", "spend next-step power immediately", "same-tick flashover proposal cannot be spent"),
    "I12_heat_accumulator_not_scaled": (
        FIRE, "\troom.hrr_kj_total += maxf(0.0, room.hrr_kw) * dt\n",
        "\troom.hrr_kj_total += maxf(0.0, proposed_hrr_kw) * dt\n",
        "record refused heat in the accumulator", "heat accumulator uses one fraction"),
    "I13_smoke_not_scaled": (
        FIRE, "room.smoke_prod_kg_s = proposed_smoke_kg_s * accepted_fraction",
        "room.smoke_prod_kg_s = proposed_smoke_kg_s",
        "smoke commits refused proposal", "common fraction smoke_prod_kg_s"),
    "I14_object_power_not_scaled": (
        FIRE, "\t\t\tactual_solid_burn_kw * accepted_fraction,\n",
        "\t\t\tactual_solid_burn_kw,\n",
        "explicit objects retain refused radiative power", "explicit object power uses accepted fraction"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    originals, variants = harness.machinery.prepared(MUTATIONS, (FIRE, OWNER, ENGINE))
    declared = harness.machinery.plan(MUTATIONS, tuple(MUTATIONS))
    if args.plan_only:
        import json
        print(json.dumps(declared, indent=2))
        return
    harness.execute(args.work.resolve(), originals, variants, declared,
                    fixture=FIXTURE, prefix=PREFIX,
                    schema="g3_m3_live_integration_mutations_v1", integration=True)


if __name__ == "__main__":
    main()
