"""M2-T mutations: predeclared defects, judged real-Godot fixture, safe monitor.

Reuses the existing SHA-verified restoration and owned-process launcher.
Script/parse errors, timeouts and memory refusals are NOT valid kills.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.simulation import run_g3_o2_room_inventory_mutations as machinery  # noqa: E402

INVENTORY = "sim/core/RoomOxygenInventory.gd"
OXYGEN = "sim/core/OxygenExchangeSystem.gd"
FIXTURE = "tests/fixtures/g3_o2_transport_acceptance.gd"
PREFIX = "G3_O2_TRANSPORT"
MUTATIONS = {
    "T01_receiver_not_committed": (
        INVENTORY,
        "\t_commit(receiver, receiver_after_kg)\n\t_note({\"kind\": \"interior\", \"cause\": cause, \"law\": \"symmetric_reference_gas_immediate\",\n",
        "\t# mutant: receiver keeps its oxygen\n\t_note({\"kind\": \"interior\", \"cause\": cause, \"law\": \"symmetric_reference_gas_immediate\",\n",
        "immediate credit without paired debit", "T01"),
    "T02_wrong_receiver_sign": (
        INVENTORY, "\tvar receiver_after_kg: float = receiver_before_kg - donor_net_kg\n",
        "\tvar receiver_after_kg: float = receiver_before_kg + donor_net_kg\n",
        "both rooms gain the same net oxygen", "T01"),
    "T03_sequential_parcel_read": (
        INVENTORY, "\tvar to_donor_kg: float = receiver_before_kg * (exchanged_gas_kg / receiver_reference_kg)\n",
        "\tvar to_donor_kg: float = (receiver_before_kg + to_receiver_kg) * (exchanged_gas_kg / receiver_reference_kg)\n",
        "receiver outgoing parcel uses an already credited inventory", "T01"),
    "T04_wrong_reference_size": (
        INVENTORY, "\tvar to_donor_kg: float = receiver_before_kg * (exchanged_gas_kg / receiver_reference_kg)\n",
        "\tvar to_donor_kg: float = receiver_before_kg * (exchanged_gas_kg / donor_reference_kg)\n",
        "unequal rooms mix on the same reference size", "T01"),
    "T05_nominal_ceiling": (
        INVENTORY, "\tvar donor_after_kg: float = donor_before_kg + donor_net_kg\n",
        "\tvar donor_after_kg: float = minf(donor_before_kg + donor_net_kg, o2_kg_from_mole_fraction(0.209, donor.volume_m3()))\n",
        "nominal ceiling silently discards a legally richer initial mixture", "T01"),
    "T06_reference_bound_removed": (
        INVENTORY, "\tif exchanged_gas_kg > minf(donor_reference_kg, receiver_reference_kg):\n",
        "\tif false:\n", "oversized reference-gas operation no longer rejected atomically", "T02"),
    "T07_legacy_transit_allowed": (
        INVENTORY, "\tif not _transit.is_empty():\n\t\treturn _reject_operation(\"live_exchange_with_diagnostic_legacy_transit\", {\"cause\": cause})\n",
        "", "live mixing accepts a synthetic outstanding legacy obligation", "T02"),
    "T08_donor_audit_lost": (
        OXYGEN, "\thot_room.o2_net_transport_kg_step += float(moved[\"donor_net_kg\"])\n",
        "\thot_room.o2_net_transport_kg_step += 0.0\n", "donor transport accumulator omits actual exchange", "T03"),
    "T09_receiver_audit_lost": (
        OXYGEN, "\tcold_room.o2_net_transport_kg_step += float(moved[\"receiver_net_kg\"])\n",
        "\tcold_room.o2_net_transport_kg_step += 0.0\n", "receiver transport accumulator omits actual exchange", "T03"),
    "T10_historical_active_debt_restored": (
        OXYGEN,
        "\tvar moved: Dictionary = room_o2_inventory.exchange_reference_gas_between_rooms(\n\t\thot_room, cold_room, exchange_kg, \"interior_active_flow\"\n\t)\n",
        "\tvar moved: Dictionary = room_o2_inventory.exchange_between_rooms(\n\t\thot_room, cold_room,\n\t\troom_o2_inventory.o2_kg_in_reference_gas(hot_room.o2, exchange_kg),\n\t\troom_o2_inventory.o2_kg_in_reference_gas(cold_room.o2, exchange_kg),\n\t\t10.0, \"interior_active_flow\"\n\t)\n",
        "old active credit plus signed delayed debt is restored", "T03"),
    "T11_background_exchange_omitted": (
        OXYGEN,
        "\t\tvar swapped: Dictionary = room_o2_inventory.exchange_reference_gas_between_rooms(\n\t\t\troom_a, room_b, exchange_kg, \"interior_background_exchange\"\n\t\t)\n",
        "\t\tvar swapped: Dictionary = {\"applied\": false}\n",
        "background route stops moving oxygen", "T03"),
    "T12_report_claims_delay": (
        INVENTORY,
        '\t\t"live_transport_policy": "symmetric_reference_gas_immediate_o2_only",\n',
        '\t\t"live_transport_policy": "historical_delayed_net",\n',
        "report falsely describes live transport approximation", "T05"),
}


def main() -> int:
    return machinery.execute(
        MUTATIONS, tuple(MUTATIONS), (INVENTORY, OXYGEN), FIXTURE, PREFIX,
        "g3_o2_transport_mutations", {}, __doc__,
    )


if __name__ == "__main__":
    raise SystemExit(main())
