# Phase 3+ F3.3v2b canonical fire-products routing experiment

Date: 2026-07-26

## Decision

F3.3v2b is **GO as a persistent atomic shadow route, default OFF**.

Runtime authority and retirement of Group C remain **NO-GO**. The route never
writes `RoomModel`, `FireModel` or explicit fuel objects. The corridor case
still reports explicit objects that require an ownership/synchronization
contract before any live activation.

## Implemented contract

The accepted F3.3v2 bundle can replace the legacy inputs of the existing
canonical combustion transaction:

- aggregate persistent fuel debit;
- O2 sink from the selected canonical zone;
- seven species sources into upper;
- convective energy into upper;
- radiative energy through the canonical multisurface solver;
- HRR and `Qc` inputs to the existing F3.3t coupled plume.

No second transport pipeline was added. The existing atomic bundle remains
the final inventory gate. If any route cannot be accepted, its atomic
fraction scales O2, species, convective energy, radiation and persistent fuel
state together.

The effective route requires all parents:

- canonical zone, persistence and combustion;
- F3.3v1 proposal and F3.3v2 products;
- canonical plume and F3.3t coupled plume;
- canonical multisurface energy.

The raw flag is
`phase3_canonical_fire_products_routing_shadow_enabled`, default `false`.
Twelve opt-in CSV fields expose the final atomic fraction and route residuals.

## Measured STOP gate

Scenario:

- input: `runs/phase3_f33t/cases/corridor_on.json`;
- Godot: `4.7.1`;
- duration: 180 s;
- baseline: committed F3.3v2 products;
- candidate: the same stack plus F3.3v2b routing.

| Check | Result |
|---|---:|
| OFF CSV vs committed F3.3v2 | byte-identical |
| Rows baseline / routed | 114 / 114 |
| Candidate columns | 786 |
| Live/legacy columns compared | 115 |
| Live/legacy value differences | 0 |
| Routing-active rows | 18, room 0 only |
| Atomic fraction | 1.0 |
| Fuel route residual | 0 MJ |
| O2 route residual | 0 kg |
| Species route residual | 0 kg |
| Convective route residual | 0 kJ |
| Radiative route residual | 0 kJ |
| Total-energy route residual | 0 kJ |
| Coupled-plume `Qc` residual | 0 kW |
| Explicit-object sync required | yes |

The routed fire consumes 0.32468773 MJ of aggregate shadow fuel over the 18
active samples. Coupled-plume `Qc` ranges from 2.09604694 to 195 kW and is
identical to the accepted F3.3v2 driver at CSV precision.

Reproduce the audit with:

```powershell
python scripts\simulation\analyze_phase3_fire_products_routing.py `
  runs\phase3_f33v2\180_on\sim_log.csv `
  runs\phase3_f33v2b\180_on\sim_log.csv
```

## Acceptance boundary

This phase proves internal transaction ownership, not live authority.

Before a runtime-authority experiment:

1. define atomic synchronization for every explicit fuel object;
2. prove aggregate fuel equals the sum of object inventories;
3. reject unsupported fire modes instead of falling back silently;
4. run 180/300/600 s correspondence with object synchronization enabled;
5. repeat physics, ILV, guardrails, FED and required-baseline review.

F3.3v2b does not authorize case activation, expected/tolerance changes,
CTRL/VALID_GAP changes, FED changes or Group C retirement.

## Regression gate

- Godot 4.7.1 parser: PASS;
- focused atomic/multisurface/plume/products tests: 108 PASS;
- F3.3v2/F3.3v2b tests and analyzer: 17 PASS;
- full pytest: 1278 PASS plus the same 17 pre-existing structural failures;
- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL;
- ILV coherence: 15 PASS / 14 CTRL / 0 FAIL;
- gap inventory: synchronized, 347/353 required PASS, 6 VALID_GAP;
- validation guardrails: 10/10 PASS after refreshing only the
  `generated_at` metadata used by R2-1;
- no official validation report or baseline was regenerated.
