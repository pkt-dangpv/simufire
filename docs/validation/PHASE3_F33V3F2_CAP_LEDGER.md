# Phase 3+ F3.3v3f2 cap-ledger diagnosis

Date: 2026-07-26

## Decision

The F3.3v3f1 post-hoc fixed-gross cap is **NO-GO as canonical route
authority with the current pressure trajectory**.

The fixed-gross architecture remains valid. The failure is temporal: large,
alternating signed-pressure requests are clipped independently every physical
timestep. That local clipping changes the cumulative direction.

No legacy or canonical authority changed in this phase.

## Added instrumentation

Ten cumulative, opt-in fields were added under the existing default-OFF
F3.3v3f1 flag:

- total requested and accepted pressure net per room;
- positive and negative cap counts;
- requested and accepted cap mass by sign;
- total and maximum absolute rejected cap mass.

The fields are cumulative so a normal 10 s CSV captures every 1/12 s physical
timestep without an impractically large log.

Verification:

- focused F3.3v3f0/f1/f2 tests: 16 PASS;
- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL;
- ILV coherence: 15 PASS / 14 CTRL / 0 FAIL;
- gap inventory: synchronized, 347/353 PASS plus 6 VALID_GAP.

## Result at 180 s, R0

| Metric | Value |
|---|---:|
| CFAST doorway net out | 7.290 kg |
| SimuFire pressure net requested | 6.368 kg (87.35% of CFAST) |
| SimuFire pressure net accepted by cap | 3.245 kg (44.51% of CFAST) |
| Cap events | 79 |
| Positive / negative cap events | 44 / 35 |
| Requested mass in positive caps | 17.368 kg |
| Requested mass in negative caps | 16.195 kg |
| Accepted mass in positive caps | 1.687 kg |
| Accepted mass in negative caps | 3.637 kg |
| Absolute rejected mass | 28.240 kg |
| Maximum single rejection | 0.986 kg |

The capped subset requests `+1.173 kg` net out of R0, but accepts
`-1.950 kg`. The cap therefore contributes a `-3.123 kg` directional bias.
Uncapped timesteps request `+5.195 kg`; combining those with the capped
accepted integral reconstructs the measured `+3.245 kg` exactly.

## Timing

The first 25 caps occur before 20.1 s and reject only `0.078 kg`. The material
bias begins with the pressure-sign transition around 120 s:

| Logged interval end | Caps | Positive | Negative | Rejected abs kg |
|---|---:|---:|---:|---:|
| 120.1 s | 9 | 3 | 6 | 3.961 |
| 130.1 s | 3 | 1 | 2 | 1.661 |
| 140.1 s | 6 | 2 | 4 | 3.381 |
| 150.1 s | 6 | 2 | 4 | 3.428 |
| 160.0 s | 9 | 3 | 6 | 4.660 |
| 170.0 s | 11 | 4 | 7 | 5.868 |
| 180.0 s | 10 | 4 | 6 | 5.203 |

## Architectural consequence

A static normalized combined-slab preview evaluated against the same pressure
trajectory cannot by itself close the error. It has the same non-negative,
fixed-gross per-step bound and therefore saturates when the requested net is
larger than the available gross counterflow.

The next useful experiment must be dynamic:

1. add a new default-OFF canonical-shadow candidate;
2. replace the additive opening plus pressure routes with the fixed-gross
   routes inside that shadow branch only;
3. let the accepted transport update the next-step canonical pressure;
4. stop at 180 s and compare cap count, pressure oscillation, mass, enthalpy
   and CFAST correspondence;
5. leave legacy state, official reports and required checks untouched.

This tests whether pressure naturally carries unrelieved demand into later
steps instead of losing it through local clipping.
