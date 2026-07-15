# Phase 3+ current workplan

Date: 2026-07-15

## Current baseline

- Guardrails: 10/10 PASS.
- Physics coherence: 0 FAIL.
- ILV suite: 0 FAIL.
- Required validation: 348/353 PASS.
- Active VALID_GAP: 5 checks.
  - Group A: `cfast_r0_window_360` x3.
  - Group C: `cfast_corridor_chain` x2.

This phase starts from a clean rule: no more per-case tuning for Groups A/C
and no more local pressure/projection fixes. The remaining gaps require a
canonical two-zone mass/energy/O2/species transaction.

## Documents of record

- Architecture: `docs/validation/PHASE3_CANONICAL_TWO_ZONE_ARCHITECTURE.md`
- F0 diagnostics: `docs/validation/PHASE3_F0_ZONE_DIAGNOSTICS.md`
- F2.2a pressure diagnosis: `docs/validation/PHASE3_F22A_PRESSURE_VENT_DIAGNOSIS.md`
- HVAC deferral decision: `docs/validation/PHASE3_HVAC_DEFERRED_DECISION.md`
- F3.0k cross-path audit: `docs/validation/PHASE3_F30K_CROSS_PATH_AUDIT.md`
- F3.0k.1a semantic claims: `docs/validation/PHASE3_F30K1A_SEMANTIC_OWNERSHIP.md`
- F3.0k.1b passive arbitration: `docs/validation/PHASE3_F30K1B_PASSIVE_ARBITRATION.md`
- Gap inventory: `docs/validation/GAPS_INVENTORY.md`
- Handoff: `docs/HANDOFF_CURRENT_STATE.md`

## Closed routes

| Route | Decision | Reason |
|---|---|---|
| JSON/per-case tuning for Group A/C | Closed | Sweeps and experiments did not close both target checks without breaking guards. |
| F2.1 ledger-aware projection | NO-GO | Lower gas collapsed and volume closure exploded when projection became honest. |
| Local pressure-vent patch | NO-GO | Pressure/vent path mixes gas mass, smoke stock and EOS backfill; fixing one term locally is unsafe. |
| Retrying `project_room_state()` compensation | Closed | It hides mass creation/deletion instead of giving ownership to physical fluxes. |

## Active route

F3.0 shadow canonical two-zone state through F3.0j are implemented. F3.0k
completed the non-HVAC cross-path audit with a NO-GO for authority. Direct
doorway transport, delayed parcels and immediate horizontal background/
counterflow, legacy vertical-opening transport and all GES exterior purge
paths plus ThermalSystem hot-gas transport for CO/CO2/HCN now have separate
contracts, and those contracts close exactly. The remaining blocker is
incomplete mass/energy/O2 ownership plus semantic overlap between Thermal and
GES legacy paths.
F3.0k.1a provides a stable pre-mutation connection key and proves the overlap
at runtime. F3.0k.1b now selects provisional shadow owners and suppresses the
duplicate Thermal opening-species request only inside the passive shadow.
It also records the exact legacy CO sink/CO2 source for CO oxidation.

F3.0k.1b returned a partial GO: gas mass, enthalpy and O2 remain unresolved on
opening and parcel paths because the current one-route request cannot express
their multi-zone bundle under one accepted fraction. CO oxidation also lacks
its legacy O2 sink. The active route is F3.0k.1c: add an atomic transaction
group or route matrix and explicit experimental O2 chemistry. Do not promote
F3.1 authority yet.

## Binding priority decision: HVAC last

HVAC is not part of the remaining F3.0 shadow sequence. It stays on the legacy
path until its behavior has been redesigned and approved. The canonical route
may advance using HVAC-disabled cases, but all closure claims must be labelled
non-HVAC and existing HVAC findings must remain visible.

The revised order is:

1. F3.0j ThermalSystem species transport. Completed.
2. F3.0k non-HVAC cross-path conservation audit. Completed NO-GO.
3. F3.0k.1a semantic claim telemetry. Completed, passive GO.
4. F3.0k.1b passive arbitration and CO-oxidation compatibility. Completed, partial GO.
5. F3.0k.1c atomic multi-zone bundle and explicit O2 chemistry. Current target.
6. F3.1 authoritative sealed mode plus zero-O2 extinction regression.
7. F3.2 exterior pressure/leakage for Group A.
8. F3.3 interior openings for Group C.
9. F3.4 remaining non-HVAC species, suppression and FED.
10. HVAC-R0 redesign specification.
11. F3.5 HVAC canonical integration as the last subsystem.
12. F3.6 final corpus promotion and legacy retirement.

Do not change this order from an implementation prompt. Re-prioritizing HVAC
requires an explicit planning decision and synchronized documentation updates.

The first implementation must be default OFF and read-only with respect to
legacy physics. It should build a shadow state from:

1. A pre-step snapshot.
2. Explicit flux requests.
3. One transaction applied exactly once.
4. Residuals against the legacy post-step state.

No request may be derived by observing a mutation after it already happened.
That would make the ledger circular.

### F3.0 delivered

- New `Phase3ZoneMassSystem.gd` with immutable request identity and cause.
- Pre-step shadow snapshot for mass, energy, O2 and CO/CO2/HCN by zone.
- Proportional inventory limiting, rejected-mass telemetry and duplicate-id
  detection.
- Ten opt-in CSV fields; legacy schema and values remain unchanged when OFF.
- No authoritative request adapters yet. `needs_flux_owner` is the expected
  signal until a subsystem provides a pre-mutation physical output.

## F3.0a delivered

- Pure preview plus exact apply for lower-to-upper plume transfer.
- Request carries gas mass, enthalpy and O2 under one accepted fraction.
- Adapter is shadow-only and restricted to rooms without active openings.
- Zero-O2 flaming is visible but remains a legacy motor debt.
- Legacy outputs are invariant OFF and ON.

## F3.0b minimum scope

1. Produce a passive combustion result before any consumer mutates zonal state.
2. Assign exactly one owner each for convective heat, O2 sink and species.
3. Reconcile ordering between CombustionSystem, OxygenExchangeSystem and
   ThermalSystem without reading post-mutation deltas.
4. Start with energy only if O2/species cannot yet share a safe contract; do
   not present partial ownership as full combustion closure.

## F3.0b delivered

- `ThermalSystem` emits the exact convective-energy value it already applies,
  before mutating `upper_energy_kj`; Engine performs translation only.
- The request is exterior-to-upper, has zero gas mass, and owns no O2 or
  species. `phase3_shadow_combustion_owned_mask=1` means energy only
  (`energy=1`, `O2=2`, `species=4`).
- The adapter remains restricted to rooms without active openings and is
  shadow-only/default OFF.
- O2 and species were deliberately deferred: combustion selects yields and O2
  references, while OES owns the actual O2 mutation. Reading either after the
  step would make the ledger circular.
- A 60 s OFF/ON control had 42 rows, 115 shared legacy columns and zero value
  differences. The ON run had two owned causes, zero rejected requests and
  zero duplicate owners.

## F3.0c delivered

- `OxygenExchangeSystem` owns the accepted upper, explicit-lower and
  plume-lower O2 removals. Each result is calculated from the same before/after
  fractions used by legacy and is recorded before assignment.
- Requests are zone-to-exterior, O2-only. Engine translates the result without
  reading HRR, Thornton accumulators or post-step deltas.
- The bulk O2 path remains deliberately unowned because it has no canonical
  upper/lower split. In legacy modes that apply bulk plus upper depletion, the
  zonal request is partial and the remaining shadow residual stays visible.
- `phase3_shadow_combustion_owned_mask` is a true bit mask: energy=1,
  zonal O2=2, species=4.
- Runtime OFF/ON retained 42 rows and 115 identical legacy columns. The sealed
  control reached mask 3 with zero rejected or duplicate requests. The zombie
  ILV control retained all 7 zero-O2 flame hits.

## F3.0d delivered

- `CombustionSystem` emits one result after the carbon clamp and before species
  writes. Exact totals preserve legacy arithmetic; upper/lower maps define the
  canonical zonal source without creating a second request.
- CO follows the Phase 2G split. CO2 and HCN enter upper. The CO2 tracer,
  irritants and smoke remain outside this contract.
- Engine translates results only. Pool/backdraft energy already feeds the
  accepted generation values upstream, so it is not added again.
- OFF remained identical to F3.0c and ON changed no legacy value across 42 rows
  and 115 columns. A VC control reached ownership mask 7 with zero duplicates;
  the zombie-ILV control retained all 7 known hits.

## F3.0e delivered

- Ownership is limited to the immediate canonical two-zone opening path.
  GasExchangeSystem computes one `doorway_species_direct` object with explicit
  source/destination zones, records it pre-mutation and applies the same object
  to legacy CO/CO2/HCN delta dictionaries.
- Engine performs translation only. It contains no opening-flow, concentration,
  headroom, cut-ratio, parcel or net-transport formulas.
- Background/counterflow, exterior purge, HVAC, thermal transport and all
  delayed parcel paths remain unowned and visible through residuals.
- Exact checkpoint/OFF/ON proof: 42 rows, 115 legacy columns, zero differences.
  Two-room, corridor and remote-CO controls had nontrivial requests, zero
  rejected species and zero duplicate ownership. Zombie ILV retained 7 hits.

## F3.0f delivered

- Delayed parcels receive one monotonic identity at carve. That identity
  survives across timesteps and terminates at delivery/refund or cancellation.
- GES emits exact lifecycle events from the values already applied by legacy.
  Total and upper species maps preserve the real CO/CO2/HCN zonal split;
  `Phase3ZoneMassSystem` derives only the complementary lower map.
- The persistent reservoir is not reset by `begin_step`; full simulation reset
  clears GES and shadow together. Engine forwards events without formulas.
- Telemetry reports in-flight CO/CO2/HCN, lifecycle totals, active parcels,
  request rejection, anomalies and conservation residual. OFF schema remains
  at 115 columns; ON has 157 and changes no shared value.
- Two-room, corridor and v4 controls closed exactly. The v4 control exercised
  0.095449 kg of refunds. No control produced rejection, orphan delivery,
  duplicate identity or negative balance.
- Smoke, irritants, O2 and parcel gas/energy remain unowned. This phase is
  passive and does not authorize canonical writes to `RoomModel`.

## F3.0g delivered

- `GasExchangeSystem` records the exact horizontal background deltas before
  writing the legacy dictionaries. Signed net values choose the real source;
  CO carries its upper share while bulk-only CO2/HCN remain lower-zone.
- The no-delay counterflow records both gross directions for CO, CO2 and HCN,
  including each source's upper share. It is not collapsed to a net value and
  cannot overlap the delayed parcel branch.
- Engine forwards events without transport formulas. The shadow component
  splits upper/lower, limits by its own inventory and exports cumulative
  mechanism totals, rejection and per-species conservation.
- OFF/ON proof retained 42 rows and 115 identical legacy columns; ON has 171.
  Background and counterflow residuals were zero in all audited controls.
  Parcel conservation is now also exported separately for CO, CO2 and HCN.
- Small shadow rejection remains intentionally visible while producers outside
  the ledger are unresolved. No legacy state, FED result, baseline or
  tolerance changed. The 7 known zero-O2 flame hits remain visible.
- Vertical-opening exchange, exterior purge, HVAC, thermal transport, smoke,
  irritants and O2 counterflow remain outside ownership.

## F3.0h delivered

- Both legacy vertical helpers emit exact events before their delta writes.
  Net CO is split into independent upper and complementary lower movement, so
  the two zones may travel in opposite room directions without cancellation.
- Directed CO preserves the existing upper/lower split. CO2 and HCN are
  lower-only because neither helper mutates their upper stocks. Smoke,
  irritants and O2 remain explicitly outside this contract.
- The canonical two-zone opening path returns before the legacy vertical
  branch, preventing overlap with F3.0e. Delayed and horizontal paths retain
  their own identities from F3.0f/F3.0g.
- OFF/ON proof retained 12 rows in the short control and 793 rows in the real
  two-storey control, with 115 shared legacy columns and zero differences.
  The real path emitted 2,154 vertical requests with zero rejection,
  duplicate ownership or per-species residual.
- A deterministic Godot harness exercised net and directed branches for CO,
  CO2 and HCN, including one opposite-zone CO direction. A horizontal control
  kept every vertical metric at zero.
- Exterior purge, HVAC, thermal transport, smoke, irritants and O2
  counterflow remain outside ownership.

## F3.0i delivered

- GES owns one explicit room-to-exterior event stream for eight purge
  mechanisms: pressure venting, exterior smoke vent, natural ventilation,
  ACH, outside-open purge, post-fire purge and PPV inlet/exhaust.
- Every event is recorded before the associated legacy stock or delta write.
  Exact total and upper CO/CO2/HCN values are carried; the lower map is the
  bounded complement. No purge mass is inferred from post-step stock.
- Events have per-step identities and mechanism names. The shadow transaction
  reports requested, accepted and rejected mass, upper/lower totals,
  mechanism totals, duplicates and separate species residuals.
- OFF/ON proof retained 150 rows and 163 shared columns with zero differences.
  A real ventilated control closed 1.144611 kg exactly; a sealed control
  emitted zero. PPV closed `requested = applied + rejected` to floating-point
  precision while exposing 0.566436 kg of inventory rejection.
- At the F3.0i checkpoint, HVAC and Thermal species transport remained
  explicitly unowned and could not reuse a GES purge identity. F3.0j has now
  assigned the Thermal owner; HVAC remains deferred until F3.5. Smoke,
  irritants and O2 are also outside the purge phase.

## F3.0j delivered

- `ThermalSystem` emits exact pre-delta events for CO, CO2 and HCN from its
  main doorway hot-gas carry and both background heat-exchange paths.
- Optional Phase 2F CO interlayer mixing has a separate upper-to-lower event.
- The contract preserves different source and destination zonal splits through
  a conservative 2x2 route matrix; it never infers a flux from final stocks.
- Projection/reconcile writes, exterior purge, smoke, irritants and HVAC are
  explicitly excluded.
- A 120 s OFF/ON control retained 78 rows and 115 shared legacy columns with
  zero differences. ON recorded all three species, zero rejection, zero
  duplicates and zero conservation residual.

## STOP gate for F3.0

Required before commit:

- `phase3_canonical_zone_shadow_enabled=false` is bit-identical to HEAD for a representative run.
- CSV schema is unchanged with the flag OFF.
- Shadow mode changes no existing legacy columns.
- No physical state is mutated by the shadow transaction.
- Every request is built from pre-step state or an explicit solver output.
- No parcel, gas mass, O2 or species has duplicate ownership.
- Guardrails PASS.
- Physics suite has 0 FAIL.
- ILV suite has 0 FAIL.
- New focused tests PASS.

## Rollback criteria

Rollback the F3.0 attempt if:

- any default-OFF behavior changes;
- the ledger needs post-mutation deltas to close;
- residuals are hidden by a projection/clamp bucket;
- zero-O2 flaming behavior is reproduced in canonical shadow without being
  visible as a failure signal;
- a subsystem emits a request from a separately reconstructed value instead of
  reusing the exact pre-mutation result applied to legacy.

## F3.0k audit decision

The eight-case runtime matrix closed every implemented species contract with
zero residual and no duplicate request identities, but every case retained
`phase3_shadow_needs_flux_owner_flag=1`. Source audit found unowned gas/energy
and O2 paths, unowned CO oxidation and semantic overlap between Thermal and
GES doorway/background mechanisms. See `PHASE3_F30K_CROSS_PATH_AUDIT.md`.

## F3.0k.1a delivered

- One step-local semantic key now joins connection, room direction, zonal
  direction and quantity before legacy mutation. Producer, transport family
  and boundary kind remain metadata so parallel owners collide visibly.
- Stable identities cover building openings, exterior purge, room interlayer
  movement and chemical generation. Delayed parcels claim only at creation.
- Eight shadow-only CSV fields report claim/conflict count, quantity mask,
  contested amounts and unknown connection identities.
- Runtime controls report mask 56 (CO + CO2 + HCN) on interior doorway,
  corridor, stairwell, remote-CO and PPV paths. Sealed and exterior-window
  controls report zero conflicts. All controls report zero unknown identity.
- OFF/ON retained 78 rows and 115 identical legacy columns; ON has 245.
- This is passive telemetry only. It does not choose an owner, suppress a
  legacy path or authorize F3.1.

## F3.0k.1b delivered

- Provisional owners are explicit for opening, interlayer, combustion and
  chemical-conversion quantities. Raw conflicts remain visible.
- GES-owned opening CO/CO2/HCN claims suppress the parallel Thermal request
  only inside the shadow transaction. Legacy physical writers remain active.
- Accepted, suppressed and unresolved claims have separate counts, masks and
  amounts. Missing gas mass, enthalpy and O2 use unresolved mask 7.
- CO oxidation now emits an exact upper CO sink and lower compatibility CO2
  source before legacy mutation. Carbon closes exactly; the absent legacy O2
  sink remains unresolved.
- Eight runtime controls have zero unresolved multi-producer conflict. The
  OFF/ON pair retained 78 rows and 115 identical legacy columns; ON has 260.
- Complete ownership is NO-GO because one accepted fraction cannot yet bind
  the observed multi-zone gas/energy/O2/species routes. F3.1 is not authorized.

## Next prompt target

Use GPT-5.6 Sol for F3.0k.1c. Design an atomic transaction group or route
matrix that applies exact pre-mutation gas mass, enthalpy, O2 and zonally split
species under one accepted fraction. Add the stoichiometric CO-oxidation O2
sink only as an explicit experimental shadow contract with tests and a STOP
gate; do not silently change legacy physics. Do not use projection/clamp
residuals as fluxes, do not enable authority and do not touch HVAC. HVAC
remains deferred until F3.5.
