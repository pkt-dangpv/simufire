# Phase 3+ F3.2b6 canonical exterior counterflow

Date: 2026-07-20

## Scope

F3.2b6 adds a default-OFF, shadow-only bidirectional exchange through real
open exterior openings. It closes the boundary-contract gap identified by
F3.2b5c: a hot compartment can now send upper gas outdoors while receiving
fresh exterior air into its lower zone at the same instant, even when net
room pressure is approximately zero.

The implementation does not write legacy `RoomModel` physics, FED or official
validation reports. Expected values, tolerances and VALID_GAP classifications
remain unchanged.

## Contract

The preview consumes only the persistent canonical pre-step state, static
opening geometry and ambient conditions. Each opening is integrated in 64
vertical segments. A hydrostatic pressure offset is solved by bisection so
the counterflow component has zero net mass:

```text
canonical upper -> exterior   m_exchange
exterior -> canonical lower   m_exchange
net counterflow mass          0
```

The exchange magnitude is the smaller of the raw upper outflow and raw lower
inflow. Both routes share one atomic acceptance fraction. Upper sensible
energy, O2 and species leave with their canonical source concentrations;
incoming air carries ambient O2 and zero sensible energy relative to ambient.

The existing F3.2a/F3.2b2 pressure-relief bundle remains the sole owner of
signed net exterior mass. Counterflow and pressure relief therefore coexist
without claiming the same mass:

```text
gross buoyant exchange: equal opposing routes, net zero
pressure relief:        signed residual net route
```

## Instrumentation

The opt-in CSV adds 29 `phase3_shadow_counterflow_*` fields covering:

- neutral plane and hydrostatic pressure offset;
- raw upper-out and lower-in requests;
- requested, accepted, rejected and cumulative exchange;
- pressure-relief mass reported beside, but not owned by, counterflow;
- outgoing energy, outgoing/incoming O2 and outgoing species;
- mass, energy, O2 and species residuals;
- opening count, duplicate owners, invalid previews and opposed outflow.

## Controls

### Deterministic fixture

The Godot 4.7.1 fixture covers ambient equilibrium, simultaneous hot-upper
outflow/lower inflow, independence from gauge-pressure sign, atomic O2 and
species routing, source-inventory limiting, coexistence with pressure relief
and duplicate-owner detection. Result:

```text
PHASE3_F32B6_EXTERIOR_COUNTERFLOW_PASS
```

### Open room without fire

The 60 s open/no-fire control produced 78 CSV rows and a consistent
469-column schema. Every physical counterflow and residual field was exactly
zero. Only `accepted_fraction=1` and `opening_count=1` were nonzero, describing
the available opening rather than a flow.

### Default-OFF invariance

The 60 s OFF control is bit-identical to the accepted F3.2b5c control across
443 shared columns and 78 rows. The Group A OFF run is also identical across
all matching non-budget columns; the only excluded `bud_*` fields came from a
scratch scenario configuration difference, not this mechanism.

## Group A result

The table compares the previous default F3.2b5c shadow, F3.2b6 with current
case inputs, a scratch-only `chi_rad=0.35` plus CFAST-leakage combination, and
CFAST. The combined candidate is diagnostic only and is not accepted tuning.

| Time | State | Upper O2 | Interface | HRR |
|---:|---|---:|---:|---:|
| 380 s | F3.2b5c | 0.0700 | 0.153 m | 210 kW |
| 380 s | F3.2b6 | 0.0810 | 0.752 m | 313 kW |
| 380 s | F3.2b6 combined scratch | 0.0829 | 0.855 m | 356 kW |
| 380 s | CFAST | 0.0616 | 0.522 m | 1280 kW |
| 400 s | F3.2b5c | 0.0626 | 0.147 m | 189 kW |
| 400 s | F3.2b6 | 0.0802 | 1.345 m | 340 kW |
| 400 s | F3.2b6 combined scratch | 0.0888 | 1.496 m | 436 kW |
| 400 s | CFAST | 0.1072 | 0.968 m | 1280 kW |
| 420 s | F3.2b5c | 0.0614 | 0.141 m | 142 kW |
| 420 s | F3.2b6 | 0.0928 | 1.574 m | 490 kW |
| 420 s | F3.2b6 combined scratch | 0.1012 | 1.622 m | 611 kW |
| 420 s | CFAST | 0.1320 | 1.020 m | 1280 kW |

The baseline counterflow accepts about 0.043-0.070 kg per 1/12 s physical
step between 370 and 420 s, approximately 0.52-0.84 kg/s of gross exchange.
It reoxygenates the upper zone and expands the lower layer in the correct
direction. Mass, energy, O2, species and hydrostatic residuals are exactly
zero, with no duplicate or invalid requests.

The mechanism also exposes the next mismatch. The interface overshoots CFAST
after 400 s while HRR remains less than half the CFAST value. Adding the best
F3.2b5c scratch inputs increases both effects and therefore is not accepted.
Boundary flow is no longer the only blocker.

## Verification

- New F3.2b6 tests plus adjacent F3.2b5 tests: 29/29 PASS.
- Direct Godot 4.7.1 fixture: PASS.
- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL.
- ILV coherence: 15 PASS / 14 CTRL / 0 FAIL.
- Gap inventory: 348/353 required PASS, 5 VALID_GAP, sync PASS.
- Guardrails: 9/10; only R2-1, expected while `sim/core` is dirty.
- Full pytest remains affected by a Windows/sandbox temporary-directory
  permission issue plus known stale structural assertions. Focused F3.2b6
  tests are clean and no new failure has been attributed to this patch.

## STOP gate

Decision: **F3.2b6 shadow mechanism GO; canonical authority and Group A
retirement NO-GO**.

F3.2b7 must diagnose and close the post-opening canonical combustion/O2/plume
feedback. It must determine why fresh lower-zone air does not restore HRR and
plume entrainment at the CFAST rate, without per-case coefficients or relaxed
validation. F3.3/Group C and production authority remain downstream.
