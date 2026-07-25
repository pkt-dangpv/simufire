# Phase 3+ F3.3r2b1 atomic gas/surface/exterior exchange

Date: 2026-07-25

Status: GO for the default-OFF gas/surface transaction and generic explicit
exterior boundary API. Official case activation, exterior-topology inference,
thermal authority and Group C retirement remain NO-GO.

## Delivered contract

F3.3r2b1 extends the existing default-OFF multi-surface owner. It does not add
a new flag, CLI switch or official-case override.

For every canonical room, the engine now:

1. prepares ceiling, upper-wall, lower-wall and floor state;
2. previews exchange from canonical pre-step gas and surface snapshots;
3. aggregates signed upper- and lower-zone gas energy;
4. queues those two gas-facing routes as one atomic bundle;
5. applies the accepted fraction once to all per-surface fluxes;
6. commits convection, gas radiation, accepted fire radiation and exterior
   removal to all four candidate surfaces atomically.

The preview never mutates persistent state or queues a transaction. The queue
never recalculates a physical flux. This separation prevents circular
bookkeeping and ensures that a partial atomic acceptance cannot deposit more
surface energy than was removed from canonical gas.

## Combined invariant

Positive `gas_exchange` means gas energy enters surfaces. Positive
`exterior_removed` means energy leaves the enclosure. The committed invariant
is:

```text
-gas_exchange
+ surface_storage_delta
+ exterior_removed
- accepted_fire_radiation
= 0
```

Gas-to-surface and surface-to-gas transfers use signed routes. The same atomic
fraction limits upper and lower gas demands against the canonical state at
the actual transaction point. Full, partial and rejected fixtures close the
combined residual without an energy or temperature clamp.

`Phase3SurfaceEnergySolver` now accepts prescribed interior-convection and
exterior-removal energies. These inputs are mutually exclusive with Robin
coefficients in the same solve, so commit cannot silently recalculate a
different flux from the preview.

## Radiation

Hot-gas longwave radiation is evaluated from the pre-step gas temperature,
surface inner-node temperature, surface emissivity and an explicit effective
gas emissivity:

```text
Q = eps_surface * eps_gas * sigma * area
    * (T_gas^4 - T_surface^4) * dt
```

Upper-gas emissivity reuses the existing upper-radiation activation envelope.
Lower-gas radiation remains zero in this phase rather than inventing a new
coefficient. Direct fire radiation remains a separate atomic source and is
combined with gas exchange only at the single surface commit.

## Exterior boundary decision

`RoomModel` currently has no authoritative enclosure topology saying which
part of ceiling, floor or walls touches exterior air, another room or an
adiabatic boundary. F3.3r2b1 therefore does not infer this from visual meshes
or opening geometry.

The generic preview accepts explicit per-surface Robin metadata and its direct
fixture closes exterior removal exactly. The runtime engine supplies an empty
map, which means:

- all four surfaces are deliberately adiabatic;
- `boundary_metadata_complete_flag = 0`;
- `adiabatic_surface_count = 4`;
- no hidden ambient loss is created.

This is fail-closed behavior, not the final physical boundary model.

## STOP gate

Godot 4.7.1:

| Check | Result |
|---|---|
| F3.3r2a solver fixture | PASS |
| F3.3r2b compatibility fixture | PASS |
| F3.3r2b1 exchange fixture | PASS |
| Full project parse | PASS |
| 10 s engine scratch OFF/ON | 66/66 rows, 0 legacy-value differences |

Direct F3.3r2b1 fixture:

| Case | Result |
|---|---|
| Default OFF | inert |
| Missing topology | four adiabatic surfaces, visible diagnostic |
| Full gas-to-surface acceptance | fraction 1, exact combined closure |
| Partial gas acceptance | fraction 0.5, exact scaled storage |
| Full gas rejection | fraction 0, unchanged surface state |
| Surface-to-gas signed transfer | exact reverse route and closure |
| Explicit four-surface exterior boundary | exact exterior removal |

Focused Python contracts: 70/70 PASS across the solver, old multi-surface
transaction, new exchange, atomic bundle, inter-zone and lumped-wall owners.

The engine scratch used identical canonical parent flags and changed only the
multi-surface override. Both runs exported 442 columns; all 163 shared
non-Phase-3 columns were byte-equivalent by value. Scratch inputs and outputs
were removed after comparison.

No official CSV, report, baseline, expected value, tolerance, gap, FED or HVAC
path changed. The legacy CSV schema remains unchanged.

## Next phase

F3.3r2b2 must add explicit enclosure boundary topology before F3.3r2c:

1. define per-surface boundary classes independently of visual geometry;
2. distinguish exterior, inter-room and adiabatic fractions;
3. populate the existing `exterior_by_surface` contract without fallback;
4. test mixed boundary fractions and conservation;
5. keep the complete path default OFF.

The staged 60/120/180 s CFAST correspondence remains unauthorized until that
STOP gate closes.
