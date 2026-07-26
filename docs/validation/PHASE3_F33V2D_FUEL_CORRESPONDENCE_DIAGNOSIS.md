# Phase 3+ F3.3v2d fuel correspondence diagnosis

Date: 2026-07-26

## Decision

F3.3v2d closes as a **diagnostic GO** and a **runtime-authority NO-GO**.

The measured `0.58758433 MJ` live/canonical difference at 180 s is not an
object allocator defect. It is an aggregate source-term semantic mismatch:

- the legacy explicit-object path debits solid inventory from
  `solid_pyrolysis_kw * dt`;
- the canonical products path debits fuel from the smoothed accepted fire
  proposal HRR;
- during fire growth, the ideal pyrolysis curve is above the smoothed
  combustion HRR;
- after both reach the 300 kW cap, the per-step mismatch becomes zero and
  the cumulative difference stays flat.

## Evidence

Input:

- F3.3v2b baseline:
  `runs/phase3_f33v2b/180_on/sim_log.csv`;
- F3.3v2c2 candidate:
  `runs/phase3_f33v2c2/180_on_final/sim_log.csv`;
- Godot 4.7.1, corridor case, 180 s.

Measured:

| Signal | Result |
|---|---:|
| Explicit objects | 7 |
| Eligible objects throughout active rows | 1 |
| Allocator residual | 0 MJ |
| Atomic residual | 0 MJ |
| Aggregate/object residual | 0 MJ |
| Maximum live/canonical inventory difference | 0.58758433 MJ |
| Difference growth window | fire growth, approximately 0-110 s |
| Difference after 120 s | constant |
| Maximum sampled legacy-minus-canonical step debit | 0.00108708 MJ |

Examples from logged active rows:

| t | Legacy pyrolysis debit | Canonical debit | Legacy curve | Canonical proposal |
|---:|---:|---:|---:|---:|
| 10 s | 0.00039167 MJ | 0.00026872 MJ | 4.70 kW | 3.22 kW |
| 40 s | 0.00626667 MJ | 0.00568365 MJ | 75.20 kW | 68.20 kW |
| 80.1 s | 0.02500000 MJ | 0.02391292 MJ | 300.00 kW | 286.96 kW |
| 120.1 s | 0.02500000 MJ | 0.02500000 MJ | 300.00 kW | 300.00 kW |

With one eligible object, object-to-object weighting cannot change aggregate
fuel consumption. The pure allocator and nested atomic commit therefore are
exonerated for this discrepancy.

## Architectural consequence

The current transaction overloads one `fuel_MJ` quantity with two different
meanings:

1. **solid pyrolysis/feedstock debit**, which owns object inventory;
2. **combusted fuel equivalent**, which owns HRR, O2 and species products.

They are equal only for a fully burning, unthrottled fire with no retained
pyrolysis products. Treating them as universally identical makes either the
object inventory or the combustion products physically dishonest.

The next design phase must introduce an explicit split:

- `requested_pyrolysis_debit_MJ`;
- `accepted_pyrolysis_debit_MJ`;
- `combusted_fuel_equivalent_MJ`;
- `retained_pyrolysis_delta_MJ`;
- an energy/inventory bridge residual.

Object fuel must follow accepted pyrolysis debit. O2, gas species and released
energy must follow combusted fuel equivalent. Both remain in one atomic
transaction, but they are not forced to have the same numeric value.

## Constraints for F3.3v2e

- default OFF;
- no live writes;
- no reuse of legacy post-step deltas as canonical authority;
- derive pyrolysis from frozen pre-step fire/object state;
- explicitly conserve object inventory plus retained fuel;
- keep the existing O2/species/energy common fraction;
- reject backdraft, pool release and unsupported smoldering modes until each
  has an explicit owner;
- repeat 180 s before any 300/600 s gate.

Runtime authority and Group C retirement remain blocked.
