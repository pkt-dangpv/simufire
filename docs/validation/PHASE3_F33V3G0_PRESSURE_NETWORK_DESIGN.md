# Phase 3+ F3.3v3g0 interior pressure network design

Date: 2026-07-26

## Decision

F3.3v3g0 is **design GO**. No motor code is implemented in this phase.

The smallest justified next step is not a general nonlinear pressure ODE and
not another direct route replacement. It is a network-wide, under-relaxed
solve evaluated against the pressure response of the **actual fixed-gross
routes**.

This directly addresses the F3.3v3f3 failure: the current relaxation is
computed for additive pressure routes, but the candidate applies a different
fixed-gross route field. The limiter therefore constrains the wrong pressure
response.

## Current runtime ordering

The canonical shadow currently performs these operations:

```text
pre-step canonical mass/energy snapshots
    |
    +-- derive room pressure and layer geometry from EOS
    |
    +-- build zero-net buoyant opening routes
    |
    +-- build independent signed-pressure routes
    |
    +-- predict pressure delta of opening routes
    |
    +-- relax signed-pressure routes so their additive response does not
    |   cross a connected-room pressure difference
    |
    +-- append opening + relaxed pressure routes to one atomic network bundle
    |
    +-- F3.3v3f1 passively recomposes those routes as fixed-gross telemetry
```

F3.3v3f3 replaced the final bundle with the recomposed routes, but retained
the relaxation calculated for the discarded additive route response. The
candidate then fed its own mismatched end pressure into the next timestep and
entered one-way positive feedback.

## Required solve

For every connected horizontal-opening network, define:

- `p_i`: pre-step canonical gauge pressure of room `i`;
- `d_base_i`: pressure change produced by the zero-net opening routes;
- `d_full_i`: pressure change produced by the full fixed-gross candidate;
- `p0_i = p_i + d_base_i`;
- `h_i = d_full_i - d_base_i`;
- `alpha`: one network-wide blend from base routes to fixed-gross routes.

For connection `e = (a, b)`:

```text
delta0_e = p0_a - p0_b
h_e      = h_a - h_b
delta_e(alpha) = delta0_e + alpha * h_e
```

Choose `alpha` by minimizing the network pressure disequilibrium:

```text
J(alpha) = sum_e weight_e * delta_e(alpha)^2

alpha_opt =
    clamp(
        -sum_e(weight_e * delta0_e * h_e)
        / sum_e(weight_e * h_e^2),
        0,
        1
    )
```

Then apply three bounds:

1. **descent bound**: if the derivative of `J` at zero is not negative,
   accept `alpha = 0`;
2. **no-crossing bound**: no connection pressure difference may reverse sign
   in one physical timestep;
3. **inventory bound**: the blended atomic routes may not debit more gas,
   energy, O2 or species than their source-zone snapshot contains.

Use a measured under-relaxation factor only after the exact minimizer is
known:

```text
alpha_accepted = min(alpha_opt, alpha_crossing, alpha_inventory)
```

The first implementation should not add an empirical factor. If later data
requires one, it must be exposed in telemetry and justified by convergence,
not tuned to a required checkpoint.

## Route construction

The fixed-gross primitive already guarantees equal gross mass before and
after skew. F3.3v3g must add a pure interpolation:

```text
route(alpha) = base_route + alpha * (full_fixed_route - base_route)
```

Mass, sensible enthalpy, O2 and every species use the same `alpha`. Routes
must retain stable connection and source/destination identities.

For any `alpha` in `[0, 1]`:

- gross mass per connection remains exactly the base-opening gross mass;
- every route quantity remains non-negative;
- source debit equals destination credit;
- mass, energy, O2 and species global residuals remain zero.

## Mandatory invariants

| Invariant | Acceptance |
|---|---:|
| Building gas mass closure | `abs(residual) <= 1e-9 kg/step` |
| Energy closure | `abs(residual) <= 1e-7 kJ/step` |
| O2 closure | `abs(residual) <= 1e-9 kg/step` |
| Species closure | `abs(residual) <= 1e-9 kg/step` |
| Gross mass preservation | `abs(candidate - base) <= 1e-9 kg/connection` |
| Network objective | `J_post <= J_pre + 1e-9 Pa2` |
| Pressure sign | no unreported crossing per connection |
| Route quantities | finite and non-negative |
| Source inventories | no accepted debit beyond snapshot |
| Canonical zones | EOS valid; no numerical mass collapse |
| Opening order | identical result under descriptor permutation |
| OFF behavior | exact legacy and shadow-column invariance |

## Implementation phases

### F3.3v3g1 - pure network relaxation primitive

Scope:

- `sim/core/Phase3ZoneMassSystem.gd`;
- a new focused structural test module.

Add a dictionary-only pure function that receives room pressures, base and
full route pressure deltas, connection pairs and optional inventory bounds.
It returns `alpha`, objective values, limiting reason and validity. It must
not read or write persistent dictionaries.

Required tests:

- one connection reaches equilibrium without crossing;
- two- and three-room chains reduce global `J`;
- opening-order permutation gives identical output;
- disconnected components do not influence each other;
- non-descent proposal returns `alpha = 0`;
- zero response is valid and dormant;
- inventory bound dominates when necessary;
- NaN, missing room and malformed connection fail closed.

STOP:

- pure tests pass;
- no runtime wiring;
- no new exported flag;
- no reports or baselines.

### F3.3v3g2 - passive runtime preview

Scope:

- new default-OFF flag;
- call the pure solver after base and **raw** fixed-gross routes exist;
- add telemetry only.

Important: use raw pressure demand to create the full fixed-gross candidate.
Do not first apply the old additive-route relaxation; that would constrain
the candidate twice.

Minimum telemetry:

- `alpha_opt`, `alpha_crossing`, `alpha_inventory`, `alpha_accepted`;
- `objective_pre_pa2`, `objective_post_pa2`;
- descent/non-descent and limiting-reason counts;
- predicted minimum upper/lower gas inventory;
- gross, mass, energy, O2 and species residuals;
- cumulative accepted net flow by sign.

STOP at 180 s:

- all 115 non-shadow fields exactly identical OFF/ON;
- `J_post <= J_pre` at every active physical timestep;
- no zone collapse in the preview;
- no atomic residual;
- gross and enthalpy correspondence remain within 5% of CFAST.

### F3.3v3g3 - persistent dynamic shadow

Only after F3.3v3g2 passes, allow the accepted blended routes to update the
private canonical shadow state. Legacy state remains untouched.

Run staged STOP gates at 30, 60, 120 and 180 s. Stop immediately if:

- pressure request or cap count grows monotonically for ten logged intervals;
- all material cap events retain one sign after a pressure sign change;
- either zone inventory reaches numerical zero unexpectedly;
- `J` increases;
- any conservation residual exceeds its invariant;
- gross or net enthalpy error exceeds 5% at 180 s.

Target at 180 s:

- requested pressure transport remains within 2x the F3.3v3f2 baseline;
- cap count remains within 2x the 79-event baseline;
- net mass correspondence improves from the F3.3v3f1 `-55.49%` error to
  within 25%;
- lower shadow gas remains positive and EOS-valid;
- fixed gross mass and net enthalpy remain within 5% of CFAST.

### F3.3v3g4 - extended shadow validation

Run 300 and 600 s Group C plus Group A only after the 180 s gate passes.
Check interface, upper/lower mass, temperature, O2, FED inputs and all
existing coherence rules. No required baseline or tolerance changes are
allowed.

### F3.3v3g5 - authority decision

Authority is a separate approval. It requires:

- Group A/C required checks improve or close;
- Physics and ILV remain at 0 FAIL;
- guardrails 10/10;
- no new CTRL or VALID_GAP;
- explicit before/after review of FED, O2 and species;
- default OFF retained until the authority STOP is approved.

## Files deliberately not touched in F3.3v3g1

- `SimulationEngine.gd`;
- `ThermalSystem.gd`;
- `GasExchangeSystem.gd`;
- validation cases and reports;
- expected values and tolerances;
- FED, HVAC and visual code.

## Recommendation

Proceed with **F3.3v3g1 only**. It is the smallest useful motor slice and can
be proven entirely with pure tests. Do not create another dynamic runtime
candidate in the same session.
