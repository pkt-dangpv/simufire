"""
gap_inventory_check.py — Verifica que el conteo de gaps documentado en GAPS_INVENTORY.md
coincide con el reporte de validación real (reference_checks.json).

Uso:
    python scripts/simulation/gap_inventory_check.py
    python scripts/simulation/gap_inventory_check.py --json path/to/reference_checks.json
    python scripts/simulation/gap_inventory_check.py --inventory path/to/GAPS_INVENTORY.md

Salida:
    - Resumen de required checks (PASS/FAIL)
    - Conteo de gaps real vs documentado
    - Breakdown de gaps por categoría (aproximado, basado en nombre de check)
    - Aviso explícito si el conteo de GAPS_INVENTORY.md no coincide con el JSON

Código de salida:
    0 — all_required_pass=True y conteo documentado coincide con el real
    1 — required failure o mismatch en el conteo de gaps
"""

import json
import re
import sys
import argparse
from pathlib import Path

# En Windows, piped stdout puede usar cp1252; reconfigure para UTF-8 si disponible
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# ---------------------------------------------------------------------------
# VALID_GAP — required checks cuyo FAIL es estructural y está aceptado.
#
# Documentados en docs/validation/GAPS_INVENTORY.md §"Los 5 fallos required
# VALID_GAP".  No son gaps non-gating: son checks required que fallan por
# limitaciones arquitectónicas (Phase 2 / Phase 3+) sin fix per-caso viable.
# El gate de required checks PASA si el conjunto de required fallidos es
# exactamente un subconjunto de esta lista; cualquier fallo required NUEVO
# sigue disparando exit 1.
#
# Regla: solo se añade una entrada aquí con su fila correspondiente en la
# tabla VALID_GAP de GAPS_INVENTORY.md (mismo commit).  Si un check de esta
# lista empieza a PASAR, elimínalo de ambos sitios.
# ---------------------------------------------------------------------------

KNOWN_VALID_GAP_REQUIRED_FAILURES: frozenset[str] = frozenset({
    # Grupo A — cfast_r0_window_360: plume_lower_mode equilibra zonas
    # bidireccional; SF usa room-avg O2 vs CFAST upper-zone O2.  Cierre: Phase 2.
    "cfast_t240_o2_depleted",
    "cfast_t350_o2",
    "cfast_t360_o2",
    # Grupo C — cfast_corridor_chain: falta ODE de presión dos zonas
    # (upper-layer outflow entálpico).  Cierre: Phase 3+.
    "cfast_chain_r0_t180_temp_upper_c",
    "cfast_chain_r0_t600_temp_upper_c",
    # Grupo D — cfast_hvac_residential: gap estructural Phase 2C (2026-07-07).
    # SF mezcla O2 uniformemente; CFAST mantiene two-zone con HVAC replenishing
    # la zona inferior y depletando solo la zona superior.  Resultado: SF.o2_upper
    # no depleta hacia ULO2 CFAST (t=180: 0.196 vs 0.132; t=300: 0.161 vs 0.074)
    # y SF.o2_lower no se mantiene near-ambient por HVAC (t=300/450: 0.161/0.129
    # vs CFAST LLO2=0.205).  Cierre requiere arquitectura two-zone explícita
    # con HVAC feed diferenciado por zona (Phase 3+).
    "cfast_hvac_t180_o2",
    "cfast_hvac_t300_o2",
    "cfast_hvac_t300_o2_lower",
    "cfast_hvac_t450_o2_lower",
})


def classify_required_failures(checks: list[dict]) -> tuple[list[str], list[str]]:
    """
    Separa los required checks fallidos en (valid_gap, unexpected).

    valid_gap  — fallos listados en KNOWN_VALID_GAP_REQUIRED_FAILURES (aceptados)
    unexpected — cualquier otro fallo required (debe disparar exit 1)
    """
    failed = [c["name"] for c in checks if c.get("required") and not c.get("pass")]
    valid_gap = [n for n in failed if n in KNOWN_VALID_GAP_REQUIRED_FAILURES]
    unexpected = [n for n in failed if n not in KNOWN_VALID_GAP_REQUIRED_FAILURES]
    return valid_gap, unexpected


def stale_valid_gap_entries(checks: list[dict]) -> list[str]:
    """Entradas VALID_GAP cuyo check ahora PASA (candidatas a retirarse)."""
    passing = {c["name"] for c in checks if c.get("required") and c.get("pass")}
    return sorted(KNOWN_VALID_GAP_REQUIRED_FAILURES & passing)


# ---------------------------------------------------------------------------
# Categorías (basadas en patrones en el nombre del check)
# Las reglas se evalúan en orden; la primera que coincide gana.
# "resto" captura todo lo que no encaje en las categorías anteriores.
# ---------------------------------------------------------------------------

CATEGORIES: list[tuple[str, callable]] = [
    ("Stage-B pending",               lambda n: n.endswith("_pending")),
    ("Presión termódinámica",         lambda n: "pressure_pa" in n),
    ("O₂ zona inferior",              lambda n: ("_o2" in n or n.endswith("_o2")) and "co2" not in n),
    ("CO₂ upper layer",               lambda n: "co2_upper" in n or "co2_upper_pct" in n),
    ("CO lower zone reporting",       lambda n: "co_lower_ppm" in n),
    ("Calibración puntual",           lambda n: n.startswith("ghanekar") or n.startswith("g3_")),
    ("RMSE temperatura superior",     lambda n: "rmse_temp" in n or "rmse_hot" in n),
    ("Phase 1.5 / Flashover / FED",   lambda n: "fed" in n or "_fo_" in n or "flashover" in n
                                                or "peak_temp" in n or "fo_" in n),
    ("Temp / HRR / Layer (otros)",    lambda n: "temp_upper" in n or "hrr" in n
                                                or "hot_layer" in n),
    ("Escenarios complejos",          lambda _: True),   # catch-all
]


def categorize(name: str) -> str:
    for label, pred in CATEGORIES:
        if pred(name):
            return label
    return "Sin categoría"


# ---------------------------------------------------------------------------
# Extrae el número de gaps de GAPS_INVENTORY.md
# Busca la línea: **Estado validación**: 289/289 PASS required, N gaps non-gating
# ---------------------------------------------------------------------------

_GAP_HEADER_RE = re.compile(r"(\d+)\s+gaps?\s+non-gating", re.IGNORECASE)


def extract_documented_gap_count(inventory_path: Path) -> int | None:
    try:
        text = inventory_path.read_text(encoding="utf-8")
    except OSError:
        return None
    m = _GAP_HEADER_RE.search(text)
    return int(m.group(1)) if m else None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compara conteo de gaps documentado en GAPS_INVENTORY.md con reference_checks.json."
    )
    parser.add_argument("--json", default=None, metavar="PATH",
                        help="Ruta a reference_checks.json")
    parser.add_argument("--inventory", default=None, metavar="PATH",
                        help="Ruta a GAPS_INVENTORY.md")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent.parent
    json_path = Path(args.json) if args.json else repo_root / "sim/validation/reports/reference_checks.json"
    inv_path  = Path(args.inventory) if args.inventory else repo_root / "docs/validation/GAPS_INVENTORY.md"

    W = 72
    print()
    print("=" * W)
    print("  Gap Inventory Check — SimuFire")
    print("=" * W)

    # -- Cargar JSON ---------------------------------------------------------
    if not json_path.exists():
        print(f"\n  ERROR: no se encontró {json_path}")
        print("  Ejecuta: python scripts/simulation/validate_reference_cases.py\n")
        return 1

    data = json.loads(json_path.read_text(encoding="utf-8"))
    checks: list[dict] = data.get("checks", [])

    all_req_pass:   bool = data.get("all_required_pass", False)
    req_count:      int  = data.get("required_count", 0)
    failed_req:     int  = data.get("failed_required_count", 0)
    known_gap_json: int  = data.get("known_gap_count", 0)

    # -- Required summary ----------------------------------------------------
    valid_gap_fails, unexpected_fails = classify_required_failures(checks)
    # Guardia de consistencia: si el JSON declara fallos required pero no
    # encontramos ninguno en checks, el reporte está corrupto → gatear.
    if not all_req_pass and not valid_gap_fails and not unexpected_fails:
        unexpected_fails = ["<inconsistencia: all_required_pass=False sin checks required fallidos>"]
    req_ok = not unexpected_fails
    req_icon = "✓" if req_ok else "✗"
    print()
    print(f"  Required checks  : {req_count}")
    print(f"  Failed required  : {failed_req}  {req_icon}")
    if valid_gap_fails:
        print(f"    de los cuales VALID_GAP permitidos: {len(valid_gap_fails)} "
              f"(documentados en GAPS_INVENTORY.md)")
    if unexpected_fails:
        print(f"    NO PERMITIDOS ({len(unexpected_fails)}):")
        for n in unexpected_fails:
            print(f"      - {n}")
    stale = stale_valid_gap_entries(checks)
    if stale:
        print(f"    NOTA: {len(stale)} entrada(s) VALID_GAP ahora PASAN — retirar de la allowlist:")
        for n in stale:
            print(f"      - {n}")
    print(f"  Gaps (JSON)      : {known_gap_json}")

    # -- Contar non-gating failures ------------------------------------------
    non_gating_fails = [c for c in checks if not c["pass"] and not c["required"]]
    real_gap_count = len(non_gating_fails)

    if real_gap_count != known_gap_json:
        print(f"\n  ⚠ MISMATCH interno: known_gap_count={known_gap_json} pero "
              f"non-gating FAIL contados={real_gap_count}")

    # -- Comparar con GAPS_INVENTORY.md --------------------------------------
    documented = extract_documented_gap_count(inv_path)
    if documented is None:
        print(f"\n  ADVERTENCIA: no se pudo leer/parsear {inv_path}")
        doc_match = False
    else:
        doc_match = (documented == known_gap_json)
        print(f"  Gaps (GAPS_INVENTORY.md): {documented}")
        if doc_match:
            print("  ✓ Conteo coincide")
        else:
            print(f"  ✗ MISMATCH: documentado={documented}, real={known_gap_json}")

    # -- Breakdown por categoría ---------------------------------------------
    from collections import Counter
    cat_counts: Counter = Counter()
    cat_names: dict[str, list[str]] = {}
    for c in non_gating_fails:
        cat = categorize(c["name"])
        cat_counts[cat] += 1
        cat_names.setdefault(cat, []).append(c["name"])

    print()
    print(f"  Breakdown de {real_gap_count} gaps (categorías aproximadas):")
    print()
    print(f"  {'Categoría':<36}  {'N':>3}  Checks (primero)")
    print(f"  {'-'*36}  ---  " + "-" * 26)
    for label, _ in CATEGORIES:
        n = cat_counts.get(label, 0)
        if n == 0:
            continue
        samples = ", ".join(cat_names[label][:2])
        if len(cat_names[label]) > 2:
            samples += f", … (+{n-2})"
        print(f"  {label:<36}  {n:>3}  {samples}")

    # catch-all label
    ca_label = "Escenarios complejos"
    extra = set(cat_counts.keys()) - {lbl for lbl, _ in CATEGORIES} - {ca_label}
    for lbl in sorted(extra):
        n = cat_counts[lbl]
        samples = ", ".join(cat_names[lbl][:2])
        print(f"  {lbl:<36}  {n:>3}  {samples}")

    # -- Resultado final -----------------------------------------------------
    print()
    print("-" * W)
    print()

    problems: list[str] = []
    if unexpected_fails:
        problems.append(f"required FAIL no permitidos: {len(unexpected_fails)} checks")
    if not doc_match and documented is not None:
        problems.append(f"conteo documentado ({documented}) ≠ real ({known_gap_json})")
    if real_gap_count != known_gap_json:
        problems.append("mismatch interno en JSON (known_gap_count vs conteo real)")

    if not problems:
        vg_note = f" (+{len(valid_gap_fails)} VALID_GAP permitidos)" if valid_gap_fails else ""
        print("  ✓ OK — reporte y documentación sincronizados.")
        print(f"    {req_count} required{vg_note}  |  {known_gap_json} gaps non-gating")
    else:
        print("  ✗ DESINCRONIZACIÓN detectada:")
        for p in problems:
            print(f"    • {p}")
        print()
        if unexpected_fails:
            print("  → Revisar required failures antes de cualquier otra acción.")
        if not doc_match and documented is not None:
            print("  → Actualizar el encabezado de docs/validation/GAPS_INVENTORY.md con el conteo real.")

    print("=" * W)
    print()

    return 0 if (req_ok and doc_match and real_gap_count == known_gap_json) else 1


if __name__ == "__main__":
    sys.exit(main())
