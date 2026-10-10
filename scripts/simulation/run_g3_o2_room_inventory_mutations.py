#!/usr/bin/env python3
"""Code mutations of stage M1 of the oxygen authority: room inventory and transit.

Each mutant changes ONE file of the working tree by an exact text replacement (every
anchor must occur exactly once), runs the acceptance fixture on the real engine through
the monitored launcher and restores the original bytes, SHA-256 verified, before the
next one and also after an error. The unmutated control runs first and must be green.

The defect each mutant injects, and the group of the fixture that must see it, are
declared here before anything runs. A kill is a fixture that reached its end and
reported failed checks. A parse error, a script error, a timeout or a monitor fault is
an invalid run, never a kill.

The first eight are the mutations declared with the plan of the authority
(docs/validation/G3_O2_AUTHORITY_2026-10-09.md); the rest are controls of the same
contract: a delivery applied twice, a transfer half applied, a refusal that is not made.

    python scripts/simulation/run_g3_o2_room_inventory_mutations.py
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation.run_g3_fuel_mass_budget_mutations import classify  # noqa: E402

INVENTORY = "sim/core/RoomOxygenInventory.gd"
OXYGEN = "sim/core/OxygenExchangeSystem.gd"
ENGINE = "sim/core/SimulationEngine.gd"
ROOM = "sim/building/RoomModel.gd"
FILES = (INVENTORY, OXYGEN, ENGINE, ROOM)
FIXTURE = "tests/fixtures/g3_o2_room_inventory.gd"
PREFIX = "G3_O2_ROOM_INVENTORY"
TIMEOUT_S = 900
# A launch is tried a little above the gate, so that it is not refused a second later.
MEMORY_MARGIN_GIB = 0.05

DECLARED_WITH_THE_PLAN = (
    "D01_debit_applied_twice", "T01_transit_omitted", "W01_room_number_written_outside_the_owner",
    "C01_credit_without_debit", "R01_transit_inherited_after_a_reset",
    "M01_inventory_initialised_with_the_mass_of_gas", "L01_layer_numbers_rewrite_the_inventory",
    "K01_clip_discarded_without_a_record",
)

# name: (file, old, new, defect, group of the fixture that must see it)
MUTATIONS: dict[str, tuple[str, str, str, str, str]] = {
    # --- the eight declared with the plan ----------------------------------------------
    "D01_debit_applied_twice": (
        INVENTORY, "\tvar after_kg: float = before_kg - applied\n", "\tvar after_kg: float = before_kg - applied - applied\n",
        "the debit of the sink leaves the inventory twice", "B05"),
    "T01_transit_omitted": (
        INVENTORY, "\t\t_transit.append({\n\t\t\t\"id\": delivery_id,", "\t\tvar _dropped: Dictionary = ({\n\t\t\t\"id\": delivery_id,",
        "a delayed exchange changes the donor and queues nothing for the receiver", "B06"),
    "W01_room_number_written_outside_the_owner": (
        ENGINE, "\t\tif not room.o2_inventory_authority:\n\t\t\troom.o2 = clampf(room.o2, 0.0, o2_nominal)\n",
        "\t\tif true:\n\t\t\troom.o2 = clampf(room.o2, 0.0, o2_nominal)\n",
        "the final clamp of the engine writes the room number of a room under authority", "B04"),
    "C01_credit_without_debit": (
        INVENTORY, "\tvar donor_after_kg: float = donor_before_kg + to_donor_kg - to_receiver_kg\n",
        "\tvar donor_after_kg: float = donor_before_kg + to_donor_kg\n",
        "the receiver is credited with oxygen the donor never loses", "B07"),
    "R01_transit_inherited_after_a_reset": (
        INVENTORY, "\t_totals.clear()\n\t_transit.clear()\n\t_step_operations.clear()\n", "\t_totals.clear()\n\t_step_operations.clear()\n",
        "a reset keeps the deliveries of the previous run", "B12"),
    "M01_inventory_initialised_with_the_mass_of_gas": (
        INVENTORY, "\treturn mole_fraction * reference_mol(volume_m3) * M_O2_KG_PER_MOL\n",
        "\treturn mole_fraction * reference_gas_kg(volume_m3)\n",
        "the mole fraction is multiplied by the mass of gas to get the inventory", "B02"),
    "L01_layer_numbers_rewrite_the_inventory": (
        OXYGEN, "\t\t\troom.o2_upper = lerpf(room.o2_upper, _upper_relax_target, clampf(0.03 * dt, 0.0, 0.10))\n",
        "\t\t\troom.o2_upper = lerpf(room.o2_upper, _upper_relax_target, clampf(0.03 * dt, 0.0, 0.10))\n"
        "\t\t\tif room_o2_inventory != null:\n"
        "\t\t\t\troom.commit_o2_inventory(room_o2_inventory.o2_kg_from_mole_fraction(\n"
        "\t\t\t\t\troom.o2_upper * upper_frac + room.o2_lower * lower_frac, room.volume_m3()),\n"
        "\t\t\t\t\troom.o2_upper * upper_frac + room.o2_lower * lower_frac)\n",
        "the blend of the two layer numbers is written over the inventory", "B10"),
    "K01_clip_discarded_without_a_record": (
        OXYGEN, "\t\t\troom, requested, consumed, \"fire_sink_room_inventory\"\n",
        "\t\t\troom, consumed, consumed, \"fire_sink_room_inventory\"\n",
        "what the cap of the sink clips is no longer handed to the owner", "B11"),
    # --- conversion ---------------------------------------------------------------------
    "M02_parcel_converted_with_the_mass_of_gas": (
        INVENTORY, "\treturn mole_fraction * (gas_kg / M_DRY_AIR_KG_PER_MOL) * M_O2_KG_PER_MOL\n", "\treturn mole_fraction * gas_kg\n",
        "the oxygen of a parcel of gas is its mole fraction times its mass", "B02"),
    # --- ownership of the room number ---------------------------------------------------
    "W02_guard_of_the_room_number_removed": (
        ROOM, "\t\tif o2_inventory_authority and not _o2_inventory_commit_open:\n\t\t\to2_unauthorized_write_count += 1\n"
              "\t\t\to2_unauthorized_write_last = value\n\t\t\treturn\n\t\to2 = value\n",
        "\t\to2 = value\n",
        "any writer can set the room number of a room under authority", "B03"),
    # --- transit --------------------------------------------------------------------------
    "E01_delivery_kept_in_the_queue": (
        INVENTORY, "\t\tif bool(delivered[\"applied\"]):\n\t\t\tarrived.append(",
        "\t\tif bool(delivered[\"applied\"]):\n\t\t\tremaining.append(entry)\n\t\t\tarrived.append(",
        "a delivered entry stays in the queue and comes due again", "B06"),
    "E02_second_delivery_not_refused": (
        INVENTORY, "\tif String(entry.get(\"state\", \"\")) != ENTRY_IN_TRANSIT:\n", "\tif false:\n",
        "the same delivery can be applied twice", "B14"),
    "G01_delivery_of_another_run_accepted": (
        INVENTORY, "\tif int(entry.get(\"generation\", -2)) != _generation:\n", "\tif false:\n",
        "a delivery of another run is credited", "B14"),
    "P01_transfer_applied_with_a_receiver_that_cannot_pay": (
        INVENTORY, "\tif donor_after_kg < 0.0 or (not delayed and receiver_after_kg < 0.0):\n", "\tif donor_after_kg < 0.0:\n",
        "a transfer the receiver cannot pay is applied: a negative inventory is written", "B14"),
    # --- laws that must not change -----------------------------------------------------------
    "O01_infiltration_reads_the_room_after_the_sink": (
        OXYGEN, "\t\t\troom, gas_kg, building.outside_o2, leaving_mole_fraction, \"infiltration\"\n",
        "\t\t\troom, gas_kg, building.outside_o2, room.o2, \"infiltration\"\n",
        "the infiltration law changes: gas leaves at the number the sink has just lowered", "B06"),
    "B01_cap_of_the_sink_on_the_historical_base": (
        OXYGEN, "\t\t\trequested, room_o2_inventory.inventory_kg(room) * FIRE_SINK_BULK_CAP_FRACTION\n",
        "\t\t\trequested, room.o2 * _compute_room_air_mass_kg(room, air_density_kg_m3) * FIRE_SINK_BULK_CAP_FRACTION\n",
        "the cap is 5 % of a mole fraction times a mass of gas, not of the inventory", "B11"),
    # --- refusals ---------------------------------------------------------------------------
    "S01_sealed_sink_route_not_refused": (
        OXYGEN, "\tif room.hrr_kw > 0.0 and sink_leaves_the_room_inventory:\n", "\tif false:\n",
        "a sealed room that burns is debited by M1 as if its sink took the room inventory", "B13"),
    "X01_exterior_opening_route_not_refused": (
        OXYGEN, "\tif room_o2_inventory != null:\n\t\troom_o2_inventory.refuse_route(indoor, \"exterior_opening_with_temperature_difference\", air_in_kg)\n\t\treturn\n",
        "",
        "the hot exterior opening is no longer refused by its name", "B13"),
    "N01_pressure_network_not_refused": (
        INVENTORY, "\t\"pressure_network_enabled\": false,\n", "",
        "the inventory arms with the pressure network on", "B13"),
    # --- life cycle in the engine ------------------------------------------------------------
    "F01_refused_inventory_still_simulated": (
        ENGINE, "\tif not o2_room_inventory_failure.is_empty():\n\t\treturn\n\tif o2_room_inventory_enabled != (\n",
        "\tif o2_room_inventory_enabled != (\n",
        "a run the inventory refused keeps advancing", "B13"),
    "Z01_switch_change_not_refused": (
        ENGINE, "\tif o2_room_inventory_enabled != (\n", "\tif false and o2_room_inventory_enabled != (\n",
        "the switch changes in the middle of a run and the run goes on", "B13"),
    "D02_retired_below_the_guards": (
        ENGINE, "\t_o2_room_inventory_discard()\n\t# G3 banco diagnóstico: misma regla. Se retira SIEMPRE, también sin edificio\n"
                "\t# o con el motor no preparado; se crea solo más abajo, cuando se puede.\n\t_g3_prescribed_thermal_discard()\n"
                "\tif building == null or not is_ready_for_validation():\n\t\t_discard_experimental_physics_authorization()\n\t\treturn\n",
        "\t# G3 banco diagnóstico: misma regla. Se retira SIEMPRE, también sin edificio\n"
        "\t# o con el motor no preparado; se crea solo más abajo, cuando se puede.\n\t_g3_prescribed_thermal_discard()\n"
        "\tif building == null or not is_ready_for_validation():\n\t\t_discard_experimental_physics_authorization()\n\t\treturn\n"
        "\t_o2_room_inventory_discard()\n",
        "a reset without a building or not ready returns before retiring the inventory and its transit", "B12"),
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _wait_for_memory(limit_s: int = 7200) -> float:
    """Wait, with the sources restored, until the launcher's own gate would open. The gate is not lowered."""
    minimum = float(os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV])
    started = time.time()
    while godot_monitored_launch._available_gib() < minimum + MEMORY_MARGIN_GIB:
        if time.time() - started > limit_s:
            raise RuntimeError("memory gate: not enough available memory after waiting")
        time.sleep(15)
    return time.time() - started


def prepared() -> tuple[dict[str, bytes], dict[str, tuple[str, str]]]:
    """Original bytes of the files and the mutated text of every mutant; anchors checked."""
    originals = {relative: (ROOT / relative).read_bytes() for relative in FILES}
    variants = {}
    for name, (relative, old, new, _defect, _where) in MUTATIONS.items():
        text = originals[relative].decode("utf-8")
        if text.count(old) != 1:
            raise ValueError(f"{name}: mutation anchor found {text.count(old)} times")
        variants[name] = (relative, text.replace(old, new))
        if variants[name][1] == text:
            raise ValueError(f"{name}: the mutation changes nothing")
    return originals, variants


def plan() -> dict:
    return {name: {"file": item[0], "defect": item[3], "expected_in": item[4],
                   "declared_with_the_plan": name in DECLARED_WITH_THE_PLAN} for name, item in MUTATIONS.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--only", action="append", default=[], help="run the control and these mutants")
    args = parser.parse_args()
    originals, variants = prepared()
    declared = plan()
    if args.plan_only:
        print(json.dumps({"declared": len(declared), "executed": False, "plan": declared}, indent=1))
        return 0
    unknown = [name for name in args.only if name not in variants]
    if unknown:
        raise ValueError(f"unknown mutants: {unknown}")
    if args.only:
        variants = {name: variants[name] for name in args.only}
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    before = {relative: _sha(data) for relative, data in originals.items()}
    evidence = ROOT / "runs" / ("g3_o2_room_inventory_mutations_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    evidence.mkdir(parents=True, exist_ok=False)
    (evidence / "plan.json").write_text(json.dumps(declared, indent=1), encoding="utf-8")
    results = []
    waited_s, refused_by_memory = 0.0, 0
    try:
        for name, (relative, text) in {"control": (None, ""), **variants}.items():
            run = None
            for _attempt in range(40):
                waited_s += _wait_for_memory()
                if relative is not None:
                    (ROOT / relative).write_bytes(text.encode("utf-8"))
                try:
                    run = godot_monitored_launch.run(
                        [godot, "--headless", "--path", ROOT, "--script", ROOT / FIXTURE],
                        timeout_s=TIMEOUT_S, environment=os.environ.copy())
                finally:
                    if relative is not None:
                        (ROOT / relative).write_bytes(originals[relative])
                        if _sha((ROOT / relative).read_bytes()) != before[relative]:
                            raise RuntimeError(f"{relative} not restored byte for byte")
                # A launch refused by the memory gate ran nothing: it is tried again, never counted.
                if run.launched or not any("memory gate" in str(item) for item in run.faults):
                    break
                refused_by_memory += 1
            folder = evidence / name
            folder.mkdir()
            for filename, content in [("health.json", json.dumps(run.health, indent=2)),
                                      ("stdout.log", run.stdout), ("stderr.log", run.stderr)]:
                (folder / filename).write_text(content or "", encoding="utf-8")
            if not run.launched:
                raise RuntimeError(f"{name}: not launched: {run.faults or run.preexisting}")
            payload, reason = {}, ""
            if run.faults or run.preexisting:
                verdict, reason = "invalid", f"monitor: {run.faults or run.preexisting}"
            else:
                try:
                    verdict, payload = classify(run.stdout, run.stderr, run.returncode, PREFIX)
                except (RuntimeError, ValueError) as exc:
                    verdict, reason = "invalid", str(exc)
            failures = payload.get("failures", [])
            expected = declared.get(name, {}).get("expected_in")
            results.append({
                "name": name, "verdict": verdict, "reason": reason,
                "file": relative, "defect": declared.get(name, {}).get("defect"), "expected_in": expected,
                "declared_with_the_plan": declared.get(name, {}).get("declared_with_the_plan"),
                "seen_where_expected": any(item.startswith(expected) for item in failures) if expected else None,
                "checks": payload.get("checks"), "failed_checks": payload.get("failure_count", len(failures)),
                "groups_with_failures": sorted(payload.get("failures_by_group", {})),
                "first_failures_where_expected": [item for item in failures if expected and item.startswith(expected)][:3],
                "mutant_sha256": _sha(text.encode("utf-8")) if relative else None,
            })
            print(json.dumps({key: results[-1][key] for key in
                              ("name", "verdict", "reason", "failed_checks", "seen_where_expected", "groups_with_failures")}),
                  flush=True)
            if name == "control" and verdict != "pass":
                raise RuntimeError("control is not green; no mutant verdict is meaningful")
    finally:
        after = {}
        for relative, data in originals.items():
            if _sha((ROOT / relative).read_bytes()) != before[relative]:
                (ROOT / relative).write_bytes(data)
            after[relative] = _sha((ROOT / relative).read_bytes())
        mutants = [item for item in results if item["name"] != "control"]
        summary = {
            "results": results, "originals_intact": after == before,
            "control": next((item["verdict"] for item in results if item["name"] == "control"), None),
            "control_checks": next((item["checks"] for item in results if item["name"] == "control"), None),
            "declared": len(variants), "executed": len(mutants),
            "killed": sum(item["verdict"] == "killed" for item in mutants),
            "killed_where_expected": sum(item["verdict"] == "killed" and bool(item["seen_where_expected"]) for item in mutants),
            "survivors": [item["name"] for item in mutants if item["verdict"] == "pass"],
            "invalid": [item["name"] for item in mutants if item["verdict"] == "invalid"],
            "killed_elsewhere": [item["name"] for item in mutants
                                 if item["verdict"] == "killed" and not item["seen_where_expected"]],
            "sha256_before": before, "sha256_after": after,
            "launches_refused_by_the_memory_gate_and_repeated": refused_by_memory,
            "seconds_waiting_for_memory": round(waited_s, 1),
        }
        (evidence / "results.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(json.dumps({key: summary[key] for key in ["control", "declared", "executed", "killed", "killed_where_expected",
                                                        "survivors", "invalid", "killed_elsewhere", "originals_intact"]}), flush=True)
        print("evidence:", evidence.relative_to(ROOT).as_posix(), flush=True)
        if after != before:
            raise RuntimeError("working sources changed")
    return 0 if summary["killed_where_expected"] == summary["declared"] == summary["executed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
