# Phase 3+ F3.3v2c fuel-object shadow synchronization design

Date: 2026-07-26

## Decision

Implement F3.3v2c as a **persistent, default-OFF object ledger** before any
runtime-authority experiment. Do not write live `FuelObjectModel` instances.

F3.3v2b closes the aggregate transaction, but the corridor case contains
seven explicit objects. Promoting only aggregate `remaining_fuel_MJ` would
allow the canonical fire and the live object inventory to disagree.

## Current ownership

The legacy object path:

1. selects non-proxy objects that are primary, flaming, pyrolyzing,
   autoignition-ready, flashover-active or sufficiently preheated;
2. assigns a positive burn weight;
3. distributes the requested solid-fuel debit by weight, capped by each
   object's remaining inventory;
4. redistributes leftover demand by remaining capacity;
5. writes object fuel, HRR, state, exposure and char directly.

The canonical shadow currently persists only aggregate fuel. Its scalar
atomic interpolator cannot conserve a nested object ledger.

## F3.3v2c contract

### Identity

- Use `FuelObjectModel.id` as the stable key.
- Reject empty or duplicate IDs.
- Exclude `room_proxy_*` whenever explicit objects exist.
- Freeze object order by sorted ID for deterministic CSV and tests.

### Persistent state

Each object entry contains:

- `id`;
- `remaining_fuel_MJ`;
- `initial_fuel_MJ`;
- immutable allocation inputs needed by the shadow policy;
- a supported/rejection code.

The aggregate canonical fuel must equal the sum of supported object
inventories at seed, before proposal, after proposal and after atomic commit.

### Allocation

F3.3v2c must be pure and dictionary-only:

1. receive the persistent pre-ledger and accepted aggregate fuel debit;
2. choose eligible objects from frozen pre-step state;
3. allocate by deterministic positive weights;
4. cap each allocation by object inventory;
5. redistribute leftover debit by remaining capacity;
6. return proposed per-object inventories and explicit residuals.

If no eligible object can own a positive debit, the bundle is unsupported.
There is no silent fallback to the aggregate fire.

### Atomic commit

Extend `_interpolate_combustion_state()` for the object ledger:

- interpolate each object's pre/proposed remaining fuel with the same atomic
  fraction used by O2, species and energy;
- preserve IDs and immutable metadata;
- derive committed aggregate fuel from the committed object sum;
- reject missing, added, reordered or duplicate objects;
- expose aggregate/object and debit residuals.

No independent object fraction is allowed.

## Flags and telemetry

New raw flag:

`phase3_canonical_fuel_object_sync_shadow_enabled = false`

It is effective only when F3.3v2b routing and persistent combustion are
active.

Minimum opt-in telemetry:

- active/supported flags and rejection mask;
- explicit/proxy/duplicate/empty-ID counts;
- pre, proposed and committed object fuel sums;
- aggregate pre, proposed and committed fuel;
- requested, allocated and committed debit;
- seed, proposal, atomic and debit residuals;
- exhausted-object count;
- minimum object remaining fuel;
- live-object comparison delta, diagnostic only.

## STOP gates

### Pure fixtures

- one object;
- seven objects with deterministic ordering;
- partial debit;
- one object exhausted with leftover redistribution;
- all objects exhausted;
- zero debit;
- duplicate and empty IDs;
- proxy plus explicit objects;
- atomic fractions 0, 0.25 and 1;
- no negative inventory;
- exact aggregate/object closure.

### Runtime

Use the existing 180 s corridor F3.3v2b run.

Acceptance:

- OFF CSV byte-identical to F3.3v2b;
- all live/non-shadow columns identical ON;
- seven stable explicit object IDs;
- every object inventory monotonic and nonnegative;
- aggregate/object residuals zero at CSV precision;
- committed debit equals F3.3v2b accepted fuel times atomic fraction;
- O2/species/energy/plume residuals remain zero.

Then repeat at 300 and 600 s. Runtime authority remains NO-GO if identity
changes, an unsupported object mode appears, or live/canonical object fuel
diverges without an explicit migration owner.

## Rollback criteria

Rollback if the ledger:

- changes any live object or `RoomModel`;
- changes OFF schema or values;
- uses legacy post-step fuel deltas as its requested debit;
- silently ignores an explicit object;
- conserves aggregate fuel while any object becomes negative;
- applies an object fraction different from the atomic bundle fraction.

## Next implementation order

1. pure snapshot, validator and allocation evaluator in `CombustionSystem`
   (**F3.3v2c1 complete**);
2. nested atomic interpolation in `Phase3ZoneMassSystem`;
3. engine/runner/logger wiring;
4. direct Godot fixture and Python structural tests;
5. 180 s OFF/ON gate;
6. only after GO, 300/600 s correspondence.

F3.3v2c1 verification: Godot 4.7.1 parser PASS; direct allocation fixture
PASS; F3.3v2b/v2c focused tests 10/10 PASS. The evaluator is not wired into
the engine tick, persistence or CSV.
