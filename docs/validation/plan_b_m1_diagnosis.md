# Plan B / M1 — Diagnóstico: `o2_scale` double-throttle en OES

**Fecha:** 2026-07-06  
**Estado:** HIPÓTESIS FALSADA (2026-07-07) — patch aplicado y revertido, CSVs idénticos.
Ver sección 0 para el resultado. El documento conserva el análisis del double-throttle
como referencia técnica (el bug es latente real, solo no activo con los casos actuales).  
**Archivos implicados:** `sim/core/OxygenExchangeSystem.gd`, `sim/fire/CombustionSystem.gd`, `sim/core/SimulationEngine.gd`, `sim/core/ThermalSystem.gd`

---

## 0. Resultado del experimento (2026-07-07)

**Patch aplicado y revertido** — `effective_plume_lower ? o2_lower : o2_upper` en OES línea 552.

CSVs regenerados byte-a-byte idénticos al baseline. D2PRE sin cambio: `cfast_slow_growth_sealed`
243, `fuel_balance_diag_sealed` 230, `o2_stoich_diag_sealed` 230. Physics suite: 10/12/7/0 sin
cambio. ILV: 15/14/0 sin cambio. FED: sin cambio.

**Por qué M1 no activa en los casos de test:**
- `cfast_slow_growth_sealed`: `validation_fire_o2_mode: "upper"` — `plume_lower_mode` nunca activa.
- `fuel_balance_diag_sealed` / `o2_stoich_diag_sealed`: aberturas interiores →
  `interior_open_factor > 0.01` — `plume_lower_mode` nunca activa.

El double-throttle es un bug **latente real** pero solo afectaría a casos con
`fire_o2_mode = "legacy"` Y sala single-room sellada. Ninguno de los 29 casos actuales
lo ejerce.

**Root cause corregido de los 7 WARN D2PRE:** La divergencia está en salas receptoras
(room=1, 2…), no en la sala de fuego. Es un problema de transporte inter-room — los dos
paths (tracer mol-fraction via OES/GES y mass kg via CombustionSystem/GES) divergen en
cómo acumulan CO₂ en salas sin fuego. Plan B real = mapear el transporte inter-room.

**Nota F0 (relacionado pero independiente):** El bug PHY-P1 CO₂ bulk >100% en salas
receptoras fue corregido en F0 Plan B (2026-07-07) — era bombeo concentrador en el
transporte de masa (GES/ThermalSystem), no el tracer OES. F0 está en
`docs/HANDOFF_CURRENT_STATE.md` sección "Session 2026-07-07 — F0 Plan B".

---

---

## 1. Contexto

D2PRE es la regla de diagnóstico que compara el tracer CO₂ de zona superior con el CO₂ derivado del balance de masa:

```
rel_div = |co2_upper_ppm_mass − co2_upper_ppm| / max(co2_upper_ppm, 400.0)
Dispara cuando rel_div > 1.0  (mass > 2× tracer ó tracer > 2× mass)
```

- `co2_upper_ppm`      = `room.co2_upper × 1e6` — tracer mol-fraction, gestionado por **OES**
- `co2_upper_ppm_mass` = `co2_upper_kg / upper_gas_kg × 1e6` — derivado del path de masa, gestionado por **CombustionSystem + ThermalSystem**

Estado actual: **7 WARN D2PRE** (no gateantes) en corpus de 29 CSVs. Causas absorbidas en otros 9 CTRLs. Objetivo M1: eliminar los 7 WARN y reducir D2PRE en CTRLs.

---

## 2. Mapa de código

### 2.1 Producción del tracer CO₂ — OES (`OxygenExchangeSystem.gd` líneas 547–556)

```gdscript
elif room.hrr_kw > 0.0:
    var cr_co2: float = co2_yield_kg_per_MJ
    var co2_produced: float = (room.hrr_kw / 1000.0) * cr_co2 * dt
    # ← AQUÍ EL BUG: segundo throttle por o2_upper
    var o2_scale: float = clampf(room.o2_upper / maxf(0.001, o2_nominal), 0.0, 1.0)
    co2_produced *= o2_scale
    var delta_co2: float = co2_produced * 29.0 / maxf(0.001, upper_air_mass * 44.0)
    room.co2_upper = room.co2_upper + delta_co2
```

### 2.2 Producción del path de masa — CombustionSystem (`CombustionSystem.gd` líneas 771–777, 856)

```gdscript
var co2_yield: float = lerpf(co2_min, co2_base, co2_phi_t)
var generated_co2_kg: float = co2_yield * maxf(heat_release_MJ, smoke_basis_MJ * 0.60)
# [...]
room.co2_upper_kg += generated_co2_kg   # ← sin o2_scale; solo throttleado por hrr_kw
```

### 2.3 Throttle del HRR — CombustionSystem (`CombustionSystem.gd` líneas 135–213)

```gdscript
# o2_selection elige la referencia según modo
var o2_ref: float = ...   # = o2_lower en salas selladas (plume_lower_mode OES)
                           # = room.o2 (bulk) en modo legacy normal
var o2_hrr_factor = smooth(o2_ref / o2_nominal, ...)
room.hrr_kw = smooth(ideal_hrr_kw * o2_hrr_factor, ...)
room.fire_o2_ref = o2_ref   # ← guardado en RoomModel para uso posterior
```

### 2.4 `plume_lower_mode` — OES (`OxygenExchangeSystem.gd` líneas 325–333)

```gdscript
var plume_lower_mode: bool = (
    fire_o2_mode == "legacy" and
    lower_frac >= 0.15 and
    hot_h_upper >= 0.3 and
    not fire_uses_lower_o2 and
    room.hrr_kw > 0.0 and
    _estimate_room_outside_open_factor(building, room) <= 0.01 and  # ← sala sellada
    _estimate_room_interior_open_factor(building, room) <= 0.01     # ← sin doorways
)
```

**Nota:** `plume_lower_mode` en OES se activa independientemente de si `two_zone_solver_enabled=true` (ese flag controla CombustionSystem). En salas selladas con modo legacy, OES usa `o2_lower` para el consumo de O₂ aunque CombustionSystem use `room.o2` (bulk) para el throttle de HRR.

### 2.5 Uso del tracer en FED — ThermalSystem (`ThermalSystem.gd` líneas 3373–3374)

```gdscript
var co2_ppm: float = compute_co2_upper_ppm(room) if in_upper else compute_co2_lower_ppm(room)
# compute_co2_upper_ppm(room) = room.co2_upper × 1e6  ← el tracer OES
# FED CO₂ usa este valor para potentiation V_CO₂ (ISO 13571)
```

### 2.6 Orden de ejecución — `SimulationEngine.gd` líneas 1506–1552 (path default)

```
1. _step_pool_fires(dt)
2. _step_fire(dt)                   ← CombustionSystem: escribe hrr_kw, fire_o2_ref, o2_hrr_factor
3. _step_co_oxidation(dt)
4. _step_targets(dt)                ← FED acumulado
5. _step_oxygen(dt)                 ← OES: lee hrr_kw + fire_o2_ref del paso actual; escribe co2_upper
6. thermal_system.step(...)         ← lee co2_upper para FED; log co2_upper_ppm
7. gas_exchange_system steps (smoke, pressure, PPV)
```

CombustionSystem corre **antes** que OES en el path default (`pre_hrr_o2_step = false`). `room.fire_o2_ref` está actualizado cuando OES ejecuta.

---

## 3. El double-throttle explicado

En sala sellada con fuego activo y `plume_lower_mode = true`:

| Variable | Comportamiento | Valor típico t=320s |
|---|---|---|
| `room.o2_lower` | Drena lento (dividido por `air_mass_kg` total) | ≈ 0.165 |
| `room.o2_upper` | Drena rápido (consumo directo + sin reposición exterior) | ≈ 0.100 |
| `room.o2` (bulk) | Promedio ponderado | ≈ 0.130 |
| `o2_ref` (CombustionSystem) | `room.o2` (legacy mode) | ≈ 0.130 |
| `o2_hrr_factor` | `o2_ref / o2_nominal` suavizado | ≈ 0.63 |
| `hrr_kw` | throttleado por `o2_hrr_factor` | alto |
| `o2_scale` (OES) | `o2_upper / o2_nominal` | ≈ **0.48** |

Resultado:
- `generated_co2_kg` (mass path) ∝ `hrr_kw` × `co2_yield` → **sin throttle adicional**
- `co2_produced` (tracer) ∝ `hrr_kw` × `co2_yield` × **`o2_scale ≈ 0.48`** → suprimido a ~48%

**El tracer recibe un segundo throttle que la masa no recibe.** La divergencia crece mientras `o2_upper` cae.

### Verificación numérica (cfast_slow_growth_sealed, t=320s, room=0)

```
co2_upper_ppm (tracer) = 49573 ppm
co2_upper_ppm_mass     = 101042 ppm
Ratio = 101042 / 49573 ≈ 2.04×
→ o2_scale implícito ≈ 49573 / 101042 ≈ 0.490
→ o2_upper ≈ 0.490 × 0.209 ≈ 0.102  ✓ (consistente con depleción a t=320s)
```

### En casos multi-room (`fuel_balance_diag_sealed`, rooms 1–5)

1. Room 0 (fire room): tracer suprimido como arriba
2. OES transporta CO₂ tracer inter-room: `hot_co2_parcel = hot_room.co2_upper × co2_ex_kg / hot_air_mass_kg`
3. Room 1–5 reciben tracer suprimido de room 0 → D2PRE dispara también en salas receptoras
4. Mass path usa GasExchangeSystem (`co2_upper_kg`, `_delta_co2_upper_kg`) → correcto independientemente

---

## 4. Los 7 casos WARN D2PRE

| Caso | Rooms con WARN | Mecanismo |
|---|---|---|
| `cfast_slow_growth_sealed` | room 0 (fire) | sala single-room sellada, `plume_lower_mode` activo |
| `fuel_balance_diag_sealed` | rooms 0–5 | room 0 suprimido, rooms 1–5 reciben tracer bajo |
| `o2_stoich_diag_sealed` | rooms 0–5 | mismo que arriba |
| `cfast_corridor_chain` | room 1 | recibe tracer bajo de room 0 vía doorway |
| `cfast_multi_fuel_couch_tv` | room 1 | same |
| `g3_gie_ppv_post_knockdown` | rooms varios | fire room suprimido, propagación a recepción |
| `glass_break_window_spike` | room 1 | same; glass break no cambia el mecanismo base |

Los CTRLs con D2PRE alto (v4_co_remote_rooms: 2929, victim_fed: 3445, flashover: 894, etc.) tienen el **mismo root cause** + otros bugs (A3, O2E1). Sus D2PRE actuales están sobredimensionados en los envelopes porque el bug infla los conteos; reducirán tras el fix.

---

## 5. Hipótesis de fix

### Opción A — Condicional por `effective_plume_lower` (RECOMENDADA)

```gdscript
# OxygenExchangeSystem.gd, línea 552 — reemplazar:
#   var o2_scale: float = clampf(room.o2_upper / maxf(0.001, o2_nominal), 0.0, 1.0)
# por:
var o2_scale: float
if effective_plume_lower:
    # En pluma-baja el fuego se alimenta de la zona inferior (aire fresco).
    # CO₂ producido debe escalar con la misma fuente que el HRR real.
    o2_scale = clampf(room.o2_lower / maxf(0.001, o2_nominal), 0.0, 1.0)
else:
    o2_scale = clampf(room.o2_upper / maxf(0.001, o2_nominal), 0.0, 1.0)
```

**Rationale:** En `plume_lower_mode`, la pluma arrastra aire de la zona inferior. La combustión ocurre con el O₂ de esa zona (o2_lower ≈ 0.165–0.205). El CO₂ producido debe escalar con esa misma disponibilidad. No se cambia nada para el modo normal (no-plume).

**Impacto esperado:**
- En `plume_lower_mode`: `o2_scale = o2_lower / 0.209 ≈ 0.79–0.98` → tracer sube de ~50% a ~80-98% del mass path
- D2PRE rel_div baja de 1.03–7.09 a < 1.0 en la mayoría de los timesteps
- Los 7 WARN D2PRE deberían eliminarse o reducirse a < threshold

### Opción B — Usar `room.fire_o2_ref` (más canónica, mayor alcance)

```gdscript
# OES línea 552 — reemplazar por:
var o2_scale: float = clampf(room.fire_o2_ref / maxf(0.001, o2_nominal), 0.0, 1.0)
```

**Rationale:** `fire_o2_ref` es el O₂ que CombustionSystem usó para throttlear `hrr_kw`. Escalar CO₂ con la misma referencia garantiza `co2_tracer / hrr = co2_yield` (constante físico). Más general que Opción A.

**Riesgo:** Requiere que OES ejecute DESPUÉS de CombustionSystem (cierto en path default). Si `pre_hrr_o2_step = true` en algún caso, `fire_o2_ref` sería del paso anterior (lag de un paso). Verificar `_uses_pre_hrr_oxygen_step()`.

### Opción C — Eliminar `o2_scale` (radical)

```gdscript
var co2_produced: float = (room.hrr_kw / 1000.0) * cr_co2 * dt
# Sin o2_scale — hrr_kw ya encoda la condición de combustión
```

**Rationale:** `hrr_kw` ya es un throttle completo; CO₂ yield es constante estequiométrico; no se necesita un segundo factor. Alinea exactamente con el mass path de CombustionSystem.

**Riesgo:** Puede sobreestimar el tracer en casos donde `o2_upper` y `room.o2` están bien acoplados y `o2_upper` contribuye realmente al throttle (salas abiertas). Cambio de comportamiento en más casos que Opción A.

---

## 6. Riesgo sobre FED — CRÍTICO

`room.co2_upper` (tracer OES) es la fuente de `co2_ppm` en el cálculo FED (ThermalSystem líneas 3373–3374, ISO 13571 V_CO₂ potentiation). Actualmente está subescalado.

**Con el fix, en salas selladas (`plume_lower_mode`):**
- `co2_upper_ppm` sube de ~50% a ~80-98% del valor correcto
- El término V_CO₂ = `exp(0.1903 × (co2_pct)^1.036)` sube
- FED_CO₂ y FED total aumentan en salas con fuego sellado

**Casos de riesgo máximo (FED baselines):**
- `v3_hallway_fed_exposure` — tiene FED baseline check; `co2_upper` actualmente subescalado en room 0 (fire), afecta transporte a room 1 (pasillo con víctima). **El FED ~3.47e9 viene de PHY-P1 (bug distinto, CO₂ bulk >100%), pero el FED de víctima en zona normal también cambiará.**
- `victim_fed_incapacitation` — FED baseline en sala con fuego; CO₂ potentiation subirá
- Cualquier caso con check `fed` o `fed_co2` en `reference_checks.json` que active `plume_lower_mode`

**Acción requerida:** Después del fix y antes de commitear, regenerar todos los baselines con checks FED/fed_co/fed_hcn y revisarlos manualmente. No son regresiones automáticas — son correcciones de valor.

**Nota de diseño (ThermalSystem línea 3248):**
> `FED usa esta función (V_CO2 potentiation en ISO 13571); NO cambiar a mass-derived sin auditar impacto en fed_co/fed_hcn.`

El fix no cambia a mass-derived — sigue usando el tracer, simplemente corrige su escala.

---

## 7. Plan de cambio mínimo

### Paso 1 — Lectura de archivos (antes de tocar)

```
sim/core/OxygenExchangeSystem.gd  líneas 547–556   ← único cambio de motor
sim/validation/cases/*.json        buscar casos con plume_lower_mode implícito (sellados)
```

### Paso 2 — Cambio de motor (1 lugar, 3 líneas)

**Archivo:** `sim/core/OxygenExchangeSystem.gd`  
**Línea:** 552  
**Cambio:**

```gdscript
# ANTES
var o2_scale: float = clampf(room.o2_upper / maxf(0.001, o2_nominal), 0.0, 1.0)

# DESPUÉS
var o2_scale: float
if effective_plume_lower:
    o2_scale = clampf(room.o2_lower / maxf(0.001, o2_nominal), 0.0, 1.0)
else:
    o2_scale = clampf(room.o2_upper / maxf(0.001, o2_nominal), 0.0, 1.0)
```

`effective_plume_lower` ya está definido en la línea 346 del mismo bloque (dentro del mismo `for room_id` loop, antes de la sección CO₂). Es accesible directamente.

### Paso 3 — Regenerar CSVs afectados

Regenerar con `run_scenario.py --timeout 480` todos los casos que tienen D2PRE activo (los 7 WARN + los que están en CTRLs con D2PRE):

```
cfast_slow_growth_sealed
fuel_balance_diag_sealed
o2_stoich_diag_sealed
cfast_corridor_chain
cfast_multi_fuel_couch_tv
g3_gie_ppv_post_knockdown
glass_break_window_spike
v4_co_remote_rooms
victim_fed_incapacitation
flashover_simple_house
pvc_curtain_hcl_release
two_storey_smoke
v1_backdraft_accumulation
v8_suppression_reburn
wood_vc_reference
```

### Paso 4 — Actualizar baselines FED (si corresponde)

1. Identificar qué casos tienen checks de FED en `reference_checks.json`
2. Correr `python scripts/simulation/validate_reference_cases.py` y revisar diffs
3. Para checks FED que cambien: confirmar que el nuevo valor es físicamente correcto (CO₂ más alto = FED más alto = correcto)
4. Si hay checks que fallen: actualizar baselines con justificación explícita

### Paso 5 — Actualizar envelopes CTRL

Tras regenerar CSVs, los conteos D2PRE en CTRLs serán menores. Actualizar `KNOWN_INTENTIONAL_CONTROLS` con los nuevos conteos medidos + 25% headroom:

```python
# Ejemplo esperado (estimaciones):
"v4_co_remote_rooms": {"A3": 16, "D2PRE": ???, "E1": 4, "O2E1": 240},  # D2PRE bajará de 2929
"victim_fed_incapacitation": {"A3": 17, "D2": 12, "D2PRE": ???, "E1": 2, "O2E1": 200},
```

---

## 8. Checks después del fix

Ejecutar en orden:

```bash
# 1. Suite de coherencia física — objetivo: 0 WARN D2PRE (los 7 desaparecen)
python scripts/simulation/audit_physics_coherence_suite.py

# 2. Suite ILV — debe mantenerse 15/14/0
python scripts/simulation/audit_ilv_layer_coherence_suite.py

# 3. Guardrails — 10/10; R2-1 detectará CSVs más nuevos que reference_checks.json
#    (normal — se resuelve regenerando también reference_checks.json)
python scripts/simulation/validation_guardrails.py

# 4. Tests — 273 PASS; si los baselines FED cambian, habrá FAIL aquí
python -m pytest tests/

# 5. Validación completa de casos
python scripts/simulation/validate_reference_cases.py

# 6. Links de docs
python scripts/check_docs_links.py
```

**Criterio de éxito:**
- Physics suite: 7 WARN D2PRE → 0 (ó reducción drástica en casos con salas receptoras)
- CTRLs: D2PRE count baja en v4, victim, flashover, pvc, two_storey, v1, v8
- validate_reference_cases: 349/354 PASS o más (posible aumento si los baselines FED aumentan correctamente)
- Tests: 273 PASS (posible actualización de baselines FED → adaptar tests)
- Guardrails: 10/10 (después de regenerar reference_checks.json)

---

## 9. Relación con otros bugs de motor

| Bug | Relación con M1 |
|---|---|
| PHY-P1: CO₂ bulk >100% en salas receptoras | **Independiente** — afecta mass path (`co2_upper_kg`), no el tracer. El fix M1 no lo toca. |
| ILV zombie lower-O₂ (A3) | Independiente — es el throttle de HRR por `o2_upper`. M1 no cambia eso. |
| HVAC instrumentación (D1/S1) | Independiente — HVACSystem, no OES. |
| Fuel inventory write-off (E1) | Independiente — CombustionSystem, no OES. |

---

## 10. Deuda post-M1 anticipada

- Si el fix reduce pero no elimina los D2PRE en casos multi-room receptores: puede quedar una divergencia residual de la dilución del tracer en el transporte inter-room (constante 25% `CO2_EXCHANGE_FRACTION` vs mass path). Diagnóstico separado si ocurre.
- Los 7 WARN D2PRE son los casos sin A3/O2E1/etc.: si D2PRE desaparece en esos, los CTRLs con D2PRE restante son los casos con zombie ILV (para los cuales el D2PRE es colateral del A3). Esos CTRLs se retiran cuando se cierre el zombie ILV.
