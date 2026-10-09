"""Isolated prescribed HRR source of one tested object: NIST Test016, one run.

Reproduction of a measured input, not prediction. The offline part checks provenance, the
importer and the oracle; the Godot part runs the real GDScript owner. Numerical tolerance
and experimental uncertainty are judged by separate tests on purpose.
"""

import csv
from decimal import Decimal
from fractions import Fraction
import hashlib
import json
import math
import os
from pathlib import Path
import re

import pytest

from scripts.simulation import audit_g3_object_fire_source as audit
from scripts.simulation import build_g3_object_hrr_source as builder
from scripts.simulation import run_g3_object_hrr_source_mutations as mutations

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "sim/fire/PrescribedObjectHrrSource.gd"
FIXTURE = ROOT / "tests/fixtures/g3_object_hrr_source.gd"
TABLE = ROOT / "tests/fixtures/g3_object_hrr_source_test016.json"
CSV = ROOT / "docs/literature/NIST/FCD_Test016_2026-04-07.csv"
PREFIX = "G3_OBJECT_HRR_SOURCE"
GROUPS = 9
CHECKS = 18148


@pytest.fixture(scope="module")
def table() -> dict:
    return json.loads(TABLE.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def printed() -> list[tuple[int, Decimal]]:
    """The HRR column of the support, read here with no help from the auditor or the builder."""
    with CSV.open(newline="", encoding="utf-8-sig") as source:
        rows = [(int(row["Time (s)"]), Decimal(row["Heat Release Rate (kW)"])) for row in csv.DictReader(source)]
    return [(t, value) for t, value in rows if 0 <= t <= 3768]


# ---------------------------------------------------------------- provenance and importer

def test_fixture_is_rebuilt_byte_for_byte_from_the_audited_inputs(table):
    text = builder.render(builder.build())
    assert TABLE.read_bytes().replace(b"\r\n", b"\n") == text.encode("utf-8")
    assert json.loads(text) == table == builder.build()


def test_source_bytes_licence_and_selection_are_the_audited_ones(table):
    record = audit.load_record()
    test = record["tests"]["Test016"]
    provenance = table["source"]["provenance"]
    assert hashlib.sha256(CSV.read_bytes()).hexdigest() == test["csv"]["sha256"] == provenance["source_sha256"]
    assert provenance["source_file"] == test["csv"]["path"] == CSV.relative_to(ROOT).as_posix()
    assert record["sources"]["nist_fcd"]["redistribution"]["verified"] is True
    assert provenance["license"] == "https://www.nist.gov/open/license"
    assert provenance["license"] in record["sources"]["nist_fcd"]["redistribution"]["basis"]
    saved = json.loads(audit.SAVED.read_text(encoding="utf-8"))["selected"]
    assert saved["decisions"]["prescribed_hrr"] == "GO_one_run_open_air"
    assert (saved["source_run"], saved["owner_id"]) == ("Test016", table["source"]["owner_id"])
    assert provenance["table_fingerprint"] == saved["table_fingerprint"]
    assert table["source"]["run_id"] == "Test016"
    assert table["source"]["owner_id"] == "nist_tn2303_stackable_chair_a_as_tested"


def test_table_is_the_printed_column_from_ignition_with_nothing_adjusted(table, printed):
    samples = table["source"]["samples"]
    assert [sample["time_s"] for sample in samples] == [float(t) for t, _value in printed]
    assert [sample["hrr_kw"] for sample in samples] == [max(0.0, float(value)) for _t, value in printed]
    assert len(samples) == 3769 and samples[0]["time_s"] == 0 and samples[-1]["time_s"] == 3768
    assert table["import"]["csv_support_s"] == [-282, 4005] and table["import"]["approved_support_s"] == [0, 3768]
    # No scale, shift or stretch exists to adjust: the source carries exactly these fields.
    assert list(table["source"]) == [
        "schema", "owner_id", "run_id", "quantity", "time_unit", "hrr_unit", "energy_unit", "time_origin",
        "interpolation", "outside_support", "negative_samples", "regime", "provenance", "unknown", "samples"]
    assert (table["source"]["time_unit"], table["source"]["hrr_unit"], table["source"]["energy_unit"]) == ("s", "kW", "kJ")
    assert table["source"]["time_origin"] == "documented_ignition_event"
    assert table["source"]["interpolation"] == "piecewise_linear" and table["source"]["outside_support"] == "reject"


def test_negative_readings_are_clipped_offline_and_the_bias_is_declared(table, printed):
    negatives = [t for t, value in printed if value < 0]
    record = table["import"]["negative_readings"]
    assert record["count"] == len(negatives) == 11 and record["at_s"] == negatives
    assert record["lowest_kw"] == float(min(value for _t, value in printed)) == -0.36
    assert record["treatment"] == table["source"]["negative_samples"] == "clipped_to_zero_offline"
    assert all(sample["hrr_kw"] >= 0 for sample in table["source"]["samples"])
    assert [sample["hrr_kw"] for sample in table["source"]["samples"] if sample["time_s"] in negatives] == [0.0] * 11
    signed = [Fraction(value) for _t, value in printed]
    clipped = [max(Fraction(0), value) for value in signed]

    def trapezoid(values):
        return sum((a + b) / 2 for a, b in zip(values, values[1:]))

    integrals = table["import"]["integrals_kj"]
    assert integrals["original_signed"] == float(trapezoid(signed)) == 115092.405
    assert integrals["after_clipping"] == float(trapezoid(clipped)) == 115093.655
    assert integrals["difference"] == float(trapezoid(clipped) - trapezoid(signed)) == 1.25
    assert integrals["page_rule_sum_original_signed"] == float(sum(signed)) == 115092.81
    assert integrals["page_rule_sum_after_clipping"] == float(sum(clipped))


def test_unknown_quantities_are_null_and_nothing_is_approved(table):
    assert table["source"]["unknown"] == {
        "mass_loss_rate": None, "species_yields": None, "composition": None, "radiative_fraction": None}
    assert set(table["approvals"].values()) == {False}
    assert table["reserved_runs_not_used"] == ["Test021"]
    text = TABLE.read_text(encoding="utf-8")
    for absent in ("heptane", "FSRI", "fsri", "heat_of_combustion", "mass_kg", "yield_kg", "o2_"):
        assert absent not in text


def test_reserved_run_other_objects_and_unlicensed_data_are_refused_by_the_importer(monkeypatch):
    record = audit.load_record()
    assert builder.selected_test(record)[1]["run_id"] == "Test016"
    monkeypatch.setattr(builder, "RUN", "Test021")
    with pytest.raises(audit.Refusal, match="reserved"):
        builder.selected_test(record)
    monkeypatch.setattr(builder, "RUN", "Test030")
    with pytest.raises(audit.Refusal, match="not a run"):
        builder.selected_test(record)
    monkeypatch.setattr(builder, "RUN", "Test016")
    unlicensed = json.loads(json.dumps(record))
    unlicensed["sources"]["nist_fcd"]["redistribution"]["verified"] = False
    with pytest.raises(audit.Refusal, match="licence"):
        builder.selected_test(unlicensed)
    moved = json.loads(json.dumps(record))
    moved["tests"]["Test016"]["csv"]["sha256"] = "0" * 64
    with pytest.raises(audit.Refusal, match="bytes changed"):
        builder.decimal_window(moved["tests"]["Test016"])
    source = (ROOT / "scripts/simulation/build_g3_object_hrr_source.py").read_text(encoding="utf-8")
    for forbidden in ("Test021", "LOCAL_FSRI", "fsri", "heptane", "audit.audit(", "local_aggregates"):
        assert forbidden not in source


# ---------------------------------------------------------------- oracle

def test_oracle_total_is_reproduced_by_three_independent_sums(table, printed):
    """Numerical agreement only: exact rationals here, floats in the two other sums."""
    clipped = [max(Fraction(0), Fraction(value)) for _t, value in printed]
    exact = sum((a + b) / 2 for a, b in zip(clipped, clipped[1:]))
    oracle = table["oracle"]["total_energy_kj"]
    assert oracle == float(exact) == 115093.655
    values = [sample["hrr_kw"] for sample in table["source"]["samples"]]
    floating = math.fsum(0.5 * (a + b) for a, b in zip(values, values[1:]))
    assert abs(floating - oracle) <= builder.ABS_TOL_KJ + builder.REL_TOL * oracle
    # The auditor integrates the same table with its own float trapezoid, in MJ.
    record = audit.load_record()
    test = record["tests"]["Test016"]
    audited = audit.table_energy_MJ(audit.prescribed_table(test, audit.load_fcd_series(test), test["owner_id"]))
    assert abs(audited * 1000.0 - oracle) <= builder.ABS_TOL_KJ + builder.REL_TOL * oracle
    # The rule of the page, a sum of samples, differs from the trapezoid by half the end values.
    assert float(sum(clipped) - exact) == float((clipped[0] + clipped[-1]) / 2) == 0.405


def test_oracle_values_and_intervals_are_exact(table, printed):
    nodes = [max(Fraction(0), Fraction(value)) for _t, value in printed]
    oracle = table["oracle"]
    assert oracle["peak"] == {"time_s": 1143.0, "hrr_kw": 621.46}
    for node in oracle["nodes"]:
        assert node["hrr_kw"] == float(nodes[int(node["time_s"])])
    for point in oracle["between_nodes"]:
        time_s = Fraction(point["time_s"])
        low = int(time_s)
        assert point["hrr_kw"] == float(nodes[low] + (nodes[low + 1] - nodes[low]) * (time_s - low))
    assert any(point["time_s"] != int(point["time_s"]) for point in oracle["between_nodes"])
    crossing = [item for item in oracle["intervals"] if int(item["end_s"]) - int(item["start_s"]) >= 2]
    inside = [item for item in oracle["intervals"] if int(item["end_s"]) == int(item["start_s"])]
    assert crossing and inside
    for item in oracle["intervals"]:
        assert item["energy_kj"] == float(builder.exact_energy(nodes, Fraction(item["start_s"]), Fraction(item["end_s"])))
    # Additivity of the exact integral, checked with rationals on a cut that is not a node.
    cut = Fraction(1143.3)
    whole = builder.exact_energy(nodes, Fraction(0), Fraction(3768))
    assert builder.exact_energy(nodes, Fraction(0), cut) + builder.exact_energy(nodes, cut, Fraction(3768)) == whole


def test_oracle_campaigns_cover_full_partial_and_null_acceptance(table):
    oracle = table["oracle"]
    assert {name: len(ends) for name, ends in oracle["partitions"].items()} == {
        "whole": 1, "minutes": 63, "seconds": 3768, "irregular": 208}
    assert [float(builder.acceptance_share(i)) for i in range(5)] == [1.0, 0.5, 0.0, 0.25, 1.0]
    assert any(end != int(end) for end in oracle["partitions"]["irregular"])
    for name, ends in oracle["partitions"].items():
        assert ends == sorted(set(ends)) and ends[-1] == 3768.0
        full, partial = oracle["campaigns"][name]["full"], oracle["campaigns"][name]["partial"]
        assert full["scheduled_kj"] == partial["scheduled_kj"] == oracle["total_energy_kj"]
        assert full["accepted_kj"] == oracle["total_energy_kj"] and full["rejected_kj"] == 0.0
        assert 0.0 <= partial["accepted_kj"] <= partial["scheduled_kj"] and partial["rejected_kj"] >= 0.0
        assert partial["accepted_kj"] + partial["rejected_kj"] == pytest.approx(partial["scheduled_kj"], rel=1e-15)
        if name != "whole":
            assert partial["rejected_kj"] > 0.0


def test_total_agrees_with_the_published_value_within_its_uncertainty(table):
    """Experimental agreement only. The margin is 6.4 MJ; the numerical tolerance is elsewhere."""
    page = audit.fcd_page("Test016")
    printed_total = audit.page_value(page, "results", "Total Heat Released")
    assert (audit.as_number(printed_total), printed_total["uc"], printed_total["unit"]) == (115.1, 6.4, "MJ")
    published = table["published"]
    assert (published["total_heat_released_MJ"], published["expanded_uncertainty_MJ"]) == (115.1, 6.4)
    total_MJ = table["oracle"]["total_energy_kj"] / 1000.0
    assert abs(total_MJ - 115.1) <= 6.4 and published["inside_published_uncertainty"] is True
    assert published["table_minus_published_kj"] == pytest.approx(-6.345, abs=1e-9)
    # Nothing was scaled to reach it: the table keeps its own total, 6.3 kJ below the rounded print.
    assert total_MJ != 115.1
    # The numerical tolerance is eleven orders of magnitude below the experimental margin.
    assert published["numerical_tolerance_over_uncertainty"] < 1.0e-10
    assert table["oracle"]["numerical_tolerance"] == {
        "abs_kj": 1.0e-9, "rel": 1.0e-12,
        "basis": "double precision rounding of the trapezoids; it is not experimental uncertainty"}


def test_identity_text_is_bit_exact_and_covers_the_whole_content(table):
    source = table["source"]
    assert builder.identity(source) == table["expected_identity"]
    assert builder.identity_text(1.0) == "f64:000000000000f03f" and builder.identity_text(-0.0) == builder.identity_text(0)
    assert builder.identity_text(0.1 + 0.2) != builder.identity_text(0.3)
    seen = {table["expected_identity"]}
    for path in (["owner_id"], ["run_id"], ["negative_samples"], *(["provenance", key] for key in source["provenance"])):
        changed = json.loads(json.dumps(source))
        holder = changed if len(path) == 1 else changed[path[0]]
        holder[path[-1]] = holder[path[-1]] + "x"
        seen.add(builder.identity(changed))
    for index, key in ((0, "hrr_kw"), (1143, "hrr_kw"), (3768, "time_s")):
        changed = json.loads(json.dumps(source))
        changed["samples"][index][key] = math.nextafter(changed["samples"][index][key], math.inf)
        seen.add(builder.identity(changed))
    assert len(seen) == 1 + 3 + len(source["provenance"]) + 3
    for bad in (True, "caf\u00e9", 'a"b'):
        with pytest.raises(ValueError):
            builder.identity_text(bad)


# ---------------------------------------------------------------- isolation

def test_module_is_isolated_and_has_no_product_consumer():
    source = MODULE.read_text(encoding="utf-8")
    assert source.startswith("extends RefCounted\n")
    for forbidden in ("class_name", "@export", "@tool", "FileAccess", "load(", "preload(", "SimulationEngine",
                      "RoomModel", "FuelObjectModel", "CombustionSystem", "Engine.", "OS.", "Time.", "randf", "randi",
                      "get_node", "signal ", "await ", "print("):
        assert forbidden not in source, forbidden
    assert set(re.findall(r"\b[a-z_]+_enabled\b", source)) == set()
    public = re.findall(r"^func ([a-z]\w*)\(", source, re.M)
    assert public == ["open", "report", "hrr_kw", "propose", "confirm", "snapshot", "restore", "reset"]
    assert re.findall(r"^var (\w+)", source, re.M) == ["_source", "_fingerprint", "_times", "_hrr", "_prefix_kj", "_state"]
    users = []
    for folder in ("sim", "editor", "ui", "view", "scenarios", "scenes", "tools", "addons", "assets"):
        for path in (ROOT / folder).rglob("*"):
            if path != MODULE and path.is_file() and path.suffix in {".gd", ".tscn", ".tres", ".json", ".cfg"}:
                if "PrescribedObjectHrrSource" in path.read_text(encoding="utf-8", errors="ignore"):
                    users.append(path.relative_to(ROOT).as_posix())
    for path in (ROOT / "project.godot", ROOT / "Main.gd", ROOT / "scripts/check_product.py"):
        if path.is_file() and "PrescribedObjectHrrSource" in path.read_text(encoding="utf-8", errors="ignore"):
            users.append(path.name)
    # Since the diagnostic coupling bench, one module preloads it; the engine reaches that
    # module by path, behind a switch that is not exported, and never names this one.
    assert users == ["sim/fire/PrescribedThermalSourceCoupling.gd"]
    engine = (ROOT / "sim/core/SimulationEngine.gd").read_text(encoding="utf-8")
    assert "PrescribedObjectHrrSource" not in engine
    assert "var g3_prescribed_thermal_source_enabled: bool = false" in engine
    assert "@export var g3_prescribed_thermal_source_enabled" not in engine
    loaders = sorted(path.name for path in (ROOT / "tests/fixtures").glob("*.gd")
                     if "PrescribedObjectHrrSource" in path.read_text(encoding="utf-8"))
    assert loaders == ["g3_object_hrr_source.gd", "g3_object_hrr_thermal_coupling.gd"]


def test_module_carries_no_mass_chemistry_or_gas_coupling():
    """Rejected energy has no physical cause here: no oxygen, no mass, no species, no other fuel."""
    code = "\n".join(line.split("##")[0] for line in MODULE.read_text(encoding="utf-8").splitlines()).lower()
    for forbidden in ("oxygen", "o2", "deficit", "heptane", "hoc", "heat_of_combustion", "kg", "yield_", "co2",
                      "soot", "pyrolysis", "ventilation", "test021", "fsri"):
        assert forbidden not in code, forbidden
    # CO and FED appear once, as an approval that is declared false.
    assert code.count("fed") == code.count('"co_fed_approval": false') == 1
    # The only words about mass, species, composition and radiation are the names of what stays null.
    assert re.findall(r'"(mass\w*|species\w*|composition|radiative\w*)"', code) == [
        "mass_loss_rate", "species_yields", "composition", "radiative_fraction"]
    assert code.count("unknown[key] = null") == 1 and "!= type_nil" in code


def test_existing_fire_modules_were_not_edited_to_integrate_it():
    for name in ("PrescribedFuelReleaseModel", "FuelMassBudgetModel", "FuelObjectModel", "CombustionSystem",
                 "PrescribedSensiblePhaseController", "PrescribedRealSensiblePhaseController", "FireModel"):
        assert "PrescribedObjectHrrSource" not in (ROOT / f"sim/fire/{name}.gd").read_text(encoding="utf-8")


# ---------------------------------------------------------------- mutation plan

def test_mutation_plan_is_declared_with_unique_anchors_and_leaves_sources_untouched():
    raw = {path: path.read_bytes() for path in mutations.ASSETS}
    plan = mutations.declared()
    variants = mutations.prepared_variants({path: data.decode("utf-8") for path, data in raw.items()})
    assert len(plan) == len(variants) == 73
    assert all(isinstance(item[3], str) and len(item[3]) > 15 for item in plan.values())
    families = {}
    for name in plan:
        families[name[0]] = families.get(name[0], 0) + 1
    assert families == {"I": 3, "N": 5, "U": 6, "L": 6, "S": 5, "D": 5, "O": 4, "Q": 3, "F": 8, "V": 14,
                        "R": 4, "P": 3, "X": 7}
    assert len({text for _path, text in variants.values()}) == 73
    assert {path: path.read_bytes() for path in mutations.ASSETS} == raw


@pytest.mark.parametrize("stdout,stderr,code", [
    ("Parse Error", "", 1),
    (PREFIX + ' {"failures":["x"]}', "SCRIPT ERROR: Invalid access", 1),
    (PREFIX + ' {"failures":[]}', "", 1),
    (PREFIX + ' {"failures":["x"]}', "", 0),
    ("", "", 1),
])
def test_syntax_runtime_or_inconsistent_exit_never_counts_as_a_kill(stdout, stderr, code):
    with pytest.raises(RuntimeError):
        mutations.classify(stdout, stderr, code, PREFIX)


def test_only_a_completed_run_with_failed_checks_is_a_kill():
    assert mutations.classify(PREFIX + ' {"failures":["G02 uneven"]}', "", 1, PREFIX)[0] == "killed"
    assert mutations.classify(PREFIX + ' {"failures":[]}\n' + PREFIX + "_PASS", "", 0, PREFIX)[0] == "pass"


# ---------------------------------------------------------------- the real GDScript owner

def test_actual_gdscript_owner_against_analytic_tables_and_the_exact_oracle(table):
    from scripts import godot_monitored_launch
    from tests.godot_runtime_launcher import run_godot

    godot = Path(os.environ.get("GODOT_EXE", r"C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe"))
    if not godot.exists():
        pytest.skip("Godot not found")
    if os.name == "nt":
        assert godot_monitored_launch._available_gib() >= 6.0, "Godot requires >=6 GiB"
    completed = run_godot([godot, "--headless", "--path", ROOT, "--script", FIXTURE],
                          timeout_s=300, allowed_exit_codes=(0,))
    assert "SCRIPT ERROR" not in completed.stdout + completed.stderr
    line = next(line for line in completed.stdout.splitlines() if line.startswith(PREFIX + " {"))
    report = json.loads(line.split(" ", 1)[1])
    assert report["failures"] == [] and PREFIX + "_PASS" in completed.stdout
    assert len(report["groups"]) == GROUPS and [name[:3] for name in report["groups"]] == [
        "G%02d" % index for index in range(1, GROUPS + 1)]
    assert report["checks"] == CHECKS
    # Judged again here, outside GDScript, against the oracle and the offline identity.
    oracle = table["oracle"]
    tolerance = builder.ABS_TOL_KJ + builder.REL_TOL * oracle["total_energy_kj"]
    measured = report["observations"]["measured"]
    assert measured["identity"] == table["expected_identity"] == builder.identity(table["source"])
    assert abs(measured["table_energy_kj"] - oracle["total_energy_kj"]) <= tolerance
    assert measured["peak_kw"] == oracle["peak"]["hrr_kw"]
    for name, modes in oracle["campaigns"].items():
        for mode, expected in modes.items():
            got = measured["campaigns"][name][mode]
            assert got["intervals"] == expected["intervals"] and got["time_s"] == expected["end_time_s"]
            assert got["scheduled_kj"] == measured["table_energy_kj"]
            for key in ("scheduled_kj", "accepted_kj", "rejected_kj"):
                assert abs(got[key] - expected[key]) <= tolerance, (name, mode, key)
            assert abs(got["accepted_kj"] + got["rejected_kj"] - got["scheduled_kj"]) <= tolerance
            assert got["accepted_kj"] >= 0.0 and got["rejected_kj"] >= 0.0
    assert abs(measured["table_energy_kj"] / 1000.0 - 115.1) <= 6.4
