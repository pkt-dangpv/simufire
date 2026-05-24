# Estado de sesión — 2026-05-24

## Resumen ejecutivo

Sesión de intento de implementación de **Phase 2E-C** (mezcla CO inter-zona + FED lower zone) seguida de diagnóstico de fallo y **revert completo**.

**Resultado final: 289/289 PASS, 73 gaps** (65 contados inicialmente; ver sección post-checkpoint). Baseline restaurada, idéntica al checkpoint 2026-05-23 salvo guard `compute_co_lower_ppm`.

---

## Lo que se hizo esta sesión

### 1. Continuación desde sesión anterior

Al iniciar la sesión, v3 (`v3_hallway_fed_exposure`) estaba pendiente de confirmar post-revert de Phase 2E-C. Se verificó:

| Caso | Resultado | Métrica clave |
|------|-----------|---------------|
| `g4_gie_delayed_entry_hazard` | ✅ PASS | `time_fed_0.1` = 198.42s (expected 197.75±10) |
| `v3_hallway_fed_exposure` | ✅ PASS | `all_pass=True` |
| `victim_fed_incapacitation` | ✅ PASS | `victim_v0_final_fed`=0.772, `peak_co`=3382 ppm |
| Suite completa 289 checks | ✅ 289/289 | 73 gaps no-gating (65 contados antes del fix reporting) |

### 2. Inventario de gaps documentado

Se extrajo el listado completo de los 65 gaps no-gating de `reference_checks.json`, se clasificaron por categoría y se documentaron en:
- `docs/GAPS_INVENTORY.md` — inventario completo con tablas detalladas
- `/memories/repo/simufire_state.md` — resumen por categoría en memoria de repo

---

## Análisis de situación

### Estado del modelo two-zone

| Variable | Estado | Nota |
|----------|--------|------|
| `o2_upper` / `o2_lower` | ✅ Implementado (Phase 2A) | O₂ inferior ≈ 20.5% (correcto); O₂ superior depleta |
| `co2_upper` | ✅ Implementado (Phase 2B) | Tracking activo, gaps CO₂ residuales no-gating |
| `co_upper_kg` | ✅ Implementado (Phase 2C) | CO en zona superior cuando fuego activo |
| `co_lower_kg` | ⚠️ Subóptimo | Siempre ≈ 0; CO no llega a zona inferior en salas remotas |
| FED zona inferior (CO) | ⚠️ Usa `compute_co_ppm` | Usa promedio sala, no CO real zona baja |
| FED zona inferior (O₂) | ✅ Implementado (Phase 2E-A) | Usa `o2_lower` — correcto |

### Phase 2E-C: por qué falló

**Objetivo**: hacer que CO llegue a zona inferior de salas remotas (sin fuego) y que el FED inferior use ese valor.

**Implementación intentada (6 cambios):**
1. Parámetro `co_interlayer_mix_rate = 0.040` (τ ≈ 25s)
2. Función `_apply_co_interlayer_mixing` — transfiere CO de `co_upper_kg` a `co_lower_kg` en salas sin fuego
3. Llamada al mixing tras `_flush_contaminant_deltas`
4. `compute_co_lower_ppm` sin strat factor (retorna valor real)
5. `compute_fed_delta_for_height` — zona inferior usa `compute_co_lower_ppm`
6. `step_fed` — ídem

**Resultados tras implementación:**

| Caso | Métrica | Resultado | Esperado |
|------|---------|-----------|----------|
| g4 | `time_room_1_fed_above_0_1_s` | 243.25s | 197.75±10s |
| v3 | `room_1_max_fed` | 0.194 | ≥1.0 |
| v3 | `time_room_1_fed_above_0_1_s` | 522.9s | 252±30s |

**Causa raíz diagnosticada:**

**Causa A — Mixing en salas con capa caliente (salas adyacentes al fuego):**
- Room_1 (pasillo) recibe gas caliente vía transporte upper→upper desde R0
- Tiene `upper_gas_kg >> 0` y CO real en `co_upper_kg`, pero `hrr_kw ≈ 0` (sin fuego propio)
- La guard `hrr_kw > 0.1` no la protege → mixing extrae CO de zona superior → FED víctima cae

**Causa B — Déficit transitorio del FED switch:**
- Al cambiar `compute_co_ppm → compute_co_lower_ppm`, durante los primeros 50-100s desde que llega CO, `co_lower_kg ≈ 0`
- FED es integral acumulativa → la pérdida temprana es permanente
- Resultado: threshold times +45s incluso cuando `compute_co_lower_ppm ≈ compute_co_ppm` al equilibrio

**Conclusión:** Phase 2E-C como diseñada es arquitectónicamente incompatible con el modelo actual. No existe combinación de parámetros que la haga funcionar sin romper los tests de timing.

### Revert aplicado

Se revirtieron los 5 cambios comportamentales. Se conservó únicamente:
- `co_interlayer_mix_rate: float = 0.040` en parámetros (~línea 102) — **sin uso, dead code infraestructura**
- Entrada en `configure()` (~línea 418) — **sin efecto**

## Post-checkpoint: compute_co_lower_ppm guard (24 mayo 2026)

### Cambio implementado

**Archivo**: `sim/core/ThermalSystem.gd` — función `compute_co_lower_ppm` (línea ~2303)  
**Tipo**: Fase 2E reporting seguro — solo afecta exportación/comparación CFAST, **no afecta FED ni checks required**.

```gdscript
# Añadido tras: if room == null: return 0.0
if room.upper_gas_kg < 0.1:
    return compute_co_ppm(room)  # distribución uniforme, sin estratificación
```

**Razón**: cuando la capa caliente colapsa (`upper_gas_kg < 0.1`), `sync_room_upper_layer` resetea `co_upper_kg = 0` pero `thermal_layer_m` puede estar aún bajo el techo, dando `strat ≈ 0` pese a que `co_lower_kg = co_kg > 0`. El fix devuelve la concentración media de sala en lugar de suprimir artificialmente a 0.

### Resultado de validación

| Check | Resultado |
|-------|----------|
| Required (289/289) | ✅ PASS — sin cambio |
| Non-gating gaps | 73 (vs 65 documentados anteriormente) |

### Análisis de la diferencia 65 → 73

- **1 gap nuevo directo**: `cfast_2r_hall_t360_co_lower_ppm` — SF reporta 125 ppm (media de sala cuando no hay hot layer); CFAST espera 0 (CO en zona superior estratificada). El fix es arquitecturalmente correcto para SF; la discrepancia con CFAST es estructural. `required=False`.
- **7 gaps pre-existentes no contados**: checks que ya fallaban antes del fix (nuestro cambio es read-only — no puede afectar O₂, presión, temperatura). El conteo de 65 en el GAPS_INVENTORY inicial tenía error aritmético (`60 + 10 ≠ 65`) y no incluía `cfast_closed_t240_pressure_pa`, `cfast_2r_hall_rmse_o2` y otros que ya fallaban.

### Backlog Phase 2E (no implementar sin rebaseline)

> ⚠️ Cualquier cambio a `_transfer_hot_gas_contaminants`, `compute_fed_delta_for_height` o `step_fed` que altere `co_upper_kg` en salas destino **requiere re-ejecutar suite completa y verificar g4 required checks** antes de commitear.  
> Checks críticos g4: `time_room_1_fed_above_0_1_s` (197.75±10s), `time_room_1_co_upper_above_1200_s` (87.33±5s), `room_1_peak_co_upper_ppm` (≥2000).

Ver `docs/GAPS_INVENTORY.md` — sección «Backlog Phase 2E arquitectónica».

---

## Lo que queda (próximas fases)

### Alternativas para Phase 2E-C (no implementadas)

**Opción A — Status quo** *(actual)*
Mantener `compute_co_ppm` para FED zona inferior. CO sin estratificación pero 289/289 PASS estable. Los gaps CO lower ya están marcados como non-gating.

**Opción B — Rediseño en transporte** *(recomendada)*
Modificar `_transfer_hot_gas_contaminants` para dividir CO entre zona superior e inferior desde el primer transporte (proporcional a volúmenes de zona). El CO llega a `co_lower_kg` directamente, sin mixing post-hoc. Evita el problema transitorio porque `co_lower_kg` crece desde t=0 del transporte.

```gdscript
# En _transfer_hot_gas_contaminants, al depositar CO en sala destino:
var co_upper_fraction = upper_gas_kg / maxf(0.1, total_gas_kg)
room_dest.co_upper_kg += co_transferred * co_upper_fraction
# co_lower_kg se calcula como co_kg - co_upper_kg (igual que ahora)
```

**Opción C — FED condicional**
Usar `compute_co_lower_ppm` solo cuando `hot_h < 0.5 * height_m` (capa caliente real bajo el punto medio). Para salas sin capa caliente real mantener `compute_co_ppm`. Más complejo de mantener.

### Gaps priorizados

| Prioridad | Categoría | Checks | Camino de cierre |
|-----------|-----------|--------|------------------|
| 1 | O₂ zona inferior | 9 | Two-zone doorway flow completo (Phase 2E continuación) |
| 2 | CO₂ upper layer | 5 | Two-zone CO₂ transport (Phase 2E) |
| 3 | Escenarios HVAC/multi-floor O₂ | 3 | Deriva de Phase 2E |
| 4 | Wall heat loss | 4 | Conducción 1D paredes (Phase 1.5, alto esfuerzo) |
| 5 | RMSE temperatura | 8 | Mejoran con 1+4 |
| 6 | Presión | 15 | Gap estructural profundo, modelo de boyancia |
| 7 | Stage-B pending | 10 | Requieren implementación previa de las fases |

### Otras tareas pendientes de sesiones anteriores

- `fed_hypoxia_*` sin `@export` en SimulationEngine (no sincronizado)
- CO₂ double-transport: transportado por OxygenExchangeSystem Y GasExchangeSystem
- Conducción 1D paredes (wall_absorption_rate lineal es parche)
- HUD: font sizes, márgenes, colores sin `@export`
- V4–V8: diseño y ejecución de casos de validación
- Causa raíz zombie fire (fire_max_active_s es parche; causa: O₂=0.1004 sostenido por ACH stack effect)

---

## Archivos modificados esta sesión

| Archivo | Cambio |
|---------|--------|
| `docs/GAPS_INVENTORY.md` | Actualizado — 73 gaps, aritmética corregida, sección CO lower + backlog Phase 2E |
| `sim/core/ThermalSystem.gd` | Guard `upper_gas_kg < 0.1` en `compute_co_lower_ppm` (Phase 2E safe); `co_interlayer_mix_rate` dead code preservado |

---

## Parámetros de referencia

- **Godot exe**: `F:\OneDrive\Escritorio\Godot_v4.6.3-stable_win64_console.exe`
- **Workspace**: `F:\OneDrive\Documentos\GitHub\simufire`
- **run_case.ps1** (desde `sim\validation\` con `$env:GODOT_EXE` seteado):
  ```powershell
  powershell -ExecutionPolicy Bypass -Command "& { . .\run_case.ps1 -CaseName 'NAME' -TimeoutSeconds 300 }"
  ```
- **Suite completa**:
  ```powershell
  cd F:\OneDrive\Documentos\GitHub\simufire
  python scripts/simulation/validate_reference_cases.py
  ```
