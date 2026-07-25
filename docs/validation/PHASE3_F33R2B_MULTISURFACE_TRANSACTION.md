# Phase 3+ F3.3r2b multi-surface state and radiation transaction

Date: 2026-07-25

Status: GO for default-OFF persistent state, interface migration and accepted
fire-radiation routing. Thermal authority and official case activation remain
NO-GO.

## Delivered scope

F3.3r2b adds the experimental flag:

```text
phase3_canonical_multisurface_shadow_enabled = false
```

The flag requires canonical zone state, persistence and canonical combustion.
It has no CLI switch and no official validation case enables it.

When active, `Phase3ZoneMassSystem` owns four independent persistent surface
states per room:

- ceiling;
- upper wall;
- lower wall;
- floor.

Each state uses the pure five-node `Phase3SurfaceEnergySolver` delivered in
F3.3r2a. Geometry and material properties must be explicit and finite.
Missing material data fails closed; the shadow does not invent fallback
properties.

## Interface migration

Ceiling and floor areas remain fixed. Upper- and lower-wall areas are derived
from room perimeter and canonical interface height.

When the interface moves, the transferred wall strip carries the donor nodal
temperature profile. The recipient profile is mixed by area:

```text
T_new[i] =
  (T_target[i] * A_target + T_donor[i] * A_moved)
  / (A_target + A_moved)
```

The fixture moves the interface in both directions after depositing surface
energy. Total surface energy and the migration residual remain zero within
the numerical tolerance. Zero-area upper or lower wall states are valid and
inert; depositing radiation on a zero-area surface fails closed.

## Combustion radiation contract

`CombustionSystem` stages total accepted fire energy and an initial radiative
estimate as transaction metadata. It does not mutate a surface.

`ThermalSystem` remains the owner of the exact convective route, including
existing two-zone and exterior-opening modifiers. During bundle finalization,
the canonical transaction therefore defines radiation as the exact
complement:

```text
accepted_radiation
  = accepted_total_fire_energy - accepted_convective_energy
```

This prevents two independent `chi_rad` formulas from double counting fire
energy.

Surface deposition occurs only after the existing atomic bundle has resolved.
The accepted radiation is multiplied by the same atomic fraction as O2,
species, convective heat and plume. It is then distributed by deterministic
area-emissivity weight:

```text
w_i = area_i * emissivity_i
E_i = accepted_radiation * w_i / sum(w)
```

All candidate surfaces are solved first. Persistent state is replaced only if
every surface solve succeeds. A rejected atomic bundle stores zero radiation;
a partial bundle stores the same partial fraction. A duplicate deposit is
rejected and counted without changing surface energy.

## Mutual exclusion

The new path and the F3.2b5b lumped wall path cannot run together:

- `SimulationEngine` does not enqueue old canonical wall requests while the
  multi-surface flag is active;
- `Phase3ZoneMassSystem` rejects a lumped wall transaction when the new owner
  is active;
- the log writer does not enable the old lumped-wall schema under the new
  flag.

This phase does not suppress true leakage, ventilation or transport energy.

## STOP gate

Godot 4.7.1 direct fixtures:

| Fixture | Result |
|---|---|
| F3.3r2a pure solver | PASS |
| F3.2b1 combustion transaction | PASS |
| F3.2b5b lumped wall transaction | PASS |
| F3.3r2b multi-surface transaction | PASS |
| Full project parse | PASS |

F3.3r2b direct transaction checks:

| Check | Result |
|---|---|
| Flag default OFF | inert |
| Four seeded areas | exact |
| Zero-area interface edge | valid and inert |
| Full atomic acceptance | 30 kJ accepted, routed and stored |
| Partial atomic acceptance | 0.5 fraction, 15 kJ stored |
| Full atomic rejection | 0 kJ stored |
| Interface migration both directions | energy-conservative |
| Duplicate commit | rejected, no energy change |
| Lumped wall conflict | rejected |

Repository checks:

- focused Python tests: 48/48 PASS;
- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL;
- ILV: 15 PASS / 14 CTRL / 0 FAIL;
- gap inventory: synchronized, 353 required with 6 documented VALID_GAP;
- guardrails before commit: 9/10, only expected R2-1 from dirty `sim/core`.

No official CSV, report, expected value, tolerance, gap, FED path or HVAC
path changed. The legacy CSV schema remains unchanged.

## Explicitly not delivered

F3.3r2b does not yet implement:

- upper/lower gas convection into surfaces;
- hot-gas longwave radiation into surfaces;
- atomic gas-energy debit paired with surface credit;
- declared exterior-boundary conduction and removal;
- per-surface CSV telemetry;
- 60/120/180 s CFAST correspondence.

Disabling the lumped path is therefore only valid inside this experimental
shadow. It is not production thermal authority.

## Next phase

F3.3r2b1 must add the missing gas/surface/exterior transaction before any
F3.3r2c correspondence run:

1. preview upper- and lower-gas convection/radiation from canonical pre-step
   snapshots;
2. debit gas and credit surfaces under one atomic fraction;
3. apply exterior Robin loss only to explicitly declared exterior surfaces;
4. close the combined gas/surface/exterior invariant;
5. preserve OFF output and keep all official cases disabled.

Only after that STOP gate may F3.3r2c run the staged 60/120/180 s scratch
correspondence.
