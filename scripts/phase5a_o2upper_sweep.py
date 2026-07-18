"""
Phase 5A sweep — cfast_r0_window_360 o2_upper calibration
Barre plume_upper_o2_displacement_frac x o2_upper_plume_entr_rate para cerrar
los 3 FAILs de Grupo A sin tocar sim/core.

Uso:
    python scripts/phase5a_o2upper_sweep.py
    python scripts/phase5a_o2upper_sweep.py --skip-run
    python scripts/phase5a_o2upper_sweep.py --godot PATH
"""
import argparse
import json
import subprocess
import sys
import copy
import os
from pathlib import Path

ROOT = Path(__file__).parent.parent
CASE_PATH = ROOT / "sim/validation/cases/cfast_r0_window_360.json"
REPORT_PATH = ROOT / "sim/validation/reports/reference_checks.json"
OUT_PATH = ROOT / "docs/architecture/PHASE_5A_O2UPPER_SWEEP_RESULTS.md"
CASE_NAME = "cfast_r0_window_360"

# Checks objetivo (deben pasar: REQ FAIL -> TARGET PASS)
TARGET_CHECKS = [
    ("cfast_t240_o2_depleted",  0.085108,   0.031),
    ("cfast_t350_o2",           0.06597990,  0.015),
    ("cfast_t360_o2",           0.0645067,   0.015),
]

# Checks guardados (REQ PASS -> no romper)
GUARD_CHECKS = [
    ("cfast_t350_hrr_kw",       288.362,    90.0),
    ("cfast_t360_hrr_kw",       288.362,    90.0),
    ("cfast_t350_temp_upper_c", 173.024,    80.0),
    ("cfast_t360_temp_upper_c", 173.161,    80.0),
    ("cfast_t350_temp_lower_c", 66.527,     45.0),
    ("cfast_t360_temp_lower_c", 66.8639,    45.0),
    ("cfast_t350_co_upper_ppm", 688.912,   320.0),
    ("cfast_t360_co_upper_ppm", 693.9640,  320.0),
]

_GODOT_CANDIDATES = [
    "C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe",
    "F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe",
]


def find_godot(requested=None):
    if requested and Path(requested).exists():
        return Path(requested).resolve()
    env_path = os.environ.get("GODOT_EXE")
    if env_path and Path(env_path).exists():
        return Path(env_path).resolve()
    for c in _GODOT_CANDIDATES:
        if Path(c).exists():
            return Path(c).resolve()
    return None


def run_godot(godot, case_name, timeout_s=360):
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--",
           f"--validation-case={case_name}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, Exception) as e:
        print(f"    Godot error: {e}")
        return False


with open(CASE_PATH, "r", encoding="utf-8") as f:
    BASE_CASE = json.load(f)


def run_case(godot, overrides_extra: dict, label: str, skip_run: bool) -> dict:
    case = copy.deepcopy(BASE_CASE)
    for k, v in overrides_extra.items():
        case["engine_overrides"][k] = v
    with open(CASE_PATH, "w", encoding="utf-8") as f:
        json.dump(case, f, indent="\t")

    if not skip_run:
        ok = run_godot(godot, CASE_NAME)
        if not ok:
            print(f"    WARNING: Godot returned non-zero for {label}")

    subprocess.run(
        [sys.executable, "scripts/simulation/validate_reference_cases.py"],
        capture_output=True, text=True, cwd=str(ROOT)
    )

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        report = json.load(f)

    checks = {c["name"]: c for c in report.get("checks", [])}

    def actual(key):
        return checks.get(key, {}).get("actual", float("nan"))

    def pf(val, exp, tol):
        if val != val:
            return "N/A"
        return "PASS" if abs(val - exp) <= tol else f"FAIL d={val-exp:+.4f}"

    def is_pass(val, exp, tol):
        return (val == val) and abs(val - exp) <= tol

    # Target checks
    target_results = {}
    target_all_pass = True
    for key, exp, tol in TARGET_CHECKS:
        v = actual(key)
        ok = is_pass(v, exp, tol)
        target_results[key] = (v, ok, pf(v, exp, tol))
        if not ok:
            target_all_pass = False

    # Guard checks
    guard_results = {}
    guard_all_pass = True
    for key, exp, tol in GUARD_CHECKS:
        v = actual(key)
        ok = is_pass(v, exp, tol)
        guard_results[key] = (v, ok, pf(v, exp, tol))
        if not ok:
            guard_all_pass = False

    # Score: sum of normalized distances to center of passing range
    def dist_norm(val, exp, tol):
        if val != val:
            return float("inf")
        return abs(val - exp) / tol

    score = sum(dist_norm(actual(k), e, t) for k, e, t in TARGET_CHECKS)
    if not guard_all_pass:
        score += 1000.0  # penalizar fuertemente romper guards
    if not target_all_pass:
        score += 10.0 * sum(1 for k, e, t in TARGET_CHECKS if not is_pass(actual(k), e, t))

    return {
        "label": label,
        "target_results": target_results,
        "target_all_pass": target_all_pass,
        "guard_results": guard_results,
        "guard_all_pass": guard_all_pass,
        "score": score,
    }


parser = argparse.ArgumentParser()
parser.add_argument("--godot", default=None)
parser.add_argument("--skip-run", action="store_true")
parser.add_argument("--timeout", type=int, default=360)
args = parser.parse_args()

godot = None
if not args.skip_run:
    godot = find_godot(args.godot)
    if godot is None:
        print("ERROR: no se encontro Godot. Define --godot PATH o GODOT_EXE o usa --skip-run.")
        sys.exit(1)
    print(f"Godot: {godot}")

# Sweep grid
FRAC_VALUES = [0.5, 0.75, 1.0]
RATE_VALUES = [0.0005, 0.001, 0.002, 0.003, 0.005]

sweeps = []
for frac in FRAC_VALUES:
    for rate in RATE_VALUES:
        label = f"frac={frac:.4f} rate={rate:.4f}"
        overrides = {
            "plume_upper_o2_displacement_frac": frac,
            "o2_upper_plume_entr_rate": rate,
        }
        sweeps.append((label, overrides))

print(f"Phase 5A sweep — {CASE_NAME} ({len(sweeps)} configs)")
print(f"Target: t240_o2 0.085108+/-0.031  t350_o2 0.06598+/-0.015  t360_o2 0.06451+/-0.015")
print()

rows = []
for label, overrides in sweeps:
    print(f"Running: {label} ...", flush=True)
    r = run_case(godot, overrides, label, args.skip_run)
    rows.append((overrides, r))

    t240 = r["target_results"].get("cfast_t240_o2_depleted", (float("nan"), False, "N/A"))
    t350 = r["target_results"].get("cfast_t350_o2", (float("nan"), False, "N/A"))
    t360 = r["target_results"].get("cfast_t360_o2", (float("nan"), False, "N/A"))
    g_str = "GUARD:OK" if r["guard_all_pass"] else "GUARD:FAIL"
    t_str = "TARGET:OK" if r["target_all_pass"] else "TARGET:FAIL"
    print(f"  t240_o2={t240[0]:.4f}({t240[2]})  t350_o2={t350[0]:.4f}({t350[2]})  t360_o2={t360[0]:.4f}({t360[2]})")
    print(f"  {g_str}  {t_str}  score={r['score']:.3f}")

# Restaurar caso base
with open(CASE_PATH, "w", encoding="utf-8") as f:
    json.dump(BASE_CASE, f, indent="\t")
print("\nCaso base restaurado.")

# Mejor config
valid_rows = [(ov, r) for ov, r in rows if r["target_all_pass"] and r["guard_all_pass"]]
if valid_rows:
    best_ov, best_r = min(valid_rows, key=lambda x: x[1]["score"])
    print(f"\nMejor config viable: {best_r['label']}")
    print(f"  Overrides: frac={best_ov['plume_upper_o2_displacement_frac']}  rate={best_ov['o2_upper_plume_entr_rate']}")
    for key, exp, tol in TARGET_CHECKS:
        v, ok, s = best_r["target_results"][key]
        print(f"  {key}: {v:.4f} ({s})")
else:
    print("\nNinguna config pasa todos los targets sin romper guards.")
    best_ov, best_r = min(rows, key=lambda x: x[1]["score"])
    print(f"Mejor parcial: {best_r['label']}  score={best_r['score']:.3f}")
    for key, exp, tol in TARGET_CHECKS:
        v, ok, s = best_r["target_results"][key]
        print(f"  {key}: {v:.4f} ({s})")

# Escribir resultados MD
lines = [
    "# Phase 5A Sweep Results — cfast_r0_window_360 o2_upper calibration",
    "",
    "Targets: t240_o2=0.085108+/-0.031  t350_o2=0.06598+/-0.015  t360_o2=0.06451+/-0.015",
    "",
    "| Config (frac / rate) | t240_o2 | t240 | t350_o2 | t350 | t360_o2 | t360 | GUARD | TOTAL |",
    "|----------------------|---------|------|---------|------|---------|------|-------|-------|",
]
for ov, r in rows:
    t240 = r["target_results"].get("cfast_t240_o2_depleted", (float("nan"), False, "N/A"))
    t350 = r["target_results"].get("cfast_t350_o2", (float("nan"), False, "N/A"))
    t360 = r["target_results"].get("cfast_t360_o2", (float("nan"), False, "N/A"))
    g = "OK" if r["guard_all_pass"] else "FAIL"
    tot = "PASS" if r["target_all_pass"] and r["guard_all_pass"] else "FAIL"
    lines.append(
        f"| frac={ov['plume_upper_o2_displacement_frac']:.2f} rate={ov['o2_upper_plume_entr_rate']:.4f} "
        f"| {t240[0]:.4f} | {'P' if t240[1] else 'F'} "
        f"| {t350[0]:.4f} | {'P' if t350[1] else 'F'} "
        f"| {t360[0]:.4f} | {'P' if t360[1] else 'F'} "
        f"| {g} | {tot} |"
    )

lines += ["", "## Guard detail (best config)", ""]
best_ov_ref = valid_rows[0][0] if valid_rows else best_ov
best_r_ref = valid_rows[0][1] if valid_rows else best_r
if valid_rows:
    best_ov_ref, best_r_ref = min(valid_rows, key=lambda x: x[1]["score"])
for key, exp, tol in GUARD_CHECKS:
    v, ok, s = best_r_ref["guard_results"].get(key, (float("nan"), False, "N/A"))
    lines.append(f"  - {key}: actual={v:.2f} exp={exp}+/-{tol} {s}")

if valid_rows:
    lines += [
        "",
        f"## ELEGIDA: frac={best_ov_ref['plume_upper_o2_displacement_frac']}  rate={best_ov_ref['o2_upper_plume_entr_rate']}",
        "",
    ]

OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"\nResultados: {OUT_PATH}")
