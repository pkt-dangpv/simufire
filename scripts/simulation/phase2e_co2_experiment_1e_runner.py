"""
phase2e_co2_experiment_1e_runner.py — Runner experimental Phase 2E CO₂, Exp 1E (Sub-D + Sub-A).

Sub-D (phase2e_co2_subd_enabled): omite snap bi-zona cuando sala tiene fuego activo.
Sub-A (phase2e_co2_suba_enabled + phase2e_co2_upper_outflow_gain):
  Reemplaza la dilución masiva de co2_upper por inflow de aire exterior (baseline)
  con un outflow selectivo de la capa alta proporcional a upper_outlet_height_m.
  Con gain=0: sin remoción y sin dilución (máxima retención).
  Con gain>0: remoción parcial vía outflow × gain.

Diagnóstico previo (Exp 1D):
  - Sub-D solo → cfast_t510 FAIL: Sub-D ON=25047ppm vs CFAST=52300ppm (Δ=-27253, fuera de ±20000)
  - Causa: ventana exterior en cfast_r0_window_360 se abre a t=360 → dilución masiva baseline
            destruye co2_upper incluso con Sub-D (Sub-D no toca _step_outside_opening_o2).
  - Sub-A: elimina esa dilución masiva → outflow controlado → co2_upper retiene más CO₂.

Modos evaluados (Sub-D=true para todos):
  base   : Sub-D=false, Sub-A=false — resultados pre-computados (carga de Exp 1D o baseline)
  subd   : Sub-D=true,  Sub-A=false — resultados de Exp 1D (_p2e1d.json)
  a05    : Sub-D=true, Sub-A=true, gain=0.50 → tag p2e1e_a05
  a10    : Sub-D=true, Sub-A=true, gain=1.00 → tag p2e1e_a10
  a20    : Sub-D=true, Sub-A=true, gain=2.00 → tag p2e1e_a20

Casos evaluados:
  Sentinels (3 obligatorios):
    g4_gie_delayed_entry_hazard
    v3_hallway_fed_exposure
    victim_fed_incapacitation
  CO₂ target (3):
    cfast_r0_window_360          ← FOCO PRINCIPAL (Sub-A controla dilución ventana)
    cfast_single_room_closed
    cfast_two_room_door_open

Uso:
    python scripts/simulation/phase2e_co2_experiment_1e_runner.py
    python scripts/simulation/phase2e_co2_experiment_1e_runner.py --skip-run
    python scripts/simulation/phase2e_co2_experiment_1e_runner.py --gains 0.5 1.0 2.0

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

SENTINEL_CASES = [
    "g4_gie_delayed_entry_hazard",
    "v3_hallway_fed_exposure",
    "victim_fed_incapacitation",
]

CO2_CASES = [
    "cfast_r0_window_360",         # FOCO: Sub-A controla dilución por ventana exterior
    "cfast_single_room_closed",
    "cfast_two_room_door_open",
]

SENTINELS: list[tuple[str, str, "float | None", "float | None", str]] = [
    ("g4_gie_delayed_entry_hazard", "time_room_1_co_upper_above_1200_s", 82.333,  92.333,  "g4 CO>1200"),
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",       187.75,  207.75,  "g4 FED"),
    ("v3_hallway_fed_exposure",     "time_room_1_fed_above_0_1_s",       222.17,  282.17,  "v3 FED"),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                    1.0,     None,    "v3 maxFED"),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",               0.7,     None,    "vic FED"),
]

FED_DELTA_METRICS: list[tuple[str, str, str]] = [
    ("g4_gie_delayed_entry_hazard", "time_room_1_fed_above_0_1_s",  "g4 FED timing"),
    ("v3_hallway_fed_exposure",     "room_1_max_fed",                "v3 max FED"),
    ("victim_fed_incapacitation",   "victim_v0_final_fed",           "vic final FED"),
]

# CO₂ gap targets: (case, room_id, target_s, check_name, expected, tolerance, unit)
CO2_GAP_TARGETS: list[tuple[str, int, float, str, float, float, str]] = [
    ("cfast_r0_window_360",       0, 510.0, "cfast_t510_co2_upper_ppm",         52300.0, 20000.0, "ppm"),
    ("cfast_r0_window_360",       0, 420.0, "cfast_t420_co2_upper_ppm",         60800.0, 22000.0, "ppm"),
    ("cfast_two_room_door_open",  0, 120.0, "cfast_2r_r0_t120_co2_upper_pct",    1.58,    3.0,   "pct"),
    ("cfast_two_room_door_open",  0, 480.0, "cfast_2r_r0_t480_co2_upper_pct",    9.91,    3.0,   "pct"),
]

# Gate explícita para t480 (verificar no exceso por Sub-A)
GATE_T120_MAX_SF_PCT = 5.58
TARGET_T480_LO_PCT   = 6.91
TARGET_T480_HI_PCT   = 12.91

# Gain sweep por defecto
DEFAULT_GAINS: list[float] = [0.5, 1.0, 2.0]

# Tag para Sub-D solo (Exp 1D)
SUBD_TAG = "p2e1d"

# Tag base para Sub-A variants
EXP_BASE_TAG = "p2e1e"


def _gain_tag(gain: float) -> str:
    """Devuelve tag de caso para un gain dado, e.g. 0.5 → 'a05', 1.0 → 'a10'."""
    return f"a{int(round(gain * 10)):02d}"


# ---------------------------------------------------------------------------
# Log parsing
# ---------------------------------------------------------------------------

def _parse_simufire_log(path: Path, room_id: int) -> list[dict]:
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
        samples.append({
            "time_s":        sample["time_s"],
            "co2_upper_ppm": co2u_raw,
            "co2_upper_pct": co2u_raw / 10000.0 if not math.isnan(co2u_raw) else math.nan,
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
# Report helpers
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

def _build_exp_case(base_path: Path, exp_path: Path, exp_name: str,
                    subd: bool, suba: bool, gain: float) -> None:
    """Crea caso experimental con los flags Sub-D y Sub-A indicados."""
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides["phase2e_co2_subd_enabled"]      = subd
    overrides["phase2e_co2_suba_enabled"]       = suba
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
        description="Phase 2E CO₂ Experiment 1E — Sub-D + Sub-A: evitar dilución masiva por ventana exterior."
    )
    parser.add_argument("--godot",    default=None, metavar="PATH")
    parser.add_argument("--skip-run", action="store_true",
                        help="No ejecutar Godot; comparar reports ya existentes")
    parser.add_argument("--gains",    type=float, nargs="+", default=DEFAULT_GAINS,
                        metavar="G", help="Gain values para Sub-A (default: 0.5 1.0 2.0)")
    parser.add_argument("--timeout",  type=int, default=300)
    args = parser.parse_args()

    gains: list[float] = args.gains
    active_cases = SENTINEL_CASES + CO2_CASES

    W = 140
    SEP = "-" * W
    print()
    print("=" * W)
    print("  Phase 2E CO₂ Experiment 1E — Sub-D + Sub-A combined")
    print(f"  Sub-A mecanismo: outflow selectivo capa alta (reemplaza dilución masiva baseline)")
    print(f"  Gain sweep     : {gains}")
    print(f"  Gap objetivo   : cfast_t510 CFAST=52300ppm, SubD-solo=25047ppm → cerrar con Sub-A")
    print(f"  Casos          : {' | '.join(active_cases)}")
    print("=" * W)

    # -- Godot ----------------------------------------------------------------
    godot = None
    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("\n  ERROR: no se encontró Godot. Define --godot PATH o GODOT_EXE.\n")
            return 1
        print(f"\n  Godot: {godot}")

    # -- Ejecutar casos nuevos (Sub-D + Sub-A gain variants) ------------------
    created_temp: list[Path] = []
    run_errors: dict[str, list[str]] = {}   # gain_tag → lista de casos fallidos

    if not args.skip_run:
        print()
        total_runs = len(gains) * len(active_cases)
        done = 0

        for gain in gains:
            gtag = _gain_tag(gain)
            run_errors[gtag] = []

            for case in active_cases:
                exp_name  = f"{case}_{EXP_BASE_TAG}_{gtag}"
                base_path = CASES_DIR / f"{case}.json"
                exp_path  = CASES_DIR / f"{exp_name}.json"

                if not base_path.exists():
                    print(f"  SKIP: {base_path.name} no encontrado")
                    run_errors[gtag].append(case)
                    done += 1
                    continue

                _build_exp_case(base_path, exp_path, exp_name,
                                subd=True, suba=True, gain=gain)
                created_temp.append(exp_path)

                done += 1
                print(f"  [{done:>3}/{total_runs}]  SubD+SubA gain={gain:.2f}  {case} ...",
                      end=" ", flush=True)
                ok = _run_case(godot, exp_name, timeout_s=args.timeout)
                print("OK" if ok else "FAIL")
                if not ok:
                    run_errors[gtag].append(case)

    # Limpiar temporales
    for p in created_temp:
        try:
            p.unlink()
        except Exception:
            pass
    created_temp.clear()

    # -- Cargar reports -------------------------------------------------------
    # Baseline (flag OFF)
    base_rpts: dict[str, "dict | None"] = {
        c: _load_report(REPORTS_DIR / f"{c}.json") for c in active_cases
    }
    base_logs: dict[str, list[dict]] = {
        c: _parse_simufire_log(REPORTS_DIR / f"{c}.log", room_id=0) for c in CO2_CASES
    }

    # Sub-D solo (Exp 1D)
    subd_rpts: dict[str, "dict | None"] = {
        c: _load_report(REPORTS_DIR / f"{c}_{SUBD_TAG}.json") for c in active_cases
    }
    subd_logs: dict[str, list[dict]] = {
        c: _parse_simufire_log(REPORTS_DIR / f"{c}_{SUBD_TAG}.log", room_id=0) for c in CO2_CASES
    }

    # Sub-D + Sub-A per gain
    gain_rpts: dict[str, dict[str, "dict | None"]] = {}
    gain_logs: dict[str, dict[str, list[dict]]]    = {}
    for gain in gains:
        gtag = _gain_tag(gain)
        gain_rpts[gtag] = {
            c: _load_report(REPORTS_DIR / f"{c}_{EXP_BASE_TAG}_{gtag}.json")
            for c in active_cases
        }
        gain_logs[gtag] = {
            c: _parse_simufire_log(REPORTS_DIR / f"{c}_{EXP_BASE_TAG}_{gtag}.log", room_id=0)
            for c in CO2_CASES
        }

    # =========================================================================
    # TABLA 1 — Sentinels por modo
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 1 — Sentinels (5/5 PASS requerido para todos los modos)")
    col_w = 14

    # Build header
    labels_modes = [("Baseline", base_rpts), ("Sub-D", subd_rpts)] + [
        (f"SubD+A{gain:.1f}", gain_rpts[_gain_tag(gain)]) for gain in gains
    ]
    hdr = f"  {'Modo':<22}"
    for _, _, _, _, lbl in SENTINELS:
        hdr += f" {lbl:<{col_w}}"
    hdr += f" {'OK?':<8}"
    print(hdr)
    print("  " + SEP)

    sentinels_ok_per_mode: dict[str, bool] = {}

    for mode_label, rpts_dict in labels_modes:
        row = f"  {mode_label:<22}"
        all_ok = True
        for case, key, lo, hi, _ in SENTINELS:
            val  = _get_metric(rpts_dict.get(case), key)
            ok   = _sentinel_pass(val, lo, hi)
            sym  = "PASS" if ok is True else ("FAIL" if ok is False else "N/A")
            if ok is not True:
                all_ok = False
            row += f" {sym:<{col_w}}"
        row += f" {'OK' if all_ok else 'FAIL':<8}"
        print(row)
        sentinels_ok_per_mode[mode_label] = all_ok

    # FED delta vs baseline
    print()
    print("  FED delta vs BASELINE — gate: |ΔFED| < 0.005 para cada modo")
    fed_ok_per_mode: dict[str, bool] = {}
    for mode_label, rpts_dict in labels_modes[1:]:   # skip baseline itself
        any_fail = False
        parts = [f"    [{mode_label}]"]
        for case, key, lbl in FED_DELTA_METRICS:
            v_base = _get_metric(base_rpts.get(case), key)
            v_exp  = _get_metric(rpts_dict.get(case), key)
            if v_base is not None and v_exp is not None:
                delta = abs(v_exp - v_base)
                ok    = delta < 0.005
                if not ok:
                    any_fail = True
                parts.append(f"{lbl}|Δ|={delta:.4f}({'OK' if ok else 'FAIL'})")
            else:
                parts.append(f"{lbl}=N/A")
        fed_ok_per_mode[mode_label] = not any_fail
        print("  " + "  ".join(parts))

    # =========================================================================
    # TABLA 2 — CO₂ gap targets multi-modo
    # =========================================================================
    print()
    print(SEP)
    print("  TABLA 2 — CO₂ gap targets (todos los modos)")
    val_w = 10
    # Column headers: Check | CFAST | Base | SubD | SubD+A(g) ...
    col_heads = ["CFAST", "Base"] + [f"SubD(1D)"] + [f"SubD+A{g:.1f}" for g in gains]
    hdr2 = f"  {'Check':<36}"
    for ch in col_heads:
        hdr2 += f" {ch:>{val_w}}"
    hdr2 += "  Gate"
    print(hdr2)
    print("  " + SEP)

    # Results per mode per check
    # Structure: {check_name: {mode_label: value}}
    check_vals: dict[str, dict[str, float]] = {}

    for case, room_id, target_s, check_name, expected, tolerance, unit in CO2_GAP_TARGETS:
        if case not in CO2_CASES:
            continue
        check_vals.setdefault(check_name, {})

        b_samp   = _nearest(base_logs.get(case, []), target_s)
        sd_samp  = _nearest(subd_logs.get(case, []), target_s)

        def _extract(samp: "dict | None") -> float:
            if samp is None:
                return math.nan
            return samp["co2_upper_pct"] if unit == "pct" else samp["co2_upper_ppm"]

        check_vals[check_name]["Base"]   = _extract(b_samp)
        check_vals[check_name]["Sub-D"]  = _extract(sd_samp)

        for gain in gains:
            gtag = _gain_tag(gain)
            g_samp = _nearest(gain_logs[gtag].get(case, []), target_s)
            check_vals[check_name][f"SubD+A{gain:.1f}"] = _extract(g_samp)

    # Gate check helpers
    def _gate_t480(v: float) -> "bool | None":
        if math.isnan(v):
            return None
        return TARGET_T480_LO_PCT <= v <= TARGET_T480_HI_PCT

    def _gate_t120(v: float) -> "bool | None":
        if math.isnan(v):
            return None
        return v <= GATE_T120_MAX_SF_PCT

    def _gate_abs(v: float, expected: float, tol: float) -> "bool | None":
        if math.isnan(v):
            return None
        return abs(v - expected) <= tol

    for case, room_id, target_s, check_name, expected, tolerance, unit in CO2_GAP_TARGETS:
        if case not in CO2_CASES:
            continue
        vals = check_vals.get(check_name, {})

        # Determinar gate para cada valor de Sub-D+Sub-A
        if check_name == "cfast_2r_r0_t480_co2_upper_pct":
            gate_fn = _gate_t480
            gate_desc = f"∈[{TARGET_T480_LO_PCT:.2f},{TARGET_T480_HI_PCT:.2f}]%"
        elif check_name == "cfast_2r_r0_t120_co2_upper_pct":
            gate_fn = _gate_t120
            gate_desc = f"≤{GATE_T120_MAX_SF_PCT:.2f}%"
        else:
            gate_fn = lambda v: _gate_abs(v, expected, tolerance)  # noqa: E731
            gate_desc = f"±{tolerance:.0f}{unit}"

        row = f"  {check_name:<36}"
        exp_str = f"{expected}{unit}" if expected is not None else "—"
        row += f" {exp_str:>{val_w}}"
        for mode_key in ["Base", "Sub-D"] + [f"SubD+A{g:.1f}" for g in gains]:
            v = vals.get(mode_key, math.nan)
            s = f"{v:.1f}{unit}" if not math.isnan(v) else "N/A"
            row += f" {s:>{val_w}}"

        # Gate marker solo para el primer Sub-A gain que pasa (para orientación)
        gate_parts: list[str] = []
        for mode_key in ["Sub-D"] + [f"SubD+A{g:.1f}" for g in gains]:
            v = vals.get(mode_key, math.nan)
            ok = gate_fn(v)
            sym = "✓" if ok is True else ("✗" if ok is False else "?")
            gate_parts.append(f"{mode_key.replace('SubD+A', 'A')}:{sym}")

        row += f"  [{gate_desc}]  " + "  ".join(gate_parts)
        print(row)

    # =========================================================================
    # VEREDICTO por gain
    # =========================================================================
    print()
    print(SEP)
    print("  VEREDICTO por modo")
    print()

    candidatos: list[str] = []

    for gain in gains:
        gtag    = _gain_tag(gain)
        mlabel  = f"SubD+A{gain:.1f}"
        rpts    = gain_rpts[gtag]

        s_ok    = sentinels_ok_per_mode.get(mlabel, False)
        fed_ok  = fed_ok_per_mode.get(mlabel, False)

        # Gate t480
        t480_v  = check_vals.get("cfast_2r_r0_t480_co2_upper_pct", {}).get(mlabel, math.nan)
        t480_ok = _gate_t480(t480_v)

        # Gate t120
        t120_v  = check_vals.get("cfast_2r_r0_t120_co2_upper_pct", {}).get(mlabel, math.nan)
        t120_ok = _gate_t120(t120_v)

        # Gate t510
        t510_v  = check_vals.get("cfast_t510_co2_upper_ppm", {}).get(mlabel, math.nan)
        t510_ok = _gate_abs(t510_v, 52300.0, 20000.0)

        # Gate t420
        t420_v  = check_vals.get("cfast_t420_co2_upper_ppm", {}).get(mlabel, math.nan)
        t420_ok = _gate_abs(t420_v, 60800.0, 22000.0)

        all_ok = all([s_ok, fed_ok, t480_ok is True, t120_ok is True,
                      t510_ok is True, t420_ok is True])

        icon = "▶" if all_ok else " "
        status = "CANDIDATO — todos los gates pasan." if all_ok else "FALLA algún gate."

        print(f"  {icon} SubD + SubA gain={gain:.2f}")
        print(f"      Sentinels 5/5 : {'OK' if s_ok else 'FAIL'}")
        print(f"      FED delta     : {'OK' if fed_ok else 'FAIL'}")
        t480_s = f"{t480_v:.2f}%" if not math.isnan(t480_v) else "N/A"
        t120_s = f"{t120_v:.2f}%" if not math.isnan(t120_v) else "N/A"
        t510_s = f"{t510_v:.0f}ppm" if not math.isnan(t510_v) else "N/A"
        t420_s = f"{t420_v:.0f}ppm" if not math.isnan(t420_v) else "N/A"
        print(f"      t480 ∈[{TARGET_T480_LO_PCT:.2f},{TARGET_T480_HI_PCT:.2f}]%: "
              f"{t480_s} → {'PASS' if t480_ok is True else 'FAIL'}")
        print(f"      t120 ≤{GATE_T120_MAX_SF_PCT:.2f}%   : "
              f"{t120_s} → {'OK' if t120_ok is True else 'FAIL'}")
        print(f"      t510 ±20000ppm: {t510_s} → {'PASS' if t510_ok is True else 'FAIL'}")
        print(f"      t420 ±22000ppm: {t420_s} → {'OK' if t420_ok is True else 'FAIL'}")
        print(f"      VEREDICTO     : {status}")
        print()

        if all_ok:
            candidatos.append(f"gain={gain:.2f}")

    print(SEP)
    if candidatos:
        print(f"  ✓ CANDIDATOS: {', '.join(candidatos)}")
        print(f"    Siguiente: promover Sub-D + Sub-A (gain óptimo) a producción.")
    else:
        # Diagnóstico de por qué falló cada check
        print("  ✗ Ningún gain pasa todos los gates.")
        print()
        print("  Diagnóstico:")
        for gain in gains:
            mlabel = f"SubD+A{gain:.1f}"
            t510_v = check_vals.get("cfast_t510_co2_upper_ppm", {}).get(mlabel, math.nan)
            t420_v = check_vals.get("cfast_t420_co2_upper_ppm", {}).get(mlabel, math.nan)
            t510_delta = t510_v - 52300.0 if not math.isnan(t510_v) else math.nan
            t420_delta = t420_v - 60800.0 if not math.isnan(t420_v) else math.nan
            print(f"    gain={gain:.2f}:  t510_Δ={t510_delta:+.0f}ppm  t420_Δ={t420_delta:+.0f}ppm")
        print()
        t510_subd = check_vals.get("cfast_t510_co2_upper_ppm", {}).get("Sub-D", math.nan)
        t510_base = check_vals.get("cfast_t510_co2_upper_ppm", {}).get("Base", math.nan)
        if not math.isnan(t510_subd) and not math.isnan(t510_base):
            print(f"  Referencia: Sub-D solo t510={t510_subd:.0f}ppm  Baseline={t510_base:.0f}ppm")
            best_gain_t510 = [g for g in gains
                              if not math.isnan(check_vals.get("cfast_t510_co2_upper_ppm", {}).get(f"SubD+A{g:.1f}", math.nan))
                              and abs(check_vals["cfast_t510_co2_upper_ppm"][f"SubD+A{g:.1f}"] - 52300.0) <= 20000.0]
            if best_gain_t510:
                print(f"  t510 cerrado por: {[f'gain={g}' for g in best_gain_t510]}")
            else:
                max_t510 = max(
                    (check_vals.get("cfast_t510_co2_upper_ppm", {}).get(f"SubD+A{g:.1f}", math.nan) for g in gains),
                    default=math.nan
                )
                print(f"  Máximo t510 alcanzado: {max_t510:.0f}ppm (CFAST=52300). "
                      f"Probar gain más bajo o rango distinto.")
    print("=" * W)

    return 0


if __name__ == "__main__":
    sys.exit(main())
