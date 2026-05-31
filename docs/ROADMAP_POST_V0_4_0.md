# SimuFire — Roadmap post v0.4.0
**Fecha**: 2026-05-31  
**Estado base**: `v0.4.0-validation-rc1` @ `80f3c09` · 379/379 PASS · 4 gaps non-gating

---

## Estado de cierre v0.4.0

v0.4.0 está **cerrado**. No se realizarán cambios bajo este tag.  
Cualquier trabajo nuevo parte de la rama `main` post-tag y se versionará como v0.4.1+.

| Fase | Estado |
|---|---|
| Phase 2B — transporte multi-habitación | ✅ Cerrada |
| Phase 2C — HVAC two-zone O₂ feed | ✅ Cerrada |
| Phase 3 — presión termodinámica | ✅ Cerrada |
| Phase 4A — HVAC blend candidato | ❌ Rechazado y revertido |
| Phase 4B — HCN/FED descompuesto | ✅ Completada y calibrada |

---

## v0.4.1 — Polish de documentación y outputs

**Objetivo**: ningún cambio de física; mejorar legibilidad y trazabilidad del paquete publicable.

Tareas candidatas:
- Actualizar `docs/PLAN_TRABAJO.md` para eliminar conteos históricos stale (`373/373`, `372/372`, `376/376` en secciones de historial).
- Actualizar `docs/GAPS_INVENTORY.md` para eliminar el mismo tipo de conteos stale en el bloque de historial.
- Revisar nombres de columnas CSV (`sim_log.csv`) para consistencia con nombres de métricas en reportes.
- Mejorar formato de salida de `validate_reference_cases.py`: tabla de checks fallidos con delta y tolerancia.
- README ampliado: descripción del modelo, alcance, limitaciones, referencia a `SIMUFIRE_VALIDATION_SUMMARY`.

**Restricciones**:
- No modificar tolerancias ni baselines.
- No tocar física.
- Requiere que `379/379 PASS` se mantenga tras cualquier cambio en scripts de validación.

---

## v0.4.2 — Reproducibilidad y export limpio

**Objetivo**: que un tercero pueda reproducir la validación completa desde cero con un único comando.

Tareas candidatas:
- Script `scripts/run_all_cases.py` que ejecute todos los casos de validación en secuencia y regenere los reportes.
- Export JSON/CSV de resumen de validación con fecha, commit hash y conteo de checks automáticamente embebido.
- Verificar que `reference_checks.json` sea determinista (mismo motor, mismo caso → misma salida bit a bit o con tolerancia documentada).
- Añadir `REPRODUCIBILITY.md` con instrucciones paso a paso para un revisor externo.

**Restricciones**:
- No cambiar resultados de simulación.
- No modificar baselines ni tolerancias.

---

## v0.5.0 — Mejora física formal (condicional)

**Objetivo**: si hay diseño formal aprobado, implementar la siguiente capa de física real.

Candidatos identificados:
- **HVAC two-zone transport** — resolver los 4 gaps estructurales (`cfast_hvac_t300/t450_co_upper/co2_upper`). Requiere modelo de transporte de contaminantes por capa (no flujo de masa uniforme). **No reabrir Phase 4A blend**: ese camino fue evaluado y rechazado.
- **Suppression / firefighting tactics** — descomentar helpers de supresión (TODO gameplay en `SimulationEngine.gd:1678`) cuando la UI de juego esté implementada.
- **HCN yield por combustible** — yields diferenciados por tipo de material (PVC, madera, textil) si se dispone de datos de literatura validados.

**Proceso requerido para v0.5.0**:
1. Documento de diseño formal antes de tocar código (equivalente a los `PHASE_*.md` anteriores).
2. Rebaseline completa con ≥ 379 checks requeridos PASS.
3. No activar `fire_o2_upper_hrr_blend` sin proceso de validación independiente.

---

## Paper / Report externo

**Objetivo**: publicación académica o informe técnico externo basado en el estado v0.4.0.

Artefactos publicables disponibles:

| Artefacto | Ruta | Tamaño |
|---|---|---|
| Resumen de validación (para terceros) | `docs/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md` | ~10 KB |
| Auditoría de preparación para publicación | `docs/PUBLICATION_READINESS_AUDIT_2026-05-31.md` | ~14 KB |
| Calibración HCN/FED detallada | `docs/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md` | ~8 KB |
| Inventario de gaps | `docs/GAPS_INVENTORY.md` | ~44 KB |
| Resultados de checks (521 checks) | `sim/validation/reports/reference_checks.json` | ~178 KB |

Tareas para el paper:
- Seleccionar figuras representativas desde `graphs/` (curvas HRR, temperatura, CO, FED vs tiempo).
- Tabla de resultados por categoría (§3 del validation summary).
- Sección de limitaciones basada en §5 del publication readiness audit.
- Metodología FED/HCN desde `AUDITORIA_CALIBRACION_FED_HCN`.

---

## Deuda técnica identificada (no bloqueante)

| Ítem | Ubicación | Tipo | Versión sugerida |
|---|---|---|---|
| `TODO(gameplay)` helpers de supresión | `SimulationEngine.gd:1678` | Gameplay diferido | v0.5.0 |
| Conteos históricos stale (`373/373`, `372/372`, etc.) | `GAPS_INVENTORY.md`, `PLAN_TRABAJO.md` — secciones de historial | Cosmético | v0.4.1 |
| 14 ficheros `ESTADO_SESION_*.md` en raíz | Directorio raíz | Ruido de sesión, no publicables | v0.4.1 o ignorar |
| `tools/phase4a_blend_sweep.py` | `tools/` | Artefacto diagnóstico inactivo | Conservar para trazabilidad |

---

## Restricciones permanentes

Estas restricciones se mantienen independientemente de la versión:

- **No cambiar física global sin rebaseline completa** (≥ 379 required PASS).
- **No tocar los 4 gaps HVAC** sin rediseño formal de transporte de capa.
- **No activar `fire_o2_upper_hrr_blend`** — Phase 4A rechazada definitivamente.
- **No modificar tolerancias** de checks existentes sin justificación documentada.
- **Guardrails siempre verdes**: `ALL GUARDRAILS PASS` antes de cualquier commit a `main`.
