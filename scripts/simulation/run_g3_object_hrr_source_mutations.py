"""Predeclared mutations of the isolated prescribed object HRR source, run in Godot.

Each variant is written to an isolated copy of the module, its fixture and the measured
table; the working sources are never edited. Every mutant states, before any run, the
defect it injects. A kill is a fixture that ran to the end and reported failed checks. A
parse error, a script error, a timeout or a monitor fault is recorded as invalid, never as
a kill. The campaign goes on after a survivor so each can be reviewed, and fails unless
every declared mutant is killed and the working sources keep their SHA-256.

Families: I interpolation, N integration, U units, L declared conventions, S support,
D double confirmation, O owner, Q queue of rejected energy, F identity, V validation,
R restore and reset, P purity of a proposal, X controls that move a number of the oracle
or of the table to show the fixture reads it.

    python scripts/simulation/run_g3_object_hrr_source_mutations.py --plan-only
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import godot_monitored_launch, run_scenario  # noqa: E402
from scripts.simulation.run_g3_fuel_mass_budget_mutations import classify  # noqa: E402

MODULE = ROOT / "sim/fire/PrescribedObjectHrrSource.gd"
FIXTURE = ROOT / "tests/fixtures/g3_object_hrr_source.gd"
TABLE = ROOT / "tests/fixtures/g3_object_hrr_source_test016.json"
ASSETS = [MODULE, FIXTURE, TABLE]
PREFIX = "G3_OBJECT_HRR_SOURCE"

_VALUE = "return (1.0 - a) * _hrr[segment] + a * _hrr[segment + 1]"
_TRAPEZOID = "return KJ_PER_KW_S * (hi - lo) * (0.5 * left + 0.5 * right)"
_UNIT = "const KJ_PER_KW_S: float = 1.0"
_LITERAL = "_literal(s.get(key), SOURCE_LITERALS[key], key, errors)"
_END_OF_SUPPORT = ('if end > _support_end():\n\t\treturn _refusal(["the interval ends outside the approved '
                   'support; nothing is extrapolated, held or clipped"])')
_VALUE_SUPPORT = ('if errors.is_empty() and at > _support_end():\n\t\terrors.append("time is outside the '
                  'approved support; nothing is extrapolated or held")')
_CLOCK = '"time_s": float(rebuilt["end_time_s"]),'
_IDENTITY = "_fingerprint = (VERSION + _serialize(canonical)).sha256_text()"
_NUMBER = "if not _finite(number) or number < 0.0:"
_KEYS = ('\tif value.size() != keys.size():\n\t\terrors.append(label + " has missing or extra fields")\n'
         '\tfor key: String in keys:\n\t\tif not value.has(key):\n\t\t\terrors.append(label + " is missing " + key)\n'
         '\tfor key: Variant in value:\n\t\tif typeof(key) != TYPE_STRING or key not in keys:\n'
         '\t\t\terrors.append(label + " has an unsupported key")\n')
_OFFER = 'return {"valid": true, "errors": [], "proposal": {'
_RESET = ('_state = {"generation": int(_state["generation"]) + 1, "time_s": 0.0,\n'
          '\t\t"scheduled_kj": 0.0, "accepted_kj": 0.0, "rejected_kj": 0.0}')
_ENERGY = ('var energy: float = _interval_kj(start, end)\n\tif not _finite(energy) or energy < 0.0 or not _near('
           'float(_state["scheduled_kj"]) + energy, _cumulative_kj(end)):')


def _without(key: str) -> str:
    return ('var reduced: Dictionary = canonical.duplicate(true)\n\treduced.erase("%s")\n\t'
            "_fingerprint = (VERSION + _serialize(reduced)).sha256_text()" % key)


def _unchecked(key: str) -> str:
    return 'if key != "%s":\n\t\t\t%s' % (key, _LITERAL)


# name: (file, old, new, the defect it injects)
MUTATIONS = {
    # --- I: interpolation -----------------------------------------------------------
    "I01_left_value_held_inside_a_segment": (
        MODULE, _VALUE, "return _hrr[segment]", "a step instead of the line between two samples"),
    "I02_right_value_taken_inside_a_segment": (
        MODULE, _VALUE, "return _hrr[segment + 1]", "the next sample instead of the line between two samples"),
    "I03_value_read_from_the_next_segment": (
        MODULE, "return clampi(_times.bsearch(time_s) - 1, 0, _times.size() - 2)",
        "return clampi(_times.bsearch(time_s), 0, _times.size() - 2)",
        "the line of the following segment prolonged backwards"),
    # --- N: integration -------------------------------------------------------------
    "N01_left_rectangle": (MODULE, _TRAPEZOID, "return KJ_PER_KW_S * (hi - lo) * left",
                           "left rectangle instead of the exact integral of a line"),
    "N02_right_rectangle": (MODULE, _TRAPEZOID, "return KJ_PER_KW_S * (hi - lo) * right",
                            "right rectangle instead of the exact integral of a line"),
    "N03_whole_segment_charged_to_a_partial_interval": (
        MODULE, "total += _segment_kj(_times, _hrr, segment, lo, hi)",
        "total += _segment_kj(_times, _hrr, segment, _times[segment], _times[segment + 1])",
        "an interval that ends inside a segment is charged the whole segment"),
    "N04_only_the_first_segment_of_an_interval": (
        MODULE, "while segment < _times.size() - 1 and _times[segment] < end:",
        "if segment < _times.size() - 1 and _times[segment] < end:",
        "an interval that crosses several nodes keeps only its first segment"),
    "N05_cumulative_energy_not_accumulated": (
        MODULE, "prefix.append(prefix[i] + _segment_kj(times, hrr, i, times[i], times[i + 1]))",
        "prefix.append(_segment_kj(times, hrr, i, times[i], times[i + 1]))",
        "the energy since ignition is the energy of one segment"),
    # --- U: units -------------------------------------------------------------------
    "U01_megajoules_reported_as_kilojoules": (
        MODULE, _UNIT, "const KJ_PER_KW_S: float = 0.001", "kW s converted with the factor of MJ"),
    "U02_joules_reported_as_kilojoules": (
        MODULE, _UNIT, "const KJ_PER_KW_S: float = 1000.0", "kW s converted with the factor of J"),
    "U03_kilowatt_hours_reported_as_kilojoules": (
        MODULE, _UNIT, "const KJ_PER_KW_S: float = 1.0 / 3600.0", "kW s converted with the factor of kWh"),
    "U04_power_unit_not_checked": (MODULE, _LITERAL, _unchecked("hrr_unit"), "a table in W or MW read as kW"),
    "U05_time_unit_not_checked": (MODULE, _LITERAL, _unchecked("time_unit"), "a table in minutes read as seconds"),
    "U06_energy_unit_not_checked": (MODULE, _LITERAL, _unchecked("energy_unit"), "an energy unit other than kJ accepted"),
    # --- L: declared conventions ----------------------------------------------------
    "L01_interpolation_not_checked": (
        MODULE, _LITERAL, _unchecked("interpolation"), "a table declared as steps or held values read as linear"),
    "L02_outside_support_rule_not_checked": (
        MODULE, _LITERAL, _unchecked("outside_support"), "a table that asks to hold or extrapolate is accepted"),
    "L03_time_origin_not_checked": (
        MODULE, _LITERAL, _unchecked("time_origin"), "a table whose zero is not the ignition is accepted"),
    "L04_regime_not_checked": (MODULE, _LITERAL, _unchecked("regime"), "a table declared for an enclosure is accepted"),
    "L05_quantity_not_checked": (MODULE, _LITERAL, _unchecked("quantity"), "a modelled curve accepted as the measured one"),
    "L06_negative_declaration_not_checked": (
        MODULE, 'if typeof(s.get("negative_samples")) != TYPE_STRING or s["negative_samples"] not in NEGATIVE_DECLARATIONS:',
        "if false:", "the treatment of negative readings need not be declared"),
    # --- S: support -----------------------------------------------------------------
    "S01_interval_clipped_to_the_support_in_silence": (
        MODULE, _END_OF_SUPPORT, "if end > _support_end():\n\t\tend = _support_end()",
        "an interval past the end is shortened without saying so"),
    "S02_value_extrapolated_past_the_support": (
        MODULE, _VALUE_SUPPORT, "if false:\n\t\tpass", "the last line is prolonged past the end of the support"),
    "S03_last_value_held_past_the_support": (
        MODULE, _VALUE_SUPPORT, "at = minf(at, _support_end())", "the last value is held past the end of the support"),
    "S04_support_need_not_start_at_the_ignition": (
        MODULE, "if times[0] != 0.0:", "if false:", "a table shifted in time is accepted"),
    "S05_empty_interval_accepted": (
        MODULE, "if end <= start:", "if end < start:", "an interval without duration is offered and can be counted"),
    # --- D: double confirmation -----------------------------------------------------
    "D01_generation_of_a_proposal_not_checked": (
        MODULE, 'if typeof(p["generation"]) != TYPE_INT or p["generation"] != _state["generation"]:', "if false:",
        "an offer of an earlier state of the owner can be confirmed"),
    "D02_generation_not_advanced_by_a_confirmation": (
        MODULE, '"generation": int(_state["generation"]) + 1, ' + _CLOCK, '"generation": int(_state["generation"]), ' + _CLOCK,
        "a confirmation does not retire the other outstanding offers"),
    "D03_clock_not_advanced_by_a_confirmation": (
        MODULE, _CLOCK, '"time_s": float(_state["time_s"]),', "energy is counted and the interval stays where it was"),
    "D04_accepted_energy_counted_twice": (
        MODULE, '"accepted_kj": float(_state["accepted_kj"]) + accepted,',
        '"accepted_kj": float(_state["accepted_kj"]) + 2.0 * accepted,', "one confirmation adds its energy twice"),
    "D05_confirmation_not_written": (
        MODULE, "\t_state = candidate\n", "\tpass\n", "a confirmation answers yes and can be repeated without end"),
    # --- O: owner -------------------------------------------------------------------
    "O01_ownership_not_checked": (
        MODULE, 'return (_same_text(record["owner_id"], _source["owner_id"]) and _same_text(record["run_id"], '
                '_source["run_id"])\n\t\tand _same_text(record["source_fingerprint"], _fingerprint))', "return true",
        "an offer or a snapshot of another object, run or table is taken"),
    "O02_owner_name_not_checked": (
        MODULE, '_same_text(record["owner_id"], _source["owner_id"]) and ', "",
        "an offer that names another object is taken"),
    "O03_run_not_checked": (
        MODULE, ' and _same_text(record["run_id"], _source["run_id"])', "", "an offer that names another run is taken"),
    "O04_source_identity_not_checked": (
        MODULE, '\n\t\tand _same_text(record["source_fingerprint"], _fingerprint))', ")",
        "an offer bound to another content is taken"),
    # --- Q: queue of rejected energy ------------------------------------------------
    "Q01_rejected_energy_added_to_the_next_offer": (
        MODULE, _ENERGY, 'var energy: float = _interval_kj(start, end) + float(_state["rejected_kj"])\n'
                         "\tif not _finite(energy) or energy < 0.0:", "rejected energy is queued and offered again"),
    "Q02_partial_confirmation_leaves_the_interval_pending": (
        MODULE, "\tvar rejected: float = scheduled - accepted\n",
        "\tvar rejected: float = scheduled - accepted\n\tif rejected > 0.0:\n"
        '\t\treturn {"valid": true, "errors": [], "scheduled_this_step_kj": scheduled, '
        '"accepted_this_step_kj": accepted,\n\t\t\t"rejected_this_step_kj": rejected, "state": snapshot()}\n',
        "after a partial confirmation the whole interval is offered again"),
    "Q03_rejected_energy_not_recorded": (
        MODULE, '"rejected_kj": float(_state["rejected_kj"]) + rejected,', '"rejected_kj": float(_state["rejected_kj"]),',
        "what was not accepted disappears from the accounts"),
    # --- F: identity ----------------------------------------------------------------
    "F01_owner_left_out_of_the_identity": (MODULE, _IDENTITY, _without("owner_id"), "two objects with one table share identity"),
    "F02_run_left_out_of_the_identity": (MODULE, _IDENTITY, _without("run_id"), "two runs with one table share identity"),
    "F03_provenance_left_out_of_the_identity": (
        MODULE, _IDENTITY, _without("provenance"), "the same numbers from another file or version share identity"),
    "F04_samples_left_out_of_the_identity": (MODULE, _IDENTITY, _without("samples"), "two different curves share identity"),
    "F05_negative_declaration_left_out_of_the_identity": (
        MODULE, _IDENTITY, _without("negative_samples"), "a clipped and an unclipped table share identity"),
    "F06_numbers_rounded_in_the_identity": (
        MODULE, 'return "f64:" + PackedFloat64Array([number]).to_byte_array().hex_encode()', "return JSON.stringify(number)",
        "two neighbouring numbers share identity"),
    "F07_version_left_out_of_the_identity": (
        MODULE, _IDENTITY, "_fingerprint = _serialize(canonical).sha256_text()", "two versions of the contract share identity"),
    "F08_key_order_read_as_content": (
        MODULE, "\t\t\tkeys.sort()\n", "", "one content written in another order gets another identity"),
    # --- V: validation --------------------------------------------------------------
    "V01_negative_numbers_admitted": (
        MODULE, _NUMBER, "if not _finite(number):", "negative power, time or accepted energy is taken"),
    "V02_negative_numbers_clipped_in_the_module": (
        MODULE, "\tvar number: float = float(value)\n\t" + _NUMBER,
        "\tvar number: float = maxf(0.0, float(value))\n\tif not _finite(number):",
        "the module clips noise itself, undeclared"),
    "V03_non_finite_numbers_admitted": (MODULE, _NUMBER, "if number < 0.0:", "NaN or infinity is taken as a number"),
    "V04_booleans_admitted_as_numbers": (
        MODULE, "if typeof(value) not in [TYPE_FLOAT, TYPE_INT]:", "if typeof(value) not in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:",
        "true and false are read as 1 and 0"),
    "V05_sample_order_not_checked": (
        MODULE, "if not times.is_empty() and time_s <= times[times.size() - 1]:", "if false:",
        "a table with times out of order is accepted"),
    "V06_unknown_quantity_admitted_as_a_number": (
        MODULE, "if typeof(unknown.get(key)) != TYPE_NIL:",
        "if typeof(unknown.get(key)) not in [TYPE_NIL, TYPE_FLOAT, TYPE_INT]:", "an unknown quantity may be declared as zero"),
    "V07_unknown_quantity_reported_as_zero": (
        MODULE, "\t\tunknown[key] = null\n", "\t\tunknown[key] = 0.0\n", "the owner reports zero for what nobody measured"),
    "V08_undeclared_fields_admitted": (
        MODULE, _KEYS, '\tfor key: String in keys:\n\t\tif not value.has(key):\n\t\t\terrors.append(label + " is missing " + key)\n',
        "a scale, a shift, a mass or a yield rides along with the table"),
    "V09_provenance_not_required": (
        MODULE, '_text(provenance.get(key), "provenance." + key, errors)', "pass", "a table without provenance is accepted"),
    "V10_hash_format_not_checked": (
        MODULE, "if typeof(provenance.get(key)) == TYPE_STRING and not _is_digest(provenance[key]):", "if false:",
        "a provenance hash that is not a hash is accepted"),
    "V11_owner_not_required": (MODULE, '_text(s.get("owner_id"), "owner_id", errors)', "pass", "a table without owner is accepted"),
    "V12_single_sample_accepted": (
        MODULE, "if typeof(raw) != TYPE_ARRAY or raw.size() < 2:", "if typeof(raw) != TYPE_ARRAY or raw.size() < 1:",
        "one point is accepted as a curve"),
    "V13_acceptance_above_the_offer": (
        MODULE, "if accepted > scheduled:", "if false:", "more energy than proposed is accepted, with negative rejection"),
    "V14_second_source_replaces_the_first": (
        MODULE, 'if not _state.is_empty():\n\t\treturn _refusal(["already opened; use a new owner for another source"])',
        "if false:\n\t\tpass", "an owner changes table and loses its accounts"),
    # --- R: restore and reset -------------------------------------------------------
    "R01_snapshot_counters_not_checked": (
        MODULE, "if not _near(scheduled, _cumulative_kj(time_s)) or not _near(accepted + rejected, scheduled):", "if false:",
        "a snapshot that disagrees with the table is restored"),
    "R02_restore_keeps_the_old_generation": (
        MODULE, '"generation": maxi(int(_state["generation"]), int(s["generation"])) + 1, "time_s": time_s,',
        '"generation": int(s["generation"]), "time_s": time_s,', "offers issued before a restore stay valid"),
    "R03_reset_keeps_the_accepted_energy": (
        MODULE, _RESET, _RESET.replace('"accepted_kj": 0.0', '"accepted_kj": float(_state["accepted_kj"])'),
        "a restart at the ignition carries energy of the previous run"),
    "R04_reset_keeps_the_generation": (
        MODULE, '_state = {"generation": int(_state["generation"]) + 1, "time_s": 0.0,',
        '_state = {"generation": int(_state["generation"]), "time_s": 0.0,', "offers issued before a reset stay valid"),
    # --- P: purity of a proposal ----------------------------------------------------
    "P01_proposal_advances_the_clock": (
        MODULE, _OFFER, '_state["time_s"] = end\n\t' + _OFFER, "asking moves the clock"),
    "P02_proposal_counts_energy": (
        MODULE, _OFFER, '_state["accepted_kj"] = float(_state["accepted_kj"]) + energy\n\t' + _OFFER, "asking delivers energy"),
    "P03_altered_energy_of_a_proposal_not_checked": (
        MODULE, 'for key: String in ["start_time_s", "end_time_s", "dt_s", "energy_kj"]:',
        'for key: String in ["start_time_s", "end_time_s", "dt_s"]:', "an offer whose energy was edited is taken"),
}

# Controls of the fixture and of the table: a number moved by one part in a thousand million,
# far below the experimental uncertainty (5.6 %) and far above the numerical tolerance.
_PART = 1.0e-9
_SYNTHETIC = "[1.5, 7.0, 17.25]"


def controls(table: dict) -> dict:
    oracle = table["oracle"]
    peak = oracle["peak"]
    span = next(item for item in oracle["intervals"] if item["end_s"] - item["start_s"] == 2.5)
    # One part in 1e9 of a value must exceed the declared absolute tolerance to be a
    # defect at all: of the first point (0.405 kW) it is 4e-10 and no fixture should see it.
    point = max(oracle["between_nodes"], key=lambda item: item["hrr_kw"])
    if point["hrr_kw"] * _PART <= 100.0 * oracle["numerical_tolerance"]["abs_kj"]:
        raise ValueError("control X03 would move its value inside the declared tolerance")
    accepted = oracle["campaigns"]["irregular"]["partial"]["accepted_kj"]
    identity = table["expected_identity"]

    def moved(key: str, value: float) -> tuple[str, str]:
        return '"%s": %r' % (key, value), '"%s": %r' % (key, value * (1.0 + _PART))

    sample = '{"time_s": %r, "hrr_kw": %r}' % (peak["time_s"], peak["hrr_kw"])
    return {
        "X01_oracle_total_energy_moved": (
            TABLE, *moved("total_energy_kj", oracle["total_energy_kj"]), "the fixture does not read the oracle total"),
        "X02_oracle_interval_energy_moved": (
            TABLE, *moved("energy_kj", span["energy_kj"]), "the fixture does not read the oracle intervals"),
        "X03_oracle_value_between_nodes_moved": (
            TABLE, '"time_s": %r,\n    "hrr_kw": %r' % (point["time_s"], point["hrr_kw"]),
            '"time_s": %r,\n    "hrr_kw": %r' % (point["time_s"], point["hrr_kw"] * (1.0 + _PART)),
            "the fixture does not read the oracle values between nodes"),
        "X04_oracle_partial_acceptance_moved": (
            TABLE, *moved("accepted_kj", accepted), "the fixture does not read the oracle of the partial campaign"),
        "X05_expected_identity_altered": (
            TABLE, identity, ("0" if identity[0] != "0" else "1") + identity[1:], "the fixture does not read the identity"),
        "X06_one_sample_of_the_table_moved": (
            TABLE, "   " + sample, "   " + '{"time_s": %r, "hrr_kw": %r}' % (peak["time_s"], peak["hrr_kw"] * (1.0 + _PART)),
            "a table that is not the audited one passes"),
        "X07_analytic_expectation_moved": (
            FIXTURE, _SYNTHETIC, "[1.5, 7.0, 17.25000002]", "the fixture does not read its analytic answers"),
    }


def declared() -> dict:
    return {**MUTATIONS, **controls(json.loads(TABLE.read_text(encoding="utf-8")))}


def prepared_variants(sources: dict[Path, str]) -> dict[str, tuple[Path, str]]:
    variants = {}
    for name, (path, old, new, _defect) in declared().items():
        if sources[path].count(old) != 1:
            raise ValueError(f"{name}: anchor found {sources[path].count(old)} times, expected 1")
        variants[name] = (path, sources[path].replace(old, new))
        if variants[name][1] == sources[path]:
            raise ValueError(f"{name}: mutation changes nothing")
    return variants


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--only", action="append", default=[], help="run the control and these mutants")
    args = parser.parse_args()
    originals = {path: path.read_bytes() for path in ASSETS}
    variants = prepared_variants({path: raw.decode("utf-8") for path, raw in originals.items()})
    plan = {name: item[3] for name, item in declared().items()}
    if args.plan_only:
        print(json.dumps({"declared": len(plan), "executed": False, "defects": plan}, indent=1))
        return 0
    unknown = [name for name in args.only if name not in variants]
    if unknown:
        raise ValueError(f"unknown mutants: {unknown}")
    if args.only:
        variants = {name: variants[name] for name in args.only}
    godot = run_scenario._find_godot()
    if godot is None:
        raise RuntimeError("Godot unavailable")
    os.environ[godot_monitored_launch.MIN_AVAILABLE_GIB_ENV] = "6"
    evidence = ROOT / "runs" / ("g3_object_hrr_source_mutations_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S"))
    evidence.mkdir(parents=True, exist_ok=False)
    (evidence / "plan.json").write_text(json.dumps(plan, indent=1), encoding="utf-8")
    results = []
    try:
        for name, (changed, text) in {"control": (None, ""), **variants}.items():
            project = evidence / name
            for path, raw in originals.items():
                target = project / path.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(text.encode("utf-8") if path == changed else raw)
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="Isolated prescribed object HRR source"\n', encoding="utf-8")
            run = godot_monitored_launch.run(
                [godot, "--headless", "--path", project, "--script", project / FIXTURE.relative_to(ROOT)],
                timeout_s=300, environment=os.environ.copy())
            for filename, content in [("health.json", json.dumps(run.health, indent=2)),
                                      ("stdout.log", run.stdout), ("stderr.log", run.stderr)]:
                (project / filename).write_text(content, encoding="utf-8")
            if not run.launched:
                raise RuntimeError(f"{name}: not launched: {run.faults or run.preexisting}")
            payload, reason = {}, ""
            if run.faults or run.preexisting:
                verdict, reason = "invalid", f"monitor: {run.faults or run.preexisting}"
            else:
                try:
                    verdict, payload = classify(run.stdout, run.stderr, run.returncode, PREFIX)
                except (RuntimeError, ValueError) as exc:
                    verdict, reason = "invalid", str(exc)
            results.append({"name": name, "verdict": verdict, "reason": reason, "defect": plan.get(name),
                            "checks": payload.get("checks"), "failed_checks": len(payload.get("failures", [])),
                            "first_failures": payload.get("failures", [])[:3],
                            "source_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest() if changed else None})
            print(json.dumps({"name": name, "verdict": verdict, "reason": reason,
                              "failed_checks": len(payload.get("failures", []))}), flush=True)
            if name == "control" and verdict != "pass":
                raise RuntimeError("control is not green; no mutant verdict is meaningful")
    finally:
        after = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in ASSETS}
        before = {path.relative_to(ROOT).as_posix(): hashlib.sha256(raw).hexdigest() for path, raw in originals.items()}
        mutants = [item for item in results if item["name"] != "control"]
        summary = {
            "results": results, "originals_intact": after == before,
            "control": next((item["verdict"] for item in results if item["name"] == "control"), None),
            "declared": len(variants), "executed": len(mutants),
            "killed": sum(item["verdict"] == "killed" for item in mutants),
            "survivors": [item["name"] for item in mutants if item["verdict"] == "pass"],
            "invalid": [item["name"] for item in mutants if item["verdict"] == "invalid"],
            "sha256_before": before, "sha256_after": after,
        }
        (evidence / "results.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        print(json.dumps({key: summary[key] for key in ["control", "declared", "executed", "killed",
                                                        "survivors", "invalid", "originals_intact"]}), flush=True)
        if after != before:
            raise RuntimeError("working sources changed")
    return 0 if summary["killed"] == summary["declared"] == summary["executed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
