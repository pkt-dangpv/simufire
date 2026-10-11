"""Audit object-scale fire tests as prescribed experimental sources.

Offline: no Godot, no engine module, no fitted parameter and no fire model. The auditor
checks provenance, units and support of the published series, rebuilds the curves and the
integrals that the data justify, and refuses the confusions the contract must not allow: a
mass loss rate presented as measured when it is HRR over a heat of combustion, an integrated
yield used as an instantaneous law, a test of a fuel set assigned to one of its items, runs,
versions or units mixed, a missing reading taken as zero, and a reserved run used to fit.

Reproducing a prescribed curve is not predicting it. Nothing here validates the engine.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics
import zipfile

from scripts.simulation import compare_g3_nist_co_processing as fcd

ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "docs" / "validation" / "G3_OBJECT_FIRE_SOURCE_INPUTS_2026-10-07.json"
SAVED = ROOT / "docs" / "validation" / "G3_OBJECT_FIRE_SOURCE_AUDIT_2026-10-07.json"
LOCAL_AGGREGATES = ROOT / "docs" / "validation" / "G3_OBJECT_FIRE_SOURCE_LOCAL_AGGREGATES_2026-10-07.json"
PAGES_ZIP = ROOT / "docs" / "literature" / "NIST" / "FCD_DesignFires_Test001-048_pages_retrieved_2026-09-29.zip"
LOCAL_FSRI = ROOT / "runs" / "literature_local" / "fsri_materials_database_a432697e"

SCHEMA = "g3_object_fire_source_selection_v1"
TABLE_SCHEMA = "g3_prescribed_object_hrr_table_v1"
FCD_COLUMNS = {
    "Time (s)": "s",
    "Heat Release Rate (kW)": "kW",
    "Burner HRR (kW)": "kW",
    "Exhaust Mass Flow Rate (kg/s)": "kg/s",
    "Oxygen (Vol Fr)": "1",
    "CO2 (Vol Fr)": "1",
    "CO (Vol Fr)": "1",
    "Radiant Heat Flux (kW/m^2)": "kW/m2",
    "Ksmoke (1/m)": "1/m",
}
FSRI_COLUMNS = ("Time (s)", "Load Cell", "Heat Release Rate", "Total Heat Released")
SPECIES = {
    "co": ("CO (Vol Fr)", 28.01, 1.0),
    "co2": ("CO2 (Vol Fr)", 44.01, 1.0),
    "o2": ("Oxygen (Vol Fr)", 32.00, -1.0),
}
M_AIR = fcd.M_AIR_KG_PER_KMOL
M_CARBON = 12.011
CLASSES = ("measured", "calculated", "assumed", "nominal", "unknown")
STATES = ("value", "zero", "below_detection", "absent", "unknown")
OBSERVABLES = ("prescribed_hrr", "prescribed_mass_loss", "energy_and_effective_heat",
               "species_emission", "temporal_species_yield", "extrapolation")
UNITS = {
    "time": {"s": 1.0, "min": 60.0},
    "power": {"kW": 1.0, "W": 1.0e-3, "MW": 1.0e3},
    "mass": {"kg": 1.0, "g": 1.0e-3},
    "energy": {"MJ": 1.0, "kJ": 1.0e-3},
}


class Refusal(ValueError):
    """The request mixes things the contract keeps apart."""


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_record(path: Path = INPUT) -> dict:
    record = json.loads(path.read_text(encoding="utf-8"))
    if record.get("schema") != SCHEMA:
        raise Refusal("unsupported record schema")
    return record


# ---------------------------------------------------------------- readings and units

def reading(printed: object) -> dict:
    """Classify one printed cell. Absent, unknown, below detection and zero stay apart."""
    if printed is None:
        return {"state": "unknown", "value": None}
    text = str(printed).strip()
    if text == "":
        return {"state": "unknown", "value": None}
    low = text.lower()
    if "below detection" in low:
        return {"state": "below_detection", "value": None}
    if low in ("not measured", "-", "nan", "not in file"):
        return {"state": "absent", "value": None}
    try:
        value = float(text.replace(",", ""))
    except ValueError:
        return {"state": "unknown", "value": None}
    if not math.isfinite(value):
        return {"state": "absent", "value": None}
    return {"state": "zero" if value == 0.0 else "value", "value": value}


def as_number(item: dict, label: str = "reading") -> float:
    if item.get("state") not in ("value", "zero"):
        raise Refusal("%s is %s, not a number: it cannot stand for zero" % (label, item.get("state")))
    return float(item["value"])


def convert(value: float, unit: str, kind: str) -> float:
    """To s, kW, kg or MJ. An undeclared or foreign unit is refused, never guessed."""
    table = UNITS.get(kind)
    if table is None or unit not in table:
        raise Refusal("unit %r is not a declared %s unit" % (unit, kind))
    return float(value) * table[unit]


def require_same(items: list[dict], key: str) -> str:
    """All the pieces of one quantity must share run or version."""
    found = {item.get(key) for item in items}
    if None in found or len(found) != 1:
        raise Refusal("mixed or undeclared %s: %s" % (key, sorted(str(x) for x in found)))
    return found.pop()


def require_class(item: dict, allowed: tuple[str, ...], label: str) -> None:
    if item.get("class") not in CLASSES:
        raise Refusal("%s has no declared class" % label)
    if item["class"] not in allowed:
        raise Refusal("%s is %s, not %s" % (label, item["class"], " or ".join(allowed)))


def present_as(quantity: dict, claimed: str) -> dict:
    """A calculated or assumed quantity cannot be relabelled as measured."""
    if quantity.get("class") != claimed:
        raise Refusal("%s is %s and cannot be presented as %s"
                      % (quantity.get("name", "the quantity"), quantity.get("class"), claimed))
    return quantity


# ---------------------------------------------------------------- archived pages

def _cells(test_id: str) -> list[str]:
    with zipfile.ZipFile(PAGES_ZIP) as archive:
        return fcd._page_cells(archive.read(test_id.lower() + ".html"))


def _rows(cells: list[str], start: str, header: int, width: int, stop: str) -> list[list[str]]:
    begin = cells.index(start) + 1 + header
    end = next(i for i in range(begin, len(cells)) if cells[i].startswith(stop))
    block = cells[begin:end]
    return [block[i:i + width] for i in range(0, len(block) - width + 1, width)]


def fcd_page(test_id: str) -> dict:
    """Read the information, results, inputs and events of one archived FCD page."""
    cells = _cells(test_id)
    start = cells.index("Table 1.")
    info = {}
    for key in ("Name", "Date", "Description", "Specimen", "Ignition"):
        info[key.lower()] = cells[cells.index(key, start) + 1]
    results = {row[0]: {"printed": row[1], "uc_printed": row[2], "unit": row[3]}
               for row in _rows(cells, "Table 2.", 5, 4, "Uc = Combined")}
    inputs = {row[0]: {"printed": row[1], "uc_printed": row[2], "unit": row[3]}
              for row in _rows(cells, "Table 3.", 5, 4, "Figure 1.")}
    events = [{"label": row[0], "time_min": float(row[1]), "description": row[2].strip()}
              for row in _rows(cells, "Table 4.", 5, 3, "Table 5.")]
    joined = " | ".join(cells)
    script = [cell for cell in cells if cell.startswith("NFRL_Report_")]
    updated = [cell for cell in cells if cell.startswith("Last Updated")]
    return {
        "test_id": info["name"], "info": info, "results": results, "inputs": inputs, "events": events,
        "report_process_script": script[0] if script else None,
        "last_updated": updated[0].replace("Last Updated ", "") if updated else None,
        "data_doi_printed": "https://doi.org/10.18434/mds2-2314" in joined,
    }


def page_value(page: dict, table: str, prefix: str) -> dict:
    """One printed row as value, uncertainty and unit, with its state kept."""
    for name, row in page[table].items():
        if name.startswith(prefix):
            out = reading(row["printed"])
            out["uc"] = reading(row["uc_printed"])["value"]
            out["unit"] = row["unit"]
            out["name"] = name
            return out
    raise Refusal("the page has no row %r" % prefix)


def event_time_s(page: dict, description: str, last: bool = False) -> int:
    found = [event for event in page["events"] if description.lower() in event["description"].lower()]
    if not found:
        raise Refusal("the page records no event %r" % description)
    return round(convert((found[-1] if last else found[0])["time_min"], "min", "time"))


# ---------------------------------------------------------------- series

def load_fcd_series(test: dict) -> dict:
    """The published 1 Hz series of one run, bytes pinned, header and axis checked."""
    path = ROOT / test["csv"]["path"]
    digest = sha256_file(path)
    if digest != test["csv"]["sha256"]:
        raise Refusal("%s bytes changed: %s" % (test["csv"]["path"], digest))
    with path.open(newline="", encoding="utf-8-sig") as source:
        reader = csv.DictReader(source)
        if tuple(reader.fieldnames or ()) != tuple(FCD_COLUMNS):
            raise Refusal("%s columns or units changed" % test["csv"]["path"])
        rows = list(reader)
    times = [int(row["Time (s)"]) for row in rows]
    if times != list(range(times[0], times[-1] + 1)):
        raise Refusal("%s time axis is not contiguous at 1 s" % test["csv"]["path"])
    columns, absent = {}, {}
    for name in list(FCD_COLUMNS)[1:]:
        values = []
        for row in rows:
            item = reading(row[name])
            values.append(item["value"])
        columns[name] = values
        missing = [t for t, v in zip(times, values) if v is None]
        if missing:
            absent[name] = missing
    return {"run_id": test["run_id"], "version": test["version"], "times": times,
            "columns": columns, "absent": absent, "sha256": digest}


def window(series: dict, column: str, start: int, end: int) -> list[tuple[int, float]]:
    """Samples of one column inside a window. A missing sample is refused, not zeroed."""
    times = series["times"]
    if start < times[0] or end > times[-1] or end < start:
        raise Refusal("window %s..%s is outside the support %s..%s" % (start, end, times[0], times[-1]))
    out = []
    for t, value in zip(times, series["columns"][column]):
        if start <= t <= end:
            if value is None:
                raise Refusal("%s has no reading at %d s: absent is not zero" % (column, t))
            out.append((t, value))
    return out


def integral_MJ(series: dict, start: int, end: int, column: str = "Heat Release Rate (kW)") -> float:
    """Sum of the 1 Hz samples times one second: the rule that returns the page totals."""
    return sum(value for _t, value in window(series, column, start, end)) / 1000.0


def species_net_kg(series: dict, species: str, start: int, end: int, background=(-60, -1)) -> dict:
    """Net species mass through the exhaust duct, user-guide method, own reconstruction."""
    column, molar, sign = SPECIES[species]
    ambient = statistics.mean(v for _t, v in window(series, column, background[0], background[1]))
    flow = dict(window(series, "Exhaust Mass Flow Rate (kg/s)", start, end))
    total = sum(sign * (value - ambient) * flow[t] * molar / M_AIR
                for t, value in window(series, column, start, end))
    return {"name": "net %s in the exhaust" % species, "class": "calculated", "kg": total,
            "ambient_fraction": ambient, "location": "exhaust duct, not the object surface",
            "run_id": series["run_id"], "version": series["version"]}


# ---------------------------------------------------------------- prescribed table

def prescribed_table(test: dict, series: dict, owner_id: str) -> dict:
    """The measured HRR of one run as a table an isolated source could replay.

    Support: ignition to fire out, the window of the published totals. Negative samples are
    noise of the calorimeter, not a heat sink; they are clipped to zero and the bias is
    reported. Nothing is smoothed, shifted or scaled.
    """
    require_same([test, series], "run_id")
    require_same([test, series], "version")
    start, end = test["events"]["ignition_s"], test["events"]["fire_out_s"]
    raw = window(series, "Heat Release Rate (kW)", start, end)
    samples = [[float(t - start), max(0.0, value)] for t, value in raw]
    signed = sum(value for _t, value in raw) / 1000.0
    body = {
        "schema": TABLE_SCHEMA, "owner_id": owner_id, "run_id": test["run_id"],
        "version": test["version"], "source_sha256": series["sha256"],
        "quantity": "measured_calorimetric_hrr", "unit": "kW",
        "time_origin": "ignition event of the source page", "interpolation": "piecewise_linear",
        "outside_support": "reject", "negative_samples": "clipped_to_zero", "samples": samples,
    }
    text = json.dumps(body, sort_keys=True, separators=(",", ":"))
    out = dict(body)
    out["fingerprint"] = hashlib.sha256(text.encode("utf-8")).hexdigest()
    out["class"] = "measured"
    out["signed_sum_MJ"] = signed
    out["clip_bias_MJ"] = sum(v for _t, v in samples) / 1000.0 - signed
    out["negative_samples_count"] = sum(1 for _t, value in raw if value < 0.0)
    return out


def evaluate(table: dict, time_s: float) -> float:
    """HRR of the table at a time since ignition. Outside the support it is refused."""
    samples = table["samples"]
    if not samples[0][0] <= time_s <= samples[-1][0]:
        raise Refusal("%.3f s is outside the support %.0f..%.0f s" % (time_s, samples[0][0], samples[-1][0]))
    low = min(int(math.floor(time_s - samples[0][0])), len(samples) - 2)
    (t0, q0), (t1, q1) = samples[low], samples[low + 1]
    return q0 + (q1 - q0) * (time_s - t0) / (t1 - t0)


def table_energy_MJ(table: dict, start_s: float | None = None, end_s: float | None = None) -> float:
    """Trapezoidal energy of the table between two times inside its support."""
    samples = table["samples"]
    start = samples[0][0] if start_s is None else start_s
    end = samples[-1][0] if end_s is None else end_s
    if start < samples[0][0] or end > samples[-1][0] or end < start:
        raise Refusal("interval outside the support of the table")
    total = 0.0
    for (t0, _q0), (t1, _q1) in zip(samples, samples[1:]):
        lo, hi = max(start, t0), min(end, t1)
        if hi > lo:
            total += 0.5 * (evaluate(table, lo) + evaluate(table, hi)) * (hi - lo)
    return total / 1000.0


def within(value: float, printed: dict) -> bool:
    """Inside the published expanded uncertainty of a printed value."""
    if printed["uc"] is None:
        raise Refusal("%s has no published uncertainty to compare against" % printed.get("name", "value"))
    return abs(value - as_number(printed)) <= printed["uc"]


def reproduction(table: dict, page: dict) -> dict:
    """Does the rebuilt curve return the peak, its time and the total of the page?"""
    peak_t, peak = max(table["samples"], key=lambda sample: sample[1])
    printed_peak = page_value(page, "results", "Peak Heat Release Rate")
    printed_time = page_value(page, "results", "Time to Peak")
    printed_thr = page_value(page, "results", "Total Heat Released")
    energy = table_energy_MJ(table)
    return {
        "peak_kW": peak, "peak_printed_kW": as_number(printed_peak), "peak_uc_kW": printed_peak["uc"],
        "peak_inside_uc": within(peak, printed_peak),
        "time_to_peak_s": peak_t,
        "time_to_peak_printed_s": convert(as_number(printed_time), printed_time["unit"], "time"),
        "time_to_peak_inside_uc": within(peak_t / 60.0, printed_time),
        "energy_MJ": energy, "thr_printed_MJ": as_number(printed_thr), "thr_uc_MJ": printed_thr["uc"],
        "energy_inside_uc": within(energy, printed_thr),
        "signed_sum_MJ": table["signed_sum_MJ"], "clip_bias_MJ": table["clip_bias_MJ"],
        "clip_bias_over_uc": table["clip_bias_MJ"] / printed_thr["uc"],
        "negative_samples": table["negative_samples_count"], "samples": len(table["samples"]),
        "what_it_is": "verification that the table returns the run it was built from, not validation",
    }


# ---------------------------------------------------------------- guards

def mass_rate_from_hrr(hrr_kw: float, effective_heat_mj_kg: float) -> dict:
    """HRR over an effective heat is a calculation. It is never a measured mass loss rate."""
    if effective_heat_mj_kg <= 0.0:
        raise Refusal("an effective heat of combustion must be positive")
    return {"name": "mass loss rate from HRR over effective heat", "class": "calculated",
            "kg_s": hrr_kw / (effective_heat_mj_kg * 1000.0),
            "depends_on": ["heat release rate", "whole-test effective heat"]}


def instantaneous_yield(integrated: dict, time_s: float) -> float:  # always refuses
    """A whole-test yield is one number for one window; it is not a law in time."""
    raise Refusal("a yield integrated over %s cannot be evaluated at %.0f s"
                  % (integrated.get("basis", "an undeclared window"), time_s))


def assign_source(candidate: dict, target_owner: str) -> str:
    """A test belongs to what was burnt, whole. It is not assigned to one of its parts."""
    if target_owner != candidate["owner_id"]:
        parts = candidate.get("inseparable_components", [])
        why = "its components %s cannot be separated" % parts if parts else "it is another object"
        raise Refusal("the test of %s cannot be assigned to %s: %s" % (candidate["owner_id"], target_owner, why))
    return candidate["source_run"]


def chemistry_for(candidate: dict, profile: dict) -> dict:
    """A chemistry profile is used only for the material it was approved for."""
    if profile.get("material_id") not in candidate.get("approved_chemistry_profiles", []):
        raise Refusal("%s is not an approved chemistry for %s; composition is %s"
                      % (profile.get("material_id"), candidate["owner_id"], candidate["composition"]["class"]))
    return profile


def use_for_fit(candidate: dict, run_id: str) -> str:
    """A run reserved for contrast is never used to choose a parameter."""
    if run_id in candidate.get("reserved_runs", []):
        raise Refusal("%s is reserved for contrast and cannot be used to fit" % run_id)
    if run_id != candidate["source_run"]:
        raise Refusal("%s is not a run of %s" % (run_id, candidate["owner_id"]))
    return run_id


def external_validation(candidate: dict, input_run: str, check_run: str, fitted_on: list[str]) -> str:
    """The curve that feeds a source cannot also prove that the source predicts."""
    if input_run == check_run:
        raise Refusal("%s is both the input and the check: that is reproduction, not prediction" % input_run)
    if check_run in fitted_on:
        raise Refusal("%s was used to fit and cannot be an external check" % check_run)
    if check_run not in candidate.get("reserved_runs", []):
        raise Refusal("%s is not a reserved run of %s" % (check_run, candidate["owner_id"]))
    return check_run


# ---------------------------------------------------------------- per-run analysis

def effective_heat(energy: dict, mass: dict) -> dict:
    """Whole-test energy over whole-test mass loss, both of the same run and version."""
    require_same([energy, mass], "run_id")
    require_same([energy, mass], "version")
    value = energy["MJ"] / mass["kg"]
    relative = math.hypot(energy["uc_MJ"] / energy["MJ"], mass["uc_kg"] / mass["kg"])
    return {"name": "whole-test effective heat", "class": "calculated", "MJ_kg": value,
            "uc_MJ_kg": value * relative, "basis": "ignition to fire out, one number per run",
            "run_id": energy["run_id"], "version": energy["version"]}


def energy_timeline(table: dict, fractions=(0.01, 0.10, 0.50, 0.90, 0.99)) -> dict:
    total = sum(q for _t, q in table["samples"])
    marks, running = {}, 0.0
    for t, q in table["samples"]:
        running += q
        for fraction in fractions:
            key = "%g" % fraction
            if key not in marks and running >= fraction * total:
                marks[key] = t
    return marks


def analyse_nist_run(test_id: str, record: dict) -> dict:
    """Everything the published data of one NIST run justify."""
    test = record["tests"][test_id]
    page = fcd_page(test_id)
    series = load_fcd_series(test)
    start, end = test["events"]["ignition_s"], test["events"]["fire_out_s"]
    if (event_time_s(page, "Ignition"), event_time_s(page, "Fire Out", last=True)) != (start, end):
        raise Refusal("%s events differ from the archived page" % test_id)
    table = prescribed_table(test, series, test["owner_id"])
    rebuilt = reproduction(table, page)
    printed_thr = page_value(page, "results", "Total Heat Released")
    printed_mass = page_value(page, "results", "Net Specimen Mass")
    energy = {"MJ": rebuilt["signed_sum_MJ"], "uc_MJ": printed_thr["uc"],
              "run_id": test["run_id"], "version": test["version"]}
    mass = {"kg": as_number(printed_mass, "net specimen mass"), "uc_kg": printed_mass["uc"],
            "run_id": test["run_id"], "version": test["version"]}
    heat = effective_heat(energy, mass)
    printed_heat = page_value(page, "results", "Net Effective Heat of Combustion")
    species = {}
    carbon = 0.0
    for name in SPECIES:
        net = species_net_kg(series, name, start, end)
        label = {"co": "CO Yield", "co2": "CO2 Yield", "o2": "O2 Yield"}[name]
        printed = page_value(page, "results", label)
        value = net["kg"] / mass["kg"]
        species[name] = {"net_kg": net["kg"], "ambient_fraction": net["ambient_fraction"],
                         "yield_kg_kg": value, "printed_kg_kg": as_number(printed), "uc_kg_kg": printed["uc"],
                         "inside_uc": within(value, printed), "basis": "whole test, exhaust duct"}
        if name != "o2":
            carbon += net["kg"] * M_CARBON / SPECIES[name][1]
    igniter = test["igniter"]
    igniter_MJ = convert(igniter["energy_kJ"], "kJ", "energy")
    pre = [v for _t, v in window(series, "Heat Release Rate (kW)", series["times"][0], start - 1)]
    burner = [v for _t, v in window(series, "Burner HRR (kW)", series["times"][0], start - 1)]
    return {
        "run_id": test["run_id"], "version": test["version"], "owner_id": test["owner_id"],
        "support_s": [series["times"][0], series["times"][-1]], "absent_samples": series["absent"],
        "table_fingerprint": table["fingerprint"], "reproduction": rebuilt,
        "energy_timeline_s": energy_timeline(table),
        "energy_after_fire_out_MJ": sum(v for t, v in zip(series["times"], series["columns"]["Heat Release Rate (kW)"])
                                        if t > end and v is not None) / 1000.0,
        "pre_ignition_hrr_kW": {"mean": statistics.mean(pre), "sd": statistics.pstdev(pre)},
        "burner_channel_before_ignition_kW": statistics.mean(burner),
        "effective_heat": {"MJ_kg": heat["MJ_kg"], "uc_MJ_kg": heat["uc_MJ_kg"],
                           "printed_MJ_kg": as_number(printed_heat), "printed_uc_MJ_kg": printed_heat["uc"],
                           "inside_uc": within(heat["MJ_kg"], printed_heat), "basis": heat["basis"]},
        "mass_lost_kg": mass["kg"], "mass_lost_uc_kg": mass["uc_kg"],
        "species": species,
        "carbon_in_co_and_co2_per_kg_lost": carbon / mass["kg"],
        "igniter_over_thr": igniter_MJ / rebuilt["signed_sum_MJ"],
        "igniter_power_over_pre_ignition_noise": convert(igniter["power_W"], "W", "power") / statistics.pstdev(pre),
    }


def replicate_contrast(first: dict, second: dict) -> dict:
    """Two runs of what the source calls the same item, compared as published."""
    def gap(a: float, ua: float, b: float, ub: float) -> dict:
        combined = math.hypot(ua, ub)
        return {"first": a, "second": b, "difference": b - a, "relative": (b - a) / a,
                "combined_uc": combined, "beyond_combined_uc": abs(b - a) > combined}
    ra, rb = first["reproduction"], second["reproduction"]
    out = {
        "runs": [first["run_id"], second["run_id"]],
        "peak_kW": gap(ra["peak_printed_kW"], ra["peak_uc_kW"], rb["peak_printed_kW"], rb["peak_uc_kW"]),
        "thr_MJ": gap(ra["thr_printed_MJ"], ra["thr_uc_MJ"], rb["thr_printed_MJ"], rb["thr_uc_MJ"]),
        "time_to_peak_s": {"first": ra["time_to_peak_s"], "second": rb["time_to_peak_s"],
                           "difference": rb["time_to_peak_s"] - ra["time_to_peak_s"]},
        "effective_heat_MJ_kg": gap(first["effective_heat"]["printed_MJ_kg"], first["effective_heat"]["printed_uc_MJ_kg"],
                                    second["effective_heat"]["printed_MJ_kg"], second["effective_heat"]["printed_uc_MJ_kg"]),
        "mass_lost_kg": gap(first["mass_lost_kg"], first["mass_lost_uc_kg"],
                            second["mass_lost_kg"], second["mass_lost_uc_kg"]),
        "co_yield_kg_kg": gap(first["species"]["co"]["printed_kg_kg"], first["species"]["co"]["uc_kg_kg"],
                              second["species"]["co"]["printed_kg_kg"], second["species"]["co"]["uc_kg_kg"]),
        "time_to_half_energy_s": {"first": first["energy_timeline_s"]["0.5"], "second": second["energy_timeline_s"]["0.5"]},
    }
    out["same_curve_within_uncertainty"] = not (out["peak_kW"]["beyond_combined_uc"] or out["thr_MJ"]["beyond_combined_uc"])
    out["what_it_is"] = "repeatability of the item as published; nothing was aligned, scaled or fitted"
    return out


def version_consistency(test_id: str) -> dict:
    """Is each printed 2025 value inside its own rounding of the 2026 value?"""
    data = fcd.load_source()
    row = next(item for item in data["tests"] if item["test_id"] == test_id)
    old, new = row["tn2025"], row["fcd2026"]
    half = 0.5 * 10 ** -fcd._decimals(old["co_yield_printed"])
    return {
        "mass_unchanged": old["mass_lost_kg"] == new["mass_lost_kg"],
        "thr_2025_MJ": old["thr_MJ"], "thr_2026_MJ": new["thr_MJ"],
        "co_yield_2025_printed": old["co_yield_printed"], "co_yield_2026": new["co_yield_kg_per_kg"],
        "co_yield_inside_rounding": abs(float(old["co_yield_printed"]) - new["co_yield_kg_per_kg"]) <= half + 1e-12,
        "declared_version": "FCD_2026", "cause_of_change": "not demonstrated; versions are never mixed",
    }


# ---------------------------------------------------------------- local, not redistributed

def local_files_present(record: dict) -> bool:
    files = record["sources"]["fsri_mapd"]["local_files"]
    return all((LOCAL_FSRI / item["filename"]).is_file() for item in files)


def load_fsri_series(replicate: str, record: dict) -> dict:
    item = next(f for f in record["sources"]["fsri_mapd"]["local_files"]
                if f["filename"] == "Overstuffed_Sofa_%s.csv" % replicate)
    path = LOCAL_FSRI / item["filename"]
    if not path.is_file():
        raise Refusal("%s is a local file that is not redistributed and is not present" % item["filename"])
    if sha256_file(path) != item["sha256"]:
        raise Refusal("%s is not the file that was reviewed" % item["filename"])
    with path.open(newline="", encoding="utf-8-sig") as source:
        reader = csv.DictReader(source)
        if not set(FSRI_COLUMNS) <= set(reader.fieldnames or ()):
            raise Refusal("%s columns changed" % item["filename"])
        rows = list(reader)
    times = [float(row["Time (s)"]) for row in rows]
    if any(abs((b - a) - 1.0) > 1e-9 for a, b in zip(times, times[1:])):
        raise Refusal("%s time axis is not contiguous at 1 s" % item["filename"])
    out = {"run_id": "FSRI_Overstuffed_Sofa_%s" % replicate, "version": record["sources"]["fsri_mapd"]["commit"],
           "times": [int(t) for t in times]}
    for name in FSRI_COLUMNS[1:]:
        values = [reading(row[name]) for row in rows]
        if any(v["state"] not in ("value", "zero") for v in values):
            raise Refusal("%s has missing readings in %s" % (item["filename"], name))
        out[name] = [v["value"] for v in values]
    return out


def analyse_fsri_run(series: dict) -> dict:
    """HRR and load cell of the same run. Units are read from the page, not from the file."""
    times, hrr, load = series["times"], series["Heat Release Rate"], series["Load Cell"]
    zero = times.index(0)
    before = statistics.median(load[:zero])
    after = statistics.median(load[-60:])
    cumulative, running = [], 0.0
    for t, q in zip(times, hrr):
        if t >= 0:
            running += q / 1000.0
        cumulative.append(running)
    energy, lost = cumulative[-1], before - after
    heat = energy / lost

    def smoothed(index: int, half: int = 5) -> float:
        return statistics.median(load[max(0, index - half):index + half + 1])

    def at_fraction(fraction: float) -> int:
        return next(i for i in range(zero, len(times)) if cumulative[i] >= fraction * energy)

    windows = {}
    for low, high in ((0.1, 0.5), (0.5, 0.9)):
        a, b = at_fraction(low), at_fraction(high)
        d_energy, d_mass = cumulative[b] - cumulative[a], smoothed(a) - smoothed(b)
        windows["%g_to_%g_of_energy" % (low, high)] = {
            "start_s": times[a], "end_s": times[b], "energy_MJ": d_energy, "mass_kg": d_mass,
            "MJ_kg": d_energy / d_mass}
    # Negative control with real data: mass rebuilt from HRR over the whole-test heat
    deviation = [(before - cumulative[i] / heat) - smoothed(i) for i in range(zero, len(times))]
    worst = max(range(len(deviation)), key=lambda k: abs(deviation[k]))
    peak = max(hrr)
    steps = [b - a for a, b in zip(load, load[1:])]
    return {
        "run_id": series["run_id"], "support_s": [times[0], times[-1]],
        "peak_kW": peak, "time_to_peak_s": times[hrr.index(peak)], "energy_MJ": energy,
        "hrr_minimum_kW": min(hrr),
        "hrr_samples_exactly_zero_after_start": sum(1 for t, q in zip(times, hrr) if t >= 0 and q == 0.0),
        "first_time_above_5_kW_s": next(t for t, q in zip(times, hrr) if q > 5.0),
        "load_before_kg": before, "load_after_kg": after, "mass_lost_kg": lost,
        "load_sd_before_kg": statistics.pstdev(load[:zero]), "largest_one_second_step_kg": max(abs(s) for s in steps),
        "effective_heat_MJ_kg": heat, "windows": windows,
        "hrr_over_heat_against_load_cell": {
            "largest_gap_kg": deviation[worst], "at_s": times[zero + worst],
            "largest_gap_over_mass_lost": abs(deviation[worst]) / lost,
            "what_it_shows": "mass rebuilt as HRR over the whole-test heat departs from the load cell of the same run"},
    }


def local_aggregates(record: dict) -> dict:
    """Scalar aggregates of the local, non redistributed series. The series are not saved."""
    runs = {rep: analyse_fsri_run(load_fsri_series(rep, record)) for rep in ("R1", "R2", "R3")}
    def spread(key: str) -> dict:
        values = [runs[rep][key] for rep in runs]
        return {"min": min(values), "max": max(values), "relative_spread": (max(values) - min(values)) / min(values)}
    return {
        "schema": "g3_object_fire_source_local_aggregates_v1",
        "nature": "scalar aggregates of series that are not redistributed; not raw data",
        "source": {"commit": record["sources"]["fsri_mapd"]["commit"],
                   "files": {f["filename"]: f["sha256"] for f in record["sources"]["fsri_mapd"]["local_files"]
                             if f["filename"].endswith(".csv")}},
        "runs": runs,
        "across_runs": {key: spread(key) for key in ("peak_kW", "time_to_peak_s", "energy_MJ", "mass_lost_kg",
                                                     "effective_heat_MJ_kg")},
    }


# ---------------------------------------------------------------- decisions

def decide(facts: dict) -> dict:
    """One decision per observable. A GO in one never approves another."""
    out = {}
    if not facts["hrr_numeric_same_run"]:
        out["prescribed_hrr"] = "NO_GO_no_numeric_series"
    elif not facts["redistribution_verified"] or not facts["igniter_documented"] or not facts["uncertainty_published"]:
        out["prescribed_hrr"] = "GO_partial_local_only_igniter_and_uncertainty_not_documented"
    elif not facts["hrr_reproduces_published_totals"]:
        out["prescribed_hrr"] = "NO_GO_series_does_not_return_published_totals"
    elif facts["inseparable_components"]:
        out["prescribed_hrr"] = "GO_one_run_open_air_as_the_whole_set"
    else:
        out["prescribed_hrr"] = "GO_one_run_open_air"
    if not facts["mass_series_numeric_same_run"]:
        out["prescribed_mass_loss"] = ("NO_GO_figure_only_total_is_gravimetric" if facts["mass_series_in_figure"]
                                       else "NO_GO_not_measured_in_time_total_is_gravimetric")
    elif not facts["redistribution_verified"] or not facts["uncertainty_published"]:
        out["prescribed_mass_loss"] = "GO_partial_local_only_load_cell_uncertainty_not_documented"
    else:
        out["prescribed_mass_loss"] = "GO_one_run_open_air"
    if facts["mass_series_numeric_same_run"] and facts["hrr_numeric_same_run"]:
        out["energy_and_effective_heat"] = ("GO_partial_local_only_energy_against_mass_in_time"
                                            if not facts["redistribution_verified"] else "GO_energy_against_mass_in_time")
    elif facts["hrr_numeric_same_run"] and facts["mass_total_published"]:
        out["energy_and_effective_heat"] = "GO_partial_whole_test_integrals_only"
    else:
        out["energy_and_effective_heat"] = "NO_GO"
    if not facts["species_series_numeric_same_run"]:
        out["species_emission"] = "NO_GO_no_species_measured"
    elif not facts["species_totals_reproduced"]:
        out["species_emission"] = "NO_GO_exhaust_totals_not_reproduced"
    elif not facts["species_version_consistent"]:
        out["species_emission"] = "GO_partial_exhaust_totals_declared_version_only_change_unexplained"
    else:
        out["species_emission"] = "GO_partial_exhaust_totals_of_CO_CO2_O2"
    if facts["mass_series_numeric_same_run"] and facts["species_series_numeric_same_run"]:
        out["temporal_species_yield"] = "GO_partial"
    else:
        out["temporal_species_yield"] = "NO_GO_no_run_has_numeric_mass_and_species_in_time"
    out["extrapolation"] = ("NO_GO_repeat_runs_differ_beyond_uncertainty" if facts["repeats_differ_beyond_uncertainty"]
                            else "NO_GO_one_regime_one_item")
    out["external_validation"] = ("reserved_run_available_not_used" if facts["reserved_run_available"]
                                  else "none_reproduction_only")
    return out


def audit(record: dict | None = None) -> dict:
    record = record or load_record()
    runs = {test_id: analyse_nist_run(test_id, record) for test_id in record["tests"]}
    versions = {test_id: version_consistency(test_id) for test_id in record["tests"]}
    local = json.loads(LOCAL_AGGREGATES.read_text(encoding="utf-8")) if LOCAL_AGGREGATES.is_file() else None
    candidates = {}
    for candidate in record["candidates"]:
        entry = {"owner_id": candidate["owner_id"], "source_run": candidate["source_run"],
                 "reserved_runs": candidate["reserved_runs"]}
        if candidate["dataset"] == "nist_fcd":
            source = runs[candidate["source_run"]]
            contrasts = {run: replicate_contrast(source, runs[run]) for run in candidate["reserved_runs"]}
            entry["contrast_with_reserved_runs"] = contrasts
            involved = [candidate["source_run"]] + candidate["reserved_runs"]
            facts = {
                "hrr_numeric_same_run": True,
                "redistribution_verified": record["sources"]["nist_fcd"]["redistribution"]["verified"],
                "igniter_documented": candidate["igniter_documented"],
                "uncertainty_published": True,
                "hrr_reproduces_published_totals": all(source["reproduction"][key] for key in
                                                       ("peak_inside_uc", "time_to_peak_inside_uc", "energy_inside_uc")),
                "inseparable_components": bool(candidate["inseparable_components"]),
                "mass_series_numeric_same_run": False,
                "mass_series_in_figure": candidate["mass_series"]["state"] == "figure_only_not_digitised",
                "mass_total_published": True,
                "species_series_numeric_same_run": True,
                "species_totals_reproduced": all(item["inside_uc"] for item in source["species"].values()),
                "species_version_consistent": all(versions[run]["co_yield_inside_rounding"] for run in involved),
                "repeats_differ_beyond_uncertainty": any(not c["same_curve_within_uncertainty"] for c in contrasts.values()),
                "reserved_run_available": bool(candidate["reserved_runs"]),
            }
        else:
            spread = local["across_runs"] if local else None
            facts = {
                "hrr_numeric_same_run": True,
                "redistribution_verified": record["sources"]["fsri_mapd"]["redistribution"]["verified"],
                "igniter_documented": candidate["igniter_documented"],
                "uncertainty_published": False,
                "hrr_reproduces_published_totals": None,
                "inseparable_components": bool(candidate["inseparable_components"]),
                "mass_series_numeric_same_run": True, "mass_series_in_figure": False, "mass_total_published": False,
                "species_series_numeric_same_run": False, "species_totals_reproduced": None,
                "species_version_consistent": None,
                "repeats_differ_beyond_uncertainty": False,
                "reserved_run_available": bool(candidate["reserved_runs"]),
            }
            entry["local_aggregates_across_runs"] = spread
        entry["facts"] = facts
        entry["decisions"] = decide(facts)
        candidates[candidate["id"]] = entry
    selected = record["selection"]["candidate"]
    return {
        "schema": "g3_object_fire_source_audit_v1",
        "record_sha256": hashlib.sha256(INPUT.read_bytes()).hexdigest(),
        "scope": "offline review of published tests; reproduction of a prescribed source, not engine validation",
        "selected": {"candidate": selected, "owner_id": candidates[selected]["owner_id"],
                     "source_run": candidates[selected]["source_run"],
                     "table_fingerprint": runs[candidates[selected]["source_run"]]["table_fingerprint"],
                     "decisions": candidates[selected]["decisions"]},
        "candidates": candidates, "runs": runs, "version_consistency": versions,
        "local_aggregates_published": local is not None,
        "standing": {"b_net": "NO_GO_closed_on_this_route", "co_fed": "OFF_NO_GO",
                     "engine_change": "not_authorised_in_this_phase", "predictive_source": "NO_GO"},
    }


def _rounded(value, digits: int = 9):
    if isinstance(value, float):
        return round(value, digits)
    if isinstance(value, dict):
        return {key: _rounded(item, digits) for key, item in value.items()}
    if isinstance(value, list):
        return [_rounded(item, digits) for item in value]
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--write", action="store_true", help="save the audit next to the record")
    parser.add_argument("--check", action="store_true", help="compare with the saved audit")
    parser.add_argument("--write-local-aggregates", action="store_true",
                        help="recompute the scalar aggregates of the local, non redistributed series")
    args = parser.parse_args()
    record = load_record()
    if args.write_local_aggregates:
        body = _rounded(local_aggregates(record), 6)
        LOCAL_AGGREGATES.write_text(json.dumps(body, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    result = _rounded(audit(record))
    if args.write:
        SAVED.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    if args.check:
        saved = json.loads(SAVED.read_text(encoding="utf-8"))
        same = saved == json.loads(json.dumps(result))
        print(json.dumps({"matches_saved_audit": same}))
        return 0 if same else 1
    print(json.dumps({"selected": result["selected"],
                      "decisions": {key: value["decisions"] for key, value in result["candidates"].items()}}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
