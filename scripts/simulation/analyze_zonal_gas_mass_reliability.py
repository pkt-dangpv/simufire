#!/usr/bin/env python3
"""H3.2-S0d6b0.2a - what the zonal gas masses are, on evidence that is not circular.

Read-only analyser over CSVs produced with `--phase3-zone-diagnostics` and
`--phase3-runtime-ownership-ledger`. It touches no engine file and runs no
simulation.

WITHDRAWN INFERENCE (2026-08-19, S0d6b0.2a)
-------------------------------------------
An earlier draft claimed that `gas_kg == volume_m3_eos * rho(T)` proved the mass
had been reconstructed by projection. That was **tautological and is withdrawn**.
`SimulationStateBuilder.gd:430-431` computes

    upper_volume_m3_eos = room.upper_gas_kg / upper_density_kg_m3
    lower_volume_m3_eos = room.lower_gas_kg / lower_density_kg_m3

so multiplying the exported volume back by the same density recovers the input by
construction. The counts it produced (20 059/20 059 and 11 863/11 863) measured
nothing but CSV rounding. The identity is retained ONLY as a self-consistency
check of the CSV, under the name SELF_DERIVED_EOS_IDENTITY, and it proves
nothing about independence, conservation or projection.

WHAT IS ACTUALLY EVIDENCE
-------------------------
1. STATIC, from code. `ZoneFireSolver.project_room_state()`:
   * `:264` caps `upper_gas_kg` at `volume * rho_upper`, but only when it
     exceeds that bound -- otherwise upper mass is carried through untouched;
   * `:266-268` derives `thermal_layer_m` FROM `upper_gas_kg`, so upper mass is
     the independent quantity and the interface follows it;
   * `:281` overwrites `lower_gas_kg` UNCONDITIONALLY with
     `remaining_volume * rho_lower`. Lower mass does not survive a projection
     call as an accumulated quantity.
   Both writes accumulate their difference into `two_zone_boundary_mass_kg`.

2. RUNTIME, and not self-derived. `two_zone_boundary_mass_kg` is a cumulative
   accumulator of exactly those two rewrites (`ZoneFireSolver.gd:265,282`). It is
   independent of the mass it corrects, and being cumulative it can be
   differenced across logged rows even though the log interval is 10 s. This is
   the only non-circular runtime measurement of projection available here.

WHAT REMAINS UNAVAILABLE
------------------------
A per-step causal mass balance. The committed cases log at `log_interval_s =
10.0` while every `*_mass_delta_kg_step` column covers one sub-step, so the two
cannot be differenced against each other. `causal_status` is therefore always
INCOMPLETE, and no room is ever RELIABLE.

DIMENSIONS REPORTED (never collapsed into one verdict)
------------------------------------------------------
  causal_status      INCOMPLETE | COMPLETE
  zone_presence      TWO_ZONE_PRESENT | UPPER_ZONE_ABSENT | LOWER_ZONE_ABSENT
                     | BOTH_ZONES_ABSENT | NONFINITE_OR_INVALID
  projection_evidence CODE_PROVEN_LOWER_RECONSTRUCTION | CODE_PROVEN_UPPER_CAP
                     | RUNTIME_TRACE_UNAVAILABLE

`UPPER_ZONE_ABSENT` is NOT a defect. A room with no hot layer is a valid
one-zone regime, and `ThermalSystem.gd:4553` already gates on it:
`in_upper = thermal_exposure_factor >= 0.5 and room.upper_gas_kg > 0.1`, so FED
reads `o2_lower` when the upper layer is absent or negligible.

Usage:
  python scripts/simulation/analyze_zonal_gas_mass_reliability.py <csv|dir> [...]
  python scripts/simulation/analyze_zonal_gas_mass_reliability.py <dir> --json-out out.json
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from pathlib import Path

PHYSICAL_STAGES = (
    "oxygen_exchange", "combustion", "thermal", "suppression",
    "gas_exchange", "hvac", "other",
)
CLOSURE_STAGES = ("reconcile", "projection_clamp")

REQUIRED = (
    "time_s", "room_id", "upper_gas_kg", "lower_gas_kg",
    "upper_volume_m3_eos", "lower_volume_m3_eos", "volume_closure_error_m3",
    "two_zone_boundary_mass_kg", "two_zone_boundary_mass_kg_step",
    "attribution_mass_residual_kg_step", "volume_m3",
    "temp_upper_c", "temp_lower_c",
) + tuple(f"{s}_mass_delta_kg_step" for s in PHYSICAL_STAGES + CLOSURE_STAGES)

AIR_DENSITY_REF_KG_M3 = 1.2      # ZoneFireSolver.AIR_DENSITY_REF_KG_M3
AMBIENT_K = 293.15

# ThermalSystem.gd:4553 - the real gate that decides whether any consumer reads
# the upper zone at all. Below it, FED and the other zone consumers read lower.
FED_UPPER_GATE_KG = 0.1

# The CSV self-consistency envelope. Temperature is written at %.2f
# (SimulationLogWriter.gd:1136-1137) and zone columns at %.8f (:1278), so a
# half-ulp of 0.005 K propagates into any density-based reconstruction. This is
# used ONLY to confirm the CSV is internally consistent; see the docstring.
TEMP_HALF_ULP_K = 0.005
VALUE_HALF_ULP = 0.5e-8


def eos_tolerance_rel(temp_c: float, value: float) -> float:
    t_k = max(50.0, temp_c + 273.15)
    quant = (VALUE_HALF_ULP / abs(value)) if value else 0.0
    return TEMP_HALF_ULP_K / t_k + 2.0 * quant


def _f(row: dict, key: str) -> float:
    try:
        return float(row[key])
    except (KeyError, TypeError, ValueError):
        return float("nan")


def rho_at(temp_c: float) -> float:
    """The engine's own gas law, ZoneFireSolver.gd:257/275."""
    return AIR_DENSITY_REF_KG_M3 * AMBIENT_K / max(50.0, temp_c + 273.15)


def analyse_csv(path: Path) -> dict:
    with path.open(encoding="utf-8", errors="replace", newline="") as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames or []
        missing = [c for c in REQUIRED if c not in header]
        if missing:
            return {"case": path.parent.name, "status": "INCOMPLETE",
                    "reason": "missing_columns", "missing_columns": missing,
                    "rooms": {}}
        rows = list(reader)

    times = sorted({_f(r, "time_s") for r in rows if math.isfinite(_f(r, "time_s"))})
    log_interval_s = (times[1] - times[0]) if len(times) > 1 else float("nan")

    rooms: dict[str, dict] = {}
    engine_residual_nonzero = 0
    engine_residual_max = 0.0

    for row in rows:
        rid = str(row.get("room_id", "")).strip()
        r = rooms.setdefault(rid, {
            "n": 0, "nominal": None,
            "upper_absent": 0, "lower_absent": 0, "both_absent": 0,
            "upper_below_fed_gate": 0, "invalid": 0,
            "min_upper": math.inf, "min_lower": math.inf,
            "eos_identity_checked": 0, "eos_identity_ok": 0,
            "worst_eos_margin": 0.0,
            "boundary_first": None, "boundary_last": None,
            "prev_total": None, "total_first": None, "total_last": None,
            "worst_volume_closure": 0.0,
        })
        res = abs(_f(row, "attribution_mass_residual_kg_step"))
        if math.isfinite(res):
            engine_residual_max = max(engine_residual_max, res)
            if res > 0.0:
                engine_residual_nonzero += 1

        up, lo = _f(row, "upper_gas_kg"), _f(row, "lower_gas_kg")
        vol = _f(row, "volume_m3")
        if r["nominal"] is None and math.isfinite(vol) and vol > 0:
            r["nominal"] = vol * AIR_DENSITY_REF_KG_M3

        # NONFINITE_OR_INVALID: the only genuine defect detectable here.
        if not (math.isfinite(up) and math.isfinite(lo)) or up < 0.0 or lo < 0.0:
            r["invalid"] += 1
            continue
        r["n"] += 1
        r["min_upper"] = min(r["min_upper"], up)
        r["min_lower"] = min(r["min_lower"], lo)

        upper_absent = up <= 0.0
        lower_absent = lo <= 0.0
        if upper_absent and lower_absent:
            r["both_absent"] += 1
        elif upper_absent:
            r["upper_absent"] += 1
        elif lower_absent:
            r["lower_absent"] += 1
        if up <= FED_UPPER_GATE_KG:
            r["upper_below_fed_gate"] += 1

        # SELF_DERIVED_EOS_IDENTITY - a CSV consistency check, never evidence.
        vu, vl = _f(row, "upper_volume_m3_eos"), _f(row, "lower_volume_m3_eos")
        tu, tl = _f(row, "temp_upper_c"), _f(row, "temp_lower_c")
        if all(math.isfinite(x) for x in (vu, vl, tu, tl)):
            for vzone, tzone, mass in ((vu, tu, up), (vl, tl, lo)):
                expected = vzone * rho_at(tzone)
                if expected > 0.0 and mass > 0.0:
                    r["eos_identity_checked"] += 1
                    rel = abs(mass - expected) / expected
                    tol = eos_tolerance_rel(tzone, mass)
                    r["worst_eos_margin"] = max(r["worst_eos_margin"], rel / tol)
                    if rel <= tol:
                        r["eos_identity_ok"] += 1

        vce = abs(_f(row, "volume_closure_error_m3"))
        if math.isfinite(vce):
            r["worst_volume_closure"] = max(r["worst_volume_closure"], vce)

        # Real, non-circular projection evidence: the cumulative boundary mass.
        bnd = _f(row, "two_zone_boundary_mass_kg")
        if math.isfinite(bnd):
            if r["boundary_first"] is None:
                r["boundary_first"] = bnd
            r["boundary_last"] = bnd
        total = up + lo
        if r["total_first"] is None:
            r["total_first"] = total
        r["total_last"] = total
        r["prev_total"] = total

    out = {
        "case": path.parent.name,
        "status": "OK",
        "log_interval_s": log_interval_s,
        "causal_status": "INCOMPLETE",
        "causal_status_reason": (
            "step deltas are sub-step samples while rows are "
            f"{log_interval_s:.1f} s apart; a per-step balance is not "
            "reconstructable from this sampling"
        ),
        "projection_evidence": [
            "CODE_PROVEN_LOWER_RECONSTRUCTION",
            "CODE_PROVEN_UPPER_CAP",
            "RUNTIME_TRACE_UNAVAILABLE",
        ],
        "engine_residual_identically_zero": engine_residual_nonzero == 0,
        "engine_residual_max_abs_kg": engine_residual_max,
        "rooms": {},
    }
    for rid, r in sorted(rooms.items(), key=lambda kv: kv[0]):
        n = max(1, r["n"])
        checked = max(1, r["eos_identity_checked"])
        if r["invalid"] > 0:
            presence = "NONFINITE_OR_INVALID"
        elif r["both_absent"] == r["n"] and r["n"]:
            presence = "BOTH_ZONES_ABSENT"
        elif r["upper_absent"] + r["both_absent"] == r["n"] and r["n"]:
            presence = "UPPER_ZONE_ABSENT"
        elif r["lower_absent"] + r["both_absent"] == r["n"] and r["n"]:
            presence = "LOWER_ZONE_ABSENT"
        else:
            presence = "TWO_ZONE_PRESENT"
        boundary_net = None
        if r["boundary_first"] is not None and r["boundary_last"] is not None:
            boundary_net = r["boundary_last"] - r["boundary_first"]
        out["rooms"][rid] = {
            "causal_status": "INCOMPLETE",
            "zone_presence": presence,
            "projection_evidence": [
                "CODE_PROVEN_LOWER_RECONSTRUCTION",
                "CODE_PROVEN_UPPER_CAP",
                "RUNTIME_TRACE_UNAVAILABLE",
            ],
            "steps_sampled": r["n"],
            "nominal_mass_kg": r["nominal"] or 0.0,
            "upper_absent_steps": r["upper_absent"] + r["both_absent"],
            "upper_absent_share": (r["upper_absent"] + r["both_absent"]) / n,
            "upper_below_fed_gate_steps": r["upper_below_fed_gate"],
            "lower_absent_steps": r["lower_absent"] + r["both_absent"],
            "invalid_steps": r["invalid"],
            "min_upper_gas_kg": None if r["min_upper"] is math.inf else r["min_upper"],
            "min_lower_gas_kg": None if r["min_lower"] is math.inf else r["min_lower"],
            "self_derived_eos_identity_holds": r["eos_identity_ok"] == r["eos_identity_checked"],
            "self_derived_eos_identity_checked": r["eos_identity_checked"],
            "self_derived_eos_identity_note":
                "CSV self-consistency only; volume_m3_eos is computed FROM gas_kg "
                "in SimulationStateBuilder.gd:430-431, so this proves nothing "
                "about independence, conservation or projection",
            "worst_eos_margin_vs_tolerance": r["worst_eos_margin"],
            # Run-length quantities only. Summing sub-step boundary deltas and
            # comparing them against interval mass differences would mix two
            # time bases -- the very error this revision exists to remove.
            "boundary_mass_net_kg": boundary_net,
            "total_mass_net_kg": (
                None if r["total_first"] is None
                else r["total_last"] - r["total_first"]),
            "boundary_net_over_nominal": (
                None if not r["nominal"] or boundary_net is None
                else boundary_net / r["nominal"]),
            "worst_volume_closure_error_m3": r["worst_volume_closure"],
        }
    return out


def collect(paths: list[str]) -> list[Path]:
    out: list[Path] = []
    for raw in paths:
        p = Path(raw)
        if p.is_dir():
            out.extend(sorted(p.glob("*/sim_log.csv")))
            if not out:
                out.extend(sorted(p.glob("sim_log.csv")))
        elif p.is_file():
            out.append(p)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--json-out")
    a = ap.parse_args(argv)

    files = collect(a.inputs)
    if not files:
        print("ERROR: no sim_log.csv found", file=sys.stderr)
        return 2
    results = [analyse_csv(p) for p in files]

    print("Zonal gas-mass audit (H3.2-S0d6b0.2a)")
    print("causal_status is INCOMPLETE everywhere: see module docstring.")
    print("The EOS identity is CSV self-consistency, NOT projection evidence.")
    print("UPPER_ZONE_ABSENT is a valid one-zone regime, not a defect.")
    print("FED reads the upper zone only when upper_gas_kg > %.1f kg "
          "(ThermalSystem.gd:4553)." % FED_UPPER_GATE_KG)
    print()
    print(f"{'case':<28} {'room':>4} {'zone_presence':<21} {'up_absent':>10} "
          f"{'<FEDgate':>9} {'bnd_net_kg':>12} {'bnd/nominal':>12}")
    tally: dict[str, int] = {}
    for res in results:
        if res["status"] == "INCOMPLETE":
            tally["MISSING_COLUMNS"] = tally.get("MISSING_COLUMNS", 0) + 1
            print(f"{res['case']:<28} {'-':>4} {'MISSING_COLUMNS':<21}")
            continue
        for rid, r in res["rooms"].items():
            tally[r["zone_presence"]] = tally.get(r["zone_presence"], 0) + 1
            bn = r["boundary_mass_net_kg"]
            ratio = r["boundary_net_over_nominal"]
            ratio = float("nan") if ratio is None else ratio
            print(f"{res['case']:<28} {rid:>4} {r['zone_presence']:<21} "
                  f"{100*r['upper_absent_share']:>9.1f}% "
                  f"{r['upper_below_fed_gate_steps']:>9} "
                  f"{(bn if bn is not None else float('nan')):>12.4e} "
                  f"{ratio:>12.2f}")

    print("\nzone_presence tally:")
    for k in ("TWO_ZONE_PRESENT", "UPPER_ZONE_ABSENT", "LOWER_ZONE_ABSENT",
              "BOTH_ZONES_ABSENT", "NONFINITE_OR_INVALID", "MISSING_COLUMNS"):
        if k in tally:
            print(f"  {k:<24} {tally[k]}")
    ok = [r for r in results if r["status"] == "OK"]
    zero = sum(1 for r in ok if r["engine_residual_identically_zero"])
    print(f"\ncausal_status: INCOMPLETE in {len(ok)}/{len(ok)} cases")
    print(f"engine attribution residual identically zero in {zero}/{len(ok)} cases")
    print("  -> it counts reconcile and projection_clamp as attribution, so it")
    print("     cannot fail and carries no conservation information")

    if a.json_out:
        Path(a.json_out).write_text(
            json.dumps({"results": results, "tally": tally}, indent=1),
            encoding="utf-8")
        print(f"\nwrote {a.json_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
