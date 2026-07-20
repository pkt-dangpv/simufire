# Phase 3+ F3.2b5c mass, energy and pressure equivalence

Date: 2026-07-19

## Scope

F3.2b5c is a diagnostic gate after canonical inter-zone heat and canonical
wall/ambient ownership. It adds no production mechanism. It repeats the Group
A CFAST equivalence matrix and runs independent closed/open, fire/no-fire
controls using the full F3.2b5b shadow stack.

No official report, baseline, expected value, tolerance or VALID_GAP
classification changes in this phase.

## Fixed comparison matrix

All rows below use the same target times between 100 and 350 s. The mass and
energy values compare canonical room state with CFAST upper+lower inventories;
pressure is the canonical EOS result, not a separately fitted value.

| Experiment | Pressure RMSE | Mass RMSE | Energy RMSE | Upper-T RMSE | Lower-T RMSE | Interface RMSE |
|---|---:|---:|---:|---:|---:|---:|
| F3.2b5b baseline | 274 Pa | 8.32 kg | 2398 kJ | 71.2 C | 23.7 C | 0.401 m |
| `chi_rad=0.35` | 875 Pa | 3.16 kg | 777 kJ | 33.9 C | 16.7 C | 0.389 m |
| CFAST leakage only | 628 Pa | 8.09 kg | 2404 kJ | 70.9 C | 23.7 C | 0.401 m |
| `chi=0.35` + CFAST leakage | 360 Pa | 2.69 kg | 803 kJ | 33.8 C | 16.7 C | 0.388 m |
| Concrete properties only | 491 Pa | 10.71 kg | 3142 kJ | 96.4 C | 30.0 C | 0.404 m |
| All three | 521 Pa | 5.16 kg | 1531 kJ | 36.6 C | 27.7 C | 0.391 m |

The baseline pressure improvement from F3.2b5b is still cancellation: at
160 s it has 11.53 kg too much gas and 3.32 MJ too little sensible energy.
Pressure happens to be 1000 Pa versus 1061 Pa in CFAST.

`chi=0.35` plus CFAST leakage is the best simultaneous state-equivalence
candidate. It reduces mass, energy and both temperature errors while keeping
pressure materially closer than `chi=0.35` alone. It is not accepted as a
case or engine change in this gate. The remaining exterior-flow contract must
be fixed before deciding configuration authority.

The concrete lumped candidate is rejected. A single canonical lumped wall
using the declared concrete capacity/conductance cools the gas too strongly
and worsens every independent state metric except pressure. CFAST wall
temperature is also not reproduced by that approximation.

## Controls

### No fire, closed and open

The 60 s closed control and an independent 60 s fully open-window control stay
at exact ambient equilibrium. Wall energy, wall exchange, ambient removal,
exterior mass/energy, gauge pressure and volume-closure residual are all zero.

### Sealed fire

The pre-opening Group A interval supplies the sealed-fire control. All atomic,
thermodynamic and wall-boundary conservation residuals remain zero. The three
Group A shadow O2 samples remain inside the existing tolerances.

### Fire plus exterior opening

The best equivalence candidate was extended to 420 s. The window opens at
360 s. The canonical pressure relaxer reaches 0 Pa without crossing, and mass,
energy, O2, species, wall and volume residuals remain exactly zero.

The physical state does not match CFAST after opening:

| Time | Shadow upper O2 | CFAST upper O2 | Shadow interface | CFAST interface | Shadow HRR | CFAST HRR |
|---:|---:|---:|---:|---:|---:|---:|
| 360 s | 0.0665 | 0.0645 | 0.164 m | 0.100 m | 118 kW | 288 kW |
| 380 s | 0.0700 | 0.0616 | 0.153 m | 0.522 m | 210 kW | 1280 kW |
| 400 s | 0.0626 | 0.1072 | 0.147 m | 0.968 m | 189 kW | 1280 kW |
| 420 s | 0.0614 | 0.1320 | 0.141 m | 1.020 m | 142 kW | 1280 kW |

The lower shadow zone remains at ambient O2 but its mass falls from 3.68 to
3.24 kg after opening. CFAST instead expands the lower layer and reoxygenates
the upper layer.

## Root cause

F3.2a/F3.2b2 models the exterior boundary as one net direction selected from
the room gauge pressure. At any instant every active exterior route is either
outflow or inflow. The pressure-equilibrium cap then drives the room to about
0 Pa, where the net request becomes small.

A hot open compartment needs simultaneous buoyant counterflow even when net
pressure is zero:

```text
upper hot gas -> exterior
exterior fresh air -> lower zone
```

CFAST window net flow reaches about 0.30-0.41 kg/s just after opening, while
the canonical net bundle carries about 0.02-0.10 kg/s at the sampled steps.
The CFAST net value also hides the larger opposing gross streams.

This missing gross exchange traps fresh O2 in the lower reservoir. Canonical
plume transfer then enters a positive-feedback failure: low upper O2 limits
canonical HRR, the weak fire entrains too little lower gas, and upper O2 cannot
recover. At 380-420 s the canonical plume carries only about 0.011 kg/s while
CFAST reports approximately 0.84-1.64 kg/s.

This is a boundary ownership gap, not a wall-rate problem and not permission
to tune plume coefficients per case.

## Next gate: F3.2b6

F3.2b6 must add a default-OFF canonical bidirectional exterior-opening shadow:

1. Compute hydrostatic pressure by vertical opening segment from canonical
   upper/lower temperature, density and interface plus ambient exterior state.
2. Locate the neutral plane and produce simultaneous upper outflow and lower
   inflow when buoyancy supports both.
3. Decompose gross counterflow from the net pressure-relief component already
   owned by F3.2a/F3.2b2. The two owners must never double-count mass.
4. Transport gas, sensible energy, O2 and species in atomic routes.
5. Export gross upper-out, gross lower-in, net flow, neutral plane and closure
   residuals separately.
6. Re-run no-fire-open, sealed-fire and fire-opening controls before any
   Group A promotion.

Existing legacy interior-opening formulas may inform the preview, but the new
request must consume canonical pre-step state and static opening geometry. It
must not call a legacy mutation and infer the result afterwards.

## STOP gate

Decision: **F3.2b5c diagnostic GO; canonical authority and Group A retirement
NO-GO**.

F3.2b6 is required before F3.3/Group C. The current shadow remains default OFF
and must not publish to `RoomModel` or FED.
