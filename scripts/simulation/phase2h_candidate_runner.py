"""
phase2h_candidate_runner.py — Validación ampliada del candidato Phase 2H.

Candidato: phase2h_lower_replenish_gain = 0.25
  Con flags:
    phase2h_o2_doorway_two_zone_enabled     = true
    phase2h_cold_room_lower_routing_enabled = true   (actualmente no-op en código)
    phase2h_lower_replenish_gain            = 0.25

Metodología:
  Dos configuraciones por caso:
    OFF — flags=false, gain=0.0  (equivalente exacto a producción actual)
    ON  — flags según candidato
  Compara OFF vs ON para cada métrica.

Casos validados (7+1):
  cfast_r0_window_360         HRR, extinction timing, O2 r0 (exterior window, Path A)
  cfast_single_room_closed    CO upper, O2 bulk (sellado, sin Path A/B)
  cfast_hvac_residential      O2l gap closure (Path B HVAC)
  cfast_two_room_door_open    O2 r0/r1, CO upper r1 (doorway interior)
  g4_gie_delayed_entry_hazard sentinel: CO>1200, FED timing
  v3_hallway_fed_exposure     sentinel: FED timing, max FED
  victim_fed_incapacitation   sentinel: vic FED, vic CO

Métricas reportadas:
  - 6 sentinels PASS/FAIL
  - room.o2 invariante (±0.001 para todos los casos)
  - o2_lower snapshots t180/t300/t450 (hvac_residential via log)
  - HRR peak y final, fire time (window360, single_room)
  - victim FED delta
  - CO upper peak (casos sentinel — non-gating gap monitor)
  - o2_lower ≥ room.o2 (ninguna violación)

Restricciones:
  - No modifica tolerancias ni reference_checks.json
  - No rebaseline
  - No activa flags por defecto (solo en experimento temporal)

Nomenclatura de reports:
  {case}_p2hC_off.json   (flag OFF)
  {case}_p2hC_on.json    (flag ON candidato)

Uso:
    python scripts/simulation/phase2h_candidate_runner.py
    python scripts/simulation/phase2h_candidate_runner.py --skip-run
    python scripts/simulation/phase2h_candidate_runner.py --cases cfast_hvac_residential

Código de salida:
    0 — experimento completado (puede haber OBSERVACIONes pero sin error crítico)
    1 — error crítico
"""

import argparse
import json
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
# Candidato
# ---------------------------------------------------------------------------

CANDIDATE_GAIN = 0.25

CANDIDATE_FLAGS_ON: dict = {
    "phase2h_o2_doorway_two_zone_enabled":     True,
    "phase2h_cold_room_lower_routing_enabled": True,
    "phase2h_lower_replenish_gain":            CANDIDATE_GAIN,
}

CANDIDATE_FLAGS_OFF: dict = {
    "phase2h_o2_doorway_two_zone_enabled":     False,
    "phase2h_cold_room_lower_routing_enabled": False,
    "phase2h_lower_replenish_gain":            0.0,
}

# ---------------------------------------------------------------------------
# Casos
# ---------------------------------------------------------------------------

DEFAULT_CASES = [
    "cfast_r0_window_360",
    "cfast_single_room_closed",
    "cfast_hvac_residential",
    "cfast_two_room_door_open",
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
]

# Métricas por caso: (key, label, es_sentinel, es_invariante_o2, es_o2lower)
METRICS: dict[str, list[tuple]] = {
    "cfast_r0_window_360": [
        ("room_0_final_o2",               "r0 final O2        ", False, True,  False),
        ("room_0_peak_hrr_kw",            "r0 peak HRR [kW]   ", False, False, False),
        ("room_0_final_hrr_kw",           "r0 final HRR [kW]  ", False, False, False),
        ("room_0_final_fire_time_s",      "r0 fire time [s]   ", False, False, False),
        ("opening_event_0_time_s",        "opening event 0 [s]", False, False, False),
        ("room_0_peak_co_upper_ppm",      "r0 peak CO upper   ", False, False, False),
        ("room_0_final_hot_layer_m",      "r0 final hot layer ", False, False, False),
    ],
    "cfast_single_room_closed": [
        ("room_0_final_o2",               "r0 final O2        ", False, True,  False),
        ("room_0_final_co_upper_ppm",     "r0 CO upper final  ", False, False, False),
        ("room_0_final_co_ppm",           "r0 CO mixed final  ", False, False, False),
        ("room_0_peak_hrr_kw",            "r0 peak HRR [kW]   ", False, False, False),
    ],
    "cfast_hvac_residential": [
        ("room_0_final_o2",               "r0 final O2        ", False, True,  False),
        # o2_lower snapshots se leen desde log separado
        ("room_0_t180_o2_lower",          "hvac O2l t=180s    ", False, False, True),
        ("room_0_t300_o2_lower",          "hvac O2l t=300s    ", False, False, True),
        ("room_0_t450_o2_lower",          "hvac O2l t=450s    ", False, False, True),
        ("room_0_final_o2_lower",         "hvac O2l final     ", False, False, True),
    ],
    "cfast_two_room_door_open": [
        ("room_0_final_o2",               "r0 final O2        ", False, True,  False),
        ("room_1_final_o2",               "r1 final O2        ", False, True,  False),
        ("room_1_final_co_upper_ppm",     "r1 CO upper final  ", False, False, False),
        ("room_0_peak_hrr_kw",            "r0 peak HRR [kW]   ", False, False, False),
    ],
    "g4_gie_delayed_entry_hazard": [
        ("time_room_1_co_upper_above_1200_s", "g4 CO>1200 [s]  ", True,  False, False),
        ("time_room_1_fed_above_0_1_s",       "g4 FED>0.1 [s]  ", True,  False, False),
        ("room_1_peak_co_upper_ppm",          "g4 peak CO upper", False, False, False),
        ("room_0_final_o2",                   "g4 r0 final O2  ", False, True,  False),
        ("room_1_final_o2",                   "g4 r1 final O2  ", False, True,  False),
    ],
    "v3_hallway_fed_exposure": [
        ("time_room_1_fed_above_0_1_s",   "v3 FED>0.1 [s]     ", True,  False, False),
        ("room_1_max_fed",                "v3 max FED         ", True,  False, False),
        ("room_1_peak_co_upper_ppm",      "v3 peak CO upper   ", False, False, False),
        ("room_0_final_o2",               "v3 r0 final O2     ", False, True,  False),
        ("room_1_final_o2",               "v3 r1 final O2     ", False, True,  False),
    ],
    "victim_fed_incapacitation": [
        ("victim_v0_final_fed",           "vic final FED      ", True,  False, False),
        ("peak_co_ppm_global",            "vic peak CO [ppm]  ", True,  False, False),
        ("room_0_final_o2",               "vic r0 final O2    ", False, True,  False),
    ],
}

# Sentinels: (case, key, lo, hi, label)
SENTINELS = [
    ("g4_gie_delayed_entry_hazard", "time_room_1_co_upper_above_1200_s", 82.333,  92.333,  "g4 CO>1200  "),
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",       187.75,  207.75,  "g4 FED     "),
    ("v3_hallway_fed_exposure",     "time_room_1_fed_above_0_1_s",       222.17,  282.17,  "v3 FED     "),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                    1.0,     None,    "v3 maxFED  "),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",               0.7,     None,    "vic FED    "),
    ("victim_fed_incapacitation",   "peak_co_ppm_global",                1500.0,  None,    "vic CO     "),
]

O2_INVARIANT_TOL = 0.001
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
    for src in (report, report.get("metrics", {}), report.get("threshold_metrics", {})):
        if not isinstance(src, dict):
            continue
        if key in src:
            v = src[key]
            if isinstance(v, (int, float)):
                return float(v)
            if isinstance(v, dict):
                for sub in ("value", "time_s"):
                    if sub in v:
                        return float(v[sub])
    return None


def _run_case(godot: Path, case_name: str, timeout_s: int = 600) -> bool:
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--",
           f"--validation-case={case_name}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode == 0
    except Exception:
        return False


def _build_exp_case(base_path: Path, exp_path: Path, flags: dict,
                    log_tag: "str | None" = None) -> None:
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides.update(flags)
    if log_tag:
        log_name = f"p2hC_{log_tag}_{base_path.stem}.log"
        overrides["enable_logging"] = True
        overrides["log_file_path"]  = f"res://sim/validation/reports/{log_name}"
    case_data["engine_overrides"] = overrides
    exp_path.write_text(
        json.dumps(case_data, indent="\t", ensure_ascii=False),
        encoding="utf-8"
    )


def _fmt_val(v: "float | None", w: int = 12) -> str:
    if v is None:
        return f"{'n/a':>{w}}"
    return f"{v:>{w}.4f}"


def _fmt_delta(base: "float | None", exp: "float | None", w: int = 18) -> str:
    if base is None or exp is None:
        return f"{'n/a':>{w}}"
    d = exp - base
    pct = (d / abs(base) * 100.0) if abs(base) > 1e-9 else 0.0
    sign = "+" if d >= 0 else ""
    s = f"{sign}{d:.4f} ({sign}{pct:.1f}%)"
    return f"{s:>{w}}"


def _sentinel_ok(case: str, key: str, val: "float | None") -> "bool | None":
    if val is None:
        return None
    for (sc, sk, lo, hi, _) in SENTINELS:
        if sc == case and sk == key:
            if lo is not None and val < lo:
                return False
            if hi is not None and val > hi:
                return False
            return True
    return None


def _parse_o2l_from_log(log_path: Path) -> dict:
    """Lee un log de simulación y extrae O2l de ROOM 0 en t=[180,300,450,final]."""
    if not log_path.exists():
        return {}
    targets = {180, 300, 450}
    content = log_path.read_text(encoding="utf-8", errors="ignore")
    results: dict = {}
    current_t: "int | None" = None
    last_o2l: "float | None" = None
    last_t:   "int | None"   = None
    for line in content.splitlines():
        tm = re.match(r"TIME=([0-9.]+)\s", line)
        if tm:
            current_t = int(float(tm.group(1)))
        elif current_t is not None and "ROOM 0" in line and "O2l=" in line:
            m = re.search(r"O2l=([0-9.]+)", line)
            if m:
                o2l = float(m.group(1))
                if current_t in targets:
                    results[current_t] = o2l
                last_o2l = o2l
                last_t   = current_t
    if last_o2l is not None:
        results["final"] = last_o2l
    return results


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2H candidate validation (gain=0.25)."
    )
    parser.add_argument("--godot",    default=None, metavar="PATH")
    parser.add_argument("--skip-run", action="store_true",
                        help="No ejecutar Godot; usar reports ya existentes.")
    parser.add_argument("--cases",    nargs="+", default=DEFAULT_CASES,
                        help="Subconjunto de casos (default: todos).")
    parser.add_argument("--timeout",  type=int, default=600)
    args = parser.parse_args()

    cases = [c for c in args.cases if c in DEFAULT_CASES]
    if not cases:
        print("ERROR: no hay casos válidos.")
        return 1

    W = 100
    print()
    print("=" * W)
    print("  Phase 2H — Validación candidato (gain=0.25)")
    print(f"  Candidato : o2_doorway_two_zone=ON, cold_room_routing=ON, gain=0.25")
    print(f"  Baseline  : todos los flags=OFF, gain=0.0")
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

    CONFIGS = [
        ("off", CANDIDATE_FLAGS_OFF),
        ("on",  CANDIDATE_FLAGS_ON),
    ]

    if not args.skip_run:
        print()
        total_runs = len(cases) * len(CONFIGS)
        done = 0
        for case in cases:
            base_path = CASES_DIR / f"{case}.json"
            if not base_path.exists():
                print(f"  SKIP: caso base no encontrado: {base_path.name}")
                continue
            for cfg_tag, cfg_flags in CONFIGS:
                exp_name = f"{case}_p2hC_{cfg_tag}"
                exp_path = CASES_DIR / f"{exp_name}.json"
                # Activar logging solo para hvac_residential (para O2l parse)
                log_tag = cfg_tag if case == "cfast_hvac_residential" else None
                _build_exp_case(base_path, exp_path, cfg_flags, log_tag=log_tag)
                created_temp.append(exp_path)
                done += 1
                print(f"  [{done:>2}/{total_runs}] {cfg_tag.upper():<4}  {case} ...",
                      end=" ", flush=True)
                ok = _run_case(godot, exp_name, timeout_s=args.timeout)
                print("OK" if ok else "FAIL")
                if not ok:
                    run_errors.append(f"{cfg_tag.upper()} / {case}")

    # -- Limpiar temporales ---------------------------------------------------
    for p in created_temp:
        try:
            p.unlink()
        except Exception:
            pass
    created_temp.clear()

    # -- Cargar reports -------------------------------------------------------
    baseline_rpts: dict[str, "dict | None"] = {}
    off_rpts:      dict[str, "dict | None"] = {}
    on_rpts:       dict[str, "dict | None"] = {}

    for case in cases:
        baseline_rpts[case] = _load_report(REPORTS_DIR / f"{case}.json")
        off_rpts[case]      = _load_report(REPORTS_DIR / f"{case}_p2hC_off.json")
        on_rpts[case]       = _load_report(REPORTS_DIR / f"{case}_p2hC_on.json")

    # O2l logs para hvac_residential
    o2l_off_log = _parse_o2l_from_log(
        REPORTS_DIR / "p2hC_off_cfast_hvac_residential.log")
    o2l_on_log  = _parse_o2l_from_log(
        REPORTS_DIR / "p2hC_on_cfast_hvac_residential.log")

    # -- Sentinel table -------------------------------------------------------
    print()
    print("-" * W)
    print("  SENTINELS — flag OFF vs ON (candidato g=0.25)")
    w_lbl = 14
    w_val = 14
    hdr = (f"  {'Sentinel':<{w_lbl}}  "
           f"{'Ventana':>18}  "
           f"{'OFF (run)':>{w_val}}  "
           f"{'ON (candidato)':>{w_val}}  "
           f"{'Δ':>10}  "
           f"{'PASS?':>6}")
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))

    sentinel_failures: list[str] = []
    for (sc, sk, lo, hi, lbl) in SENTINELS:
        if sc not in cases:
            continue
        off_v = _get_metric(off_rpts.get(sc), sk)
        on_v  = _get_metric(on_rpts.get(sc), sk)

        # Ventana
        lo_s = f"{lo:.3f}" if lo is not None else "-∞"
        hi_s = f"{hi:.3f}" if hi is not None else "+∞"
        window = f"[{lo_s}, {hi_s}]"

        ok_off = _sentinel_ok(sc, sk, off_v)
        ok_on  = _sentinel_ok(sc, sk, on_v)

        off_s = (_fmt_val(off_v, w_val).rstrip() + (" ✅" if ok_off else " ❌"))
        on_s  = (_fmt_val(on_v,  w_val).rstrip() + (" ✅" if ok_on  else " ❌"))
        d_s   = _fmt_delta(off_v, on_v, 10)

        if ok_on is False:
            sentinel_failures.append(lbl.strip())

        print(f"  {lbl:<{w_lbl}}  {window:>18}  {off_s:>{w_val+2}}  {on_s:>{w_val+2}}  "
              f"{d_s:>10}  {'❌ FAIL' if ok_on is False else '✅ PASS'}")

    # -- Invariante room.o2 ---------------------------------------------------
    print()
    print("  INVARIANTE room.o2 (OFF vs ON, tol ±0.001)")
    print(f"  {'Caso':<35}  {'OFF':>10}  {'ON':>10}  {'|Δ|':>10}  {'OK?':>5}")
    print("  " + "-" * 70)

    o2_violations: list[str] = []
    for case in cases:
        for key in ("room_0_final_o2", "room_1_final_o2"):
            off_v = _get_metric(off_rpts.get(case), key)
            on_v  = _get_metric(on_rpts.get(case), key)
            if off_v is None or on_v is None:
                continue
            delta = abs(on_v - off_v)
            ok    = delta <= O2_INVARIANT_TOL
            label = f"{case} [{key.replace('room_', 'r').replace('_final_o2', '')}]"
            if not ok:
                o2_violations.append(label)
            print(f"  {label:<35}  {off_v:>10.4f}  {on_v:>10.4f}  {delta:>10.4f}  "
                  f"{'✅' if ok else '❌'}")

    # -- O2l gap closure (hvac_residential) -----------------------------------
    if "cfast_hvac_residential" in cases:
        print()
        print("  O2l GAP CLOSURE — cfast_hvac_residential (desde logs)")
        print("  CFAST ref: t=180s≈0.2049  t=300s≈0.2049  t=450s≈0.2049")
        print(f"  {'Tiempo':<10}  {'OFF O2l':>10}  {'ON O2l':>10}  {'Δ':>10}  {'O2l≥O2?':>8}")
        print("  " + "-" * 55)
        CFAST_REF = {180: 0.2049, 300: 0.2049, 450: 0.2049}
        o2l_inv_violations: list[str] = []
        for t_key, t_label in [(180, "t=180s"), (300, "t=300s"), (450, "t=450s"), ("final", "final")]:
            off_o2l = o2l_off_log.get(t_key)
            on_o2l  = o2l_on_log.get(t_key)
            # Verificar o2l >= o2 bulk usando report
            off_o2  = _get_metric(off_rpts.get("cfast_hvac_residential"), "room_0_final_o2")
            on_o2   = _get_metric(on_rpts.get("cfast_hvac_residential"),  "room_0_final_o2")
            o2l_inv_ok = True
            if t_key == "final":
                if on_o2l is not None and on_o2 is not None and on_o2l < on_o2 - 0.001:
                    o2l_inv_ok = False
                    o2l_inv_violations.append(f"O2l({t_label})={on_o2l:.4f} < O2={on_o2:.4f}")
            off_s = f"{off_o2l:.4f}" if off_o2l is not None else "  n/a"
            on_s  = f"{on_o2l:.4f}"  if on_o2l  is not None else "  n/a"
            d     = (on_o2l - off_o2l) if (off_o2l is not None and on_o2l is not None) else None
            d_s   = f"{d:+.4f}" if d is not None else "   n/a"
            inv_s = "✅" if o2l_inv_ok else "❌"
            print(f"  {t_label:<10}  {off_s:>10}  {on_s:>10}  {d_s:>10}  {inv_s:>8}")
        if o2l_inv_violations:
            print(f"\n  ❌ VIOLACIÓN o2_lower < room.o2: {o2l_inv_violations}")

    # -- Tabla detallada (HRR, extinction, CO) --------------------------------
    print()
    print("-" * W)
    print("  TABLA DETALLADA — métricas por caso")
    print(f"  {'Caso / Métrica':<40}  {'OFF':>12}  {'ON':>12}  {'Δ (ON-OFF)':>20}  {'Nota':>8}")
    print("  " + "-" * (W - 2))

    for case in cases:
        mets = METRICS.get(case, [])
        if not mets:
            continue
        print(f"\n  [{case}]")
        for (key, lbl, is_sentinel, is_inv, is_o2l) in mets:
            if is_o2l:
                continue  # ya reportado en sección O2l
            off_v = _get_metric(off_rpts.get(case), key)
            on_v  = _get_metric(on_rpts.get(case),  key)
            note  = "[*]" if is_sentinel else ("[I]" if is_inv else "   ")
            off_s = _fmt_val(off_v, 12)
            on_s  = _fmt_val(on_v,  12)
            d_s   = _fmt_delta(off_v, on_v, 20)
            print(f"    {lbl:<38}  {off_s}  {on_s}  {d_s}  {note}")

    # -- Victim FED delta -----------------------------------------------------
    print()
    print("  VICTIM FED — seguridad (ON no puede superar OFF + 0.005)")
    vic_off = _get_metric(off_rpts.get("victim_fed_incapacitation"), "victim_v0_final_fed")
    vic_on  = _get_metric(on_rpts.get("victim_fed_incapacitation"),  "victim_v0_final_fed")
    vic_base = _get_metric(baseline_rpts.get("victim_fed_incapacitation"), "victim_v0_final_fed")
    if vic_off is not None and vic_on is not None:
        fed_delta = vic_on - vic_off
        fed_ok    = fed_delta <= VIC_FED_MAX_DELTA
        print(f"  OFF={vic_off:.6f}  ON={vic_on:.6f}  Δ={fed_delta:+.6f}  "
              f"baseline={vic_base:.6f}  {'✅ OK' if fed_ok else '❌ EXCEDE LÍMITE'}")
    else:
        print("  (datos no disponibles)")
        fed_ok = True

    # -- Resumen errores de ejecución -----------------------------------------
    if run_errors:
        print()
        print("  ⚠  ERRORES DE EJECUCIÓN:")
        for e in run_errors:
            print(f"    - {e}")

    # -- Resumen final --------------------------------------------------------
    print()
    print("=" * W)
    all_sentinels_ok = len(sentinel_failures) == 0
    all_o2_ok        = len(o2_violations)    == 0
    fed_ok_final     = fed_ok if (vic_off is not None and vic_on is not None) else True

    status_s = "✅ PASS" if all_sentinels_ok else f"❌ FAIL — {sentinel_failures}"
    o2_s     = "✅ OK"   if all_o2_ok        else f"❌ VIOLACIONES: {o2_violations}"
    fed_s    = "✅ OK"   if fed_ok_final     else "❌ FED victim excede baseline+0.005"

    print(f"  Sentinels (6)    : {status_s}")
    print(f"  room.o2 invar.   : {o2_s}")
    print(f"  vic FED delta    : {fed_s}")
    print()
    all_ok = all_sentinels_ok and all_o2_ok and fed_ok_final and not run_errors
    if all_ok:
        print(f"  ✅ CANDIDATO VÁLIDO — gain=0.25 seguro para opt-in.")
        print(f"  Recomendación: promover como preset opt-in, flag OFF por defecto.")
    else:
        print(f"  ⚠  Revisar fallos antes de promover el candidato.")
    print("=" * W)
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
