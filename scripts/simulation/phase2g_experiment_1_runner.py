"""
phase2g_experiment_1_runner.py — Runner experimental Phase 2G, experimento 1.

Barre combinaciones de lower_source_fraction × guard del término fuente experimental
de CO en zona lower (_apply fase generación en CombustionSystem.gd).

Mecanismo:
  En cada paso de combustión, una fracción de generated_co_kg se asigna al lower
  implícito (co_lower = co_kg - co_upper_kg):
    room.co_kg      += generated_co_kg                          # total invariante
    room.co_upper_kg += generated_co_kg * (1 - fraction)       # upper recibe el resto

  Diferencia vs Phase 2F: Phase 2F redistribuía CO upper→lower DESPUÉS de generación.
  Phase 2G actúa EN el momento de generación, lo cual crea señal lower nueva paso a paso.

Flags activados:
  phase2g_co_lower_source_enabled  = true
  phase2g_co_lower_source_fraction = <barrido>
  phase2g_co_lower_source_guard    = <barrido>
  (phase2e y phase2f permanecen en default OFF)

Parámetros barridos:
  fraction : 0.000 | 0.005 | 0.010 | 0.020 | 0.050
  guard    : fire_room_only | only_when_hot_layer_above_1_8m | all_rooms_with_fire

Casos evaluados (5):
  g4_gie_delayed_entry_hazard      sentinel: CO>1200 timing, FED timing, peak CO upper
  v3_hallway_fed_exposure          sentinel: FED timing, max FED
  victim_fed_incapacitation        sentinel: final FED, peak CO global
  cfast_single_room_closed         observacional: CO upper / CO mixed final
  cfast_two_room_door_open         observacional: CO upper / CO mixed r1

Nomenclatura de reports experimentales:
  {case}_p2g1_f{frac_milli}_{guard_short}.json
  Ejemplos:
    g4_gie_delayed_entry_hazard_p2g1_f010_fr.json
    cfast_single_room_closed_p2g1_f050_g18m.json

Ventanas sentinel (para evaluación PASS/FAIL):
  g4 CO>1200 [s]   : [82.333, 92.333]
  g4 FED>0.1 [s]   : [187.75, 207.75]
  v3 FED>0.1 [s]   : [222.17, 282.17]
  v3 max FED       : >= 1.0
  vic final FED    : >= 0.7
  vic peak CO      : >= 1500.0 ppm

Uso:
    python scripts/simulation/phase2g_experiment_1_runner.py
    python scripts/simulation/phase2g_experiment_1_runner.py --skip-run
    python scripts/simulation/phase2g_experiment_1_runner.py --fractions 0.000 0.010 0.050

Código de salida:
    0 — barrido completado (puede haber runs individuales FAIL)
    1 — error crítico (Godot no encontrado, caso base no encontrado)
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
# Configuración del experimento
# ---------------------------------------------------------------------------

FRACTIONS: list[float] = [0.000, 0.005, 0.010, 0.020, 0.050]

GUARDS: list[str] = [
    "fire_room_only",
    "only_when_hot_layer_above_1_8m",
    "all_rooms_with_fire",
]

GUARD_SHORT: dict[str, str] = {
    "fire_room_only":                    "fr",
    "only_when_hot_layer_above_1_8m":    "g18m",
    "all_rooms_with_fire":               "all",
}

CASES = [
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
    "cfast_single_room_closed",
    "cfast_two_room_door_open",
]

# Métricas de interés: (key_en_report, label_corto, es_sentinel)
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
    "cfast_single_room_closed": [
        ("room_1_final_co_upper_ppm",          "sc CO upper final", False),
        ("room_1_final_co_ppm",                "sc CO mixed final", False),
        ("peak_co_upper_ppm_global",           "sc peak CO upper ", False),
        ("room_1_peak_co_ppm",                 "sc peak CO mixed ", False),
    ],
    "cfast_two_room_door_open": [
        ("room_1_final_co_upper_ppm",          "2r CO upper r1   ", False),
        ("room_1_final_co_ppm",                "2r CO mixed r1   ", False),
        ("peak_co_upper_ppm_global",           "2r peak CO upper ", False),
    ],
}

# Definición explícita de sentinels por case/key
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

def _frac_str(frac: float) -> str:
    """0.005 -> '005', 0.050 -> '050', 0.0 -> '000'"""
    return f"{int(round(frac * 1000)):03d}"


def _report_suffix(frac: float, guard: str) -> str:
    return f"_p2g1_f{_frac_str(frac)}_{GUARD_SHORT[guard]}"


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
    """Evalúa si val cumple el sentinel para (case, key). None si no aplica."""
    if val is None:
        return None
    for (sc, sk, lo, hi, _label) in SENTINELS:
        if sc == case and sk == key:
            if lo is not None and val < lo:
                return False
            if hi is not None and val > hi:
                return False
            return True
    return None


def _run_case(godot: Path, case_name: str, timeout_s: int = 300) -> bool:
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--",
           f"--validation-case={case_name}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, Exception):
        return False


def _combo_key(frac: float, guard: str) -> str:
    return f"f{_frac_str(frac)}_{GUARD_SHORT[guard]}"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2G experiment 1 — CO lower source term sweep."
    )
    parser.add_argument("--godot", default=None, metavar="PATH")
    parser.add_argument("--skip-run", action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--fractions", nargs="+", type=float, default=FRACTIONS,
                        metavar="FRAC")
    parser.add_argument("--guards", nargs="+", default=GUARDS, choices=GUARDS,
                        metavar="GUARD")
    parser.add_argument("--timeout", type=int, default=300)
    args = parser.parse_args()

    active_fracs: list[float]  = args.fractions
    active_guards: list[str]   = args.guards
    combos = [(f, g) for f in active_fracs for g in active_guards]

    W = 104
    print()
    print("=" * W)
    print("  Phase 2G Experiment 1 — CO Lower Source Term Sweep")
    print(f"  fraction : {' | '.join(_frac_str(f) for f in active_fracs)}")
    print(f"  guard    : {' | '.join(GUARD_SHORT[g] for g in active_guards)}")
    print(f"  Casos    : {' | '.join(CASES)}")
    print("=" * W)

    # -- Resolver Godot -------------------------------------------------------
    godot = None
    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("\n  ERROR: no se encontró Godot. Define --godot PATH o GODOT_EXE.\n")
            return 1
        print(f"\n  Godot: {godot}")

    # -- Cargar baselines -----------------------------------------------------
    baselines: dict[str, "dict | None"] = {}
    for case in CASES:
        baselines[case] = _load_report(REPORTS_DIR / f"{case}.json")

    # -- Ejecutar / verificar por combinación ---------------------------------
    created_temp: list[Path] = []
    run_errors: dict[str, list[str]] = {_combo_key(f, g): [] for f, g in combos}

    if not args.skip_run:
        print()
        total_runs = len(combos) * len(CASES)
        done = 0
        for frac, guard in combos:
            for case in CASES:
                suffix    = _report_suffix(frac, guard)
                exp_name  = case + suffix
                base_path = CASES_DIR / f"{case}.json"
                exp_path  = CASES_DIR / f"{exp_name}.json"
                ck        = _combo_key(frac, guard)

                if not base_path.exists():
                    print(f"  SKIP: caso base no encontrado: {base_path.name}")
                    run_errors[ck].append(case)
                    done += 1
                    continue

                # Construir caso experimental
                case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
                overrides = dict(case_data.get("engine_overrides", {}))
                overrides["phase2g_co_lower_source_enabled"]  = True
                overrides["phase2g_co_lower_source_fraction"] = frac
                overrides["phase2g_co_lower_source_guard"]    = guard
                # phase2e y phase2f permanecen en default (OFF)
                case_data["engine_overrides"] = overrides
                exp_path.write_text(
                    json.dumps(case_data, indent="\t", ensure_ascii=False),
                    encoding="utf-8"
                )
                created_temp.append(exp_path)

                done += 1
                label = f"f={frac:.3f}  {guard}"
                print(f"  [{done:>3}/{total_runs}] {label:<60} {case} ...",
                      end=" ", flush=True)
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
    results: dict[tuple, dict[str, dict[str, "float | None"]]] = {}
    for frac, guard in combos:
        results[(frac, guard)] = {}
        for case in CASES:
            suffix = _report_suffix(frac, guard)
            rpt = _load_report(REPORTS_DIR / f"{case}{suffix}.json")
            results[(frac, guard)][case] = {}
            for key, _label, _s in METRICS_PER_CASE[case]:
                results[(frac, guard)][case][key] = _get_metric(rpt, key)

    # -- Tabla comparativa por caso ----------------------------------------
    print()
    print("-" * W)
    print("  TABLA COMPARATIVA — delta vs baseline (flag OFF)")
    print("-" * W)

    for case in CASES:
        base    = baselines[case]
        metrics = METRICS_PER_CASE[case]
        print()
        print(f"  [{case}]")
        for key, label, is_sentinel in metrics:
            base_val = _get_metric(base, key)
            base_str = f"{base_val:>10.3f}" if base_val is not None else f"{'n/a':>10}"
            sentinel_mark = " *" if is_sentinel else "  "
            print(f"  {label}{sentinel_mark}  base={base_str}")
            for frac in active_fracs:
                frac_label = f"    f={frac:.3f}"
                parts = []
                for guard in active_guards:
                    exp_val = results[(frac, guard)][case].get(key)
                    sp = _sentinel_pass(case, key, exp_val)
                    tag = "" if sp is None else (" [OK]" if sp else " [!!]")
                    parts.append(
                        f"{GUARD_SHORT[guard]}:{_delta_str(base_val, exp_val, 16)}{tag}"
                    )
                print(f"  {frac_label}  " + "  ".join(parts))

    # -- Tabla resumen sentinels por combinación --------------------------------
    print()
    print("-" * W)
    sl_labels = [lbl for (_, _, _, _, lbl) in SENTINELS]
    w_col = 14
    header = f"  {'Combo':<32}" + "".join(f"{lbl:<{w_col}}" for lbl in sl_labels) + "  Total"
    print(header)
    print("  " + "-" * (len(header) - 2))

    # Fila baseline
    base_vals_row: list[str] = []
    for (sc, sk, _lo, _hi, _lbl) in SENTINELS:
        bv = _get_metric(baselines.get(sc), sk)
        base_vals_row.append(f"{bv:.3f}" if bv is not None else "n/a")
    print(f"  {'BASELINE':<32}" + "".join(f"{v:<{w_col}}" for v in base_vals_row) + f"  {'6/6'}")

    for frac, guard in combos:
        row_parts: list[str] = []
        passes = 0
        total_s = 0
        for (sc, sk, lo, hi, _lbl) in SENTINELS:
            ev = results[(frac, guard)][sc].get(sk)
            total_s += 1
            ok: bool = True
            if ev is None:
                ok = False
            else:
                if lo is not None and ev < lo:
                    ok = False
                if hi is not None and ev > hi:
                    ok = False
            if ok:
                passes += 1
            tag = " [OK]" if ok else " [!!]"
            val_s = f"{ev:.3f}" if ev is not None else "n/a"
            row_parts.append(f"{val_s}{tag}")
        combo_lbl = f"f={frac:.3f}  {GUARD_SHORT[guard]}"
        print(
            f"  {combo_lbl:<32}"
            + "".join(f"{p:<{w_col}}" for p in row_parts)
            + f"  {passes}/{total_s}"
        )

    # -- Resumen de errores de ejecución ------------------------------------
    total_run_errors = sum(len(v) for v in run_errors.values())
    print()
    print("=" * W)
    if total_run_errors == 0:
        n_combos = len(combos)
        n_cases  = len(CASES)
        print(f"  {n_combos * n_cases}/{n_combos * n_cases} runs OK — "
              f"{n_combos} combos × {n_cases} casos")
    else:
        print(f"  ADVERTENCIA: {total_run_errors} runs fallidos")
        for ck, errs in run_errors.items():
            if errs:
                print(f"    {ck}: {errs}")
    print("=" * W)
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
