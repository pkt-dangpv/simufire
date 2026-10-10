#!/usr/bin/env python3
"""Code mutations of stage M2 of the oxygen authority: one selection per room and step.

Same machinery as ``run_g3_o2_room_inventory_mutations.py``: each mutant changes ONE
file of the working tree by an exact text replacement (every anchor must occur exactly
once), runs the acceptance fixture of stage M2 on the real engine through the monitored
launcher and restores the original bytes, SHA-256 verified. The unmutated control runs
first and must be green. A parse error, a script error, a timeout or a monitor fault is
an invalid run, never a kill.

The defect of each mutant and the group that must see it are declared here before
anything runs. The first eight families are the ones asked for with the stage: the sink
rebuilds the selection; the fire is handed the lower-layer number; another deposit is
debited; the second declaration of consumption comes back; the inventory is rewritten
from the layers in a sealed room; a selection of an earlier step or run is used; the
transit is left out; the historical route is taken with the mode on.

Mutants and control run the JUDGED groups of the fixture (C01 to C09). Group C10 only
measures the effect against the historical route and judges nothing of the fire; the
full fixture, with it, is the acceptance run of ``run_g3_o2_selection.py``.

    python scripts/simulation/run_g3_o2_selection_mutations.py
"""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.simulation import run_g3_o2_room_inventory_mutations as machinery  # noqa: E402

INVENTORY = "sim/core/RoomOxygenInventory.gd"
OXYGEN = "sim/core/OxygenExchangeSystem.gd"
ENGINE = "sim/core/SimulationEngine.gd"
COMBUSTION = "sim/fire/CombustionSystem.gd"
FILES = (INVENTORY, OXYGEN, ENGINE, COMBUSTION)
FIXTURE = "tests/fixtures/g3_o2_selection.gd"
PREFIX = "G3_O2_SELECTION"
JUDGED_ONLY = {"G3_O2_SELECTION_JUDGED_ONLY": "1"}

DECLARED_WITH_THE_STAGE = (
    "S01_sink_rebuilds_the_selection", "S02_fire_is_handed_the_lower_number", "S03_another_deposit_is_debited",
    "S04_second_declaration_of_consumption", "S05_inventory_rewritten_from_the_layers_in_a_sealed_room",
    "S06_selection_of_the_previous_step_kept", "S07_selection_ignores_the_transit",
    "S08_historical_route_when_the_selection_is_refused",
)

# name: (file, old, new, defect, group of the fixture that must see it)
MUTATIONS: dict[str, tuple[str, str, str, str, str]] = {
    "S01_sink_rebuilds_the_selection": (
        OXYGEN, "\t\tvar selection: Dictionary = room_o2_inventory.selection_for(room, \"sink\")\n",
        "\t\troom_o2_inventory._select_for_step()\n\t\tvar selection: Dictionary = room_o2_inventory.selection_for(room, \"sink\")\n",
        "the sink builds the selections again in the middle of the step: the one it debits is not the one the fire read", "C01"),
    "S02_fire_is_handed_the_lower_number": (
        COMBUSTION, "\t\t\t\t\"o2_ref\": float(selected[\"mole_fraction\"]),\n", "\t\t\t\t\"o2_ref\": room.o2_lower,\n",
        "the fire consults the selection and is handed the lower-layer number", "C02"),
    "S03_another_deposit_is_debited": (
        OXYGEN, "\t\tvar debit: Dictionary = room_o2_inventory.consume(\n\t\t\troom, selection, requested, consumed, \"fire_sink_room_inventory\"\n\t\t)\n",
        "\t\troom.o2_lower = maxf(0.0, room.o2_lower - consumed / _compute_room_air_mass_kg(room, air_density_kg_m3))\n"
        "\t\tvar debit: Dictionary = {\"applied\": true}\n",
        "the sink takes its debit from the lower-layer number and the inventory of the selection is not debited", "C03"),
    "S04_second_declaration_of_consumption": (
        OXYGEN, "\t\t\tif room_o2_inventory == null:\n\t\t\t\troom.o2_consumed_kg_step_all += upper_consumed\n",
        "\t\t\tif true:\n\t\t\t\troom.o2_consumed_kg_step_all += upper_consumed\n",
        "the write on the upper-layer number is declared as consumption again", "C03"),
    "S05_inventory_rewritten_from_the_layers_in_a_sealed_room": (
        OXYGEN, "\t\t\t\troom.o2 = clampf(room.o2_upper * upper_frac + room.o2_lower * lower_frac, 0.0, o2_nominal)\n",
        "\t\t\t\troom.o2 = clampf(room.o2_upper * upper_frac + room.o2_lower * lower_frac, 0.0, o2_nominal)\n"
        "\t\t\tif effective_plume_lower and room_o2_inventory != null:\n"
        "\t\t\t\troom.commit_o2_inventory(room_o2_inventory.o2_kg_from_mole_fraction(\n"
        "\t\t\t\t\troom.o2_upper * upper_frac + room.o2_lower * lower_frac, room.volume_m3()),\n"
        "\t\t\t\t\troom.o2_upper * upper_frac + room.o2_lower * lower_frac)\n",
        "in a sealed room the blend of the layer numbers is written over the inventory, as the historical route does with the room number", "C04"),
    "S06_selection_of_the_previous_step_kept": (
        INVENTORY, "\t_step_operations.clear()\n\t_selections.clear()\n\tif _state != STATE_ARMED:\n\t\treturn\n"
                   "\tvar errors: Array[String] = _environment_errors(environment)\n\tif not errors.is_empty():\n"
                   "\t\t_reject(\"environment_changed_after_arming\", {\"errors\": errors})\n\t\treturn\n\t_select_for_step()\n",
        "\t_step_operations.clear()\n\tif _state != STATE_ARMED:\n\t\treturn\n"
        "\tvar errors: Array[String] = _environment_errors(environment)\n\tif not errors.is_empty():\n"
        "\t\t_reject(\"environment_changed_after_arming\", {\"errors\": errors})\n\t\treturn\n",
        "a step opens with the selections of the step before", "C01"),
    "S07_selection_ignores_the_transit": (
        INVENTORY, "\t\t\t\towed_kg -= minf(0.0, float(entry[\"net_kg\"]))\n", "\t\t\t\tpass\n",
        "what a room still owes in transit is left out of what its selection says is available", "C01"),
    "S08_historical_route_when_the_selection_is_refused": (
        COMBUSTION, "\t\treturn {\"mode\": \"o2_selection_refused\", \"o2_ref\": 0.0, \"o2_min_ref\": o2_min_ref}\n", "",
        "with the mode on, a fire whose selection is refused goes back to reading a layer number", "C07"),
    # --- controls of the same contract ---------------------------------------------------
    "S09_engine_does_not_hand_the_owner_to_the_fire": (
        ENGINE, "\tif oxygen_exchange_system.room_o2_inventory != null:\n\t\tcontext[\"o2_room_inventory\"] = oxygen_exchange_system.room_o2_inventory\n", "",
        "with the mode on the fire is never told there is a selection and reads as the historical route does", "C02"),
    "S10_selection_of_another_step_accepted": (
        INVENTORY, "\tif _whole(selection.get(\"step\")) != _step_index or _whole(selection.get(\"id\")) != int(current[\"id\"]):\n", "\tif false:\n",
        "a debit acts on the selection of an earlier step", "C06"),
    "S11_selection_of_another_run_accepted": (
        INVENTORY, "\tif _whole(selection.get(\"generation\")) != _generation:\n", "\tif false:\n",
        "a selection of the run before a reset is not told from one of another step", "C06"),
    "S12_selection_of_another_room_accepted": (
        INVENTORY, "\tif _whole(selection.get(\"room\")) != room.id:\n", "\tif false:\n",
        "the selection of another room is not told from one of another step", "C06"),
    "S13_selection_debited_twice": (
        INVENTORY, "\tif bool(current[\"debited\"]):\n\t\treturn \"selection_already_debited\"\n", "",
        "the same selection can be debited twice in a step", "C06"),
    "S14_another_deposit_accepted": (
        INVENTORY, "\tif str(selection.get(\"deposit\")) != DEPOSIT_ROOM_INVENTORY or current[\"deposit\"] != DEPOSIT_ROOM_INVENTORY:\n", "\tif false:\n",
        "a selection that names another deposit debits the room inventory", "C06"),
    "S15_fire_blend_with_the_upper_number_armed": (
        INVENTORY, "\t\"fire_blend_with_the_upper_number\": 0.0,\n", "",
        "the mode arms with a fire setting that reads the upper-layer number and would be ignored", "C08"),
}


def prepared():
    return machinery.prepared(MUTATIONS, FILES)


def plan() -> dict:
    return machinery.plan(MUTATIONS, DECLARED_WITH_THE_STAGE)


def main() -> int:
    return machinery.execute(MUTATIONS, DECLARED_WITH_THE_STAGE, FILES, FIXTURE, PREFIX,
                             "g3_o2_selection_mutations", JUDGED_ONLY, __doc__)


if __name__ == "__main__":
    raise SystemExit(main())
