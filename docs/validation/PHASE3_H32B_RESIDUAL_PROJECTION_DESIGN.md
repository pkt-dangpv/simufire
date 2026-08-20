# Phase 3 H3.2b0 Residual Projection — Design

Date: 2026-08-19
Scope: **design only, documentation only.** No file under `sim/`, `tests/`,
`scripts/`, `tools/`, no runner, case file or report was modified. No flag, no
physics, no campaign, no implementation.

Decision: **GO for H3.2b1 (passive causal instrumentation). NO-GO for any
physics change until that instrumentation lands and reports.**

> **CORRECTION 2026-08-19 (review of H3.2b0).** Five points in the first issue of
> this design were wrong or under-specified and are corrected in place below,
> each marked `[CORRECTED]`: energy without mass must fail closed rather than be
> routed to a sink; the suppression lower write stays dead and H3.2b must not
> revive it; the thermal cap is a *cause*, not a physical destination, and can
> block promotion even when the ledger closes; the two residuals must **not** be
> required to differ; and the multiplicity metrics were incomplete.

H3.2-S, H3.2b and H3.3 remain open; S0d6b1 stays blocked; HVAC stays deferred; no
runtime authority is granted.

---

## 1. The problem, restated from proven facts

From the S0d6b0.2/0.2a static trace of `ZoneFireSolver.project_room_state()`:

- `upper_gas_kg` survives a projection **unless** it exceeds `V_room · ρ_upper`,
  in which case it is capped (`:264`).
- `thermal_layer_m` is derived **from** `upper_gas_kg` (`:266-268`), so the
  interface follows the upper mass.
- `lower_gas_kg` is **overwritten unconditionally** with
  `remaining_volume · ρ_lower` (`:281`). It never survives as an accumulated
  quantity.
- `upper_energy_kj` and `lower_energy_kj` are re-derived from the **clamped**
  temperatures (`:246-251`), so a genuine energy correction cannot survive
  either.
- Both mass rewrites accumulate into `two_zone_boundary_mass_kg` (`:265`, `:282`)
  and the energy difference into `two_zone_boundary_energy_kj` (`:290`).

**The engine currently closes the volume by creating or destroying mass and
energy.** That is the defect H3.2b must remove, and it is why H3.3 cannot take
authority: a solver that commits a mass or energy correction has it discarded at
the next projection.

---

## 2. Phase 1 — the exact map

### 2.1 Call sites of `project_room_state()`

| # | Site | `cause` | Position in tick | Preceding writer | Repeatable in one timestep |
|---|---|---|---|---|---|
| 1 | `ThermalSystem.gd:1239` | `thermal_energy_projection` | inside `thermal_system.step`, after the zone energy update | thermal energy transfer, plume, doorway | once per room per `step` |
| 2 | `ThermalSystem.gd:4954` | `projection_cause` argument, default `thermal_layer_sync` (`:4812`) | `_sync_room_two_zone_layer`, called from `reconcile_two_zone_building` | reconcile | once per call, and reconcile is itself called from the tick |
| 3 | `SimulationEngine.gd:4283` | `final_clamp_quiescent` | `_clamp_rooms`, quiescent branch, after `collapse_upper_into_lower` | everything in the tick | mutually exclusive with #4 |
| 4 | `SimulationEngine.gd:4302` | `final_clamp_active` | `_clamp_rooms`, active branch | everything in the tick | mutually exclusive with #3 |
| 5 | `SimulationEngine.gd:4363` | `stairwell_temperature_cap` | `_clamp_rooms`, stairwell cap, **after** #3/#4 | #3 or #4 | **additional**, same pass |

**A room can therefore be projected at least three times in one timestep**: once
in `thermal_system.step`, once in reconcile, and once or twice in `_clamp_rooms`.
Sites #3/#4 and #5 both live inside `_clamp_rooms`, so `_clamp_rooms` alone can
project twice.

**Not measured:** the actual per-timestep call count. `ZoneFireSolver` maintains
`_projection_call_index` and a per-call trace, but neither is exported. This is
the single most important missing number and H3.2b1 must export it.

> **[MEASURED 2026-08-19 by H3.2b1 — this table was incomplete.]** The five rows
> above are the five *direct* `project_room_state(` call sites. They are not the
> five causes. `ThermalSystem._sync_room_two_zone_layer` takes `projection_cause`
> as a parameter and is itself invoked from many places, so the runtime shows
> **seventeen distinct causes**, not five. On `cfast_corridor_chain`, 7 201
> timesteps and 6 rooms produced **429 471 projection calls**, a maximum of
> **17 calls in a single room-step**, and **43 206 room-steps carrying more than
> one call**. The design's estimate of "at least three per timestep" was a lower
> bound that understated reality by roughly a factor of five. The largest
> contributors by call count are `reconcile_layer_sync` (86 412),
> `gas_exchange_sync` (64 057), and `thermal_energy_projection`,
> `thermal_post_combustion_sync` and `thermal_post_losses_sync` (43 206 each,
> i.e. once per room per timestep). Section 6's idempotence invariant becomes
> correspondingly more important, and any deduplication scheme must handle
> seventeen causes rather than five.
>
> > **[UNITS CORRECTED 2026-08-20.]** The measurements above are unchanged; the
> > wording was wrong. **43 206 is a count of room-steps, not of physical
> > timesteps** — it is 7 201 timesteps × 6 rooms, i.e. every room in every
> > timestep, which the earlier phrasing "43 206 steps" invited being read as a
> > timestep count. Likewise the maximum of 17 is per **room-step**, not per
> > timestep. A room-step is one room within one physical timestep. The ledger
> > now names both units explicitly and, because `accumulate_step` is invoked
> > exactly once per `SimulationEngine.step()`, the physical-timestep boundary is
> > genuinely known, so per-timestep multiplicity is measured too rather than
> > approximated from room-steps.

### 2.2 Writers of zone state

| Quantity | Physical owners | Numerical corrections |
|---|---|---|
| `upper_gas_kg` | plume entrainment (`ZoneFireSolver:163-165`), doorway and canonical exchange (`ThermalSystem`), parcels and openings (`GasExchangeSystem`), HVAC | non-negativity clamp (`:115`), **upper cap** (`:264`), collapse (`:356`) |
| `lower_gas_kg` | the same transports, plus ACH and exterior | non-negativity clamp (`:117`), **seeding** (`:121`), **unconditional reconstruction** (`:281`), collapse (`:354`) |
| `upper_energy_kj` | combustion, radiation, convection, wall losses, transports | thermal-inversion mix (`:227-232`), **re-derivation from clamped `temp_upper_c`** (`:246-248`), proportional rescale under the cap (`:262`) |
| `lower_energy_kj` | the same, plus suppression | **re-derivation from `temp_lower_c`** (`:249-251`), proportional rescale (`:279`), zeroing when mass is negligible (`:285`) |
| `temp_upper_c` / `temp_lower_c` | none — always derived | `minf(raw, max_upper_temp_c)` (`:239`), collapse to lower when the upper zone is negligible (`:241-244`) |
| `thermal_layer_m` | none — always derived | derived from `upper_gas_kg` (`:266-268`) |
| pressure | `Phase3CoupledPressureSolver` (shadow only), thermodynamic pressure paths | not part of projection today |

**The asymmetry that matters:** temperature and interface are *already* derived
quantities and that is correct. Mass and energy are supposed to be conserved
quantities, and today they are not — they are back-filled to make the derived
quantities close.

---

## 3. Phase 2 — the canonical equation

### 3.1 Authoritative versus derived

| Authoritative, stored | Derived, never stored as truth |
|---|---|
| `M_upper`, `M_lower` (kg) | `T_upper = E_upper / (M_upper · cp)` + ambient |
| `E_upper`, `E_lower` (kJ, sensible) | `T_lower` likewise |
| `V_room` (fixed geometry) | `p`, the common room pressure |
| | `V_upper`, `V_lower` |
| | `thermal_layer_m = height − V_upper / floor_area` |

### 3.2 The closure

For a valid state, with both zones at the same pressure and filling the room:

```
p        = (R / V_room) · (M_upper · T_upper + M_lower · T_lower)
V_upper  = M_upper · R · T_upper / p
V_lower  = M_lower · R · T_lower / p
V_upper + V_lower = V_room                    (satisfied identically)
```

The third line is **not an extra constraint to be enforced** — substituting the
first into the second and third makes it an algebraic identity. That is the whole
point: **once `p` is derived from the conserved state, the volumes close by
construction and nothing needs to be back-filled.**

```
V_upper + V_lower = (R/p)·(M_u·T_u + M_l·T_l) = (R/p)·(p·V_room/R) = V_room
```

**The projection must never modify `M` or `E` to close the volume.** It computes
`p`, then the volumes, then the interface. Mass and energy are inputs, never
outputs.

### 3.3 Degenerate and transition cases, defined explicitly

| Case | Rule |
|---|---|
| `M_upper = 0` | `V_upper = 0`, interface at the ceiling, `T_upper` is **undefined and reported as such** — never ambient, never `T_lower` masquerading as a measurement. `p` reduces to the one-zone form. |
| `M_lower = 0` | symmetric; a room cannot normally reach it, and if it does that is a finding, not a state to smooth over |
| `E > 0` with `M = 0` | **[CORRECTED]** **invalid state, fail closed.** It is detected, counted and reported with a reason code; the state is **not mutated**, the energy is **not** routed to a sink, and no repair is attempted. The legacy path is used as an explicit, counted fallback, and any non-zero count **blocks promotion**. Converting it to a sink would be inventing a physical destination for energy whose origin is unknown |
| both zero | the room has no gas; every derived quantity is `unknown` |
| one-zone → two-zone (upper born by plume) | the plume transfer at `:163-165` already moves `(ΔM, ΔE)` as a pair from lower to upper. That pairing is the contract: **a zone is born by receiving mass and its accompanying energy, never by being seeded from geometry** |
| two-zone → one-zone (upper dies) | `collapse_upper_into_lower` (`:354-356`) already adds upper into lower. It must also add `E_upper` into `E_lower`, and the pair must be conserved and counted |
| thermal cap binds | see section 4 |
| `p` non-finite | fail closed: keep the previous valid state, emit a `numerical_correction` with a reason code, and never write a NaN into `M` or `E` |
| interface out of range | clamp the *derived* interface only; **never** adjust `M` or `E` to bring it back |

---

## 4. Phase 3 — the thermal cap as an explicit sink

Today the cap is invisible: `temp_upper_c = minf(raw, max_upper_temp_c)` and then
`upper_energy_kj` is re-derived from the clamped temperature, which silently
destroys the excess.

Proposed contract, **not implemented**:

```
E_max_upper   = M_upper · cp · (T_max − T_ambient)
E_requested   = E_upper                       (before the cap)
E_accepted    = min(E_requested, E_max_upper)
E_rejected    = E_requested − E_accepted      (>= 0, a sink)
```

- **[CORRECTED]** `E_rejected` is emitted as a `numerical_correction` whose
  **`cause`** is `thermal_cap_upper`. It is a cause, **not a physical
  destination**: no owner receives that energy, and the record must never be read
  as a transfer. `requested`, `accepted`, `rejected` and the **sign** of each are
  recorded separately.
- **[CORRECTED] The cap can block promotion even when the ledger closes.** If the
  cap removes *material* energy without a corresponding physical transfer to
  walls, to ambient or to water, then the books balancing algebraically is not
  sufficient: energy is leaving the model with no destination. That condition is
  a **promotion blocker** for H3.2b6/b7 in its own right, independent of whether
  every term sums to zero.
- A cumulative `thermal_cap_rejected_kj_total` per room, plus a per-cause
  breakdown, so the sink is auditable across a run.
- Conservation is then stated **with the sink as its own term**:
  `E_post = E_pre + owners − rejected`.
- **[CORRECTED]** The **suppression lower-energy write (S0d1)** was described
  here as something residual projection would revive. That was wrong. The dead
  write sets `temp_lower_c` only, and temperature is a **derived** quantity under
  both the current and the proposed design — it is re-derived from
  `lower_energy_kj / (M_lower · cp)` either way. **Writing `temp_lower_c` alone
  therefore remains a dead write after H3.2b, and H3.2b does not revive it.**
  Only the S0d2 experiment, which writes `lower_energy_kj` directly, can make
  that cooling physical. H3.2b's role is limited to **exposing the
  incompatibility**: it reports that a suppression cooling request existed and
  that no conserved-state owner received it. Making it physical is S0d2's gate,
  not this one.

**The cap is not removed.** It becomes visible.

---

## 5. Phase 4 — instrumentation that must land first

H3.2b1 is passive, default OFF, and must survive the 10 s CSV sampling. Every
quantity below is a **cumulative `*_total`**, because differencing sub-step deltas
against interval rows is the error this programme has already made twice.

| Metric | Why |
|---|---|
| **[CORRECTED]** `projection_call_count_total`; `projection_call_count_total` per `cause`; `projection_calls_this_step`; `projection_calls_per_step_max`; `steps_with_multiple_projection_calls_total` | the per-timestep multiplicity is question 4. A single grand total cannot answer it: the per-step maximum and the count of steps with more than one call are what distinguish "three call sites exist" from "three actually fire in the same timestep". All cumulative except `projection_calls_this_step`, which is a per-step scalar feeding the two accumulators |
| `projection_upper_mass_correction_signed_kg_total` | net intervention |
| `projection_upper_mass_correction_gross_kg_total` | gross, since the signed net cancels and is only a lower bound |
| the same two for `lower` | the lower zone is the proven blocker |
| the same four for energy | the cap and the re-derivation both act here |
| `pre` / `ensured` / `pre_geometry` / `post` snapshots, already built at `:207,210,253` | lets pre-projection closure be tested instead of inferred |
| `residual_physical_kg_total` = Δstate − physical owners | the quantity S0d6b0.2 could not compute |
| `residual_closure_inclusive_kg_total` | its difference from the above **is** the projection contribution |
| `zone_birth_count_total`, `zone_death_count_total` | transitions are where conservation is easiest to lose |
| `thermal_cap_requested / accepted / rejected_kj_total`, each signed | section 4; the cap is a cause, not a destination |
| **[ADDED]** `physical_owner_completeness`, `completeness_mask`, `completeness_reason_codes` | `residual_physical` is meaningless without them |
| **[ADDED]** `energy_without_mass_count_total`, `nonfinite_pressure_count_total`, `nonfinite_interface_count_total` | fail-closed states must be counted, never repaired |

**[CORRECTED] Acceptance for H3.2b1:** OFF is byte-identical; both residuals are
exported; and the projection call count is exported. The earlier criterion — "if
the two residuals are equal, the instrumentation is wrong" — is **withdrawn**.
Equality is a legitimate outcome whenever the numerical corrections happen to sum
to zero over the accumulation window, and demanding a difference would be
demanding a specific result.

The two residuals are **computed independently**, not one from the other, and
their algebraic relation is then **asserted** with an explicit sign convention:

```
sign convention: every term is a signed contribution to the state delta

residual_physical  = ΔState − Σ physical_owners
residual_closure   = ΔState − Σ physical_owners − Σ numerical_corrections

therefore, identically:
residual_physical − residual_closure = Σ numerical_corrections
```

That identity is a **contract to verify**, not an expectation about magnitude. It
holding proves the two accumulators are consistent; it says nothing about whether
either is small.

**`residual_physical` is only valid when `physical_owner_completeness = true`.**
If any owner is missing, the physical residual is not a conservation measurement
— it is the missing owner. The instrumentation must therefore export:

- `physical_owner_completeness` (bool), and
- `completeness_mask` / `completeness_reason_codes`, naming every owner that is
  absent or only partially attributed.

Known entries for that mask today: **HVAC** (writes mass and energy, unowned and
deferred), the `other` catch-all stage, the suppression lower request of
section 4, and any exterior removal path not attributed per zone. A consumer of
`residual_physical` must check the flag first and refuse to interpret the number
when it is false.

> **[NAMES CORRECTED 2026-08-20 by the H3.2b1 delivery — §11.2.]** The
> requirement above is unchanged; the exported names are different and sharper.
> `physical_owner_completeness` / `completeness_mask` were a single notion doing
> two incompatible jobs, so they ship split in two: **static** coverage gaps
> (`static_instrumentation_gap_reason_codes`, known from reading the code, never
> implying the path ran) and **observed active** gaps
> (`observed_active_gap_reason_codes` / `observed_active_gap_counts`, incremented
> only when the writer materially moved mass or energy). Validity
> (`residual_physical_valid`) requires `data_available`, no active gap **and**
> complete structural coverage. The accumulators are
> `candidate_physical_residual_*` and `closure_inclusive_residual_*`, and the
> physical one carries the label `candidate_incomplete_physical_residual` while
> it is invalid, so it can never be quoted as a physical residual by accident.

---

## 6. Phase 5 — staged architecture

| Phase | Files | Flag | Authority | Fixtures / cases | STOP gate | Rollback | Unblocks | Still blocked |
|---|---|---|---|---|---|---|---|---|
| **H3.2b0** design, this doc | docs only | none | none | none | this document | delete | H3.2b1 | all |
| **H3.2b1** passive causal instrumentation | `ZoneFireSolver`, `SimulationEngine`, `SimulationLogWriter`, `SimulationStateBuilder` | `phase3_projection_causal_diagnostics_enabled`, OFF | none | unit fixture; the ten S0d6b0.2 cases | OFF byte-identical; both residuals independently exported; algebraic relation exact; equality permitted; completeness gates validity; call count non-zero | flag off | H3.2b2 | all physics |
| **H3.2b2** pure residual-projection primitive | new `sim/core/Phase3ResidualProjection.gd`, **no call sites** | none | none | unit fixture for every case in §3.3 | primitive proven pure; zero call sites; zero physics diff | delete file | H3.2b3 | all |
| **H3.2b3** shadow compare | primitive + read-only shadow in `ZoneFireSolver` | same OFF flag | none, shadow | ten cases | per-room divergence legacy vs residual, quantified and explained | flag off | H3.2b4 | all |
| **H3.2b4** zone transition contract | primitive only | same flag | shadow | birth/death fixtures | mass and energy conserved across every transition | flag off | H3.2b5 | authority |
| **H3.2b5** thermal cap as explicit sink | `ZoneFireSolver` + ledger | `phase3_thermal_cap_sink_enabled`, OFF | shadow | cap fixtures | rejected energy accounted; **S0d1 dead write re-examined, not silently revived** | flag off | H3.2b6 | authority |
| **H3.2b6** experimental authority | call sites switched behind the flag | `phase3_residual_projection_enabled`, OFF | **experimental** | ten cases + baselines | baseline movement explained physically, never tuned; legacy fallback counted | flag off | H3.2b7 | promotion |
| **H3.2b7** promotion | remove legacy path | flag removed | **authoritative** | full suites, guardrails, baselines re-derived | authority granted explicitly | revert commit | H3.3, S0d6b1 | H3.2-S closure |

Every phase default OFF, byte-identical when off, independently revertible, and
gated before the next starts.

> **[H3.2b1 ROW CORRECTED 2026-08-20.]** Two entries in the H3.2b1 row are
> superseded by what actually shipped. Its STOP gate does **not** require the two
> residuals to be **different** — equality is a legitimate outcome, and on
> `cfast_corridor_chain` the closure-inclusive residual is exactly zero while the
> candidate physical one is +23.978 kg; what is required is the relation
> `candidate_physical_residual − closure_inclusive_residual = numerical_correction`,
> which holds with **exactly** zero error. And the delivery touched neither
> `SimulationLogWriter` nor `SimulationStateBuilder`: no CSV column was added, the
> ledger exports through an opt-in summary block only.

---

## 7. Mandatory questions

**1. Can `Phase3CoupledPressureSolver` be reused for the derived pressure?**
**No, and it should not be.** It solves a *network*: a connected set of rooms and
openings for the pressure field satisfying the end-of-step mass balance
(`:191-198`). H3.2b needs a **single-room, closed-form** pressure from
`(M_u, T_u, M_l, T_l, V_room)` — one line of algebra, no iteration, no
convergence risk, no opening data. Coupling the two would make every projection
depend on a solver that currently runs last and passively. H3.2b needs its own
primitive; the two can be reconciled later, at H3.3, when the network solver
takes authority.

**2. Where should residual projection live?** In a new pure primitive,
`Phase3ResidualProjection.gd`, taking `(M_u, E_u, M_l, E_l, V_room, ambient,
T_max)` and returning derived values plus an explicit correction record. Pure,
no `RoomModel` writes. `ZoneFireSolver` calls it and applies the result; keeping
it inside `ZoneFireSolver` would inherit the current entanglement.

**3. Authoritative versus derived?** Section 3.1. `M` and `E` authoritative;
`T`, `p`, `V`, interface derived.

**4. How to stop `_clamp_rooms` projecting several times?** Two changes, both
after instrumentation confirms the count: make projection **idempotent** — with
`M` and `E` fixed inputs, a second call must produce a bit-identical result, and
a fixture must assert it — and give `_clamp_rooms` a single projection point at
the end of the room loop, with the stairwell cap (#5) recording a correction
rather than triggering its own projection. Idempotence is the real fix;
deduplication is an optimisation once idempotence holds.

**5. How is OFF kept bit-identical?** The legacy path stays intact and is chosen
by the flag; the primitive is not consulted when off; and every phase carries a
CSV byte-identity check on the ten cases, as S0d6 did.

**6. Which consumers tolerate an absent zone?** FED, CO, CO2 and HCN already do,
via `ThermalSystem.gd:4553` (`upper_gas_kg > 0.1`). Consumers that do **not**
declare a policy must be enumerated in H3.2b2 and given one before H3.2b6. `p`
and the interface are always defined, so most geometry consumers are unaffected.

**7. How is an upper zone born conserving mass and energy?** By the existing
plume transfer, which moves `(ΔM, ΔE)` as a pair (`:163-165`). The contract is
that a zone is only ever born by **receiving a paired mass and energy transfer**
from another zone or an owner — never by geometric seeding as `:121` does today
for `lower_gas_kg`.

**8. How is the thermal cap recorded?** Section 4: requested, accepted, rejected,
owner `thermal_cap_upper`, cumulative totals, and conservation stated with the
sink as an explicit term.

**9. Which owners are missing to close the physical residual?** Unknown today —
that is precisely what H3.2b1 measures. Known suspects from prior phases: HVAC
mass and energy (unowned, deferred), the suppression lower-energy write (dead
under two-zone), the `other` catch-all stage, and exterior removal paths not
instrumented per zone.

**10. Can H3.2b precede H3.2-S / O2?** **Yes, and it must.** S0d6b0.2a proved
S0d6b1 is blocked on exactly this. H3.2b has no dependency on the O2 work; the O2
inventory depends on H3.2b. The order is H3.2b then S0d6b1.

**11. Relation to the 6 VALID_GAP?** They are accepted gaps in the required
checks, not conservation defects, and this design does not touch them. If
residual projection later moves a metric that a VALID_GAP describes, that is a
physics result to be reported at that phase's gate — **it must never be used to
justify editing a VALID_GAP**.

**12. What forces rollback?** Any of: OFF ceases to be byte-identical; the two
residuals come out equal (instrumentation not measuring what it claims); a zone
transition loses mass or energy; a `numerical_correction` is counted twice; the
primitive is not idempotent; energy exists with no mass; a baseline moves and the
movement cannot be explained physically; or the legacy fallback fires unexpectedly
while the flag is experimental.

---

## 8. Invariants

1. Deriving geometry never changes `M` or `E`.
2. Volume closes through pressure and interface, never by back-fill.
3. No energy without mass — and when it occurs it is **detected, counted and left unmutated**, never repaired.
4. No negative or non-finite mass or energy.
5. Every cap emits an explicit rejected/sink term with an owner.
6. A correction is counted exactly once.
7. A zone transition conserves mass and energy as a pair.
8. Interior transport conserves the building.
9. Exterior transport is accounted.
10. OFF is bit-identical.
11. Telemetry never governs physics.
12. No per-scenario tuning.
13. No expected/tolerance change to hide a movement.
14. The legacy fallback is explicit and counted while experimental.
15. **Projection is idempotent**: applying it twice to the same `(M, E)` gives a
    bit-identical result.

---

## 9. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Baselines move once volume closes through pressure instead of back-fill | **high** | expected; explained physically at H3.2b6, never tuned |
| The suppression lower-energy write stops being dead and changes suppression behaviour | **high** | isolated at H3.2b5 with its own gate; not switched on as a side effect |
| Multiple projections per timestep interact badly with a residual formulation | high | idempotence invariant plus the call-count metric from H3.2b1 |
| `p` non-finite in a degenerate room | medium | fail closed; keep the last valid state; emit a correction |
| The physical residual turns out large and unattributable | medium | that is a finding, not a failure; it names the missing owners for a later phase |
| `Phase3CoupledPressureSolver` and the new primitive disagree on pressure | medium | they answer different questions until H3.3; the divergence is reported, not reconciled early |
| Effort under-estimated across eight phases | medium | assume several sessions per phase; every phase independently revertible |

---

## 10. Decision

**GO for H3.2b1 — passive causal instrumentation only.**
**NO-GO for any physics change, including the primitive, until H3.2b1 reports.**

The architecture is specified well enough to build the primitive, but three
numbers that shape it are still unmeasured: the per-timestep projection call
count, the split between the physical and closure-inclusive residuals, and the
gross rather than net magnitude of the corrections. Building a primitive against
guesses for those is how the last two audits went wrong.

This phase is docs-only. Nothing was implemented, no flag added, no campaign run,
and `sim/`, `tests/`, `scripts/` and `tools/` are untouched.

---

## 11. H3.2b1 — passive causal ledger, delivered 2026-08-20

Instrumentation only. No physics changed, no flag defaults changed, no CSV column
added, no case file or report touched. The ledger observes; it never repairs a
state, never creates a sink, and none of its metrics is readable from an engine
decision.

### 11.1 What was built

| File | Role |
| --- | --- |
| `sim/core/Phase3ProjectionCausalLedger.gd` | passive accumulator, **new** |
| `sim/core/SimulationEngine.gd` | `@export phase3_projection_causal_diagnostics_enabled` (default `false`), one hook at the end of `step()` |
| `scripts/run_scenario.py`, `tools/run_scenario_headless.gd` | `--phase3-projection-causal-diagnostics` |
| `tests/fixtures/phase3_h32b1_projection_causal.gd` | 14 runtime assertions, fail-closed |
| `tests/test_phase3_h32b1_projection_causal.py` | 30 structural contracts |

It instruments nothing itself. `ZoneFireSolver` already emits a per-call
projection trace and the zone diagnostics already compute a per-stage
attribution; the ledger only accumulates both, so `project_room_state()` is never
instrumented twice.

### 11.2 Semantics, stated before the numbers

These definitions are the point of the phase; the earlier H3.2b1 draft reported
the same measurements under names that overstated what they meant.

- **Units.** A **room-step** is one room within one physical timestep. A
  **timestep** is one `SimulationEngine.step()`. `accumulate_step` is invoked
  exactly once per step, so the physical-timestep boundary is genuinely known and
  per-timestep multiplicity is *measured*, not inferred from room-steps. No
  metric is approximated across an unknown boundary; where a boundary is not
  known, the coverage is declared absent instead.
- **`gross_absolute` is projection churn** — the volume of rewriting a cause
  performed. It is **not** a physical contribution and **not** a source.
  `signed_net`, `gross_absolute` and `call_count` are kept as three separate
  numbers and never collapsed into one.
- **The physical residual is a candidate.** It is only called a physical residual
  when `residual_physical_valid`, which requires all three of: `data_available`,
  no observed active gap, and complete structural coverage. Otherwise the export
  labels it **`candidate_incomplete_physical_residual`**, because when an owner is
  missing the number *is* the missing owner, not a conservation measurement.
  `numerical_correction` is a valid observation in either case, and the contract
  `candidate_physical_residual − closure_inclusive_residual = numerical_correction`
  is computed and verified, under the sign convention that every term is a signed
  contribution to the state delta.
- **Static gaps are not active gaps.** `static_instrumentation_gap_reason_codes`
  lists owners whose coverage is known from reading the code to be absent or
  partial; it describes coverage and never implies that the path ran.
  `observed_active_gap_reason_codes` is incremented only when the corresponding
  writer materially moved mass or energy in this run
  (`MATERIAL_ACTIVITY_EPS = 1e-12`, derived from double precision, not fitted).
- **Fail closed.** If either telemetry source is off the ledger reports
  `data_available: false` with reason codes rather than zeros, since a zero
  meaning "not measured" is indistinguishable from a zero meaning "no
  correction".

### 11.3 Measured on `cfast_corridor_chain` (600 s, 6 rooms, 7 201 timesteps)

Committed case file, flags `--phase3-zone-diagnostics
--phase3-projection-causal-diagnostics`.

| Quantity | Value |
| --- | --- |
| timesteps | 7 201 |
| room-steps | 43 206 (= 7 201 × 6) |
| projection calls | **429 471** |
| max calls in one **room-step** | **17** |
| max calls in one **timestep** (all rooms) | **65** |
| room-steps with >1 call | **43 206 — every room, every timestep** |
| timesteps with >1 call | 7 201 |
| distinct causes | **17**, against the five direct call sites §2.1 mapped |
| `data_available` | `true` |
| static instrumentation gaps | 4: `hvac_mass_energy_unowned`, `other_stage_is_catchall`, `suppression_lower_write_dead`, `exterior_removal_not_zonal` |
| observed **active** gaps | **none** |
| `residual_physical_valid` | **`false`** — structural coverage incomplete |
| label applied | `candidate_incomplete_physical_residual` |
| candidate incomplete physical residual, mass | **+23.978 kg** |
| closure-inclusive residual, mass | **0.0 exactly** |
| numerical correction, mass | +23.978 kg |
| candidate incomplete physical residual, energy | −3.04e−11 kJ |
| closure-inclusive residual, energy | 0.0 exactly |
| relation error (mass, energy) | **0.0, 0.0 — exact** |

Largest causes by call count and by churn:

| Cause | calls | mass gross (kg) | mass net (kg) |
| --- | --- | --- | --- |
| `reconcile_layer_sync` | 86 412 | 23.964 | 23.964 |
| `gas_exchange_sync` | 64 057 | **12 415.669** | 442.949 |
| `thermal_energy_projection` | 43 206 | 62.646 | 62.646 |
| `thermal_post_combustion_sync` | 43 206 | 157.634 | −157.356 |
| `doorway_hot_source_sync` | 12 411 | 153.237 | 153.237 |
| `doorway_cold_target_sync` | 12 411 | 152.587 | −152.587 |

`gas_exchange_sync` rewrites **28×** more mass than it nets. That ratio is the
churn statement and nothing more: it is not a mass source, and none of it is
evidence of a physical contribution.

Per room, the corrections are **entirely on the lower zone**:

| Room | calls | max/room-step | lower net (kg) | lower gross (kg) | upper net/gross (kg) | cap binds |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 78 742 | 13 | +413.476 | 3 638.110 | 0.0 / 0.0 | 0 |
| 1 | 110 571 | **17** | −20.717 | 6 291.691 | 0.0 / 0.0 | 0 |
| 2 | 75 136 | 11 | −21.607 | 3 110.489 | 0.0 / 0.0 | 0 |
| 3 | 53 493 | 8 | −0.003 | 0.009 | 0.0 / 0.0 | 0 |
| 4 | 58 036 | 9 | −0.023 | 0.098 | 0.0 / 0.0 | 0 |
| 5 | 53 493 | 8 | −0.003 | 0.009 | 0.0 / 0.0 | 0 |

The ledger exported zero upper-zone births and deaths, values later shown by
H3.2b1a to be invalid / non-interpretable because the counter is blind. Zero
energy-without-mass states and non-finite states
in every room.

### 11.4 What this settles, and what it does not

Settled:

- The upper-mass cap of §2.1 and the thermal cap of §4 **never bind** in this
  scenario: `upper_mass_correction` and `thermal_cap_rejected` are exactly zero
  in all six rooms. **All** projection churn here is the unconditional lower
  rewrite. A primitive that only reworks the cap would change nothing on this
  case.
- The closure-inclusive residual is **exactly zero** and the relation error is
  **exactly zero**, which reconfirms §1: with `reconcile` and `projection_clamp`
  counted as attribution, the residual the engine itself computes cannot fail.
  The whole +23.978 kg sits in the numerical correction.
- Multiplicity is worse than the design assumed. "At least three per timestep"
  understated the room-step maximum by roughly a factor of five, and every single
  room-step carries more than one call.

Not settled, and explicitly **not** claimed:

- The +23.978 kg is **not** a proven physical residual. Four static coverage gaps
  remain open, so `residual_physical_valid` is `false`. No active gap was
  observed, which means the number is structurally uncertain but not observably
  contaminated — that is weaker than valid and stronger than unusable.
- One scenario is not a corpus. Whether these shapes hold across topologies is
  the question H3.2b1a answers.

> **[EXTENDED 2026-08-20 by H3.2b1a — nothing above is withdrawn.]** The ten-
> topology campaign confirms every shape in §11.4 and widens two numbers. The
> cause count is **20 across the corpus**, not 17: three causes
> (`exterior_background_source_sync`, `exterior_background_target_sync` and the
> `interlayer_*` pair) appear in a single scenario each, so seventeen was a
> one-scenario floor and twenty is still a lower bound. And the upper-cap result
> generalises: `upper_mass_correction`, `thermal_cap_bind_count` and
> `thermal_cap_rejected_kj` are exactly zero in **all ten** topologies, so the
> conclusion that a cap-only primitive would change nothing **at 120 s in this
> ten-case corpus** is a corpus property rather than a corridor-chain accident;
> it is not a claim about longer runs or other topologies. The campaign also measures the effect of
> run length directly: `gas_exchange_sync` churns 6.36× at 120 s and 28.03× at
> 600 s on this same scenario, so churn figures scale with duration and every
> H3.2b1a number is a lower bound for a full-length run. Full record:
> `docs/validation/PHASE3_H32B1A_PROJECTION_CAMPAIGN.md`.

### 11.5 Gates verified

- **OFF byte-identical.** `sim_log.csv` SHA-256 is identical between baseline and
  `--phase3-projection-causal-diagnostics` alone, and identical between
  `--phase3-zone-diagnostics` alone and that flag plus the causal flag. 367 rows
  in both pairs.
- Summaries differ by the opt-in `phase3_projection_causal` block only.
- No new CSV column; no legacy column changed.
- 30 pytest contracts and 14 Godot fixture assertions pass.

**H3.2b2 and every physics change remain blocked.**
