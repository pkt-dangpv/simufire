# Phase 3+ F3.3v canonical fire proposal design

Date: 2026-07-25

Status: design complete; no runtime implementation in F3.3v.

## Decision

F3.3u proved that the coupled plume is stable through 600 s, but also proved
that the canonical combustion transaction receives its HRR too late. The live
legacy step has already used legacy O2 to change:

- the fire clock;
- the ideal HRR;
- solid pyrolysis;
- flame, smolder and pool targets;
- retained unburned fuel;
- the smoothed HRR;
- fuel consumption and species generation.

The current canonical transaction can reject this result. It cannot restore
fire potential already removed upstream.

F3.3v therefore selects a new contract:

1. construct an O2-unconstrained fire proposal from persistent canonical fire
   state and immutable fire parameters;
2. apply binary extinction, available O2, ventilation and fuel limits;
3. derive fuel, species, heat and plume from the same accepted HRR;
4. commit the complete bundle with one atomic fraction;
5. keep legacy runtime untouched while the contract remains shadow-only.

Dividing legacy HRR by `room.o2_hrr_factor`, forcing 300 kW, or reading a
post-throttle target are explicitly rejected.

## Tick-order diagnosis

The current order in `SimulationEngine.step()` is:

```text
canonical begin_step / opening requests
  -> optional legacy O2 step
  -> snapshot live fire state
  -> legacy CombustionSystem.step_room_fire()
  -> evaluate canonical combustion from mutated RoomModel
  -> thermal / plume
  -> atomic canonical commit
```

The new shadow order must become:

```text
canonical begin_step / opening requests
  -> canonical pre-step environment and persistent fire state
  -> pure fire proposal (no O2 throttle, no RoomModel writes)
  -> canonical acceptance decision
  -> species + heat + plume requests from accepted HRR
  -> one atomic bundle
  -> persistent canonical fire-state commit

legacy combustion continues separately while the feature is shadow-only
```

The proposal must be evaluated before the live `_step_fire()` mutation, or
from a complete pre-step snapshot that makes the result order-independent.

## Existing state that can be reused

`Phase3ZoneMassSystem` already persists and atomically interpolates:

- `active_flag`;
- `hrr_kw`;
- `hrr_target_kw`;
- `o2_hrr_factor`;
- `remaining_fuel_MJ`;
- `retained_unburned_MJ`;
- `fire_time_s`;
- `fire_dormant_time_s`;
- `extinguished_flag`.

The atomic bundle already shares one inventory-limited fraction across O2,
species, convective energy and plume transport. F3.3t already derives the
complete Heskestad plume from accepted HRR and effective `chi_rad`.

These pieces remain. The current proposal source does not.

## State additions

The canonical fire state needs names that distinguish potential from accepted
combustion:

```text
proposal_age_s
proposal_hrr_kw
proposal_target_kw
accepted_hrr_kw
accepted_target_kw
o2_quality_factor
remaining_fuel_MJ
retained_unburned_MJ
fire_dormant_time_s
active_flag
extinguished_flag
```

The immutable fire contract must be captured once instead of repeatedly read
from a live, mutable `RoomModel`:

```text
growth_alpha_kw_s2
max_hrr_kw
fuel_energy_MJ
o2_nominal
o2_min_for_flame
o2_consumption_kg_per_MJ
```

`FireModel.max_burn_rate_kw` exists but the legacy path does not currently
use it as an HRR cap. F3.3v must not introduce that dormant field into the
physics without a separate semantics audit.

Later phases must extend the persistent state before supporting fuel objects,
latent fire, retained-gas release, backdraft, flashover, suppression or
secondary ignition.

## Proposal contract

For the initial simple-fire scope:

```text
curve_hrr = min(alpha * proposal_age_s^2, max_hrr)
fuel_decay = clamp((remaining_fuel / initial_fuel) / 0.15, 0, 1)
thermal_feedback = existing bounded feedback contract
proposal_target = min(curve_hrr * fuel_decay * thermal_feedback,
                      max_hrr)
proposal_hrr = existing rise/fall smoothing toward proposal_target
```

The proposal excludes:

- the linear O2 concentration throttle;
- the O2 inventory cap;
- the Kawagoe ventilation cap;
- post-throttle legacy HRR and targets.

`proposal_age_s` advances by full `dt` while the simple fire is active and
above the hard extinction boundary. It does not advance fractionally with the
linear O2 quality factor. At or below hard extinction it freezes, accepted HRR
is zero and the dormant clock advances. This preserves the zero-O2 invariant
without recreating the legacy slow-growth throttle.

## Acceptance contract

The first shadow implementation must make every limit explicit:

```text
o2_inventory_cap_kw =
    available_o2_above_extinction_kg
    * 1000 / (dt * o2_consumption_kg_per_MJ)

ventilation_cap_kw =
    kawagoe_limit_kw if configured, otherwise +INF

fuel_cap_kw =
    remaining_fuel_MJ * 1000 / dt

accepted_hrr_kw =
    0                                              if hard-extinguished
    min(proposal_hrr_kw,
        o2_inventory_cap_kw,
        ventilation_cap_kw,
        fuel_cap_kw)                               otherwise
```

The existing smoothed `canonical_o2_hrr_factor` remains diagnostic and may
inform combustion quality/yields. It must not silently multiply the new
proposal in F3.3v1. O2 is already represented by a hard extinction boundary,
an exact stoichiometric inventory cap and the opening-derived ventilation
cap. Multiplying by concentration again would recreate the double throttle
that F3.3v is intended to isolate.

This is an experimental decision, not runtime authority. The 180/300/600 s
STOP gate must show whether it matches the CFAST fire contract without
creating a zero-O2 flame or consuming unavailable O2.

## Atomic products

All products must derive from the accepted transaction, never from live
legacy deltas:

```text
accepted_fuel_MJ
accepted_o2_kg
accepted_total_fire_energy_kj
accepted_radiative_energy_kj
accepted_convective_energy_kj
accepted_species_kg
accepted_plume_mass_kg
accepted_plume_energy_kj
```

The order is:

1. compute the pure proposal;
2. compute the canonical decision fraction;
3. compute proposed products from that decision;
4. stage one atomic route bundle;
5. apply any final source-inventory fraction to every product and to the
   persistent fire-state transition.

Species generation must be extracted into a pure helper. Reusing
`legacy_species_result`, `room.fuel_consumed_MJ_step` or post-mutation carbon
counters is not sufficient for canonical authority.

## Initial support boundary

F3.3v1 should support only the simple fire contract exercised by Group A/C:

- one room-level t-squared fire;
- no secondary HRR gain;
- flashover disabled;
- thermal feedback zero or explicitly supported;
- unburned generation and pool release disabled;
- no active backdraft;
- no intraroom spread;
- no suppression;
- no authoritative explicit fuel-object graph.

An unsupported configuration must emit a reason mask and remain shadow-only.
It must not silently fall back to legacy HRR and report itself as canonical.

Both `cfast_corridor_chain` and `cfast_r0_window_360` satisfy the intended
room-level validation scope. Their `simple_house` template does contain
explicit furniture objects, but the active fire is still created from the
room aggregate `fuel_energy_MJ`/`max_hrr_kw` contract and then synchronized
back to those objects. F3.3v1 may diagnose the aggregate proposal; F3.3v2
must own the object-level fuel/yield synchronization before any authority
promotion.

## Proposed implementation phases

### F3.3v1 - pure proposal and telemetry

Files:

- `sim/fire/CombustionSystem.gd`
- `sim/core/SimulationEngine.gd`
- `sim/core/Phase3ZoneMassSystem.gd`
- `sim/core/SimulationStateBuilder.gd`
- `sim/core/SimulationLogWriter.gd`
- focused GDScript/Python tests

Add default-OFF `phase3_canonical_fire_proposal_shadow_enabled`.

Required telemetry:

- support flag and unsupported-reason mask;
- proposal age, curve HRR, target HRR and smoothed HRR;
- O2 inventory, ventilation and fuel caps;
- hard-extinction flag;
- decision and atomic fractions;
- accepted HRR and all requested/accepted products;
- persistent state before/proposed/committed summaries.

F3.3v1 remains passive. It may feed the F3.3t plume only inside the complete
shadow stack.

### F3.3v2 - pure species and fuel transaction

Extract the existing yield/carbon logic into a non-mutating result. Prove that
fuel, carbon, O2, heat and species close under partial atomic acceptance.

No runtime authority is allowed while species still come from legacy writes.

### F3.3v3 - extended 180/300/600 correspondence

Run OFF/ON pairs for Group C and Group A. Compare:

- proposal and accepted HRR;
- upper/lower mass and O2;
- plume rate and interface;
- upper/lower temperature;
- fuel, carbon and energy residuals;
- every currently required validation projection.

Only after this gate may an authority experiment be proposed.

### F3.3v4 - advanced fire modes

Design separate state transitions for fuel objects, latent combustion,
retained gas, pool release, backdraft, suppression, flashover and spread.
They are not implicit extensions of the simple-fire proposal.

## Required fixtures

1. Nominal O2: proposal and accepted HRR agree.
2. Moderate O2: proposal is unchanged; accepted HRR is limited only by
   explicit inventory/ventilation contracts.
3. Zero O2: accepted HRR, fuel, species, heat and plume are exactly zero.
4. Inventory-limited O2: every atomic product receives the same fraction.
5. Ventilation-limited opening: Kawagoe cap is applied once.
6. Fuel exhaustion: fuel never becomes negative and all products stop.
7. Legacy-independence: changing live `room.hrr_kw`, target, fire clock or
   O2 factor after the pre-step snapshot cannot change the proposal.
8. Unsupported fire mode: explicit reason, no false canonical authority.
9. OFF invariance: legacy CSV remains byte-identical.
10. 180/300/600 prefix determinism and residuals at or below `1e-6`.

## STOP gates

F3.3v1 GO requires:

- default OFF and exact legacy invariance;
- no `RoomModel` or `FireModel` writes from the pure proposal;
- no reads of post-throttle legacy HRR/target/fire clock/species;
- all zero-O2 and atomic-conservation fixtures pass;
- finite positive canonical zone inventories;
- F3.3t plume equation unchanged;
- physics and ILV suites remain at zero FAIL;
- guardrails 10/10;
- no baseline, tolerance, CTRL or VALID_GAP change.

Runtime authority remains NO-GO unless:

- no previously passing required check is reopened;
- all Group C required projections pass;
- Group A does not regress;
- fuel/O2/carbon/energy/species residuals close;
- advanced/unsupported fire modes remain outside the authority scope.

## Rollback criteria

Rollback the experiment if it:

- produces HRR at or below the hard O2 extinction limit;
- consumes more O2 or fuel than the canonical source owns;
- changes F3.3t plume equations or adds a corridor-only coefficient;
- obtains 300 kW by a case constant instead of the fire contract;
- reads post-throttle legacy state as proposal input;
- improves temperature by breaking mass, energy, O2 or species closure;
- hides an unsupported fire mode behind a legacy fallback.

## Expected first experiment

For `cfast_corridor_chain`, the t-squared curve naturally reaches its declared
300 kW cap near 80 s. At 590 s the existing shadow accepts all of a legacy
proposal of only 137.46 kW. F3.3v1 will test whether the canonical proposal
remains at the model-derived cap and whether exact O2/ventilation inventories
accept it.

That result is not assumed. It is the next measured STOP gate.
