# Phase 3+ F3.0k.1a semantic ownership claims

Date: 2026-07-15

## Decision

**GO for passive semantic telemetry. NO-GO for canonical authority remains.**

F3.0k.1a gives the shadow transaction a shared, pre-mutation identity for a
physical connection and reports when more than one subsystem claims the same
quantity on that connection during one physics step. It does not choose an
owner, suppress a legacy writer, change request acceptance or write any
physical room state.

The runtime result confirms the F3.0k diagnosis: ThermalSystem and
GasExchangeSystem overlap on CO, CO2 and HCN transport across active interior
openings. The same controls show no semantic conflict for gas mass, enthalpy
or O2 because those cross-path quantities are still incompletely claimed.
Zero there is not a conservation proof.

## Semantic key

The registry is reset by `begin_step()`, so the current physics tick is an
implicit transaction boundary. Within that tick, the key is:

```text
connection_id
source_room_id -> destination_room_id
source_zone -> destination_zone
quantity
```

`producer`, `transport_family` and `boundary_kind` are claim metadata and are
deliberately excluded from the key. Including them would prevent two
producers from colliding and would reproduce the ambiguity F3.0k found.

Stable connection namespaces:

| Boundary | Identity |
|---|---|
| Building opening | `opening:<OpeningModel.opening_index>` |
| Exterior purge | `exterior:<room_id>:<mechanism>` |
| Internal interlayer transfer | `room:<room_id>:interlayer` |
| Combustion energy/O2 | `chemical:<room_id>:combustion` |
| Combustion species | `chemical:<room_id>:combustion_species` |

`OpeningModel.opening_index` is assigned deterministically by BuildingModel
and is passed through Thermal doorway events, GES direct/background/vertical
events and delayed parcel creation before their legacy state writes.

Delayed parcels claim transport only at creation. Delivery, refund and
cancellation remain lifecycle resolution of that claim and do not create a
second semantic owner.

## Conflict metric

A semantic conflict exists when one key has positive claims from more than
one producer. The contested amount is:

```text
sum(producer amounts) - max(producer amount)
```

This reports the amount not explained by selecting the largest current claim
as a provisional owner. It is diagnostic only; no amount is removed.

Quantity mask:

| Quantity | Bit |
|---|---:|
| gas mass | 1 |
| enthalpy | 2 |
| O2 | 4 |
| CO | 8 |
| CO2 | 16 |
| HCN | 32 |

Eight shadow-only CSV fields expose claim count, conflict count, mask,
contested mass/energy/O2/species and unknown-connection count. The fields are
present only when `phase3_canonical_zone_shadow_enabled=true`.

## Runtime matrix

All runs used Godot 4.6.3 console, sequentially, with HVAC absent. Scratch
output was isolated from the concurrently open visual editor with `.gdignore`.
One first stairwell CSV was discarded because the editor importer locked it
and truncated logging at 10 s; the isolated retry reached 180 s and is the
only stairwell result used below.

| Case | Final time | Max claims | Max conflicts | Mask | Max contested species | Unknown connection |
|---|---:|---:|---:|---:|---:|---:|
| sealed control | 60 s | 12 | 0 | 0 | 0 kg | 0 |
| two-room doorway | 120 s | 115 | 14 | 56 | 0.00004777 kg | 0 |
| corridor chain | 120 s | 115 | 15 | 56 | 0.00007182 kg | 0 |
| two-floor stairwell | 180 s | 104 | 3 | 56 | 0.00000772 kg | 0 |
| remote CO | 220 s | 137 | 15 | 56 | 0.00392172 kg | 0 |
| partial exterior window | 120 s | 47 | 0 | 0 | 0 kg | 0 |
| PPV post-knockdown | 320 s | 136 | 15 | 56 | 0.00413024 kg | 0 |

Mask 56 is exactly CO + CO2 + HCN. Interior doorway, vertical and PPV cases
therefore reproduce the expected Thermal/GES overlap. The sealed and exterior
window controls produce claims but no conflict, showing that the detector is
not triggered merely by combustion or exterior purge activity.

The OFF/ON pair on `cfast_two_room_door_open` retained 78 rows and all 115
legacy columns byte-for-value identical. OFF had 115 columns; ON has 245.

## STOP gate

| Gate | Result |
|---|---|
| Focused Phase 3 tests | 121 PASS |
| Godot 4.6.3 parse | PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Required validation | 348/353 PASS, 5 VALID_GAP |
| Guardrails while motor is dirty | 9/10; only expected R2-1 freshness FAIL |
| Full `tests/` suite | 818 PASS / 17 historical FAIL + expected R2-1 FAIL |
| Official report values/baselines/tolerances | unchanged; `generated_at` metadata refreshed for R2-1 |

## What this phase does not prove

- It does not identify the physically correct producer merely by size.
- It does not claim gas mass, enthalpy or O2 closure on opening paths.
- It does not make `phase3_shadow_needs_flux_owner_flag` zero.
- It does not resolve CO oxidation, projection/reconcile or zero-O2 flaming.
- It does not include HVAC.

## Next phase: F3.0k.1b

F3.0k.1b should remain passive and default OFF:

1. Choose one provisional semantic owner per interior horizontal, vertical,
   exterior and delayed transport family using the measured keys.
2. Extend the selected event to carry gas mass, enthalpy and O2 together with
   CO/CO2/HCN under one accepted fraction.
3. Add an exact pre-mutation CO sink/CO2 source event for CO oxidation.
4. Report suppressed shadow claims and unresolved quantities; do not suppress
   any legacy physical writer yet.
5. Repeat this HVAC-disabled matrix and require unknown connections to remain
   zero, contract residuals to remain zero and OFF/ON legacy values to remain
   identical.

F3.1 authority remains blocked until F3.0k.1b closes its declared scope and
the zero-O2 extinction regression is fixed. HVAC remains deferred to F3.5.
