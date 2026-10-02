#!/usr/bin/env python3
"""Engine mutation audit of the balance observables (``g3_balance_v1``).

Each mutant changes the ENGINE by exact text replacement (every anchor must
occur exactly once), runs one instrumented control (switch ON, ledger v3)
through the monitored launcher, evaluates ``analyze_g3_balance_ledger`` on
the engine ledger and restores the original bytes (SHA-256 verified) before
the next mutant, also after an error. One Godot at a time, >= 6 GiB free, no
pre-existing Godot process or error dialog.

A mutant is valid only if it compiles and runs, and it is caught only if the
finding it targets appears and was absent in the unmutated control. Any other
new finding is reported, not counted as its detection.

    python scripts/simulation/run_g3_balance_mutations.py \
        --baseline runs/g3_optd_balinstr_on_.../o2_closed
"""

from __future__ import annotations

import argparse
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
import analyze_g3_balance_ledger as bal  # noqa: E402

COMBUSTION = "sim/fire/CombustionSystem.gd"
OXYGEN = "sim/core/OxygenExchangeSystem.gd"
CASE = "o2_closed"

MUTANTS = {
    # A pool loss the ledger never sees: the pool shrinks after its last observed write.
    "MB1_pool_loss_omitted": {
        "file": COMBUSTION,
        "edits": [(
            "\t\t_g3_ledger_note(room, {\"bal_pool\": g3_bal_pool})\n",
            "\t\t_g3_ledger_note(room, {\"bal_pool\": g3_bal_pool})\n"
            "\troom.retained_unburned_MJ *= 0.999\n",
        )],
        "target": "P_unrecorded_change",
    },
    # A carbon scale acts on the species and is not written. The unmutated clamp
    # never acts in this control, so the mutant makes it act at half the carbon
    # (a valid engine change) and drops the two lines that record its scale.
    "MB2_carbon_scale_unrecorded": {
        "file": COMBUSTION,
        "edits": [(
            "\tif c_clamp_kg > 0.0 and c_total > c_clamp_kg:\n"
            "\t\tvar c_scale: float = c_clamp_kg / c_total\n"
            "\t\tif g3_fuel_ledger_enabled:\n"
            "\t\t\tg3_bal_species[\"carbon_clamp\"][\"applied\"] = true\n"
            "\t\t\tg3_bal_species[\"carbon_clamp\"][\"scale\"] = c_scale\n",
            "\tif c_clamp_kg > 0.0 and c_total > c_clamp_kg * 0.5:\n"
            "\t\tvar c_scale: float = c_clamp_kg * 0.5 / c_total\n",
        )],
        "target": "S_carbon_scale_unrecorded",
    },
    # The fire's O2 debit is cut below min(requested, cap) with nothing declaring it.
    "MB3_o2_truncation_undeclared": {
        "file": OXYGEN,
        "edits": [(
            "\t\t\t\tplume_consumed = minf(plume_consumed, lower_air_mass * room.o2_lower * FIRE_SINK_PLUME_CAP_FRACTION)\n",
            "\t\t\t\tplume_consumed = minf(plume_consumed, lower_air_mass * room.o2_lower * FIRE_SINK_PLUME_CAP_FRACTION)\n"
            "\t\t\t\tplume_consumed *= 0.5\n",
        )],
        "target": "O_truncation_undeclared",
    },
    # CO is computed on the target instead of on the solid heat.
    "MB4_co_on_the_wrong_basis": {
        "file": COMBUSTION,
        "edits": [(
            "\tvar co_basis_kw: float = actual_solid_burn_kw + pool_co_basis_kw + retained_co_basis_kw\n",
            "\tvar co_basis_kw: float = (fresh_flame_target_kw + smolder_target_kw) + pool_co_basis_kw + retained_co_basis_kw\n",
        )],
        "target": "S_co_basis_rule",
    },
}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def findings(case_dir: Path) -> dict:
    report = bal.analyze_case(case_dir)
    return {item["code"]: {"steps": item["steps"], "amount": item["amount"]} for item in report["findings"]}


def run(baseline_case: Path, selected: list[str] | None) -> int:
    names = selected or list(MUTANTS)
    originals = {}
    for name in names:
        spec = MUTANTS[name]
        path = ROOT / spec["file"]
        originals.setdefault(spec["file"], path.read_bytes())
        text = originals[spec["file"]].decode("utf-8")
        for old, _new in spec["edits"]:
            if text.count(old) != 1:
                raise RuntimeError(f"{name}: mutation anchor found {text.count(old)} times")
    shas = {relative: _sha(data) for relative, data in originals.items()}
    base = findings(baseline_case)
    results = {"baseline": {"case_dir": str(baseline_case), "findings": base}}
    try:
        for name in names:
            spec = MUTANTS[name]
            path = ROOT / spec["file"]
            mutated = originals[spec["file"]].decode("utf-8")
            for old, new in spec["edits"]:
                mutated = mutated.replace(old, new)
            path.write_bytes(mutated.encode("utf-8"))
            try:
                scenario = optd.cases()[CASE]
                scenario["engine_overrides"][batch.SWITCH] = True
                baseline.TIMEOUT_S = 900
                exit_code = baseline.run(
                    case_scenarios={CASE: scenario},
                    output_label=f"g3_balance_mut_{name}",
                    report_schema=f"g3_balance_mutation_{name}_v1",
                    extra_runner_args=[batch.LEDGER_ARG],
                )
            finally:
                path.write_bytes(originals[spec["file"]])
                if _sha(path.read_bytes()) != shas[spec["file"]]:
                    raise RuntimeError(f"{spec['file']} not restored byte for byte")
            run_root = sorted((ROOT / "runs").glob(f"g3_balance_mut_{name}_*"))[-1]
            found = findings(run_root / CASE)
            new = sorted(code for code in found if code not in base)
            outcome = {
                "run_root": str(run_root), "runner_exit": exit_code, "target": spec["target"],
                "target_in_baseline": spec["target"] in base,
                "caught": spec["target"] in found and spec["target"] not in base,
                "target_finding": found.get(spec["target"]), "new_findings": new,
            }
            results[name] = outcome
            print(json.dumps({name: outcome}, ensure_ascii=False), flush=True)
    finally:
        for relative, data in originals.items():
            if _sha((ROOT / relative).read_bytes()) != shas[relative]:
                (ROOT / relative).write_bytes(data)
    report = ROOT / "runs" / "g3_balance_mutations_report.json"
    report.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0 if all(results[name]["caught"] for name in names) else 3


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--baseline", type=Path, required=True, help="unmutated instrumented o2_closed run")
    parser.add_argument("--mutant", action="append", dest="mutants", choices=sorted(MUTANTS))
    args = parser.parse_args()
    try:
        raise SystemExit(run(args.baseline.resolve(), args.mutants))
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"G3 BALANCE MUTATIONS FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
