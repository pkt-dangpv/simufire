# Phase 3 H3.2-S0d6 O2 Ownership and Acceptance Audit

Date: 2026-08-07
Verdict: **Outcome C — exact per-owner, per-zone attribution of accepted O2 is not
viable without a representational change**, with one narrow, now-measured
Outcome-B carve-out.

No physics was changed. One passive, default-OFF measurement flag was added and
proven byte-identical when off. HVAC stays deferred, the integrator does not
exist, H3.2-S stays open, H3.2b still blocks H3.3 and no runtime authority was
granted.

**Scope of the inventory — this is not a complete inventory.** What follows is
**16 sites found and instrumented in one static pass**. The adversarial
per-writer verification did not complete; a short second static sweep was run
instead and is reported in §6.6, and it found writes the first pass had missed.
Nothing in this document should be read as full coverage of O2 writes.

## 0. Why the previous record was insufficient

S0d3 recorded O2 as `bulk_only`, "no zone identity", with **1798 upper-bound clamp
applications**. Both statements are narrower than the code.

- The 1798 is `entry["clamp_high_bound_count"]`, incremented at
  `GasExchangeSystem.gd:964` from the single call site
  `GasExchangeSystem.gd:2342`. It therefore describes **exactly one** O2 clamp —
  the room-loop bulk write at `GasExchangeSystem.gd:2345`. Every other O2 clamp in
  the engine is observed by nothing: no attribution counter, no
  `_record_clamp_correction`, and `_record_zonal_guard` is never invoked for `o2`.
- O2 **does** have persistent zone state. `RoomModel.gd:47,49` declare `o2_upper`
  and `o2_lower`, and `:48` states the contract verbatim: *"Fraccion O2 en capa
  inferior (zona fría). Variable persistente; NO derivada de o2."* The problem is
  not that the zone is missing; it is that the three fractions are **independent**
  and no invariant ties them together.

## 1. Units — established, not assumed

| Field | Declaration | Unit |
|---|---|---|
| `room.o2` | `RoomModel.gd:45` `var o2: float = 0.209` | **fraction** |
| `room.o2_upper` | `RoomModel.gd:47` | **fraction** |
| `room.o2_lower` | `RoomModel.gd:49` | **fraction** |
| `room.upper_o2_mass_tracked` | `RoomModel.gd:53`, `-1.0` sentinel | kg, separate tracker |
| `o2_consumed_*`, `o2_exterior_net_kg_*`, `o2_net_transport_kg_*` | `RoomModel.gd:179-201` | kg, **telemetry** |
| `o2_zone_sync_kg_*` | `RoomModel.gd:206-207` | kg, telemetry, *"No es transporte físico"* |

`RoomModel.upper_o2_mass_kg()` and `lower_o2_mass_kg()` (`:375-381`) are **dead
code**: zero call sites in the repository.

Three distinct 0.209-valued ceilings exist and are not interchangeable:
`SimulationEngine.gd:64 const o2_nominal` (a GDScript `const`, so **not**
settable through engine overrides), `SimulationEngine.gd:217 @export
fire_o2_nominal` (a FireModel parameter, exported under the *same* key name
`"o2_nominal"` at `:3105`), and `BuildingModel.gd:26 @export outside_o2`
(scenario-loadable at `BuildingModel.gd:405-406`). Different O2 clamps use
different ones — see §3.

## 2. Writer order inside one tick

Driver: `SimulationEngine.step()` at `SimulationEngine.gd:2885`.

| # | Call | Site | Writes |
|---|---|---|---|
| 1 | `_step_oxygen` (pre-HRR) | `:2961`, gate `fire_o2_mode ∈ {upper,lower,interface}` | `o2`, `o2_upper`, `o2_lower` |
| 2 | `_step_fire` → `CombustionSystem.step_room_fire` | `:2969` | **no O2 state**; resets per-step O2 telemetry at `CombustionSystem.gd:1434-1439` |
| 3 | `_step_co_oxidation` | `:2974` | computes `consumed_o2_kg` at `:3671` but **never applies it** to any O2 field |
| 4 | `_step_oxygen` (post-HRR) | `:2978`, mutually exclusive with #1 | as #1 |
| 5 | `thermal_system.step` | `:2984` | `o2`, `o2_upper`, `o2_lower` (counterflow + canonical doorway) |
| 6 | `_step_gas_exchange` | `:3010` | `o2` **bulk only**, four sites |
| 7 | `_step_hvac` | `:3314` | `o2`, `o2_upper`, `o2_lower` |
| 8 | `_clamp_rooms` | `:2695`→`:4128` | `room.o2` only |

`_step_oxygen` runs **once**, at one of two positions depending on `fire_o2_mode`.
`CombustionSystem` is the reset point for the per-step telemetry accumulators but
writes no O2 state — its `:2190-2193` block is gated by
`fire_o2_stoich_consumption_enabled` (default false) and its own comment at
`:2182-2186` says it accounts "sin modificar o2_upper (evita doble-descuento)".

## 3. Clamp sites found in one pass — one of them previously measured

| Site | Expression | Bound | Owners at clamp time | Observed? |
|---|---|---|---|---|
| `OES:393` | `room.o2 = clampf(o2_mass_kg / air_mass_kg, 0, o2_nominal)` | `[0, o2_nominal]` | **accumulated**: combustion sink + ACH | no |
| `OES:574` | `room.o2_upper = clampf(..., 0, o2_nominal)` | `[0, o2_nominal]` | accumulated | no |
| `OES:580` | `room.o2_lower = clampf(..., 0, _o2_lower_final_ceil)` | `[0, outside_o2 or o2_nominal]` | accumulated | no |
| `OES:796` | exterior opening mix | `[0, o2_nominal]` | single (exterior) | no |
| `OES:816/825` | `indoor.o2_lower` exterior replenish | `[0, o2_nominal]`, `[o2, o2_nominal]` | single | no |
| `OES:989/990` | `room_a.o2`, `room_b.o2` immediate exchange | `[0, o2_nominal]` | single | no |
| `OES:1048/1053/1093` | counterflow zone writes | `[0, o2_nominal]` | single | no |
| `OES:1151` | `_apply_room_o2_mass_delta` | `[0, o2_nominal]` | parcel release | no |
| `GES:1628` | pressure-vent mix | `[0, o2_nominal]` | single | no |
| **`GES:2345`** | **room-loop bulk** | `[0, o2_nominal]` | **accumulated, ~8 transport paths** | **yes — the 1798** |
| `GES:2866` | parcel delivery target | `[0, o2_nominal]` | single | no |
| `GES:4198` | PPV inlet | `[0, o2_nominal]` | single | no |
| `HVAC:306/308/314` | zone supply | `[0, outside_o2]`, `[o2, outside_o2]` | single | no |
| `Thermal:3355/3356/3364` | counterflow | `[0, 0.209]` **literal**, not `o2_nominal` | single | no |
| `Thermal:3427/3517/3525` | canonical doorway | `[0, o2_nominal]` | single | no |
| `SimEngine:4134` | final tick clamp | `[0, o2_nominal]` | **accumulated, whole tick** | no |

`_clamp_rooms` bounds **only `room.o2`**. It leaves `o2_upper` and `o2_lower`
entirely unbounded — unlike CO, where `SimulationEngine.gd:4196` binds
`co_upper_kg` to `co_kg`. There is no O2 analogue of the zonal invariant.

## 4. The blocking findings

### 4.1 The kg conversion is not well defined — the code disagrees with itself

Every O2 write assigns a **fraction**. Turning that into kg needs a mass base, and
the engine uses different bases for different zones, deliberately:

| Path | Cap | Mass base used to convert | Site |
|---|---|---|---|
| bulk combustion sink | `minf(consumed, o2_mass_kg * 0.05)` | `air_mass_kg` (room) | `OES:375-376` |
| upper combustion sink | `minf(upper_consumed, upper_air_mass * o2_upper * 0.20)` | **`upper_air_mass` (zone)** | `OES:432,439` |
| lower combustion sink | `minf(consumed_lower, air_mass_kg * o2_lower * 0.05)` | **`air_mass_kg` (room)** | `OES:504,507` |
| plume lower sink | `minf(plume_consumed, lower_air_mass * o2_lower * 0.20)` | **`air_mass_kg` (room)** | `OES:527,533` |

The comment at `OES:528-530` states the room-mass divisor for the plume path is
intentional modelling, not an oversight. So a change in `o2_lower` cannot be
converted to kg by any single rule: the writer that produced it used room mass,
while the lower zone's physical inventory is `lower_air_mass × o2_lower`. The plume
cap and its application even use **different** bases from each other
(`lower_air_mass` to cap, `air_mass_kg` to apply).

**This already corrupts the one existing kg-denominated O2 ownership.**
`_record_phase3_shadow_o2_sink` (`OES:672`, gated `phase3_canonical_zone_shadow_enabled`)
converts with `upper_air_mass` for the upper sink (`OES:441-443`) but with
`air_mass_kg` for both lower sinks (`OES:509-511`, `OES:535-537`). Its `o2_kg`
values are therefore not on a common basis.

### 4.2 Physical sinks are silently truncated by unowned floors

`OES:507` writes `lower_o2_after = maxf(room.o2, room.o2_lower - consumed_lower / air_mass_kg)`.
When the floor binds, the fire consumes **less** O2 than the expression above it
computed, and nothing records the difference. The same floor pattern appears at
`OES:497` and `OES:559`. These are unowned corrections applied to a *physical sink*,
which is why the directive's prohibition on deriving accepted O2 from HRR is
correct: `OES:375`, `:432`, `:504` and `:527` each cap consumption before it is
applied, so stoichiometry never equals what the engine accepted.

### 4.3 The same inflow is credited to two inventories

At an exterior opening, `air_in_kg` mixes into the bulk at `OES:796-800` **and**
into the lower zone at `OES:816-818`, against two different mass bases
(`room_air_mass_kg` and `lower_mass_ext`), with no relation enforced between the
results. The bulk telemetry at `OES:802-803` is then written as
`(indoor.o2 - _o2_before_ext) * room_air_mass_kg` — a post-minus-pre reconstruction,
precisely the construction this phase is forbidden to use for attribution.

### 4.4 `room.o2` is overwritten as a blend that discards the OES value

`ThermalSystem` writes `hot_room.o2 = _hot_blend` (`:3377`) and
`cold_room.o2 = _cold_blend` (`:3388`), plus `:3562`/`:3577` for the canonical
path, and books the difference into `o2_zone_sync_kg_*` — declared in
`RoomModel.gd:204-205` as *"No es transporte físico"*. So a `numerical_correction`
term for O2 already exists in production telemetry, unclassified as such, and
`room.o2` as written by OES does not survive the tick unmodified.

### 4.5 HVAC writes O2 with no mass balance and no telemetry at all

`HVACSystem.gd:302` is `room.o2 = lerpf(room.o2, clampf(supply_o2, ...), air_fraction)`
— a fraction lerp, not a mass mix. HVAC emits **no** O2 telemetry: no
`o2_exterior_net_kg_*`, no `o2_consumed_*`. Its zone writes at `:306/:308/:314`
clamp against `building.outside_o2` while `_clamp_rooms` clamps against the const
`o2_nominal`, so the two ceilings are structurally allowed to differ.
HVAC is deferred by directive; it is inventoried here, not fixed.

## 5. Answer to the decisive question

> Can accepted O2 deltas be attributed per owner and zone without post-pre
> reconstruction, legacy transport, or arbitrary splitting?

**No — Outcome C for O2 as a whole.** Four independent blockers, each sufficient:

1. `unit_not_mass_ambiguous_base` — the state is a fraction and the engine uses
   inconsistent mass bases per zone (§4.1).
2. `no_zonal_invariant` — `o2`, `o2_upper`, `o2_lower` are independent persistent
   fractions; nothing enforces a relation, and `_clamp_rooms` bounds only the bulk.
3. `aggregate_clamp_multi_owner` — `OES:393`, `GES:2345` and `SimEngine:4134` each
   clamp a value already summed over several owners.
4. `sink_truncated_unowned` — combustion caps and `room.o2` floors reduce a
   physical sink with no record of the rejected amount (§4.2).

### The Outcome-B carve-out

Exactly one path has requested, accepted, zone and a **self-consistent** zone mass
base all present in code at the same site: the **upper-zone combustion sink**,
`OES:428-447`. It caps against `upper_air_mass * o2_upper`, applies against
`upper_air_mass`, and already computes an explicit accepted kg at `:441-443`. That
path can carry `completeness = true`. Every other O2 path must carry
`completeness = false` with one of the four reason codes above.

## 6. Phase 2 -- measurement

A passive ledger, `sim/core/Phase3O2AcceptanceLedger.gd`, is shared by every
subsystem that mutates O2 except HVAC, which this phase defers. One flag,
`phase3_o2_attribution_diagnostics_enabled`, default OFF, governs all four
instances. Sixteen owner slugs are observed at the exact mutation sites.

It records the native unit -- a fraction -- and publishes a kilogram **only** when
the site itself capped and applied against the same mass base. Everywhere else it
reports `NAN` with an explicit reason code. Two fail-closed rules apply: an
undeclared reason code is never complete, and a second, different reason for the
same `owner|zone` downgrades the row to `reason_code_conflict`, clears
`kg_available` and discards the kilograms accumulated before the conflict.

### 6.1 Corpus and validation

Ten cases, twenty runs, zero failures. Every run validated on schema version,
room count, CSV row count and an empty-of-errors Godot log rather than exit code
alone: `o2_stoich_diag_sealed`, `fuel_balance_diag_sealed`,
`cfast_slow_growth_sealed`, `cfast_corridor_chain`, `cfast_r0_window_360`,
`cfast_two_floor_stairwell`, `v1_backdraft_accumulation`, `postfire_decay`,
`ppv_attack_pressurized`, and `cfast_hvac_residential` as the declared incomplete
control.

### 6.2 Acceptance by owner and zone

Summed over the ten ON runs. `maxcorr` is in fraction units; the material
threshold is `1.0e-9`.

| owner\|zone | applications | strict | material | max corr | kg | reason |
|---|---:|---:|---:|---:|---|---|
| `thermal_zone_sync_blend\|bulk` | 24 822 | **24 822** | **24 820** | **4.44e−04** | n/a | `no_zonal_invariant` |
| `oes_bulk_combustion_and_ach\|bulk` | 624 283 | 84 692 | 0 | 2.78e−17 | n/a | `aggregate_clamp_multi_owner` |
| `ges_room_loop_transport\|bulk` | 624 283 | 84 681 | 0 | 2.78e−17 | n/a | `aggregate_clamp_multi_owner` |
| `oes_combustion_upper_sink\|upper` | 76 928 | 0 | 0 | 0 | **−208.47 kg** | `complete` |
| `engine_final_tick_clamp\|bulk` | 624 283 | 0 | 0 | 0 | n/a | `aggregate_clamp_multi_owner` |
| `oes_final_zone_clamp\|upper` | 624 283 | 0 | 0 | 0 | n/a | `no_zonal_invariant` |
| `oes_final_zone_clamp\|lower` | 624 283 | 0 | 0 | 0 | n/a | `no_zonal_invariant` |
| `ges_pressure_vent\|bulk` | 72 140 | 0 | 0 | 0 | n/a | `no_zonal_invariant` |
| `oes_exterior_opening\|bulk` | 12 583 | 0 | 0 | 0 | n/a | `no_zonal_invariant` |
| `oes_exterior_opening_lower_replenish\|lower` | 12 583 | 0 | 0 | 0 | n/a | `unit_not_mass_ambiguous_base` |
| `thermal_canonical_doorway\|upper` | 12 411 | 0 | 0 | 0 | n/a | `unit_not_mass_ambiguous_base` |
| `thermal_canonical_doorway\|lower` | 12 411 | 0 | 0 | 0 | n/a | `unit_not_mass_ambiguous_base` |
| `ges_ppv_inlet\|bulk` | 5 820 | 0 | 0 | 0 | n/a | `unit_not_mass_ambiguous_base` |
| `oes_combustion_plume_lower_sink\|lower` | 4 321 | 0 | 0 | 0 | n/a | `unit_not_mass_ambiguous_base` |

**Only 76 928 of 3 355 434 applications -- 2.29 % -- can carry an attributable
kilogram**, and all of them are the single complete path.

### 6.3 The material correction is not a clamp

The headline result overturns the phase's own starting assumption. Every clamp in
the corpus corrects only floating-point noise: the largest clamp correction
anywhere is `2.78e−17` of fraction, eight orders of magnitude below the
FED-anchored material threshold. **In particular, the clamp S0d3 counted 1798
times (`ges_room_loop_transport`) binds 84 681 times here and is material zero
times.**

The one materially significant unowned rewrite of O2 is not a clamp at all. It is
`thermal_zone_sync_blend`: `ThermalSystem` **discards** `room.o2` and rewrites it
as a volumetric blend of the two zones, at `ThermalSystem.gd:3381/3392` and again
at `:3634/:3649`. It binds on **100 % of its applications** (24 822 / 24 822),
is material in 24 820 of them, and its largest correction is `4.44e−04` of
fraction -- **2.4 times a 1 % move in `FED_hypoxia`**, so it is well inside the
range that changes a tenability verdict.

That rewrite is already booked into `o2_zone_sync_kg_*`, which `RoomModel.gd:204`
declares verbatim as *"No es transporte físico"*. So the engine already knows this
term is not physics, records it, and has no owner for it.

It appears in exactly one case of the ten, `cfast_corridor_chain` (53 626 strict,
24 820 material), which is the case where the doorway counterflow and canonical
doorway paths are active. The other nine cases show zero material corrections.

### 6.4 OFF/ON and conservation

- **CSV byte-identical on all ten cases**: identical row counts and identical
  SHA-256, from 319 rows (`cfast_r0_window_360`) to 11 407 (`postfire_decay`).
- The OFF summaries carry **no** `phase3_o2_attribution` key.
- Comparing the two technical summaries key by key, the **only** difference in
  any case is the added block: zero other keys differ. That covers conservation,
  `o2_consumed_fire_kg_total` (O2E1), FED, HRR and the carbon balance.
- Physics coherence and ILV layer coherence are **identical OFF and ON on all ten
  cases**, count for count.
- Sample-level closure over 2 701 samples: `requested + correction = accepted`
  with a worst residual of `9.44e−16` of fraction, and **zero** samples carry a
  kilogram while `completeness = false`.

Reported without hiding them: the physics-coherence and ILV FAIL counts are
non-zero on several of these cases (`ppv_attack_pressurized` 485 FAIL,
`postfire_decay` 253, `cfast_hvac_residential` 118, `cfast_two_floor_stairwell`
24, `v1_backdraft_accumulation` 18, the two sealed diagnostics 1 each). They are
**identical in both arms**, so they are pre-existing properties of these
diagnostic scenarios and not caused by this phase. They are not part of the
official reference corpus and no expected value, tolerance, CTRL or VALID_GAP was
touched. The gap inventory is unchanged at 353 required + 6 VALID_GAP + 71
non-gating.

### 6.5 Consequences for the verdict

The measurement **confirms Outcome C but relocates the reason**. Before it, the
natural reading was that the clamps were the obstacle. They are not: they are
slack to within floating-point noise across the whole corpus. The obstacles are
the two structural ones, now quantified:

1. `no_zonal_invariant` -- and specifically the zone-sync blend, which is a
   material, unowned rewrite of `room.o2` on every application.
2. `unit_not_mass_ambiguous_base` -- 97.71 % of applications cannot be converted
   to kilograms at all.

The Outcome-B carve-out stands and is now measured: the upper-zone combustion
sink accepted **−208.47 kg** of O2 across the corpus with `completeness = true`
and its clamp never binding.

### 6.6 Short adversarial sweep — what the first pass missed

The per-writer adversarial verification did not complete. A short second static
sweep was run in its place, matching every assignment to `o2`, `o2_upper` or
`o2_lower` across the whole tree. It found **45 O2 state writes in production
code**, of which **23 are instrumented and 22 are not**:

| Component | Writes | Instrumented | Not instrumented |
|---|---:|---:|---:|
| `OxygenExchangeSystem` | 25 | 8 | **17** |
| `ThermalSystem` | 10 | 10 | 0 |
| `GasExchangeSystem` | 4 | 4 | 0 |
| `SimulationEngine` | 1 | 1 | 0 |
| `HVACSystem` | 5 | 0 | 5 (deferred by directive) |

Two concrete misses in the first pass, both now recorded:

1. **`OxygenExchangeSystem.gd:666`** —
   `room.o2 = clampf(room.o2_upper * upper_frac + room.o2_lower * lower_frac, 0.0, o2_nominal)`.
   This is a **second** recomposition of the bulk from the two zones, structurally
   the same operation as `thermal_zone_sync_blend`. So the engine rebuilds
   `room.o2` from the zones in **two different subsystems**, under different
   conditions (`effective_plume_lower or _phase2b_upper_active` here, the doorway
   paths there), with no shared rule about which one is authoritative. This
   strengthens the §6.3 finding rather than qualifying it, and it is the direct
   motivation for H3.2-S0d6a.
2. **`HVACSystem.gd:213`** — a fifth HVAC O2 write that the first declaration of
   `uninstrumented_writers` omitted. Now declared.

The 22 uninstrumented writes are enumerated verbatim in the technical-summary
export under `uninstrumented_writers`, alongside a `writer_coverage` block that
states the counts and the method. The measured tables in §6.2 therefore describe
the clamp sites, **not** every O2 write.

## 7. What this phase deliberately did not do

No instrumentation was added, no flag created, no physics touched, no
combustion/extinction/tolerance/expected/report modified, no HVAC work, no
integrator, and H3.2b/H3.3 were not started. The Godot measurement campaign named
in the directive belongs to phase 2 and has not been run; nothing in this document
is presented as a measured result — every claim above is a source-code reading with
file and line.
