"""Research-only comparison of NIST TN 2303 (2025) and FCD 2026 CO processing.

Both versions report the same 48 open-air tests. TN 2303 Table 8 prints CO
yields with three decimals; the FCD pages (``NFRL_Report_8.7.1``, updated
2026-04-07) print more digits and a combined expanded uncertainty. Neither
source publishes the processing code, integration bounds or change log.

This module only tests *which documented or candidate treatment of the
public 2026 CSVs is compatible with each printed version*. Acceptance
criteria are fixed before evaluation:

* FCD 2026: reconstructed CO / FCD mass within the published ``Uc``.
* TN 2025: reconstructed CO / TN mass within the printed rounding interval
  ``printed ± 0.0005 kg/kg`` (all Table 8 CO yields have three decimals).

A compatible hypothesis is *not* a demonstrated cause: the 2025 exports and
script are unavailable. No instantaneous yield or engine value is derived.
"""

from __future__ import annotations

import csv
import hashlib
import html
import json
import re
import statistics
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/validation/G3_NIST_TN2303_FCD_CO_PROCESSING_2026-09-29.json"
M_CO_KG_PER_KMOL = 28.01
M_AIR_KG_PER_KMOL = 28.97
TN_ROUNDING_HALF_STEP = 0.0005
# Interval edges count as compatible: 0.0335 printed later as 0.034 is not a change.
FLOAT_TOLERANCE = 1e-12
HYPOTHESES = {
    "H0_guide_bg60_ignition_to_fire_out": {},
    "H1_bg60_ignition_to_end_of_file": {"end_of_file": True},
    "H2_no_background_ignition_to_fire_out": {"background": None},
    "H3_bg120_ignition_to_fire_out": {"background": (-120, 0)},
    "H4a_co_lag_plus20s_ignition_to_fire_out": {"shift_s": 20},
    "H4b_co_lag_minus20s_ignition_to_fire_out": {"shift_s": -20},
    "H5_bg60_file_start_to_fire_out": {"from_file_start": True},
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_source() -> dict:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    for key in ("tn2303_pdf", "fcd_pages_zip", "fcd_user_guide_pdf"):
        item = data["sources"][key]
        digest = _sha256(ROOT / item["path"])
        if digest != item["sha256"]:
            raise ValueError(f"{item['path']} bytes changed: {digest}")
    return data


def _page_cells(raw: bytes) -> list[str]:
    text = raw.decode("utf-8")
    text = re.sub(r"<script.*?</script>|<style.*?</style>", "", text, flags=re.S)
    text = html.unescape(re.sub(r"<[^>]+>", " | ", text))
    text = re.sub(r"(\s*\|\s*)+", " | ", text)
    return [cell.strip() for cell in text.split("|")]


def _number(value: str) -> float | str:
    try:
        return float(value.replace(",", ""))
    except ValueError:
        return value


def extract_fcd_page(raw: bytes) -> dict[str, object]:
    """Read Table 2 values and Table 4 events from one archived FCD page."""
    cells = _page_cells(raw)

    def raw_row(prefix: str) -> tuple[str, str]:
        for index, cell in enumerate(cells):
            if cell.startswith(prefix):
                return cells[index + 1], cells[index + 2]
        raise ValueError(f"missing FCD row {prefix}")

    def row(prefix: str) -> tuple[float | str, float | str]:
        value, uncertainty = raw_row(prefix)
        return _number(value), _number(uncertainty)

    co, co_uc = row("CO Yield")
    mass, mass_uc = row("Net Specimen Mass")
    thr, _ = row("Total Heat Released, THR")
    joined = " | ".join(cells)
    events = joined[joined.find("Table 4."):joined.find("Table 5.")]
    found = re.findall(r"\| (\S+) \| (-?[\d.]+) \| ([^|]+?) (?=\|)", events)
    ignition = [float(t) for _, t, d in found if d.strip() == "Ignition"]
    fire_out = [float(t) for _, t, d in found if "Fire Out" in d]
    script = re.search(r"NFRL_Report_[0-9.]+", joined)
    updated = re.search(r"Last Updated ([A-Za-z]+ \d+, \d{4})", joined)
    return {
        "co_yield_kg_per_kg": co,
        # When the yield is below detection NIST prints the Uc cell anyway;
        # keep it only when the yield itself is numeric.
        "co_yield_Uc_kg_per_kg": co_uc if isinstance(co, float) else None,
        "mass_lost_kg": mass,
        "mass_lost_printed": raw_row("Net Specimen Mass")[0],
        "mass_lost_Uc_kg": mass_uc,
        "thr_MJ": thr,
        "ignition_s": round(ignition[0] * 60),
        "fire_out_s": round(fire_out[-1] * 60),
        "report_process_script": script.group(0) if script else None,
        "last_updated": updated.group(1) if updated else None,
    }


def archived_pages(data: dict) -> dict[str, dict[str, object]]:
    archive = ROOT / data["sources"]["fcd_pages_zip"]["path"]
    with zipfile.ZipFile(archive) as bundle:
        return {
            "Test" + name[4:7]: extract_fcd_page(bundle.read(name))
            for name in sorted(bundle.namelist())
        }


def _series(record: dict) -> tuple[list[int], list[float], list[float], list[float]]:
    path = ROOT / record["csv"]["path"]
    digest = _sha256(path)
    if digest != record["csv"]["sha256"]:
        raise ValueError(f"{path} bytes changed: {digest}")
    with path.open(newline="", encoding="utf-8-sig") as source:
        rows = list(csv.DictReader(source))
    return (
        [int(row["Time (s)"]) for row in rows],
        [float(row["CO (Vol Fr)"]) for row in rows],
        [float(row["Exhaust Mass Flow Rate (kg/s)"]) for row in rows],
        [float(row["Heat Release Rate (kW)"]) for row in rows],
    )


def net_exhaust_co_kg(record: dict, hypothesis: dict, series=None) -> float:
    times, co, flow, _ = series or _series(record)
    background = hypothesis.get("background", (-60, 0))
    ambient = 0.0
    if background is not None:
        ambient = statistics.mean(
            value for time, value in zip(times, co) if background[0] <= time < background[1]
        )
    start = times[0] if hypothesis.get("from_file_start") else record["csv"]["ignition_s"]
    end = times[-1] if hypothesis.get("end_of_file") else record["csv"]["fire_out_s"]
    shift = hypothesis.get("shift_s", 0)
    total = 0.0
    for index, time in enumerate(times):
        lagged = index + shift
        if start <= time <= end and 0 <= lagged < len(times):
            total += (co[lagged] - ambient) * flow[index] * M_CO_KG_PER_KMOL / M_AIR_KG_PER_KMOL
    return total


def _decimals(printed: str) -> int:
    return len(printed.split(".")[1]) if "." in printed else 0


def _mass_changed(record: dict) -> bool:
    """True only beyond the printed precision of the coarser version."""
    old, new = record["tn2025"], record["fcd2026"]
    digits = min(_decimals(old["mass_lost_printed"]), _decimals(new["mass_lost_printed"]))
    return abs(old["mass_lost_kg"] - new["mass_lost_kg"]) > 0.5 * 10 ** -digits + FLOAT_TOLERANCE


def hrr_windows_MJ(record: dict, series=None) -> dict[str, float]:
    """HRR integral inside and after the FCD ignition-to-fire-out window.

    The last CSV row carries NaN HRR in several exports; NaN is skipped.
    """
    times, _, _, hrr = series or _series(record)
    start, end = record["csv"]["ignition_s"], record["csv"]["fire_out_s"]
    inside = sum(q for t, q in zip(times, hrr) if start <= t <= end and q == q)
    after = sum(q for t, q in zip(times, hrr) if t > end and q == q)
    return {"ignition_to_fire_out_MJ": inside / 1000.0, "after_fire_out_MJ": after / 1000.0}


def comparison_set(data: dict) -> list[dict]:
    """Tests with numeric CO yield and mass in both published versions."""
    selected = []
    for record in data["tests"]:
        old, new = record["tn2025"], record["fcd2026"]
        if old["co_yield_printed"] is None or not isinstance(old["mass_lost_kg"], float):
            continue
        if not isinstance(new["co_yield_kg_per_kg"], float) or not isinstance(new["mass_lost_kg"], float):
            continue
        selected.append(record)
    return selected


def evaluate(data: dict | None = None) -> dict[str, object]:
    data = data or load_source()
    tests = comparison_set(data)
    series = {record["test_id"]: _series(record) for record in tests}
    discrepant = []
    for record in tests:
        old, new = record["tn2025"], record["fcd2026"]
        printed = float(old["co_yield_printed"])
        published_2026_on_2025_mass = new["co_yield_kg_per_kg"] * new["mass_lost_kg"] / old["mass_lost_kg"]
        if abs(published_2026_on_2025_mass - printed) > TN_ROUNDING_HALF_STEP + FLOAT_TOLERANCE:
            discrepant.append(record["test_id"])
    results = {}
    for name, hypothesis in HYPOTHESES.items():
        per_test = {}
        for record in tests:
            old, new = record["tn2025"], record["fcd2026"]
            total = net_exhaust_co_kg(record, hypothesis, series[record["test_id"]])
            tn_yield = total / old["mass_lost_kg"]
            fcd_yield = total / new["mass_lost_kg"]
            per_test[record["test_id"]] = {
                "co_kg": total,
                "matches_tn2025_printed": abs(tn_yield - float(old["co_yield_printed"]))
                <= TN_ROUNDING_HALF_STEP + FLOAT_TOLERANCE,
                "within_fcd2026_Uc": abs(fcd_yield - new["co_yield_kg_per_kg"]) <= new["co_yield_Uc_kg_per_kg"],
            }
        results[name] = {
            "tn2025_matches": sorted(t for t, r in per_test.items() if r["matches_tn2025_printed"]),
            "fcd2026_within_Uc": sorted(t for t, r in per_test.items() if r["within_fcd2026_Uc"]),
            "tn2025_matches_on_discrepant": sorted(
                t for t in discrepant if per_test[t]["matches_tn2025_printed"]
            ),
            "per_test": per_test,
        }
    mass_changed = sorted(
        record["test_id"] for record in tests if _mass_changed(record)
    )
    hrr = {record["test_id"]: hrr_windows_MJ(record, series[record["test_id"]]) for record in tests}
    return {
        "status": "research_only_cause_not_demonstrated",
        "hrr_windows_MJ": hrr,
        "comparison_set": [record["test_id"] for record in tests],
        "discrepant_tests": discrepant,
        "mass_changed_tests": mass_changed,
        "hypotheses": results,
    }


if __name__ == "__main__":
    report = evaluate()
    summary = {
        key: value for key, value in report.items() if key not in ("hypotheses", "hrr_windows_MJ")
    }
    summary["hypotheses"] = {
        name: {
            "tn2025_matches": len(item["tn2025_matches"]),
            "fcd2026_within_Uc": len(item["fcd2026_within_Uc"]),
            "tn2025_matches_on_discrepant": item["tn2025_matches_on_discrepant"],
        }
        for name, item in report["hypotheses"].items()
    }
    print(json.dumps(summary, indent=2))
