"""
phase2h_diag_victim.py — Diagnóstico OFF vs ON para victim_fed_incapacitation.

Objetivo: confirmar que la regresión FED +18.9% viene de la supresión de
doorway replenishment (lower_replenish_scale=0) que hace caer room_0.o2_lower
hacia room.o2 con Phase 2H ON (sala sin ventana exterior).

Captura timeseries CSV Room 0:
  time_s | o2 | o2_upper | o2_lower | (o2_lower - o2) | hrr_kw |
  co_ppm | co_upper_ppm | co_lower_ppm | fed | hot_layer_m

Víctima: height_m=0.9m  → in_upper_layer = (h_layer_m < 0.9)
  → casi siempre in_lower_layer → FED usa o2_lower para hipoxia.

Uso:
    python scripts/simulation/phase2h_diag_victim.py
    python scripts/simulation/phase2h_diag_victim.py --skip-run
"""

import argparse
import csv
import json
import subprocess
import sys
from pathlib import Path

ROOT        = Path(__file__).resolve().parents[2]
CASES_DIR   = ROOT / "sim" / "validation" / "cases"
REPORTS_DIR = ROOT / "sim" / "validation" / "reports"

BASE_CASE = "victim_fed_incapacitation"

_GODOT_CANDIDATES = [
    "F:/OneDrive/Escritorio/Godot_v4.6.3-stable_win64_console.exe",
    "C:/Users/dangp/Desktop/Godot_v4.6.3-stable_win64_console.exe",
]


def find_godot(requested=None):
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


FLAGS_OFF = {
    "phase2h_o2_doorway_two_zone_enabled":     False,
    "phase2h_cold_room_lower_routing_enabled": False,
    "phase2h_lower_replenish_gain":            0.0,
}

FLAGS_ON = {
    "phase2h_o2_doorway_two_zone_enabled":     True,
    "phase2h_cold_room_lower_routing_enabled": True,
    "phase2h_lower_replenish_gain":            0.25,
}


def _build_diag_case(base_path: Path, out_path: Path, flags: dict, tag: str) -> None:
    case_data = json.loads(base_path.read_text(encoding="utf-8-sig"))
    # enable_logging MUST be top-level: CaseRunner reads it at line 134 directly
    # from _case_config, overriding any engine_overrides value.
    case_data["enable_logging"] = True
    overrides = dict(case_data.get("engine_overrides", {}))
    overrides.update(flags)
    overrides["log_file_path"]  = f"res://sim/validation/reports/p2h_diag_{tag}.log"
    overrides["enable_csv_log"] = True
    overrides["csv_log_file_path"] = f"res://sim/validation/reports/p2h_diag_{tag}.csv"
    overrides["log_interval_s"] = 5.0  # captura cada 5 s simulados
    # reporte en ruta estándar del runner
    case_data["engine_overrides"] = overrides
    out_path.write_text(
        json.dumps(case_data, indent="\t", ensure_ascii=False),
        encoding="utf-8"
    )


def _run_case(godot: Path, case_name: str, timeout_s: int = 600) -> bool:
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--",
           f"--validation-case={case_name}"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode == 0
    except Exception as e:
        print(f"    ERROR: {e}")
        return False


def _load_csv(csv_path: Path, room_id: int = 0) -> list[dict]:
    """Lee un CSV de log y devuelve filas de room_id ordenadas por time_s."""
    rows = []
    if not csv_path.exists():
        return rows
    with csv_path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                if int(float(row.get("room_id", -1))) == room_id:
                    rows.append({k: float(v) for k, v in row.items()
                                 if v.replace(".", "", 1).replace("-", "", 1).isdigit()})
            except (ValueError, AttributeError):
                continue
    rows.sort(key=lambda r: r.get("time_s", 0.0))
    return rows


def _load_report(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _get_metric(report: dict, key: str):
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


def _fmt(v, w=9, p=4):
    if v is None:
        return f"{'n/a':>{w}}"
    return f"{v:>{w}.{p}f}"


def _delta(a, b, w=10):
    if a is None or b is None:
        return f"{'n/a':>{w}}"
    d = b - a
    s = "+" if d >= 0 else ""
    return f"{s}{d:>{w-1}.4f}"


VICTIM_HEIGHT_M = 0.9


def main():
    parser = argparse.ArgumentParser(description="Phase 2H victim FED regression diagnostic")
    parser.add_argument("--godot",    default=None, metavar="PATH")
    parser.add_argument("--skip-run", action="store_true",
                        help="Usar CSVs y reports ya existentes.")
    parser.add_argument("--timeout",  type=int, default=600)
    parser.add_argument("--interior-drain-gain", type=float, default=0.0)
    parser.add_argument("--interior-drain-max-scale", type=float, default=1.40)
    args = parser.parse_args()

    base_path  = CASES_DIR / f"{BASE_CASE}.json"
    if not base_path.exists():
        print(f"ERROR: caso base no encontrado: {base_path}")
        return 1

    off_case_path    = CASES_DIR / f"{BASE_CASE}_p2h_diag_off.json"
    on_case_path     = CASES_DIR / f"{BASE_CASE}_p2h_diag_on.json"
    off_report_path  = REPORTS_DIR / f"{BASE_CASE}_p2h_diag_off.json"
    on_report_path   = REPORTS_DIR / f"{BASE_CASE}_p2h_diag_on.json"
    off_csv_path     = REPORTS_DIR / "p2h_diag_off.csv"
    on_csv_path      = REPORTS_DIR / "p2h_diag_on.csv"

    created_temp = []

    if not args.skip_run:
        godot = find_godot(args.godot)
        if godot is None:
            print("ERROR: no se encontró Godot. Define --godot PATH o GODOT_EXE.")
            return 1
        print(f"\n  Godot: {godot}\n")

        # Construir casos temporales
        flags_on = dict(FLAGS_ON)
        flags_on["phase2h_interior_no_exterior_drain_gain"] = args.interior_drain_gain
        flags_on["phase2h_interior_no_exterior_drain_max_scale"] = args.interior_drain_max_scale
        _build_diag_case(base_path, off_case_path, FLAGS_OFF, "off")
        _build_diag_case(base_path, on_case_path,  flags_on,  "on")
        created_temp.extend([off_case_path, on_case_path])

        for tag, case_name in [("OFF", f"{BASE_CASE}_p2h_diag_off"),
                                ("ON",  f"{BASE_CASE}_p2h_diag_on")]:
            print(f"  Corriendo {tag} ...", end=" ", flush=True)
            ok = _run_case(godot, case_name, args.timeout)
            print("OK" if ok else "FAIL")

    # --- Leer datos ---
    off_rows  = _load_csv(off_csv_path,  room_id=0)
    on_rows   = _load_csv(on_csv_path,   room_id=0)
    off_rep   = _load_report(off_report_path)
    on_rep    = _load_report(on_report_path)

    # Limpiar temporales (sólo los casos .json; los CSV/reports se mantienen)
    for p in created_temp:
        try:
            p.unlink(missing_ok=True)
        except Exception:
            pass

    # Métricas finales del report
    vic_fed_off = _get_metric(off_rep, "victim_v0_final_fed")
    vic_fed_on  = _get_metric(on_rep,  "victim_v0_final_fed")
    r0_fed_off  = _get_metric(off_rep, "room_0_final_fed")
    r0_fed_on   = _get_metric(on_rep,  "room_0_final_fed")
    r0_o2_off   = _get_metric(off_rep, "room_0_final_o2")
    r0_o2_on    = _get_metric(on_rep,  "room_0_final_o2")

    W = 120
    print()
    print("=" * W)
    print("  Phase 2H — Diagnóstico victim_fed_incapacitation  (Room 0, víctima h=0.9m)")
    print(f"  Hipótesis original (2026-05-26): cold_room_lower_routing reoxigenaba sala fuego")
    print(f"                     → o2_lower sube → fuego prolonga burn/CO → regresión FED")
    print(f"  Guard v4 (2026-05-27): drenaje acelerado o2_lower solo si outside_open_factor>0.01")
    print(f"                     → sin ventana exterior, lower_entr_scale=0.20 (baseline)")
    print("=" * W)

    # --- Tabla resumen final ---
    print()
    print("  RESUMEN FINAL (report):")
    print(f"  {'Métrica':<30}  {'OFF':>10}  {'ON':>10}  {'Δ(ON-OFF)':>12}  {'%':>8}")
    print(f"  {'-'*30}  {'-'*10}  {'-'*10}  {'-'*12}  {'-'*8}")

    def _pct(a, b):
        if a is None or b is None or abs(a) < 1e-9:
            return "n/a"
        return f"{(b-a)/abs(a)*100:+.1f}%"

    for label, vo, vn in [
        ("victim_v0_final_fed",  vic_fed_off, vic_fed_on),
        ("room_0_final_fed",     r0_fed_off,  r0_fed_on),
        ("room_0_final_o2",      r0_o2_off,   r0_o2_on),
    ]:
        d = (vn - vo) if (vo is not None and vn is not None) else None
        d_str = f"{d:+.4f}" if d is not None else "n/a"
        print(f"  {label:<30}  {_fmt(vo,10,4)}  {_fmt(vn,10,4)}  {d_str:>12}  {_pct(vo,vn):>8}")

    # --- Determinar tiempos comunes ---
    off_by_t = {int(r["time_s"]): r for r in off_rows}
    on_by_t  = {int(r["time_s"]): r for r in on_rows}
    common_t = sorted(set(off_by_t) & set(on_by_t))

    if not common_t:
        print("\n  ADVERTENCIA: no se encontraron datos de timeseries (CSV vacío o no generado).")
        print(f"  Revisar: {off_csv_path}")
        print(f"           {on_csv_path}")
        return 0

    # --- Tabla timeseries ---
    print()
    print("  TIMESERIES Room 0  (víctima a 0.9m → in_upper ↔ hot_layer_m < 0.9)")
    print()
    H = (f"  {'t_s':>5}  {'HRR_OFF':>8}  {'o2_OFF':>7}  {'o2u_OFF':>8}  "
         f"{'o2l_OFF':>8}  {'Δl-r_OFF':>9}  "
         f"{'o2_ON':>7}  {'o2u_ON':>8}  {'o2l_ON':>8}  {'Δl-r_ON':>9}  "
         f"{'Δo2l':>9}  {'fed_OFF':>8}  {'fed_ON':>8}  {'Δfed':>8}  "
         f"{'hl_OFF':>7}  {'hl_ON':>7}  {'in_up?':>7}")
    print(H)
    print("  " + "-" * (len(H) - 2))

    # Calcular FED acumulado incremental (o2_lower contribution estimado)
    # Nota: el CSV ya incluye el FED de sala acumulado

    for t in common_t:
        ro = off_by_t[t]
        rn = on_by_t[t]

        hrr_off   = ro.get("hrr_kw", 0.0)
        o2_off    = ro.get("o2", 0.0)
        o2u_off   = ro.get("o2_upper", o2_off)
        o2l_off   = ro.get("o2_lower", o2_off)
        dl_r_off  = o2l_off - o2_off

        o2_on     = rn.get("o2", 0.0)
        o2u_on    = rn.get("o2_upper", o2_on)
        o2l_on    = rn.get("o2_lower", o2_on)
        dl_r_on   = o2l_on - o2_on

        d_o2l     = o2l_on - o2l_off

        fed_off   = ro.get("fed", 0.0)
        fed_on    = rn.get("fed", 0.0)
        d_fed     = fed_on - fed_off

        hl_off    = ro.get("hot_layer_m", 0.0)
        hl_on     = rn.get("hot_layer_m", 0.0)
        # Víctima en upper layer si hot_layer_m < VICTIM_HEIGHT_M
        in_up_off = hl_off < VICTIM_HEIGHT_M and ro.get("o2_upper", -1.0) > 0.0
        in_up_on  = hl_on  < VICTIM_HEIGHT_M and rn.get("o2_upper", -1.0) > 0.0
        in_up_str = "UPP" if (in_up_off or in_up_on) else "LOW"

        d_sign = "↑" if d_fed > 0.001 else ("↓" if d_fed < -0.001 else "=")
        l_sign = "↓" if d_o2l < -0.001 else ("↑" if d_o2l > 0.001 else "=")

        print(
            f"  {t:>5}  "
            f"{hrr_off:>8.1f}  "
            f"{o2_off:>7.4f}  {o2u_off:>8.4f}  {o2l_off:>8.4f}  {dl_r_off:>+9.4f}  "
            f"{o2_on:>7.4f}  {o2u_on:>8.4f}  {o2l_on:>8.4f}  {dl_r_on:>+9.4f}  "
            f"{l_sign}{d_o2l:>+8.4f}  "
            f"{fed_off:>8.4f}  {fed_on:>8.4f}  {d_sign}{d_fed:>+7.4f}  "
            f"{hl_off:>7.3f}  {hl_on:>7.3f}  {in_up_str:>7}"
        )

    # --- Análisis de FED por componente (estimado desde timeseries) ---
    # Verificar si hay diferencia en CO2 upper
    print()
    print("  CO₂ upper (tracción de v_co2):")
    H2 = (f"  {'t_s':>5}  {'co2_ppm_OFF':>12}  {'co2u_ppm_OFF':>13}  "
          f"{'co2_ppm_ON':>12}  {'co2u_ppm_ON':>13}  {'Δco2':>9}  {'Δco2u':>9}")
    print(H2)
    print("  " + "-" * (len(H2) - 2))
    for t in common_t:
        ro = off_by_t[t]
        rn = on_by_t[t]
        co2_off  = ro.get("co2_ppm", 0.0)
        co2u_off = ro.get("co2_upper_ppm", 0.0)   # co2_upper_ppm en CSV
        co2_on   = rn.get("co2_ppm", 0.0)
        co2u_on  = rn.get("co2_upper_ppm", 0.0)
        if abs(co2_off - co2_on) < 0.1 and abs(co2u_off - co2u_on) < 0.1:
            continue   # sin diferencia → saltar
        d_co2  = co2_on  - co2_off
        d_co2u = co2u_on - co2u_off
        print(f"  {t:>5}  {co2_off:>12.1f}  {co2u_off:>13.1f}  "
              f"{co2_on:>12.1f}  {co2u_on:>13.1f}  "
              f"{d_co2:>+9.1f}  {d_co2u:>+9.1f}")
    else:
        print("  (solo se muestran timesteps con diferencias)")

    # --- FED hipoxia estimado ---
    # FED_O2_delta = dt_min / exp(fed_hypoxia_a - fed_hypoxia_b * (20.9 - o2_pct))
    # Parámetros: fed_hypoxia_a=8.13, fed_hypoxia_b=0.54 (típicos Purser)
    FED_A = 8.13
    FED_B = 0.54
    import math
    print()
    print("  HIPOXIA FED ESTIMADA (in_lower, usando o2_lower):")
    print(f"  Fórmula: δFED = (dt_s/60) / exp({FED_A} - {FED_B}*(20.9 - o2_lower*100))")
    H3 = (f"  {'t_s':>5}  {'o2l_OFF':>8}  {'δFEDhyp_OFF':>12}  "
          f"{'o2l_ON':>8}  {'δFEDhyp_ON':>12}  {'Δδhyp':>10}")
    print(H3)
    print("  " + "-" * (len(H3) - 2))

    prev_t = None
    cum_hyp_off = 0.0
    cum_hyp_on  = 0.0
    for t in common_t:
        ro = off_by_t[t]
        rn = on_by_t[t]
        if prev_t is None:
            prev_t = t
            continue
        dt_s  = t - prev_t
        dt_min = dt_s / 60.0
        prev_t = t

        o2l_off = ro.get("o2_lower", ro.get("o2", 0.0))
        o2l_on  = rn.get("o2_lower", rn.get("o2", 0.0))

        def hyp_delta(o2l, dt_m):
            o2_pct = min(max(o2l * 100.0, 0.0), 20.9)
            o2_def = max(0.0, 20.9 - o2_pct)
            if o2_def <= 0.0:
                return 0.0
            t_crit = math.exp(FED_A - FED_B * o2_def)
            return dt_m / t_crit if t_crit > 0.0 else 0.0

        dh_off = hyp_delta(o2l_off, dt_min)
        dh_on  = hyp_delta(o2l_on,  dt_min)
        cum_hyp_off += dh_off
        cum_hyp_on  += dh_on
        d_dh = dh_on - dh_off
        if abs(d_dh) > 1e-8 or t in (30, 60, 120, 180, 240, 300, 400, 600, 800):
            print(f"  {t:>5}  {o2l_off:>8.4f}  {dh_off:>12.6f}  "
                  f"{o2l_on:>8.4f}  {dh_on:>12.6f}  {d_dh:>+10.6f}")

    print()
    print(f"  Hipoxia FED acumulada estimada:")
    print(f"    OFF: {cum_hyp_off:.4f}")
    print(f"    ON:  {cum_hyp_on:.4f}")
    print(f"    Δ:   {cum_hyp_on - cum_hyp_off:+.4f}")
    print()

    # --- Veredicto ---
    print("=" * W)
    vic_fed_delta = (vic_fed_on - vic_fed_off) if (vic_fed_off and vic_fed_on) else None
    o2l_at_peak_off = None
    o2l_at_peak_on  = None
    # Tomar el snapshot de mayor HRR
    max_hrr_t = max(common_t, key=lambda t: off_by_t[t].get("hrr_kw", 0.0), default=None)
    if max_hrr_t:
        o2l_at_peak_off = off_by_t[max_hrr_t].get("o2_lower", None)
        o2l_at_peak_on  = on_by_t[max_hrr_t].get("o2_lower", None)

    print()
    print("  VEREDICTO:")
    if vic_fed_delta is not None:
        sign = "❌" if vic_fed_delta > 0.005 else "✅"
        print(f"    vic FED delta = {vic_fed_delta:+.4f}  {sign}")
    if o2l_at_peak_off is not None and o2l_at_peak_on is not None:
        d_o2l_peak = o2l_at_peak_on - o2l_at_peak_off
        cause = ("↑ o2_lower_ON > o2_lower_OFF → replenishment activo (exterior abierto, esperado)"
                 if d_o2l_peak > 0.001 else
                 ("≈ o2_lower igual → guard v4 efectivo, sin regresión"
                  if abs(d_o2l_peak) <= 0.001 else
                  "↓ o2_lower_ON < o2_lower_OFF → guard v4 no efectivo, investigar"))
        print(f"    o2_lower@peak_HRR  OFF={o2l_at_peak_off:.4f}  ON={o2l_at_peak_on:.4f}"
              f"  Δ={d_o2l_peak:+.4f}  {cause}")
    hyp_delta_total = cum_hyp_on - cum_hyp_off
    if abs(hyp_delta_total) > 0.001:
        print(f"    Hipoxia FED explica ~{abs(hyp_delta_total):.4f} del Δ FED = {abs(vic_fed_delta or 0):.4f}")
        ratio = abs(hyp_delta_total) / abs(vic_fed_delta) * 100 if vic_fed_delta else 0
        print(f"    → Fracción explicada: {ratio:.0f}%")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
