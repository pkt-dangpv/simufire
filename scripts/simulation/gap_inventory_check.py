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
    req_icon = "✓" if all_req_pass else "✗"
    print()
    print(f"  Required checks  : {req_count}")
    print(f"  Failed required  : {failed_req}  {req_icon}")
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
    if not all_req_pass:
        problems.append(f"required FAIL: {failed_req} checks")
    if not doc_match and documented is not None:
        problems.append(f"conteo documentado ({documented}) ≠ real ({known_gap_json})")
    if real_gap_count != known_gap_json:
        problems.append("mismatch interno en JSON (known_gap_count vs conteo real)")

    if not problems:
        print("  ✓ OK — reporte y documentación sincronizados.")
        print(f"    {req_count} required PASS  |  {known_gap_json} gaps non-gating")
    else:
        print("  ✗ DESINCRONIZACIÓN detectada:")
        for p in problems:
            print(f"    • {p}")
        print()
        if not all_req_pass:
            print("  → Revisar required failures antes de cualquier otra acción.")
        if not doc_match and documented is not None:
            print("  → Actualizar el encabezado de docs/validation/GAPS_INVENTORY.md con el conteo real.")

    print("=" * W)
    print()

    return 0 if (all_req_pass and doc_match and real_gap_count == known_gap_json) else 1


if __name__ == "__main__":
    sys.exit(main())
