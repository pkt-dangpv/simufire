# Phase 3+ F3.0k non-HVAC cross-path audit

Date: 2026-07-15

## Decision

**NO-GO for canonical authority.** The shadow contracts delivered through
F3.0j are internally conservative, but the non-HVAC transaction does not yet
own every physical mass, energy, O2 and CO/CO2/HCN mutation. No motor change,
new telemetry, baseline, expected value, tolerance, control envelope or gap
classification was made in this audit.

The result is not a failure of the existing contracts. Every exercised
species contract closed exactly. The blocker is incomplete and ambiguous
cross-path ownership outside those contracts.

## Scope and method

The audit combined:

1. A source-level inventory of every non-HVAC writer for upper/lower gas mass,
   energy, O2, CO, CO2 and HCN.
2. Classification of each write as exact owner, partial owner, projection or
   reconcile, unowned physical flux, or parallel legacy mechanism.
3. Eight sequential Godot 4.6.3 console runs in `runs/phase3_f30k`, with copied
   case JSONs stripped of official report paths.
4. One matching OFF/ON pair on `cfast_two_room_door_open` to reconfirm that the
   shadow remains passive.

HVAC was excluded by design. None of the eight cases contains HVAC config.
Godot was run outside the sandbox, one process at a time. All nine runs ended
with `RUN_SCENARIO PASS`, and no Godot process remained afterward.

## Source ownership map

| State or mechanism | Current owner | Classification | Audit decision |
|---|---|---|---|
| Combustion CO/CO2/HCN generation | `CombustionSystem._apply_species_generation_result()` | `OWNED_EXACT` | Keep. The exact accepted result is emitted before legacy writes. |
| Combustion upper/lower O2 sinks | `OxygenExchangeSystem` accepted sink results | `OWNED_PARTIAL` | Keep, but bulk O2 depletion still has no canonical zonal owner. |
| Sealed plume mass/enthalpy and convective combustion energy | `ThermalSystem._phase3_shadow_flux_results` | `OWNED_PARTIAL` | Exact only inside `_phase3_shadow_sealed_room_scope()`. It cannot close opened or multi-room cases. |
| Direct doorway species | GES `doorway_species_direct` | `OWNED_EXACT` | Keep. |
| Delayed CO/CO2/HCN parcels | GES parcel lifecycle | `OWNED_EXACT` for species | Gas mass, enthalpy, O2, smoke and irritants in the same physical parcel remain unowned. |
| Horizontal background/counterflow species | GES immediate events | `OWNED_EXACT` for CO/CO2/HCN | Keep. Associated gas/energy/O2 transport remains unowned. |
| Vertical species paths | GES vertical net/directed events | `OWNED_EXACT` for CO/CO2/HCN | Keep. Associated gas/energy/O2 transport remains unowned. |
| Exterior purge species | GES purge events | `OWNED_EXACT` for CO/CO2/HCN | Keep. Associated gas/energy/O2 boundary flow is not a complete canonical transaction. |
| Thermal doorway/background/interlayer species | `ThermalSystem._transfer_hot_gas_contaminants()` and Phase 2F mixing | `OWNED_EXACT` | Keep as exact observations until semantic arbitration selects the authoritative physical path. |
| Thermal doorway, background, radiation, wall and stairwell gas/energy | `ThermalSystem` legacy writes | `UNOWNED` | Must receive explicit pre-mutation mass/enthalpy contracts or be retired from canonical mode. |
| GES parcel/background gas and energy | `GasExchangeSystem` legacy writes | `UNOWNED` | Must travel in the same canonical transaction as the species they carry. |
| O2 entrainment, ACH, exterior replenishment, room exchange and diffusion | `OxygenExchangeSystem` and Thermal doorway/counterflow writes | `UNOWNED` | Requires explicit zonal/boundary requests. |
| CO oxidation | `SimulationEngine._step_co_oxidation()` | `UNOWNED` | Needs one exact CO sink plus CO2 source event before any authority promotion. |
| Suppression energy removal and temperature caps | `SimulationEngine` / Thermal legacy paths | `UNOWNED` | Defer to the non-HVAC suppression phase, but keep the global gate closed. |
| Upper/lower species scaling and clamps | Thermal sync functions and `SimulationEngine._clamp_rooms()` | `PROJECTION_OR_RECONCILE` | Not physical flux owners. Residuals must remain visible; do not create a projection bucket to force closure. |

## Semantic overlap

The request identity system found no duplicate request IDs. That proves each
implemented event is applied once; it does **not** prove that one physical
opening is represented by only one legacy mechanism.

In the open and multi-room controls, the runtime activates both:

- Thermal doorway/background hot-gas and species transport; and
- GES direct doorway, background/counterflow or delayed-parcel transport.

These writes use different identities and formulas but can represent the same
physical connection and time interval. They are classified as
`PARALLEL_LEGACY_MECHANISM`, not `DUPLICATE_CODE_OWNER`. Canonical authority
requires an arbitration rule that chooses one physical owner per connection,
direction, zone and timestep. Adding a shared identity after the fact would
hide the ambiguity rather than solve it.

## Runtime results

All contract-specific CO/CO2/HCN residuals were exactly zero in every case.
No duplicate owner, orphan parcel, duplicate parcel ID or negative parcel
balance was observed. Inventory limiting remained visible as rejected mass.

| Scratch case | Rows / rooms | Max global mass residual (kg) | Max global energy residual (kJ) | Contract residual | `needs_flux_owner` | Relevant paths |
|---|---:|---:|---:|---:|---:|---|
| `single_closed_on` | 78 / 6 | 0.018094 | 14.624 | 0 | 1 | sealed plume, combustion, purge |
| `fuel_sealed_on` | 150 / 6 | 0.025836 | 7.571 | 0 | 1 | O2/species, background/counterflow, purge |
| `two_room_on` | 78 / 6 | 0.004947 | 1.450 | 0 | 1 | GES doorway/parcels plus Thermal doorway/background |
| `corridor_on` | 78 / 6 | 0.006849 | 2.008 | 0 | 1 | GES doorway/parcels plus Thermal doorway/background |
| `stairwell_on` | 468 / 13 | 0.104034 | 30.497 | 0 | 1 | horizontal, vertical, parcel, Thermal, purge |
| `v4_remote_on` | 1326 / 6 | 0.090405 | 26.495 | 0 | 1 | remote species parcels and parallel doorway paths |
| `partial_window_on` | 150 / 6 | 0.450829 | 132.171 | 0 | 1 | exterior boundary/purge |
| `ppv_on` | 1926 / 6 | 0.811302 | 237.826 | 0 | 1 | PPV purge, parcels and parallel doorway paths |

The OFF/ON control retained 78 rows, 115 shared legacy columns and zero value
differences. OFF had 115 columns and ON had 237. The shadow remains a no-op.

`phase3_shadow_zero_o2_flame_flag` was observed in the PPV, stairwell and v4
controls. This is the already documented zombie-ILV motor debt. It is not
caused by the shadow, but it remains a hard prerequisite for F3.1 authority.

## Validation checkpoint

| Gate | Result |
|---|---|
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Validation guardrails | 10/10 PASS |
| Required validation | 348/353 PASS, 5 documented VALID_GAP |
| Artifact integrity | 29 official CSV PASS; 101 run packages complete, 0 partial/malformed |
| Full pytest | 804 PASS / 17 historical failures / 12 subtests PASS |

The first sandboxed pytest invocation was discarded because Windows denied
pytest access to its temporary directory and produced false cascading errors.
The table reports the valid rerun outside the sandbox.

## Why no telemetry patch was added

Existing telemetry already answers the gate:

- each implemented contract exposes accepted, rejected and residual mass;
- parcel lifecycle conservation is explicit;
- duplicate request identities are counted;
- shadow-vs-legacy mass/energy residuals remain visible; and
- `needs_flux_owner` is set in all audited cases.

More counters would refine attribution but would not change the architectural
decision. The next useful work is ownership and arbitration, not another
post-mutation observer.

## Follow-up: F3.0k.1a semantic claims

F3.0k.1a is now complete as passive telemetry. A shared key based on opening,
room direction, zonal direction and quantity detects the predicted
Thermal/GES overlap before mutation. Interior doorway, corridor, stairwell,
remote-CO and PPV controls report CO/CO2/HCN conflicts (mask 56); sealed and
exterior-window controls report none. Every connection is identified and
OFF/ON legacy values remain identical. See
`PHASE3_F30K1A_SEMANTIC_OWNERSHIP.md`.

The original NO-GO for authority is unchanged. F3.0k.1b must select one
provisional shadow owner and complete gas mass, enthalpy, O2 and CO-oxidation
claims before F3.1.

## Next phase: F3.0k.1b ownership completion

F3.0k.1 remains passive and default OFF. It must precede F3.1.

1. Use the delivered step-local connection key and measured conflict set.
2. Choose one provisional shadow owner for each horizontal, vertical, exterior and
   delayed path. Thermal and GES may supply solver outputs, but may not both
   own the same physical transfer.
3. Extend the selected opening/parcel requests to carry gas mass, enthalpy and
   O2 with CO/CO2/HCN under one accepted fraction.
4. Add exact events for unowned O2 boundary/mixing paths and CO oxidation.
5. Keep projections and clamps outside ownership and visible as residuals.
6. Repeat this audit on the same HVAC-disabled matrix.

### F3.0k.1b STOP gate

- Contract residuals remain zero and rejected inventory remains explicit.
- `phase3_shadow_duplicate_owner_flag=0` and semantic arbitration reports no
  parallel owner for an active connection.
- `phase3_shadow_needs_flux_owner_flag=0` for the declared non-HVAC scope.
- Building and room mass/energy/O2/species close without a projection bucket.
- OFF/ON shared legacy values remain identical.
- Zero-O2 flame remains visible and blocks F3.1 until its dedicated regression
  is fixed.
- Physics and ILV have zero FAIL; guardrails and gap inventory remain green.

HVAC remains deferred to F3.5 and is not part of any F3.0k.1 closure claim.
