# Phase 3+ F3.3r0 material correspondence

Date: 2026-07-24

Status: diagnostic GO, runtime/adoption NO-GO.

## Purpose

F3.3r0 tested the first mismatch isolated by F3.3q: the official
`cfast_corridor_chain` case does not map the CFAST concrete properties into
the canonical shadow wall contract. The experiment changed only the existing
room material overrides in a scratch copy of the case. It kept the canonical
wall area at `40.0 m2` and did not change direct ambient decay, openings,
combustion, official reports, baselines, tolerances, gaps, FED or HVAC.

The material control used, for rooms 0, 1 and 2:

| Property | Value |
|---|---:|
| Conductivity | `0.00175 kW/(m K)` |
| Density | `2200 kg/m3` |
| Specific heat | `1.0 kJ/(kg K)` |
| Thickness | `0.15 m` |

## Reproduction gate

The current tree no longer contains the temporary F3.3p1 coupled-Qc helper.
It was reintroduced only long enough to reproduce the valid F3.3p1 shadow
composition in scratch and was then removed completely.

The base scratch run and
`runs/phase3_f33p1_180_on_v2/sim_log.csv` have the same 114 `(time, room)`
rows. All 552 shared canonical columns are identical within `1e-9`.
Therefore the material delta is attributable to the room material mapping,
not to a changed source, plume or routing contract.

## Boundary-energy result

| Window | CFAST sink | Base sink | Material sink | Material shortfall |
|---|---:|---:|---:|---:|
| 0-60 s | 0.959 MJ | 0.309 MJ | 0.558 MJ | 0.401 MJ |
| 60-120 s | 5.657 MJ | 3.837 MJ | 5.243 MJ | 0.414 MJ |
| 120-180 s | 7.547 MJ | 6.603 MJ | 7.632 MJ | -0.085 MJ |
| 0-180 s | 14.163 MJ | 10.749 MJ | 13.433 MJ | 0.730 MJ |

Concrete mapping removes `2.684 MJ`, or 78.6%, of the previous `3.414 MJ`
boundary-sink deficit. The canonical inferred and observed balances still
close exactly in every time window.

## Thermal STOP gate

### R0

| Time | CFAST upper/lower/interface | Base upper/lower/interface | Material upper/lower/interface |
|---|---|---|---|
| 60 s | 64.5 C / 22.2 C / 1.250 m | 69.2 C / 20.9 C / 1.152 m | 60.8 C / 20.6 C / 1.147 m |
| 120 s | 139.2 C / 33.7 C / 0.790 m | 185.4 C / 28.3 C / 0.809 m | 144.1 C / 25.0 C / 0.840 m |
| 180 s | 159.8 C / 61.6 C / 0.736 m | 200.7 C / 53.1 C / 0.681 m | 147.2 C / 35.6 C / 0.796 m |

The material control corrects the upper-zone overtemperature through 120 s
and remains much closer at 180 s. It does not preserve lower-zone
correspondence: R0 lower temperature is `26.0 C` below CFAST at 180 s.

### Downstream rooms at 180 s

| Room | CFAST upper/lower/interface | Base upper/lower/interface | Material upper/lower/interface |
|---|---|---|---|
| Hall | 93.6 C / 48.4 C / 0.568 m | 134.2 C / 59.3 C / 0.763 m | 90.4 C / 35.4 C / 0.821 m |
| R2 | 62.1 C / 21.3 C / 0.100 m | 77.7 C / 25.5 C / 0.105 m | 49.0 C / 22.6 C / 0.166 m |

The Hall upper temperature improves, but its lower zone is `13.0 C` too
cold and the interface remains `0.253 m` too high. R2 upper temperature
changes from an overshoot to a `13.1 C` undershoot.

The single canonical wall reservoir also remains much colder than the four
CFAST surface classes. At 180 s its material temperature is `20.68 C`,
while CFAST reports approximately `29.22-52.38 C` across lower wall,
upper wall, floor and ceiling. A matched total sink is therefore not yet a
matched surface or zone heat-transfer contract.

## Decision

Direct material mapping is **not sufficient for runtime adoption**. It moves
the total boundary sink in the correct direction, but redistributes the
thermal state incorrectly and overcools lower/downstream zones. Increasing
the wall area from `40.0 m2` to the full `83.2 m2` enclosure is not authorized:
with the current zone/surface split it would increase an already excessive
late sink.

F3.3r1 is redefined as a read-only boundary-partition audit:

1. separate ceiling, upper-wall, lower-wall and floor exposure areas;
2. attribute convective and radiative requests to upper and lower gas;
3. compare per-surface stored energy and temperature with CFAST;
4. identify whether the missing contract is surface area, zone allocation,
   wall thermal penetration, or a combination;
5. design a default-OFF multi-surface shadow only after that attribution.

No official validation artifact or motor behavior changed in F3.3r0.

F3.3r1 completed this attribution in
`PHASE3_F33R1_BOUNDARY_PARTITION_AUDIT.md`: direct fire radiation and
wall-bypassing ambient decay, not another area multiplier, own the remaining
surface-state mismatch.
