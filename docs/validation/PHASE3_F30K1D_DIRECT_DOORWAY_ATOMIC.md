# Phase 3+ F3.0k.1d direct doorway atomic shadow bundle

Date: 2026-07-16

## Decision

**GO for the passive direct two-zone doorway bundle. Delayed parcels remain
NO-GO for this phase, and F3.1 authority remains blocked.**

The direct doorway path already exposes one pre-mutation route per opening
segment: source/destination room and zone, transported air mass, zonal
sensible energy, O2 and CO/CO2/HCN. F3.0k.1d forwards that exact result to the
atomic shadow API. Legacy deltas still run unchanged and the shadow never
writes `RoomModel`.

Delayed parcels were not migrated. Their accepted fraction must persist from
carve through flight to delivery, refund or cancellation. Treating creation
and delivery as independent bundles could create or destroy shadow inventory.

## Exact producer contract

`GasExchangeSystem` emits the bundle before applying its legacy species/O2
deltas. Each route contains:

- Bernoulli air mass for the opening segment;
- sensible enthalpy from the source zone's conserved energy per unit gas mass;
- the exact O2 amount used by the legacy doorway delta, including zero when
  the configured multiplier disables O2 carry;
- the exact CO, CO2 and HCN masses already computed for the legacy delta; and
- stable opening, room-direction and zone-direction identity.

The shadow applies one inventory-limited fraction to every quantity. Semantic
ownership of gas mass, enthalpy and O2 is assigned to GES only for the exact
`doorway_bulk` family. Other opening families remain unresolved. Ownership is
order-independent when a provisional unresolved claim is observed before the
exact GES claim.

## Runtime evidence

The 120 s `cfast_two_room_door_open` OFF/ON pair completed sequentially with
Godot 4.6.3:

| Metric | Result |
|---|---:|
| Rows OFF / ON | 78 / 78 |
| Columns OFF / ON | 115 / 277 |
| Shared legacy value differences | 0 |
| Snapshots with doorway atomic bundles | 42 |
| Bundles/routes per active snapshot | 2-8 / 2-8 |
| Minimum accepted fraction | 1.0 |
| Rejected mass/energy/O2/species | 0 |
| Duplicate/invalid bundles | 0 / 0 |
| Unresolved multi-producer conflicts | 0 |

The global unresolved quantity mask can still be 7 because delayed parcels,
background/counterflow, vertical and exterior transport have not migrated.
This phase removes unresolved declarations only from direct doorway events.

## Zero-O2 flaming audit

The known zombie-ILV defect is unchanged and remains visible in the official
ILV controls. `CombustionSystem` can select `o2_lower` in plume-lower mode
while `o2_upper` is near zero; the optional M4
`fire_o2_upper_throttle_enabled` replaces that reference below its critical
threshold, but defaults OFF and cannot be enabled across legacy cases without
reworking expectations that were calibrated on the old HRR behavior.

This is independent of doorway shadow ownership. F3.1 cannot become
authoritative until a dedicated extinction change and regression prove that
flaming HRR cannot persist below the selected physical O2 threshold. No
combustion code or validation envelope was changed in F3.0k.1d.

## Remaining route

1. Give delayed parcels a persistent atomic lifecycle and accepted fraction.
2. Migrate the remaining non-HVAC immediate/vertical/exterior producers.
3. Implement and validate the separate zero-O2 extinction fix.
4. Only then consider F3.1 authoritative sealed mode.

HVAC remains deferred to F3.5.
