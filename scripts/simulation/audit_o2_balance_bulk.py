#!/usr/bin/env python3
"""O1-D: auditoría de balance de masa de O2 bulk por sala y timestep.

Calcula, por cada sala y log-interval:

    delta_o2_mass_bulk  = (o2[t] - o2[t-1]) * air_mass_kg          [kg]
    expected            = -Δ(o2_consumed_bulk_kg_total)
                          + Δ(o2_exterior_net_kg_total)
                          + Δ(o2_net_transport_kg_total)
                          + Δ(o2_zone_sync_kg_total)                [kg]
    residual            = delta_o2_mass_bulk - expected              [kg]

SF-O1D: o2_zone_sync_kg_total captura la corrección de sincronización zonal
que ThermalSystem aplica al mezclar o2_upper/o2_lower en room.o2 (bulk).
Esta corrección no es transporte físico sino un ajuste numérico necesario para
cerrar el balance cuando ambos sistemas (OES bulk y ThermalSystem zonas) escriben
room.o2 de forma independiente.

fire_o2_mode_used: cuando es "plume_lower" o "plume_blend", room.o2 es derivado
de las zonas (no independiente); el balance bulk O1 no es aplicable en ese modo.

Requiere columnas O1-A/O1-C/O1-D:
    o2_consumed_bulk_kg_total, o2_exterior_net_kg_total,
    o2_net_transport_kg_total, o2_zone_sync_kg_total, air_mass_kg

Uso
---
    python scripts/simulation/audit_o2_balance_bulk.py <csv> [<csv> ...]
    python scripts/simulation/audit_o2_balance_bulk.py --all

Salida: resumen por caso/sala + peores filas.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_REPO = Path(__file__).resolve().parent.parent.parent

REQUIRED_COLS = {
    "time_s",
    "room_id",
    "o2",
    "air_mass_kg",
    "o2_consumed_bulk_kg_total",
    "o2_exterior_net_kg_total",
    "o2_net_transport_kg_total",
    "o2_zone_sync_kg_total",
}

# O1-B compatibility: fall back to _all if bulk-only column absent (pre-O1C CSVs).
_CONSUMED_COL = "o2_consumed_bulk_kg_total"
_CONSUMED_COL_FALLBACK = "o2_consumed_kg_total_all"

OPTIONAL_COLS_FOR_CONTEXT = [
    "hrr_kw",
    "fire_o2_mode_used",
    "o2_consumed_kg_step_all",
    "o2_exterior_net_kg_step",
    "o2_net_transport_kg_step",
    "o2_zone_sync_kg_step",
]

# Tolerance thresholds for classifying residuals
_ABS_FLOOR_KG = 1e-4     # < 0.1 g  → numeric noise
_WARN_KG      = 1e-3     # ≥ 1 g    → worth investigating
_FAIL_KG      = 1e-2     # ≥ 10 g   → likely missing writer


def _load_csv(path: Path) -> tuple[list[str], list[dict]]:
    with open(path, encoding="utf-8") as f:
        lines = [l.rstrip("\n") for l in f if l.strip()]
    if not lines:
        return [], []
    header = [c.strip() for c in lines[0].split(",")]
    rows = []
    for line in lines[1:]:
        parts = line.split(",")
        if len(parts) < len(header):
            parts += [""] * (len(header) - len(parts))
        rows.append(dict(zip(header, parts)))
    return header, rows


def _check_columns(header: list[str], path: Path) -> tuple[bool, list[str], list[str]]:
    present = set(header)
    missing = sorted(REQUIRED_COLS - present)
    extra_o2 = [c for c in header if c.startswith("o2_") and c not in REQUIRED_COLS]
    return len(missing) == 0, missing, extra_o2


def _analyse(path: Path, verbose: bool = False) -> dict:
    header, rows = _load_csv(path)
    ok, missing, extra = _check_columns(header, path)

    result = {
        "path": str(path),
        "name": path.stem,
        "columns_ok": ok,
        "missing_columns": missing,
        "extra_o2_columns": extra,
        "rooms": {},
        "worst_rows": [],
        "summary": {},
    }

    if not ok:
        return result

    # Group rows by room_id, sorted by time
    from collections import defaultdict
    by_room: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        by_room[row["room_id"]].append(row)

    all_residuals: list[tuple[float, str, float, str]] = []  # (|res|, room_id, time_s, note)

    for room_id, rrows in sorted(by_room.items(), key=lambda x: int(x[0])):
        rrows.sort(key=lambda r: float(r["time_s"]))

        air_mass_values = [float(r["air_mass_kg"]) for r in rrows if float(r.get("air_mass_kg", 0)) > 0]
        air_mass_kg = air_mass_values[0] if air_mass_values else 0.0

        residuals: list[float] = []
        row_records: list[dict] = []

        for i in range(1, len(rrows)):
            prev = rrows[i - 1]
            curr = rrows[i]

            try:
                o2_curr  = float(curr["o2"])
                o2_prev  = float(prev["o2"])
                # SF-O1C: prefer bulk-only column; fall back to _all for pre-O1C CSVs.
                _ccol = _CONSUMED_COL if _CONSUMED_COL in curr else _CONSUMED_COL_FALLBACK
                consumed_curr  = float(curr[_ccol])
                consumed_prev  = float(prev[_ccol])
                exterior_curr  = float(curr["o2_exterior_net_kg_total"])
                exterior_prev  = float(prev["o2_exterior_net_kg_total"])
                transport_curr = float(curr["o2_net_transport_kg_total"])
                transport_prev = float(prev["o2_net_transport_kg_total"])
                # SF-O1D: zone_sync corrects for ThermalSystem blend overwrites.
                zone_sync_curr = float(curr.get("o2_zone_sync_kg_total", 0.0) or 0.0)
                zone_sync_prev = float(prev.get("o2_zone_sync_kg_total", 0.0) or 0.0)
            except (ValueError, KeyError):
                continue

            # SF-O1D: skip fire rooms in plume_lower/plume_blend mode — room.o2 is a
            # derived zone quantity there, making the bulk balance formula N/A.
            # Non-fire rooms (hrr_kw == 0) carry the mode label from CombustionSystem's
            # idle path but their room.o2 is NOT derived; include them in the audit.
            o2_mode = curr.get("fire_o2_mode_used", "legacy")
            row_hrr = float(curr.get("hrr_kw", 0.0) or 0.0)
            if row_hrr > 0.1 and o2_mode in ("plume_lower", "plume_blend"):
                continue

            delta_bulk      = (o2_curr - o2_prev) * air_mass_kg
            delta_consumed  = consumed_curr - consumed_prev
            delta_exterior  = exterior_curr - exterior_prev
            delta_transport = transport_curr - transport_prev
            delta_zone_sync = zone_sync_curr - zone_sync_prev
            expected        = -delta_consumed + delta_exterior + delta_transport + delta_zone_sync
            residual        = delta_bulk - expected

            residuals.append(residual)

            rec = {
                "time_s":       float(curr["time_s"]),
                "room_id":      room_id,
                "delta_bulk":   delta_bulk,
                "expected":     expected,
                "residual":     residual,
                "abs_res":      abs(residual),
                "d_consumed":   delta_consumed,
                "d_exterior":   delta_exterior,
                "d_transport":  delta_transport,
                "d_zone_sync":  delta_zone_sync,
                "hrr_kw":       float(curr.get("hrr_kw", 0.0) or 0.0),
                "o2_mode":      o2_mode,
            }
            row_records.append(rec)
            all_residuals.append((abs(residual), room_id, float(curr["time_s"]), rec))

        if not residuals:
            continue

        abs_res = [abs(r) for r in residuals]
        result["rooms"][room_id] = {
            "air_mass_kg": air_mass_kg,
            "n_intervals": len(residuals),
            "max_abs_residual_kg": max(abs_res),
            "mean_abs_residual_kg": sum(abs_res) / len(abs_res),
            "p95_abs_residual_kg": sorted(abs_res)[int(0.95 * len(abs_res))],
            "n_above_warn": sum(1 for r in abs_res if r >= _WARN_KG),
            "n_above_fail": sum(1 for r in abs_res if r >= _FAIL_KG),
        }

    # Top 10 worst rows across all rooms
    all_residuals.sort(key=lambda x: x[0], reverse=True)
    result["worst_rows"] = [r for _, _, _, r in all_residuals[:10]]

    # Case-level summary
    all_abs = [x[0] for x in all_residuals]
    if all_abs:
        result["summary"] = {
            "max_abs_residual_kg": max(all_abs),
            "mean_abs_residual_kg": sum(all_abs) / len(all_abs),
            "n_above_warn": sum(1 for r in all_abs if r >= _WARN_KG),
            "n_above_fail": sum(1 for r in all_abs if r >= _FAIL_KG),
            "total_intervals": len(all_abs),
            "verdict": (
                "FAIL_CANDIDATE" if max(all_abs) >= _FAIL_KG else
                "WARN_CANDIDATE" if max(all_abs) >= _WARN_KG else
                "CLEAN"
            ),
        }
    return result


def _classify_residual(abs_res: float) -> str:
    if abs_res < _ABS_FLOOR_KG:
        return "NOISE"
    if abs_res < _WARN_KG:
        return "SMALL"
    if abs_res < _FAIL_KG:
        return "WARN"
    return "FAIL"


def _diagnose_row(rec: dict) -> str:
    """Heuristic: guess probable cause from sign/magnitude of delta components."""
    res  = rec["residual"]
    d_c  = rec["d_consumed"]
    d_e  = rec["d_exterior"]
    d_t  = rec["d_transport"]
    d_zs = rec.get("d_zone_sync", 0.0)
    hrr  = rec["hrr_kw"]

    hints = []
    if abs(d_c) > 10 * max(abs(d_e), abs(d_t), 1e-9) and hrr > 0.1:
        hints.append("consumo domina (combustion activa)")
    if abs(d_e) > 1e-4:
        hints.append(f"exterior neto {d_e:+.4f} kg")
    if abs(d_t) > 1e-4:
        hints.append(f"transporte {d_t:+.4f} kg")
    if abs(d_zs) > 1e-4:
        hints.append(f"zone_sync {d_zs:+.4f} kg (blend ThermalSystem)")
    if res > _WARN_KG:
        hints.append("bulk cae menos de lo esperado — probable writer no contabilizado")
    elif res < -_WARN_KG:
        hints.append("bulk cae más de lo esperado — posible doble-conteo")
    return "; ".join(hints) if hints else "sin indicios claros"


def _print_report(results: list[dict], verbose: bool = False) -> None:
    sep = "-" * 72

    # ── Column inventory (first case) ─────────────────────────────────────
    print(sep)
    print("INVENTARIO DE COLUMNAS (primer CSV)")
    print(sep)
    first = results[0]
    path0 = Path(first["path"])
    header0, _ = _load_csv(path0)
    print(f"  Total columnas: {len(header0)}")
    o2_cols = [c for c in header0 if "o2" in c.lower()]
    print(f"  Columnas O2 presentes ({len(o2_cols)}): {', '.join(o2_cols)}")
    missing_all = sorted(set().union(*[set(r["missing_columns"]) for r in results]))
    if missing_all:
        print(f"  FALTAN (requeridas): {', '.join(missing_all)}")
    else:
        print("  Todas las columnas requeridas presentes.")
    print()

    # ── Per-case summary ──────────────────────────────────────────────────
    print(sep)
    print("RESUMEN POR CASO")
    print(sep)
    for r in results:
        s = r.get("summary", {})
        if r["missing_columns"]:
            print(f"  {r['name']}: SKIP — faltan columnas: {r['missing_columns']}")
            continue
        verdict = s.get("verdict", "?")
        max_r   = s.get("max_abs_residual_kg", 0.0)
        mean_r  = s.get("mean_abs_residual_kg", 0.0)
        n_warn  = s.get("n_above_warn", 0)
        n_fail  = s.get("n_above_fail", 0)
        n_tot   = s.get("total_intervals", 0)
        print(f"  {r['name']:<35}  {verdict:<18}  "
              f"max={max_r:.4e} kg  mean={mean_r:.4e} kg  "
              f"warn={n_warn}/{n_tot}  fail={n_fail}/{n_tot}")
    print()

    # ── Per-room breakdown ─────────────────────────────────────────────────
    print(sep)
    print("DISTRIBUCIÓN POR SALA")
    print(sep)
    for r in results:
        if r["missing_columns"] or not r.get("rooms"):
            continue
        print(f"\n  [{r['name']}]")
        print(f"  {'room_id':<8}  {'air_kg':>8}  {'max|res|':>10}  {'mean|res|':>10}  "
              f"{'p95|res|':>10}  {'warn':>5}  {'fail':>5}  {'n':>5}")
        print(f"  {'-'*8}  {'-'*8}  {'-'*10}  {'-'*10}  {'-'*10}  {'-'*5}  {'-'*5}  {'-'*5}")
        for rid, rd in sorted(r["rooms"].items(), key=lambda x: int(x[0])):
            print(f"  {rid:<8}  {rd['air_mass_kg']:>8.2f}  "
                  f"{rd['max_abs_residual_kg']:>10.4e}  "
                  f"{rd['mean_abs_residual_kg']:>10.4e}  "
                  f"{rd['p95_abs_residual_kg']:>10.4e}  "
                  f"{rd['n_above_warn']:>5}  "
                  f"{rd['n_above_fail']:>5}  "
                  f"{rd['n_intervals']:>5}")
    print()

    # ── Worst rows ─────────────────────────────────────────────────────────
    print(sep)
    print("PEORES FILAS (top 10 por |residual|)")
    print(sep)
    worst: list[tuple[float, str, dict]] = []
    for r in results:
        for wr in r.get("worst_rows", []):
            worst.append((wr["abs_res"], r["name"], wr))
    worst.sort(key=lambda x: x[0], reverse=True)
    for rank, (abs_res, case_name, wr) in enumerate(worst[:10], 1):
        cls = _classify_residual(abs_res)
        diag = _diagnose_row(wr)
        print(f"  #{rank:02d} [{cls}] {case_name} sala={wr['room_id']}  t={wr['time_s']:.1f}s")
        print(f"       |residual|={abs_res:.4e} kg  "
              f"delta_bulk={wr['delta_bulk']:+.4e}  expected={wr['expected']:+.4e}")
        print(f"       d_consumed={wr['d_consumed']:+.4e}  "
              f"d_exterior={wr['d_exterior']:+.4e}  "
              f"d_transport={wr['d_transport']:+.4e}  "
              f"d_zone_sync={wr.get('d_zone_sync', 0.0):+.4e}  "
              f"hrr={wr['hrr_kw']:.0f} kW  mode={wr.get('o2_mode', '?')}")
        print(f"       Probable causa: {diag}")
        print()

    # ── Conclusion ─────────────────────────────────────────────────────────
    print(sep)
    print("CONCLUSIÓN")
    print(sep)
    any_fail = any(r.get("summary", {}).get("n_above_fail", 0) > 0 for r in results)
    any_warn = any(r.get("summary", {}).get("n_above_warn", 0) > 0 for r in results)
    if any_fail:
        print("  O1 estado: BLOQUEADO — residuales >= 10 g; hay writers sin contabilizar.")
        print("  Siguiente paso: identificar los paths específicos (ver peores filas).")
    elif any_warn:
        print("  O1 estado: WARN posible — residuales < 10 g pero >= 1 g.")
        print("  Siguiente paso: valorar si la tolerancia 1% del total O2 consumido es aceptable.")
    else:
        print("  O1 estado: IMPLEMENTABLE como WARN — todos los residuales < 1 g.")
        print("  Siguiente paso: definir tolerancias y crear regla O1 WARN.")
    print()
    _print_missing_col_note()


def _print_missing_col_note() -> None:
    print("NOTA SOBRE COLUMNAS CLAVE")
    print("  air_mass_kg: densidad fija 1.2 kg/m³ × volume_m3() — misma constante que OES.")
    print("  o2_consumed_bulk_kg_total (SF-O1C): solo el path que depleta room.o2 bulk")
    print("  directamente (OES linea bulk). NO incluye consumo de o2_upper ni o2_lower.")
    print("  o2_consumed_kg_total_all: suma de todos los paths (bulk + upper + lower + pluma).")
    print("  o2_zone_sync_kg_total (SF-O1D): corrección de sincronización zonal acumulada.")
    print("    ThermalSystem blend-overwrites room.o2 con promedio(o2_upper, o2_lower);")
    print("    la diferencia (blend - bulk_previo) × air_mass_kg se acumula aquí.")
    print("    No es transporte; es un artefacto de tener dos representaciones de O2.")
    print("  fire_o2_mode_used: filas de SALA FUEGO (hrr_kw > 0.1) con 'plume_lower'/'plume_blend'")
    print("    se OMITEN porque room.o2 es derivado de zonas (bulk balance N/A).")
    print("    Salas idle (no-fuego) siempre se incluyen aunque lleven el label (artefacto")
    print("    de CombustionSystem que llama _resolve_fire_o2_selection en salas idle).")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="O1-B: auditoría de balance de masa O2 bulk por sala/timestep"
    )
    parser.add_argument("csvs", nargs="*", help="Rutas a CSVs a analizar")
    parser.add_argument(
        "--all",
        action="store_true",
        help="Analizar todos los CSVs en sim/validation/reports/",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    paths: list[Path] = []
    if args.all:
        reports_dir = _REPO / "sim" / "validation" / "reports"
        paths = sorted(reports_dir.glob("*.csv"))
    else:
        for p in args.csvs:
            paths.append(Path(p))

    if not paths:
        parser.print_help()
        return 2

    results = []
    for p in paths:
        if not p.exists():
            print(f"SKIP: {p} — no encontrado", file=sys.stderr)
            continue
        results.append(_analyse(p, verbose=args.verbose))

    if not results:
        print("No CSVs procesados.", file=sys.stderr)
        return 2

    _print_report(results, verbose=args.verbose)
    return 0


if __name__ == "__main__":
    sys.exit(main())
