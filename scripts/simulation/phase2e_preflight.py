"""
phase2e_preflight.py — Preflight check para Phase 2E arquitectónica.

Lee sim/validation/reports/reference_checks.json (generado por validate_reference_cases.py)
y reporta los checks sentinel que Phase 2E puede afectar:
  - g4: timing FED, timing CO upper, peak CO upper
  - v3: hallway FED timing, hallway max FED
  - victim_fed: FED final, peak CO global

Uso:
    python scripts/simulation/phase2e_preflight.py
    python scripts/simulation/phase2e_preflight.py --json path/to/reference_checks.json

Salida por check:
    actual | bound (exp ±tol / min / max) | margin to boundary | PASS/FAIL

Código de salida:
    0 — todos los sentinels PASS
    1 — algún sentinel FAIL o no encontrado en el reporte
"""

import json
import sys
import argparse
from pathlib import Path

# ---------------------------------------------------------------------------
# Definición de checks sentinel
# ---------------------------------------------------------------------------

SENTINELS = [
    # (name, label_corto, riesgo)
    (
        "g4_gie_delayed_entry_hazard_time_room_1_fed_above_0_1_s",
        "g4  FED timing [s]         ",
        "ALTO — Phase 2E-B/C puede retrasar FED en sala receptora",
    ),
    (
        "g4_gie_delayed_entry_hazard_time_room_1_co_upper_above_1200_s",
        "g4  CO>1200 timing [s]     ",
        "ALTO — Phase 2E-A (CO transport split) cambia co_upper_kg destino",
    ),
    (
        "g4_gie_delayed_entry_hazard_room_1_peak_co_upper_ppm",
        "g4  peak CO upper [ppm]    ",
        "MEDIO — peak en sala fuego; solo si carry fraction cambia",
    ),
    (
        "v3_hallway_fed_exposure_time_room_1_fed_above_0_1_s",
        "v3  hallway FED timing [s] ",
        "ALTO — pasillo receptor; Phase 2E-A/B afecta directamente",
    ),
    (
        "v3_hallway_fed_exposure_room_1_max_fed",
        "v3  hallway max FED        ",
        "MEDIO — cota mínima; holgado pero a verificar",
    ),
    (
        "victim_fed_incapacitation_victim_v0_final_fed",
        "victim  final FED          ",
        "ALTO — margen estrecho sobre mínimo 0.7; Phase 2E-B reduce CO lower",
    ),
    (
        "victim_fed_incapacitation_peak_co_ppm_global",
        "victim  peak CO [ppm]      ",
        "BAJO — cota mínima holgada; referencia",
    ),
]


# ---------------------------------------------------------------------------
# Lógica de margen
# ---------------------------------------------------------------------------

def _compute_margin(c: dict) -> tuple[float | None, str]:
    """
    Devuelve (margin, description).
    margin > 0  → cuánto queda antes de FAIL
    margin <= 0 → ya está fallando (o en el límite)
    """
    actual = c["actual"]
    tol = c["tolerance"]
    exp = c["expected"]
    lo = c["minimum"]
    hi = c["maximum"]

    if tol is not None and exp is not None:
        # Check tipo ±tolerancia
        deviation = abs(actual - exp)
        return tol - deviation, f"exp={exp:.4f} ±{tol:.2f}"

    if lo is not None and hi is None:
        # Check tipo minimum
        return actual - lo, f"min={lo:.4f}"

    if hi is not None and lo is None:
        # Check tipo maximum
        return hi - actual, f"max={hi:.4f}"

    if lo is not None and hi is not None:
        return min(actual - lo, hi - actual), f"min={lo:.4f}, max={hi:.4f}"

    return None, "n/a"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Phase 2E preflight — verifica checks sentinel antes de tocar transporte/FED."
    )
    parser.add_argument(
        "--json",
        default=None,
        metavar="PATH",
        help="Ruta al reference_checks.json (por defecto: sim/validation/reports/reference_checks.json)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    json_path = Path(args.json) if args.json else repo_root / "sim/validation/reports/reference_checks.json"

    if not json_path.exists():
        print(f"\nERROR: no se encontró {json_path}")
        print("Ejecuta primero: python scripts/simulation/validate_reference_cases.py\n")
        return 1

    data = json.loads(json_path.read_text(encoding="utf-8"))
    checks_by_name: dict = {c["name"]: c for c in data.get("checks", [])}

    req_count = data.get("required_count", "?")
    gap_count = data.get("known_gap_count", "?")
    all_req_pass = data.get("all_required_pass", None)
    baseline_ok = "✓" if all_req_pass else "✗"

    W = 72
    _src = json_path.relative_to(repo_root) if json_path.is_relative_to(repo_root) else json_path
    print()
    print("=" * W)
    print("  Phase 2E Preflight — Sentinel Required Checks")
    print(f"  Fuente : {_src}")
    print(f"  Suite  : {req_count} required {baseline_ok}  |  {gap_count} non-gating gaps")
    print("=" * W)

    all_pass = True
    missing: list[str] = []

    for name, label, risk in SENTINELS:
        c = checks_by_name.get(name)
        if c is None:
            missing.append(name)
            all_pass = False
            continue

        actual: float = c["actual"]
        status_bool: bool = c["pass"]
        is_required: bool = c.get("required", False)
        margin, bound_desc = _compute_margin(c)

        # Solo los sentinels required gatean.  Un sentinel non-required que
        # falla es un known gap del validador (cuenta en known_gap_count y en
        # GAPS_INVENTORY.md): se reporta con margen pero no bloquea el preflight.
        if not status_bool and is_required:
            all_pass = False

        # Formato margin
        if margin is not None:
            pct = (margin / abs(actual) * 100.0) if actual != 0.0 else float("inf")
            margin_str = f"{margin:+.3f}  ({pct:.1f}% de actual)"
        else:
            margin_str = "n/a"

        if status_bool:
            status_tag = "PASS"
        elif is_required:
            status_tag = "FAIL ←"
        else:
            status_tag = "GAP (non-gating)"
        warn = " ⚠" if (margin is not None and 0 < margin < abs(actual) * 0.05) else ""

        print()
        print(f"  {label}  [{status_tag}{warn}]")
        print(f"    actual  : {actual:.4f}")
        print(f"    bound   : {bound_desc}")
        print(f"    margin  : {margin_str}")
        print(f"    riesgo  : {risk}")

    print()
    print("-" * W)

    if missing:
        print(f"\n  ADVERTENCIA: {len(missing)} check(s) no encontrados en el reporte:")
        for m in missing:
            print(f"    - {m}")
        print("  Regenera con: python scripts/simulation/validate_reference_cases.py")

    print()
    if all_pass and not missing:
        print("  ✓ PREFLIGHT OK — todos los sentinels PASS.")
        print("    Puedes iniciar la rama Phase 2E.")
        print("    Vuelve a ejecutar este script después de cada commit en la rama.")
    else:
        print("  ✗ PREFLIGHT FAIL — NO inicies Phase 2E hasta resolver todos los sentinels.")

    print("=" * W)
    print()

    return 0 if (all_pass and not missing) else 1


if __name__ == "__main__":
    sys.exit(main())
