# Phase 3+ F3.0k.1e delayed parcel atomic shadow lifecycle

Date: 2026-07-16

Commit: `4f718791 feat(validation): add atomic shadow lifecycle for delayed parcels`

## Decision

**GO for the passive delayed-parcel atomic lifecycle. F3.1 authority remains
blocked.**

GasExchangeSystem now gives each delayed parcel one monotonic identity and
emits its exact pre-mutation payload at creation. The canonical shadow limits
the complete payload once at carve, persists that accepted fraction while the
parcel is in flight, and reuses it at delivery, refund or cancellation.
Legacy transport and RoomModel writes are unchanged.

This closes the ownership gap left by F3.0k.1d without treating parcel
creation and resolution as independent inventory sources.

## Lifecycle contract

One parcel carries:

- upper-zone gas mass;
- upper-zone sensible enthalpy;
- signed O2 carry;
- smoke;
- CO;
- CO2;
- HCN;
- HCl;
- acrolein; and
- formaldehyde.

The lifecycle is:

```text
source room
  -- atomic carve using one accepted_fraction -->
in-flight reservoir
  -- delivery/refund/cancellation using the stored fraction -->
destination, source refund or terminal cancellation ledger
```

The accepted fraction is calculated only by the carve bundle. Delivery never
recalculates it from destination inventory. Negative signed O2 is represented
as an explicit reverse route. Duplicate delivery becomes an orphan event and
cannot apply the parcel twice.

Cancellation follows the legacy behavior: a parcel whose destination no
longer exists is discarded. The shadow records that loss in an explicit
terminal cancellation ledger instead of fabricating a source-room refund.

## Conservation telemetry

Shadow-only CSV fields report:

- created, delivered, refunded, cancelled and in-flight gas mass;
- created, delivered, cancelled and in-flight sensible energy;
- created, delivered, cancelled and in-flight O2;
- aggregate in-flight species;
- mass, energy, O2 and species lifecycle residuals; and
- incomplete lifecycle resolutions.

The existing parcel anomaly counters remain authoritative for orphan
deliveries, duplicate IDs and negative balances.

## Runtime evidence

The 120 s `cfast_two_room_door_open` OFF/ON pair ran sequentially with Godot
4.6.3 console and isolated scratch output:

| Metric | OFF | ON |
|---|---:|---:|
| Simulated final time | 120.1 s | 120.1 s |
| Wall-clock time | 22.5 s | 36.3 s |
| CSV rows | 78 | 78 |
| CSV columns | 115 | 296 |

All 115 shared legacy columns were compared over 78 rows: 8,970 cells with
zero differences.

Final lifecycle values:

| Quantity | Value |
|---|---:|
| Active parcels | 514 |
| Created gas | 129.88026501 kg |
| Delivered gas | 93.76759058 kg |
| Refunded/cancelled gas | 0 kg |
| In-flight gas | 36.11267443 kg |
| Gas residual | -1.42e-14 kg |
| Energy residual | 0 kJ |
| O2 residual | 0 kg |
| Species residual | 0 kg |
| Minimum accepted fraction | 1.0 |
| Orphans / duplicate IDs | 0 / 0 |
| Negative balances | 0 |
| Invalid / duplicate bundles | 0 / 0 |
| Unfinalized resolutions | 0 |

A dedicated runtime fixture also proves an inventory-limited carve at
accepted fraction 0.5, persistence across `begin_step()`, exactly-once
delivery, duplicate-delivery rejection and terminal cancellation.

## Performance correction

The first 120 s ON attempt was invalid: it remained at the initial snapshot
for more than eleven minutes. The cause was diagnostic, not physical. Parcel
residual helpers rebuilt the complete in-flight inventory repeatedly for each
room and physics step.

F3.0k.1e now calculates the in-flight payload and all lifecycle residuals once
per step before publishing per-room telemetry. After that correction, the
valid 120 s ON run completed in 36.3 s.

## STOP gate

| Gate | Result |
|---|---|
| Lifecycle structural tests | 13 PASS |
| Related focused tests | 76 PASS |
| All Phase 3 tests | 252 PASS |
| GDScript runtime lifecycle fixture | PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Required validation | 348/353 PASS, 5 VALID_GAP |
| Gap inventory | synchronized |
| Guardrails while motor dirty | 9/10; expected R2-1 freshness only |
| Official reports/baselines/tolerances | unchanged |

The valid full-suite run reported 887 PASS and 19 FAIL. Seventeen are the
known structural baseline, one is from concurrent UI work, and one is the
expected R2-1 dirty-motor integration failure. No Phase 3 test failed.

## Remaining route

F3.0k.1e closes delayed parcels only. Remaining non-HVAC families must still
be reviewed independently:

1. horizontal background diffusion and doorway counterflow;
2. legacy vertical-opening exchange;
3. exterior purge and pressure/leakage boundaries; and
4. suppression and remaining FED/species ownership.

Background/counterflow cannot be assumed to share one gas/enthalpy/O2/species
bundle merely because they use a common exchange coefficient. Their legacy
terms may have different directions and activation conditions. F3.0k.1f must
audit that contract before implementing it.

Zero-O2 flaming remains a separate required regression and continues to block
F3.1 authoritative mode. HVAC remains deferred to F3.5.
