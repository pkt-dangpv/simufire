"""Check that the controls of the object fire source audit notice a broken auditor.

Each variant rewrites one rule of the auditor in memory, inside a child process, and runs the
focused tests against it. Nothing is written to the repository. A variant counts as detected
only if the unchanged auditor passes and the variant fails a test; a variant that does not even
import is invalid, not detected. The comparison with the saved audit is left out, so that each
variant has to be noticed by a control of its own. Offline: no Godot, no engine module.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types

ROOT = Path(__file__).resolve().parents[2]
MODULE = "scripts.simulation.audit_g3_object_fire_source"
SOURCE = ROOT / "scripts" / "simulation" / "audit_g3_object_fire_source.py"
TESTS = "tests/test_g3_object_fire_source.py"
LEFT_OUT = ("test_the_saved_audit_is_the_audit_of_the_record",
            "test_the_published_aggregates_are_those_of_the_local_series",
            "test_the_auditor_holds_no_engine_no_solver_and_no_fit")
INVALID = 97

VARIANTS = [
    ("below_detection_taken_as_zero",
     '        return {"state": "below_detection", "value": None}',
     '        return {"state": "zero", "value": 0.0}'),
    ("unreadable_cell_taken_as_zero",
     '    except ValueError:\n        return {"state": "unknown", "value": None}',
     '    except ValueError:\n        return {"state": "zero", "value": 0.0}'),
    ("missing_sample_integrated_as_zero",
     '                raise Refusal("%s has no reading at %d s: absent is not zero" % (column, t))',
     '                value = 0.0'),
    ("unit_guessed",
     '        raise Refusal("unit %r is not a declared %s unit" % (unit, kind))',
     '        return float(value)'),
    ("runs_and_versions_mixed",
     '    if None in found or len(found) != 1:',
     '    if False:'),
    ("header_units_not_checked",
     '        if tuple(reader.fieldnames or ()) != tuple(FCD_COLUMNS):',
     '        if False:'),
    ("bytes_not_pinned",
     '    if digest != test["csv"]["sha256"]:',
     '    if False:'),
    ("broken_time_axis_accepted",
     '    if times != list(range(times[0], times[-1] + 1)):',
     '    if False:'),
    ("window_outside_the_support",
     '    if start < times[0] or end > times[-1] or end < start:',
     '    if False:'),
    ("table_extrapolated",
     '    if not samples[0][0] <= time_s <= samples[-1][0]:',
     '    if False:'),
    ("negative_samples_kept",
     '    samples = [[float(t - start), max(0.0, value)] for t, value in raw]',
     '    samples = [[float(t - start), value] for t, value in raw]'),
    ("clipping_bias_hidden",
     '    out["clip_bias_MJ"] = sum(v for _t, v in samples) / 1000.0 - signed',
     '    out["clip_bias_MJ"] = 0.0'),
    ("owner_left_out_of_the_fingerprint",
     '        "schema": TABLE_SCHEMA, "owner_id": owner_id, "run_id": test["run_id"],',
     '        "schema": TABLE_SCHEMA, "owner_id": "any", "run_id": test["run_id"],'),
    ("hrr_over_heat_presented_as_measured",
     '    return {"name": "mass loss rate from HRR over effective heat", "class": "calculated",',
     '    return {"name": "mass loss rate from HRR over effective heat", "class": "measured",'),
    ("relabelling_allowed",
     '    if quantity.get("class") != claimed:',
     '    if False:'),
    ("integrated_yield_used_as_a_law",
     '    raise Refusal("a yield integrated over %s cannot be evaluated at %.0f s"\n'
     '                  % (integrated.get("basis", "an undeclared window"), time_s))',
     '    return float(integrated["value"])'),
    ("set_assigned_to_one_of_its_items",
     '    if target_owner != candidate["owner_id"]:',
     '    if False:'),
    ("foreign_chemistry_accepted",
     '    if profile.get("material_id") not in candidate.get("approved_chemistry_profiles", []):',
     '    if False:'),
    ("reserved_run_used_to_fit",
     '    if run_id in candidate.get("reserved_runs", []):',
     '    if False:'),
    ("input_curve_proves_prediction",
     '    if input_run == check_run:',
     '    if False:'),
    ("fitted_run_used_as_external_check",
     '    if check_run in fitted_on:',
     '    if False:'),
    ("comparison_without_uncertainty",
     '    if printed["uc"] is None:',
     '    if False:'),
    ("hrr_go_approves_mass_loss",
     '        out["prescribed_mass_loss"] = ("NO_GO_figure_only_total_is_gravimetric" if facts["mass_series_in_figure"]',
     '        out["prescribed_mass_loss"] = (out["prescribed_hrr"] if facts["mass_series_in_figure"]'),
    ("totals_approve_a_yield_in_time",
     '    if facts["mass_series_numeric_same_run"] and facts["species_series_numeric_same_run"]:',
     '    if facts["species_series_numeric_same_run"]:'),
    ("rights_ignored",
     '    elif not facts["redistribution_verified"] or not facts["igniter_documented"] or not facts["uncertainty_published"]:',
     '    elif False:'),
    ("version_change_ignored",
     '    elif not facts["species_version_consistent"]:',
     '    elif False:'),
    ("repeat_runs_let_the_curve_travel",
     '    out["extrapolation"] = ("NO_GO_repeat_runs_differ_beyond_uncertainty" if facts["repeats_differ_beyond_uncertainty"]',
     '    out["extrapolation"] = ("GO" if facts["repeats_differ_beyond_uncertainty"]'),
    ("local_file_not_pinned",
     '    if sha256_file(path) != item["sha256"]:',
     '    if False:'),
]


def mutated_source(index: int) -> str:
    source = SOURCE.read_text(encoding="utf-8")
    if index < 0:
        return source
    _name, old, new = VARIANTS[index]
    if source.count(old) != 1:
        raise SystemExit(INVALID)
    return source.replace(old, new)


def child(index: int, basetemp: str) -> int:
    """Run the focused tests against one variant held only in memory."""
    sys.path.insert(0, str(ROOT))
    try:
        source = mutated_source(index)
        module = types.ModuleType(MODULE)
        module.__file__ = str(SOURCE)
        sys.modules[MODULE] = module
        exec(compile(source, str(SOURCE), "exec"), module.__dict__)
        import scripts.simulation as package
        package.audit_g3_object_fire_source = module
    except SystemExit:
        raise
    except Exception:  # the variant does not import: invalid, never detected
        return INVALID
    import pytest
    arguments = [TESTS, "-q", "-x", "-p", "no:cacheprovider", "--basetemp", basetemp]
    for name in LEFT_OUT:
        arguments += ["--deselect", TESTS + "::" + name]
    return int(pytest.main(arguments))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--child", type=int, default=None, help=argparse.SUPPRESS)
    parser.add_argument("--basetemp", default=None, help=argparse.SUPPRESS)
    parser.add_argument("--plan-only", action="store_true", help="list the variants and stop")
    args = parser.parse_args()
    if args.child is not None:
        return child(args.child, args.basetemp)
    if args.plan_only:
        print(json.dumps([name for name, _old, _new in VARIANTS], indent=1))
        return 0
    results = {}
    with tempfile.TemporaryDirectory(prefix="g3_object_source_mutations_") as work:
        env = dict(os.environ, PYTHONUTF8="1")
        for index in range(-1, len(VARIANTS)):
            name = "unchanged" if index < 0 else VARIANTS[index][0]
            run = subprocess.run(
                [sys.executable, "-m", "scripts.simulation.run_g3_object_source_control_mutations",
                 "--child", str(index), "--basetemp", str(Path(work) / ("v%02d" % (index + 1)))],
                cwd=str(ROOT), env=env, capture_output=True, text=True)
            if index < 0:
                results[name] = "passes" if run.returncode == 0 else "FAILS"
                if run.returncode != 0:
                    print(run.stdout[-2000:])
                    break
            elif run.returncode == INVALID:
                results[name] = "invalid"
            elif run.returncode == 1:
                results[name] = "detected"
            else:
                results[name] = "SURVIVES" if run.returncode == 0 else "error %d" % run.returncode
    summary = {
        "unchanged": results.get("unchanged"),
        "variants": len(VARIANTS),
        "detected": sum(value == "detected" for value in results.values()),
        "results": results,
    }
    print(json.dumps(summary, indent=1))
    ok = summary["unchanged"] == "passes" and summary["detected"] == len(VARIANTS)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
