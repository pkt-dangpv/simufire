"""
phase2e_co2_experiment_1a_runner.py — Runner experimental Phase 2E CO₂, Exp 1A (Sub-C solo).

Barrido de `phase2e_co2_fire_upper_boost_gain` (0.0, 0.25, 0.50, 0.75, 1.0) con
`phase2e_co2_subc_enabled = true` sobre 3 casos sentinel + 3 casos CO₂ target para verificar:
  1. Si Sub-C cierra ≥1 gap CO₂ upper sin romper sentinels.
  2. Cuánto aumenta room.co2_upper por sala con fuego activo.
  3. Si hay riesgo V_CO2 (co2_upper > 2%) en posiciones de víctimas.

Mecanismo (Phase 2E Sub-C):
  En OxygenExchangeSystem.gd / step():
    Cuando phase2e_co2_subc_enabled=true y gain>0 y room.hrr_kw>0:
      delta_co2_boost = delta_co2_baseline × gain
      room.co2_upper += delta_co2_boost   ← tracer calibrado, no masa
    Diagnóstico no bloqueante: push_warning si co2_upper_equiv_kg > co2_kg × 5.
    gain=0.0 → rama inactiva, no-op exacto (=baseline).

Casos evaluados:
  Sentinels (3):
    g4_gie_delayed_entry_hazard      CO>1200 timing, FED timing
    v3_hallway_fed_exposure          FED timing, max FED
    victim_fed_incapacitation        final FED

  CO₂ target (3):
    cfast_r0_window_360              → cfast_t510_co2_upper_ppm
    cfast_single_room_closed         → sala sellada, acumulación pura
    cfast_two_room_door_open         → cfast_2r_r0_t120/t480_co2_upper_pct

  (cfast_post_flashover_vented se ejecuta si --include-flashover)

Sentinels obligatorios (ventanas Phase 2H-validadas):
  g4 CO>1200 [s]   : [82.333, 92.333]
  g4 FED>0.1 [s]   : [187.75, 207.75]
  v3 FED>0.1 [s]   : [222.17, 282.17]
  v3 max FED       : >= 1.0
  vic final FED    : >= 0.7

Gates para candidato:
  1. Sentinels: 5/5 PASS.
  2. FED delta (ON - baseline) en sentinel cases: |ΔFED| < 0.005.
  3. ≥1 gap CO₂ cerrado.
  4. Sin push_warning masivo de ratio > 5 (monitoreado en consola Godot).

Ganancias evaluadas:
  0.00 (baseline = flag ON pero gain=0 → no-op)
  0.25, 0.50, 0.75, 1.00

Uso:
    python scripts/simulation/phase2e_co2_experiment_1a_runner.py
    python scripts/simulation/phase2e_co2_experiment_1a_runner.py --skip-run
    python scripts/simulation/phase2e_co2_experiment_1a_runner.py --gains 0.25 0.50 1.0
    python scripts/simulation/phase2e_co2_experiment_1a_runner.py --include-flashover

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

DEFAULT_GAINS: list[float] = [0.25, 0.50, 0.75, 1.00]

SENTINEL_CASES = [
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
]

CO2_CASES_DEFAULT = [
    "cfast_r0_window_360",
    "cfast_single_room_closed",
    "cfast_two_room_door_open",
]

CO2_CASES_FLASHOVER = [
    "cfast_post_flashover_vented",
]

# Sentinels: (case, key, lo, hi, label)
SENTINELS: list[tuple[str, str, "float | None", "float | None", str]] = [
    ("g4_gie_delayed_entry_hazard", "time_room_1_co_upper_above_1200_s", 82.333,  92.333,  "g4 CO>1200"),
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",       187.75,  207.75,  "g4 FED"),
    ("v3_hallway_fed_exposure",     "time_room_1_fed_above_0_1_s",       222.17,  282.17,  "v3 FED"),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                    1.0,     None,    "v3 maxFED"),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",               0.7,     None,    "vic FED"),
]

# FED metrics for sentinel delta check (gate: |delta| < 0.005)
FED_DELTA_METRICS: list[tuple[str, str, str]] = [
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",  "g4 FED timing"),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                "v3 max FED"),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",           "vic final FED"),
]

# CO₂ gap targets: (case, room_id, target_s, check_name, expected, tolerance, unit)
CO2_GAP_TARGETS: list[tuple[str, int, float, str, float, float, str]] = [
    ("cfast_r0_window_360",        0, 510.0, "cfast_t510_co2_upper_ppm",        52300.0, 20000.0, "ppm"),
    ("cfast_r0_window_360",        0, 420.0, "cfast_t420_co2_upper_ppm",        60800.0, 22000.0, "ppm"),
    ("cfast_single_room_closed",   0, 300.0, "cfast_src_t300_co2_upper_ppm",   None,    None,    "ppm"),  # observación, sin ref CFAST
    ("cfast_two_room_door_open",   0, 120.0, "cfast_2r_r0_t120_co2_upper_pct",   1.58,  3.0,    "pct"),
    ("cfast_two_room_door_open",   0, 480.0, "cfast_2r_r0_t480_co2_upper_pct",   9.91,  3.0,    "pct"),
    ("cfast_post_flashover_vented", 0, 240.0, "cfast_fo_t240_co2_upper_pct",    7.77,  3.0,    "pct"),
    ("cfast_post_flashover_vented", 0, 350.0, "cfast_fo_t350_co2_upper_pct",    7.89,  3.0,    "pct"),
]

# Baseline CO₂ values (from last validated run, flag OFF)
CO2_BASELINE: dict[str, float] = {
    "cfast_t510_co2_upper_ppm":        16182.0,   # GAP: SF 16182 vs CFAST 52300 ± 20000
    "cfast_t420_co2_upper_ppm":        41438.0,   # PASS baseline
    "cfast_2r_r0_t120_co2_upper_pct":   4.75,    # GAP: SF 4.75% vs CFAST 1.58% ± 3%
    "cfast_2r_r0_t480_co2_upper_pct":   0.999,   # GAP: SF 0.999% vs CFAST 9.91% ± 3%
    "cfast_fo_t240_co2_upper_pct":      4.32,    # GAP: SF 4.32% vs CFAST 7.77% ± 3%
    "cfast_fo_t350_co2_upper_pct":      0.77,    # GAP: SF 0.77% vs CFAST 7.89% ± 3%
}


def _gain_str(g: float) -> str:
    """Convert gain to compact string: 0.25 → 'g25', 1.00 → 'g100'."""
    return f"g{int(round(g * 100))}"


# ---------------------------------------------------------------------------
# Log parsing
# ---------------------------------------------------------------------------

def _parse_simufire_log(path: Path, room_id: int) -> list[dict]:
    """Parse SimuFire validation log, return list of per-timestep dicts for a room."""
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

        co2u_raw = sample.get("CO2u", math.nan)
        co2_upper_pct = co2u_raw / 10000.0 if not math.isnan(co2u_raw) else math.nan
        samples.append({
            "time_s": sample["time_s"],
            "co2_upper_ppm": co2u_raw,
            "co2_upper_pct": co2_upper_pct,
        })
    return samples


def _nearest(samples: list[dict], target_s: float) -> "dict | None":
    if not samples:
        return None
    return min(samples, key=lambda s: abs(s["time_s"] - target_s))


def _max_co2_upper_ppm(samples: list[dict]) -> float:
    if not samples:
        return math.nan
    vals = [s["co2_upper_ppm"] for s in samples if not math.isnan(s.get("co2_upper_ppm", math.nan))]
    return max(vals) if vals else math.nan


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


def _co2_gap_passes(actual: "float | None", expected: "float | None",
                    tolerance: "float | None") -> "bool | None":
    if actual is None or math.isnan(actual) or expected is None or tolerance is None:
        return None
    return abs(actual - expected) <= tolerance


# ---------------------------------------------------------------------------
# Experiment case builder
# ---------------------------------------------------------------------------

def _build_exp_case(base_path: Path, exp_path: Path, exp_name: str, gain: float) -> None:
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides["phase2e_co2_subc_enabled"] = True
    overrides["phase2e_co2_fire_upper_boost_gain"] = gain
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
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2E CO₂ Experiment 1A — Sub-C fire-room CO2 upper tracer boost sweep."
    )
    parser.add_argument("--godot",              default=None, metavar="PATH")
    parser.add_argument("--skip-run",           action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--gains",              nargs="+", type=float,
                        default=DEFAULT_GAINS, metavar="G",
                        help="Ganancias a evaluar (default: 0.25 0.50 0.75 1.00)")
    parser.add_argument("--include-flashover",  action="store_true",
                        help="Incluir cfast_post_flashover_vented en la evaluación")
    parser.add_argument("--timeout",            type=int, default=300)
    args = parser.parse_args()

    gains = sorted(set(args.gains))
    co2_cases = CO2_CASES_DEFAULT + (CO2_CASES_FLASHOVER if args.include_flashover else [])
    active_cases = SENTINEL_CASES + co2_cases

    W = 120
    print()
    print("=" * W)
    print("  Phase 2E CO₂ Experiment 1A — Sub-C: fire-room CO₂ upper tracer boost")
    print(f"  Ganancias  : {gains}")
    print(f"  Casos      : {' | '.join(active_cases)}")
    print(f"  Mecanismo  : phase2e_co2_subc_enabled=true + boost_gain sweep")
    print(f"  Invariante : room.co2_upper es tracer calibrado (fracción molar, no masa)")
    print(f"  Gate       : sentinels 5/5 PASS + |ΔFED| < 0.005 + ≥1 CO₂ gap cerrado")
    print("=" * W)

    # -- Resolver Godot -------------------------------------------------------
    godot = None
    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("\n  ERROR: no se encontró Godot. Define --godot PATH o GODOT_EXE.\n")
            return 1
        print(f"\n  Godot: {godot}")

    # -- Ejecutar casos por ganancia ------------------------------------------
    created_temp: list[Path] = []
    run_errors: list[str] = []

    if not args.skip_run:
        print()
        total_runs = len(gains) * len(active_cases)
        done = 0
        for gain in gains:
            gstr = _gain_str(gain)
            for case in active_cases:
                exp_name  = f"{case}_p2e1a_{gstr}"
                base_path = CASES_DIR / f"{case}.json"
                exp_path  = CASES_DIR / f"{exp_name}.json"

                if not base_path.exists():
                    print(f"  SKIP: caso base no encontrado: {base_path.name}")
                    run_errors.append(exp_name)
                    done += 1
                    continue

                _build_exp_case(base_path, exp_path, exp_name, gain)
                created_temp.append(exp_path)

                done += 1
                print(f"  [{done:>2}/{total_runs}] Phase2E-1A gain={gain:.2f}  {case} ...",
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
    baseline_logs: dict[str, list[dict]] = {
        case: _parse_simufire_log(REPORTS_DIR / f"{case}.log", room_id=0)
        for case in co2_cases
    }

    # -- Cargar experiment reports + logs por ganancia ------------------------
    exp_rpts: dict[tuple[str, float], "dict | None"] = {}
    exp_logs: dict[tuple[str, float], list[dict]] = {}
    for gain in gains:
        gstr = _gain_str(gain)
        for case in active_cases:
            exp_name = f"{case}_p2e1a_{gstr}"
            exp_rpts[(case, gain)] = _load_report(REPORTS_DIR / f"{exp_name}.json")
        for case in co2_cases:
            exp_name = f"{case}_p2e1a_{gstr}"
            exp_logs[(case, gain)] = _parse_simufire_log(
                REPORTS_DIR / f"{exp_name}.log", room_id=0)

    # =========================================================================
    # TABLA 1: Sentinels por ganancia
    # =========================================================================
    print()
    print("-" * W)
    print("  TABLA 1 — Sentinels requeridos por ganancia (ON vs baseline)")
    sl_labels = [lbl for (_, _, _, _, lbl) in SENTINELS]
    w_col = 17
    hdr = f"  {'Ganancia':<14}" + "".join(f"{lbl:<{w_col}}" for lbl in sl_labels) + "  Total"
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))

    def _print_sentinel_row(tag: str, rpts: dict) -> None:
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
        label = f"  {'BASELINE':<14}" if tag == "BASELINE" else f"  {f'g={tag}':<14}"
        print(label, end="")
        print("".join(f"{p:<{w_col}}" for p in row_parts) + f"  {passes}/{len(SENTINELS)}")

    _print_sentinel_row("BASELINE", baseline_rpts)
    for gain in gains:
        frac_rpts = {c: exp_rpts.get((c, gain)) for c in active_cases}
        _print_sentinel_row(f"{gain:.2f}", frac_rpts)

    # =========================================================================
    # TABLA 2: FED deltas en sentinel cases (gate |ΔFED| < 0.005)
    # =========================================================================
    print()
    print("-" * W)
    print("  TABLA 2 — FED deltas en sentinel cases (gate: |Δ| < 0.005 = no riesgo V_CO₂)")
    print(f"  {'Métrica':<38} {'Baseline':>10}", end="")
    for gain in gains:
        print(f"  {f'g={gain:.2f}':>15}", end="")
    print()
    print("  " + "-" * 90)

    max_fed_delta_by_gain: dict[float, float] = {g: 0.0 for g in gains}
    for (sc, sk, lbl) in FED_DELTA_METRICS:
        base_val = _get_metric(baseline_rpts.get(sc), sk)
        print(f"  {lbl:<38} {(f'{base_val:.4f}' if base_val is not None else 'n/a'):>10}",
              end="")
        for gain in gains:
            r = exp_rpts.get((sc, gain))
            ev = _get_metric(r, sk)
            if ev is None or base_val is None:
                print(f"  {'n/a':>15}", end="")
            else:
                d = abs(ev - base_val)
                gate_ok = d < 0.005
                flag = "OK" if gate_ok else "⚠ GATE"
                max_fed_delta_by_gain[gain] = max(max_fed_delta_by_gain[gain], d)
                print(f"  {f'{d:+.4f} {flag}':>15}", end="")
        print()

    print()
    print(f"  {'Max |ΔFED| por ganancia':<38}", end="")
    for gain in gains:
        d = max_fed_delta_by_gain[gain]
        gate_ok = d < 0.005
        flag = "OK" if gate_ok else "FAIL"
        print(f"  {f'{d:.4f} {flag}':>15}", end="")
    print()

    # =========================================================================
    # TABLA 3: CO₂ upper por ganancia (desde log)
    # =========================================================================
    print()
    print("-" * W)
    print("  TABLA 3 — CO₂ upper por ganancia (desde log, CO2u= field, room 0)")
    print()

    active_co2_targets = [t for t in CO2_GAP_TARGETS if t[0] in co2_cases]

    # Header
    print(f"  {'Check':<42} {'Baseline':>12} {'CFAST ref':>10} {'Tol':>8}", end="")
    for gain in gains:
        print(f"  {f'g={gain:.2f}':>18}", end="")
    print(f"  {'Base OK'}")

    for (case, room_id, target_s, check_name, expected, tolerance, unit) in active_co2_targets:
        if case not in co2_cases:
            continue
        base_logs = baseline_logs.get(case, [])
        b_sample = _nearest(base_logs, target_s)

        if unit == "pct":
            base_raw = b_sample["co2_upper_pct"] if b_sample else math.nan
            exp_label = f"{expected:.2f}%" if expected is not None else "n/a"
            tol_label = f"±{tolerance:.1f}%" if tolerance is not None else "n/a"
            base_label = f"{base_raw:.3f}%" if not math.isnan(base_raw) else "n/a"
        else:
            base_raw = b_sample["co2_upper_ppm"] if b_sample else math.nan
            exp_label = f"{expected:.0f}" if expected is not None else "obs"
            tol_label = f"±{tolerance:.0f}" if tolerance is not None else "obs"
            base_label = f"{base_raw:.0f}" if not math.isnan(base_raw) else "n/a"

        base_passes = _co2_gap_passes(base_raw, expected, tolerance)
        pass_flag = "PASS" if base_passes is True else ("FAIL" if base_passes is False else "obs")

        print(f"  {check_name:<42} {base_label:>12} {exp_label:>10} {tol_label:>8}", end="")
        for gain in gains:
            logs = exp_logs.get((case, gain), [])
            sample = _nearest(logs, target_s)
            if unit == "pct":
                raw = sample["co2_upper_pct"] if sample else math.nan
                if math.isnan(raw):
                    val_s = "n/a"
                elif not math.isnan(base_raw):
                    d = raw - base_raw
                    val_s = f"{raw:.3f}% ({d:+.4f})"
                else:
                    val_s = f"{raw:.3f}%"
            else:
                raw = sample["co2_upper_ppm"] if sample else math.nan
                if math.isnan(raw):
                    val_s = "n/a"
                elif not math.isnan(base_raw):
                    d = raw - base_raw
                    val_s = f"{raw:.0f} ({d:+.0f})"
                else:
                    val_s = f"{raw:.0f}"
            print(f"  {val_s:>18}", end="")
        print(f"  {pass_flag}")

    # =========================================================================
    # TABLA 4: Max CO₂ upper ppm en salas de fuego (proxy riesgo V_CO₂)
    # =========================================================================
    print()
    print("-" * W)
    print("  TABLA 4 — Max CO₂ upper ppm (sala 0, toda la simulación)")
    print(f"  Nota: V_CO₂=1.0 hasta 20000 ppm (2%). Riesgo alto >120000 ppm (12%).")
    print()
    print(f"  {'Caso':<38} {'Baseline':>12}", end="")
    for gain in gains:
        print(f"  {f'g={gain:.2f}':>12}", end="")
    print()

    for case in co2_cases:
        base_logs = baseline_logs.get(case, [])
        base_max = _max_co2_upper_ppm(base_logs)
        b_str = f"{base_max:.0f}" if not math.isnan(base_max) else "n/a"
        risk_b = "⚠" if not math.isnan(base_max) and base_max > 20000 else ""
        print(f"  {case:<38} {b_str + risk_b:>12}", end="")
        for gain in gains:
            logs = exp_logs.get((case, gain), [])
            mx = _max_co2_upper_ppm(logs)
            s = f"{mx:.0f}" if not math.isnan(mx) else "n/a"
            risk = "⚠" if not math.isnan(mx) and mx > 20000 else ""
            print(f"  {s + risk:>12}", end="")
        print()

    # =========================================================================
    # RESUMEN: gaps cerrados por ganancia
    # =========================================================================
    print()
    print("-" * W)
    print("  RESUMEN — CO₂ gaps cerrados por ganancia (de los 5 gaps requeridos)")
    print()
    print(f"  {'Ganancia':<14} {'Sentinels':>12} {'FED gate':>12} {'CO₂ gaps cerrados':>22}")

    best_candidate: "tuple[float, int] | None" = None
    for gain in gains:
        # sentinels
        sentinel_ok = 0
        for (sc, sk, lo, hi, _lbl) in SENTINELS:
            ev = _get_metric(exp_rpts.get((sc, gain)), sk)
            if _sentinel_pass(ev, lo, hi) is True:
                sentinel_ok += 1
        sentinels_pass = sentinel_ok == len(SENTINELS)

        # FED gate
        fed_ok = max_fed_delta_by_gain[gain] < 0.005

        # CO2 gaps: count of gaps closed that were previously failing
        closed = 0
        previously_failing = 0
        for (case, room_id, target_s, check_name, expected, tolerance, unit) in active_co2_targets:
            if expected is None or tolerance is None:
                continue  # observación, sin referencia CFAST
            base_logs = baseline_logs.get(case, [])
            b_sample = _nearest(base_logs, target_s)
            if unit == "pct":
                base_raw = b_sample["co2_upper_pct"] if b_sample else math.nan
            else:
                base_raw = b_sample["co2_upper_ppm"] if b_sample else math.nan
            base_passed = _co2_gap_passes(base_raw, expected, tolerance)
            if not base_passed:
                previously_failing += 1

            logs = exp_logs.get((case, gain), [])
            sample = _nearest(logs, target_s)
            if unit == "pct":
                raw = sample["co2_upper_pct"] if sample else math.nan
            else:
                raw = sample["co2_upper_ppm"] if sample else math.nan
            passes = _co2_gap_passes(raw, expected, tolerance)
            if passes and not base_passed:
                closed += 1

        gate_all = sentinels_pass and fed_ok and closed >= 1

        s_flag   = f"{sentinel_ok}/{len(SENTINELS)} {'OK' if sentinels_pass else 'FAIL'}"
        fed_flag = f"{'OK' if fed_ok else 'FAIL'} (max Δ={max_fed_delta_by_gain[gain]:.4f})"
        co2_flag = f"{closed}/{previously_failing} cerrados"
        candidate_flag = " ← CANDIDATO" if gate_all else ""

        print(f"  {f'g={gain:.2f}':<14} {s_flag:>12} {fed_flag:>12} {co2_flag:>22}{candidate_flag}")

        if gate_all and (best_candidate is None or closed > best_candidate[1]):
            best_candidate = (gain, closed)

    # =========================================================================
    # INTERPRETACIÓN FINAL
    # =========================================================================
    print()
    print("=" * W)
    print("  INTERPRETACIÓN Phase 2E CO₂ Exp 1A (Sub-C)")
    print("=" * W)

    if run_errors:
        print(f"\n  ⚠ Errores de ejecución en: {run_errors}")

    if best_candidate is not None:
        g, closed = best_candidate
        print()
        print(f"  CANDIDATO IDENTIFICADO: gain = {g:.2f}  ({closed} CO₂ gaps cerrados)")
        print()
        print("  Próximo paso: Exp 2E-CO₂-1B (Sub-A solo) o promoción de Sub-C si cierra ≥3 gaps.")
        print("  Sub-C no altera co2_upper_kg/co2_kg. No requiere cambio de baseline.")
        print("  Para promover: añadir ganancia al preset del scenario JSON.")
    else:
        all_sentinels_ok = True
        for gain in gains:
            for (sc, sk, lo, hi, _lbl) in SENTINELS:
                ev = _get_metric(exp_rpts.get((sc, gain)), sk)
                if ev is not None and not _sentinel_pass(ev, lo, hi):
                    all_sentinels_ok = False
                    break

        co2_closed_any = False
        for gain in gains:
            for (case, _room_id, target_s, _check, expected, tolerance, unit) in active_co2_targets:
                if expected is None or tolerance is None:
                    continue
                base_logs = baseline_logs.get(case, [])
                b_sample = _nearest(base_logs, target_s)
                base_raw = (b_sample["co2_upper_pct"] if unit == "pct"
                            else b_sample["co2_upper_ppm"]) if b_sample else math.nan
                base_passed = _co2_gap_passes(base_raw, expected, tolerance)
                logs = exp_logs.get((case, gain), [])
                sample = _nearest(logs, target_s)
                raw = (sample["co2_upper_pct"] if unit == "pct"
                       else sample["co2_upper_ppm"]) if sample else math.nan
                if _co2_gap_passes(raw, expected, tolerance) and not base_passed:
                    co2_closed_any = True

        if not co2_closed_any:
            print()
            print("  RESULTADO: Sub-C (tracer boost) no cierra ningún gap CO₂ upper con gains evaluadas.")
            print()
            print("  DIAGNÓSTICO:")
            print("    • Sub-C amplifica delta_co2 (producción por fuego) multiplicado por gain.")
            print("    • Si los gaps requieren más de 2× la tasa de producción para cerrarse,")
            print("      el problema raíz es la dilución (Sub-A) o el exchange inter-room (Sub-B),")
            print("      no la tasa de producción.")
            print()
            print("  DECISIÓN: SUB-C DESCARTADO como mecanismo principal si 0 gaps cerrados.")
            print("  → Continuar con Exp 2E-CO₂-1B (Sub-A: outflow proxy en apertura exterior).")
        elif not all_sentinels_ok:
            print()
            print("  RESULTADO: Sub-C cierra gaps CO₂ pero rompe sentinels → NO es candidato.")
            print("  → El boost causa V_CO₂ > 1.0 en salas de víctimas → FED amplificado.")
            print("  DECISIÓN: SUB-C DESCARTADO en todas las ganancias evaluadas.")
        else:
            print()
            print("  RESULTADO: Sub-C cierra gaps pero no pasa FED gate (|ΔFED| ≥ 0.005).")
            print("  → Investigar origen del delta FED antes de promover.")

    print()
    print("  Documentar resultados en PHASE_2E_CO2_DESIGN.md §10 (Exp 1A results).")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
