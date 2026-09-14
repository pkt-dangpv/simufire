"""
R0-4: Informe de credibilidad de la suite de validación.

Lee tolerance_provenance.csv (R0-1) y reference_checks.json y genera
un informe Markdown con:
  - % de checks por categoría
  - Los 20 checks más problemáticos
  - Lista de overrides de física en casos de validación
  - Kill rate si existe mutation_results.json (R0-2)
  - Recomendaciones priorizadas para R1

USO:
    python tools/credibility_report.py
    python tools/credibility_report.py --output docs/audits/CREDIBILITY_REPORT.md
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROVENANCE_CSV = ROOT / "tools/reports/tolerance_provenance.csv"
CHECKS_JSON = ROOT / "sim/validation/reports/reference_checks.json"
MUTATION_JSON = ROOT / "tools/reports/mutation_results.json"
OVERRIDE_REGISTRY = ROOT / "sim/validation/override_registry.json"

# Claves de motor consideradas "overrides de física" (no de escenario)
# Un caso de validación NO debe contener estas claves.
# Claves que son claramente knobs del motor (no inputs del escenario).
# fire_alpha_kw_s2 NO está aquí porque es la tasa de crecimiento del fuego del
# experimento (especificación del escenario), aunque puede abusarse como tuning.
PHYSICS_OVERRIDE_KEYS = {
    "fire_hrr_global_multiplier",       # mutant-only
    "vent_bernoulli_flow_multiplier",   # mutant-only
    "two_zone_convective_heat_multiplier",
    "doorway_o2_upper_routing_gain",
    "phase2h_lower_cf_drain_coeff",
    "outside_open_upper_heat_boost",
    "fire_co_vent_limited_multiplier",
    "background_species_exchange_kg_s_m2",
    "hot_gas_species_carry_fraction",
}


def load_provenance() -> list[dict]:
    if not PROVENANCE_CSV.exists():
        return []
    with open(PROVENANCE_CSV, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_checks() -> list[dict]:
    if not CHECKS_JSON.exists():
        return []
    data = json.loads(CHECKS_JSON.read_text(encoding="utf-8"))
    return data.get("checks", [])


def find_physics_overrides() -> list[dict[str, str]]:
    """Busca overrides de física del motor en casos de validación."""
    cases_dir = ROOT / "sim/validation/cases"
    violations: list[dict[str, str]] = []
    for case_file in sorted(cases_dir.glob("*.json")):
        try:
            case = json.loads(case_file.read_text(encoding="utf-8"))
        except Exception:
            continue
        overrides = case.get("engine_overrides", {})
        for key in overrides:
            if key in PHYSICS_OVERRIDE_KEYS:
                violations.append({
                    "case": case_file.stem,
                    "key": key,
                    "value": str(overrides[key]),
                })
    return violations


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="R0-4: Informe de credibilidad.")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/audits/CREDIBILITY_REPORT.md")
    args = parser.parse_args()

    provenance = load_provenance()
    checks = load_checks()
    physics_overrides = find_physics_overrides()
    mutation_results = None
    if MUTATION_JSON.exists():
        mutation_results = json.loads(MUTATION_JSON.read_text(encoding="utf-8"))

    # ── Estadísticas por categoría ────────────────────────────────────────────
    from collections import Counter
    required_rows = [r for r in provenance if r.get("required") == "True"]
    cat_counts = Counter(r["category"] for r in required_rows)
    total_req = len(required_rows)

    def pct(n: int) -> str:
        return f"{n/total_req*100:.1f}%" if total_req else "n/a"

    # ── Top 20 problemáticos ──────────────────────────────────────────────────
    problematic = [
        r for r in required_rows
        if r["category"] in ("FITTED", "VACUOUS", "WINDOWED")
    ]
    # Sort: FITTED primero, luego por diff_over_tol desc
    def sort_key(r: dict) -> tuple:
        order = {"FITTED": 0, "WINDOWED": 1, "VACUOUS": 2}
        return (order.get(r["category"], 9), -float(r["diff_over_tol"] or 0))
    problematic.sort(key=sort_key)

    # ── Redactar informe ──────────────────────────────────────────────────────
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    lines: list[str] = []

    lines += [
        f"# Informe de credibilidad de la suite de validación",
        f"",
        f"**Fecha:** {now}  ",
        f"**Base:** `reference_checks.json` (381 required)  ",
        f"**Generado por:** `python tools/credibility_report.py`",
        f"",
        f"---",
        f"",
        f"## 1. Resumen ejecutivo",
        f"",
        f"| Categoría | Required | % |",
        f"|---|---|---|",
    ]
    categories = ["A_PRIORI", "CONSERVATION", "FITTED", "WINDOWED", "VACUOUS"]
    for cat in categories:
        n = cat_counts.get(cat, 0)
        lines.append(f"| {cat} | {n} | {pct(n)} |")
    lines += [
        f"",
        f"**Checks con poder de detección real (A_PRIORI + CONSERVATION):** "
        f"{cat_counts.get('A_PRIORI',0) + cat_counts.get('CONSERVATION',0)}/{total_req} "
        f"({pct(cat_counts.get('A_PRIORI',0) + cat_counts.get('CONSERVATION',0))})",
        f"",
        f"**Checks con baja credibilidad (FITTED + WINDOWED + VACUOUS):** "
        f"{sum(cat_counts.get(c,0) for c in ('FITTED','WINDOWED','VACUOUS'))}/{total_req} "
        f"({pct(sum(cat_counts.get(c,0) for c in ('FITTED','WINDOWED','VACUOUS')))})",
        f"",
    ]

    # ── Kill rate ─────────────────────────────────────────────────────────────
    if mutation_results:
        kr = mutation_results.get("kill_rate_global", None)
        killed = mutation_results.get("killed_count", 0)
        total_m = mutation_results.get("total_mutants", 0)
        lines += [
            f"## 2. Kill rate de mutation testing (R0-2)",
            f"",
            f"**Kill rate global: {killed}/{total_m} mutantes detectados "
            f"({kr*100:.0f}% — objetivo: ≥90%)**",
            f"",
            f"| Mutante | Estado | Fallos/Req | Kill% | Muestra checks muertos |",
            f"|---|---|---|---|---|",
        ]
        for m_id, r in mutation_results.get("mutants", {}).items():
            status = "KILLED" if r["killed"] else "**SURVIVED**"
            sample = ", ".join(r["failed_check_names"][:2]) if r.get("failed_check_names") else "-"
            kr_pct = f"{r.get('kill_rate',0)*100:.1f}%"
            lines.append(
                f"| {m_id} | {status} | "
                f"{r['checks_failed_by_mutation']}/{r['required_checks_evaluated']} | "
                f"{kr_pct} | {sample} |"
            )
        lines.append("")
        survived = [m for m, r in mutation_results.get("mutants", {}).items() if not r["killed"]]
        if survived:
            lines += [
                f"> **Acción R1:** diseñar ≥1 check nuevo que detecte cada mutante SURVIVED: "
                f"{', '.join(survived)}.",
                f"",
            ]
    else:
        lines += [
            f"## 2. Kill rate de mutation testing (R0-2)",
            f"",
            f"> Kill rate no medido aún. Ejecutar `python tools/mutation_audit.py` con Godot.",
            f"",
        ]

    # ── Top problemáticos ─────────────────────────────────────────────────────
    lines += [
        f"## 3. Los {min(20, len(problematic))} checks required con menor credibilidad",
        f"",
        f"| # | Nombre | Categoría | Razón | actual | expected | tol |",
        f"|---|---|---|---|---|---|---|",
    ]
    for i, r in enumerate(problematic[:20], 1):
        lines.append(
            f"| {i} | `{r['name']}` | {r['category']} | {r['reason'][:60]} "
            f"| {r['actual']} | {r['expected']} | {r['tolerance']} |"
        )
    lines.append("")

    # ── Overrides de física ───────────────────────────────────────────────────
    lines += [
        f"## 4. Overrides de física del motor en casos de validación ({len(physics_overrides)})",
        f"",
        f"Regla R1-3: ningún caso bajo `sim/validation/` debe contener claves de "
        f"parámetros del motor (solo inputs del escenario).",
        f"",
    ]
    if physics_overrides:
        lines += [
            f"| Caso | Clave | Valor |",
            f"|---|---|---|",
        ]
        for v in physics_overrides:
            lines.append(f"| `{v['case']}` | `{v['key']}` | `{v['value']}` |")
        lines.append("")
    else:
        lines.append("> Sin overrides de física detectados. ✓\n")

    # ── Recomendaciones R1 ────────────────────────────────────────────────────
    n_fitted = cat_counts.get("FITTED", 0)
    n_vacuous = cat_counts.get("VACUOUS", 0)
    n_windowed = cat_counts.get("WINDOWED", 0)
    lines += [
        f"## 5. Recomendaciones prioritarias para R1",
        f"",
        f"1. **Reclasificar {n_fitted} checks FITTED** a KNOWN_DEVIATION: revertir tolerancias "
        f"a los valores a priori de §6.2 de la auditoría y reclasificar como Nivel III "
        f"con ficha de causa.",
        f"",
        f"2. **Endurecer o eliminar {n_vacuous} checks VACUOUS**: los 2 con ratio > 5× "
        f"(hot_layer_m) deben reformularse. Los checks de mínimo trivial (min: 1 ppm HCN) "
        f"deben reemplazarse por bandas bilaterales.",
        f"",
        f"3. **Publicar RMSE de ventana completa** en los {n_windowed} checks WINDOWED: "
        f"añadir el RMSE total como métrica no-gating además del RMSE truncado.",
        f"",
        f"4. **Linter R1-3**: activar la comprobación de overrides de física como "
        f"check pre-commit (los {len(physics_overrides)} overrides detectados deben "
        f"eliminarse antes de R2).",
        f"",
        f"5. **Medir kill rate real** ejecutando `python tools/mutation_audit.py` — "
        f"cada mutante SURVIVED define exactamente qué check diseñar.",
        f"",
        f"---",
        f"",
        f"*Generado por `tools/credibility_report.py` — R0-4 de la hoja de ruta R0–R5.*",
    ]

    # ── Escribir ──────────────────────────────────────────────────────────────
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")
    print(f"Informe escrito: {args.output}")
    print(f"  A_PRIORI+CONSERVATION: {cat_counts.get('A_PRIORI',0)+cat_counts.get('CONSERVATION',0)}/{total_req}")
    print(f"  FITTED+VACUOUS+WINDOWED: {sum(cat_counts.get(c,0) for c in ('FITTED','WINDOWED','VACUOUS'))}/{total_req}")
    if physics_overrides:
        print(f"  Overrides de fisica en validacion: {len(physics_overrides)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
