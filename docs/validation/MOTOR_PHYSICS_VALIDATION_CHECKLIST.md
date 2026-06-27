# Motor Physics Validation Checklist

Date: 2026-06-24.

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

### O1 bulk O2 mass balance — CLOSED AS WARN (2026-06-26)

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

- O1 is implemented in `scripts/simulation/check_physics_coherence.py` as **WARN**, not FAIL-gating.
- Corpus O1 audit after O1-F: 11/11 PASS, 0 O1 findings, 0 WARN, 0 FAIL.
- Maximum residual observed after fixes: `3.87e-4 kg`.
- Tests: 22 `TestCheckO1`; O1 instrumentation subset green.

Important fixes found while closing O1:

- `SimulationStateBuilder` had applied a CO2 molar correction to logged `o2` in non-fire rooms only. This made CSV `o2` diverge from actual `room.o2`; fixed by exporting `room.o2` directly.
- `o2_consumed_kg_total_all` cannot be used for bulk O1 because it includes upper/lower/plume consumption. O1 uses `o2_consumed_bulk_kg_total`.
- `_apply_room_o2_mass_delta` now accumulates the post-clamp `actual_delta_kg`, not the intended delta, avoiding false WARNs when clamped at `o2_nominal`.

### Open gaps

- O1 is not yet FAIL-gating. Keep as WARN until it remains clean across a broader long-duration/multi-floor corpus.
- O1 is a bulk balance rule. It does not replace future zonal O2 balance for `o2_upper`/`o2_lower`.
- `upper_o2_mass_tracked` is orphaned — not used in combustion, not exported to CSV.
- Dual-track risk: `o2_upper` (fraction) and `upper_o2_mass_tracked` (mass) may diverge if `canonical_o2_upper_updated` flag handling fails.
- Option C (canonical mass redesign) needed to fully separate combustion/transport/dilution paths.

### O2E1 Thornton cross-check — OPEN AS WARN (2026-06-27)

O2E1 cross-checks `o2_consumed_kg_total_all` (OES all-paths accumulator) against the Thornton prediction derived from `hrr_kj_total` (CombustionSystem tracking-only accumulator). Rule:

```text
expected_o2 = delta(hrr_kj_total) * 7.6e-5  (kg/kJ — Thornton 13.1 MJ/kg O2)
residual    = |delta(o2_consumed_kg_total_all) - expected_o2|
tolerance   = max(1e-5, 0.05 * |expected_o2|)
```

Status after corpus audit (2026-06-27):

- **11 CSVs audited**: 8 WARN, 3 PASS (old schema — no `hrr_kj_total` column, graceful skip).
- **0 FAIL findings** (O2E1 is WARN-only, not gating).
- **1308 WARN findings** across the 8 cases with `hrr_kj_total`.
- **Root cause identified**: in standard two-zone mode (`lower_frac ≥ 0.15`, not `plume_lower`, not `two_zone_solver`), OES accumulates Thornton O2 in **both** the bulk path (line 362, `room.o2_consumed_kg_total_all += consumed`) and the upper-zone path (line 407, `room.o2_consumed_kg_total_all += upper_consumed`). Each uses the same formula `(hrr_kw/1000) * cr * dt`, so `o2_consumed_kg_total_all ≈ 2 × Thornton`. The `o2_consumed_bulk_kg_total` (O1 rule) is not affected because it only accumulates from the bulk path.
- **Max residual**: `1.948e-5 kg` (`fp_ilv_open_partial_window`, t=10s, room 2). All residuals are small (1–2 × 10⁻⁵ kg), but exceed the `1e-5` absolute floor.

Open items:

- O2E1 is not FAIL-gating. Keep as WARN until root cause is addressed.
- Fix path: restructure `o2_consumed_kg_total_all` to accumulate net O2 removed from the room (not additive across parallel paths that represent the same fire consumption event). Requires explicit plan — do not touch without one.
- Alternative: create separate accumulators `o2_consumed_bulk_total` + `o2_consumed_upper_total` and use only one for Thornton cross-check.
- Promotion to FAIL requires: (a) fix the double-accounting in `o2_consumed_kg_total_all`, (b) clean corpus re-audit across ≥ 11 cases including backdraft and pool release.

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
- D2: CO/CO2 ratio out of expected range. Blocked: `co2_upper_ppm` uses a tracer path, not mass-derived. Do not implement until CO2 dual tracking is resolved.
- D3: CO absent with high HRR.
- D4: HCN present with zero CO.
- D5: CO/HRR/O2 magnitude consistency.

Instrumentation now available in CSV (as of 2026-06-24):

- `co_generated_kg_step`, `co2_generated_kg_step`, `hcn_generated_kg_step` per room and step.
- `co_net_transport_kg_step` per room and step (net, not split in/out).
- `co_generated_kg_total`, `co_net_transport_kg_total`, `co_exterior_removed_kg_total` per room (cumulative).
- `c_balance_frac`, `carbon_conservation_error_kg` per room and step.

Remaining gap: `co_transported_in_kg` and `co_transported_out_kg` (split in/out) are not tracked separately. `co_net_transport_kg_total` covers the net; split tracking would require additional instrumentation.

## 4. Smoke And Soot

Items to check:

- Smoke/soot generation against HRR, fuel and regime.
- Smoke transport conservation between rooms and layers.
- Coupling between smoke movement, CO movement and hot-layer transport.
- Smoke cooling over time when HRR falls.
- Smoke descent when cooled gases lose buoyancy and there is room below the hot layer.
- Relationship among `smoke_kg`, `visibility_m`, layer heights and ventilation.

Open gaps:

- S1 smoke mass balance by room/layer.
- Soot-yield validation.
- Cooling/descent validation.

Current auditor coverage:

- S0: global smoke conservation is FAIL-gating. Invariant:
  `Σ smoke_kg + smoke_in_transit_kg ≈ smoke_generated_total_kg - smoke_vented_total_kg - smoke_deposited_total_kg`.
- Fresh corpus result: 11/11 CSVs PASS, 0 S0 findings; 9 CSVs have the fresh S0 schema and 2 legacy `p2h_diag_*` CSVs skip gracefully.
- S0 closure fixed missing smoke accounting in ACH/infiltration removal and natural-ventilation purge, exposed `smoke_in_transit_kg` for delayed interior deliveries, and stopped `SmokeModel.recompute_layer_from_mass()` from zeroing sub-threshold smoke mass.
- Limitation: S0 is global. It can miss compensated inter-room transport errors. S1 remains blocked until per-room `smoke_generated`, `smoke_vented`, `smoke_deposited` and `smoke_net_transport` accumulators exist.

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

## 15. Current Priority Order

1. Keep the current auditors green and integrated.
2. Add missing instrumentation needed for gas and energy balances.
3. Build balance-based checks before heuristic checks.
4. Expand the CFAST/reference scenario battery.
5. Only then change motor physics, one subsystem at a time, behind explicit validation.
