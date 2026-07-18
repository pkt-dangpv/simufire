"""
Phase 4A sweep — slow_growth_sealed chi_rad fix
Barre hrr_chi_rad_normal/low_o2 x upper_to_ambient_loss_rate para cerrar
el gap de temp_upper t480/t600 en sala sellada sin tocar sim/core.

Uso:
    python scripts/phase4a_chirad_sweep.py
    python scripts/phase4a_chirad_sweep.py --skip-run
    python scripts/phase4a_chirad_sweep.py --godot PATH
"""
import argparse
import json
import subprocess
import sys
import copy
import os
from pathlib import Path

ROOT = Path(__file__).parent.parent
CASE_PATH = ROOT / "sim/validation/cases/cfast_slow_growth_sealed.json"
REPORT_PATH = ROOT / "sim/validation/reports/reference_checks.json"
OUT_PATH = ROOT / "docs/architecture/PHASE_4A_CHIRAD_SWEEP_RESULTS.md"
CASE_NAME = "cfast_slow_growth_sealed"

# Checks de temperatura (gating)
T480_KEY = "cfast_slow_t480_temp_upper_c"
T600_KEY = "cfast_slow_t600_temp_upper_c"
T480_EXP, T480_TOL = 151.003, 10.0
T600_EXP, T600_TOL = 152.025, 15.0

# Checks de O2 (deben seguir PASS)
O2_CHECKS = [
    ("cfast_slow_t300_o2",   0.1646,    0.01),
    ("cfast_slow_t480_o2",   0.084,     0.012),
    ("cfast_slow_t600_o2",   0.069659,  0.02),
    ("cfast_slow_t900_o2",   0.045971,  0.015),
    ("cfast_slow_t1200_o2",  0.035066,  0.025),
]

# Checks de temp no-gating (informativo)
TEMP_INFO = [
    ("cfast_slow_t120_temp_upper_c",  39.69,  15.0),
    ("cfast_slow_t240_temp_upper_c",  104.93, 50.0),
    ("cfast_slow_t300_temp_upper_c",  154.20, 60.0),
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
        return "PASS" if abs(val - exp) <= tol else f"FAIL d={val-exp:+.1f}"

    t480 = actual(T480_KEY)
    t600 = actual(T600_KEY)

    o2_all_pass = True
    o2_results = {}
    for key, exp, tol in O2_CHECKS:
        v = actual(key)
        ok = (v == v) and abs(v - exp) <= tol
        o2_results[key] = (v, ok)
        if not ok:
            o2_all_pass = False

    info_temps = {key: actual(key) for key, _, _ in TEMP_INFO}

    # Distancia al centro del rango de PASSing como metrica de calidad
    def dist_to_center(val, exp, tol):
        if val != val:
            return float("inf")
        d = abs(val - exp)
        return d / tol  # normalizado: <1 = PASS, centro = 0

    score = dist_to_center(t480, T480_EXP, T480_TOL) + dist_to_center(t600, T600_EXP, T600_TOL)
    if not o2_all_pass:
        score += 100.0  # penalizar fuertemente si rompe O2

    return {
        "label": label,
        "t480": t480,
        "t480_pf": pf(t480, T480_EXP, T480_TOL),
        "t600": t600,
        "t600_pf": pf(t600, T600_EXP, T600_TOL),
        "o2_all_pass": o2_all_pass,
        "o2_results": o2_results,
        "info_temps": info_temps,
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
CHI_RAD_VALUES = [0.30, 0.35, 0.40, 0.45, 0.50]
AMBIENT_LOSS_VALUES = [0.002, 0.005, 0.008, 0.010]

sweeps = []
for chi in CHI_RAD_VALUES:
    for amb in AMBIENT_LOSS_VALUES:
        label = f"chi={chi:.2f} amb={amb:.3f}"
        overrides = {
            "hrr_chi_rad_normal": chi,
            "hrr_chi_rad_low_o2": chi,
            "upper_to_ambient_loss_rate": amb,
        }
        sweeps.append((label, overrides))

print(f"Phase 4A sweep — slow_growth_sealed ({len(sweeps)} configs)")
print(f"T480 target: {T480_EXP}+/-{T480_TOL}  T600 target: {T600_EXP}+/-{T600_TOL}")
print()

rows = []
for label, overrides in sweeps:
    print(f"Running: {label} ...", flush=True)
    r = run_case(godot, overrides, label, args.skip_run)
    rows.append((overrides, r))
    o2_str = "O2:OK" if r["o2_all_pass"] else "O2:FAIL"
    print(f"  t480={r['t480']:.1f}({r['t480_pf']})  t600={r['t600']:.1f}({r['t600_pf']})  {o2_str}")

# Restaurar caso base
with open(CASE_PATH, "w", encoding="utf-8") as f:
    json.dump(BASE_CASE, f, indent="\t")
print("\nCaso base restaurado.")

# Mejor config
valid_rows = [(ov, r) for ov, r in rows if r["o2_all_pass"]
              and r["t480_pf"] == "PASS" and r["t600_pf"] == "PASS"]
if valid_rows:
    best_ov, best_r = min(valid_rows, key=lambda x: x[1]["score"])
    print(f"\nMejor config: {best_r['label']}")
    print(f"  t480={best_r['t480']:.2f} {best_r['t480_pf']}")
    print(f"  t600={best_r['t600']:.2f} {best_r['t600_pf']}")
    print(f"  O2: all PASS")
    print(f"  Overrides: {best_ov}")
else:
    print("\nNinguna config alcanza PASS en t480+t600 con O2 OK.")
    # Mostrar mejor parcial
    best_ov, best_r = min(rows, key=lambda x: x[1]["score"])
    print(f"Mejor parcial: {best_r['label']}  score={best_r['score']:.3f}")

# Escribir resultados MD
lines = [
    "# Phase 4A Sweep Results — slow_growth_sealed chi_rad fix",
    "",
    f"CFAST targets: t480={T480_EXP}+/-{T480_TOL}C   t600={T600_EXP}+/-{T600_TOL}C",
    "",
    "| Config (chi_rad / amb_rate) | t480(C) | t480 result | t600(C) | t600 result | O2 |",
    "|------------------------------|---------|-------------|---------|-------------|----|",
]
for ov, r in rows:
    o2_col = "OK" if r["o2_all_pass"] else "FAIL"
    lines.append(
        f"| {r['label']:28s} | {r['t480']:7.1f} | {r['t480_pf']:11s} | "
        f"{r['t600']:7.1f} | {r['t600_pf']:11s} | {o2_col} |"
    )

lines += ["", "## O2 detail (best PASS configs)", ""]
for ov, r in rows:
    if r["o2_all_pass"] and r["t480_pf"] == "PASS" and r["t600_pf"] == "PASS":
        lines.append(f"### {r['label']}")
        for key, exp, tol in O2_CHECKS:
            v, ok = r["o2_results"][key]
            pf_str = "PASS" if ok else f"FAIL d={v-exp:+.4f}"
            lines.append(f"  - {key}: actual={v:.4f} exp={exp}+/-{tol} {pf_str}")
        for key, exp, tol in TEMP_INFO:
            v = r["info_temps"].get(key, float("nan"))
            lines.append(f"  - {key}: actual={v:.1f} exp={exp}+/-{tol}")
        lines.append("")

if valid_rows:
    lines += ["", f"## ELEGIDA: {best_r['label']}",
              f"hrr_chi_rad_normal={best_ov['hrr_chi_rad_normal']}",
              f"hrr_chi_rad_low_o2={best_ov['hrr_chi_rad_low_o2']}",
              f"upper_to_ambient_loss_rate={best_ov['upper_to_ambient_loss_rate']}",
              ""]

OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"\nResultados: {OUT_PATH}")
