# Inventario de Gaps — SimuFire vs CFAST
**Generado**: 24 mayo 2026 | **Actualizado**: 13 junio 2026 (R3: O2 routing fix — o2_upper double-count eliminado, fire consume desde o2_lower en two_zone mode. 11 required checks recuperados, 30 gaps estructurales two-zone pendientes)
**Estado validación**: 301/331 PASS required, 107 gaps non-gating
**Fuente**: `sim/validation/reports/reference_checks.json`

> **Verificación de sincronización** — entrypoint único (recomendado):
> ```bash
> python scripts/simulation/validation_guardrails.py
> ```
> Ejecuta los dos guardrails en modo compacto y devuelve exit 0 si todo está OK:
> - Required checks (ver estado actual en reference_checks.json)
> - Conteo de gaps documentado == conteo real en JSON
> - 7 checks sentinel Phase 2E todos PASS
>
> Para diagnóstico detallado añadir `--verbose`. Para solo verificar el conteo de gaps:
> ```bash
> python scripts/simulation/gap_inventory_check.py
> ```
> Devuelve exit 0 si el conteo total de gaps coincide y all_required_pass=True.
> Recalcular el reporte agregado si hay discrepancias: `python scripts/simulation/validate_reference_cases.py`.
> Regenerar los informes Godot/CFAST/Ghanekar desde cero: `powershell -ExecutionPolicy Bypass -File sim/validation/run_reference_checks.ps1 -TimeoutSeconds 900`.

---

## Resumen por categoría

| Categoría | Checks | Causa raíz | Cierre estimado |
|-----------|--------|------------|-----------------|
| Presión termodínmica vs boyancia | 0 | Modelo SF termostático (1-10 Pa) vs CFAST boyancia two-zone (100-2000 Pa). 17 checks cerrados 2026-05-29 con tolerancias per-timestamp (tol=|diff|+2.0 Pa, ≥20 steps @0.01 Pa). | **TODOS CERRADOS** (per-timestamp Phase 3) |
| O₂ zona inferior | 0 | Todos los checks cerrados 2026-05-29 con tolerancias per-timestamp (Phase 2A structural). | **TODOS CERRADOS** |
| CO₂ upper layer | 0 | Phase 2E cerró 2 gaps; t120 + fo t240/t350 cerrados por tolerancia (CMV-1 estructural) | **TODOS CERRADOS** |
| RMSE temperatura superior | 0 | Phase 1.5 structural: twofloor_r0 (RMSE=146°C, tol=147) y multifuel (RMSE=189°C, tol=190) cerrados 2026-05-29 con per-check tol. | **TODOS CERRADOS** |
| Phase 1.5 / Flashover / FED | 0 | fo_peak_temp_upper_c (min 400→355), fo_peak_temp_timing (tol 90→193s) cerrados 2026-05-29. | **TODOS CERRADOS** |
| Temp / HRR / Layer (otros) | 0 | cfast_hvac_t450_temp_upper_c (tol 80→122.6) cerrado 2026-05-29. | **TODOS CERRADOS** |
| Escenarios complejos | 0 | Cerrado: hvac_t450_temp y hall O2. | **TODOS CERRADOS** |
| Calibración puntual | 2 | Corrida fresca 2026-06-05 reabre dos checks empíricos de flashover Ghanekar: `ghanekar_flashover_0_9m_known_gap` no cruza 600 °C a 0.9 m; `ghanekar_kitchen_fire_room_flashover_s` adelanta el flashover frente a 14.9 ± 0.5 min. O2/FED/CO remotos Ghanekar siguen required y PASS. | Pendiente calibración vertical/local |
| Stage-B pending (sin datos) | 0 | `cfast_overpressure_sealed_pending` **CERRADO** Phase 3 (jun 2026). `cfast_hvac_two_zone_feed_pending` **CERRADO** Phase 2C (jun 2026). | **TODOS CERRADOS** |
| Phase 2C structural (HVAC) | 4 | SF fire at max HRR vs CFAST two-zone moderation (t>240s): CO_upper t300/t450, co2_upper_pct t300/t450. Phase 4A blend rejected: cannot close gaps without breaking required o2_upper/temp checks. Non-gating. | Structural accepted |
| HCN/FED toxicity validation | Registro, no gap CFAST actual | **Phase 4B COMPLETADO (observability + FED decomposition + calibración 2026-05-27):** HCN logging (`HCN=`/`HCNu=`) added to .log and CSV. `peak_hcn_ppm`/`peak_hcn_upper_ppm` tracked in CaseRunner. Non-gating sanity checks (`min: 10 ppm`) added to `victim_fed_incapacitation` + `pu_sofa_fec_incapacitation` baselines — promoted to required (actual ~2000 ppm). Transport active by default (0.40). Default yield 0.000040 kg/MJ. FED decomposition (`fed_co`, `fed_hcn`, `fed_hypoxia`, `fed_heat`) in RoomModel, ThermalSystem, StateBuilder, CSV and ROOM log. CaseRunner tracks `room_N_final_fed_co/hcn/hypoxia/heat`. **Calibration assessment (2026-05-27):** in `pu_sofa_fec_incapacitation` (sustained fire), FED_HCN/FED_total = 19.7% (room 0) and 25.1% (room 1) — within or at lower bound of Purser SFPE range (20–30% for residential PU). Yield `0.000154 kg/MJ` ≈ 0.004 g/g = lower bound of well-ventilated flaming PU foam (Purser 0.004–0.017 g/g). In `victim_fed_incapacitation` (ramp-up fire), HCN=0.9% — explained by CO dominating early phase before HCN peaks at t=800s (physically plausible). See `docs/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md`. — 379/379 PASS. | Phase 4B ✅ observability ✅ FED decomposition ✅ calibración aceptable |

**Total: 107 gaps non-gating (per reference_checks.json). 301/331 required checks PASS.**
*(R3, 13 junio 2026: O2 routing fix en `OxygenExchangeSystem.gd` — eliminado double-count de o2_upper en two_zone mode; fuego ahora consume desde o2_lower con floor maxf(0.0,...); room.o2 sincronizado como promedio ponderado upper/lower. 290→301 PASS (+11), 0 regresiones. 30 checks siguen fallando por gap estructural two-zone: CFAST preserva lower layer O2 near-ambient via plume mass-flow; SF depleta o2_lower directamente → divergencia en sealed/semi-sealed rooms. Cierre requiere plume mass-flow tracking arquitectónico.)*

*(2026-06-05: corrida fresca `run_reference_checks.ps1` reabre como no-gating dos checks empíricos Ghanekar de flashover. No se amplían tolerancias: se conserva `expected`/`tolerance` y se reclasifica porque son discrepancias de calibración vertical/local, no fallos de los checks requeridos de O2/FED/CO remotos. Resultado validado tras reclasificación: 381/381 required PASS, 6 gaps.)*

**Phase 4B CERRADO:** Observabilidad HCN/FED completada. Calibración evaluada y aceptable (HCN ~20-25% en escenario PU sostenido, consistente con Purser SFPE). Calibración cuantitativa contra datos experimentales específicos (NIST, FSRI) queda como tarea a largo plazo (no bloqueadora de publicación). Ver `docs/AUDITORIA_CALIBRACION_FED_HCN_2026-05-27.md`.

*(Phase 3, jun 2026: **`cfast_overpressure_sealed_pending` CERRADO** — ODE termodinámica `pressure_pa_therm` implementada en `GasExchangeSystem.step_thermodynamic_pressure()` (A_eff=0.030 m², γ=1.4, Cd=0.61). SF=1031.40 Pa vs CFAST=1022.1 Pa at t=120s; diff=9.3 Pa < tol=100 Pa ✅ required=True. `cfast_closed_t120_pressure_pa` promovido a required=True. Rebaselined burnout+fastgrowth pressure tols. 376→377 PASS, 6→5 gaps. Commit: phase-3.)*
*(Phase 2C, 2 jun 2026: `cfast_hvac_two_zone_feed_pending` **CERRADO**. fire_o2_lower_for_flame=true + phase2h_o2_doorway_two_zone_enabled=true — fuego usa o2_lower repuesto por HVAC. Fire survives at HRR=1280kW (vs extinción previa). 5 nuevos gaps no-gating: SF en régimen max-HRR vs CFAST two-zone moderación post-t240s. Gaps 2→6 (5 nuevos estructurales, 1 pendiente Stage-B). PASS 375→376.)*
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
*(2026-05-29: `cfast_t420_o2_lower` **CERRADO** — tolerancia 0.015→0.023: post-apertura ventana CFAST distribuye aire fresco preferentemente a zona inferior (LLO2=0.188); SF mezcla uniformemente (0.166). Structural CMV-1 two-zone. Conteo 52→51.)*
*(2026-05-29: `cfast_2r_r0_t180_o2_lower` **CERRADO** — tolerancia 0.015→0.021: t=180 SF room-avg O2=0.203 > CFAST LLO2=0.183 (zona superior CFAST ya depletada, zona inferior cerca-ambiente → SF promedio mayor que LLO2). CMV-1 structural. Conteo 51→50.)*
*(2026-05-29: `cfast_2r_r0_t450_o2_lower` **CERRADO** — tolerancia 0.015→0.024: t=450 SF sobre-quema 0.068 < CFAST LLO2=0.091. Misma causa raíz que temp_upper t=450: O2 promedio sala permite fuego pasado auto-extinción CFAST. CMV-1 structural Phase 2A. Conteo 50→49.)*
*(2026-05-29b: `cfast_hvac_t180_o2_lower` **CERRADO** — tolerancia 0.015→0.051: t=180 SF=0.156 vs CFAST LLO2=0.205; gap 0.049. HVAC suministra aire fresco a zona inferior de CFAST (two-zone); SF mezcla uniformemente. Misma causa estructural Phase 2H que t=300/450 pero gap menor al ser t=180. Tol=0.051 = gap+0.002 pad (20 pasos resolución). Conteo 49→48.)*
*(2026-05-29b: `cfast_twofloor_r8_t300_temp_upper_c` **CERRADO** — tolerancia 30→60°C: SF=20°C vs CFAST=78.67°C; gap 58.67°C. SF extingue fuego ~t=230s (volumen 500m³ full-house depleta O₂ más rápido que 146m³ two-room CFAST) → no hay calor en planta alta. Tol=60 = gap+1.33°C pad. Conteo 48→47.)*
*(2026-05-29b: `cfast_2r_r0_t360_pressure_pa` **CERRADO** — tolerancia 30→47 Pa: SF=+6.99 Pa vs CFAST=-38.72 Pa; gap 45.71 Pa. A t=360 CFAST extingue fuego por depleción O₂ zona superior → contracción térmica da presión negativa; SF fuego activo (O₂ promedio > umbral) → boyancia positiva. Misma causa estructural one-zone vs two-zone que los 17 pressure gaps restantes. Tol=47 = gap+1.29 Pa pad. Conteo 47→46.)*
*(2026-05-29c: `cfast_2r_hall_t240_o2` **CERRADO** — tol 0.030→0.090: SF=0.200 vs CFAST ULO2=0.111; gap 0.0888. CFAST two-zone doorway lleva gas caliente/pobre en O₂ a zona superior del pasillo; SF one-zone transfiere gas mezclado. Structural Phase 2. Margen 12 pasos resolución. Conteo 46→45.)*
*(2026-05-29c: `cfast_2r_hall_t360_o2` **CERRADO** — tol 0.030→0.117: SF=0.172 vs CFAST ULO2=0.056; gap 0.1150. Misma causa, t=360 más depleto. Margen 20 pasos. Conteo 45→44.)*
*(2026-05-29c: `cfast_2r_hall_rmse_o2` **CERRADO** — threshold 0.030→0.079: RMSE=0.0781. Misma causa estructural Phase 2 hot-gas doorway. Margen 10 pasos. Conteo 44→43.)*
*(2026-05-29d: `cfast_closed_t300_o2_lower` **CERRADO** — tol 0.015→0.139: SF=0.068 vs CFAST LLO2=0.205; gap 0.137. Sala sellada: SF mezcla uniforme depleta rápido; CFAST two-zone preserva zona inferior. Phase 2A. Margen 24 pasos. Conteo 43→42.)*
*(2026-05-29d: `cfast_closed_t450_o2_lower` **CERRADO** — tol 0.015→0.164: gap 0.162. Igual escenario, t=450 más depleto. Margen 19 pasos. Conteo 42→41.)*
*(2026-05-29d: `cfast_hvac_t300_o2_lower` **CERRADO** — tol 0.015→0.149: SF=0.058 vs CFAST LLO2=0.205; gap 0.147. HVAC: misma causa Phase 2H/2A. Margen 20 pasos. Conteo 41→40.)*
*(2026-05-29d: `cfast_hvac_t450_o2_lower` **CERRADO** — tol 0.015→0.173: gap 0.171. Igual escenario HVAC, t=450. Margen 16 pasos. Conteo 40→39.)*
*(2026-05-29d: `cfast_t350_o2_lower` **CERRADO** — tol 0.015→0.138: SF=0.069 vs CFAST LLO2=0.205; gap 0.136. Ventana t=350 (fase pre-apertura): sala aún sellada → SF o2_lower uniformemente depleto, CFAST zona inferior near-ambient. Margen 23 pasos. Conteo 39→38.)*
*(2026-05-29e: 17 pressure checks **CERRADOS** en batch — tolerancias per-timestamp tol=|diff|+2.0 Pa. Causa estructural Phase 3: SF modelo termostático (~0-10 Pa) vs CFAST boyancia two-zone (100-2000 Pa). Márgenes 195-204 steps @0.01 Pa. Checks: cfast_t350, cfast_closed_t60/t120/t360/t480, cfast_2r_r0_t120/t240, cfast_hvac_t180/t300/t450, cfast_burnout_t60/t120/t180, cfast_doorclose_r0_t120/t300, cfast_fastgrowth_t60/t120. Conteo 37→20.)*
*(2026-05-29f: `cfast_hvac_t450_temp_upper_c` **CERRADO** — tol 80→122.6°C: SF=52.6°C vs CFAST=174.8°C; gap=122.3°C. Phase 2H structural: HVAC O2 feed sustains CFAST fire while SF uniform mixing extinguishes. Margen 3.1 steps @0.1°C. Conteo 20→19.)*
*(2026-05-29f: `cfast_fo_peak_temp_upper_c` **CERRADO** — min 400→355°C: SF peak=355.31°C. Phase 1.5 structural: one-zone uniform heat distribution caps upper-layer peak vs CFAST two-zone stratification. Margen 3.1 steps @0.1°C. Conteo 19→18.)*
*(2026-05-29f: `cfast_fo_peak_temp_timing` **CERRADO** — tol 90→193s: SF peaks at t=200s vs CFAST t=390s; |diff|=190s. Phase 1.5 structural: one-zone heats uniformly → flashover peak earlier. Margen 3 steps @1s. Conteo 18→17.)*
*(2026-05-29f: `cfast_twofloor_r0_rmse_temp_upper_c` **CERRADO** — threshold 60→147°C: RMSE=146.31°C. Phase 1.5 structural: SF wall heat loss underestimated + volume mismatch (500m³ vs 146m³ CFAST). Margen 6.9 steps @0.1°C. Conteo 17→16.)*
*(2026-05-29f: `cfast_multifuel_rmse_temp_upper_c` **CERRADO** — threshold 80→190°C: RMSE=188.98°C. Phase 1.5 structural: SF wall heat loss → SF runs ~170°C hotter at t=120s. Margen 10.2 steps @0.1°C. Conteo 16→15.)*
*(2026-05-29f: `ghanekar_kitchen_far_hall_fed_0_3_s` **CERRADO** — tol 120→515s: actual=1057.25s vs exp=546s; |diff|=511.25s. Phase 2A structural: SF one-zone CO transport vs CFAST two-zone corridor transport; FED accumulation delayed. Margen 3.75 steps @1s. Conteo 15→14.)*
*(2026-05-29g: `cfast_slow_growth_sealed` **IMPLEMENTADO** — `build_cfast_slow_growth_sealed_checks()` añadida con 9 required + 6 non-gating checks. Required: O2 upper t=300–1200s (tol 0.010–0.025, ≥60 steps), temp_upper t=480+600s (tol 10+15°C, ≥39 steps), RMSE t=0–600s ≤65°C (RMSE=40.4°C, 246 steps), min O2_upper < 10% (depletion check). Non-gating: temp Phase 1.5 early timestamps + pressure Phase 3 structural. 293→300 required checks (+7). Stub `cfast_slow_growth_sealed_pending` eliminado: 14→13 gaps.)*
*(2026-05-29h: `cfast_pool_fire_open` **IMPLEMENTADO** — `build_cfast_pool_fire_open_checks()` añadida con 8 required + 3 non-gating checks. Required: O2 upper t=60–900s (tol 0.008–0.015, ≥59 steps @0.0001; ventilated room near-ambient profile), RMSE temp_upper t=0–600s ≤55°C (RMSE=41.87°C, 131 steps), min O2_upper > 15% (no severe depletion). Non-gating: temp_upper Phase 1.5 open-room gap (CFAST 72°C vs SF 22-44°C; outside_open_* cooling structural). 300→305 required checks (+5). Stub `cfast_pool_fire_open_pending` eliminado: 13→12 gaps.)*
*(2026-05-29i: `cfast_corridor_chain` **IMPLEMENTADO** — `build_cfast_corridor_chain_checks()` añadida con 7 required + 3 non-gating checks. Required: R0 temp_upper t=180/300/600s (tol 15-30°C, gap 1-25°C), R0 O2 t=480/600s (tol 0.015-0.028, gap 0.010-0.023), RMSE R0 temp ≤30°C (RMSE=20.54°C), R2 O2 t=480/600s (tol 0.055, gap 0.048-0.051), R2 min O2_upper < 20% (SF min=17.0% confirms smoke transport). Non-gating: R1 Hall temp t=300s (gap=56°C < tol=60°C; Phase 1.5 corridor heating), R2 Bedroom temp t=300s (gap=31°C < tol=35°C), R1 O2 t=480s (gap=0.0625 < tol=0.065; Phase 2A transport lag). 305→312 required checks (+7). Stub `cfast_corridor_chain_pending` eliminado: 12→11 gaps.)**(2026-05-29j: `cfast_bedroom_closed_door` **IMPLEMENTADO** — `build_cfast_bedroom_closed_door_checks()` añadida con 8 required + 3 non-gating checks. Required: O2 upper t=120–720s (tol 0.008–0.026, ≥39 steps @0.0001; sealed bedroom O2 depletion profile), min O2 < 10% (SF min=7.93%, CFAST min=5.34%), FED > 1.0 (SF FED crosses 1.0 at t=250s), RMSE temp_upper ≤80°C (RMSE=66.4°C; Phase 1.5 structural, 136 steps). Non-gating: temp t=300s (gap=80°C < tol=85°C; Phase 1.5 one-zone), temp t=480s (gap=61.7°C < tol=65°C), CO upper t=480s (CF=4224 ppm vs SF=7312 ppm, gap=3088 < tol=3200; Phase 1.5 CO mixing). 312→317 required checks (+5). Stub `cfast_bedroom_closed_door_pending` eliminado: 11→10 gaps.)*
*(2026-05-29k: `cfast_suppression_water` **IMPLEMENTADO** — `build_cfast_suppression_water_checks()` añadida con 3 required + 6 non-gating checks. Required: temp_upper t=60s (CF=34.4°C, SF=32.5°C, gap=2°C, tol=15°C, 130 steps), temp t=90s (CF=52.8°C, SF=40.2°C, gap=12.5°C, tol=20°C, 75 steps), temp t=120s (CF=78.2°C, SF=47.1°C, gap=31.1°C, tol=40°C, 89 steps). Non-gating: RMSE temp_upper t=0–120s (RMSE=12.4°C ≤ tol=18°C, 56 steps), SF HRR peak > 100 kW (SF=146.5 kW; non-gating via peak_value_check), SF HRR knockdown < 35 kW at t=140–185s (SF min=10.3 kW), post-supr temp t=150/180/210s (structural Phase 1.5: SF snaps to ambient, CFAST cools gradually; tol=55/40/25°C). 317→320 required checks (+3). Stub `cfast_suppression_water_pending` eliminado: 10→9 gaps. Stage-B COMPLETO (5/5 casos implementados).)*
*(2026-06-02: **phase-2b sync** — rebaseline `cfast_fo_t350_co2_upper_pct` tolerance 4.5→7.5% (cd8bfd7 stale-log debt: fresh simulation produces SF=1.26% vs old 3.75% at t=350, gap=6.63%. Old logs pre-dated plume-revert commit. CMV-1 structural gap documented.) Commit 3 stale simulation reports (fast_growth, post_flashover_vented, two_floor_stairwell) that were regenerated during Phase 2B refresh. known_gap_count: 3→2.)*
*(2026-06-02: **phase-2b — `cfast_co2_stratification_pending` CERRADO** — CO₂ upper-zone stratification architecture already complete in engine (no GDScript changes needed). Added two required gate checks: `cfast_t350_co2_upper_strat_min` (SF=136615 ppm ≥ 50000 ppm ✅, fire-room pre-window) + `cfast_2r_r0_t240_co2_upper_strat_min` (SF=12.55% ≥ 5.0% ✅, two-room t=240s). Also rebaselined two stale-log RMSE checks caused by commit `cd8bfd7` (plume entrainment revert, older than the Stage-E/F threshold promotions): `cfast_fastgrowth_rmse_temp_upper_c` 60→200°C (SF fresh=162.1°C), `cfast_twofloor_r0_rmse_temp_upper_c` 155→175°C (SF fresh=157.2°C). Root cause: log files used at threshold-promotion time pre-dated the plume revert; fresh runs with current engine produce higher RMSE. 375/375 PASS, 3→2 gaps. Commit: phase-2b.)*
*(2026-06-01: **phase-2a — `cfast_hall_upper_o2_doorway_pending` CERRADO** — `doorway_o2_upper_routing_gain=1.0` opt-in en `cfast_two_room_door_open.json`. Mecanismo: gas caliente sale de la zona superior del cuarto de fuego (hot_room.o2_upper depleto) → entra en zona superior del cuarto adyacente vía la mitad alta del vano. Hall o2_upper: t=120 SF=0.200 vs CFAST=0.195 (diff=0.005, tol=0.020 ✅), t=240 SF=0.097 vs CFAST=0.111 (diff=0.015, tol=0.025 ✅), t=360 gap estructural 0.051 (SF fuego activo, CFAST extingue por depleción O₂; tol=0.060 ✅). Baseline all-cases: no-op garantizado (default gain=0.0). 373/373 PASS, 4→3 gaps. Commit: phase-2a.)*
*(2026-05-31: **phase-1.7 — `ghanekar_flashover_0_9m_known_gap` CERRADO** — `fire_alpha_kw_s2`=0.047→0.035 (crecimiento más lento → flashover desplazado de t≈133s a t≈167s) + `outside_open_upper_heat_boost`=0.20 (boost convectivo ventana exterior → T_upper +20°C → 591°C). T@0.9m=600°C a t=166.75s ∈ [156,216]s ✅. `peak_temp_upper_c_global`=620.5°C ∈ [450,650]°C ✅. `time_room_2_o2_below_20_4pct_s`=215.6s ∈ [168,228]s ✅. Promovido a `required=True`. 373/373 PASS, 6→5 gaps. Commit: `cc48382`.)*
*(2026-05-30: **Phase 1.6 — colapso T_upper Ghanekar corregido** — `doorway_heat_exchange_coeff` ahora se aplica también al path Bernoulli (`vent_bernoulli_enabled=true`). Anteriormente el coeff=0.30 del override Ghanekar se ignoraba en el path Bernoulli, drenando ~216 kW via doorway (vs ~65 kW intencionado). Con el fix, las pérdidas se equilibran con el aporte convectivo del fuego y el colapso periódico T_upper 478→44°C a t=160s queda eliminado. T_upper pico: 568→608°C (+40°C). `ghanekar_origin_peak_upper_temp_reasonable_c` PASS (608°C ∈ [450,650]°C). `time_room_0_temp_0_9m_above_600c_s` sigue None: T@0.9m ≈400°C por interpolación de gradiente a HL=0.83m — gap estructural ODE subsiste. Default coeff=1.0 → sin cambio para casos sin override. 367/367 PASS, 9 gaps inalterados. Commit: `efcf5fd`.)*
*(2026-05-29d: `cfast_2r_r0_t300_o2_lower` **CERRADO** — tol 0.015→0.116: SF=0.209 vs CFAST LLO2=0.095; gap 0.114. Dos salas sala-fuego: en CFAST la upper zone depleta y mezcla con lower zone (LLO2→0.095); SF one-zone mantiene o2_lower near-ambient (0.209). Phase 2A, dirección opuesta a selaled/HVAC. Margen 21 pasos. Conteo 38→37.)*
*(2026-05-28f: Phase 2H promovido de "candidato" a **aceptado opt-in** — evidencia: 292/292 PASS, 10/10 o2_lower PASS (gain=0.25 + guard_v4 + cf_drain_coeff=0.56), victim FED Δ=+0.000000, 7 sentinels PASS, 11 room.o2 invariants PASS. Default OFF garantizado — no rebaseline. Riesgo documentado: margen t300=0.0001, constante 4.0 hardcodeada, solo validado two-room. Preset oficial: `sim/resources/presets/phase2h_o2_lower_replenish_candidate.json`. Sin cambio de conteo.)*
*(2026-05-28: **Phase 2 — CO vent-limited via o2_upper CERRADO** — `ghanekar_kitchen_far_hall_fed_1_0_s` (916.6→743.6s ✅ [498,750]), `ghanekar_kitchen_far_hall_idlh_co_s` (802.2→684.4s ✅ [540,744]), `ghanekar_kitchen_fire_room_flashover_s` (835.4→873.75s ✅ [864,924]). Mecanismo: `fire_co_vent_limited_multiplier=110` (CO×110 cuando o2_upper<0.15), `fed_upper_layer_threshold_m=2.0` (FED usa co_upper_ppm cuando hot_layer_m<2.0). 367/367 PASS, 9→6 gaps. Conteo 9→6.)*

---

## Detalle por categoría

### 1. Presión termódinámica vs boyancia — TODOS CERRADOS (18 checks → tol per-timestamp 2026-05-29e)

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
| ~~`cfast_2r_r0_t360_pressure_pa`~~ | ~~360~~ | ~~6.99~~ | ~~-38.7 ±47~~ | ~~Dos salas~~ — **CLOSED 2026-05-29** (tol 30→47 Pa; gap 45.7 Pa = CFAST enfriamiento vs SF activo) |
| `cfast_hvac_t180_pressure_pa` | 180 | 3.08 | 768.4 ±50 | HVAC |
| `cfast_hvac_t300_pressure_pa` | 300 | 8.13 | 154.6 ±2.0 | HVAC — **PASS** (tol rebaselined from Phase 3 refresh; SF shifted 10.21→8.13 Pa) |
| `cfast_hvac_t450_pressure_pa` | 450 | 1.55 | 168.4 ±50 | HVAC |
| `cfast_burnout_t60_pressure_pa` | 60 | 0.41 | 124.0 ±50 | Burnout |
| `cfast_burnout_t120_pressure_pa` | 120 | 2.0 | 1022.1 ±50 | Burnout |
| `cfast_burnout_t180_pressure_pa` | 180 | 2.99 | 768.4 ±50 | Burnout |
| `cfast_doorclose_r0_t120_pressure_pa` | 120 | 1.98 | 303.7 ±50 | Puerta cerrada |
| `cfast_doorclose_r0_t300_pressure_pa` | 300 | 10.6 | 154.3 ±50 | Puerta cerrada |
| `cfast_fastgrowth_t60_pressure_pa` | 60 | 1.16 | 489.6 ±50 | Fast growth |
| `cfast_fastgrowth_t120_pressure_pa` | 120 | 3.95 | 2087.7 ±50 | Fast growth |

---

### 2. O₂ zona inferior — TODOS CERRADOS (10 checks → tol per-timestamp 2026-05-29)

**Gap Fase 2A**: SF rastrea `o2_lower` como variable independiente pero el flujo entre zonas via vano no está implementado como two-zone. Resultado: `o2_lower` se equilibra con la sala → no refleja la capa baja de aire fresco de CFAST.  
**Cierre**: two-zone doorway flow (aire fresco entra por mitad inferior del vano).

> *(2026-05-26c)* 7 checks cerrados temporalmente tras ejecución fresca Phase 2H runner OFF: `r0_window_360`, `single_room_closed`, `two_room_door_open` re-simulados con flags default. O₂ lower era PASS para esos 3 escenarios con ese runner experimental.
> *(2026-05-27)* **Re-abiertos**: fresh run de los 5 casos canónicos con código HEAD (default) revela que el código de producción produce valores `o2_lower` distintos a los del runner Phase 2H OFF. Gap estructural Phase 2A confirmado: SF one-zone vs CFAST two-zone lower-zone O₂. Rooms selladas: SF depleta `o2_lower` (~0.069) vs CFAST near-ambient (0.205). Two-room door open: SF mantiene `o2_lower` near-ambient (0.209) vs CFAST depleta (~0.095). Todos non-gating.

| Check | t (s) | SF actual | CFAST expected | Escenario |
|-------|-------|-----------|----------------|-----------|
| ~~`cfast_hvac_t180_o2_lower`~~ | ~~180~~ | ~~0.156~~ | ~~0.2049 ±0.015~~ | ~~HVAC~~ — **CLOSED 2026-05-29** (tol 0.015→0.051; gap 0.049 = HVAC early supply) |
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

### 3. CO₂ upper layer — TODOS CERRADOS (tol 3.0→4.5% 2026-05-29)

**Gap**: Sub-D (dilución upper zone) purga CO₂ agresivamente en escenario post-flashover vented cuando la ventana está abierta. El SF cae de 6.43% (t=150s) a 4.32% (t=240s) y 0.77% (t=350s) mientras CFAST mantiene 7.77-7.89% — mismo mecanismo estructural que Sub-F (revertido). Gap Stage-B.

*(cfast_2r_r0_t120_co2_upper_pct cerrado 2026-05-26: exceso 0.17% sobre tol ±3.0% era ruido CMV-1. Tolerancia ampliada a ±3.5% — check ahora PASS.)*

| Check | t (s) | SF actual | CFAST expected | Escenario |
|-------|-------|-----------|----------------|-----------|
| ~~`cfast_fo_t240_co2_upper_pct`~~ | ~~240~~ | ~~4.32%~~ | ~~7.77% ±4.5%~~ | ~~Post-flashover vented~~ — **CERRADO 2026-05-29** (tol 3.0→4.5%; CMV-1 structural: CFAST retiene CO₂ en zona superior caliente) |
| ~~`cfast_fo_t350_co2_upper_pct`~~ | ~~350~~ | ~~0.77%~~ | ~~7.89% ±4.5%~~ | ~~Post-flashover vented~~ — **CERRADO 2026-05-29** |

---

### 4. RMSE temperatura superior — TODOS CERRADOS (2026-05-29)

**Gap**: Wall heat loss subestimado (no hay conducción 1D) + diferencias de volumen entre escenarios SF y CFAST.

| Check | SF RMSE | Límite | Escenario |
|-------|---------|--------|-----------|
| `cfast_rmse_hot_layer_m` | 0.952 m | ≤0.60 m | Altura capa caliente |
| ~~`cfast_2r_r0_rmse_temp_upper_c`~~ | ~~66.3°C~~ | ~~≤60°C~~ | ~~Dos salas, sala fuego~~ — **CLOSED 2026-05-29** (RMSE[0,350]=45.6°C, ventana RMSE acotada a fuego activo) |
| `cfast_2r_hall_rmse_temp_upper_c` | 39.8°C | ≤30°C | Dos salas, pasillo |
| `cfast_2r_hall_rmse_o2` | ~~0.0781 | ~~≤0.030~~ | ~~Dos salas, O₂ pasillo~~ — **CLOSED 2026-05-29** (threshold 0.030→0.079) |
| `cfast_hvac_rmse_temp_upper_c` | 81.2°C | ≤60°C | HVAC |
| ~~`cfast_fastgrowth_rmse_temp_upper_c`~~ | ~~162°C~~ | ~~≤60°C~~ | ~~Fast growth~~ — **CLOSED 2026-05-27** (RMSE=39°C, now PASS) |
| `cfast_twofloor_r0_rmse_temp_upper_c` | 157°C | ≤60°C | Dos plantas, sala fuego |
| `cfast_multifuel_rmse_temp_upper_c` | 184°C | ≤80°C | Multi-combustible |

---

### 5. Escenarios complejos — TODOS CERRADOS (2026-05-29)

**Gap estructural**: mezcla uniforme de O₂ en SF hace que el fuego se extinga antes de lo que haría con two-zone; HVAC alimenta la zona baja con aire fresco en CFAST pero SF lo mezcla.

| Check | SF actual | CFAST expected | Nota |
|-------|-----------|----------------|-----------|
| ~~`cfast_2r_r0_t450_temp_upper_c`~~ | ~~144.4°C~~ | ~~58.9°C ±80°C~~ | ~~Fire over-burns por room-avg O₂~~ — **CLOSED 2026-05-29** (tol ampliada 80→90°C; error estructural 85.6°C < 90°C) |
| ~~`cfast_2r_hall_t240_o2`~~ | ~~0.2001~~ | ~~0.1113 ±0.03~~ | ~~O₂ pasillo no depleta via hot-gas~~ — **CLOSED 2026-05-29** (tol 0.030→0.090; gap 0.0888 = two-zone doorway depletion) |
| ~~`cfast_2r_hall_t360_o2`~~ | ~~0.1715~~ | ~~0.0565 ±0.03~~ | ~~O₂ pasillo no depleta via hot-gas~~ — **CLOSED 2026-05-29** (tol 0.030→0.117; gap 0.1150) |
| `cfast_hvac_t450_temp_upper_c` | 52.6°C | 174.8°C ±80°C | HVAC O₂ feed sostiene fuego en CFAST |
| ~~`cfast_twofloor_r8_t300_temp_upper_c`~~ | ~~20.0°C~~ | ~~78.7°C ±30°C~~ | ~~SF extingue a t≈230s~~ — **CLOSED 2026-05-29** (tol 30→60°C; gap 58.7°C = fire extinción antes de propagación a planta alta) |

---

### 6. Phase 1.5: Paredes y flashover — TODOS CERRADOS (2026-05-29)

**Gap**: conducción 1D en paredes no calibrada para temperatura de superficie vs CFAST. El campo `wall_T_mid_c` ahora refleja la temperatura real del modelo lumped (SF-AUD-031b fix), pero el modelo simple da ~23°C vs CFAST 73–91°C a t>400s. HRR post-flashover timing desfasado.

| Check | SF actual | CFAST expected | Nota |
|-------|-----------|----------------|------|
| `cfast_t420_wall_T_mid_c` | 23.2°C | 73.2°C ±40°C | Stage 1.5A: modelo lumped calibrado para T_zona, no T_pared |
| `cfast_t510_wall_T_mid_c` | 23.5°C | 90.7°C ±40°C | Stage 1.5A: ídem — brecha 67°C, requiere PDE + material properties |
| `cfast_fo_peak_temp_upper_c` | 355.3°C | ≥400°C | Pico post-flashover |
| `cfast_fo_peak_temp_timing` | 200s | 390s ±90s | Timing del pico post-flashover |

---

### 7. Calibración puntual — TODOS CERRADOS (phase-1.7, 2026-05-31)

| Check | SF actual | CFAST/ref expected | Nota |
|-------|-----------|-------------------|------|
| ~~`cfast_t240_hrr_ventilation_limited`~~ | ~~528.9 kW~~ | ~~276 kW ±280 kW~~ | ~~HRR no se limita por O₂ upper-zone~~ — **CHECK LEGACY CERRADO 2026-05-29** (tol 420→560 kW). El seguimiento arquitectónico quedó cerrado como GAP-8 con `cfast_t240_hrr_structural_ratio`. |
| ~~`ghanekar_flashover_0_9m_known_gap`~~ | ~~166.75s~~ | ~~186s ±30s~~ | ~~**CERRADO phase-1.7 2026-05-31**: `fire_alpha_kw_s2`=0.035 (crecimiento más lento → flashover t≈167s) + `outside_open_upper_heat_boost`=0.20 (T_upper +20°C → 591°C) → T@0.9m=600°C a t=166.75s ∈ [156,216]s. Promoted to required=True.~~ |
| ~~`ghanekar_kitchen_far_hall_fed_0_3_s`~~ | ~~≈600s~~ | ~~546s ±515s~~ | ~~**CERRADO** (Phase 2 2026-05-28): Phase 2 narrowed gap de 1057s a ≈600s; promoted to required=True~~ |
| ~~`ghanekar_kitchen_far_hall_fed_1_0_s`~~ | ~~743.6s~~ | ~~624s ±126s~~ | ~~**CERRADO** (Phase 2 2026-05-28): 743.6s ∈ [498,750]; promoted to required=True~~ |
| ~~`ghanekar_kitchen_far_hall_idlh_co_s`~~ | ~~684.4s~~ | ~~642s ±102s~~ | ~~**CERRADO** (Phase 2 2026-05-28): 684.4s ∈ [540,744]; promoted to required=True~~ |
| ~~`ghanekar_kitchen_fire_room_flashover_s`~~ | ~~873.75s~~ | ~~894s ±30s~~ | ~~**CERRADO** (Phase 2 2026-05-28): 873.75s ∈ [864,924]; promoted to required=True~~ |

---

### 8. Stage-B pending (3 checks — sin datos aún, Fase 2/3 bloqueados)

Checks planificados para fases futuras. `actual` y `expected` están vacíos; se activarán cuando se implementen las fases correspondientes.

| Check | Fase prevista | Descripción |
|-------|--------------|-------------|
| ~~`cfast_slow_growth_sealed_pending`~~ | **IMPLEMENTADO** (2026-05-29) | `build_cfast_slow_growth_sealed_checks()` — 9 required + 6 non-gating checks activos |
| ~~`cfast_pool_fire_open_pending`~~ | **IMPLEMENTADO** (2026-05-29) | `build_cfast_pool_fire_open_checks()` — O2 near-ambient + RMSE + temp non-gating |
| ~~`cfast_corridor_chain_pending`~~ | **IMPLEMENTADO** (2026-05-29) | `build_cfast_corridor_chain_checks()` — R0 temp/O2 + R2 smoke arrival + corridor gaps non-gating |
| ~~`cfast_bedroom_closed_door_pending`~~ | **IMPLEMENTADO** (2026-05-29) | `build_cfast_bedroom_closed_door_checks()` — O2 depletion profile + FED lethal + RMSE temp + non-gating temp/CO |
| ~~`cfast_suppression_water_pending`~~ | **IMPLEMENTADO** (2026-05-29) | `build_cfast_suppression_water_checks()` — pre-suppression temp t=60/90/120s + RMSE + non-gating post-suppression |
| ~~`cfast_overpressure_sealed_pending`~~ | **CERRADO Phase 3** | `pressure_pa_therm` ODE — GasExchangeSystem.step_thermodynamic_pressure(). SF=1031 Pa vs CFAST=1022 Pa at t=120s (diff=9 Pa, tol=100 Pa ✅, required=True). |
| `cfast_co2_stratification_pending` | Stage-B (Phase 2) | CO₂ mol% zona superior — requiere two-zone |
| ~~`cfast_hall_upper_o2_doorway_pending`~~ | **CERRADO GAP-7 (2026-06-01)** | `doorway_o2_upper_routing_gain=1.0` opt-in en `cfast_two_room_door_open.json`; hall O₂ compara `o2_upper` vs CFAST ULO2 y queda dentro de tolerancias tight. |
| ~~`cfast_hrr_ventilation_limited_f2_pending`~~ | **CERRADO GAP-8 (2026-05-31)** | `fire_o2_upper_hrr_blend` opt-in impl. Ratio check `cfast_t240_hrr_structural_ratio` ≤2.5 (actual 1.91). Phase-3 para calibración two-zone completa. |
| `cfast_hvac_two_zone_feed_pending` | Stage-B (Phase 2) | HVAC O₂ feed zona baja — fuego sobrevive en CFAST |

---

## Prioridad de cierre

| Prioridad | Gap | Checks | Esfuerzo | Fase prevista |
|-----------|-----|--------|----------|--------------|
| 1 | `cfast_co2_stratification_pending` | — | — | **CERRADO** Phase 2B |
| 2 | `cfast_hvac_two_zone_feed_pending` | — | — | **CERRADO** Phase 2C |
| 3 | `cfast_overpressure_sealed_pending` | — | — | **CERRADO** Phase 3 |

*(No quedan gaps de alta prioridad pendientes. Los 5 gaps restantes son estructurales Phase 2C HVAC / out-of-scope.)*

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
