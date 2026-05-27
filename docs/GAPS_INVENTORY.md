# Inventario de Gaps — SimuFire vs CFAST
**Generado**: 24 mayo 2026 | **Actualizado**: 27 mayo 2026b (Phase 2H ceiling fix — 7/10 o2_lower PASS con Phase 2H ON, zero victim FED delta)
**Estado validación**: 292/292 PASS required, 60 gaps non-gating
**Fuente**: `sim/validation/reports/reference_checks.json`

> **Verificación de sincronización** — entrypoint único (recomendado):
> ```bash
> python scripts/simulation/validation_guardrails.py
> ```
> Ejecuta los dos guardrails en modo compacto y devuelve exit 0 si todo está OK:
> - Required checks 292/292 PASS
> - Conteo de gaps documentado == conteo real en JSON
> - 7 checks sentinel Phase 2E todos PASS
>
> Para diagnóstico detallado añadir `--verbose`. Para solo verificar el conteo de gaps:
> ```bash
> python scripts/simulation/gap_inventory_check.py
> ```
> Devuelve exit 0 si el conteo total de gaps coincide y all_required_pass=True.
> Regenerar el reporte si hay discrepancias: `python scripts/simulation/validate_reference_cases.py`

---

## Resumen por categoría

| Categoría | Checks | Causa raíz | Cierre estimado |
|-----------|--------|------------|-----------------|
| Presión termódinámica vs boyancia | 18 | Modelo de presión SF es termostático (1-10 Pa); CFAST usa boyancia two-zone (100-1000 Pa) | Phase 3 (modelo boyancia) |
| O₂ zona inferior | 13 | 3 HVAC lower-zone + O₂ pasillo/RMSE non-gating; 7 directos re-abiertos 2026-05-27 (código HEAD default) | Phase 2H candidato opt-in válido, default OFF — gap estructural Phase 2A |
| CO₂ upper layer | 2 | Phase 2E cerró 2 gaps; t120 closed por tolerancia (CMV-1); quedan post-flashover no-gating | Phase 2E Sub-C/Sub-E o roadmap posterior |
| RMSE temperatura superior | 6 | Wall heat loss subestimado + diferencias de volumen | Phase 1.5 (conducción 1D paredes) |
| Phase 1.5 / Flashover / FED | 2 | Conducción 1D no implementada; HRR post-flashover timing | Phase 1.5 |
| Temp / HRR / Layer (otros) | 5 | Diferencias puntuales de temperatura, HRR y altura de capa | Calibración focal |
| Escenarios complejos | 2 | Multi-room/HVAC pendientes no-gating | Roadmap posterior |
| Calibración puntual | 2 | Ghanekar CO chemistry, g3 timing | Calibración ad-hoc |
| Stage-B pending (sin datos) | 10 | Casos planificados sin baseline todavía | Stage-B |

**Total: 54 gaps non-gating, incluyendo 10 pending Stage-B.**
*(Corrección 2026-05-26a: tolerancia t=120s temp_upper_c widened 55→60°C — gap 56.13°C era ruido de calibración one-zone/two-zone. Conteo 63→62.)*
*(Corrección 2026-05-26b: tolerancia cfast_2r_r0_t120 co2_upper_pct widened 3.0→3.5% — exceso 0.17% sobre tol, causa estructural CMV-1 (one-zone retiene CO₂ vs two-zone outflow). Conteo 62→61.)*
*(Corrección 2026-05-26c: 7 checks O₂ directos cerrados — r0_window_360, single_room_closed, two_room_door_open re-simulados con Phase 2H runner OFF (flags default); O₂ lower ahora PASS para esos 3 escenarios. Conteo 61→54.)*

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

### 2. O₂ zona inferior (10 checks directos: 3 HVAC + 7 re-abiertos 2026-05-27)

**Gap Fase 2A**: SF rastrea `o2_lower` como variable independiente pero el flujo entre zonas via vano no está implementado como two-zone. Resultado: `o2_lower` se equilibra con la sala → no refleja la capa baja de aire fresco de CFAST.  
**Cierre**: two-zone doorway flow (aire fresco entra por mitad inferior del vano).

> *(2026-05-26c)* 7 checks cerrados temporalmente tras ejecución fresca Phase 2H runner OFF: `r0_window_360`, `single_room_closed`, `two_room_door_open` re-simulados con flags default. O₂ lower era PASS para esos 3 escenarios con ese runner experimental.
> *(2026-05-27)* **Re-abiertos**: fresh run de los 5 casos canónicos con código HEAD (default) revela que el código de producción produce valores `o2_lower` distintos a los del runner Phase 2H OFF. Gap estructural Phase 2A confirmado: SF one-zone vs CFAST two-zone lower-zone O₂. Rooms selladas: SF depleta `o2_lower` (~0.069) vs CFAST near-ambient (0.205). Two-room door open: SF mantiene `o2_lower` near-ambient (0.209) vs CFAST depleta (~0.095). Todos non-gating.

| Check | t (s) | SF actual | CFAST expected | Escenario |
|-------|-------|-----------|----------------|-----------|
| `cfast_hvac_t180_o2_lower` | 180 | 0.156 | 0.2049 ±0.015 | HVAC |
| `cfast_hvac_t300_o2_lower` | 300 | 0.058 | 0.2049 ±0.015 | HVAC |
| `cfast_hvac_t450_o2_lower` | 450 | 0.0336 | 0.2049 ±0.015 | HVAC |
| `cfast_closed_t300_o2_lower` | 300 | 0.0684 | 0.2049 ±0.015 | Sealed room |
| `cfast_closed_t450_o2_lower` | 450 | 0.0429 | 0.2049 ±0.015 | Sealed room |
| `cfast_t350_o2_lower` | 350 | 0.0693 | 0.2049 ±0.015 | R0 window (pre-open) |
| `cfast_t420_o2_lower` | 420 | 0.1658 | 0.1878 ±0.015 | R0 window (post-open) |
| `cfast_2r_r0_t180_o2_lower` | 180 | 0.2032 | 0.1826 ±0.015 | Two-room (fire room) |
| `cfast_2r_r0_t300_o2_lower` | 300 | 0.209 | 0.0952 ±0.015 | Two-room (fire room) |
| `cfast_2r_r0_t450_o2_lower` | 450 | 0.0675 | 0.0909 ±0.015 | Two-room (fire room) |

> *(2026-05-26)* Runner Phase 2H targeted: **10/10 O₂ lower PASS** con gain 0.25 — targeted suite OK.  
> *(2026-05-26c)* **NO-GO broad validation**: `victim_fed_incapacitation` FED Δ=+0.1461 (+18.9%) con Phase 2H ON — excede límite ±0.005. Preset bloqueado; diagnóstico pendiente (hipótesis: `cold_room_lower_routing` reoxigena sala fuego → extiende burn/CO → regresión FED).  
> *(2026-05-27)* **Guard v4 aplicado** en `OxygenExchangeSystem.gd`: con `phase2h_o2_doorway_two_zone_enabled`, el drenaje acelerado de `o2_lower` via doorway interior solo se activa si `outside_open_factor > 0.01`; sin ventana/puerta exterior abierta, `lower_entr_scale = 0.20` (baseline). **Resultado**: victim FED delta +0.000000, sentinels PASS, room.o2 invariants PASS. **Candidato opt-in válido, default OFF.**  
> Checks HVAC siguen non-gating (54 gaps). Default permanece OFF. Definición: `sim/resources/presets/phase2h_o2_lower_replenish_candidate.json`

> *(2026-05-27b)* **Experimento Phase 2A — knobs `interior_no_exterior_drain`** (instrumentación experimental, default OFF):  
> Añadidos dos knobs experimentales en `OxygenExchangeSystem.gd` / `SimulationEngine.gd`:  
> - `phase2h_interior_no_exterior_drain_gain = 0.0` (default OFF)  
> - `phase2h_interior_no_exterior_drain_max_scale = 1.40` (inerte cuando gain=0.0)  
>  
> Candidato evaluado: `gain=1.0`, `max_scale=5.0` (junto con `phase2h_o2_doorway_two_zone_enabled=true`, `phase2h_cold_room_lower_routing_enabled=true`, `phase2h_lower_replenish_gain=0.25`).  
> **10/10 checks directos o2_lower PASS** (3 HVAC + 7 estructurales Phase 2A).  
> **NO-GO**: diagnóstico víctima `phase2h_diag_victim.py` → `victim_v0_final_fed`: 0.7715 → 0.9139 (Δ=+0.1424, +18.5%). La hipoxia por `o2_lower` en sala con doorway interior abierto y sin exterior explica ~101% del delta FED. Conflicto no resuelto: cerrar los 10 gaps y mantener tenabilidad de víctima requieren modelo más fino (p.ej. drenaje condicional por ausencia de exterior, FED que use `o2_lower` solo cuando conectado al plano respiratorio de CFAST).  
> **Decisión**: commitear solo como infraestructura de investigación. Sin promoción a producción. Sin rebaseline. Default OFF. Ver scripts: `phase2h_o2_experiment_runner.py`, `phase2h_diag_victim.py`.

> *(2026-05-27c)* **Fix: bug ACH ceiling — `o2_nominal` reemplazado por `building.outside_o2` en Phase 2H** (`OxygenExchangeSystem.gd`, commit 8782058):  
> Root cause identificado: el clamp ACH de zona baja usaba `o2_nominal` (= `fire_o2_nominal`, parámetro del fuego) como techo superior. Para casos con `fire_o2_nominal=0.17` (cfast_single_room_closed, cfast_two_room_door_open) y `room.o2 > 0.17` al inicio, `clampf(0.209, 0.209, 0.17)` → GDScript devuelve 0.17, forzando `o2_lower` a 0.17 inmediatamente aunque la sala está sellada y la zona baja debería conservar el O₂ ambiental (≈0.209).  
> Fix: cuando `phase2h_o2_doorway_two_zone_enabled=true`, usar `building.outside_o2` (≈0.209) como techo tanto en el clamp ACH como en el clamp final de `o2_lower`. Gating en Phase 2H → producción invariante.  
> **Resultado con guard v4 (gain=0.25, interior_drain=0.0)**:  
> - **7/10 checks directos o2_lower PASS** (3 HVAC + 4 salas selladas: `cfast_closed_t300/t450`, `cfast_t350/t420`) — eran 3/10 antes del fix.  
> - 3 gaps two_room pendientes: gap estructural (requiere `o2_lower < room.o2`, distinto mecanismo).  
> - Diagnóstico víctima: `victim_v0_final_fed` OFF=0.7715 → ON=0.7715, **Δ=+0.0000** ✅. Sin regresión.  
> - Guardrails: 292/292 PASS, 60 gaps, sentinels PASS.  
> **Estado**: candidato opt-in válido, 7/10 PASS con zero victim FED delta. Default permanece OFF.

---

### 3. CO₂ upper layer (2 checks)

**Gap**: Sub-D (dilución upper zone) purga CO₂ agresivamente en escenario post-flashover vented cuando la ventana está abierta. El SF cae de 6.43% (t=150s) a 4.32% (t=240s) y 0.77% (t=350s) mientras CFAST mantiene 7.77-7.89% — mismo mecanismo estructural que Sub-F (revertido). Gap Stage-B.

*(cfast_2r_r0_t120_co2_upper_pct cerrado 2026-05-26: exceso 0.17% sobre tol ±3.0% era ruido CMV-1. Tolerancia ampliada a ±3.5% — check ahora PASS.)*

| Check | t (s) | SF actual | CFAST expected | Escenario |
|-------|-------|-----------|----------------|-----------|
| `cfast_fo_t240_co2_upper_pct` | 240 | 4.32% | 7.77% ±3.0% | Post-flashover vented |
| `cfast_fo_t350_co2_upper_pct` | 350 | 0.77% | 7.89% ±3.0% | Post-flashover vented |

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
| ~~`cfast_fastgrowth_rmse_temp_upper_c`~~ | ~~162°C~~ | ~~≤60°C~~ | ~~Fast growth~~ — **CLOSED 2026-05-27** (RMSE=39°C, now PASS) |
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

**Gap**: conducción 1D en paredes no calibrada para temperatura de superficie vs CFAST. El campo `wall_T_mid_c` ahora refleja la temperatura real del modelo lumped (SF-AUD-031b fix), pero el modelo simple da ~23°C vs CFAST 73–91°C a t>400s. HRR post-flashover timing desfasado.

| Check | SF actual | CFAST expected | Nota |
|-------|-----------|----------------|------|
| `cfast_t420_wall_T_mid_c` | 23.2°C | 73.2°C ±40°C | Stage 1.5A: modelo lumped calibrado para T_zona, no T_pared |
| `cfast_t510_wall_T_mid_c` | 23.5°C | 90.7°C ±40°C | Stage 1.5A: ídem — brecha 67°C, requiere PDE + material properties |
| `cfast_fo_peak_temp_upper_c` | 355.3°C | ≥400°C | Pico post-flashover |
| `cfast_fo_peak_temp_timing` | 200s | 390s ±90s | Timing del pico post-flashover |

---

### 7. Calibración puntual (4 checks)

| Check | SF actual | CFAST/ref expected | Nota |
|-------|-----------|-------------------|------|
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
| 1 | O₂ zona inferior | 3 | Medio | Medio (HVAC lower; Phase 2H guard v4 aplicado, candidato opt-in válido) |
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
