#!/usr/bin/env python3
"""Independent analyzer of the engine balance observables (``g3_balance_v1``).

Reads ``g3_fuel_ledger_v3.jsonl`` rows that carry the ``bal_*`` blocks emitted
by the engine when the G3 ledger is on. It runs no engine and writes nothing
but its own report.

Every check keeps three kinds of value apart:

- **requested**: what a formula asks for before caps and scales;
- **applied**: what the formula hands over after caps and scales;
- **inventory**: the state read from the room or the object before and after
  the write.

A check never accepts two fields copied from the same computation as proof of
conservation: it recomputes the rule from the recorded inputs and compares it
with the inventory change. Tolerances are fixed here and are not tuned per run.

``U`` (pyrolysate that neither burns nor enters the pool) is reported as a
derived amount WITHOUT physical inventory; it is never counted as a resolved
loss.

    python scripts/simulation/analyze_g3_balance_ledger.py \
        --case D_o2_closed=runs/.../o2_closed --out runs/g3_balance_ledger_...
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

SCHEMA = "g3_balance_v1"
LEDGER = "g3_fuel_ledger_v3.jsonl"
ABS_TOL = 1e-12
REL_TOL = 1e-9

C_IN_CO, C_IN_CO2, C_IN_HCN = 12.0 / 28.0, 12.0 / 44.0, 12.0 / 27.0
O_IN_CO, O_IN_CO2 = 16.0 / 28.0, 32.0 / 44.0
SOOT_CARBON_FRACTION = 0.87
CO2_SMOKE_BASIS_FRACTION = 0.60
CO_LATENT_SMOLDER_FRACTION = 0.75
BACKDRAFT_POOL_FRACTION = 0.60
SUPPRESSION_POOL_FLOOR = 0.30
TRACER_MIN, TRACER_MAX = 0.0004, 0.30
MW_AIR, MW_CO2 = 29.0, 44.0
ZONE_MASS_KEY = {"bulk": "air_mass_kg", "upper": "upper_air_mass_kg", "lower": "lower_air_mass_kg",
                 "plume_lower": "lower_air_mass_kg"}

FINDINGS = {
    # code: (unit, owner, text)
    "F_debit_inventory": ("MJ", "CombustionSystem (débito por objeto)",
                          "el combustible quitado a los objetos no iguala el débito de la sala"),
    "F_debit_counter": ("MJ", "CombustionSystem (fuel_consumed_MJ_total)",
                        "el acumulado de combustible de la sala no avanza lo debitado"),
    "F_pyrolysis_without_debit": ("MJ", "CombustionSystem (extinción antes del débito)",
                                  "pirólisis anotada en el paso sin débito de combustible"),
    "F_generation_rule": ("MJ", "CombustionSystem (alta del depósito)",
                          "el alta pedida al depósito no sigue su regla"),
    "F_U_definition": ("MJ", "libro (campo derivado)",
                       "U no es pirólisis − objetivo − alta del depósito"),
    "F_heat_split": ("MJ", "CombustionSystem (reparto sólido/depósito)",
                     "calor sólido + calor del depósito no iguala el calor aplicado"),
    "F_heat_counter": ("MJ", "CombustionSystem (hrr_kj_total)",
                       "el acumulado de calor no avanza el calor aplicado"),
    "F_R_inventory": ("MJ", "CombustionSystem (saldo R por objeto)",
                      "el saldo R de los objetos no cambia lo que dice el cálculo"),
    "P_entry_continuity": ("MJ", "desconocido (entre el inicio del paso y el alta)",
                           "el depósito cambió antes de su primera escritura observada"),
    "P_credit_write": ("MJ", "CombustionSystem (alta del depósito)",
                       "el depósito tras el alta no es min(capacidad, antes + alta)"),
    "P_burn_write": ("MJ", "CombustionSystem (quema del depósito)",
                     "la baja por quema no iguala la quema pedida"),
    "P_decay_write": ("MJ", "CombustionSystem (decaimiento)",
                      "la baja por decaimiento no sigue la tasa y las señales registradas"),
    "P_backdraft_write": ("MJ", "CombustionSystem (backdraft)",
                          "la baja por backdraft no sigue su regla"),
    "P_suppression_write": ("MJ", "SimulationEngine (supresión)",
                            "la baja por supresión no sigue su factor"),
    "P_unrecorded_change": ("MJ", "desconocido",
                            "el depósito cambió en el paso sin ninguna baja o alta registrada"),
    "P_between_steps": ("MJ", "desconocido (entre pasos)",
                        "el depósito cambió entre el cierre de un paso y el inicio del siguiente"),
    "S_smoke_basis_rule": ("kW", "CombustionSystem (base del humo)",
                           "la base del humo no sale de sus términos registrados"),
    "S_smoke_request": ("kg", "CombustionSystem (humo)",
                        "el humo solicitado no es base × rendimiento"),
    "S_smoke_not_applied": ("kg", "GasExchangeSystem / extinción",
                            "el humo solicitado no es el que se añadió al inventario"),
    "S_co_basis_rule": ("kW", "CombustionSystem (base del CO)",
                        "la base del CO no sale de sus términos registrados"),
    "S_co_request": ("kg", "CombustionSystem (CO)", "el CO solicitado no es base × rendimiento"),
    "S_hcn_request": ("kg", "CombustionSystem (HCN)", "el HCN solicitado no es base × rendimiento"),
    "S_co2_request": ("kg", "CombustionSystem (CO₂ de masa)",
                      "el CO₂ solicitado no es rendimiento × max(calor, 0,6 × base del humo)"),
    "S_co2_terms": ("MJ", "CombustionSystem (base del CO₂)",
                    "los términos de la base del CO₂ no salen del calor ni de la base del humo"),
    "S_carbon_available": ("kg", "CombustionSystem (tope de carbono)",
                           "el carbono disponible no es el factor × el débito del paso"),
    "S_carbon_scale_unrecorded": ("kg", "CombustionSystem (tope de carbono)",
                                  "lo aplicado no es lo solicitado × la escala registrada"),
    "S_carbon_scale_rule": ("-", "CombustionSystem (tope de carbono)",
                            "la escala registrada no es tope / carbono solicitado"),
    "S_inventory_write": ("kg", "CombustionSystem (escritura de especies)",
                          "el inventario no cambió lo aplicado"),
    "S_generated_counter": ("kg", "CombustionSystem (contadores del paso)",
                            "el contador de especie generada no iguala lo aplicado"),
    "S_irritant_write": ("kg", "CombustionSystem (irritantes)",
                         "el inventario del irritante no cambió base × rendimiento"),
    "O_heat_seen": ("MJ", "OxygenExchangeSystem / extinción",
                    "el calor que ve el sumidero de O₂ no es el calor aplicado por la combustión"),
    "O_request": ("kg", "OxygenExchangeSystem",
                  "el O₂ solicitado por una ruta no es su regla sobre el calor"),
    "O_truncation_undeclared": ("kg", "OxygenExchangeSystem",
                                "lo aplicado no es min(solicitado, tope): hay un recorte sin declarar"),
    "O_inventory": ("kg", "OxygenExchangeSystem",
                    "el inventario de O₂ de la zona no cambió lo aplicado"),
    "O_zone_mass_base": ("kg", "OxygenExchangeSystem (base de masa de la ruta)",
                         "la fracción de la zona baja con una masa que no es la de la zona: "
                         "el O₂ aplicado no sale entero del inventario de esa zona"),
    "O_primary": ("kg", "OxygenExchangeSystem (o2_consumed_fire)",
                  "el débito primario del fuego no es el aplicado de su ruta"),
    "O_counters": ("kg", "OxygenExchangeSystem (contadores del paso)",
                   "los contadores de O₂ del paso no igualan lo aplicado"),
    "T_production": ("kg", "OxygenExchangeSystem (trazador de CO₂)",
                     "el CO₂ del trazador no es calor × rendimiento × escala de O₂"),
    "T_chain": ("fracción", "OxygenExchangeSystem (trazador de CO₂)",
                "el trazador no pasa de antes a después por los términos registrados"),
    "X_between_steps": ("mixto", "desconocido (entre pasos)",
                        "un inventario cambió entre el cierre de un paso y el inicio del siguiente"),
    "X_missing_block": ("pasos", "libro", "falta un bloque del esquema en un paso que debía tenerlo"),
}

CONTINUITY_FIELDS = (
    "co_kg", "co_upper_kg", "co2_kg", "co2_upper_kg", "hcn_kg", "hcn_upper_kg",
    "o2", "o2_upper", "o2_lower", "co2_upper_tracer", "smoke_kg",
    "hcl_kg", "acrolein_kg", "formaldehyde_kg",
)


def close(a: float, b: float) -> bool:
    return abs(a - b) <= ABS_TOL + REL_TOL * max(abs(a), abs(b))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


class Book:
    """Accumulates terms and findings over the steps of one room."""

    def __init__(self) -> None:
        self.terms: dict[str, float] = {}
        self.counts: dict[str, int] = {}
        self.findings: dict[str, dict] = {}
        self.time_s = 0.0

    def add(self, name: str, value: float) -> None:
        self.terms[name] = self.terms.get(name, 0.0) + value

    def count(self, name: str, n: int = 1) -> None:
        self.counts[name] = self.counts.get(name, 0) + n

    def flag(self, code: str, amount: float, detail: str = "") -> None:
        unit, owner, text = FINDINGS[code]
        entry = self.findings.setdefault(code, {
            "code": code, "steps": 0, "amount": 0.0, "abs_amount": 0.0, "worst": 0.0,
            "unit": unit, "owner": owner, "text": text, "first_time_s": self.time_s, "details": [],
        })
        entry["steps"] += 1
        entry["amount"] += amount
        entry["abs_amount"] += abs(amount)
        if abs(amount) > abs(entry["worst"]):
            entry["worst"] = amount
        if detail and detail not in entry["details"] and len(entry["details"]) < 6:
            entry["details"].append(detail)

    def expect(self, code: str, measured: float, expected: float, detail: str = "") -> bool:
        if close(measured, expected):
            return True
        self.flag(code, measured - expected, detail)
        return False


# --------------------------------------------------------------------------- fuel

def check_fuel(row: dict, book: Book) -> None:
    fuel = row.get("bal_fuel")
    before, after = row["bal_state_before"], row.get("bal_state_after", {})
    consumed = float(row.get("consumed_MJ", 0.0))
    book.add("fuel_debit_MJ", consumed)
    objects = [o for o in row.get("objects", []) if not o.get("is_proxy")]
    if objects and row.get("ownership_mode") == "explicit_owned":
        taken = sum(float(o["remaining_before_MJ"]) - float(o.get("remaining_after_MJ", o["remaining_before_MJ"]))
                    for o in objects)
        book.add("fuel_object_inventory_change_MJ", taken)
        book.expect("F_debit_inventory", taken, consumed)
    if after:
        book.expect("F_debit_counter",
                    float(after["fuel_consumed_MJ_total"]) - float(before["fuel_consumed_MJ_total"]), consumed)
    if fuel is None:
        return
    pyrolysis = float(fuel["pyrolysis_MJ"])
    target = float(fuel["flame_target_MJ"]) + float(fuel["smolder_target_MJ"])
    generation = float(fuel["pool_generation_MJ"])
    unowned = float(fuel["unburned_without_inventory_MJ"])
    book.add("pyrolysis_MJ", pyrolysis)
    book.add("target_MJ", target)
    book.add("pool_generation_requested_MJ", generation)
    book.add("U_without_inventory_MJ", unowned)
    book.add("U_while_flaming_MJ" if fuel["can_flame"] else "U_while_not_flaming_MJ", unowned)
    if fuel.get("physical_inventory") is not False:
        book.flag("F_U_definition", unowned, "U sin la etiqueta physical_inventory = false")
    book.expect("F_U_definition", unowned, pyrolysis - target - generation)
    if not close(pyrolysis, consumed):
        book.flag("F_pyrolysis_without_debit", pyrolysis - consumed,
                  "extinción" if "bal_extinction" in row else "sin extinción registrada")
    rule = float(fuel["unburned_generation_fraction"]) * max(0.0, pyrolysis - target)
    if not fuel["can_flame"] and fuel["latent_viable"]:
        rule = 0.0
    book.expect("F_generation_rule", generation, rule)
    solid, pool_heat = float(fuel["solid_heat_MJ"]), float(fuel["pool_heat_MJ"])
    dt = float(row["dt_s"])
    book.add("solid_heat_MJ", solid)
    book.add("pool_heat_MJ", pool_heat)
    book.add("release_from_R_MJ", float(fuel["release_from_R_MJ"]))
    book.expect("F_heat_split", solid + pool_heat, float(row["hrr_applied_kw"]) * dt / 1000.0,
                "extinción: liberación de R calculada y no confirmada" if row.get("optd_uncommitted") else "")
    if after:
        counted = (float(after["hrr_kj_total"]) - float(before["hrr_kj_total"])) / 1000.0
        book.add("heat_counted_MJ", counted)
        book.expect("F_heat_counter", counted, solid + pool_heat,
                    "extinción" if "bal_extinction" in row else "sin extinción registrada")
    optd = row.get("optd")
    if optd and not row.get("optd_uncommitted"):
        computed = sum(float(o["acc_MJ"]) - float(o["rel_MJ"]) for o in optd["objects"].values())
        stored = sum(float(o["r_balance_after_MJ"]) - float(o["r_balance_before_MJ"])
                     for o in objects if "r_balance_before_MJ" in o)
        book.add("R_change_MJ", stored)
        book.add("R_accrued_MJ", sum(float(o["acc_MJ"]) for o in optd["objects"].values()))
        book.add("R_released_MJ", sum(float(o["rel_MJ"]) for o in optd["objects"].values()))
        book.expect("F_R_inventory", stored, computed)


# --------------------------------------------------------------------------- pool

def check_pool(row: dict, book: Book) -> None:
    before, after = row["bal_state_before"], row.get("bal_state_after")
    chain = float(before["pool_MJ"])
    dt = float(row["dt_s"])
    pool = row.get("bal_pool")
    if pool is not None:
        book.expect("P_entry_continuity", float(pool["before_MJ"]), chain)
        start = float(pool["before_MJ"])
        credit = float(pool["credit_requested_MJ"])
        after_credit = float(pool["after_credit_MJ"])
        book.expect("P_credit_write", after_credit, min(float(pool["capacity_MJ"]), max(0.0, start + credit)))
        book.add("pool_credit_requested_MJ", credit)
        book.add("pool_credit_applied_MJ", after_credit - start)
        book.add("pool_loss_cap_MJ", start + credit - after_credit)
        after_burn = float(pool["after_burn_MJ"])
        burn = float(pool["burn_requested_MJ"])
        book.expect("P_burn_write", after_credit - after_burn, min(after_credit, burn))
        book.add("pool_loss_burn_MJ", after_credit - after_burn)
        after_decay = float(pool["after_decay_MJ"])
        factor = 1.0 + 1.5 * float(pool["opening_signal"]) + 0.5 * (1.0 - float(pool["temp_signal"]))
        book.expect("P_decay_write", after_burn - after_decay,
                    min(after_burn, after_burn * float(pool["decay_per_s"]) * factor * dt))
        book.add("pool_loss_decay_MJ", after_burn - after_decay)
        after_backdraft = float(pool["after_backdraft_MJ"])
        expected = 0.0
        if pool["backdraft_active"] and after_decay > 0.0:
            expected = min(after_decay, float(pool["backdraft_hrr_kw"]) * dt / 1000.0 * BACKDRAFT_POOL_FRACTION)
        book.expect("P_backdraft_write", after_decay - after_backdraft, expected)
        book.add("pool_loss_backdraft_MJ", after_decay - after_backdraft)
        chain = after_backdraft
    elif chain > 0.0:
        # No fire in the room: the engine runs no pool step, so what is left neither
        # decays, burns nor moves.
        book.count("pool_positive_without_fire_steps")
        book.add("pool_held_without_fire_MJ_s", chain * dt)
    extinction = row.get("bal_extinction")
    if extinction is not None:
        book.count("extinction_steps")
        if extinction["burned_out"]:
            book.add("pool_loss_burnout_reset_MJ", chain)
            chain = 0.0
    suppression = row.get("bal_suppression")
    if suppression is not None:
        start = float(suppression["pool_before_MJ"])
        end = float(suppression["pool_after_MJ"])
        if not close(start, chain):
            book.flag("P_unrecorded_change", chain - start, "antes de la supresión")
        book.expect("P_suppression_write", start - end,
                    start * (1.0 - lerp(SUPPRESSION_POOL_FLOOR, 1.0, float(suppression["hrr_factor"]))))
        book.add("pool_loss_suppression_MJ", start - end)
        chain = end
    if after is not None:
        final = float(after["pool_MJ"])
        if not close(final, chain):
            book.flag("P_unrecorded_change", chain - final, "entre la última escritura observada y el cierre")
            book.add("pool_loss_unrecorded_MJ", chain - final)
        book.terms["pool_end_MJ"] = final
    book.terms.setdefault("pool_start_MJ", float(before["pool_MJ"]))


# ------------------------------------------------------------------------ species

def check_species(row: dict, book: Book) -> None:
    species = row.get("bal_species")
    fuel = row.get("bal_fuel")
    after = row.get("bal_state_after", {})
    if species is None or fuel is None:
        return
    dt = float(row["dt_s"])
    can_flame, latent = bool(fuel["can_flame"]), bool(fuel["latent_viable"])
    smoke = species["smoke"]
    solid = float(smoke["solid_heat_term_kw"])
    target = (float(smoke["flame_target_kw"]) + float(smoke["smolder_target_kw"])) * float(smoke["basis_multiplier"])
    retained, pool_term = float(smoke["retained_term_kw"]), float(smoke["pool_term_kw"])
    basis = max(solid, target) + retained + pool_term
    if not can_flame:
        basis = max(basis, float(smoke["smolder_target_kw"]) + retained) if latent else 0.0
    book.expect("S_smoke_basis_rule", float(smoke["basis_kw"]), basis)
    book.expect("F_heat_split", solid * dt / 1000.0, float(fuel["solid_heat_MJ"]), "término de calor del humo")
    smoke_yield = max(0.0, float(smoke["yield_kg_per_MJ"]))
    requested = float(smoke["requested_kg"])
    book.expect("S_smoke_request", requested, max(0.0, float(smoke["basis_kw"])) / 1000.0 * smoke_yield * dt)
    added = float(after.get("step", {}).get("smoke_generated_kg", 0.0)) if after else 0.0
    book.add("smoke_requested_kg", requested)
    book.add("smoke_added_kg", added)
    if not close(requested, added):
        book.flag("S_smoke_not_applied", requested - added,
                  "extinción" if "bal_extinction" in row else "sin extinción registrada")
    if can_flame or latent:
        heat_only = solid / 1000.0 * smoke_yield * dt
        book.add("smoke_requested_on_heat_kg", min(requested, heat_only))
        book.add("smoke_requested_above_heat_kg", max(0.0, requested - heat_only))
        book.add("smoke_basis_above_heat_MJ", max(0.0, float(smoke["basis_kw"]) - solid) * dt / 1000.0)
    if not species.get("committed"):
        book.count("species_uncommitted_steps")
        return
    co = species["co"]
    co_basis = float(co["solid_heat_term_kw"]) + float(co["pool_term_kw"]) + float(co["retained_term_kw"])
    if not can_flame and latent:
        co_basis = max(co_basis, float(co["smolder_target_kw"]) * CO_LATENT_SMOLDER_FRACTION
                       + float(co["retained_term_kw"]))
    book.expect("S_co_basis_rule", float(co["basis_kw"]), co_basis)
    book.expect("F_heat_split", float(co["solid_heat_term_kw"]) * dt / 1000.0, float(fuel["solid_heat_MJ"]),
                "término de calor del CO")
    co_basis_MJ = float(co["basis_kw"]) * dt / 1000.0
    book.expect("S_co_request", float(co["requested_kg"]), float(co["yield_kg_per_MJ"]) * co_basis_MJ)
    hcn = species["hcn"]
    book.expect("S_hcn_request", float(hcn["requested_kg"]),
                float(hcn["yield_kg_per_MJ"]) * float(hcn["basis_kw"]) * dt / 1000.0)
    co2 = species["co2"]
    heat_term, smoke_term = float(co2["heat_term_MJ"]), float(co2["smoke_basis_term_MJ"])
    book.expect("S_co2_terms", heat_term, float(row["hrr_applied_kw"]) * dt / 1000.0, "término de calor")
    book.expect("S_co2_terms", smoke_term, CO2_SMOKE_BASIS_FRACTION * float(smoke["basis_kw"]) * dt / 1000.0,
                "término de la base del humo")
    co2_yield = float(co2["yield_kg_per_MJ"])
    book.expect("S_co2_request", float(co2["requested_kg"]), co2_yield * max(heat_term, smoke_term))
    book.add("co2_requested_on_heat_kg", co2_yield * heat_term)
    book.add("co2_requested_above_heat_kg", co2_yield * max(0.0, smoke_term - heat_term))
    if smoke_term > heat_term:
        book.count("co2_on_smoke_basis_steps")

    clamp_block = species["carbon_clamp"]
    c_per_MJ = float(clamp_block["c_kg_per_MJ"])
    book.expect("S_carbon_available", float(clamp_block["c_available_kg"]),
                c_per_MJ * float(row.get("consumed_MJ", 0.0)))
    c_requested = (float(co["requested_kg"]) * C_IN_CO + float(co2["requested_kg"]) * C_IN_CO2
                   + float(hcn["requested_kg"]) * C_IN_HCN)
    c_clamp = float(clamp_block["c_clamp_kg"])
    acts = c_clamp > 0.0 and c_requested > c_clamp
    scale = float(clamp_block["scale"])
    book.expect("S_carbon_scale_rule", scale, c_clamp / c_requested if acts else 1.0)
    if bool(clamp_block["applied"]) != acts:
        book.flag("S_carbon_scale_rule", 1.0, "el tope dice que actuó y no debía, o al revés")
    if acts:
        book.count("carbon_clamp_steps")
    inv_before, inv_after = species["inventory_before"], species["inventory_after"]
    counters = after.get("step", {}) if after else {}
    for name, block, c_fraction, counter in (
            ("co", co, C_IN_CO, "co_generated_kg"), ("co2", co2, C_IN_CO2, "co2_generated_kg"),
            ("hcn", hcn, C_IN_HCN, "hcn_generated_kg")):
        requested_kg, applied_kg = float(block["requested_kg"]), float(block["applied_kg"])
        book.add(f"{name}_requested_kg", requested_kg)
        book.add(f"{name}_applied_kg", applied_kg)
        book.add("carbon_clamp_removed_kg", (requested_kg - applied_kg) * c_fraction)
        book.expect("S_carbon_scale_unrecorded", applied_kg, requested_kg * scale, name)
        change = float(inv_after[f"{name}_kg"]) - float(inv_before[f"{name}_kg"])
        book.add(f"{name}_inventory_change_kg", change)
        book.expect("S_inventory_write", change, applied_kg, name)
        upper_applied = float(block.get("applied_upper_kg", applied_kg))
        book.expect("S_inventory_write",
                    float(inv_after[f"{name}_upper_kg"]) - float(inv_before[f"{name}_upper_kg"]),
                    upper_applied, f"{name} zona superior")
        if counters:
            book.expect("S_generated_counter", float(counters[counter]), applied_kg, name)
    irritants = species.get("irritants")
    if irritants:
        basis_MJ = float(irritants["basis_kw"]) * dt / 1000.0
        for name in ("hcl", "acrolein", "formaldehyde"):
            change = float(irritants[f"{name}_after_kg"]) - float(irritants[f"{name}_before_kg"])
            book.add(f"{name}_inventory_change_kg", change)
            book.expect("S_irritant_write", change, float(irritants[f"{name}_yield_kg_per_MJ"]) * basis_MJ, name)
    gas_carbon = (float(co["applied_kg"]) * C_IN_CO + float(co2["applied_kg"]) * C_IN_CO2
                  + float(hcn["applied_kg"]) * C_IN_HCN)
    book.add("carbon_available_kg", float(clamp_block["c_available_kg"]))
    book.add("carbon_of_R_release_kg", c_clamp - float(clamp_block["c_available_kg"]))
    book.add("carbon_in_gases_kg", gas_carbon)
    book.add("carbon_in_soot_requested_kg", float(clamp_block["c_in_soot_kg"]))
    book.add("carbon_in_soot_added_kg", SOOT_CARBON_FRACTION * added)
    book.add("oxygen_in_co_co2_kg", float(co["applied_kg"]) * O_IN_CO + float(co2["applied_kg"]) * O_IN_CO2)


# -------------------------------------------------------------------------- oxygen

def _primary_route(o2: dict) -> str | None:
    sinks = o2["sinks"]
    route = "bulk" if "bulk" in sinks else None
    if o2.get("phase2b_upper_active") and "upper" in sinks:
        route = "upper"
    if "lower" in sinks:
        route = "lower"
    if "plume_lower" in sinks:
        route = "plume_lower"
    return route


def check_oxygen(row: dict, book: Book) -> None:
    o2 = row.get("bal_o2")
    if o2 is None:
        return
    dt = float(row["dt_s"])
    rate = float(o2["o2_kg_per_MJ"])
    heat_seen = float(o2["hrr_kw"]) * dt / 1000.0
    fuel = row.get("bal_fuel")
    heat_applied = (float(fuel["solid_heat_MJ"]) + float(fuel["pool_heat_MJ"])) if fuel else 0.0
    book.add("heat_seen_by_o2_sink_MJ", heat_seen)
    if not close(heat_seen, heat_applied):
        book.flag("O_heat_seen", heat_applied - heat_seen,
                  "extinción" if "bal_extinction" in row else "sin extinción registrada")
    primary = _primary_route(o2)
    applied_total = 0.0
    for route, sink in o2["sinks"].items():
        factor = 1.0
        if route == "upper" and sink.get("branch") == "displacement":
            factor = float(sink["displacement_frac"])
        if route == "plume_lower":
            factor = float(sink["depletion_fraction"])
        requested = float(sink["requested_kg"])
        applied = float(sink.get("applied_kg", 0.0))
        book.expect("O_request", requested, float(o2["hrr_kw"]) / 1000.0 * rate * dt * factor, route)
        expected_applied = min(requested, float(sink["cap_kg"]))
        if not close(applied, expected_applied):
            book.flag("O_truncation_undeclared", expected_applied - applied, route)
        truncated = requested - applied
        if route == "bulk":
            change = float(sink["mass_before_kg"]) - float(sink["mass_after_kg"])
        else:
            change = (float(sink["fraction_before"]) - float(sink["fraction_after"])) * float(sink["mass_base_kg"])
        follows_own_base = book.expect("O_inventory", change, applied, route)
        zone_change = change
        if route != "bulk":
            zone_change = (float(sink["fraction_before"]) - float(sink["fraction_after"]))                 * float(o2[ZONE_MASS_KEY[route]])
        if follows_own_base and not close(zone_change, applied):
            book.flag("O_zone_mass_base", applied - zone_change, route)
        role = "fire" if route == primary else "non_fire"
        book.add(f"o2_{role}_zone_mass_change_kg", zone_change)
        book.add(f"o2_{role}_requested_kg", requested)
        book.add(f"o2_{role}_applied_kg", applied)
        book.add(f"o2_{role}_truncated_kg", truncated)
        book.add(f"o2_{role}_inventory_change_kg", change)
        book.add(f"o2_route_{route}_applied_kg", applied)
        if truncated > ABS_TOL:
            book.count(f"o2_truncated_steps_{route}")
        applied_total += applied
    primary_applied = float(o2["sinks"][primary].get("applied_kg", 0.0)) if primary else 0.0
    book.expect("O_primary", float(o2["fire_primary_kg"]), primary_applied)
    book.add("o2_thornton_on_applied_heat_kg", rate * heat_applied)
    book.add("o2_fire_debit_minus_thornton_kg", primary_applied - rate * heat_applied)
    if "bulk" in o2["sinks"] or "bulk_ach_kg" in o2:
        air = float(o2["air_mass_kg"])
        mass = float(o2["bulk_fraction_before_write"]) * air
        if "bulk" in o2["sinks"]:
            book.expect("O_inventory", float(o2["sinks"]["bulk"]["mass_before_kg"]), mass, "bulk: masa de entrada")
            mass = float(o2["sinks"]["bulk"]["mass_after_kg"])
        ach = float(o2.get("bulk_ach_kg", 0.0))
        unclamped = (mass + ach) / air
        book.expect("O_inventory", float(o2["bulk_fraction_unclamped"]), unclamped, "bulk: fracción sin clamp")
        clamped = clamp(float(o2["bulk_fraction_unclamped"]), 0.0, float(o2["o2_nominal"]))
        book.expect("O_inventory", float(o2["bulk_fraction_after_write"]), clamped, "bulk: clamp")
        book.add("o2_bulk_ach_kg", ach)
        book.add("o2_bulk_clamp_loss_kg", (float(o2["bulk_fraction_unclamped"]) - clamped) * air)
    upper_mass, lower_mass = float(o2["upper_air_mass_kg"]), float(o2["lower_air_mass_kg"])
    book.add("o2_room_loop_bulk_mass_drop_kg",
             (float(o2["o2_before"]) - float(o2["o2_after"])) * float(o2["air_mass_kg"]))
    book.add("o2_room_loop_zonal_mass_drop_kg",
             (float(o2["o2_upper_before"]) - float(o2["o2_upper_after"])) * upper_mass
             + (float(o2["o2_lower_before"]) - float(o2["o2_lower_after"])) * lower_mass)
    lower_ach = o2.get("lower_ach")
    if lower_ach:
        book.add("o2_lower_ach_zone_mass_kg", float(lower_ach["delta_fraction"]) * lower_mass)
    after = row.get("bal_state_after")
    if after:
        counters = after["step"]
        book.expect("O_counters", float(counters["o2_consumed_fire_kg"]), float(o2["fire_primary_kg"]), "fuego")
        book.expect("O_counters", float(counters["o2_consumed_all_kg"]), applied_total, "todos")
        book.add("o2_exterior_net_kg", float(counters["o2_exterior_net_kg"]))
        book.add("o2_net_transport_kg", float(counters["o2_net_transport_kg"]))


# -------------------------------------------------------------------------- tracer

def check_tracer(row: dict, book: Book) -> None:
    tracer = row.get("bal_co2_tracer")
    if tracer is None:
        return
    dt = float(row["dt_s"])
    before = float(tracer["fraction_before"])
    base = float(tracer["mass_base_kg"])
    if tracer["branch"] == "production":
        produced = float(tracer["produced_kg"])
        book.expect("T_production", produced,
                    float(tracer["hrr_kw"]) / 1000.0 * float(tracer["yield_kg_per_MJ"]) * dt * float(tracer["o2_scale"]))
        delta = produced * MW_AIR / max(0.001, base * MW_CO2)
        book.expect("T_chain", float(tracer["delta_fraction"]), delta, "incremento")
        if not tracer.get("subc_boost_active"):
            book.expect("T_chain", float(tracer["fraction_before_clamp"]),
                        before + float(tracer["delta_fraction"]) + float(tracer["ach_delta_fraction"]), "suma")
        book.add("co2_tracer_produced_kg", produced)
        book.add("co2_tracer_unscaled_kg", float(tracer["hrr_kw"]) / 1000.0 * float(tracer["yield_kg_per_MJ"]) * dt)
        book.count("co2_tracer_production_steps")
    else:
        book.count(f"co2_tracer_{tracer['branch']}_steps")
    book.expect("T_chain", float(tracer["fraction_after"]),
                clamp(float(tracer["fraction_before_clamp"]), TRACER_MIN, TRACER_MAX), "clamp")
    equivalent = float(tracer["fraction_after"]) * base * MW_CO2 / MW_AIR
    gap = equivalent - float(tracer["room_co2_upper_kg"])
    if abs(gap) > abs(book.terms.get("co2_two_accounts_largest_gap_kg", 0.0)):
        book.terms["co2_two_accounts_largest_gap_kg"] = gap
        book.terms["co2_two_accounts_largest_gap_time_s"] = book.time_s
    book.terms["co2_tracer_equivalent_end_kg"] = equivalent
    book.terms["co2_mass_upper_end_kg"] = float(tracer["room_co2_upper_kg"])


def check_continuity(previous: dict | None, row: dict, book: Book) -> None:
    if previous is None:
        return
    before = row["bal_state_before"]
    if not close(float(previous["pool_MJ"]), float(before["pool_MJ"])):
        book.flag("P_between_steps", float(before["pool_MJ"]) - float(previous["pool_MJ"]))
    for name in CONTINUITY_FIELDS:
        if not close(float(previous[name]), float(before[name])):
            book.flag("X_between_steps", float(before[name]) - float(previous[name]), name)


def check_row(previous_after: dict | None, row: dict, book: Book) -> None:
    book.time_s = float(row.get("time_s", 0.0))
    book.count("steps")
    if row.get("bal_schema") != SCHEMA:
        book.flag("X_missing_block", 1.0, "bal_schema")
        return
    for block in ("bal_state_before", "bal_state_after", "bal_o2", "bal_co2_tracer"):
        if block not in row:
            book.flag("X_missing_block", 1.0, block)
    if row.get("fire_present_before"):
        book.count("fire_steps")
        for block in ("bal_fuel", "bal_pool", "bal_species"):
            if block not in row:
                book.flag("X_missing_block", 1.0, block)
    if "bal_state_before" not in row:
        return
    check_continuity(previous_after, row, book)
    check_fuel(row, book)
    check_pool(row, book)
    check_species(row, book)
    check_oxygen(row, book)
    check_tracer(row, book)


def summarize(book: Book) -> dict:
    terms = dict(book.terms)
    pool_losses = sum(terms.get(name, 0.0) for name in (
        "pool_loss_cap_MJ", "pool_loss_burn_MJ", "pool_loss_decay_MJ", "pool_loss_backdraft_MJ",
        "pool_loss_burnout_reset_MJ", "pool_loss_suppression_MJ", "pool_loss_unrecorded_MJ"))
    terms["pool_closure_MJ"] = (terms.get("pool_start_MJ", 0.0) + terms.get("pool_credit_requested_MJ", 0.0)
                                - pool_losses - terms.get("pool_end_MJ", 0.0))
    products = terms.get("carbon_in_gases_kg", 0.0) + terms.get("carbon_in_soot_added_kg", 0.0)
    allowed = terms.get("carbon_available_kg", 0.0) + terms.get("carbon_of_R_release_kg", 0.0)
    terms["carbon_products_minus_fuel_kg"] = products - terms.get("carbon_available_kg", 0.0)
    terms["carbon_products_minus_clamp_kg"] = products - allowed
    terms["co2_tracer_minus_mass_applied_kg"] = (terms.get("co2_tracer_produced_kg", 0.0)
                                                 - terms.get("co2_applied_kg", 0.0))
    return {
        "schema": SCHEMA,
        "tolerance": {"absolute": ABS_TOL, "relative": REL_TOL},
        "counts": dict(sorted(book.counts.items())),
        "terms": dict(sorted(terms.items())),
        "U_without_inventory": {
            "MJ": terms.get("U_without_inventory_MJ", 0.0),
            "physical_inventory": False,
            "note": "derivado; el motor no tiene variable ni destino para esta energía",
        },
        "findings": sorted(book.findings.values(), key=lambda item: item["code"]),
    }


def room_rows(path: Path, room_id: int):
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if f'"room_id":{room_id},' not in line and f'"room_id": {room_id},' not in line:
                continue
            row = json.loads(line)
            if int(row["room_id"]) == room_id:
                yield row


def analyze_rows(rows) -> dict:
    book = Book()
    previous_after = None
    for row in rows:
        check_row(previous_after, row, book)
        previous_after = row.get("bal_state_after")
    return summarize(book)


def analyze_case(case_dir: Path, room_id: int = 0) -> dict:
    return analyze_rows(room_rows(case_dir / LEDGER, room_id))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", action="append", required=True, metavar="LABEL=DIR")
    parser.add_argument("--room", type=int, default=0)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    args.out.mkdir(parents=True, exist_ok=True)
    report = {}
    for item in args.case:
        label, _, directory = item.partition("=")
        report[label] = analyze_case(Path(directory), args.room)
        report[label]["case_dir"] = directory
    (args.out / "balance_ledger.json").write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
    brief = {label: {"findings": {f["code"]: [f["steps"], f["amount"]] for f in data["findings"]}}
             for label, data in report.items()}
    print(json.dumps(brief, indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
