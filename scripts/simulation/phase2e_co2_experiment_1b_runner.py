"""
phase2e_co2_experiment_1b_runner.py — Runner experimental Phase 2E CO₂, Exp 1B (Sub-A solo).

Barrido de `phase2e_co2_upper_outflow_gain` ∈ {0.0, 0.25, 0.50, 0.75, 1.0} con
`phase2e_co2_suba_enabled = true` sobre 3 casos sentinel + 3 casos CO₂ target para verificar:
  1. Si Sub-A cierra ≥1 gap CO₂ upper sin romper sentinels.
  2. Si la supresión de inflow-dilución (gain=0.0 con flag ON) es suficiente para cerrar gaps.
  3. Qué nivel de outflow removal (gain) produce el mejor balance gap/sentinel.

Mecanismo (Phase 2E Sub-A):
  En OxygenExchangeSystem.gd / _step_outside_opening_o2():
    FLAG OFF (default):
      Dilución proporcional original:
        indoor.co2_upper = (co2_upper * mass_room + 0.0004 * air_in) / (mass_room + air_in)
    FLAG ON:
      - Si upper_outlet_height_m > 0: solo outflow selectivo de capa alta.
          outflow_ratio = clamp(upper_outlet_height_m / max(lower_inlet_height_m, 0.05), 0, 2)
          upper_air_mass = max(upper_gas_kg, room_air_mass * upper_zone_frac)
          upper_out_kg   = min(upper_air_mass * 0.25, air_in * outflow_ratio * gain)
          removal_frac   = clamp(upper_out_kg / max(upper_air_mass, 0.1), 0, 0.25)
          co2_upper      = lerp(co2_upper, 0.0004, removal_frac)
        gain=0.0 → removal_frac=0 → co2_upper sin cambio (supresión pura de dilución masiva)
      - Si upper_outlet_height_m <= 0: no-op (ni dilución ni outflow)

Casos evaluados:
  Sentinels (3):
    g4_gie_delayed_entry_hazard      CO>1200 timing, FED timing
    v3_hallway_fed_exposure          FED timing, max FED
    victim_fed_incapacitation        final FED

  CO₂ target (3):
    cfast_r0_window_360              → cfast_t510_co2_upper_ppm  [TARGET: cierre de gap principal]
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
  1. Flag OFF: 292/292 PASS exacto (verificado por guardrails, no por este runner).
  2. Sentinels: 5/5 PASS con flag ON.
  3. FED delta (ON vs baseline) en sentinel cases: |ΔFED| < 0.005.
  4. Sin nuevos required FAIL (no regresar required checks que ya pasaban).
  5. ≥1 gap CO₂ cerrado.
  6. Si cfast_2r_r0_t120 empeora (SF sube aún más por encima del rango), descartar.

Ganancias evaluadas:
  0.00 (flag ON, gain=0 → supresión de dilución, outflow nulo)
  0.25, 0.50, 0.75, 1.00

Uso:
    python scripts/simulation/phase2e_co2_experiment_1b_runner.py
    python scripts/simulation/phase2e_co2_experiment_1b_runner.py --skip-run
    python scripts/simulation/phase2e_co2_experiment_1b_runner.py --gains 0.0 0.25 0.50 1.0
    python scripts/simulation/phase2e_co2_experiment_1b_runner.py --include-flashover

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

DEFAULT_GAINS: list[float] = [0.0, 0.25, 0.50, 0.75, 1.00]

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
    ("cfast_single_room_closed",   0, 300.0, "cfast_src_t300_co2_upper_ppm",   None,    None,    "ppm"),  # observación
    ("cfast_two_room_door_open",   0, 120.0, "cfast_2r_r0_t120_co2_upper_pct",   1.58,  3.0,    "pct"),
    ("cfast_two_room_door_open",   0, 480.0, "cfast_2r_r0_t480_co2_upper_pct",   9.91,  3.0,    "pct"),
    ("cfast_post_flashover_vented", 0, 240.0, "cfast_fo_t240_co2_upper_pct",    7.77,  3.0,    "pct"),
    ("cfast_post_flashover_vented", 0, 350.0, "cfast_fo_t350_co2_upper_pct",    7.89,  3.0,    "pct"),
]

# Baseline CO₂ values (from last validated run, flag OFF)
CO2_BASELINE: dict[str, float] = {
    "cfast_t510_co2_upper_ppm":        16182.0,   # GAP: SF 16182 vs CFAST 52300 ± 20000
    "cfast_t420_co2_upper_ppm":        41438.0,   # PASS baseline
    "cfast_2r_r0_t120_co2_upper_pct":   4.75,     # GAP: SF 4.75% vs CFAST 1.58% ± 3%
    "cfast_2r_r0_t480_co2_upper_pct":   0.999,    # GAP: SF 0.999% vs CFAST 9.91% ± 3%
    "cfast_fo_t240_co2_upper_pct":      4.32,     # GAP: SF 4.32% vs CFAST 7.77% ± 3%
    "cfast_fo_t350_co2_upper_pct":      0.77,     # GAP: SF 0.77% vs CFAST 7.89% ± 3%
}

# Sub-A specific: sentinels for cfast_two_room cases that may be impacted by outside opening logic
# (g4/v3 sentinel rooms are interior; r0_window has an exterior opening → Sub-A may affect it)
SUBA_RISK_CASES = ["cfast_r0_window_360"]  # cases with exterior openings (Sub-A is active here)


def _gain_str(g: float) -> str:
    """Convert gain to compact string: 0.0 → 'g0', 0.25 → 'g25', 1.00 → 'g100'."""
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


def _count_required_pass(report: "dict | None") -> "tuple[int, int]":
    """Return (passing_required, total_required) from a report JSON."""
    if report is None:
        return (0, 0)
    checks = report.get("checks", [])
    if not isinstance(checks, list):
        return (0, 0)
    required = [c for c in checks if c.get("required", False)]
    passing  = [c for c in required  if c.get("pass",     False)]
    return (len(passing), len(required))


# ---------------------------------------------------------------------------
# Experiment case builder
# ---------------------------------------------------------------------------

def _build_exp_case(base_path: Path, exp_path: Path, exp_name: str, gain: float) -> None:
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides["phase2e_co2_suba_enabled"] = True
    overrides["phase2e_co2_upper_outflow_gain"] = gain
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
        description="Phase 2E CO₂ Experiment 1B — Sub-A outside-opening CO2 upper outflow correction sweep."
    )
    parser.add_argument("--godot",             default=None, metavar="PATH")
    parser.add_argument("--skip-run",          action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--gains",             nargs="+", type=float,
                        default=DEFAULT_GAINS, metavar="G",
                        help="Ganancias a evaluar (default: 0.0 0.25 0.50 0.75 1.00)")
    parser.add_argument("--include-flashover", action="store_true",
                        help="Incluir cfast_post_flashover_vented en la evaluación")
    parser.add_argument("--timeout",           type=int, default=300)
    args = parser.parse_args()

    gains = sorted(set(args.gains))
    co2_cases = CO2_CASES_DEFAULT + (CO2_CASES_FLASHOVER if args.include_flashover else [])
    active_cases = SENTINEL_CASES + co2_cases

    W = 128
    print()
    print("=" * W)
    print("  Phase 2E CO₂ Experiment 1B — Sub-A: outside-opening CO₂ upper outflow correction")
    print(f"  Ganancias  : {gains}")
    print(f"  Casos      : {' | '.join(active_cases)}")
    print(f"  Mecanismo  : phase2e_co2_suba_enabled=true + upper_outflow_gain sweep")
    print(f"  gain=0.0   : supresión de inflow-dilución, outflow nulo (control de dilución pura)")
    print(f"  Gate       : sentinels 5/5 PASS + |ΔFED|<0.005 + ≥1 CO₂ gap cerrado + t120 no empeora")
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
                exp_name  = f"{case}_p2e1b_{gstr}"
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
                print(f"  [{done:>2}/{total_runs}] Phase2E-1B gain={gain:.2f}  {case} ...",
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
            exp_name = f"{case}_p2e1b_{gstr}"
            exp_rpts[(case, gain)] = _load_report(REPORTS_DIR / f"{exp_name}.json")
        for case in co2_cases:
            exp_name = f"{case}_p2e1b_{gstr}"
            exp_logs[(case, gain)] = _parse_simufire_log(
                REPORTS_DIR / f"{exp_name}.log", room_id=0)

    # =========================================================================
    # TABLA 1 — Sentinels + required checks
    # =========================================================================
    SEP = "-" * W
    print()
    print(SEP)
    print("  TABLA 1 — Sentinels + required checks por ganancia")
    col_w = 16
    header_parts = ["  Ganancia    "]
    for _, _, _, _, lbl in SENTINELS:
        header_parts.append(f"{lbl:<{col_w}}")
    header_parts.append(f"{'Total':>{col_w}}")
    header_parts.append(f"{'Req.PASS':>{col_w}}")
    print("".join(header_parts))
    print("  " + "-" * (W - 4))

    def _fmt_sentinel(val: "float | None", lo: "float | None", hi: "float | None",
                      base: "float | None" = None) -> str:
        ok = _sentinel_pass(val, lo, hi)
        if val is None:
            return f"{'N/A':<{col_w}}"
        badge = "OK" if ok else "FAIL"
        delta_str = ""
        if base is not None and val is not None:
            d = val - base
            delta_str = f"({d:+.3f})" if abs(d) > 0.0005 else ""
        return f"{val:.3f}{delta_str} {badge:<4}"[:col_w]

    # baseline row
    parts = [f"  {'BASELINE':<12} "]
    total_ok = 0
    for case, key, lo, hi, _ in SENTINELS:
        val = _get_metric(baseline_rpts.get(case), key)
        ok = _sentinel_pass(val, lo, hi)
        if ok:
            total_ok += 1
        parts.append(_fmt_sentinel(val, lo, hi))
    parts.append(f"{total_ok}/5".rjust(col_w))
    # required baseline
    total_req_pass = sum(_count_required_pass(baseline_rpts.get(c))[0] for c in active_cases)
    total_req_all  = sum(_count_required_pass(baseline_rpts.get(c))[1] for c in active_cases)
    parts.append(f"{total_req_pass}/{total_req_all}".rjust(col_w))
    print("".join(parts))

    for gain in gains:
        gstr = _gain_str(gain)
        parts = [f"  g={gain:.2f}       "]
        total_ok = 0
        for case, key, lo, hi, _ in SENTINELS:
            val = _get_metric(exp_rpts.get((case, gain)), key)
            base = _get_metric(baseline_rpts.get(case), key)
            ok = _sentinel_pass(val, lo, hi)
            if ok:
                total_ok += 1
            parts.append(_fmt_sentinel(val, lo, hi, base))
        parts.append(f"{total_ok}/5".rjust(col_w))
        req_pass = sum(_count_required_pass(exp_rpts.get((c, gain)))[0] for c in active_cases)
        req_all  = sum(_count_required_pass(exp_rpts.get((c, gain)))[1] for c in active_cases)
        req_badge = "OK" if req_pass == total_req_all else f"FAIL(-{total_req_all - req_pass})"
        parts.append(f"{req_pass}/{req_all} {req_badge}".rjust(col_w + 8))
        print("".join(parts))

    # =========================================================================
    # TABLA 2 — FED deltas en sentinel cases
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 2 — FED deltas en sentinel cases (gate: |Δ| < 0.005)")
    GATE_FED = 0.005
    col_w2 = 18

    header2 = f"  {'Métrica':<40} {'Baseline':>{col_w2}}"
    for gain in gains:
        header2 += f"  {'g='+f'{gain:.2f}':>{col_w2}}"
    print(header2)
    print("  " + "-" * (W - 4))

    max_fed_delta_by_gain: dict[float, float] = {g: 0.0 for g in gains}

    for case, key, label in FED_DELTA_METRICS:
        base_val = _get_metric(baseline_rpts.get(case), key)
        base_str = f"{base_val:.4f}" if base_val is not None else "N/A"
        row = f"  {label:<40} {base_str:>{col_w2}}"
        for gain in gains:
            val = _get_metric(exp_rpts.get((case, gain)), key)
            if val is None or base_val is None:
                cell = "N/A"
            else:
                delta = val - base_val
                max_fed_delta_by_gain[gain] = max(max_fed_delta_by_gain[gain], abs(delta))
                badge = "OK" if abs(delta) < GATE_FED else "⚠FAIL"
                cell = f"{delta:+.4f} {badge}"
            row += f"  {cell:>{col_w2}}"
        print(row)

    # Max FED delta row
    row = f"  {'Max |ΔFED| por ganancia':<40} {' ':>{col_w2}}"
    for gain in gains:
        mx = max_fed_delta_by_gain[gain]
        badge = "OK" if mx < GATE_FED else "⚠FAIL"
        row += f"  {f'{mx:.4f} {badge}':>{col_w2}}"
    print(row)

    # =========================================================================
    # TABLA 3 — CO₂ upper por ganancia (check targets)
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 3 — CO₂ upper por ganancia (targets con referencia CFAST)")
    print()

    col_base = 10
    col_g = 20

    header3 = f"  {'Check':<42} {'Baseline':>{col_base}} {'CFAST ref':>{col_base}} {'Tol':>{col_base}}"
    for gain in gains:
        header3 += f"  {'g='+f'{gain:.2f}':>{col_g}}"
    header3 += f"  {'Base OK':>{8}}"
    print(header3)

    active_targets = [t for t in CO2_GAP_TARGETS
                      if t[0] in co2_cases]

    gaps_closed_by_gain: dict[float, int] = {g: 0 for g in gains}
    t120_worsened_by_gain: dict[float, bool] = {g: False for g in gains}

    for case, room_id, target_s, check_name, expected, tol, unit in active_targets:
        b_samples = baseline_logs.get(case, [])
        b_pt = _nearest(b_samples, target_s)

        if unit == "ppm":
            b_val = b_pt["co2_upper_ppm"] if b_pt else math.nan
            b_str = f"{b_val:.0f}" if not math.isnan(b_val) else "N/A"
            exp_str = f"{expected:.0f}" if expected is not None else "obs"
            tol_str = f"±{tol:.0f}" if tol is not None else "obs"
        else:  # pct
            b_val = b_pt["co2_upper_pct"] if b_pt else math.nan
            b_str = f"{b_val:.3f}%" if not math.isnan(b_val) else "N/A"
            exp_str = f"{expected:.2f}%" if expected is not None else "obs"
            tol_str = f"±{tol:.1f}%" if tol is not None else "obs"

        # baseline gap status
        b_gap_ok = _co2_gap_passes(b_val, expected, tol)
        base_badge = "PASS" if b_gap_ok is True else ("FAIL" if b_gap_ok is False else "obs")

        row = f"  {check_name:<42} {b_str:>{col_base}} {exp_str:>{col_base}} {tol_str:>{col_base}}"

        for gain in gains:
            g_samples = exp_logs.get((case, gain), [])
            g_pt = _nearest(g_samples, target_s)

            if unit == "ppm":
                g_val = g_pt["co2_upper_ppm"] if g_pt else math.nan
                if not math.isnan(g_val) and not math.isnan(b_val):
                    delta = g_val - b_val
                    cell = f"{g_val:.0f} ({delta:+.0f})"
                elif not math.isnan(g_val):
                    cell = f"{g_val:.0f}"
                else:
                    cell = "N/A"
                    g_val = math.nan
            else:  # pct
                g_val = g_pt["co2_upper_pct"] if g_pt else math.nan
                if not math.isnan(g_val) and not math.isnan(b_val):
                    delta = g_val - b_val
                    cell = f"{g_val:.3f}% ({delta:+.3f})"
                elif not math.isnan(g_val):
                    cell = f"{g_val:.3f}%"
                else:
                    cell = "N/A"
                    g_val = math.nan

            # gap status for this gain
            g_gap_ok = _co2_gap_passes(g_val, expected, tol)
            if g_gap_ok is True and b_gap_ok is not True:
                # Newly closed gap
                gaps_closed_by_gain[gain] += 1

            # t120 worsening check: SF already high → Sub-A should not make it worse
            if check_name == "cfast_2r_r0_t120_co2_upper_pct":
                if not math.isnan(g_val) and not math.isnan(b_val) and g_val > b_val + 0.5:
                    t120_worsened_by_gain[gain] = True

            row += f"  {cell:>{col_g}}"

        row += f"  {base_badge:>{8}}"
        print(row)

    # =========================================================================
    # TABLA 4 — Max CO₂ upper ppm (sala 0, toda la sim) — riesgo V_CO₂
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 4 — Max CO₂ upper ppm (sala 0, toda la simulación)")
    print("  Nota: V_CO₂=1.0 hasta 20000 ppm (2%). Riesgo alto >120000 ppm (12%).")
    print()

    WARN_PPM = 120000.0
    col_max = 14
    header4 = f"  {'Caso':<42} {'Baseline':>{col_max}}"
    for gain in gains:
        header4 += f"  {'g='+f'{gain:.2f}':>{col_max}}"
    print(header4)

    for case in co2_cases:
        b_max = _max_co2_upper_ppm(baseline_logs.get(case, []))
        b_str = f"{b_max:.0f}{'⚠' if b_max > WARN_PPM else ''}" if not math.isnan(b_max) else "N/A"
        row = f"  {case:<42} {b_str:>{col_max}}"
        for gain in gains:
            g_max = _max_co2_upper_ppm(exp_logs.get((case, gain), []))
            g_str = f"{g_max:.0f}{'⚠' if g_max > WARN_PPM else ''}" if not math.isnan(g_max) else "N/A"
            row += f"  {g_str:>{col_max}}"
        print(row)

    # =========================================================================
    # TABLA 5 — Diagnóstico Sub-A específico: cfast_r0_window_360 t510 evolución
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 5 — Diagnóstico Sub-A: evolución CO₂ upper ppm (cfast_r0_window_360, room 0)")
    print("  Objetivo: cfast_t510 debe subir hacia ≥32300 ppm para cerrar gap.")
    print()

    diag_case = "cfast_r0_window_360"
    diag_times = [120.0, 240.0, 360.0, 420.0, 510.0]

    col_t = 8
    header5 = f"  {'t [s]':<{col_t}}"
    header5 += f"  {'Baseline':>{col_max}}"
    for gain in gains:
        header5 += f"  {'g='+f'{gain:.2f}':>{col_max}}"
    print(header5)

    b_samples_diag = baseline_logs.get(diag_case, [])
    for t in diag_times:
        b_pt = _nearest(b_samples_diag, t)
        b_v = b_pt["co2_upper_ppm"] if b_pt else math.nan
        row = f"  {t:<{col_t}.0f}  {f'{b_v:.0f}' if not math.isnan(b_v) else 'N/A':>{col_max}}"
        for gain in gains:
            g_samples = exp_logs.get((diag_case, gain), [])
            g_pt = _nearest(g_samples, t)
            g_v = g_pt["co2_upper_ppm"] if g_pt else math.nan
            if not math.isnan(g_v) and not math.isnan(b_v):
                delta = g_v - b_v
                cell = f"{g_v:.0f} ({delta:+.0f})"
            elif not math.isnan(g_v):
                cell = f"{g_v:.0f}"
            else:
                cell = "N/A"
            row += f"  {cell:>{col_max}}"
        print(row)

    # =========================================================================
    # RESUMEN
    # =========================================================================
    print()
    print(SEP)
    print("  RESUMEN — CO₂ gaps cerrados por ganancia (de los targets requeridos)")
    print()

    GATE_T120_UPPER_LIMIT = 5.58  # 1.58% + 3.0pp tolerancia SF HIGH: sobre esto Sub-A es contraproducente

    print(f"  {'Ganancia':<14} {'Sentinels':<12} {'FED gate':<30} {'CO₂ gaps':<16} {'t120 ok':<10} {'Decisión'}")
    for gain in gains:
        gstr = _gain_str(gain)
        # Sentinels
        s_total = 0
        for case, key, lo, hi, _ in SENTINELS:
            val = _get_metric(exp_rpts.get((case, gain)), key)
            if _sentinel_pass(val, lo, hi):
                s_total += 1
        s_badge = f"{s_total}/5 {'OK' if s_total == 5 else 'FAIL'}"

        # FED gate
        mx_fed = max_fed_delta_by_gain[gain]
        fed_badge = f"OK (max Δ={mx_fed:.4f})" if mx_fed < GATE_FED else f"⚠FAIL (max Δ={mx_fed:.4f})"

        # CO₂ gaps
        n_gaps = gaps_closed_by_gain[gain]
        gaps_badge = f"{n_gaps}/{'?' if not active_targets else len([t for t in active_targets if t[4] is not None])} cerrados"

        # t120
        t120_badge = "OK" if not t120_worsened_by_gain[gain] else "⚠WORSE"

        # Decisión
        if s_total == 5 and mx_fed < GATE_FED and n_gaps >= 1 and not t120_worsened_by_gain[gain]:
            decision = "✓ CANDIDATO"
        elif s_total == 5 and mx_fed < GATE_FED and n_gaps == 0:
            decision = "✗ no cierra gaps"
        elif t120_worsened_by_gain[gain]:
            decision = "✗ t120 empeorado"
        elif s_total < 5:
            decision = "✗ sentinels FAIL"
        else:
            decision = "? revisar"

        print(f"  g={gain:.2f}          {s_badge:<12} {fed_badge:<30} {gaps_badge:<16} {t120_badge:<10} {decision}")

    # =========================================================================
    # INTERPRETACIÓN
    # =========================================================================
    print()
    print("=" * W)
    print("  INTERPRETACIÓN Phase 2E CO₂ Exp 1B (Sub-A)")
    print("=" * W)

    candidates = [g for g in gains
                  if (sum(1 for c, k, lo, hi, _ in SENTINELS
                         if _sentinel_pass(_get_metric(exp_rpts.get((c, g)), k), lo, hi) is True) == 5
                      and max_fed_delta_by_gain[g] < GATE_FED
                      and gaps_closed_by_gain[g] >= 1
                      and not t120_worsened_by_gain[g])]

    print()
    if candidates:
        best = candidates[0]
        print(f"  RESULTADO: Sub-A candidato. Gain={best:.2f} cierra {gaps_closed_by_gain[best]} gap(s) CO₂.")
        print()
        print("  DIAGNÓSTICO:")
        # Check if gain=0.0 already closes gaps
        g0_gaps = gaps_closed_by_gain.get(0.0, 0) if 0.0 in gains else -1
        if g0_gaps >= 1:
            print("    • gain=0.0 (supresión de dilución masiva sin outflow) ya cierra gaps.")
            print("      → El problema raíz es la dilución por inflow masivo, no la falta de outflow.")
        else:
            print("    • gain=0.0 no cierra gaps; se requiere outflow removal activo.")
            print("      → La dilución masiva Y el outflow insuficiente contribuyen al gap.")
        print()
        print(f"  DECISIÓN: CANDIDATO gain={best:.2f} para Sub-A.")
        print("  → Proceder con Exp 2E-CO₂-1C (Sub-B) o Exp 2E-CO₂-2 (combinado Sub-A + Sub-B).")
        print("  Documentar resultados en PHASE_2E_CO2_DESIGN.md §11 (Exp 1B results).")
    else:
        print("  RESULTADO: Sub-A no cierra ningún gap CO₂ upper con las ganancias evaluadas,")
        print("             o rompe sentinels/FED/t120.")
        print()
        print("  DIAGNÓSTICO:")
        print("    • Si gain=0.0 sube los valores pero no cierra el gap → la dilución contribuye")
        print("      pero el gap es demasiado grande para Sub-A solo.")
        print("    • Si gain=0.0 no cambia nada → la apertura exterior en estos casos no tiene")
        print("      upper_outlet_height_m > 0, o la condición de delta_t_k < 2 detiene el flujo.")
        print()
        print("  DECISIÓN: SUB-A INSUFICIENTE como mecanismo único.")
        print("  → Continuar con Exp 2E-CO₂-1C (Sub-B: doorway two-zone exchange).")
        print("  → O considerar experimento combinado Sub-A+Sub-C si hay mejora parcial.")
        print("  Documentar resultados en PHASE_2E_CO2_DESIGN.md §11 (Exp 1B results).")

    if run_errors:
        print()
        print(f"  ADVERTENCIA: {len(run_errors)} run(s) fallaron: {run_errors}")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
