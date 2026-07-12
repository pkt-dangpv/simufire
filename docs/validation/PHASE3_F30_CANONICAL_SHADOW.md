# Phase 3+ F3.0 canonical shadow transaction

Date: 2026-07-12

## Scope

F3.0 establishes the transaction boundary without changing simulation physics.
`SimulationEngine` snapshots each room before the legacy fixed step and asks
`Phase3ZoneMassSystem` to compare an independently evolved shadow state with
the legacy state after projection and clamps.

The feature is controlled by `phase3_canonical_zone_shadow_enabled`, default
OFF. It may be activated in `engine_overrides` or with
`run_scenario.py --phase3-canonical-shadow`.

## Request contract

Every request carries a unique id, cause, source/destination room and zone,
gas mass, sensible enthalpy, O2 mass and species masses. An exterior reservoir
uses room id `-1`. Duplicate request ids are rejected and exposed. Requests
larger than source inventory are proportionally limited and rejected mass is
reported.

The shadow component never writes `RoomModel`. It does not read F0 stage deltas,
projection residuals or other post-mutation observations as physical inputs.

## Current ownership

F3.0 has no authoritative flux producer. The empty transaction is useful: any
legacy mass or energy change appears as a residual and sets
`phase3_shadow_needs_flux_owner_flag`. This prevents an incomplete ledger from
presenting numerical closure as physical conservation.

F3.0a will connect one sealed-room producer at a time. A producer is accepted
only when it exposes a value before mutating legacy state and cannot debit the
same inventory through a second adapter.

## Runtime proof

`cfast_co2_stratification`, 10 s, was run OFF and ON:

| Check | Result |
|---|---|
| Rows | 12 OFF / 12 ON |
| Shared legacy columns | 115 |
| Legacy value differences | 0 |
| Shadow-only columns | 10 |
| Godot parse | PASS |
| Focused Phase 3 tests | 34 PASS |
| Physics suite | 0 FAIL |
| ILV suite | 0 FAIL |
| Gap inventory | 348/353, 5 VALID_GAP |

The OFF CSV schema remains legacy-only. ON adds state, residual, request count,
rejected mass, duplicate-owner and missing-owner diagnostics.

## Next STOP gate

F3.0a must demonstrate a real request from a pre-mutation physical output,
request-level conservation, zero duplicate ownership and unchanged legacy
outputs. It must stop if closure depends on F0 observed deltas or a
projection/clamp compensation term.
