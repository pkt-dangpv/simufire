# Phase 3 H3.2b1b — Persistent zone transition ledger, design

Date: 2026-08-21
Scope: **design only, documentation only.** No file under `sim/`, `tests/`,
`scripts/` or `tools/` is modified by this document. No flag, no physics, no
campaign, no implementation. No R2-1 refresh, because no engine source is
touched.

Decision: **GO to implement H3.2b1b as specified below. NO-GO for H3.2b4 and for
any runtime authority until it reports.**

---

## 1. The defect

`Phase3ProjectionCausalLedger._scan_zone_transition` compares `ev["pre"]` against
`ev["post"]` — the two snapshots of a **single `project_room_state` call**.
Projection never creates upper mass, so the 0 → present step happens *outside*
the call and both snapshots already show the new regime by the time projection
runs. The counter is therefore structurally incapable of witnessing a birth.

H3.2b1a measured the consequence directly: **0 births reported against at least
29 real ones**, and all 85 rooms in the corpus start one-zone.

---

## 2. Observation boundaries

The repair is to compare **persistent room state across a boundary between two
observations**, never within one projection.

| granularity | boundary | role |
|---|---|---|
| **step** | `upper_gas_kg` observed at the same point at the end of step *N* versus the same point at the end of step *N−1* | **PRIMARY.** The boundary is known exactly — the observer runs once per `SimulationEngine.step()` — so the count is unambiguous and physically meaningful |
| **call** | `post` of a room's previous projection call versus `pre` of that room's next projection call | **SECONDARY.** A strictly narrower bound only |

**Both can still miss transitions.** A regime that changes and changes back
*between* two observations is invisible at that granularity: the step counter
misses oscillation inside a step, and the call counter misses oscillation between
two consecutive projection calls for the same room. Neither is a ground truth;
each is a **lower bound**, and the call bound is narrower than the step bound but
not exact. Anything finer would require instrumenting every writer of
`upper_gas_kg`, which this phase does not do.

**Call granularity compares `post`(previous call) with `pre`(next call), for the
same room.** That interval is precisely the window in which some other subsystem
wrote, which is what the within-projection comparison could never see.

**No cause attribution, ever.** The transition observed at a call boundary was
produced *between* the calls, by whatever wrote in that window — not by the
projection whose `pre` closes the interval. Labelling it with the following
call's cause would attribute an effect to something that did not cause it. The
call-granularity counters therefore carry **no `by_cause` breakdown at all**, and
that absence is deliberate and contractual.

---

## 3. Seeding and cardinality

### 3.1 The initial snapshot precedes the first physical step

The observer takes a **seed snapshot before the first physical timestep runs**.
Without it the first observation would have no predecessor and would either be
discarded (losing a real transition in step 1) or counted as a birth from
nothing (inflating every room, since all 85 rooms in the corpus start one-zone).

The seed is classified once per room, into `initial_present` or
`initial_absent`. **A seed is never a transition.**

### 3.2 Two separate cardinality identities

`initial` and the transition classes count **different populations** and are
never summed together.

```
initial_present + initial_absent                              == rooms_seeded
birth + death + stable_present + stable_absent + room_added
                                              + room_removed == transition_observations
```

where `transition_observations` is the number of **boundaries actually
observed** over the N steps — not `rooms × timesteps`, because a room that
appears or disappears mid-run does not contribute a boundary for every step.

For a run in which the room set never changes, `transition_observations` reduces
to `rooms × N`, and that is worth asserting as a separate check when
`room_added == room_removed == 0`. Both identities are exported and both are
verified per predicate and per granularity.

### 3.3 Room set changes are their own outcome

A room present at boundary *N* but absent at *N−1* is **`room_added`**, not a
birth. A room absent at *N* but present at *N−1* is **`room_removed`**, not a
death. Fabricating a birth or a death out of a room-set change would invent a
zone transition that never happened. Each is counted separately, and each is
excluded from `birth`/`death`.

---

## 4. Presence predicates — four, simultaneously, none authoritative

There is no shared definition of an absent zone in this codebase: seven
predicates are in use, from `> 0.1` kg at the FED gate to `> 1e-12` kg in the
coupled solver. **H3.2b1b does not choose one, and must not**, because that
choice is a blocker owned by H3.2b6.

Every counter set is therefore emitted **under four named predicates at once**:

| name | threshold | where it comes from |
|---|---|---|
| `strict_positive` | `> 0.0` | `Phase3ResidualProjection`, the H3.2b2 primitive |
| `ledger` | `> 1.0e-6` | `Phase3ProjectionCausalLedger.ZONE_MASS_EPS_KG` |
| `projection` | `> 1.0e-4` | `ZoneFireSolver.ZONE_MASS_EPS_KG` |
| `fed_gate` | `> 0.1` | `ThermalSystem.gd:4553`, the FED hypoxia gate |

The divergence between the four is itself the evidence H3.2b6 needs. Reporting
all four costs one loop and forecloses nothing.

---

## 5. The ≥29 acceptance gate, tied to the right predicate

H3.2b1a's "at least 29 births" was produced by
`scripts/simulation/phase3_h32b1a_projection_campaign.py`, which classifies the
logged `upper_gas_kg` state column with `present = upper > ZONE_MASS_EPS_KG`
where that module sets `ZONE_MASS_EPS_KG = 1.0e-6`.

> **[PROVENANCE CORRECTED 2026-08-21.]** The comment above that constant in the
> analyser reads *"It is ZoneFireSolver's own constant, mirrored by the ledger"*.
> That misattributes it. `ZoneFireSolver.ZONE_MASS_EPS_KG` is **1.0e-4**;
> **1.0e-6** is `Phase3ProjectionCausalLedger.ZONE_MASS_EPS_KG`. The value the
> analyser actually used is 1.0e-6, so **the 29 belongs to the `ledger`
> predicate**, not to the `projection` one. The comment should be corrected when
> the analyser is next touched; the measurement itself is unaffected.

**The gate therefore applies to the `ledger` predicate only** — comparing it
against a count produced under a different threshold would be meaningless.

Same corpus, same duration, same commit-identified inputs: the ten committed case
files at **120 s**, blob OIDs at HEAD

| scenario | blob OID | H3.2b1a sampled births (`ledger`, 10 s sampling) |
|---|---|---:|
| `cfast_corridor_chain` | `a4eeae6bebd0` | 3 |
| `cfast_r0_window_360` | `3b93649cd09e` | 1 |
| `cfast_two_floor_stairwell` | `2a91c9348eff` | 2 |
| `two_storey_smoke` | `828812bfe0fd` | 2 |
| `ghanekar_bedroom_hallway` | `2dbb0416d17e` | 2 |
| `piso_mediterraneo_smoke` | `c9032b5e1cd4` | 4 |
| `uk_bungalow_smoke` | `269e31f6ca59` | 5 |
| `compact_apartment_smoke` | `52c76a6bc4be` | 3 |
| `three_bed_apartment_smoke` | `78294dc3c0ee` | 3 |
| `flashover_simple_house` | `e2931ea0e1e1` | 4 |
| **total** | | **29** |

**Acceptance:** the step-granularity `birth` count under the `ledger` predicate,
summed over the ten scenarios, must be **≥ 29**. The reasoning is one-directional
and therefore safe: H3.2b1a sampled the state column every 10 s and so produced a
lower bound; the step observer sees **every** step and cannot see fewer real
transitions than a 10 s sampler did. **A total below 29 means the counter is
still blind and the phase fails.** A total above 29 is expected and is the
measure of what the sampling missed.

Per-scenario counts are also compared against the table above; a scenario falling
below its own sampled figure is a failure even if the total passes.

---

## 6. The historical surface is preserved

`upper_zone_birth_count_total` and `upper_zone_death_count_total` **stay exactly
where they are**, with their current names and values, as **deprecated aliases**.
Nothing that reads them breaks.

Alongside them, `Phase3ProjectionCausalLedger` gains explicitly-named twins:

```
within_projection_call_upper_zone_birth_count_total
within_projection_call_upper_zone_death_count_total
```

carrying the same numbers under a name that states what they measure and why they
are near-always zero. The summary gains a note marking the old keys deprecated
and pointing at the H3.2b1b counters as the ones with meaning. **The old keys are
not removed in this phase.**

---

## 7. Component shape

New `sim/core/Phase3ZoneTransitionLedger.gd`, independent of everything else.

- `@export var phase3_zone_transition_diagnostics_enabled: bool = false` on
  `SimulationEngine`.
- **Registered in `_phase3_projection_diagnostics_active()`.** The call
  granularity consumes the per-call trace, and H3.2b3 established what happens to
  a flag that needs the trace and is absent from that gate: the trace is
  reasserted off at every logging point and the ledger silently accumulates
  nothing. A contract pins the registration.
- **Seeded before the first physical step**, and thereafter observed **at the
  same point at the end of every step**, so the boundary never drifts.
- Reads room state from `building.get_rooms()`. **No dependency on the H3.2b3
  shadow**, on `Phase3ResidualProjection`, or on the zone diagnostics.
- Cumulative `*_total` only; passive; fail-closed with reason codes when the
  trace is unavailable (call granularity is then declared absent, not zeroed).
- Writes no state, governs no physics, adds **no CSV column**; exports an opt-in
  summary block only.

---

## 8. Fixtures

Births; deaths; stable present; stable absent; the seed snapshot classified as
initial and never as a transition; oscillation within one step visible at call
granularity and merged at step granularity; divergence between the four
predicates on a zone parked between 1e-6 and 0.1 kg; `room_added` and
`room_removed` never counted as birth/death; both cardinality identities; OFF is
a no-op; and a negative control proving the counter can fail.

---

## 9. Risks

1. **Neither granularity is ground truth.** Both are lower bounds. The document
   and the summary must keep saying so.
2. **The four-predicate output multiplies the counter set** and could drift into
   being read as a de-facto choice. The summary states that none is authoritative.
3. **Observation-point drift.** If the end-of-step observation is ever moved, the
   boundary changes meaning silently. It is placed once and pinned by a contract.
4. **The alias could be mistaken for the repaired counter.** Hence the explicit
   deprecation note next to it.
5. **Room-set churn is untested by this corpus**, where the room set is constant.
   `room_added` / `room_removed` will be exercised by fixtures only.

---

## 10. Decision

**GO to implement, exactly as specified.** Default OFF, passive, cumulative,
fail-closed, independent of H3.2b3, preserving the historical surface.

**NO-GO for H3.2b4 and for any runtime authority.** H3.2-S, H3.2b and H3.3 remain
open; S0d6b1 stays blocked; HVAC stays deferred; the presence predicate stays
unresolved and remains a blocker for H3.2b6.

---

## 11. Implementation STOP gate (2026-08-21)

The design above was implemented without changing physics, authority, CSV
columns, case files, expected values, baselines or tolerances.

The first ten-topology matrix correctly failed: the observer was seeded at the
end of step one and reported only 19 births, with one ignition room per scenario
misclassified as initially present. Seeding was moved to the start of
`SimulationEngine.step()`, before every physical stage, and pinned by a contract.

The corrected corpus reports:

- 85 initially absent rooms and zero initially present rooms.
- 29 step births under each of `strict_positive`, `ledger` and `projection`.
- 29 step births under `fed_gate`, with different stable-state counts.
- 30 call births and one call death under the three finer predicates.
- Exact initial and boundary cardinality for all predicates in all scenarios.
- Zero room additions/removals in the committed corpus; both are fixture-tested.
- Byte-identical OFF/ON shared CSV in all ten scenarios.
- Complete manifests, 120.083 s reached and zero residual Godot processes.

The old within-projection counters remain as deprecated aliases and explicitly
named twins. No call-boundary transition is assigned to the cause of the next
projection call. `authoritative_predicate` remains null.

Decision: **GO for passive H3.2b1b only. USER AUDIT STOP REACHED.** H3.2b4 and
H3.3 remain blocked by the binding independent audit in
`MOTOR_PRE_AUTHORITY_AUDIT_PLAN.md` and by explicit user authorization after its
closure.
