# Phase 3 H3.2-S Independent Source Diagnosis

Date: 2026-08-03
Decision: **NO-GO for implementation from the current owner ledger**

## Objective

H3.2-S must feed the coupled pressure solver with mass and sensible-energy
sources that are independent of the legacy interior-opening result. In
particular, the source constructor must not use either:

```text
post_state - pre_state
canonical_interior_opening_by_room
```

The current H2 preview uses both through
`(post - pre) - legacy_interior`. H3.2-M therefore marks its source provenance
as circular and its coupled-versus-legacy comparison as invalid.

## Actual Tick Order

`SimulationEngine.step()` executes the relevant writers in this order:

1. pool-fire controls;
2. optional pre-HRR O2 exchange;
3. combustion and CO oxidation;
4. optional post-HRR O2 exchange;
5. `ThermalSystem.step()`;
6. suppression and steam decay;
7. `GasExchangeSystem` pressure venting, PPV and smoke/parcel transport;
8. HVAC;
9. passive fuel and spread;
10. two-zone reconcile;
11. `_clamp_rooms()` and `ZoneFireSolver.project_room_state()`;
12. passive Phase 3 finalization.

H3.1 snapshots the state after each stage. Those snapshots close attribution
of the completed legacy step, but a stage delta is not necessarily one physical
owner.

## Owner Inventory

| Owner or stage | Writes mass/energy | Classification | Independent payload available? | H3.2-S status |
|---|---|---|---|---|
| Pool-fire controls | No zone mass/energy; changes fire HRR ceiling | local control | Yes, but no source payload needed | usable |
| Combustion | Local products/HRR; thermal convective energy is applied later | local source | Stage delta exists; canonical combustion/thermal requests cover parts | partially usable |
| O2 exchange | O2 consumption, ACH exterior exchange, delayed O2 and opening exchange | local sink + exterior boundary + interior transport | O2 events exist, but zone gas mass/energy source does not | excluded from current mass/energy source |
| Thermal plume and surfaces | Plume redistribution, convective fire heat, radiation, wall exchange, cooling/reconcile | local source + internal redistribution + exterior sink + numerical projection | Some canonical flux events exist | incomplete |
| Thermal doorway paths | Upper transfer, lower return and thermal counterflow | interior transport | Three explicit H3.1 transfer mechanisms exist | explicitly excluded |
| Suppression | Local thermal sink and steam effects | local source/sink | Stage delta exists | usable as a stage owner |
| Gas pressure venting / PPV | Exterior loss/inlet plus projection calls | exterior boundary + numerical projection | Species purge events exist; gas mass/enthalpy events do not cover every path | incomplete |
| Gas smoke transport | Immediate inter-room transfer, background exchange and delayed parcels | interior transport | Parcel create/resolve/cancel ledger exists; immediate/background gas mass and enthalpy lack one complete owner ledger | explicitly excluded but incomplete |
| Delayed parcel pool | Cross-timestep gas mass/enthalpy inventory | interior transport in flight | Complete create/deliver/cancel/in-flight totals exist | explicitly excluded |
| HVAC | Exterior/mechanical boundary and local thermal effects | exterior boundary | Stage delta exists, but HVAC is intentionally deferred in the motor plan | usable only as a coarse boundary stage |
| Passive fuel/spread | Fire-state changes; may trigger later combustion | control/other | Stage delta exists | no direct source in the same step |
| Reconcile | Rebuilds two-zone state after legacy writers | numerical correction | Stage delta exists | residual only, never physical source |
| Clamp/projection | Clamps and reconstructs mass/energy from geometry/temperature | numerical correction | Projection trace and boundary-energy ledger exist | residual only; H3.2b blocker |

## Why H3.1 Is Insufficient

H3.1 has two useful granular ledgers:

- the three thermal doorway mechanisms; and
- delayed parcel creation, resolution, cancellation and in-flight inventory.

However, its principal room records are deltas between stage snapshots. The
`thermal` stage combines plume redistribution, fire heat, wall exchange,
ambient losses, doorway transport and projection. The `gas_exchange` stage
combines exterior pressure venting, PPV, immediate/background interior gas
transport, delayed parcel operations and projection callbacks.

Deriving a source as either of the following would still depend on accepted
legacy transport:

```text
thermal_stage_delta - thermal_doorway_events
gas_exchange_stage_delta - parcel_events - interior_exchange
```

That is subtraction from a legacy post-mutation delta, not an independently
measured source. It would reproduce the same circular structure under a new
name.

The gap is material, not merely missing labels:

- `ThermalSystem` contains many direct zone mass/energy writes outside the
  three doorway event sites.
- `GasExchangeSystem` directly debits and credits upper gas mass and enthalpy
  for immediate, delayed and background paths, while pressure venting removes
  upper-layer fractions through callbacks.
- `project_room_state()` and `_clamp_rooms()` can overwrite energy after those
  owners run, so a final state delta cannot recover the original physical
  source uniquely.

## Required Precursor

Before H3.2-S can be implemented, add a passive **physical owner event ledger**
at the actual mutation sites. Each event must carry:

- stable owner/event ID and room ID;
- `mass_delta_kg` and `energy_delta_kj`;
- classification: `local_source`, `exterior_boundary`,
  `interior_transport`, `delayed_parcel`, or `numerical_correction`;
- source/destination room and zone for transport;
- step-local duplicate protection.

The ledger must be emitted before mutation or from measured pre/post values at
that single mutation site. It must not be reconstructed from a whole-stage or
whole-step delta. Projection and clamp events remain residuals, never source
physics.

Minimum missing coverage:

1. Thermal plume/fire/surface/ambient owners separated from doorway paths.
2. Gas exterior pressure/PPV mass and enthalpy separated from all interior
   transport.
3. Immediate and background gas mass/enthalpy transport, alongside the already
   complete delayed-parcel ledger.
4. HVAC boundary ownership when HVAC work resumes; until then comparisons for
   HVAC-active cases must remain invalid.

Only after this ledger closes
`pre + physical sources + legacy interior transport + numerical residual = post`
without using a remainder may H3.2-S set `source_inputs_independent=true` and
`comparison_valid=true`.

## STOP Decision

**NO-GO.** No H3.2-S motor patch was written. Building sources from the current
H3.1 stage deltas would violate the non-circularity gate. H3.2-M remains a valid
mechanical shadow bundle with explicitly invalid comparison. H3.2b remains a
hard prerequisite, and H3.3 remains blocked.

## H3.2-S0 follow-up audit

The mutation-site inventory found 112 direct mass/energy writes. The initial
five-value event classification is insufficient because it cannot represent
physical lower/upper redistribution inside one room without falsely calling it
a source, inter-room transport or numerical correction. H3.2-S0 therefore also
stopped before motor edits. The required split is S0a contract, S0b thermal,
S0c gas and S0d integration. See
`PHASE3_H32S0_PHYSICAL_OWNER_LEDGER_AUDIT.md`.
