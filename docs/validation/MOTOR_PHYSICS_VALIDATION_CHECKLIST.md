# Motor Physics Validation Checklist

Date: 2026-06-28.

This checklist tracks the physics and validation items that must be audited before treating the SimuFire motor as physically credible. It is intentionally focused on engine data and validation, not first-person visuals or presentation-layer effects.

## Scope

Primary goal: validate that the engine produces physically coherent data across combustion, two-zone transport, toxic gases, smoke, pressure, wall heat exchange and tenability.

Out of scope for this phase:

- First-person visual polish.
- HVAC, until the core fire, gas, smoke, pressure and two-zone behavior is stable.
- Global motor changes without an explicit validation plan.
- Widening tolerances or rewriting reports to force PASS.

## Baseline Principle

Validation must check more than isolated final values. Each scenario should be traceable through:

1. Source generation.
2. Storage by room and layer.
3. Transport between layers, rooms and exterior.
4. Conversion to observable metrics.
5. Comparison against CFAST or documented realistic scenarios.
6. Temporal consistency over the full fire, not only single checkpoints.

## 1. HRR And Energy

### Internal storage and calculation (audited 2026-06-25)

HRR pipeline (`CombustionSystem.gd::step_room_fire`):

- `ideal_hrr_kw` — t² curve up to `fire.max_hrr_kw`, before any limiting.
- `solid_pyrolysis_kw` — fuel gasification rate (pre-combustion, O2-independent).
- `fresh_flame_target_kw` — portion burning immediately in flames (O2-limited via `flame_drive`).
- `smolder_hrr_target_kw` — portion burning in low-O2 smoldering.
- `pool_release_hrr_target_kw` — portion from `retained_unburned_MJ` pool release.
- `hrr_target_kw` — sum of the three above (stored in `room.hrr_target_kw`).
- `room.hrr_kw` — time-smoothed output via rise/fall constants; **primary HRR seen by room**.
- `burned_hrr_kw` — equals `maxf(0, room.hrr_kw)`; semantically redundant with `hrr_kw` post-clamp.
- `unburned_generation_kw` — pyrolysis gases not combusted; feeds `retained_unburned_MJ` pool.
- `retained_unburned_MJ` — unburned gas pool; released in backdraft or decays.

Fuel accounting (`fire.remaining_fuel_MJ`, `FireModel.gd:13`):

- Decremented each step: `maxf(0, remaining_fuel_MJ - solid_pyrolysis_kw * dt / 1000)`.
- Scale-clamped: if demand exceeds available, all pyrolysis targets scale down proportionally.
- Extinguishment gate: `remaining_fuel_MJ <= 0 AND retained_unburned_MJ <= 0.01`.
- Multi-object: `fuel_objects[].remaining_fuel_MJ` decremented independently per object.

Thermal feedback:

- `rad_feedback = 1.0 + thermal_feedback_coeff * (T_upper - T_ambient) / 500.0`
- Amplifies HRR target with room temperature. O2 consumption is NOT scaled proportionally — stoichiometric violation (see risks below).

Energy budget fields (exported to JSON only, not CSV by default):

- `bud_e_fire_kj`, `bud_q_rad_kj`, `bud_q_to_lower_kj`, `bud_q_to_ambient_kj`
- `bud_q_wall_abs_kj`, `bud_q_wall_emit_kj`, `bud_de_upper_kj`, `bud_q_residual_kj`
- `bud_chi_rad`, `bud_q_fire_rad_kj`

### CSV/JSON export status

Already exported to CSV: `hrr_kw`, `pyrolysis_kw`, `burned_hrr_kw`, `unburned_generation_kw`, `flame_hrr_target_kw`, `smolder_hrr_target_kw`, `pool_release_hrr_target_kw`, `o2_hrr_factor`, `fuel_remaining_MJ`, `retained_unburned_MJ`.

Already exported to JSON: all of the above plus `hrr_target_kw`, `fire_time_s`, `fuel_energy_MJ`, `fuel_capacity_MJ`, `unburned_fuel_MJ`, energy budget fields.

### Missing for per-step HRR/energy audit

- `fuel_consumed_MJ_step` — `solid_pyrolysis_kw * dt / 1000` not persisted; only snapshot `remaining_fuel_MJ` available.
- `hrr_delivered_kj_step` — `hrr_kw * dt` (kJ released to room this step); derivable from CSV but not explicit.
- `fuel_burned_fraction_step` — `fresh_flame_target_kw / solid_pyrolysis_kw`; not exported.
- `backdraft_energy_release_kj_step` — pool combustion energy not isolated from base HRR.

### Current auditor coverage

- A2: HRR without fuel (FAIL-gating).
- A3: fuel-controlled regime with critical O2 (FAIL-gating).
- ILV HRR-zombie pattern (ILV coherence auditor).

### Open gaps

- Per-step `fuel_consumed_MJ_step` to close integrated-energy balance.
- HRR × dt vs `Δfuel_remaining_MJ` consistency check (not yet implementable without step field).
- Backdraft energy isolation.
- Reventilation HRR growth validation.

---

## 2. Oxygen

### Internal storage (audited 2026-06-25)

O2 representation is **dual: fraction (primary) + optional mass (secondary, opt-in)**.

RoomModel O2 fields:

| Field | Type | Semantics |
|-------|------|-----------|
| `o2` | fraction | Whole-room average. Derived from two-zone layers if solver enabled; legacy field. |
| `o2_upper` | fraction | Upper-layer (hot zone). Canonical O2 source for combustion throttling. Updated by ThermalSystem + GasExchangeSystem. |
| `o2_lower` | fraction | Lower-layer (cool zone). Independent since Phase 2A. Near-ambient unless HVAC or fire affects it. |
| `upper_o2_mass_tracked` | kg | Mass of O2 in upper zone. **Opt-in Phase 5 M2** (`fire_o2_mass_tracking_enabled`). `-1.0` = uninitialized. Never used in combustion physics. |
| `canonical_o2_upper_updated` | bool | Set by ThermalSystem; prevents OxygenExchangeSystem from overwriting with stale fraction. |

### O2 consumption — corrected diagnosis (2026-06-25)

> **Prior diagnosis was wrong.** An earlier audit stated that `fire.o2_consumption_kg_per_MJ` was
> "defined but never applied." That was incorrect.

`OxygenExchangeSystem.gd` **already applies** the Thornton rate (`fire.o2_consumption_kg_per_MJ = 0.076`)
for stoichiometric combustion depletion:

| Site | Variable | Condition |
|------|----------|-----------|
| Line 356 | `room.o2` (bulk) | `hrr_kw > 0` and not lower-zone / canonical modes |
| Lines 386–395 | `room.o2_upper` | `lower_frac ≥ 0.15`, `hrr_kw > 0`, and not `two_zone_solver_enabled` |

Both uses: `consumed = (hrr_kw / 1000.0) * fire.o2_consumption_kg_per_MJ * dt`.
Capped at 5 % of total O2 mass (bulk) and 20 % of upper O2 mass per step to prevent numeric instability.

This means combustion **does** remove O2 from the room — via OxygenExchangeSystem, not CombustionSystem.

### Double-count fix (commit d7e4aba, 2026-06-25)

An MVP implementation (`fire_o2_stoich_consumption_enabled`, commit 03372fe) attempted to add a second
Thornton-rate deduction inside CombustionSystem. Because OES already applies the same deduction, this
caused `o2_upper` to deplete at **twice** the correct rate.

Fix: the CombustionSystem block was converted to **tracking-only**. It computes
`o2_consumed_kg = hrr_kw * dt / 1000 * fire.o2_consumption_kg_per_MJ` and stores it in
`room.o2_consumed_kg_step` / `room.o2_consumed_kg_total` for diagnostic CSV export, but does **not**
modify `room.o2_upper`. OES remains the sole writer of combustion O2 depletion.

`fire_o2_stoich_consumption_enabled` (default=`false`) now means "emit Thornton accounting in CSV,"
not "activate a second depletion physics path."

### O2 transport functions

- OxygenExchangeSystem lines 386–395 — combustion depletion of `o2_upper` (Thornton rate).
- OxygenExchangeSystem line 356 — combustion depletion of `room.o2` bulk (Thornton rate).
- OxygenExchangeSystem line 405 — plume entrainment: blends `o2_lower` into `o2_upper`.
- OxygenExchangeSystem line 440 — plume drag: drains `o2_lower`.
- OxygenExchangeSystem line 472 — ACH infiltration replenishes `o2_lower`.
- ThermalSystem `_step_two_zone_plume_entrainment` — blending ratio update on `o2_upper`/`o2_lower`.
- GasExchangeSystem `_handle_internal_doorway_flow` — inter-room O2 transfer.
- GasExchangeSystem `step_pressure_venting` → `_vent_exterior_gas` — vents O2 to exterior.
- GasExchangeSystem `step_ppv` — injects exterior O2 via PPV.

### Diagnostic tracking fields (available in CSV)

| Field | Status | Semantics |
|-------|--------|-----------|
| `o2_consumed_kg_step` | Exported (flag=true) | Thornton O2 consumed by fire this step (shadow of OES). |
| `o2_consumed_kg_total` | Exported (flag=true) | Cumulative Thornton O2 consumed. |
| `o2_consumed_bulk_kg_step` | Exported | O2 consumed by the path that directly depletes `room.o2` bulk. |
| `o2_consumed_bulk_kg_total` | Exported | Cumulative bulk-only O2 consumption. Used by O1. |
| `o2_consumed_kg_step_all` | Exported | Sum of all O2 consumption paths: bulk, upper, lower and plume. Diagnostic only for O1 bulk. |
| `o2_consumed_kg_total_all` | Exported | Cumulative all-path O2 consumption. Diagnostic only for O1 bulk. |
| `o2_exterior_net_kg_step` | Exported | Net O2 exchange with exterior this step; positive means O2 entered the room. |
| `o2_exterior_net_kg_total` | Exported | Cumulative exterior O2 exchange. Used by O1. |
| `o2_net_transport_kg_step` | Exported | Net inter-room O2 transport this step; positive means the room received O2. |
| `o2_net_transport_kg_total` | Exported | Cumulative inter-room O2 transport. Used by O1. |
| `o2_zone_sync_kg_step` | Exported | Bulk O2 mass delta caused by zone-to-bulk sync. Used by O1 after O1-D. |
| `o2_zone_sync_kg_total` | Exported | Cumulative zone-sync O2 mass delta. Used by O1. |
| `upper_o2_mass_tracked` | Orphaned | Opt-in Phase 5 M2; `-1.0` = uninitialized; not used in physics. |

### O1 bulk O2 mass balance — CLOSED AS FAIL/GATING (2026-06-29)

O1 now audits the bulk `room.o2` mass balance per room/log interval:

```text
delta_bulk = (o2[t] - o2[t-1]) * air_mass_kg
expected   = -delta(o2_consumed_bulk_kg_total)
             + delta(o2_exterior_net_kg_total)
             + delta(o2_net_transport_kg_total)
             + delta(o2_zone_sync_kg_total)
residual   = abs(delta_bulk - expected)
```

Status:

- O1 is implemented in `scripts/simulation/check_physics_coherence.py` as **FAIL-gating**.
- Corpus O1 audit after canonical doorway fix and promotion: 14 PASS / 0 FAIL in active cases.
- `cfast_two_room_door_open` is clean after the O1-D canonical doorway fix.
- Tests: 22 `TestCheckO1`; O1 instrumentation subset green.

Important fixes found while closing O1:

- `SimulationStateBuilder` had applied a CO2 molar correction to logged `o2` in non-fire rooms only. This made CSV `o2` diverge from actual `room.o2`; fixed by exporting `room.o2` directly.
- `o2_consumed_kg_total_all` cannot be used for bulk O1 because it includes upper/lower/plume consumption. O1 uses `o2_consumed_bulk_kg_total`.
- `_apply_room_o2_mass_delta` now accumulates the post-clamp `actual_delta_kg`, not the intended delta, avoiding false WARNs when clamped at `o2_nominal`.
- `_apply_canonical_doorway_exchange` no longer records `_cde_net_hot` as direct `o2_net_transport_kg_total`: bulk `room.o2` changes through zone blend, so `o2_zone_sync_kg_total` is the correct O1 term for the CDE effect.
- CDE now tracks zone sync for `cold_room` as well as `hot_room`.

### Open gaps

- O1 is a bulk balance rule. It does not replace future zonal O2 balance for `o2_upper`/`o2_lower`.
- `upper_o2_mass_tracked` is orphaned — not used in combustion, not exported to CSV.
- Dual-track risk: `o2_upper` (fraction) and `upper_o2_mass_tracked` (mass) may diverge if `canonical_o2_upper_updated` flag handling fails.
- Option C (canonical mass redesign) needed to fully separate combustion/transport/dilution paths.

### O2E1 Thornton cross-check — CLOSED AS FAIL/GATING (2026-06-29)

O2E1 cross-checks `o2_consumed_fire_kg_total` (OES primary-path accumulator) against the Thornton prediction derived from `hrr_kj_total` (CombustionSystem tracking-only accumulator).

```text
expected_o2 = delta(hrr_kj_total) * 7.6e-5  (kg/kJ — Thornton 13.1 MJ/kg O2)
residual    = |delta(o2_consumed_fire_kg_total) - expected_o2|
tolerance   = max(1e-5, 0.05 * |expected_o2|)
```

Why `o2_consumed_fire_kg_total` and not `o2_consumed_kg_total_all`:

`o2_consumed_kg_total_all` accumulates from every OES depletion path per step. In standard two-zone mode (`lower_frac ≥ 0.15`, no special flags), OES runs both the bulk path (OES line 362) and the upper-zone path (OES line 407) with the same full Thornton formula, making `*_all ≈ 2 × Thornton`. This is a pre-existing tracking issue, not a physics bug (both zone layers do lose O2), but it makes O2E1 compare against the wrong magnitude.

`o2_consumed_fire_kg_total` captures exactly ONE Thornton unit per step by selecting the primary depletion path:

| Condition | Primary path | Rationale |
|---|---|---|
| Default (bulk ran) | bulk (`o2_consumed_bulk_kg_step`) | bulk always runs in homogeneous and standard two-zone |
| `fire_uses_lower_o2` | lower (`consumed_lower`) | bulk is blocked by this flag |
| `effective_plume_lower` | plume (`plume_consumed`) | bulk is blocked by this flag |
| `_phase2b_upper_active` only | upper (`upper_consumed`) | bulk is blocked by this flag |

Status:

- **FAIL-gating** in `scripts/simulation/check_physics_coherence.py`.
- **14 PASS / 0 FAIL** — active physics coherence corpus clean after M5/C1 closure and O1-D.
- Prior state before fix: 8 WARN, 1308 false WARN findings, max residual 1.95e-5 kg.
- `o2_consumed_kg_total_all` and `o2_consumed_bulk_kg_total` (O1) unchanged.
- Tests: 157 PASS (includes `test_two_zone_double_count_does_not_warn`, `test_old_o2_consumed_all_col_alone_skips_gracefully`).
- No physics change. No O1 impact.

Corpus diagnóstico (2026-06-27) — ampliación O2E1/O1:

Three new cases run to cover the WARN→FAIL promotion criteria:

| Caso | Criterio | Dur | O2E1 | O1 | Resultado |
|---|---|---|---|---|---|
| `cfast_slow_growth_sealed` | C2 larga duración ≥ 600 s + O2 sealed | 1800 s | PASS | PASS | ✅ Criterio cumplido |
| `cfast_two_room_door_open` | C3 multi-room + intercambio O2 | 600 s | PASS | 247 WARN | O2E1 ✅; O1 gap (ver abajo) |
| `v1_backdraft_accumulation` | C1 backdraft / pool-release | 650 s | 16 WARN | PASS | ❌ A3 FAIL (CTRL — ver abajo) |
| `v1_m4_pool_release` | C1 backdraft path-exercise (M4) | 650 s | 5 WARN | PASS | ⚠️ Path ejercitado; WARNs en zombie post-backdraft (CTRL) |

**C4** (`effective_plume_lower`): ya cubierto por `fp_ilv_open_partial_window` (280 pasos con path no-bulk activo, O2E1 PASS — en suite desde 2026-06-27).

Diagnóstico por caso:

- **`cfast_slow_growth_sealed`** (PASS total): O2E1 y O1 PASS en 1800 s sellado con fuerte depleción O2 y plume engine overrides. Confirma que el acumulador primario se mantiene dentro de Thornton bajo condiciones de cap extenso. Apto para suite permanente.

- **`cfast_two_room_door_open`** (O2E1 PASS, O1 PASS after O1-D): C3 multi-room remains covered for O2E1, and the prior O1 canonical doorway double-count is closed by `bd3e13e`.

- **`v1_backdraft_accumulation`** (CTRL — A3 + O2E1 FAIL): Motor mantiene `FULLY_DEVELOPED` con `o2_upper=0.0009`. A3 captura la incoherencia; O2E1 FAIL consecuencia (O2E1 es ahora FAIL-gating). `retained_unburned_MJ=0` — pool release nunca activó. Registrado como CTRL en ambos audit suites.

- **`v1_m4_pool_release`** (CTRL — path-exercise): M4 activo, gates relajados (`fire_backdraft_pool_threshold_MJ: 0.35`, `fire_backdraft_o2_max: 0.20`, `fire_backdraft_temp_min_c: 100.0`, `fire_backdraft_lfl: 0.001`). `backdraft_triggered=1` a t=350 s, HRR pico 21.369 kW, `retained_unburned_MJ` agotado a t=355 s — **path de backdraft/pool-release ejercitado**. Post-evento: zombie A3 reanuda (mismo bug que v1_backdraft). 8 A3 FAILs + 5 O2E1 FAILs en fase zombie, no durante backdraft. Ambos casos registrados como CTRL en `KNOWN_INTENTIONAL_CONTROLS` de physics + ILV suites. Physics coherence suite ahora exit 0.

Estado de criterios WARN→FAIL (actualizado):

| Criterio | Estado |
|---|---|
| C1 backdraft / pool-release | ✅ M5 cerrado — zombie eliminado; `v1_m4_pool_release` CTRL limpio en ventana backdraft |
| C2 larga duración ≥ 600 s | ✅ Cubierto — `cfast_slow_growth_sealed` PASS |
| C3 multi-room O2 exchange | ✅ Cubierto para O2E1 — `cfast_two_room_door_open` O2E1 PASS |
| C4 effective_plume_lower | ✅ Cubierto — `fp_ilv_open_partial_window` PASS |

**Decision C1 — cerrada (2026-06-29):** M5 (`fire_post_bd_hrr_cut_enabled`) produced the clean C1 evidence required for promotion. `v1_m4_pool_release` preserves the main backdraft event and removes the post-event zombie findings. O2E1 is now FAIL-gating.

Open items:

- `o2_consumed_kg_total_all` still double-counts in two-zone mode — not fixed (tracking issue, not physics). Future rules needing "one Thornton unit" must use `o2_consumed_fire_kg_total`, not `*_all`.
- `upper_o2_mass_tracked` remains orphaned — not used in combustion, not exported to CSV.

## 3. CO, CO2 And HCN

Items to check:

- CO, CO2 and HCN generation from combustion yields.
- Yield dependence on fuel, ventilation state and `o2_hrr_factor`.
- Carbon budget enforcement.
- Transport conservation between rooms, layers and exterior.
- Distinguish local generation from imported gases.
- PPM conversion from internal mass and layer volume/density.
- CO/CO2/HCN consistency with FED and tenability metrics.

### D1 CO Mass Balance — CLOSED (2026-06-24, commit b41fcbd + promotion)

Rule D1 verifies per-room, per-step CO mass balance:

```
delta_co = co_kg[t] - co_kg[t-1]
expected = delta(co_generated_kg_total) + delta(co_net_transport_kg_total) - delta(co_exterior_removed_kg_total)
residual = abs(delta_co - expected)
threshold = max(1e-6, 0.05 * max(abs(expected), 1e-6))
```

D1 is **FAIL-gating** as of 2026-06-24. Validated on 5 permanent CSVs (0 findings across all).

Three previously untracked CO paths were instrumented (commit b41fcbd):

1. `GasExchangeSystem._purge_upper_species_to_exterior_direct` — two_zone=true pressure-venting branch now accumulates `co_exterior_removed_kg_total`.
2. `ThermalSystem._flush_contaminant_deltas` — hot-gas carry between rooms now accumulates `co_net_transport_kg_total` using actual post-clamp delta (`room.co_kg - _co_pre_thermal`).
3. `GasExchangeSystem._release_pending_interior_deliveries` — delayed inter-room CO deliveries now accumulate `co_net_transport_kg_total` using actual post-clamp delta (`target.co_kg - _co_pre_delivery`).

Semantic note: `co_net_transport_kg_total` is a broad net transport field. It includes inter-room exchange, hot-gas carry (ThermalSystem), and delayed interior deliveries — not only direct room-to-room doorway flow.

Required CSV columns: `co_kg`, `co_generated_kg_total`, `co_net_transport_kg_total`, `co_exterior_removed_kg_total`, `time_s`, `room_id`. D1 is silently skipped for CSVs that lack these columns.

### Current Toxic Gas Audit Findings

Internal storage:

- `co_kg`: total room CO mass.
- `co_upper_kg`: upper-layer CO mass.
- `co2_kg`: total room CO2 mass.
- `co2_upper_kg`: upper-layer CO2 mass.
- `co2_upper`: calibrated mole fraction tracer, not derived from `co2_upper_kg`.
- `hcn_kg`: total room HCN mass.
- `hcn_upper_kg`: upper-layer HCN mass.
- `c_burned_total_kg`: accumulated burned carbon.
- `c_exited_kg`: carbon exited through openings.
- `c_balance_frac`: unclamped-yield fraction; `1.0` means no carbon clamp, lower values mean clamp active.
- `carbon_conservation_error_kg`: gas carbon minus burned carbon; negative can mean carbon exited, positive suggests spurious creation.

Generation pipeline:

- CO generation is phi-dependent and HRR-based.
- CO yield is boosted in ventilation-limited and afterburning conditions.
- CO, CO2 and HCN generation are clamped by carbon budget (`SF-AUD-032`).
- Generated CO is added to `co_kg` and partitioned to `co_upper_kg`.

Transport:

- Gas transport uses delta accumulators and applies deltas at the end of the step.
- Doorway counterflow is bidirectional and proportional to exchanged air mass.
- Exterior ventilation and purge remove species; they should not create them.
- Smoke-CO coupling moves CO with smoke during doorway smoke movement.

Conversion to ppm:

- Bulk `co_ppm`, `co2_ppm` and `hcn_ppm` use constant density `1.2 kg/m3`.
- Upper-layer `co_upper_ppm` and `hcn_upper_ppm` use temperature-corrected layer density.
- `co2_upper_ppm` is computed from `co2_upper * 1e6`, not from `co2_upper_kg`.

Important caveats:

- `co2_upper_ppm` is not directly comparable to `co_upper_ppm`, because CO upper ppm is mass-derived while CO2 upper ppm is tracer-derived.
- A naive "CO rises without local HRR" rule is invalid in multi-room cases: CO can be transported from a burning room into a non-burning room.
- D1 CO-zombie detection requires local generation instrumentation, not only room-local concentration deltas.

Rules viable from current CSV columns:

- **D1**: CO mass balance — FAIL-gating, closed 2026-06-24.
- **D2**: CO/CO2 ratio. Implemented as WARN diagnostic on mass-derived fields; see plan/results below (2026-06-30).
- D3: CO absent with high HRR.
- D4: HCN present with zero CO.
- D5: CO/HRR/O2 magnitude consistency.

Instrumentation now available in CSV (as of 2026-06-24):

- `co_generated_kg_step`, `co2_generated_kg_step`, `hcn_generated_kg_step` per room and step.
- `co_net_transport_kg_step` per room and step (net, not split in/out).
- `co_generated_kg_total`, `co_net_transport_kg_total`, `co_exterior_removed_kg_total` per room (cumulative).
- `c_balance_frac`, `carbon_conservation_error_kg` per room and step.

Remaining gap: `co_transported_in_kg` and `co_transported_out_kg` (split in/out) are not tracked separately. `co_net_transport_kg_total` covers the net; split tracking would require additional instrumentation.

### D2 — Plan semántico y regla diagnóstica (2026-06-30)

**Raíz del bloqueo:**

`co2_upper_ppm` (usado actualmente en CSV y FED) es tracer-derived: `room.co2_upper * 1e6`, donde `room.co2_upper` es una fracción molar ODE actualizada por `OxygenExchangeSystem`. Init: `0.0004` (ambient).

`co_upper_ppm` (CO upper) es mass-derived/temperatura-corregida: usa `room.co_upper_kg / upper_zone_mass_kg * 29e6 / 28`. Init: `0.0`.

Un ratio CO/CO2 construido sobre estas dos representaciones mezcla trayectorias incomparables.

**Brecha de inicialización adicional:** `room.co2_upper_kg` (mass-derived CO2 upper) se inicializa a `0.0`, no a la masa ambient equivalente a 400 ppm. Cualquier regla D2 sobre mass-derived producirá falsos positivos al inicio de cada simulación hasta que el fuego genere suficiente CO2 para superar el gap.

**Ruta recomendada — Opción C (3 fases):**

Fase 1 — Exportar `co2_upper_ppm_mass` (mínimo GDScript, sin cambio de FED): **COMPLETA (2026-06-30)**
- [x] `ThermalSystem.gd`: `compute_co2_upper_ppm_mass(room)` añadida. Guarda `upper_gas_kg < 0.1` → fallback tracer. FED sin cambio.
- [x] `SimulationEngine.gd`: callable registrado.
- [x] `SimulationStateBuilder.gd`: callable declarado + `"co2_upper_ppm_mass"` en state dict.
- [x] `SimulationLogWriter.gd`: `co2_upper_ppm` y `co2_upper_ppm_mass` añadidos al CSV (header=115, body=115).
- [x] Verificado: `cfast_slow_growth_sealed` 384 rows, ambas columnas presentes, fallback = 400 ppm a t=5s.
- [x] Audit suite: 14 PASS / 2 CTRL / 0 FAIL — sin regresiones.
- **Nota init:** `co2_upper_kg` permanece en 0.0 (RoomModel sin cambio). El guard `upper_gas_kg < 0.1` resuelve la brecha de inicialización usando el fallback tracer (400 ppm) hasta que exista zona caliente. RoomModel init NO fue necesario cambiar.

Fase 2 — Regla D2-pre diagnóstica (WARN, sin gating): **COMPLETA (2026-06-30)**
- [x] `check_physics_coherence.py`: regla `D2PRE` añadida. `rel_div = |co2_upper_ppm_mass − co2_upper_ppm| / max(co2_upper_ppm, 400)`. Threshold: `rel_div > 1.0` (100%, mass >2× tracer). Severity: WARN, no gating, skip graceful en CSV legacy.
- [x] 21 tests `TestCheckD2PRE` — 183/183 PASS total.
- [x] **Resultado diagnóstico `cfast_slow_growth_sealed`**: 243 D2PRE WARNs en room 0 desde t=320s. Tracer toca ~85k ppm y decrece; mass-derived llega a >220k ppm y sigue subiendo. `rel_div` crece a 2.2+ indefinidamente.
- [x] **Audit suite**: 13 PASS / 1 WARN (D2PRE) / 2 CTRL / 0 FAIL. Exit code = 0.
- **Diagnóstico completo (2026-06-30)** — causa raíz identificada:
  - **M1 (DOMINANTE):** OES aplica `o2_scale = o2_upper/0.209` a producción tracer. A t=700s o2_scale=0.301 → tracer recibe solo 30% de producción. CombustionSystem usa HRR real (ya throttleado por O₂) — double-throttle. Ratio producción mass/tracer = 2.56× a t=700s, 2.65× a t=1800s.
  - **M2 (amplificador):** `compute_co2_upper_ppm_mass` usa densidad caliente (~0.71 kg/m³ a 186°C); OES usa densidad ambiente 1.2 kg/m³. Ratio densidades = 1.68× a t=700s (crece a 1.83×). Densidad caliente es más correcta físicamente.
  - **M3 (early-transient):** Tracer inicia en 400 ppm atmosférico; mass en 0 kg → tracer > mass para t < 300s.
  - **dt_phys = 0.0833s:** `co2_generated_kg_step` es por paso físico; 120 pasos/10s → producción total 0.155 kg/10s > drenaje ACH 0.082 kg/10s → co2_kg crece correctamente.
  - **Track más fiable para tenabilidad t > 300s:** mass path (`co2_upper_ppm_mass`). Tracer subestima por M1.

Fase 3 — D2 ratio rule (WARN inicial): **COMPLETA (2026-06-30)**
- [x] `check_physics_coherence.py`: regla `D2` añadida. `ratio = co_upper_ppm / co2_upper_ppm_mass`. Threshold: `ratio > 0.5` (CO > 50% de CO₂ en moles → VC severo / post-FO). Severity: WARN, no gating.
- [x] Skip conditions: `co2_upper_ppm_mass` ausente → legacy CSV; `co2_upper_ppm_mass < 1000 ppm` → CO₂ no establecido; `time_s < 60 s` → M3 early-transient guard.
- [x] `co2_upper_ppm` tracer NO usado como denominador — suprimido por o2_scale double-throttle (M1).
- [x] 26 tests `TestCheckD2` — **209/209 PASS** total suite.
- [x] **Resultado `cfast_slow_growth_sealed`**: CO/CO₂ ppm ratio = 0.006–0.008 durante toda la simulación. Threshold 0.5 no disparado → **0 findings D2**. Exit code = 0.
- [x] **Audit suite**: 13 PASS / 1 WARN (D2PRE sin cambio) / 2 CTRL / 0 FAIL — sin regresiones.
- **Observación calibración CO:** Ratio generación CO/CO₂ = ~0.004–0.005 constante incluso en VENTILATION_CONTROLLED. SFPE para wood under-ventilated (phi~2): ~0.3 masa → ~0.47 molar. SimuFire infra-estima CO en VC — pendiente como plan calibración separado, no bloqueante.
- **Pendiente separado:** Plan motor para corregir o2_scale double-throttle en OES tracer CO₂ (M1 D2PRE root cause).

### Próximos planes D2 (post-Fase 3)

**Plan A — Calibración CO en régimen ventilation-controlled** *(diagnóstico completado 2026-06-30)*

#### Diagnóstico Plan A (2026-06-30)

Root cause identificado. El bajo CO/CO₂ en `cfast_slow_growth_sealed` no es un bug del motor de escalado phi→CO sino una combinación de tres capas arquitectónicas:

**Capa 1 — Force override en caso CFAST (causa primaria, intencional):**
`sim/validation/cases/cfast_slow_growth_sealed.json` contiene `"fire_co_yield_force_kg_per_MJ": 0.0003`.
Esto activa el bloque en `CombustionSystem.gd` líneas 705–707:
```
var co_yield_force = context.get("fire_co_yield_force_kg_per_MJ", -1.0)
if co_yield_force >= 0.0:
    co_yield = co_yield_force   # ← bypasses ALL phi-scaling unconditionally
```
Resultado: yield fijo 0.0003 kg CO/MJ a todo phi (phi=1.0 hasta phi=3.6), confirmado por CSV: `yld_co = co_gen/fuel_step ≈ 0.000300` constante en todo tiempo. Esto es **intencional**: el comentario en CombustionSystem indica que CFAST usa CO_YIELD fijo por kg combustible sin escalar con equivalence ratio. Sin esta capa, el yield phi-escalado a phi=2.79 sería `0.0003 * exp(2.0*(2.79-1)) ≈ 0.0108 kg/MJ` — 36× mayor.

**Capa 2 — Default `co_base_yield` = 0.0 (brecha arquitectónica silenciosa):**
`CombustionSystem.gd` línea 663: `context.get("co_base_yield_kg_per_MJ", 0.0)` — default 0.0.
Casos sin `co_base_yield_kg_per_MJ` explícito y sin fuel objects con `co_yield_kg_per_MJ > 0` generan CO = 0 kg silenciosamente. El default `FuelObjectModel.co_yield_kg_per_MJ = 0.00025` es muy bajo (nivel CFAST), no SFPE.

**Capa 3 — Clamp invertido cuando `co_max_yield` = 0.0 (default):**
`CombustionSystem.gd` líneas 665–671:
```
var co_max_yield = context.get("co_max_yield_kg_per_MJ", 0.0)   # default 0.0
co_yield = clampf(
    co_base * exp(k * (phi - 1)),
    co_base,       # min
    co_max_yield   # max = 0.0
)
```
`clampf(value, 0.05, 0.0)` en GDScript = `max(0.05, min(0.0, value))` = `max(0.05, 0.0)` = 0.05 → phi-scaling queda fijo en `co_base` incluso si phi >> 1. Solo cuando `co_max_yield > co_base` el scaling funciona. El único caso con ambos correctamente seteados es `ghanekar_kitchen_living_room.json` (`co_base=0.00015`, `co_max=0.0075`).

#### Estado del escalado phi→CO en el motor

El escalado phi→CO **está implementado correctamente** en `CombustionSystem.gd` (fórmula `co_base * exp(k*(phi-1))`, k=2.0, phi from `o2_hrr_factor`). El motor produce el yield correcto cuando las condiciones de uso son satisfechas:
1. `co_base_yield_kg_per_MJ > 0` en engine_overrides (o fuel objects con `co_yield_kg_per_MJ > 0`)
2. `co_max_yield_kg_per_MJ > co_base_yield` (estrictamente mayor)
3. `fire_co_yield_force_kg_per_MJ` NO seteado (default -1.0)

#### Propuesta Plan A — Fases (pendiente implementación)

**Fase A1 — Caso físico-realista sin force override:** *(COMPLETADO 2026-06-30)*

Caso creado: `sim/validation/cases/wood_vc_reference.json`
- `co_base_yield_kg_per_MJ: 0.004` (SFPE Tewarson wood, bien ventilado)
- `co_max_yield_kg_per_MJ: 0.10` (cap VC severo)
- `fire_co_phi_rate: 2.0` (default)
- Sin `fire_co_yield_force_kg_per_MJ`
- `fire_alpha_kw_s2: 0.003`, `fire_max_hrr_kw: 800.0`, selllado, 1800s

Resultados (simulación 2026-06-30):
- **D2 primer WARN: t=710s** — ratio=0.5123, regime=`VENTILATION_CONTROLLED_BURNING`, phi=3.45, yld_co=0.04554 kg/MJ ✓
- Ratio D2 escala de 0.51 (t=710s) hasta 2.13 (t=1790s) — crece conforme CO₂ mass decae y CO acumula.
- `yld_co` se estabiliza en ~0.04563 kg/MJ en régimen VC (cap por co_max_yield=0.10 vía clamp, phi >> 1 → raw yield escapa, clampado).
- D2PRE también activo (74 WARNs) — M1 o2_scale double-throttle también opera en este caso (esperado).
- Audit suite: **0 FAIL, 13 PASS, 2 WARN, 2 CTRL** — sin regresiones.

Diferencia vs `cfast_slow_growth_sealed`:

| Caso | phi a t=710s | yld_co (kg/MJ) | D2 ratio | D2 fires |
|------|-------------|----------------|----------|----------|
| cfast_slow_growth_sealed | 2.79 | 0.000300 (forzado) | 0.008 | NO |
| wood_vc_reference | 3.45 | 0.045541 | 0.512 | **SÍ** |

**Conclusión Fase A1:** El motor phi→CO scaling funciona correctamente con co_base=0.004, co_max=0.10, sin force override. D2 dispara a t=710s en VENTILATION_CONTROLLED_BURNING, confirmando que la regla es funcional para casos físico-realistas.

**Fase A2 — Análisis de impacto defaults CO yield** *(diagnóstico completado 2026-06-30)*

#### Hallazgo A2-1 — Los defaults están en SimulationEngine.gd, no en FuelObjectModel

El campo `FuelObjectModel.co_yield_kg_per_MJ = 0.00025` es efectivamente **irrelevante** para el corpus actual:
- `_has_explicit_fuel_objects()` devuelve `false` para todos los 106 casos (ningún caso define `fuel_objects` explícito en JSON — todos usan legacy room proxy).
- Cuando no hay fuel objects explícitos, `_resolve_room_co_yield_kg_per_MJ` retorna `fallback_yield = context.get("co_base_yield_kg_per_MJ", ...)` — que viene del **motor** (`SimulationEngine.gd:327`), no de FuelObjectModel.
- Los defaults reales son: `SimulationEngine.co_base_yield_kg_per_MJ = 0.00025` y `SimulationEngine.co_max_yield_kg_per_MJ = 0.01250`.

#### Hallazgo A2-2 — Los defaults del motor SON los valores SFPE para madera

Los valores actuales del motor son físicamente correctos para madera (ISO 19706 / SFPE Handbook Tewarson):
- `co_base = 0.00025 kg/MJ` = 0.004 kg/kg ÷ 16 MJ/kg (yield FC, madera bien ventilada) ✓
- `co_max = 0.01250 kg/MJ` = 0.200 kg/kg ÷ 16 MJ/kg (yield VC extremo, madera) ✓
- phi-scaling YA activo para todos los casos plain (co_base > 0, co_max > co_base).

#### Hallazgo A2-3 — D2 threshold (0.5) nunca se alcanza con madera SFPE

Con los defaults actuales, el máximo ratio molar CO/CO₂ para madera es:
- phi → inf: `clampf(0.00025*exp(k*(phi-1)), 0.00025, 0.01250)` → 0.01250 kg/MJ (cap)
- Molar ratio = (0.01250/28) / (0.0831/44) = **0.236 < 0.5** — por debajo del threshold siempre.
- Para disparar D2 a phi=2: se necesita `co_base ≥ 0.00358 kg/MJ` → equivale a `0.057 kg/kg fuel` (14× el valor SFPE de madera FC).
- `wood_vc_reference` usa `co_base=0.004, co_max=0.10` — corresponde a `0.064 kg/kg FC` (16× SFPE). Son valores de combustibles mixtos/PU, no madera pura.

#### Hallazgo A2-4 — Inventario de casos por riesgo de cambio global

| Categoría | Nro casos | Risk si se cambian defaults motor | Detalle |
|-----------|-----------|----------------------------------|---------|
| CFAST (force override) | 23 | NINGUNO | `fire_co_yield_force` bypasses todo |
| co_base+co_max explícitos | 2 | NINGUNO | `ghanekar`, `wood_vc_reference` |
| co_base solo (clamp invertido) | 1 | BAJO | `c_balance_high_phi` — phi-scaling bloqueado anyway |
| Plain (engine defaults) | 81 | **ALTO** | CO escalaría ~16× si se sube co_base de 0.00025→0.004 |
| Sin baseline CO checks (non-CFAST) | 81 | Cero impacto en PASS count | No hay checks CO en non-CFAST |
| Con CO checks en validate_reference_cases | 0 non-CFAST | N/A | Todos están en funciones CFAST |

FED CO impacto si co_base global sube de 0.00025 → 0.004 (16×):
- CO ppm en FC room ~16×: de ~100 ppm → ~1600 ppm. FED CO contribution 16× mayor.
- Todos los escenarios de entrenamiento mostrarían CO mucho más alto que madera real.
- Suite 349/354 PASS conteo sin cambio (no hay CO checks non-CFAST), pero los valores físicos serían incorrectos para madera.

#### Recomendación A2 — Tres opciones, ninguna es "cambiar defaults globales a madera 0.004"

**Opción 1 (Recomendada) — Bajar threshold D2 a ~0.20:**
- Con SFPE wood y phi=3+, el ratio real es ~0.236. Threshold 0.20 lo capturaría.
- Fundamento: "CO supera 20% de CO₂ en moles" ya indica fuego severamente sub-ventilado.
- Riesgo: D2 dispararía en muchos más plain cases (cualquier sealed VC con phi≥3).
- Impacto suite: más D2 WARNs en corpus, exit code 0 sin cambio, CFAST inmune (force).

**Opción 2 — Introducir caso `pu_foam_vc_reference.json` con yields PU:**
- PU foam FC: ~0.001 kg/MJ, VC max: ~0.006 kg/MJ → D2 ratio at phi=3 ≈ 0.44 (cerca del threshold).
- Para PU foam VC severo: co_base=0.002, co_max=0.03 → D2 fires a phi~2.
- Mantiene engine defaults sin cambiar. Documenta que D2 es para escenarios de PU foam VC.
- Riesgo: ninguno para suite actual.

**Opción 3 — Mantener wood_vc_reference como único caso D2 + documentar:**
- D2 es una regla diagnóstica, no gating. No necesita disparar en todos los casos VC.
- Documentar explícitamente: D2 captura escenarios de alta producción CO (fuel mixto, PU foam severo, post-FO). Para madera pura, el ratio máximo es ~0.24 — la regla D2 no es redundante, es conservadora.
- No se necesita ningún cambio de motor o defaults.
- Opción más segura para esta fase.

#### Qué NO hacer en Fase A2
- NO cambiar `SimulationEngine.co_base_yield_kg_per_MJ` de 0.00025 a 0.004 globalmente (físicamente incorrecto para madera, FED CO 16× inflado).
- NO cambiar `FuelObjectModel.co_yield_kg_per_MJ` (irrelevante para corpus actual).
- NO regenerar baselines antes de decidir la estrategia de umbral D2.

#### Próximo paso recomendado (post-A2)

~~Implementar **Opción 1** (bajar threshold D2)~~ — DESCARTADO por datos de Sesión 4. Ver análisis de sensibilidad abajo.

---

### Plan A Sesión 4 — Análisis de sensibilidad D2 threshold (2026-06-30)

**Objetivo:** Medir max D2 ratio y cruces de umbral (0.10/0.20/0.30/0.50) en todos los casos con `co2_upper_ppm_mass`. Corregir la recomendación A2 basándose en datos medidos, no en estimación teórica.

**Caso diagnóstico creado:** `tmp_d2_sensitivity_engine_defaults.json` — sellado 1800s, engine defaults, sin pool release. Controla la variable: mide el máximo alcanzable por phi-scaling puro.

#### Tabla de sensibilidad D2 (9 casos con co2_upper_ppm_mass)

| Caso | CO yield config | max phi | max yld_co | max D2 | ≥0.10 | ≥0.20 | ≥0.50 |
|---|---|---|---|---|---|---|---|
| cfast_slow_growth_sealed | FORCE=0.0003 | 3.60 | 0.00032 | 0.0077 | never | never | never |
| fuel_balance_diag_sealed | engine def | 1.06 | 0.01098 | 0.2465 | 135s | 175s | never |
| o2_stoich_diag_sealed | engine def | 1.06 | 0.01098 | 0.2465 | 135s | 175s | never |
| v1_backdraft_accumulation (CTRL) | engine def | 1.17 | 0.01193 | 0.2529 | 135s | 160s | never |
| **tmp_d2_sensitivity_eng_def** | **engine def, 1800s sellado** | 8.24 | 0.01301 | **0.2982** | 580s | 870s | **never** |
| v5_m4_ventilation_throttle | eng + pool_release=0.18 | 8.38 | 0.03577 | **0.6184** | 135s | 145s | **225s** |
| tmp_v1_backdraft_accum_m4 | eng + pool_release | 7.87 | 0.03577 | **0.5661** | 135s | 155s | **285s** |
| v1_m4_pool_release (CTRL) | eng + pool_release | 10.00 | 0.03577 | **0.7997** | 135s | 155s | **285s** |
| wood_vc_reference | base=0.004, max=0.10 | 8.24 | 0.04563 | **2.1388** | 550s | 600s | **710s** |

#### Hallazgos S4-1 — Bifurcación pool release

- **Sin pool release, SFPE wood engine defaults, phi→8.24 (1800s sellado):** max ratio = **0.2982**. NUNCA alcanza 0.30 ni 0.50.
- **Con pool release activo:** `yld_co` alcanza 0.03577 kg/MJ (2.84× cap co_max=0.01250). CO del pool de gases no quemados no está sujeto al phi-scaling cap. Ratio alcanza 0.566–0.800 con madera engine defaults.
- La estimación teórica A2 (max=0.236, phi→inf, phi-scaling puro) era correcta. Pool release es un mecanismo independiente que genera CO por encima del cap.

#### Hallazgo S4-2 — Threshold 0.50 ya operacional

D2 threshold 0.50 detecta correctamente:
1. **Pool release CO bursts** — v5_m4_ventilation_throttle (225s), tmp_v1_backdraft (285s), v1_m4_pool_release/CTRL (285s).
2. **Combustibles mixtos/sintéticos** — wood_vc_reference co_base=0.004 (710s).
3. **NO dispara** para VC limpio de madera SFPE sin pool release (max 0.2982 < 0.50). Correcto.

#### Hallazgo S4-3 — Riesgo de bajar threshold a 0.20

Si threshold baja a 0.20, dispararía en `fuel_balance_diag_sealed` y `o2_stoich_diag_sealed` a t=135–175s. Estas WARNs serían de room=1 (non-fire room) por asimetría M3 init — artefacto diagnóstico sin valor físico. Ruido innecesario.

#### Hallazgo S4-4 — v5_m4_ventilation_throttle genera D2 WARNs

`v5_m4_ventilation_throttle` tiene 13 D2 WARNs actualmente (ratio pico 0.6184, t=225s, `pool_release_max_fraction=0.18`). El caso NO está en CTRL. Las WARNs son físicamente reales (CO burst ventilation-induced). **Pendiente: agregar a CTRL en sesión futura con plan explícito.**

#### Recomendación S4 — REVISADA (corrige A2)

**Opción 3 — Mantener threshold 0.50. No cambiar.** Razones:
1. El threshold 0.50 detecta pool-release CO bursts y combustibles mixtos — exactamente los escenarios de CO extremo que D2 debe capturar.
2. Bajar a 0.20 introduce ruido en casos diagnósticos (t=135s, room no-fire).
3. Para VC limpio de madera SFPE (no pool release), max ratio = 0.298 — no hay alarma física justificada.
4. `wood_vc_reference` valida que D2 funciona para combustibles de alto CO yield.

**Qué NO tocar:**
- `cfast_slow_growth_sealed.json`: force override 0.0003 intencional. No eliminar.
- `CombustionSystem.gd` phi-scaling: correcto. No modificar.
- D2 threshold (0.5): calibrado correctamente para escenarios extremos. **No cambiar.**
- Plan B (OES o2_scale): independiente. No tocar.

**Pendiente (sesiones futuras):**
- ~~Agregar `v5_m4_ventilation_throttle` a CTRL~~ — **COMPLETADO (rev 33).**
- ~~Revisar D2PRE en room=1 de fuel_balance_diag_sealed / o2_stoich_diag_sealed~~ — **DIAGNOSTICADO (rev 34). Ver abajo.**

#### wood_vc_reference — CTRL añadido (2026-06-30, rev 34)

Añadido a `KNOWN_INTENTIONAL_CONTROLS`. Caso referencia canónico D2: diseñado en Plan A Fase A1 con `co_base=0.004 kg/MJ`, `co_max=0.10`. 114 D2 WARNs (t=710–1800s, ratio 0.51→2.14) + 74 D2PRE WARNs (M1 colateral). Todos esperados.

#### fuel_balance_diag_sealed / o2_stoich_diag_sealed — D2PRE diagnóstico (2026-06-30, rev 34)

230 D2PRE WARNs en cada caso (rooms 0–5, t=60–300s). Análisis:
- Room 0 (13/caso): M1 o2_scale en fire room — misma causa que cfast_slow_growth_sealed.
- Rooms 1–5 (217/caso): tracer CO₂ (400–1100 ppm) << mass CO₂ (4000–21000 ppm) desde t=60s. El ThermalSystem transporta CO₂ mass entre rooms más rápido que el tracer OES puede seguir (M1 suprime tracer en room 0, reduciéndolo también en rooms adyacentes por transporte).
- **Decisión: dejar como WARN.** Documentan el alcance de Plan B en escenarios multi-room. No son controles intencionales.

#### Estado audit suite final (2026-06-30)

**9 PASS / 5 CTRL / 3 WARN / 0 FAIL.** Los 3 WARN son todos D2PRE (Plan B): `cfast_slow_growth_sealed`, `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`. Sin FAILs. Sin cambios de motor ni thresholds.

#### v5_m4_ventilation_throttle — CTRL añadido (2026-06-30)

Diagnóstico completo de 13 D2 WARNs: todos en room=0, t=225–600s, ratio 0.51–0.62. Causa: M4 throttle cíclico → ILV_LATENT → `retained_unburned_MJ` acumula 0.12–0.17 MJ → pool release CO burst cada ~45s. `fire_pool_release_max_fraction=0.18`, `fire_secondary_hrr_gain_kw=2500`. WARNs son consecuencia directa del mecanismo M4 bajo prueba — clasificados CTRL.

**Audit state final:** 9 PASS / 4 CTRL / 4 WARN / 0 FAIL. Exit code 0.

#### Referencia SFPE vs simulación actual

| Régimen | phi | SFPE wood CO yield | SimuFire cfast_sealed | D2 ratio molar |
|---------|-----|---------------------|----------------------|----------------|
| FC | 1.0 | ~0.004 kg/MJ | 0.0003 (forced) | 0.006 |
| VC leve | 1.5 | ~0.010 kg/MJ | 0.0003 (forced) | 0.007 |
| VC | 2.0 | ~0.020 kg/MJ | 0.0003 (forced) | 0.008 |
| VC severo | 2.8 | ~0.040 kg/MJ | 0.0003 (forced) | 0.008 |
| Threshold D2 | — | — | ~0.027 kg/MJ needed | **0.5** |

- **Motivación:** CO/CO₂ generación masa ~0.004–0.005 constante en `cfast_slow_growth_sealed`, incluso en VENTILATION_CONTROLLED_BURNING con o2_upper=0.063. Referencia SFPE/Tewarson para wood phi~2: yield CO ~0.02–0.04 kg/MJ → ratio masa ~0.24–0.48 → ratio molar ~0.38–0.75. El threshold D2 de 0.5 molar nunca se alcanzará hasta que CombustionSystem escale correctamente el CO yield con phi.
- **Impacto en D2:** Sin Plan A Fase A1, la regla D2 nunca disparará en condiciones VC — funciona como guardia de casos extremos (post-FO con CO anomalamente alto) pero no captura subventilación gradual.

**Plan B — Fix motor: eliminar o2_scale double-throttle en OES tracer CO₂** *(prioridad: baja, no urgente)*

- **Motivación:** `OxygenExchangeSystem` aplica `o2_scale = o2_upper/0.209` a la producción de CO₂ tracer. El HRR ya incorpora throttle de O₂ (régimen VENTILATION_CONTROLLED). El o2_scale duplica la supresión, causando la divergencia D2PRE (ratio mass/tracer = 2.56× a t=700s).
- **Fix propuesto:** Eliminar la línea `co2_produced *= o2_scale` en OES (o moverla a un flag per-case opt-in). La producción de CO₂ tracer pasaría a ser proporcional al HRR directamente, sin throttle adicional.
- **Impacto en D2PRE:** El tracer se aproximaría al mass path, reduciendo/eliminando los 243 WARNs en `cfast_slow_growth_sealed`. Podría promover D2PRE de WARN a PASS en ese caso.
- **Impacto en FED:** El tracer CO₂ se usa en `compute_co2_upper_ppm` → FED CO₂ narcosis. Eliminar o2_scale aumentaría la contribución FED de CO₂ en condiciones VC. Requiere validación FED antes de activar.
- **Precondición:** Plan explícito motor ("No tocar sim/core sin plan explícito"). Requiere sesión dedicada: leer OES, confirmar que HRR ya refleja O₂, estimar impacto FED, proponer test cases.
- **Constraint:** No implementar globalmente — usar flag per-case como M4/M5 hasta que el corpus valide el comportamiento.

## 4. Smoke And Soot

Items to check:

- Smoke/soot generation against HRR, fuel and regime.
- Smoke transport conservation between rooms and layers.
- Coupling between smoke movement, CO movement and hot-layer transport.
- Smoke cooling over time when HRR falls.
- Smoke descent when cooled gases lose buoyancy and there is room below the hot layer.
- Relationship among `smoke_kg`, `visibility_m`, layer heights and ventilation.

Open gaps:

- Soot-yield validation.
- Cooling/descent validation.

Current auditor coverage:

- S0: global smoke conservation is FAIL-gating. Invariant:
  `Σ smoke_kg + smoke_in_transit_kg ≈ smoke_generated_total_kg - smoke_vented_total_kg - smoke_deposited_total_kg`.
- Fresh corpus result: 11/11 CSVs PASS, 0 S0 findings; 9 CSVs have the fresh S0 schema and 2 legacy `p2h_diag_*` CSVs skip gracefully.
- S0 closure fixed missing smoke accounting in ACH/infiltration removal and natural-ventilation purge, exposed `smoke_in_transit_kg` for delayed interior deliveries, and stopped `SmokeModel.recompute_layer_from_mass()` from zeroing sub-threshold smoke mass.
- Limitation: S0 is global. It can miss compensated inter-room transport errors; S1 closes the local balance per room.

### S1 Smoke per-room balance — CLOSED AS FAIL/GATING (2026-06-30)

S1 validates per room/log interval:

```text
delta(smoke_kg) = delta(smoke_generated_kg_total)
                - delta(smoke_vented_kg_total)
                - delta(smoke_deposited_kg_total)
                + delta(smoke_net_transport_kg_total)
```

Per-room accumulators (`smoke_generated_kg_total`, `smoke_vented_kg_total`, `smoke_deposited_kg_total`, `smoke_net_transport_kg_total`) already existed in `RoomModel.gd`, are populated by `GasExchangeSystem` and `ThermalSystem`, exported via `SimulationStateBuilder`, and present in the CSV header — no GDScript changes were needed.

Status:

- S1 implemented in `scripts/simulation/check_physics_coherence.py` as **WARN** (observation phase).
- Tolerance: 5 % of abs(expected), floor 0.01 kg — same as S0.
- Tests: 5 tests in `TestCheckS1` — all PASS (perfect balance, net transport, gap triggers WARN, legacy skip, reason format).
- Corpus audit (2026-06-30): **14 PASS / 0 WARN / 0 FAIL** across all active cases. `v1_backdraft_accumulation` is CTRL (expected A3/O2E1 findings; S1 is clean there too).
- Corpus audit (2026-06-30, C-S1-3): **15 PASS / 0 WARN / 0 FAIL** after adding `cfast_two_floor_stairwell`. Inter-floor transport confirmed: `Escalera P1` (room 6) 0.101 kg, `Distribuidor P1` (room 7) 0.138 kg, dormitorios P1 0.021–0.026 kg — all above 0.01 kg floor. C-S1-3 satisfied. C-S1-5 satisfied (no compensated residuals in multi-floor run).
- Graceful skip: CSVs without S1 columns (older schema) skip silently.
- S1 promoted to **FAIL/gating** (2026-06-30) after C-S1-1 through C-S1-6 satisfied. Severity changed from `"WARN"` to `"FAIL"` in `_check_s1_smoke_per_room_balance`. No tolerance changes.

Required columns: `smoke_kg`, `smoke_generated_kg_total`, `smoke_vented_kg_total`, `smoke_deposited_kg_total`, `smoke_net_transport_kg_total`.

### S1 promotion criteria (WARN → FAIL/gating)

The following criteria must all be met before S1 can be promoted. Do not promote without evidence for each item.

**C-S1-1 Sustained clean corpus.**
Current corpus (14 cases) must remain 0 WARN / 0 FAIL on every re-run after any motor change. A single regression must be investigated and resolved before promotion proceeds.

**C-S1-2 Multi-room smoke transport coverage.**
At least one permanent case must exercise active inter-room smoke transport (doorway or stairwell smoke flow between two or more rooms) and exit S1-clean. The current corpus includes `cfast_two_room_door_open`, `living_room_hallway`, and several multi-room apartment cases — verify these have non-trivial `smoke_net_transport_kg_total` values before crediting them. If all rooms in those cases have `smoke_net_transport_kg_total ≈ 0`, add or modify a case to exercise the transport path.
**Status (2026-06-30): ✅ CUBIERTO** — `cfast_two_room_door_open`: room 0 emite 5.43 kg, rooms 1–5 reciben 0.19–0.21 kg c/u. S1 exit 0.

**C-S1-3 Multi-floor smoke transport coverage.**
At least one permanent case must exercise smoke transport between floors (stairwell or vertical opening) and exit S1-clean. `cfast_two_floor_stairwell` is the candidate; confirm it has non-zero per-room transport totals.
**Status (2026-06-30): ✅ CUBIERTO** — `cfast_two_floor_stairwell` (13 rooms, PB + P1): `csv_log_file_path` añadido al caso JSON. S1 exit 0. Inter-floor transport: Escalera PB→P1 chain: Escalera P1 (room 6) 0.101 kg, Distribuidor P1 (room 7) 0.138 kg, dormitorios P1 0.021–0.026 kg. Todos ≥ 0.01 kg floor. Corpus: 15 PASS / 0 WARN / 0 FAIL.

**C-S1-4 Non-trivial deposition and venting coverage.**
At least one permanent case must have measurable `smoke_deposited_kg_total > 0` and at least one must have measurable `smoke_vented_kg_total > 0` — not just edge-of-zero values that are dominated by the floor (0.01 kg). Existing venting cases (window/door open scenarios) likely cover the venting criterion; deposition may need explicit verification.
**Status (2026-06-30): ✅ venting CUBIERTO / ⚠️ deposition LIMITACIÓN DE ESCALA** — Venting: `fp_ilv_open_partial_window` (45.97 kg), `cfast_slow_growth_sealed` (15.87 kg), `cfast_two_room_door_open` (1.97 kg). Deposition: max 0.002 kg en todos los casos activos — por debajo del floor S1 de 0.01 kg. Fisicamente plausible (soot settling bajo en escenarios cortos). Un error del 100% en el acumulador `smoke_deposited_kg_total` sería invisible a S1 a esta escala. Limitación conocida de floor precision; no es un gap de instrumentación. No bloquea promoción — deposition no es ruta dominante en los escenarios actuales.

**C-S1-5 No compensated inter-room residuals.**
After adding multi-room transport coverage (C-S1-2 and C-S1-3), confirm that S1 finds 0 WARN even in cases where S0 could have masked a compensated error. This is the main value S1 adds over S0 — if S1 stays clean after these cases are confirmed to have non-zero transport, compensation errors are ruled out.
**Status (2026-06-30): ✅ CUBIERTO** — `cfast_two_room_door_open` (multi-room, 5.43 kg transport) y `cfast_two_floor_stairwell` (multi-floor, 0.101–0.138 kg inter-floor) ambos salen S1 exit 0 sin WARNs. Errores compensados descartados en rutas de transporte no triviales.

**C-S1-6 No tolerance change without evidence.**
The current 5 % / 0.01 kg tolerance must not be widened to achieve a clean corpus. If C-S1-1 through C-S1-5 produce residuals above the floor, investigate the root cause; do not raise the floor.

**Procedure when all criteria are met:**
1. Change `severity="WARN"` to `severity="FAIL"` in `_check_s1_smoke_per_room_balance`.
2. Update the S1 entry in `REQUIRED_COLS` documentation and module docstring.
3. Re-run the full corpus audit and confirm 0 FAIL.
4. Update this checklist, CHANGELOG, and HANDOFF to record the promotion date and corpus result.

## 5. Smoke Height, Layer Interfaces And Neutral Plane

Items to check:

- `smoke_layer_m`, `thermal_layer_m`, `visible_smoke_layer_m`, `flow_interface_m` and `hot_layer_m`.
- Neutral plane height.
- `layer_150c_m` / 150 C isotherm.
- Layer response to window and door changes.
- Layer response in multi-room and multi-floor fires.
- Directional interpretation: thermal and optical layer heights should not be blindly compared with `abs()` until conventions are confirmed.

Current B3 probe result:

- Existing corpus is too small to calibrate `abs(thermal_layer_m - smoke_layer_m)`.
- One transient outlier at 0.135 m appears physically legitimate.
- Do not implement B3 yet; revisit after a richer CSV corpus exists.

## 6. Visibility

Items to check:

- `visibility_m` derived from smoke/soot concentration, not from presentation-layer effects.
- Visibility degradation with smoke mass and layer position.
- Visibility recovery under ventilation/dilution.
- Consistency with FED, smoke layer and thermal state.

Open gaps:

- Need motor-side validation only; do not rely on first-person overlay behavior.
- Need scenarios where visibility curves can be compared against reference expectations.

## 7. FED And Tenability

Items to check:

- `fed = fed_co + fed_hcn + fed_hypoxia + fed_heat`.
- FED monotonicity.
- FED components correspond to CO, HCN, O2 and thermal conditions.
- Irritant FEC/HCl behavior where applicable.
- Long-duration accumulation behavior.

Current auditor coverage:

- C1: FED arithmetic.
- C2: FED monotonicity by room.

Open gaps:

- FED component magnitude validation against gas and temperature histories.
- HCN/FED coupling validation.

## 8. Temperatures

Items to check:

- `temp_upper_c` and `temp_lower_c` against HRR, ventilation, wall losses and layer height.
- No strong impossible inversion under active hot-layer conditions.
- Cooling after HRR decay.
- Temperature response to reventilation.
- Consistency with FED heat and 150 C isotherm.
- Consistency with wall temperature and wall reradiation.

Current auditor coverage:

- B1: strong thermal inversion.

Open gaps:

- Full energy balance.
- Cooling curves.
- Temperature response to remote ventilation and multi-room flows.

## 9. Two-Zone Model

Items to check:

- Upper/lower mass and energy storage.
- Upper/lower oxygen and gas species routing.
- Layer exchange and entrainment.
- Buoyancy: hot gases and smoke rise; cooler gases tend to descend or mix.
- Coupling between combustion, plume, hot layer and lower-layer oxygen.
- Stability over long fires.

Open gaps:

- Canonical two-zone mass and energy balance per layer.
- Explicit validation of two-zone flow equations against CFAST-like behavior.

Current Phase 3+ direction (2026-07-12):

- F0/F2 diagnostics are in place and should be kept passive.
- F2.1 ledger-aware projection and local pressure fixes are closed as NO-GO.
- Next implementation target is F3.0 shadow canonical two-zone state, default OFF:
  pre-step snapshot + explicit flux requests + shadow transaction + residuals.
- `project_room_state()` must not be changed into another compensating mass
  source. In the canonical path it should become derivation/validation only.
- See `docs/validation/PHASE3_CANONICAL_TWO_ZONE_ARCHITECTURE.md`.

## 10. Doors, Windows And Ventilation

Items to check:

- Partial door/window opening effects.
- Bidirectional flow through vertical openings.
- Upper hot-gas outflow and lower fresh-air inflow.
- Remote window effects through connected rooms.
- Multi-room and multi-floor convection paths.
- Pressure-driven direction and magnitude of flows.
- Reventilation and fire growth after opening changes.

Open gaps:

- Broad CFAST battery for opening fractions and remote ventilation.
- Multi-floor validation.
- Door/window transient validation.

## 11. Pressure

Items to check:

- `pressure_pa_therm` and `overpressure_pa` accumulation.
- Pressure by layer at a coarse two-zone level.
- Flow direction from pressure differences.
- Neutral plane calculation.
- Pressure response to fire growth, ventilation and cooling.

Recent lesson:

- A regression that reset `pressure_pa_therm` each step caused `cfast_closed_t120_pressure_pa` to fail. Pressure must be treated as a core validation signal, not an auxiliary output.

Open gaps:

- Coarse two-zone pressure ODE validation.
- Neutral plane validation.

Current pressure decision:

- F2.2a pressure diagnostics are accepted as passive instrumentation.
- Do not implement another pressure-vent patch before canonical zone inventory
  exists. The legacy path mixes gas mass, smoke-particle stock and EOS backfill;
  patching any one term locally can double-count venting or collapse lower gas.

## 12. Walls, Radiation And Heat Storage

Items to check:

- Radiative and convective absorption by walls.
- Wall heat capacity and saturation.
- Wall reradiation into rooms after saturation or HRR decay.
- Energy conservation among HRR, gases, walls, ventilation and residual terms.
- `wall_T_mid_c`, `bud_q_rad_kj`, `bud_de_upper_kj`, `bud_q_residual_kj`, `bud_chi_rad`.

Open gaps:

- Full wall heat budget validation.
- Long-fire wall reradiation curves.

## 13. Validation Battery

Required scenario families:

- Sealed single-room fires.
- Single-room with partial window openings.
- Door-open two-room fires.
- Remote window opened in a connected room.
- Multi-room corridor chains.
- Multi-floor convection cases.
- Long fires with cooling and wall reradiation.
- Reventilation cases.
- Toxic gas transport cases.
- Smoke/visibility cases.
- Pressure/neutral-plane cases.

Reference strategy:

- Compare against CFAST where possible.
- Use documented realistic scenarios where CFAST is not enough.
- Compare curves, not only point checks.
- Keep legacy/control cases separate from physical validation cases.
- Do not calibrate expected behavior around known bugs.

## 14. Instrumentation Backlog

High priority:

- F3.0 shadow canonical request ledger:
  gas mass, enthalpy, O2 and species per request, with source/destination zone,
  cause and ownership.
- Per-step local gas generation: `co_generated_kg`, `co2_generated_kg`, `hcn_generated_kg`.
- Per-step gas transport in/out by room: at least CO first.
- Carbon budget fields in CSV: `c_balance_frac`, `carbon_conservation_error_kg`.
- O2 consumed per room/step.
- Fuel energy consumed per room/step.
- Layer mass and energy terms in CSV for selected diagnostic cases.

Medium priority:

- Smoke generated and transported per step.
- Species exterior loss per step.
- Wall heat in/out per step.
- Neutral plane height.
- Door/window bidirectional flow components.

## 15. Balance Lane Closure Status (2026-06-29)

Active FAIL-gating rules in `scripts/simulation/check_physics_coherence.py`:

| Lane | Rule | Invariant | Corpus | Status |
|------|------|-----------|--------|--------|
| S0 | Smoke global conservation | Σroom smoke_kg + in_transit = generated − vented − deposited | 14/14 PASS | ✅ FAIL/gating |
| E1 | Fuel balance | Δsolid_fuel_remaining_MJ = −Δfuel_consumed_MJ_total | 14/14 PASS | ✅ FAIL/gating |
| D1 | CO balance | Δco_kg = Δco_generated − Δco_exterior + Δco_transport | 14/14 PASS | ✅ FAIL/gating |
| O2E1 | Thornton HRR↔O2 | Δo2_consumed_fire = Δhrr_kj × 7.6e-5 kg/kJ | 14/14 PASS | ✅ FAIL/gating |
| O1 | O2 bulk balance | Δo2_bulk = −Δcons + Δext + Δtrans + Δzsync | 14/14 PASS | ✅ FAIL/gating |
| S1 | Smoke per-room conservation | Δsmoke_kg = Δgenerated − Δvented − Δdeposited + Δtransport | 15/15 PASS before CTRL classification | ✅ FAIL/gating |
| D2 | CO/CO2 upper ratio | co_upper_ppm / co2_upper_ppm_mass > 0.50 | Diagnostic corpus only | WARN diagnostic, not gating |

Other active rules (not balance lanes): B1 (thermal inversion), C1 (FED arithmetic), C2 (FED monotonicity), A2 (HRR without fuel), A3 (regime/O2 mismatch).

Diagnostic / planned lanes:

| Lane | Status |
|------|---------|
| D2PRE CO2 tracer-vs-mass | WARN diagnostic. Remaining WARNs document Plan B scope: `cfast_slow_growth_sealed`, `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`. |
| Plan B CO2 tracer/OES | Pending motor plan. Root cause: `o2_scale` double-throttle in OES tracer CO2; do not change without FED impact validation. |
| HCN / D3-D5 toxic gas checks | Pending future instrumentation/rule design. |

## 16. Current Priority Order (2026-07-26)

1. Keep guardrails, physics coherence and ILV at 0 FAIL.
2. Retain F3.3v3f1 as passive, default-OFF telemetry. It preserves gross
   doorway flow and matches CFAST net enthalpy, but is not authoritative.
3. Diagnose the 79 R0 directional cap events: time, requested pressure net
   and available base counterflow. **Closed F3.3v3f2:** the cap changes the
   signed integral from requested `+1.173 kg` to accepted `-1.950 kg`.
4. **Closed F3.3v3f3, NO-GO:** direct dynamic replacement creates explicit
   positive feedback. Caps rise `79 -> 1676`, requested pressure transport
   `6.368 -> 804.659 kg`, and lower shadow gas collapses to zero.
5. Preserve the isolation proof: 114/114 rows and all 115 non-shadow fields
   are identical. The failed motor candidate is reverted.
6. Design F3.3v3g0 before more motor work: an implicit or under-relaxed
   connected-room pressure solve with antisymmetric flow, inventory bounds
   and explicit convergence/rollback criteria.
7. **Closed F3.3v3g1:** the pure network relaxation primitive is dormant and
   fails closed. **Closed F3.3v3g2:** the passive default-OFF preview wires it
   per connected component using the raw pressure demand. It descends the
   objective at every one of 2160 steps, closes mass, energy, O2 and species
   at exactly zero, collapses no occupied zone and leaves all 838 shared CSV
   columns byte-identical.
8. Retain the F3.3v3g2 measurement: the binding limiter is the pressure-sign
   crossing bound (2008 steps), not the source inventory (0 steps). Extra
   inventory alone would not increase accepted transport.
9. **Closed F3.3v3g3, NO-GO:** driving the persistent canonical shadow with
   those blended routes is atomically exact but physically unstable. The
   crossing bound stops binding exactly when the imbalance grows, `alpha`
   reaches `1.0`, doorway counterflow collapses to one-way flow and shadow
   pressure diverges `5.65x` from baseline by 30 s. The experimental runtime
   candidate was fully reverted; no g3 flag or application path remains.
   F3.3v3g2 is the current motor state.
10. **Closed F3.3v3h0, design GO:** the canonical EOS is exactly affine in
    room total mass and energy, so pressure owners superpose with no cross
    terms. Attribution closes to `1.37e-4 Pa` (CSV print precision). Plume and
    inter-zone heat are exactly pressure-neutral. Owners cancel by `273x` to
    `15612x`, which is why any subset solve - g3 included - is wrong at the
    sign level rather than merely imprecise.
11. Retain the F3.3v3h0 owner spectrum for R0, peak per 10 s interval:
    combustion `11701 Pa`, multisurface `7533 Pa` (still reported as `other`),
    interior_opening `3490 Pa`, interior_pressure `1973 Pa`,
    exterior `1776 Pa`, net `110 Pa`.
12. Do not retry direct route replacement, per-step clipping, static
    normalization over the old pressure trajectory, or the F3.3v3g3 candidate
    with a tuned under-relaxation factor. Any future candidate must reduce a
    residual that contains **every** pressure owner.
13. Group A and Group C remain VALID_GAP until an authoritative canonical
    slice passes required checks without tolerance or baseline relaxation.

## 17. Phase 3+ Doorway Transport Checkpoint (2026-07-26)

| Phase | Result | Decision |
|---|---|---|
| F3.3v3d | Pressure inventory closes; sign reversal is upstream of pressure route | Pressure tuning NO-GO |
| F3.3v3e | Opening-only enthalpy matches CFAST; pressure route adds churn | Fixed-gross architecture selected |
| F3.3v3f0 | Pure atomic fixed-gross skew primitive | Runtime-tested, dormant |
| F3.3v3f1 | Opt-in runtime preview, 21 CSV fields, exact OFF no-op | Shadow GO, authority NO-GO |
| F3.3v3f2 | 79-cap cumulative sign/magnitude ledger | Static cap authority NO-GO |
| F3.3v3f3 | Dynamic fixed-gross route replacement | Exact isolation, physical candidate NO-GO |
| F3.3v3g0 | Actual-route pressure-network design | Design GO; no runtime code |
| F3.3v3g1 | Pure pressure objective/relaxation primitive | Primitive GO; no runtime call |
| F3.3v3g2 | Passive per-component preview from raw pressure demand | Preview GO; authority and persistent shadow NO-GO |
| F3.3v3g3 | Experimental persistent shadow driven by the blended routes | Mechanism exact, physics NO-GO at 30 s; runtime candidate reverted |
| F3.3v3h0 | Coupled pressure/opening solver design plus owner attribution | Design GO; ready for H1; no motor code |
| F3.3v3h1 | Pure damped-Newton coupled pressure primitive | Primitive GO; no runtime call, no flag |
| F3.3v3h2 | Passive coupled-solver preview, one call site | Preview GO; authority NO-GO; 13.6% steps non-convergent |

F3.3v3f1 measured at 180 s:

- gross mass error: `-1.57%`;
- net enthalpy error: `+0.32%`;
- net mass error: `-55.49%`;
- R0 cap count: `79`;
- mass/energy/O2/species residuals: `0`.

The current hard rule is: pressure may bias the bidirectional opening field,
but may not create an independent gross transport path.

F3.3v3f2 added a second rule: evaluate a candidate dynamically against its own
next-step pressure state. F3.3v3f3 performed that test and exposed an explicit
one-way pressure feedback. The next candidate must solve pressure and
fixed-gross transport together, implicitly or with measured under-relaxation;
it may not directly substitute routes into the explicit timestep loop.

F3.3v3g0 selects the next bounded sequence:

1. `g1` pure network objective/relaxation primitive only;
2. `g2` passive default-OFF preview using raw pressure demand;
3. `g3` persistent shadow with 30/60/120/180 s STOP gates;
4. `g4` Group A/C 300/600 s shadow validation;
5. `g5` separate authority decision.

The network objective must not increase, gross transport must remain fixed,
all payloads must share one blend fraction, and no source-zone inventory may
be overdrawn. F3.3v3g1 is not permission to wire a runtime candidate.

F3.3v3g1 STOP:

- pure function only: PASS;
- optimum/crossing/inventory bounds separate: PASS;
- non-descent and malformed input fail closed: PASS;
- chain, disconnected components and opening-order contracts: PASS;
- Godot 4.7.1 parse/runtime fixture: PASS;
- runtime call site, flag, reports and baselines: absent.

F3.3v3g2 STOP at 180 s (`cfast_corridor_chain`, complete F3.3v stack, OFF/ON
differing by exactly one flag):

- rows 114/114, 838 shared columns, 0 shared value differences: PASS;
- 58 new columns, all in the `phase3_shadow_pressure_network_` family, and no
  column lost: PASS;
- objective never increases across all 2160 physical steps
  (max increase `0.0 Pa2`): PASS;
- mass, gross-mass, energy, O2 and species residuals all exactly `0`: PASS;
- no negative payload and no occupied-zone collapse
  (`predicted_collapse_count = 0`): PASS;
- gross mass error `-1.57%` and net enthalpy error `-0.95%` versus CFAST,
  both inside the mandatory 5%: PASS;
- one connected component (rooms 0/1/2, two connections) with stable,
  opening-order-independent identity: PASS;
- accepted bounds at 180 s: optimal `0.254`, crossing `0.0077`,
  inventory `1.000`, accepted `0.0077`, limiting reason `crossing`;
- net mass error `-97.29%` is expected and non-gating at this phase: a passive
  preview cannot evolve the pressure trajectory that bounds it.

F3.3v3g3 STOP at stage 1 (30 s), `cfast_corridor_chain`, baseline g2 ON/g3 OFF
versus candidate g2 ON/g3 ON:

The following measurements are historical experiment evidence. The g3 runtime
candidate was reverted after this STOP; only the analyzer, analyzer tests and
the binding technical record are retained.

Mechanism, all PASS:

- 24/24 rows and all 115 live columns byte-identical; 58 new columns, all in
  the persistent family; zero columns lost;
- gross mass preserved exactly per step; mass/energy/O2/species residuals `0`;
- minimum accepted bundle fraction `1.0` with zero double-limit events, so the
  F3.3v3g2 inventory bound is already sufficient and nothing is limited twice;
- zero unexpected zone collapses, EOS valid throughout, minimum post lower
  shadow gas `30.158 kg`, accepted transport bidirectional;
- the three known ignition-transient fail-closed steps stayed bounded to the
  first logged interval.

Physics, NO-GO:

- R0 shadow gauge pressure ratio candidate/baseline `1.08 -> 2.27 -> 5.65`;
- relaxed pressure request `1.838 kg` at 30 s, `5.07x` baseline at one sixth of
  the F3.3v3f2 duration;
- monotonic request growth 111 consecutive intervals (limit 10);
- predicted/observed objective divergence 239 consecutive intervals (limit 10);
- cap count 717 (limit 158).

Owner: once the imbalance is large the unconstrained optimum reaches
`alpha = 1.0`, the pressure-crossing bound stops binding, and the accepted route
set becomes fully one-directional. The doorway counterflow collapses. The
interior-network objective is not a Lyapunov function for the coupled system,
because plume, combustion and exterior leakage also own canonical pressure.

Stages 2/3/4 were not launched. The 30 s CFAST envelope was excluded from the
gate because the baseline itself is `-51.12%` on gross mass there.

The next slice must include the other pressure owners in the residual it
reduces, define stability on the coupled pressure trajectory rather than the
instantaneous interior objective, and treat an accepted alpha that zeroes one
doorway direction as invalid. Do not retry the current candidate with a tuned
under-relaxation factor; F3.3v3g0 forbids fitting a coefficient to a required
checkpoint.


F3.3v3h0 STOP (design only, no motor code):

- affine EOS premise proven numerically, not assumed: PASS;
- intra-room owners measured at exactly zero pressure effect: PASS;
- owner cancellation ratio `273x` to `15612x` measured: PASS;
- complete pressure-owner inventory and exact tick map recorded: PASS;
- numerical method selected with measured justification - damped Newton over
  one pressure unknown per room, Picard first iterate only, because the
  crossing bound was active in 93% of F3.3v3g2 steps: PASS;
- H0-H6 plan with files, default-OFF flags, tests, metrics, STOP gates,
  GO/NO-GO, rollback and cost: PASS;
- open gap recorded rather than hidden: the multisurface gas/surface exchange
  is the second-largest owner and is still classified `other`. H1 closes it
  with a diagnostic-only family addition.

F3.3v3h1 STOP (pure primitive, no runtime wiring):

- `sim/core/Phase3CoupledPressureSolver.gd` exists with no call site, no
  exported flag, no member state and no reach into engine or model types,
  enforced by structural tests rather than by intent: PASS;
- one pressure unknown per room, damped Newton, residual containing every
  owner - opening fluxes implicit, combustion/multisurface/other as sources
  inside the same residual: PASS;
- counterflow structural via the exact `dp(z)` zero crossing, with an
  unphysical one-way solution rejected when the neutral plane is inside the
  span: PASS;
- orifice law regularised below one global `dp` threshold, never a per-case
  knob: PASS;
- no `alpha`, `blend` or `skew` identifier anywhere in the code: PASS;
- Godot 4.7.1 fixture 18/18 with a negative control proving a broken assertion
  exits non-zero: PASS;
- conservation, convergence, symmetry, neutral plane, malformed input and
  fail-closed contracts all covered: PASS;
- analytic neutral-plane height reproduced to `1e-9`, Newton residual driven to
  `3e-14`: PASS.

Two defects were found and fixed while bringing the primitive up, and both are
recorded because they are easy to reintroduce:

1. normalising the line-search merit function by gross throughput is invalid,
   because that denominator depends on the pressure iterate and collapses
   toward equilibrium; an improving step can then score worse and Newton
   stalls. Normalise by room inventory instead.
2. Godot's `SceneTree.quit()` only requests a shutdown, so a fixture that calls
   `quit(1)` without returning prints its PASS marker and exits `0`.
   **Closed by the 2026-07-27 fixture audit**: 13 of 32 fixtures could report
   success while failing, across three shapes - fall-through exit, a helper
   that quits and returns to a caller reaching PASS, and a bare `assert()`
   that hangs instead of exiting. All are fixed and all 32 are now verified by
   injected-failure sweep to exit `1` without printing PASS.
   `tests/test_godot_fixture_fail_closed.py` holds 129 static contracts that
   prevent regression, each mutation-tested.

F3.3v3h2 STOP (passive preview, no physical write):

- OFF/ON isolation exact on `corridor_chain` 10/30/60 s and
  `cfast_r0_window_360` 120 s: zero shared value differences, zero columns
  lost, 37 new columns all in the `phase3_shadow_coupled_solver_` family: PASS;
- owner sources recovered exactly as `(post - pre) - interior_accepted`, so
  every non-opening owner is inside the residual: PASS;
- every converged step closes its residual (`max_normalized_residual = 0.0`)
  and zero counterflow violations occurred in 2642 solved steps: PASS;
- the preview emits no route, bundle or state, enforced by structural tests
  that whitelist the two ledgers it may write: PASS.

Substantive measurement: the coupled solve leaves `0.07 Pa` across the
connected chain at 60 s where the legacy additive path leaves `69.3 Pa`, and it
moves `3.32x` more net doorway mass. Directionally consistent with the standing
`-55.49%` net-mass deficit versus CFAST, but a single-step preview cannot claim
the deficit would close.

Measured limit, deliberately not gated: `13.6%` of steps do not converge at
60 s. Iteration-cap failures are confined to the ignition transient and stop
after ~20 s; damping-exhausted failures accumulate with time. They are separate
problems with separate remedies and are counted separately.

Next slice is **H3 only**, and only after the convergence gap is diagnosed. Do
not raise the iteration cap or loosen the residual tolerance to hide it, and do
not write a persistent apply path before the cause is known.