"""
phase2e_experiment_2_runner.py — Runner experimental Phase 2E, experimento 2.

Barre cuatro estrategias de deposicion CO en _transfer_hot_gas_contaminants() con
phase2e_two_zone_transport_enabled=true y phase2e_co_deposition_mode={modo}:

  all_upper       : 100% CO al upper del destino  (= baseline; cancela split)
  geometric_split : split h_upper_tgt / height_m  (Exp 1)
  upper_floor_90  : geometric_split con minimo 90% a upper
  upper_floor_95  : geometric_split con minimo 95% a upper

Casos evaluados:
  g4_gie_delayed_entry_hazard   (sentinel CO>1200 timing, FED timing, peak CO upper)
  v3_hallway_fed_exposure       (sentinel FED timing, max FED, peak CO upper)
  victim_fed_incapacitation     (sentinel final FED, peak CO global)
  cfast_two_room_door_open      (CO upper/lower room 1)

Uso:
    python scripts/simulation/phase2e_experiment_2_runner.py
    python scripts/simulation/phase2e_experiment_2_runner.py --skip-run
    python scripts/simulation/phase2e_experiment_2_runner.py --modes all_upper geometric_split

Codigo de salida:
    0 — barrido completado
    1 — error critico (Godot no encontrado, etc.)
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

ROOT        = Path(__file__).resolve().parents[2]
CASES_DIR   = ROOT / "sim" / "validation" / "cases"
REPORTS_DIR = ROOT / "sim" / "validation" / "reports"

# ---------------------------------------------------------------------------
# Godot
# ---------------------------------------------------------------------------

_GODOT_CANDIDATES = [
    "C:/Users/dangp/Desktop/Godot_v4.6.3-stable_win64_console.exe",
    "F:/OneDrive/Escritorio/Godot_v4.6.3-stable_win64_console.exe",
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
# Configuracion del experimento
# ---------------------------------------------------------------------------

MODES = ["all_upper", "geometric_split", "upper_floor_90", "upper_floor_95"]
CASES = [
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
    "cfast_two_room_door_open",
]

# Metricas de interes: (key_en_report, label_corto, sentinel)
METRICS_PER_CASE: dict[str, list[tuple[str, str, bool]]] = {
    "g4_gie_delayed_entry_hazard": [
        ("time_room_1_co_upper_above_1200_s", "g4 CO>1200 [s]      ", True),
        ("time_room_1_fed_above_0_1_s",       "g4 FED>0.1 [s]      ", True),
        ("room_1_peak_co_upper_ppm",           "g4 peak CO upper    ", True),
        ("room_1_final_co_upper_ppm",          "g4 final CO upper   ", False),
    ],
    "v3_hallway_fed_exposure": [
        ("time_room_1_fed_above_0_1_s",       "v3 FED>0.1 [s]      ", True),
        ("room_1_max_fed",                     "v3 max FED          ", True),
        ("room_1_peak_co_upper_ppm",           "v3 peak CO upper    ", False),
        ("room_1_peak_co_ppm",                 "v3 peak CO mixed    ", False),
    ],
    "victim_fed_incapacitation": [
        ("victim_v0_final_fed",                "vic final FED       ", True),
        ("peak_co_ppm_global",                 "vic peak CO [ppm]   ", True),
    ],
    "cfast_two_room_door_open": [
        ("room_1_final_co_upper_ppm",          "cfast CO upper r1   ", False),
        ("room_1_final_co_ppm",                "cfast CO mixed r1   ", False),
        ("peak_co_upper_ppm_global",           "cfast peak CO upper ", False),
    ],
}

# Nombre del suffix de reporte para cada modo
def _report_suffix(mode: str) -> str:
    return f"_p2e2_{mode}"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_report(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        return None


def _get_metric(report: dict | None, key: str) -> float | None:
    if report is None:
        return None
    if key in report:
        val = report[key]
        if isinstance(val, (int, float)):
            return float(val)
    metrics = report.get("metrics", {})
    if isinstance(metrics, dict) and key in metrics:
        val = metrics[key]
        if isinstance(val, (int, float)):
            return float(val)
        if isinstance(val, dict):
            if "value" in val:
                return float(val["value"])
            if "time_s" in val:
                return float(val["time_s"])
    thr = report.get("threshold_metrics", {})
    if isinstance(thr, dict) and key in thr:
        v = thr[key]
        if isinstance(v, (int, float)):
            return float(v)
    return None


def _delta_str(base: float | None, exp: float | None) -> str:
    if base is None or exp is None:
        return "n/a"
    d = exp - base
    pct = (d / abs(base) * 100.0) if base != 0.0 else 0.0
    sign = "+" if d >= 0 else ""
    return f"{sign}{d:.2f} ({sign}{pct:.1f}%)"


def _run_case(godot: Path, case_name: str, timeout_s: int = 300) -> bool:
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--",
           f"--validation-case={case_name}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode == 0
    except subprocess.TimeoutExpired:
        return False
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2E experiment 2 — CO deposition strategy sweep."
    )
    parser.add_argument("--godot", default=None, metavar="PATH")
    parser.add_argument("--skip-run", action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--modes", nargs="+", default=MODES, choices=MODES,
                        metavar="MODE", help="Subconjunto de modos a evaluar")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()

    active_modes: list[str] = args.modes

    W = 80
    print()
    print("=" * W)
    print("  Phase 2E Experiment 2 — CO Deposition Strategy Sweep")
    print(f"  Modos: {' | '.join(active_modes)}")
    print(f"  Casos: {' | '.join(CASES)}")
    print("=" * W)

    # -- Resolver Godot -------------------------------------------------------
    godot = None
    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("\n  ERROR: no se encontro Godot. Define --godot PATH o GODOT_EXE.\n")
            return 1
        print(f"\n  Godot: {godot}")

    # -- Cargar baselines -----------------------------------------------------
    baselines: dict[str, dict | None] = {}
    for case in CASES:
        baselines[case] = _load_report(REPORTS_DIR / f"{case}.json")

    # -- Ejecutar / verificar por modo ----------------------------------------
    created_temp: list[Path] = []
    run_errors: dict[str, list[str]] = {m: [] for m in active_modes}

    if not args.skip_run:
        print()
        total_runs = len(active_modes) * len(CASES)
        done = 0
        for mode in active_modes:
            for case in CASES:
                suffix = _report_suffix(mode)
                exp_case_name = case + suffix
                exp_case_path = CASES_DIR / f"{exp_case_name}.json"
                base_case_path = CASES_DIR / f"{case}.json"

                if not base_case_path.exists():
                    run_errors[mode].append(case)
                    done += 1
                    continue

                # Construir caso experimental
                case_data = json.loads(base_case_path.read_text(encoding="utf-8-sig"))
                overrides = dict(case_data.get("engine_overrides", {}))
                overrides["phase2e_two_zone_transport_enabled"] = True
                overrides["phase2e_co_deposition_mode"] = mode
                case_data["engine_overrides"] = overrides
                exp_case_path.write_text(
                    json.dumps(case_data, indent="\t", ensure_ascii=False),
                    encoding="utf-8"
                )
                created_temp.append(exp_case_path)

                # Ejecutar
                done += 1
                progress = f"[{done}/{total_runs}]"
                print(f"  {progress} {mode:<20} {case} ...", end=" ", flush=True)
                ok = _run_case(godot, exp_case_name, timeout_s=args.timeout)
                print("OK" if ok else "FAIL")
                if not ok:
                    run_errors[mode].append(case)

    # -- Recolectar resultados ------------------------------------------------
    # results[mode][case][metric] = float | None
    results: dict[str, dict[str, dict[str, float | None]]] = {}
    for mode in active_modes:
        results[mode] = {}
        for case in CASES:
            suffix = _report_suffix(mode)
            rpt = _load_report(REPORTS_DIR / f"{case}{suffix}.json")
            results[mode][case] = {}
            for key, _label, _s in METRICS_PER_CASE[case]:
                results[mode][case][key] = _get_metric(rpt, key)

    # -- Tabla de comparacion -------------------------------------------------
    print()
    print("-" * W)
    print("  TABLA COMPARATIVA — delta vs baseline (flag OFF)")
    print("-" * W)

    for case in CASES:
        base = baselines[case]
        metrics = METRICS_PER_CASE[case]
        # Header
        mode_header = "  ".join(f"{m:<22}" for m in active_modes)
        print()
        print(f"  [{case}]")
        print(f"  {'Metrica':<22}  {'Baseline':>10}  {mode_header}")
        print("  " + "-" * (22 + 10 + 4 + len(active_modes) * 24))

        for key, label, is_sentinel in metrics:
            base_val = _get_metric(base, key)
            base_str = f"{base_val:>10.3f}" if base_val is not None else f"{'n/a':>10}"
            sentinel_mark = " *" if is_sentinel else "  "
            cells = []
            for mode in active_modes:
                exp_val = results[mode][case].get(key)
                cells.append(f"{_delta_str(base_val, exp_val):<22}")
            print(f"  {label:<22}{sentinel_mark}{base_str}  {'  '.join(cells)}")

    # -- Tabla de sentinels ---------------------------------------------------
    print()
    print("-" * W)
    print("  SENTINELS — resumen por modo")
    print("-" * W)
    # Collect all sentinel (case, key, label) pairs
    sentinels: list[tuple[str, str, str]] = []
    for case in CASES:
        for key, label, is_s in METRICS_PER_CASE[case]:
            if is_s:
                sentinels.append((case, key, label))

    hdr = f"  {'Sentinel':<30}  {'Baseline':>10}  " + "  ".join(f"{m:<22}" for m in active_modes)
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))
    for case, key, label in sentinels:
        base_val = _get_metric(baselines[case], key)
        base_str = f"{base_val:>10.4f}" if base_val is not None else f"{'n/a':>10}"
        cells = []
        for mode in active_modes:
            exp_val = results[mode][case].get(key)
            cells.append(f"{_delta_str(base_val, exp_val):<22}")
        print(f"  {label:<30}  {base_str}  {'  '.join(cells)}")

    # -- Errores --------------------------------------------------------------
    any_err = any(v for v in run_errors.values())
    if any_err:
        print()
        print("  ADVERTENCIA — errores de ejecucion:")
        for mode, errs in run_errors.items():
            if errs:
                print(f"    {mode}: {errs}")

    # -- Limpiar casos temporales --------------------------------------------
    for p in created_temp:
        try:
            p.unlink()
        except OSError:
            pass

    print()
    print("=" * W)
    print("  Barrido completado. Reports experimentales guardados en")
    print("  sim/validation/reports/*_p2e2_*.json  (no modifican baselines).")
    print("=" * W)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
