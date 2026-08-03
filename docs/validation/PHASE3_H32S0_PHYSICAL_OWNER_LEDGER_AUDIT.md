# Phase 3 H3.2-S0 Physical Owner Ledger Audit

Date: 2026-08-03
Decision: **NO-GO before implementation; event contract is incomplete**

## Scope audited

The audit enumerated direct assignments to `upper_gas_kg`, `lower_gas_kg`,
`upper_energy_kj` and `lower_energy_kj` in the active engine writers.

| File | Direct mutation statements |
|---|---:|
| `ThermalSystem.gd` | 58 |
| `ZoneFireSolver.gd` | 27 |
| `GasExchangeSystem.gd` | 16 |
| `SimulationEngine.gd` | 11 |
| **Total** | **112** |

This is a source-level count, not a count of physical events at runtime. Several
statements belong to one atomic transfer, while one helper can be called by
several physically distinct owners.

## Existing authoritative observations

These must be reused rather than duplicated:

- `ZoneFireSolver` projection trace: pre/post state, cause and projection mass
  and energy deltas for each `project_room_state()` call.
- `two_zone_boundary_energy_kj`: cumulative energy inserted or removed by
  projection.
- `ThermalSystem` ownership events for canonical doorway upper transfer,
  canonical lower return and doorway thermal counterflow.
- `GasExchangeSystem` parcel lifecycle: created, resolved, cancelled and
  in-flight mass/enthalpy.

## Blocking contract defect

The proposed classification set was:

```text
local_source
exterior_boundary
interior_transport
delayed_parcel
numerical_correction
```

It cannot truthfully represent physical redistribution between the lower and
upper zones of the same room. Active examples include:

- plume entrainment and `ZoneFireSolver.transfer_lower_to_upper()`;
- upper-to-lower sensible-energy exchange;
- post-transfer vertical mixing;
- collapse of an upper layer into the lower layer.

These operations are not a room-level source, not an exterior boundary, not
inter-room transport and not necessarily a numerical correction. Calling them
any of those would corrupt provenance. Omitting them would violate the required
gate that every material writer has exactly one owner event.

The contract therefore needs a sixth classification:

```text
interzone_redistribution
```

It must carry upper and lower deltas separately and close to zero at room level
for mass and energy, except where a separately recorded physical source or sink
is applied in the same logical operation.

## Additional provenance blockers

1. `remove_upper_layer_fraction(room, fraction)` is invoked through a generic
   callable by pressure venting, smoke venting and PPV. The helper receives no
   owner/cause, so mutation-site telemetry cannot distinguish those mechanisms
   without extending the diagnostic call contract.
2. Thermal local processing combines plume redistribution, convective fire
   heat, radiation, wall storage, ambient loss and projection calls in one room
   loop. A single before/after event around that loop would be another composite
   stage delta and is prohibited.
3. Immediate smoke transport, delayed parcel creation and background gas
   exchange share parts of the same gas-exchange loop. The existing parcel
   ledger covers only the delayed branch; a wrapper around the whole loop would
   double-count parcels.
4. Wall storage is a signed local boundary owner. Its room delta is measurable,
   but the wall-side inventory is internal to `ThermalSystem`; conservation
   needs both sides or an explicit boundary-storage term.

All four are instrumentable without changing numerical equations, but not as
one safe patch while preserving the proposed schema and exact-once gates.

## Revised phased prerequisite

### H3.2-S0a — event contract and validator

- Add `interzone_redistribution`.
- Represent upper/lower deltas explicitly.
- Define signed wall/surface storage.
- Pin event IDs, validation, exact-once semantics and duplicate detection.
- Pure fixtures only; no production call sites yet.

Implemented and at GO STOP gate on 2026-08-03 as an isolated pure primitive.
It remains uncommitted pending approval. Binding record:
`PHASE3_H32S0A_PHYSICAL_OWNER_EVENT_CONTRACT.md`.

### H3.2-S0b — thermal owners

- Instrument plume/interzone redistribution, convective fire heat, radiation,
  wall storage, ambient loss and inter-room thermal paths.
- Reuse the three existing doorway events and projection trace.
- Require room and building closure without stage-delta remainders.

### H3.2-S0c — gas owners

- Add diagnostic provenance to upper-layer removal callbacks.
- Instrument exterior pressure/PPV, immediate gas transport and background
  exchange.
- Reuse delayed parcel events; prove no parcel duplication.

### H3.2-S0d — integration gate

- Join thermal, gas, combustion/suppression and existing projection/parcel
  ledgers.
- Report HVAC as deferred unless explicitly instrumented.
- Set coverage complete only per scenario and only when no material owner is
  missing.

H3.2-S may consume the ledger only after S0d closes without a whole-stage or
whole-step remainder.

## STOP decision

**NO-GO for the requested implementation as one phase.** No `sim/core`, runner,
test or validation file was changed. The safe next step is H3.2-S0a, a pure
event-contract phase. H3.2-S, H3.2b and H3.3 remain unstarted/blocked.
