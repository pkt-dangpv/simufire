"""
phase2h_experiment_1_runner.py — Runner experimental Phase 2H, experimento 1.

Activa phase2h_o2_doorway_two_zone_enabled=true y compara cada caso contra la
baseline (flag OFF) para verificar que:
  1. Los 5 sentinels de FED/CO pasan con el flag ON.
  2. room.o2 (variable de retrocompatibilidad) no cambia — invariante del diseño.
  3. No se introduce regresión en CO upper / FED / HRR.

Mecanismo (Phase 2H):
  En OxygenExchangeSystem.gd, cuando phase2h_o2_doorway_two_zone_enabled=true:
    - El piso de o2_lower cambia de room.o2 → room.o2_upper.
    - Permite que o2_lower se mantenga por encima del bulk cuando hay
      flujo fresco por la mitad baja de las aperturas (Kawagoe/Bernoulli).
    - room.o2, room.o2_upper, CO, HRR y FED permanecen inalterados.
  Objetivo: cerrar los 10 gaps de o2_lower (CFAST ≈ 0.205, SF ≈ 0.05–0.20).

Flags activados en este experimento:
  phase2h_o2_doorway_two_zone_enabled        = true
  phase2h_cold_room_lower_routing_enabled    = false  (Exp 2H.2)

Casos evaluados (5):
  g4_gie_delayed_entry_hazard      sentinel: CO>1200 timing, FED timing
  v3_hallway_fed_exposure          sentinel: FED timing, max FED
  victim_fed_incapacitation        sentinel: final FED, peak CO
  cfast_single_room_closed         observacional: o2 bulk, CO upper (sala sellada)
  cfast_two_room_door_open         observacional: o2 bulk r0/r1, CO upper r1

Invariante verificado:
  room_0_final_o2 (y room_1_final_o2 donde aplique) debe ser idéntico
  en ON vs OFF dentro de la tolerancia numérica (±0.001).

Sentinels obligatorios (ventanas ya establecidas por Phase 2G):
  g4 CO>1200 [s]   : [82.333, 92.333]
  g4 FED>0.1 [s]   : [187.75, 207.75]
  v3 FED>0.1 [s]   : [222.17, 282.17]
  v3 max FED       : >= 1.0
  vic final FED    : >= 0.7
  vic peak CO      : >= 1500.0 ppm

Nomenclatura de reports experimentales:
  {case}_p2h1_on.json   (flag ON)
  {case}_p2h1_off.json  (flag OFF — redundante con baseline pero explícito)

Uso:
    python scripts/simulation/phase2h_experiment_1_runner.py
    python scripts/simulation/phase2h_experiment_1_runner.py --skip-run
    python scripts/simulation/phase2h_experiment_1_runner.py --only-on

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
    "F:/OneDrive/Escritorio/Godot_v4.6.3-stable_win64_console.exe",
    "C:/Users/dangp/Desktop/Godot_v4.6.3-stable_win64_console.exe",
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

CASES = [
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
    "cfast_single_room_closed",
    "cfast_two_room_door_open",
]

# Métricas por caso: (key_en_report, label_corto, es_sentinel, es_invariante)
METRICS_PER_CASE: dict[str, list[tuple[str, str, bool, bool]]] = {
    "g4_gie_delayed_entry_hazard": [
        ("time_room_1_co_upper_above_1200_s", "g4 CO>1200 [s]   ", True,  False),
        ("time_room_1_fed_above_0_1_s",       "g4 FED>0.1 [s]   ", True,  False),
        ("room_1_peak_co_upper_ppm",           "g4 peak CO upper ", True,  False),
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
        ("room_0_peak_co2_ppm",                "sc peak CO2 upper", False, False),
    ],
    "cfast_two_room_door_open": [
        ("room_0_final_o2",                    "2r r0 final o2   ", False, True),
        ("room_1_final_o2",                    "2r r1 final o2   ", False, True),
        ("room_1_final_co_upper_ppm",          "2r CO upper r1   ", False, False),
        ("room_1_final_co_ppm",                "2r CO mixed r1   ", False, False),
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

# Tolerancia para el chequeo de invariante room.o2
O2_INVARIANT_TOL = 0.001


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


def _delta_str(base: "float | None", exp: "float | None", width: int = 20) -> str:
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


def _build_exp_case(base_path: Path, exp_path: Path, flag_on: bool) -> None:
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides["phase2h_o2_doorway_two_zone_enabled"]     = flag_on
    overrides["phase2h_cold_room_lower_routing_enabled"] = False  # Exp 2H.2
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
        description="Phase 2H experiment 1 — O₂ doorway two-zone flow ON/OFF comparison."
    )
    parser.add_argument("--godot",     default=None, metavar="PATH")
    parser.add_argument("--skip-run",  action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--only-on",   action="store_true",
                        help="Solo ejecutar variante ON (no reejecutar OFF)")
    parser.add_argument("--timeout",   type=int, default=300)
    args = parser.parse_args()

    W = 100
    print()
    print("=" * W)
    print("  Phase 2H Experiment 1 — O₂ Doorway Two-Zone Flow  (ON vs OFF)")
    print("  Flags ON  : phase2h_o2_doorway_two_zone_enabled=true, cold_room=false")
    print(f"  Casos     : {' | '.join(CASES)}")
    print("=" * W)

    # -- Resolver Godot -------------------------------------------------------
    godot = None
    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("\n  ERROR: no se encontró Godot. Define --godot PATH o GODOT_EXE.\n")
            return 1
        print(f"\n  Godot: {godot}")

    # -- Configuración de variantes -------------------------------------------
    variants: list[tuple[str, bool]] = []
    if not args.only_on:
        variants.append(("off", False))
    variants.append(("on", True))

    suffix_map = {"on": "_p2h1_on", "off": "_p2h1_off"}

    # -- Ejecutar casos -------------------------------------------------------
    created_temp: list[Path] = []
    run_errors: dict[str, list[str]] = {"on": [], "off": []}

    if not args.skip_run:
        print()
        total_runs = len(variants) * len(CASES)
        done = 0
        for (tag, flag_on) in variants:
            for case in CASES:
                suffix    = suffix_map[tag]
                exp_name  = case + suffix
                base_path = CASES_DIR / f"{case}.json"
                exp_path  = CASES_DIR / f"{exp_name}.json"

                if not base_path.exists():
                    print(f"  SKIP: caso base no encontrado: {base_path.name}")
                    run_errors[tag].append(case)
                    done += 1
                    continue

                _build_exp_case(base_path, exp_path, flag_on)
                created_temp.append(exp_path)

                done += 1
                flag_label = "ON " if flag_on else "OFF"
                print(f"  [{done:>2}/{total_runs}] Phase2H {flag_label}  {case} ...",
                      end=" ", flush=True)
                ok = _run_case(godot, exp_name, timeout_s=args.timeout)
                print("OK" if ok else "FAIL")
                if not ok:
                    run_errors[tag].append(case)

    # -- Limpiar temporales ---------------------------------------------------
    for p in created_temp:
        try:
            p.unlink()
        except Exception:
            pass
    created_temp.clear()

    # -- Cargar reports -------------------------------------------------------
    baseline_rpts: dict[str, "dict | None"] = {}
    on_rpts: dict[str, "dict | None"]  = {}
    off_rpts: dict[str, "dict | None"] = {}
    for case in CASES:
        baseline_rpts[case] = _load_report(REPORTS_DIR / f"{case}.json")
        on_rpts[case]  = _load_report(REPORTS_DIR / f"{case}_p2h1_on.json")
        off_rpts[case] = _load_report(REPORTS_DIR / f"{case}_p2h1_off.json")

    # -- Tabla comparativa por caso -------------------------------------------
    print()
    print("-" * W)
    print("  TABLA COMPARATIVA — ON vs baseline y OFF vs baseline")
    print("  [I] = métrica invariante (room.o2 — debe ser ≈0)")
    print("  [*] = sentinel")
    print("-" * W)

    invariant_violations: list[str] = []

    for case in CASES:
        base  = baseline_rpts[case]
        on_r  = on_rpts[case]
        off_r = off_rpts[case]
        metrics = METRICS_PER_CASE[case]
        print()
        print(f"  [{case}]")
        for key, label, is_sentinel, is_invariant in metrics:
            base_val = _get_metric(base, key)
            on_val   = _get_metric(on_r, key)
            off_val  = _get_metric(off_r, key)

            base_str = f"{base_val:>10.4f}" if base_val is not None else f"{'n/a':>10}"
            on_str   = f"{on_val:>10.4f}"   if on_val  is not None else f"{'n/a':>10}"
            off_str  = f"{off_val:>10.4f}"  if off_val is not None else f"{'n/a':>10}"

            tag = ""
            if is_sentinel:
                sp = _sentinel_pass(case, key, on_val)
                tag = " [SENT:OK]" if sp else " [SENT:!!]"
            elif is_invariant:
                tag = " [I]"
                if on_val is not None and base_val is not None:
                    if abs(on_val - base_val) > O2_INVARIANT_TOL:
                        tag = f" [I:VIOLATION Δ={on_val - base_val:+.5f}]"
                        invariant_violations.append(
                            f"{case} / {key}: base={base_val:.5f} on={on_val:.5f}"
                        )

            delta_on  = _delta_str(base_val, on_val,  20)
            delta_off = _delta_str(base_val, off_val, 20)
            print(f"    {label}  base={base_str}  on={on_str}  off={off_str}"
                  f"  Δ_on={delta_on}  Δ_off={delta_off}{tag}")

    # -- Tabla resumen sentinels (ON solamente) --------------------------------
    print()
    print("-" * W)
    print("  SENTINELS — Phase 2H ON")
    sl_labels = [lbl for (_, _, _, _, lbl) in SENTINELS]
    w_col = 16
    header = f"  {'Variante':<20}" + "".join(f"{lbl:<{w_col}}" for lbl in sl_labels) + "  Total"
    print(header)
    print("  " + "-" * (len(header) - 2))

    for (tag, rpts) in [("BASELINE", baseline_rpts), ("OFF", off_rpts), ("ON", on_rpts)]:
        row_parts: list[str] = []
        passes = 0
        total_s = len(SENTINELS)
        for (sc, sk, lo, hi, _lbl) in SENTINELS:
            ev = _get_metric(rpts.get(sc) if tag != "BASELINE" else baseline_rpts.get(sc), sk)
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
        print(f"  {tag:<20}" + "".join(f"{p:<{w_col}}" for p in row_parts)
              + f"  {passes}/{total_s}")

    # -- Chequeo invariante ---------------------------------------------------
    print()
    print("-" * W)
    if not invariant_violations:
        print("  INVARIANTE room.o2: OK — sin violaciones (Δ < ±0.001)")
    else:
        print(f"  INVARIANTE room.o2: {len(invariant_violations)} VIOLACIONES")
        for v in invariant_violations:
            print(f"    {v}")

    # -- Resumen de errores de ejecución --------------------------------------
    total_run_errors = sum(len(v) for v in run_errors.values())
    print()
    print("=" * W)
    if total_run_errors == 0:
        total = len(variants) * len(CASES)
        print(f"  {total}/{total} runs OK — {len(variants)} variantes × {len(CASES)} casos")
    else:
        print(f"  ADVERTENCIA: {total_run_errors} runs fallidos")
        for tag_k, errs in run_errors.items():
            if errs:
                print(f"    {tag_k}: {errs}")
    print()
    print("  NOTA: los checks de o2_lower (cfast_2r_r0_t*_o2_lower, etc.) requieren")
    print("  ejecutar la suite completa de validación con el flag ON activado.")
    print("  Ver docs/architecture/PHASE_2E_DESIGN.md §12 para el protocolo de verificación.")
    print("=" * W)
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
