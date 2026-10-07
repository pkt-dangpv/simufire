"""Check that the controls of the cone benchmark audit notice a broken auditor.

Each variant rewrites one rule of the auditor in memory, inside a child process, and runs the
focused tests against it. Nothing is written to the repository. A variant counts as detected
only if the unchanged auditor passes and the variant fails a test; a variant that does not even
import is invalid, not detected. Offline: no Godot, no engine module.
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
MODULE = "scripts.simulation.audit_g3_cone_evaporation_benchmark"
SOURCE = ROOT / "scripts" / "simulation" / "audit_g3_cone_evaporation_benchmark.py"
TESTS = "tests/test_g3_cone_evaporation_benchmark.py"
INVALID = 97

VARIANTS = [
    ("nominal_relabelled_as_net_heat",
     '    raise Refusal("%s cannot be presented as %s" % (own, role))',
     '    return quantity'),
    ("assumed_term_counts_as_identified",
     '        if identification not in BOUNDING_CLASSES:',
     '        if identification == "unknown":'),
    ("incident_taken_as_absorbed",
     '    if not status["identified"]:\n        raise Refusal("incident irradiation is not absorbed heat',
     '    if False:\n        raise Refusal("incident irradiation is not absorbed heat'),
    ("runs_mixed",
     '    if len(runs) != 1:',
     '    if False:'),
    ("reading_outside_its_window",
     '    if not start <= time_s <= end:',
     '    if False:'),
    ("mass_validates_itself",
     '    return observable not in quantity.get("depends_on", [])',
     '    return True'),
    ("digitisation_passes_as_raw",
     '    if series_nature(series) != nature:',
     '    if False:'),
    ("series_without_declared_nature",
     '    if "digitisation of published figures" not in nature or "not raw data" not in nature:',
     '    if False:'),
    ("thermocouples_taken_as_mean",
     '    if not profile_measured:',
     '    if False:'),
    ("emitted_energy_counted_twice",
     '        demand = [stored[0] + emitted[0], stored[1] + emitted[1]]',
     '        demand = [stored[0] + 2.0 * emitted[0], stored[1] + 2.0 * emitted[1]]'),
    ("stored_energy_with_the_wrong_sign",
     '        low = middle * rise(lower_c) + top * rise(lower_c)\n        high = bottom * rise(lower_c) + (middle + top) * rise(limit_c)',
     '        low = -(middle * rise(lower_c) + top * rise(lower_c))\n        high = -(bottom * rise(lower_c) + (middle + top) * rise(limit_c))'),
    ("grams_accumulated_as_kilograms",
     '        total += rate * step / 1000.0',
     '        total += rate * step'),
    ("missing_reading_accumulated_as_zero",
     '            raise Refusal("a missing reading cannot be accumulated as if it were zero")',
     '            continue'),
    ("rate_differentiated_without_declaring_it",
     '    if not smoothing:',
     '    if False:'),
    ("absent_uncertainty_taken_as_zero",
     '    if any(part is None for part in parts):\n        return None',
     '    parts = [part or 0.0 for part in parts]'),
    ("liquid_clipped_to_its_support",
     '        return (net.enthalpy(liquid, celsius_to_kelvin(celsius), "liquid temperature")',
     '        return (net.enthalpy(liquid, min(celsius_to_kelvin(celsius), liquid[-1]["temperature_k"]), "liquid temperature")'),
    ("emission_approved_by_the_heating",
     '    if facts["frontier_identified"] and facts["initial_mass_reported"] and facts["gas_side_measured"]:',
     '    if facts["temperature_profile_measured"]:'),
    ("net_heat_approved_by_measured_irradiation",
     '    out["net_absorbed_heat"] = "GO" if facts["frontier_identified"] else "NO_GO_not_identified"',
     '    out["net_absorbed_heat"] = "GO" if facts["frontier_identified"] or facts["in_test_irradiation_measured"] else "NO_GO_not_identified"'),
    ("rim_ignored",
     '                if rim and (abs(x0 + lip_mm * dx) > half or abs(y0 + lip_mm * dy) > half):',
     '                if False and (abs(x0 + lip_mm * dx) > half or abs(y0 + lip_mm * dy) > half):'),
    ("window_past_the_support",
     '        if value + half <= support_limit_c:',
     '        if value + half <= support_limit_c + 40.0:'),
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
        package.audit_g3_cone_evaporation_benchmark = module
    except SystemExit:
        raise
    except Exception:  # the variant does not import: invalid, never detected
        return INVALID
    import pytest
    code = pytest.main([TESTS, "-q", "-x", "-p", "no:cacheprovider", "--basetemp", basetemp,
                        "--deselect", TESTS + "::test_the_auditor_holds_no_solver_and_no_fit"])
    return int(code)


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
    with tempfile.TemporaryDirectory(prefix="g3_cone_mutations_") as work:
        env = dict(os.environ, PYTHONUTF8="1")
        for index in range(-1, len(VARIANTS)):
            name = "unchanged" if index < 0 else VARIANTS[index][0]
            run = subprocess.run(
                [sys.executable, "-m", "scripts.simulation.run_g3_cone_benchmark_control_mutations",
                 "--child", str(index), "--basetemp", str(Path(work) / ("v%02d" % (index + 1)))],
                cwd=str(ROOT), env=env, capture_output=True, text=True)
            if index < 0:
                results[name] = "passes" if run.returncode == 0 else "FAILS"
                if run.returncode != 0:
                    print(run.stdout[-2000:])
                    break
            elif run.returncode == INVALID:
                results[name] = "invalid"
            else:
                results[name] = "detected" if run.returncode == 1 else ("SURVIVES" if run.returncode == 0 else "error %d" % run.returncode)
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
