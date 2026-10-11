"""Offline eligibility audit of the liquid n-heptane isobaric heat capacity.

Design evidence only: nothing here is engine input and no file under sim/ is
written or changed. Csat is never relabelled Cp: it is converted with the
thermodynamic identity

    Cp(T, P0) = Csat + T (dV/dT)_p (dPsat/dT) - T * integral_Psat^P0 (d2V/dT2)_p dP

using measured (p, rho, T) data. The identity is exact; its inputs are not.
The volumetric data are the NIST TRC capture of a 2008 article that was not
inspected, and the scale conversion acts on smoothed values, which is an
approximation. The gas checks contrast printed values; they do not verify the
original calorimetry. Controls in the tests are offline, not engine mutants.
"""
from __future__ import annotations

from decimal import Decimal
import hashlib
import json
import math
from pathlib import Path

from scripts.simulation import audit_g3_heptane_real_profile as real
from scripts.simulation.audit_g3_heptane_phase_basis import number
from scripts.simulation.audit_g3_measured_mass_candidate import confined_artifact
from scripts.simulation.validate_g3_mass_material_profile import load_profile


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs/validation/G3_D1_HEPTANE_LIQUID_INPUTS_2026-10-06.json"
SAVED = ROOT / "docs/validation/G3_D1_HEPTANE_LIQUID_AUDIT_2026-10-06.json"
PRIOR = {"path": "docs/validation/G3_D1_HEPTANE_REAL_PROFILE_INPUTS_2026-10-05.json",
         "sha256_lf": "7e703cb4530fb4ce8299fc883704e998d0480406027cb18f7bcab2056f3a6abd"}
SOURCES = {
    "volumetric": {
        "path": ("docs/literature/data/NIST_THERMOML_HEPTANE_2008/"
                 "ThermoML_10.1016_j.jct.2008.02.020.json"),
        "url": "https://trc.nist.gov/ThermoML/10.1016/j.jct.2008.02.020.json",
        "sha256_lf": "07643839f2f4c98f344faed4d2eed5c6bf671098a31d524d69ea8720c1dca73b"},
    "gas_correlation": {
        "path": ("docs/literature/Reviews_and_Models/"
                 "USBM_Bulletin_666_Alkane_Ideal_Gas_Properties_1974.pdf"),
        "url": ("https://digital.library.unt.edu/ark:/67531/metadc12811/m2/1/high_res_d/"
                "Bulletin0666.pdf"),
        "sha256_raw": "e2eb9547815339f7cbeb29032b8178fb8586a4cc40b085d229932411b417e5b2"},
}
CONTRAST_SHA = "f0593e09bf9281ecb0a2bbfa5aadc5643662959cdd323d93e294e263c5b1d72e"
REVIEW_SHA = "8d5bbc873b5282005d812687b65aa9c942d645fb88c41f0c0ceea9b8969b9fda"
SOURCES_SHA = hashlib.sha256(json.dumps(SOURCES, sort_keys=True).encode("utf-8")).hexdigest()

P0 = Decimal(100000)
ATM = Decimal(101325)
NATIVE_LOW = Decimal(280)
NATIVE_ROWS = [280, 285, 290, 295, 298.16, 300, 310, 320, 330, 340, 350, 360, 370]
# Predeclared bounds. A 1 % error in the first derivative moves Cp by at most
# 0.003 J/(mol*K) and a 25 % error in the second by at most 0.006; together
# they stay under the declared conversion residue. None is an experimental
# uncertainty or a sim tolerance.
FIRST_DERIVATIVE_REL_TOL = Decimal("0.01")
SECOND_DERIVATIVE_REL_TOL = Decimal("0.25")
CONVERSION_ABS_TOL = Decimal("0.01")
# Two whole-joule H rows, printed Csat over 71.84 K, 1 % of the V dP term and
# the quadrature.
CLOSURE_ABS_TOL = Decimal("1.6")
# h^2*|f''|/8 for 10 K knots with the largest printed second difference, 0.16.
CP_INTERPOLATION_ABS_TOL = Decimal("0.025")
# Uncertainty stated by the published ITS-90 evaluation up to 370 K.
CONTRAST_PERCENT_TOL = Decimal("0.1")

REAL_FIXED = {"schema": "g3_real_liquid_isobaric_cp_v1", "component_id": "n-heptane",
              "caloric_model": "declared_liquid", "pressure_path": "constant_pressure",
              "temperature_scale": "ITS-90_kelvin", "quantity": "isobaric_specific_heat",
              "quantity_unit": "kJ/(kg*K)", "interpolation": "piecewise_linear",
              "calibration_status": "primary_source_property_not_fire_validation"}
DECLARED_ERRORS = {
    "source_probable_error_percent_280_to_360_k": 0.1,
    "source_error_kind": "probable_error_as_stated_not_a_standard_uncertainty",
    "source_error_statement_above_360_k_percent": None,
    "conversion_abs_j_mol_k": float(CONVERSION_ABS_TOL),
    "scale_conversion_kind": "approximate_on_smoothed_values",
    "scale_difference_to_published_evaluation_percent": 0.07,
    "cp_interpolation_abs_j_mol_k": float(CP_INTERPOLATION_ABS_TOL),
    "label_abs_k": float(real.LABEL_ABS_TOL_K),
    "scale_factor_abs": float(real.SCALE_FACTOR_ABS_TOL),
    "volumetric_sample_purity_mol_percent": 99.3,
    "volumetric_article_inspected": False,
    "fire_validation": False,
}
_ISOTHERMS = {}


def _f(value, places=6):
    return float(round(Decimal(value), places))


def isotherms_from(payload, review):
    """Density isotherms of the reviewed data set: {T: [(p_Pa, rho_kg_m3), ...]}."""
    spec = review["volumetric"]
    wanted = spec["data_set_number"]
    sets = [s for s in payload.get("PureOrMixtureData", [])
            if s.get("nPureOrMixtureDataNumber") == wanted]
    if len(sets) != 1 or len(sets[0]["Component"]) != 1:
        raise ValueError("volumetric data set is not the reviewed one")
    data = sets[0]
    organism = data["Component"][0]["RegNum"]["nOrgNum"]
    compound = [c for c in payload["Compound"] if c["RegNum"]["nOrgNum"] == organism][0]
    prop = data["Property"][0]["Property-MethodID"]["PropertyGroup"]["VolumetricProp"]
    variables = [[name for name in v["VariableID"]["VariableType"].values()
                  if isinstance(name, str)] for v in data["Variable"]]
    purity = compound["Sample"][0]["purity"][0].get("nPurityMol")
    if (spec["compound_name"] not in compound["sCommonName"]
            or prop["ePropName"] != spec["property_name"]
            or data["PhaseID"][0]["ePhase"] != "Liquid"
            or variables != [["Temperature, K"], ["Pressure, kPa"]]
            or purity != spec["sample_purity_mol_percent"]
            or len(data["NumValues"]) != spec["points"]):
        raise ValueError("volumetric data set is not the reviewed one")
    result = {}
    for entry in data["NumValues"]:
        values = {v["nVarNumber"]: v["nVarValue"] for v in entry["VariableValue"]}
        density = entry["PropertyValue"][0]["nPropValue"]
        if not all(real._finite(v) and v > 0 for v in (values[1], values[2], density)):
            raise ValueError("volumetric values must be finite and positive")
        result.setdefault(number(values[1], "T"), []).append(
            (number(values[2], "p") * 1000, number(density, "rho")))
    if sorted(float(t) for t in result) != spec["isotherms_k"]:
        raise ValueError("volumetric data set is not the reviewed one")
    return {t: sorted(points) for t, points in result.items()}


def read_isotherms(root, review):
    root = Path(root).resolve()
    source = SOURCES["volumetric"]
    stat = (root / source["path"]).stat()
    key = (str(root), stat.st_size, stat.st_mtime_ns)
    if key not in _ISOTHERMS:
        _, data = confined_artifact(root, source, text=True)
        _ISOTHERMS[key] = isotherms_from(json.loads(data.decode("utf-8")), review)
    return _ISOTHERMS[key]


def _reviewed(record, root):
    root = Path(root).resolve()
    if record is None:
        record = load_profile(root / INPUT.relative_to(ROOT))
    keys = {"schema", "prior_review", "sources", "contrast_not_archived", "review"}
    if (not isinstance(record, dict) or set(record) != keys
            or record["schema"] != "g3_heptane_liquid_source_review_v1"):
        raise ValueError("unreviewed liquid record/schema")
    contrast = record["contrast_not_archived"]
    if (record["sources"] != SOURCES or not isinstance(contrast, dict)
            or contrast.get("sha256_raw") != CONTRAST_SHA or contrast.get("archived") is not False):
        raise ValueError("unreviewed source identity")
    if record["prior_review"] != PRIOR:
        raise ValueError("unreviewed prior review identity")
    if real._sha_lf(root / PRIOR["path"]) != PRIOR["sha256_lf"]:
        raise ValueError("prior gas review record changed")
    real._confined_once(root, SOURCES["gas_correlation"])
    encoded = json.dumps(record, sort_keys=True, allow_nan=False).encode("utf-8")
    if hashlib.sha256(encoded).hexdigest() != REVIEW_SHA:
        raise ValueError("unreviewed semantics, units or approvals")
    prior, gas_review = real._reviewed(None, root)
    return prior, gas_review, record["review"]


def context(record=None, root=ROOT):
    """Reviewed inputs: 2026-10-04 and 2026-10-05 reviews, this review and the isotherms."""
    prior, gas_review, review = _reviewed(record, root)
    return {"prior": prior, "gas_review": gas_review, "review": review,
            "isotherms": read_isotherms(root, review),
            "molar_mass": number(gas_review["molar_mass"]["value_g_mol"], "molar mass")}


def _newton(points, x):
    """Value, first and second derivative of the polynomial through the points."""
    xs = [p[0] for p in points]
    table = [p[1] for p in points]
    coefficients = [table[0]]
    for order in range(1, len(points)):
        table = [(table[i + 1] - table[i]) / (xs[i + order] - xs[i])
                 for i in range(len(table) - 1)]
        coefficients.append(table[0])
    value, first, second = coefficients[-1], Decimal(0), Decimal(0)
    for k in range(len(points) - 2, -1, -1):
        step = x - xs[k]
        second = second * step + 2 * first
        first = first * step + value
        value = value * step + coefficients[k]
    return value, first, second


def density(ctx, isotherm_k, pressure_pa):
    """rho(T_i, p): quadratic in p through the three lowest-pressure points."""
    key = number(isotherm_k, "isotherm")
    if key not in ctx["isotherms"]:
        raise ValueError("not a measured isotherm")
    points = ctx["isotherms"][key][:3]
    pressure = number(pressure_pa, "pressure") if not isinstance(pressure_pa, Decimal) else pressure_pa
    if not 0 < pressure <= points[-1][0]:
        raise ValueError("pressure outside the low-pressure support of the isotherm")
    return _newton(points, pressure)[0]


def volume(ctx, t90, pressure_pa, nodes=4):
    """Molar volume and its first two temperature derivatives on an isobar, m3/mol."""
    t = number(t90, "temperature") if not isinstance(t90, Decimal) else t90
    grid = sorted(ctx["isotherms"])
    if not grid[0] <= t <= grid[-1]:
        raise ValueError("temperature outside the volumetric support")
    below = max(i for i, node in enumerate(grid) if node <= t)
    nearest = min(range(len(grid)), key=lambda i: abs(grid[i] - t))
    start = below - (nodes - 2) // 2 if nodes % 2 == 0 else nearest - nodes // 2
    start = max(0, min(start, len(grid) - nodes))
    kilogram_per_mole = ctx["molar_mass"] / 1000
    points = [(node, kilogram_per_mole / density(ctx, float(node), pressure_pa))
              for node in grid[start:start + nodes]]
    return _newton(points, t)


def saturation(ctx, t_native):
    """Vapour pressure in Pa and its slope, equation 19 on the source's own labels."""
    eq = ctx["gas_review"]["liquid"]["vapour_pressure_equation"]
    b, c = number(eq["b"], "b"), number(eq["c"], "c")
    t = number(t_native, "temperature") if not isinstance(t_native, Decimal) else t_native
    celsius = t - number(ctx["gas_review"]["temperature"]["native_kelvin_offset"], "offset")
    pressure = real._vapour_pressure_atm(ctx["gas_review"], celsius) * ATM
    return pressure, pressure * Decimal(10).ln() * b / (celsius + c) ** 2


def boiling_native(ctx):
    """Temperature, on the source's labels, at which equation 19 gives P0."""
    eq = ctx["gas_review"]["liquid"]["vapour_pressure_equation"]
    a, b, c = (number(eq[k], k) for k in ["a", "b", "c"])
    celsius = b / (a - (P0 / ATM).log10()) - c
    return celsius + number(ctx["gas_review"]["temperature"]["native_kelvin_offset"], "offset")


def _csat_rows(ctx):
    rows = (ctx["review"]["liquid_rows_below_290"]["rows"]
            + ctx["gas_review"]["liquid"]["table_rows"])
    return {number(row[0], "T"): (number(row[1], "Csat"), number(row[2], "H")) for row in rows}


def _csat(ctx, t):
    """Printed Csat; only the boiling knot is interpolated, between 370 and 380 K."""
    rows = _csat_rows(ctx)
    if t in rows:
        return rows[t][0]
    low, high = Decimal(370), Decimal(380)
    if not low < t < high:
        raise ValueError("no printed Csat row at this temperature")
    return rows[low][0] + (rows[high][0] - rows[low][0]) * (t - low) / (high - low)


def conversion(ctx, t_native, nodes=4):
    """Csat -> Cp at the saturation pressure -> Cp at P0, J/(mol*K) per source kelvin."""
    t = number(t_native, "temperature") if not isinstance(t_native, Decimal) else t_native
    top = boiling_native(ctx)
    if not NATIVE_LOW <= t <= top:
        raise ValueError("outside the reviewed liquid support; no extrapolation")
    t90 = real.source_to_its90(ctx["gas_review"], float(t))
    pressure, slope = saturation(ctx, t)
    first = t90 * volume(ctx, t90, pressure, nodes)[1] * slope
    second = -t90 * volume(ctx, t90, (pressure + P0) / 2, nodes)[2] * (P0 - pressure)
    csat = _csat(ctx, t)
    return {"native_k": t, "its90_k": t90, "saturation_pressure_pa": pressure, "csat_j_mol_k": csat,
            "first_term_j_mol_k": first, "second_term_j_mol_k": second,
            "cp_minus_csat_j_mol_k": first + second,
            "cp_at_saturation_j_mol_k": csat + first, "cp_j_mol_k": csat + first + second}


def _natives(ctx):
    return [number(v, "T") for v in NATIVE_ROWS] + [boiling_native(ctx)]


def _knots(ctx):
    knots = []
    for native in _natives(ctx):
        result = conversion(ctx, native)
        factor = real.its90_scale_factor(ctx["gas_review"], float(native))
        knots.append({
            **result, "scale_factor": factor,
            "native_k": float(native.quantize(Decimal("1e-6"))),
            "its90_k": float(result["its90_k"].quantize(Decimal("1e-6"))),
            "cp_native_j_mol_k": result["cp_j_mol_k"],
            "cp_kj_kg_k": float((result["cp_j_mol_k"] * factor / ctx["molar_mass"]).quantize(
                Decimal("1e-12"))),
        })
    return knots


def _labels(ctx, values):
    return [float(real.source_to_its90(ctx["gas_review"], float(v)).quantize(Decimal("1e-6")))
            for v in values]


def _evidence_tiers(ctx):
    top = float(boiling_native(ctx).quantize(Decimal("1e-6")))
    return [
        {"native_range_k": [280, 360], "its90_range_k": _labels(ctx, [280, 360]),
         "evidence_kind": "tabulated_Csat_of_the_source_converted_to_Cp_here"},
        {"native_range_k": [360, 370], "its90_range_k": _labels(ctx, [360, 370]),
         "evidence_kind": "same_table_with_source_error_rising_above_360_K"},
        {"native_range_k": [370, top], "its90_range_k": _labels(ctx, [370, top]),
         "evidence_kind": "interpolation_towards_a_row_beyond_the_adjusted_table"},
    ]


def _provenance():
    return ("primary:sha256:" + real.SOURCES["calorimetry"]["sha256_raw"] + ";volumetric:sha256:"
            + SOURCES["volumetric"]["sha256_lf"] + ";sources:sha256:" + SOURCES_SHA
            + ";review:sha256:" + REVIEW_SHA + ";adapter:g3_heptane_liquid_cp_adapter_v1")


def _preview(ctx):
    knots = _knots(ctx)
    samples = [{"temperature_k": k["its90_k"], "cp_kj_kg_k": k["cp_kj_kg_k"]} for k in knots]
    picks = [0, NATIVE_ROWS.index(370), len(knots) - 1]
    return {
        **REAL_FIXED, "phase": "liquid",
        "reference_temperature_k": real.REFERENCE_K, "reference_pressure_pa": real.REFERENCE_PA,
        "samples": samples, "provenance": _provenance(),
        "molar_mass_g_mol": ctx["gas_review"]["molar_mass"]["value_g_mol"],
        "native_support_k": [knots[0]["native_k"], knots[-1]["native_k"]],
        "evidence_tiers": _evidence_tiers(ctx),
        "declared_errors": dict(DECLARED_ERRORS),
        "witnesses": [{"temperature_k": samples[i]["temperature_k"],
                       "specific_sensible_enthalpy_kj_kg":
                           real.canonical_enthalpy(samples, samples[i]["temperature_k"])}
                      for i in picks],
    }


def contract_preview(record=None, root=ROOT):
    """Candidate of the proposed real liquid schema. A design output, not an engine profile."""
    return _preview(context(record, root))


def _interpolation_error(knots, used):
    """Largest |converted Cp - straight line between kept knots| at the dropped knots."""
    line = [(k["native_k"], float(k["cp_native_j_mol_k"])) for k in used]
    worst = 0.0
    for knot in knots:
        if line[0][0] <= knot["native_k"] <= line[-1][0]:
            worst = max(worst, abs(real._interp(line, knot["native_k"])
                                   - float(knot["cp_native_j_mol_k"])))
    return worst


def check_candidate(candidate, record=None, root=ROOT):
    """Contract controls of the proposed real liquid schema against the pinned reviews."""
    ctx = context(record, root)
    expected = _preview(ctx)
    if not isinstance(candidate, dict) or set(candidate) != set(expected):
        raise ValueError("unexpected or missing candidate field")
    if candidate["phase"] != "liquid":
        raise ValueError("this contract covers the liquid phase only")
    if candidate["caloric_model"] != "declared_liquid":
        raise ValueError("phase/caloric_model mismatch")
    for key, value in REAL_FIXED.items():
        if candidate[key] != value:
            raise ValueError("unsupported " + key)
    if (candidate["reference_temperature_k"] != real.REFERENCE_K
            or candidate["reference_pressure_pa"] != real.REFERENCE_PA):
        raise ValueError("incompatible reference state")
    if candidate["molar_mass_g_mol"] != expected["molar_mass_g_mol"]:
        raise ValueError("molar mass differs from the basis stated by the source")
    if candidate["provenance"] != expected["provenance"]:
        raise ValueError("provenance does not match the reviewed sources")
    samples = real.checked_samples(candidate["samples"])
    knots = _knots(ctx)
    used = real.matched_knots(samples, knots)
    for sample, knot in zip(samples, used):
        if not math.isclose(sample["cp_kj_kg_k"], knot["cp_kj_kg_k"], rel_tol=1e-9, abs_tol=0.0):
            raise ValueError("Cp does not reproduce the converted source value on the declared "
                             "unit, molar-mass, pressure and scale basis")
    if _interpolation_error(knots, used) > float(CP_INTERPOLATION_ABS_TOL):
        raise ValueError("discretization outside the declared interpolation error")
    for key in ["native_support_k", "evidence_tiers", "declared_errors"]:
        if candidate[key] != expected[key]:
            raise ValueError("declared limits altered: " + key)
    real.check_witnesses(samples, candidate["witnesses"],
                         [w["temperature_k"] for w in expected["witnesses"]])
    return {"valid": True, "knots": len(samples), "engine_profile": False}


def _simpson(values, first_width):
    """Trapezoid on the 298.16-300 K sliver, Simpson 1/3 on 300-340 and 3/8 on 340-370."""
    v = values
    return ((v[0] + v[1]) * first_width / 2
            + Decimal(10) / 3 * (v[1] + 4 * v[2] + 2 * v[3] + 4 * v[4] + v[5])
            + Decimal(30) / 8 * (v[5] + 3 * v[6] + 3 * v[7] + v[8]))


def _volumetric_section(ctx):
    review, gas_review = ctx["review"], ctx["gas_review"]
    brooks = gas_review["liquid"]["density"]
    relation = gas_review["liquid"]["saturation_relation"]
    offset = number(gas_review["temperature"]["native_kelvin_offset"], "offset")
    middle = Decimal("22.5") + offset
    t90 = real.source_to_its90(gas_review, float(middle))
    v, v1, _ = volume(ctx, t90, ATM)
    kilogram_per_mole = ctx["molar_mass"] / 1000
    slope = -kilogram_per_mole * v1 / (v * v)
    brooks_slope = number(brooks["d_rho_dt_g_ml_c"], "slope") * 1000
    t20 = real.source_to_its90(gas_review, float(Decimal(20) + offset))
    rho20 = kilogram_per_mole / volume(ctx, t20, ATM)[0]
    brooks20 = number(brooks["rho_20_c_g_ml"], "rho") * 1000
    pressure, p_slope = saturation(ctx, middle)
    grid = sorted(ctx["isotherms"])
    spread = {}
    for node in grid:
        lowest = ctx["isotherms"][node][0][0]
        if lowest > 2 * P0:
            four = _newton(ctx["isotherms"][node][:4], P0)[0]
            spread["%.2f" % node] = _f(abs(four - density(ctx, float(node), P0)), 4)
    return {
        "data_set": review["volumetric"]["compound_name"] + " " + review["volumetric"]["property_name"],
        "evidence_kind": review["volumetric"]["evidence_kind"],
        "uncertainty_kind": review["volumetric"]["uncertainty_kind"],
        "sample_purity_mol_percent": review["volumetric"]["sample_purity_mol_percent"],
        "isobar_100_kpa_kg_m3": [[float(node), _f(density(ctx, float(node), P0), 3)] for node in grid],
        "extrapolated_isotherms_k": sorted(float(key) for key in spread),
        "extrapolation_quadratic_minus_cubic_kg_m3": spread,
        "density_slope_22_5_c_kg_m3_k": _f(slope, 5),
        "density_slope_ratio_to_brooks": _f(slope / brooks_slope, 4),
        "density_20_c_minus_brooks_percent": _f(100 * (rho20 - brooks20) / brooks20, 3),
        "v_dp_dt_22_5_c_j_mol_k": _f(volume(ctx, t90, pressure)[0] * p_slope, 5),
        "osborne_ginnings_dh_dt_minus_csat_j_mol_k":
            _f((number(relation["observed_dh_dt_20_25_c_int_j_g_c"], "dH/dT")
                - number(relation["observed_csat_20_25_c_int_j_g_c"], "Csat")) * ctx["molar_mass"], 4),
    }


def _conversion_section(ctx):
    rows, first_spread, second_spread = [], Decimal(0), Decimal(0)
    for native in _natives(ctx):
        base = conversion(ctx, native)
        for nodes in (3, 5):
            other = conversion(ctx, native, nodes)
            first_spread = max(first_spread, abs(
                other["first_term_j_mol_k"] / base["first_term_j_mol_k"] - 1))
            if base["second_term_j_mol_k"] != 0:
                second_spread = max(second_spread, abs(
                    other["second_term_j_mol_k"] / base["second_term_j_mol_k"] - 1))
        rows.append({"native_k": float(native.quantize(Decimal("1e-4"))),
                     "its90_k": _f(base["its90_k"], 4),
                     "saturation_pressure_pa": _f(base["saturation_pressure_pa"], 1),
                     "csat_j_mol_k": _f(base["csat_j_mol_k"], 4),
                     "first_term_j_mol_k": _f(base["first_term_j_mol_k"], 5),
                     "second_term_j_mol_k": _f(base["second_term_j_mol_k"], 5),
                     "cp_minus_csat_j_mol_k": _f(base["cp_minus_csat_j_mol_k"], 5),
                     "cp_j_mol_k": _f(base["cp_j_mol_k"], 4)})
    if first_spread > FIRST_DERIVATIVE_REL_TOL or second_spread > SECOND_DERIVATIVE_REL_TOL:
        raise ValueError("volume derivatives depend on the stencil beyond the declared bounds")
    worst = max(rows, key=lambda r: abs(r["cp_minus_csat_j_mol_k"]))
    return {
        "relation": ctx["review"]["relation"]["form"],
        "exactness": ctx["review"]["relation"]["exactness"],
        "derivative_method": "cubic through four isotherms; quadratic and quartic stencils as spread",
        "rows": rows,
        "max_abs_cp_minus_csat_j_mol_k": abs(worst["cp_minus_csat_j_mol_k"]),
        "max_abs_percent_of_csat": _f(100 * max(abs(r["cp_minus_csat_j_mol_k"]) / r["csat_j_mol_k"]
                                                 for r in rows), 4),
        "first_derivative_method_spread_max": _f(first_spread, 5),
        "second_derivative_method_spread_max": _f(second_spread, 4),
        "declared_conversion_abs_j_mol_k": float(CONVERSION_ABS_TOL),
    }


def _pressure_step(ctx, native):
    """H(T, P0) - Hsat(T) = (V - T dV/dT)(P0 - Psat), J/mol."""
    t90 = real.source_to_its90(ctx["gas_review"], float(native))
    pressure, _ = saturation(ctx, native)
    v, v1, _ = volume(ctx, t90, (pressure + P0) / 2)
    return (v - t90 * v1) * (P0 - pressure)


def _closure_section(ctx, preview):
    rows = _csat_rows(ctx)
    low = number(ctx["prior"]["native_reference_temperature_k"], "reference")
    span = [low] + [number(v, "T") for v in NATIVE_ROWS if v >= 300]
    csat = [rows[t][0] for t in span]
    cp = [conversion(ctx, t)["cp_j_mol_k"] for t in span]
    printed = rows[span[-1]][1] - rows[span[0]][1]
    panels = 72
    width = (span[-1] - span[0]) / panels
    total = Decimal(0)
    for i in range(panels + 1):
        t = span[0] + width * i
        pressure, slope = saturation(ctx, t)
        value = volume(ctx, real.source_to_its90(ctx["gas_review"], float(t)), pressure)[0] * slope
        total += value * (1 if i in (0, panels) else 4 if i % 2 else 2)
    v_dp = total * width / 3
    csat_integral = _simpson(csat, span[1] - span[0])
    cp_integral = _simpson(cp, span[1] - span[0])
    step_low, step_high = _pressure_step(ctx, span[0]), _pressure_step(ctx, span[-1])
    isobaric = printed + step_high - step_low
    saturation_residual = printed - csat_integral - v_dp
    isobaric_residual = cp_integral - isobaric
    samples = preview["samples"]
    canonical = Decimal(str(
        real.canonical_enthalpy(samples, samples[NATIVE_ROWS.index(370)]["temperature_k"])
        - real.canonical_enthalpy(samples, samples[NATIVE_ROWS.index(298.16)]["temperature_k"])
    )) * ctx["molar_mass"]
    if (abs(saturation_residual) > CLOSURE_ABS_TOL or abs(isobaric_residual) > CLOSURE_ABS_TOL
            or abs(canonical - isobaric) > Decimal("4.2")):
        raise ValueError("converted Cp does not close with the printed enthalpy column")
    eq12 = real._vdp(ctx["gas_review"], span[-1])[0] - real._vdp(ctx["gas_review"], span[0])[0]
    return {
        "printed_delta_h_sat_j_mol": int(printed),
        "csat_simpson_298_16_to_370_j_mol": _f(csat_integral, 4),
        "v_dp_measured_volume_j_mol": _f(v_dp, 4),
        "v_dp_measured_minus_equation_12_j_mol": _f(v_dp - eq12, 4),
        "saturation_residual_j_mol": _f(saturation_residual, 4),
        "pressure_step_298_16_j_mol": _f(step_low, 4),
        "pressure_step_370_j_mol": _f(step_high, 4),
        "isobaric_delta_h_from_printed_rows_j_mol": _f(isobaric, 4),
        "cp_simpson_298_16_to_370_j_mol": _f(cp_integral, 4),
        "isobaric_residual_j_mol": _f(isobaric_residual, 4),
        "csat_as_cp_error_j_mol": _f(csat_integral - isobaric, 4),
        "canonical_delta_h_298_16_to_370_j_mol": _f(canonical, 4),
        "canonical_minus_simpson_j_mol": _f(canonical - cp_integral, 4),
        "closure_abs_tol_j_mol": float(CLOSURE_ABS_TOL),
    }


def _converted_at(points, t90):
    return Decimal(str(real._interp(points, float(t90))))


def _scale_section(ctx, knots):
    rows = _csat_rows(ctx)
    old = sorted((float(t), float(v[0])) for t, v in rows.items())
    new_csat = [(k["its90_k"], float(k["csat_j_mol_k"] * k["scale_factor"])) for k in knots]
    labels_only = [(k["its90_k"], float(k["csat_j_mol_k"])) for k in knots]
    table, worst = [], Decimal(0)
    for t90, nbs, d_printed, _ in ctx["review"]["contrast_jpcrd_1994"]["table_2_rows"]:
        same = Decimal(str(real._interp(old, t90)))
        mine = 100 * (_converted_at(new_csat, t90) - same) / same
        only = 100 * (_converted_at(labels_only, t90) - same) / same
        worst = max(worst, abs(mine - number(d_printed, "d")))
        table.append({"its90_k": t90, "this_gate_percent": _f(mine, 4),
                      "labels_only_percent": _f(only, 4), "jpcrd_percent": d_printed,
                      "jpcrd_nbs_csat_j_mol_k": nbs})
    return {
        "kind": DECLARED_ERRORS["scale_conversion_kind"],
        "exact_conversion_needs": "raw_heat_and_initial_and_final_temperatures",
        "same_numerical_temperature_rows": table,
        "max_abs_difference_to_jpcrd_percent": _f(worst, 4),
        "declared_difference_percent": DECLARED_ERRORS["scale_difference_to_published_evaluation_percent"],
        "difference_includes_recorrelation_of_the_raw_data": True,
    }


def _contrast_section(ctx, knots):
    contrast = ctx["review"]["contrast_jpcrd_1994"]
    csat = [(k["its90_k"], float(k["csat_j_mol_k"] * k["scale_factor"])) for k in knots]
    cp_sat = [(k["its90_k"], float(k["cp_at_saturation_j_mol_k"] * k["scale_factor"])) for k in knots]
    first = [(k["its90_k"], float(k["first_term_j_mol_k"])) for k in knots]
    rows = []
    for t90, ref_csat, ref_cp in contrast["table_4_rows"]:
        a = 100 * (_converted_at(csat, t90) / number(ref_csat, "Csat") - 1)
        b = 100 * (_converted_at(cp_sat, t90) / number(ref_cp, "Cp") - 1)
        if abs(a) > CONTRAST_PERCENT_TOL or abs(b) > CONTRAST_PERCENT_TOL:
            raise ValueError("converted values leave the uncertainty of the published evaluation")
        column_difference = number(ref_cp, "Cp") - number(ref_csat, "Csat")
        rows.append({"its90_k": t90, "csat_percent": _f(a, 4), "cp_at_saturation_percent": _f(b, 4),
                     "first_term_minus_jpcrd_difference_j_mol_k":
                         _f(_converted_at(first, t90) - column_difference, 4)})
    labs = max(abs(100 * (number(row[3], "BM") / number(row[1], "NBS") - 1))
               for row in contrast["table_2_rows"])
    return {
        "citation": "Zabransky and Ruzicka, J. Phys. Chem. Ref. Data 23, 55 (1994)",
        "archived": False, "sha256_raw": CONTRAST_SHA,
        "evidence_kind": contrast["evidence_kind"],
        "cp_definition": contrast["cp_definition"],
        "rows": rows,
        "bureau_of_mines_minus_nbs_max_percent": _f(labs, 3),
        "stated_uncertainty_percent_up_to_370_k": contrast["stated_uncertainty_percent"]["up_to_370_k"],
    }


def _gas_section(ctx):
    review, prior, gas_review = ctx["review"], ctx["prior"], ctx["gas_review"]
    scott = review["contrast_bulletin_666"]
    calorie = number(scott["calorie_j"], "calorie")
    low = prior["native_reference_temperature_k"]
    rows = []
    for temperature, cal in scott["cp_rows"]:
        correlated = number(cal, "Cp") * calorie
        source = real.gas_cp_native(prior, gas_review, max(temperature, low))
        rows.append({"temperature_k": temperature, "correlated_cp_j_mol_k": _f(correlated, 5),
                     "source_cp_j_mol_k": _f(source, 5),
                     "correlated_minus_source_j_mol_k": _f(correlated - source, 4),
                     "percent": _f(100 * (correlated - source) / source, 3)})
    (t0, h0), (t1, h1) = scott["enthalpy_rows"]
    a, b, c = (number(v, "coefficient") for v in prior["gas_high_equation_coefficients"])
    low_t = number(low, "T")
    extrapolated = a + b * low_t + c * low_t * low_t
    first = number(scott["cp_rows"][0][1], "Cp") * calorie
    mines = review["contrast_jpcrd_1994"]["bureau_of_mines_liquid_calorimetry"]
    bm = number(mines["molar_mass_g_mol"], "M")
    top = gas_review["gas"]["table_rows_above_370"][-1][0]
    return {
        "decision_changed": False,
        "authorized_native_range_k": [low, top],
        "original_calorimetry_obtained": review["gas_original_calorimetry"]["obtained"],
        "scale_and_molar_mass_verified_at_origin":
            review["gas_original_calorimetry"]["scale_and_molar_mass_verified_at_origin"],
        "same_laboratory_molar_mass_relative_difference":
            _f((ctx["molar_mass"] - bm) / ctx["molar_mass"], 7),
        "same_laboratory_evidence_applies_to": mines["applies_to"],
        "contrast_kind": scott["evidence_kind"],
        "contrast_independence": scott["independence"],
        "contrast_rows": rows,
        "contrast_label_note": "298.15 K of the correlation is compared with the source row at 298.16 K",
        "equation_22_extrapolated_minus_correlated_percent": _f(100 * (extrapolated - first) / first, 3),
        "delta_h_300_to_400_correlated_j_mol": _f((number(h1, "H") - number(h0, "H")) * calorie * 1000, 4),
        "delta_h_300_to_400_source_j_mol": _f(real.gas_delta_native(prior, gas_review, t0, t1), 4),
        "correlation_range_k": scott["range_k"],
        "gas_range_extension_decided_here": False,
    }


def audit(record=None, root=ROOT):
    ctx = context(record, root)
    preview = _preview(ctx)
    check_candidate(preview, record, root)
    knots = _knots(ctx)
    gas_preview = real.contract_preview(None, root)
    liquid_support = [preview["samples"][0]["temperature_k"], preview["samples"][-1]["temperature_k"]]
    gas_support = [gas_preview["samples"][0]["temperature_k"], gas_preview["samples"][-1]["temperature_k"]]
    worst = max(abs(value) for value in _second_differences(ctx))
    approvals = ctx["review"]["approvals"]
    return {
        "schema": "g3_heptane_liquid_eligibility_audit_v1",
        "decision": {
            "liquid": "GO_partial_isobaric_cp_at_100_kPa_native_280_to_371.139_K_by_justified_conversion",
            "gas": "GO_partial_unchanged_conditional_on_declared_assumptions",
            "joint_adapter": "GO_partial_design_only_same_real_schema_family",
            "current_synthetic_contract": "NO_GO_by_design_requires_versioned_real_schema",
            "net_heat_budget_B": "NO_GO_separate_gate",
        },
        "review_sha256": REVIEW_SHA,
        "sources_sha256": SOURCES_SHA,
        "required_property": ctx["review"]["required_property"],
        "volumetric": _volumetric_section(ctx),
        "conversion": _conversion_section(ctx),
        "closure": _closure_section(ctx, preview),
        "scale": _scale_section(ctx, knots),
        "contrast_jpcrd_1994": _contrast_section(ctx, knots),
        "discretization": {"largest_printed_second_difference_j_mol_k": _f(worst, 4),
                           "cp_interpolation_bound_j_mol_k": _f(worst / 8, 4),
                           "declared_j_mol_k": float(CP_INTERPOLATION_ABS_TOL)},
        "joint": {
            "liquid_its90_support_k": liquid_support,
            "gas_its90_support_k": gas_support,
            "emission_window_its90_k": [max(liquid_support[0], gas_support[0]),
                                        min(liquid_support[1], gas_support[1])],
            "vaporization_basis": "NIST_TN_2126_upd1_at_298.15_K_not_recomputed_here",
            "shared_fields": sorted(set(preview) & set(gas_preview)),
            "ledger_scope_labels_still_synthetic": True,
        },
        "gas_review": _gas_section(ctx),
        "synthetic_schema_conflicts": real.synthetic_schema_conflicts(preview, root),
        "contract_preview": preview,
        "negative_searches": ctx["review"]["negative_searches"],
        "net_heat_budget_B_missing_evidence": list(real.MISSING_B_EVIDENCE),
        "csat_accepted_as_cp_substitute": approvals["csat_accepted_as_cp_substitute"],
        "gas_assumptions_verified_at_origin": approvals["gas_assumptions_verified_at_origin"],
        "gas_range_extended": approvals["gas_range_extension"],
        "volumetric_article_inspected": ctx["review"]["volumetric"]["original_article_inspected"],
        "adapter_implemented_in_sim": False,
        "physical_benchmark_approval": False,
        "engine_integration": False,
        "production_activation": False,
    }


def _second_differences(ctx):
    """Second differences of the printed 10 K rows used by the profile, J/(mol*K)."""
    rows = _csat_rows(ctx)
    tens = [number(v, "T") for v in NATIVE_ROWS if v >= 300]
    return [rows[c][0] - 2 * rows[b][0] + rows[a][0]
            for a, b, c in zip(tens, tens[1:], tens[2:]) if c - b == b - a == 10]


def main():
    try:
        result = audit()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"decision": "rejected", "error": str(exc)}))
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
