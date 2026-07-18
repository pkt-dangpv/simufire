"""
Phase 3 sweep — corridor_chain
Prueba combinaciones de Phase 3A, 3B, 3D y registra t180/t600 temp_upper R0.
Guarda resultados en docs/architecture/PHASE_3_SWEEP_RESULTS.md.

Uso:
    python scripts/phase3_sweep.py
    python scripts/phase3_sweep.py --skip-run
    python scripts/phase3_sweep.py --godot PATH
"""
import argparse
import json
import subprocess
import sys
import copy
import os
from pathlib import Path

ROOT = Path(__file__).parent.parent
CASE_PATH = ROOT / "sim/validation/cases/cfast_corridor_chain.json"
REPORT_PATH = ROOT / "sim/validation/reports/reference_checks.json"
OUT_PATH = ROOT / "docs/architecture/PHASE_3_SWEEP_RESULTS.md"
CASE_NAME = "cfast_corridor_chain"

# Checks de interés en reference_checks.json
T180_KEY = "cfast_chain_r0_t180_temp_upper_c"
T600_KEY = "cfast_chain_r0_t600_temp_upper_c"

# Baseline esperado (de CFAST)
T180_EXP = 159.816
T600_EXP = 168.796
T180_TOL = 15.0
T600_TOL = 30.0

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


def run_godot(godot, case_name, timeout_s=300):
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--",
           f"--validation-case={case_name}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, Exception) as e:
        print(f"    Godot error: {e}")
        return False


# Caso base sin Phase 3 (se restaura entre sweeps)
with open(CASE_PATH, "r", encoding="utf-8") as f:
    BASE_CASE = json.load(f)


def run_case(godot, engine_overrides_extra: dict, label: str, skip_run: bool) -> dict:
    """Aplica overrides, ejecuta Godot, valida y retorna {t180, t600, ...}."""
    case = copy.deepcopy(BASE_CASE)
    for k, v in engine_overrides_extra.items():
        case["engine_overrides"][k] = v
    with open(CASE_PATH, "w", encoding="utf-8") as f:
        json.dump(case, f, indent="\t")

    if not skip_run:
        ok = run_godot(godot, CASE_NAME)
        if not ok:
            print(f"    WARNING: Godot returned non-zero for {label}")

    # Regenerate reference_checks.json
    subprocess.run(
        [sys.executable, "scripts/simulation/validate_reference_cases.py"],
        capture_output=True, text=True, cwd=str(ROOT)
    )

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        report = json.load(f)

    checks = {c["name"]: c for c in report.get("checks", [])}
    t180 = checks.get(T180_KEY, {}).get("actual", float("nan"))
    t600 = checks.get(T600_KEY, {}).get("actual", float("nan"))

    def passfail(actual, expected, tol):
        if actual != actual:  # nan
            return "N/A"
        return "PASS" if abs(actual - expected) <= tol else f"FAIL d={actual-expected:+.1f}C"

    return {
        "label": label,
        "t180": t180,
        "t180_pf": passfail(t180, T180_EXP, T180_TOL),
        "t600": t600,
        "t600_pf": passfail(t600, T600_EXP, T600_TOL),
    }


def fmt_row(r):
    return (f"| {r['label']:52s} | {r['t180']:6.1f} | {r['t180_pf']:25s} | "
            f"{r['t600']:6.1f} | {r['t600_pf']:25s} |")


parser = argparse.ArgumentParser()
parser.add_argument("--godot", default=None)
parser.add_argument("--skip-run", action="store_true",
                    help="No ejecutar Godot; usar logs ya existentes")
parser.add_argument("--timeout", type=int, default=300)
args = parser.parse_args()

godot = None
if not args.skip_run:
    godot = find_godot(args.godot)
    if godot is None:
        print("ERROR: no se encontro Godot. Define --godot PATH o GODOT_EXE o usa --skip-run.")
        sys.exit(1)
    print(f"Godot: {godot}")

print("Phase 3 sweep — corridor_chain")
print(f"Baseline CFAST: t180={T180_EXP}+/-{T180_TOL}  t600={T600_EXP}+/-{T600_TOL}")
print()

rows = []

sweeps = [
    # (label, overrides)
    ("baseline (no Phase 3)", {}),
    ("3A only (dp ODE)",
        {"phase3a_pressure_ode_enabled": True}),
    ("3A+3B (dp + neutral plane)",
        {"phase3a_pressure_ode_enabled": True, "phase3b_neutral_plane_dp_correction": True}),
    ("3D=0.1 (direct upper frac)",
        {"canonical_doorway_plume_direct_upper_frac": 0.1}),
    ("3D=0.2",
        {"canonical_doorway_plume_direct_upper_frac": 0.2}),
    ("3D=0.3",
        {"canonical_doorway_plume_direct_upper_frac": 0.3}),
    ("3D=0.4",
        {"canonical_doorway_plume_direct_upper_frac": 0.4}),
    ("3D=0.5",
        {"canonical_doorway_plume_direct_upper_frac": 0.5}),
    ("3D=0.7",
        {"canonical_doorway_plume_direct_upper_frac": 0.7}),
    ("3D=1.0",
        {"canonical_doorway_plume_direct_upper_frac": 1.0}),
    ("3A+3B+3D=0.3",
        {"phase3a_pressure_ode_enabled": True,
         "phase3b_neutral_plane_dp_correction": True,
         "canonical_doorway_plume_direct_upper_frac": 0.3}),
    ("3A+3B+3D=0.5",
        {"phase3a_pressure_ode_enabled": True,
         "phase3b_neutral_plane_dp_correction": True,
         "canonical_doorway_plume_direct_upper_frac": 0.5}),
]

for label, overrides in sweeps:
    print(f"Running: {label} ...", flush=True)
    r = run_case(godot, overrides, label, args.skip_run)
    rows.append(r)
    print(f"  t180={r['t180']:.1f} ({r['t180_pf']})  t600={r['t600']:.1f} ({r['t600_pf']})")

# Restaurar caso base (sin Phase 3)
with open(CASE_PATH, "w", encoding="utf-8") as f:
    json.dump(BASE_CASE, f, indent="\t")
print("\nCaso base restaurado.")

# Escribir resultados
header = (
    "# Phase 3 Sweep Results — corridor_chain\n\n"
    f"CFAST targets: t180={T180_EXP}+/-{T180_TOL}C,  t600={T600_EXP}+/-{T600_TOL}C\n\n"
    "| Config                                                 |  t180 | t180 result              |  t600 | t600 result              |\n"
    "|--------------------------------------------------------|-------|--------------------------|-------|--------------------------|"
)
lines = [header] + [fmt_row(r) for r in rows]
OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"\nResultados: {OUT_PATH}")
