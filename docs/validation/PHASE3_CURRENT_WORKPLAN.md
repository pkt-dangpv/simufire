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

F3.0 shadow canonical two-zone state is implemented as infrastructure. F3.0a
is now active: connect the first explicit sealed-room flux owner.

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

## F3.0a minimum scope

1. Implement sealed single-room shadow requests first:
   - combustion heat;
   - O2 sink;
   - CO2/CO/HCN/species source where already available;
   - plume lower-to-upper mass/enthalpy if explicitly available.
2. Prove each request originates in an explicit solver output before mutation.
3. Add request-level conservation tests and a zero-O2 visibility assertion.
4. Keep all legacy outputs bit-identical when the flag is OFF or ON.

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

Use GPT-5.6 Sol for F3.0 implementation planning or implementation. The task is
architecture-sensitive and token-heavy enough to justify the stronger model.
