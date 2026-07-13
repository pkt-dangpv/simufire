# Phase 3+ current workplan

Date: 2026-07-12

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

F3.0 shadow canonical two-zone state, F3.0a plume ownership and the energy-only
part of F3.0b are implemented. F3.0c is now active: define non-duplicated O2
sink and species-source contracts across CombustionSystem and
OxygenExchangeSystem.

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
- a subsystem both mutates legacy canonical quantities and emits an
  authoritative request in the same mode.

## Next prompt target

Use GPT-5.6 Sol for F3.0c contract design. Start by identifying one authoritative
pre-mutation result for O2 consumption; do not infer it from HRR or accounting
fields after OxygenExchangeSystem has mutated the room. Species may follow in a
separate STOP gate if their generation object can be reused exactly.
