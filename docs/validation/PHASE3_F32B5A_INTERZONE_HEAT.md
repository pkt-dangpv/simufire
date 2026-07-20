# Phase 3+ F3.2b5a canonical inter-zone heat transfer

Date: 2026-07-19

## Scope

F3.2b5a replaces only the passive shadow interpretation of the legacy
`thermal_upper_to_lower` request. The new path derives direction and magnitude
from the persistent canonical pre-step state and applies one energy-only atomic
bundle between the upper and lower canonical reservoirs.

The feature is opt-in through
`phase3_canonical_interzone_heat_shadow_enabled=false`. Legacy physics,
official reports, expected values, tolerances and VALID_GAP classifications
remain unchanged.

## Canonical transfer

For positive canonical temperature difference `dT = T_upper - T_lower`:

```text
Cu  = m_upper * cp
Cl  = m_lower * cp
Ceq = Cu * Cl / (Cu + Cl)

Q_candidate   = Ceq * dT * rate * fade * dt
Q_equilibrium = Ceq * dT
Q_requested   = min(E_upper, Q_candidate, Q_equilibrium)
```

`rate` reuses the existing upper-to-lower and lower-warming coefficients as a
per-second coupling rate. `fade` reuses the declared interface-depth fade but
is evaluated with canonical geometry. If the lower zone is as hot as or hotter
than the upper zone, the downward request is zero.

The reduced-capacity equilibrium bound is exact for two finite reservoirs. It
prevents one step from crossing thermal equilibrium. The transaction moves no
gas mass, O2 or species and conserves total canonical sensible energy exactly.

## Atomic ownership

When the flag is ON:

1. The engine suppresses only the legacy shadow request with cause
   `thermal_upper_to_lower`.
2. `ThermalSystem` previews the replacement from canonical pre-step mass,
   energy, temperature and interface.
3. `Phase3ZoneMassSystem` queues one upper-to-lower energy bundle.
4. The existing atomic limiter caps acceptance by the available upper energy.
5. Accepted, rejected and residual energy are exported as opt-in telemetry.

This preserves the pre-step transaction order and avoids reading live
`RoomModel` state for the canonical request.

## Direct controls

The Godot fixture covers positive transfer, equal and inverted temperatures,
tiny zones, exact equilibrium, repeated application, duplicate rejection and
an upstream energy-depletion conflict. In the conflict control, a prior 700 kJ
upper loss leaves 100 kJ available; the inter-zone bundle accepts only that
100 kJ and rejects the rest without creating energy.

The no-fire OFF/ON control is identical across all 407 shared columns and the
new request remains zero. The Group A OFF control also matches the accepted
F3.2b4 baseline at every matching timestamp and shared column.

## Group A result

The mechanism removes the specific cross-state failure found in F3.2b4:

| Metric | F3.2b4/OFF | F3.2b5a/ON |
|---|---:|---:|
| First lower-hotter-than-upper inversion | about 313 s | none |
| Peak `T_lower - T_upper` | 191.8 C | 0 C |
| Lower-temperature RMSE vs CFAST | 93.2 C | 23.2 C |
| Upper-temperature RMSE vs CFAST | 70.5 C | 70.0 C |
| Pressure RMSE vs CFAST | 506.6 Pa | 498.5 Pa |
| Total-mass RMSE vs CFAST | 8.09 kg | 8.12 kg |
| Total-energy RMSE vs CFAST | 2310.7 kJ | 2317.0 kJ |
| Cumulative accepted inter-zone heat | legacy cross-state | 530.716 kJ |
| Maximum energy residual | not applicable | 0 kJ |

All three Group A shadow O2 checks remain inside their existing envelopes.
The late lower zone is now too cold, reaching about 20-23 C while CFAST remains
near 67 C. Pressure still results from cancellation between large mass and
energy errors. F3.2b5a therefore fixes local inter-zone ownership but does not
close room-to-wall or room-to-ambient energy ownership.

## Verification

| Check | Result |
|---|---|
| Godot 4.7.1 parse with absolute unique log | PASS |
| New structural tests | 10/10 PASS |
| Direct Godot fixture | PASS |
| Focused current/prior Phase 3 tests | 60/60 PASS |
| Broad Phase 3 excluding known tempfile analyzer issue | 363/363 PASS |
| Physics coherence suite | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV suite | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 PASS, 5 VALID_GAP |
| Validation guardrails | 9/10; only R2-1 from dirty motor |
| Official reports or baselines changed | No |

The full pytest run retains the 17 structural failures already present before
F3.2b5a. Additional analyzer failures in this sandbox are caused by denied
`TemporaryDirectory` writes and are not motor findings.

## STOP gate

Decision: **mechanism GO; canonical authority and Group A retirement NO-GO**.

F3.2b5a is suitable to keep as default-OFF shadow infrastructure. It must not
be enabled as production authority. The next gate is F3.2b5b: a pure canonical
wall/ambient exchange preview with explicit reservoir ownership. It must
explain the remaining total-energy error and late lower-zone underheating
without per-case tuning or a pressure clamp.
