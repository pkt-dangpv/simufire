"""M2-T: earlier judged fixtures and nine OFF identities, safe sequential launches."""

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.simulation import run_g3_balance_identity as identity  # noqa: E402
from scripts.simulation import run_g3_o2_selection as m2  # noqa: E402
from scripts.simulation import run_g3_o2_transport_gate as gate  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    gate.prepare_environment(work)
    before_sources = gate.source_inventory()
    fixtures = {}
    for name, path, prefix in (
        ("M1", m2.INVENTORY_FIXTURE, m2.INVENTORY_PREFIX),
        ("M2", m2.FIXTURE, m2.PREFIX),
        ("M2-V", "tests/fixtures/g3_o2_venting.gd", "G3_O2_VENTING"),
    ):
        result = m2._launch(path, prefix)
        if result["failure_count"] != 0 or not result["pass_marker"]:
            raise RuntimeError(f"{name} regression: {result['first_failures']}")
        fixtures[name] = result
        print(f"{name}: {result['checks']} checks, PASS", flush=True)
    existing = set((ROOT / "runs").glob("g3_balance_identity_off_ledgeroff_*"))
    if identity.run("off", False, args.reference.resolve(), None, None) != 0:
        raise RuntimeError("OFF identity changed")
    created = set((ROOT / "runs").glob("g3_balance_identity_off_ledgeroff_*")) - existing
    if len(created) != 1:
        raise RuntimeError("ambiguous new OFF identity run")
    record = json.loads((created.pop() / "identity_report.json").read_text(encoding="utf-8"))
    if record["identical_cases"] != record["total_cases"] or record["total_cases"] != 9:
        raise RuntimeError("nine OFF cases did not all match")
    if gate.source_inventory() != before_sources:
        raise RuntimeError("source changed during regressions")
    result = {"schema": "g3_o2_transport_m2t_regressions_v1", "sources": before_sources,
              "fixtures": fixtures, "off_identity": record, "launch_health": gate.verified_health(work)}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"regressions record: {args.out}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
