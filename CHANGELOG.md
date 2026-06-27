# Changelog

All notable changes to SimuFire should be recorded here.

## Unreleased

### Corpus diagnóstico O2E1/O1 — 3 casos nuevos (2026-06-27)

- **Ampliación de corpus O2E1/O1**: tres casos nuevos corridos para cubrir los criterios WARN→FAIL antes de promover O2E1. Sin cambio de física, motor, tolerancias ni baselines. Solo se actualizan los JSON de caso (añadido `csv_log_file_path`, `enable_logging`) y se generan los CSVs.
- **`cfast_slow_growth_sealed` (C2) — PASS completo**: O2E1 y O1 PASS en 1800 s sellado. Confirma que el acumulador `o2_consumed_fire_kg_total` se mantiene dentro de la tolerancia Thornton bajo fuerte depleción de O2 y cap activo. Criterio C2 (larga duración ≥ 600 s) cubierto. Apto para suite permanente.
- **`cfast_two_room_door_open` (C3) — O2E1 PASS, O1 247 WARNs**: O2E1 sin hallazgos — criterio C3 (multi-room con intercambio O2) cubierto para O2E1. Los 247 O1 WARNs exponen un gap estructural: la fórmula O1 no captura completamente el flujo O2 vía `canonical_doorway_exchange_enabled`. Residual típico 0.11-0.12 kg vs. tolerancia 0.003-0.004 kg, en todos los rooms desde t=90 s. Gap documentado — O1 no debe ser gating en multi-room con canonical doorway hasta resolverlo.
- **`v1_backdraft_accumulation` (C1) — FAIL**: A3 (2 FAIL): motor mantiene `FULLY_DEVELOPED` con `o2_upper=0.0009` (0.09%), violando la transición de régimen con `fire_o2_min_for_flame=0.10`. Los 16 O2E1 WARNs son consecuencia directa: HRR acumula ~3425 kW mientras O2 está capeado a cero. `retained_unburned_MJ=0` en todo el CSV — el pool release nunca activa. Criterio C1 (backdraft/pool-release) NO cubierto.
- **Nueva incoherencia A3 identificada**: motor no transiciona régimen cuando O2 baja a 0.09% — el fuego debería estar LATENTE pero permanece FULLY_DEVELOPED. Esta incoherencia es capturada por la regla A3 existente. No se corrige en esta sesión.
- **Estado criterios WARN→FAIL**: C2 ✅ C3 ✅ C4 ✅ (fp_ilv_open_partial_window) — solo C1 pendiente.

### Physics validation — general coherence auditor and D1 CO balance (2026-06-25)

- **General physics coherence auditor** — added `check_physics_coherence.py` and `audit_physics_coherence_suite.py`, integrated into the full reference suite. Current gating rules cover strong thermal inversion (`B1`), FED arithmetic (`C1`), FED monotonicity (`C2`), HRR without fuel (`A2`), regime vs critical upper-layer O2 (`A3`), and per-step CO mass balance (`D1`).
- **Phase 3 pressure regression fixed** — removed the `ThermalSystem` branch that reset `pressure_pa_therm` when the Phase 3A pressure ODE was disabled. `cfast_closed_t120_pressure_pa` is restored and the reference suite is back to **349/354 PASS** with only the 5 accepted `VALID_GAP` failures.
- **CO/CO2/HCN diagnostic instrumentation** — CSV exports now include toxic-gas diagnostic fields needed for balance checks, including CO mass, per-step generated CO/CO2/HCN, carbon clamp/error fields, CO net transport and cumulative CO balance terms.
- **D1 CO balance is FAIL-gating** — D1 verifies per-room, per-step CO conservation using `co_kg`, cumulative generated CO, broad net CO transport and exterior CO removal. It started as WARN, found three untracked CO paths, and was promoted to FAIL after fresh CSVs produced 0 findings.
- **D1 tracking fixes** (`b41fcbd`) — instrumented `GasExchangeSystem._purge_upper_species_to_exterior_direct`, `ThermalSystem._flush_contaminant_deltas`, and `GasExchangeSystem._release_pending_interior_deliveries` so all relevant CO movement is included in the D1 balance.
- **E1 fuel balance uses explicit solid fuel** — E1 now validates `solid_fuel_remaining_MJ` against `fuel_consumed_MJ_total`, avoiding the legacy visible `fuel_remaining_MJ` field whose semantics can include retained/unburned/object state and produce false residuals.
- **S0 smoke global conservation is FAIL-gating** — S0 validates `Σ smoke_kg + smoke_in_transit_kg` against generated minus vented minus deposited smoke. Closure fixed missing ACH and natural-vent purge accounting, exposed delayed interior smoke in transit, and stopped sub-threshold smoke mass from being zeroed. Fresh audit: 11/11 CSVs PASS, 0 findings; 9 fresh-schema CSVs exercise S0/E1 and 2 legacy `p2h_diag_*` CSVs skip gracefully.
- **O1 bulk O2 balance is WARN-clean** — O1 now audits bulk `room.o2` mass using `air_mass_kg`, bulk-only O2 consumption, exterior net exchange, inter-room transport and zone-sync accumulators. It found and fixed stale/incorrect CSV semantics (`o2` must export actual `room.o2`) and post-clamp transport accounting. Current corpus: 11/11 PASS, 0 O1 findings, max residual < 4e-4 kg. O1 remains WARN, not FAIL-gating, until validated on broader long-duration/multi-floor cases.
- **O2E1 Thornton cross-check added and fixed (WARN, commits 90c436a → 88ce7d7)** — added cross-subsystem rule O2E1 comparing CombustionSystem HRR accumulator (`hrr_kj_total`) against OES O2 consumption via Thornton. Initial implementation used `o2_consumed_kg_total_all` which double-counted in standard two-zone mode (bulk + upper both accumulated → 2× Thornton, 1308 false WARNs). Fix: introduced `o2_consumed_fire_kg_total`, a tracking-only primary-path accumulator that captures exactly one Thornton unit per step (bulk when it ran; lower/plume/upper otherwise). O2E1 now uses this column. Corpus re-audit after fix (2026-06-27, 11 CSVs): **11/11 PASS, 0 WARN, 0 FAIL**. 157 unit tests PASS. Guardrails: 349/354 stable. O2E1 remains WARN, not gating.
- **Motor validation checklist** — added `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`, capturing the remaining validation items for HRR/energy, O2, toxic gases, smoke/visibility, FED, temperatures, two-zone behavior, ventilation, pressure, wall radiation and the future CFAST/reference battery.
- **Known toxic-gas caveat** — `co2_upper_ppm` is tracer-derived (`co2_upper * 1e6`), while CO upper ppm is mass-derived. CO/CO2 ratio rules remain blocked until the CO2 upper dual-tracking semantics are resolved.

### FP ILV HUD / Smoke Visibility (visual-only)

- **HUD ILV critical display** (`a6d44c0`) — FP technical HUD now shows `Reg ILC`, `Reg ILV` or `Reg ILV CRIT`, labels gases by layer (`O₂u/O₂l`, `COu`, `CO₂u`, `HCNu`), removes duplicated HRR/visibility from the top FP panel while the technical overlay is visible, and visually dampens FP flames in `ILV_LATENT` or critical upper-layer O₂. No simulation physics changed.
- **FP smoke visibility hardening** (`b59fa33`) — ILV-critical FP view now clamps effective display visibility to a severe default (`smoke_overlay_ilv_severe_visibility_m = 1.6` m), increases overlay opacity, and allows ceiling/opening lights to attenuate almost completely through smoke (`smoke_light_min_transmission = 0.01`). Tests cover `Reg ILV CRIT`, `Vis FP 1.6m`, damped fire light, and near-extinguished ceiling light under ILV smoke.
- **FP eye-height layer consistency** (`d69232c`) — FP technical HUD now selects gas labels/readings by eye height versus `smoke_layer_m`/`smoke_display_layer_m`, instead of mixing upper-layer gases with lower-layer visibility/temperature while crouched. Critical upper-layer O₂ can override the display label to `Reg ILV CRIT`. No simulation physics changed.
- **Overhead smoke visibility tightening** (`696f03f`) — FP smoke display no longer jumps back to clear `Vis FP 29m` merely because the camera is below the smoke plane when the upper layer is optically severe. Crouching still improves visibility, but ceiling smoke/lights remain obscured.
- **ILV layer coherence detector** — added `scripts/simulation/check_ilv_layer_coherence.py` plus unit tests. The check fails on exported CSV rows with significant HRR and critical `o2_upper` while the base regime remains fuel-controlled or `o2_hrr_factor` remains high from lower/global oxygen.
- **Open follow-up:** this is presentation-layer mitigation only. New manual QA logs show a motor/layer-coupling issue: HRR and base regime can remain high/`FUEL_CONTROLLED` with `o2_upper` near zero while `o2_lower` remains fresh. The next milestone is an ILV motor audit covering HRR/regime/O₂/gases/smoke by layer.

### ILV motor — Ruta B: v5_m4_ventilation_throttle reference case (2026-06-23)

- **Caso de referencia M4 `v5_m4_ventilation_throttle`** — nuevo caso headless que verifica que `fire_o2_upper_throttle_enabled: true` SUPRIME el spike HRR zombie en ventilación exterior. Semántica invertida respecto a `v5_ventilation_hrr_spike` (legacy control): el nuevo caso testea supresión (HRR ≤ 600 kW), no ocurrencia del spike.
- **`v5_ventilation_hrr_spike` sin cambios** — conservado como caso legacy/control que expone el bug ILV (spike 3245 kW, `time_hrr_above_1000_post_vent ≈ 164 s`). No se modifica ni se activa M4 en él.
- **Métricas verificadas** (física M4 desde `tmp_v5_m4.csv`): `peak_hrr ≈ 492 kW` (≤ 600 ✓), `min_o2_upper ≈ 6.37%` (≥ 5% ✓), `min_l150 ≈ 1.98 m` (≥ 1.90 ✓), `peak_co_upper ≈ 12386 ppm` (≥ 1000 ✓).
- **Archivos nuevos**: `sim/validation/cases/v5_m4_ventilation_throttle.json`, `sim/validation/baselines/v5_m4_ventilation_throttle.json`, `sim/validation/reports/v5_m4_ventilation_throttle.{json,csv}`.
- **Suite ampliada**: `validate_reference_cases.py` incluye el nuevo caso en `build_single_room_fire_checks()`. Guardrails suben de 350 a 354 checks (4 nuevos, todos PASS).

### ILV motor — Phase C: Motor credibility audit + primera migración M4 (2026-06-22)

- **Suite auditor `audit_ilv_layer_coherence_suite.py`** (`d635c83`) — wrapper batch sobre `check_ilv_layer_coherence.py`. Escanea todos los CSVs en `sim/validation/reports/`, reporta findings por archivo (total rows, finding counts, peor fila), sale con código 1 si hay findings salvo `--allow-findings`. 16 tests Python PASS. Resultados sobre 10 CSVs: 7 PASS, 3 FAIL (364 findings totales).
- **Mapa de daño — motor credibility audit**: 8 CSVs permanentes auditados. 3 casos con HRR zombie: `fp_ilv_upper_throttle_off` (258, control intencional), `tmp_v5_off` (95, spike calibrado sobre bug), `layer_interface_single_room_window` (11, hallazgo nuevo — ILV incidental en testbed de capas).
- **Primera migración M4 segura: `layer_interface_single_room_window`** (`ee9216c`) — `fire_o2_upper_throttle_enabled: true` activado permanentemente en caso de regresión de interfaz de capa. El caso no tiene `threshold_metrics` — es diagnóstico puro de alturas de capa. Todos los 7 baseline checks pasan: los mínimos de capa son idénticos (descenso ocurre antes de que M4 se active, t<130 s), los finales dentro de tolerancia. Zombie eliminado: HRR 1142→32 kW a t=180 s, `o2_upper` se recupera de 0.08% a 8.5%. Fix adicional: `two_zone_solver_enabled: true` añadido explícitamente al JSON del caso (y `fed_thermal_layer_smoke_only.json`), corrigiendo 2 failures pre-existentes en `test_layer_interface_model.py`. Suite auditor post-migración: 7/8 PASS (único FAIL = `fp_ilv_upper_throttle_off`, control intencional).

| Tiempo | HRR OFF | HRR M4 | o2_upper OFF | o2_upper M4 | Regime OFF | Regime M4 |
|--------|---------|--------|-------------|------------|-----------|----------|
| t=100s | 377.7 kW | 377.7 kW | 16.9% | 16.9% | FUEL_CONTROLLED | FUEL_CONTROLLED |
| t=130s | 662.3 kW | 336.1 kW | 4.2% | 6.5% | VCB | ILV_LATENT |
| t=160s | 959.3 kW | 79.9 kW | 0.08% | 6.6% | VCB | VCB |
| t=180s | **1142.2 kW** | **32.8 kW** | 0.08% | 8.5% | VCB | VCB |

- **Próximo caso pendiente**: `v5_ventilation_hrr_spike` (95 findings, HRR zombie 3245 kW). Requiere actualizar `threshold_metrics` antes de activar M4 — el spike está calibrado sobre el bug ILV.

### ILV motor — Phase 5 M4: fire_o2_upper_throttle_enabled (2026-06-22)

- **Motor guard `fire_o2_upper_throttle_enabled`** (`pending`) — Nuevo flag en `SimulationEngine` y `CombustionSystem`. Cuando está activo y el two-zone solver elige `o2_lower` como referencia de throttle (modo `plume_lower/blend`) pero `o2_upper` cae bajo el umbral crítico (`fire_o2_upper_throttle_critical=0.10`): reemplaza `o2_ref = minf(room.o2, room.o2_upper)`, forzando el throttle de HRR a respetar la zona superior. Fix de física real (no solo display/régimen).
- **Bug raíz corregido**: el flag se colocó erróneamente en `_sync_auxiliary_services()` (dict de `OxygenExchangeSystem`) en lugar de `_build_room_combustion_context()` (dict leído por `CombustionSystem.step_room_fire()`). Resultado: `CombustionSystem` siempre leía `fire_o2_upper_throttle_enabled=false` en escenarios headless.
- **Unit test 7/7 PASS** (`tools/validate_fire_o2_upper_throttle.gd`): bug secundario en el test era `fire_max_active_s` ausente del contexto (`context.get` usa default 0.0 → extinguía el fuego en step 0). Fix: agregar `"fire_max_active_s": 1800.0` + `"fire_extinction_delay_s": 90.0`.
- **Scenarios**: `fp_ilv_upper_throttle_on.json` / `fp_ilv_upper_throttle_off.json` — verificación before/after con `fire_o2_upper_throttle_enabled` per-caso. Coherence checker: 258 FAIL (throttle OFF) → 0 FAIL/1686 rows (throttle ON).
- **Efecto físico verificado**:

| Tiempo | HRR (OFF) | o2_upper (OFF) | o2_hrr (OFF) | HRR (ON) | o2_upper (ON) | o2_hrr (ON) |
|--------|-----------|----------------|--------------|----------|---------------|-------------|
| t=110s | 459 kW | 6.03% | 0.983 | 299 kW | 7.02% | 0.817 |
| t=120s | 550 kW | 0.08% | 0.971 | 184 kW | 5.08% | 0.612 |
| t=150s | 833 kW | 0.08% | 0.921 | 46 kW | 6.45% | 0.243 |
| t=200s | 1201 kW | 0.08% | 0.883 | (fuego apagado) | — | — |
| t=1400s | 1211 kW | 0.08% | 0.894 | N/A | — | — |

- **Flag scoped per-caso**: default `false`. El motor base no cambia. Baseline 345/350 PASS intacto (sin regresión).
- **EXP-1 (`cfast_ilv_open_window_repro` + M4, 2026-06-22) — REVERTIDO**: M4 y `fire_o2_canonical_enabled` son mecanismos en competencia. Canonical depleta `o2_lower` a ~13%; M4 sobreescribe con `min(room.o2, o2_upper) ≈ 9%` (más agresivo). Resultado: doble-freno, HRR oscila 100–750 kW vs 972 kW estable. Coherence=0, guardrails intactos, pero ±10% HRR no cumplido. M4 aplica en casos SIN canonical.
- **EXP-2 (`v5_ventilation_hrr_spike` + M4 standalone, 2026-06-22) — NO VIABLE**: M4 funciona correctamente (coherence OFF: 75 findings → M4: 0 findings). Pero el caso mide el spike como `threshold_metric: hrr >= 1000 post-vent`, que es precisamente el HRR zombie permitido por el bug. Con M4: HRR = 58–210 kW (vs 537→3232 kW OFF). El threshold_metric fallaría. El caso **testea comportamiento buggy como feature esperada**. Misma lógica aplica a todos los casos existentes con ventanas exteriores y `threshold_metrics` calibradas pre-M4.
- **CAMPAÑA M4 CERRADA (2026-06-22)**: activación en casos existentes bloqueada. M4 queda como fix gated (default `false`). Ruta futura: (A) nuevos escenarios ILV/FP con M4 como física correcta, o (B) pasada coordinada de validación que actualice los `threshold_metrics` afectados (~8-10 casos con ventana exterior). EXP-3 (`cfast_r0_window_360`) abortado — mismo patrón que EXP-2.

### ILV motor — Opción A + Opción C (en curso 2026-06-22)

- **Opción A — classifier fix** (`9e23f9e`) — `CombustionRegimeClassifier` rule 7.5: when `o2_upper < 5%` AND `hrr_kw >= 100`, reclassify as `VENTILATION_CONTROLLED_BURNING` regardless of `o2_hrr_factor`. Display/regime now reflects upper-zone starvation in open-room ILV. No HRR/O₂/physics change. Test 11/11 PASS.
- **Opción C — canonical O₂ routing per-case** (`56faa6e`) — `fire_o2_canonical_enabled: true` in `cfast_ilv_open_window_repro.json` only. Routes combustion O₂ consumption to `o2_lower` (the zone CombustionSystem reads for throttle), making HRR physically self-consistent with the two-zone plume path. Result: `o2_lower` depletes 19.7% → 13%, `o2_hrr_factor` drops 0.894 → 0.278, HRR throttles 1211 → 972 kW, `o2_upper` stabilises at ~7.9% via bidirectional entrainment. ILV coherence checker: 0 findings (was 258). Baseline 345/350 unaffected — flag scoped to repro case only.
- **FP/QA ILV base scenario** (`pending`) — `sim/validation/cases/fp_ilv_open_partial_window.json`: dedicated headless FP scenario for open-window ILV with `fire_o2_canonical_enabled: true` per-case. Verified: coherence checker 0/1686 findings, HRR throttled to ~972 kW at steady state (by design — canonical routing without secondary gain; manual QA target of ~3100 kW requires a future stress variant with `fire_secondary_hrr_gain_kw`). No motor defaults changed.

### Hito B — ILV latent observability milestone (cerrado 2026-06-21)

**Alcance cerrado:** observabilidad de régimen ILV en escenario de auditoría. El campo `fire_latent_active=true` y el régimen `ILV_LATENT` son visibles en `cfast_ilv_audit.csv`. No hay pool latent smoldering real con HRR positivo durante `ILV_LATENT` — eso es Fase 3. Validación 345/350 PASS intacta.

| Componente | Commit | Descripción |
|-----------|--------|-------------|
| Fase 0 auditoría | `c59aeba` | Escenario sellado + script diagnóstico read-only |
| Fase 1 clasificador | `922a56a` | `CombustionRegimeClassifier` 9 regímenes, `combustion_regime` en CSV |
| Fase 2 Paso 1 | `efcc492` | `fire_latent_active: bool` en `RoomModel`, upstream de `fire_smoldering` |
| Fase 2 Paso 2 | `fbf4d3e` | `thermal_hold` fix per-caso 40°C, idle reset, revert código muerto |

---

### Hito B — ILV Fase 2 Paso 2 (thermal_hold fix → ILV_LATENT en auditoría)

- **Thermal hold overrides** (`cfast_ilv_audit.json`) — `fire_latent_hold_upper_temp_c=40.0` y `fire_latent_hold_lower_temp_c=40.0`. Causa raíz: el engine default de 140°C/60°C excluía la sala sellada (pico ~70°C) del check `thermal_hold`, por lo que `latent_viable` nunca fue `true`. 40°C es alcanzable: `temp_upper=67°C` y `temp_lower=49°C` a t=406 s.
- **Idle reset `fire_latent_active`** (`CombustionSystem.gd` línea ~94) — `room.fire_latent_active = false` añadido junto a `room.fire_smoldering = false` en la rama idle/post-extinción, evitando que el campo quede stuck en `true` tras `_extinguish_room_fire`.
- **Revertido código muerto** (`CombustionSystem.gd`) — `fire_latent_smolder_o2_margin` nunca fue añadido al diccionario de contexto en `_build_room_combustion_context`; la variable `latent_smolder_margin` era inerte. Revertido a usar `latent_o2_viable_margin` directamente.
- **Resultado:** `fire_latent_active=1` durante 52 s (t=406.1–457.1 s), régimen `VENTILATION_CONTROLLED_BURNING → ILV_LATENT → EXTINGUISHED` en `cfast_ilv_audit.csv`. Post-extinción: `latent=0` correctamente. Clasificador 9/9 PASS. Baseline 345/350 PASS intacto.

### Hito B — ILV Fase 2 Paso 1 (observabilidad fire_latent_active)

- **`fire_latent_active: bool`** (`efcc492`) — nuevo campo en `RoomModel`, asignado desde `(not can_flame) AND latent_viable` sin gate de `hrr_kw`. Señal upstream de `fire_smoldering`; el clasificador ahora lee `fire_latent_active` para el régimen `ILV_LATENT`. Expuesto en dict de estado y CSV. Default `false`; ningún cambio de física. Con defaults el gap O2 (8.5–10.8 %) impide que `fire_latent_active` se active — Paso 2 cerrará ese gap.

### Hito B — ILV Auditoría Fase 0 (extinción directa)

- **Audit scenario** (`sim/validation/cases/cfast_ilv_audit.json`) — escenario sellado room 2 (dormitorio, ~36 m³), legacy fire path (`fuel_objects: []`), 900 s, sin infiltración ni spread. Reproduce extinción directa ILV para diagnóstico reproducible sin tocar física.
- **Audit script** (`scripts/simulation/audit_ilv_phase0.py`) — script diagnóstico read-only. Registra por segundo los campos ILV clave y reporta transiciones de régimen, condiciones en extinción y gap estructural `can_flame`/`latent_viable`. No modifica física ni validación.
- **Hallazgo Fase 0:** fuego pasa `VENTILATION_CONTROLLED_BURNING → EXTINGUISHED` a t=436 s, o2=10.9 %, sin pasar por `ILV_LATENT`. Causa raíz: `fire_smoldering` requiere `hrr_kw > 0.5`; el HRR cayó por debajo antes de que `fire_smoldering` pudiera activarse. Gap estructural: con `fire_o2_min_for_flame=0.10`, `can_flame=false` a o2<8.5 % pero `latent_viable=false` a o2<10.8 % — ventana 8.5–10.8 % bloquea llama y latencia simultáneamente.

### Hito B — ILV Clasificador (Fase 1 diagnóstico)

- **CombustionRegimeClassifier** (`922a56a`) — clasificador read-only de régimen de combustión. Lee campos existentes de `RoomModel` y escribe un nuevo campo `combustion_regime: String`. No modifica HRR, O₂, gases, temperaturas ni ningún check de validación. 9 regímenes: `FUEL_CONTROLLED`, `VENTILATION_STRESSED`, `VENTILATION_CONTROLLED_BURNING`, `VENTILATION_INDUCED_GROWTH`, `ILV_LATENT`, `FULLY_DEVELOPED`, `BACKDRAFT_RISK`, `BACKDRAFT_EVENT`, `EXTINGUISHED`. Campo expuesto en estado de sala (dict + CSV). Test headless 9 casos: `tools/validate_combustion_regime.gd`. Baseline validación: 345/350 PASS intacto.

## v0.4.0+ux-polish

### FP UX Polish

- **Camera stance easing** (`c7e3db8`) — `_apply_stance(immediate=false)` now lerps the camera toward the stance target height (tau = 80 ms) instead of snapping. `immediate=true` preserves snap on init. Test: `tools/validate_fp_stance_easing.gd` (stand/crouch/prone convergence in 30 physics frames).
- **Opening prompt text** (`a689f1d`) — four consistency and orthography fixes: `"Dejar pulsado F: elegir apertura"` → `"Mantén F: elegir grado"`; `"ventilacion"` → `"ventilación"`; `"Suelta para aplicar."` → `"Suelta F para aplicar."`; `"Suelta F: puerta 0% | manten F…"` → `"Suelta F: cerrar puerta 0% | mantén F…"` (added action verb, fixed accent).
- **FP corner collision diagnostic** — code inspection of `CharacterBody3D + CapsuleShape3D + move_and_slide()` stack found no reproducible issue. Room geometry (min 2.8 m free span) and doorway clearance (0.42 m) are well above the 0.48 m capsule diameter. No bug identified; no headless test added (no reproduction case). Debt closed as "sin issue reproducible".

## v0.4.0

### QA FP/UX

- Headless FP suite (Godot): victim states, detector alarm, fire visuals, player start, technical HUD — all PASS.
- `FPVisibilityOverlay` smoke layer transition confirmed continuous (42 cm band); no step-function issue.
- Known minor debt: `_apply_stance(immediate)` camera easing not implemented — resolved in v0.4.0+ux-polish.

## v0.4.0-validation-rc2

### Validation — 345/350 PASS, 5 VALID_GAP

- **Phase 2A** — zonal mass sync (`upper_gas_kg`/`lower_gas_kg`) for all rooms in `ThermalSystem`.
- **Phase 2B** — combustion O₂ routing: consumption and throttle from `o2_upper`; `fire_o2_mode="upper"` for bedroom case.
- **Phase 2C** — canonical doorway exchange in `cfast_two_room_door_open`; RMSE 53.8 °C (threshold ≤60 °C).
- **Phase 2D** — HVAC two-zone O₂ mass balance: return extracts from `o2_upper`, supply from `o2_lower`; `cfast_hvac_t300_o2` PASS.
- **Phase 2E-bedroom** — per-case O₂ calibration for `cfast_bedroom_closed_door`; all 5 O₂ checks PASS.
- **Phase 4B** — wall reradiation during active fire (`phase4b_wall_reradiation_during_fire_enabled`); `cfast_slow_growth_sealed` temperature checks PASS.
- **Phase 5A sweep** — 15-config per-case sweep for Group A (`cfast_r0_window_360`); confirmed VALID_GAP, no viable fix without canonical two-zone architecture.
- **Validation milestone closed 2026-06-21** — final baseline 345/350 PASS, 5/350 required FAIL (all VALID_GAP, structural Phase 2/3+). See `docs/validation/GAPS_INVENTORY.md`.

Required FAIL summary:

| Group | Checks | Root cause |
|-------|--------|------------|
| A — `cfast_r0_window_360` | 3 O₂ upper checks | Requires canonical two-zone O₂ architecture (Phase 2+) |
| C — `cfast_corridor_chain` | 2 temp_upper checks | Requires two-zone pressure/exchange ODE (Phase 3+) |

### Product / FP

- **HUD temperature blend** (`497b663`) — replaces step-function `temp_at_N_m_c` lookup with a display-side lerp (±25 cm band around `thermal_layer_m`). Eliminates HUD temperature jumps when the hot layer crosses player eye height. No physics changed.

### Documentation and Repository Structure

- Organized documentation into `docs/audits/`, `docs/architecture/`, `docs/roadmaps/`, `docs/validation/`, `docs/planning/`, `docs/handoff/`, `docs/archive/`, and `docs/literature/`.
- Added documentation entrypoints: `docs/INDEX.md`, `docs/COMMANDS.md`, `docs/LOCAL_WORKSPACE.md`, `docs/ARTIFACT_POLICY.md`, `docs/LINK_AUDIT.md`, and `docs/RELEASE_CHECKLIST.md`.
- Added architecture documents: `PROGRAM_FLOW.md`, `CONTRIBUTOR_GUIDE.md`, `MODULE_BOUNDARIES.md`, and `REFACTOR_PLAN.md`.
- Added ADRs for documentation layout, script/tool boundaries, validation lanes, artifact policy, and local literature.
- Added audit issue index and templates for future ADRs, audits, release notes, and technical issues.
- Moved root session notes, temporary artifacts, exploratory scripts, and local literature into documented archive/library locations.

### Tooling

- Added `scripts/check_docs_links.py` for lightweight Markdown link checks.
- Added `scripts/clean_workspace.ps1` for safe cleanup of ignored local artifacts.
- Added documentation and product Python GitHub Actions workflows.
- Added `tools/diag_fp_temp_jump.json` — diagnostic scenario for reproducing HUD temperature layer-crossing jumps.

## v0.4.0-validation-rc1

### Validation Status

- Legacy required checks documented as passing.
- Two-Zone M4 contract documented as opt-in and passing.
- Known non-gating HVAC and empirical flashover gaps documented.

### Notes

- See `docs/validation/SIMUFIRE_VALIDATION_SUMMARY_2026-05-31.md` and `docs/validation/STATUS_VALIDATION.md` for validation detail.
