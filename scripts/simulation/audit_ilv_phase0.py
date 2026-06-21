#!/usr/bin/env python3
"""Fase 0 ILV — Auditoría de extinción en sala sellada.

Corre el caso cfast_ilv_audit (room 2 / bedroom, ~36 m³, sin aperturas,
sin explicit fuel_objects) y vuelca por segundo los campos de diagnóstico ILV.

Objetivo: entender por qué el fuego pasa a EXTINGUISHED sin pasar por
ILV_LATENT, documentando el gap estructural entre can_flame y latent_viable.

Iteración 2: room 2 (legacy, sin fuel_objects explícitos), 900s.

No modifica ningún archivo de física ni de validación.

Uso:
  python audit_ilv_phase0.py            # corre simulación + análisis
  python audit_ilv_phase0.py --no-run   # análisis sobre CSV ya existente
  python audit_ilv_phase0.py --all      # imprime cada segundo (no submuestreado)
"""

from __future__ import annotations

import csv
import io
import subprocess
import sys
from pathlib import Path

# Force UTF-8 output on Windows consoles (avoids cp1252 UnicodeEncodeError)
if hasattr(sys.stdout, "buffer"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parents[2]
CASE_NAME = "cfast_ilv_audit"
WATCH_ROOM_ID = "2"
CSV_PATH = ROOT / "sim" / "validation" / "reports" / f"{CASE_NAME}.csv"
PS_RUNNER = ROOT / "sim" / "validation" / "run_case.ps1"

# Iteración 1 (room 0, 600s) para comparativa
IT1_TRANSITIONS = [
    (0.0,   "(sin fuego)",              "EXTINGUISHED"),
    (1.0,   "EXTINGUISHED",            "FUEL_CONTROLLED"),
    (232.0, "FUEL_CONTROLLED",         "VENTILATION_STRESSED"),
    (407.1, "VENTILATION_STRESSED",    "VENTILATION_CONTROLLED_BURNING"),
]
IT1_NOTE = "600s sin extincion, O2=12.27% al final, fire_smoldering nunca true"

DIAG_COLS = [
    "time_s",
    "combustion_regime",
    "o2",
    "o2_upper",
    "o2_lower",
    "o2_hrr_factor",
    "hrr_kw",
    "hrr_target_kw",
    "flame_hrr_target_kw",
    "smolder_hrr_target_kw",
    "pyrolysis_kw",
    "retained_unburned_MJ",
    "unburned_gas_vol_frac",
    "ventilation_response_factor",
    "temp_upper_c",
    "temp_lower_c",
    "fire_smoldering",
    "fire_latent_active",
]

COL_W = {
    "time_s": 7,
    "combustion_regime": 28,
    "o2": 8,
    "o2_upper": 8,
    "o2_lower": 8,
    "o2_hrr_factor": 12,
    "hrr_kw": 8,
    "hrr_target_kw": 13,
    "flame_hrr_target_kw": 18,
    "smolder_hrr_target_kw": 21,
    "pyrolysis_kw": 12,
    "retained_unburned_MJ": 19,
    "unburned_gas_vol_frac": 20,
    "ventilation_response_factor": 26,
    "temp_upper_c": 12,
    "temp_lower_c": 12,
    "fire_smoldering": 14,
    "fire_latent_active": 18,
}


def _run_case() -> None:
    print(f"[audit] Ejecutando caso {CASE_NAME} (it.2: room {WATCH_ROOM_ID}, 900s)...")
    cmd = [
        "powershell.exe", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", str(PS_RUNNER),
        "-CaseName", CASE_NAME,
        "-TimeoutSeconds", "420",
        "-AllowBaselineFailure",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print("[audit] STDERR:", result.stderr[-2000:] if result.stderr else "(vacío)")
        print("[audit] STDOUT:", result.stdout[-1000:] if result.stdout else "(vacío)")
        sys.exit(f"[audit] ERROR: Godot salió con código {result.returncode}")
    print("[audit] Simulación completada.")


def _load_csv() -> list[dict[str, str]]:
    if not CSV_PATH.exists():
        sys.exit(f"[audit] CSV no encontrado: {CSV_PATH}")
    with CSV_PATH.open(newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        rows = [row for row in reader if row.get("room_id", "").strip() == WATCH_ROOM_ID]
    if not rows:
        sys.exit(f"[audit] CSV sin filas para room_id={WATCH_ROOM_ID}: {CSV_PATH}")
    return rows


def _print_header() -> None:
    parts = [col.ljust(COL_W.get(col, 12)) for col in DIAG_COLS]
    line = "  ".join(parts)
    print(line)
    print("-" * len(line))


def _fmt(col: str, val: str) -> str:
    w = COL_W.get(col, 12)
    if col == "combustion_regime":
        return val.ljust(w)
    if col == "fire_smoldering":
        return ("true" if val.strip() in ("1", "true", "True") else "false").ljust(w)
    try:
        f = float(val)
        if col == "time_s":
            return f"{f:>7.1f}".ljust(w)
        if col in ("o2", "o2_upper", "o2_lower"):
            return f"{f:.5f}".ljust(w)
        if col in ("o2_hrr_factor", "ventilation_response_factor"):
            return f"{f:.4f}".ljust(w)
        return f"{f:.2f}".ljust(w)
    except (ValueError, TypeError):
        return str(val).ljust(w)


def _detect_transitions(rows: list[dict[str, str]]) -> list[tuple[float, str, str]]:
    transitions: list[tuple[float, str, str]] = []
    prev = ""
    for row in rows:
        regime = row.get("combustion_regime", "").strip()
        if regime != prev:
            t = float(row.get("time_s", 0.0))
            transitions.append((t, prev, regime))
            prev = regime
    return transitions


def _print_summary(rows: list[dict[str, str]], transitions: list[tuple[float, str, str]]) -> None:
    print("\n=== RESUMEN DE TRANSICIONES — ITERACIÓN 2 (room 2, 900s) ===")
    for t, frm, to in transitions:
        arrow = f"{frm or '(inicio)'} -> {to}"
        print(f"  t={t:6.1f}s  {arrow}")

    # Condiciones en extinción (primera fila EXTINGUISHED tras ignición)
    post_ignition = [r for r in rows if r.get("combustion_regime", "").strip() != "EXTINGUISHED"
                     or float(r.get("time_s", 0)) > 2.0]
    ext_row = next(
        (r for r in post_ignition if r.get("combustion_regime", "").strip() == "EXTINGUISHED"),
        None,
    )
    if ext_row:
        t_ext = float(ext_row.get("time_s", 0.0))
        print(f"\n=== CONDICIONES EN EXTINCIÓN (t={t_ext:.1f}s) ===")
        for col in DIAG_COLS:
            val = ext_row.get(col, "n/a")
            print(f"  {col:<28} {val}")
    else:
        last = rows[-1]
        t_last = float(last.get("time_s", 0.0))
        o2_last = float(last.get("o2", "0"))
        hrr_last = float(last.get("hrr_kw", "0"))
        print(f"\n  Sin extinción en {t_last:.0f}s — O₂={o2_last:.5f}, hrr={hrr_last:.1f} kW al final.")

    # fire_smoldering / fire_latent_active
    smoldering_rows = [r for r in rows if r.get("fire_smoldering", "").strip() in ("1", "true", "True")]
    latent_rows = [r for r in rows if r.get("fire_latent_active", "").strip() in ("1", "true", "True")]
    if smoldering_rows:
        t0 = float(smoldering_rows[0].get("time_s", 0.0))
        t1 = float(smoldering_rows[-1].get("time_s", 0.0))
        print(f"\n  fire_smoldering=true: t={t0:.1f}s .. {t1:.1f}s  ({len(smoldering_rows)} muestras)")
    else:
        print("\n  fire_smoldering nunca fue true.")
    if latent_rows:
        t0 = float(latent_rows[0].get("time_s", 0.0))
        t1 = float(latent_rows[-1].get("time_s", 0.0))
        print(f"  fire_latent_active=true: t={t0:.1f}s .. {t1:.1f}s  ({len(latent_rows)} muestras)")
    else:
        print("  fire_latent_active nunca fue true — ILV_LATENT no se activó (gap O2 sin cerrar).")

    # Primer instante con o2_hrr_factor < 0.15
    stressed_row = next(
        (r for r in rows
         if float(r.get("o2_hrr_factor", "1.0")) < 0.15
         and float(r.get("hrr_kw", "0")) > 0.0),
        None,
    )
    if stressed_row:
        t_s = float(stressed_row.get("time_s", 0.0))
        o2_s = float(stressed_row.get("o2", "0.0"))
        factor_s = float(stressed_row.get("o2_hrr_factor", "0.0"))
        print(f"\n  o2_hrr_factor < 0.15 por primera vez: t={t_s:.1f}s,  o2={o2_s:.5f},  factor={factor_s:.4f}")

    # Comparativa con iteración 1
    print("\n=== COMPARATIVA ITERACIONES ===")
    print("  Iteración 1 (room 0, 600s, explicit fuel_objects):")
    for t, frm, to in IT1_TRANSITIONS:
        print(f"    t={t:6.1f}s  {frm or '(inicio)'} -> {to}")
    print(f"    Nota: {IT1_NOTE}")
    print("  Iteración 2 (room 2, 900s, legacy):")
    for t, frm, to in transitions:
        print(f"    t={t:6.1f}s  {frm or '(inicio)'} -> {to}")

    # Diagnóstico del gap can_flame / latent_viable
    print("\n=== DIAGNÓSTICO GAP ESTRUCTURAL ===")
    print("  Umbrales con fire_o2_min_for_flame=0.10 (defaults):")
    print("    can_flame=false cuando o2 < 0.085  (o2_min_for_flame - 0.015)")
    print("    latent_viable=false cuando o2 < 0.108  (o2_min_for_flame + latent_o2_viable_margin=0.008)")
    print("    → GAP 8.5–10.8%: ni llama ni latencia → extinción directa")


def main() -> None:
    skip_run = "--no-run" in sys.argv
    if not skip_run:
        _run_case()
    else:
        print("[audit] --no-run: usando CSV existente.")

    rows = _load_csv()
    print(f"\n[audit] {len(rows)} filas cargadas (room_id={WATCH_ROOM_ID}, it.2).\n")

    step = 1 if "--all" in sys.argv else 10
    _print_header()
    prev_regime = ""
    for row in rows:
        t = float(row.get("time_s", 0.0))
        regime = row.get("combustion_regime", "").strip()
        if regime != prev_regime or int(t) % step == 0:
            parts = [_fmt(col, row.get(col, "")) for col in DIAG_COLS]
            print("  ".join(parts))
        prev_regime = regime

    transitions = _detect_transitions(rows)
    _print_summary(rows, transitions)


if __name__ == "__main__":
    main()
