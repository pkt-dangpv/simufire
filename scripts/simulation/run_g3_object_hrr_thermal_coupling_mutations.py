#!/usr/bin/env python3
"""Code mutations of the thermal coupling bench of the prescribed HRR source.

Each mutant changes ONE of the three files of the coupling in the working tree by an
exact text replacement (every anchor must occur exactly once), runs the real-engine
fixture through the monitored launcher and restores the original bytes, SHA-256
verified, before the next one and also after an error. The unmutated control runs
first and must be green.

The defect each mutant injects is declared here, before anything runs. A kill is a
fixture that reached its end and reported failed checks. A parse error, a script
error, a timeout or a monitor fault is an invalid run, never a kill.

These are CODE mutants. The controls of invalid configuration (a room with fuel, a
second owner, a sealed room, an engine that is not the declared one) live inside the
fixture and are reported apart.

    python scripts/simulation/run_g3_object_hrr_thermal_coupling_mutations.py
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

COUPLING = "sim/fire/PrescribedThermalSourceCoupling.gd"
ENGINE = "sim/core/SimulationEngine.gd"
OXYGEN = "sim/core/OxygenExchangeSystem.gd"
FIXTURE = "tests/fixtures/g3_object_hrr_thermal_coupling.gd"
PREFIX = "G3_OBJECT_HRR_THERMAL_COUPLING"
TIMEOUT_S = 900
# A launch is tried a little above the gate, so that it is not refused a second later.
MEMORY_MARGIN_GIB = 0.05

# name: (file, old, new, defect, where the fixture must see it)
MUTATIONS: dict[str, tuple[str, str, str, str, str]] = {
    # --- power of the step ------------------------------------------------------------
    "P01_power_passes_through_a_first_order_filter": (
        COUPLING, "\t_room.hrr_kw = power_kw\n\t_room.burned_hrr_kw = power_kw\n\t_room.combustion_regime = REGIME_LABEL\n",
        "\t_room.hrr_kw = lerpf(float(_owned_room_fields.get(\"hrr_kw\", 0.0)), power_kw, 0.5)\n"
        "\t_room.burned_hrr_kw = power_kw\n\t_room.combustion_regime = REGIME_LABEL\n",
        "N1: the applied power is filtered instead of being the energy of the step", "B02"),
    "P02_fire_clock_used_as_the_clock_of_the_source": (
        COUPLING, "\tvar clock: float = _clock()\n\tif clock >= _support_end_s:\n",
        "\tvar clock: float = float(_room.fire_time_s)\n\tif clock >= _support_end_s:\n",
        "N2: the interval is taken from the fire clock of the room", "B02"),
    "P03_last_value_held_after_the_support": (
        COUPLING, "\tif _state != STATE_REPLAYING and _state != STATE_OUTSIDE:\n\t\treturn\n\tif not (dt > 0.0)",
        "\tif _state == STATE_COMPLETED:\n\t\t_write_room_power(float(_owned_room_fields.get(\"hrr_kw\", 0.0)))\n\t\treturn\n"
        "\tif _state != STATE_REPLAYING and _state != STATE_OUTSIDE:\n\t\treturn\n\tif not (dt > 0.0)",
        "N3: after the support the last power keeps being applied", "B02"),
    "P04_last_interval_divided_by_its_own_duration": (
        COUPLING, "\t_write_room_power(energy_kj / dt)\n",
        "\t_write_room_power(energy_kj / (end_time_s - clock))\n",
        "the last, shorter interval is spread over itself and not over the whole step: energy is created", "B03"),
    "P05_interval_not_cut_at_the_end_of_the_support": (
        COUPLING, "\tvar end_time_s: float = minf(clock + dt, _support_end_s)\n",
        "\tvar end_time_s: float = clock + dt\n",
        "the last step asks the source for time outside its support", "B03"),
    # --- oxygen -----------------------------------------------------------------------
    "O01_debit_not_compared_with_the_committed_one": (
        COUPLING, "\tif absf(room_inventory_kg - committed_kg) > tolerance or absf(primary_kg - room_inventory_kg) > tolerance:\n",
        "\tif false:\n",
        "N7: a debit that is not the committed one leaves its heat counted as valid", "B06"),
    "O02_heat_not_withdrawn_when_the_debit_differs": (
        COUPLING, "\t\t_totals[\"oxygen_debited_without_heat_kg\"] += all_kg\n\t\t_withdraw_room_power()\n",
        "\t\t_totals[\"oxygen_debited_without_heat_kg\"] += all_kg\n",
        "N7: the step is rejected but its power still reaches ThermalSystem", "B06"),
    "O03_no_oxygen_committed": (
        COUPLING, "\tvar committed_kg: float = energy_kj / 1000.0 * float(_case[\"oxygen_kg_per_MJ\"])\n",
        "\tvar committed_kg: float = 0.0\n",
        "energy is accepted with no equivalent oxygen committed", "B02"),
    "O04_generic_co2_tracer_not_excluded_in_the_sink": (
        OXYGEN, "\t\telif room.hrr_kw > 0.0 and not g3_prescribed_thermal_room_ids.has(room.id):\n",
        "\t\telif room.hrr_kw > 0.0:\n",
        "N6: the generic carbon dioxide tracer produces from the power of the bench", "B02"),
    "O05_engine_does_not_tell_the_sink_which_room": (
        ENGINE, "\t\toxygen_hooks[\"g3_prescribed_thermal_room_ids\"] = [\n\t\t\tint(g3_prescribed_thermal_source_case.get(\"room_id\", -1))\n\t\t]\n",
        "\t\tpass\n",
        "N6: the engine does not hand the room to the oxygen system", "B02"),
    # --- regime and latch --------------------------------------------------------------
    "R01_oxygen_tolerance_not_judged": (
        COUPLING, "\tif room_drop > tolerance or lower_drop > tolerance:\n", "\tif false:\n",
        "R2: the oxygen of the room may fall without leaving the regime", "B06"),
    "R02_layer_criterion_not_judged": (
        COUPLING, "\tif interface_m < float(_case[\"regime\"][\"layer_interface_min_m\"]):\n", "\tif false:\n",
        "R3: the hot layer may wrap the source without leaving the regime", "B06"),
    "R03_room_fire_not_judged": (
        COUPLING, "\tif _room.fire != null:\n\t\treturn {\"cause\": \"the_room_has_a_room_fire\"}\n", "",
        "R4: a room fire beside the bench is not named as the cause", "B07"),
    "R04_fuel_in_the_room_not_judged": (
        COUPLING, "\tif not _room_errors(_room).is_empty():\n\t\treturn {\"cause\": \"the_room_has_fuel\"}\n", "",
        "R4: fuel put in the room during the run does not stop the bench", "B07"),
    "R05_suppression_not_judged": (
        COUPLING, "\tif bool(_hooks[\"suppression_active\"].call(int(_room.id))):\n", "\tif false:\n",
        "R4: water in the room does not stop the bench", "B07"),
    "R06_regime_can_be_entered_again": (
        COUPLING, "\tif _state == STATE_REPLAYING:\n\t\tvar cause: Dictionary = _regime_failure(energy_kj, dt)\n",
        "\tif _state == STATE_OUTSIDE and _regime_failure(energy_kj, dt).is_empty():\n\t\t_state = STATE_REPLAYING\n"
        "\tif _state == STATE_REPLAYING:\n\t\tvar cause: Dictionary = _regime_failure(energy_kj, dt)\n",
        "N10: the state is not latched and the bench starts again when the oxygen returns", "B06"),
    "R07_rejected_interval_waits_instead_of_being_confirmed": (
        COUPLING, "\tif _state == STATE_OUTSIDE:\n\t\t_settle(proposal, 0.0)\n\t\treturn\n", "\tif _state == STATE_OUTSIDE:\n\t\treturn\n",
        "N8: outside the regime the clock stops and the interval is kept for later", "B06"),
    "R08_rejected_energy_becomes_unburned_inventory": (
        COUPLING, "\t_totals[\"rejected_kj\"] += float(done[\"rejected_this_step_kj\"])\n",
        "\t_totals[\"rejected_kj\"] += float(done[\"rejected_this_step_kj\"])\n"
        "\t_room.retained_unburned_MJ += float(done[\"rejected_this_step_kj\"]) / 1000.0\n",
        "N9: rejected energy is stored as unburned fuel of the room", "B06"),
    "R09_half_accepted_at_the_exit": (
        COUPLING, "\tif _state == STATE_OUTSIDE:\n\t\t_settle(proposal, 0.0)\n\t\treturn\n",
        "\tif _state == STATE_OUTSIDE:\n\t\t_settle(proposal, 0.5 * energy_kj)\n\t\treturn\n",
        "outside the regime a part of the interval is still accepted", "B06"),
    "R10_power_applied_while_the_interval_is_rejected": (
        COUPLING, "\tif _state == STATE_OUTSIDE:\n\t\t_settle(proposal, 0.0)\n\t\treturn\n",
        "\tif _state == STATE_OUTSIDE:\n\t\t_write_room_power(energy_kj / dt)\n\t\t_settle(proposal, 0.0)\n\t\treturn\n",
        "outside the regime the room still receives power and loses oxygen", "B06"),
    "R11_exit_not_latched_when_the_debit_differs": (
        COUPLING, "\t\t_leave_regime({\n\t\t\t\"cause\": \"oxygen_debit_is_not_the_committed_one\",\n", "\t\t_last_step.merge({\n\t\t\t\"cause\": \"oxygen_debit_is_not_the_committed_one\",\n",
        "a debit that differs rejects the step but leaves the bench replaying", "B06"),
    # --- heat ---------------------------------------------------------------------------
    "H01_heat_reported_by_thermal_system_not_judged": (
        COUPLING, "\tif not errors.is_empty():\n\t\t_fail(errors)\n\n\n# ---------------------------------------------------------------- what it says",
        "\tif not errors.is_empty():\n\t\tpass\n\n\n# ---------------------------------------------------------------- what it says",
        "heat that is not the accepted energy does not stop the bench", "B07"),
    "H02_radiative_fraction_of_the_case_not_handed_to_the_room": (
        COUPLING, "\t_room.chi_rad_normal = declared\n", "",
        "the engine default fraction is applied whatever the case declares", "B05"),
    # --- arming ---------------------------------------------------------------------------
    "A01_room_not_checked_when_arming": (
        COUPLING, "\terrors.append_array(_room_errors(room))\n\tif not errors.is_empty():\n", "\tif not errors.is_empty():\n",
        "N4/N5: a room with fuel or with a room fire is armed", "B08"),
    "A02_engine_not_checked_when_arming": (
        COUPLING, "\terrors.append_array(_environment_errors(environment))\n", "",
        "N14: an engine with another oxygen mode or without the heat diagnostic is armed", "B08"),
    "A03_identity_of_the_source_not_checked": (
        COUPLING, "\tif described.get(\"source_fingerprint\") != c[\"expected_source_fingerprint\"]:\n", "\tif false:\n",
        "N15: a table with the same energy and another content is armed", "B08"),
    "A04_radiative_class_not_checked": (
        COUPLING, "\tif typeof(value[\"class\"]) != TYPE_STRING or not RADIATIVE_CLASSES.has(value[\"class\"]):\n", "\tif false:\n",
        "a fraction presented as measured in the enclosure is armed", "B08"),
    "A05_regime_status_not_checked": (
        COUPLING, "\tif not _same_text(value[\"status\"], REGIME_STATUS):\n", "\tif false:\n",
        "regime criteria presented as validated limits are armed", "B08"),
    # --- life cycle in the engine -----------------------------------------------------------
    "L01_failed_bench_still_simulated": (
        ENGINE, "\tif not g3_prescribed_thermal_source_failure.is_empty():\n\t\treturn\n\tif building == null or is_finished:\n",
        "\tif building == null or is_finished:\n",
        "a case that did not arm lets the engine advance", "B08"),
    "L02_previous_instance_not_retired": (
        ENGINE, "\tif _g3_prescribed_thermal_source != null:\n\t\t_g3_prescribed_thermal_source.discard()\n\t_g3_prescribed_thermal_source = null\n",
        "\t_g3_prescribed_thermal_source = null\n",
        "N12: a reset drops the previous instance without retiring what it wrote", "B09"),
    "L03_retired_below_the_guards": (
        ENGINE, "\t_g3_prescribed_thermal_discard()\n\tif building == null or not is_ready_for_validation():\n"
                "\t\t_discard_experimental_physics_authorization()\n\t\treturn\n",
        "\tif building == null or not is_ready_for_validation():\n"
        "\t\t_discard_experimental_physics_authorization()\n\t\treturn\n\t_g3_prescribed_thermal_discard()\n",
        "a reset without a building or not ready returns before retiring the bench", "B09"),
    "L04_clock_started_by_the_reset": (
        ENGINE, "\t_g3_prescribed_thermal_arm()\n\tif not g3_prescribed_thermal_source_failure.is_empty():\n\t\treturn\n",
        "\t_g3_prescribed_thermal_arm()\n\tif not g3_prescribed_thermal_source_failure.is_empty():\n\t\treturn\n"
        "\tif _g3_prescribed_thermal_source != null:\n\t\t_g3_prescribed_thermal_source.ignite(sim_time_s)\n",
        "the clock of the source starts at the reset and not at the ignition", "B09"),
    "L05_failure_of_a_previous_case_kept": (
        ENGINE, "\t_g3_prescribed_thermal_source = null\n\tg3_prescribed_thermal_source_failure = \"\"\n",
        "\t_g3_prescribed_thermal_source = null\n",
        "the failure of a refused case survives the next reset", "B09"),
    "L06_room_power_not_withdrawn_on_discard": (
        COUPLING, "\t\tif _owned_room_fields.has(\"hrr_kw\") and _room.hrr_kw == _owned_room_fields[\"hrr_kw\"]:\n\t\t\t_room.hrr_kw = 0.0\n",
        "\t\tif _owned_room_fields.has(\"hrr_kw\") and _room.hrr_kw == _owned_room_fields[\"hrr_kw\"]:\n\t\t\tpass\n",
        "a retired bench leaves its last power in the room", "B09"),
    # --- report ------------------------------------------------------------------------------
    "S01_any_run_reported_as_a_reproduction": (
        COUPLING, "\t\t\"is_a_reproduction_of_the_input\": _state == STATE_COMPLETED,\n",
        "\t\t\"is_a_reproduction_of_the_input\": _state != STATE_FAILED,\n",
        "a run that left the regime is reported as a reproduction", "B06"),
    "S02_nothing_declared_as_not_evaluated": (
        COUPLING, "\t\t\"not_evaluated\": NOT_EVALUATED.duplicate(),\n", "\t\t\"not_evaluated\": [],\n",
        "CO, FED and the rest are no longer declared as not evaluated", "B10"),
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _wait_for_memory(limit_s: int = 3600) -> float:
    """Wait, with the sources restored, until the launcher's own gate would open. The gate is not lowered."""
    minimum = float(os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV])
    started = time.time()
    while godot_monitored_launch._available_gib() < minimum + MEMORY_MARGIN_GIB:
        if time.time() - started > limit_s:
            raise RuntimeError("memory gate: not enough available memory after waiting")
        time.sleep(15)
    return time.time() - started


def prepared() -> tuple[dict[str, bytes], dict[str, tuple[str, str]]]:
    """Original bytes of the three files and the mutated text of every mutant; anchors checked."""
    originals = {relative: (ROOT / relative).read_bytes() for relative in (COUPLING, ENGINE, OXYGEN)}
    variants = {}
    for name, (relative, old, new, _defect, _where) in MUTATIONS.items():
        text = originals[relative].decode("utf-8")
        if text.count(old) != 1:
            raise ValueError(f"{name}: mutation anchor found {text.count(old)} times")
        variants[name] = (relative, text.replace(old, new))
        if variants[name][1] == text:
            raise ValueError(f"{name}: the mutation changes nothing")
    return originals, variants


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--only", action="append", default=[], help="run the control and these mutants")
    args = parser.parse_args()
    originals, variants = prepared()
    plan = {name: {"file": item[0], "defect": item[3], "expected_in": item[4]} for name, item in MUTATIONS.items()}
    if args.plan_only:
        print(json.dumps({"declared": len(plan), "executed": False, "plan": plan}, indent=1))
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
    evidence = ROOT / "runs" / ("g3_object_hrr_thermal_coupling_mutations_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    evidence.mkdir(parents=True, exist_ok=False)
    (evidence / "plan.json").write_text(json.dumps(plan, indent=1), encoding="utf-8")
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
            expected = plan.get(name, {}).get("expected_in")
            results.append({
                "name": name, "verdict": verdict, "reason": reason,
                "file": relative, "defect": plan.get(name, {}).get("defect"), "expected_in": expected,
                "seen_where_expected": any(item.startswith(expected) for item in failures) if expected else None,
                "checks": payload.get("checks"), "failed_checks": payload.get("failure_count", len(failures)),
                "groups_with_failures": sorted({item[:3] for item in failures}),
                "first_failures": failures[:4],
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
        if after != before:
            raise RuntimeError("working sources changed")
    return 0 if summary["killed_where_expected"] == summary["declared"] == summary["executed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
