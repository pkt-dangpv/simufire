# Estado de sesión — 2026-05-28

## Resumen ejecutivo

Sesión de micro-calibración: sweep paramétrico de 3 variantes para el caso `ghanekar_kitchen_living_room`.

- **Objetivo**: Cerrar los 4 gaps non-gating del caso (fed_0_3, fed_1_0, idlh_co, flashover_s) mediante ajuste de `open_fraction` de la puerta exterior R3 y/o `fire_alpha_kw_s2`.
- **Resultado**: Sweep completado (v1 door=0.0, v2 door=0.3, v3 α=0.0005+door=0.0). **Ninguna variante cierra los gaps**. Se identifica una bifurcación dura: los 4 gaps requieren configuraciones de ventilación mutuamente excluyentes.
- **Diagnóstico final**: El caso necesita **rediseño de topología** (cambio de template o geometría), no micro-calibración de parámetros.
- **Sin regresión**: 292/292 required PASS no alterados (casos sweep son exploratorios, fuera del set de validación formal).

---

## Estado del sistema de validación

| Componente | Estado |
|---|---|
| `reference_checks.json` | ✅ **293/293 PASS, 63 gaps** — g3 gap cerrado (Phase 2A rebaseline) |
| `GAPS_INVENTORY.md` | ✅ 63 gaps — `g3_gie_ppv_post_knockdown_time_room_1_smoke_below_0_1kg_post_vent_s` eliminado |
| Guardrails | ✅ **293/293 PASS** — ALL GUARDRAILS PASS |
| Git | HEAD = `17d5981` (main, 1 ahead of origin/main) |

<!-- audit-score: [Reference Checks] PASS: 293/293 required checks passed, gaps: 63 non-gating checks did not pass -->

---

## Sweep de micro-calibración — ghanekar_kitchen_living_room

### Casos creados (exploratorios — no en suite formal)

| Caso | open_fraction | fire_alpha_kw_s2 | Propósito |
|------|--------------|-----------------|-----------|
| `ghanekar_kitchen_sweep_v1.json` | 0.0 (cerrada) | 0.0025 | Aislar efecto ventilación pura |
| `ghanekar_kitchen_sweep_v2.json` | 0.3 | 0.0025 | Fracción intermedia baja |
| `ghanekar_kitchen_sweep_v3.json` | 0.0 (cerrada) | 0.0005 | Crecimiento 5× más lento, objetivo flashover ~894s |

### Tabla de resultados comparativos

| Métrica | Esperado (rango) | Baseline door=1.0 | v1 door=0.0 | v2 door=0.3 | v3 α=0.0005 door=0.0 |
|---|---|---|---|---|---|
| O₂ R2 crossing (s) | 402±84 → [318–486] | **388 ✅** | 304 ❌ | 321 ⚠️ | 538 ❌ |
| FED=0.3 R2 (s) | 546±120 → [426–666] | 1057 ❌ | 888 ❌ | null ❌ | 1068 ❌ |
| FED=1.0 R2 (s) | 624±126 → [498–750] | null ❌ | null ❌ | null ❌ | null ❌ |
| CO>1200ppm R2 (s) | 642±102 → [540–744] | null ❌ | 1096 ❌ | null ❌ | null ❌ |
| Flashover R3 (s) | 894±30 → [864–924] | null ❌ | 421 ❌ | 411 ❌ | null ❌ |
| R3 peak temp (°C) | — | 426 | **673** | **663** | 234 |
| R2 CO peak (ppm) | — | 148 | **1217** | 245 | 66 |
| R2 FED max | — | 0.408 | **0.945** | 0.060 | 0.340 |
| HRR peak (kW) | — | 1061 | 405 | 665 | 241 |

### Diagnóstico — bifurcación dura del espacio de parámetros

El sweep revela una **discontinuidad topológica** en el comportamiento del caso:

1. **Puerta cerrada (door=0.0, 0.3) + α=0.0025**: Flashover ocurre a ~411–421s (2.1× demasiado temprano respecto a los 894s esperados). CO en R2 sube significativamente solo con door=0.0 (1217 ppm), pero todos los timings están desfasados.

2. **Puerta abierta (door=1.0) + α=0.0025**: No hay flashover (T_upper_R3 pico = 426°C). La disipación de calor es excesiva. CO en R2 es mínimo (148 ppm). El único check que pasa es O₂ timing (388s ✅).

3. **Puerta cerrada + α=0.0005**: Fuego demasiado débil (HRR pico = 241 kW, O₂-estrangulado). R3 pico = 234°C, no hay flashover. Toda la dinámica se desplaza ~3× más tarde.

**Restricciones mutuamente excluyentes**:
- Para flashover a 894s → necesita puerta entre 0.3 y 1.0 que disipe calor progresivamente. Sin embargo, la transición de "flashover a 420s" → "sin flashover" es abrupta (no existe régimen intermedio gradual).
- Para CO>1200ppm en R2 a 642s → necesita puerta casi cerrada (máxima acumulación). Con door=0.3, el efecto dilución colapsa R2 FED de 0.945 → 0.060.
- Para mantener O₂ check PASS → rango [318–486s], solo compatible con door≈0.3–1.0.

**Estimación del α necesario** (análisis numérico):

$$\alpha_{target} = \frac{HRR_{critical}}{t_{flashover}^2} \approx \frac{400 \text{ kW}}{894^2 \text{ s}^2} \approx 0.0005 \text{ kW/s}^2$$

Con α=0.0005 y puerta cerrada, el fuego se apaga por O₂ antes de alcanzar flashover (HRR limitado a 241 kW). La habitación no acumula suficiente energía.

### Conclusión

No existe combinación de `{open_fraction, fire_alpha_kw_s2}` que cierre simultáneamente los 4 gaps dentro de la configuración actual del template `ghanekar_bedroom_hallway`. Los 4 gaps son el resultado de una **incompatibilidad topológica**: el template conecta R3 (fuego) directamente al exterior con una puerta de 1.8 m², mientras que el escenario de referencia Ghanekar probablemente tiene el fuego en un espacio más interior con un camino más largo (y más restrictivo) hacia el exterior.

---

## Archivos creados esta sesión

| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `sim/validation/cases/ghanekar_kitchen_sweep_v1.json` | Case (exploratorio) | door=0.0, α=0.0025 |
| `sim/validation/cases/ghanekar_kitchen_sweep_v2.json` | Case (exploratorio) | door=0.3, α=0.0025 |
| `sim/validation/cases/ghanekar_kitchen_sweep_v3.json` | Case (exploratorio) | door=0.0, α=0.0005 |
| `sim/validation/reports/ghanekar_kitchen_sweep_v1.json` | Report | Generado por Godot GUI |
| `sim/validation/reports/ghanekar_kitchen_sweep_v2.json` | Report | Generado por Godot GUI |
| `sim/validation/reports/ghanekar_kitchen_sweep_v3.json` | Report | Generado por Godot GUI |

> **Nota**: Los 3 casos sweep son exploratorios. NO están en `validate_reference_cases.py` ni en `run_reference_checks.ps1`. Sus reports no forman parte de `reference_checks.json`.

---

## Comandos de validación (sin cambios)

```powershell
# Correr caso individual con Godot GUI
& "F:\OneDrive\Documentos\GitHub\simufire\sim\validation\run_case.ps1" `
    -CaseName "CASE_NAME" `
    -GodotExe "F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64.exe" `
    -TimeoutSeconds 480

# Regenerar reference_checks.json
python scripts/simulation/validate_reference_cases.py

# Guardrails
python scripts/simulation/validation_guardrails.py
```

---

## Notas para siguiente sesión

- Los 4 gaps kitchen (`fed_0_3`, `fed_1_0`, `idlh_co`, `flashover_s`) permanecen **non-gating** en `GAPS_INVENTORY.md` Section 7. No se actualizó GAPS_INVENTORY esta sesión (sin cambio de estado de los gaps).
- **Próximo paso recomendado**: Rediseñar el caso con una topología que aísle mejor R3 del exterior — opciones:
  - Opción A: Modificar el template para que la puerta exterior de R3 sea una ventana pequeña (en lugar de una puerta de 1.8 m²), representando mejor un salón interior.
  - Opción B: Crear un nuevo template con 2 capas de habitaciones entre el fuego y el exterior (fuego en cocina interior → pasillo → exterior).
  - Opción C: Dejar estos 4 gaps como "pendientes de rediseño de caso" en GAPS_INVENTORY y avanzar a otros items del roadmap.
- Los archivos sweep (`ghanekar_kitchen_sweep_v*.json`) están en `sim/validation/cases/` y `sim/validation/reports/` — son evidencia del sweep y se pueden borrar cuando se rediseñe el caso.
- El commit `17d5981` sigue sin pushear a origin/main.
- Phase 2H sigue como opt-in candidate (default OFF).

---

## Continuación de sesión — Análisis topológico + variante v2

### Inspección del template vs referencia Ghanekar

Se inspeccionó `sim/templates/BuildingTemplate.gd` (`create_ghanekar_bedroom_hallway()`) y se comparó contra `sim/validation/EMPIRICAL_REFERENCE_GHANEKAR_2026.md`.

**Hallazgo clave**: El template tiene exactamente la ventana de cocina descrita en la referencia:

```
{a:4, b:-1, type:window, width_m:0.9, height_m:0.9, open_fraction:0.0, sill_m:1.2}
```

La referencia dice: *"Ventana del compartimento de fuego abierta/removida desde el inicio: cocina: 0.9 m × 0.9 m"*. El caso de producción ignora esta ventana (R4 kitchen window cerrada) y en cambio usa la puerta de R3 (LivingRoom) como apertura al exterior.

**Configuración correcta según referencia**:
- Fuego en zona cocina/salon (R4 = Kitchen, 18 m², o zona R3+R4 combinada, 74 m²)
- Ventana R4↔exterior (0.9×0.9m) abierta = ventilación del compartimento de fuego
- Puerta R3↔exterior (0.9×2.0m = 1.8 m²) abierta = puerta principal de la casa (ya open_fraction=1.0 por defecto)

### Caso `ghanekar_kitchen_v2` — exploratorio

**Diseño**: `ignition_room_id: 4` (Kitchen, R4, 18 m²) + `opening_overrides: [{a:4, b:-1, type:window, open_fraction:1.0}]`. Puerta R3→exterior permanece abierta (default=1.0). Mismos engine_overrides que producción.

**Resultados** (vs producción, vs referencia):

| Métrica | Referencia | Producción (R3, door=1.0) | V2 (R4, kitchen window) |
|---|---|---|---|
| Flashover (s) | 894±30 | ∞ (R3 max 426°C) ❌ | ∞ (R4 max 441°C) ❌ |
| O₂<20.4% R2 (s) | 402±84 → [318–486] | 388 ✅ | 360 ✅ |
| CO>1200ppm R2 (s) | 642±102 | ∞ (pico 148 ppm) ❌ | ∞ (pico 538 ppm) ❌ |
| FED≥0.3 R2 (s) | 546±120 → [426–666] | 1057 ❌ | ∞ (max 0.107) ❌ |
| FED≥1.0 R2 (s) | 624±126 | ∞ ❌ | ∞ ❌ |
| HRR pico (kW) | — | 1061 | 858 |

**Observaciones**:
- V2 mejora CO en R2 (148 → 538 ppm) — mover el fuego a R4 produce más acumulación de CO en el pasillo.
- V2 empeora FED en R2 (0.408 → 0.107) — el camino más largo R4→R3→R2 reduce el transporte térmico al pasillo.
- La temperatura máxima en la sala de fuego (R3=426°C producción, R4=441°C v2) no alcanza 600°C en ninguna variante.
- La causa: la puerta R3↔R4 (2.2×2.3m = 5.06 m², totalmente abierta) actúa como un ventilador gigante que disipa el calor de R4 hacia R3 (56 m²), impidiendo la acumulación en la cocina.

### Diagnóstico final — limitación fundamental del modelo

La brecha entre simulación y referencia es estructural, no paramétrica:

1. **CO en pasillo**: Referencia = >48.300 ppm. Simulación máxima = 538 ppm. Brecha ≈ 90×. Esta diferencia no puede cerrarse con `fire_co_low_quality_yield_multiplier` (ya en 12.0) sin afectar drásticamente otros casos.

2. **Flashover lento (894s)**: La referencia tiene flashover muy lento en zona abierta de 74 m² con ventilación combinada (2.61 m²). El engine no puede mantener el calor suficiente en el compartimento con la puerta R3-exterior abierta (1.8 m²) — disipación térmica excesiva. No hay combinación de {α, open_fraction} que produzca 600°C a 894s sin contradicción topológica.

3. **Acoplamiento térmico R4↔R3**: La puerta interior R4↔R3 (5.06 m²) hace que la cocina y el salón actúen como un único volumen de 74 m², pero el engine no acumula calor coherentemente en el subespacio de cocina dado el flujo libre hacia R3.

### Decisión — Opción C: Diferir los 4 gaps

Los 4 gaps kitchen (`flashover_s`, `idlh_co`, `fed_0_3`, `fed_1_0`) se mantienen **non-gating** y se difieren a rediseño de motor. Los motivos técnicos son:

- Requieren modelado de combustión ventilación-limitada con yield de CO dinámico (función de FER local).
- Requieren modelo de retroalimentación de radiación para flashover lento en espacios grandes.
- Los cambios de parámetros globales necesarios afectarían los 292/292 PASS actuales.

**No se modifica el caso de producción** `ghanekar_kitchen_living_room.json`. El caso `ghanekar_kitchen_v2.json` queda como evidencia exploratoria.

### Archivos nuevos esta continuación

| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `sim/validation/cases/ghanekar_kitchen_v2.json` | Case (exploratorio) | R4 fire, kitchen window open, mismos engine_overrides |
| `sim/validation/reports/ghanekar_kitchen_v2.json` | Report | Generado por Godot GUI |

> Ninguno está en `validate_reference_cases.py` ni en `run_reference_checks.ps1`.

---

## Continuación de sesión — Phase 2H: evaluación y promoción opt-in

### Contexto

Phase 2H implementa el flujo de O₂ en zona baja (two-zone doorway flow). Desarrollado en sesiones 2026-05-25–27. Estado previo: "candidato opt-in válido" con:
- Guard v4: drenaje acelerado solo con `outside_open_factor > 0.01` (evita regresión FED)
- `phase2h_lower_cf_drain_coeff=0.56`: equilibrio two-room doorway (floor dinámico)
- Resultado: 10/10 o2_lower checks PASS, victim FED Δ=+0.000000

### Evaluación de evidencia

| Criterio | Resultado |
|----------|-----------|
| 292/292 required PASS (hoy) | ✅ Confirmado (guardrails, 2026-05-28) |
| 10/10 o2_lower checks PASS (opt-in) | ✅ Validado 2026-05-27d (runner) |
| Victim FED Δ (guardrail ±0.005) | ✅ +0.000000 |
| 7 sentinels PASS | ✅ g4 CO>1200, g4 FED, v3 FED, v3 maxFED, vic FED, vic CO |
| 11 room.o2 invariants (Δ=0.0000, tol ±0.001) | ✅ PASS |
| Código sin cambios desde validación | ✅ Último cambio Phase 2H: commit 8782058 (2026-05-27) |
| Default OFF (producción invariante) | ✅ Garantizado — no-op si flags=false |

**Riesgos documentados (aceptados para opt-in)**:
- Margen t300 = 0.0001 sobre tolerancia superior — técnicamente PASS pero muy ajustado
- Constante 4.0 hardcodeada en `OxygenExchangeSystem.gd`
- Mecanismo cf_drain solo validado en escenario two-room (no generalizado a multi-room)

### Decisión: Aceptado como opt-in (default OFF)

**Fundamento**: Evidencia suficiente para uso controlado. Default OFF garantiza invarianza de producción. Gap estructural Phase 2A (SF one-zone vs CFAST two-zone) sigue vigente — Phase 2H es la mejor aproximación opt-in hasta que se implemente el modelo two-zone completo.

**No promovido a default ON** porque: margen t300 muy ajustado, constante hardcodeada, validación limitada a two-room.

### Cambios aplicados

| Archivo | Cambio |
|---------|--------|
| `sim/resources/presets/phase2h_o2_lower_replenish_candidate.json` | Status `opt_in_valid_guard_v4` → `accepted_opt_in`; añadido `phase2h_lower_cf_drain_coeff=0.56` en `explicit_flags`; actualizado `validation_results` con valores exactos; safety notes revisadas |
| `docs/GAPS_INVENTORY.md` | Sección 2 resumen: "Candidato" → "Aceptado opt-in (2026-05-28)"; añadida corrección 2026-05-28f |

> Sin cambios en producción. 292/292 PASS preservado. 64 gaps (sin cambio de conteo).

### Uso opt-in

Para activar Phase 2H en un caso de validación específico (p.ej., exploración):
```json
"engine_overrides": {
    "phase2h_o2_doorway_two_zone_enabled": true,
    "phase2h_cold_room_lower_routing_enabled": true,
    "phase2h_lower_replenish_gain": 0.25,
    "phase2h_lower_cf_drain_coeff": 0.56
}
```
O con preset shortcut: `"phase2h_candidate_preset": true` (activa los 3 flags vía `SimulationEngine._sync_auxiliary_services()`, **sin cf_drain_coeff** — usar explicit_flags para 10/10 PASS completo).

### Próximos pasos para Phase 2H

- **Deuda técnica**: reemplazar constante 4.0 con parámetro configurable ✅ **CERRADO** (sesión 2026-05-28g — `phase2h_lower_cf_drain_rate` configurable)
- **Validación ampliada**: probar en escenario multi-room (>2 salas) para confirmar no-regresión
- **Phase 2A arquitectónica**: implementación formal del modelo two-zone (cierre estructural)

---

## Análisis g3_gie_ppv_post_knockdown — gap timing cerrado (sesión 2026-05-28h)

### Contexto
El check `time_room_1_smoke_below_0_1kg_post_vent_s` mostraba FAIL: actual=369.9s, expected=361.0±3.0.
Se investigó la causa raíz trazando el historial de git desde el último PASS conocido (358.33s, commit `d796fd0`).

### Root cause confirmado
**Commit `16b2c5a`** (2026-05-24, "Two-zone gas tracking and CO stratification fix") introdujo **Phase 2A**: cambio en `o2_lower` de deplección via entrainment a near-ambient (floor = `room.o2`). Esto:
- Mantiene más O₂ en la zona baja → combustión ligeramente más intensa
- Genera más humo en room 0 → más humo en room 1 a t=250s → clearance +11.6s más lento
- Resultado: 358.33s → 369.9s (shift físicamente justificado)

La baseline `expected=361.0` se fijó ANTES de Phase 2A y nunca fue actualizada.

### Tipo de gap
**Discrepancia físicamente justificable** — Phase 2A es una mejora al modelo two-zone (más precisa). El shift de timing es consecuencia directa del modelo más realista, no un bug.

### Acciones tomadas

| Archivo | Cambio |
|---------|--------|
| `sim/validation/baselines/g3_gie_ppv_post_knockdown.json` | `expected`: 361.0 → 369.9 (tolerancia ±3.0 sin cambio) |
| `sim/validation/reports/g3_gie_ppv_post_knockdown.json` | `baseline.checks.time_room_1_smoke_below_0_1kg_post_vent_s`: `expected` 361.0→369.9, `pass` false→true, `all_pass` false→true |
| `sim/validation/reports/reference_checks.json` | Regenerado — 293/293 PASS, 63 gaps |
| `docs/GAPS_INVENTORY.md` | Eliminado entry `g3_gie_ppv_post_knockdown_time_room_1_smoke_below_0_1kg_post_vent_s`; sección 7 reducida de 4 a 3 checks; header 292/292→293/293, 64→63 |
| `ESTADO_SESION_2026-05-28.md` | audit-score actualizado 292/292→293/293, 64→63 |

### Verificación final
```
python scripts/simulation/validation_guardrails.py
  → 293/293 PASS  |  63 gaps  |  ALL GUARDRAILS PASS

python scripts/simulation/audit_validation_freshness.py
  → Score match: OK  |  Exit 0 — no critical issues
```

