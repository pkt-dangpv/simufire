"""Build the fixture of the isolated prescribed HRR source: NIST Test016, one run.

Offline importer. It reads the audited inputs, checks their hashes and licence, takes the
table of the selection audit as it is, and writes the source the GDScript owner reads, the
accounting of the negative readings and an oracle.

The oracle is exact rational arithmetic on the decimal text of the CSV. It shares the data
with the module under test and nothing else: no float is used until the last rounding, and
no expected number is taken from the module. Nothing is scaled, shifted or stretched to
reach the published total.

Reproducing the measured curve of the run it was built from is not predicting a fire.

    python -m scripts.simulation.build_g3_object_hrr_source --check
"""

from __future__ import annotations

import argparse
import csv
from decimal import Decimal
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import struct

from scripts.simulation import audit_g3_object_fire_source as audit

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "fixtures" / "g3_object_hrr_source_test016.json"
RUN = "Test016"
LICENSE = "https://www.nist.gov/open/license"
HRR_COLUMN = "Heat Release Rate (kW)"
MODULE_VERSION = "prescribed_object_hrr_source_v1"
SOURCE_SCHEMA = "g3_prescribed_object_hrr_source_v1"
FIXTURE_SCHEMA = "g3_object_hrr_source_fixture_v1"
# Numerical tolerance of every comparison with the oracle. It is the rounding of a few
# thousand double precision trapezoids, eleven orders of magnitude below the published
# uncertainty of the test, so the experimental margin cannot hide an integration error.
ABS_TOL_KJ = 1.0e-9
REL_TOL = 1.0e-12
UNKNOWN = ("mass_loss_rate", "species_yields", "composition", "radiative_fraction")
_SAMPLES = "@@SAMPLES@@"


def selected_test(record: dict) -> tuple[dict, dict]:
    """The selected candidate and its source run. A reserved run is refused."""
    candidate = next(item for item in record["candidates"] if item["id"] == record["selection"]["candidate"])
    audit.use_for_fit(candidate, RUN)
    if candidate["dataset"] != "nist_fcd":
        raise audit.Refusal("the selected candidate is not a NIST run")
    source = record["sources"]["nist_fcd"]
    if source["redistribution"]["verified"] is not True or LICENSE not in source["redistribution"]["basis"]:
        raise audit.Refusal("the licence of the source is not verified: the table cannot be versioned")
    test = record["tests"][RUN]
    if test["owner_id"] != candidate["owner_id"] or candidate["inseparable_components"]:
        raise audit.Refusal("the run does not belong to the whole selected object")
    return candidate, test


def decimal_window(test: dict) -> list[tuple[int, Decimal]]:
    """The printed HRR of the support, read again from the bytes, as exact decimals."""
    path = ROOT / test["csv"]["path"]
    if audit.sha256_file(path) != test["csv"]["sha256"]:
        raise audit.Refusal("%s bytes changed" % test["csv"]["path"])
    start, end = test["events"]["ignition_s"], test["events"]["fire_out_s"]
    rows = []
    with path.open(newline="", encoding="utf-8-sig") as source:
        for row in csv.DictReader(source):
            time_s = int(row["Time (s)"])
            if start <= time_s <= end:
                rows.append((time_s - start, Decimal(row[HRR_COLUMN])))
    if [t for t, _v in rows] != list(range(0, end - start + 1)):
        raise audit.Refusal("the support is not contiguous at 1 s from the ignition")
    if any(not value.is_finite() for _t, value in rows):
        raise audit.Refusal("a reading of the support is not a number")
    return rows


def module_source(test: dict, table: dict, record: dict) -> dict:
    """The audited table as the source the isolated owner reads. Unknowns stay null."""
    page = test["page"]
    source = record["sources"]["nist_fcd"]
    return {
        "schema": SOURCE_SCHEMA,
        "owner_id": table["owner_id"],
        "run_id": table["run_id"],
        "quantity": table["quantity"],
        "time_unit": "s",
        "hrr_unit": table["unit"],
        "energy_unit": "kJ",
        "time_origin": "documented_ignition_event",
        "interpolation": table["interpolation"],
        "outside_support": table["outside_support"],
        "negative_samples": "clipped_to_zero_offline",
        "regime": "open_air_as_tested",
        "provenance": {
            "dataset": "%s, doi:%s" % (source["title"], source["doi"]),
            "dataset_version": "%s, record %s, page %s updated %s" % (
                table["version"], source["record_version"], page["report_process_script"], page["last_updated"]),
            "license": LICENSE,
            "source_file": test["csv"]["path"],
            "source_sha256": table["source_sha256"],
            "source_column": HRR_COLUMN,
            "support_events": "Ignition to Fire Out of the source page, %d to %d s" % (
                test["events"]["ignition_s"], test["events"]["fire_out_s"]),
            "importer": "scripts/simulation/build_g3_object_hrr_source.py",
            "table_fingerprint": table["fingerprint"],
        },
        "unknown": {key: None for key in UNKNOWN},
        "samples": [{"time_s": time_s, "hrr_kw": value} for time_s, value in table["samples"]],
    }


def identity_text(value) -> str:
    """The identity text of the owner, written again here: sorted keys, numbers bit by bit."""
    if isinstance(value, dict):
        return "{" + ",".join(json.dumps(key) + ":" + identity_text(value[key]) for key in sorted(value)) + "}"
    if isinstance(value, list):
        return "[" + ",".join(identity_text(item) for item in value) + "]"
    if value is None:
        return "null"
    if isinstance(value, str):
        if not value.isascii() or '"' in value or "\\" in value:
            raise ValueError("identity text is declared for plain ASCII only: %r" % value)
        return json.dumps(value)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("no identity text for %r" % (value,))
    return "f64:" + struct.pack("<d", abs(float(value)) if value == 0 else float(value)).hex()


def identity(source: dict) -> str:
    return hashlib.sha256((MODULE_VERSION + identity_text(source)).encode("utf-8")).hexdigest()


# ---------------------------------------------------------------- exact oracle

def exact_value(nodes: list[Fraction], time_s: Fraction) -> Fraction:
    """The piecewise linear table at a time of the support, 1 s nodes from zero."""
    last = len(nodes) - 1
    if not 0 <= time_s <= last:
        raise audit.Refusal("%s s is outside the support" % time_s)
    low = min(int(time_s), last - 1)
    return nodes[low] + (nodes[low + 1] - nodes[low]) * (time_s - low)


def exact_energy(nodes: list[Fraction], start: Fraction, end: Fraction) -> Fraction:
    """Exact integral in kW s, which is kJ, between two times of the support."""
    last = len(nodes) - 1
    if not 0 <= start <= end <= last:
        raise audit.Refusal("interval outside the support")
    total = Fraction(0)
    for low in range(int(start), min(int(end) + 1, last)):
        lo, hi = max(start, Fraction(low)), min(end, Fraction(low + 1))
        if hi > lo:
            total += (exact_value(nodes, lo) + exact_value(nodes, hi)) * (hi - lo) / 2
    return total


def irregular_endpoints(last: int) -> list[float]:
    """A deterministic partition whose ends are not nodes: steps of 0.4 to 37 s."""
    ends, at, step = [], Fraction(0), 0
    while True:
        step += 1
        at += Fraction(2 + (step * 37) % 181, 5)
        if at >= last:
            break
        ends.append(float(at))
    ends.append(float(last))
    return ends


def acceptance_share(index: int) -> Fraction:
    """Declared rule of the partial acceptance campaign: all, half, none, a quarter, all."""
    return (Fraction(1), Fraction(1, 2), Fraction(0), Fraction(1, 4), Fraction(1))[index % 5]


def campaign(nodes: list[Fraction], ends: list[float], partial: bool) -> dict:
    accepted, scheduled, start = Fraction(0), Fraction(0), Fraction(0)
    for index, end in enumerate(ends):
        energy = exact_energy(nodes, start, Fraction(end))
        scheduled += energy
        accepted += energy * (acceptance_share(index) if partial else 1)
        start = Fraction(end)
    return {"intervals": len(ends), "end_time_s": float(start), "scheduled_kj": float(scheduled),
            "accepted_kj": float(accepted), "rejected_kj": float(scheduled - accepted)}


def oracle(nodes: list[Fraction], negatives: list[int]) -> dict:
    last = len(nodes) - 1
    peak = max(range(len(nodes)), key=lambda index: nodes[index])
    node_times = sorted({0, 1, 2, 641, peak - 1, peak, peak + 1, 1183, 1861, last - 1, last, *negatives[:3]})
    between = [0.5, 0.25, 640.75, peak - 0.5, peak + 0.125, 1182.9, 2000.3, last - 0.001]
    between += [negatives[0] - 0.5, negatives[0] + 0.5]
    spans = [(0, 1), (0, 0.5), (0.25, 0.75), (0, last), (peak - 0.75, peak + 1.75), (640.2, 1861.9),
             (1000, 1300), (negatives[0] - 1.5, negatives[0] + 1.5), (last - 1, last), (last - 0.5, last),
             (17.3, 17.4), (0, peak), (peak, last)]
    partitions = {
        "whole": [float(last)],
        "minutes": [float(t) for t in range(60, last, 60)] + [float(last)],
        "seconds": [float(t) for t in range(1, last + 1)],
        "irregular": irregular_endpoints(last),
    }
    return {
        "method": "exact rational arithmetic on the decimal text of the CSV, rounded once at the end",
        "shares_with_the_module": "the table only; no code, no float integration and no output of the module",
        "numerical_tolerance": {
            "abs_kj": ABS_TOL_KJ, "rel": REL_TOL,
            "basis": "double precision rounding of the trapezoids; it is not experimental uncertainty"},
        "total_energy_kj": float(exact_energy(nodes, Fraction(0), Fraction(last))),
        "peak": {"time_s": float(peak), "hrr_kw": float(nodes[peak])},
        "nodes": [{"time_s": float(t), "hrr_kw": float(nodes[t])} for t in node_times],
        "between_nodes": [{"time_s": t, "hrr_kw": float(exact_value(nodes, Fraction(t)))} for t in between],
        "intervals": [{"start_s": float(a), "end_s": float(b),
                       "energy_kj": float(exact_energy(nodes, Fraction(float(a)), Fraction(float(b))))}
                      for a, b in spans],
        "partitions": partitions,
        "acceptance_rule": "by interval index modulo 5: all, half, none, a quarter, all",
        "campaigns": {name: {"full": campaign(nodes, ends, False), "partial": campaign(nodes, ends, True)}
                      for name, ends in partitions.items()},
    }


# ---------------------------------------------------------------- fixture

def build() -> dict:
    record = audit.load_record()
    _candidate, test = selected_test(record)
    series = audit.load_fcd_series(test)
    page = audit.fcd_page(RUN)
    if (audit.event_time_s(page, "Ignition"), audit.event_time_s(page, "Fire Out", last=True)) != (
            test["events"]["ignition_s"], test["events"]["fire_out_s"]):
        raise audit.Refusal("the events of the record differ from the archived page")
    table = audit.prescribed_table(test, series, test["owner_id"])
    saved = json.loads(audit.SAVED.read_text(encoding="utf-8"))["selected"]
    if (saved["source_run"], saved["table_fingerprint"]) != (RUN, table["fingerprint"]):
        raise audit.Refusal("the table is not the one of the saved selection audit")
    printed = decimal_window(test)
    signed = [Fraction(value) for _t, value in printed]
    nodes = [max(Fraction(0), value) for value in signed]
    source = module_source(test, table, record)
    if [Fraction(sample["hrr_kw"]) for sample in source["samples"]] != [Fraction(float(v)) for v in nodes]:
        raise audit.Refusal("the audited table is not the clipped column of the CSV")
    last = len(nodes) - 1
    negatives = [t for t, value in printed if value < 0]
    whole = (Fraction(0), Fraction(last))
    signed_kj, clipped_kj = exact_energy(signed, *whole), exact_energy(nodes, *whole)
    thr = audit.page_value(page, "results", "Total Heat Released")
    peak = audit.page_value(page, "results", "Peak Heat Release Rate")
    published_kj = Fraction(str(audit.as_number(thr))) * 1000
    uncertainty_kj = Fraction(str(thr["uc"])) * 1000
    return {
        "schema": FIXTURE_SCHEMA,
        "scope": "reproduction of one measured open-air run; not prediction, not validation of the engine",
        "approvals": {"predictive_source": False, "enclosure_or_underventilated_use": False,
                      "mass_loss_from_hrr": False, "species_or_co_fed": False, "other_objects": False,
                      "engine_integration": False, "product_activation": False},
        "reserved_runs_not_used": _candidate["reserved_runs"],
        "source": source,
        "expected_identity": identity(source),
        "import": {
            "what_was_done": "the HRR column between the two events, time counted from the ignition; negative "
                             "readings set to zero; nothing smoothed, shifted, scaled or resampled",
            "csv_support_s": [series["times"][0], series["times"][-1]],
            "approved_support_s": [0, last],
            "left_out": "readings before the ignition and after Fire Out",
            "samples": len(nodes),
            "negative_readings": {"count": len(negatives), "at_s": negatives,
                                  "lowest_kw": float(min(value for _t, value in printed)),
                                  "treatment": "clipped_to_zero_offline",
                                  "why": "noise of the calorimeter; a source cannot release negative power"},
            "integrals_kj": {
                "rule": "trapezoid between consecutive readings, exact",
                "original_signed": float(signed_kj), "after_clipping": float(clipped_kj),
                "difference": float(clipped_kj - signed_kj),
                "page_rule_sum_original_signed": float(sum(signed)), "page_rule_sum_after_clipping": float(sum(nodes)),
            },
        },
        "published": {
            "source": "archived page of the run, version 2026",
            "total_heat_released_MJ": audit.as_number(thr), "expanded_uncertainty_MJ": thr["uc"],
            "peak_hrr_kW": audit.as_number(peak), "peak_expanded_uncertainty_kW": peak["uc"],
            "table_minus_published_kj": float(clipped_kj - published_kj),
            "table_minus_published_over_uncertainty": float(abs(clipped_kj - published_kj) / uncertainty_kj),
            "inside_published_uncertainty": abs(clipped_kj - published_kj) <= uncertainty_kj,
            "numerical_tolerance_over_uncertainty": float(
                (Fraction(ABS_TOL_KJ) + Fraction(REL_TOL) * clipped_kj) / uncertainty_kj),
        },
        "oracle": oracle(nodes, negatives),
    }


def render(fixture: dict) -> str:
    """Deterministic text: one sample and one partition per line."""
    body = json.loads(json.dumps(fixture, allow_nan=False))
    samples = body["source"]["samples"]
    partitions = body["oracle"]["partitions"]
    body["source"]["samples"] = _SAMPLES
    body["oracle"]["partitions"] = {name: "@@%s@@" % name for name in partitions}
    text = json.dumps(body, indent=1, allow_nan=False)
    text = text.replace(json.dumps(_SAMPLES), "[\n" + ",\n".join(
        "   " + json.dumps(sample, allow_nan=False) for sample in samples) + "\n  ]")
    for name, ends in partitions.items():
        text = text.replace(json.dumps("@@%s@@" % name), json.dumps(ends, allow_nan=False))
    if not text.isascii() or json.loads(text) != fixture:
        raise ValueError("the rendered fixture does not read back as built")
    return text + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--write", action="store_true", help="write the fixture")
    parser.add_argument("--check", action="store_true", help="compare with the committed fixture")
    args = parser.parse_args()
    text = render(build())
    if args.write:
        FIXTURE.write_text(text, encoding="utf-8", newline="\n")
    if args.check:
        same = FIXTURE.read_bytes().replace(b"\r\n", b"\n") == text.encode("utf-8")
        print(json.dumps({"matches_committed_fixture": same}))
        return 0 if same else 1
    fixture = json.loads(text)
    print(json.dumps({"identity": fixture["expected_identity"], "import": fixture["import"]["integrals_kj"],
                      "published": fixture["published"],
                      "total_energy_kj": fixture["oracle"]["total_energy_kj"]}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
