# Phase 3+ F3.3r2 multi-surface shadow design

Date: 2026-07-25

Status: design and instrumentation GO through F3.3r2c. The 180 s physical
correspondence gate is NO-GO. Runtime authority and gap retirement remain
blocked.

## Decision

The next thermal experiment will not enlarge the current canonical wall and
will not tune another room coefficient. It will introduce a default-OFF
multi-surface shadow with four independently stored surface classes:

- ceiling;
- upper wall;
- lower wall;
- floor.

The shadow will own its state inside `Phase3ZoneMassSystem`, use a new pure
surface-conduction solver and close one explicit energy invariant across
upper gas, lower gas, surfaces and exterior removal. It will not share state
with the legacy wall PDE.

Implementation is split into reviewed phases. F3.3r2a delivered the pure
solver and deterministic fixtures. F3.3r2b passed its STOP gate for persistent
state, interface migration and atomic fire-radiation routing. F3.3r2b1 must
close gas/surface/exterior exchange before F3.3r2c correspondence begins.

## Why the current contract is insufficient

F3.3r1 established the following R0 partition at 180 s:

| Quantity | Energy |
|---|---:|
| CFAST total surface storage | 26.993 MJ |
| Direct combustion radiation | 13.392 MJ |
| Gas-driven surface storage | 13.601 MJ |
| Independently inferred gas boundary sink | 14.163 MJ |
| Canonical material-shadow storage | 9.009 MJ |
| Canonical direct ambient decay | 3.796 MJ |

The gas-side sink can therefore look approximately correct while the physical
surface state is wrong. The current canonical contract has three structural
defects:

1. accepted combustion radiation is not deposited in a surface reservoir;
2. wall-like ambient decay removes gas energy without storing it in a
   surface;
3. one lumped wall cannot return heat to the correct upper or lower zone.

The legacy five-node wall PDE contains useful numerical machinery, but its
state is tied to legacy `RoomModel` mutation. Reusing that state would create
two authorities and is prohibited.

## State ownership

Persistent state remains owned by `Phase3ZoneMassSystem.gd`:

```text
_canonical_surface_state_by_room[room] = {
    reference_temp_c,
    material,
    interface_m,
    step_index,
    ceiling: {
        area_m2,
        nodes_c[5],
        stored_energy_kj
    },
    upper_wall: {
        area_m2,
        nodes_c[5],
        stored_energy_kj
    },
    lower_wall: {
        area_m2,
        nodes_c[5],
        stored_energy_kj
    },
    floor: {
        area_m2,
        nodes_c[5],
        stored_energy_kj
    }
}
```

`Phase3SurfaceEnergySolver.gd` will be a pure numerical component. It receives
an immutable pre-step surface snapshot and explicit accepted fluxes, and
returns a proposed post-step state plus residuals. It must not read or mutate
`RoomModel`.

The initial implementation may seed all four classes from one room material.
It must not silently invent material properties. Missing or incomplete
material data causes the shadow to skip the room and emit a diagnostic.

## Geometry contract

For a rectangular room:

```text
A_ceiling    = room floor area
A_floor      = room floor area
A_upper_wall = room perimeter * max(0, room height - interface height)
A_lower_wall = room perimeter * clamp(interface height, 0, room height)
```

Ceiling and floor areas are fixed. Upper- and lower-wall areas change with
the interface.

When the interface moves, wall area migrates between upper and lower classes.
The transferred segment carries the donor nodal energy profile. The migration
operation must conserve total wall energy before any thermal flux is applied.
Resetting the transferred area to ambient temperature is forbidden.

The current building model does not identify every wall as exterior,
adiabatic or shared with an adjacent room. Until boundary topology is
explicit, the shadow is diagnostic only. Scenario-declared material and
boundary metadata may support scratch validation, but cannot establish global
runtime authority.

## Energy paths

The shadow distinguishes three paths that must never be merged:

1. **Accepted fire radiation**
   - originates in the accepted canonical combustion transaction;
   - does not debit upper or lower gas;
   - is deposited directly into surface nodes.
2. **Gas-to-surface exchange**
   - convection and hot-gas longwave radiation;
   - debits one gas zone and credits one or more surfaces atomically.
3. **Surface-to-exterior loss**
   - conduction through a declared exterior boundary;
   - debits surface storage and credits the exterior ledger.

The old wall-like direct ambient gas decay is disabled only inside the new
shadow path. True leakage, ventilation and explicit exterior gas exchange
remain separate.

## Combustion transaction extension

The canonical combustion decision already applies one atomic acceptance
fraction to O2, fuel, species, convective heat and plume. F3.3r2 must extend
the same bundle with:

```text
requested_radiative_energy_kj
accepted_radiative_energy_kj
routed_surface_radiation_kj
radiative_route_residual_kj
```

The accepted split must satisfy:

```text
accepted_fire_energy_kj
  = accepted_convective_energy_kj
  + accepted_radiative_energy_kj
```

The radiation accepted by the transaction is distributed to surfaces by
deterministic geometry and emissivity weights. The initial rule is:

```text
w_i = emissivity_i * area_i
fraction_i = w_i / sum(w)
```

All fractions must sum to one within numerical tolerance. Flame view factors
and orientation-specific tuning are future work; no per-case routing knob is
allowed in this phase.

## Step order

The proposed shadow step is:

1. capture canonical gas and surface pre-step snapshots;
2. stage the canonical combustion decision;
3. preview interface movement and energy-conserving wall-area migration;
4. resolve the atomic combustion bundle;
5. route accepted fire radiation to the migrated surface geometry;
6. preview gas-to-surface convection and longwave radiation;
7. resolve the atomic gas/surface exchange bundle;
8. solve internal surface conduction and declared exterior boundary loss;
9. commit accepted surface state exactly once;
10. record the complete gas/surface/exterior invariant.

Rejected or partially accepted bundles must scale all associated energy paths
with the same accepted fraction. Duplicate bundle commit is an error.

## Required invariants

The following are gating invariants for the shadow:

1. gas-to-surface exchange is antisymmetric;
2. internal node conduction sums to zero;
3. upper/lower wall-area migration conserves total wall energy;
4. surface radiation shares sum to accepted combustion radiation;
5. accepted convective plus radiative energy equals accepted fire energy;
6. exterior loss is debited from surface storage exactly once;
7. the old lumped wall path and new multi-surface path cannot run together;
8. no surface area, stored energy, mass or temperature is NaN or infinite;
9. no negative area or duplicate transaction is accepted;
10. default OFF is bit-identical to the current canonical output.

The room-level cumulative energy invariant is:

```text
delta(E_upper_gas + E_lower_gas + sum(E_surfaces))
  + E_exterior_removed
  + E_transported_out
  - E_transported_in
  - E_accepted_fire
  = 0
```

Every term must be calculated from pre-step snapshots and accepted physical
fluxes. A residual reconstructed only from post-step state is not an
independent ledger.

## Flag and exclusivity

Proposed flag:

```text
phase3_canonical_multisurface_shadow_enabled = false
```

The flag requires the existing canonical persistence, combustion and wall
transaction prerequisites. When enabled, it replaces the canonical lumped
wall/ambient path. Running both surface contracts in the same room and step
must fail closed with a diagnostic.

No official validation case may enable the flag during F3.3r2a or F3.3r2b.

## Telemetry

Per surface class:

- area;
- inner, middle and outer node temperatures;
- stored energy;
- accepted gas convection;
- accepted gas radiation;
- accepted fire radiation;
- exterior loss;
- migrated energy;
- step and cumulative residual.

Per room:

- requested, accepted and routed fire radiation;
- fire-radiation route residual;
- gas/surface exchange residual;
- internal conduction residual;
- wall migration residual;
- cumulative exterior removal;
- total gas/surface/exterior residual;
- diagnostic energy still using the legacy ambient bypass.

Telemetry is opt-in and must not alter the legacy CSV schema while the flag is
OFF.

## Implementation phases

### F3.3r2a - pure solver and fixtures

Files expected:

- new `sim/core/Phase3SurfaceEnergySolver.gd`;
- new focused Python structural/numerical tests;
- this document and workplan updates.

Scope:

- extract or independently implement a five-node implicit solver;
- define immutable input/output records;
- test one surface with convection, radiation and exterior Robin loss;
- test energy accounting over long deterministic runs;
- no `SimulationEngine`, `RoomModel`, state-builder or CSV wiring.

STOP gate:

- constant-ambient case is a no-op;
- radiation-only deposition closes exactly;
- early-time step response agrees with a semi-infinite reference within 5%;
- 10,000-step cumulative energy residual stays within the numerical budget;
- no runtime behavior or official artifact changes.

### F3.3r2b - state and transaction wiring

Files expected:

- `Phase3ZoneMassSystem.gd`;
- `CombustionSystem.gd`;
- `SimulationEngine.gd`;
- state builder/log writer;
- focused transaction and default-OFF tests.

Scope:

- add persistent four-surface state;
- add interface migration;
- extend the canonical combustion bundle with accepted radiation;
- replace lumped wall/ambient exchange only under the new flag;
- add opt-in diagnostics.

STOP gate:

- OFF output is bit-identical;
- direct fire energy split closes;
- wall migration conserves energy in both directions;
- duplicate/conflicting bundles fail closed;
- no official case enables the flag.

### F3.3r2c - staged scratch correspondence

Cases:

- `cfast_corridor_chain`;
- no-fire and no-opening controls;
- a sealed single-room material fixture.

Runtime gates:

1. 60 s;
2. 120 s;
3. 180 s.

Do not run 300 or 600 s until the 180 s gate passes.

At 180 s, provisional acceptance requires:

- total R0 surface storage within 15% of `26.993 MJ`;
- gas-driven storage within 10% of `13.601 MJ`;
- accepted fire radiation within 2% of `13.392 MJ`;
- cumulative energy residual within the declared numerical tolerance;
- R0 upper-temperature error no worse than 31 C;
- R0 lower-temperature error no worse than 10 C;
- Hall upper/lower errors no worse than 15 C;
- R2 upper error no worse than 15 C and lower error no worse than 5 C;
- canonical mass and interface metrics no worse than the valid F3.3p1 state.

These gates authorize later experiments only. They do not retire Group C or
promote the shadow to production authority.

### F3.3r2c result

The staged scratch experiment stopped at 180 s with a physical NO-GO:

- total surface storage passed at `23.472 MJ` versus `26.993 MJ`;
- gas-driven storage passed at `14.347 MJ` versus `13.601 MJ`;
- the combined cumulative residual closed to `-0.00000008 kJ`;
- accepted fire radiation failed at `9.124 MJ` versus `13.392 MJ`;
- R0, Hall and R2 temperature gates failed except R2 lower;
- R0 upper/lower mass and interface were worse than the valid F3.3p1 state;
- CFAST-boundary and physical-topology variants were nearly identical.

No 300 or 600 s run was made. The binding record is
`docs/validation/PHASE3_F33R2C_MULTISURFACE_CORRESPONDENCE.md`.

## Rollback conditions

Revert the experimental phase if any of the following occurs:

- default-OFF output changes;
- gas/surface/exterior energy does not close;
- accepted radiation is counted as both gas heat and surface heat;
- interface migration creates or destroys wall energy;
- lower-zone overcooling is worse than F3.3r0;
- surface topology requires hidden per-case coefficients;
- official reports, expected values, tolerances or gaps must be changed to
  make the experiment pass.

## Final recommendation

F3.3r2d completed the required separation:

- `3.814 MJ` of the 180 s shortfall is combustion-decision rejection driven
  exactly by the canonical O2 HRR factor;
- atomic surface routing rejects `0 MJ`;
- the simulated interface independently shifts `1.775 MJ` from upper wall to
  lower wall in the read-only CFAST-interface counterfactual;
- source, gas/surface split, migration and legacy invariants close.

The binding record is
`docs/validation/PHASE3_F33R2D_SOURCE_ROUTING_ATTRIBUTION.md`.

Do not add another thermal/radiative coefficient, run 300/600 s, enable an
official case or promote runtime authority. Proceed only to F3.3s, a
read-only layer-mass/O2 owner audit that identifies the first incorrect
plume, doorway, O2-sink or projection delta.
