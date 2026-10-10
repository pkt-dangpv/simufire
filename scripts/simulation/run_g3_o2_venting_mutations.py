#!/usr/bin/env python3
"""Code mutations of stage M2-V of the oxygen authority: pressure venting as an operation
of the owner of the room oxygen inventory.

Same machinery as ``run_g3_o2_room_inventory_mutations.py``: each mutant changes ONE
file of the working tree by an exact text replacement (every anchor must occur exactly
once), runs the acceptance fixture of the stage on the real engine through the monitored
launcher and restores the original bytes, SHA-256 verified. The unmutated control runs
first and must be green. A parse error, a script error, a timeout or a monitor fault is
an invalid run, never a kill.

The defect of each mutant and the group that must see it are declared here before
anything runs. The first ten are the families asked for with the stage: the venting is
left out of the inventory; its sign is wrong; the entry or the exit is counted twice; a
mole fraction is taken for a mass fraction; the result is clipped to 0.209 in silence;
the operation is applied twice; the transit is left out of the budget; the room number
is written directly again; the old refusal of the route is kept.

Mutants and control run the JUDGED groups of the fixture (V01 to V09). Group V10 only
measures the effect against the historical route; the full fixture, with it, is the
acceptance run of ``run_g3_o2_venting.py``.

    python scripts/simulation/run_g3_o2_venting_mutations.py
"""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_o2_room_inventory_mutations as machinery  # noqa: E402

INVENTORY = "sim/core/RoomOxygenInventory.gd"
GAS = "sim/core/GasExchangeSystem.gd"
FILES = (INVENTORY, GAS)
FIXTURE = "tests/fixtures/g3_o2_venting.gd"
PREFIX = "G3_O2_VENTING"
JUDGED_ONLY = {"G3_O2_VENTING_JUDGED_ONLY": "1"}

DECLARED_WITH_THE_STAGE = (
    "W01_venting_left_out_of_the_inventory", "W02_wrong_sign", "W03_entry_counted_twice", "W04_exit_counted_twice",
    "W05_mole_fraction_taken_for_a_mass_fraction", "W06_clipped_to_the_ceiling_in_silence", "W07_applied_twice",
    "W08_transit_left_out_of_the_budget", "W09_room_number_written_directly", "W10_old_refusal_kept",
)

_APPLY = ("\t\t\towned_dilution = room_o2_inventory.dilute_with_outside(\n"
          "\t\t\t\troom, air_in_kg, building.outside_o2, \"pressure_venting\"\n\t\t\t)\n")
_ASKED_FIRST = ("\t\tif room_o2_inventory != null and not room_o2_inventory.outside_dilution_would_apply(\n"
                "\t\t\t\troom, air_in_kg, building.outside_o2):\n"
                "\t\t\troom_o2_inventory.dilute_with_outside(room, air_in_kg, building.outside_o2, \"pressure_venting\")\n"
                "\t\t\tcontinue\n")
_LEFT = ("\tvar out_kg: float = o2_kg_in_reference_gas(mixture_mole_fraction, entering_kg)\n"
         "\tvar after_kg: float = before_kg + in_kg - out_kg\n")

# name: (file, old, new, defect, group of the fixture that must see it)
MUTATIONS: dict[str, tuple[str, str, str, str, str]] = {
    "W01_venting_left_out_of_the_inventory": (
        GAS, _APPLY, "\t\t\tpass\n",
        "the venting retires smoke and gases and its dilution never reaches the inventory", "V02"),
    "W02_wrong_sign": (
        INVENTORY, _LEFT, _LEFT.replace("before_kg + in_kg - out_kg", "before_kg - in_kg + out_kg"),
        "the entry is taken from the room and the exit is given to it", "V03"),
    "W03_entry_counted_twice": (
        INVENTORY, _LEFT, _LEFT.replace("before_kg + in_kg - out_kg", "before_kg + in_kg + in_kg - out_kg"),
        "the oxygen that enters is credited twice", "V03"),
    "W04_exit_counted_twice": (
        INVENTORY, _LEFT, _LEFT.replace("before_kg + in_kg - out_kg", "before_kg + in_kg - out_kg - out_kg"),
        "the oxygen that leaves is debited twice", "V03"),
    "W05_mole_fraction_taken_for_a_mass_fraction": (
        INVENTORY, "\tvar in_kg: float = o2_kg_in_reference_gas(float(outside_mole_fraction), entering_kg)\n",
        "\tvar in_kg: float = float(outside_mole_fraction) * entering_kg\n",
        "the outside mole fraction is multiplied by the mass of gas directly", "V03"),
    "W06_clipped_to_the_ceiling_in_silence": (
        INVENTORY, _LEFT, _LEFT + "\tafter_kg = minf(after_kg, o2_kg_from_mole_fraction(0.209, room.volume_m3()))\n",
        "what the dilution leaves is cut to 0.209, as the historical write does, with no record", "V04"),
    "W07_applied_twice": (
        GAS, _APPLY, _APPLY + "\t\t\troom_o2_inventory.dilute_with_outside(room, air_in_kg, building.outside_o2, \"pressure_venting\")\n",
        "one venting event dilutes the room twice", "V06"),
    "W08_transit_left_out_of_the_budget": (
        INVENTORY, "\t\t_transit.append({\n\t\t\t\"id\": delivery_id,", "\t\tvar _dropped: Dictionary = ({\n\t\t\t\"id\": delivery_id,",
        "a delayed exchange changes the donor and queues nothing for the receiver, while the room vents", "V05"),
    "W09_room_number_written_directly": (
        GAS, _APPLY, _APPLY + "\t\t\troom.o2 = clampf(\n\t\t\t\t(room.o2 * room_mass_kg + building.outside_o2 * air_in_kg) / (room_mass_kg + air_in_kg),\n"
                              "\t\t\t\t0.0,\n\t\t\t\to2_nominal\n\t\t\t)\n",
        "with the mode on the venting also writes the room number, as the historical route does", "V07"),
    "W10_old_refusal_kept": (
        GAS, _APPLY, "\t\t\troom_o2_inventory.refuse_route(room, \"pressure_venting\", air_in_kg)\n",
        "the venting is still a route the owner refuses", "V02"),
    # --- controls of the same contract ---------------------------------------------------
    "W11_owner_asked_after_writing": (
        GAS, _ASKED_FIRST, "",
        "the owner is not asked before the event writes smoke, gases and pressure: a refused event leaves them written", "V08"),
    "W12_accumulator_taken_from_the_number": (
        GAS, "\t\t\t_pv_o2_delta = float(owned_dilution.get(\"net_kg\", 0.0))\n", "\t\t\tpass\n",
        "the exterior accumulator of the room is the change of its number by its mass, not what the owner applied", "V06"),
    "W13_gas_leaves_at_the_fraction_of_before": (
        INVENTORY, "\tvar out_kg: float = o2_kg_in_reference_gas(mixture_mole_fraction, entering_kg)\n",
        "\tvar out_kg: float = o2_kg_in_reference_gas(mole_fraction_from_o2_kg(before_kg, room.volume_m3()), entering_kg)\n",
        "the gas leaves at the fraction the room had before mixing: the entering mass used directly, which is not the historical law", "V03"),
    "W14_selection_built_again_after_the_venting": (
        GAS, _APPLY, _APPLY + "\t\t\troom_o2_inventory._select_for_step()\n",
        "the selections of the step are built again when a room vents", "V07"),
    "W15_owner_says_it_would_apply_anything": (
        INVENTORY, "\treturn _open() and _dilution_error(room, gas_kg, outside_mole_fraction) == \"\"\n", "\treturn true\n",
        "the owner answers that any dilution would apply, so nothing is stopped before the event writes", "V08"),
    "W16_entry_and_exit_recorded_as_a_net": (
        INVENTORY, "\"in_kg\": in_kg,\n\t\t\"out_kg\": out_kg, \"leaving_mole_fraction\"", "\"in_kg\": in_kg - out_kg,\n\t\t\"out_kg\": 0.0, \"leaving_mole_fraction\"",
        "the event records its net as an entry and no exit", "V02"),
}


def prepared():
    return machinery.prepared(MUTATIONS, FILES)


def plan() -> dict:
    return machinery.plan(MUTATIONS, DECLARED_WITH_THE_STAGE)


def main() -> int:
    return machinery.execute(MUTATIONS, DECLARED_WITH_THE_STAGE, FILES, FIXTURE, PREFIX,
                             "g3_o2_venting_mutations", JUDGED_ONLY, __doc__)


if __name__ == "__main__":
    raise SystemExit(main())
