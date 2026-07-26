# Phase 3+ F3.3v3e energy and doorway correspondence

Date: 2026-07-26

## Decision

F3.3v3e is **diagnostic GO**. It assigns the first cross-model energy
authority gap to the additive interior-pressure route, not to the
multisurface solver.

The first justified motor experiment is now narrow:

```text
replace additive interior-pressure transport with a fixed-gross directional
skew of the canonical opening flow
```

It must remain shadow-only and default OFF until its own STOP gate.

The read-only analyzer is:

```text
scripts/simulation/analyze_phase3_f33v3e_energy_correspondence.py
```

No motor, scenario, official report, expected value, tolerance, CTRL,
VALID_GAP, FED, HVAC or visual path changed.

## Comparable energy budgets

For SimuFire, the cumulative residence ledgers expose all terms directly:

```text
E_gas =
    E_combustion
  + E_multisurface
  + E_interior_opening
  + E_interior_pressure
  + E_exterior
```

For CFAST, the gas-surface term is inferred from its own exported balance:

```text
E_surface =
    E_gas_observed
  - E_fire_convective
  - E_doorway_net
  - E_exterior_net
```

Doorway sensible enthalpy uses the exported slab mass flows and slab source
temperatures. Exterior sensible enthalpy uses the layer-resolved leakage
flows and R0 upper/lower temperatures. Ambient inflow has zero sensible
enthalpy relative to the shared 20 C reference.

Both model budgets close below `2.1e-8 kJ`.

## First pressure-sign mismatch

At 120 s, where F3.3v3d first found CFAST positive and SimuFire negative:

| Cumulative energy error, SF minus CFAST | Value |
|---|---:|
| Observed R0 gas energy | `-435.4 kJ` |
| Combustion input | about `-133 kJ` |
| Multisurface exchange | `-78.7 kJ` |
| Doorway transport | `-217.9 kJ` |
| Exterior transport | `-5.4 kJ` |

Doorway transport is already the largest energy owner at the first sign
mismatch.

## State at 180 s

| Cumulative comparison | CFAST | SimuFire | SF-CFAST |
|---|---:|---:|---:|
| Gas sensible energy | `4407.3 kJ` | `3306.4 kJ` | `-1100.9 kJ` |
| Surface net exchange | `-13661.2 kJ` | `-13891.8 kJ` | `-230.6 kJ` |
| Doorway net enthalpy | `-6301.7 kJ` | `-7106.0 kJ` | `-804.3 kJ` |
| Exterior net enthalpy | `-501.5 kJ` | `-417.8 kJ` | `+83.6 kJ` |

The surface term differs by only `1.69%`. The doorway term differs by
`12.76%` and owns about 73% of the final gas-energy deficit.

Multisurface is therefore a large absolute sink but not the primary
cross-model error owner.

## Doorway decomposition

At 180 s:

| Directional mass | CFAST | SimuFire current |
|---|---:|---:|
| R0 to Hall | `76.732 kg` | `94.989 kg` |
| Hall to R0 | `69.442 kg` | `88.621 kg` |
| Gross exchange | `146.174 kg` | `183.611 kg` |
| Net R0 outflow | `7.290 kg` | `6.368 kg` |

The SimuFire routes decompose as:

| Route family | Gross mass | Net R0 enthalpy out |
|---|---:|---:|
| `interior_opening` | `143.881 kg` | `6310.464 kJ` |
| `interior_pressure` | `39.729 kg` | `795.539 kJ` |

The opening route alone differs from CFAST gross mass by `-1.57%` and from
CFAST net enthalpy by only `+8.756 kJ` (`0.14%`). It is already an excellent
aggregate correspondence.

The pressure route is still needed to create net mass outflow:

- opening route net mass: approximately `0 kg`;
- pressure route net mass: `6.368 kg`;
- CFAST net mass: `7.290 kg`.

However, the current implementation adds the pressure route on top of the
opening exchange. That raises gross traffic by `39.729 kg` (`+25.6%` total)
and adds the excess `795.539 kJ` net enthalpy loss.

CFAST solves buoyancy and pressure in one slab-flow field. SimuFire currently
models a zero-net counterflow and then adds an independent pressure flow.
F3.3v3e identifies this additive split as the correspondence defect.

## Fixed-gross shadow candidate

The next experiment must preserve the existing opening gross exchange while
using the pressure solution only to skew its two directions.

With the measured pressure-route net outflow:

```text
out_new = out_opening + 0.5 * net_pressure
in_new  = in_opening  - 0.5 * net_pressure
```

The 180 s cumulative directional masses would become:

| Direction | Fixed-gross shadow | CFAST |
|---|---:|---:|
| R0 to Hall | `75.125 kg` | `76.732 kg` |
| Hall to R0 | `68.756 kg` | `69.442 kg` |

This is a diagnostic projection, not yet a motor result. The implementation
must recompute mass, enthalpy, O2 and species atomically from the adjusted
directional routes and cap the skew so neither direction becomes negative.

## STOP gate

| Check | Result |
|---|---|
| CFAST gas-energy budget | PASS |
| SimuFire gas-energy budget | PASS |
| Primary owner at 120 s | doorway |
| Primary owner at 180 s | doorway |
| Surface cumulative error | 1.69% |
| Doorway cumulative error | 12.76% |
| Opening-only CFAST enthalpy match | 0.14% error |
| Additive pressure enthalpy owner | confirmed |
| Pressure/leakage coefficient tuning | still NO-GO |
| Fixed-gross directional-skew shadow | GO for design/implementation |
| Motor/cases/reports/baselines | unchanged |

## Next gate: F3.3v3f

F3.3v3f should implement an opt-in shadow preview only:

1. consume the canonical opening counterflow and pressure-net request;
2. preserve opening gross mass;
3. skew outbound/inbound mass by half the accepted net request;
4. cap at zero directional mass;
5. derive enthalpy, O2 and species from each adjusted source zone;
6. expose projected directional and net budgets;
7. never apply the preview to canonical or legacy state.

Acceptance requires:

- exact mass/energy/O2/species closure;
- reduced gross-flow and net-enthalpy error against CFAST;
- no pressure-sign regression in the shadow projection;
- identical physics with the flag OFF and ON;
- no change to official reports or validation baselines.
