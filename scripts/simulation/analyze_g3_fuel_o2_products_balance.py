#!/usr/bin/env python3
"""Read-only book of pyrolysed fuel, heat, O2 and products per step (design section 14).

Built from ledgers that already exist (``g3_fuel_ledger_v3.jsonl`` and
``fuel_source_ledger.jsonl``), streamed line by line. It runs no engine and
changes nothing. It keeps two things apart:

* the **accounting closure** of a step, in MJ: fuel debited
  ``C = B_solid + lag + G + U``, where ``lag = T_s dt - B_solid`` is option D's
  ``dR`` when the switch is ON and an unowned term otherwise;
* the **physical balance** afterwards: what happens to ``G`` inside the room
  pool (burned, decayed, left), that ``U`` has no owner at all, which O2 was
  debited for which heat, and how much carbon and oxygen the generated species
  carry compared with the fuel that actually burned.

MJ of ``R``, ``G`` or ``U`` are never a gas mass: the engine keeps the fuel in
MJ only. Carbon uses the engine's single ``fuel_c_kg_per_MJ``.

``findings`` lists what does not close. On the current engine several of them
are open by design; they are the falsification gates of a future correction.

    python scripts/simulation/analyze_g3_fuel_o2_products_balance.py \
        --case sofa_vent=runs/g3_optd_final_on_Y/sofa_vent --out runs/g3_balance_Z
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Iterable, Iterator


# Engine constants, read in the code on 2026-10-02 (not calibrated here).
FUEL_C_KG_PER_MJ = 0.027          # CombustionSystem: context "fuel_c_kg_per_MJ"
O2_KG_PER_MJ = 0.076              # SimulationEngine.fire_o2_consumption_kg_per_MJ (Thornton)
UNBURNED_GENERATION_FRACTION = 0.30   # fire_unburned_generation_fraction
POOL_DECAY_PER_S = 0.0025         # fire_unburned_decay_per_s
POOL_DECAY_FACTOR = (1.0, 3.0)    # 1 + 1.5 opening_signal + 0.5 (1 - temp_signal)
SOOT_CARBON_FRACTION = 0.87       # c_in_soot = smoke * 0.87
CO2_YIELD_MAX_KG_PER_MJ = 0.0831  # co2_base_yield_kg_per_MJ (the largest CO2 yield)
C_IN_CO, C_IN_CO2, C_IN_HCN = 12.0 / 28.0, 12.0 / 44.0, 12.0 / 27.0
O_IN_CO, O_IN_CO2 = 16.0 / 28.0, 32.0 / 44.0

STEP_TOL_MJ = 1.0e-9
STEP_TOL_KG = 1.0e-12
fsum = math.fsum

STEP_FIELDS = (
    "time_s", "dt_s", "fire", "flame",
    "C_MJ", "object_debit_MJ", "pyrolysis_MJ", "target_MJ", "B_solid_MJ", "B_pool_MJ", "lag_MJ", "dR_MJ",
    "G_MJ", "G_rule_MJ", "U_MJ",
    "pool_before_MJ", "pool_after_MJ", "pool_other_loss_MJ",
    "o2_fire_kg", "o2_all_sinks_kg", "o2_exterior_net_kg", "o2_thornton_kg",
    "co_kg", "co2_kg", "hcn_kg", "smoke_kg",
    "c_debited_kg", "c_gas_kg", "c_soot_kg", "c_burned_route_kg", "o_in_products_kg",
)


def room_rows(path: Path, schema: str, room_id: int = 0) -> Iterator[dict]:
    with Path(path).open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            row = json.loads(line)
            if row.get("schema_version") != schema:
                raise ValueError(f"{path}:{number}: schema mismatch")
            if int(row["room_id"]) == room_id:
                yield row


def book_step(v3: dict, v2: dict) -> dict:
    """One step of the book from the engine's two ledgers of the same step."""
    dt = float(v3["dt_s"])
    fire = bool(v3["fire_present_before"])
    mj = dt / 1000.0
    consumed = float(v3["consumed_MJ"]) if fire else 0.0
    target = (float(v3["flame_target_kw"]) + float(v3["smolder_target_kw"])) * mj if fire else 0.0
    solid = float(v3["actual_solid_burn_kw"]) * mj
    pool_burn = float(v3["actual_pool_burn_kw"]) * mj
    generation = float(v3["pool_generation_MJ"]) if fire else 0.0
    optd = v3.get("optd")
    delta_r = None
    if optd is not None:
        delta_r = fsum(o["acc_MJ"] - o["rel_MJ"] for o in optd["objects"].values())
    species = v3["species"]
    co, co2, hcn, smoke = (float(species[k]) for k in ("co_kg", "co2_kg", "hcn_kg", "smoke_kg"))
    pool_before, pool_after = float(v3["pool_before_MJ"]), float(v3["pool_after_MJ"])
    explicit = [obj for obj in v3["objects"] if not obj["is_proxy"]]
    # Fuel taken from the objects themselves: independent of the room's consumed_MJ.
    object_debit = fsum(float(o["remaining_before_MJ"]) - float(o["remaining_after_MJ"]) for o in explicit)         if explicit and v3.get("ownership_mode") == "explicit_owned" else None
    flame = fire and float(v3["flame_target_kw"]) > 0.0
    return {
        "time_s": float(v3["time_s"]), "dt_s": dt, "fire": fire,
        "flame": flame,
        "C_MJ": consumed, "object_debit_MJ": object_debit,
        "pyrolysis_MJ": float(v3["pyrolysis_kw"]) * mj if fire else 0.0,
        "target_MJ": target, "B_solid_MJ": solid, "B_pool_MJ": pool_burn,
        "lag_MJ": target - solid, "dR_MJ": delta_r,
        "G_MJ": generation,
        # The rule: with a flame, 30 % of the pyrolysate that does not burn goes to the pool.
        "G_rule_MJ": UNBURNED_GENERATION_FRACTION * max(0.0, consumed - target) if flame else None,
        "U_MJ": consumed - target - generation,
        "pool_before_MJ": pool_before, "pool_after_MJ": pool_after,
        "pool_other_loss_MJ": pool_before + generation - pool_burn - pool_after,
        "o2_fire_kg": float(v2["room_o2_consumed_fire_kg_total_delta"]),
        "o2_all_sinks_kg": float(v2["room_o2_consumed_kg_total_all_delta"]),
        "o2_exterior_net_kg": float(v2["room_o2_exterior_net_kg_total_delta"]),
        "o2_thornton_kg": O2_KG_PER_MJ * (solid + pool_burn),
        "co_kg": co, "co2_kg": co2, "hcn_kg": hcn, "smoke_kg": smoke,
        "c_debited_kg": FUEL_C_KG_PER_MJ * consumed,
        "c_gas_kg": C_IN_CO * co + C_IN_CO2 * co2 + C_IN_HCN * hcn,
        "c_soot_kg": SOOT_CARBON_FRACTION * smoke,
        "c_burned_route_kg": FUEL_C_KG_PER_MJ * (solid + pool_burn),
        "o_in_products_kg": O_IN_CO2 * co2 + O_IN_CO * co,
    }


def summarize(steps: Iterable[dict]) -> dict:
    """Cumulative book and the per-step extremes the findings need."""
    total: dict[str, list[float]] = {key: [] for key in (
        "C_MJ", "pyrolysis_MJ", "target_MJ", "B_solid_MJ", "B_pool_MJ", "G_MJ", "U_MJ", "pool_other_loss_MJ",
        "o2_fire_kg", "o2_all_sinks_kg", "o2_exterior_net_kg", "o2_thornton_kg",
        "co_kg", "co2_kg", "hcn_kg", "smoke_kg", "c_debited_kg", "c_gas_kg", "c_soot_kg",
        "c_burned_route_kg", "o_in_products_kg")}
    lag_positive, lag_negative, delta_r = [], [], []
    target_above_heat = []           # T_s dt above the solid heat: basis of smoke/CO2, not of O2
    u_flame, u_no_flame = [], []
    worst = {"debit_minus_pyrolysis_MJ": 0.0, "lag_minus_dR_MJ": 0.0, "o2_truncated_kg": 0.0,
             "pool_loss_below_decay_MJ": 0.0, "pool_loss_above_decay_MJ": 0.0, "negative_U_MJ": 0.0,
             "pool_negative_other_loss_MJ": 0.0, "object_debit_minus_C_MJ": 0.0, "G_minus_rule_MJ": 0.0}
    counts = {"steps": 0, "fire_steps": 0, "flame_steps": 0, "o2_truncated_steps": 0,
              "co2_over_heat_yield_steps": 0, "gas_carbon_over_burned_route_steps": 0,
              "oxygen_in_products_over_debit_steps": 0, "heat_without_fire_steps": 0}
    co2_excess_over_heat, c_gas_over_burned, o_over_debit = [], [], []
    has_r = False
    pool_first = pool_last = pool_peak = None
    last_time = 0.0
    for step in steps:
        counts["steps"] += 1
        counts["fire_steps"] += step["fire"]
        counts["flame_steps"] += step["flame"]
        last_time = step["time_s"]
        for key in total:
            total[key].append(step[key])
        heat = step["B_solid_MJ"] + step["B_pool_MJ"]
        if not step["fire"] and heat > STEP_TOL_MJ:
            counts["heat_without_fire_steps"] += 1
        (lag_positive if step["lag_MJ"] >= 0.0 else lag_negative).append(step["lag_MJ"])
        target_above_heat.append(max(0.0, step["lag_MJ"]))
        (u_flame if step["flame"] else u_no_flame).append(step["U_MJ"])
        worst["negative_U_MJ"] = min(worst["negative_U_MJ"], step["U_MJ"])
        worst["debit_minus_pyrolysis_MJ"] = max(
            worst["debit_minus_pyrolysis_MJ"], abs(step["C_MJ"] - step["pyrolysis_MJ"]))
        if step["object_debit_MJ"] is not None:
            worst["object_debit_minus_C_MJ"] = max(
                worst["object_debit_minus_C_MJ"], abs(step["object_debit_MJ"] - step["C_MJ"]))
        if step["G_rule_MJ"] is not None:
            worst["G_minus_rule_MJ"] = max(worst["G_minus_rule_MJ"], abs(step["G_MJ"] - step["G_rule_MJ"]))
        if step["dR_MJ"] is not None:
            has_r = True
            delta_r.append(step["dR_MJ"])
            if step["fire"]:
                worst["lag_minus_dR_MJ"] = max(worst["lag_minus_dR_MJ"], abs(step["lag_MJ"] - step["dR_MJ"]))
        truncated = step["o2_thornton_kg"] - step["o2_fire_kg"]
        if abs(truncated) > STEP_TOL_KG:
            counts["o2_truncated_steps"] += 1
            if abs(truncated) > abs(worst["o2_truncated_kg"]):
                worst["o2_truncated_kg"] = truncated
        if pool_first is None:
            pool_first = step["pool_before_MJ"]
        pool_last = step["pool_after_MJ"]
        pool_peak = max(pool_peak or 0.0, step["pool_after_MJ"])
        basis = step["pool_before_MJ"] + step["G_MJ"] - step["B_pool_MJ"]
        low = basis * POOL_DECAY_PER_S * POOL_DECAY_FACTOR[0] * step["dt_s"]
        high = basis * POOL_DECAY_PER_S * POOL_DECAY_FACTOR[1] * step["dt_s"]
        loss = step["pool_other_loss_MJ"]
        worst["pool_negative_other_loss_MJ"] = min(worst["pool_negative_other_loss_MJ"], loss)
        worst["pool_loss_below_decay_MJ"] = max(worst["pool_loss_below_decay_MJ"], low - loss)
        worst["pool_loss_above_decay_MJ"] = max(worst["pool_loss_above_decay_MJ"], loss - high)
        co2_allowed = CO2_YIELD_MAX_KG_PER_MJ * heat
        if step["co2_kg"] > co2_allowed + STEP_TOL_KG:
            counts["co2_over_heat_yield_steps"] += 1
            co2_excess_over_heat.append(step["co2_kg"] - co2_allowed)
        if step["c_gas_kg"] > step["c_burned_route_kg"] + STEP_TOL_KG:
            counts["gas_carbon_over_burned_route_steps"] += 1
            c_gas_over_burned.append(step["c_gas_kg"] - step["c_burned_route_kg"])
        if step["o_in_products_kg"] > step["o2_fire_kg"] + STEP_TOL_KG:
            counts["oxygen_in_products_over_debit_steps"] += 1
            o_over_debit.append(step["o_in_products_kg"] - step["o2_fire_kg"])
    sums = {key: fsum(values) for key, values in total.items()}
    out = {
        "counts": counts, "last_time_s": last_time, "has_R": has_r,
        "energy_MJ": {
            "C_debited": sums["C_MJ"], "pyrolysis": sums["pyrolysis_MJ"], "target": sums["target_MJ"],
            "B_solid": sums["B_solid_MJ"], "B_pool": sums["B_pool_MJ"],
            "lag_heat_below_target": fsum(lag_positive), "lag_heat_above_target": -fsum(lag_negative),
            "R_final": fsum(delta_r) if has_r else None,
            "R_accrued": fsum(lag_positive) if has_r else None,
            "R_released": -fsum(lag_negative) if has_r else None,
            "G_to_pool": sums["G_MJ"], "U_unowned": sums["U_MJ"],
            "U_while_flaming": fsum(u_flame), "U_while_not_flaming": fsum(u_no_flame),
            "closure_C_minus_B_lag_G_U": sums["C_MJ"] - sums["B_solid_MJ"]
            - (fsum(lag_positive) + fsum(lag_negative)) - sums["G_MJ"] - sums["U_MJ"],
        },
        "pool_MJ": {
            "start": pool_first, "end": pool_last, "peak": pool_peak,
            "credited_G": sums["G_MJ"], "burned": sums["B_pool_MJ"],
            "other_loss": sums["pool_other_loss_MJ"],
            "closure_start_plus_G_minus_burn_minus_loss_minus_end":
                (pool_first or 0.0) + sums["G_MJ"] - sums["B_pool_MJ"] - sums["pool_other_loss_MJ"] - (pool_last or 0.0),
        },
        "o2_kg": {
            "fire_debit": sums["o2_fire_kg"], "thornton_for_heat": sums["o2_thornton_kg"],
            "truncated": sums["o2_thornton_kg"] - sums["o2_fire_kg"],
            "all_sinks": sums["o2_all_sinks_kg"], "sinks_beyond_fire": sums["o2_all_sinks_kg"] - sums["o2_fire_kg"],
            "exterior_net": sums["o2_exterior_net_kg"],
            "oxygen_in_CO2_and_CO": sums["o_in_products_kg"],
            "oxygen_in_products_over_fire_debit": (sums["o_in_products_kg"] / sums["o2_fire_kg"])
            if sums["o2_fire_kg"] > 0.0 else None,
            "oxygen_in_products_above_debit_steps_sum": fsum(o_over_debit),
        },
        "species_kg": {key[:-3]: sums[key] for key in ("co_kg", "co2_kg", "hcn_kg", "smoke_kg")},
        "carbon_kg": {
            "debited_with_fuel": sums["c_debited_kg"],
            "in_CO_CO2_HCN": sums["c_gas_kg"], "in_soot": sums["c_soot_kg"],
            "untracked": sums["c_debited_kg"] - sums["c_gas_kg"] - sums["c_soot_kg"],
            "of_fuel_that_burned": sums["c_burned_route_kg"],
            "of_R": FUEL_C_KG_PER_MJ * fsum(delta_r) if has_r else None,
            "of_G": FUEL_C_KG_PER_MJ * sums["G_MJ"], "of_U": FUEL_C_KG_PER_MJ * sums["U_MJ"],
            "gas_carbon_over_burned_fuel": (sums["c_gas_kg"] / sums["c_burned_route_kg"])
            if sums["c_burned_route_kg"] > 0.0 else None,
            "gas_carbon_above_burned_route_steps_sum": fsum(c_gas_over_burned),
        },
        "species_basis": {
            "target_above_solid_heat_MJ": fsum(target_above_heat),
            "co2_per_MJ_of_heat": (sums["co2_kg"] / (sums["B_solid_MJ"] + sums["B_pool_MJ"]))
            if sums["B_solid_MJ"] + sums["B_pool_MJ"] > 0.0 else None,
            "co2_above_max_yield_on_heat_kg": fsum(co2_excess_over_heat),
            "smoke_per_MJ_of_heat": (sums["smoke_kg"] / (sums["B_solid_MJ"] + sums["B_pool_MJ"]))
            if sums["B_solid_MJ"] + sums["B_pool_MJ"] > 0.0 else None,
            "co_per_MJ_of_heat": (sums["co_kg"] / (sums["B_solid_MJ"] + sums["B_pool_MJ"]))
            if sums["B_solid_MJ"] + sums["B_pool_MJ"] > 0.0 else None,
        },
        "worst_step": worst,
    }
    out["findings"] = findings(out)
    return out


def findings(book: dict) -> list[dict]:
    """What does not close, each with its owner (or the lack of one). Never a generic loss."""
    energy, pool, o2, carbon = book["energy_MJ"], book["pool_MJ"], book["o2_kg"], book["carbon_kg"]
    worst, counts, basis = book["worst_step"], book["counts"], book["species_basis"]
    out: list[dict] = []

    def add(code: str, amount: float, unit: str, owner: str, text: str) -> None:
        out.append({"code": code, "amount": amount, "unit": unit, "owner": owner, "text": text})

    if abs(energy["closure_C_minus_B_lag_G_U"]) > 1e-6:
        add("E0_accounting_closure", energy["closure_C_minus_B_lag_G_U"], "MJ", "none",
            "C differs from B_solid + lag + G + U: a route of the debited fuel is missing from the book")
    if worst["debit_minus_pyrolysis_MJ"] > STEP_TOL_MJ:
        add("E1_debit_is_not_pyrolysis", worst["debit_minus_pyrolysis_MJ"], "MJ/step", "CombustionSystem",
            "fuel debited in a step differs from pyrolysis x dt")
    if book["has_R"] and worst["lag_minus_dR_MJ"] > STEP_TOL_MJ:
        add("E2_R_is_not_the_lag", worst["lag_minus_dR_MJ"], "MJ/step", "CombustionSystem (option D)",
            "dR of a step differs from target x dt minus solid heat")
    if not book["has_R"] and energy["lag_heat_below_target"] > 1e-6:
        add("E3_unowned_lag", energy["lag_heat_below_target"], "MJ", "none",
            "heat below the target with no balance to hold it (switch OFF or engine before option D)")
    if not book["has_R"] and energy["lag_heat_above_target"] > 1e-6:
        # With option D the heat above the target is R being released (checked by E2).
        add("E4_heat_above_target", energy["lag_heat_above_target"], "MJ", "HRR filter",
            "solid heat above the target with no balance behind it: fuel the same step counted as G or U, or no fuel at all")
    if energy["U_unowned"] > 1e-6:
        add("E5_U_has_no_owner", energy["U_unowned"], "MJ", "none",
            "pyrolysed fuel that is neither burned, nor R, nor in the pool: no inventory, zone or transport")
    if worst["negative_U_MJ"] < -STEP_TOL_MJ:
        add("E6_negative_U", worst["negative_U_MJ"], "MJ/step", "CombustionSystem",
            "target plus pool generation exceed the fuel debited in a step")
    if worst["object_debit_minus_C_MJ"] > STEP_TOL_MJ:
        add("E8_objects_debited_differently", worst["object_debit_minus_C_MJ"], "MJ/step", "CombustionSystem",
            "fuel taken from the objects in a step differs from the fuel the room consumed")
    if worst["G_minus_rule_MJ"] > STEP_TOL_MJ:
        add("E9_pool_generation_off_rule", worst["G_minus_rule_MJ"], "MJ/step", "CombustionSystem",
            "pool generation with a flame differs from 30 % of the pyrolysate that does not burn")
    if counts["heat_without_fire_steps"]:
        add("E7_heat_without_fire", counts["heat_without_fire_steps"], "steps", "CombustionSystem",
            "heat recorded in a step that had no fire")
    if abs(pool["closure_start_plus_G_minus_burn_minus_loss_minus_end"]) > 1e-6:
        add("P0_pool_closure", pool["closure_start_plus_G_minus_burn_minus_loss_minus_end"], "MJ", "none",
            "pool inventory does not follow start + G - burned - other loss")
    if pool["other_loss"] > 1e-6:
        add("P1_pool_loss_without_destination", pool["other_loss"], "MJ", "CombustionSystem (pool decay)",
            "retained fuel removed from the pool without burning: no heat, no O2, no species, no transport")
    if worst["pool_loss_above_decay_MJ"] > STEP_TOL_MJ:
        add("P2_pool_loss_above_decay", worst["pool_loss_above_decay_MJ"], "MJ/step", "unknown",
            "pool lost more in a step than its decay law allows (capacity cap, backdraft or suppression)")
    if worst["pool_loss_below_decay_MJ"] > STEP_TOL_MJ:
        add("P3_pool_loss_below_decay", worst["pool_loss_below_decay_MJ"], "MJ/step", "unknown",
            "pool lost less in a step than its decay law requires")
    if worst["pool_negative_other_loss_MJ"] < -STEP_TOL_MJ:
        add("P4_pool_gain_without_source", worst["pool_negative_other_loss_MJ"], "MJ/step", "unknown",
            "pool grew by more than the generation credited to it")
    if counts["o2_truncated_steps"]:
        add("O0_o2_debit_is_not_thornton", o2["truncated"], "kg", "OxygenExchangeSystem",
            f"fire O2 debit differs from 0.076 kg/MJ x heat in {counts['o2_truncated_steps']} steps")
    if o2["sinks_beyond_fire"] > 1e-9:
        add("O1_o2_sinks_beyond_the_fire", o2["sinks_beyond_fire"], "kg", "OxygenExchangeSystem (O2-4)",
            "O2 removed from the room by sinks other than the fire's Thornton debit")
    if counts["oxygen_in_products_over_debit_steps"]:
        add("O2_oxygen_in_products_above_debit", o2["oxygen_in_products_above_debit_steps_sum"], "kg",
            "CombustionSystem (species basis)",
            f"CO2 and CO carry more oxygen than the O2 debited in {counts['oxygen_in_products_over_debit_steps']} steps")
    if carbon["untracked"] > 1e-9:
        add("C0_carbon_untracked", carbon["untracked"], "kg", "none",
            "carbon debited with the fuel that is in no species: the carbon of R, G, U and unmodelled products")
    if carbon["untracked"] < -1e-9:
        add("C1_carbon_created", -carbon["untracked"], "kg", "CombustionSystem (species)",
            "species carry more carbon than the fuel debited")
    if counts["gas_carbon_over_burned_route_steps"]:
        add("C2_gas_carbon_above_burned_fuel", carbon["gas_carbon_above_burned_route_steps_sum"], "kg",
            "CombustionSystem (species basis)",
            f"CO, CO2 and HCN carry more carbon than the fuel burned in {counts['gas_carbon_over_burned_route_steps']} steps")
    if counts["co2_over_heat_yield_steps"]:
        add("S0_co2_above_yield_on_heat", basis["co2_above_max_yield_on_heat_kg"], "kg",
            "CombustionSystem (CO2 basis)",
            f"CO2 above its largest yield times the heat released in {counts['co2_over_heat_yield_steps']} steps")
    if basis["target_above_solid_heat_MJ"] > 1e-6:
        add("S1_species_basis_without_heat", basis["target_above_solid_heat_MJ"], "MJ",
            "CombustionSystem (smoke and CO2 basis)",
            "target above the solid heat: smoke and CO2 are produced on it, O2 is not debited for it")
    return out


def analyze_case(case_dir: Path, steps_csv: Path | None = None) -> dict:
    v3 = room_rows(case_dir / "g3_fuel_ledger_v3.jsonl", "g3_fuel_ledger_v3")
    v2 = room_rows(case_dir / "fuel_source_ledger.jsonl", "g3_fuel_source_step_v2")
    handle = writer = None
    if steps_csv is not None:
        steps_csv.parent.mkdir(parents=True, exist_ok=True)
        handle = steps_csv.open("w", encoding="utf-8", newline="")
        writer = csv.DictWriter(handle, fieldnames=STEP_FIELDS)
        writer.writeheader()

    def steps() -> Iterator[dict]:
        for row3, row2 in zip(v3, v2, strict=True):
            if abs(float(row3["time_s"]) - float(row2["time_s"])) > 1e-6:
                raise ValueError(f"{case_dir}: ledgers out of step at {row3['time_s']}")
            step = book_step(row3, row2)
            if writer is not None:
                writer.writerow(step)
            yield step

    try:
        book = summarize(steps())
    finally:
        if handle is not None:
            handle.close()
    scenario = json.loads((case_dir / "scenario.json").read_text(encoding="utf-8"))
    book["engine_overrides"] = scenario.get("engine_overrides", {})
    # CO2 is kept twice: as mass by CombustionSystem (co2_upper_ppm_mass) and as an
    # upper-zone mole fraction produced by OxygenExchangeSystem from the HRR (co2_upper_ppm).
    peak_tracer = peak_mass = 0.0
    largest_gap = (0.0, 0.0, 0.0, 0.0)
    with (case_dir / "sim_log.csv").open(encoding="utf-8-sig", newline="") as source:
        last = None
        for row in csv.DictReader(source):
            if row["room_id"] == "0":
                last = row
                tracer, mass = float(row["co2_upper_ppm"]), float(row["co2_upper_ppm_mass"])
                peak_tracer, peak_mass = max(peak_tracer, tracer), max(peak_mass, mass)
                if abs(tracer - mass) > abs(largest_gap[1] - largest_gap[2]):
                    largest_gap = (float(row["time_s"]), tracer, mass, tracer - mass)
    book["co2_two_representations_ppm"] = {
        "peak_upper_tracer_from_OES": peak_tracer, "peak_upper_from_mass_CombustionSystem": peak_mass,
        "final_upper_tracer": float(last["co2_upper_ppm"]), "final_upper_from_mass": float(last["co2_upper_ppm_mass"]),
        "largest_gap": dict(zip(("time_s", "tracer", "from_mass", "gap"), largest_gap)),
    }
    book["csv_final"] = {key: float(last[key]) for key in (
        "fuel_consumed_MJ_total", "hrr_kj_total", "retained_unburned_MJ", "co_generated_kg_total",
        "o2_consumed_fire_kg_total", "o2_consumed_kg_total_all", "smoke_generated_kg_total",
        "smoke_vented_kg_total", "smoke_deposited_kg_total", "co_exterior_removed_kg_total",
        "co_kg", "smoke_kg", "c_balance_frac", "carbon_conservation_error_kg")}
    return book


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case", action="append", required=True, metavar="LABEL=DIR",
                        help="case directory holding both ledgers (repeatable)")
    parser.add_argument("--out", type=Path, help="directory for <label>_steps.csv and balance.json")
    args = parser.parse_args()
    report = {}
    for item in args.case:
        label, directory = item.split("=", 1)
        steps_csv = args.out / f"{label}_steps.csv" if args.out is not None else None
        report[label] = analyze_case(Path(directory), steps_csv)
    if args.out is not None:
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "balance.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
