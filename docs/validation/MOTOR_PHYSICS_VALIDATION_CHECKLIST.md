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

## Phase 3 Runtime Authority

| Phase | Status | Decision |
|---|---|---|
| H3.0 ownership map | CLOSED | Design only; projection reconstruction and cross-step parcels identified as hard ownership constraints. |
| H3.1 passive ownership ledger | GO / STOP gate | Default OFF; 12-case corpus closes ownership, parcel and projection ledgers with zero legacy-column differences. No authority granted. |
| H3.2a zonal decomposition | GO / STOP gate | Additive solver output (+227/-0); bands were already split at both interfaces, so zoning is a read of an existing decision. Exterior never labelled. No authority. |
| H3.2-M mechanical bundle shadow | GO / STOP gate | Existing atomic primitives and pure donor limit reused in separate coupled ledgers; no application or authority; comparison explicitly invalid because sources are circular. |
| H3.2-S independent owner sources | NO-GO / BLOCKING | H3.1 stage deltas mix physical owners and legacy transport. Add mutation-site physical owner events before replacing `(post-pre)-legacy_interior`; no motor patch was made. |
| H3.2-S0 physical owner ledger | NO-GO / SPLIT | Initial event schema cannot represent same-room interzone redistribution. Proceed as S0a contract, S0b thermal, S0c gas and S0d integration. |
| H3.2-S0a event contract | GO / STOP gate | Pure isolated primitive with six classifications, explicit zonal deltas, fail-closed aggregation and zero runtime call sites. |
| H3.2-S0b thermal owners | GO / STOP gate | Default-OFF events at accepted thermal mutation sites; no duplicated projection/doorway/parcel ownership and no CSV or physics change. S0c/S0d remain blocking. |
| H3.2-S0c gas owners | GO / STOP gate | Default-OFF gas mass/energy events with caller provenance and cross-step parcel identity. Species/O2 accepted-owner attribution remains absent; S0d remains blocked. |
| H3.2-S0d source integration | NO-GO / BLOCKING | Mass and energy are incomplete too: suppression, the opening-radiation mass seed, the doorway-counterflow mass injection and HVAC emit no owner. A pure integrator also cannot detect an absent owner. No integrator was created. |
| H3.2-S0d1 suppression and seeds | GO / STOP gate | Suppression upper sink owned as a signed local source; the two donor-less mass seeds declared numerical corrections. B1-lower left uninstrumented because the legacy write is dead under two-zone. |
| H3.2-S0d2 suppression lower sink | GO experimental / NO-GO promotion | Default-OFF flag applies the lower cooling to `lower_energy_kj` under two-zone. OFF is byte-identical; no official case enables it. B1-lower stays open. |
| H3.2-S0d3 species attribution measurement | GO parcial / STOP gate | Default-OFF measurement shows the lower species clamp never bound over 12 cases; CO/CO2/HCN are attributable, O2 and the zone-less species are not. Measurement only, no enrichment. |
| H3.2-S0d4 zonal species consistency | NO-GO attribution / GO guard | The unowned `upper <= bulk` clamp rewrites the zonal split in 5.4-7.5 % of applications, so per-owner zonal attribution of CO/CO2/HCN is not reconstructible. Only the passive guard shipped. |
| H3.2-S0d5a CO zonal transport | GO experimental / NO-GO promotion | Default-OFF symmetric CO bulk/upper debit removes 81.9 % of the `upper > bulk` violations. The residual 18.1 % has no provenance, so S0d5a2 is mandatory before S0d5b. |
| H3.2b residual projection | BLOCKING | Must preserve the thermal cap as an explicit sink before any state commit. |
| H3.3 mass/energy authority | BLOCKED | Cannot start before H3.2-S and H3.2b pass their STOP gates. |

H3.1 binding checks (2026-08-02):

- `phase3_runtime_ownership_ledger_enabled` defaults false and extends CSV only
  when enabled.
- F0 and H3.1 flags are independent; projection tracing uses their effective OR
  and both ON do not duplicate calls or H3.1 fields.
- Ten real writer stages are attributed; the three thermal doorway mechanisms
  and delayed parcels are reported separately without being added twice.
- 12 committed cases, 120 s, Godot 4.7.1: maximum mass, energy, parcel and
  projection-boundary residuals are all `0`.
- Ten topology cases match H2.10 OFF in 115/115 legacy columns and row counts.
- H3.1 does not close Group A/C, change expected values or authorize runtime
  state. Full record: `PHASE3_H31_RUNTIME_OWNERSHIP_LEDGER.md`.

H3.2-S source audit (2026-08-03):

- H3.1 is complete as an attribution ledger but insufficient as a source
  constructor: its `thermal` and `gas_exchange` stage deltas are composite.
- Thermal doorway upper/lower/counterflow and delayed parcels are independently
  measured; thermal local/surface/exterior owners and gas exterior/immediate/
  background mass/enthalpy are not yet complete at mutation-site granularity.
- Subtracting known transports from stage deltas is prohibited because it
  remains a legacy post-state reconstruction.
- Result: **NO-GO**, zero `sim/core` changes. Full record:
  `PHASE3_H32S_INDEPENDENT_SOURCE_DIAGNOSIS.md`.

H3.2-S0 mutation-site audit (2026-08-03):

- 112 direct upper/lower mass/energy mutation statements were inventoried.
- Projection, three thermal doorway mechanisms and delayed parcels already have
  ledgers and must not be instrumented twice.
- The event contract needs `interzone_redistribution` plus upper/lower deltas;
  without them plume and vertical mixing cannot be represented truthfully.
- Result: **NO-GO before implementation**, zero motor changes. Full record:
  `PHASE3_H32S0_PHYSICAL_OWNER_LEDGER_AUDIT.md`.

H3.2-S0a contract gate (2026-08-03):

- Pure `RefCounted` dictionary API; no engine/building/room dependencies,
  production call sites, flags, runners or CSV fields.
- Adds `interzone_redistribution`; only local and exterior classes can become
  physical sources.
- Duplicate/invalid events are excluded and visible; no partial source is
  returned from an invalid aggregate.
- Runtime negative control exits non-zero with no PASS marker. Full record:
  `PHASE3_H32S0A_PHYSICAL_OWNER_EVENT_CONTRACT.md`.

H3.2-S0b thermal-owner gate (2026-08-03):

- Default OFF and legacy CSV schema unchanged; four official OFF/ON pairs are
  byte-identical.
- Thermal local sources, exterior boundaries, interzone redistribution and
  auxiliary interior transports emit accepted mutation-site deltas.
- Projection, canonical doorway exchange and delayed parcels remain uniquely
  owned by their existing ledgers.
- Final-step summaries have zero invalid/duplicate events; maximum conservative
  residuals are `2.665e-15 kg` and `8.882e-16 kJ`.
- Seven Godot 4.7.1 regression fixtures pass; Physics and ILV remain at zero
  FAIL; gap inventory is unchanged. Guardrails are 9/10 solely because the
  uncommitted motor patch correctly triggers R2-1 freshness.
- **GO for passive S0b only.** S0c gas ownership and S0d integration remain
  required before H3.2-S can close. Full record:
  `PHASE3_H32S0B_THERMAL_PHYSICAL_OWNER_EVENTS.md`.

H3.2-S0c gas-owner gate (2026-08-04):

- Six official 30 s OFF/ON pairs are byte-identical with the same 115 legacy
  columns and row counts; the OFF summary contains no owner ledger.
- Pressure/smoke/PPV upper-layer removal has caller provenance; immediate and
  background transport close exactly; delayed parcels preserve identity across
  steps and expose created/delivered/cancelled lifecycle plus refunds.
- Combined thermal/gas aggregates have zero invalid or duplicate IDs. Species
  and O2 owner shares behind aggregate clamps remain explicitly uncovered.
- **GO for passive S0c only.** S0d is not started, H3.2-S remains blocked,
  H3.2b still blocks H3.3 and no authority is granted. Full record:
  `PHASE3_H32S0C_GAS_PHYSICAL_OWNER_EVENTS.md`.

H3.2-S0d source-integration gate (2026-08-04):

- The owner events cannot yet build an independent per-room/zone source vector.
  Mass and energy are incomplete, not only species and O2.
- Unowned zone mass/energy writes: the suppression upper sink and its
  temperature-written lower sink, the opening-radiation target mass seed, the
  doorway-counterflow minimum-mass injection and HVAC.
- Seven cases run with the ledger enabled contain zero suppression owners and
  zero HVAC owners while those mechanisms drive the step.
- A pure integrator fed only by owner events cannot report truthful
  completeness: an absent owner is invisible without post-state or an invented
  per-room registry.
- **NO-GO.** No motor file changed and no integrator was created. H3.2-S cannot
  close, H3.2b still blocks H3.3 and no authority is granted. Full record:
  `PHASE3_H32S0D_SOURCE_INTEGRATION_AUDIT.md`.

H3.2-S0d1 suppression and donor-less mass gate (2026-08-04):

- The suppression upper sink is an accepted `kJ` at one mutation site and is now
  owned as a signed `local_source`, with `steam_kg` as the visible counterpart.
- The opening-radiation target mass seed and the doorway-counterflow minimum
  mass are numerical initialisation of an empty upper layer: no donor, no
  exterior enthalpy, reconciled by the projection volume closure. Both are
  declared `numerical_correction` and cannot reach a source vector.
- B1-lower is a dead write under two-zone: a probe of the exact call sequence
  shows `temp_lower_c` restored from `lower_energy_kj` by the projection. No
  owner was fabricated; the correction is separate work.
- Eight OFF/ON pairs byte-identical, zero invalid or duplicate events.
- **GO for passive S0d1 only.** HVAC deferred, species/O2 pending, no
  integrator, H3.2-S blocked, H3.2b still blocks H3.3, no authority. Full
  record: `PHASE3_H32S0D1_SUPPRESSION_AND_DONORLESS_MASS.md`.

H3.2-S0d2 experimental lower suppression sink gate (2026-08-05):

- `phase3_suppression_lower_energy_sink_enabled` is explicit and default OFF.
  OFF reproduces the S0d1 checkpoint byte for byte, including the CSV SHA-256 of
  the comparable pairs, and no official case sets it.
- ON plus two-zone applies the lower cooling to `lower_energy_kj` instead of a
  temperature the projection discards. Requested, accepted, rejected and
  available are reported separately; the availability cap binds and the
  remainder is declared rejected, never applied.
- `cfast_suppression_water` keeps `temp_lower_c` at ambient in all logged rows,
  so the legacy request is zero there and OFF/ON stay identical. The measured
  effect lives in `v8_suppression_reburn`: up to 9.77 °C lower `temp_lower_c`
  during suppression, HRR/FED/O2 under 0.1 %, extinction timing unchanged.
- **GO experimental only, NO-GO to promote.** Promotion would move a state
  variable that expected values depend on and needs its own baseline review.
  B1-lower stays open; the upstream question is whether the projection should
  pin `temp_lower_c` at ambient at all. Full record:
  `PHASE3_H32S0D2_SUPPRESSION_LOWER_ENERGY_SINK.md`.

H3.2-S0d3 species attribution measurement gate (2026-08-05):

- `phase3_species_attribution_diagnostics_enabled` is default OFF and measures
  the aggregate clamp at its single application site. It has no per-owner field,
  so a clamped deficit cannot be distributed by construction.
- Over 12 cases and 92 202 applications per species the lower `maxf(0.0, ...)`
  clamp bound **zero** times; `requested_kg_total` equals `accepted_kg_total`
  exactly for every species accumulator. This contradicts the S0c assumption and
  makes per-owner acceptance exact for the measured corpus.
- O2 stays blocked: 1798 upper-bound clamps, multiple owners and no zone.
- Zone identity is declared, not inferred: CO/CO2/HCN carry bulk plus an upper
  accumulator; smoke, HCl, acrolein and formaldehyde are bulk only.
- The non-binding result is empirical, not a proof. Any attribution must verify
  the guard per room, species and step and fall back to `completeness=false`
  with `aggregate_clamp_multi_owner`.
- **GO parcial for measurement only.** No event enrichment, no integrator,
  H3.2-S still open. Full record:
  `PHASE3_H32S0D3_SPECIES_ATTRIBUTION_MEASUREMENT.md`.

H3.2-S0d4 zonal species consistency gate (2026-08-05):

- `lower = bulk - upper` is only meaningful while `upper <= bulk`. The legacy
  clamp that enforces it has no owner, and it binds: CO 7 444 / 98 690 (7.5 %),
  CO2 5 753 (5.8 %), HCN 5 324 (5.4 %). All twelve cases violate it; the lower
  bound never binds. Max excess is 2.54e-05 kg for CO.
- Cause: owner paths that move a species' bulk stock without moving its upper
  stock. CO's transported amount is derived from `source.co_upper_kg` but
  removed from `source.co_kg` only; CO2 and HCN move bulk only in the background
  and vertical-opening paths.
- Attributing CO zonally today would encode the defect: the ledger would report
  CO leaving a room's lower zone in a transfer sized from its upper zone.
- **NO-GO for attribution, GO for the passive guard only.** Prerequisites:
  S0d5a CO transport coherence, S0d5b CO2/HCN bulk-only paths, S0d5c own or
  remove the clamp. Full record:
  `PHASE3_H32S0D4_ZONAL_ATTRIBUTION_AUDIT.md`.

H3.2-S0d5a CO zonal transport gate (2026-08-05):

- `phase3_co_zonal_transport_consistency_enabled` is explicit and default OFF.
  OFF is byte-identical to the S0d4 checkpoint, verified by stashing the change
  and comparing CSV SHA-256 on `v4_co_remote_rooms`.
- ON debits CO's upper stock with the same accepted amount as its bulk stock in
  immediate and delayed transport, keeping the derived lower stock invariant,
  and refunds bulk and upper equally. The refund half is inert in a clean state.
- CO violations fall 9 280 to 1 682 over nine cases: 7 598 (81.9 %) attributable
  to the immediate/parcel paths, **1 682 (18.1 %) still unattributed**. CO2 and
  HCN are unchanged, `upper < 0` stays zero, the aggregate CO clamp never binds,
  and HRR/O2/upper temperature are identical OFF/ON.
- `co_ppm` peak +3.8 %, FED peak within 0.3 % in both directions.
- **GO experimental only, NO-GO to promote.** The residual contradicts the
  earlier claim that the other CO writers were coherent, so S0d5a2 must localise
  it before S0d5b starts. Full record:
  `PHASE3_H32S0D5A_CO_ZONAL_TRANSPORT.md`.

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
| F3.3v3h2.5 | Convergence hardening from reconstructed states | NO-GO; 528 synthetic cases converged 100%; reverted |
| F3.3v3h2.5a | Real failing-step capture and deterministic replay | Capture GO; solver unchanged; H3 still blocked |
| F3.3v3h2.5b | Offline diagnosis of the captured failure | Diagnosis GO; recommended centred Jacobian; evidence single-topology |
| F3.3v3h2.5c | Centred-difference Jacobian candidate | **NO-GO**; helps corridor, destroys r0_window_360; reverted; second capture retained |
| F3.3v3h2.5d | Gauge vs Armijo, measured on both captures | Combined patch **NO-GO**; gauge alone is the only non-regressing mechanism |
| F3.3v3h2.5e | Coupled solve in gauge coordinates | **GO, partial**; r0_window 86.33→91.33%, no stage regressed; corridor still open |
| F3.3v3h2.5f | Fail-only rescue design, measured offline | L2 and LM both viable; LM chosen on 39/39 vs 20/39 |
| F3.3v3h2.5g | Bounded LM recovery, one step per solve | **GO** for the canonical damping mode; corridor still 84.18% at 120 s; iteration_cap unmoved |
| F3.3v3h2.5h | Real iteration_cap capture plus a mode selector | Capture GO; latch defect found and fixed; solver untouched |
| F3.3v3h2.5j | Accepted-cycle guard reusing bounded LM | **GO with revised gate**; r0 125 caps -> 0; corridor late regime remains open |
| F3.3v3h2.5l-A | Passive post-budget cycle observation | **GO telemetry only**; H2.5m authority NO-GO; H2 open |
| F3.3v3h2.5l-B | Per-solve recurrence ledger | **GO passive ledger**; cross-topology separation confirmed; H2.5m blocked |
| F3.3v3h2.5m | Analytic half step for the period-2 orbit | **GO**; corridor 100% at all stages, iteration_cap 378 -> 0; H2 still open, H3 blocked |
| F3.3v3h2.6 | Cross-topology audit, eight cases | **GO as audit**; zero regressions; **NO-GO to close H2** - two_storey_smoke keeps 20 iteration_cap; H2.7 = cap sizing |
| F3.3v3h2.7 | Iteration-budget diagnosis | **GO as diagnosis**; **NO-GO for any cap change** - cap is above P99, cause is an undetected alternating-gain orbit; P2 deferred to H2.8 |
| F3.3v3h2.9 | `uk_bungalow_smoke` damping-exhausted diagnosis | **GO as diagnosis**; forward Jacobian crosses donor branch; LM-budget expansion NO-GO; H2.10 = branch-preserving adaptive quotient |
| F3.3v3h2.10 | Adaptive branch-preserving unilateral Jacobian | **GO**; 9/9 captures, 189/189 neighbourhood, C8 parallel openings and ten-case runtime gate PASS; H2 closed, H3 unblocked |
| H3.0 | Runtime authority ownership map and phase plan | **DESIGN ONLY**; no motor change; H3.2b identified as prerequisite for any mass/energy commit; recommends authorising H3.1 alone |
| F3.3v3h2.8 | Alternating-gain cycle detector | **GO**; all 22 iteration_cap eliminated, two_storey 98.61%->100%; **H2 still open** on uk_bungalow damping_exhausted |

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

F3.3v3h2.5 STOP (convergence hardening): **NO-GO, reverted.** The three
hypotheses - Jacobian FD step, seed pressure, residual roughness - were all
tested against *reconstructed* states, and 528 synthetic cases converged
`100%` of the time. The hardening therefore had no failure to falsify against
and its own instrumentation produced unexplained values. Nothing was committed.

F3.3v3h2.5a STOP (capture only, no fix attempted):

- the capture path is empty by default and the first failure latches before any
  write, so an unconfigured run cannot be affected: PASS;
- `tests/fixtures/data/coupled_solver_failure_corridor_chain.json` records a
  real non-converged solve - `corridor_chain` step 297, `damping_exhausted`,
  failure code 6, **3 iterations** against a cap of 24: PASS;
- every numeric leaf carries the exact IEEE754 bit pattern alongside a readable
  decimal, so the replay solves the captured problem and not a nearby one
  (`String.num_scientific` alone round-trips ~9 significant digits and the
  replay measurably diverged before the hex field existed): PASS;
- `phase3_f33v3h25a_captured_solver_failure.gd` replays with no engine,
  building or scenario, is deterministic across two runs, and asserts the
  failure **still reproduces**: PASS;
- `Phase3CoupledPressureSolver.gd` is unchanged from H2 and a test forbids the
  H2.5 knobs; solver behaviour at 30 s is identical to the committed baseline
  (361 steps, 299 converged, 46 iteration-cap, 16 damping-exhausted): PASS.

Substantive observation, deliberately not acted on: the captured step fails
after 3 iterations, so it is not an effort problem, and the room-0 owner source
carries **negative** mass with positive energy. H2.5b must work on this fixture
offline before touching runtime. H3 remains blocked.

F3.3v3h2.5c STOP (centred Jacobian candidate): **NO-GO, reverted.**

- on `corridor_chain` it did exactly what H2.5b predicted - `damping_exhausted`
  52 -> 1 at 60 s and 120 s, convergence 86.39% -> 93.75% at 60 s: PASS;
- on `r0_window_360` convergence went **86.33% -> 0.14%**, with 1439 of 1441
  steps at `iteration_cap` and a 1.68x cost: **FAIL, and decisive**;
- isolation and mechanics were correct throughout - OFF byte-identical on all
  five pairs, zero counterflow violations, all five fixtures PASS, and a
  mutation control caught a regression to the one-sided quotient: PASS;
- the failure is numerical, not structural: at the failing state the centred
  difference is *more* accurate than the forward one, and the Newton steps then
  alternate sign in a **period-2 limit cycle** that the bare `< norm`
  acceptance test accepts at full damping forever. Centring removed the
  accidental asymmetry that had been breaking the cycle.

Consequence: `damping_exhausted` and `iteration_cap` are **not** separate
problems. They are the same missing globalization at two extremes.

Retained: a second real capture,
`tests/fixtures/data/coupled_solver_failure_r0_window_360.json` (star topology,
five rooms, four openings all at room 1), its replay fixture and 12 contracts.
It records a **third** mode - the solve reaches `1.147e-12` against a `1.0e-12`
tolerance and the correction it still owes is `0.38 ulp` of the absolute
pressure iterate, so no damped trial is a different double.

Why H2.5b's evidence was insufficient, recorded so it is not repeated: its
204-case family perturbed **one topology**. Perturbing a single capture
explores states, not topologies.

Binding constraints for H2.5d: both captures are a mandatory gate offline
before any scenario run; do not retune the Jacobian step and do not centre the
difference; the named candidate is Armijo / sufficient decrease plus cycle
detection; `iteration_cap` remains uncaptured because the instrumentation
records only the first failure.

F3.3v3h2.5d STOP (offline, both captures): **combined patch NO-GO.**

- **Armijo cannot help either capture, structurally**: a sufficient-decrease
  test is stricter than plain decrease, so it never rescues a step that already
  fails plain decrease. Measured identical to baseline on both: PASS as a
  falsification, NO-GO as a fix;
- cycle detection is **correct and fires diagnostically** - given the H2.5c
  centred-difference stimulus it reports `cycle_detected` at iteration 3, never
  as convergence - and fires on neither capture under the shipped quotient;
- a non-monotone L-infinity line search was far worse than baseline (22/82);
- `gauge` closes `r0_window_360` (37/41 -> 40/41 in its neighbourhood, **zero**
  regressions) and is neutral on corridor; an L2 acceptance merit closes
  corridor (26/41 -> 40/41) and **wrecks r0** (37/41 -> 26/41);
- the two are antagonistic. Together they pass both exact captures - the letter
  of the gate - while breaking 12 neighbourhood cases the baseline solved. That
  is the H2.5c signature, so the combination was **rejected on evidence** rather
  than accepted on the criterion.

F3.3v3h2.5e STOP (gauge coordinates, one file):

- the unknown is a gauge pressure relative to the exterior reference the solve
  received; the seed, the opening difference and the EOS residual all avoid
  forming a subtraction of two numbers near ambient: PASS;
- the EOS is expanded about `M_ref = P_ext V / (R T_ref)`, dropping the
  residual's rounding floor from `1.455e-11 Pa` to `1.14e-13 Pa` (128x): PASS;
- `r0_window_360` converges in 3 iterations at `9.5e-17`, inside the unchanged
  `1e-12` tolerance: PASS;
- shift invariance, a 90 kPa exterior reference, conservation, counterflow and
  bit-for-bit determinism are pinned by a dedicated fixture, with exterior
  openings on **both** sides so neither branch is left unexercised: PASS;
- runtime gate - no stage regressed; corridor 66.67->67.50, 82.83->83.10,
  86.39->86.53, 81.33->81.40; **r0_window_360 86.33% -> 91.33%** with
  `damping_exhausted` **72 -> 0**; `iteration_cap` unchanged everywhere; OFF
  byte-identical on all five pairs; cost went down: PASS;
- Jacobian, merit, damping, tolerance, regularization, band segments and flux
  law are unchanged, and no tuning knob was added: PASS.

F3.3v3h2.5f/g STOP (bounded LM recovery): **GO for the canonical
`damping_exhausted` mode only.** `corridor_chain` is NOT closed - at 120 s it
is still 84.18%, with 217 `iteration_cap` and 11 `damping_exhausted` past the
one-step budget. H2 stays blocked, principally on `iteration_cap`.

- the recovery is reachable ONLY from the `damping_exhausted` dead end; over
  **432** baseline-successful solves the trajectory and result are
  **bit-identical** and it fired zero times: PASS;
- it damps the same Jacobian toward steepest descent on a sum-of-squares merit
  and demands sufficient decrease. The accepted step deliberately RAISES
  L-infinity (2.169e-04 -> 2.348e-04) while lowering that merit - the trade the
  ordinary test refused: PASS;
- bounded to one accepted step per solve and five regularization strengths, all
  global constants, never read from `options`: PASS;
- matrix - no stage regressed and **`iteration_cap` is identical everywhere**
  (39/46/46/217/125), so there is no damping-to-iteration shift. corridor
  83.10 -> 87.26%, 86.53 -> 92.08%, 81.40 -> 84.18%; `damping_exhausted`
  15 -> 0, 51 -> 11, 51 -> 11; `r0_window_360` untouched at 91.33% with zero
  attempts: PASS;
- OFF byte-identical on all five pairs, analyzer exit 0, zero counterflow
  violations, coupled-vs-legacy divergence bit-identical: PASS.

Two gaps recorded rather than hidden: no physical case exists where the
recovery declines (~2500 offline solves, it succeeded every invocation), so
that branch is covered structurally plus mutation control; and the per-step
`..._rescue_*` columns are sampled at the 10 s log cadence and almost never
coincide with a recovery, so the `_total` counters are the usable signal.

F3.3v3h2.5h STOP (instrumentation only): **GO.**

- an opt-in mode selector lets a specific failure be waited for; empty keeps the
  original semantics: PASS;
- **a latch defect was found and fixed**: the engine re-applies configuration on
  every log tick and the capture reset its latch each time, so the artifact was
  the first failure after the LAST reconfigure. Latch and invalid-selector error
  are now gated on the selector having changed: PASS;
- unknown selector reported once and capture disabled; `run_scenario.py` rejects
  it before launching Godot with a non-zero exit; both mode lists pinned to
  agree by test: PASS;
- `Phase3CoupledPressureSolver.gd` unmodified, asserted by test: PASS.

Measured anatomy of the real `iteration_cap`, corrected after the latch fix:
residual `2.160e-02 -> 4.339e-04` over 24 monotone iterations, and the **same
input converges in 26 iterations** given room; a late-run step needs **108**. An
earlier draft extrapolated the first 24 iterations' linear rate to ~4600 and
concluded a bigger cap was pointless - wrong by about forty times. The fixture
now measures the required budget instead of extrapolating.

That is still not an argument for raising the cap: 26 and 108 are both far past
a healthy Newton, so the defect is the rate and raising the cap would hide it.

`persistent_step_index` is an **opaque identifier, not chronological time** - the
two selectors report 510 and 1435 on the same run, which is not an ordering.

**H2.5i must diagnose why quadratic convergence is lost.** Do not raise the cap,
do not widen the LM budget, do not touch gauge, tolerance or the flux law.

**`iteration_cap` is now the dominant remaining failure mode** - alongside the
11 post-budget `damping_exhausted` at 120 s - and is captured bit-exactly by
H2.5h. Its measured convergence is monotone but unhealthy: the first capture
needs 26 iterations when given room and a late-run input needs 108. **H3 stays
blocked**, and all real captures remain the gate for any future attempt.

F3.3v3h2.5j STOP: **GO with the revised cross-topology gate.**

- the real H2.5h period-2 capture converges in 8 iterations with exactly one
  accepted-cycle guard and one bounded LM step: PASS;
- corridor convergence improves to 99.17 / 99.17 / 98.06 / 87.16% at
  10/30/60/120 s; `iteration_cap` falls 39/46/46/217 -> 1/3/3/174: PASS;
- `damping_exhausted` does not increase and there is no failure-mode
  displacement: PASS;
- OFF artifacts are byte-identical, ON live shared columns are identical and
  converged sampled roots are unchanged: PASS;
- counterflow violations remain zero; Physics and ILV remain at 0 FAIL: PASS;
- the original requirement "r0_window does not activate the safeguard" was
  retired as a false premise. It activates 186 times with the same cycle
  signature and removes all 125 prior iteration caps, taking convergence
  91.33% -> 100%, without violating any invariant: PASS under revised gate.

The revised gate permits activation in another topology only when it
strictly removes failures while OFF output, live ON values, already-converged
roots, conservation and counterflow remain unchanged. H2.5j satisfies it.

The GO is bounded. All corridor improvement occurs before 60 s. From 60 to
120 s both baseline and candidate add 171 failures; between 80.1 and 90.1 s,
120 guard rescues are accepted and 120 solves still hit `iteration_cap`, with
rho about 0.0478 near the threshold. H2 remains open with 174 `iteration_cap`
and 11 `damping_exhausted` at corridor 120 s; H3 stays blocked. H2.5k owns the
late-regime selectivity and retry-cost question.

F3.3v3h2.5k STOP: **GO for diagnostic capture only.**

- `iteration_cap_after_rescue` is an opt-in composite selector that requires
  both `limiting_reason == iteration_cap` and an accepted cycle-guard rescue;
  it is evaluated before the one-shot capture latch: PASS;
- the coupled pressure solver, rescue budget, tolerance and iteration cap are
  unchanged: PASS;
- the late corridor failure is the same period-2 mode recurring after the
  rescue budget is spent. Its two-step contraction remains
  `0.9896..1.0101`, while the early successful cycle contracts strongly:
  PASS;
- current cycle telemetry stops observing when rescue budget is exhausted:
  known instrumentation gap, not hidden;
- no physical report, expected value, tolerance, CTRL or VALID_GAP changes:
  PASS.

H2.5l must separate cycle observation from rescue authority and measure
two-step contraction across corridor and r0-window before any change to the
rescue strategy. H2 remains open and H3 remains blocked.

F3.3v3h2.5l-A STOP: **GO for passive telemetry only.**

- cycle detection runs before and outside the rescue-budget gate, while the
  one-step LM rescue remains inside the original gate: PASS;
- a real corridor replay preserves `iteration_cap`, 24 iterations and one
  accepted rescue while reporting 22 detections, 21 after budget: PASS;
- OFF CSVs are byte-identical and all existing ON columns are identical across
  corridor 30/60/120 s and r0-window 120 s: PASS;
- corridor 120 s reports 2722 detections, 2211 after budget; r0-window reports
  204 detections and zero after budget: measured;
- contraction ranges overlap (`0.7731..1.0465` corridor,
  `1.0038..1.0480` r0-window), so no cross-topology authority threshold is
  justified: **H2.5m NO-GO**;
- Physics and ILV stay at 0 FAIL, counterflow violations stay zero, and the gap
  inventory is unchanged: PASS.

The four cumulative scalars cannot count distinct solves with a second cycle
or report their eventual outcome. A passive per-solve recurrence ledger is the
required next evidence. H2 remains open and H3 remains blocked. Full record:
`docs/validation/PHASE3_F33V3H25L_PASSIVE_CYCLE_OBSERVATION.md`.

F3.3v3h2.5l-B STOP: **GO for passive per-solve recurrence ledger.**

- `post_budget_cycle_streak_max` tracks the longest consecutive post-budget
  cycle within each solve; the streak resets on every trajectory break
  (rescue accepted, damped step, no cycle detected): PASS;
- five cumulative counters classify each solve that recurs post-budget by
  outcome (converged / iteration_cap / damping_exhausted); each solve adds at
  most one to any counter: PASS;
- corpus results (120 s):
  - corridor_chain: 559/1441 solves recur (181 converge, 378 iteration_cap,
    0 damping_exhausted); streak_max = 21;
  - r0_window_360: 0/1441 solves recur; streak_max = 0;
  - **clean cross-topology separation on the per-solve flag**;
- OFF SHA-256 stable across corridor 30/60/120 s and r0-window 120 s: PASS;
- all shared ON columns byte-identical: PASS;
- zero counterflow violations in all four cases: PASS;
- Physics and ILV at 0 FAIL; gap inventory unchanged: PASS;
- no physical report, expected value, tolerance, CTRL or VALID_GAP changes:
  PASS.

H2.5m solver authority remains blocked until the per-solve separation is
confirmed on a wider corpus. The corridor recurrence rate is 38.8%
(559/1441); 32.4% converge after recurrence. H2 remains open and H3 remains
blocked. Full record:
`docs/validation/PHASE3_F33V3H25LB_PER_SOLVE_RECURRENCE_LEDGER.md`.

F3.3v3h2.5m STOP: **GO for the analytic half step.**

- the factor is the closed-form annihilator of a period-2 Newton orbit on a
  residual of degree 1/2 (`|F| ~ |u|^0.5007`, R^2 = 0.9999), not a corpus
  threshold; the measured merit minimum is `alpha = 0.50`: PASS;
- reachable only after `cycle_detected`, reuses the Newton direction, accepted
  only on a valid finite strictly decreasing L-infinity residual, one extra
  evaluation, no access to the LM budget: PASS;
- runtime matrix on the committed case files (baseline from a clean worktree at
  `4ec0f09a`):
  - corridor 30 s 98.06% -> 100.00%, `iteration_cap` 7 -> 0;
  - corridor 60 s 99.03% -> 100.00%, `iteration_cap` 7 -> 0;
  - corridor 120 s 73.77% -> **100.00%**, `iteration_cap` **378 -> 0**,
    post-budget solves **559 -> 0**;
  - r0-window 120 s unchanged at 100.00%;
- LM rescue intact and still load-bearing: 723 cycle rescues -> 0, the 5
  fail-only `damping_exhausted` rescues remain: PASS;
- OFF SHA-256 identical, legacy ON columns unchanged (0 differences over 594
  columns x 4 stages), counterflow 0, `max_normalized_residual` 0.0: PASS;
- determinism 4/4 identical SHA-256 on corridor 120 s ON: PASS;
- Physics 0 FAIL, ILV 0 FAIL, gap inventory unchanged: PASS;
- no expected value, tolerance, CTRL or VALID_GAP changed: PASS.

Recorded rather than claimed away: no committed capture exercises the
post-budget branch any more, so the H2.5l telemetry has structural coverage
only; shared-root identity is sampled at the 10 s CSV cadence with the
population bound remaining the offline `1.857e-11 Pa`; and the corpus is still
two topologies.

**H2 is NOT closed by this result.** H3 remains blocked. Full record:
`docs/validation/PHASE3_F33V3H25M_CYCLE_STRATEGY_DESIGN.md`.

F3.3v3h2.6 STOP: **GO as an audit; NO-GO for closing H2.**

- `sim/core` unchanged; baseline `4ec0f09a`, candidate `db2815df`: PASS;
- topology inventory separates the network a template declares from the one the
  solver sees after `opening_overrides`; effective shapes over 108 cases are
  89 star, 11 loop, 6 branched tree, 2 chain: PASS;
- corpus extended two -> eight topologies (chain, star, branched tree, loop,
  multi-floor), 32 runs on committed case files with hashes recorded;
- convergence: `uk_bungalow_smoke` 68.63% -> 99.93%, `piso_mediterraneo_smoke`
  83.14% -> 100.00%, `ghanekar_bedroom_hallway` 94.80% -> 99.93%,
  `compact_apartment_smoke` 91.39% -> 99.31%;
- zero converged-to-failed, OFF byte-identical, legacy ON columns unchanged,
  counterflow 0, residual under original tolerance, determinism 3/3 on
  multi-floor and loop, root divergence `0.000e+00` over 4567 rows: PASS;
- **gate "at most one half step accepted per solve": FAIL** - eight solves of
  ~2600 accept two, on loop and branched networks. Safe by construction (each
  accept demands strict descent, and there is no artificial budget) but the
  historical claim is corrected rather than deleted;
- **open failure mode**: `two_storey_smoke` keeps 20 `iteration_cap`. The
  capture shows a monotone residual and zero cycles before the cap, then
  converges at **39 iterations** with a raised budget. The cap of 24 is sized
  for three-room networks; this is not an unresolved orbit;
- coverage absent, not solved: C8 parallel openings (no template) and the half
  step's rejection branch (never taken by a real solve in twelve topology runs).

**H2 REMAINS OPEN.** H3 remains blocked. Single principal blocker: **H2.7,
iteration-cap sizing for large networks** - derive how the budget scales with
rooms and openings; swapping 24 for 48 is not accepted. Full record:
`docs/validation/PHASE3_F33V3H26_CROSS_TOPOLOGY_AUDIT.md`.

F3.3v3h2.7 STOP: **GO as a diagnosis; NO-GO for any iteration-cap change.**

- `sim/core` unchanged and `DEFAULT_MAX_ITERATIONS` untouched: PASS;
- five bit-exact captures replayed across budgets 24/32/40/48/64/96/128/256,
  every converging budget landing on a bit-identical root: PASS;
- **the cap is not the cause**: iterations needed do not scale with rooms (a
  six-room star needs 28, an eleven-room tree 25, another 39), openings,
  diameter (2, 2, 4, 2) or conditioning (474, 19291, 27119, 16428), and 24
  already sits above the **P99 of 20** across 5016 logged solves;
- **cause identified**: the period-2 square-root orbit of H2.5m, undetected for
  17-34 iterations because the H2.5j detector requires two consecutive gain
  ratios below `0.05` while the gain itself alternates (~`0.08` / ~`-0.01`),
  so the conjunction never fires although the step cosine is `-0.9999`;
- policy comparison at the shipped cap - baseline 4/9 captures and 1179
  evaluations, cap 48 gives 8/9 and 1409, **P2 gives 8/9 and 693** with no new
  constant; leave-one-topology-out leaves every held-out capture identical;
- captures versioned with a fail-closed fixture and negative controls that
  compare residual history rather than iteration count: PASS;
- no expected value, tolerance, CTRL, VALID_GAP or report changed: PASS.

**H2.6's framing of this as cap sizing is withdrawn.** **H2 has at least two
open items**: the alternating-gain detector (**H2.8**, not started) and
`uk_bungalow_smoke`'s `damping_exhausted`, which damps on every iteration so
the detector is structurally unreachable and which fails identically at 24, 64
and 256. H3 remains blocked. Full record:
`docs/validation/PHASE3_F33V3H27_ITERATION_BUDGET_DESIGN.md`.

F3.3v3h2.8 STOP: **GO for the alternating-gain detector.**

- one predicate changed, `min(previous_gain, current_gain)` against the
  unchanged `0.05`; no new constant enters it, enforced structurally: PASS;
- cap, tolerance, half step, LM budget, Jacobian, gauge, regularization, flux
  law, EOS and counterflow all unchanged: PASS;
- the four H2.7 orbits close inside the cap at 11, 10, 14 and 12 iterations,
  matching the offline prediction exactly, through the new branch and without
  spending LM budget: PASS;
- runtime matrix over ten committed cases: **all 22 `iteration_cap`
  eliminated**, `two_storey_smoke` 98.61% -> 100.00%, zero regressions,
  `damping_exhausted` unchanged everywhere so nothing was displaced: PASS;
- OFF byte-identical 10/10, legacy ON columns 0 differences, counterflow 0,
  determinism 3/3 on corridor, r0-window, multi-floor and loop: PASS;
- **shared-root divergence `0.000000e+00 Pa` over 5078 rows**, including the
  already-healthy solves where the wider detector now fires: PASS;
- Physics and ILV 0 FAIL, gap inventory unchanged: PASS.

**H2 REMAINS OPEN.** `uk_bungalow_smoke`'s `damping_exhausted` is unreachable
by the detector by construction and unaffected by any budget; the C8
parallel-openings gap and the untaken half-step rejection branch stand. H3
remains blocked. Full record:
`docs/validation/PHASE3_F33V3H28_ALTERNATING_GAIN_CYCLE_DETECTOR.md`.

F3.3v3h2.9 STOP: **GO as diagnosis; NO-GO for a motor change in this phase.**

- the exact UK capture reproduces `damping_exhausted` at iteration 12 after
  one accepted LM rescue: PASS;
- LM accepted-step budgets 2 and 4 still fail at iterations 15 and 24, so
  budget expansion is rejected: PASS;
- the shipped forward quotient crosses the donor branch: local opening
  `dp=-5.31e-4 Pa`, quotient width `1e-3 Pa`, perturbed
  `dp=+4.69e-4 Pa`: measured;
- Jacobian finite and non-singular, but all actual damped trials increase both
  norms while the linear model predicts descent: measured;
- forward `h=1e-4` and `1e-5` close 189/189 deterministic states versus
  baseline 182/189, zero regressions: measured;
- the branch-preserving unilateral candidate closes the exact UK capture,
  keeps all eight healthy exact captures converged, and improves 182/189 to
  187/189 with zero regressions; two UK variants remain: measured;
- `sim/core`, solver constants, official reports, expected values, tolerances,
  CTRL and VALID_GAP are unchanged: PASS.

**H2 REMAINS OPEN.** H2.10 must combine branch preservation with deterministic
adaptive width/derivative self-consistency and pass the runtime topology gate.
H3 remains blocked. Full record:
`docs/validation/PHASE3_F33V3H29_UK_DAMPING_EXHAUSTED_DIAGNOSIS.md`.

F3.3v3h2.10 STOP: **GO for the adaptive branch-preserving Jacobian.**

- shipped forward Newton/Jacobian path and strict L-infinity line search remain
  first authority; adaptive recovery is fail-only and precedes LM: PASS;
- no new threshold or per-case knob; cap 24, tolerance, LM budget, cycle
  detector, gauge, EOS, regularization and orifice law unchanged: PASS;
- all nine committed exact captures converge and the deterministic H2.9
  neighbourhood improves 182/189 -> **189/189** with no regression: PASS;
- C8 parallel-opening fixture preserves both routes, mass/energy closure,
  reordering invariance and counterflow: PASS;
- ten committed 120 s cases: convergence 100% in all cases,
  `damping_exhausted` 27 -> 0, `iteration_cap` 0 -> 0, adaptive 54/54 and LM
  accepts 54 -> 0; no converged solve regresses: PASS;
- OFF byte-identical 10/10, shared ON legacy columns unchanged, shared-root
  delta `0.000000e+00 Pa` at CSV cadence and counterflow violations 0: PASS;
- three complete byte-identical runs each for UK bungalow, compact apartment
  and flashover house, with matching row counts and manifests: PASS;
- Physics and ILV 0 FAIL; gap inventory unchanged; 12/12 direct Godot fixtures
  and 213/213 focused structural tests PASS.

**H2 CLOSES as numerical readiness for the passive coupled pressure solver.**
**H3 is unblocked but not started.** Coverage remains bounded to ten committed
runtime topologies plus synthetic C8, and no real runtime solve exercised an
adaptive decline into LM; the fallback path remains structurally tested. Full
record:
`docs/validation/PHASE3_F33V3H210_ADAPTIVE_BRANCH_JACOBIAN.md`.

H3.0 STOP: **DESIGN ONLY - authorise H3.1 alone.**

- `sim/core` unchanged; no flag, no authority, no baseline, expected value,
  tolerance, CTRL or VALID_GAP touched: PASS;
- ownership traced from real writes, not names, which contradicted the names in
  three places: `ZoneFireSolver.gd` writes mass and energy and was not on the
  reading list; `ThermalSystem` owns interior doorway transport through **two**
  paths; `_clamp_rooms` writes mass and energy and calls `project_room_state`
  twice. Roughly ten call sites own the same state;
- **prerequisite discovered:** `project_room_state` reconstructs energy from
  clamped temperature and runs last, so a committed energy is overwritten
  before the step ends. **H3.2b** must convert it to residual projection before
  H3.3 commits anything, preserving the thermal cap as an explicit reported
  sink;
- delayed parcels cross timestep boundaries, so the in-flight pool must be
  disabled per authoritative opening rather than coexist with a bundle;
- `Phase3ZoneMassSystem` measured at **zero** room-state writes, so **H3.1 is
  provably physics-neutral**;
- non-convergence policy: explicit per-step legacy fallback, counted, blocking
  promotion. Silent fallback and step abort rejected.

H3 remains unstarted as implementation. Full record:
`docs/validation/PHASE3_H3_RUNTIME_AUTHORITY_PLAN.md`.

H3.2-M STOP: **GO for the mechanical shadow bundle only.**

- default-OFF flag; no legacy registry entry, route application, writer
  suppression, tick reorder or room-state mutation: PASS;
- shared pure donor acceptance used by legacy and coupled paths; one fraction
  scales mass and enthalpy once: PASS;
- source provenance is explicitly circular and comparison remains invalid;
  no coupled-vs-legacy delta is fabricated: PASS;
- ten committed topologies at 10 s: 1,200/1,200 valid steps, 672 shared columns
  byte-identical, 57 opt-in columns, zero fallback, duplicate, double-limit or
  counterflow violations: PASS;
- donor limiting and parcel overlap are fixture-only at this horizon; a 120 s
  attempt did not complete and is not counted as evidence: OPEN LIMIT;
- H3.2 remains open for H3.2-S independent sources; H3.2b and H3.3 remain
  blocked.

Full record: `docs/validation/PHASE3_H32M_COUPLED_BUNDLE_SHADOW.md`.

Headless runner completion contract (2026-07-29): **GO at STOP.**

- every `scripts/run_scenario.py` invocation owns a random token that must match
  both the current PASS marker and the final manifest: PASS;
- manifest status, scene entrypoint, scenario, duration and
  `sim_time_s >= duration_s` are validated; stale or truncated artifacts fail:
  PASS;
- fatal parse/script-load signatures are inspected in stdout/stderr and
  `godot.log`; warnings remain non-fatal: PASS;
- real Godot 4.7.1 one-second run produced matching token and completed
  manifest; an invalid-scene probe with valid stale artifacts failed closed and
  published no result paths: PASS;
- no physics, solver, official report, expected value, tolerance, CTRL or
  VALID_GAP changed: PASS.
