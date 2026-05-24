#!/usr/bin/env python3
"""
SF-AUD-040: Monte Carlo runner para análisis de incertidumbre en SimuFire.

Perturba ±1σ los 20 parámetros más sensibles del modelo (fire growth, peak HRR,
O2 thresholds, radiative loss, heat exchange, smoke transport, etc.) y agrega
los percentiles 5/50/95 de métricas de supervivencia (FED, visibilidad, layer 150°C).

Referencia: NFPA 921 §4.4 / SFPE PRA — se recomiendan ≥100 runs.

Uso:
    python monte_carlo_runner.py [--case <nombre>] [--n <N>] [--godot <exe>]

Ejemplo:
    python monte_carlo_runner.py --case layer150_tenability --n 100 ^
        --godot "F:/OneDrive/Escritorio/Godot_v4.6.3-stable_win64_console.exe"

Salida: sim/validation/mc_results_<case>.json con sección "percentiles" {P05, P50, P95}.
"""

import argparse
import json
import os
import random
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Paths (resueltos relativos a este script)
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent.parent
CASES_DIR = SCRIPT_DIR / "cases"
BASELINES_DIR = SCRIPT_DIR / "baselines"
REPORTS_DIR = SCRIPT_DIR / "reports"
RUN_CASE_PS1 = SCRIPT_DIR / "run_case.ps1"

DEFAULT_GODOT_EXE = r"F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe"

# ---------------------------------------------------------------------------
# Parámetros a perturbar: {nombre: (valor_nominal, coeficiente_de_variación)}
# CV = σ/μ — e.g. 0.20 → ±20% en un sigma
# Todos son @export vars de SimulationEngine.gd
# ---------------------------------------------------------------------------
PERTURBATION_CONFIG: Dict[str, Tuple[float, float]] = {
    # --- Crecimiento y extinción del fuego ---
    "fire_alpha_kw_s2":                          (0.047,  0.30),
    "fire_secondary_hrr_gain_kw":                (800.0,  0.20),
    "fire_o2_min_for_flame":                     (0.122,  0.08),
    "fire_o2_consumption_kg_per_MJ":             (0.076,  0.05),
    "fire_o2_hrr_rise_tau_s":                    (14.0,   0.20),
    "fire_o2_hrr_fall_tau_s":                    (32.0,   0.20),
    "fire_latent_o2_viable_margin":              (0.015,  0.15),
    "fire_extinction_delay_s":                   (240.0,  0.15),
    "fire_latent_extinction_delay_s":            (300.0,  0.15),
    # --- Pérdidas radiativas ---
    "upper_radiative_loss_emissivity":           (0.90,   0.05),
    "upper_radiative_loss_area_factor":          (1.10,   0.10),
    "upper_radiative_loss_start_c":              (80.0,   0.10),
    # --- Intercambio de calor y transporte ---
    "doorway_heat_exchange_coeff":               (1.0,    0.15),
    "smoke_heat_mix_coeff":                      (0.025,  0.20),
    "hot_gas_smoke_carry_fraction":              (0.30,   0.20),
    "hot_gas_species_carry_fraction":            (0.72,   0.05),
    "interior_background_heat_exchange_kg_s_m2": (0.015,  0.15),
    # --- Captura de calor y pluma ---
    "upper_heat_capture_min":                    (0.10,   0.20),
    "upper_heat_capture_max":                    (0.25,   0.15),
    "plume_fire_diameter_m":                     (1.0,    0.20),
}

# ---------------------------------------------------------------------------
# Métricas de salida SVV (Supervivencia / Viabilidad / Vulnerabilidad)
# ---------------------------------------------------------------------------
SVV_METRICS: List[str] = [
    "room_0_max_fed",
    "room_0_final_fed",
    "room_0_min_visibility_m",
    "room_0_final_visibility_m",
    "room_0_min_l150_m",
    "room_0_final_layer_150c_m",
    "room_0_peak_hrr_kw",
    "room_0_final_hrr_kw",
    "room_0_peak_temp_upper_c",
    "room_0_final_temp_upper_raw_c",
    "room_0_final_smoke_layer_m",
    "room_0_final_co_ppm",
    "room_0_peak_co_ppm",
    "room_0_final_temp_at_2_2m_c",
    "room_0_final_temp_at_1_8m_c",
    "room_0_final_temp_at_0_1m_c",
]


# ---------------------------------------------------------------------------
# Funciones auxiliares
# ---------------------------------------------------------------------------

def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def sample_perturbed(rng: random.Random) -> Dict[str, float]:
    """Muestrea un conjunto de parámetros perturbados ±2σ (truncated Normal)."""
    params: Dict[str, float] = {}
    for name, (nominal, cv) in PERTURBATION_CONFIG.items():
        sigma = nominal * cv
        z = clamp(rng.gauss(0.0, 1.0), -2.0, 2.0)
        perturbed = nominal + z * sigma
        # Todos los parámetros deben ser positivos
        perturbed = max(perturbed, nominal * 0.05)
        params[name] = round(perturbed, 8)
    return params


def write_temp_case(base_case: dict, perturbed: Dict[str, float], run_id: int) -> str:
    """Escribe el JSON de caso temporal. Devuelve el nombre del caso."""
    case_name = f"_mc_{run_id:05d}"
    case_data = json.loads(json.dumps(base_case))  # deep copy

    overrides: dict = case_data.setdefault("engine_overrides", {})
    overrides.update(perturbed)
    case_data["enable_logging"] = False  # sin logging para mayor velocidad

    (CASES_DIR / f"{case_name}.json").write_text(
        json.dumps(case_data, indent="\t"), encoding="utf-8"
    )
    # Baseline vacío: solo necesitamos que el runner guarde el reporte
    (BASELINES_DIR / f"{case_name}.json").write_text(
        json.dumps({"metrics": {}}, indent="\t"), encoding="utf-8"
    )
    return case_name


def run_case(case_name: str, godot_exe: str, timeout_s: int = 180) -> dict:
    """Ejecuta un caso via run_case.ps1. Devuelve el dict del reporte o {}."""
    cmd = [
        "powershell.exe",
        "-NonInteractive", "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", str(RUN_CASE_PS1),
        case_name,
        "-GodotExe", godot_exe,
    ]
    try:
        subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_s,
            cwd=str(REPO_ROOT),
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {}
    except OSError:
        return {}

    report_path = REPORTS_DIR / f"{case_name}.json"
    if not report_path.exists():
        return {}
    try:
        return json.loads(report_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def cleanup_temp(case_name: str) -> None:
    for d in (CASES_DIR, BASELINES_DIR, REPORTS_DIR):
        p = d / f"{case_name}.json"
        try:
            p.unlink(missing_ok=True)
        except OSError:
            pass


def percentile(sorted_vals: List[float], p: float) -> float:
    if not sorted_vals:
        return float("nan")
    n = len(sorted_vals)
    idx = (n - 1) * p / 100.0
    lo = int(idx)
    hi = min(lo + 1, n - 1)
    return sorted_vals[lo] + (idx - lo) * (sorted_vals[hi] - sorted_vals[lo])


def aggregate(all_metrics: List[dict]) -> dict:
    """Calcula P5/P50/P95 para cada métrica SVV."""
    data: Dict[str, List[float]] = defaultdict(list)
    for m in all_metrics:
        for key in SVV_METRICS:
            val = m.get(key)
            if val is not None:
                try:
                    data[key].append(float(val))
                except (ValueError, TypeError):
                    pass

    result = {}
    for key, vals in data.items():
        if not vals:
            continue
        s = sorted(vals)
        mean = sum(s) / len(s)
        variance = sum((x - mean) ** 2 for x in s) / len(s)
        result[key] = {
            "n":    len(s),
            "mean": round(mean, 4),
            "std":  round(variance ** 0.5, 4),
            "p05":  round(percentile(s, 5),  4),
            "p50":  round(percentile(s, 50), 4),
            "p95":  round(percentile(s, 95), 4),
            "min":  round(s[0],  4),
            "max":  round(s[-1], 4),
        }
    return result


# ---------------------------------------------------------------------------
# CLI principal
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="SF-AUD-040: Monte Carlo runner para SimuFire"
    )
    parser.add_argument(
        "--case", default="layer150_tenability",
        help="Nombre del caso base (sin .json). Default: layer150_tenability"
    )
    parser.add_argument(
        "--n", type=int, default=50,
        help="Número de runs Monte Carlo. NFPA 921 recomienda ≥100. Default: 50"
    )
    parser.add_argument(
        "--seed", type=int, default=42,
        help="Semilla RNG para reproducibilidad. Default: 42"
    )
    parser.add_argument(
        "--godot", default=DEFAULT_GODOT_EXE,
        help="Ruta al ejecutable Godot headless"
    )
    parser.add_argument(
        "--out", default=None,
        help="Ruta de salida JSON. Default: sim/validation/mc_results_<case>.json"
    )
    parser.add_argument(
        "--timeout", type=int, default=180,
        help="Timeout por run en segundos. Default: 180"
    )
    args = parser.parse_args()

    base_path = CASES_DIR / f"{args.case}.json"
    if not base_path.exists():
        print(f"[ERROR] Caso no encontrado: {base_path}", file=sys.stderr)
        sys.exit(1)

    out_path = Path(args.out) if args.out else SCRIPT_DIR / f"mc_results_{args.case}.json"

    base_case = json.loads(base_path.read_text(encoding="utf-8"))
    rng = random.Random(args.seed)

    all_metrics: List[dict] = []
    run_log: List[dict] = []
    failed = 0

    print(f"[MC] Caso base:   {args.case}")
    print(f"[MC] N runs:      {args.n}")
    print(f"[MC] Semilla RNG: {args.seed}")
    print(f"[MC] Godot exe:   {args.godot}")
    print(f"[MC] Salida:      {out_path}")
    print(f"[MC] Parámetros perturbados: {len(PERTURBATION_CONFIG)}")
    print()

    t0 = time.time()

    for i in range(args.n):
        perturbed = sample_perturbed(rng)
        case_name = write_temp_case(base_case, perturbed, i)

        fed_str = ""
        try:
            report = run_case(case_name, args.godot, timeout_s=args.timeout)
            metrics = report.get("metrics", {}) if report else {}
            if metrics:
                all_metrics.append(metrics)
                fed_val = metrics.get("room_0_max_fed") or metrics.get("room_0_final_fed", "?")
                vis_val = metrics.get("room_0_min_visibility_m", "?")
                fed_str = f"  FED={fed_val:.3f}  vis={vis_val:.2f}" if isinstance(fed_val, (int, float)) else "  OK"
            else:
                failed += 1
                fed_str = "  FAIL/EMPTY"
        except Exception as exc:
            failed += 1
            fed_str = f"  ERROR: {exc}"
        finally:
            cleanup_temp(case_name)

        run_log.append({"run": i, "params": perturbed})
        elapsed_run = time.time() - t0
        eta = (elapsed_run / (i + 1)) * (args.n - i - 1)
        print(f"  [{i+1:3d}/{args.n}]{fed_str}  ETA {eta:.0f}s")

    elapsed = time.time() - t0
    n_valid = len(all_metrics)

    print(f"\n[MC] Completo: {n_valid}/{args.n} válidos en {elapsed:.1f}s "
          f"({elapsed/max(n_valid,1):.1f}s/run avg)")
    if failed:
        print(f"[MC] Fallidos: {failed}")

    percentiles = aggregate(all_metrics)

    output = {
        "case":           args.case,
        "n_requested":    args.n,
        "n_valid":        n_valid,
        "n_failed":       failed,
        "seed":           args.seed,
        "elapsed_s":      round(elapsed, 1),
        "perturbation": {
            k: {"nominal": v[0], "cv": v[1], "sigma": round(v[0] * v[1], 6)}
            for k, v in PERTURBATION_CONFIG.items()
        },
        "percentiles": percentiles,
        "run_params": run_log,
    }

    out_path.write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(f"\n[MC] Resultados guardados en: {out_path}")

    # --- Resumen de percentiles ---
    print("\n" + "=" * 72)
    print(f"{'Métrica':<42}  {'P05':>8}  {'P50':>8}  {'P95':>8}  {'N':>5}")
    print("=" * 72)
    for metric, stats in sorted(percentiles.items()):
        print(
            f"  {metric:<40}  {stats['p05']:8.3f}  {stats['p50']:8.3f}"
            f"  {stats['p95']:8.3f}  {stats['n']:5d}"
        )
    print("=" * 72)


if __name__ == "__main__":
    main()
