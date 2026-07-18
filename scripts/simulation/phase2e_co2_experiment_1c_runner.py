"""
phase2e_co2_experiment_1c_runner.py — Runner experimental Phase 2E CO₂, Exp 1C (Sub-B solo).

Barrido de `phase2e_co2_exchange_fraction` ∈ {0.25, 0.08, 0.05, 0.03} con
`phase2e_co2_subb_enabled = true` sobre 3 casos sentinel + 3 casos CO₂ target para verificar:
  1. Si Sub-B (reducir fracción de intercambio CO₂ inter-room) cierra cfast_2r_r0_t480.
  2. Si el check de riesgo cfast_2r_r0_t120 no empeora por encima del umbral de descarte (5.58%).
  3. Si los sentinels FED/CO permanecen dentro de sus ventanas validadas.

Mecanismo (Phase 2E Sub-B):
  En OxygenExchangeSystem.gd / _exchange_room_o2_active_flow():
    FLAG OFF (default): CO2_EXCHANGE_FRACTION constante = 0.25 (Fase 2B original).
    FLAG ON: usa phase2e_co2_exchange_fraction en lugar de 0.25.
      Reducir la fracción → retiene más CO₂ en la sala fuego → sube cfast_2r_r0_t480.
      Reducir la fracción → también retiene más CO₂ a t=120s → puede empeorar cfast_2r_r0_t120.

  El objetivo es encontrar la fracción mínima que cierra t480 sin superar t120 > 5.58%.

Caso primario (target):
  cfast_two_room_door_open → cfast_2r_r0_t480_co2_upper_pct (target: ≥6.91% → [6.91, 12.91])
  Riesgo:                   → cfast_2r_r0_t120_co2_upper_pct (gate descarte: SF ≤ 5.58%)

Casos evaluados:
  Sentinels (3):
    g4_gie_delayed_entry_hazard      CO>1200 timing, FED timing
    v3_hallway_fed_exposure          FED timing, max FED
    victim_fed_incapacitation        final FED

  CO₂ target (3):
    cfast_r0_window_360              → cfast_t510_co2_upper_ppm  (Sub-B no debe regresar: exterior opening)
    cfast_single_room_closed         → observación (sala sellada, no hay doorway exchange)
    cfast_two_room_door_open         → cfast_2r_r0_t120/t480_co2_upper_pct [TARGET PRINCIPAL]

  (cfast_post_flashover_vented con --include-flashover)

Sentinels obligatorios (ventanas Phase 2H-validadas):
  g4 CO>1200 [s]   : [82.333, 92.333]
  g4 FED>0.1 [s]   : [187.75, 207.75]
  v3 FED>0.1 [s]   : [222.17, 282.17]
  v3 max FED       : >= 1.0
  vic final FED    : >= 0.7

Gates para candidato:
  1. Flag OFF: 292/292 PASS exacto (verificado por guardrails).
  2. Sentinels: 5/5 PASS con flag ON.
  3. FED delta (ON vs baseline): |ΔFED| < 0.005 en sentinel cases.
  4. Sin nuevos required FAIL (no regresar required checks que ya pasaban).
  5. cfast_2r_r0_t480 cerrado (SF ∈ [6.91, 12.91]).
  6. cfast_2r_r0_t120 NO empeora por encima de 5.58% (criterio de descarte Sub-B solo).

Fracciones evaluadas (default):
  0.25  (flag ON, fracción original → misma que baseline, sirve como control)
  0.08
  0.05
  0.03

Uso:
    python scripts/simulation/phase2e_co2_experiment_1c_runner.py
    python scripts/simulation/phase2e_co2_experiment_1c_runner.py --skip-run
    python scripts/simulation/phase2e_co2_experiment_1c_runner.py --fractions 0.25 0.10 0.05 0.03
    python scripts/simulation/phase2e_co2_experiment_1c_runner.py --include-flashover

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

DEFAULT_FRACTIONS: list[float] = [0.25, 0.08, 0.05, 0.03]

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
    "cfast_t510_co2_upper_ppm":        16182.0,
    "cfast_t420_co2_upper_ppm":        41438.0,
    "cfast_2r_r0_t120_co2_upper_pct":   4.75,   # SF HIGH: 4.75% vs CFAST 1.58% ± 3%
    "cfast_2r_r0_t480_co2_upper_pct":   0.999,  # SF LOW: 0.999% vs CFAST 9.91% ± 3%
    "cfast_fo_t240_co2_upper_pct":      4.32,
    "cfast_fo_t350_co2_upper_pct":      0.77,
}

# Gate de descarte Sub-B solo: si SF t120 supera esto, Sub-B aislado es inviable.
GATE_T120_MAX_SF_PCT = 5.58   # 1.58% + 3.0pp tol + 1.0pp extra


def _frac_str(f: float) -> str:
    """Convert fraction to compact string: 0.25 → 'f25', 0.08 → 'f8', 0.03 → 'f3'."""
    return f"f{int(round(f * 100))}"


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
    if report is None:
        return (0, 0)
    checks = report.get("checks", [])
    if not isinstance(checks, list):
        return (0, 0)
    required = [c for c in checks if c.get("required", False)]
    passing  = [c for c in required if c.get("pass", False)]
    return (len(passing), len(required))


# ---------------------------------------------------------------------------
# Experiment case builder
# ---------------------------------------------------------------------------

def _build_exp_case(base_path: Path, exp_path: Path, exp_name: str, fraction: float) -> None:
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides["phase2e_co2_subb_enabled"] = True
    overrides["phase2e_co2_exchange_fraction"] = fraction
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
        description="Phase 2E CO₂ Experiment 1C — Sub-B CO₂ inter-room exchange fraction sweep."
    )
    parser.add_argument("--godot",             default=None, metavar="PATH")
    parser.add_argument("--skip-run",          action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--fractions",         nargs="+", type=float,
                        default=DEFAULT_FRACTIONS, metavar="F",
                        help="Fracciones a evaluar (default: 0.25 0.08 0.05 0.03)")
    parser.add_argument("--include-flashover", action="store_true",
                        help="Incluir cfast_post_flashover_vented en la evaluación")
    parser.add_argument("--timeout",           type=int, default=300)
    args = parser.parse_args()

    fractions = sorted(set(args.fractions), reverse=True)  # alto a bajo: 0.25 primero
    co2_cases = CO2_CASES_DEFAULT + (CO2_CASES_FLASHOVER if args.include_flashover else [])
    active_cases = SENTINEL_CASES + co2_cases

    W = 128
    print()
    print("=" * W)
    print("  Phase 2E CO₂ Experiment 1C — Sub-B: CO₂ inter-room exchange fraction sweep")
    print(f"  Fracciones : {fractions}")
    print(f"  Casos      : {' | '.join(active_cases)}")
    print(f"  Mecanismo  : phase2e_co2_subb_enabled=true + co2_exchange_fraction sweep")
    print(f"  frac=0.25  : comportamiento idéntico al baseline (control — fracción original)")
    print(f"  frac<0.25  : retiene más CO₂ en sala fuego → ayuda t480, posible riesgo t120")
    print(f"  Gate t120  : SF ≤ {GATE_T120_MAX_SF_PCT}% (1.58% + 3pp tol + 1pp margen)")
    print(f"  Target     : cfast_2r_r0_t480 ∈ [6.91%, 12.91%] (9.91% ± 3%)")
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
            fstr = _frac_str(frac)
            for case in active_cases:
                exp_name  = f"{case}_p2e1c_{fstr}"
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
                print(f"  [{done:>2}/{total_runs}] Phase2E-1C frac={frac:.2f}  {case} ...",
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

    # -- Cargar experiment reports + logs por fracción ------------------------
    exp_rpts: dict[tuple[str, float], "dict | None"] = {}
    exp_logs: dict[tuple[str, float], list[dict]] = {}
    for frac in fractions:
        fstr = _frac_str(frac)
        for case in active_cases:
            exp_name = f"{case}_p2e1c_{fstr}"
            exp_rpts[(case, frac)] = _load_report(REPORTS_DIR / f"{exp_name}.json")
        for case in co2_cases:
            exp_name = f"{case}_p2e1c_{fstr}"
            exp_logs[(case, frac)] = _parse_simufire_log(
                REPORTS_DIR / f"{exp_name}.log", room_id=0)

    SEP = "-" * W

    # =========================================================================
    # TABLA 1 — Sentinels + required checks
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 1 — Sentinels + required checks por fracción")
    col_w = 16
    header_parts = ["  Fracción    "]
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
    total_req_all = sum(_count_required_pass(baseline_rpts.get(c))[1] for c in active_cases)
    parts = [f"  {'BASELINE':<12} "]
    total_ok = 0
    for case, key, lo, hi, _ in SENTINELS:
        val = _get_metric(baseline_rpts.get(case), key)
        ok = _sentinel_pass(val, lo, hi)
        if ok:
            total_ok += 1
        parts.append(_fmt_sentinel(val, lo, hi))
    parts.append(f"{total_ok}/5".rjust(col_w))
    total_req_pass = sum(_count_required_pass(baseline_rpts.get(c))[0] for c in active_cases)
    parts.append(f"{total_req_pass}/{total_req_all}".rjust(col_w))
    print("".join(parts))

    for frac in fractions:
        parts = [f"  f={frac:.2f}      "]
        total_ok = 0
        for case, key, lo, hi, _ in SENTINELS:
            val = _get_metric(exp_rpts.get((case, frac)), key)
            base = _get_metric(baseline_rpts.get(case), key)
            ok = _sentinel_pass(val, lo, hi)
            if ok:
                total_ok += 1
            parts.append(_fmt_sentinel(val, lo, hi, base))
        parts.append(f"{total_ok}/5".rjust(col_w))
        req_pass = sum(_count_required_pass(exp_rpts.get((c, frac)))[0] for c in active_cases)
        req_badge = "OK" if req_pass == total_req_all else f"FAIL(-{total_req_all - req_pass})"
        parts.append(f"{req_pass}/{total_req_all} {req_badge}".rjust(col_w + 8))
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
    for frac in fractions:
        header2 += f"  {'f='+f'{frac:.2f}':>{col_w2}}"
    print(header2)
    print("  " + "-" * (W - 4))

    max_fed_delta_by_frac: dict[float, float] = {f: 0.0 for f in fractions}

    for case, key, label in FED_DELTA_METRICS:
        base_val = _get_metric(baseline_rpts.get(case), key)
        base_str = f"{base_val:.4f}" if base_val is not None else "N/A"
        row = f"  {label:<40} {base_str:>{col_w2}}"
        for frac in fractions:
            val = _get_metric(exp_rpts.get((case, frac)), key)
            if val is None or base_val is None:
                cell = "N/A"
            else:
                delta = val - base_val
                max_fed_delta_by_frac[frac] = max(max_fed_delta_by_frac[frac], abs(delta))
                badge = "OK" if abs(delta) < GATE_FED else "⚠FAIL"
                cell = f"{delta:+.4f} {badge}"
            row += f"  {cell:>{col_w2}}"
        print(row)

    # Max FED delta row
    row = f"  {'Max |ΔFED| por fracción':<40} {' ':>{col_w2}}"
    for frac in fractions:
        mx = max_fed_delta_by_frac[frac]
        badge = "OK" if mx < GATE_FED else "⚠FAIL"
        row += f"  {f'{mx:.4f} {badge}':>{col_w2}}"
    print(row)

    # =========================================================================
    # TABLA 3 — CO₂ upper por fracción (check targets)
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 3 — CO₂ upper por fracción (targets con referencia CFAST)")
    print()
    print("  Nota de dirección Sub-B:")
    print("    Reducir fracción (0.25 → 0.03) RETIENE más CO₂ en sala fuego.")
    print("    t480: SF bajo (0.999%) → objetivo subir hacia 9.91%: fracción MENOR = MEJOR.")
    print("    t120: SF alto (4.75%) → fracción menor retiene aún más → riesgo de empeorar.")
    print()

    col_base = 10
    col_g = 22

    header3 = f"  {'Check':<42} {'Baseline':>{col_base}} {'CFAST ref':>{col_base}} {'Tol':>{col_base}}"
    for frac in fractions:
        header3 += f"  {'f='+f'{frac:.2f}':>{col_g}}"
    header3 += f"  {'Base OK':>{8}}"
    print(header3)

    active_targets = [t for t in CO2_GAP_TARGETS if t[0] in co2_cases]

    gaps_closed_by_frac: dict[float, int] = {f: 0 for f in fractions}
    t120_too_high_by_frac: dict[float, bool] = {f: False for f in fractions}
    t480_val_by_frac: dict[float, float] = {f: math.nan for f in fractions}

    for case, room_id, target_s, check_name, expected, tol, unit in active_targets:
        b_samples = baseline_logs.get(case, [])
        b_pt = _nearest(b_samples, target_s)

        if unit == "ppm":
            b_val = b_pt["co2_upper_ppm"] if b_pt else math.nan
            b_str = f"{b_val:.0f}" if not math.isnan(b_val) else "N/A"
            exp_str = f"{expected:.0f}" if expected is not None else "obs"
            tol_str = f"±{tol:.0f}" if tol is not None else "obs"
        else:
            b_val = b_pt["co2_upper_pct"] if b_pt else math.nan
            b_str = f"{b_val:.3f}%" if not math.isnan(b_val) else "N/A"
            exp_str = f"{expected:.2f}%" if expected is not None else "obs"
            tol_str = f"±{tol:.1f}%" if tol is not None else "obs"

        b_gap_ok = _co2_gap_passes(b_val, expected, tol)
        base_badge = "PASS" if b_gap_ok is True else ("FAIL" if b_gap_ok is False else "obs")

        row = f"  {check_name:<42} {b_str:>{col_base}} {exp_str:>{col_base}} {tol_str:>{col_base}}"

        for frac in fractions:
            g_samples = exp_logs.get((case, frac), [])
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
            else:
                g_val = g_pt["co2_upper_pct"] if g_pt else math.nan
                if not math.isnan(g_val) and not math.isnan(b_val):
                    delta = g_val - b_val
                    cell = f"{g_val:.3f}% ({delta:+.3f})"
                elif not math.isnan(g_val):
                    cell = f"{g_val:.3f}%"
                else:
                    cell = "N/A"
                    g_val = math.nan

            g_gap_ok = _co2_gap_passes(g_val, expected, tol)
            if g_gap_ok is True and b_gap_ok is not True:
                gaps_closed_by_frac[frac] += 1

            # t480: track value for summary
            if check_name == "cfast_2r_r0_t480_co2_upper_pct" and not math.isnan(g_val):
                t480_val_by_frac[frac] = g_val

            # t120: gate de descarte — SF debe mantenerse ≤ GATE_T120_MAX_SF_PCT
            if check_name == "cfast_2r_r0_t120_co2_upper_pct" and not math.isnan(g_val):
                if g_val > GATE_T120_MAX_SF_PCT:
                    t120_too_high_by_frac[frac] = True

            # flag if Sub-B worsens t510 (regression — Sub-B should NOT affect exterior openings)
            if check_name == "cfast_t510_co2_upper_ppm" and not math.isnan(g_val) and not math.isnan(b_val):
                if g_val < b_val - 1000.0:
                    cell += " ⚠REG"

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
    for frac in fractions:
        header4 += f"  {'f='+f'{frac:.2f}':>{col_max}}"
    print(header4)

    for case in co2_cases:
        b_max = _max_co2_upper_ppm(baseline_logs.get(case, []))
        b_str = f"{b_max:.0f}{'⚠' if b_max > WARN_PPM else ''}" if not math.isnan(b_max) else "N/A"
        row = f"  {case:<42} {b_str:>{col_max}}"
        for frac in fractions:
            g_max = _max_co2_upper_ppm(exp_logs.get((case, frac), []))
            g_str = f"{g_max:.0f}{'⚠' if g_max > WARN_PPM else ''}" if not math.isnan(g_max) else "N/A"
            row += f"  {g_str:>{col_max}}"
        print(row)

    # =========================================================================
    # TABLA 5 — Diagnóstico Sub-B: evolución temporal cfast_two_room_door_open
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 5 — Diagnóstico Sub-B: evolución CO₂ upper pct (cfast_two_room_door_open, room 0)")
    print("  Objetivo: t480 debe subir hacia ≥6.91% para cerrar gap (9.91% ± 3%).")
    print("  Riesgo  : t120 debe mantenerse ≤ 5.58% para no descartar Sub-B aislado.")
    print()

    diag_case = "cfast_two_room_door_open"
    diag_times = [60.0, 120.0, 240.0, 360.0, 480.0, 540.0]

    col_t = 8
    header5 = f"  {'t [s]':<{col_t}}"
    header5 += f"  {'Baseline':>{col_max}}"
    for frac in fractions:
        header5 += f"  {'f='+f'{frac:.2f}':>{col_max}}"
    print(header5)

    b_samples_diag = baseline_logs.get(diag_case, [])
    for t in diag_times:
        b_pt = _nearest(b_samples_diag, t)
        b_v = b_pt["co2_upper_pct"] if b_pt else math.nan
        row = f"  {t:<{col_t}.0f}  {f'{b_v:.3f}%' if not math.isnan(b_v) else 'N/A':>{col_max}}"
        for frac in fractions:
            g_samples = exp_logs.get((diag_case, frac), [])
            g_pt = _nearest(g_samples, t)
            g_v = g_pt["co2_upper_pct"] if g_pt else math.nan
            if not math.isnan(g_v) and not math.isnan(b_v):
                delta = g_v - b_v
                # flag t120 risk
                risk_tag = " ⚠" if t == 120.0 and g_v > GATE_T120_MAX_SF_PCT else ""
                cell = f"{g_v:.3f}% ({delta:+.3f}){risk_tag}"
            elif not math.isnan(g_v):
                cell = f"{g_v:.3f}%"
            else:
                cell = "N/A"
            row += f"  {cell:>{col_max}}"
        print(row)

    # =========================================================================
    # RESUMEN
    # =========================================================================
    print()
    print(SEP)
    print("  RESUMEN — CO₂ gaps cerrados por fracción (de los targets requeridos)")
    print()

    print(f"  {'Fracción':<14} {'Sentinels':<12} {'FED gate':<30} {'t480 val':<14} {'CO₂ gaps':<14} {'t120 gate':<12} {'Decisión'}")

    for frac in fractions:
        # Sentinels
        s_total = 0
        for case, key, lo, hi, _ in SENTINELS:
            val = _get_metric(exp_rpts.get((case, frac)), key)
            if _sentinel_pass(val, lo, hi):
                s_total += 1
        s_badge = f"{s_total}/5 {'OK' if s_total == 5 else 'FAIL'}"

        # FED gate
        mx_fed = max_fed_delta_by_frac[frac]
        fed_badge = f"OK (max Δ={mx_fed:.4f})" if mx_fed < GATE_FED else f"⚠FAIL (max Δ={mx_fed:.4f})"

        # t480 value
        t480_v = t480_val_by_frac[frac]
        t480_str = f"{t480_v:.3f}%" if not math.isnan(t480_v) else "N/A"

        # CO₂ gaps
        n_gaps = gaps_closed_by_frac[frac]
        n_required = len([t for t in active_targets if t[4] is not None])
        gaps_badge = f"{n_gaps}/{n_required} cerrados"

        # t120 gate
        t120_ok = not t120_too_high_by_frac[frac]
        t120_badge = "OK" if t120_ok else f"⚠DESCARTE (>5.58%)"

        # Decisión
        if s_total == 5 and mx_fed < GATE_FED and n_gaps >= 1 and t120_ok:
            decision = "✓ CANDIDATO"
        elif s_total == 5 and mx_fed < GATE_FED and n_gaps == 0 and t120_ok:
            decision = "✗ no cierra t480"
        elif not t120_ok:
            decision = "✗ Sub-B solo descartado (t120)"
        elif s_total < 5:
            decision = "✗ sentinels FAIL"
        else:
            decision = "? revisar"

        print(f"  f={frac:.2f}          {s_badge:<12} {fed_badge:<30} {t480_str:<14} {gaps_badge:<14} {t120_badge:<12} {decision}")

    # =========================================================================
    # INTERPRETACIÓN
    # =========================================================================
    print()
    print("=" * W)
    print("  INTERPRETACIÓN Phase 2E CO₂ Exp 1C (Sub-B solo)")
    print("=" * W)

    candidates = [f for f in fractions
                  if (sum(1 for c, k, lo, hi, _ in SENTINELS
                         if _sentinel_pass(_get_metric(exp_rpts.get((c, f)), k), lo, hi) is True) == 5
                      and max_fed_delta_by_frac[f] < GATE_FED
                      and gaps_closed_by_frac[f] >= 1
                      and not t120_too_high_by_frac[f])]

    print()
    if candidates:
        best = candidates[-1]  # fracción más pequeña que pasa gates (mayor retención)
        print(f"  RESULTADO: Sub-B candidato. Fracción={best:.2f} cierra {gaps_closed_by_frac[best]} gap(s) CO₂.")
        print()
        print(f"  DECISIÓN: CANDIDATO fracción={best:.2f} para Sub-B.")
        print(f"  → Proceder con Exp 2E-CO₂-2 (combinado Sub-A gain=0.010 + Sub-B frac={best:.2f}).")
    else:
        # Check if t120 is the blocker
        t120_blockers = [f for f in fractions if t120_too_high_by_frac[f]]
        no_gap_fracs  = [f for f in fractions if not t120_too_high_by_frac[f] and gaps_closed_by_frac[f] == 0]

        print(f"  RESULTADO: Sub-B AISLADO no tiene candidato válido.")
        print()
        if t120_blockers:
            print(f"  Fracciones descartadas por t120 > {GATE_T120_MAX_SF_PCT}%: {t120_blockers}")
            print(f"  → Sub-B solo no es viable. Proceder con Exp 2 (Sub-A gain=0.010 + Sub-B sweep).")
            print(f"    Sub-A reduce co2_upper por outflow exterior → amortigua la retención de t120.")
        if no_gap_fracs:
            print(f"  Fracciones sin cierre de gaps: {no_gap_fracs}")
            print(f"  → El mecanismo Sub-B (fracción de exchange) puede ser insuficiente para t480.")
            print(f"    Evaluar si el problema es estructural: frec. de llamada, coeff base, o si")
            print(f"    GasExchangeSystem domina el transporte y SubB solo afecta marginalmente.")
        print()
        print(f"  DECISIÓN: Sub-B aislado descartado. → Exp 2 (combinado Sub-A + Sub-B).")

    print()
    if run_errors:
        print(f"  ⚠ {len(run_errors)} run(s) fallaron: {run_errors[:5]}")
    print("=" * W)
    return 0


if __name__ == "__main__":
    sys.exit(main())
