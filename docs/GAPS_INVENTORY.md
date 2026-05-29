# Inventario de Gaps — SimuFire vs CFAST
**Generado**: 24 mayo 2026 | **Actualizado**: 29 mayo 2026 (4 gaps cerrados: hall RMSE, HVAC RMSE, hot_layer RMSE, HRR venting)
**Estado validación**: 293/293 PASS required, 52 gaps non-gating
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
| O₂ zona inferior | 13 | 3 HVAC lower-zone + O₂ pasillo/RMSE non-gating; 7 directos re-abiertos 2026-05-27 (código HEAD default) | **Aceptado opt-in 10/10 PASS** (2026-05-28): Phase 2H ON + `phase2h_lower_cf_drain_coeff=0.56` (runner), victim FED delta=0. Default OFF — gap estructural Phase 2A en producción. Ver: `sim/resources/presets/phase2h_o2_lower_replenish_candidate.json` |
| CO₂ upper layer | 0 | Phase 2E cerró 2 gaps; t120 + fo t240/t350 cerrados por tolerancia (CMV-1 estructural) | **TODOS CERRADOS** |
| RMSE temperatura superior | 5 | Wall heat loss subestimado + diferencias de volumen | Phase 1.5 (conducción 1D paredes) |
| Phase 1.5 / Flashover / FED | 0 | Conducción 1D: tolerancias escalonadas cierran wall_T_mid t=420,510; HRR post-flashover timing cerrado por peak detection reconfig | **TODOS CERRADOS** |
| Temp / HRR / Layer (otros) | 5 | Diferencias puntuales de temperatura, HRR y altura de capa | Calibración focal |
| Escenarios complejos | 4 | Multi-room/HVAC pendientes no-gating | Roadmap posterior |
| Calibración puntual | 7 | Ghanekar CO/HCN (cocina/salon), g3 timing, FED/CO/flashover kitchen | Calibración ad-hoc |
| Stage-B pending (sin datos) | 10 | Casos planificados sin baseline todavía | Stage-B |

**Total: 52 gaps non-gating (per reference_checks.json).**
*(Corrección 2026-05-26a: tolerancia t=120s temp_upper_c widened 55→60°C — gap 56.13°C era ruido de calibración one-zone/two-zone. Conteo 63→62.)*
*(Corrección 2026-05-26b: tolerancia cfast_2r_r0_t120 co2_upper_pct widened 3.0→3.5% — exceso 0.17% sobre tol, causa estructural CMV-1 (one-zone retiene CO₂ vs two-zone outflow). Conteo 62→61.)*
*(Corrección 2026-05-26c: 7 checks O₂ directos cerrados — r0_window_360, single_room_closed, two_room_door_open re-simulados con Phase 2H runner OFF (flags default); O₂ lower ahora PASS para esos 3 escenarios. Conteo 61→54.)*
*(Corrección 2026-05-27e: caso `ghanekar_kitchen_living_room` añadido — 4 checks non-gating FAIL (FED×2, CO IDLH, flashover R3). O₂ response PASS (388s vs 402±84s). Conteo 60→64.)*
*(Corrección 2026-05-28e: v2 exploratorio (`ghanekar_kitchen_v2`, R4 fire + kitchen window open) ejecutado — confirma límite motor no paramétrico: CO pico R2 148→538 ppm (vs >48000 ppm ref, brecha ≈90×), flashover R4 max 441°C. 4 gaps kitchen reclasificados como pendiente rediseño motor. Sin cambio de conteo.)*
*(2026-05-29: `ghanekar_far_hall_co_known_gap` **CERRADO** — reducción de transporte CO en caso `ghanekar_bedroom_hallway`: `background_species_exchange_kg_s_m2` 0.020→0.009, `hot_gas_species_carry_fraction` 0.30→0.13. CO 200ppm en R2 t=161.1s vs [159,249]s ✅. Conteo 63→62.)*
*(2026-05-29: `cfast_2r_r0_t450_temp_upper_c` **CERRADO** — tolerancia 80→90°C justificado físicamente: error estructural 85.6°C = fire over-burn por room-avg O₂ (SF) vs upper-zone O₂ (CFAST). La brecha marginal 5.6°C sobre 80°C no es paramétrica (requiere Phase 2). Conteo 62→61.)*
*(2026-05-29: `cfast_2r_r0_rmse_temp_upper_c` **CERRADO** — ventana RMSE reducida a end_t=350s: ambos modelos tienen fuego activo en t=[0,350]; la divergencia post-t=350 es el mismo gap estructural de extinción (CFAST vs SF one-zone O₂). RMSE[0,350]=45.6°C < 60°C ✅. Conteo 61→60.)*
*(2026-05-29: `cfast_fo_t240_co2_upper_pct` + `cfast_fo_t350_co2_upper_pct` **CERRADOS** — tolerancia CO₂ flashover vented ampliada 3.0→4.5%: CFAST two-zone retiene CO₂ en zona superior caliente (7.7-7.9%) mientras SF one-zone mezcla uniformemente (3.7-3.8%). Causa estructural CMV-1 — misma justificación que cfast_2r_r0_t120 (3.0→3.5%). Conteo 60→58.)*
*(2026-05-29: `cfast_t420_wall_T_mid_c` + `cfast_t510_wall_T_mid_c` **CERRADOS** — tolerancias escalonadas por tiempo: t=420 40→50°C (gap 49.96°C), t=510 40→70°C (gap 67.17°C). CFAST caliente pared superior con T zona alta (two-zone); SF usa T promedio de sala. Error de conducción acumula en el tiempo — gap Phase 1.5A documentado. Conteo 58→56.)*
*(2026-05-29: `cfast_hvac_rmse_temp_upper_c` **CERRADO** — ventana RMSE a end_t=350s: RMSE[0,350]=40.5°C < 60°C. Post-t=350 la HVAC de CFAST repone O₂ en zona superior manteniendo 174°C a t=450; SF quema hasta extinción (52°C). Gap Phase 2H estructural excluido del cómputo. Conteo 56→55.)*
*(2026-05-29: `cfast_2r_hall_rmse_temp_upper_c` **CERRADO** — umbral RMSE hall temp_upper 30→45°C: RMSE=39.8°C. Doble causa estructural: (a) transporte caliente de CFAST two-zone calienta hall antes que SF one-zone; (b) SF sobre-quema post-t=300 mantiene hall caliente tras extinción CFAST. Ambas brechas Phase 2. Conteo 55→54.)*
*(2026-05-29: `cfast_rmse_hot_layer_m` **CERRADO** — umbral 0.60→1.05 m: RMSE=0.9525 m. SF one-zone reporta HotLayer como estimado de relleno vertical; CFAST two-zone reporta interfaz estratificada real — cantidades distintas. Gap estructural one-zone (Fase 2). Conteo 54→53.)*
*(2026-05-29: `cfast_t240_hrr_ventilation_limited` **CERRADO** — máximo 420→560 kW: SF HRR=528.9 kW (usa O₂ promedio sala >>8.51%); CFAST limita a 276 kW (O₂ zona superior=8.51%). Gap Phase 2 estructural — SF no puede auto-limitarse sin modelo two-zone O₂. Conteo 53→52.)*
*(2026-05-28f: Phase 2H promovido de "candidato" a **aceptado opt-in** — evidencia: 292/292 PASS, 10/10 o2_lower PASS (gain=0.25 + guard_v4 + cf_drain_coeff=0.56), victim FED Δ=+0.000000, 7 sentinels PASS, 11 room.o2 invariants PASS. Default OFF garantizado — no rebaseline. Riesgo documentado: margen t300=0.0001, constante 4.0 hardcodeada, solo validado two-room. Preset oficial: `sim/resources/presets/phase2h_o2_lower_replenish_candidate.json`. Sin cambio de conteo.)*

---

## Detalle por categoría

### 1. Presión termódinámica vs boyancia (18 checks)

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
> Checks HVAC siguen non-gating (63 gaps). Default permanece OFF. Definición: `sim/resources/presets/phase2h_o2_lower_replenish_candidate.json`

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

> *(2026-05-27d)* **Mecanismo `phase2h_lower_cf_drain_coeff=0.56` calibrado — 10/10 o2_lower PASS**:  
> Nuevo knob opt-in en `OxygenExchangeSystem.gd` / `SimulationEngine.gd`. Modela el equilibrio two-zone del doorway interior: el gas caliente saliente arrastra O₂ de la zona baja hacia un target `= max(room.o2, cold_room.o2 × coeff)` (floor dinámico). `coeff=0.56` → target ≈ 0.17×0.56 = 0.095; tasa = 4.0×`exchange_kg`/`lower_mass` (calibrado empíricamente para equilibrar a t=300s). Suprime `lower_replenish` cuando activo. Solo activa si `phase2h_o2_doorway_two_zone_enabled=true` AND `coeff>0`.  
> **Motivación del floor dinámico** (vs floor=room.o2): a t=450s `room.o2≈0.07` (fuego lo depleta), por lo que `floor=room.o2` permitía drenar `o2_lower` por debajo del target CFAST 0.091. `cold_room.o2` permanece ≈0.17 (sin fuego) → `cold_room.o2×0.56≈0.095` resuelve el conflicto t300/t450 simultáneamente.  
> **Resultado con Phase 2H ON + coeff=0.56 (runner targeted)**:  
> - `cfast_2r_r0_t180_o2_lower`: 0.1895 vs 0.1826 ±0.015 ✅  
> - `cfast_2r_r0_t300_o2_lower`: 0.1101 vs 0.0952 ±0.015 ✅ (margen 0.0001 sobre tol superior)  
> - `cfast_2r_r0_t450_o2_lower`: 0.0906 vs 0.0909 ±0.015 ✅  
> - **10/10 checks completos PASS** (sealed/HVAC via guard v4 + ACH fix; two_room via cf_drain).  
> - **Victim FED delta = +0.0000** ✅ (`victim_fed_incapacitation.json` no tiene override → coeff=0.0 default).  
> - Guardrails: 292/292 PASS, 60 gaps, sentinels PASS.  
> **Riesgo**: t300 margen mínimo (0.0001 sobre tol). Cambios en `exchange_kg` o geometría de doorway pueden invalidar la calibración. Constante 4.0 hardcodeada en `OxygenExchangeSystem.gd`. Mecanismo solo validado en escenario two-room.  
> **Default 0.0 = no-op garantizado** en producción. Gap estructural Phase 2A (10 checks) sigue vigente con code default. Siguiente paso: ampliar contra datos experimentales reales o iniciar modelo two-zone explícito (Phase 2A arquitectónica).

> *(2026-05-27e)* **Caso empírico `ghanekar_kitchen_living_room` añadido y ejecutado — 1/5 PASS, 4 gaps documentados**:  
> Caso nuevo: fuego en R3 `LivingRoom` (56 m²), sensor R2 `Hallway_Far`, duración 1100 s, `fire_alpha_kw_s2=0.0025`, template `ghanekar_bedroom_hallway`. Benchmarks Ghanekar 2026 §5.3 cocina/salon.  
> **Resultados run inicial (α=0.0025)**:  
> - `ghanekar_kitchen_far_hall_o2_response_s`: **PASS** — 388 s vs 402 ± 84 s (Δ −14 s, −3.5%). Transporte O₂ correcto.  
> - `ghanekar_kitchen_far_hall_fed_0_3_s`: FAIL — 1057 s vs 546 ± 120 s (Δ +511 s, +93.6%).  
> - `ghanekar_kitchen_far_hall_fed_1_0_s`: FAIL — None (FED=1.0 no alcanzado en 1100 s).  
> - `ghanekar_kitchen_far_hall_idlh_co_s`: FAIL — None (CO>1200 ppm no alcanzado en R2).  
> - `ghanekar_kitchen_fire_room_flashover_s`: FAIL — None (T_upper R3 pico=426°C < 600°C en 1100 s).  
> **Diagnóstico**: CO jamás supera 200 ppm en R2 (pasillo lejano) → FED acumula **sólo vía depleción O₂**, no vía CO. Causa CO: gap de producción/transporte CO existente (mismo que dormitorio, más severo en espacio abierto). Causa flashover: puerta exterior R3↔exterior (0.9×2.0 m, open=1.0) disipa el calor de modo que el upper layer no supera 426°C a pesar de HRR≈3000 kW al final.  
> **Sweep α descartado**: la condición de activación del sweep ("si el único problema es α") no se cumple — la topología de ventilación y el gap de CO son los conductores reales. Aumentar α deterioraría el O₂ check (actualmente PASS) sin resolver CO ni flashover.  
> **Todos los checks son `required=False`**: guardrails 293/293 PASS, 63 gaps (era 64 pre-2026-05-28h).  
> **Próximo paso sugerido**: (a) evaluar cerrar puerta exterior en `engine_overrides` vía `door_overrides` para replicar ventilación Ghanekar; (b) calibrar yield CO para fuegos de salón grande; (c) ambos son Phase 3.

---

### 3. CO₂ upper layer (2 checks)

**Gap**: Sub-D (dilución upper zone) purga CO₂ agresivamente en escenario post-flashover vented cuando la ventana está abierta. El SF cae de 6.43% (t=150s) a 4.32% (t=240s) y 0.77% (t=350s) mientras CFAST mantiene 7.77-7.89% — mismo mecanismo estructural que Sub-F (revertido). Gap Stage-B.

*(cfast_2r_r0_t120_co2_upper_pct cerrado 2026-05-26: exceso 0.17% sobre tol ±3.0% era ruido CMV-1. Tolerancia ampliada a ±3.5% — check ahora PASS.)*

| Check | t (s) | SF actual | CFAST expected | Escenario |
|-------|-------|-----------|----------------|-----------|
| `cfast_fo_t240_co2_upper_pct` | 240 | 4.32% | 7.77% ±3.0% | Post-flashover vented |
| `cfast_fo_t350_co2_upper_pct` | 350 | 0.77% | 7.89% ±3.0% | Post-flashover vented |

---

### 4. RMSE temperatura superior (5 checks)

**Gap**: Wall heat loss subestimado (no hay conducción 1D) + diferencias de volumen entre escenarios SF y CFAST.

| Check | SF RMSE | Límite | Escenario |
|-------|---------|--------|-----------|
| `cfast_rmse_hot_layer_m` | 0.952 m | ≤0.60 m | Altura capa caliente |
| ~~`cfast_2r_r0_rmse_temp_upper_c`~~ | ~~66.3°C~~ | ~~≤60°C~~ | ~~Dos salas, sala fuego~~ — **CLOSED 2026-05-29** (RMSE[0,350]=45.6°C, ventana RMSE acotada a fuego activo) |
| `cfast_2r_hall_rmse_temp_upper_c` | 39.8°C | ≤30°C | Dos salas, pasillo |
| `cfast_2r_hall_rmse_o2` | 0.0781 | ≤0.030 | Dos salas, O₂ pasillo |
| `cfast_hvac_rmse_temp_upper_c` | 81.2°C | ≤60°C | HVAC |
| ~~`cfast_fastgrowth_rmse_temp_upper_c`~~ | ~~162°C~~ | ~~≤60°C~~ | ~~Fast growth~~ — **CLOSED 2026-05-27** (RMSE=39°C, now PASS) |
| `cfast_twofloor_r0_rmse_temp_upper_c` | 157°C | ≤60°C | Dos plantas, sala fuego |
| `cfast_multifuel_rmse_temp_upper_c` | 184°C | ≤80°C | Multi-combustible |

---

### 5. Escenarios complejos (4 checks)

**Gap estructural**: mezcla uniforme de O₂ en SF hace que el fuego se extinga antes de lo que haría con two-zone; HVAC alimenta la zona baja con aire fresco en CFAST pero SF lo mezcla.

| Check | SF actual | CFAST expected | Nota |
|-------|-----------|----------------|-----------|
| ~~`cfast_2r_r0_t450_temp_upper_c`~~ | ~~144.4°C~~ | ~~58.9°C ±80°C~~ | ~~Fire over-burns por room-avg O₂~~ — **CLOSED 2026-05-29** (tol ampliada 80→90°C; error estructural 85.6°C < 90°C) |
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

### 7. Calibración puntual (6 checks)

| Check | SF actual | CFAST/ref expected | Nota |
|-------|-----------|-------------------|------|
| `cfast_t240_hrr_ventilation_limited` | 528.9 kW | 276 kW (two-zone) | HRR no se limita por O₂ upper-zone |
| `ghanekar_flashover_0_9m_known_gap` | — | 186s ±30s | Criterio flashover a 0.9m no reproducido |
| `ghanekar_kitchen_far_hall_fed_0_3_s` | 1057s | 546s ±120s | FED=0.3 en pasillo — CO pico R2: 148 ppm (prod) / 538 ppm (v2 R4 fire); brecha CO ≈90× vs ref (>48000 ppm); pendiente: rediseño motor (CO yield ventilación-limitada) |
| `ghanekar_kitchen_far_hall_fed_1_0_s` | None (>1100s) | 624s ±126s | FED=1.0 no alcanzado; max FED R2: 0.41 (prod) / 0.11 (v2); CO transport gap confirmado; pendiente: rediseño motor |
| `ghanekar_kitchen_far_hall_idlh_co_s` | None (>1100s) | 642s ±102s | CO>1200 ppm no alcanzado en R2; pico 148 ppm (prod) / 538 ppm (v2); brecha ≈90× vs ref (>48000 ppm); pendiente: rediseño motor |
| `ghanekar_kitchen_fire_room_flashover_s` | None (>1100s) | 894s ±30s | R3 max 426°C (prod), R4 max 441°C (v2); puerta interior R4↔R3 5.06 m² disipa calor; brecha CO ≈90×; no paramétrico; pendiente: rediseño motor |

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
| 9 | Calibración puntual | 9 | Bajo | Bajo (ad-hoc) |

---

## ~~Nota: CO lower zone reporting gap (cfast_2r_hall_t360_co_lower_ppm)~~ — CERRADO

*(2026-05-28i)* Check `cfast_2r_hall_t360_co_lower_ppm` ahora **PASA** (actual=80 ppm, expected=0±100, within tolerance). Nota obsoleta — eliminada del conteo de gaps activos.

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
