"""
R0-1: Matriz de procedencia de tolerancias.

Clasifica cada check de reference_checks.json en:
  A_PRIORI    — tolerancia fijada antes de conocer el resultado (o no clasificable en otra categoría)
  FITTED      — tol ≈ |diff| + pad (diff ocupa >85% de la tolerancia)
  WINDOWED    — ventana de comparación truncada para excluir la región de divergencia
  VACUOUS     — margen actual/umbral > 5× o tolerancia > 50% del expected
  CONSERVATION — residual físico (conservación de masa/energía, simetría)
  NON_GATING  — required=False (no afecta al CI)

Salida: tools/reports/tolerance_provenance.csv + resumen impreso por pantalla.
"""

import json
import csv
import sys
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECKS_JSON = ROOT / "sim/validation/reports/reference_checks.json"
OUTPUT_CSV = ROOT / "tools/reports/tolerance_provenance.csv"

# ── palabras clave para checks de conservación ───────────────────────────────
CONSERVATION_KEYWORDS = [
    "carbon_balance", "c_balance", "cbal", "mass_balance", "conservation",
    "residual", "energy_balance", "o2_balance", "species_balance",
    "sentinel", "no_negative", "non_negative",
]

# ── checks cuya nota menciona ventana truncada ────────────────────────────────
WINDOWED_PATTERNS = [
    r"end_t\s*=\s*\d+",          # end_t=350
    r"t=\[0,\s*\d+\]",           # t=[0,350]s or t=[0,240]s
    r"ventana\s+rmse",
    r"rmse\[0,",
    r"window.*truncat",
    r"acotad[ao].*end_t",
    r"over\s+t=\[",              # "over t=[0,240]"
]

# Threshold para FITTED: diff / tol > FITTED_RATIO
FITTED_RATIO = 0.85

# Threshold para VACUOUS_TOL: tol / |expected| > VACUOUS_TOL_RATIO
VACUOUS_TOL_RATIO = 0.50

# Threshold para VACUOUS_MIN: actual / minimum > VACUOUS_MIN_FACTOR
VACUOUS_MIN_FACTOR = 5.0


def classify(check: dict) -> tuple[str, str]:
    """Devuelve (category, reason)."""
    name = check.get("name", "")
    note = (check.get("note") or "").lower()
    required = check.get("required", False)
    actual = check.get("actual")
    expected = check.get("expected")
    tolerance = check.get("tolerance")
    minimum = check.get("minimum")
    maximum = check.get("maximum")

    if not required:
        return "NON_GATING", "required=False"

    # ── CONSERVATION ─────────────────────────────────────────────────────────
    name_lower = name.lower()
    for kw in CONSERVATION_KEYWORDS:
        if kw in name_lower or kw in note:
            return "CONSERVATION", f"keyword '{kw}'"

    # ── WINDOWED ─────────────────────────────────────────────────────────────
    for pat in WINDOWED_PATTERNS:
        if re.search(pat, note, re.IGNORECASE):
            return "WINDOWED", f"note matches /{pat}/"

    # ── VACUOUS (minimum-only check with trivial threshold) ───────────────────
    if minimum is not None and expected is None and tolerance is None and actual is not None:
        if minimum > 0 and actual > VACUOUS_MIN_FACTOR * minimum:
            return "VACUOUS", f"actual={actual:.3g} >> {VACUOUS_MIN_FACTOR}× min={minimum:.3g}"

    # ── VACUOUS (maximum-only check where actual is very far from max) ────────
    if maximum is not None and expected is None and tolerance is None and actual is not None:
        if maximum > 0 and actual < maximum / VACUOUS_MIN_FACTOR:
            return "VACUOUS", f"actual={actual:.3g} << max={maximum:.3g}/{VACUOUS_MIN_FACTOR}"

    # ── checks with expected + tolerance ─────────────────────────────────────
    if expected is not None and tolerance is not None and tolerance > 0:
        diff = abs((actual or 0.0) - expected)

        # FITTED: diff ocupa más del FITTED_RATIO de la tolerancia
        ratio_diff = diff / tolerance
        if ratio_diff > FITTED_RATIO:
            return "FITTED", f"|diff|/tol={ratio_diff:.3f} > {FITTED_RATIO}"

        # VACUOUS: tolerancia > 50% del expected
        if expected != 0:
            ratio_tol = tolerance / abs(expected)
            if ratio_tol > VACUOUS_TOL_RATIO:
                return "VACUOUS", f"tol/|expected|={ratio_tol:.3f} > {VACUOUS_TOL_RATIO}"

    return "A_PRIORI", "no heuristic triggered"


def main():
    sys.stdout.reconfigure(encoding="utf-8")

    if not CHECKS_JSON.exists():
        print(f"ERROR: no se encuentra {CHECKS_JSON}", file=sys.stderr)
        sys.exit(1)

    with open(CHECKS_JSON, encoding="utf-8") as f:
        data = json.load(f)

    checks = data.get("checks", [])
    print(f"Checks cargados: {len(checks)}")

    rows = []
    for c in checks:
        category, reason = classify(c)
        rows.append({
            "name": c.get("name", ""),
            "required": c.get("required", False),
            "pass": c.get("pass", None),
            "category": category,
            "reason": reason,
            "actual": c.get("actual", ""),
            "expected": c.get("expected", ""),
            "tolerance": c.get("tolerance", ""),
            "minimum": c.get("minimum", ""),
            "maximum": c.get("maximum", ""),
            "diff_over_tol": (
                f"{abs((c.get('actual') or 0.0) - (c.get('expected') or 0.0)) / c['tolerance']:.3f}"
                if c.get("tolerance") and c.get("expected") is not None else ""
            ),
            "tol_over_expected": (
                f"{c['tolerance'] / abs(c['expected']):.3f}"
                if c.get("tolerance") and c.get("expected") and c["expected"] != 0 else ""
            ),
            "note": c.get("note", ""),
        })

    # ── escribir CSV ──────────────────────────────────────────────────────────
    fieldnames = [
        "name", "required", "pass", "category", "reason",
        "actual", "expected", "tolerance", "minimum", "maximum",
        "diff_over_tol", "tol_over_expected", "note",
    ]
    with open(OUTPUT_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"CSV escrito en: {OUTPUT_CSV}")
    print()

    # ── resumen ───────────────────────────────────────────────────────────────
    from collections import Counter
    required_rows = [r for r in rows if r["required"]]
    all_cats = Counter(r["category"] for r in rows)
    req_cats = Counter(r["category"] for r in required_rows)

    print("=" * 60)
    print("  MATRIZ DE PROCEDENCIA DE TOLERANCIAS — R0-1")
    print("=" * 60)
    print(f"  Total checks:    {len(rows)}")
    print(f"  Required:        {len(required_rows)}")
    print()
    print(f"  {'Categoría':<14}  {'Total':>7}  {'Required':>9}  {'%req':>6}")
    print(f"  {'-'*14}  {'-'*7}  {'-'*9}  {'-'*6}")
    categories = ["A_PRIORI", "FITTED", "WINDOWED", "VACUOUS", "CONSERVATION", "NON_GATING"]
    for cat in categories:
        total = all_cats.get(cat, 0)
        req = req_cats.get(cat, 0)
        pct = f"{req/len(required_rows)*100:.1f}%" if required_rows else "-"
        print(f"  {cat:<14}  {total:>7}  {req:>9}  {pct:>6}")
    print()

    # Top 10 más problemáticos por categoría
    for cat in ["FITTED", "VACUOUS", "WINDOWED"]:
        subset = [r for r in required_rows if r["category"] == cat]
        if not subset:
            continue
        print(f"  ── {cat} required ({len(subset)}) ──")
        for r in subset[:15]:
            name = r["name"]
            reason = r["reason"]
            print(f"    {name:<55}  {reason}")
        if len(subset) > 15:
            print(f"    ... y {len(subset)-15} más (ver CSV)")
        print()

    # Kill rate note
    fitted_req = req_cats.get("FITTED", 0)
    vacuous_req = req_cats.get("VACUOUS", 0)
    windowed_req = req_cats.get("WINDOWED", 0)
    problematic = fitted_req + vacuous_req + windowed_req
    pct_prob = problematic / len(required_rows) * 100 if required_rows else 0
    print(f"  Checks required con baja credibilidad (FITTED+VACUOUS+WINDOWED): "
          f"{problematic}/{len(required_rows)} ({pct_prob:.1f}%)")
    print()
    print("  CONSERVATION + A_PRIORI = checks con poder de detección real:")
    real_power = req_cats.get("A_PRIORI", 0) + req_cats.get("CONSERVATION", 0)
    print(f"    {real_power}/{len(required_rows)} ({real_power/len(required_rows)*100:.1f}%)")
    print("=" * 60)


if __name__ == "__main__":
    main()
