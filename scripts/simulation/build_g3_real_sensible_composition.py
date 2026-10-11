"""Independent Python oracle of the real sensible composition, and its generated block.

The Godot fixture tests/fixtures/g3_real_sensible_composition.gd compares the
GDScript owner with the numbers written here. What is and is not independent:

* METHOD: independent. The step law is restated below from its written
  contract (prescribed heating, release cost L + h_gas(T) - h_liquid, release
  capped by inventory and by what B can still pay, oxidation capped by vapour
  and O2, mass-weighted mixing, signed Q). The prescribed release is integrated
  by its antiderivative, the analytic case sums knot trapezoids on its own and
  the context identity is recomputed here. None of it shares code with GDScript.
* DATA: not independent. The property values come from the same two approved
  profiles and the reference chemistry from the same audited phase basis.

The declared prototype chemistry is NOT a heptane calibration: specific heats
of reaction and latent heat per kilogram on the tabulated 100.20 g/mol, and
C/H mass fractions on NOMINAL atomic masses (C=12, H=1). The two bases serve
different purposes and are not reconciled. Nothing here starts Godot.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.simulation import audit_g3_heptane_phase_basis as phase_basis  # noqa: E402
from scripts.simulation import audit_g3_heptane_real_profile as real  # noqa: E402
from scripts.simulation import build_g3_heptane_real_cp_profiles as profiles  # noqa: E402

FIXTURE = ROOT / "tests/fixtures/g3_real_sensible_composition.gd"
NAME = "COMPOSITION EXPECTATIONS"
BEGIN = "# BEGIN GENERATED {name} (scripts/simulation/build_g3_real_sensible_composition.py)\n"
END = "# END GENERATED {name}\n"
LIQUID = "g3_real_liquid_isobaric_cp_v1"
GAS = "g3_real_ideal_gas_cp_v1"
REFERENCE_K = real.REFERENCE_K
OWNER_VERSION = "prescribed_real_sensible_phase_controller_v1"
COMPONENT = "n-heptane"
# Prescribed rate per unit initial mass, [time s, rate 1/s], linear between points.
PROGRAMS = {
    "ramp": [[0.0, 0.05], [4.0, 0.05], [8.0, 0.0]],
    "exhaust": [[0.0, 0.5], [2.0, 0.5]],
}
# name: (program, initial mass kg, O2 kg, B kJ, initial liquid sensible kJ,
#        steps of [end s, oxidation kg, heat liquid kJ, heat vapour kJ, emitted K])
SEQUENCES = {
    "main": ("ramp", 1.0, 10.0, 600.0, -5.0, [
        [1.0, 0.0, 100.0, 0.0, 371.0], [2.0, 0.03, 50.0, 2.0, 350.0], [2.0, 0.5, 9.0, 9.0, 400.0],
        [3.0, 0.5, 0.0, 0.0, 420.0], [5.0, 0.01, 10.0, 1.0, 469.0], [9.0, 0.0, 0.0, 0.0, 298.15]]),
    "budget_limited": ("ramp", 1.0, 10.0, 30.0, 0.0, [
        [1.0, 0.0, 20.0, 0.0, 371.0], [2.0, 0.0, 0.0, 0.0, 371.0], [3.0, 0.2, 0.0, 0.0, 330.0],
        [4.0, 0.0, 0.0, 0.0, 371.0], [5.0, 0.0, 1.0, 0.0, 371.0]]),
    "oxygen_limited": ("ramp", 1.0, 0.05, 600.0, 0.0, [
        [1.0, 0.04, 0.0, 0.0, 371.0], [2.0, 0.04, 0.0, 0.0, 371.0], [3.0, 0.04, 0.0, 0.0, 371.0]]),
    "heating_does_not_fit": ("ramp", 1.0, 10.0, 80.0, 0.0, [
        [1.0, 0.0, 60.0, 0.0, 371.0], [2.0, 0.0, 60.0, 0.0, 371.0], [2.0, 0.0, 5.0, 0.0, 371.0]]),
    "support": ("ramp", 1.0, 10.0, 600.0, 0.0, [
        [1.0, 0.0, 0.0, 0.0, 480.0], [1.0, 0.0, 0.0, 0.0, 298.0], [1.0, 0.0, 0.0, 0.0, 371.0],
        [2.0, 0.0, 200.0, 0.0, 371.0], [2.0, 0.0, 0.0, 12.0, 371.0], [2.0, 0.0, 100.0, 5.0, 371.0]]),
    "separate_supports": ("ramp", 1.0, 10.0, 600.0, 170.0, [
        [1.0, 0.0, 0.0, 0.0, 469.99], [2.0, 0.01, 0.0, 0.0, 298.14]]),
    "cold_liquid": ("ramp", 1.0, 10.0, 600.0, -40.0, [
        [1.0, 0.0, 0.0, 0.0, 298.15], [2.0, 0.02, 0.0, 0.0, 298.14]]),
    "history_cold": ("ramp", 1.0, 10.0, 600.0, 0.0, [
        [1.0, 0.0, 0.0, 0.0, 371.0], [2.0, 0.02, 0.0, 0.0, 371.0]]),
    "history_hot": ("ramp", 1.0, 10.0, 600.0, 0.0, [
        [1.0, 0.0, 90.0, 0.0, 371.0], [2.0, 0.02, 40.0, 3.0, 371.0]]),
    "exhaust": ("exhaust", 1.0, 10.0, 2000.0, 0.0, [
        [1.0, 0.0, 0.0, 0.0, 371.0], [2.0, 0.1, 0.0, 0.0, 371.0], [3.0, 0.1, 5.0, 0.0, 371.0],
        [3.0, 0.1, 0.0, 5.0, 371.0]]),
    "small_mass": ("ramp", 1.0e-9, 10.0, 600.0, 0.0, [
        [1.0, 1.0e-11, 5.0e-8, 0.0, 371.0], [9.0, 1.0, 0.0, 0.0, 400.0]]),
}


def reference_material():
    """Declared prototype chemistry: audited per-kilogram heats, nominal CHO atoms."""
    specific = phase_basis.audit(phase_basis.load_profile(phase_basis.INPUT))["specific_kj_kg"]
    carbon = 7 * 12.0 / (7 * 12.0 + 16 * 1.0)
    return {
        "schema": "g3_phase_reference_CHO_material_v1", "liquid_phase": "liquid", "vapour_phase": "gas",
        "water_product_phase": "gas", "atom_mass_basis": "nominal_C12_H1_O16",
        "chemical_energy_basis": "complete_oxidation_net", "reference_temperature_k": REFERENCE_K,
        "reference_pressure_pa": real.REFERENCE_PA,
        "mass_fractions": {"C": carbon, "H": 1.0 - carbon, "O": 0.0},
        "liquid_heat_kj_kg": specific["liquid_net_release"],
        "vapour_heat_kj_kg": specific["vapour_net_release"],
        "phase_enthalpy_kj_kg": specific["fuel_vaporization_enthalpy"],
        "provenance": ("declared prototype: NIST TN 2126-upd1 heats per kg on 100.20 g/mol with nominal C7H16 "
                       "atom fractions; not a heptane calibration"),
    }


def context_parts(program, mass, oxygen, budget, liquid_sensible):
    """Everything of the owner context except the two profiles, which the fixture asks the adapter for."""
    return {
        "schema": "g3_prescribed_real_sensible_context_v1",
        "program": {
            "profile_id": "declared_" + program, "component_id": COMPONENT, "initial_mass_kg": mass,
            "mode": "prescribed", "quantity": "modeled_component_emission", "unit": "kg/s",
            "time_origin": "declared_zero", "outside_domain": "reject", "interpolation": "piecewise_linear",
            "samples": [{"time_s": time, "rate_kg_s": rate * mass} for time, rate in PROGRAMS[program]]},
        "material": {"schema": "g3_phase_real_sensible_material_v1", "component_id": COMPONENT,
                     "reference_material": reference_material()},
        "attribution": {
            "input_component_id": COMPONENT, "modeled_component_id": COMPONENT,
            "input_quantity": "modeled_component_emission", "rule": "same_declared_component",
            "status": "synthetic_declared_emission",
            "provenance": "declared: prescribed emission program, not a measured or predicted evaporation"},
        "seed": {"schema": "g3_prescribed_real_sensible_seed_v1", "initial_o2_kg": oxygen,
                 "initial_thermal_budget_kj": budget, "initial_liquid_sensible_kj": liquid_sensible,
                 "energy_boundary_kind": "synthetic_independent_initial_budget",
                 "energy_boundary_provenance": "synthetic: independent initial budget, not a measured heat flux"},
    }


def _serialize(value):
    """Restatement of the owner's content serialisation: sorted keys, exact IEEE-754 bits."""
    if isinstance(value, dict):
        return "{" + ",".join(json.dumps(key) + ":" + _serialize(value[key]) for key in sorted(value)) + "}"
    if isinstance(value, list):
        return "[" + ",".join(_serialize(item) for item in value) + "]"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return "f64:" + struct.pack("<d", abs(float(value)) if value == 0 else float(value)).hex()
    return json.dumps(value)


def fingerprint(context):
    """Identity of a full context. The numbers must be the ones Godot holds, bit for bit:
    its parser does not always round a decimal literal as Python does."""
    return hashlib.sha256((OWNER_VERSION + _serialize(context)).encode("utf-8")).hexdigest()


def _released(program, start, end):
    """Released fraction of the initial mass in [start, end], by the antiderivative of the rate."""
    total = 0.0
    for (t0, r0), (t1, r1) in zip(program, program[1:]):
        lo, hi = max(start, t0), min(end, t1)
        if hi > lo:
            slope = (r1 - r0) / (t1 - t0)
            total += r0 * (hi - lo) + 0.5 * slope * ((hi - t0) ** 2 - (lo - t0) ** 2)
    return total


def _phase_kinds(profile, mass, sensible):
    """Evidence classes between the reference and a specific enthalpy, compared in enthalpy."""
    if mass <= 0.0:
        return []
    specific = sensible / mass
    low, high = min(0.0, specific), max(0.0, specific)
    kinds = []
    for tier in profile["evidence_tiers"]:
        first = real.canonical_enthalpy(profile["samples"], tier["its90_range_k"][0])
        last = real.canonical_enthalpy(profile["samples"], tier["its90_range_k"][1])
        if min(last, high) - max(first, low) > 0.0 or (low == high and first <= low <= last):
            kinds.append(tier["evidence_kind"])
    return kinds


class Oracle:
    def __init__(self, content, material, program, mass, oxygen, budget, liquid_sensible):
        self.liquid_profile, self.gas_profile = content[LIQUID], content[GAS]
        self.liquid, self.gas = content[LIQUID]["samples"], content[GAS]["samples"]
        self.material = material
        self.program = PROGRAMS[program]
        self.mass0 = mass
        self.time = 0.0
        self.source_time = 0.0
        self.state = {"initial_fuel_mass_kg": mass, "liquid_fuel_kg": mass, "vapour_fuel_kg": 0.0, "o2_kg": oxygen,
                      "thermal_budget_kj": budget, "deposited_heat_kj": 0.0,
                      "liquid_sensible_kj": liquid_sensible, "vapour_sensible_kj": 0.0}

    def _inside(self, samples, mass, sensible):
        if mass == 0.0:
            return sensible == 0.0
        low = real.canonical_enthalpy(samples, samples[0]["temperature_k"])
        high = real.canonical_enthalpy(samples, samples[-1]["temperature_k"])
        return mass * low <= sensible <= mass * high

    def valid(self):
        s = self.state
        return (self._inside(self.liquid, s["liquid_fuel_kg"], s["liquid_sensible_kj"])
                and self._inside(self.gas, s["vapour_fuel_kg"], s["vapour_sensible_kj"]))

    def accounts(self):
        s, m = self.state, self.material
        potential = s["liquid_fuel_kg"] * m["liquid_heat_kj_kg"] + s["vapour_fuel_kg"] * m["vapour_heat_kj_kg"]
        sensible = s["liquid_sensible_kj"] + s["vapour_sensible_kj"]
        return {"potential_a_kj": potential, "sensible_s_kj": sensible, "budget_b_kj": s["thermal_budget_kj"],
                "deposited_q_kj": s["deposited_heat_kj"],
                "total_kj": potential + sensible + s["thermal_budget_kj"] + s["deposited_heat_kj"]}

    def step(self, end, oxidation, heat_liquid, heat_vapour, emitted_k):
        """Returns (accepted, accounts). A rejected step leaves the oracle untouched."""
        s, m = self.state, self.material
        if end < self.time or not self.gas[0]["temperature_k"] <= emitted_k <= self.gas[-1]["temperature_k"]:
            return False, {}
        dt = end - self.time
        source_end = min(end, self.program[-1][0])
        source_dt = source_end - self.source_time
        demand = self.mass0 * _released(self.program, self.source_time, source_end)
        emitted = real.canonical_enthalpy(self.gas, emitted_k)
        if dt == 0.0:
            return True, {"no_op": True}
        heating = heat_liquid + heat_vapour
        if heating > s["thermal_budget_kj"]:
            return False, {}
        liquid, vapour = s["liquid_fuel_kg"], s["vapour_fuel_kg"]
        heated_liquid = s["liquid_sensible_kj"] + heat_liquid
        heated_vapour = s["vapour_sensible_kj"] + heat_vapour
        if not self._inside(self.liquid, liquid, heated_liquid) or not self._inside(self.gas, vapour, heated_vapour):
            return False, {}
        liquid_specific = heated_liquid / liquid if liquid > 0.0 else 0.0
        latent = m["phase_enthalpy_kj_kg"]
        cost = latent + emitted - liquid_specific if liquid > 0.0 and demand > 0.0 else latent
        if cost <= 0.0:
            return False, {}
        available = s["thermal_budget_kj"] - heating
        fractions = m["mass_fractions"]
        oxygen_per_kg = (8.0 / 3.0) * fractions["C"] + 8.0 * fractions["H"] - fractions["O"]
        transferred = min(demand, liquid, available / cost)
        oxidized = min(oxidation, vapour + transferred, s["o2_kg"] / oxygen_per_kg)
        release_cost = min(available, transferred * cost)
        mixed_mass = vapour + transferred
        mixed_sensible = heated_vapour + transferred * emitted
        mixed_specific = mixed_sensible / mixed_mass if mixed_mass > 0.0 else 0.0
        oxidized_sensible = oxidized * mixed_specific
        chemical = oxidized * m["vapour_heat_kj_kg"]
        after = {
            "initial_fuel_mass_kg": s["initial_fuel_mass_kg"], "liquid_fuel_kg": liquid - transferred,
            "vapour_fuel_kg": mixed_mass - oxidized,
            "o2_kg": s["o2_kg"] - min(s["o2_kg"], oxidized * oxygen_per_kg),
            "thermal_budget_kj": available - release_cost,
            "deposited_heat_kj": s["deposited_heat_kj"] + chemical + oxidized_sensible,
            "liquid_sensible_kj": (liquid - transferred) * liquid_specific,
            "vapour_sensible_kj": (mixed_mass - oxidized) * mixed_specific,
        }
        before = self.state
        self.state = after
        if not self.valid():
            self.state = before
            return False, {}
        self.time, self.source_time = end, source_end
        return True, {
            "no_op": False, "physical_dt_s": dt, "source_dt_s": source_dt,
            "requested_release_kg": demand, "accepted_release_kg": transferred,
            "rejected_release_kg": demand - transferred,
            "accepted_oxidation_kg": oxidized, "rejected_oxidation_kg": oxidation - oxidized,
            "release_cost_kj": release_cost, "release_cost_kj_kg": cost,
            "heating_liquid_kj": heat_liquid, "heating_vapour_kj": heat_vapour,
            "released_liquid_sensible_kj": transferred * liquid_specific,
            "emitted_vapour_sensible_kj": transferred * emitted,
            "oxidized_sensible_kj": oxidized_sensible, "chemical_oxidation_heat_kj": chemical,
            "deposited_increment_kj": chemical + oxidized_sensible,
            "co2_kg": oxidized * fractions["C"] * (11.0 / 3.0), "water_vapour_kg": oxidized * fractions["H"] * 9.0,
            "o2_consumed_kg": min(before["o2_kg"], oxidized * oxygen_per_kg),
            "mixed_specific_kj_kg": mixed_specific,
            "temperature_average_specific_kj_kg": _temperature_average(self, vapour, heated_vapour, transferred,
                                                                       emitted_k),
            "emitted_kinds": profiles._kinds(self.gas_profile, min(REFERENCE_K, emitted_k),
                                             max(REFERENCE_K, emitted_k)),
        }


def _temperature(samples, specific):
    """Oracle-only bisection, used to show what a temperature average WOULD have given."""
    low, high = samples[0]["temperature_k"], samples[-1]["temperature_k"]
    for _ in range(80):
        middle = 0.5 * (low + high)
        if real.canonical_enthalpy(samples, middle) < specific:
            low = middle
        else:
            high = middle
    return 0.5 * (low + high)


def _temperature_average(oracle, vapour, heated_vapour, transferred, emitted_k):
    if vapour <= 0.0 or transferred <= 0.0:
        return None
    old_k = _temperature(oracle.gas, heated_vapour / vapour)
    mean_k = (vapour * old_k + transferred * emitted_k) / (vapour + transferred)
    return real.canonical_enthalpy(oracle.gas, mean_k)


def _knot_enthalpy(samples, index):
    """h(knot) - h(298.15 K) by its own trapezoid sum; it does not call the shared restatement."""
    reference = REFERENCE_K
    below = max(i for i, sample in enumerate(samples) if sample["temperature_k"] <= reference)
    if index <= below:
        raise ValueError("analytic knots are chosen above the reference")
    left, right = samples[below], samples[below + 1]
    fraction = (reference - left["temperature_k"]) / (right["temperature_k"] - left["temperature_k"])
    cp_reference = left["cp_kj_kg_k"] + fraction * (right["cp_kj_kg_k"] - left["cp_kj_kg_k"])
    terms = [0.5 * (cp_reference + right["cp_kj_kg_k"]) * (right["temperature_k"] - reference)]
    for a, b in zip(samples[below + 1:index], samples[below + 2:index + 1]):
        terms.append(0.5 * (a["cp_kj_kg_k"] + b["cp_kj_kg_k"]) * (b["temperature_k"] - a["temperature_k"]))
    return math.fsum(terms)


def _nearest(samples, temperature):
    return min(range(len(samples)), key=lambda i: abs(samples[i]["temperature_k"] - temperature))


def analytic(content, material):
    """Two steps in closed form: liquid on a knot, heated exactly to the next knot, vapour on a knot."""
    liquid, gas = content[LIQUID]["samples"], content[GAS]["samples"]
    il, ig = _nearest(liquid, 330.0), _nearest(gas, 400.0)
    h_liquid, h_next, h_gas = _knot_enthalpy(liquid, il), _knot_enthalpy(liquid, il + 1), _knot_enthalpy(gas, ig)
    latent = material["phase_enthalpy_kj_kg"]
    liquid_heat, vapour_heat = material["liquid_heat_kj_kg"], material["vapour_heat_kj_kg"]
    budget, oxygen, rate, oxidation = 600.0, 10.0, PROGRAMS["ramp"][0][1], 0.04
    cost_1 = latent + h_gas - h_liquid
    budget_1 = budget - rate * cost_1
    heat = (1.0 - rate) * (h_next - h_liquid)
    cost_2 = latent + h_gas - h_next
    total = liquid_heat + h_liquid + budget
    steps = [
        {"request": [1.0, 0.0, 0.0, 0.0, gas[ig]["temperature_k"]], "release_cost_kj_kg": cost_1,
         "phase": {"initial_fuel_mass_kg": 1.0, "liquid_fuel_kg": 1.0 - rate, "vapour_fuel_kg": rate, "o2_kg": oxygen,
                   "thermal_budget_kj": budget_1, "deposited_heat_kj": 0.0,
                   "liquid_sensible_kj": (1.0 - rate) * h_liquid, "vapour_sensible_kj": rate * h_gas},
         "potential_a_kj": (1.0 - rate) * liquid_heat + rate * vapour_heat, "total_kj": total},
        {"request": [2.0, oxidation, heat, 0.0, gas[ig]["temperature_k"]], "release_cost_kj_kg": cost_2,
         "phase": {"initial_fuel_mass_kg": 1.0, "liquid_fuel_kg": 1.0 - 2 * rate,
                   "vapour_fuel_kg": 2 * rate - oxidation, "o2_kg": oxygen - oxidation * 3.52,
                   "thermal_budget_kj": budget_1 - heat - rate * cost_2,
                   "deposited_heat_kj": oxidation * (vapour_heat + h_gas),
                   "liquid_sensible_kj": (1.0 - 2 * rate) * h_next,
                   "vapour_sensible_kj": (2 * rate - oxidation) * h_gas},
         "potential_a_kj": (1.0 - 2 * rate) * liquid_heat + (2 * rate - oxidation) * vapour_heat, "total_kj": total},
    ]
    parts = context_parts("ramp", 1.0, oxygen, budget, h_liquid)
    return {"context": parts, "steps": steps,
            "liquid_knot_k": liquid[il]["temperature_k"], "next_liquid_knot_k": liquid[il + 1]["temperature_k"],
            "gas_knot_k": gas[ig]["temperature_k"], "knot_enthalpies_kj_kg": [h_liquid, h_next, h_gas]}


def expectations(root=ROOT):
    content = profiles.approved_content(root)
    material = reference_material()
    liquid, gas = content[LIQUID]["samples"], content[GAS]["samples"]
    result = {
        "liquid_support_kj_kg": [real.canonical_enthalpy(liquid, liquid[0]["temperature_k"]),
                                 real.canonical_enthalpy(liquid, liquid[-1]["temperature_k"])],
        "gas_support_kj_kg": [real.canonical_enthalpy(gas, gas[0]["temperature_k"]),
                              real.canonical_enthalpy(gas, gas[-1]["temperature_k"])],
        "liquid_support_k": [liquid[0]["temperature_k"], liquid[-1]["temperature_k"]],
        "gas_support_k": [gas[0]["temperature_k"], gas[-1]["temperature_k"]],
        "molar_mass_g_mol": [content[LIQUID]["molar_mass_g_mol"], content[GAS]["molar_mass_g_mol"]],
        "nominal_molar_mass_g_mol": 7 * 12.0 + 16 * 1.0,
        "analytic": analytic(content, material),
        "sequences": {},
    }
    for name, (program, mass, oxygen, budget, liquid_sensible, steps) in SEQUENCES.items():
        oracle = Oracle(content, material, program, mass, oxygen, budget, liquid_sensible)
        if not oracle.valid():
            raise ValueError("seed outside support: " + name)
        parts = context_parts(program, mass, oxygen, budget, liquid_sensible)
        rows = []
        for end, oxidation, heat_liquid, heat_vapour, emitted_k in steps:
            accepted, accounts = oracle.step(end, oxidation, heat_liquid, heat_vapour, emitted_k)
            state = oracle.state
            rows.append({
                "request": [end, oxidation, heat_liquid, heat_vapour, emitted_k], "accepted": accepted,
                "step": accounts, "phase": dict(state), "time_s": oracle.time, "accounts": oracle.accounts(),
                "liquid_kinds": _phase_kinds(oracle.liquid_profile, state["liquid_fuel_kg"],
                                             state["liquid_sensible_kj"]),
                "vapour_kinds": _phase_kinds(oracle.gas_profile, state["vapour_fuel_kg"],
                                             state["vapour_sensible_kj"])})
        result["sequences"][name] = {"context": parts, "steps": rows}
    return profiles._floats(result)


def expectations_block(root=ROOT):
    return "const EXPECTED: Dictionary = " + profiles._literal(expectations(root), 0) + "\n"


def _spliced(text, block):
    begin, end = BEGIN.format(name=NAME), END.format(name=NAME)
    if text.count(begin) != 1 or text.count(end) != 1:
        raise ValueError("generated markers missing or repeated")
    head, rest = text.split(begin)
    return head + begin + block + end + rest.split(end)[1]


def stale(root=ROOT):
    text = FIXTURE.read_text(encoding="utf-8")
    return [] if _spliced(text, expectations_block(root)) == text else [FIXTURE.relative_to(ROOT).as_posix()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    if args.write:
        text = FIXTURE.read_text(encoding="utf-8")
        FIXTURE.write_text(_spliced(text, expectations_block()), encoding="utf-8", newline="\n")
    outdated = stale()
    print({"stale": outdated, "written": args.write})
    return 1 if outdated else 0


if __name__ == "__main__":
    raise SystemExit(main())
