# SimuFire

Simulador de dinámica de incendios en compartimentos para entrenamiento y toma de decisiones de bomberos.

**Estado**: `v0.4.0-validation-rc1` · legacy 381/381 required PASS · two-zone M4 contract PASS opt-in · Godot 4.6.3

---

## Quickstart

```powershell
# 1. Checks de producto/editor (incluye smokes Godot headless)
python scripts/check_product.py         # 57 tests: editor JSON + UI localization + editabilidad Godot + guardrails + export headless

# 2. Guardrails científicos (sin Godot, lee reference_checks.json)
python scripts/simulation/validation_guardrails.py

# 3. Suite completa de validación científica (requiere Godot, ~15 min)
python scripts/simulation/validate_reference_cases.py

# 4. Comparar candidato two-zone v1 contra la referencia legacy congelada
powershell -ExecutionPolicy Bypass -File sim/validation/run_legacy_two_zone_compare.ps1 -Action compare -CandidateMode two-zone -TwoZoneV1 -AllowContractFailure

# 5. Reproducir un escenario predefinido y generar export tecnico
python scripts/run_scenario.py scenarios/compact_apartment_reference.json --duration 60

# 6. Ejecutar un caso individual (headless)
& "C:\Users\dangp\Desktop\Godot_v4.6.3-stable_win64_console.exe" `
    --headless --path "." -- --validation-case=victim_fed_incapacitation
```

---

## Fenómenos modelados

- Combustión: HRR por objeto, pirólisis, factor O₂, extinción, smoldering, backdraft.
- Termodinámica zonal: temperaturas capa superior/inferior, altura de capa de humo, presión termodinámica en recintos sellados.
- Transición: flashover (Thomas + MQH), burnout.
- Productos tóxicos: CO, CO₂, O₂, HCN estratificado upper/lower.
- Tenabilidad: FED descompuesto (CO · HCN · hipoxia · calor) + FEC irritantes + visibilidad.
- Ventilación: vanos (Bernoulli), rotura de cristal, apertura/cierre de puertas, HVAC, PPV.

---

## Validación (v0.4.0)

| Métrica | Valor |
|---|---|
| Checks requeridos | **381/381 PASS** |
| Gaps no-gating | 4 (estructurales HVAC, aceptados) |
| Guardrails científicos | ALL PASS |
| Tests unitarios guardrails | 13/13 OK |
| Tests editor/producto | 57/57 OK |
| Commit base | `80f3c09` |

---

## Artefactos publicables

| Documento | Contenido |
|---|---|
| [docs/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md](docs/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md) | Resumen de validación para terceros |
| [docs/PUBLICATION_READINESS_AUDIT_2026-05-31.md](docs/PUBLICATION_READINESS_AUDIT_2026-05-31.md) | Auditoría interna pre-publicación |
| [docs/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md](docs/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md) | Calibración HCN/FED |
| [docs/GAPS_INVENTORY.md](docs/GAPS_INVENTORY.md) | Inventario de gaps |
| [docs/ROADMAP_POST_V0_4_0.md](docs/ROADMAP_POST_V0_4_0.md) | Roadmap v0.4.1+ |

---

## Limitaciones conocidas

- **HVAC two-zone transport**: 4 checks CO/CO₂ upper con HVAC divergen de CFAST (gaps no-gating aceptados). No afectan escenarios de tenabilidad.
- **HCN yield conservador**: representa combustión bien ventilada; subestima HCN bajo-ventilado.
- **Modelo zonal**: no sustituye simulaciones CFD (p. ej. FDS) para análisis cuantitativo de alto rigor.
- **Two-zone v1.0 opt-in**: masa/energía, O2 local y flujos de apertura por zona activos por flags; el preset de validación `-TwoZoneV1` activa `two-zone + two_zone_opening_flow + canonical_pressure` y compara contra legacy con **18/18 required PASS**. `fire_o2_mode=upper` queda explícito, no default global, porque aún introduce regresiones HRR/temperatura al forzarlo en todos los casos.

---

## Motor

Godot 4.6.3 / GDScript · Windows · Python 3.x para scripts de validación.
