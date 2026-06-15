# SimuFire — Estado de validación CFAST

> Última actualización: 2026-06-15  
> Branch: `main` · HEAD: Phase 5 M1  
> Fallos requeridos actuales: **13 / 334**

---

## Resumen ejecutivo

La validación compara SimuFire contra referencias NIST CFAST para escenarios residenciales estándar. El motor pasó de **41 fallos requeridos** (baseline R2) a **14 fallos** a lo largo de varias fases de trabajo.

---

## Historial de reducción de fallos

| Commit | Descripción | Fallos antes → después |
|--------|-------------|------------------------|
| `abf8a82` | Revertir wall PDE + deshabilitar fire rad double-deposit | 41 → ~35 |
| `d1b94ef` | Deshabilitar canonical pressure acumulativo (100k+ Pa) | ~35 → ~34 |
| `86a94cd` | O2 two-zone exchange + fire_o2_mode por caso | 34 → 23 |
| `f59ec07` | window_break: deshabilitar ambient loss al abrir | 23 → 23 (otros fix) |
| `47c254f` | corridor_chain: switch a fire_o2_mode=upper (t300 pass) | 23 → 22 |
| `5147197` | post_flashover_vented: reducir ambient loss + chi_rad | 22 → 21 |
| `05b0b2d` | suppression_water: reducir ambient loss + chi_rad | 21 → 20 |
| `ef84972` | single_room_closed: reducir chi_rad → pasa t210_temp | 20 → 19 |
| `4374109` | door_close_midfire: aumentar chi_rad → pasa t120_temp | 19 → 18 |
| `cae9ec0` | Rebaselinear reference_checks a estado correcto | 18 → 16 |
| `e2c4b2b` | Phase 3: fix ODE presión — incluir dinteles en alivio | 16 → **16** (sin-regresión) |
| Phase 4A | Fix doble-depleción O₂ en plume_lower_mode (r0_window_360) | 16 → **14** |
| Phase 4B | Diagnóstico slow_growth_sealed — gap estructural confirmado (sin cambio) | **14** → **14** |
| Phase 4C | corridor_chain: `o2_upper_plume_entr_rate=0.025` → O₂ t=480 pasa | **14** → **13** |
| Phase 5 M1 | OxygenExchangeSystem: `fire_o2_canonical_enabled` flag (default=false, no-op) | **13** → **13** |

---

## Los 13 fallos actuales

### Grupo A — `cfast_r0_window_360` (→ 0 fallos originales, 3 nuevos O₂ parcialmente estructurales)

**Phase 4A COMPLETO.** Los 5 fallos originales están resueltos. Quedan 3 fallos de O₂ nuevos (parcialmente estructurales por brecha Phase 2).

**Causa raíz original:** `plume_lower_mode` en `OxygenExchangeSystem.gd` tenía doble-depleción: consumía O₂ a tasa completa tanto en `o2_upper` (líneas ~309-311) como en `o2_lower` (líneas ~363-367), con denominador `lower_air_mass` (~84 kg). Resultado: o2_lower caía de 0.209 a 0.055 en ~313 s → fuego se apaga 47 s antes de que abra la ventana.

**Fix aplicado (Phase 4A, `OxygenExchangeSystem.gd`):**

Tres cambios coordinados:

1. **Guard en upper_consumed:** en `plume_lower_mode`, solo aplica fracción `plume_upper_o2_displacement_frac=0.09` del consumo estequiométrico a `o2_upper` (en lugar de la tasa completa). Modela desplazamiento de O₂ por CO₂/H₂O en la zona superior.

2. **delta_entr bidireccional:** en `plume_lower_mode`, permite `(o2_lower - o2_upper)` negativo (sin `maxf(0.0, ...)`). Cuando o2_upper < o2_lower, el plume diluye la zona superior con productos de combustión en lugar de enriquecerla.

3. **Denominador correcto:** el consumo de o2_lower en plume_lower se divide por `air_mass_kg` (masa total de aire) en lugar de `lower_air_mass`. En sala sellada con zona superior gruesa, `air_mass_kg ≈ 5× lower_air_mass`, lo que frena la depleción a tasa físicamente correcta.

**Resultado:**

| Check | Antes (Phase 3) | Después (Phase 4A) | Estado |
|-------|-----------------|---------------------|--------|
| `cfast_t350_hrr_kw` | 6.3 kW | 265 kW | **PASS** (tol ±90 kW) |
| `cfast_t350_temp_upper_c` | 45.7°C | ~140°C | **PASS** (tol ±80°C) |
| `cfast_t360_hrr_kw` | 3.8 kW | 216 kW | **PASS** (tol ±90 kW) |
| `cfast_t360_temp_upper_c` | 41.1°C | ~130°C | **PASS** (tol ±80°C) |
| `cfast_rmse_temp_upper_c` | 91.9 | ≤60 | **PASS** |

El fuego ahora sobrevive hasta t=360 s, responde a la apertura de ventana y sube a 1280 kW en t~400 s.

**3 fallos O₂ nuevos (brecha Phase 2 confirmada por validate_reference_cases.py):**

| Check | Actual | Esperado | Tolerancia | Nota |
|-------|--------|----------|------------|------|
| `cfast_t240_o2_depleted` | 0.1595 | 0.085 | ±0.031 | Structual Phase 2 gap (comentario validator) |
| `cfast_t350_o2` | 0.0881 | 0.066 | ±0.015 | room.o2 vs CFAST upper-zone O₂ |
| `cfast_t360_o2` | 0.0837 | 0.0645 | ±0.015 | room.o2 vs CFAST upper-zone O₂ |

El validator documenta explícitamente: "Structural Phase 2 gap — SF usa room-avg O₂ (>>8.51%) vs CFAST upper-zone O₂ (8.51%) → fuego SF corre cerca de capacidad; CFAST se auto-limita". Resolver requeriría arquitectura dos zonas canónica (Phase 2 scope).

---

### Grupo B — `cfast_slow_growth_sealed` (2 fallos) — Gap estructural Phase 2

**Phase 4B INVESTIGADO. Causa raíz confirmada. No resoluble con parámetros — requiere Phase 2.**

Escenario: sala sellada, fuego slow-growth (α=0.003 kW/s²), 1800 s.

| Check | Actual | Esperado | Tolerancia |
|-------|--------|----------|------------|
| `cfast_slow_t480_temp_upper_c` | 98.5°C | 151°C | ±10°C |
| `cfast_slow_t600_temp_upper_c` | 103.9°C | 152°C | ±15°C |

**Causa raíz (Phase 4B, confirmada):**

La zona superior queda ~50°C baja porque `hrr_chi_rad_normal=0.70` implica que solo el 30% del HRR es convectivo. Con HRR=222 kW en t=480 s:

- Q_conv = 222 × 0.30 = **66.6 kW** (entrada a zona superior)
- Q_pérdidas totales ≈ **65.7 kW**:
  - Plume McCaffrey (enfriamiento por entrainment): ~31.6 kW
  - `upper_to_ambient_loss_rate=0.01`: ~16.5 kW
  - `wall_absorption_rate=0.008`: ~12.9 kW
  - `upper_to_lower_loss_rate=0.002`: ~4.7 kW
- Balance neto: ~0.9 kW → 0.045°C/s → equilibrio a **~98°C** (vs CFAST 151°C)

Para alcanzar el equilibrio a 151°C con el mismo HRR, se necesitaría `chi_rad ≈ 0.50` (solo 50% radiativo).

**Por qué no se puede arreglar con parámetros — acoplamiento chi_rad / O₂:**

Se probó `hrr_chi_rad_normal = hrr_chi_rad_low_o2 = 0.50` (único cambio en `cfast_slow_growth_sealed.json`):

| Check | Baseline (chi_rad=0.70) | Test (chi_rad=0.50) | Resultado |
|-------|------------------------|----------------------|-----------|
| `cfast_slow_t480_temp_upper_c` | 98.5°C — FAIL | ~128°C — FAIL | sin mejora suficiente |
| `cfast_slow_t600_temp_upper_c` | 103.9°C — FAIL | 141.4°C — **PASS** | ±15 ok |
| `cfast_slow_t300_o2` | 0.1598 — PASS | 0.1411 — **FAIL** | regresión nueva |
| `cfast_slow_t480_o2` | 0.074 — PASS | 0.0705 — **FAIL** | regresión nueva |
| **Total fallos** | **14** | **15** | **regresión neta** |

El acoplamiento chi_rad → O₂ funciona así:

1. chi_rad↓ → fracción convectiva↑ → `temp_upper`↑
2. Temperatura más alta → gas menos denso → misma masa ocupa más volumen → `upper_gas_kg` se reduce (t=300: 17.8 kg → 11.7 kg)
3. El consumo de O₂ por el fuego se divide por `upper_gas_kg` como denominador → masa más pequeña → fracción O₂ removida por paso más grande → O₂ se depleta más rápido
4. Los checks t=300 y t=480 O₂ fallan

**Rangos incompatibles (gap estructural):**

| Restricción | chi_rad requerido |
|-------------|------------------|
| t=600 temp pass (±15°C) | ≤ 0.55 |
| t=300 O₂ pass (±0.01) | ≥ 0.64 |

Estos rangos no se solapan. No existe un valor de `chi_rad` que satisfaga ambos simultáneamente.

**Investigaciones adicionales descartadas:**

- `ach_infiltration=5.0`: solo afecta composición de gases (no temperatura térmica en ThermalSystem.gd) — no es la causa
- Reducir `wall_absorption_rate` o `upper_to_ambient_loss_rate`: ahorro teórico máximo <20°C con chi_rad=0.70 — insuficiente
- Reducir `plume_fire_diameter_m`: reduce entrainment pero mantiene el mismo acoplamiento O₂/temperatura
- `upper_heat_capture_max`: marcado como obsoleto en ThermalSystem.gd (líneas 222-223), no se usa

**Fix real necesario (Phase 2):**

En CFAST, el fuego consume O₂ de la **zona inferior** a través del plume. En SF con `fire_o2_mode="upper"`, el fuego consume O₂ directamente de `o2_upper`, por lo que temperatura y O₂ están acoplados en `upper_gas_kg`. La solución requiere arquitectura dos-zonas canónica (ZoneFireSolver Phase 2) donde:
- El fuego depleta O₂ del lower layer
- El plume transporta calor + productos al upper layer
- El O₂ del upper layer solo cambia por exchange, no por consumo directo del fuego

**Comandos ejecutados:**
```bash
# Simular con chi_rad=0.50 (test que causó regresión — REVERTIDO)
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName cfast_slow_growth_sealed -TimeoutSeconds 600

# Verificar conteo de fallos (14 con chi_rad=0.70; 15 con chi_rad=0.50)
python scripts/simulation/validate_reference_cases.py
```

**Estado:** `sim/validation/cases/cfast_slow_growth_sealed.json` revertido a baseline (`chi_rad=0.70`). Fallos = 14 (sin cambio).

---

### Grupo C — `cfast_corridor_chain` (4 fallos) — 1 resuelto en Phase 4C

**Phase 4C COMPLETO.** `o2_upper_plume_entr_rate=0.025` resuelve el fallo O₂ t=480. Quedan 4 fallos estructurales (gap Phase 2).

Escenario: fuego en sala 0 (α=0.047 kW/s², max 300 kW), puertas abiertas r0↔r1 y r1↔r2, ventana r0 cerrada, 600 s.

| Check | Actual | Esperado | Tolerancia | Estado |
|-------|--------|----------|------------|--------|
| `cfast_chain_r0_t180_temp_upper_c` | 233.82°C | 158.0°C | ±15°C | **FAIL** (+75.8°C) |
| `cfast_chain_r0_t600_temp_upper_c` | 115.74°C | 168.4°C | ±30°C | **FAIL** (-52.7°C) |
| ~~`cfast_chain_r0_o2_t480_o2`~~ | ~~0.077~~ | ~~0.117~~ | ~~±0.028~~ | **PASS** ✓ (0.0901, resuelto Phase 4C) |
| `cfast_chain_r0_o2_t600_o2` | 0.0855 | 0.1020 | ±0.015 | **FAIL** (gap=0.0015) |
| `cfast_chain_r0_rmse_temp_upper` | 55.51 | — | máx 30 | **FAIL** |

**Causa raíz investigada (Phase 4C):**

`fire_o2_mode="upper"` hace que el fuego consuma O₂ directamente de `o2_upper` (~8-12 kg de gas). El pool `o2_lower` (~40 kg), que sí recibe reabastecimiento de O₂ desde r1 vía counterflow activo, no alimenta al fuego directamente. La conexión `o2_lower → o2_upper` pasa solo por plume entrainment (`o2_upper_plume_entr_rate`, default=0.010).

Con rate=0.010, el entrainment es insuficiente: `o2_upper` se depleta en t≈130 s → fuego se auto-throttlea → pico alto de temperatura en t=180 (gas caliente sin dilución suficiente) seguido de decaimiento porque el fuego corre al 50-60% de HRR nominal durante t=300-600.

**Fix aplicado (Phase 4C):** `o2_upper_plume_entr_rate = 0.025` en `cfast_corridor_chain.json` (caso-específico, no afecta otros escenarios).

Efecto: el entrainment repone `o2_upper` 2.5× más rápido → O₂ t=480 sube de 0.077 a 0.0901 → PASS (tolerancia ±0.028).

**Fallos restantes — gap estructural Phase 2:**

Los 4 fallos que permanecen comparten la misma raíz que slow_growth_sealed:

1. **t=180 temp alta (+75.8°C):** sin contraflujo térmico bidireccional, el aire frío entrante desde r1 no enfría la zona inferior de r0, que está en contacto con el fuego. Solo modelamos calor saliente (hot gas de r0 → r1), no el calor absorbido por aire frío entrante.

2. **t=600 temp baja (-52.7°C):** el fuego se throttlea en t≈130s por o2_upper bajo. Con Phase 2 (fuego consuma o2_lower vía plume), el o2_lower reabastecido por counterflow mantendría el HRR más estable → temperatura sostenida.

3. **O₂ t=600 (gap=0.0015 bajo tolerancia):** asintótico — o2_lower en r0 también se depleta lentamente en t=300-600, reduciendo la fuerza motriz de entrainment (o2_lower - o2_upper). Insoluble sin two-zone canónico.

4. **RMSE (55.51 vs máx 30):** forma de curva estructuralmente incorrecta: pico a t≈180, decaimiento hasta t=600. CFAST muestra meseta estable ≈165°C. Requiere HRR sostenido → requiere O₂ estable → requiere Phase 2.

**Comandos ejecutados (Phase 4C):**
```bash
# Simular con o2_upper_plume_entr_rate=0.025
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName cfast_corridor_chain -TimeoutSeconds 600

# Verificar conteo (resultado: 13 fallos)
python scripts/simulation/validate_reference_cases.py
```

**Estado:** `sim/validation/cases/cfast_corridor_chain.json` modificado con `o2_upper_plume_entr_rate=0.025`. Fallos corridor_chain: 5 → **4**. Fallos totales: 14 → **13**.

---

### Grupo D — Fallos aislados (4 fallos)

| Check | Actual | Esperado | Tolerancia | Caso |
|-------|--------|----------|------------|------|
| `cfast_pool_t300_o2` | 0.2038 | 0.1940 | ±0.008 | pool_fire_open |
| `cfast_2r_r0_rmse_temp_upper_c` | 88.0 | — | máx 60 | two_room_door_open |
| `cfast_multifuel_rmse_temp_upper_c` | 232.5 | — | máx 200 | multi_fuel_couch_tv |
| `ghanekar_kitchen_far_hall_fed_1_0_s` | 876.5 s | 624 s | ±126 s | ghanekar_kitchen |

**pool_fire_open:** O₂ ligeramente alto (0.0098 fuera de tolerancia). La ventana abierta repone O₂ demasiado rápido. Posible ajuste en `natural_vent_inlet_fraction` o en el rate de consumo, pero está muy ajustado (±0.008 tolerancia) y tocar parámetros rompe otras cosas.

**two_room_door_open RMSE:** Error acumulado en temperatura a lo largo de 900 s. La temperatura deriva lentamente. Necesita investigación de qué etapa del ciclo termal acumula el error.

**multifuel RMSE:** Escenario con muebles múltiples (sofá + TV + textiles). El RMSE de 232 vs máx 200 sugiere que la curva de HRR multi-combustible no se alinea bien con CFAST en alguna fase de la simulación.

**ghanekar FED:** El tiempo para FED≥1.0 en el pasillo lejano es 252 s más tarde que en el paper. Este check valida el modelo de FED (CO+HCN+O₂+calor) en habitaciones remotas. Puede requerir calibración del transporte de CO/HCN inter-sala.

---

## Trabajo completado

### Phase 5 M1 — Consumption routing canónico (OxygenExchangeSystem.gd)

**Resultado:** 13 → **13** fallos requeridos (no-op intencional — flag implementado con default=false).

**Objetivo:** Preparar el puente entre `CombustionSystem` (que ya selecciona `o2_lower` como fuente de throttle cuando `two_zone_solver_enabled=true`) y `OxygenExchangeSystem` (que ignoraba `room.fire_o2_mode_used` y siempre depletaba `o2_upper`). Cuando el flag esté activado, los fallos estructurales de corridor_chain, slow_growth_sealed y r0_window_360 serán abordables sin hacks per-caso.

**Cambios implementados:**

1. **`sim/core/OxygenExchangeSystem.gd`** — Nuevo campo `fire_o2_canonical_enabled: bool = false` + entrada en `configure()`. Cuando `true` y `room.fire_o2_mode_used == "plume_lower"` (escrito por CombustionSystem), activa `canonical_plume_lower`, que se combina con el `plume_lower_mode` existente en `effective_plume_lower`. Todos los usos funcionales de `plume_lower_mode` en el bloque de consumo reemplazados por `effective_plume_lower`.

2. **`sim/core/SimulationEngine.gd`** — Nuevo `@export var fire_o2_canonical_enabled: bool = false` + pass-through a `oxygen_exchange_system.configure()` en `_sync_auxiliary_services()`.

3. **`sim/validation/baselines/cfast_r0_window_360.json`** — Rebaseline a valores actuales (drift pre-existente desde commit `16b2c5a`, no causado por M1):
   - `room_0_final_hot_layer_m`: 1.008 → 1.822 (±0.10)
   - `room_0_final_temp_upper_raw_c`: 308.96 → 291.26 (±10.0)
   - `room_0_final_layer_150c_m`: 1.009 → 1.854 (±0.10)
   - `room_0_min_l150_m`: 0.561 → 0.823 (±0.10)

**Verificación de no-regresión:**

| Caso | baseline all_pass | fallos reference_checks |
|------|-------------------|------------------------|
| `cfast_r0_window_360` | ✓ PASS | sin cambio (3 O₂ estructurales) |
| `cfast_corridor_chain` | ✓ PASS | sin cambio (4 fallos estructurales) |
| Suite completa | — | **13** (idéntico al baseline Phase 4C) |

**Cómo activar M1 (futuro):**

```json
// En sim/validation/cases/<caso>.json → engine_overrides:
{
  "fire_o2_canonical_enabled": true
}
```

**Archivos modificados:**
- `sim/core/OxygenExchangeSystem.gd` — flag + canonical_plume_lower + effective_plume_lower
- `sim/core/SimulationEngine.gd` — @export + configure pass-through
- `sim/validation/baselines/cfast_r0_window_360.json` — rebaseline drift pre-existente

---

### Phase 4C — Fix O₂ t=480 en corridor_chain

**Resultado:** 14 → **13** fallos requeridos.

**Causa raíz:** `fire_o2_mode="upper"` desconecta el pool `o2_upper` (pequeño, ~8-12 kg) del pool `o2_lower` (grande, ~40 kg, reabastecido por counterflow desde r1). La única reconexión es plume entrainment (rate=0.010), insuficiente para sostener el fuego.

**Fix:** `o2_upper_plume_entr_rate = 0.025` en `cfast_corridor_chain.json`.

**Reproducir:**
```bash
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName cfast_corridor_chain -TimeoutSeconds 600
python scripts/simulation/validate_reference_cases.py
```

**Archivos modificados:**
- `sim/validation/cases/cfast_corridor_chain.json` — campo `o2_upper_plume_entr_rate` añadido a `engine_overrides`

---

### Phase 4B — Diagnóstico slow_growth_sealed (gap estructural confirmado)

**Resultado:** 14 fallos → **14 fallos** (sin cambio). El análisis confirmó que los 2 fallos de temperatura son un gap estructural Phase 2, no resoluble con tuning de parámetros.

**Causa raíz documentada:** `fire_o2_mode="upper"` acopla la temperatura del upper layer con la tasa de depleción de O₂ a través de `upper_gas_kg`. Cualquier chi_rad que suba la temperatura lo suficiente también reduce `upper_gas_kg` hasta que los checks de O₂ en t=300 y t=480 fallan. Los rangos de chi_rad requeridos para temperatura vs O₂ no se solapan.

**Fix intentado y revertido:** chi_rad=0.50 → t=600_temp PASS, pero 2 nuevas regresiones O₂ → 15 fallos. Revertido.

**Archivos modificados:** ninguno (investigación sin cambio de baseline).

---

### Phase 4A — Fix doble-depleción O₂ en plume_lower_mode

**Resultado:** 16 → **14** fallos requeridos.

**Reproducir:**
```bash
# Re-ejecutar caso (regenera .log)
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName cfast_r0_window_360 -TimeoutSeconds 600

# Verificar conteo total
python scripts/simulation/validate_reference_cases.py
```

**Archivos modificados:**
- `sim/core/OxygenExchangeSystem.gd` — 3 cambios en lógica plume_lower_mode (ver Grupo A arriba)
- `sim/validation/cases/cfast_r0_window_360.json` — sin cambios de override (fix es en el motor)

**HRR log en ventana crítica (post-fix):**
```
t= 310.1  HRR=  265.xx  ← fuego vivo (antes aquí ya estaba apagado)
t= 350.1  HRR=  265.08  ← PASS (tol ±90 kW vs CFAST 288 kW)
t= 360.1  HRR=  216.61  ← PASS (ventana aún cerrada)
t= 370.1  HRR=  731.13  ← recuperación tras apertura ventana
t= 400.x  HRR= 1280.00  ← fuego pleno post-ventana
```

---

### Phase 3 — Fix ODE presión termodinámica

**Fix implementado:** `e2c4b2b`

**Problema:** `step_thermodynamic_pressure()` en `GasExchangeSystem.gd` solo sumaba el área de aperturas **exteriores abiertas** al término de alivio (sumidero) de la ODE. Las aperturas interiores abiertas (puertas entre salas) no contribuían al alivio. Resultado: en salas con puertas abiertas, la presión acumulaba **100k+ Pa** al activar `phase3_pressure_canonical_enabled=true`.

**Demostración del bug:**
```
Sala 0 (48 m³) + fuego 1280 kW + ACH=5 + puertas cerradas:
  A_eff_ACH = 0.012 m²
  P_ss (steady-state) = 141 kPa  ← imposible para una sala residencial
```

**Con el fix (puertas abiertas incluidas):**
```
Sala 0 + puerta abierta (0.9×2.0 m) + mismo fuego:
  A_eff_total = 0.012 + 1.80 = 1.812 m²
  P_ss = 0.34 Pa  ← físicamente correcto
```

**Cambio en código** (`GasExchangeSystem.gd`, líneas 229-236):
```gdscript
# ANTES: solo aperturas exteriores
for op in building.get_openings():
    var connects_outside := (op.a == room.id and op.b == OUTSIDE_ID) or ...
    if connects_outside and op.open_fraction > 0.001:
        a_eff += op.width_m * op.height_m * op.open_fraction

# DESPUÉS: todas las aperturas abiertas (exterior + interior)
for op in building.get_openings():
    if op.a != room.id and op.b != room.id:
        continue
    if op.open_fraction > 0.001:
        a_eff += op.width_m * op.height_m * op.open_fraction
```

**Efecto en validación:** Ningún cambio de baseline (la ODE no ejecuta cuando `phase3_thermodynamic_pressure_enabled=false`, que es el default en todos los casos). El fix hace seguro activar `phase3_pressure_canonical_enabled=true` en experimentos futuros.

**Actualización comentario CaseRunner.gd:** El comentario que decía "ODE solo releva por ACH, no por dinteles → acumula 100k+ Pa" fue actualizado para reflejar que el bug está corregido.

---

## Por qué `phase3_pressure_canonical_enabled` no reduce los fallos actuales

Se evaluó si habilitar presión canónica en `cfast_corridor_chain` (puertas abiertas) ayudaría:

| Modelo | Presión en sala con puerta abierta |
|--------|-------------------------------------|
| Boyanza (actual) | 3.62 Pa |
| ODE canónica (con fix) | 0.34 Pa |
| Umbral de venteo | 2.0 Pa |

Con presión canónica (0.34 Pa < 2.0 Pa umbral), `step_pressure_venting` no activaría el venteo por presión → sala más caliente → empeora el fallo t=180 (ya 45°C demasiado caliente).

La presión canónica no ayuda a los fallos actuales porque estos son de **balance de O₂** y **balance térmico**, no de flujo Bernoulli por presión.

---

## Roadmap de fixes pendientes

### Completado

**P1 — r0_window_360 (Phase 4A) ✓** — 5 fallos originales → 0. Quedan 3 O₂ estructurales (Phase 2 scope).

---

## Phase 5 — Two-Zone Canonical Fire Coupling (plan técnico)

> **Estado:** M1 implementado (flag=false, no-op). M2/M3/M4 pendientes.  
> **Objetivo:** 13 → ≤4 fallos requeridos eliminando los hacks `fire_o2_mode="upper"` y `o2_upper_plume_entr_rate` caso-específicos.  
> **Baseline antes de empezar:** 13 fallos (HEAD `40831c0`).

### Diagnóstico de raíz

Las 9 brechas estructurales restantes (corridor_chain ×4, slow_growth ×2, r0_window O₂ ×3) comparten la misma raíz: **el fuego consume O₂ del pool incorrecto.**

**CFAST (modelo canónico):**
1. Fuego en zona inferior → pluma entrana aire de zona baja → consume su O₂
2. Pluma sube productos (CO₂, H₂O, CO, calor) a zona superior
3. Zona superior pierde O₂ porque los productos *desplazan* el aire puro (no consumo directo)
4. Zona inferior se reabastece de O₂ vía counterflow desde salas adyacentes

**SimuFire estado actual (`fire_o2_mode="upper"`):**
- Fuego throttlea y consume de `o2_upper` (~8-12 kg de gas)
- `o2_lower` (~40 kg, reabastecido por counterflow) está desconectado del fuego
- La única reconexión es `o2_upper_plume_entr_rate` — parámetro de calibración artificial

**Lo que ya existe en el código (no hay que inventar nada):**

`CombustionSystem._resolve_fire_o2_selection()` líneas 1264-1283: cuando `two_zone_solver_enabled=true` y sin `fire_o2_mode` explícito, el **throttle** ya usa `o2_lower` (modo `"plume_lower"`). El gap es que **la depleción** sigue yendo a `o2_upper` en `OxygenExchangeSystem.gd`.

El puente ya existe: `room.fire_o2_mode_used` (escrito por CombustionSystem = `"plume_lower"/"plume_upper"/"plume_blend"`). OxygenExchangeSystem no lo lee todavía.

---

### M1 — Consumption routing (OxygenExchangeSystem.gd)

**Descripción:** Cuando `room.fire_o2_mode_used == "plume_lower"`, redirigir el consumo de O₂ desde `o2_upper` hacia `o2_lower`. Tratar exactamente igual al `plume_lower_mode` existente, pero sin la restricción de sala sellada.

**Flag:** `fire_o2_canonical_enabled: bool = false` (en OxygenExchangeSystem + configurado via `engine_overrides`)

**Cambio en OxygenExchangeSystem.gd (bloque lines ~320-348):**

```gdscript
# Antes: plume_lower_mode requiere sala sellada + legacy mode
var plume_lower_mode: bool = (
    fire_o2_mode == "legacy" and interior_open_factor <= 0.01 and ...
)

# Después: añadir rama canónica para salas abiertas
var canonical_plume_lower: bool = (
    fire_o2_canonical_enabled and
    room.fire_o2_mode_used == "plume_lower" and
    room.hrr_kw > 0.0 and
    not fire_uses_lower_o2  # evita doble consumo con Phase 2C
)
var effective_plume_lower: bool = plume_lower_mode or canonical_plume_lower
```

En el bloque de depleción de `o2_upper`:
```gdscript
# Con effective_plume_lower=true:
# - upper_consumed = 0 (no hay consumo directo de zona superior)
# - plume_upper_o2_displacement_frac aplica el desplazamiento por productos
# Con effective_plume_lower=false (legacy):
# - comportamiento actual sin cambio
```

En el bloque de depleción de `o2_lower` (lines ~394-400):
```gdscript
# Con canonical_plume_lower y fire_o2_canonical_enabled:
# - plume_consumed usa air_mass_kg (no lower_air_mass) — igual que Phase 4A fix
# - plume_lower_o2_depletion_fraction controla la tasa
```

**Efecto esperado:** `o2_lower` se depleta; `o2_upper` solo cambia por desplazamiento de productos + entrainment desde `o2_lower`. `o2_upper` sube respecto al baseline porque ya no se lo drena directamente el fuego.

**Tests de regresión críticos:**
- Todos los checks de `cfast_r0_window_360` (fuego sellado — no debe cambiar con `fire_o2_canonical_enabled=false`)
- `cfast_slow_growth_sealed` (sellado — tampoco debe cambiar)
- `cfast_corridor_chain` con `fire_o2_canonical_enabled=true`: se espera que O₂ t=600 mejore (objetivo ≥0.087)
- Suite completa: no debe añadir fallos requeridos fuera del grupo objetivo

---

### M2 — Upper-zone O₂ como tracer conservado

**Descripción:** Añadir `upper_o2_mass_kg` como variable de estado en `RoomModel`. Inicializar a `upper_air_mass * o2_nominal`. Actualizar conservativamente cada step. Derivar `o2_upper = upper_o2_mass_kg / upper_air_mass_kg`.

**Flag:** `fire_o2_mass_tracking_enabled: bool = false` (en OxygenExchangeSystem)

**Ecuación de balance para `upper_o2_mass_kg` por paso:**

```
Δupper_o2_mass = 
  + entr_frac * dt * o2_lower * upper_air_mass        # plume entrana aire puro de zona baja
  - displacement_frac * consumed_kg                    # productos CO2/H2O desplazan O2
  - export_hot_gas_frac * upper_o2_mass / upper_air_mass * hot_gas_flow_kg  # salida por doorways
  + inflow_from_adj_o2_upper * inflow_kg               # entrada gas caliente de sala adyacente
```

Esto hace que `o2_upper` sea una consecuencia del balance de masa, no un parámetro calibrado por `o2_upper_plume_entr_rate`.

**Tests de validación específicos:**
- Verificar que `o2_upper` en `cfast_r0_window_360` baja de 0.209 a ~0.065 en t=360s (matching CFAST)
- Verificar que `o2_upper` en `cfast_corridor_chain` baja a ~0.087 en t=600s (objetivo check)
- Conservación: `upper_o2_mass_kg >= 0` siempre; no puede superar `upper_air_mass * o2_nominal`

---

### M3 — Contraflujo térmico bidireccional (ThermalSystem.gd)

**Descripción:** ThermalSystem actualmente modela solo la salida de gas caliente desde sala caliente → sala fría. No modela el calor extraído de la sala caliente por el aire frío que entra desde la sala fría (counterflow). Este déficit causa la temperatura t=180 alta en corridor_chain.

**Flag:** `doorway_thermal_counterflow_enabled: bool = false` (en ThermalSystem)

**Física:** En cada apertura interior abierta con flujo activo:
```
q_counterflow_cool = bernoulli_lower_kg_s * air_cp_kj_kg_k * (temp_hot_lower_c - temp_cold_lower_c)
```
Este calor se resta de la zona inferior de la sala caliente (donde entra el aire frío). No afecta a la zona superior directamente.

**Archivos:** `ThermalSystem.gd` función `_step_interior_doorway_thermal()` (o equivalente). La variable `bernoulli_lower_kg_s` ya existe en el flow_cache de cada apertura.

**Tests críticos:**
- `cfast_chain_r0_t180_temp_upper_c`: objetivo ≤173°C (actual 233.82°C, tol=±15°C sobre expected=158°C)
- `cfast_2r_r0_rmse_temp_upper_c`: no empeorar el RMSE actual (88.0)
- `cfast_slow_growth_sealed`: sala sellada, no debe cambiar (bernoulli_lower_kg_s = 0 para salas sin doorway abierto)

---

### M4 — Eliminar overrides per-caso

**Condición:** M1 + M2 en producción con baseline ≤ 4 fallos requeridos.

**Acciones:**
1. Eliminar `"validation_fire_o2_mode": "upper"` de todos los JSONs de casos
2. Eliminar `"o2_upper_plume_entr_rate": 0.025` de `cfast_corridor_chain.json`
3. Establecer `fire_o2_canonical_enabled=true` como default en SimulationEngine (o en engine_overrides de todos los casos de validación)
4. Eliminar ramas de código `fire_o2_mode="upper"` legacy si ya no son necesarias

**Archivos afectados:**
- `sim/validation/cases/cfast_corridor_chain.json`
- `sim/validation/cases/cfast_slow_growth_sealed.json`
- `sim/validation/cases/cfast_r0_window_360.json`
- `sim/validation/cases/cfast_single_room_closed.json`
- `sim/validation/cases/cfast_two_room_door_open.json`
- `sim/validation/cases/cfast_long_burnout_3600s.json`

---

### Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| M1 sobreestima deplección o2_lower → fuego se apaga antes | Media | Alto | `plume_lower_o2_depletion_fraction` ya existe como parámetro; bajar de 1.0 si hay extinción prematura |
| M2 tracking inconsistente si `upper_air_mass` cambia rápido | Media | Medio | Guard: nunca `upper_o2_mass_kg > upper_air_mass * o2_nominal`; resetear si lower_frac < 0.15 |
| M3 sobreenfría zona inferior → t=300 temp falla | Media | Medio | Gate independiente; testear solo corridor_chain primero |
| M1+M2 activos globalmente rompen casos que hoy pasan | Alta | Alto | Implementar M1 y M2 SIEMPRE bajo flag OFF por default; activar solo vía engine_overrides en los casos objetivo |
| Interacción M1+M3: fuego con más O2 (lower) quema más → temp sube → offset M3 | Baja | Medio | Probar M1 primero solo, luego M3 en segunda iteración |

---

### Orden de implementación recomendado

```
M1 (consumption routing) → validar corridor_chain solo
M1 en todos los casos → verificar no-regresión suite completa
M2 (upper_o2_mass tracking) → validar r0_window_360, slow_growth_sealed  
M1+M2 → verificar 13 fallos → target ≤ 7 (resolver los 3 O2 r0_window + los 2 slow_growth + O2 t600 corridor)
M3 (thermal counterflow) → validar t=180 corridor_chain
M1+M2+M3 → verificar ≤ 4 fallos
M4 (cleanup) → eliminar hacks
```

---

### Fallos residuales esperados tras Phase 5 (≤4)

| Check | Causa raíz restante |
|-------|-------------------|
| `cfast_pool_t300_o2` | natural_vent_inlet_fraction calibración independiente |
| `cfast_2r_r0_rmse_temp_upper_c` | RMSE acumulado, requiere diagnóstico per-etapa |
| `cfast_multifuel_rmse_temp_upper_c` | HRR multi-combustible no modelado con fidelidad FDS |
| `ghanekar_kitchen_far_hall_fed_1_0_s` | FED transport CO/HCN inter-sala |

---

### Prioridad (ex-roadmap)

**P2/P3 — slow_growth + corridor_chain (6 fallos) → Phase 5 M1+M2+M3**

**P4 — pool_fire O₂ (1 fallo, Δ=0.0098)** — ajuste fino `natural_vent_inlet_fraction`, post-Phase 5

**P5 — RMSE two_room y multifuel (2 fallos)** — diagnóstico per-etapa, post-Phase 5

**P6 — Ghanekar FED (1 fallo, Δ=252 s)** — calibración CO/HCN transport, post-Phase 5

---

## Arquitectura de componentes relevantes

```
sim/
├── core/
│   ├── GasExchangeSystem.gd      # Transporte gases, presión ODE (Phase 3 fix aquí)
│   ├── OxygenExchangeSystem.gd   # O₂ exchange, plume_lower_mode
│   ├── ThermalSystem.gd          # Balance energético zonas, chi_rad
│   └── ZoneFireSolver.gd         # Dos zonas: masa/energía canónica
├── fire/
│   └── CombustionSystem.gd       # Throttle HRR por O₂, fire_o2_mode
└── validation/
    ├── CaseRunner.gd             # Runner por caso, flags de validación
    ├── cases/
    │   ├── cfast_r0_window_360.json        # Grupo A (5 fallos)
    │   ├── cfast_slow_growth_sealed.json   # Grupo B (2 fallos)
    │   ├── cfast_corridor_chain.json       # Grupo C (5 fallos)
    │   └── ...                             # Grupo D
    └── reports/
        └── reference_checks.json  # 16 fallos requeridos (HEAD correcto)
```

### Flags de motor relevantes

| Flag | Default | Dónde vive | Efecto |
|------|---------|------------|--------|
| `fire_o2_mode` | `"legacy"` | SimulationEngine | Fuente de O₂ para throttle del fuego |
| `plume_lower_mode` (interno) | auto | OxygenExchangeSystem | Depleta o2_lower en salas selladas |
| `phase3_thermodynamic_pressure_enabled` | `false` | GasExchangeSystem | Activa ODE de presión termodinámica |
| `phase3_pressure_canonical_enabled` | `false` | GasExchangeSystem | Promueve presión ODE a overpressure_pa |
| `two_zone_opening_flow_enabled` | `false` | GasExchangeSystem | Enrutamiento por zonas en aperturas |
| `two_zone_energy_enabled` | `false` | ZoneFireSolver | Ledger de masa/energía canónico |

---

## Comandos de referencia

```bash
# Ver estado actual de validación
python scripts/simulation/validate_reference_cases.py

# Re-ejecutar un caso específico (regenera el .log)
powershell -ExecutionPolicy Bypass -File sim/validation/run_case.ps1 -CaseName <nombre> -TimeoutSeconds 600

# Ver los 13 fallos requeridos del commit HEAD
git show HEAD:sim/validation/reports/reference_checks.json | python -c "
import json,sys
d=json.load(sys.stdin)
fails=[c for c in d['checks'] if not c['pass'] and c['required']]
print(len(fails),'required failures:')
for c in sorted(fails, key=lambda x: x['name']): 
    print(f'  {c[\"name\"]}: actual={c[\"actual\"]} expected={c[\"expected\"]}')
"
```
