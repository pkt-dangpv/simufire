"""Offline audit of the flameless n-heptane evaporation test as a benchmark.

Source: Beji, Helson, Rogaume and Luche, Fire Safety Journal 121 (2021) 103317. A 250 ml batch of
n-heptane in an insulated steel pan is irradiated by a cone heater at two nominal levels inside a
controlled-atmosphere cone calorimeter kept low in oxygen, so the liquid evaporates without flame.

The audit answers five separate questions and never lets one answer stand for another:

1. which observables are eligible as contrasts;
2. whether the irradiation arriving at the liquid is identified;
3. whether the net heat absorbed by the liquid is identified;
4. what could be validated about the heating of the liquid;
5. what could be validated about the emission.

Four objects are kept apart throughout. The nominal irradiation is a set point checked at one
point before each test. The irradiation on the regressing surface is a geometric calculation.
The net heat absorbed by the liquid is neither of them. The demand rebuilt from the evaporated
mass and the thermocouples is a diagnostic that consumes the observables it would have to
predict, so it is never offered as an independent thermal input.

The published curves exist only as figures. Their digitisation lives outside version control
(see digitise_g3_cone_benchmark_figures); this module works from scalar aggregates derived from
it, recomputes them when the local digitisation is present and says so when it is not.

No thermal solver is implemented here and nothing is fitted to the data.
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
from scripts.simulation import audit_g3_net_thermal_budget as net  # noqa: E402
from scripts.simulation import digitise_g3_cone_benchmark_figures as digitiser  # noqa: E402

INPUT = ROOT / "docs/validation/G3_D1_CONE_EVAPORATION_BENCHMARK_INPUTS_2026-10-07.json"
AGGREGATES = ROOT / "docs/validation/G3_D1_CONE_EVAPORATION_BENCHMARK_AGGREGATES_2026-10-07.json"
SAVED = ROOT / "docs/validation/G3_D1_CONE_EVAPORATION_BENCHMARK_AUDIT_2026-10-07.json"
SCHEMA = "g3_cone_evaporation_benchmark_v1"
AGGREGATES_SCHEMA = "g3_cone_evaporation_benchmark_aggregates_v1"
AUDIT_SCHEMA = "g3_cone_evaporation_benchmark_audit_v1"

KELVIN = 273.15
CLASSES = ("nominal", "measured", "calculated", "assumed", "unknown")
BOUNDING_CLASSES = ("measured", "bounded")
ROLES = ("nominal_irradiation", "incident_irradiation", "absorbed_heat", "net_heat", "demand_diagnostic")
NATURES = ("digitisation", "raw", "calculated")
DECISIONS = ("observables_eligibility", "incident_irradiation", "net_absorbed_heat",
             "heating_validation", "emission_validation")


class Refusal(ValueError):
    """A request that would turn one kind of evidence into another."""


# ---------------------------------------------------------------------------------------------
# Units, rates and accumulated quantities
# ---------------------------------------------------------------------------------------------

def celsius_to_kelvin(value_c):
    return net.number(value_c, "temperature in Celsius") + KELVIN


def accumulate(rates_g_m2_s, step_s):
    """Mass per unit area lost at each marker, in kg/m2, from block means in g/(m2 s).

    The accumulation is what the balance recorded; the rate is the published derivative of it.
    A mean over a block times the length of the block is exactly the mass lost in the block, so
    summing is the one operation that adds no smoothing of its own.
    """
    step = net.number(step_s, "block length")
    if step <= 0.0:
        raise Refusal("the block length must be positive")
    total = 0.0
    out = []
    for value in rates_g_m2_s:
        if value is None:
            raise Refusal("a missing reading cannot be accumulated as if it were zero")
        rate = net.number(value, "mass loss rate")
        total += rate * step / 1000.0
        out.append(total)
    return out


def rate_from_accumulated(accumulated_kg_m2, step_s, smoothing=None):
    """Refuse to differentiate an accumulation unless the smoothing is declared."""
    if not smoothing:
        raise Refusal("a rate derived from accumulated mass needs a declared differentiation or smoothing")
    step = net.number(step_s, "block length")
    previous = 0.0
    out = []
    for value in accumulated_kg_m2:
        out.append((value - previous) * 1000.0 / step)
        previous = value
    return {"rates_g_m2_s": out, "smoothing": smoothing}


# ---------------------------------------------------------------------------------------------
# Evidence kinds
# ---------------------------------------------------------------------------------------------

def require_class(value, label):
    if value not in CLASSES:
        raise Refusal("%s: class %r is not one of %s" % (label, value, ", ".join(CLASSES)))
    return value


def relabel(quantity, role):
    """Offer a quantity under a role; only the role its evidence supports is accepted."""
    if role not in ROLES:
        raise Refusal("unknown role %r" % role)
    own = quantity.get("role")
    if own not in ROLES:
        raise Refusal("the quantity does not declare a known role")
    if role == own:
        return quantity
    raise Refusal("%s cannot be presented as %s" % (own, role))


def series_nature(series):
    """Nature of a published series; a figure reading is never raw data."""
    nature = series.get("nature", "")
    if "digitisation of published figures" not in nature or "not raw data" not in nature:
        raise Refusal("the series does not declare itself a digitisation of figures")
    return "digitisation"


def present_series_as(series, nature):
    if nature not in NATURES:
        raise Refusal("unknown nature %r" % nature)
    if series_nature(series) != nature:
        raise Refusal("a digitised figure cannot be presented as %s data" % nature)
    return series


def combined_uncertainty(parts):
    """An absent uncertainty stays absent: the total is null, never the sum of the known parts."""
    if any(part is None for part in parts):
        return None
    return math.sqrt(sum(net.number(part, "uncertainty") ** 2 for part in parts))


def frontier_status(terms):
    """Net heat is identified only if every frontier term is measured or bounded."""
    classes = {}
    blocking = []
    for term in terms:
        identification = term["identification"]
        classes[term["key"]] = identification
        if identification not in BOUNDING_CLASSES:
            blocking.append(term["key"])
    return {"classes": classes, "blocking": blocking, "identified": not blocking}


def absorbed_from_incident(incident_kw_m2, terms):
    """Incident irradiation becomes absorbed heat only through identified optical terms."""
    status = frontier_status(terms)
    if not status["identified"]:
        raise Refusal("incident irradiation is not absorbed heat: unidentified terms %s" % ", ".join(status["blocking"]))
    value = net.number(incident_kw_m2, "incident irradiation")
    for term in terms:
        value *= term.get("factor", 1.0)
    return value


def independent_prediction_allowed(quantity, observable):
    """A quantity built from an observable cannot validate a prediction of that observable."""
    return observable not in quantity.get("depends_on", [])


def require_independent(quantity, observable):
    if not independent_prediction_allowed(quantity, observable):
        name = quantity.get("name", "the quantity")
        raise Refusal("%s is built from %s and cannot validate a prediction of it" % (name, observable))
    return quantity


def same_run(*channels):
    """Channels are synchronous only when they belong to the same run."""
    runs = {channel["run"] for channel in channels}
    if len(runs) != 1:
        raise Refusal("curves of different runs are not synchronous channels: %s" % ", ".join(sorted(runs)))
    return runs.pop()


def inside_window(time_s, window):
    start, end = window
    if not start <= time_s <= end:
        raise Refusal("%.1f s lies outside the window %.1f to %.1f s" % (time_s, start, end))
    return time_s


def mean_temperature(readings, profile_measured=False):
    """Point thermocouples are a mean temperature only if the profile between them is measured."""
    if not profile_measured:
        raise Refusal("%d point temperatures are not a mean or a surface temperature" % len(readings))
    return sum(readings) / len(readings)


# ---------------------------------------------------------------------------------------------
# Geometry of the irradiation
# ---------------------------------------------------------------------------------------------

def disc_factor(radius, height, offset):
    """Configuration factor from a horizontal element to a parallel coaxial disc above it."""
    if offset < 1.0e-9:
        return radius * radius / (radius * radius + height * height)
    h, r = height / offset, radius / offset
    z = 1.0 + h * h + r * r
    return 0.5 * (1.0 - (1.0 + h * h - r * r) / math.sqrt(z * z - 4.0 * r * r))


def frustum_factor(distance, offset, cone):
    """Factor to the inner surface of the cone: its base opening minus its top opening."""
    return (disc_factor(cone["base_radius_mm"], distance, offset)
            - disc_factor(cone["top_radius_mm"], distance + cone["height_mm"], offset))


def area_average_factor(distance, side_mm, cone, cells=40):
    half = side_mm / 2.0
    total = 0.0
    for i in range(cells):
        for j in range(cells):
            x, y = (i + 0.5) * half / cells, (j + 0.5) * half / cells
            total += frustum_factor(distance, math.hypot(x, y), cone)
    return total / (cells * cells)


def line_average_factor(distance, side_mm, cone, cells=400):
    """Mean along the line from the centre to the middle of a side."""
    half = side_mm / 2.0
    return sum(frustum_factor(distance, (i + 0.5) * half / cells, cone) for i in range(cells)) / cells


def hemisphere_factor(lip_mm, side_mm, cone, gap_mm, rim=True, cells=8, rings=60, sectors=120):
    """Area-averaged factor by direct quadrature of the hemisphere, with the pan rim as a screen.

    A ray leaving the liquid counts when it clears the rim, enters the base of the cone and does
    not leave through its top opening. The cone is taken as a uniform diffuse emitter, which is
    the assumption of the analytic expression as well.
    """
    half = side_mm / 2.0
    distance = lip_mm + gap_mm
    top = distance + cone["height_mm"]
    r_base2 = cone["base_radius_mm"] ** 2
    r_top2 = cone["top_radius_mm"] ** 2
    directions = []
    for k in range(rings):
        u = (k + 0.5) / rings
        tangent = math.sqrt(u / (1.0 - u))
        for m in range(sectors):
            phi = (m + 0.5) * 2.0 * math.pi / sectors
            directions.append((tangent * math.cos(phi), tangent * math.sin(phi)))
    total = 0.0
    for i in range(cells):
        for j in range(cells):
            x0, y0 = (i + 0.5) * half / cells, (j + 0.5) * half / cells
            hits = 0
            for dx, dy in directions:
                if rim and (abs(x0 + lip_mm * dx) > half or abs(y0 + lip_mm * dy) > half):
                    continue
                xb, yb = x0 + distance * dx, y0 + distance * dy
                if xb * xb + yb * yb > r_base2:
                    continue
                xt, yt = x0 + top * dx, y0 + top * dy
                if xt * xt + yt * yt <= r_top2:
                    continue
                hits += 1
            total += hits / len(directions)
    return total / (cells * cells)


_GEOMETRY_CACHE = {}


def geometry(setup):
    """Relative irradiation on the liquid, the calibration point taken as one."""
    key = json.dumps([setup["cone"], setup["pan"]["inner_side_mm"], setup["pan"]["depth_mm"], setup["gap_rim_to_cone_mm"],
                      setup["levels_mm"], setup["authors_view_factor"]], sort_keys=True)
    if key not in _GEOMETRY_CACHE:
        _GEOMETRY_CACHE[key] = _geometry(setup)
    return json.loads(json.dumps(_GEOMETRY_CACHE[key]))


def _geometry(setup):
    cone = setup["cone"]
    pan = setup["pan"]
    gap = setup["gap_rim_to_cone_mm"]["value"]
    depth = pan["depth_mm"]["value"]
    sides = [pan["inner_side_mm"]["value"]] + list(pan["inner_side_mm"]["alternatives"])
    levels = setup["levels_mm"]
    centre = frustum_factor(depth - levels["initial_nominal"] + gap, 0.0, cone)
    table = {}
    for side in sides:
        rows = {}
        for name, level in levels.items():
            lip = depth - level
            distance = lip + gap
            analytic = area_average_factor(distance, side, cone) / centre
            open_numeric = hemisphere_factor(lip, side, cone, gap, rim=False) / centre
            screened = hemisphere_factor(lip, side, cone, gap, rim=True) / centre
            rows[name] = {
                "liquid_level_mm": level,
                "distance_to_cone_mm": distance,
                "centre": frustum_factor(distance, 0.0, cone) / centre,
                "area_average_open": analytic,
                "area_average_open_by_quadrature": open_numeric,
                "area_average_with_rim": screened,
                "line_average_open": line_average_factor(distance, side, cone) / centre,
            }
        table["%g" % side] = rows
    base = table["%g" % sides[0]]
    authors = setup["authors_view_factor"]
    printed = [authors["start"], authors["end"]]
    ours = [base["initial_nominal"]["area_average_open"], base["empty"]["area_average_open"]]
    line = [base["initial_nominal"]["line_average_open"], base["empty"]["line_average_open"]]
    return {
        "assumption": "uniform diffuse cone surface; rim opaque and non-reflecting; calibration point taken as 1",
        "centre_factor_absolute": centre,
        "by_side_mm": table,
        "authors": {"start": authors["start"], "end": authors["end"], "ratio": authors["end"] / authors["start"]},
        "area_average": {"start": ours[0], "end": ours[1], "ratio": ours[1] / ours[0]},
        "line_average": {"start": line[0], "end": line[1], "ratio": line[1] / line[0]},
        "authors_values_reproduced_by_area_average": all(abs(a - b) <= 0.01 for a, b in zip(ours, printed)),
        "authors_values_reproduced_by_line_average": all(abs(a - b) <= 0.01 for a, b in zip(line, printed)),
        "authors_ratio_reproduced": abs(ours[1] / ours[0] - authors["end"] / authors["start"]) <= 0.01,
        "quadrature_error": max(abs(row["area_average_open"] - row["area_average_open_by_quadrature"])
                                for rows in table.values() for row in rows.values()),
        "mass_free_range": {
            "open": [base["empty"]["area_average_open"], base["initial_nominal"]["area_average_open"]],
            "with_rim": [base["empty"]["area_average_with_rim"], base["initial_nominal"]["area_average_with_rim"]],
            "envelope": [base["empty"]["area_average_with_rim"], base["initial_nominal"]["area_average_open"]],
            "depends_on": [],
        },
    }


# ---------------------------------------------------------------------------------------------
# Aggregates of the digitised series
# ---------------------------------------------------------------------------------------------

def _curve(series, run, quantity):
    for curve in series["curves"]:
        if curve["run"] == run and curve["quantity"] == quantity:
            return curve
    return None


def _filled(readings):
    """Readings with a hidden marker replaced by the range of its neighbours, declared as such."""
    out = []
    for index, reading in enumerate(readings):
        if reading.get("value") is not None:
            out.append((reading["t_s"], reading["value"], reading["half_width"], reading["status"]))
            continue
        before = next((r for r in reversed(readings[:index]) if r.get("value") is not None), None)
        after = next((r for r in readings[index + 1:] if r.get("value") is not None), None)
        if before is None or after is None:
            out.append((reading["t_s"], None, None, reading["status"]))
            continue
        low = min(before["value"] - before["half_width"], after["value"] - after["half_width"])
        high = max(before["value"] + before["half_width"], after["value"] + after["half_width"])
        out.append((reading["t_s"], 0.5 * (low + high), 0.5 * (high - low), "assumed_between_neighbours"))
    return out


def mass_table(curve, step_s):
    """Accumulated mass per unit area at every marker, with its reading range. Not published."""
    rows = _filled(curve["readings"])
    peak = max((value, time) for time, value, _half, _status in rows if value is not None)
    fall = None
    for time, value, _half, _status in rows:
        if value is not None and time > peak[1] and value <= 0.25 * peak[0]:
            fall = time
            break
    usable = [row for row in rows if row[1] is not None]
    times = [row[0] for row in usable]
    central = accumulate([row[1] for row in usable], step_s)
    spread = accumulate([row[2] for row in usable], step_s)
    return {"rows": rows, "times": times, "central": central, "spread": spread, "peak": peak, "end_of_fall_s": fall}


def mass_aggregates(table, checkpoints):
    """Accumulated mass per unit area at the markers that the audit needs."""
    rows, times, central, spread = table["rows"], table["times"], table["central"], table["spread"]
    at = {}
    for moment in checkpoints:
        if moment in times:
            k = times.index(moment)
            # The paper does not say whether a block mean is drawn at the start, middle or end of
            # its block; the readings differ by the last block, which is the stated range.
            at["%g" % moment] = {
                "block_ends_at_marker": central[k],
                "block_starts_at_marker": central[k - 1] if k else 0.0,
                "reading_half_width": spread[k],
            }
    fall = table["end_of_fall_s"]
    main = central[times.index(fall)] if fall in times else None
    return {
        "markers": len(rows),
        "assumed_between_neighbours_s": [time for time, _v, _h, status in rows if status == "assumed_between_neighbours"],
        "not_read_s": [time for time, value, _h, _s in rows if value is None],
        "peak": {"value_g_m2_s": table["peak"][0], "t_s": table["peak"][1]},
        "end_of_fall_s": fall,
        "main_kg_m2": main,
        "total_kg_m2": central[-1],
        "tail_kg_m2": central[-1] - main if main is not None else None,
        "reading_half_width_kg_m2": spread[-1],
        "last_marker_s": times[-1],
        "accumulated_at": at,
    }


def immersion_confirmed_until(table, height_mm, margin_mm, density):
    """Last marker up to which the mass still places the surface above a thermocouple.

    The level is the mass left in the pan over the density declared at 25 C, with the lowest
    reading of the evaporated total and the highest of the accumulated mass. Thermal expansion
    would only raise the real level. The result depends on the mass and is declared so.
    """
    times, central, spread = table["times"], table["central"], table["spread"]
    fall = table["end_of_fall_s"]
    if fall not in times:
        return None
    lowest_total = central[times.index(fall)] - spread[-1]
    confirmed = None
    for time, acc, half in zip(times, central, spread):
        level = 1000.0 * (lowest_total - acc - half) / density
        if level >= height_mm + margin_mm:
            confirmed = time
        else:
            break
    return confirmed


def temperature_aggregates(curve, support_limit_c):
    """Start value, support exit and the highest reading of one thermocouple trace."""
    rows = _filled(curve["readings"])
    usable = [(time, value, half) for time, value, half, _status in rows if value is not None]
    inside = None
    for time, value, half in usable:
        if value + half <= support_limit_c:
            inside = (time, value, half)
        else:
            break
    plateau = [(time, value) for time, value, _half in usable if inside and time > inside[0] and abs(value - 98.5) <= 12.0]
    after = [(time, value) for time, value, _half in usable if plateau and time > plateau[-1][0]]
    values = {"%g" % time: {"value_c": value, "half_width_c": half} for time, value, half in usable}
    return {
        "start": {"t_s": usable[0][0], "value_c": usable[0][1], "half_width_c": usable[0][2]},
        "last_inside_support_s": inside[0] if inside else None,
        "highest_near_boiling_c": max(value for _t, value in plateau) if plateau else None,
        "plateau_s": [plateau[0][0], plateau[-1][0]] if plateau else None,
        "first_marker_after_plateau_s": after[0][0] if after else None,
        "readings": values,
    }


def aggregates_from_series(series, record):
    """Scalar aggregates of the local digitisation: the only part of it that is published."""
    present_series_as(series, "digitisation")
    step = series["method"]["marker_step_s"]
    limit = record["support"]["liquid_upper_k"] - KELVIN
    setup = record["setup"]
    density = setup["liquid_declared"]["density_kg_m3"]
    probes = setup["thermocouples"]
    margin = 0.5 * probes["bead_mm"]["value"]
    heights = {
        "upper": max([probes["upper_height_mm"]["value"]] + probes["upper_height_mm"].get("alternatives", [])),
        "lower": probes["lower_height_mm"]["value"],
    }
    runs = {}
    for run in record["corpus"]["runs"]:
        name = run["run"]
        entry = {"mass": None, "upper": None, "lower": None}
        mass = _curve(series, name, "mass_loss_rate_per_area")
        table = mass_table(mass, step) if mass else None
        checkpoints = set()
        for key, quantity in (("upper", "temperature_upper_centre"), ("lower", "temperature_lower_centre")):
            curve = _curve(series, name, quantity)
            if not curve:
                continue
            trace = temperature_aggregates(curve, limit)
            trace["immersion_confirmed_until_s"] = (
                immersion_confirmed_until(table, heights[key], margin, density) if table else None)
            ends = [trace["last_inside_support_s"], trace["immersion_confirmed_until_s"]]
            trace["usable_until_s"] = None if None in ends else min(ends)
            for moment in ends + [trace["usable_until_s"]]:
                if moment is not None:
                    checkpoints.add(moment)
            entry[key] = trace
        if table:
            entry["mass"] = mass_aggregates(table, sorted(checkpoints))
        for key in ("upper", "lower"):
            if entry[key]:
                keep = {"0"} | {"%g" % moment for moment in checkpoints}
                entry[key]["readings"] = {stamp: value for stamp, value in entry[key]["readings"].items() if stamp in keep}
        runs[name] = entry
    panels = {name: {"authors_vertical_line_s": panel["authors_vertical_line_s"],
                     "authors_horizontal_line": panel["authors_horizontal_line"],
                     "seconds_per_px": panel["seconds_per_px"], "units_per_px": panel["units_per_px"],
                     "marker_spacing_px": panel["marker_spacing_px"]}
              for name, panel in series["panels"].items()}
    return _rounded({
        "schema": AGGREGATES_SCHEMA,
        "nature": "scalar aggregates of a digitisation of published figures; not raw data",
        "series_sha256": series["series_sha256"],
        "document_sha256": series["source"]["document_sha256"],
        "marker_step_s": step,
        "immersion_rule": "level from the mass left over %g kg/m3; thermocouple heights %g and %g mm plus half a bead"
                          % (density, heights["lower"], heights["upper"]),
        "panels": panels,
        "runs": runs,
    })


def _rounded(value, digits=6):
    if isinstance(value, float):
        return round(value, digits)
    if isinstance(value, dict):
        return {key: _rounded(item, digits) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_rounded(item, digits) for item in value]
    return value


# ---------------------------------------------------------------------------------------------
# Balance
# ---------------------------------------------------------------------------------------------

def demand_per_kg_range(props, feed_c, surface_c):
    """Enthalpy to take 1 kg of liquid at the feed temperature to vapour leaving the surface.

    Both ends are evaluated inside the approved supports. The surface temperature is not
    measured; the range runs from the lowest gas temperature of the approved profile to the
    boiling point printed in the paper.
    """
    values = [net.demand_per_kg(props, celsius_to_kelvin(surface), celsius_to_kelvin(feed))
              for surface in surface_c for feed in feed_c]
    return [min(values), max(values)]


def storage_bracket(props, remaining_kg_m2, layers, feed_c, lower_c, upper_c, limit_c, density):
    """Sensible energy held by the remaining liquid, in kJ/m2, from two point temperatures.

    The liquid is split at the thermocouple heights. The bracket assumes that temperature does
    not decrease with height, which the two thermocouples do not prove. Its upper end fills the
    liquid above the highest immersed thermocouple at the upper end of the approved support and
    is conditional on that; nothing is evaluated outside the support.
    """
    liquid = props["liquid"]

    def rise(celsius):
        return (net.enthalpy(liquid, celsius_to_kelvin(celsius), "liquid temperature")
                - net.enthalpy(liquid, celsius_to_kelvin(feed_c), "feed temperature"))

    low_height, high_height = layers
    bottom = min(remaining_kg_m2, density * low_height / 1000.0)
    middle = min(remaining_kg_m2 - bottom, density * (high_height - low_height) / 1000.0)
    top = remaining_kg_m2 - bottom - middle
    if upper_c is None:
        low = middle * rise(lower_c) + top * rise(lower_c)
        high = bottom * rise(lower_c) + (middle + top) * rise(limit_c)
    else:
        low = middle * rise(lower_c) + top * rise(upper_c)
        high = bottom * rise(lower_c) + middle * rise(upper_c) + top * rise(limit_c)
    return {
        "kj_m2": [low, high],
        "layers_kg_m2": {"below_lower": bottom, "between": middle, "above_upper": top},
        "assumption": "temperature not decreasing with height; liquid above the upper thermocouple not above the support limit",
        "kind": "assumption_interval",
        "depends_on": ["mass", "temperature"],
    }


def pan_heat_capacity(setup):
    """Heat capacity of the steel pan per unit pool area, from the declared dimensions."""
    pan = setup["pan"]
    side = pan["inner_side_mm"]["value"] / 1000.0
    depth = pan["depth_mm"]["value"] / 1000.0
    wall = pan["wall_mm"]["value"] / 1000.0
    steel = setup["steel_simulation_properties"]
    per_area = steel["density_kg_m3"] * steel["cp_kj_kg_k"] * wall
    bottom = per_area
    walls = per_area * 4.0 * side * depth / (side * side)
    liquid = setup["charge"]["volume_ml"]["value"] * 1.0e-6 * setup["liquid_declared"]["density_kg_m3"] \
        * setup["liquid_declared"]["cp_kj_kg_k"] / (side * side)
    return {
        "bottom_kj_m2_k": bottom,
        "walls_kj_m2_k": walls,
        "pan_kj_m2_k": bottom + walls,
        "liquid_charge_kj_m2_k": liquid,
        "pan_over_liquid": (bottom + walls) / liquid,
        "class": "calculated",
        "note": "dimensions from the text and steel properties from the authors' simulation table; "
                "no pan temperature was measured, so the exchange with the liquid has no sign or size",
    }


def run_balance(name, entry, record, props, shape):
    """Diagnostic balance of one run. Everything here consumes the mass or the thermocouples."""
    setup = record["setup"]
    nominal = next(test["nominal_irradiation_kw_m2"] for test in record["tests"] if test["id"] == name)
    feed = list(record["balance"]["feed_temperature_c"])
    if entry.get("upper"):
        # The warmest liquid this run shows at its first marker closes the range from above.
        first = entry["upper"]["start"]
        feed[1] = min(feed[1], first["value_c"] + first["half_width_c"])
    surface = record["balance"]["surface_temperature_c"]
    density = setup["liquid_declared"]["density_kg_m3"]
    limit_c = record["support"]["liquid_upper_k"] - KELVIN
    mass = entry["mass"]
    out = {"nominal_irradiation_kw_m2": nominal, "depends_on": ["mass", "temperature"], "feed_temperature_c": feed}
    per_kg = demand_per_kg_range(props, feed, surface)
    half = mass["reading_half_width_kg_m2"]
    total = [mass["main_kg_m2"] - half, mass["total_kg_m2"] + half]
    charge = setup["charge"]["volume_ml"]["value"] * 1.0e-6 * density
    side_mm = setup["pan"]["inner_side_mm"]
    areas = [side * side * 1.0e-6 for side in [side_mm["value"]] + side_mm["alternatives"]]
    nominal_charge = [charge / max(areas), charge / min(areas)]
    out["mass"] = {
        "evaporated_kg_m2": total,
        "nominal_charge_kg_m2": nominal_charge,
        "evaporated_over_nominal_charge": [total[0] / nominal_charge[1], total[1] / nominal_charge[0]],
        "equivalent_initial_level_mm": [1000.0 * total[0] / density, 1000.0 * total[1] / density],
        "end_of_fall_s": mass["end_of_fall_s"],
        "tail_kg_m2": mass["tail_kg_m2"],
        "peak_g_m2_s": mass["peak"]["value_g_m2_s"],
    }
    out["thermocouples"] = {}
    for trace_key in ("upper", "lower"):
        trace = entry.get(trace_key)
        if trace:
            out["thermocouples"][trace_key] = {
                "start_c": trace["start"]["value_c"],
                "support_ends_s": trace["last_inside_support_s"],
                "immersion_confirmed_until_s": trace["immersion_confirmed_until_s"],
                "usable_until_s": trace["usable_until_s"],
                "highest_near_boiling_c": trace["highest_near_boiling_c"],
                "plateau_s": trace["plateau_s"],
                "leaves_plateau_s": trace["first_marker_after_plateau_s"],
                "leaves_plateau_minus_end_of_fall_s": None if trace["first_marker_after_plateau_s"] is None
                else trace["first_marker_after_plateau_s"] - mass["end_of_fall_s"],
            }
    end = mass["end_of_fall_s"]
    whole = [total[0] * per_kg[0], total[1] * per_kg[1]]
    out["whole_test"] = {
        "demand_kj_kg": per_kg,
        "demand_kj_m2": whole,
        "mean_demand_kw_m2": [whole[0] / end, whole[1] / end],
        "over_nominal": [whole[0] / (nominal * end), whole[1] / (nominal * end)],
        "storage_at_end_kj_m2": 0.0,
        "note": "the pan ends empty, so no stored energy has to be guessed; the surface temperature of the "
                "leaving vapour is not measured and spans the whole stated range",
        "role": "demand_diagnostic",
    }
    envelope = shape["mass_free_range"]["envelope"]
    out["whole_test"]["over_geometric_incident"] = [whole[0] / (nominal * end * envelope[1]),
                                                    whole[1] / (nominal * end * envelope[0])]
    out["windows"] = {}
    layers = [setup["thermocouples"]["lower_height_mm"]["value"], setup["thermocouples"]["upper_height_mm"]["value"]]
    for key, trace_key in (("first", "upper"), ("second", "lower")):
        trace = entry.get(trace_key)
        if not trace or trace["usable_until_s"] is None:
            out["windows"][key] = None
            continue
        moment = trace["usable_until_s"]
        if moment <= 0.0:
            out["windows"][key] = None
            continue
        stamp = "%g" % moment
        acc = mass["accumulated_at"][stamp]
        evaporated = [acc["block_starts_at_marker"] - acc["reading_half_width"],
                      acc["block_ends_at_marker"] + acc["reading_half_width"]]
        remaining = [total[0] - evaporated[1], total[1] - evaporated[0]]
        lower_c = entry["lower"]["readings"][stamp]["value_c"]
        upper_c = entry["upper"]["readings"][stamp]["value_c"] if key == "first" else None
        low = storage_bracket(props, remaining[0], layers, feed[1], lower_c, upper_c, limit_c, density)
        high = storage_bracket(props, remaining[1], layers, feed[0], lower_c, upper_c, limit_c, density)
        stored = [low["kj_m2"][0], high["kj_m2"][1]]
        emitted = [evaporated[0] * per_kg[0], evaporated[1] * per_kg[1]]
        demand = [stored[0] + emitted[0], stored[1] + emitted[1]]
        incident_nominal = nominal * moment
        out["windows"][key] = {
            "ends_s": moment,
            "ends_because": "last marker at which the %s thermocouple stays inside the liquid support "
                            "and the mass still places the surface above it" % trace_key,
            "support_ends_s": trace["last_inside_support_s"],
            "immersion_confirmed_until_s": trace["immersion_confirmed_until_s"],
            "lower_thermocouple_c": lower_c,
            "upper_thermocouple_c": upper_c,
            "evaporated_kg_m2": evaporated,
            "remaining_kg_m2": remaining,
            "remaining_level_mm": [1000.0 * remaining[0] / density, 1000.0 * remaining[1] / density],
            "stored_kj_m2": stored,
            "stored_kind": "assumption_interval",
            "emitted_kj_m2": emitted,
            "demand_kj_m2": demand,
            "nominal_irradiation_kj_m2": incident_nominal,
            "demand_over_nominal": [demand[0] / incident_nominal, demand[1] / incident_nominal],
            "demand_relative_width": (demand[1] - demand[0]) / (0.5 * (demand[1] + demand[0])),
            "geometric_relative_width": (envelope[1] - envelope[0]) / (0.5 * (envelope[1] + envelope[0])),
        }
        row = out["windows"][key]
        row["discriminates_thermal_input"] = row["demand_relative_width"] < row["geometric_relative_width"]
    return out


def peak_discrepancy(record, shape):
    """What the comparison of peak rates in the paper does and does not separate."""
    table = record["authors_peak_comparison"]
    latent = record["setup"]["liquid_declared"]["latent_kj_kg"]
    base = shape["by_side_mm"]["%g" % record["setup"]["pan"]["inner_side_mm"]["value"]]["empty"]
    reflectivity = record["setup"]["reflectivity_assumed"]["value"]
    rows = []
    for row in table["n_heptane"]:
        nominal, measured = row["nominal_kw_m2"], row["measured_g_m2_s"]
        estimate = 1000.0 * nominal / latent
        cases = {
            "nominal": estimate,
            "authors_factor": estimate * record["setup"]["authors_view_factor"]["end"],
            "area_average_open": estimate * base["area_average_open"],
            "area_average_with_rim": estimate * base["area_average_with_rim"],
        }
        residual = {key: measured / value - 1.0 for key, value in cases.items()}
        reflected = {key: measured / (value * (1.0 - reflectivity)) - 1.0 for key, value in cases.items()}
        rows.append({
            "nominal_kw_m2": nominal,
            "measured_g_m2_s": measured,
            "estimate_g_m2_s": cases,
            "deviation": residual,
            "deviation_with_assumed_reflection": reflected,
            "printed_deviation": row["printed_deviation"],
            "printed_reproduced": abs(residual["nominal"] - row["printed_deviation"]) <= 0.01,
        })
    signs = {row["nominal_kw_m2"]: sorted({1 if value > 0 else -1 for value in list(row["deviation"].values())
                                            + list(row["deviation_with_assumed_reflection"].values())}) for row in rows}
    return {
        "compares": "peak of the 15 s mean mass loss rate against nominal irradiation over the latent heat alone",
        "rows": rows,
        "residual_changes_sign_with_geometry": {"%g" % key: value == [-1, 1] for key, value in signs.items()},
        "causes": record["discrepancy"]["causes"],
        "discriminates_energy_from_transfer": False,
        "reason": "the residual moves from about -45 % to about +10 % with geometric and optical treatments "
                  "that were not measured; vapour accumulation was proposed, not measured",
    }


# ---------------------------------------------------------------------------------------------
# Decisions
# ---------------------------------------------------------------------------------------------

def decide(facts):
    """Five separate decisions. Each reads only its own facts."""
    out = {}
    out["observables_eligibility"] = (
        "GO_partial_digitised_mass_and_two_point_temperatures"
        if facts["mass_curves"] and facts["point_temperatures"] and not facts["raw_series_public"]
        else ("GO" if facts["raw_series_public"] else "NO_GO")
    )
    if facts["in_test_irradiation_measured"]:
        out["incident_irradiation"] = "GO"
    elif facts["nominal_checked_before_test"] and facts["geometric_range_calculated"]:
        out["incident_irradiation"] = "GO_partial_nominal_set_point_and_calculated_geometric_range"
    else:
        out["incident_irradiation"] = "NO_GO"
    out["net_absorbed_heat"] = "GO" if facts["frontier_identified"] else "NO_GO_not_identified"
    if facts["temperature_profile_measured"] and facts["frontier_identified"]:
        out["heating_validation"] = "GO"
    elif facts["point_temperatures"] and facts["windows_inside_support"] and facts["lower_thermocouple_usable_runs"]:
        out["heating_validation"] = "GO_partial_lower_point_temperature_inside_support_NO_GO_energy_mean_and_surface_temperature"
    else:
        out["heating_validation"] = "NO_GO"
    if facts["frontier_identified"] and facts["initial_mass_reported"] and facts["gas_side_measured"]:
        out["emission_validation"] = "GO"
    else:
        out["emission_validation"] = "NO_GO_no_independent_thermal_input"
    return out


def audit(record=None, aggregates=None, root=ROOT):
    record = record if record is not None else json.loads(INPUT.read_text(encoding="utf-8"))
    aggregates = aggregates if aggregates is not None else json.loads(AGGREGATES.read_text(encoding="utf-8"))
    if record.get("schema") != SCHEMA:
        raise ValueError("unknown record schema")
    if aggregates.get("schema") != AGGREGATES_SCHEMA:
        raise ValueError("unknown aggregates schema")
    present_series_as(aggregates, "digitisation")
    if aggregates["series_sha256"] != record["digitisation"]["series_sha256"]:
        raise ValueError("the aggregates do not come from the digitisation named by the record")
    for path, item in walk_classified(record["setup"]):
        require_class(item["class"], path)
    for test in record["tests"]:
        for key, item in test["fields"].items():
            require_class(item["class"], "%s.%s" % (test["id"], key))
    props = net.properties(root)
    support = record["support"]
    liquid_low, liquid_high = props["liquid"][0]["temperature_k"], props["liquid"][-1]["temperature_k"]
    gas_low, gas_high = props["gas"][0]["temperature_k"], props["gas"][-1]["temperature_k"]
    if abs(liquid_high - support["liquid_upper_k"]) > 1.0e-6 or abs(liquid_low - support["liquid_lower_k"]) > 1.0e-6:
        raise ValueError("the record does not state the approved liquid support")
    boiling_k = celsius_to_kelvin(record["setup"]["liquid_declared"]["boiling_c"])
    shape = geometry(record["setup"])
    frontier = frontier_status(record["frontier_terms"])
    balances = {}
    for run in record["corpus"]["runs"]:
        entry = aggregates["runs"][run["run"]]
        balances[run["run"]] = run_balance(run["run"], entry, record, props, shape)
    by_level = {}
    for name, balance in balances.items():
        by_level.setdefault("%g" % balance["nominal_irradiation_kw_m2"], []).append(name)
    summary = {}
    for level, names in by_level.items():
        first = [balances[name]["windows"]["first"] for name in names if balances[name]["windows"]["first"]]
        second = [balances[name]["windows"]["second"] for name in names if balances[name]["windows"]["second"]]
        windows = first + second
        upper = [aggregates["runs"][name]["upper"] for name in names if aggregates["runs"][name]["upper"]]
        lower = [aggregates["runs"][name]["lower"] for name in names if aggregates["runs"][name]["lower"]]
        summary[level] = {
            "runs": names,
            "evaporated_kg_m2": [min(balances[n]["mass"]["evaporated_kg_m2"][0] for n in names),
                                 max(balances[n]["mass"]["evaporated_kg_m2"][1] for n in names)],
            "whole_test_over_nominal": [min(balances[n]["whole_test"]["over_nominal"][0] for n in names),
                                        max(balances[n]["whole_test"]["over_nominal"][1] for n in names)],
            "first_window_over_nominal": [min(w["demand_over_nominal"][0] for w in first),
                                          max(w["demand_over_nominal"][1] for w in first)] if first else None,
            "first_window_discriminates": any(w["discriminates_thermal_input"] for w in first) if first else None,
            "second_window_over_nominal": [min(w["demand_over_nominal"][0] for w in second),
                                           max(w["demand_over_nominal"][1] for w in second)] if second else None,
            "any_window_discriminates": any(w["discriminates_thermal_input"] for w in windows),
            "mean_demand_kw_m2": [min(balances[n]["whole_test"]["mean_demand_kw_m2"][0] for n in names),
                                  max(balances[n]["whole_test"]["mean_demand_kw_m2"][1] for n in names)],
            "upper_start_c": [min(t["start"]["value_c"] for t in upper), max(t["start"]["value_c"] for t in upper)],
            "lower_start_c": [min(t["start"]["value_c"] for t in lower), max(t["start"]["value_c"] for t in lower)],
            "lower_highest_near_boiling_c": max(t["highest_near_boiling_c"] for t in lower),
        }
    mains = [aggregates["runs"][name]["mass"]["main_kg_m2"] for name in balances]
    spread = max(mains) / min(mains) - 1.0
    usable = {"upper": {}, "lower": {}}
    for name, balance in balances.items():
        for key, trace in balance["thermocouples"].items():
            usable[key][name] = trace["usable_until_s"]
    any_window = [w for balance in balances.values() for w in balance["windows"].values() if w]
    facts = {
        "mass_curves": all(aggregates["runs"][run["run"]]["mass"] for run in record["corpus"]["runs"]),
        "point_temperatures": any(aggregates["runs"][run["run"]]["upper"] for run in record["corpus"]["runs"]),
        "raw_series_public": record["source"]["public_data"]["raw_series_located"],
        "in_test_irradiation_measured": record["thermal_input"]["in_test_irradiation_measured"],
        "nominal_checked_before_test": record["thermal_input"]["nominal_checked_before_test"],
        "geometric_range_calculated": shape["quadrature_error"] < 0.005,
        "frontier_identified": frontier["identified"],
        "temperature_profile_measured": record["setup"]["thermocouples"]["profile_measured"],
        "windows_inside_support": bool(any_window),
        "upper_thermocouple_usable_runs": sorted(name for name, end in usable["upper"].items() if end),
        "lower_thermocouple_usable_runs": sorted(name for name, end in usable["lower"].items() if end),
        "initial_mass_reported": record["setup"]["charge"]["initial_mass_per_run"]["class"] == "measured",
        "gas_side_measured": record["thermal_input"]["gas_side_measured"],
    }
    decisions = decide(facts)
    result = {
        "schema": AUDIT_SCHEMA,
        "record_sha256": hashlib.sha256(json.dumps(record, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest(),
        "series_sha256": aggregates["series_sha256"],
        "nature_of_series": "digitisation of published figures; not raw data",
        "objects": record["objects"],
        "support": {
            "liquid_k": [liquid_low, liquid_high],
            "gas_k": [gas_low, gas_high],
            "boiling_point_printed_k": boiling_k,
            "boiling_point_inside_liquid_support": liquid_low <= boiling_k <= liquid_high,
            "initial_temperature_inside_liquid_support": all(
                liquid_low <= celsius_to_kelvin(t) <= liquid_high for t in record["balance"]["feed_temperature_c"]),
            "consequence": "the plateau of the thermocouples lies outside the liquid support; the windows end before it",
        },
        "geometry": shape,
        "pan": pan_heat_capacity(record["setup"]),
        "frontier": frontier,
        "runs": balances,
        "usable_temperature_stretch_s": usable,
        "by_irradiation_level": summary,
        "repeatability": {
            "evaporated_main_kg_m2": [min(aggregates["runs"][n]["mass"]["main_kg_m2"] for n in balances),
                                      max(aggregates["runs"][n]["mass"]["main_kg_m2"] for n in balances)],
            "evaporated_mass_spread_between_runs": spread,
            "initial_mass_reported": facts["initial_mass_reported"],
            "consequence": "the level history of each run, and with it the depth of the upper thermocouple, is not identified",
        },
        "peak_discrepancy": peak_discrepancy(record, shape),
        "digitisation_check": {
            "printed_peaks_g_m2_s": {"%g" % row["nominal_kw_m2"]: row["measured_g_m2_s"]
                                     for row in record["authors_peak_comparison"]["n_heptane"]},
            "digitised_peaks_g_m2_s": {level: max(balances[n]["mass"]["peak_g_m2_s"] for n in names)
                                       for level, names in by_level.items()},
            "boiling_line_read_c": sorted({line for panel in aggregates["panels"].values()
                                           for line in panel["authors_horizontal_line"]}),
            "boiling_line_printed_c": record["setup"]["liquid_declared"]["boiling_c"],
        },
        "uncertainty": {
            "instrument": None,
            "between_runs": "reported only as the spread visible in the figures",
            "reading": "bitmap resolution of the digitisation, stated per reading",
            "combined": combined_uncertainty([None]),
        },
        "facts": facts,
        "decisions": decisions,
        "b_net": "NO_GO_not_identified",
        "sim_implementation": "not_authorised",
        "co_fed": "OFF_NO_GO",
    }
    return _rounded(result)


def walk_classified(node, path="setup"):
    """Every item of the set-up that carries a class."""
    if isinstance(node, dict):
        if "class" in node:
            yield path, node
        for key, value in node.items():
            if isinstance(value, (dict, list)):
                yield from walk_classified(value, "%s.%s" % (path, key))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk_classified(value, "%s[%d]" % (path, index))


def recompute_aggregates(record=None):
    """Aggregates from the local digitisation, or None when this checkout does not hold it."""
    record = record if record is not None else json.loads(INPUT.read_text(encoding="utf-8"))
    series = digitiser.load_series()
    if series is None:
        return None
    return aggregates_from_series(series, record)


def _dump(value):
    return json.dumps(value, indent=1, ensure_ascii=False, sort_keys=True) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="compare with the saved audit and aggregates")
    parser.add_argument("--write-aggregates", action="store_true", help="rebuild the aggregates from the local digitisation")
    parser.add_argument("--write", action="store_true", help="save the audit")
    args = parser.parse_args()
    if args.write_aggregates:
        fresh = recompute_aggregates()
        if fresh is None:
            print("no local digitisation: run digitise_g3_cone_benchmark_figures first")
            return 1
        AGGREGATES.write_text(_dump(fresh), encoding="utf-8", newline="\n")
        print("written", AGGREGATES)
    result = audit()
    if args.write:
        SAVED.write_text(_dump(result), encoding="utf-8", newline="\n")
        print("written", SAVED)
    if args.check:
        fresh = recompute_aggregates()
        status = {
            "audit_matches_saved": result == json.loads(SAVED.read_text(encoding="utf-8")),
            "aggregates_match_local_digitisation": None if fresh is None
            else fresh == json.loads(AGGREGATES.read_text(encoding="utf-8")),
        }
        if fresh is None:
            status["note"] = "no local digitisation in this checkout: the aggregates were not recomputed"
        print(json.dumps(status, indent=1))
        return 0 if status["audit_matches_saved"] and status["aggregates_match_local_digitisation"] in (True, None) else 1
    if not args.write and not args.write_aggregates:
        print(_dump(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
