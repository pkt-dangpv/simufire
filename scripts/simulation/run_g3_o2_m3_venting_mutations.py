"""Rejudge M2-V on M3, including explicit diagnostic-only transit coverage.

No historical record or fixture is rewritten. W08 is diagnostic API coverage,
not a claim that current product transport delays oxygen. Every control and
mutant uses the safe sequential M3 harness with exact source restoration.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path

from scripts.simulation import run_g3_o2_m3_reservation_mutations as safe
from scripts.simulation import run_g3_o2_room_inventory_mutations as machinery
from scripts.simulation import run_g3_o2_venting_mutations as old

FIXTURE = "tests/fixtures/g3_o2_m3_venting_regression.gd"


def classify_bounded_assertions(stdout, stderr, returncode, prefix):
    """The inherited fixture keeps at most eight assertion messages per group.

    Reconcile that declared bound with the complete counters. Never accept a
    missing group, inconsistent total, parse error or non-assertion exit.
    """
    if "SCRIPT ERROR" in stdout + stderr or "Parse Error" in stdout + stderr:
        raise RuntimeError("script/parse error is never a valid kill")
    lines = [line[len(prefix) + 1:] for line in stdout.splitlines() if line.startswith(prefix + " ")]
    if len(lines) != 1:
        raise RuntimeError("fixture missing unique terminal payload")
    payload = json.loads(lines[0])
    failures, groups = payload.get("failures"), payload.get("failures_by_group")
    count = payload.get("failure_count")
    if (type(payload.get("checks")) is not int or payload["checks"] <= 0
            or not isinstance(failures, list) or any(not isinstance(item, str) for item in failures)
            or not isinstance(groups, dict) or type(count) is not int or count < 0
            or any(type(value) is not int or value <= 0 for value in groups.values())
            or sum(groups.values()) != count):
        raise RuntimeError("invalid complete assertion counters")
    kept = Counter(item[:3] for item in failures)
    if dict(kept) != {group: min(value, 8) for group, value in groups.items()}:
        raise RuntimeError("bounded assertion messages contradict complete counters")
    if returncode == 0 and count == 0:
        return "pass", payload
    if returncode == 1 and count > 0:
        return "killed", payload
    raise RuntimeError("termination is not a judged assertion result")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", required=True, type=Path)
    args = parser.parse_args()
    originals, variants = old.prepared()
    declared = machinery.plan(old.MUTATIONS, old.DECLARED_WITH_THE_STAGE)
    os.environ.update(old.JUDGED_ONLY)
    # Local to this Python invocation: preserve the frozen M3 classifier and
    # its byte-bound campaigns while recognizing this older fixture format.
    classifier = safe.classify
    try:
        safe.classify = classify_bounded_assertions
        safe.execute(args.work.resolve(), originals, variants, declared, fixture=FIXTURE,
                     prefix=old.PREFIX, schema="g3_m3_venting_regression_with_diagnostic_transit_v1")
    finally:
        safe.classify = classifier


if __name__ == "__main__":
    main()
