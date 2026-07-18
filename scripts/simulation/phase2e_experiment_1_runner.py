"""
phase2e_experiment_1_runner.py — Runner experimental Phase 2E, experimento 1.

Crea variantes de 4 casos de validacion con phase2e_two_zone_transport_enabled=true
en engine_overrides, ejecuta Godot headless, y compara metricas CO-upper contra baseline.

Casos evaluados:
  g4_gie_delayed_entry_hazard   (sentinel FED timing, CO>1200 timing, peak CO upper)
  v3_hallway_fed_exposure       (sentinel FED timing, max FED, peak CO upper)
  victim_fed_incapacitation     (sentinel final FED, peak CO global)
  cfast_two_room_door_open      (CO upper room 1 final + peak)

Uso:
    python scripts/simulation/phase2e_experiment_1_runner.py
    python scripts/simulation/phase2e_experiment_1_runner.py --godot PATH_TO_EXE
    python scripts/simulation/phase2e_experiment_1_runner.py --skip-run  # solo compara reports existentes

Codigo de salida:
    0 — experimento completado (deltas impresos; no se exige PASS)
    1 — error critico (Godot no encontrado, reporte no generado, etc.)
"""

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

ROOT       = Path(__file__).resolve().parents[2]
CASES_DIR  = ROOT / "sim" / "validation" / "cases"
REPORTS_DIR = ROOT / "sim" / "validation" / "reports"

# ---------------------------------------------------------------------------
# Godot resolution
# ---------------------------------------------------------------------------

_GODOT_CANDIDATES = [
    "C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe",
    "F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe",
]


def find_godot(requested: str | None = None) -> Path | None:
    import os
    if requested and Path(requested).exists():
        return Path(requested).resolve()
    env_path = os.environ.get("GODOT_EXE")
    if env_path and Path(env_path).exists():
        return Path(env_path).resolve()
    for c in _GODOT_CANDIDATES:
        if Path(c).exists():
            return Path(c).resolve()
    return None


# ---------------------------------------------------------------------------
# Metricas de interes por caso
# ---------------------------------------------------------------------------

# (metric_key_in_report, label_corto, es_sentinel)
METRICS_PER_CASE: dict[str, list[tuple[str, str, bool]]] = {
    "g4_gie_delayed_entry_hazard": [
        ("time_room_1_fed_above_0_1_s",       "g4  FED timing [s]       ", True),
        ("time_room_1_co_upper_above_1200_s",  "g4  CO>1200 timing [s]   ", True),
        ("room_1_peak_co_upper_ppm",           "g4  peak CO upper [ppm]  ", True),
        ("room_1_final_co_upper_ppm",          "g4  final CO upper [ppm] ", False),
        ("room_1_peak_co_ppm",                 "g4  peak CO (mixed) [ppm]", False),
    ],
    "v3_hallway_fed_exposure": [
        ("time_room_1_fed_above_0_1_s",       "v3  FED timing [s]       ", True),
        ("room_1_max_fed",                     "v3  max FED              ", True),
        ("room_1_peak_co_upper_ppm",           "v3  peak CO upper [ppm]  ", False),
        ("room_1_final_co_upper_ppm",          "v3  final CO upper [ppm] ", False),
        ("room_1_peak_co_ppm",                 "v3  peak CO (mixed) [ppm]", False),
    ],
    "victim_fed_incapacitation": [
        ("victim_v0_final_fed",                "vic  final FED           ", True),
        ("peak_co_ppm_global",                 "vic  peak CO global [ppm]", True),
        ("room_0_final_fed",                   "vic  room0 final FED     ", False),
        ("room_0_peak_co_ppm",                 "vic  room0 peak CO [ppm] ", False),
    ],
    "cfast_two_room_door_open": [
        ("room_1_final_co_upper_ppm",          "cfast room1 CO upper fin.", False),
        ("room_1_final_co_ppm",                "cfast room1 CO mixed fin.", False),
        ("peak_co_upper_ppm_global",           "cfast peak CO upper glob.", False),
        ("peak_co_ppm_global",                 "cfast peak CO mixed glob.", False),
    ],
}

CASES = list(METRICS_PER_CASE.keys())
EXP_SUFFIX = "_phase2e_exp1"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_report(path: Path) -> dict | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        # Los reports tienen metrics en top-level dict
        return data
    except Exception as e:
        print(f"  ERROR cargando {path}: {e}")
        return None


def _get_metric(report: dict, key: str) -> float | None:
    """Extrae metrica del report (puede estar en metrics{} o directamente)."""
    if report is None:
        return None
    # Primer nivel directo
    if key in report:
        val = report[key]
        if isinstance(val, (int, float)):
            return float(val)
    # Bajo "metrics"
    metrics = report.get("metrics", {})
    if isinstance(metrics, dict) and key in metrics:
        val = metrics[key]
        if isinstance(val, (int, float)):
            return float(val)
        if isinstance(val, dict):
            # threshold_metrics format: {"value": ..., "time_s": ...}
            if "value" in val:
                return float(val["value"])
            if "time_s" in val:
                return float(val["time_s"])
    # Threshold metrics at top level (como en g4)
    thr = report.get("threshold_metrics", {})
    if isinstance(thr, dict) and key in thr:
        v = thr[key]
        if isinstance(v, (int, float)):
            return float(v)
    return None


def _fmt_delta(base: float | None, exp: float | None) -> str:
    if base is None or exp is None:
        return "n/a"
    delta = exp - base
    pct = (delta / abs(base) * 100.0) if base != 0.0 else 0.0
    sign = "+" if delta >= 0 else ""
    return f"{sign}{delta:+.3f} ({sign}{pct:.1f}%)"


def _run_case(godot: Path, case_name: str, timeout_s: int = 300) -> bool:
    """Ejecuta Godot para el caso dado. Devuelve True si terminó con exit 0."""
    cmd = [
        str(godot),
        "--headless",
        "--path", str(ROOT),
        "--",
        f"--validation-case={case_name}",
    ]
    print(f"  [Godot] {case_name}  ...", end=" ", flush=True)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        if result.returncode == 0:
            print("OK")
            return True
        else:
            print(f"FAIL (exit {result.returncode})")
            if result.stderr:
                print(f"    stderr: {result.stderr[:300]}")
            return False
    except subprocess.TimeoutExpired:
        print(f"TIMEOUT ({timeout_s}s)")
        return False
    except Exception as exc:
        print(f"ERROR: {exc}")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2E experiment 1 — CO two-zone transport split."
    )
    parser.add_argument("--godot", default=None, metavar="PATH",
                        help="Ruta al ejecutable de Godot")
    parser.add_argument("--skip-run", action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--timeout", type=int, default=300,
                        help="Timeout por caso en segundos (default 300)")
    args = parser.parse_args()

    W = 72
    print()
    print("=" * W)
    print("  Phase 2E Experiment 1 — CO Two-Zone Transport Split")
    print("  Flag: phase2e_two_zone_transport_enabled = true")
    print("  Casos: g4 | v3 | victim_fed | cfast_two_room_door_open")
    print("=" * W)

    # -- Resolver Godot -------------------------------------------------------
    godot = None
    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("\n  ERROR: no se encontro el ejecutable de Godot.")
            print("  Define --godot PATH o la variable GODOT_EXE.")
            print("  O usa --skip-run para comparar reports existentes.\n")
            return 1
        print(f"\n  Godot: {godot}")
    else:
        print("\n  [modo --skip-run: usando reports existentes]\n")

    # -- Crear casos experimentales y ejecutar --------------------------------
    created_temp_cases: list[Path] = []
    run_errors: list[str] = []

    if not args.skip_run:
        print()
        print("  Ejecutando casos con flag ON:")
        print()

    for case in CASES:
        base_case_path = CASES_DIR / f"{case}.json"
        exp_case_name  = case + EXP_SUFFIX
        exp_case_path  = CASES_DIR / f"{exp_case_name}.json"
        exp_report_path = REPORTS_DIR / f"{exp_case_name}.json"

        if not args.skip_run:
            # Cargar caso base y añadir flag ON en engine_overrides
            if not base_case_path.exists():
                print(f"  ADVERTENCIA: caso base no encontrado: {base_case_path}")
                run_errors.append(case)
                continue

            case_data = json.loads(base_case_path.read_text(encoding="utf-8-sig"))
            overrides = dict(case_data.get("engine_overrides", {}))
            overrides["phase2e_two_zone_transport_enabled"] = True
            case_data["engine_overrides"] = overrides

            exp_case_path.write_text(
                json.dumps(case_data, indent="\t", ensure_ascii=False),
                encoding="utf-8"
            )
            created_temp_cases.append(exp_case_path)

            # Ejecutar
            ok = _run_case(godot, exp_case_name, timeout_s=args.timeout)
            if not ok:
                run_errors.append(case)

    # -- Comparar resultados --------------------------------------------------
    print()
    print("  Comparacion de metricas  (baseline flag=OFF  vs  experimento flag=ON)")
    print()

    results: list[dict] = []

    for case in CASES:
        base_report_path = REPORTS_DIR / f"{case}.json"
        exp_report_path  = REPORTS_DIR / f"{case}{EXP_SUFFIX}.json"

        base_report = _load_report(base_report_path)
        exp_report  = _load_report(exp_report_path)

        if exp_report is None and not args.skip_run and case not in run_errors:
            print(f"  [!] Report experimental no generado para {case}")
            continue
        if exp_report is None:
            print(f"  [!] Sin report experimental para {case} (omitiendo)")
            continue

        print(f"  --- {case} ---")
        hdr = f"  {'Metrica':<30}  {'Baseline':>14}  {'Exp (ON)':>14}  {'Delta':>22}  Sentinel"
        print(hdr)
        print("  " + "-" * (len(hdr) - 2))

        for metric_key, label, is_sentinel in METRICS_PER_CASE[case]:
            base_val = _get_metric(base_report, metric_key)
            exp_val  = _get_metric(exp_report, metric_key)
            delta_str = _fmt_delta(base_val, exp_val)
            sentinel_mark = "*" if is_sentinel else " "
            base_str = f"{base_val:.3f}" if base_val is not None else "n/a"
            exp_str  = f"{exp_val:.3f}"  if exp_val  is not None else "n/a"
            print(f"  {label:<30}  {base_str:>14}  {exp_str:>14}  {delta_str:>22}  {sentinel_mark}")
            results.append({
                "case": case,
                "metric": metric_key,
                "sentinel": is_sentinel,
                "baseline": base_val,
                "experiment": exp_val,
            })

        print()

    # -- Resumen sentinels ----------------------------------------------------
    print("-" * W)
    print("  Resumen sentinels (Phase 2E impacto directo):")
    print()
    sentinel_rows = [r for r in results if r["sentinel"]]
    if sentinel_rows:
        for r in sentinel_rows:
            b = r["baseline"]
            e = r["experiment"]
            delta_str = _fmt_delta(b, e)
            b_str = f"{b:.4f}" if b is not None else "n/a"
            e_str = f"{e:.4f}" if e is not None else "n/a"
            print(f"  {r['case']:<36}  {r['metric']:<44}")
            print(f"    baseline={b_str}  exp={e_str}  delta={delta_str}")
    else:
        print("  (sin sentinels con datos comparables)")

    if run_errors:
        print()
        print(f"  ADVERTENCIA: {len(run_errors)} caso(s) con error en ejecucion: {run_errors}")

    print()
    print("=" * W)
    print("  Experimento completado. Los reports experimentales no modifican")
    print("  reference_checks.json ni los baselines de referencia.")
    print("  Para documentar resultados ver docs/architecture/PHASE_2E_DESIGN.md.")
    print("=" * W)
    print()

    # -- Limpiar casos temporales ---------------------------------------------
    for p in created_temp_cases:
        try:
            p.unlink()
        except OSError:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())
