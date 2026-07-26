# Phase 3+ F3.3v3a unfiltered canonical growth experiment

Date: 2026-07-26

## Decision

F3.3v3a is **GO for fuel-source correspondence** and **NO-GO for runtime
authority or Group C retirement**.

The new
`phase3_canonical_unfiltered_fire_growth_shadow_enabled` flag is default OFF
and effective only inside the F3.3v proposal stack. When enabled, the pure
canonical proposal uses its t-squared target directly instead of applying a
second HRR rise/fall filter.

No live `RoomModel`, `FireModel` or `FuelObjectModel` is written.

## Why this experiment was needed

F3.3v2d measured a `0.58758433 MJ` live/canonical object-fuel difference at
180 s. Legacy explicit objects debit the ideal solid-pyrolysis curve while
the canonical product transaction debited the smoothed proposal HRR.

For the supported corridor profile there is no retained pool, backdraft,
spread or thermal feedback. The difference therefore had no separate
physical owner. The direct t-squared proposal tests whether the second filter
owns both the inventory mismatch and the early temperature deficit.

## STOP gate

Scenario:

- `runs/phase3_f33t/cases/corridor_on.json`;
- Godot 4.7.1;
- complete F3.3t stack plus F3.3v2c2 object synchronization;
- 180 s only, per the mandatory STOP.

| Check | Filtered | Unfiltered | Result |
|---|---:|---:|---|
| Live-column differences vs OFF | 0 | 0 | PASS |
| Stable explicit objects | 7 | 7 | PASS |
| Eligible objects | 1 | 1 | PASS |
| Source-mismatch rows | 9 | 0 | PASS |
| Max live/canonical fuel delta | 0.58758433 MJ | 0.00000248 MJ | PASS at physical precision |
| Allocation/atomic/aggregate residual | 0 | 0 | PASS |
| R0 upper temperature t=180 | 139.8689 C | 140.0305 C | +0.1616 C |
| Required lower bound | 144.816 C | 144.816 C | FAIL |
| Cumulative fire radiation | 13.1062 MJ | 13.3118 MJ | +0.2057 MJ |
| Total surface energy | 26.7536 MJ | 27.2035 MJ | +0.4499 MJ |

Physics coherence remains at zero FAIL. The direct proposal closes fuel
source correspondence, but it does not close the required thermal check.
Per STOP, no 300/600 s run was performed with this flag.

## Revised physical owner

At 180 s the unfiltered candidate has:

- upper gas `24.756 kg` versus CFAST `26.94 kg`;
- lower gas `21.555 kg` versus CFAST `15.41 kg`;
- total gas `46.310 kg` versus CFAST `42.35 kg`;
- interface `0.946 m` versus CFAST `0.736 m`;
- upper/lower temperatures `140.03 / 35.54 C` versus
  `159.82 / 61.56 C`.

The extra fire energy mostly reaches surfaces, whose total stored energy is
already close to CFAST. The remaining early error is therefore not an HRR
source deficit. It is a zone-mass and interface partition error:

1. roughly `3.96 kg` too much total gas remains in R0;
2. too much of that gas remains in lower;
3. upper is correspondingly underfilled and the interface stays too high.

## Next gate

F3.3v3b must be diagnostic first. Attribute the 180 s R0 mass error to:

- exterior/interior opening accepted net mass;
- plume lower-to-upper transfer;
- pressure relaxation and boundary exchange;
- EOS/interface projection.

Do not tune HRR, wall coefficients, CFAST expected values or case knobs.
Runtime authority remains blocked.
