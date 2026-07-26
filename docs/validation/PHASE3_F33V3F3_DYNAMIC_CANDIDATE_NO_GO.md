# Phase 3+ F3.3v3f3 dynamic fixed-gross candidate

Date: 2026-07-26

## Decision

The direct dynamic replacement of additive opening plus pressure routes by
the fixed-gross directional routes is **NO-GO**.

The experiment was correctly isolated: all 115 non-shadow CSV fields are
identical to the F3.3v3f2 baseline for all 114 rows. It therefore did not
change legacy state, FED or official validation behavior.

The canonical candidate itself is unstable. Its accepted transport changes
the next-step pressure in one direction, which increases the following
request instead of converging. The lower zone then loses all of its shadow
gas mass.

The experimental motor patch was reverted. Only this record, a read-only
analyzer and its tests remain.

## R0 result at 180 s

| Metric | F3.3v3f2 baseline | Dynamic candidate |
|---|---:|---:|
| Cap events | 79 | 1676 |
| Positive / negative caps | 44 / 35 | 1676 / 0 |
| Pressure net requested | 6.368 kg | 804.659 kg |
| Pressure net accepted | 3.245 kg | 205.113 kg |
| Absolute rejected mass | 28.240 kg | 599.516 kg |
| Preview out / in | 73.560 / 70.315 kg | 216.126 / 11.013 kg |
| Preview net enthalpy out | 6321.966 kJ | 22075.625 kJ |
| Upper / lower shadow gas | 24.756 / 21.555 kg | 39.326 / 0.000 kg |
| Shadow pressure gauge | -19.028 Pa | +14.836 Pa |
| Zone mass residual | -7.618 kg | -14.603 kg |
| Zone energy residual | 2230.182 kJ | 4283.234 kJ |

Requested pressure transport grows by about 126 times. All 1676 cap events
have the same sign. This is a one-way pressure feedback, not convergence.

## What this rejects

Do not retry any of the following as an authority candidate:

- direct replacement of the additive pressure route by the current
  fixed-gross preview;
- independent per-timestep clipping against available gross counterflow;
- a static normalized replay over the existing pressure trajectory;
- increasing gross doorway flow to provide more cap headroom.

The first three have now been measured directly. The fourth would spoil the
already good gross-mass and net-enthalpy correspondence with CFAST.

## Next architectural gate

The next phase is design-first: **F3.3v3g0 implicit interior pressure network**.

It must solve pressure and fixed-gross directional flow together, rather than
letting an explicit route mutate the next request. At minimum, the design
must define:

1. the pressure residual carried between physical timesteps;
2. an implicit or under-relaxed solve over all connected rooms;
3. antisymmetric connection flow and exact building mass closure;
4. a per-zone inventory bound that cannot collapse the lower zone;
5. convergence criteria for pressure, net flow and enthalpy;
6. rollback criteria before any runtime implementation.

No F3.3v3g motor code should be written until that design has a STOP gate.

## Reproduction

```powershell
python scripts/simulation/analyze_phase3_f33v3f3_dynamic_candidate.py
python -m pytest tests/test_analyze_phase3_f33v3f3_dynamic_candidate.py
```

The analyzer intentionally succeeds only when it proves both facts:

- isolation is exact;
- the candidate is unstable and not ready for runtime authority.
