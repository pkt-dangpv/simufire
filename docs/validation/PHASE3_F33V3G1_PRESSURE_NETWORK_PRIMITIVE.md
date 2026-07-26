# Phase 3+ F3.3v3g1 pressure-network relaxation primitive

Date: 2026-07-26

## Decision

F3.3v3g1 is **pure primitive GO**. Runtime wiring remains forbidden.

Added:

```text
compute_fixed_gross_pressure_network_relaxation(...)
```

The function operates only on dictionaries and arrays supplied by the caller.
It does not read snapshots, persistent ledgers, rooms, openings or engine
flags, and it has no runtime call site.

## Contract

For one connected-room component, the function:

1. derives pressure after base opening routes;
2. derives the pressure response from base to full fixed-gross routes;
3. minimizes the sum of squared connection pressure differences;
4. rejects a proposal whose objective derivative is non-descending;
5. prevents pressure-sign crossing in one step;
6. applies the independent source-inventory fraction;
7. verifies that the accepted objective does not increase.

It reports the unconstrained optimum, crossing bound, inventory bound,
accepted fraction, pre/post objective, derivative, connection counts and
limiting reason.

Malformed or non-finite input fails closed with `fraction = 0`.

## Verification

Godot 4.7.1 runtime fixture covers:

- one connection reaching equilibrium;
- a three-room chain;
- a non-descending proposal remaining dormant;
- an inventory-limited proposal;
- independent disconnected-component calls;
- opening-order invariance;
- zero pressure response;
- malformed input.

Result:

```text
PHASE3_F33V3G1_PRESSURE_NETWORK_RELAXATION_PASS
```

Focused structural chain: 23/23 PASS. The Windows root-certificate warning
printed by headless Godot is unrelated to the fixture and does not change its
exit code.

## Scope proof

- no `SimulationEngine.gd` change;
- no exported flag;
- no call from `queue_canonical_interior_opening_requests`;
- no state, report, case, expected or tolerance change;
- no FED, HVAC, legacy physics or visual change.

## Next gate

F3.3v3g2 may wire a **passive default-OFF preview only**.

It must:

- partition descriptors into connected components;
- build full fixed-gross routes from raw pressure demand;
- compute actual base and full route pressure deltas;
- call this primitive once per component;
- blend complete atomic payloads with the accepted component fraction;
- emit objective, bound and predicted-inventory telemetry;
- never append those preview routes to the canonical bundle.

The first runtime STOP remains 180 s OFF/ON invariance. Persistent shadow
state is a later phase.
