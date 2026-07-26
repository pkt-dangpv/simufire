# Phase 3+ F3.3v2c2 fuel-object shadow synchronization experiment

Date: 2026-07-26

## Decision

F3.3v2c2 is **GO as a persistent, default-OFF shadow ledger**.

Runtime authority and Group C retirement remain **NO-GO**. The canonical
ledger closes exactly, but differs from the live object path by up to
0.58758433 MJ at 180 s. That difference must be owned by a later migration
phase, not hidden by a tolerance.

## Implemented contract

- `phase3_canonical_fuel_object_sync_shadow_enabled`, default `false`;
- stable object identity by non-empty unique `FuelObjectModel.id`;
- legacy proxies excluded when explicit objects exist;
- deterministic sorted ledger;
- bounded weighted debit and leftover redistribution;
- nested interpolation with the same atomic fraction as O2, species and
  energy;
- committed aggregate fuel derived from the committed object sum;
- fail-closed unsupported result for invalid identity or positive debit
  without an eligible owner;
- 20 opt-in CSV fields and a reproducible analyzer.

No `FuelObjectModel`, `FireModel` or `RoomModel` is written by this path.

## Measured STOP gate

Input: corridor shadow stack, Godot 4.7.1, 180 s.

| Check | Result |
|---|---:|
| OFF vs F3.3v2b | byte-identical |
| Rows baseline / ON | 114 / 114 |
| ON columns | 806 |
| Live columns compared | 115 |
| Live differences | 0 |
| Active object-sync rows | 18, room 0 |
| Object count | 7 |
| Identity signatures | 1 stable value |
| Eligible objects | 1 |
| Unsupported/rejected rows | 0 |
| Seed residual | 0 MJ |
| Allocation residual | 0 MJ |
| Atomic residual | 0 MJ |
| Aggregate/object residual | 0 MJ |
| Maximum live/canonical difference | 0.58758433 MJ |

The existing F3.3v2b fuel/O2/species/energy/plume route residuals also remain
zero.

Reproduce:

```powershell
python scripts\simulation\analyze_phase3_fuel_object_sync.py `
  runs\phase3_f33v2b\180_on\sim_log.csv `
  runs\phase3_f33v2c2\180_on_final\sim_log.csv
```

## Verification

- Godot 4.7.1 parser and direct fixture: PASS;
- focused F3.3v2b/v2c tests: 14 PASS;
- full pytest: 1284 PASS plus the same 17 pre-existing structural failures;
- post-commit guardrails: 10/10 PASS, including reports freshness R2-1 and
  `test_exit0_real_json`;
- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL;
- ILV coherence: 15 PASS / 14 CTRL / 0 FAIL;
- no official case, physical report, expected, tolerance, CTRL or VALID_GAP
  changed.

## Remaining boundary

The live path consumes slightly more fuel because its object weights and
state transitions remain authoritative. F3.3v2c2 deliberately records that
difference.

Next phase F3.3v2d must diagnose the delta by object and decide which
canonical object-state inputs are still missing. It must not write live fuel
until 180/300/600 s correspondence demonstrates bounded object-by-object
agreement and all unsupported modes are explicit.
