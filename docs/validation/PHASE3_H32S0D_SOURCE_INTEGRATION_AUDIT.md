# Phase 3 H3.2-S0d Source Integration Audit

Date: 2026-08-04
Decision: **NO-GO — mass and energy coverage is also incomplete (outcome C)**

No `sim/core`, runner, CSV, expected, tolerance or report file was changed.
`Phase3PhysicalSourceIntegrator.gd` was **not** created.

## Decisive question

> Can `source_mass_kg`, `source_energy_kj`, `source_o2_kg` and
> `source_species_kg` be built per room and zone from a pre-step snapshot plus
> explicit owner events, without reading post-state and without legacy
> transport?

**No.** Neither the species/O2 half nor the mass/energy half closes. The answer
is not "B, partial honest closure of mass/energy": mass and energy have active,
material owners that emit no event at all.

## Coverage table

`upper/lower` zone mass and sensible energy are written at **107 statements**
across five files.

| File | Statements | Owner coverage |
|---|---:|---|
| `ThermalSystem.gd` | 58 | S0b events + H3.1 doorway ledger + projection trace; four uncovered sites |
| `ZoneFireSolver.gd` | 27 | projection trace and `two_zone_boundary_energy_kj`; `transfer_lower_to_upper` / `add_lower_energy` owned at their S0b call sites |
| `GasExchangeSystem.gd` | 10 | fully owned by S0c |
| `SimulationEngine.gd` | 10 | one uncovered source; the rest are `_clamp_rooms` numerical corrections |
| `HVACSystem.gd` | 2 | uncovered, deferred |

### Classification by family

| Family | Class | Covered by | Feeds the source vector? |
|---|---|---|---|
| combustion convective heat | local_source | S0b `thermal_combustion_convective_heat` | yes |
| plume entrainment, layer lift, vertical mixing, minimum layer | interzone_redistribution | S0b (two-zone branch only) | no, by contract |
| radiation to exterior, ambient loss, lower decay, fresh-air cooling, exterior mixing | exterior_boundary | S0b | yes |
| wall absorption/emission, wall conduction | local_source | S0b | yes |
| opening radiation, thermal background, stairwell bridge, outside-assisted | interior_transport | S0b | no, by contract |
| canonical doorway upper/lower/counterflow | interior_transport | H3.1 doorway ledger | no, by contract |
| gas exterior removal (venting, smoke vent, PPV inlet/exhaust) | exterior_boundary | S0c | yes |
| gas immediate and background upper transport | interior_transport | S0c | no, by contract |
| delayed parcels | delayed_parcel | S0c + parcel ledger | no, by contract |
| projection, reconcile, `_clamp_rooms`, collapse, layer sync | numerical_correction | projection trace, `two_zone_boundary_energy_kj` | no, by contract |
| **suppression** | **local_source** | **nothing** | **required, missing** |
| **opening-radiation target mass seed** | **local_source** | **nothing** | **required, missing** |
| **doorway counterflow minimum mass** | **local_source** | **nothing** | **required, missing** |
| **HVAC** | **exterior_boundary** | **nothing** | **required, missing** |
| O2 (all paths) | mixed | none representable | blocked |
| CO, CO2, HCN, HCl, acrolein, formaldehyde, smoke | mixed | partial shadow ledgers only | blocked |

## Blocking findings

### B1 — Suppression has no owner (`SimulationEngine.gd:3315-3330`)

```
upper_loss_kj  = min(room.upper_energy_kj, cooling_kj * suppression_upper_heat_fraction)
room.upper_energy_kj = max(0.0, room.upper_energy_kj - upper_loss_kj)   # no event
room.temp_lower_c    = max(ambient_c, room.temp_lower_c - lower_drop_c) # no event
```

The upper sink is an explicit accepted `kJ` and would be instrumentable, but it
emits nothing today. The lower sink is worse: it is written as a **temperature**,
so its energy only enters `lower_energy_kj` later, through
`sync_room_upper_layer` — a numerical correction that the contract forbids from
feeding physical sources. A mass/energy owner ledger cannot recover it without
post-state.

### B2 — Unowned mass creation in opening radiation (`ThermalSystem.gd:1629-1631`)

```
if tgt.upper_gas_kg <= 0.0001:
    tgt.upper_gas_kg = tgt.floor_area_m2() * 0.08 * gas_density_kg_m3(tgt.temp_lower_c)
```

Upper-zone mass appears with no donor, no exterior boundary and no event. The
`thermal_opening_radiation` event next to it carries energy only.

### B3 — Unowned mass creation in doorway counterflow (`ThermalSystem.gd:3272-3273`)

```
if cold_room.upper_gas_kg < 0.01:
    cold_room.upper_gas_kg += 0.005
```

Mass is created so the cold room can accept energy. The H3.1 doorway ledger
observes the magnitude, but records it as a transport counterparty — a transfer
whose mass does not balance. H3.1 composite records are explicitly barred as
source inputs, and transport is barred by the contract regardless.

### B4 — HVAC is unowned (`HVACSystem.gd:490-491` plus its removal callback)

```
room.upper_gas_kg    = max(room.upper_gas_kg, air_kg * 0.35)
room.upper_energy_kj = max(0.0, room.upper_gas_kg * (room.temp_upper_c - ambient_c))
```

HVAC also calls the generic `remove_upper_layer_fraction`; S0c gave provenance
only to the four `GasExchangeSystem` call sites. HVAC remains deferred by the
motor plan, so any HVAC-active scenario has an incomplete source vector by
construction.

### B5 — Species and O2 remain blocked (carried from S0c)

Species and O2 move through per-room `*_delta_kg` accumulators applied once,
under `maxf(0.0, ...)`. When that clamp binds, the accepted share per owner is
not recoverable without inventing an allocation rule. Bulk-room O2 additionally
has no zone identity, so it cannot satisfy the S0a event schema.

### B6 — The specified integrator cannot report its own completeness

Even with full coverage, the component described for this phase
(pure, S0a events in, no post-state, no legacy transport) **cannot** produce
truthful `completeness` flags or `missing_owner_reasons`. Absence of an owner is
not observable inside the event stream. Detecting it needs either post-state,
which the phase forbids as input, or a hardcoded per-room registry of expected
owners, which is invented ownership. Building it anyway would ship a component
that reports `complete = true` precisely because the missing owners are silent.

## Empirical confirmation

Seven cases were run with `--phase3-physical-owner-ledger` (read-only; no motor
change). Every ledger is valid with zero invalid and zero duplicate events, and
**no suppression owner and no HVAC owner exists in any of them**:

| Case | events | classes | suppression owners | HVAC owners |
|---|---:|---|---|---|
| `cfast_suppression_water` | 10 | local 7, exterior 2, interzone 1 | none | none |
| `v8_suppression_reburn` | 17 | local 7, exterior 4, transport 2, parcel 2, interzone 2 | none | none |
| `cfast_hvac_residential` | 11 | local 7, exterior 2, interzone 2 | none | none |
| `ppv_attack_pressurized` | 17 | local 7, exterior 4, transport 2, parcel 2, interzone 2 | none | none |
| `cfast_two_floor_stairwell` | 21 | local 14, exterior 3, transport 2, interzone 2 | none | none |
| `two_storey_smoke` | 22 | local 14, exterior 3, transport 2, parcel 1, interzone 2 | none | none |
| `uk_bungalow_smoke` | 23 | local 8, exterior 5, transport 4, parcel 4, interzone 2 | none | none |

A source vector restricted to `local_source` and `exterior_boundary` is
computable for every room in all seven cases. It is simply **wrong**: in the two
suppression cases and the HVAC case it silently omits the dominant sink of the
step.

## Accounting chain

```
pre-state
  + local_source        (S0b thermal, S0c gas)          -> source vector
  + exterior_boundary   (S0b thermal, S0c gas)          -> source vector
  + interzone           (S0b, room-internal, sums to 0) -> excluded
  + interior_transport  (S0b, S0c, H3.1 doorway)        -> excluded
  + delayed_parcel      (S0c, parcel ledger)            -> excluded
  + numerical_correction(projection trace, clamps)      -> excluded
  + UNOWNED: suppression, opening-radiation mass seed,
             doorway counterflow mass, HVAC             -> nothing
  + species/O2 behind aggregate clamps                  -> nothing
= post-state
```

The chain does not close. The gap is not a residual to be classified; it is a
set of named mutation sites that emit nothing.

## What would unblock S0d

Each item is instrumentation work at a mutation site, not integration:

1. Own the suppression upper sink with its explicit `upper_loss_kj`, and own the
   lower sink as energy rather than letting a temperature write reach the state
   through projection.
2. Own the opening-radiation target mass seed and the doorway-counterflow
   minimum-mass injection, or remove both in favour of a real donor.
3. Own HVAC, or declare every HVAC-active scenario permanently invalid for the
   source vector.
4. Give species and O2 per-owner accepted shares before the aggregate clamp, or
   accept that only mass and energy can ever be sourced.

Only after 1-3 can a mass/energy source vector claim completeness, and only
after 4 can H3.2-S claim a full independent source.

## STOP decision

**NO-GO (outcome C).** H3.2-S **cannot** be closed. S0d stays open, H3.2b still
blocks H3.3, and no runtime authority was granted to any solver.
`Phase3CoupledPressureSolver` was neither called nor modified.
