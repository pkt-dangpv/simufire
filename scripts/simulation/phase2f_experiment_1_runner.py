"""
phase2f_experiment_1_runner.py — Runner experimental Phase 2F, experimento 1.

Barre combinaciones de mixing_rate × guard del mecanismo experimental de mixing
CO inter-capa (_apply_phase2f_co_interlayer_mixing), siempre con:
  phase2e_two_zone_transport_enabled = true
  phase2e_co_deposition_mode         = "all_upper"   (transporte sigue 100% upper)
  phase2f_co_interlayer_mixing_enabled = true

Parametros barridos:
  mixing_rate : 0.000 | 0.002 | 0.005 | 0.010 | 0.020   (fraccion co_upper_kg/s)
  guard       : no_guard | only_when_upper_gas_kg_lt_0_1
              | only_when_hot_layer_interface_above_1_8m
              | only_when_no_occupant_in_upper_probe

Casos evaluados (4):
  g4_gie_delayed_entry_hazard   sentinel: CO>1200 timing, FED timing, peak CO upper
  v3_hallway_fed_exposure       sentinel: FED timing, max FED
  victim_fed_incapacitation     sentinel: final FED, peak CO global
  cfast_two_room_door_open      observacional: CO upper / CO mixed r1

Nomenclatura de reports experimentales:
  {case}_p2f1_r{rate_milli}_{guard_short}.json
  Ejemplos:
    g4_gie_delayed_entry_hazard_p2f1_r002_ng.json
    v3_hallway_fed_exposure_p2f1_r010_g18m.json

Ventanas sentinel (para evaluacion PASS/FAIL):
  g4 CO>1200 [s]   : [82.333, 92.333]
  g4 FED>0.1 [s]   : [187.75, 207.75]
  v3 FED>0.1 [s]   : [222.17, 282.17]
  v3 max FED       : >= 1.0
  vic final FED    : >= 0.7
  vic peak CO      : >= 1500.0 ppm

Uso:
    python scripts/simulation/phase2f_experiment_1_runner.py
    python scripts/simulation/phase2f_experiment_1_runner.py --skip-run
    python scripts/simulation/phase2f_experiment_1_runner.py --rates 0.000 0.005 0.020

Codigo de salida:
    0 — barrido completado (puede haber runs individuales FAIL)
    1 — error critico (Godot no encontrado, caso base no encontrado)
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
    "C:/Users/dangp/Desktop/Godot_v4.7.1-stable_win64_console.exe",
    "F:/OneDrive/Escritorio/Godot_v4.7.1-stable_win64_console.exe",
]


def find_godot(requested: str | None = None) -> "Path | None":
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

MIXING_RATES: list[float] = [0.000, 0.002, 0.005, 0.010, 0.020]

GUARDS: list[str] = [
    "no_guard",
    "only_when_upper_gas_kg_lt_0_1",
    "only_when_hot_layer_interface_above_1_8m",
    "only_when_no_occupant_in_upper_probe",
]

GUARD_SHORT: dict[str, str] = {
    "no_guard":                                   "ng",
    "only_when_upper_gas_kg_lt_0_1":              "g01",
    "only_when_hot_layer_interface_above_1_8m":   "g18m",
    "only_when_no_occupant_in_upper_probe":       "gup",
}

CASES = [
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
    "cfast_two_room_door_open",
]

# Metricas de interes: (key_en_report, label_corto, es_sentinel)
METRICS_PER_CASE: dict[str, list[tuple[str, str, bool]]] = {
    "g4_gie_delayed_entry_hazard": [
        ("time_room_1_co_upper_above_1200_s", "g4 CO>1200 [s]   ", True),
        ("time_room_1_fed_above_0_1_s",       "g4 FED>0.1 [s]   ", True),
        ("room_1_peak_co_upper_ppm",           "g4 peak CO upper ", True),
        ("room_1_final_co_upper_ppm",          "g4 final CO upper", False),
    ],
    "v3_hallway_fed_exposure": [
        ("time_room_1_fed_above_0_1_s",       "v3 FED>0.1 [s]   ", True),
        ("room_1_max_fed",                     "v3 max FED       ", True),
        ("room_1_peak_co_upper_ppm",           "v3 peak CO upper ", False),
        ("room_1_peak_co_ppm",                 "v3 peak CO mixed ", False),
    ],
    "victim_fed_incapacitation": [
        ("victim_v0_final_fed",                "vic final FED    ", True),
        ("peak_co_ppm_global",                 "vic peak CO [ppm]", True),
    ],
    "cfast_two_room_door_open": [
        ("room_1_final_co_upper_ppm",          "cfast CO upper r1", False),
        ("room_1_final_co_ppm",                "cfast CO mixed r1", False),
        ("peak_co_upper_ppm_global",           "cfast peak CO up ", False),
    ],
}

# Ventanas sentinel: (key, lo, hi) donde None = sin limite
SENTINEL_WINDOWS: list[tuple[str, float | None, float | None]] = [
    ("time_room_1_co_upper_above_1200_s", 82.333, 92.333),
    ("time_room_1_fed_above_0_1_s",       187.75, 207.75),   # g4
    ("time_room_1_fed_above_0_1_s",       222.17, 282.17),   # v3 — mismo key, case distinto
    ("room_1_max_fed",                    1.0,    None),
    ("victim_v0_final_fed",               0.7,    None),
    ("peak_co_ppm_global",                1500.0, None),
]

# Definicion explicita de sentinels por case/key para evaluacion correcta
SENTINELS: list[tuple[str, str, float | None, float | None, str]] = [
    # (case, key, lo, hi, label)
    ("g4_gie_delayed_entry_hazard", "time_room_1_co_upper_above_1200_s", 82.333, 92.333,  "g4 CO>1200"),
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",       187.75, 207.75,  "g4 FED"),
    ("v3_hallway_fed_exposure",     "time_room_1_fed_above_0_1_s",       222.17, 282.17,  "v3 FED"),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                    1.0,    None,     "v3 maxFED"),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",               0.7,    None,     "vic FED"),
    ("victim_fed_incapacitation",   "peak_co_ppm_global",                1500.0, None,     "vic CO"),
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _rate_str(rate: float) -> str:
    """0.005 -> '005', 0.020 -> '020', 0.0 -> '000'"""
    return f"{int(round(rate * 1000)):03d}"


def _report_suffix(rate: float, guard: str) -> str:
    return f"_p2f1_r{_rate_str(rate)}_{GUARD_SHORT[guard]}"


def _load_report(path: Path) -> "dict | None":
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _get_metric(report: "dict | None", key: str) -> "float | None":
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


def _delta_str(base: "float | None", exp: "float | None", width: int = 18) -> str:
    if base is None or exp is None:
        return f"{'n/a':<{width}}"
    d = exp - base
    pct = (d / abs(base) * 100.0) if base != 0.0 else 0.0
    sign = "+" if d >= 0 else ""
    s = f"{sign}{d:.2f} ({sign}{pct:.1f}%)"
    return f"{s:<{width}}"


def _sentinel_pass(case: str, key: str, val: "float | None") -> "bool | None":
    """Evalua si val cumple el sentinel para (case, key). None si no aplica."""
    if val is None:
        return None
    for (sc, sk, lo, hi, _label) in SENTINELS:
        if sc == case and sk == key:
            if lo is not None and val < lo:
                return False
            if hi is not None and val > hi:
                return False
            return True
    return None  # no es sentinel


def _run_case(godot: Path, case_name: str, timeout_s: int = 300) -> bool:
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--",
           f"--validation-case={case_name}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, Exception):
        return False


def _combo_key(rate: float, guard: str) -> str:
    return f"r{_rate_str(rate)}_{GUARD_SHORT[guard]}"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2F experiment 1 — CO interlayer mixing sweep."
    )
    parser.add_argument("--godot", default=None, metavar="PATH")
    parser.add_argument("--skip-run", action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--rates", nargs="+", type=float, default=MIXING_RATES,
                        metavar="RATE")
    parser.add_argument("--guards", nargs="+", default=GUARDS, choices=GUARDS,
                        metavar="GUARD")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()

    active_rates: list[float] = args.rates
    active_guards: list[str]  = args.guards
    combos = [(r, g) for r in active_rates for g in active_guards]

    W = 96
    print()
    print("=" * W)
    print("  Phase 2F Experiment 1 — CO Interlayer Mixing Sweep")
    print(f"  mixing_rate : {' | '.join(_rate_str(r) for r in active_rates)}")
    print(f"  guard       : {' | '.join(GUARD_SHORT[g] for g in active_guards)}")
    print(f"  Casos       : {' | '.join(CASES)}")
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
    baselines: dict[str, "dict | None"] = {}
    for case in CASES:
        baselines[case] = _load_report(REPORTS_DIR / f"{case}.json")

    # -- Ejecutar / verificar por combinacion ---------------------------------
    created_temp: list[Path] = []
    run_errors: dict[str, list[str]] = {_combo_key(r, g): [] for r, g in combos}

    if not args.skip_run:
        print()
        total_runs = len(combos) * len(CASES)
        done = 0
        for rate, guard in combos:
            for case in CASES:
                suffix       = _report_suffix(rate, guard)
                exp_name     = case + suffix
                base_path    = CASES_DIR / f"{case}.json"
                exp_path     = CASES_DIR / f"{exp_name}.json"
                ck           = _combo_key(rate, guard)

                if not base_path.exists():
                    print(f"  SKIP: caso base no encontrado: {base_path.name}")
                    run_errors[ck].append(case)
                    done += 1
                    continue

                # Construir caso experimental
                case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
                overrides = dict(case_data.get("engine_overrides", {}))
                overrides["phase2e_two_zone_transport_enabled"]  = True
                overrides["phase2e_co_deposition_mode"]          = "all_upper"
                overrides["phase2f_co_interlayer_mixing_enabled"] = True
                overrides["phase2f_co_interlayer_mixing_rate"]    = rate
                overrides["phase2f_co_interlayer_mixing_guard"]   = guard
                case_data["engine_overrides"] = overrides
                exp_path.write_text(
                    json.dumps(case_data, indent="\t", ensure_ascii=False),
                    encoding="utf-8"
                )
                created_temp.append(exp_path)

                done += 1
                label = f"r={rate:.3f}  {guard}"
                print(f"  [{done:>3}/{total_runs}] {label:<55} {case} ...", end=" ", flush=True)
                ok = _run_case(godot, exp_name, timeout_s=args.timeout)
                print("OK" if ok else "FAIL")
                if not ok:
                    run_errors[ck].append(case)

    # -- Limpiar temporales ---------------------------------------------------
    for p in created_temp:
        try:
            p.unlink()
        except Exception:
            pass
    created_temp.clear()

    # -- Recolectar resultados ------------------------------------------------
    # results[(rate, guard)][case][key] = float | None
    results: dict[tuple, dict[str, dict[str, "float | None"]]] = {}
    for rate, guard in combos:
        results[(rate, guard)] = {}
        for case in CASES:
            suffix = _report_suffix(rate, guard)
            rpt = _load_report(REPORTS_DIR / f"{case}{suffix}.json")
            results[(rate, guard)][case] = {}
            for key, _label, _s in METRICS_PER_CASE[case]:
                results[(rate, guard)][case][key] = _get_metric(rpt, key)

    # -- Tabla de comparacion por caso ----------------------------------------
    print()
    print("-" * W)
    print("  TABLA COMPARATIVA — delta vs baseline (flag OFF, all_upper transport)")
    print("-" * W)

    for case in CASES:
        base = baselines[case]
        metrics = METRICS_PER_CASE[case]
        print()
        print(f"  [{case}]")
        # Header: primero un subconjunto de combos para legibilidad
        # Mostrar solo combinaciones rate × guard agrupadas por rate
        for key, label, is_sentinel in metrics:
            base_val = _get_metric(base, key)
            base_str = f"{base_val:>10.3f}" if base_val is not None else f"{'n/a':>10}"
            sentinel_mark = " *" if is_sentinel else "  "
            print(f"  {label}{sentinel_mark}  base={base_str}")
            for rate in active_rates:
                rate_label = f"    r={rate:.3f}"
                parts = []
                for guard in active_guards:
                    exp_val = results[(rate, guard)][case].get(key)
                    sp = _sentinel_pass(case, key, exp_val)
                    tag = "" if sp is None else (" [OK]" if sp else " [!!]")
                    parts.append(f"{GUARD_SHORT[guard]}:{_delta_str(base_val, exp_val, 16)}{tag}")
                print(f"  {rate_label}  " + "  ".join(parts))

    # -- Tabla resumen sentinels por combinacion --------------------------------
    print()
    print("-" * W)
    print("  SENTINELS — PASS count por (rate, guard)  [max=6]")
    print("-" * W)
    sentinel_labels = [lbl for (_, _, _, _, lbl) in SENTINELS]
    header_sent = "  ".join(f"{lbl:<12}" for lbl in sentinel_labels)
    print(f"  {'Combo':<28}  {header_sent}  Total")
    print("  " + "-" * (28 + 2 + len(SENTINELS) * 14 + 8))

    # Baseline row
    baseline_row: list[str] = []
    for (sc, sk, lo, hi, _lbl) in SENTINELS:
        base_val = _get_metric(baselines[sc], sk)
        sp = _sentinel_pass(sc, sk, base_val)
        bv_str = f"{base_val:.3f}" if base_val is not None else "n/a"
        baseline_row.append(f"{bv_str:<12}")
    print(f"  {'BASELINE':<28}  " + "  ".join(baseline_row) + "  6/6")

    for rate, guard in combos:
        combo_label = f"r={rate:.3f}  {GUARD_SHORT[guard]}"
        row_cells: list[str] = []
        pass_count = 0
        for (sc, sk, lo, hi, _lbl) in SENTINELS:
            exp_val = results[(rate, guard)][sc].get(sk)
            sp = _sentinel_pass(sc, sk, exp_val)
            if sp is True:
                pass_count += 1
            ev_str = f"{exp_val:.3f}" if exp_val is not None else "n/a"
            tag = "" if sp is None else (" [OK]" if sp else "[!!] ")
            row_cells.append(f"{ev_str+tag:<12}")
        print(f"  {combo_label:<28}  " + "  ".join(row_cells) + f"  {pass_count}/6")

    # -- Resumen de errores ---------------------------------------------------
    any_error = any(v for v in run_errors.values())
    if any_error:
        print()
        print("  ADVERTENCIA — errores de ejecucion:")
        for ck, cases_err in run_errors.items():
            if cases_err:
                print(f"    {ck}: {cases_err}")

    print()
    print("=" * W)
    print("  Barrido completado. Reports experimentales en")
    print("  sim/validation/reports/*_p2f1_*.json  (no modifican baselines).")
    print("=" * W)
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
