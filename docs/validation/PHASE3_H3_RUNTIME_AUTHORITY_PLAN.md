# Phase 3 H3 - Runtime Authority Plan for the Coupled Pressure Solver

Date: 2026-08-02. Checkpoint `ef1f3ffb`.

Design and wiring diagnosis only. `sim/core` was read, never modified. No flag
was added, no authority granted, no baseline touched.

## Headline

**H3.1 (passive dual-write ledger) can be implemented without changing
physics.** `Phase3ZoneMassSystem` writes **zero** room state today - measured,
not assumed - so a second ledger alongside it cannot move a number.

**H3.3 (mass/energy commit) is blocked by a prerequisite this diagnosis
found.** `ZoneFireSolver.project_room_state` is not a projection. It
*reconstructs* energy from clamped temperature and runs after everything,
including inside `_clamp_rooms`. Any energy an authoritative solver commits is
overwritten before the step ends. Committing energy while that stands would not
be authority; it would be a write that silently disappears.

## 1. Architectural diagnosis, from real writes

The methodological rule was to follow actual writes rather than names. Doing so
contradicts the names in three places.

### 1.1 Who actually owns room mass and energy

Counted assignments to `upper_gas_kg`, `lower_gas_kg`, `upper_energy_kj`,
`lower_energy_kj`:

| File | mass | energy | dominant functions |
|---|---:|---:|---|
| `ThermalSystem.gd` | 22 | 34 | `step` (17), `sync_room_upper_layer` (8), `_apply_canonical_doorway_exchange` (7), `_apply_doorway_thermal_counterflow` (3) |
| `ZoneFireSolver.gd` | 9 | 16 | `project_room_state` (7), `ensure_room_state` (6), `collapse_upper_into_lower` (4), `apply_lower_to_upper_transfer` (4) |
| `GasExchangeSystem.gd` | 5 | 5 | `step_smoke` (4), `_apply_background_species_exchange` (4), `_release_pending_interior_deliveries` (2) |
| `SimulationEngine.gd` | 3 | 7 | `_clamp_rooms` (7) |
| `HVACSystem.gd` | 1 | 1 | `_apply_supply_heat` (2) |

Three findings the file names hide:

1. **`ZoneFireSolver` is a mass and energy writer**, and it was not in the
   reading list for this session. It is the last word on energy.
2. **`ThermalSystem`, not `GasExchangeSystem`, owns interior doorway
   transport** - through two separate paths,
   `_apply_canonical_doorway_exchange` and `_apply_doorway_thermal_counterflow`.
3. **`SimulationEngine._clamp_rooms` writes mass and energy**, and also calls
   `project_room_state` twice.

Species and O2 confirm the pattern: `ThermalSystem` writes species 37 times and
`GasExchangeSystem` 32; O2 is written by `OxygenExchangeSystem` (19),
`ThermalSystem` (7) and `HVACSystem` (4).

**Roughly ten distinct call sites own the same state.** That is the real
obstacle to authority, not the solver.

### 1.2 `project_room_state` reconstructs; it does not project

`sim/core/ZoneFireSolver.gd:199`. After `ensure_room_state`, and after a
thermal-inversion mix that rewrites both energies, it ends with:

```gdscript
room.upper_energy_kj = room.upper_gas_kg \
        * maxf(0.0, room.temp_upper_c - ambient_c) * AIR_CP_KJ_KG_K
room.lower_energy_kj = room.lower_gas_kg \
        * maxf(0.0, room.temp_lower_c - ambient_c) * AIR_CP_KJ_KG_K
```

`temp_upper_c` is already `minf(raw, max_upper_temp_c)`, and the source comment
states the intent plainly: the thermal cap is an explicit numerical sink.

Energy is therefore a **derived** quantity re-derived from `(mass, clamped
temperature, ambient)` at every call, from nine call sites across
`SimulationEngine` (3) and `ThermalSystem` (5) plus its own recursion, and last
of all from `_clamp_rooms`.

**Consequence.** A committed `upper_energy_kj` survives only if it happens to
equal `mass x (clamped T - ambient) x cp`. Any genuine energy correction the
solver makes is discarded. This is the hard blocker for H3.3.

### 1.3 Delayed parcels cross timestep boundaries

`sim/core/GasExchangeSystem.gd:110` holds `_pending_interior_deliveries`.
Entries carry `upper_gas_kg`, `upper_energy_kj`, `o2_kg` and every species, are
appended at line 1338, and are released by `_release_pending_interior_deliveries`
(1733), which decrements `delay_s` by `dt` and **keeps** anything still above
`1e-6`.

So interior mass, energy, O2 and species are **in flight across ticks**, with a
parallel `_inflight_species_kg` ledger tracking them. An atomic per-step bundle
and a cross-tick in-flight pool cannot both own the same transport without
double counting on release or losing it on adoption.

### 1.4 The solver is passive, and provably so

`Phase3ZoneMassSystem.gd` contains **zero** assignments to room mass, energy or
O2. `solve_coupled_pressure` is called from exactly one place -
`Phase3ZoneMassSystem.gd:5879`, inside `_record_coupled_pressure_solver_preview`
- and its result feeds only telemetry.

It also runs **last**: `SimulationEngine.gd:2698` calls `finalize_step` after
`_clamp_rooms`. The solver currently observes a step that is already finished.

## 2. Current tick

```text
step(dt)                                          SimulationEngine.gd:2562
 ├─ _step_exterior_opening_smooth                 2583
 ├─ _build_opening_flow_cache                     2590   frozen per-step view
 ├─ phase3 shadow: begin_step + queue requests    2595-2630  (passive)
 ├─ _step_pool_fires                              2634
 ├─ [_step_oxygen]  (pre-HRR variant)             2636   WRITES O2
 ├─ _step_fire                                    2642   WRITES species, fuel
 ├─ _step_co_oxidation / _step_targets            2647
 ├─ [_step_oxygen]  (post-HRR variant)            2651   WRITES O2
 ├─ thermal_system.step                           2655   WRITES mass, energy,
 │     ├─ _apply_canonical_doorway_exchange              species  <-- interior
 │     ├─ _apply_doorway_thermal_counterflow             transport lives here
 │     └─ sync_room_upper_layer / project_room_state
 ├─ conservation check                            2664   read-only
 ├─ _step_suppression / _step_steam_decay / glass 2669
 ├─ _step_gas_exchange                            2678   WRITES mass, energy,
 │     ├─ step_smoke                                     species; creates and
 │     └─ _release_pending_interior_deliveries           releases parcels
 ├─ _step_hvac                                    2685   WRITES mass, energy, O2
 ├─ _step_passive_fuel / fire_spread              2687
 ├─ reconcile_two_zone_building                   2693   WRITES (M1 absorb)
 ├─ _clamp_rooms                                  2695   WRITES + project_room_state
 ├─ phase3_zone_mass_system.finalize_step         2698   PASSIVE, solver runs here
 └─ carbon balance / ILV guardrails / logging     2700+
```

The solver sits at the end of a pipeline whose state has already been written
by five systems and reconstructed twice.

## 3. Proposed H3 tick

```text
step(dt)
 ├─ opening smooth + flow cache                   unchanged
 ├─ PRE-STATE SNAPSHOT (authoritative)            new, owned by Phase3ZoneMassSystem
 ├─ sources: pool fires, fire, CO oxidation, O2   unchanged - these are OWNERS,
 │     (they produce mass/energy/species sources,        not transport
 │      not interior transport)
 ├─ COUPLED SOLVE                                 moved here from finalize_step
 │     input : pre-state + owner sources + opening geometry
 │     output: pressure field + accepted opening bundle
 ├─ ACCEPT BUNDLE (single atomic write)           new
 │     mass, energy per room from the SAME bundle
 ├─ ADVECT with the accepted fractions            new
 │     O2 and every species use the bundle's donor fractions - no second law
 ├─ interface / EOS update                        from committed state
 ├─ RESIDUAL PROJECTION (not reconstruction)      requires the H3.2b change
 ├─ non-transport systems: suppression, HVAC,     unchanged initially
 │     wall conduction, radiation
 └─ finalize / telemetry / guardrails             unchanged
```

The essential inversion: the solver must run **before** the writers it is meant
to replace, not after them.

## 4. Ownership, current versus target

| State | Current owners | H3 target owner | Retired when |
|---|---|---|---|
| room pressure | derived in `RoomModel` / EOS from mass+energy | coupled solver | H3.2 |
| interior opening mass flux | `ThermalSystem._apply_canonical_doorway_exchange`, `_apply_doorway_thermal_counterflow`, `GasExchangeSystem` parcels | accepted bundle | H3.3 |
| interior opening energy flux | same three | accepted bundle | H3.3 |
| upper/lower mass split | `ThermalSystem`, `ZoneFireSolver` | bundle + interface rule | H3.5 |
| energy from temperature | `ZoneFireSolver.project_room_state` (**reconstruction**) | residual projection only | **H3.2b, prerequisite** |
| O2 through interior openings | `OxygenExchangeSystem`, `ThermalSystem` | bundle advection | H3.4 |
| species through interior openings | `ThermalSystem` (37), `GasExchangeSystem` (32) | bundle advection | H3.4 |
| delayed parcels | `GasExchangeSystem._pending_interior_deliveries` | **removed for authoritative interior openings** | H3.3 |
| exterior vent purge | `ThermalSystem` / engine | bundle (exterior openings) | H3.5 |
| HVAC | `HVACSystem` | stays legacy, declared source | out of H3 scope |
| final clamp | `SimulationEngine._clamp_rooms` | non-negativity only | H3.5 |

## 5. Invariants to gate every timestep

Hard gates, all evaluated before a committed step is accepted:

1. building total mass conserved to the owner-source budget;
2. building total energy conserved to the owner-source budget;
3. `upper_gas_kg >= 0` and `lower_gas_kg >= 0` for every room;
4. EOS closure: solved pressure reproduces the committed mass and energy;
5. O2 mass conserved and consistent with its tracer fraction;
6. every species conserved, with zero net creation in transport;
7. gross transport counted exactly once per opening per step;
8. counterflow preserved where the neutral plane is inside the vent;
9. donor stock never exceeded - no opening moves more than the donor holds;
10. zero species pumping - no concentration rises above every contributing donor;
11. zero parcel duplication - a bundle and an in-flight parcel never carry the
    same mass;
12. pressure finite on every room;
13. interface height inside the room geometry;
14. solver converged, or the step fails closed (see 7 below).

Metrics that distinguish a real correction from residual redistribution:

- the pressure-owner residual must **close**, not merely shrink: the committed
  bundle must satisfy the same mass balance the solver solved;
- the coupled-vs-legacy divergence must be reported per owner, so a change that
  merely moves error between rooms is visible as a redistribution rather than a
  reduction;
- `max_abs_residual_kg` per room, not just the normalized L-infinity.

## 6. Flags, all default OFF

No per-case knobs. Physics is never calibrated through a flag; each flag only
transfers ownership.

| Flag | Grants | OFF behaviour |
|---|---|---|
| `phase3_coupled_pressure_solver_shadow` | existing preview | already shipped |
| `phase3_coupled_dual_write_ledger` | H3.1 passive second ledger | no ledger, byte-identical |
| `phase3_coupled_interior_bundle_authority` | H3.2 solver owns the bundle, state still shadow | legacy bundle |
| `phase3_coupled_commit_mass_energy` | H3.3 bundle writes mass and energy | legacy writes |
| `phase3_coupled_advect_species` | H3.4 O2 and species use bundle fractions | legacy advection |
| `phase3_coupled_interface_authority` | H3.5 interface, EOS, residual projection | legacy projection |
| `phase3_projection_residual_mode` | H3.2b projection instead of reconstruction | reconstruction |

## 7. Failure policy when the solver does not converge

Three options were considered. The recommendation is **fail closed with an
explicit legacy fallback for the step**, not a silent one:

- **abort the step** - rejected: it would stall the simulation on a single bad
  component and is worse than the current behaviour;
- **silent legacy fallback** - rejected: it hides non-convergence inside a
  physically plausible result, which is exactly the failure mode this whole
  H2 series existed to eliminate;
- **explicit fallback** - recommended: the component reverts to the legacy path
  for that step, the step is flagged in telemetry with the limiting reason, and
  a per-run counter gates promotion. A run with any fallback cannot be promoted.

H2.10 makes this rare rather than theoretical: across ten runtime topologies
convergence is 100%, `damping_exhausted` fell 27 to 0 and `iteration_cap`
stayed 0. The fallback must still exist and be counted.

## 8. Phase plan

### H3.0 - design and ownership map (this document)

Files: documentation only. Flag: none. Authority: none.
STOP gate: this document accepted. Rollback: n/a.
**Blocks:** everything below until accepted.

### H3.1 - passive dual-write ledger

- **Files:** `Phase3ZoneMassSystem.gd`, `SimulationLogWriter.gd`, new fixture
  and structural test.
- **Flag:** `phase3_coupled_dual_write_ledger`, default OFF.
- **OFF:** no columns, no allocation, byte-identical CSV.
- **Authority:** none. The ledger records, per step and per opening, what the
  accepted bundle *would* be, beside what legacy actually did.
- **Telemetry:** per-opening legacy vs bundle mass and energy, per-room
  divergence, parcel-overlap count, and the pressure-owner residual.
- **Fixtures:** the twelve minimum cases; assert OFF byte-identity and that the
  ledger never writes room state.
- **Duration:** 120 s per case.
- **STOP gate:** OFF byte-identical on all twelve; ledger writes zero state;
  divergence characterised per topology.
- **Rollback:** remove the flag; nothing else changed.
- **Blocks:** H3.2 until the divergence is understood per topology.

### H3.2 - bundle authority, state still shadow

- **Files:** `Phase3ZoneMassSystem.gd` only.
- **Flag:** `phase3_coupled_interior_bundle_authority`.
- **Authority:** the solver decides the interior opening bundle; the bundle is
  still not written to rooms.
- **STOP gate:** bundle satisfies invariants 7-11 on every step of the corpus.
- **Blocks:** H3.3 until the bundle is provably donor-limited and single-counted.

### H3.2b - projection becomes residual (PREREQUISITE, newly identified)

- **Files:** `ZoneFireSolver.gd`, `SimulationEngine.gd` call sites.
- **Flag:** `phase3_projection_residual_mode`.
- **Why it exists:** without it, H3.3 cannot succeed. `project_room_state`
  currently rebuilds energy from clamped temperature, so a committed energy is
  overwritten before the step ends.
- **Authority:** projection corrects only the residual inconsistency between
  mass, energy and temperature instead of re-deriving energy.
- **Risk:** this touches the thermal cap, which is an intentional energy sink.
  Removing it silently would change physics. The flag must preserve the cap as
  an **explicitly reported sink**, not delete it.
- **STOP gate:** with the flag ON but no other H3 flag, every case is
  byte-identical or its difference is fully explained by the cap accounting.
- **Blocks:** H3.3 absolutely.

### H3.3 - commit mass and energy

- **Files:** `Phase3ZoneMassSystem.gd`, `ThermalSystem.gd`,
  `GasExchangeSystem.gd`, `SimulationEngine.gd`.
- **Flag:** `phase3_coupled_commit_mass_energy`.
- **Authority:** the bundle writes interior mass and energy; the legacy doorway
  paths and the interior delayed parcels are **disabled for authoritative
  openings only**.
- **STOP gate:** invariants 1-14; no double transport; conservation closed; FED
  without unexplained regression.
- **Rollback:** flag OFF restores every legacy path.
- **Blocks:** H3.4.

### H3.4 - O2 and species on the common bundle

- **Files:** `OxygenExchangeSystem.gd`, `GasExchangeSystem.gd`,
  `ThermalSystem.gd`.
- **Flag:** `phase3_coupled_advect_species`.
- **Authority:** O2 and every species advect with the **same accepted donor
  fractions** as mass. No independent transport law.
- **STOP gate:** invariants 5, 6, 10; carbon and HCN sentinels unchanged.
- **Blocks:** H3.5.

### H3.5 - interface, EOS and limited projection

- **Files:** `ZoneFireSolver.gd`, `SimulationEngine.gd`.
- **Flag:** `phase3_coupled_interface_authority`.
- **STOP gate:** invariants 4, 13; `_clamp_rooms` reduced to non-negativity.
- **Blocks:** H3.6.

### H3.6 - Group A / Group C and long corpus

- **Files:** none; validation only.
- **STOP gate:** CFAST Group A and Group C within existing tolerances; long
  corpus stable; no VALID_GAP closed and no baseline updated without explicit
  approval.
- **Blocks:** H3.7.

### H3.7 - promotion and legacy retirement

- **Files:** removal of superseded paths.
- **STOP gate:** explicit approval; only here may a default flip ON.

## 9. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | committed energy silently overwritten by `project_room_state` | **critical** | H3.2b prerequisite; a fixture that asserts a committed energy survives to end of step |
| 2 | double transport: bundle plus a released parcel | **critical** | parcels disabled per authoritative opening; invariant 11 with a parcel-overlap counter |
| 3 | `ThermalSystem` has two doorway paths, not one | high | ledger in H3.1 must attribute both before either is retired |
| 4 | thermal cap is a real energy sink; removing it changes physics | high | keep it, report it as an explicit sink |
| 5 | O2 advected by a different law than mass | high | H3.4 forces the shared donor fraction |
| 6 | `_clamp_rooms` masks conservation errors as clamp loss | medium | measure clamp loss per step before H3.3 |
| 7 | solver non-convergence in an unvisited topology | medium | explicit fallback plus promotion gate on the counter |
| 8 | HVAC writes mass, energy, O2 and species outside the bundle | medium | out of scope, declared as an owner source |
| 9 | in-flight parcels at the moment a flag flips | medium | flags may only flip between runs, never mid-run |
| 10 | ten runtime topologies is still a narrow corpus | medium | H3.6 widens before promotion |

## 10. Recommendation for H3.1

**Implement H3.1 as specified. It cannot change physics**, and that is
demonstrated rather than asserted: `Phase3ZoneMassSystem` performs zero writes
to room mass, energy or O2 today, and the flag adds only a second passive
ledger inside that same system plus opt-in CSV columns.

The ledger must answer, per topology, before H3.2 is designed:

1. how far the accepted bundle diverges from what the two `ThermalSystem`
   doorway paths plus the parcels actually moved;
2. how much mass and energy is in flight at step boundaries;
3. how much `_clamp_rooms` removes per step;
4. how much energy `project_room_state` re-derives away per step.

Items 3 and 4 are the ones this diagnosis could not answer by reading, and they
determine whether H3.3 is a small commit or a restructuring.

## 11. STOP gate

Design only. No `sim/core` change, no flag, no authority, no baseline touched,
no VALID_GAP closed. H3 remains unstarted as implementation.

**Requested decision:** accept this ownership map and the phase plan, and
authorise **H3.1 only**. H3.2b is newly identified as a hard prerequisite for
H3.3 and should be scheduled before any commit of mass or energy.
