"""
validation_guardrails.py — Entrypoint único para verificar el estado de salud de SimuFire
antes de cualquier cambio de código.

Ejecuta (silenciosamente) la lógica de:
  - phase2e_preflight.py   → 7 checks sentinel de Phase 2E
  - gap_inventory_check.py → sincronización de conteo de gaps

Uso:
    python scripts/simulation/validation_guardrails.py
    python scripts/simulation/validation_guardrails.py --json path/to/reference_checks.json
    python scripts/simulation/validation_guardrails.py --verbose   # muestra salida completa

Código de salida:
    0 — todos los guardrails PASS
    1 — algún guardrail FAIL
"""

import sys
import io
import json
import argparse
import contextlib
from pathlib import Path

# En Windows, piped stdout puede usar cp1252; reconfigure para UTF-8 si disponible
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Añadir el directorio de scripts al path para importar los módulos hermanos
_scripts_dir = Path(__file__).resolve().parent
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import phase2e_preflight
import gap_inventory_check
import legacy_two_zone_compare


# ---------------------------------------------------------------------------
# PHY-C1 — Carbon/HCN sentinel checks
# ---------------------------------------------------------------------------

# Checks que deben estar presentes, ser required=True y pass=True en reference_checks.json.
# Confirman que: (a) el balance elemental de carbono incluye HCN (SF-AUD-032), y
# (b) HCN se produce en casos PU foam con yield calibrado (PHY-C2, Purser bounds).
_CARBON_HCN_SENTINELS: list[str] = [
    "c_balance_high_phi_room_0_peak_c_balance_frac",
    "pu_sofa_fec_incapacitation_room_0_peak_c_balance_frac",
    "pu_sofa_fec_incapacitation_room_0_peak_hcn_upper_ppm",
    "victim_fed_incapacitation_room_0_peak_c_balance_frac",
    "victim_fed_incapacitation_room_0_peak_hcn_upper_ppm",
]


def _check_carbon_hcn_sentinels(data: dict) -> tuple[int, str]:
    """
    Verifica que los checks sentinel de balance C/HCN estén presentes,
    sean required=True y pasen. Devuelve (exit_code, summary_str).
    """
    checks_by_name = {c["name"]: c for c in data.get("checks", [])}
    lines: list[str] = []
    failed = False
    for sentinel in _CARBON_HCN_SENTINELS:
        c = checks_by_name.get(sentinel)
        if c is None:
            lines.append(f"  MISSING  {sentinel}")
            failed = True
        elif not c.get("required", False):
            lines.append(f"  NOT-REQ  {sentinel}  (actual={c.get('actual')})")
            failed = True
        elif not c.get("pass", False):
            lines.append(f"  FAIL     {sentinel}  (actual={c.get('actual')})")
            failed = True
        else:
            lines.append(f"  PASS     {sentinel}  (actual={c.get('actual')})")
    return (1 if failed else 0, "\n".join(lines))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _run_silent(fn: callable, extra_argv: list[str] | None = None) -> tuple[int, str]:
    """Ejecuta fn() con stdout redirigido; devuelve (exit_code, output_str)."""
    old_argv = sys.argv[:]
    if extra_argv is not None:
        sys.argv = [sys.argv[0]] + extra_argv
    buf = io.StringIO()
    rc = 1
    try:
        with contextlib.redirect_stdout(buf):
            rc = fn()
    except SystemExit as e:
        rc = e.code if isinstance(e.code, int) else 1
    finally:
        sys.argv = old_argv
    return rc, buf.getvalue()


def _load_json(json_path: Path) -> dict | None:
    try:
        return json.loads(json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validation guardrails — verifica todos los checks de salud de SimuFire."
    )
    parser.add_argument(
        "--json", default=None, metavar="PATH",
        help="Ruta a reference_checks.json (por defecto: sim/validation/reports/reference_checks.json)",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Mostrar la salida completa de cada guardrail además del resumen.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    json_path = Path(args.json) if args.json else repo_root / "sim/validation/reports/reference_checks.json"

    if not json_path.exists():
        print(f"\n  ERROR: no se encontró {json_path}")
        print("  Ejecuta: python scripts/simulation/validate_reference_cases.py\n")
        return 1

    # Argumentos a pasar a cada sub-script
    json_argv = ["--json", str(json_path)]

    W = 72
    _src = json_path.relative_to(repo_root) if json_path.is_relative_to(repo_root) else json_path
    print()
    print("=" * W)
    print("  Validation Guardrails — SimuFire")
    print(f"  Fuente: {_src}")
    print("=" * W)

    # -- Leer JSON para resumen propio ------------------------------------------
    data = _load_json(json_path)
    req_count    = data.get("required_count",    "?") if data else "?"
    failed_req   = data.get("failed_required_count", "?") if data else "?"
    all_req_pass = data.get("all_required_pass", False) if data else False
    gap_count    = data.get("known_gap_count",   "?") if data else "?"

    # -- Ejecutar guardrails ----------------------------------------------------
    rc_sentinel, out_sentinel = _run_silent(phase2e_preflight.main, json_argv)
    rc_gaps,     out_gaps     = _run_silent(gap_inventory_check.main, json_argv)
    rc_carbon,   out_carbon   = (0, "(sin datos)") if data is None else _check_carbon_hcn_sentinels(data)
    rc_two_zone, out_two_zone = _run_silent(legacy_two_zone_compare.main, ["check-reference"])

    # -- Resumen compacto -------------------------------------------------------
    def _tag(rc: int) -> str:
        return "PASS" if rc == 0 else "FAIL"

    req_icon  = "OK" if all_req_pass else "!!"
    req_label = f"{req_count}/{req_count} PASS" if all_req_pass else f"FAIL ({failed_req} fallidos)"

    print()
    print(f"  {'Guardrail':<32}  {'Resultado':>10}")
    print(f"  {'-'*32}  {'-'*10}")
    print(f"  {'Required checks':<32}  {req_label:>12}  [{req_icon}]")
    print(f"  {'Known gaps (JSON)':<32}  {str(gap_count):>12}")
    print(f"  {'Gap inventory sync':<32}  {_tag(rc_gaps):>12}")
    print(f"  {'Phase 2E sentinels (7)':<32}  {_tag(rc_sentinel):>12}")
    print(f"  {'Carbon/HCN sentinels (5)':<32}  {_tag(rc_carbon):>12}")
    print(f"  {'Legacy/two-zone contract':<32}  {_tag(rc_two_zone):>12}")

    # -- Salida verbose ---------------------------------------------------------
    if args.verbose:
        print()
        print("─" * W)
        print("  [Detalle] Phase 2E Preflight")
        print("─" * W)
        print(out_sentinel)
        print("─" * W)
        print("  [Detalle] Gap Inventory Check")
        print("─" * W)
        print(out_gaps)
        print("─" * W)
        print("  [Detalle] Carbon/HCN Sentinels (PHY-C1/C2)")
        print("─" * W)
        print(out_carbon)
        print("─" * W)
        print("  [Detalle] Legacy/two-zone contract (Pre-M1)")
        print("─" * W)
        print(out_two_zone)

    # -- Resultado global -------------------------------------------------------
    all_ok = all_req_pass and rc_sentinel == 0 and rc_gaps == 0 and rc_carbon == 0 and rc_two_zone == 0
    print()
    print("-" * W)
    print()
    if all_ok:
        print("  ALL GUARDRAILS PASS -- working tree listo.")
    else:
        print("  GUARDRAIL(S) FAILED:")
        if not all_req_pass:
            print(f"    - Required checks: {failed_req} FAIL(s)")
        if rc_sentinel != 0:
            print("    - Phase 2E sentinels: ejecuta --verbose para detalles")
        if rc_gaps != 0:
            print("    - Gap inventory sync: ejecuta --verbose para detalles")
        if rc_carbon != 0:
            print("    - Carbon/HCN sentinels: ejecuta --verbose para detalles")
        if rc_two_zone != 0:
            print("    - Legacy/two-zone contract: regenera o corrige la referencia Pre-M1")
        print()
        print("  Para diagnóstico completo:")
        print("    python scripts/simulation/validation_guardrails.py --verbose")

    print("=" * W)
    print()

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
