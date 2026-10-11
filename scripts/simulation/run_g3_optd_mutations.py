#!/usr/bin/env python3
"""Mutation audit of the Gate B option-D prototype: each mutant must be caught.

Each mutant re-introduces one defect in ``sim/fire/CombustionSystem.gd`` by
exact text replacement (every ``old`` must occur exactly once), runs the one
control that exposes it (switch ON, ledger v3), evaluates the contract checks
on the ENGINE ledger and restores the original bytes (SHA-256 verified) before
the next mutant, also after an error. One Godot at a time through the
monitored launcher (>= 6 GiB free, no pre-existing error dialog).

A mutant is valid only if the check it targets fails; any other failing
check is reported, not counted as its detection.

    python scripts/simulation/run_g3_optd_mutations.py
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts" / "simulation"))

from scripts.simulation import run_g3_fuel_baseline as baseline  # noqa: E402
from scripts.simulation import run_g3_fuel_ledger_batch as batch  # noqa: E402
from scripts.simulation import run_g3_optd_controls as optd  # noqa: E402
import check_g3_option_d_contract as ck  # noqa: E402
from analyze_g3_fuel_ledger import load  # noqa: E402


TARGET = ROOT / "sim/fire/CombustionSystem.gd"
MUTANTS = {
    "MD1_r_silent_loss": {
        "edits": [(
            "\t\t\tobj.state = FuelObjectModelScript.State.BURNED_OUT\n"
            "\t\t\tif bool(flaming_before.get(key, false)) and int(obj.g3_r_tail_state) == 0 \\\n",
            "\t\t\tobj.state = FuelObjectModelScript.State.BURNED_OUT\n"
            "\t\t\tobj.g3_r_balance_MJ = 0.0\n"
            "\t\t\tif bool(flaming_before.get(key, false)) and int(obj.g3_r_tail_state) == 0 \\\n",
        )],
        "case": "low_power_vent",
        "target_check": "K4_no_silent_loss",
    },
    "MD2_foreign_flame_release": {
        "edits": [
            ("\t\tif int(obj.g3_r_tail_state) != 1:\n", "\t\tif int(obj.g3_r_tail_state) == 2:\n"),
            ("\t\t\t\tobj.g3_r_tail_state = 1\n", "\t\t\t\tpass\n"),
        ],
        "case": "low_power_vent",
        "target_check": "K3_no_foreign_flame",
    },
    "MD3_unbounded_tail": {
        "edits": [(
            "\t\tif float(r_new[key]) / tau_f_s * 1000.0 < tail_min_kw:\n",
            "\t\tif false:\n",
        )],
        "case": "low_power_vent",
        "target_check": "K5_bounded_post_depletion",
    },
    "MD4_double_use": {
        "edits": [(
            "\tvar base_kw: float = minf(request_kw, maxf(0.0, target_kw))\n",
            "\tvar base_kw: float = minf(request_kw, maxf(0.0, pyrolysis_kw))\n",
        )],
        "case": "o2_closed",
        "target_check": "K9_no_double_use",
    },
    "MD5_new_heat_without_o2": {
        "edits": [("\tif release_MJ > mass_headroom_MJ:\n", "\tif false:\n")],
        "case": "o2_stress_cap",
        "target_check": "K0R_release_in_truncated_step",
    },
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def evaluate(case_dir: Path) -> dict:
    v3 = load(case_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    v2 = [json.loads(line) for line in (case_dir / "fuel_source_ledger.jsonl").open(encoding="utf-8")]
    v2 = [row for row in v2 if row["room_id"] == 0]
    records = ck.records_from_engine(v3)
    failing = {name: len(v) for name, v in ck.run_all(records).items() if v}
    k0 = ck.k0_split(v3, v2)
    if k0["with_release"]:
        failing["K0R_release_in_truncated_step"] = len(k0["with_release"])
    k8 = ck.k8_mass_headroom(v3)
    if k8:
        failing["K8_mass_headroom"] = len(k8)
    return {"failing": failing, "k0_counts": {k: len(v) for k, v in k0.items()}}


def run() -> int:
    original = TARGET.read_bytes()
    original_sha = _sha(original)
    text = original.decode("utf-8")
    for name, spec in MUTANTS.items():
        for old, _new in spec["edits"]:
            if text.count(old) != 1:
                raise RuntimeError(f"{name}: mutation anchor found {text.count(old)} times")
    results = {}
    try:
        for name, spec in MUTANTS.items():
            mutated = text
            for old, new in spec["edits"]:
                mutated = mutated.replace(old, new)
            TARGET.write_bytes(mutated.encode("utf-8"))
            try:
                scenario = optd.cases()[spec["case"]]
                scenario["engine_overrides"][batch.SWITCH] = True
                baseline.TIMEOUT_S = 900
                baseline.run(
                    case_scenarios={spec["case"]: scenario},
                    output_label=f"g3_optd_mut_{name}",
                    report_schema=f"g3_optd_mutation_{name}_v1",
                    extra_runner_args=[batch.LEDGER_ARG],
                )
            finally:
                TARGET.write_bytes(original)
                if _sha(TARGET.read_bytes()) != original_sha:
                    raise RuntimeError("CombustionSystem.gd not restored byte for byte")
            run_root = sorted((ROOT / "runs").glob(f"g3_optd_mut_{name}_*"))[-1]
            outcome = evaluate(run_root / spec["case"])
            outcome["run_root"] = str(run_root)
            outcome["target_check"] = spec["target_check"]
            outcome["caught"] = spec["target_check"] in outcome["failing"]
            results[name] = outcome
            print(json.dumps({name: outcome}), flush=True)
    finally:
        if _sha(TARGET.read_bytes()) != original_sha:
            TARGET.write_bytes(original)
    report = ROOT / "runs" / "g3_optd_mutations_report.json"
    report.write_text(json.dumps(results, indent=2), encoding="utf-8")
    return 0 if all(r["caught"] for r in results.values()) else 3


if __name__ == "__main__":
    try:
        raise SystemExit(run())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 OPTD MUTATIONS FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
