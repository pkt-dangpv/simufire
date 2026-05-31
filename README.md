# SimuFire

Simulador de dinámica de incendios en compartimentos para entrenamiento y toma de decisiones de bomberos.

**Estado**: `v0.4.0-validation-rc1` · 379/379 required PASS · 4 gaps no-gating · Godot 4.6.3

---

## Quickstart

```powershell
# 1. Validar suite completa (379 checks)
python scripts/simulation/validate_reference_cases.py

# 2. Guardrails automáticos
python scripts/simulation/validation_guardrails.py

# 3. Tests unitarios
python tests/test_guardrails.py

# 4. Ejecutar un caso individual (headless)
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
| Checks requeridos | **379/379 PASS** |
| Gaps no-gating | 4 (estructurales HVAC, aceptados) |
| Guardrails | ALL PASS |
| Tests unitarios | 13/13 OK |
| Commit | `80f3c09` |

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

---

## Motor

Godot 4.6.3 / GDScript · Windows · Python 3.x para scripts de validación.
