"""
Phase 4A diagnostic sweep for the rejected HVAC HRR blend candidate.

Usage:
    py tools/phase4a_blend_sweep.py

This script was used to test the temporary candidate where
fire_o2_upper_hrr_blend also affected the fire_o2_lower_for_flame path.
That engine candidate was rejected and reverted:

- CO2_upper remained far outside tolerance at t=300/t=450.
- CO_upper at t=450 still exceeded tolerance.
- blend=1.0 broke required o2_upper and t180 temp_upper checks.

The artifact is kept to document the diagnostic method and reproduce the
rejection only if the temporary candidate patch is re-applied. It does not
commit anything and restores the case JSON to its original state.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

WORKSPACE = Path(__file__).resolve().parents[1]
GODOT_EXE = r"C:\Users\dangp\Desktop\Godot_v4.6.3-stable_win64_console.exe"
CASE_JSON = WORKSPACE / "sim/validation/cases/cfast_hvac_residential.json"
LOG_FILE  = WORKSPACE / "sim/validation/reports/cfast_hvac_residential.log"
CFAST_REF = {
    "t180": {"o2_upper": 0.1323, "o2_lower": 0.2049, "co_upper": 380.4,  "co2_upper_pct": 6.106, "temp_upper": 259.6},
    "t300": {"o2_upper": 0.0737, "o2_lower": 0.2049, "co_upper": 661.3,  "co2_upper_pct": 10.616,"temp_upper": 173.4},
    "t450": {"o2_upper": 0.0530, "o2_lower": 0.2049, "co_upper": 731.5,  "co2_upper_pct": 11.743,"temp_upper": 174.8},
}
# Required check tolerances (from validate_reference_cases.py)
REQUIRED_TOLS = {
    "o2_upper_t180": 0.025, "o2_upper_t300": 0.025, "o2_upper_t450": 0.045,
    "o2_lower_t180": 0.010, "o2_lower_t300": 0.010, "o2_lower_t450": 0.010,
    "co_upper_t180":  500.0, "temp_upper_t180": 80.0,
}

BLEND_VALUES = [0.0, 0.25, 0.50, 0.75, 1.00]
TARGETS = [180, 300, 450]

LOG_PATTERN = re.compile(
    r"^ROOM 0.*?"
    r"HRR=(?P<hrr>[\d.]+).*?"
    r"Up=(?P<temp_upper>[\d.]+).*?"
    r"O2=(?P<o2>[\d.]+).*?"
    r"O2u=(?P<o2_upper>[\d.]+).*?"
    r"O2l=(?P<o2_lower>[\d.]+).*?"
    r"COu=(?P<co_upper>\d+)ppm.*?"
    r"CO2u=(?P<co2_upper>\d+)ppm"
)


def run_sim(blend: float) -> bool:
    """Inject blend into JSON, run simulation, return success."""
    with open(CASE_JSON, encoding="utf-8") as f:
        data = json.load(f)

    overrides = data.setdefault("engine_overrides", {})
    if blend == 0.0:
        overrides.pop("fire_o2_upper_hrr_blend", None)
    else:
        overrides["fire_o2_upper_hrr_blend"] = blend

    with open(CASE_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    cmd = [
        GODOT_EXE,
        "--headless",
        f"--path={WORKSPACE}",
        "--",
        "--validation-case=cfast_hvac_residential",
    ]
    result = subprocess.run(cmd, capture_output=True, timeout=300)
    return result.returncode == 0


def parse_log(target_s: int) -> dict:
    """Return ROOM 0 fields at nearest logged timestamp to target_s."""
    if not LOG_FILE.exists():
        return {}
    lines = LOG_FILE.read_text(encoding="utf-8", errors="replace").splitlines()
    best_t = None
    best_row = None
    i = 0
    while i < len(lines):
        m = re.match(r"^TIME=([\d.]+)\s*s", lines[i])
        if m:
            t = float(m.group(1))
            if best_t is None or abs(t - target_s) < abs(best_t - target_s):
                for j in range(i + 1, min(i + 5, len(lines))):
                    rm = LOG_PATTERN.match(lines[j])
                    if rm:
                        best_t = t
                        best_row = rm.groupdict()
                        break
        i += 1
    return best_row or {}


def check_required(tag: str, sf: float, cfast: float, tol: float) -> str:
    diff = abs(sf - cfast)
    margin = tol - diff
    ok = diff <= tol
    return f"{'OK' if ok else 'FAIL'} (diff={diff:.4f}, margin={margin:+.4f})"


def main():
    original = CASE_JSON.read_text(encoding="utf-8")

    header = (
        f"\n{'='*100}\n"
        f"Phase 4A Blend Sweep — fire_o2_upper_hrr_blend in use_o2_lower path\n"
        f"{'='*100}\n"
        f"  Blend  | t(s) |  HRR (kW) | O2_upper |  O2_lower | CO_upper (ppm) | CO2_upper (%) | Temp_upper (°C)\n"
        f"  -------|------|-----------|----------|-----------|----------------|---------------|----------------"
    )
    print(header)

    results = {}
    try:
        for blend in BLEND_VALUES:
            print(f"\n>>> Running blend={blend:.2f} ...", flush=True)
            ok = run_sim(blend)
            if not ok:
                print(f"    [WARN] sim returned non-zero exit code for blend={blend}")
            rows = {}
            for t in TARGETS:
                row = parse_log(t)
                rows[t] = row
                hrr       = float(row.get("hrr", 0))
                o2u       = float(row.get("o2_upper", 0))
                o2l       = float(row.get("o2_lower", 0))
                co_u      = float(row.get("co_upper", 0))
                co2_u_pct = float(row.get("co2_upper", 0)) / 10000.0
                temp_u    = float(row.get("temp_upper", 0))
                print(
                    f"  {blend:.2f}    | {t:4d} | {hrr:9.1f} | {o2u:.4f}   | {o2l:.4f}    | "
                    f"{co_u:14.0f} | {co2_u_pct:13.4f} | {temp_u:.1f}"
                )
            results[blend] = rows
    finally:
        # Always restore original JSON
        CASE_JSON.write_text(original, encoding="utf-8")
        print("\n>>> JSON restored to original (no blend override).")

    # Invariant impact analysis
    print(f"\n{'='*100}")
    print("INVARIANT IMPACT ANALYSIS — Required checks")
    print(f"{'='*100}")
    ref = CFAST_REF

    for blend in BLEND_VALUES:
        rows = results.get(blend, {})
        print(f"\n  blend={blend:.2f}:")
        for t, tag in [(180, "t180"), (300, "t300"), (450, "t450")]:
            row = rows.get(t, {})
            o2u  = float(row.get("o2_upper", 0))
            o2l  = float(row.get("o2_lower", 0))
            co_u = float(row.get("co_upper", 0))
            temp = float(row.get("temp_upper", 0))
            cfast_o2u  = ref[tag]["o2_upper"]
            cfast_o2l  = ref[tag]["o2_lower"]
            cfast_co_u = ref[tag]["co_upper"]
            cfast_temp = ref[tag]["temp_upper"]

            o2u_tol  = REQUIRED_TOLS[f"o2_upper_{tag}"]
            o2l_tol  = REQUIRED_TOLS[f"o2_lower_{tag}"]
            print(f"    t={t:3d}: o2_upper {check_required('o2u', o2u, cfast_o2u, o2u_tol):<35s}"
                  f"  o2_lower {check_required('o2l', o2l, cfast_o2l, o2l_tol):<35s}"
                  f"  CO_upper(SF={co_u:.0f} CFAST={cfast_co_u:.0f})")
            if t == 180:
                co_u_tol  = REQUIRED_TOLS["co_upper_t180"]
                temp_tol  = REQUIRED_TOLS["temp_upper_t180"]
                print(f"         co_upper {check_required('co_u', co_u, cfast_co_u, co_u_tol):<35s}"
                      f"  temp_upper {check_required('temp', temp, cfast_temp, temp_tol)}")

    # Non-gating gap summary
    print(f"\n{'='*100}")
    print("NON-GATING GAP SUMMARY — CO_upper and CO2_upper vs tol=500/3.0%")
    print(f"{'='*100}")
    print(f"  {'Blend':^6} | {'CO t300':^16} | {'CO t450':^16} | {'CO2% t300':^16} | {'CO2% t450':^16} | score")
    print(f"  {'------':^6}+{'----------------':^18}+{'----------------':^18}+{'----------------':^18}+{'----------------':^18}+------")
    for blend in BLEND_VALUES:
        rows = results.get(blend, {})
        r300 = rows.get(300, {}); r450 = rows.get(450, {})
        co300   = float(r300.get("co_upper", 0))
        co450   = float(r450.get("co_upper", 0))
        co2_300 = float(r300.get("co2_upper", 0)) / 10000.0
        co2_450 = float(r450.get("co2_upper", 0)) / 10000.0
        cfast_co300 = CFAST_REF["t300"]["co_upper"]; cfast_co450 = CFAST_REF["t450"]["co_upper"]
        cfast_co2_300 = CFAST_REF["t300"]["co2_upper_pct"]; cfast_co2_450 = CFAST_REF["t450"]["co2_upper_pct"]
        d_co300  = abs(co300  - cfast_co300)
        d_co450  = abs(co450  - cfast_co450)
        d_co2300 = abs(co2_300 - cfast_co2_300)
        d_co2450 = abs(co2_450 - cfast_co2_450)
        def fmt_gap(d, tol, cfast_v, sf_v):
            over = d - tol
            return f"{sf_v:.0f} (d={d:.0f},{'+' if over>0 else ''}{over:.0f})"
        score = sum(1 for d, tol in [(d_co300,500),(d_co450,500),(d_co2300,3.0),(d_co2450,3.0)] if d <= tol)
        print(f"  {blend:^6.2f} | {fmt_gap(d_co300,500,cfast_co300,co300):^16} | "
              f"{fmt_gap(d_co450,500,cfast_co450,co450):^16} | "
              f"{fmt_gap(d_co2300,3.0,cfast_co2_300,co2_300):^16} | "
              f"{fmt_gap(d_co2450,3.0,cfast_co2_450,co2_450):^16} | "
              f"{score}/4 pass")
    print()


if __name__ == "__main__":
    main()
