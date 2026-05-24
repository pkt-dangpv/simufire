# Inventario de Gaps — SimuFire vs CFAST
**Generado**: 24 mayo 2026 | **Actualizado**: 24 mayo 2026 (post Phase 2E reporting fix)  
**Estado validación**: 289/289 PASS required, 73 gaps non-gating  
**Fuente**: `sim/validation/reports/reference_checks.json`

---

## Resumen por categoría

| Categoría | Checks | Causa raíz | Cierre estimado |
|-----------|--------|------------|-----------------|
| Presión termódinámica vs boyancia | 18 | Modelo de presión SF es termostático (1-10 Pa); CFAST usa boyancia two-zone (100-1000 Pa) | Phase 3 (modelo boyancia) |
| O₂ zona inferior | 10 | SF mezcla O₂ uniformemente; CFAST preserva ≈20.5% en zona baja | Phase 2E (two-zone doorway flow) |
| CO₂ upper layer | 5 | Transporte CO₂ a zona superior subestimado | Phase 2E (two-zone CO₂) |
| RMSE temperatura superior | 8 | Wall heat loss subestimado + diferencias de volumen | Phase 1.5 (conducción 1D paredes) |
| Escenarios complejos (HVAC, multi-floor) | 5 | Mezcla uniforme O₂ extingue fuego; CFAST two-zone lo sostiene | Phase 2E |
| Phase 1.5 (paredes, flashover) | 4 | Conducción 1D no implementada; HRR post-flashover timing | Phase 1.5 |
| Calibración puntual | 5 | Ghanekar CO chemistry, g3 timing, growth-phase | Calibración ad-hoc |
| CO lower zone reporting | 1 | `compute_co_lower_ppm` retorna media de sala cuando `upper_gas_kg < 0.1`; CFAST upper-stratified → lower≈0 | Diferencia arquitectural — no regresión required |
| Stage-B pending (sin datos) | 10 | Casos planificados sin baseline todavía | Stage-B |

**Total: 63 checks con datos + 10 pending = 73 gaps**  
*(Corrección respecto a conteo anterior: el GAPS_INVENTORY inicial reportaba 65, pero la verificación post Phase 2E reporting fix muestra 73. La diferencia de 8 se debe a: 7 checks que ya fallaban antes pero no estaban en el conteo inicial — incluyendo presión `cfast_closed_t240`, `cfast_fastgrowth`, y O₂ pasillo — más 1 gap nuevo introducido por el guard `upper_gas_kg < 0.1` en `compute_co_lower_ppm`.)*

---

## Detalle por categoría

### 1. Presión termódinámica vs boyancia (15 checks)

**Gap estructural**: SF calcula presión desde balance de masa/energía (termostático) → 1-10 Pa.  
CFAST usa modelo de boyancia two-zone con gradiente de densidad → 100-1000 Pa en sala sellada.  
**No se puede cerrar sin reimplementar el modelo de presión.**

| Check | t (s) | SF actual (Pa) | CFAST expected (Pa) | Escenario |
|-------|-------|----------------|---------------------|-----------|
| `cfast_closed_t60_pressure_pa` | 60 | 0.41 | 124.0 ±50 | Sala sellada |
| `cfast_closed_t120_pressure_pa` | 120 | 2.0 | 1022.1 ±50 | Sala sellada |
| `cfast_closed_t360_pressure_pa` | 360 | 9.01 | 167.9 ±50 | Sala sellada |
| `cfast_closed_t480_pressure_pa` | 480 | 4.55 | 168.2 ±50 | Sala sellada |
| `cfast_t350_pressure_pa` | 350 | 6.57 | 167.5 ±20 | Ventana abierta |
| `cfast_2r_r0_t120_pressure_pa` | 120 | 1.98 | 303.7 ±30 | Dos salas |
| `cfast_2r_r0_t240_pressure_pa` | 240 | 4.82 | 163.1 ±30 | Dos salas |
| `cfast_2r_r0_t360_pressure_pa` | 360 | 6.99 | -38.7 ±30 | Dos salas |
| `cfast_hvac_t180_pressure_pa` | 180 | 3.08 | 768.4 ±50 | HVAC |
| `cfast_hvac_t300_pressure_pa` | 300 | 10.21 | 154.6 ±50 | HVAC |
| `cfast_hvac_t450_pressure_pa` | 450 | 1.55 | 168.4 ±50 | HVAC |
| `cfast_burnout_t60_pressure_pa` | 60 | 0.41 | 124.0 ±50 | Burnout |
| `cfast_burnout_t120_pressure_pa` | 120 | 2.0 | 1022.1 ±50 | Burnout |
| `cfast_burnout_t180_pressure_pa` | 180 | 2.99 | 768.4 ±50 | Burnout |
| `cfast_doorclose_r0_t120_pressure_pa` | 120 | 1.98 | 303.7 ±50 | Puerta cerrada |
| `cfast_doorclose_r0_t300_pressure_pa` | 300 | 10.6 | 154.3 ±50 | Puerta cerrada |
| `cfast_fastgrowth_t60_pressure_pa` | 60 | 1.16 | 489.6 ±50 | Fast growth |
| `cfast_fastgrowth_t120_pressure_pa` | 120 | 3.95 | 2087.7 ±50 | Fast growth |

---

### 2. O₂ zona inferior (9 checks)

**Gap Fase 2A**: SF rastrea `o2_lower` como variable independiente pero el flujo entre zonas via vano no está implementado como two-zone. Resultado: `o2_lower` se equilibra con la sala → no refleja la capa baja de aire fresco de CFAST.  
**Cierre**: two-zone doorway flow (aire fresco entra por mitad inferior del vano).

| Check | t (s) | SF actual | CFAST expected | Escenario |
|-------|-------|-----------|----------------|-----------|
| `cfast_t350_o2_lower` | 350 | 0.0693 | 0.2049 ±0.015 | Ventana abierta |
| `cfast_t420_o2_lower` | 420 | 0.1658 | 0.1878 ±0.015 | Ventana abierta |
| `cfast_closed_t300_o2_lower` | 300 | 0.0684 | 0.2049 ±0.015 | Sala sellada |
| `cfast_closed_t450_o2_lower` | 450 | 0.0429 | 0.2049 ±0.015 | Sala sellada |
| `cfast_hvac_t180_o2_lower` | 180 | 0.156 | 0.2049 ±0.015 | HVAC |
| `cfast_hvac_t300_o2_lower` | 300 | 0.058 | 0.2049 ±0.015 | HVAC |
| `cfast_hvac_t450_o2_lower` | 450 | 0.0336 | 0.2049 ±0.015 | HVAC |
| `cfast_2r_r0_t180_o2_lower` | 180 | 0.2032 | 0.1826 ±0.015 | Dos salas (sala fuego) |
| `cfast_2r_r0_t300_o2_lower` | 300 | 0.209 | 0.0952 ±0.015 | Dos salas (sala fuego) |
| `cfast_2r_r0_t450_o2_lower` | 450 | 0.0675 | 0.0909 ±0.015 | Dos salas (sala fuego) |

---

### 3. CO₂ upper layer (5 checks)

**Gap**: Transporte de CO₂ a la zona superior es insuficiente. Requiere two-zone CO₂ tracking completo con fracción upper/lower en el transporte de gas caliente.

| Check | t (s) | SF actual | CFAST expected | Escenario |
|-------|-------|-----------|----------------|-----------|
| `cfast_t510_co2_upper_ppm` | 510 | 16182 ppm | 52300 ±20000 ppm | Sala única |
| `cfast_2r_r0_t120_co2_upper_pct` | 120 | 4.75% | 1.58% ±3.0% | Dos salas (sala fuego) |
| `cfast_2r_r0_t480_co2_upper_pct` | 480 | 0.999% | 9.91% ±3.0% | Dos salas (sala fuego) |
| `cfast_fo_t240_co2_upper_pct` | 240 | 4.32% | 7.77% ±3.0% | Post-flashover |
| `cfast_fo_t350_co2_upper_pct` | 350 | 0.77% | 7.89% ±3.0% | Post-flashover |

---

### 4. RMSE temperatura superior (8 checks)

**Gap**: Wall heat loss subestimado (no hay conducción 1D) + diferencias de volumen entre escenarios SF y CFAST.

| Check | SF RMSE | Límite | Escenario |
|-------|---------|--------|-----------|
| `cfast_rmse_hot_layer_m` | 0.952 m | ≤0.60 m | Altura capa caliente |
| `cfast_2r_r0_rmse_temp_upper_c` | 66.3°C | ≤60°C | Dos salas, sala fuego |
| `cfast_2r_hall_rmse_temp_upper_c` | 39.8°C | ≤30°C | Dos salas, pasillo |
| `cfast_2r_hall_rmse_o2` | 0.0781 | ≤0.030 | Dos salas, O₂ pasillo |
| `cfast_hvac_rmse_temp_upper_c` | 81.2°C | ≤60°C | HVAC |
| `cfast_fastgrowth_rmse_temp_upper_c` | 162°C | ≤60°C | Fast growth |
| `cfast_twofloor_r0_rmse_temp_upper_c` | 157°C | ≤60°C | Dos plantas, sala fuego |
| `cfast_multifuel_rmse_temp_upper_c` | 184°C | ≤80°C | Multi-combustible |

---

### 5. Escenarios complejos (5 checks)

**Gap estructural**: mezcla uniforme de O₂ en SF hace que el fuego se extinga antes de lo que haría con two-zone; HVAC alimenta la zona baja con aire fresco en CFAST pero SF lo mezcla.

| Check | SF actual | CFAST expected | Nota |
|-------|-----------|----------------|------|
| `cfast_2r_r0_t450_temp_upper_c` | 144.4°C | 58.9°C ±80°C | Fire over-burns por room-avg O₂ |
| `cfast_2r_hall_t240_o2` | 0.2001 | 0.1113 ±0.03 | O₂ pasillo no depleta via hot-gas |
| `cfast_2r_hall_t360_o2` | 0.1715 | 0.0565 ±0.03 | O₂ pasillo no depleta via hot-gas |
| `cfast_hvac_t450_temp_upper_c` | 52.6°C | 174.8°C ±80°C | HVAC O₂ feed sostiene fuego en CFAST |
| `cfast_twofloor_r8_t300_temp_upper_c` | 20.0°C | 78.7°C ±30°C | SF extingue a t≈230s antes de propagación |

---

### 6. Phase 1.5: Paredes y flashover (4 checks)

**Gap**: conducción 1D en paredes no implementada (solo `wall_absorption_rate` lineal). HRR post-flashover timing desfasado.

| Check | SF actual | CFAST expected | Nota |
|-------|-----------|----------------|------|
| `cfast_t420_wall_T_mid_c` | 20.0°C | 73.2°C ±40°C | Nodo medio pared vs t=420s |
| `cfast_t510_wall_T_mid_c` | 20.0°C | 90.7°C ±40°C | Nodo medio pared vs t=510s |
| `cfast_fo_peak_temp_upper_c` | 355.3°C | ≥400°C | Pico post-flashover |
| `cfast_fo_peak_temp_timing` | 200s | 390s ±90s | Timing del pico post-flashover |

---

### 7. Calibración puntual (4 checks)

| Check | SF actual | CFAST/ref expected | Nota |
|-------|-----------|-------------------|------|
| `cfast_t120_temp_upper_c` | 178.0°C | 121.9°C ±55°C | Growth-phase calibration |
| `cfast_t240_hrr_ventilation_limited` | 528.9 kW | 276 kW (two-zone) | HRR no se limita por O₂ upper-zone |
| `ghanekar_flashover_0_9m_known_gap` | — | 186s ±30s | Criterio flashover a 0.9m no reproducido |
| `ghanekar_far_hall_co_known_gap` | 149.6s | 204s ±45s | Química CO/HCN no calibrada a Ghanekar |
| `g3_gie_ppv_post_knockdown_time_room_1_smoke_below_0_1kg_post_vent_s` | 369.9s | 361s ±3s | Timing smoke decay post-PPV |

---

### 8. Stage-B pending (10 checks — sin datos aún)

Checks planificados para fases futuras. `actual` y `expected` están vacíos; se activarán cuando se implementen las fases correspondientes.

| Check | Fase prevista | Descripción |
|-------|--------------|-------------|
| `cfast_slow_growth_sealed_pending` | Stage-B | Fuego lento (α=0.003 kW/s²) — depleción O₂ y CO en 30 min |
| `cfast_pool_fire_open_pending` | Stage-B | Pool fire heptano 80 kW — HRR estable, CO yield |
| `cfast_corridor_chain_pending` | Stage-B | 3 salas corredor — timing humo y O₂ en R2 |
| `cfast_bedroom_closed_door_pending` | Stage-B | Dormitorio sellado — FED a 0.9m vs tiempo |
| `cfast_suppression_water_pending` | Stage-B | Supresión con agua — curva knockdown HRR |
| `cfast_overpressure_sealed_pending` | Stage-B (Phase 2) | Presión termódinámica sala sellada 100-1000 Pa |
| `cfast_co2_stratification_pending` | Stage-B (Phase 2) | CO₂ mol% zona superior — requiere two-zone |
| `cfast_hall_upper_o2_doorway_pending` | Stage-B (Phase 2) | O₂ zona superior pasillo via doorway hot-gas |
| `cfast_hrr_ventilation_limited_f2_pending` | Stage-B (Phase 2) | HRR limitado por O₂ upper-layer |
| `cfast_hvac_two_zone_feed_pending` | Stage-B (Phase 2) | HVAC O₂ feed zona baja — fuego sobrevive en CFAST |

---

## Prioridad de cierre

| Prioridad | Categoría | Checks | Esfuerzo | Impacto |
|-----------|-----------|--------|----------|---------|
| 1 | O₂ zona inferior | 10 | Medio | Alto (Phase 2E en progreso) |
| 2 | CO₂ upper layer | 5 | Medio | Alto (Phase 2E) |
| 3 | Escenarios complejos (O₂/HVAC) | 3 | Bajo | Medio (deriva de Phase 2E) |
| 4 | Wall heat loss / paredes | 4 | Alto | Medio (conducción 1D) |
| 5 | RMSE temperatura | 8 | Bajo | Bajo (mejoran con 1+4) |
| 6 | Presión | 18 | Muy alto | Bajo (gap estructural profundo) |
| 7 | CO lower zone reporting | 1 | N/A | Diferencia arquitectural — cerrar con Phase 2E transporte two-zone |
| 8 | Stage-B pending | 10 | N/A | N/A (requieren implementación previa) |
| 9 | Calibración puntual | 5 | Bajo | Bajo (ad-hoc) |

---

## Nota: CO lower zone reporting gap (cfast_2r_hall_t360_co_lower_ppm)

**Introducido**: 24 mayo 2026, guard `upper_gas_kg < 0.1` en `compute_co_lower_ppm`.  
**Tipo**: diferencia arquitectural — **NO es regresión required** (check `required=False`).  

| Check | SF actual (ppm) | CFAST expected (ppm) | Tolerancia | Escenario |
|-------|-----------------|---------------------|------------|-----------|
| `cfast_2r_hall_t360_co_lower_ppm` | 125.0 | 0.0 | ±100 | Dos salas, pasillo t=360s |

**Causa**: en SF, el pasillo no establece capa caliente (`upper_gas_kg < 0.1`) pero tiene CO residual de transporte (`co_kg > 0`). El guard devuelve `compute_co_ppm = 125 ppm` (CO uniformemente distribuido). CFAST coloca el CO en zona superior estratificada → lower zone = 0.  
**Comportamiento anterior**: el factor `strat = 0` (capa caliente descendida) suprimía el valor → 0 ppm, coincidiendo con CFAST por razón equivocada.  
**Cièrre correcto**: Phase 2E transporte two-zone completo (CO split proporcional al volumen de zona en destino) + rebaseline explícito de `cfast_2r_hall_*`. **No tocar antes.**

---

## Backlog Phase 2E arquitectónica

> ⚠️ **Aviso de rebaseline**: cualquier cambio a `_transfer_hot_gas_contaminants`, `compute_fed_delta_for_height` o `step_fed` que altere `co_upper_kg` en salas destino **requiere re-ejecutar la suite completa y re-verificar g4 required checks** antes de commitear:
> - `time_room_1_fed_above_0_1_s`: expected=197.75, tol=10.0
> - `time_room_1_co_upper_above_1200_s`: expected=87.33, tol=5.0  
> - `room_1_peak_co_upper_ppm`: min=2000.0

| Opción | Descripción | Estado | Riesgo |
|--------|-------------|--------|--------|
| **B-transport** | Dividir CO en `_transfer_hot_gas_contaminants` por fracción `upper_gas/total_gas` destino | Pendiente | ALTO — modifica `co_upper_kg` → afecta g4 FED required |
| **C-FED-cond** | `compute_co_lower_ppm` en FED solo cuando `hot_h < 0.5 * height_m` | Pendiente | MEDIO — no cambia transporte pero afecta step_fed |
| **D-two-zone doorway** | Flujo two-zone en vano: aire fresco entra por mitad inferior | Pendiente | BAJO en CO, ALTO en O₂ lower |

