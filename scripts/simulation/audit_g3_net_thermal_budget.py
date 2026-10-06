"""Offline audit of a net thermal budget of the liquid fuel, B. Never a solver.

B is the net heat that crosses the boundary of the LIQUID control volume: what
the liquid absorbs minus what it loses. It is not the heat release rate, not a
chemical heat, not the flux a sensor reads and not a latent heat inferred from
the mass that was lost.

Two estimates are kept apart and never merged:

* INDEPENDENT: from measured heat flux, with the corrections the sources allow.
  It uses no mass measurement.
* DEMAND: a diagnostic reconstruction from the measured mass rate and the
  approved property profiles, mass times (latent + h_gas(T_surface) -
  h_liquid(T_feed)). It is what B would have to be; it is not an input.

An unknown term stays unknown: it is named, never filled in so that the
residual closes. An absent uncertainty is null, never zero. Temperatures
outside an approved profile are refused, not clipped. Nothing here starts
Godot, reads the engine or writes a file.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.simulation import audit_g3_heptane_phase_basis as phase_basis  # noqa: E402
from scripts.simulation import audit_g3_heptane_real_profile as real  # noqa: E402
from scripts.simulation import audit_g3_pool_thermal_evidence as pool  # noqa: E402
from scripts.simulation import build_g3_heptane_real_cp_profiles as profiles  # noqa: E402
from scripts.simulation.audit_g3_measured_mass_candidate import confined_artifact  # noqa: E402
from scripts.simulation.validate_g3_mass_material_profile import load_profile  # noqa: E402

INPUT = ROOT / "docs/validation/G3_D1_NET_THERMAL_BUDGET_INPUTS_2026-10-06.json"
SAVED = ROOT / "docs/validation/G3_D1_NET_THERMAL_BUDGET_AUDIT_2026-10-06.json"
# Pins the whole reviewed record: values, locators, term classification and approvals.
REVIEW_SHA256 = "b224c4bddfc1311fedd9e6e8f0562f6ab0f925cc08e2949053ff4044ffa9d32c"
LIQUID = "g3_real_liquid_isobaric_cp_v1"
GAS = "g3_real_ideal_gas_cp_v1"
KELVIN = 273.15
STATUSES = ("measured", "computed", "calculated", "modelled", "estimated", "assumed", "unknown",
            "demonstrably", "not reported")


def number(value, label):
    """A finite float; bool, text and None are refused."""
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{label}: finite number required")
    return float(value)


def fraction(value, label):
    value = number(value, label)
    if not 0.0 <= value < 1.0:
        raise ValueError(f"{label}: a fraction in [0, 1) is required; a percentage is not one")
    return value


def watts_to_kilowatts(value_w):
    return number(value_w, "power in W") / 1000.0


def grams_to_kilograms(value_g):
    return number(value_g, "mass in g") / 1000.0


def celsius_to_kelvin(value_c):
    return number(value_c, "temperature in C") + KELVIN


def properties(root=ROOT):
    content = profiles.approved_content(root)
    specific = phase_basis.audit(phase_basis.load_profile(phase_basis.INPUT))["specific_kj_kg"]
    return {"liquid": content[LIQUID]["samples"], "gas": content[GAS]["samples"],
            "latent_kj_kg": specific["fuel_vaporization_enthalpy"]}


def enthalpy(samples, temperature_k, label):
    """Signed h(T) - h(298.15 K) inside the approved support, or a refusal."""
    temperature = number(temperature_k, label)
    low, high = samples[0]["temperature_k"], samples[-1]["temperature_k"]
    if not low <= temperature <= high:
        raise ValueError(f"{label}: {temperature} K is outside the approved support {low} to {high} K")
    return real.canonical_enthalpy(samples, temperature)


def demand_per_kg(props, surface_k, feed_k):
    """Enthalpy to take 1 kg of liquid at the feed temperature to vapour at the surface temperature."""
    return (props["latent_kj_kg"] + enthalpy(props["gas"], surface_k, "surface temperature (gas)")
            - enthalpy(props["liquid"], feed_k, "feed temperature (liquid)"))


def ring_average(gauges, rings):
    """Pan average of equal-area rings. A ring needs at least one working gauge."""
    means = []
    for members in rings:
        values = [number(gauges[index - 1], f"gauge {index}") for index in members if gauges[index - 1] is not None]
        if not values:
            raise ValueError("a ring has no working gauge: the area integral has no support there")
        if any(value < 0 for value in values):
            raise ValueError("negative heat flux")
        means.append(math.fsum(values) / len(values))
    return means, math.fsum(means) / len(means)


def demand_rate_kw(mass_rate_g_s, enthalpy_kj_kg, storage_kw=0.0):
    """Diagnostic demand in kW. The storage term is added once, here, and nowhere else."""
    return grams_to_kilograms(mass_rate_g_s) * number(enthalpy_kj_kg, "enthalpy") + number(storage_kw, "storage")


def independent_rate_kw(gauge_kw, reflected_fraction, subtract_kw=(), add_kw=()):
    """Independent estimate in kW. It takes no mass rate and no residual."""
    absorbed = number(gauge_kw, "gauge power") * (1.0 - fraction(reflected_fraction, "reflected fraction"))
    return (absorbed - math.fsum(number(v, "loss") for v in subtract_kw)
            + math.fsum(number(v, "gain") for v in add_kw))


def rss(*fractions):
    if any(value is None for value in fractions):
        raise ValueError("an absent uncertainty cannot be combined: it is not zero")
    return math.sqrt(math.fsum(fraction(v, "uncertainty") ** 2 for v in fractions))


def closure(independent_range, demand_range, strict_fraction, loose_fraction):
    """Worst relative gap between two intervals, and the two predeclared verdicts."""
    gaps = [(i - d) / d for i in independent_range for d in demand_range]
    worst = max(gaps, key=abs)
    return {"relative_gap_range": [min(gaps), max(gaps)], "worst_relative_gap": worst,
            "strict_fraction": strict_fraction, "strict_closure": abs(worst) <= strict_fraction,
            "loose_fraction": loose_fraction, "loose_closure": abs(worst) <= loose_fraction}


def _status(terms):
    for name, text in terms.items():
        if not isinstance(text, str) or not text.startswith(STATUSES):
            raise ValueError(f"term {name} has no recognised status")
    return {name: text.split(":")[0].split(",")[0].split(" ")[0] for name, text in terms.items()}


def sandia(candidate, props, criteria):
    radius = number(candidate["pan_diameter_m"], "pan diameter") / 2.0
    area = math.pi * radius ** 2
    rings = candidate["rings"]["gauges_by_ring"]
    if abs(len(rings) * number(candidate["rings"]["equal_area_m2"], "ring area") - area) > 0.01:
        raise ValueError("the rings do not cover the pan: no area integral")
    unc = candidate["uncertainty"]
    strict = rss(unc["gauge_manufacturer_fraction"], unc["mass_rate_fraction_example"])
    loose = fraction(criteria["loose_closure_fraction"], "loose closure")
    reflect_low, reflect_high = (fraction(v, "reflectance")
                                 for v in candidate["reflectance"]["bounding_fraction_of_incident"])
    surface_k = celsius_to_kelvin(candidate["surface_temperature_c"])
    band = number(candidate["liquid_thermocouple_uncertainty_c"], "thermocouple uncertainty")
    tests = {}
    for name, test in candidate["tests"].items():
        means, average = ring_average(test["gauge_kw_m2"], rings)
        printed = [number(v, "printed ring mean") for v in test["ring_average_printed_kw_m2"]]
        if any(abs(a - b) > 0.06 for a, b in zip(means, printed)) or \
                abs(average - number(test["pan_average_printed_kw_m2"], "printed mean")) > 0.11:
            raise ValueError(f"{name}: the transcribed gauges do not reproduce the printed ring means")
        gauge_kw = average * area
        row = {"ring_mean_kw_m2": means, "pan_average_kw_m2": average, "gauge_power_kw": gauge_kw,
               "independent_kw_range": [independent_rate_kw(gauge_kw, reflect_high),
                                        independent_rate_kw(gauge_kw, reflect_low)],
               "independent_uses_mass": False, "mass_rate_g_s": test["burn_rate_g_s"]}
        if test["burn_rate_g_s"] is None:
            row.update({"in_balance": False, "reason": "no mass rate printed for this test"})
            tests[name] = row
            continue
        # The mass rate and the heat flux are averages of the same valid window of the same test.
        if test["valid_window_min"] is None or test["t_fuel_t0_c"] is None:
            raise ValueError(f"{name}: a mass rate without its window or feed temperature")
        mass = number(test["burn_rate_g_s"], "mass rate")
        if abs(mass / area - number(test["regression_g_m2_s"], "mass flux")) > 0.06:
            raise ValueError(f"{name}: mass rate and mass flux of the two tables disagree")
        feed_k = celsius_to_kelvin(test["t_fuel_t0_c"])
        central = demand_per_kg(props, surface_k, feed_k)
        per_kg = [demand_per_kg(props, surface_k - band, feed_k + band),
                  demand_per_kg(props, surface_k + band, feed_k - band)]
        demand = [demand_rate_kw(mass, value) for value in per_kg]
        row.update({
            "in_balance": True, "feed_temperature_k": feed_k, "surface_temperature_k": surface_k,
            "demand_kj_kg": central, "demand_kj_kg_range": per_kg,
            "demand_kw": demand_rate_kw(mass, central), "demand_kw_range": demand,
            "storage_growth_kw": None, "unknown_block_kw_range": [row["independent_kw_range"][0] - demand[1],
                                                                  row["independent_kw_range"][1] - demand[0]],
            "closure": closure(row["independent_kw_range"], demand, strict, loose)})
        tests[name] = row
    used = [name for name, row in tests.items() if row["in_balance"]]
    base = tests[used[0]]
    tracking = {name: {"heat_flux_change": tests[name]["pan_average_kw_m2"] / base["pan_average_kw_m2"] - 1.0,
                       "mass_rate_change": tests[name]["mass_rate_g_s"] / base["mass_rate_g_s"] - 1.0}
                for name in used[1:]}
    return {"area_m2": area, "tests": tests, "tests_in_balance": used, "relative_to": used[0],
            "run_to_run": tracking, "strict_fraction": strict,
            "strict_fraction_scope": unc["mass_rate_example_scope"],
            "combined_gauge_uncertainty": unc["gauge_combined_for_fuel_surface"],
            "total_uncertainty_quantified": False,
            "strict_closure_every_run": all(tests[n]["closure"]["strict_closure"] for n in used),
            "loose_closure_every_run": all(tests[n]["closure"]["loose_closure"] for n in used),
            "term_status": _status(candidate["term_status"]),
            "unknown_terms": sorted(k for k, v in _status(candidate["term_status"]).items() if v == "unknown")}


def nist(candidate, props, criteria, gauge_power_kw):
    """Second condition, kept apart: another laboratory, another scale, channels from different runs."""
    radius = number(candidate["pool_diameter_m"], "pool diameter") / 2.0
    area = math.pi * radius ** 2
    minor = candidate["minor_terms_over_q_fuel"]
    # The paper normalises its minor terms by its own, mass-derived, heat of vaporisation.
    published_q_fuel = fraction(candidate["feedback_fraction_printed"], "feedback fraction") * \
        number(candidate["ideal_heat_release_kw"], "ideal heat release")
    share = fraction(candidate["radiative_share_of_net"], "radiative share")
    reflect = [fraction(v, "reflection") * share for v in candidate["reflection_fraction_of_incident_radiation"]]
    losses = [fraction(minor["reradiation"], "reradiation") * published_q_fuel,
              fraction(minor["burner_loss"], "burner loss") * published_q_fuel]
    gain = [number(candidate["wall_conduction_kw_m2"], "wall conduction") * area]
    independent = [independent_rate_kw(gauge_power_kw, max(reflect), losses, gain),
                   independent_rate_kw(gauge_power_kw, min(reflect), losses, gain)]
    storage = fraction(minor["storage_growth"], "storage") * published_q_fuel
    surfaces = [number(v, "surface temperature") for v in candidate["surface_temperature_candidates_k"]]
    feeds = [number(v, "feed temperature") for v in candidate["feed_temperature_candidates_k"]]
    per_kg = [demand_per_kg(props, min(surfaces), max(feeds)), demand_per_kg(props, max(surfaces), min(feeds))]
    mass = number(candidate["mass_rate_g_s"], "mass rate")
    demand = [demand_rate_kw(mass, value, storage) for value in per_kg]
    unc = candidate["uncertainty"]
    strict = rss(unc["gauge_signal_fraction"], unc["load_cell_fraction"])
    return {"area_m2": area, "gauge_power_kw": gauge_power_kw, "published_q_fuel_kw": published_q_fuel,
            "independent_kw_range": independent, "independent_uses_mass": False,
            "independent_uses_ratio_to_mass_derived_quantity": True,
            "demand_kj_kg_range": per_kg, "storage_growth_kw": storage, "demand_kw_range": demand,
            "surface_temperature_accepted_k": candidate["surface_temperature_k"],
            "channels_from_one_run": False,
            "closure": closure(independent, demand, strict, fraction(criteria["loose_closure_fraction"], "loose")),
            "total_uncertainty_quantified": False,
            "term_status": _status(candidate["term_status"])}


def _pv_over_cp(props):
    """P dv per kelvin over Cp for the liquid: why enthalpy and internal energy are interchangeable here."""
    density = real.load_profile(real.INPUT)["review"]["liquid"]["density"]
    rho = number(density["rho_20_c_g_ml"], "density") * 1000.0
    expansion = -number(density["d_rho_dt_g_ml_c"], "density slope") / number(density["rho_20_c_g_ml"], "density")
    cp_j = profiles._cp(props["liquid"], 293.15) * 1000.0
    return real.REFERENCE_PA * (1.0 / rho) * expansion / cp_j


def property_checks(props, selected):
    """What the unreconciled property bases can move, and what stays out of support."""
    liquid_end = props["liquid"][-1]["temperature_k"]
    composite = (props["latent_kj_kg"] + enthalpy(props["gas"], liquid_end, "gas at the liquid end")
                 - enthalpy(props["liquid"], liquid_end, "liquid end"))
    handbook = 316.0  # heat of vaporisation at the boiling point listed in Table 3 of the Sandia report
    first = selected["tests"][selected["tests_in_balance"][0]]
    try:
        demand_per_kg(props, celsius_to_kelvin(200.0), first["feed_temperature_k"])
        gauge_plane = "inside support"
    except ValueError as error:
        gauge_plane = "refused: " + str(error)
    return {"composite_latent_at_liquid_support_end_kj_kg": composite, "handbook_latent_at_boiling_kj_kg": handbook,
            "latent_basis_gap_kj_kg": composite - handbook,
            "latent_basis_gap_over_demand": (composite - handbook) / first["demand_kj_kg"],
            "real_gas_departure_applied": False,
            "control_volume_at_the_gauge_plane_200_c": gauge_plane,
            "liquid_pv_work_per_k_over_cp": _pv_over_cp(props),
            "mass_basis_relevant_to_B": False}


def sensitivities(props, candidate, selected):
    """How much each unmeasured or loosely known quantity can move the balance of the first run."""
    name = selected["tests_in_balance"][0]
    run = selected["tests"][name]
    mass = run["mass_rate_g_s"]
    surface, feed = run["surface_temperature_k"], run["feed_temperature_k"]
    base = run["demand_kj_kg"]
    density = real.load_profile(real.INPUT)["review"]["liquid"]["density"]
    inventory_kg = selected["area_m2"] * number(candidate["liquid_depth_above_baffle_m"], "depth") * \
        number(density["rho_20_c_g_ml"], "density") * 1000.0
    cp = profiles._cp(props["liquid"], feed)
    gas_end = props["gas"][-1]["temperature_k"]
    superheat = grams_to_kilograms(mass) * (enthalpy(props["gas"], gas_end, "gas support end")
                                            - enthalpy(props["gas"], surface, "surface"))
    return {
        "run": name,
        "demand_change_per_k_of_feed_temperature": (demand_per_kg(props, surface, feed + 1.0) - base) / base,
        "demand_change_per_k_of_surface_temperature": (demand_per_kg(props, surface + 1.0, feed) - base) / base,
        "liquid_inventory_above_baffle_kg": inventory_kg,
        "storage_kw_per_k_per_minute": inventory_kg * cp / 60.0,
        "storage_kw_per_k_per_minute_over_gauge_power": inventory_kg * cp / 60.0 / run["gauge_power_kw"],
        "vapour_superheat_to_gas_support_end_kw": superheat,
        "vapour_superheat_to_gas_support_end_over_gauge_power": superheat / run["gauge_power_kw"],
        "gas_support_end_k": gas_end,
        "deficit_at_independent_lower_bound_kw": max(0.0, run["demand_kw"] - run["independent_kw_range"][0]),
        "deficit_at_independent_upper_bound_kw": max(0.0, run["demand_kw"] - run["independent_kw_range"][1]),
    }


def decisions(selected, second):
    point = selected["strict_closure_every_run"] and not selected["unknown_terms"]
    interval = selected["loose_closure_every_run"]
    return {
        "benchmark_eligibility": "GO_partial_stationary_open_pool_2m_heptane" if interval else "NO_GO",
        "net_B_identifiability": ("GO_point_value" if point else
                                  "GO_partial_bounded_stationary_rate_NO_GO_point_value" if interval else "NO_GO"),
        "balance_scope": "stationary_mean_only_NO_GO_transient",
        "thermal_prediction": "NO_GO",
        "emission_prediction": "NO_GO",
        "second_condition_consistent_at_loose_level": second["closure"]["loose_closure"],
        "second_condition_strict": second["closure"]["strict_closure"],
    }


def audit(record=None, root=ROOT):
    root = Path(root).resolve()
    if record is None:
        record = load_profile(root / INPUT.relative_to(ROOT))
    if (not isinstance(record, dict) or record.get("schema") != "g3_net_thermal_budget_review_v1"
            or set(record) != {"schema", "reviewed_at", "definition", "sources", "criteria", "candidates", "review"}):
        raise ValueError("unreviewed net thermal budget record")
    reviewed = json.dumps(record, sort_keys=True, allow_nan=False).encode("utf-8")
    if hashlib.sha256(reviewed).hexdigest() != REVIEW_SHA256:
        raise ValueError("unreviewed values, provenance, term status or approval")
    review = record["review"]
    if any(review[key] is not False for key in ["predictive_thermal_input_approval", "predictive_emission_approval",
                                                "engine_integration", "production_activation", "co_fed_approval"]):
        raise ValueError("an approval was promoted")
    source = record["sources"]["sandia_2011"]
    confined_artifact(root, {"path": source["path"], "sha256_raw": source["sha256_raw"]}, text=False)
    props = properties(root)
    thermal = pool.audit(None, root)
    gauge_power = thermal["gauge_profile_diagnostic"]["axisymmetric_piecewise_linear_gauge_power_kw"]
    selected = sandia(record["candidates"][review["selected"]], props, record["criteria"])
    second = nist(record["candidates"][review["reserved_second_condition"]], props, record["criteria"], gauge_power)
    return {
        "schema": "g3_net_thermal_budget_audit_v1",
        "definition": record["definition"]["meaning"],
        "selected": review["selected"], "second_condition": review["reserved_second_condition"],
        "rejected": {"nist_alcohols_030m": record["candidates"]["nist_alcohols_030m"]["rejected_for"]},
        "latent_kj_kg": props["latent_kj_kg"],
        "supports_k": {"liquid": [props["liquid"][0]["temperature_k"], props["liquid"][-1]["temperature_k"]],
                       "gas": [props["gas"][0]["temperature_k"], props["gas"][-1]["temperature_k"]]},
        "sandia_2m": selected, "nist_030m": second,
        "property_checks": property_checks(props, selected),
        "sensitivities": sensitivities(props, record["candidates"][review["selected"]], selected),
        "decisions": decisions(selected, second),
        "review_sha256": REVIEW_SHA256, "source_sha256_raw": source["sha256_raw"],
        "predictive_thermal_input_approval": False, "predictive_emission_approval": False,
        "engine_integration": False, "production_activation": False, "co_fed_approval": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare with the saved audit; write nothing")
    args = parser.parse_args()
    result = audit()
    if args.check:
        saved = json.loads(SAVED.read_text(encoding="utf-8"))
        print(json.dumps({"matches_saved": saved == json.loads(json.dumps(result))}))
        return 0 if saved == json.loads(json.dumps(result)) else 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
