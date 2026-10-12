"""Named M4-A1 code mutants; safe sequential monitor and SHA-256 restoration.

Reuses the unchanged M3 owned-process harness. No engine integration verdict.
"""
import argparse
import json
from pathlib import Path

from scripts.simulation import run_g3_o2_m3_reservation_mutations as harness
from scripts.simulation import run_g3_o2_m4_partition as fixture

MODEL = fixture.MODEL
MUTATIONS = {
    "A01_wrong_growing_donor": (MODEL,
        "after_upper = upper + (total - upper) * (difference / old_lower_base)",
        "after_upper = upper + upper * (difference / old_lower_base)",
        "growing upper takes its own concentration", "analytic remap donor"),
    "A02_wrong_shrinking_donor": (MODEL,
        "after_upper = upper * (new_upper / old_upper_base)",
        "after_upper = total * (new_upper / base)",
        "reset shrinking upper to the room average", "analytic remap donor"),
    "A03_ambient_reset_on_collapse": (MODEL,
        "elif new_upper == base:\n\t\tafter_upper = total",
        "elif new_upper == base:\n\t\ttotal = base * 0.209\n\t\tafter_upper = total",
        "create ambient oxygen in a collapsed upper", "analytic remap donor"),
    "A04_mix_omitted": (MODEL,
        "var after_upper: float = upper + alpha * (target - upper)",
        "var after_upper: float = upper",
        "no zonal mixing", "analytic mix target"),
    "A05_mix_one_way": (MODEL,
        "var after_upper: float = upper + alpha * (target - upper)",
        "var after_upper: float = upper + alpha * maxf(0.0, target - upper)",
        "upper never donates", "mix donates in both directions"),
    "A06_missing_paired_delta": (MODEL,
        '"cause": cause, "upper_delta_kg": du, "lower_delta_kg": dl, "room_delta_kg": du + dl}',
        '"cause": cause, "upper_delta_kg": du, "lower_delta_kg": 0.0, "room_delta_kg": du + dl}',
        "receipt omits the donating lower", "mix P3 lower"),
    "A07_budget_total_not_updated": (MODEL,
        'after["total_kg"] = upper + lower',
        'after["total_kg"] = float(state["total_kg"])',
        "zonal debit does not reach room total", "budget P1 room"),
    "A08_negative_upper_accepted": (MODEL,
        "if total < 0.0 or upper < 0.0 or upper > total:",
        "if total < 0.0 or upper > total:",
        "accept tiny negative upper below audit tolerance", "invalid state range rejected"),
    "A09_capacity_check_omitted": (MODEL,
        "if upper > upper_base or total - upper > lower_base:",
        "if false:", "allow overfilled or absent zones", "invalid state range rejected"),
    "A10_bool_is_number": (MODEL,
        "(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))",
        "(typeof(value) == TYPE_BOOL or typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))",
        "treat boolean as oxygen", "invalid state number"),
    "A11_absent_is_zero": (MODEL,
        '"upper": upper / upper_base if upper_base > 0.0 else null,',
        '"upper": upper / upper_base if upper_base > 0.0 else 0.0,',
        "report empty layer as zero oxygen", "absent zone is null not zero or epsilon"),
    "A12_result_aliases_receipt": (MODEL,
        'return {"valid": true, "state": after.duplicate(true),\n'
        '\t\t"receipt": {"before": before.duplicate(true), "after": after.duplicate(true),',
        'return {"valid": true, "state": after,\n'
        '\t\t"receipt": {"before": before.duplicate(true), "after": after,',
        "return state aliases receipt after", "receipt after snapshot isolated"),
    "A13_mix_ignores_range": (MODEL,
        "if alpha < 0.0 or alpha > 1.0:",
        "if false:", "allow arbitrary mixing fraction", "mix outside unit interval rejected"),
    "A14_ambient_ceiling": (MODEL,
        'after["upper_kg"] = after_upper',
        'after["upper_kg"] = minf(after_upper, float(state["upper_base_kg"]) * 0.209)',
        "discard an oxygen-rich upper", "no ambient ceiling"),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=Path)
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    originals, variants = harness.machinery.prepared(MUTATIONS, (MODEL,))
    declared = harness.machinery.plan(MUTATIONS, tuple(MUTATIONS))
    if args.plan_only:
        print(json.dumps(declared, indent=2))
        return
    fixture_before = harness.sha((harness.ROOT / fixture.FIXTURE).read_bytes())
    try:
        harness.execute(args.work.resolve(), originals, variants, declared,
                        fixture=fixture.FIXTURE, prefix=fixture.PREFIX,
                        schema="g3_m4_pure_partition_mutations_v1", integration=False)
    finally:
        result_path = args.work.resolve() / "results.json"
        if result_path.exists():
            record = json.loads(result_path.read_text(encoding="utf-8"))
            fixture_after = harness.sha((harness.ROOT / fixture.FIXTURE).read_bytes())
            record.update({"fixture_sha256_before": fixture_before, "fixture_sha256_after": fixture_after})
            result_path.write_text(json.dumps(record, indent=2), encoding="utf-8")
            if fixture_before != fixture_after:
                raise RuntimeError("fixture changed during the mutation campaign")


if __name__ == "__main__":
    main()
