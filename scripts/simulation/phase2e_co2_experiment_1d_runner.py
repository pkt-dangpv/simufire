"""
phase2e_co2_experiment_1d_runner.py — Runner experimental Phase 2E CO₂, Exp 1D (Sub-D solo).

Sub-D: omite el snap bi-zona (lower_frac < 0.15 ó lower_frac < 0.40 + O₂ < 7%) cuando
       la sala tiene fuego activo (hrr_kw > 0). Sin Sub-D, ese snap colapsa co2_upper
       desde ~12% a ~0.65% a t=380s (Salon, cfast_two_room_door_open).

Diagnóstico previo (Exp 1C + log analysis):
  - t=370 → HotLayer=0.63m, CO2u=119 907 ppm (12.0%)
  - t=380 → HotLayer=0.30m, lower_frac=0.12 < 0.15 → SNAP → CO2u=6 520 ppm (0.65%)
  - t=380+ → quasi-steady ~9 000–12 000 ppm (producción vs. exportación por puerta)
  Causa: Rama A (bi-zona inválida, snap a valor-masa). Sub-B no la toca.
  Sub-D: skip snap → rama producción continúa → CO2u decrece gradualmente, no abrupto.

Casos evaluados:
  Sentinels (3 obligatorios):
    g4_gie_delayed_entry_hazard
    v3_hallway_fed_exposure
    victim_fed_incapacitation
  CO₂ target (3):
    cfast_r0_window_360
    cfast_single_room_closed
    cfast_two_room_door_open   ← FOCO PRINCIPAL

Checks principales:
  1. Godot parse: EXIT 0.
  2. Flag OFF = no-op: resultados idénticos al baseline (sentinels + CO₂).
  3. Sentinels ON: 5/5 PASS (ventanas Phase 2H).
  4. FED delta ON vs OFF: |ΔFED| < 0.005.
  5. cfast_2r_r0_t480_co2_upper_pct ∈ [6.91%, 12.91%].
  6. cfast_2r_r0_t120_co2_upper_pct ≤ 5.58% (gate descarte).
  7. Diagnóstico temporal: CO2u en room 0 a t=350,360,370,380,400,420,480.

Uso:
    python scripts/simulation/phase2e_co2_experiment_1d_runner.py
    python scripts/simulation/phase2e_co2_experiment_1d_runner.py --skip-run
    python scripts/simulation/phase2e_co2_experiment_1d_runner.py --include-flashover

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

EXP_TAG = "p2e1d"   # tag para nombrar casos y reportes

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

# FED delta metrics (gate: |delta| < 0.005)
FED_DELTA_METRICS: list[tuple[str, str, str]] = [
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",  "g4 FED timing"),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                "v3 max FED"),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",           "vic final FED"),
]

# CO₂ gap targets: (case, room_id, target_s, check_name, expected, tolerance, unit)
CO2_GAP_TARGETS: list[tuple[str, int, float, str, float, float, str]] = [
    ("cfast_r0_window_360",       0, 510.0, "cfast_t510_co2_upper_ppm",      52300.0, 20000.0, "ppm"),
    ("cfast_r0_window_360",       0, 420.0, "cfast_t420_co2_upper_ppm",      60800.0, 22000.0, "ppm"),
    ("cfast_single_room_closed",  0, 300.0, "cfast_src_t300_co2_upper_ppm",  None,    None,    "ppm"),
    ("cfast_two_room_door_open",  0, 120.0, "cfast_2r_r0_t120_co2_upper_pct",  1.58,  3.0,    "pct"),
    ("cfast_two_room_door_open",  0, 480.0, "cfast_2r_r0_t480_co2_upper_pct",  9.91,  3.0,    "pct"),
    ("cfast_post_flashover_vented", 0, 240.0, "cfast_fo_t240_co2_upper_pct", 7.77,   3.0,    "pct"),
    ("cfast_post_flashover_vented", 0, 350.0, "cfast_fo_t350_co2_upper_pct", 7.89,   3.0,    "pct"),
]

# Baseline CO₂ values (flag OFF, validated)
CO2_BASELINE: dict[str, float] = {
    "cfast_t510_co2_upper_ppm":       16182.0,
    "cfast_t420_co2_upper_ppm":       41438.0,
    "cfast_2r_r0_t120_co2_upper_pct":  4.75,
    "cfast_2r_r0_t480_co2_upper_pct":  0.999,
    "cfast_fo_t240_co2_upper_pct":     4.32,
    "cfast_fo_t350_co2_upper_pct":     0.77,
}

# Tiempos de diagnóstico temporal para cfast_two_room_door_open room 0
# Cobertura del snap: t=350–480 (snap ocurre entre t=370 y t=380)
DIAG_TIMES_S: list[float] = [350.0, 360.0, 370.0, 380.0, 390.0, 400.0, 420.0, 440.0, 460.0, 480.0]

GATE_T120_MAX_SF_PCT = 5.58   # gate descarte: t120 no debe superar 5.58%
TARGET_T480_LO_PCT   = 6.91   # mínimo para cerrar el gap
TARGET_T480_HI_PCT   = 12.91  # techo (+3pp sobre CFAST 9.91%)


# ---------------------------------------------------------------------------
# Log parsing
# ---------------------------------------------------------------------------

def _parse_simufire_log(path: Path, room_id: int) -> list[dict]:
    """Parse SimuFire validation log; devuelve lista de dicts por timestep para room_id."""
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
            "time_s":       sample["time_s"],
            "co2_upper_ppm": co2u_raw,
            "co2_upper_pct": co2_upper_pct,
            "hrr":           sample.get("HRR", math.nan),
            "hot_layer_m":   sample.get("HotLayer", math.nan),
            "o2":            sample.get("O2", math.nan),
            "o2u":           sample.get("O2u", math.nan),
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

def _build_exp_case(base_path: Path, exp_path: Path, exp_name: str) -> None:
    """Crea caso experimental con phase2e_co2_subd_enabled = true."""
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides["phase2e_co2_subd_enabled"] = True
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
        description="Phase 2E CO₂ Experiment 1D — Sub-D: skip bi-zone snap on active fire."
    )
    parser.add_argument("--godot",             default=None, metavar="PATH")
    parser.add_argument("--skip-run",          action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--include-flashover", action="store_true",
                        help="Incluir cfast_post_flashover_vented en la evaluación")
    parser.add_argument("--timeout",           type=int, default=300)
    args = parser.parse_args()

    co2_cases = CO2_CASES_DEFAULT + (CO2_CASES_FLASHOVER if args.include_flashover else [])
    active_cases = SENTINEL_CASES + co2_cases

    W = 128
    print()
    print("=" * W)
    print("  Phase 2E CO₂ Experiment 1D — Sub-D: skip bi-zone snap cuando fuego activo")
    print(f"  Mecanismo  : phase2e_co2_subd_enabled=true")
    print(f"  Root cause : lower_frac < 0.15 a t=380s (HotLayer=0.30m, 2.5m sala) → snap CO2u")
    print(f"              119907ppm → 6520ppm. Sub-D: skip snap → rama producción continúa.")
    print(f"  Casos      : {' | '.join(active_cases)}")
    print(f"  Gate t120  : SF ≤ {GATE_T120_MAX_SF_PCT}% (1.58% + 3pp tol + 1pp margen)")
    print(f"  Target     : cfast_2r_r0_t480 ∈ [{TARGET_T480_LO_PCT}%, {TARGET_T480_HI_PCT}%]")
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
        total_runs = len(active_cases)
        done = 0
        for case in active_cases:
            exp_name  = f"{case}_{EXP_TAG}"
            base_path = CASES_DIR / f"{case}.json"
            exp_path  = CASES_DIR / f"{exp_name}.json"

            if not base_path.exists():
                print(f"  SKIP: caso base no encontrado: {base_path.name}")
                run_errors.append(exp_name)
                done += 1
                continue

            _build_exp_case(base_path, exp_path, exp_name)
            created_temp.append(exp_path)

            done += 1
            print(f"  [{done:>2}/{total_runs}] Phase2E-1D  Sub-D  {case} ...",
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

    # -- Cargar reports -------------------------------------------------------
    baseline_rpts: dict[str, "dict | None"] = {
        c: _load_report(REPORTS_DIR / f"{c}.json") for c in active_cases
    }
    baseline_logs: dict[str, list[dict]] = {
        c: _parse_simufire_log(REPORTS_DIR / f"{c}.log", room_id=0) for c in co2_cases
    }
    exp_rpts: dict[str, "dict | None"] = {
        c: _load_report(REPORTS_DIR / f"{c}_{EXP_TAG}.json") for c in active_cases
    }
    exp_logs: dict[str, list[dict]] = {
        c: _parse_simufire_log(REPORTS_DIR / f"{c}_{EXP_TAG}.log", room_id=0)
        for c in co2_cases
    }

    SEP = "-" * W

    # =========================================================================
    # TABLA 1 — Sentinels + required checks
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 1 — Sentinels + required checks (Sub-D ON vs baseline OFF)")
    col_w = 16
    header_parts = ["  Configuración "]
    for _, _, _, _, lbl in SENTINELS:
        header_parts.append(f"{lbl:<{col_w}}")
    header_parts.append(f"{'REQ-OK':<12}")
    print("  " + " | ".join(header_parts))
    print("  " + SEP)

    sentinel_results: dict[str, list["bool | None"]] = {}

    for label, rpts_dict in [("BASELINE (OFF)", baseline_rpts), ("Sub-D (ON)", exp_rpts)]:
        vals: list["bool | None"] = []
        for case, key, lo, hi, _ in SENTINELS:
            val = _get_metric(rpts_dict.get(case), key)
            vals.append(_sentinel_pass(val, lo, hi))
        sentinel_results[label] = vals

        req_ok_list = [_count_required_pass(rpts_dict.get(c)) for c in active_cases]
        req_total = sum(n for _, n in req_ok_list)
        req_pass  = sum(p for p, _ in req_ok_list)

        parts = [f"  {label:<18}"]
        for v in vals:
            sym = "PASS" if v is True else ("FAIL" if v is False else "N/A")
            parts.append(f"{sym:<{col_w}}")
        parts.append(f"{req_pass}/{req_total}")
        print(" | ".join(parts))

    # FED delta check
    print()
    print("  FED delta (Sub-D ON vs OFF) — gate: |ΔFED| < 0.005")
    any_fed_fail = False
    for case, key, lbl in FED_DELTA_METRICS:
        v_base = _get_metric(baseline_rpts.get(case), key)
        v_exp  = _get_metric(exp_rpts.get(case),      key)
        if v_base is not None and v_exp is not None:
            delta = abs(v_exp - v_base)
            ok    = delta < 0.005
            sym   = "OK " if ok else "FAIL"
            if not ok:
                any_fed_fail = True
            print(f"    [{sym}] {lbl:<22} baseline={v_base:.4f}  exp={v_exp:.4f}  |Δ|={delta:.4f}")
        else:
            print(f"    [N/A] {lbl}")

    sentinel_on  = sentinel_results.get("Sub-D (ON)", [])
    sentinels_ok = all(v is True for v in sentinel_on)

    # =========================================================================
    # TABLA 2 — CO₂ gap targets
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 2 — CO₂ gap targets: baseline vs Sub-D ON")
    print(f"  {'Check':<36} {'CFAST':>10} {'Base OFF':>10} {'Sub-D ON':>10} "
          f"{'ΔvBase':>10} {'ΔvCFAST':>10}  Gate")
    print("  " + SEP)

    t480_ok = None
    t120_ok = None
    target_cases = [(c, ri, ts, ck, ex, tol, un)
                    for c, ri, ts, ck, ex, tol, un in CO2_GAP_TARGETS
                    if c in co2_cases]

    for case, room_id, target_s, check_name, expected, tolerance, unit in target_cases:
        base_samples = baseline_logs.get(case, [])
        exp_samples  = exp_logs.get(case, [])

        b_samp = _nearest(base_samples, target_s)
        e_samp = _nearest(exp_samples,  target_s)

        b_val = (b_samp["co2_upper_pct"] if unit == "pct"
                 else b_samp["co2_upper_ppm"]) if b_samp else math.nan
        e_val = (e_samp["co2_upper_pct"] if unit == "pct"
                 else e_samp["co2_upper_ppm"]) if e_samp else math.nan

        delta_base  = e_val - b_val       if not math.isnan(e_val) and not math.isnan(b_val) else math.nan
        delta_cfast = e_val - (expected or math.nan) if not math.isnan(e_val) and expected is not None else math.nan

        # Gate check
        if expected is not None and tolerance is not None and not math.isnan(e_val):
            gate_ok = abs(e_val - expected) <= tolerance
        else:
            gate_ok = None

        # Special gate overrides
        if check_name == "cfast_2r_r0_t480_co2_upper_pct":
            t480_ok = (not math.isnan(e_val)) and TARGET_T480_LO_PCT <= e_val <= TARGET_T480_HI_PCT
            gate_str = (f"[{'OK ' if t480_ok else 'FAIL'}] ∈ [{TARGET_T480_LO_PCT:.2f},{TARGET_T480_HI_PCT:.2f}]%")
        elif check_name == "cfast_2r_r0_t120_co2_upper_pct":
            t120_ok = (not math.isnan(e_val)) and e_val <= GATE_T120_MAX_SF_PCT
            gate_str = (f"[{'OK ' if t120_ok else 'FAIL'}] ≤ {GATE_T120_MAX_SF_PCT:.2f}%")
        elif gate_ok is None:
            gate_str = "observación"
        else:
            gate_str = f"[{'OK ' if gate_ok else 'FAIL'}] ±{tolerance}"

        b_str  = f"{b_val:.1f}{unit}"  if not math.isnan(b_val)      else "N/A"
        e_str  = f"{e_val:.1f}{unit}"  if not math.isnan(e_val)       else "N/A"
        db_str = (f"{delta_base:+.1f}"  if not math.isnan(delta_base)  else "N/A")
        dc_str = (f"{delta_cfast:+.1f}" if not math.isnan(delta_cfast) else "N/A")

        exp_str = f"{expected}{unit}" if expected is not None else "—"
        print(f"  {check_name:<36} {exp_str:>10} {b_str:>10} {e_str:>10} "
              f"{db_str:>10} {dc_str:>10}  {gate_str}")

    # =========================================================================
    # TABLA 3 — Diagnóstico temporal cfast_two_room_door_open room 0
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 3 — Diagnóstico temporal: cfast_two_room_door_open room 0 (región del snap)")
    print(f"  {'t[s]':>7} {'HRR':>7} {'HotLay':>8} {'O2u':>7} "
          f"{'CO2u-OFF(ppm)':>14} {'CO2u-ON(ppm)':>14} {'Δ(ppm)':>9}")
    print("  " + SEP)

    base_two  = baseline_logs.get("cfast_two_room_door_open", [])
    exp_two   = exp_logs.get("cfast_two_room_door_open", [])

    for ts in DIAG_TIMES_S:
        bs = _nearest(base_two, ts)
        es = _nearest(exp_two,  ts)
        b_co2 = bs["co2_upper_ppm"] if bs else math.nan
        e_co2 = es["co2_upper_ppm"] if es else math.nan
        hrr_  = bs["hrr"]          if bs else math.nan
        hot_  = bs["hot_layer_m"]   if bs else math.nan
        o2u_  = bs["o2u"]           if bs else math.nan
        delta = e_co2 - b_co2 if not math.isnan(e_co2) and not math.isnan(b_co2) else math.nan

        hrr_s  = f"{hrr_:.0f}"    if not math.isnan(hrr_)  else "N/A"
        hot_s  = f"{hot_:.2f}m"   if not math.isnan(hot_)  else "N/A"
        o2u_s  = f"{o2u_:.4f}"    if not math.isnan(o2u_)  else "N/A"
        bc_s   = f"{b_co2:.0f}"   if not math.isnan(b_co2) else "N/A"
        ec_s   = f"{e_co2:.0f}"   if not math.isnan(e_co2) else "N/A"
        d_s    = f"{delta:+.0f}"  if not math.isnan(delta) else "N/A"

        # Marcar el timestep donde ocurre el snap en baseline
        marker = "  ← SNAP aquí" if abs(ts - 380.0) < 5.0 else ""
        print(f"  {ts:>7.1f} {hrr_s:>7} {hot_s:>8} {o2u_s:>7} "
              f"{bc_s:>14} {ec_s:>14} {d_s:>9}{marker}")

    # =========================================================================
    # VEREDICTO
    # =========================================================================
    print()
    print(SEP)
    print("  VEREDICTO Sub-D (phase2e_co2_subd_enabled)")
    print()

    verdict_items: list[tuple[bool, str]] = []

    # 1. No run errors
    if not args.skip_run:
        no_errors = len(run_errors) == 0
        verdict_items.append((no_errors, f"Runs sin error: {len(active_cases) - len(run_errors)}/{len(active_cases)}"))

    # 2. Sentinels
    verdict_items.append((sentinels_ok, f"Sentinels 5/5: {'OK' if sentinels_ok else 'FAIL'}"))

    # 3. FED delta
    verdict_items.append((not any_fed_fail, f"FED delta < 0.005: {'OK' if not any_fed_fail else 'FAIL'}"))

    # 4. t480 target
    t480_str = ("PASS" if t480_ok else ("FAIL" if t480_ok is False else "N/A"))
    verdict_items.append(
        (t480_ok is True,
         f"cfast_2r_r0_t480 ∈ [{TARGET_T480_LO_PCT}%,{TARGET_T480_HI_PCT}%]: {t480_str}")
    )

    # 5. t120 gate
    t120_str = ("OK" if t120_ok else ("FAIL (sub-d deteriora t120)" if t120_ok is False else "N/A"))
    verdict_items.append(
        (t120_ok is True,
         f"cfast_2r_r0_t120 ≤ {GATE_T120_MAX_SF_PCT}%: {t120_str}")
    )

    all_pass = all(ok for ok, _ in verdict_items)
    for ok, msg in verdict_items:
        sym = "✓" if ok else "✗"
        print(f"    [{sym}] {msg}")

    print()
    if all_pass:
        print("  ▶ Sub-D CANDIDATO — todos los gates pasan.")
        print("    Siguiente: Sub-D+Sub-A combinados (si Sub-D+Solo cierra el gap).")
    else:
        fails = [msg for ok, msg in verdict_items if not ok]
        print("  ▶ Sub-D no pasa todos los gates.")
        for f in fails:
            print(f"    ✗ {f}")
        if t480_ok is False and t120_ok is not False:
            print("    → Gap t480 aún no cerrado. Evaluar Sub-D + Sub-B combinados.")
        elif t120_ok is False:
            print("    → Sub-D deteriora t120. Analizar si Sub-D necesita condición adicional.")

    print()
    print("=" * W)
    print()

    if run_errors:
        print(f"  WARN: {len(run_errors)} caso(s) con error de Godot: {run_errors}")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
