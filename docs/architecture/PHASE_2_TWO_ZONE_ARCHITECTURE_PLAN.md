# Phase 2 Two-Zone Architecture Plan

Date: 2026-06-20
Status: DESIGN — no motor code written yet
Baseline: 336/350 PASS, **14/350 required FAIL** (all VALID_GAP)

---

## 1. Objetivo

Eliminar los 14 required FAILs actuales mediante un conjunto de cambios arquitectónicos por fases que refuerzan el motor hacia un comportamiento canónico de dos zonas (two-zone), sin tocar tolerancias ni reclasificar checks. Cada fase debe ser segura: flag default=false → no-op exacto antes de activarla.

---

## 2. Análisis de causas raíz por grupo

Los 14 FAILs comparten una raíz común: **SimuFire carece de un balance de masa conservativo por zona** para O₂. Los efectos se manifiestan de tres formas distintas según el grupo:

| Grupo | Checks | Mecanismo faltante |
|-------|--------|--------------------|
| A — r0_window (×3) | O2 upper t240/t350/t360 | Fire throtea por `room.o2` (bulk) en lugar de `o2_upper`; ventana exterior no tiene `early_opening_signal` → `fire_o2_full_hrr_open` inactivo hasta apertura |
| B — slow_growth_sealed (×2) | temp_upper t480/t600 | Acoplamiento térmico/O₂ en sala sellada; chi_rad no puede mejorar temperatura sin romper O₂ |
| C — corridor_chain (×2) | temp R0 t180+t600 | Curva temporal de entalpía incorrecta en la cadena de pasillos; el exchange canónico existe pero la masa/energía exportada no cuadra con CFAST en t180 y t600 |
| D — bedroom_closed_door (×5) | O2 upper t120–t720 | Sin `validation_fire_o2_mode`; fuego depleta `room.o2` (bulk) y `o2_upper` pero plume_entrainment repone `o2_upper` desde zona baja fresca → depleción neta < CFAST |
| E — two_room_door_open (×1) | RMSE [0–350 s] | `fire_o2_mode="upper"` activo pero sin canonical_doorway_exchange: O₂u R0 colapsa sin reposición desde Pasillo |
| E — hvac_residential (×1) | O2 upper t300 | Return HVAC extrae gas bulk (no zona alta); sin balance de masa upper/lower → O₂u colapsa; SF sin mecanismo equivalente al two-zone HVAC de CFAST |

---

## 3. Inventario de flags existentes

### 3a. Mantener activos (funcionan, necesarios)

| Flag | Sistema | Uso actual |
|------|---------|------------|
| `two_zone_solver_enabled` | OxygenExchangeSystem, CombustionSystem | Routing canónico plume_lower/upper/blend; default=false |
| `canonical_doorway_exchange_enabled` | ThermalSystem | Exchange bidireccional masa+entalpía+O₂ por puertas; activo en corridor_chain |
| `doorway_thermal_counterflow_enabled/gain` | ThermalSystem | Exchange térmico M3; activo en corridor_chain con gain=0.25 |
| `canonical_doorway_lower_flow_frac` | ThermalSystem | Calibración del flujo inferior de exchange canónico |
| `fire_o2_lower_for_flame` | OxygenExchangeSystem | Fire throtea por `o2_lower`; activo en hvac_residential |
| `o2_upper_plume_entr_rate` | OxygenExchangeSystem | Tasa de reposición de O₂u desde O₂l por el penacho |
| `plume_upper_o2_displacement_frac` | OxygenExchangeSystem | Fracción de consumo O₂u por productos de combustión |
| `fire_o2_canonical_enabled` (M1) | OxygenExchangeSystem | Routing canónico O₂ cuando CombustionSystem elige plume_lower; no-op por defecto |

### 3b. No reactivar (rotos o superados)

| Flag | Por qué no |
|------|-----------|
| `fire_o2_mass_tracking_enabled` (M2) | Rompió 10+ checks globalmente; nunca reactivar |
| `phase2h_o2_doorway_two_zone_enabled` | Fix parcial HVAC; será superado por Phase 2D |
| `phase2h_interior_no_exterior_drain_gain/max_scale` | Heurística experimental sin target validado |
| `phase2e_co2_subc_enabled`, `phase2e_co2_subd_enabled` | Tracer CO₂ experimental; sin target CFAST confirmado |

### 3c. A promover (candidatos a activar globalmente en fases posteriores)

| Flag | Acción |
|------|--------|
| `fire_o2_canonical_enabled` (M1) | Activar globalmente cuando Phase 2B pase todas las guards |
| `canonical_doorway_exchange_enabled` | Extender a two_room y bedroom en Phase 2C |

---

## 4. Fases de implementación

### Orden de ejecución

```
2A (data model no-op) → 2B (combustion routing) → 2C (doorway exchange) → 2D (HVAC) → 2E (cleanup)
```

La razón del orden: 2A es fundación sin riesgo; 2B es la pieza más crítica (combustion) y debe estabilizarse antes de añadir 2C; 2C depende del comportamiento de 2B para doorway; 2D es independiente (solo HVAC) y puede hacerse en paralelo con 2C una vez 2B está verde; 2E es cleanup final.

---

### Phase 2A — Fundación: zona másica disponible para todos los sistemas (no-op)

**Objetivo:** Garantizar que `upper_gas_kg`, `lower_gas_kg`, `upper_energy_kj`, `lower_energy_kj` se calculan cada paso para **todas** las habitaciones, no solo las que tienen `canonical_doorway_exchange_enabled`. Estos campos son el sustrato sobre el que 2B–2D operarán.

**Estado actual:**
- `upper_gas_kg` y `lower_gas_kg` se calculan en `ThermalSystem` dentro del bloque de exchange canónico. Si `canonical_doorway_exchange_enabled=false`, los campos pueden estar a 0 o desfasados.
- OxygenExchangeSystem calcula `upper_air_mass`/`lower_air_mass` localmente (línea 291–293) en cada paso, pero no escribe a `room.upper_gas_kg`.

**Cambio propuesto:**
- Añadir un paso de inicialización/sync en ThermalSystem o en un nuevo helper que compute `upper_gas_kg = rho × upper_volume_m3()` para todos los rooms, independientemente del resto de flags.
- Proteger con `phase2a_zone_mass_canonical=true` (nuevo flag, default=false).

**Archivos a tocar:**
- `sim/core/ThermalSystem.gd`: nuevo bloque pre-exchange que compute zone masses cuando `phase2a_zone_mass_canonical=true`
- `sim/building/RoomModel.gd`: verificar que `upper_gas_kg` etc. son campos escritos (ya existen, líneas 120–140 aprox)

**Casos que deben mejorar:** ninguno (no-op puro)
**Casos sentinel:** todos 350 — resultado idéntico al baseline
**Comando de validación:**
```
python scripts\simulation\validate_reference_cases.py --all
```
Verificar: 336 PASS, 14 FAIL — sin cambio.

**Riesgo:** Muy bajo. Flag default=false garantiza no-op.

---

### Phase 2B — Routing canónico de combustión: O₂u como fuente principal

**Objetivo:** Cuando el fuego quema en una habitación con capa caliente establecida, el consumo de O₂ debe ir **solo** a `o2_upper` (no también a `room.o2` bulk simultáneamente). El throttle de HRR en CombustionSystem debe usar `o2_upper`. La zona baja repone `o2_upper` vía penacho a la tasa calibrada. `room.o2` se deriva como promedio ponderado de zonas al final del paso.

**Estado actual:**
- Con `fire_o2_mode="upper"` (per-case): CombustionSystem throtea por `o2_upper` ✓, pero OxygenExchangeSystem depleta **tanto** `room.o2` (bulk, línea 346) **como** `room.o2_upper` (línea 376) simultáneamente → doble contabilidad que puede causar `o2_upper < room.o2` (no físico).
- Sin `fire_o2_mode` (bedroom): CombustionSystem usa `room.o2` bulk para throttle; `o2_upper` se depleta por el bloque de línea 376 pero el penacho lo repone parcialmente.

**Diagnóstico diferencial Grupo D (bedroom):**
En sala sellada, door closed:
- `o2_lower` permanece cerca de 0.209 (ACH lo mantiene)
- Plume entrainment: `entr_frac × (o2_lower − o2_upper)` siempre positivo → frena la depleción de o2_upper
- CFAST depleta ULO2 sin la misma reposición → divergencia creciente

**Cambio propuesto:**
1. Añadir flag `phase2b_canonical_combustion_enabled=false` (nuevo, default=false)
2. Cuando `phase2b_canonical_combustion_enabled=true`:
   - **OxygenExchangeSystem:** consumo de O₂ va SOLO a `o2_upper` (no a `room.o2` bulk)
   - `room.o2 = upper_frac × o2_upper + lower_frac × o2_lower` al final del paso (derivado, no independiente)
   - El penacho sigue entrañando de `o2_lower` → `o2_upper`, pero la tasa `o2_upper_plume_entr_rate` necesita recalibración (actualmente 0.010 por segundo; puede necesitar bajar para permitir depleción más rápida)
   - **CombustionSystem:** throttle basado en `o2_upper` cuando `phase2b_canonical_combustion_enabled=true` (no en `room.o2` bulk)
3. Per-case: añadir `validation_fire_o2_mode: "upper"` a `cfast_bedroom_closed_door.json` (sin este flag el caso usa legacy mode, que depende de room.o2)

**Interacción con plume entrainment (riesgo principal):**
La `o2_upper_plume_entr_rate=0.010` per-segundo puede seguir siendo demasiado alta para que `o2_upper` deplecte al ritmo de CFAST. Dos opciones:
- **Opción A:** Calibrar `o2_upper_plume_entr_rate` por caso (riesgo: muchos casos afectados)
- **Opción B:** Calcular la tasa de entrainment desde la geometría del penacho (Mc Caffrey) y la interfaz de capa — tasa fija calibrada globalmente pero físicamente derivada

Para el plan inicial usar Opción A solo para bedroom (per-case en JSON), verificar que corridor_chain no se rompe.

**Archivos a tocar:**
- `sim/core/OxygenExchangeSystem.gd` — bloque de consumo O₂u (líneas 341–350 y 376–396)
- `sim/fire/CombustionSystem.gd` — selección O₂ para throttle (función `_resolve_fire_o2_selection`)
- `sim/validation/cases/cfast_bedroom_closed_door.json` — añadir `validation_fire_o2_mode: "upper"`

**Casos que deben mejorar:** Grupo D (O2 ×5), Grupo A (O2 ×3, parcialmente)
**Casos sentinel (deben seguir PASS):**
- `cfast_corridor_chain` — t300 temp PASS (más sensible al routing O₂)
- `cfast_pool_fire_open` — O2 t180/t300/t480 (actualmente PASS)
- `cfast_slow_growth_sealed` — O2 t300 (PASS con margen pequeño)
- `ghanekar_bedroom_hallway` — FED timing (PASS)
- `cfast_hvac_residential` — todos los checks PASS actuales (o2_lower_*, t180_o2)

**Comando de validación:**
```
python scripts\simulation\validate_reference_cases.py --all
```
**Gate de éxito:** ≥ 341/350 PASS (al menos 5 FAIL resueltos = todos Grupo D), **sin reducir** checks que actualmente pasan.

**Riesgo:** ALTO — path de combustión central. Cualquier cambio en OxygenExchangeSystem.step() afecta todos los casos con fuego. Activar solo por caso primero (`phase2b_canonical_combustion_enabled=true` solo en `cfast_bedroom_closed_door.json` como `engine_override`), luego extender si sentinels pasan.

---

### Phase 2C — Exchange bidireccional de O₂/masa por puertas interiores

**Objetivo:** Extender `canonical_doorway_exchange_enabled` a los casos `cfast_two_room_door_open` y opcionalmente recalibrar corridor_chain para resolver t180/t600. Cuando hay capa caliente diferencial entre dos habitaciones y la puerta está abierta, O₂ debe fluir bidireccional: gas caliente agotado sale por parte alta del vano, gas fresco de zona baja/alta de la habitación fría entra.

**Estado actual de `_apply_canonical_doorway_exchange`:**
- **Parte A:** Gas caliente sale de hot.upper → cold.upper. O₂u de cold se mezcla con el gas entrante (ya implementado).
- **Parte B:** Flujo inferior cold.lower → hot.lower (energía + O₂). hot.o2_lower se mezcla con gas de cold.o2_lower.

El mecanismo es bidireccional en masa y energía. El problema para two_room:
- No está activado en two_room (`canonical_doorway_exchange_enabled=false` por defecto)
- La Parte B (cold.lower → hot.lower) repone `hot.o2_lower`, pero `hot.o2_upper` solo recibe reposición vía penacho de `hot.o2_lower`

**Gap específico two_room:** R0.o2_upper colapsa porque:
1. Fire depleta R0.o2_upper ✓
2. Pasillo tiene o2_upper=20.7% (fresco)
3. Sin canonical exchange, R0 no recibe gas fresco del Pasillo
4. La Parte B del exchange tampoco llega a reponer R0.o2_upper directamente

**Posible fix Parte A extendida:** Cuando cold → hot, el gas frío de la zona superior de cold podría reponer hot.upper. Actualmente solo hot → cold. Para that, en el frame donde hot.upper < cold.upper (inverso de lo habitual), necesitamos un "reverse exchange" o un exchange neutral-temperature aware.

**Cambio propuesto:**
1. Activar `canonical_doorway_exchange_enabled=true` en `cfast_two_room_door_open.json`
2. Verificar que la Parte B del exchange efectivamente lleva o2_lower de Pasillo (0.209) a hot.o2_lower de R0, y que el penacho luego lo mueve a hot.o2_upper
3. Si ese camino es demasiado lento: añadir en Parte A un "reverse upper O₂ mix" cuando cold.o2_upper > hot.o2_upper, proporcional al flujo de la Parte B

**Para corridor_chain t180/t600:**
Estos fallos son de temperatura, no de O₂. La curva de temperatura en R0 tiene una forma diferente a CFAST:
- t180: SF demasiado caliente (HRR alcanza pico más rápido?)
- t600: SF demasiado frío (energía ya salió hacia Pasillo y R2?)
El `doorway_thermal_counterflow_gain=0.25` fijó t300 pero desplazó el error a t180/t600.
Esto sugiere que la **forma de la curva** no es solo de amplitud sino de timing — posiblemente un desfase en cuándo el calor llega al Pasillo.
Posible corrección: ajustar `canonical_doorway_lower_flow_frac` o añadir un delay de mezcla térmica. **No cambiar gain sin evaluar impacto en curva completa** (t60 a t600).

**Archivos a tocar:**
- `sim/core/ThermalSystem.gd` — `_apply_canonical_doorway_exchange` Parte A (añadir reverse upper mix opcional)
- `sim/validation/cases/cfast_two_room_door_open.json` — añadir `canonical_doorway_exchange_enabled: true`

**Casos que deben mejorar:** Grupo E two_room (RMSE ×1), Grupo C corridor_chain t180/t600 (×2, con recalibración)
**Casos sentinel:**
- `cfast_corridor_chain` — t300 temp PASS, t480 O₂ PASS, t600 O₂ PASS
- `cfast_two_room_door_open` — O2 t120/t180/t300/t600 PASS, temp t180/t300/t600 PASS (no romper checks que actualmente pasan)

**Comando de validación:**
```
python scripts\simulation\validate_reference_cases.py --all
```
**Gate de éxito:** ≥ 336 + mejora en two_room RMSE o corridor t180/t600

**Riesgo:** MEDIO-ALTO. Añadir canonical exchange a two_room puede romper sus checks de O₂ y temperatura actuales que están PASS. Activar con flag por caso antes de global.

---

### Phase 2D — Balance de masa HVAC upper/lower

**Objetivo:** Cuando el return del HVAC está por encima de la interfaz de capa caliente (`return_height_m > hot_layer_m`), extrae gas de zona alta (agotado). CFAST repone la zona alta con gas de la zona baja en el balance de masa. SF no tiene este mecanismo → O₂u colapsa.

**Estado actual:**
- `HVACSystem._extract_return_air()` línea 210: `sample["o2_weighted_kg"] += room.o2 * air_kg` → usa `room.o2` (bulk)
- El `upper_sample_factor` se calcula (existe) pero solo se usa para determinar qué fracción del gas retornado viene de la zona alta; no mueve O₂ entre zonas

**Cambio propuesto:**
1. Añadir flag `phase2d_hvac_two_zone_enabled=false` (nuevo)
2. Cuando `phase2d_hvac_two_zone_enabled=true` y el return está por encima de la interfaz:
   - Extraer de `room.o2_upper` en proporción a `upper_sample_factor`
   - Compensar: mover masa proporcional de `o2_lower` a `o2_upper` (gas de zona baja sube para llenar el volumen evacuado por el return)
   - Fórmula: `delta_o2_upper = (o2_lower - o2_upper) × upper_sample_factor × air_extracted_kg / upper_air_mass`
3. Para supply: cuando supply está por debajo de la interfaz, boost `o2_lower` en proporción a `supply_flow × outside_o2`

**Archivos a tocar:**
- `sim/core/HVACSystem.gd` — `_extract_return_air` (línea 148–231), `_apply_supply_air`
- `sim/validation/cases/cfast_hvac_residential.json` — añadir `phase2d_hvac_two_zone_enabled: true`

**Casos que deben mejorar:** Grupo E HVAC (O2 t300 ×1)
**Casos sentinel:**
- `cfast_hvac_residential` — o2_lower_t180/t300/t450 PASS, t180_o2 PASS, t180_co_upper_ppm PASS
- Todos los demás casos sin HVAC — sin cambio

**Comando de validación:**
```
python scripts\simulation\validate_reference_cases.py --case cfast_hvac_residential
```
Seguido de:
```
python scripts\simulation\validate_reference_cases.py --all
```

**Gate de éxito:** `cfast_hvac_t300_o2` cambia a PASS sin romper otros HVAC checks

**Riesgo:** MEDIO. El caso HVAC es específico; otros casos no tienen HVAC con return en zona alta. Riesgo principal: que `o2_lower → o2_upper` boost cause que `o2_lower` caiga demasiado (afectando FED en zona baja).

---

### Phase 2E — Limpieza de flags experimentales (post-validación)

**Objetivo:** Una vez que 2B–2D están en verde y la baseline es ≥ 350/350, retirar el scaffolding experimental que queda sin función.

**Cambios:**
1. Eliminar bloques `fire_o2_mass_tracking_enabled` de OxygenExchangeSystem (M2 — nunca re-habilitar)
2. Eliminar `phase2h_*` cuando Phase 2D los supere
3. Limpiar comentarios stale de `validate_reference_cases.py` (bedroom O₂, HVAC)
4. Estandarizar `canonical_doorway_exchange_enabled=true` como default si todos los casos con doorway pasan

**Archivos:**
- `sim/core/OxygenExchangeSystem.gd`
- `sim/validation/cases/cfast_hvac_residential.json` (remover phase2h_*)
- `scripts/simulation/validate_reference_cases.py` (comentarios stale)

**Riesgo:** Bajo (cleanup). Solo hacer después de que todos los gates 2A–2D pasen.

---

## 5. Matriz de casos vs fases

| Caso / Check | Grupo | Phase 2A | Phase 2B | Phase 2C | Phase 2D |
|--------------|-------|----------|----------|----------|----------|
| bedroom O2 ×5 | D | — | **target** | sentinel | — |
| r0_window O2 ×3 | A | — | **target parcial** | — | — |
| corridor_chain temp t180+t600 | C | — | sentinel | **target** | — |
| two_room RMSE | E | — | sentinel | **target** | — |
| hvac O2 t300 | E | — | sentinel | — | **target** |
| slow_growth_sealed temp ×2 | B | — | watch | watch | — |

*Nota Grupo B (slow_growth_sealed):* La causa es el acoplamiento chi_rad/temperatura en sala sellada. No está claro que 2B o 2C lo resuelvan directamente. Puede requerir una sub-fase específica tras observar el comportamiento después de 2B.

---

## 6. Estrategia de validación por fase

Para cada fase:

1. **Pre-condición:** correr baseline completo y confirmar 336 PASS / 14 FAIL
2. **Activar per-case primero** (engine_override en JSON del caso target)
3. Correr solo el caso target: `python scripts\simulation\validate_reference_cases.py --case <nombre>`
4. Verificar que target mejora sin romper sus propios checks PASS
5. Correr todos los casos: `python scripts\simulation\validate_reference_cases.py --all`
6. **Gate de no-regresión:** total PASS ≥ baseline anterior
7. Documentar resultado en `docs/validation/STATUS_VALIDATION.md`
8. Solo si pasa gate → extender flag globalmente o al siguiente caso

---

## 7. Restricciones de diseño (reglas invariantes)

- **No cambiar tolerancias** ni reclasificar required-flags para hacer pasar checks
- **No tocar `sim/core` ni `sim/fire` sin autorización explícita** para cada fase
- `fire_o2_mass_tracking_enabled` (M2): nunca re-habilitar globalmente
- Cada fase nueva lleva flag default=false — el engine produce resultados idénticos al baseline si el flag no está en el JSON del caso
- `o2_upper_plume_entr_rate` per-case solo para bedroom en Phase 2B; no cambiar global default (0.010) sin evidencia de todos los casos afectados

---

## 8. Entregables por fase

| Fase | Artefacto |
|------|-----------|
| 2A | Bloque de sync zonal en ThermalSystem + sentinel run clean |
| 2B | Combustion O₂ routing canónico + bedroom PASS D×5 |
| 2C | Doorway exchange en two_room + two_room RMSE PASS o documentar por qué no |
| 2D | HVAC two-zone balance + hvac_t300_o2 PASS |
| 2E | Repo sin flags zombie, comentarios actualizados |

---

## 9. Archivos afectados por fase (resumen)

| Fase | Archivos motor | Archivos caso JSON | Archivos docs |
|------|---------------|-------------------|---------------|
| 2A | ThermalSystem.gd | ninguno | - |
| 2B | OxygenExchangeSystem.gd, CombustionSystem.gd | cfast_bedroom_closed_door.json | STATUS_VALIDATION.md |
| 2C | ThermalSystem.gd | cfast_two_room_door_open.json | STATUS_VALIDATION.md |
| 2D | HVACSystem.gd | cfast_hvac_residential.json | STATUS_VALIDATION.md |
| 2E | OxygenExchangeSystem.gd, validate_reference_cases.py | cfast_hvac_residential.json | HANDOFF, STATUS |

---

## 10. Señales de alarma (abort/replantear)

- Phase 2B causa que cualquier check actualmente PASS pase a FAIL → revertir flag, analizar interacción
- O₂u en corridor_chain (PASS actual) empieza a divergir tras 2B → plume_entr_rate necesita ajuste
- Phase 2C sube RMSE two_room (empeora) → el reverse-upper-mix propuesto va en dirección errónea
- Phase 2D causa que o2_lower_t300 falle → el boost lower→upper drena demasiado O₂ de zona baja

---

*Este documento es el plan técnico acordado antes de tocar código de motor. No implementar hasta autorización explícita por fase.*
