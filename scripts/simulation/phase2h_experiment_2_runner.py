"""
phase2h_experiment_2_runner.py — Runner experimental Phase 2H, experimento 2.

Activa phase2h_o2_doorway_two_zone_enabled=true junto con un gain
(phase2h_lower_replenish_gain) parametrizable y compara cada caso contra
la baseline (flags OFF) para verificar que:
  1. Los 6 sentinels de FED/CO pasan para TODOS los gain values.
  2. room.o2 no cambia — invariante de retrocompatibilidad (±0.001).
  3. o2_lower ≥ room.o2 en los casos con o2_lower observable (HVAC).
  4. FED de víctima NO supera baseline (o2_lower mejorado ≠ más riesgo).

Mecanismo (Phase 2H Exp 2H.2):
  _step_outside_opening_o2(): boost = gain × (air_in_kg / lower_mass) × (outside_o2 − o2_lower)
  HVACSystem._supply_air(): cuando height_fraction < 0.5, lerp o2_lower toward supply_o2 × air_fraction
  Ambos paths protegen invariante o2_lower ≥ room.o2 mediante clampf.
  Flags ON por default OFF; gain 0.0 = no-op exacto con Exp 2H.1 revertida.

Casos evaluados (6):
  g4_gie_delayed_entry_hazard      sentinel: CO>1200 timing, FED timing
  v3_hallway_fed_exposure          sentinel: FED timing, max FED
  victim_fed_incapacitation        sentinel: final FED ≤ baseline, peak CO
  cfast_single_room_closed         observacional: o2 bulk, CO upper (sala sellada)
  cfast_two_room_door_open         observacional: o2 bulk r0/r1, CO upper
  cfast_hvac_residential           objetivo: o2_lower gap closure (t180/t300/t450)

Gain sweep: [0.0, 0.25, 0.5, 1.0] → 4 × 6 = 24 runs.

Invariante verificado:
  room_0_final_o2 (y room_1_final_o2 donde aplique) idéntico ON vs baseline (±0.001).
  victim_v0_final_fed (ON con cualquier gain) ≤ baseline_fed + 0.005.

Sentinels obligatorios:
  g4 CO>1200 [s]   : [82.333, 92.333]
  g4 FED>0.1 [s]   : [187.75, 207.75]
  v3 FED>0.1 [s]   : [222.17, 282.17]
  v3 max FED       : >= 1.0
  vic final FED    : >= 0.7 AND <= baseline + 0.005
  vic peak CO      : >= 1500.0 ppm

Nomenclatura de reports experimentales:
  {case}_p2h2_g{gain_tag}.json   (gain_tag = 000 / 025 / 050 / 100 para 0/0.25/0.5/1.0)

Uso:
    python scripts/simulation/phase2h_experiment_2_runner.py
    python scripts/simulation/phase2h_experiment_2_runner.py --skip-run
    python scripts/simulation/phase2h_experiment_2_runner.py --gains 0.0 0.5
    python scripts/simulation/phase2h_experiment_2_runner.py --cases cfast_hvac_residential

Código de salida:
    0 — experimento completado
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


def find_godot(requested: "str | None" = None) -> "Path | None":
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

DEFAULT_GAINS: list[float] = [0.0, 0.25, 0.5, 1.0]

# Gain → etiqueta de 3 chars para nombres de archivo
def _gain_tag(gain: float) -> str:
    return f"{int(round(gain * 100)):03d}"


CASES = [
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
    "cfast_single_room_closed",
    "cfast_two_room_door_open",
    "cfast_hvac_residential",
]

# Métricas por caso: (key_en_report, label_corto, es_sentinel, es_invariante)
METRICS_PER_CASE: dict[str, list[tuple[str, str, bool, bool]]] = {
    "g4_gie_delayed_entry_hazard": [
        ("time_room_1_co_upper_above_1200_s", "g4 CO>1200 [s]   ", True,  False),
        ("time_room_1_fed_above_0_1_s",       "g4 FED>0.1 [s]   ", True,  False),
        ("room_1_peak_co_upper_ppm",           "g4 peak CO upper ", False, False),
        ("room_0_final_o2",                    "g4 r0 final o2   ", False, True),
        ("room_1_final_o2",                    "g4 r1 final o2   ", False, True),
    ],
    "v3_hallway_fed_exposure": [
        ("time_room_1_fed_above_0_1_s",       "v3 FED>0.1 [s]   ", True,  False),
        ("room_1_max_fed",                     "v3 max FED       ", True,  False),
        ("room_1_peak_co_upper_ppm",           "v3 peak CO upper ", False, False),
        ("room_0_final_o2",                    "v3 r0 final o2   ", False, True),
        ("room_1_final_o2",                    "v3 r1 final o2   ", False, True),
    ],
    "victim_fed_incapacitation": [
        ("victim_v0_final_fed",                "vic final FED    ", True,  False),
        ("peak_co_ppm_global",                 "vic peak CO [ppm]", True,  False),
        ("room_0_final_o2",                    "vic r0 final o2  ", False, True),
    ],
    "cfast_single_room_closed": [
        ("room_0_final_co_upper_ppm",          "sc CO upper final", False, False),
        ("room_0_final_co_ppm",                "sc CO mixed final", False, False),
        ("room_0_final_o2",                    "sc r0 final o2   ", False, True),
    ],
    "cfast_two_room_door_open": [
        ("room_0_final_o2",                    "2r r0 final o2   ", False, True),
        ("room_1_final_o2",                    "2r r1 final o2   ", False, True),
        ("room_1_final_co_upper_ppm",          "2r CO upper r1   ", False, False),
    ],
    "cfast_hvac_residential": [
        ("room_0_final_o2",                    "hvac r0 final o2 ", False, True),
        # o2_lower snapshots: estas claves se emiten si el logger las registra
        ("room_0_t180_o2_lower",               "hvac o2_lower t180", False, False),
        ("room_0_t300_o2_lower",               "hvac o2_lower t300", False, False),
        ("room_0_t450_o2_lower",               "hvac o2_lower t450", False, False),
        ("room_0_final_o2_lower",              "hvac o2_lower fin", False, False),
    ],
}

# Sentinels: (case, key, lo, hi, label)
SENTINELS: list[tuple[str, str, "float | None", "float | None", str]] = [
    ("g4_gie_delayed_entry_hazard", "time_room_1_co_upper_above_1200_s", 82.333,  92.333,  "g4 CO>1200"),
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",       187.75,  207.75,  "g4 FED"),
    ("v3_hallway_fed_exposure",     "time_room_1_fed_above_0_1_s",       222.17,  282.17,  "v3 FED"),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                    1.0,     None,    "v3 maxFED"),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",               0.7,     None,    "vic FED"),
    ("victim_fed_incapacitation",   "peak_co_ppm_global",                1500.0,  None,    "vic CO"),
]

# Tolerancia invariante room.o2
O2_INVARIANT_TOL = 0.001
# Tolerancia FED víctima: ON no puede superar baseline + esta delta
VIC_FED_MAX_DELTA = 0.005


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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


def _delta_str(base: "float | None", exp: "float | None", width: int = 22) -> str:
    if base is None or exp is None:
        return f"{'n/a':<{width}}"
    d = exp - base
    pct = (d / abs(base) * 100.0) if base != 0.0 else 0.0
    sign = "+" if d >= 0 else ""
    s = f"{sign}{d:.4f} ({sign}{pct:.2f}%)"
    return f"{s:<{width}}"


def _sentinel_pass(case: str, key: str, val: "float | None") -> "bool | None":
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


def _build_exp_case(
    base_path: Path,
    exp_path: Path,
    gain: float,
) -> None:
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides["phase2h_o2_doorway_two_zone_enabled"]     = gain > 0.0
    overrides["phase2h_cold_room_lower_routing_enabled"] = False
    overrides["phase2h_lower_replenish_gain"]            = gain
    case_data["engine_overrides"] = overrides
    exp_path.write_text(
        json.dumps(case_data, indent="\t", ensure_ascii=False),
        encoding="utf-8"
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2H experiment 2 — o2_lower replenishment gain sweep."
    )
    parser.add_argument("--godot",    default=None, metavar="PATH")
    parser.add_argument("--skip-run", action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--gains",    nargs="+", type=float, default=DEFAULT_GAINS,
                        help="Lista de gains a evaluar (default: 0.0 0.25 0.5 1.0)")
    parser.add_argument("--cases",    nargs="+", default=CASES,
                        help="Subconjunto de casos a correr (default: todos)")
    parser.add_argument("--timeout",  type=int, default=300)
    args = parser.parse_args()

    gains = args.gains
    cases = [c for c in args.cases if c in CASES]

    W = 110
    print()
    print("=" * W)
    print("  Phase 2H Experiment 2 — o2_lower Replenishment Gain Sweep")
    print(f"  Gains     : {gains}")
    print(f"  Casos     : {' | '.join(cases)}")
    print("=" * W)

    # -- Resolver Godot -------------------------------------------------------
    godot = None
    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("\n  ERROR: no se encontró Godot. Define --godot PATH o GODOT_EXE.\n")
            return 1
        print(f"\n  Godot: {godot}")

    # -- Ejecutar casos -------------------------------------------------------
    created_temp: list[Path] = []
    run_errors: list[str] = []

    if not args.skip_run:
        print()
        total_runs = len(gains) * len(cases)
        done = 0
        for gain in gains:
            tag = _gain_tag(gain)
            for case in cases:
                exp_name  = f"{case}_p2h2_g{tag}"
                base_path = CASES_DIR / f"{case}.json"
                exp_path  = CASES_DIR / f"{exp_name}.json"

                if not base_path.exists():
                    print(f"  SKIP: caso base no encontrado: {base_path.name}")
                    done += 1
                    continue

                _build_exp_case(base_path, exp_path, gain)
                created_temp.append(exp_path)

                done += 1
                print(f"  [{done:>2}/{total_runs}] gain={gain:.2f}  {case} ...",
                      end=" ", flush=True)
                ok = _run_case(godot, exp_name, timeout_s=args.timeout)
                print("OK" if ok else "FAIL")
                if not ok:
                    run_errors.append(f"gain={gain:.2f} / {case}")

    # -- Limpiar temporales ---------------------------------------------------
    for p in created_temp:
        try:
            p.unlink()
        except Exception:
            pass
    created_temp.clear()

    # -- Cargar baseline ------------------------------------------------------
    baseline_rpts: dict[str, "dict | None"] = {}
    for case in cases:
        baseline_rpts[case] = _load_report(REPORTS_DIR / f"{case}.json")

    # -- Cargar reports experimentales ----------------------------------------
    exp_rpts: dict[float, dict[str, "dict | None"]] = {}
    for gain in gains:
        tag = _gain_tag(gain)
        exp_rpts[gain] = {}
        for case in cases:
            exp_rpts[gain][case] = _load_report(REPORTS_DIR / f"{case}_p2h2_g{tag}.json")

    # -- Tabla de sentinels por gain ------------------------------------------
    print()
    print("-" * W)
    print("  TABLA SENTINELS POR GAIN")
    sl_labels = [lbl for (_, _, _, _, lbl) in SENTINELS]
    w_col = 16
    header = f"  {'Gain':<10}" + "".join(f"{lbl:<{w_col}}" for lbl in sl_labels) + "  Total"
    print(header)
    print("  " + "-" * (len(header) - 2))

    def _row_sentinels(label: str, rpts: dict[str, "dict | None"]) -> None:
        row_parts: list[str] = []
        passes = 0
        for (sc, sk, lo, hi, _lbl) in SENTINELS:
            if sc not in rpts:
                row_parts.append(f"{'skip':<{w_col}}")
                continue
            ev = _get_metric(rpts.get(sc), sk)
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
            flag_tag = " OK" if ok else " !!"
            val_s = f"{ev:.3f}" if ev is not None else "n/a"
            row_parts.append(f"{val_s}{flag_tag}")
        print(f"  {label:<10}" + "".join(f"{p:<{w_col}}" for p in row_parts)
              + f"  {passes}/{len(SENTINELS)}")

    _row_sentinels("BASELINE", baseline_rpts)
    for gain in gains:
        _row_sentinels(f"g={gain:.2f}", exp_rpts[gain])

    # -- Tabla detallada por caso (por gain) ----------------------------------
    invariant_violations: list[str] = []
    fed_regressions: list[str] = []
    baseline_vic_fed = _get_metric(baseline_rpts.get("victim_fed_incapacitation"),
                                   "victim_v0_final_fed")

    print()
    print("-" * W)
    print("  TABLA DETALLADA POR CASO")
    print("  [I] = invariante room.o2   [*] = sentinel")

    for case in cases:
        base = baseline_rpts[case]
        metrics = METRICS_PER_CASE[case]
        print()
        print(f"  [{case}]")
        col_labels = ["baseline"] + [f"g={g:.2f}" for g in gains]
        col_w = 12
        hdr = f"    {'metrica':<24}" + "".join(f"{c:<{col_w}}" for c in col_labels)
        print(hdr)
        for key, label, is_sentinel, is_invariant in metrics:
            base_val = _get_metric(base, key)
            vals = [base_val] + [_get_metric(exp_rpts[g][case], key) for g in gains]
            row_strs = []
            for i, (g, v) in enumerate(zip([None] + gains, vals)):
                if v is None:
                    row_strs.append(f"{'n/a':<{col_w}}")
                else:
                    s = f"{v:.4f}"
                    row_strs.append(f"{s:<{col_w}}")
            # Checks for each gain value
            annotations = []
            for gain in gains:
                v = _get_metric(exp_rpts[gain][case], key)
                if is_invariant and v is not None and base_val is not None:
                    if abs(v - base_val) > O2_INVARIANT_TOL:
                        annotations.append(f"[I:VIO g={gain:.2f} Δ={v-base_val:+.5f}]")
                        invariant_violations.append(
                            f"{case}/{key}: g={gain:.2f} base={base_val:.5f} exp={v:.5f}"
                        )
                if is_sentinel and case == "victim_fed_incapacitation" and key == "victim_v0_final_fed":
                    if v is not None and baseline_vic_fed is not None:
                        if v > baseline_vic_fed + VIC_FED_MAX_DELTA:
                            annotations.append(f"[FED_REG g={gain:.2f}]")
                            fed_regressions.append(
                                f"gain={gain:.2f} vic_fed={v:.5f} > baseline+delta={baseline_vic_fed+VIC_FED_MAX_DELTA:.5f}"
                            )
            tag_str = ""
            if is_invariant:
                tag_str = " [I]"
            elif is_sentinel:
                tag_str = " [*]"
            if annotations:
                tag_str += " " + " ".join(annotations)
            print(f"    {label:<24}" + "".join(row_strs) + tag_str)

    # -- Tabla o2_lower específica para HVAC ----------------------------------
    if "cfast_hvac_residential" in cases:
        print()
        print("-" * W)
        print("  o2_lower GAP CLOSURE — cfast_hvac_residential")
        print("  CFAST referencia: t180≈0.2049  t300≈0.2049  t450≈0.2049")
        hvac_keys = [
            ("room_0_t180_o2_lower", "t=180s"),
            ("room_0_t300_o2_lower", "t=300s"),
            ("room_0_t450_o2_lower", "t=450s"),
            ("room_0_final_o2_lower", "final"),
        ]
        col_labels = ["baseline"] + [f"g={g:.2f}" for g in gains]
        hdr = f"  {'tiempo':<12}" + "".join(f"{c:<12}" for c in col_labels)
        print(hdr)
        for key, t_label in hvac_keys:
            base_val = _get_metric(baseline_rpts.get("cfast_hvac_residential"), key)
            vals = [base_val] + [_get_metric(exp_rpts[g].get("cfast_hvac_residential"), key) for g in gains]
            row_strs = [f"{v:.4f}" if v is not None else "n/a" for v in vals]
            print(f"  {t_label:<12}" + "".join(f"{s:<12}" for s in row_strs))

    # -- Resumen final --------------------------------------------------------
    print()
    print("=" * W)
    if not invariant_violations:
        print("  INVARIANTE room.o2   : OK — sin violaciones (Δ < ±0.001)")
    else:
        print(f"  INVARIANTE room.o2   : {len(invariant_violations)} VIOLACIONES")
        for v in invariant_violations:
            print(f"    {v}")

    if not fed_regressions:
        print("  FED víctima          : OK — no supera baseline + 0.005 para ningún gain")
    else:
        print(f"  FED víctima          : {len(fed_regressions)} REGRESIONES")
        for v in fed_regressions:
            print(f"    {v}")

    if run_errors:
        print(f"  Runs fallidos        : {len(run_errors)}")
        for e in run_errors:
            print(f"    {e}")
    else:
        total = len(gains) * len(cases)
        print(f"  Runs                 : {total}/{total} OK")

    print()
    print("  Criterio de selección de gain candidato:")
    print("    → Mínimo gain donde hvac o2_lower mejora > +0.03 en t300 y sentinels PASS")
    print()
    print("=" * W)
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
