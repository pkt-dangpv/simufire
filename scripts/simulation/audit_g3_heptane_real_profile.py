"""Offline eligibility audit of real n-heptane thermal properties.

Design evidence for a later versioned adapter: nothing here is engine input and
no file under sim/ is written or changed. The gas result is an ideal-gas
property; liquid Csat stays on its saturation path and is not relabelled Cp.
Comparing printed equations with printed tables checks the transcription and
the arithmetic. It is not an independent experimental validation, and the
controls in the tests are offline checks, not executed engine mutants.
"""
from __future__ import annotations

from decimal import Decimal
import hashlib
import json
import math
from pathlib import Path

from scripts.simulation import audit_g3_heptane_sensible_basis as sensible
from scripts.simulation.audit_g3_heptane_phase_basis import number
from scripts.simulation.audit_g3_measured_mass_candidate import confined_artifact
from scripts.simulation.validate_g3_mass_material_profile import load_profile


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs/validation/G3_D1_HEPTANE_REAL_PROFILE_INPUTS_2026-10-05.json"
SAVED = ROOT / "docs/validation/G3_D1_HEPTANE_REAL_PROFILE_AUDIT_2026-10-05.json"
PRIOR = {"path": "docs/validation/G3_D1_HEPTANE_SENSIBLE_INPUTS_2026-10-04.json",
         "sha256_lf": "b167db1c281d2125d3abf11ca6556a2f491b3a05bed210353a50abea06a4931b"}
NIST = "docs/literature/NIST/"
PUBS = "https://nvlpubs.nist.gov/nistpubs/"
SOURCES = {
    "calorimetry": {"path": sensible.SOURCE, "url": sensible.SOURCE_URL,
                    "sha256_raw": sensible.SOURCE_SHA},
    "scale_1948_to_1968": {
        "path": NIST + "NBS_IPTS68_Conversion_Douglas_1969.pdf",
        "url": PUBS + "jres/73A/jresv73An5p451_A1b.pdf",
        "sha256_raw": "11e9a97e0a157618e3df898f235098e4c010dfed8c44f763d83b92710e5a3c67"},
    "scale_1968_to_1990": {
        "path": NIST + "NIST_TN_1265_ITS90_Guidelines_1990.pdf",
        "url": PUBS + "Legacy/TN/nbstechnicalnote1265.pdf",
        "sha256_raw": "5c90691e7a496becd0ec56e2d837dee8aef4aeb64fe750b76c3cf4bc7e2b5c1b"},
    "saturation_relation": {
        "path": NIST + "NBS_Hydrocarbon_Heat_Capacity_Osborne_Ginnings_1947.pdf",
        "url": PUBS + "jres/39/jresv39n5p453_A1b.pdf",
        "sha256_raw": "0dcceb5865b44de7cb6fb02e5d0f23d1257e63106d1f135400095c1340abd288"},
    "liquid_density": {
        "path": NIST + "NBS_Aliphatic_Hydrocarbon_Properties_Brooks_1940.pdf",
        "url": PUBS + "jres/24/jresv24n1p33_A1b.pdf",
        "sha256_raw": "3f85b59231716430e73fed7e503d710083b42c674df52523578c0c1d0e0e1082"},
}
REVIEW_SHA = "71e0c2fce7cee228e10d65629ea8dd8ed7eac559d89c2cd635fa69af71260bb3"
SOURCES_SHA = hashlib.sha256(json.dumps(SOURCES, sort_keys=True).encode("utf-8")).hexdigest()

# Synthetic helper reviewed for the compatibility verdict (LF-normalised hash).
# Reviewed again on 2026-10-06 when its integration loop became the shared
# `integrate` function: the synthetic validator, its fields and its fixed labels
# did not change, so the synthetic schema still rejects the real labels. The
# real schemas are validated by HeptaneRealCpProfiles.gd, not by this helper.
SYNTHETIC_HELPER = "sim/fire/SensibleEnthalpyModel.gd"
SYNTHETIC_HELPER_SHA_LF = "272de43f4a2b9fb1801c3924b08489c4b9d4d8c89026e576e3b4a8e62e796750"
SYNTHETIC_FIELDS = ["schema", "component_id", "phase", "caloric_model", "pressure_path",
                    "reference_temperature_k", "reference_pressure_pa", "temperature_scale",
                    "quantity", "quantity_unit", "interpolation", "samples", "provenance",
                    "calibration_status"]
SYNTHETIC_FIXED = {"schema": "g3_synthetic_isobaric_cp_v1", "pressure_path": "constant_pressure",
                   "temperature_scale": "synthetic_kelvin", "quantity": "isobaric_specific_heat",
                   "quantity_unit": "kJ/(kg*K)", "interpolation": "piecewise_linear",
                   "calibration_status": "synthetic_not_material_calibration"}
REFERENCE_K = 298.15
REFERENCE_PA = 100000.0

# Predeclared bounds. They separate print resolution, conversion residue and
# discretization; none is an experimental uncertainty or a sim tolerance.
MU_TABLE_ABS_TOL = Decimal("0.0001")        # Douglas table 4 prints 0.0001 K
DMU_TABLE_ABS_TOL = Decimal("0.00002")      # and 0.00001 for the derivative
LABEL_ABS_TOL_K = Decimal("0.0006")         # 0.5 mK table rounding + 0.1 mK
SCALE_FACTOR_ABS_TOL = Decimal("0.0001")    # 1 mK rounding over a 10 K secant
SECANT_HALF_WIDTH_K = Decimal(5)
# h^2*|f''|/8 for 10 K knots of equation 22, plus half the unsmoothed join.
CP_INTERPOLATION_ABS_TOL = Decimal("0.007")
# Equation 12 is stated within 2 J/mol; two whole-joule H rows; printed Csat
# over 71.84 K; trapezoid convexity from the printed second differences.
LIQUID_CLOSURE_ABS_TOL = Decimal("4.3")
PRESSURE_ATM_PA = Decimal(101325)

REAL_FIXED = {"schema": "g3_real_ideal_gas_cp_v1", "component_id": "n-heptane",
              "caloric_model": "ideal_gas", "pressure_path": "constant_pressure",
              "temperature_scale": "ITS-90_kelvin", "quantity": "isobaric_specific_heat",
              "quantity_unit": "kJ/(kg*K)", "interpolation": "piecewise_linear",
              "calibration_status": "primary_source_property_not_fire_validation"}
DECLARED_ERRORS = {
    "cp_interpolation_abs_j_mol_k": float(CP_INTERPOLATION_ABS_TOL),
    "label_abs_k": float(LABEL_ABS_TOL_K),
    "scale_factor_abs": float(SCALE_FACTOR_ABS_TOL),
    "source_fit_percent": 0.05,
    "source_precision_percent": 0.1,
    "source_accuracy_statement": None,
    "source_uncertainty_in_assumed_range": None,
    "real_gas_departure_applied": False,
    # Limits established by the 2026-10-06 gate, carried with the profile.
    "scale_conversion_kind": "approximate_on_smoothed_values",
    "scale_approximation_residual_percent": None,
    "molar_mass_and_scale_verified_at_origin": False,
    "fire_validation": False,
}
MISSING_B_EVIDENCE = [
    "net_heat_absorbed_by_the_liquid_not_flux_to_a_cooled_gauge",
    "surface_reradiation_reflection_and_transmission_losses",
    "liquid_temperature_history_and_in_depth_profile_of_the_same_test",
    "heat_to_burner_walls_cooled_pan_and_fuel_feed_enthalpy",
    "published_uncertainty_and_repeatability_of_the_flux_profile",
    "flux_mass_and_temperature_channels_synchronised_in_one_run",
]
MISSING_LIQUID_EVIDENCE = [
    "liquid_molar_volume_273_to_371_K",
    "first_temperature_derivative_of_volume_273_to_371_K",
    "second_temperature_derivative_of_volume_273_to_371_K",
]


_VERIFIED = set()


def _f(value, places=9):
    return float(round(Decimal(value), places))


def _sha_lf(path):
    return hashlib.sha256(Path(path).read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def _confined_once(root, source):
    # Hashing 85 MB per call is the cost; a changed size or mtime hashes again.
    stat = (root / source["path"]).stat()
    key = (str(root), source["path"], stat.st_size, stat.st_mtime_ns)
    if key not in _VERIFIED:
        confined_artifact(root, source, text=False)
        _VERIFIED.add(key)


def prior_review(root=ROOT):
    """Reviewed 2026-10-04 record: equation 23, equation 22 and rows up to 370 K."""
    path = Path(root).resolve() / PRIOR["path"]
    if _sha_lf(path) != PRIOR["sha256_lf"]:
        raise ValueError("prior review record changed")
    review = load_profile(path)["review"]
    encoded = json.dumps(review, sort_keys=True, allow_nan=False).encode("utf-8")
    if hashlib.sha256(encoded).hexdigest() != sensible.REVIEW_SHA:
        raise ValueError("prior review semantics changed")
    return review


def _mu(review, t68_k):
    """T68 - T48 from the transcribed defining relation, kelvin."""
    eq = review["temperature"]["mu_equation"]
    t = t68_k - number(review["temperature"]["modern_kelvin_offset"], "offset")
    low, high = (number(v, "scale range") for v in eq["range_t68_c"])
    if not low <= t <= high:
        raise ValueError("outside the 1948-1968 relation support")
    a, b, c, t1, t2 = (number(eq[k], k) for k in ["a", "b", "c", "t1", "t2"])
    hundred = Decimal(100)
    phi = c * (t / hundred) * (t / hundred - 1) * (t / t1 - 1) * (t / t2 - 1)
    return a * t * (t - hundred) / (1 - b * t) + phi


def _t90_minus_t68(review, t90_c):
    rows = review["temperature"]["t90_minus_t68_rows"]
    for (x0, y0), (x1, y1) in zip(rows, rows[1:]):
        x0, y0, x1, y1 = (number(v, "scale table") for v in (x0, y0, x1, y1))
        if x0 <= t90_c <= x1:
            return y0 + (y1 - y0) * (t90_c - x0) / (x1 - x0)
    raise ValueError("outside the 1968-1990 table support")


def source_to_its90(review, t_native):
    """ITS-90 label of a temperature printed by the 1954 source.

    Three separate steps: kelvin offset 273.16 -> 273.15 (a convention, not a
    scale change), IPTS-48 -> IPTS-68 and IPTS-68 -> ITS-90.
    """
    temp = review["temperature"]
    offset = number(temp["modern_kelvin_offset"], "offset")
    t48 = number(t_native, "native temperature") - (
        number(temp["native_kelvin_offset"], "native offset") - offset)
    t68 = t48
    for _ in range(8):
        t68 = t48 + _mu(review, t68)
    t90 = t68
    for _ in range(8):
        t90 = t68 + _t90_minus_t68(review, t90 - offset)
    return t90


def its90_scale_factor(review, t_native):
    """dT_native/dT90: keeps enthalpy increments between source states."""
    t = number(t_native, "native temperature")
    half = SECANT_HALF_WIDTH_K
    return 2 * half / (source_to_its90(review, float(t + half))
                       - source_to_its90(review, float(t - half)))


def _gas_support(prior, review):
    return (number(prior["native_reference_temperature_k"], "support"),
            number(review["gas"]["table_rows_above_370"][-1][0], "support"))


def gas_cp_native(prior, review, t_native):
    """Ideal-gas Cp in J/(mol*K) on the source's own temperature labels."""
    t = number(t_native, "native temperature")
    low, high = _gas_support(prior, review)
    if not low <= t <= high:
        raise ValueError("outside reviewed gas support; no extrapolation")
    anchor = number(prior["gas_cp_anchor_temperature_k"], "anchor")
    if t <= anchor:
        return (number(prior["gas_cp_anchor_j_mol_k"], "anchor Cp")
                + number(prior["gas_cp_slope_j_mol_k2"], "slope") * (t - anchor))
    a, b, c = (number(v, "coefficient") for v in prior["gas_high_equation_coefficients"])
    return a + b * t + c * t * t


def _gas_enthalpy_native(prior, review, t_native):
    t = number(t_native, "native temperature")
    low, high = _gas_support(prior, review)
    if not low <= t <= high:
        raise ValueError("outside reviewed gas support; no extrapolation")
    anchor = number(prior["gas_cp_anchor_temperature_k"], "anchor")
    result = sensible.linear_gas_delta(prior, float(low), float(min(t, anchor)))
    if t > anchor:
        a, b, c = (number(v, "coefficient") for v in prior["gas_high_equation_coefficients"])
        upper = (a * (t - anchor) + b * (t * t - anchor * anchor) / 2
                 + c * (t ** 3 - anchor ** 3) / 3)
        result += upper.quantize(Decimal("1e-12"))
    return result


def gas_delta_native(prior, review, start_k, end_k):
    """Signed J/mol: equation 23 up to 370 K, equation 22 above, join unsmoothed."""
    return _gas_enthalpy_native(prior, review, end_k) - _gas_enthalpy_native(prior, review, start_k)


def canonical_enthalpy(samples, temperature_k, reference_k=REFERENCE_K):
    """Python restatement of the helper's signed piecewise-linear integral, kJ/kg.

    Same formula as SensibleEnthalpyModel.evaluate; it is not that GDScript
    code and has not been exercised in Godot.
    """
    temperature = float(temperature_k)
    if not samples[0]["temperature_k"] <= temperature <= samples[-1]["temperature_k"]:
        raise ValueError("query outside profile support; no extrapolation")
    lower, upper = min(reference_k, temperature), max(reference_k, temperature)
    integral = 0.0
    for left, right in zip(samples, samples[1:]):
        t0, t1 = left["temperature_k"], right["temperature_k"]
        c0, c1 = left["cp_kj_kg_k"], right["cp_kj_kg_k"]
        a, b = max(lower, t0), min(upper, t1)
        if b <= a:
            continue
        ca = c0 + (a - t0) / (t1 - t0) * (c1 - c0)
        cb = c0 + (b - t0) / (t1 - t0) * (c1 - c0)
        integral += (0.5 * ca + 0.5 * cb) * (b - a)
    return -integral if temperature < reference_k else integral


def _knots(prior, review):
    """One knot per printed table temperature: native label, ITS-90 label, values."""
    molar_mass = number(review["molar_mass"]["value_g_mol"], "molar mass")
    natives = ([row[0] for row in prior["gas_table_rows"]]
               + [row[0] for row in review["gas"]["table_rows_above_370"]])
    knots = []
    for native in natives:
        cp_native = gas_cp_native(prior, review, native)
        factor = its90_scale_factor(review, native)
        knots.append({
            "native_k": native,
            "its90_k": float(source_to_its90(review, native).quantize(Decimal("1e-6"))),
            "scale_factor": factor,
            "cp_native_j_mol_k": cp_native,
            "cp_kj_kg_k": float((cp_native * factor / molar_mass).quantize(Decimal("1e-12"))),
        })
    return knots


def _evidence_tiers(review):
    def labels(low, high):
        return [float(source_to_its90(review, v).quantize(Decimal("1e-6"))) for v in (low, high)]
    fitted, assumed = review["gas"]["evidence"]
    low, join = assumed["range_native_k"]
    measured_top = fitted["measured_range_native_k"][1]
    top = fitted["range_native_k"][1]
    return [
        {"native_range_k": [low, join], "its90_range_k": labels(low, join),
         "evidence_kind": assumed["evidence_kind"]},
        {"native_range_k": [join, measured_top], "its90_range_k": labels(join, measured_top),
         "evidence_kind": fitted["evidence_kind"]},
        {"native_range_k": [measured_top, top], "its90_range_k": labels(measured_top, top),
         "evidence_kind": "extrapolation_tabulated_by_source"},
    ]


def _provenance():
    return ("primary:sha256:" + SOURCES["calorimetry"]["sha256_raw"] + ";sources:sha256:"
            + SOURCES_SHA + ";review:sha256:" + REVIEW_SHA
            + ";adapter:g3_heptane_ideal_gas_cp_adapter_v1")


def _preview(prior, review):
    knots = _knots(prior, review)
    samples = [{"temperature_k": k["its90_k"], "cp_kj_kg_k": k["cp_kj_kg_k"]} for k in knots]
    anchor = prior["gas_cp_anchor_temperature_k"]
    picks = [0, [k["native_k"] for k in knots].index(anchor), len(knots) - 1]
    low, high = _gas_support(prior, review)
    return {
        **REAL_FIXED, "phase": "gas",
        "reference_temperature_k": REFERENCE_K, "reference_pressure_pa": REFERENCE_PA,
        "samples": samples, "provenance": _provenance(),
        "molar_mass_g_mol": review["molar_mass"]["value_g_mol"],
        "native_support_k": [float(low), float(high)],
        "evidence_tiers": _evidence_tiers(review),
        "declared_errors": dict(DECLARED_ERRORS),
        "witnesses": [{"temperature_k": samples[i]["temperature_k"],
                       "specific_sensible_enthalpy_kj_kg":
                           canonical_enthalpy(samples, samples[i]["temperature_k"])}
                      for i in picks],
    }


def _reviewed(record, root):
    root = Path(root).resolve()
    if record is None:
        record = load_profile(root / INPUT.relative_to(ROOT))
    if (not isinstance(record, dict)
            or set(record) != {"schema", "prior_review", "sources", "review"}
            or record["schema"] != "g3_heptane_real_profile_source_review_v1"):
        raise ValueError("unreviewed real-profile record/schema")
    if record["sources"] != SOURCES:
        raise ValueError("unreviewed source identity")
    if record["prior_review"] != PRIOR:
        raise ValueError("unreviewed prior review identity")
    for source in SOURCES.values():
        _confined_once(root, source)
    encoded = json.dumps(record["review"], sort_keys=True, allow_nan=False).encode("utf-8")
    if hashlib.sha256(encoded).hexdigest() != REVIEW_SHA:
        raise ValueError("unreviewed semantics, units or approvals")
    return prior_review(root), record["review"]


def contract_preview(record=None, root=ROOT):
    """Candidate of the proposed real schema. A design output, not an engine profile."""
    return _preview(*_reviewed(record, root))


def _finite(value):
    return (not isinstance(value, bool) and isinstance(value, (int, float))
            and math.isfinite(value))


def _interp(points, x):
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    raise ValueError("interpolation outside support")


def checked_samples(samples):
    """Structure of the canonical sample list; shared by the gas and liquid contracts."""
    if not isinstance(samples, list) or len(samples) < 2:
        raise ValueError("samples must be a list of at least two points")
    previous = None
    for sample in samples:
        if not isinstance(sample, dict) or set(sample) != {"temperature_k", "cp_kj_kg_k"}:
            raise ValueError("sample must have exactly temperature_k and cp_kj_kg_k")
        if not _finite(sample["temperature_k"]) or not _finite(sample["cp_kj_kg_k"]):
            raise ValueError("sample values must be finite numbers, never bool or text")
        if previous is not None and sample["temperature_k"] <= previous:
            raise ValueError("temperatures must be strictly increasing")
        if sample["cp_kj_kg_k"] <= 0:
            raise ValueError("Cp must be strictly positive")
        previous = sample["temperature_k"]
    return samples


def matched_knots(samples, knots):
    """Each sample must sit on a reviewed knot; the reference must stay inside."""
    used = []
    for sample in samples:
        nearest = min(knots, key=lambda k: abs(k["its90_k"] - sample["temperature_k"]))
        gap = abs(nearest["its90_k"] - sample["temperature_k"])
        if gap <= 1e-6:
            used.append(nearest)
        elif not knots[0]["its90_k"] - 0.5 <= sample["temperature_k"] <= knots[-1]["its90_k"] + 0.5:
            raise ValueError("extrapolation outside the reviewed support")
        else:
            raise ValueError("temperature labels do not follow the archived 1948-1968-1990 "
                             "mapping, or knots were resampled")
    if not samples[0]["temperature_k"] <= REFERENCE_K <= samples[-1]["temperature_k"]:
        raise ValueError("reference outside profile support")
    return used


def check_witnesses(samples, witnesses, temperatures):
    """Signed witness enthalpies recomputed with the canonical integral."""
    wanted = [{"temperature_k": temperature,
               "specific_sensible_enthalpy_kj_kg": canonical_enthalpy(samples, temperature)}
              for temperature in temperatures]
    matches = (isinstance(witnesses, list) and len(witnesses) == len(wanted) and all(
        isinstance(w, dict) and set(w) == set(e) and all(_finite(v) for v in w.values())
        and math.isclose(w["temperature_k"], e["temperature_k"], abs_tol=1e-9)
        and math.isclose(w["specific_sensible_enthalpy_kj_kg"],
                         e["specific_sensible_enthalpy_kj_kg"], rel_tol=1e-9, abs_tol=1e-12)
        for w, e in zip(witnesses, wanted)))
    if not matches or not wanted[0]["specific_sensible_enthalpy_kj_kg"] < 0 < wanted[-1][
            "specific_sensible_enthalpy_kj_kg"]:
        raise ValueError("witness enthalpy does not match the canonical signed integral")


def check_candidate(candidate, record=None, root=ROOT):
    """Contract controls of the proposed real schema against the pinned review."""
    prior, review = _reviewed(record, root)
    expected = _preview(prior, review)
    if not isinstance(candidate, dict) or set(candidate) != set(expected):
        raise ValueError("unexpected or missing candidate field")
    if candidate["phase"] != "gas":
        raise ValueError("no approved profile for this phase: the liquid source quantity "
                         "is Csat, not isobaric Cp")
    if candidate["caloric_model"] != "ideal_gas":
        raise ValueError("phase/caloric_model mismatch")
    for key, value in REAL_FIXED.items():
        if candidate[key] != value:
            raise ValueError("unsupported " + key)
    if (candidate["reference_temperature_k"] != REFERENCE_K
            or candidate["reference_pressure_pa"] != REFERENCE_PA):
        raise ValueError("incompatible reference state")
    if candidate["molar_mass_g_mol"] != expected["molar_mass_g_mol"]:
        raise ValueError("molar mass differs from the basis stated by the source")
    if candidate["provenance"] != expected["provenance"]:
        raise ValueError("provenance does not match the reviewed sources")
    samples = checked_samples(candidate["samples"])
    used = matched_knots(samples, _knots(prior, review))
    for sample, knot in zip(samples, used):
        if not math.isclose(sample["cp_kj_kg_k"], knot["cp_kj_kg_k"], rel_tol=1e-9, abs_tol=0.0):
            raise ValueError("Cp does not reproduce the source value on the declared unit, "
                             "molar-mass and scale basis")
    native_points = [(float(k["native_k"]), float(k["cp_native_j_mol_k"])) for k in used]
    if _native_interpolation_error(prior, review, native_points) > CP_INTERPOLATION_ABS_TOL:
        raise ValueError("discretization outside the declared interpolation error")
    for key in ["native_support_k", "evidence_tiers", "declared_errors"]:
        if candidate[key] != expected[key]:
            raise ValueError("declared limits altered: " + key)
    check_witnesses(samples, candidate["witnesses"],
                    [w["temperature_k"] for w in expected["witnesses"]])
    return {"valid": True, "knots": len(samples), "engine_profile": False}


def _native_interpolation_error(prior, review, native_points):
    """Largest |source Cp - straight line between kept knots|, J/(mol*K), native labels."""
    low, high = native_points[0][0], native_points[-1][0]
    natives = [float(k) for k in ([row[0] for row in prior["gas_table_rows"]]
                                  + [row[0] for row in review["gas"]["table_rows_above_370"]])]
    probes = natives + [(a + b) / 2 for a, b in zip(natives, natives[1:])]
    worst = Decimal(0)
    for probe in probes:
        if low <= probe <= high:
            line = Decimal(str(_interp(native_points, probe)))
            worst = max(worst, abs(gas_cp_native(prior, review, probe) - line))
    return worst


def synthetic_schema_conflicts(candidate, root=ROOT):
    """Why the current synthetic helper rejects the real labels, field by field."""
    if _sha_lf(Path(root).resolve() / SYNTHETIC_HELPER) != SYNTHETIC_HELPER_SHA_LF:
        raise ValueError("synthetic helper changed; review the compatibility verdict again")
    conflicts = {key: [candidate[key], value] for key, value in SYNTHETIC_FIXED.items()
                 if candidate[key] != value}
    if not candidate["provenance"].startswith("synthetic:"):
        conflicts["provenance"] = [candidate["provenance"].split(";")[0], "synthetic:*"]
    extra = sorted(set(candidate) - set(SYNTHETIC_FIELDS))
    if extra:
        conflicts["unexpected_fields"] = extra
    return conflicts


def _scale_section(prior, review):
    offset = number(review["temperature"]["modern_kelvin_offset"], "offset")
    step = Decimal("0.001")
    mu_worst = dmu_worst = Decimal(0)
    rows = review["temperature"]["mu_table_rows"]
    for t68, mu, dmu in rows:
        t = number(t68, "T68")
        mu_worst = max(mu_worst, abs(_mu(review, t) - number(mu, "mu")))
        if t - step >= offset:
            slope = (_mu(review, t + step) - _mu(review, t - step)) / (2 * step)
            dmu_worst = max(dmu_worst, abs(slope - number(dmu, "dmu")))
    if mu_worst > MU_TABLE_ABS_TOL or dmu_worst > DMU_TABLE_ABS_TOL:
        raise ValueError("printed scale table and relation inconsistent")
    knots = _knots(prior, review)
    shifts = [Decimal(str(k["its90_k"])) - number(k["native_k"], "native") for k in knots]
    factors = [k["scale_factor"] for k in knots]
    return {
        "steps": ["kelvin_offset_273.16_to_273.15", "IPTS-48_to_IPTS-68", "IPTS-68_to_ITS-90"],
        "mu_rows_checked": len(rows),
        "mu_max_abs_residual_k": _f(mu_worst, 6),
        "dmu_max_abs_residual": _f(dmu_worst, 7),
        "label_shift_min_k": _f(min(shifts), 6),
        "label_shift_max_k": _f(max(shifts), 6),
        "scale_factor_min": _f(min(factors), 6),
        "scale_factor_max": _f(max(factors), 6),
        "its90_reference_on_native_label_k": _f(_native_label_of(review, Decimal(str(REFERENCE_K))), 4),
        "rows": [{"native_k": k["native_k"], "its90_k": k["its90_k"],
                  "scale_factor": _f(k["scale_factor"], 6)} for k in knots],
        "gas_equation_scale_is_assumed": True,
    }


def _native_label_of(review, t90):
    low, high = Decimal("298.16"), Decimal("298.20")
    for _ in range(40):
        middle = (low + high) / 2
        if source_to_its90(review, float(middle)) < t90:
            low = middle
        else:
            high = middle
    return low


def _gas_section(prior, review, preview):
    reference = prior["native_reference_temperature_k"]
    anchor = prior["gas_cp_anchor_temperature_k"]
    anchor_h = number(prior["gas_table_rows"][-1][2], "H at join")
    rows = []
    for temperature, cp, enthalpy in review["gas"]["table_rows_above_370"]:
        cp_residual = gas_cp_native(prior, review, temperature) - number(cp, "table Cp")
        h_residual = (gas_delta_native(prior, review, anchor, temperature)
                      - (number(enthalpy, "table H") - anchor_h))
        if abs(cp_residual) > sensible.CP_PRINT_ABS_TOL or abs(h_residual) > sensible.H_PRINT_ABS_TOL:
            raise ValueError("printed gas equation/table inconsistent")
        rows.append({"temperature_k": temperature, "cp_residual_j_mol_k": _f(cp_residual, 6),
                     "delta_h_residual_j_mol": _f(h_residual, 6)})
    top = review["gas"]["table_rows_above_370"][-1]
    printed_total = number(top[2], "H") - number(prior["gas_table_rows"][0][2], "H")
    molar_mass = number(review["molar_mass"]["value_g_mol"], "molar mass")
    knots = _knots(prior, review)
    samples = preview["samples"]
    worst = Decimal(0)
    for left, right, a, b in zip(knots, knots[1:], samples, samples[1:]):
        native = gas_delta_native(prior, review, left["native_k"], right["native_k"])
        canonical = Decimal(str(canonical_enthalpy(samples, b["temperature_k"])
                                - canonical_enthalpy(samples, a["temperature_k"]))) * molar_mass
        residual = abs(canonical - native)
        if residual > Decimal("0.04") + SCALE_FACTOR_ABS_TOL * abs(native):
            raise ValueError("canonical integral does not keep the source enthalpy increment")
        worst = max(worst, residual)
    interpolation = _native_interpolation_error(
        prior, review, [(float(k["native_k"]), float(k["cp_native_j_mol_k"])) for k in knots])
    if interpolation > CP_INTERPOLATION_ABS_TOL:
        raise ValueError("discretization outside the declared interpolation error")
    a, b, c = (number(v, "coefficient") for v in prior["gas_high_equation_coefficients"])
    spread = []
    for temperature in [reference, 357]:
        t = number(temperature, "T")
        difference = a + b * t + c * t * t - gas_cp_native(prior, review, temperature)
        spread.append({"temperature_k": temperature, "equation_22_minus_23_j_mol_k": _f(difference, 4),
                       "percent": _f(100 * difference / gas_cp_native(prior, review, temperature), 3)})
    low_t, join_t = number(reference, "T"), number(anchor, "T")
    extrapolated = (a * (join_t - low_t) + b * (join_t * join_t - low_t * low_t) / 2
                    + c * (join_t ** 3 - low_t ** 3) / 3)
    adopted = gas_delta_native(prior, review, reference, anchor)
    departure = [{"temperature_k": t, "observed_j_mol_k_atm": value,
                  "percent_of_ideal_cp_per_atm":
                      _f(100 * number(value, "dCp/dP") / gas_cp_native(prior, review, t), 2)}
                 for t, value in review["gas"]["pressure_coefficient_observed_rows"]]
    total = canonical_enthalpy(samples, samples[-1]["temperature_k"]) - canonical_enthalpy(
        samples, samples[0]["temperature_k"])
    return {
        "quantity": review["gas"]["quantity"],
        "comparison_kind": "printed_equation_vs_derived_table_NOT_fire_experiment",
        "rows_above_370": rows,
        "delta_h_298_16_to_470_j_mol": _f(gas_delta_native(prior, review, reference, top[0])),
        "printed_delta_h_298_16_to_470_j_mol": int(printed_total),
        "canonical_delta_h_same_states_j_mol": _f(Decimal(str(total)) * molar_mass, 4),
        "interval_enthalpy_max_abs_residual_j_mol": _f(worst, 4),
        "cp_interpolation_max_abs_j_mol_k": _f(interpolation, 6),
        "assumed_range_model_form_spread": spread,
        "assumed_range_delta_h_equation_22_minus_23_j_mol": _f(extrapolated - adopted, 3),
        "assumed_range_delta_h_spread_percent": _f(100 * (extrapolated - adopted) / adopted, 3),
        "real_gas_departure_not_applied": departure,
        "molar_mass_g_mol": review["molar_mass"]["value_g_mol"],
        "cp_370_native_kj_kg_k": _f(gas_cp_native(prior, review, anchor) / molar_mass),
        "upper_limit_native_k": top[0],
        "covers_flame_temperatures": False,
    }


def _vdp(review, t):
    eq = review["liquid"]["v_dp_equation"]
    b1, b0, b3, tc = (number(eq[k], k) for k in ["b1", "b0", "b3", "tc"])
    exponent = b1 * t + b0 + b3 * (tc - t) ** 3
    value = Decimal(10) ** exponent
    slope = value * Decimal(10).ln() * (b1 - 3 * b3 * (tc - t) ** 2)
    return value, slope


def _csat_equation(review, t):
    eq = review["liquid"]["csat_equation"]
    a0, a1, a2, a3, tc = (number(eq[k], k) for k in ["a0", "a1", "a2", "a3", "tc"])
    root = (tc - t).sqrt()
    return a0 + a1 * t + a2 * t * t + a3 / root * Decimal(10) ** (Decimal("-0.3") * root)


def _vapour_pressure_atm(review, t_c):
    eq = review["liquid"]["vapour_pressure_equation"]
    a, b, c = (number(eq[k], k) for k in ["a", "b", "c"])
    return Decimal(10) ** (a - b / (t_c + c))


def _liquid_section(prior, review):
    liquid = review["liquid"]
    reference = number(prior["native_reference_temperature_k"], "reference")
    top = number(prior["gas_cp_anchor_temperature_k"], "top")
    rows = [[number(v, "liquid row") for v in row] for row in liquid["table_rows"]]
    span = [row for row in rows if reference <= row[0] <= top]
    trapezoid = sum((a[1] + b[1]) * (b[0] - a[0]) / 2 for a, b in zip(span, span[1:]))
    printed = span[-1][2] - span[0][2]
    gap = printed - trapezoid
    v_dp = _vdp(review, top)[0] - _vdp(review, reference)[0]
    if abs(gap - v_dp) > LIQUID_CLOSURE_ABS_TOL:
        raise ValueError("saturation enthalpy does not close with the V dP term")
    by_t = {row[0]: row for row in rows}
    for t in [Decimal(380), Decimal(390)]:
        if abs(_csat_equation(review, t) - by_t[t][1]) > sensible.CP_PRINT_ABS_TOL:
            raise ValueError("printed liquid equation/table inconsistent above 370 K")
    density = liquid["density"]
    molar_mass = number(review["molar_mass"]["value_g_mol"], "molar mass")
    rho20, rho25 = number(density["rho_20_c_g_ml"], "rho"), number(density["rho_25_c_g_ml"], "rho")
    volume = molar_mass / rho25
    expansivity = -number(density["d_rho_dt_g_ml_c"], "drho") / ((rho20 + rho25) / 2)
    psat = _vapour_pressure_atm(review, Decimal(25)) * PRESSURE_ATM_PA
    bound = volume * Decimal("1e-6") * (Decimal(str(REFERENCE_PA)) - psat)
    boiling = _vapour_pressure_atm(review, number(density["normal_boiling_point_c"], "nbp"))
    if abs(boiling - 1) > Decimal("0.001"):
        raise ValueError("vapour pressure relation inconsistent with the independent boiling point")
    relation = liquid["saturation_relation"]
    middle = Decimal("22.5") + number(review["temperature"]["native_kelvin_offset"], "offset")
    low, high = by_t[Decimal(295)], by_t[reference]
    table_middle = low[1] + (high[1] - low[1]) * (middle - low[0]) / (high[0] - low[0])
    difference = (number(relation["observed_dh_dt_20_25_c_int_j_g_c"], "dH/dT")
                  - number(relation["observed_csat_20_25_c_int_j_g_c"], "Csat")) * molar_mass
    return {
        "quantity": liquid["quantity"],
        "path": liquid["path"],
        "isobaric_profile_approval": False,
        "printed_delta_h_sat_298_16_to_370_j_mol": int(printed),
        "csat_trapezoid_298_16_to_370_j_mol": _f(trapezoid, 4),
        "gap_without_v_dp_j_mol": _f(gap, 4),
        "v_dp_term_298_16_to_370_j_mol": _f(v_dp, 4),
        "closure_residual_with_v_dp_j_mol": _f(gap - v_dp, 4),
        "closure_abs_tol_j_mol": float(LIQUID_CLOSURE_ABS_TOL),
        "v_dp_dt_298_16_j_mol_k": _f(_vdp(review, reference)[1], 5),
        "v_dp_dt_370_j_mol_k": _f(_vdp(review, top)[1], 5),
        "csat_equation_380_j_mol_k": _f(_csat_equation(review, Decimal(380)), 4),
        "csat_equation_390_j_mol_k": _f(_csat_equation(review, Decimal(390)), 4),
        "csat_equation_minus_table_298_16_j_mol_k":
            _f(_csat_equation(review, reference) - by_t[reference][1], 4),
        "molar_volume_25_c_ml_mol": _f(volume, 4),
        "expansivity_20_25_c_per_k": _f(expansivity, 9),
        "expansivity_times_t_at_22_5_c": _f(expansivity * middle, 5),
        "cp_minus_csat_at_saturation_298_16_j_mol_k":
            _f(expansivity * reference * _vdp(review, reference)[1], 5),
        "pressure_term_bound_at_298_15_j_mol": _f(bound, 4),
        "volumetric_data_range_c": density["range_c"],
        "vapour_pressure_at_brooks_boiling_point_atm": _f(boiling, 6),
        "osborne_ginnings_csat_22_5_c_j_mol_k_unconverted_joule":
            _f(number(relation["observed_csat_20_25_c_int_j_g_c"], "Csat") * molar_mass, 4),
        "table_csat_interpolated_22_5_c_j_mol_k": _f(table_middle, 4),
        "osborne_ginnings_dh_dt_minus_csat_j_mol_k": _f(difference, 4),
        "v_dp_dt_22_5_c_j_mol_k": _f(_vdp(review, middle)[1], 5),
        "stated_csat_vs_cp_bound_percent": 0.2,
        "stated_bound_range_c": relation["statement_range_c"],
        "stated_bound_kind": relation["evidence_kind"],
        "missing_for_isobaric_conversion": list(MISSING_LIQUID_EVIDENCE),
    }


def audit(record=None, root=ROOT):
    prior, review = _reviewed(record, root)
    preview = _preview(prior, review)
    check_candidate(preview, record, root)
    return {
        "schema": "g3_heptane_real_profile_eligibility_audit_v1",
        "decision": {
            "gas": "GO_partial_ideal_gas_native_298.16_to_470_K",
            "liquid": "NO_GO_isobaric_profile_native_Csat_only",
            "current_synthetic_contract": "NO_GO_by_design_requires_versioned_real_schema",
            "net_heat_budget_B": "NO_GO_separate_gate",
        },
        "review_sha256": REVIEW_SHA,
        "sources_sha256": SOURCES_SHA,
        "scale": _scale_section(prior, review),
        "gas": _gas_section(prior, review, preview),
        "liquid": _liquid_section(prior, review),
        "synthetic_schema_conflicts": synthetic_schema_conflicts(preview, root),
        "contract_preview": preview,
        "net_heat_budget_B_missing_evidence": list(MISSING_B_EVIDENCE),
        "adapter_implemented_in_sim": False,
        "liquid_isobaric_profile_approval": False,
        "real_gas_correction_applied": False,
        "physical_benchmark_approval": False,
        "engine_integration": False,
        "production_activation": False,
    }


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
