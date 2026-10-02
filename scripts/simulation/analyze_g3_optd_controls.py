#!/usr/bin/env python3
"""Read-only verdicts for the Gate B option-D engine runs (``--tag optd``).

* ON: contract checks K1-K9 on the ENGINE ledger, K0 split by cause, K8, and
  the predictions registered before the engine change (design 8.7 and 9.1).
* OFF: byte identity of every physics output against the pre-change run.

Predictions and tolerances are copied verbatim from the design; this script
reports pass/fail and never adjusts them.

    python scripts/simulation/analyze_g3_optd_controls.py --on runs/g3_optd_optd_on_X \
        --off runs/g3_optd_optd_off_Y --pre-off runs/g3_energy_pre_off_Z runs/g3_optd_pre_off_W \
        --pre-on runs/g3_energy_pre_on_A runs/g3_optd_pre_on_B
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_g3_option_d_contract as ck  # noqa: E402
import replay_g3_option_d as rp  # noqa: E402
from analyze_g3_fuel_ledger import load  # noqa: E402


IDENTITY_FILES = (
    "scenario.json", "sim_log.csv", "sim_log.txt", "events.json", "summary.json",
    "fuel_object_state_snapshot.json", "fuel_source_ledger.jsonl",
    "g3_fuel_ledger_v3.jsonl", "co_inventory_trace.jsonl",
)


def _find_case(roots: list[Path], case: str) -> Path | None:
    for root in roots:
        if (root / case / "g3_fuel_ledger_v3.jsonl").exists():
            return root / case
    return None


def _v2(case_dir: Path) -> list[dict]:
    rows = [json.loads(line) for line in (case_dir / "fuel_source_ledger.jsonl").open(encoding="utf-8")]
    return [row for row in rows if row["room_id"] == 0]


def _within(value: float, target: float, rel: float) -> bool:
    return abs(value - target) <= rel * abs(target)


def on_case(case_dir: Path, pre_on_dir: Path | None) -> dict:
    v3 = load(case_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
    records = ck.records_from_engine(v3)
    checks = {name: v for name, v in ck.run_all(records).items()}
    k0 = ck.k0_split(v3, _v2(case_dir))
    summary = rp.summarize(records)
    heat_applied = math.fsum(r["hrr_applied_kw"] * r["dt_s"] / 1000.0 for r in v3)
    out = {
        "checks": {name: len(v) for name, v in checks.items()},
        "first_violation": {name: v[0] for name, v in checks.items() if v},
        "K8_mass_headroom": len(ck.k8_mass_headroom(v3)),
        "K0": {name: len(v) for name, v in k0.items()},
        "K0_extinction_max_J": max((x[2] for x in k0["extinction"]), default=0.0),
        "K0_base_heat_MJ": math.fsum(x[1] for x in k0["base_heat"]) / ck.O2_KG_PER_MJ,
        "mass_limited_steps": sum(1 for r in v3 if (r.get("optd") or {}).get("mass_limited")),
        "released_in_power_permit_but_mass_limited_MJ": None,
        "C_MJ": summary["C_MJ"], "B_MJ": summary["B_MJ"], "B_over_C": summary["B_over_C"],
        "heat_applied_MJ": heat_applied,
        "R_peak_MJ": summary["R_peak_MJ"], "R_final_MJ": summary["R_final_MJ"],
        "R_final_by_owner_MJ": summary["R_final_by_owner_MJ"],
        "release_MJ": summary["release_MJ"], "closure_MJ": summary["closure_MJ"],
        "G_MJ": summary["G_MJ"], "U_MJ": summary["U_MJ"],
        "post_depletion": summary["post_depletion"],
        "last_time_s": v3[-1]["time_s"],
        "fire_extinguished_s": [r["time_s"] for r in v3 if r.get("fire_extinguished_this_step")],
    }
    if pre_on_dir is not None:
        pre = load(pre_on_dir / "g3_fuel_ledger_v3.jsonl", room_id=0)
        out["pre_on_B_MJ"] = math.fsum(r["actual_solid_burn_kw"] * r["dt_s"] / 1000.0 for r in pre)
    return out


def predictions(on: dict) -> list[dict]:
    """Design 8.7 (+ 9.1 for the stress case), verbatim tolerances."""
    rows = []

    def add(name, ok, measured, predicted):
        rows.append({"prediction": name, "pass": bool(ok), "measured": measured, "predicted": predicted})

    s = on.get("sofa_vent")
    if s:
        add("sofa_vent R_peak = 0.934 +-2%", _within(s["R_peak_MJ"], 0.934, 0.02), s["R_peak_MJ"], 0.934)
        add("sofa_vent R_final <= 1e-6 MJ", s["R_final_MJ"] <= 1e-6, s["R_final_MJ"], 1e-6)
        add("sofa_vent B/C >= 0.999", s["B_over_C"] >= 0.999, s["B_over_C"], 0.999)
    d = on.get("sofa_vent_dt24")
    if s and d:
        add("dt24 R_peak within 0.3% of dt12", _within(d["R_peak_MJ"], s["R_peak_MJ"], 0.003),
            d["R_peak_MJ"], s["R_peak_MJ"])
        add("dt24 sum B within 1% of dt12", _within(d["B_MJ"], s["B_MJ"], 0.01), d["B_MJ"], s["B_MJ"])
    lp = on.get("low_power_vent")
    if lp:
        info = lp["post_depletion"].get("g3_sofa", {})
        add("low_power R_d = 0.976 +-2%", _within(info.get("R_at_depletion_MJ") or 0.0, 0.976, 0.02),
            info.get("R_at_depletion_MJ"), 0.976)
        add("low_power tail heat = 0.936 +-2%", _within(info.get("heat_after_depletion_MJ", 0.0), 0.936, 0.02),
            info.get("heat_after_depletion_MJ"), 0.936)
        add("low_power tail duration = 63.9 +-1 s", abs(info.get("tail_duration_s", 0.0) - 63.9) <= 1.0,
            info.get("tail_duration_s"), 63.9)
        add("low_power R_final(sofa) <= 0.040 MJ", lp["R_final_by_owner_MJ"].get("g3_sofa", 0.0) <= 0.040,
            lp["R_final_by_owner_MJ"].get("g3_sofa"), 0.040)
    ta = on.get("two_active_vent")
    if ta:
        info = ta["post_depletion"].get("g3_sofa_a", {})
        add("two_active R_d = 0.188 +-2%", _within(info.get("R_at_depletion_MJ") or 0.0, 0.188, 0.02),
            info.get("R_at_depletion_MJ"), 0.188)
        add("two_active tail heat = 0.148 +-2%", _within(info.get("heat_after_depletion_MJ", 0.0), 0.148, 0.02),
            info.get("heat_after_depletion_MJ"), 0.148)
        add("two_active tail duration = 30.9 +-1 s", abs(info.get("tail_duration_s", 0.0) - 30.9) <= 1.0,
            info.get("tail_duration_s"), 30.9)
        add("two_active R_final(sofa_a) <= 0.040 MJ", ta["R_final_by_owner_MJ"].get("g3_sofa_a", 0.0) <= 0.040,
            ta["R_final_by_owner_MJ"].get("g3_sofa_a"), 0.040)
    for name in ("o2_closed", "o2_closed_dt24", "o2_reopen_300", "o2_reopen_700"):
        c = on.get(name)
        if not c:
            continue
        add(f"{name} double use = 0", c["checks"]["K9_no_double_use"] == 0, c["checks"]["K9_no_double_use"], 0)
        add(f"{name} K2 power permit clean", c["checks"]["K2_power_permit"] == 0, c["checks"]["K2_power_permit"], 0)
        add(f"{name} R never decreases while forbidden (K6)", c["checks"]["K6_hold_when_forbidden"] == 0,
            c["checks"]["K6_hold_when_forbidden"], 0)
        if "pre_on_B_MJ" in c:
            add(f"{name} sum B <= sum B of ON pre", c["B_MJ"] <= c["pre_on_B_MJ"] + 1e-9, c["B_MJ"], c["pre_on_B_MJ"])
    for name, c in on.items():
        failing = [k for k, v in c["checks"].items() if v and k != "K2_power_permit"]
        add(f"{name} K1,K3-K7,K9 clean", not failing, failing, [])
        add(f"{name} K0 only at extinction (<= 15 J, no release)",
            c["K0"]["with_release"] == 0 and c["K0"]["extinction_over_exception"] == 0
            and (c["K0"]["base_heat"] == 0 or name == "o2_stress_cap"),
            c["K0"], "with_release=0, extinction<=15 J")
        add(f"{name} K8 release <= O2 headroom", c["K8_mass_headroom"] == 0, c["K8_mass_headroom"], 0)
    return rows


def off_identity(off_root: Path, pre_roots: list[Path], cases: list[str]) -> dict:
    result = {}
    for case in cases:
        pre = _find_case(pre_roots, case)
        cur = off_root / case
        if pre is None or not cur.exists():
            result[case] = {"error": "missing pre or current case"}
            continue
        files = {}
        for name in IDENTITY_FILES:
            a, b = pre / name, cur / name
            if not a.exists() and not b.exists():
                continue
            if not a.exists() or not b.exists():
                files[name] = "missing"
                continue
            ha = hashlib.sha256(a.read_bytes()).hexdigest()
            hb = hashlib.sha256(b.read_bytes()).hexdigest()
            files[name] = "identical" if ha == hb else f"DIFFERENT {ha[:12]} != {hb[:12]}"
        result[case] = files
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--on", type=Path, required=True)
    parser.add_argument("--off", type=Path)
    parser.add_argument("--pre-off", type=Path, nargs="*", default=[])
    parser.add_argument("--pre-on", type=Path, nargs="*", default=[])
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    cases = sorted(p.name for p in args.on.iterdir() if (p / "g3_fuel_ledger_v3.jsonl").exists())
    on = {case: on_case(args.on / case, _find_case(args.pre_on, case)) for case in cases}
    report = {"on": on, "predictions": predictions(on)}
    if args.off is not None:
        report["off_identity"] = off_identity(args.off, args.pre_off, cases)
    text = json.dumps(report, indent=2, default=str)
    if args.out is not None:
        args.out.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
