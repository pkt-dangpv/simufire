# Phase 3+ F3.3r1 boundary-partition audit

Date: 2026-07-24

Status: diagnostic GO. Full-area patch remains NO-GO.

## Purpose

F3.3r0 showed that concrete material mapping nearly closes the total
boundary sink but overcools lower/downstream gas. F3.3r1 determines why a
matched gas-energy sink does not produce a matched wall or zone state.

The read-only analyzer is:

```text
scripts/simulation/analyze_phase3_f33r1_boundary_partition.py
```

It consumes committed CFAST wall/zone/compartment exports and the ignored
F3.3r0 base/material scratch CSVs. It does not change motor code, official
cases, reports, baselines, tolerances, gaps, FED or HVAC.

## Method

CFAST exports inner-surface temperature histories for ceiling, upper wall,
lower wall and floor. The audit estimates inward conductive heat flux using
the Duhamel solution for a semi-infinite solid with the declared concrete:

- `k = 1.75 W/(m K)`;
- `rho = 2200 kg/m3`;
- `Cp = 1000 J/(kg K)`.

At 180 s the thermal penetration scale is about `0.012 m`, much smaller than
the `0.15 m` slab. The semi-infinite approximation is therefore suitable for
owner attribution over this window, although it is not a replacement for
CFAST's finite-difference wall solver.

Dynamic upper/lower wall areas use the exported CFAST interface. Ceiling and
floor areas remain fixed. The calculation is tested against the committed
surface histories.

## Surface storage

### R0 cumulative estimated energy

| Time | Ceiling | Upper wall | Lower wall | Floor | Total |
|---|---:|---:|---:|---:|---:|
| 60 s | 1.101 MJ | 0.204 MJ | 0.334 MJ | 0.490 MJ | 2.128 MJ |
| 120 s | 6.567 MJ | 2.531 MJ | 1.541 MJ | 2.706 MJ | 13.345 MJ |
| 180 s | 12.614 MJ | 6.382 MJ | 2.707 MJ | 5.290 MJ | 26.993 MJ |

The 180 s upper-associated surfaces hold `18.996 MJ`; lower-associated
surfaces hold `7.997 MJ`.

## Source partition

CFAST declares a radiative fraction of `0.35`. Applying it to the integrated
fire HRR separates direct fire-to-surface radiation from surface energy
driven by gas convection/radiation:

| Time | Surface storage | Direct fire radiation | Gas-driven surface storage | Inferred gas boundary sink | Residual |
|---|---:|---:|---:|---:|---:|
| 60 s | 2.128 MJ | 1.250 MJ | 0.878 MJ | 0.959 MJ | 0.081 MJ |
| 120 s | 13.345 MJ | 7.092 MJ | 6.253 MJ | 6.616 MJ | 0.363 MJ |
| 180 s | 26.993 MJ | 13.392 MJ | 13.601 MJ | 14.163 MJ | 0.562 MJ |

At 180 s the independently reconstructed gas-driven surface storage agrees
with the F3.3q gas balance within `0.562 MJ`, or about 4% of the inferred gas
boundary sink. Leakage, vent radiation and the semi-infinite approximation
can own that residual. This correspondence is strong enough to identify the
missing energy paths.

## SimuFire material-shadow partition

At 180 s the material control removes:

| Canonical path | Energy |
|---|---:|
| Gas to wall reservoir | 9.107 MJ |
| Direct ambient decay | 3.796 MJ |
| Exterior/leakage | 0.531 MJ |
| Total gas boundary sink | 13.433 MJ |
| Wall reservoir energy retained | 9.009 MJ |

The total gas sink matches CFAST because direct ambient decay substitutes for
part of the missing wall conductance. It does not heat any physical surface.

The canonical wall reservoir is also missing the `13.392 MJ` direct
combustion-radiation source. Its retained energy is therefore about
`17.985 MJ` below the estimated CFAST surface storage. That explains why the
single canonical wall remains at `20.68 C` while CFAST surfaces reach
approximately `29.22-52.38 C`, even though the gas boundary sink is close.

## Root cause

The F3.3r0 late overcool is not evidence that concrete is wrong. It is caused
by a semantically incomplete boundary contract:

1. accepted combustion radiation does not enter a wall/surface reservoir;
2. direct ambient decay removes gas energy without surface storage;
3. one reservoir cannot represent ceiling, floor and wall temperatures or
   return heat to the correct zone;
4. increasing the current `40 m2` conductance would strengthen the sink
   without repairing any of those paths.

## Decision

F3.3r1 is diagnostic GO. It closes owner attribution but authorizes no
runtime change.

F3.3r2 must be a design-only phase for a default-OFF multi-surface shadow:

1. define ceiling, wall and floor reservoirs with explicit area/capacity;
2. route accepted combustion radiation atomically to surfaces;
3. replace wall-like ambient decay with gas-to-surface exchange while
   retaining true exterior/leakage loss separately;
4. assign surface exchange to upper/lower zones using interface geometry;
5. preserve a single room energy invariant across gas, surfaces and exterior;
6. require 60/120/180 s STOP gates before any 300/600 s experiment.

No full-area patch, new coefficient or motor authority is allowed before
that design is reviewed.
