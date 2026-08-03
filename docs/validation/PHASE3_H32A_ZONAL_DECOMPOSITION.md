# Phase 3 H3.2a - Zonal Decomposition of the Coupled Pressure Routes

Date: 2026-08-02. Baseline `344ec5fe`.

Purely additive output extension. `sim/` changes are confined to
`Phase3CoupledPressureSolver.gd`, **+227 lines and zero deletions**. No
authority granted, no VALID_GAP closed, no baseline, expected value, tolerance
or CTRL touched.

## Why this phase exists

H3.2 needs to feed the existing atomic route primitives, and
`_atomic_route_is_valid` requires `source_zone` and `destination_zone` to be
exactly `upper` or `lower`. The solver did not produce that: its unknown is one
gauge pressure per **room**, and `solved["connections"]` reported only the
aggregate `a_to_b_kg` / `b_to_a_kg` / `a_to_b_kj` / `b_to_a_kj`.

Three ways forward were considered and two were rejected outright. Assigning a
zone by convention would fabricate physics and make the planned comparison
against `canonical doorway upper` versus `lower` meaningless. Splitting the
aggregate by the neutral plane inside the adapter would add a flux derivation
the solver never performed. What H3.2a does instead is **surface a
classification the solver had already made and simply was not reporting**.

## Band and interface alignment

The decomposition rests entirely on a pre-existing invariant.
`_build_opening` splits the opening span at both rooms' interfaces before any
band is created:

```gdscript
# Split the span at every density discontinuity so that within a band both
# profiles are constant and dp(z) is exactly linear.
var boundaries: Array[float] = [bottom_m, top_m]
for interface_m in [float(side_a["interface_m"]), float(side_b["interface_m"])]:
    if is_finite(interface_m) and interface_m > bottom_m + 1.0e-9 \
            and interface_m < top_m - 1.0e-9:
        boundaries.append(interface_m)
boundaries.sort()
```

| Question | Answer | Evidence |
|---|---|---|
| Are bands cut exactly at **both** rooms' interfaces? | **Yes** | the loop iterates over `side_a` and `side_b` |
| Can a whole band be classified without subdivision? | **Yes** | the solver's own invariant: profiles are constant within a band |
| Can a band cross an interface? | **No, by construction** | interfaces are band boundaries, never interior points |
| Are interfaces in the same coordinates as `z0`/`z1`? | **Yes** | same opening-span height axis |

The stop rule from the phase brief - halt if an active band could cross an
interface - therefore does not trigger. No quadrature was changed, no active
integration was subdivided, and no split was approximated.

Two consequences reduced the authorised scope:

- **`Phase3ZoneMassSystem` was not touched.** Passing interface heights into
  the opening context was authorised but proved unnecessary: `_side_profile`
  already computes `interface_m` for both sides inside the solver.
- **Classification is a read, not a derivation.** `_zone_at` uses the *same
  band midpoint* that already selects the band's density and specific
  enthalpy, and mirrors the same convention (`height_m <= interface_m` is
  lower). The label therefore cannot disagree with the profile the integration
  actually used. Because interfaces are band boundaries, no midpoint can ever
  land on an interface, so the boundary case is unreachable; the convention is
  mirrored anyway so it cannot drift.

## Output schema

Per connection:

| Field | Meaning |
|---|---|
| `connection_id` | `"opening:<id>"`, shared by both directions |
| `zonal_decomposition_applicable` | false for exterior openings |
| `zonal_routes` | sorted route list, see below |
| `zonal_decomposition_valid` | no unclassified interior band on this connection |
| `unclassified_interior_band_count` | interior bands without both labels |
| `exterior_unzoned_band_count` | bands on an exterior opening |
| `zonal_mass_residual_kg` | routes versus aggregate, reported not corrected |
| `zonal_energy_residual_kj` | idem |

Per route:

`connection_id`, `direction` (`a_to_b` / `b_to_a`), `source_room_id`,
`destination_room_id`, `source_zone`, `destination_zone`, `gas_mass_kg`,
`sensible_energy_kj`, `band_count`.

Routes are sorted by connection, then direction, then source and destination
zone, so ordering is deterministic and independent of room or opening
iteration order - the solver already sorts openings by a stable key.

Per solve: `zonal_interior_connection_count`,
`zonal_exterior_connection_skipped_count`, `zonal_exterior_unzoned_band_count`,
`zonal_unclassified_interior_band_count`, `zonal_mass_residual_kg`,
`zonal_energy_residual_kj`, `zonal_decomposition_valid`.

## Exterior

The exterior has no layers. `_density_at` maps its non-finite interface to the
lower profile, which is harmless there because both exterior profiles hold the
same density - but that is a numerical convenience, **not** a claim that the
exterior has a lower layer.

`_zone_at` therefore returns an empty label for an exterior side, and the
connection is reported `zonal_decomposition_applicable = false` with no routes.
Its bands are counted in `exterior_unzoned_band_count`, never in
`unclassified_interior_band_count`, and **global validity is decided by interior
bands alone** so an exterior opening cannot invalidate the interior network. A
mutation control pins that returning `ZONE_LOWER` instead of `""` is
detectable. Exterior semantics are deferred to H3.5.

## Aggregate identity

The aggregates are accumulated exactly as before; the zonal ledger is filled in
a parallel branch afterwards, and a structural test forbids any aggregate from
being assigned out of a route total. The diff has **zero deleted lines**.

Evidence, strongest first:

- **13/13 Godot fixtures PASS**, including H1 and the whole H2.5-H2.10 family.
  These assert bit-exact residual histories, exact iteration counts and
  convergence modes on nine committed captures. This is the real proof.
- 28/28 structural tests, including negative controls.
- Runtime matrix byte-identical on ten scenarios.

**The runtime identity must not be over-read.** H3.2a adds no CSV column at
all - the decomposition lives only in the solver's returned dictionary - so
byte-identical logs are the expected outcome, not a strong isolation result.
The fixtures are what actually pin that no aggregate moved.

## Captures

| capture | conv | iters | interior/exterior | routes | counterflow | unclassified | mass residual | energy residual |
|---|---|---:|---|---:|---:|---:|---|---|
| `failure_corridor_chain` | yes | 5 | 2/0 | 3 | 0 | 0 | 0.0 | 0.0 |
| `failure_r0_window_360` | yes | 3 | 4/0 | 5 | 1 | 0 | 0.0 | 0.0 |
| `iteration_cap_corridor_chain` | yes | 7 | 2/0 | 2 | 0 | 0 | 0.0 | 0.0 |
| `iteration_cap_after_rescue_corridor` | yes | 4 | 2/0 | 2 | 0 | 0 | 0.0 | 0.0 |
| `iteration_cap_two_floor_stairwell` | yes | 11 | 9/0 | 11 | 1 | 0 | 0.0 | 0.0 |
| `iteration_cap_two_storey_smoke` | yes | 10 | 9/0 | 11 | 1 | 0 | 0.0 | **1e-14** |
| `iteration_cap_three_bed_apartment` | yes | 14 | 6/0 | 8 | 1 | 0 | 0.0 | 0.0 |
| `iteration_cap_flashover_simple_house` | yes | 12 | 5/0 | 11 | 5 | 0 | 0.0 | 0.0 |
| `damping_exhausted_uk_bungalow` | yes | 14 | 5/0 | 11 | 4 | 0 | 0.0 | 0.0 |

`uk_bungalow` converging in 14 iterations is post-H2.10 behaviour - the
adaptive branch-preserving Jacobian closed that mode - not an H3.2a change.

## Numerical bound

Routes and aggregates are summed in different orders **on purpose**: the
aggregate summation order is frozen and was not altered to force an exact zero.

- declared bound: `1e-12 kg` and `1e-12 kJ`;
- **maximum measured: mass `0.0` exact on all nine captures, energy `1e-14 kJ`**
  on `two_storey_smoke` alone.

This is a floating-point agreement limit, not a physical tolerance.

## Runtime matrix

Ten committed scenarios, 120 s, Godot 4.7.1, sequential, outside the sandbox,
via `scripts/run_scenario.py`. Baseline from a clean worktree at `344ec5fe`.

| scenario | rows base/candidate | result |
|---|---|---|
| `cfast_corridor_chain` | 79/79 | identical |
| `cfast_r0_window_360` | 79/79 | identical |
| `cfast_two_floor_stairwell` | 170/170 | identical |
| `two_storey_smoke` | 1574/1574 | identical |
| `ghanekar_bedroom_hallway` | 131/131 | identical |
| `piso_mediterraneo_smoke` | 1211/1211 | identical |
| `uk_bungalow_smoke` | 848/848 | identical |
| `compact_apartment_smoke` | 606/606 | identical |
| `three_bed_apartment_smoke` | 1090/1090 | identical |
| `flashover_simple_house` | 727/727 | identical |

OFF was verified on the first three; the remaining seven were run ON only,
because with the shadow flag off `_record_coupled_pressure_solver_preview`
returns before the solver is invoked, so OFF cannot be affected by a change
inside the solver.

## Zone coverage

| combination | source |
|---|---|
| `lower->lower` | real captures, dominant |
| `upper->lower` | real captures |
| **`upper->upper`** | synthetic fixture - both rooms hot-dominated, so both interfaces sit low and the tall band above them is upper on both sides |
| **`lower->upper`** | synthetic fixture - A cool with a deep lower layer, B hot with a shallow one, so the middle band is lower on A and upper on B |

The asymmetric synthetic pair reaches **all four combinations at once**, which
is the strongest single case in the fixture.

## Open risks

1. **`upper->upper` and `lower->upper` exist only in synthetic fixtures.** No
   runtime topology in the corpus reaches them. Real coverage, but not observed
   in a scenario.
2. **No CSV export.** The decomposition is not auditable from a run; H3.2 will
   need that.
3. **Exterior semantics deferred** to H3.5, as agreed.
4. The corpus remains the same ten topologies plus the synthetic C8 contract.

## Decision

**GO for H3.2a.** Strictly additive: zero deleted lines, aggregates unchanged,
classification is a read of decisions already made using the solver's own
mirrored convention, and a structural test forbids rebuilding an aggregate from
`zonal_routes`.

**H3.2 is unblocked** - the zone information the atomic route primitives
require now exists. **H3.2b and H3.3 remain blocked**: `project_room_state`
still reconstructs energy from clamped temperature, and that must become a
residual projection before any mass or energy is committed.

H3.2a grants no runtime authority and closes no VALID_GAP.
