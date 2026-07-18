"""
phase2i_experiment_1_runner.py — Runner experimental Phase 2I, experimento 1.

Barrido de `phase2i_co2_upper_fraction` (0.0, 0.25, 0.50, 0.75, 1.0) sobre 3 casos
sentinel + 3 casos de observación CO₂ para verificar:
  1. Si alguna fracción cierra ≥2 gaps CO₂ upper (5 non-gating) sin romper sentinels.
  2. Si los sentinels FED/CO permanecen dentro de sus ventanas en todas las fracciones.
  3. Diagnosticar si el mecanismo co2_upper_kg es suficiente para cerrar los gaps, o si
     se requiere Phase 2E plena (modificar room.co2_upper directamente en OxygenExchangeSystem).

Mecanismo (Phase 2I):
  En ThermalSystem.gd / sync_room_upper_layer():
    Cuando phase2i_co2_upper_fraction > 0.0 y la sala tiene fuego activo:
      room.co2_upper_kg = max(room.co2_upper_kg, room.co2_kg × fraction)
    co2_kg total permanece invariante (sin creación/destrucción).
  NOTA ARQUITECTÓNICA: room.co2_upper (fracción molar, CO2u= en log, FED V_CO2 en upper)
  es gestionado por OxygenExchangeSystem y NO se modifica por este flag.
  Los gaps CO₂ upper (cfast_t510_co2_upper_ppm, etc.) miden room.co2_upper, por lo que
  Phase 2I actuando solo sobre co2_upper_kg NO puede cerrarlos directamente.

Casos evaluados:
  Sentinels (3):
    g4_gie_delayed_entry_hazard      CO>1200 timing, FED timing
    v3_hallway_fed_exposure          FED timing, max FED
    victim_fed_incapacitation        final FED

  Observación CO₂ (3 + opcional):
    cfast_r0_window_360              → cfast_t510_co2_upper_ppm (GAP: 16182 vs 52300 ppm)
    cfast_two_room_door_open         → cfast_2r_r0_t120/t480_co2_upper_pct (GAP)
    cfast_post_flashover_vented      → cfast_fo_t240/t350_co2_upper_pct (GAP)

Sentinels obligatorios (ventanas Phase 2H-validadas):
  g4 CO>1200 [s]   : [82.333, 92.333]
  g4 FED>0.1 [s]   : [187.75, 207.75]
  v3 FED>0.1 [s]   : [222.17, 282.17]
  v3 max FED       : >= 1.0
  vic final FED    : >= 0.7

Fracciones evaluadas:
  0.00 (baseline = flag OFF, sin efecto)
  0.25, 0.50, 0.75, 1.00

Nomenclatura de temporales:
  {case}_p2i_f{frac_str}  p.ej. cfast_r0_window_360_p2i_f25 (fraction=0.25)
  fraction 0.0 → usa directamente el baseline (no se genera temporal)

Uso:
    python scripts/simulation/phase2i_experiment_1_runner.py
    python scripts/simulation/phase2i_experiment_1_runner.py --skip-run
    python scripts/simulation/phase2i_experiment_1_runner.py --fractions 0.25 0.50 1.0
    python scripts/simulation/phase2i_experiment_1_runner.py --skip-co2-cases

Código de salida:
    0 — experimento completado
    1 — error crítico (Godot no encontrado)
"""

import argparse
import json
import math
import re
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

DEFAULT_FRACTIONS = [0.25, 0.50, 0.75, 1.00]

# Casos sentinel — se leen del report JSON.
SENTINEL_CASES = [
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
]

# Casos CO₂ — además del report JSON, se parsea el .log para CO₂ upper ppm en tiempos objetivo.
CO2_CASES = [
    "cfast_r0_window_360",
    "cfast_two_room_door_open",
    "cfast_post_flashover_vented",
]

ALL_CASES = SENTINEL_CASES + CO2_CASES

# Sentinels: (case, key, lo, hi, label)
SENTINELS: list[tuple[str, str, "float | None", "float | None", str]] = [
    ("g4_gie_delayed_entry_hazard", "time_room_1_co_upper_above_1200_s", 82.333,  92.333,  "g4 CO>1200"),
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",       187.75,  207.75,  "g4 FED"),
    ("v3_hallway_fed_exposure",     "time_room_1_fed_above_0_1_s",       222.17,  282.17,  "v3 FED"),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                    1.0,     None,    "v3 maxFED"),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",               0.7,     None,    "vic FED"),
]

# CO₂ gap targets: (case, room_id, target_s, check_name, expected, tolerance, unit)
# unit: "ppm" → compare directly; "pct" → value from log is mol%, multiply by 10000 for ppm
CO2_GAP_TARGETS: list[tuple[str, int, float, str, float, float, str]] = [
    ("cfast_r0_window_360",       0, 510.0, "cfast_t510_co2_upper_ppm",    52300.0, 20000.0, "ppm"),
    ("cfast_r0_window_360",       0, 420.0, "cfast_t420_co2_upper_ppm",    60800.0, 22000.0, "ppm"),
    ("cfast_two_room_door_open",  0, 120.0, "cfast_2r_r0_t120_co2_upper_pct", 1.58, 3.0,    "pct"),
    ("cfast_two_room_door_open",  0, 480.0, "cfast_2r_r0_t480_co2_upper_pct", 9.91, 3.0,    "pct"),
    ("cfast_post_flashover_vented", 0, 240.0, "cfast_fo_t240_co2_upper_pct",  7.77, 3.0,    "pct"),
    ("cfast_post_flashover_vented", 0, 350.0, "cfast_fo_t350_co2_upper_pct",  7.89, 3.0,    "pct"),
]

# Baseline (fraction=0.0): actual values from reference_checks.json snapshot OFF
CO2_BASELINE: dict[str, float] = {
    "cfast_t510_co2_upper_ppm":       16182.0,  # GAP: 16182 vs 52300 ± 20000
    "cfast_t420_co2_upper_ppm":       41438.0,  # PASS: 41438 vs 60800 ± 22000
    "cfast_2r_r0_t120_co2_upper_pct":  4.75,   # GAP: 4.75% vs 1.58% ± 3%
    "cfast_2r_r0_t480_co2_upper_pct":  0.999,  # GAP: 0.999% vs 9.91% ± 3%
    "cfast_fo_t240_co2_upper_pct":     4.32,   # GAP: 4.32% vs 7.77% ± 3%
    "cfast_fo_t350_co2_upper_pct":     0.77,   # GAP: 0.77% vs 7.89% ± 3%
}


def _fraction_str(f: float) -> str:
    """Convert fraction to compact string: 0.25 → 'f25', 1.00 → 'f100'."""
    return f"f{int(round(f * 100))}"


# ---------------------------------------------------------------------------
# Log parsing
# ---------------------------------------------------------------------------

def _parse_simufire_log(path: Path, room_id: int) -> list[dict]:
    """Parse SimuFire validation log, return list of per-timestep dicts."""
    if not path.exists():
        return []
    time_s: "float | None" = None
    samples: list[dict] = []
    time_re = re.compile(r"^TIME=([0-9.]+) s")
    room_re = re.compile(rf"^ROOM {room_id}\([^)]*\) \| (.*)$")

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m_time = time_re.match(line)
        if m_time:
            time_s = float(m_time.group(1))
            continue
        m_room = room_re.match(line)
        if not m_room or time_s is None:
            continue

        sample: dict = {"time_s": time_s}
        for segment in m_room.group(1).split(" | "):
            if "=" not in segment:
                continue
            key, value = segment.split("=", 1)
            value = (value.split()[0]
                     .replace("ppm", "").replace("Pa", "")
                     .replace("%", "").replace("m", ""))
            try:
                sample[key] = float(value)
            except ValueError:
                continue

        _co2u_raw = sample.get("CO2u", math.nan)
        co2_upper_pct = _co2u_raw / 10000.0 if not math.isnan(_co2u_raw) else math.nan
        samples.append({
            "time_s": sample["time_s"],
            "co2_upper_ppm": sample.get("CO2u", math.nan),
            "co2_upper_pct": co2_upper_pct,
        })
    return samples


def _nearest(samples: list[dict], target_s: float) -> "dict | None":
    if not samples:
        return None
    return min(samples, key=lambda s: abs(s["time_s"] - target_s))


# ---------------------------------------------------------------------------
# Helpers — report JSON
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
            for sub in ("value", "time_s"):
                if sub in val:
                    return float(val[sub])
    thr = report.get("threshold_metrics", {})
    if isinstance(thr, dict) and key in thr:
        v = thr[key]
        if isinstance(v, (int, float)):
            return float(v)
    return None


def _sentinel_pass(val: "float | None", lo: "float | None", hi: "float | None") -> "bool | None":
    if val is None:
        return None
    if lo is not None and val < lo:
        return False
    if hi is not None and val > hi:
        return False
    return True


# ---------------------------------------------------------------------------
# Experiment case builder
# ---------------------------------------------------------------------------

def _build_exp_case(base_path: Path, exp_path: Path, exp_name: str, fraction: float) -> None:
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides["phase2i_co2_upper_fraction"] = fraction
    # Redirect log to experiment-specific path so we can parse CO₂ per fraction.
    overrides["log_file_path"] = f"res://sim/validation/reports/{exp_name}.log"
    case_data["engine_overrides"] = overrides
    exp_path.write_text(
        json.dumps(case_data, indent="\t", ensure_ascii=False),
        encoding="utf-8"
    )


def _run_case(godot: Path, case_name: str, timeout_s: int = 300) -> bool:
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--",
           f"--validation-case={case_name}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, Exception):
        return False


# ---------------------------------------------------------------------------
# CO₂ gap check helper
# ---------------------------------------------------------------------------

def _co2_gap_passes(check_name: str, actual: "float | None",
                    expected: float, tolerance: float) -> "bool | None":
    """Returns True if |actual - expected| <= tolerance, False if fails, None if no data."""
    if actual is None or math.isnan(actual):
        return None
    return abs(actual - expected) <= tolerance


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2I Experiment 1 — CO₂ upper fraction sweep."
    )
    parser.add_argument("--godot",       default=None, metavar="PATH")
    parser.add_argument("--skip-run",    action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--skip-co2-cases", action="store_true",
                        help="Solo correr casos sentinel, omitir CO₂ obs cases")
    parser.add_argument("--fractions",   nargs="+", type=float,
                        default=DEFAULT_FRACTIONS,
                        metavar="F",
                        help="Fracciones a evaluar (default: 0.25 0.50 0.75 1.00)")
    parser.add_argument("--timeout",     type=int, default=300)
    args = parser.parse_args()

    fractions = sorted(set(args.fractions))
    active_cases = SENTINEL_CASES + ([] if args.skip_co2_cases else CO2_CASES)

    W = 110
    print()
    print("=" * W)
    print("  Phase 2I Experiment 1 — CO₂ upper fraction sweep (sync_room_upper_layer)")
    print(f"  Fracciones : {fractions}")
    print(f"  Casos      : {' | '.join(active_cases)}")
    print(f"  Mecanismo  : phase2i_co2_upper_fraction → floor en co2_upper_kg sala fuego")
    print(f"  NOTA       : CO₂ ppm log usa room.co2_upper (molar frac) — independiente de co2_upper_kg")
    print("=" * W)

    # -- Resolver Godot -------------------------------------------------------
    godot = None
    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("\n  ERROR: no se encontró Godot. Define --godot PATH o GODOT_EXE.\n")
            return 1
        print(f"\n  Godot: {godot}")

    # -- Ejecutar casos por fracción ------------------------------------------
    created_temp: list[Path] = []
    run_errors: list[str] = []

    if not args.skip_run:
        print()
        total_runs = len(fractions) * len(active_cases)
        done = 0
        for frac in fractions:
            fstr = _fraction_str(frac)
            for case in active_cases:
                exp_name  = f"{case}_p2i_{fstr}"
                base_path = CASES_DIR / f"{case}.json"
                exp_path  = CASES_DIR / f"{exp_name}.json"

                if not base_path.exists():
                    print(f"  SKIP: caso base no encontrado: {base_path.name}")
                    run_errors.append(exp_name)
                    done += 1
                    continue

                _build_exp_case(base_path, exp_path, exp_name, frac)
                created_temp.append(exp_path)

                done += 1
                print(f"  [{done:>2}/{total_runs}] Phase2I f={frac:.2f}  {case} ...",
                      end=" ", flush=True)
                ok = _run_case(godot, exp_name, timeout_s=args.timeout)
                print("OK" if ok else "FAIL")
                if not ok:
                    run_errors.append(exp_name)

    # -- Limpiar temporales ---------------------------------------------------
    for p in created_temp:
        try:
            p.unlink()
        except Exception:
            pass
    created_temp.clear()

    # -- Cargar baseline reports + logs ---------------------------------------
    baseline_rpts: dict[str, "dict | None"] = {c: _load_report(REPORTS_DIR / f"{c}.json")
                                                for c in active_cases}
    baseline_logs: dict[str, list[dict]] = {}
    if not args.skip_co2_cases:
        for case in CO2_CASES:
            baseline_logs[case] = _parse_simufire_log(REPORTS_DIR / f"{case}.log", room_id=0)

    # -- Cargar experiment reports + logs por fracción -----------------------
    exp_rpts: dict[tuple[str, float], "dict | None"] = {}
    exp_logs: dict[tuple[str, float], list[dict]] = {}
    for frac in fractions:
        fstr = _fraction_str(frac)
        for case in active_cases:
            exp_name = f"{case}_p2i_{fstr}"
            exp_rpts[(case, frac)] = _load_report(REPORTS_DIR / f"{exp_name}.json")
        if not args.skip_co2_cases:
            for case in CO2_CASES:
                exp_name = f"{case}_p2i_{fstr}"
                exp_logs[(case, frac)] = _parse_simufire_log(
                    REPORTS_DIR / f"{exp_name}.log", room_id=0)

    # =========================================================================
    # TABLA 1: Sentinels por fracción
    # =========================================================================
    print()
    print("-" * W)
    print("  TABLA 1 — Sentinels requeridos por fracción (ON vs baseline)")
    sl_labels = [lbl for (_, _, _, _, lbl) in SENTINELS]
    w_col = 16
    hdr = f"  {'Fracción':<14}" + "".join(f"{lbl:<{w_col}}" for lbl in sl_labels) + "  Total"
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))

    def _sentinel_row(tag: str, rpts: dict) -> None:
        row_parts: list[str] = []
        passes = 0
        for (sc, sk, lo, hi, _lbl) in SENTINELS:
            r = rpts.get(sc)
            ev = _get_metric(r, sk)
            ok = _sentinel_pass(ev, lo, hi)
            if ok is True:
                passes += 1
            flag_tag = "OK" if ok is True else ("!!" if ok is False else "??")
            val_s = f"{ev:.3f}" if ev is not None else "n/a"
            row_parts.append(f"{val_s} {flag_tag}")
        print(f"  {'BASELINE':<14}" if tag == "BASELINE" else f"  {f'f={tag}':<14}",
              end="")
        print("".join(f"{p:<{w_col}}" for p in row_parts)
              + f"  {passes}/{len(SENTINELS)}")

    _sentinel_row("BASELINE", baseline_rpts)
    for frac in fractions:
        frac_rpts = {c: exp_rpts.get((c, frac)) for c in active_cases}
        _sentinel_row(f"{frac:.2f}", frac_rpts)

    # =========================================================================
    # TABLA 2: Sentinel detalle — delta por fracción
    # =========================================================================
    print()
    print("-" * W)
    print("  TABLA 2 — Sentinel deltas por fracción (Δ vs baseline)")
    print(f"  {'Métrica':<38} {'Baseline':>10}", end="")
    for frac in fractions:
        print(f"  {f'f={frac:.2f}':>13}", end="")
    print(f"  {'Ventana'}")

    for (sc, sk, lo, hi, lbl) in SENTINELS:
        base_val = _get_metric(baseline_rpts.get(sc), sk)
        lo_s = f"{lo:.2f}" if lo is not None else "-inf"
        hi_s = f"{hi:.2f}" if hi is not None else "+inf"
        print(f"  {lbl:<38} {(f'{base_val:.3f}' if base_val is not None else 'n/a'):>10}",
              end="")
        for frac in fractions:
            r = exp_rpts.get((sc, frac))
            ev = _get_metric(r, sk)
            if ev is None or base_val is None:
                print(f"  {'n/a':>13}", end="")
            else:
                d = ev - base_val
                ok = _sentinel_pass(ev, lo, hi)
                flag = "OK" if ok is True else "!!"
                print(f"  {f'{d:+.3f} {flag}':>13}", end="")
        print(f"  [{lo_s}, {hi_s}]")

    # =========================================================================
    # TABLA 3: CO₂ upper ppm por fracción (desde log)
    # =========================================================================
    if not args.skip_co2_cases:
        print()
        print("-" * W)
        print("  TABLA 3 — CO₂ upper por fracción (desde log, CO2u= field)")
        print(f"  NOTA: CO2u= usa room.co2_upper (fracción molar, OxygenExchangeSystem).")
        print(f"        Phase 2I actúa sobre co2_upper_kg (ThermalSystem). Δ esperado ≈ 0.")
        print()
        print(f"  {'Check':<38} {'Baseline':>10} {'CFAST ref':>10} {'Tol':>8}", end="")
        for frac in fractions:
            print(f"  {f'f={frac:.2f}':>13}", end="")
        print(f"  {'Pass baseline'}")

        for (case, room_id, target_s, check_name, expected, tolerance, unit) in CO2_GAP_TARGETS:
            if case not in active_cases:
                continue

            # Baseline value
            base_logs = baseline_logs.get(case, [])
            b_sample = _nearest(base_logs, target_s)
            if unit == "pct":
                base_raw = b_sample["co2_upper_pct"] if b_sample else math.nan
                exp_label = f"{expected:.2f}%"
                tol_label = f"±{tolerance:.1f}%"
                base_label = f"{base_raw:.3f}%" if not math.isnan(base_raw) else "n/a"
                base_passes = _co2_gap_passes(check_name, base_raw, expected, tolerance)
            else:
                base_raw = b_sample["co2_upper_ppm"] if b_sample else math.nan
                exp_label = f"{expected:.0f}"
                tol_label = f"±{tolerance:.0f}"
                base_label = f"{base_raw:.0f}" if not math.isnan(base_raw) else "n/a"
                base_passes = _co2_gap_passes(check_name, base_raw, expected, tolerance)

            pass_flag = "PASS" if base_passes else ("FAIL" if base_passes is False else "n/a")

            print(f"  {check_name:<38} {base_label:>10} {exp_label:>10} {tol_label:>8}", end="")

            for frac in fractions:
                logs = exp_logs.get((case, frac), [])
                sample = _nearest(logs, target_s)
                if unit == "pct":
                    raw = sample["co2_upper_pct"] if sample else math.nan
                    val_s = f"{raw:.3f}%" if not math.isnan(raw) else "n/a"
                    if not math.isnan(raw) and not math.isnan(base_raw):
                        delta = raw - base_raw
                        val_s = f"{raw:.3f}% ({delta:+.4f})"
                else:
                    raw = sample["co2_upper_ppm"] if sample else math.nan
                    val_s = f"{raw:.0f}" if not math.isnan(raw) else "n/a"
                    if not math.isnan(raw) and not math.isnan(base_raw):
                        delta = raw - base_raw
                        val_s = f"{raw:.0f} ({delta:+.0f})"
                print(f"  {val_s:>13}", end="")

            print(f"  {pass_flag}")

        # Resumen: cuántos CO₂ gaps cierra cada fracción
        print()
        print(f"  {'Fracción':<14} {'CO₂ gaps cerrados / 6':>22} {'CO₂ gaps que antes fallaban':>30}")
        for frac in fractions:
            closed = 0
            prev_fails = 0
            for (case, room_id, target_s, check_name, expected, tolerance, unit) in CO2_GAP_TARGETS:
                if case not in active_cases:
                    continue
                base_logs = baseline_logs.get(case, [])
                b_sample = _nearest(base_logs, target_s)
                if unit == "pct":
                    base_raw = b_sample["co2_upper_pct"] if b_sample else math.nan
                else:
                    base_raw = b_sample["co2_upper_ppm"] if b_sample else math.nan
                base_passed = _co2_gap_passes(check_name, base_raw, expected, tolerance)
                if not base_passed:
                    prev_fails += 1

                logs = exp_logs.get((case, frac), [])
                sample = _nearest(logs, target_s)
                if unit == "pct":
                    raw = sample["co2_upper_pct"] if sample else math.nan
                else:
                    raw = sample["co2_upper_ppm"] if sample else math.nan
                passes = _co2_gap_passes(check_name, raw, expected, tolerance)
                if passes and not base_passed:
                    closed += 1
            print(f"  {f'f={frac:.2f}':<14} {f'{closed}/{prev_fails} (de {prev_fails} fallidos)':>22}  [baseline falló {prev_fails}]")

    # =========================================================================
    # INTERPRETACIÓN
    # =========================================================================
    print()
    print("=" * W)
    print("  INTERPRETACIÓN Phase 2I Experiment 1")
    print("=" * W)

    # Check if any fraction closed CO₂ gaps
    co2_gaps_closed_any = False
    if not args.skip_co2_cases:
        for frac in fractions:
            for (case, room_id, target_s, check_name, expected, tolerance, unit) in CO2_GAP_TARGETS:
                if case not in active_cases:
                    continue
                base_logs = baseline_logs.get(case, [])
                b_sample = _nearest(base_logs, target_s)
                base_raw = (b_sample["co2_upper_pct"] if unit == "pct"
                            else b_sample["co2_upper_ppm"]) if b_sample else math.nan
                base_passed = _co2_gap_passes(check_name, base_raw, expected, tolerance)
                logs = exp_logs.get((case, frac), [])
                sample = _nearest(logs, target_s)
                raw = (sample["co2_upper_pct"] if unit == "pct"
                       else sample["co2_upper_ppm"]) if sample else math.nan
                if _co2_gap_passes(check_name, raw, expected, tolerance) and not base_passed:
                    co2_gaps_closed_any = True

    # Check if any fraction broke sentinels
    sentinel_broken_any = False
    for frac in fractions:
        for (sc, sk, lo, hi, _lbl) in SENTINELS:
            ev = _get_metric(exp_rpts.get((sc, frac)), sk)
            if ev is not None and not _sentinel_pass(ev, lo, hi):
                sentinel_broken_any = True

    if not co2_gaps_closed_any and not sentinel_broken_any:
        print()
        print("  RESULTADO: Phase 2I (co2_upper_kg floor) no cierra ningún gap CO₂ upper.")
        print()
        print("  DIAGNÓSTICO:")
        print("    • Los gaps CO₂ upper (cfast_t510_co2_upper_ppm, cfast_2r_*, cfast_fo_*)")
        print("      usan room.co2_upper (fracción molar, log CO2u=, OxygenExchangeSystem).")
        print("    • Phase 2I actúa sobre co2_upper_kg (ThermalSystem), variable separada.")
        print("    • Incrementar co2_upper_kg no modifica room.co2_upper → Δ CO₂ ppm ≈ 0.")
        print("    • Sentinels preservados → el mecanismo es safe pero insuficiente.")
        print()
        print("  DECISIÓN RECOMENDADA:")
        print("    → DESCARTAR Phase 2I como parametrización de co2_upper_kg.")
        print("    → Los gaps CO₂ upper requieren Phase 2E plena:")
        print("       Modificar room.co2_upper directamente en OxygenExchangeSystem")
        print("       (aumentar co2_yield o reducir dilución inter-room en ventilated phase).")
        print("    → Ver PHASE_2E_DESIGN.md §12.14 para estrategia recomendada.")
    elif co2_gaps_closed_any and not sentinel_broken_any:
        best_frac = None
        best_closed = 0
        for frac in fractions:
            closed = 0
            for (case, room_id, target_s, check_name, expected, tolerance, unit) in CO2_GAP_TARGETS:
                if case not in active_cases:
                    continue
                logs = exp_logs.get((case, frac), [])
                sample = _nearest(logs, target_s)
                base_logs = baseline_logs.get(case, [])
                b_sample = _nearest(base_logs, target_s)
                base_raw = (b_sample["co2_upper_pct"] if unit == "pct"
                            else b_sample["co2_upper_ppm"]) if b_sample else math.nan
                raw = (sample["co2_upper_pct"] if unit == "pct"
                       else sample["co2_upper_ppm"]) if sample else math.nan
                if (_co2_gap_passes(check_name, raw, expected, tolerance)
                        and not _co2_gap_passes(check_name, base_raw, expected, tolerance)):
                    closed += 1
            if closed > best_closed:
                best_closed = closed
                best_frac = frac
        print()
        print(f"  RESULTADO: CANDIDATO encontrado — fracción {best_frac:.2f} cierra {best_closed} gap(s).")
        print("  Sentinels: todos PASS en todas las fracciones.")
        print(f"  → Promover phase2i_co2_upper_fraction={best_frac:.2f} como preset opt-in.")
    elif sentinel_broken_any:
        print()
        print("  RESULTADO: Phase 2I rompe al menos un sentinel en alguna fracción.")
        print("  → CO₂ upper elevado afecta FED via V_CO2 o timing CO>1200.")
        print("  → Requiere Phase 2E plena con rebaseline explícito.")

    # -- Errores de ejecución
    print()
    print("-" * W)
    if not run_errors:
        print(f"  {len(fractions) * len(active_cases)}/{len(fractions) * len(active_cases)} runs OK")
    else:
        print(f"  ADVERTENCIA: {len(run_errors)} runs con error:")
        for e in run_errors:
            print(f"    {e}")
    print("=" * W)
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
