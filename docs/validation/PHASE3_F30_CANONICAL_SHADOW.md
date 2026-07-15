# Phase 3+ F3.0 canonical shadow transaction

Date: 2026-07-15

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

F3.0a connects the first authoritative flux producer: plume entrainment in a
room with no active opening. `ZoneFireSolver` creates a pure transfer preview;
Thermal stores that result before applying the exact same object to legacy;
Engine translates it to a lower-to-upper request. Gas mass, sensible enthalpy
and O2 share one accepted fraction.

Other legacy changes continue to set `phase3_shadow_needs_flux_owner_flag`.
Combustion is intentionally deferred: its HRR, O2 and species effects are split
between CombustionSystem, OxygenExchangeSystem and ThermalSystem, so no single
non-duplicated result object exists yet.

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

The OFF CSV schema remains legacy-only. F3.0a ON adds zone residuals, plume
request mass, owned cause count and zero-O2-flame visibility to the original
shadow diagnostics.

## F3.0a runtime proof

| Check | Result |
|---|---|
| OFF vs previous F3.0 checkpoint | 12 rows x 115 columns, 0 differences |
| OFF vs ON, 60 s | 42 rows x 115 shared columns, 0 differences |
| Maximum plume request | 0.02416765 kg/step |
| Rejected plume mass | 0 kg |
| Duplicate owner flag | 0 |
| Owned causes | 1 (`plume_entrainment`) |
| Upper mass residual for owned plume | 0 kg |
| Physics / ILV | 0 FAIL / 0 FAIL |
| Gap inventory | 348/353, 5 VALID_GAP |

The zombie-ILV control `cfast_multi_fuel_couch_tv` produced 7 passive
`phase3_shadow_zero_o2_flame_flag` hits from 120-180 s. The strongest observed
state retained about 971 kW HRR with `o2_upper` around 0.00081. This records the
known defect without changing combustion.

## F3.0b combustion energy contract

F3.0b connected the first combustion contract as energy-only. Thermal computes
`convective_energy_kj` once, records that exact value before legacy mutation,
then applies the same value to `upper_energy_kj`. Engine only translates the
result into an exterior-to-upper shadow request. The contract carries zero gas
mass, zero O2 and no species.

Runtime proof (`cfast_co2_stratification`, 60 s): 42 OFF/ON rows, 115 shared
legacy columns, zero differences, maximum combustion energy request
0.23977973 kJ, two owned causes, zero rejected requests and zero duplicate
owners. `phase3_shadow_combustion_owned_mask=1` explicitly means energy only
(`energy=1`, `O2=2`, `species=4`).

## F3.0c zonal oxygen contract

F3.0c connects only the unambiguous zonal O2 sinks. OxygenExchangeSystem derives
the accepted O2 mass from the exact before/after fractions before assigning
`o2_upper` or `o2_lower`. Engine emits O2-only zone-to-exterior requests and
does not read HRR, Thornton accumulators or post-mutation state.

The legacy bulk sink remains unowned because there is no physical upper/lower
split to apply to the shadow state. This is visible in `fuel_balance_diag_sealed`
and `o2_stoich_diag_sealed`: the shadow request captures the upper sink while
the bulk contribution remains in the residual. In a genuinely sealed plume
case, zonal requests equal `o2_consumed_kg_step_all` exactly.

Runtime proof (`cfast_co2_stratification`, 60 s): 42 OFF/ON rows, 115 shared
legacy columns, zero differences, maximum zonal O2 request 0.00006621 kg,
ownership mask 3, zero rejected requests and zero duplicates. The zombie-ILV
control retained 7 hits from 120-180 s, including about 971 kW at 0.08% upper
O2.

## F3.0d combustion species source contract

`CombustionSystem` now builds one result after the carbon-balance clamp and
before mutating any CO, CO2 or HCN stock. `total_species_kg` preserves the exact
legacy totals; `upper_species_kg` and `lower_species_kg` are the unique zonal
split consumed by shadow. They are views of one generated quantity, not two
independent sources.

CO follows the existing Phase 2G upper fraction. CO2 and HCN enter upper. Pool
release and backdraft are already included in the accepted generation basis
upstream. The OES CO2 tracer, smoke, HCl, acrolein and formaldehyde are excluded.
Engine drains and translates the result only; it contains no yield, phi,
carbon-clamp or retained-fuel formulas.

Runtime proof (`cfast_co2_stratification`, 60 s):

| Check | Result |
|---|---|
| OFF vs F3.0c | 42 rows x 115 columns, 0 differences |
| OFF vs ON | 42 rows x 115 shared columns, 0 differences |
| CO / CO2 / HCN requests | nonzero |
| Rejected species mass | 0 kg |
| Duplicate owner flag | 0 |
| Maximum ownership mask | 7 (energy + O2 + species) |

The 720 s `wood_vc_reference` control produced all three species with zero
duplicates. `cfast_multi_fuel_couch_tv` retained all 7 known zero-O2 flame
hits, so this contract does not hide or fix zombie ILV.

## F3.0e direct doorway species transport

The owned path is the immediate canonical two-zone opening exchange only.
`_move_upper_zone_species` and `_move_lower_zone_species` create one
`doorway_species_direct` result containing source/destination room, explicit
zones and CO/CO2/HCN masses. GasExchangeSystem records it before applying the
same result to legacy delta dictionaries. Engine drains and translates it
without transport physics.

Explicit exclusions are background/counterflow exchange, exterior purge,
HVAC, thermal transport, parcel carve and delayed parcel delivery. In
particular, no request is derived from `*_net_transport_kg_step`, final stocks
or the in-flight ledger.

Runtime proof:

| Check | Result |
|---|---|
| Checkpoint vs OFF | 42 rows x 115 columns, 0 differences |
| OFF vs ON | 42 rows x 115 shared columns, 0 differences |
| Two-room CO / CO2 transfer | source and destination values identical |
| Doorway species rejection | 0 kg |
| Duplicate owner flag | 0 |
| Corridor control | all 6 rooms receive nontrivial direct telemetry |
| Remote-CO control | direct requests nonzero; missing-owner residual remains |
| Zombie ILV | 7 hits, unchanged |

## F3.0f persistent delayed-species reservoir

Each delayed parcel receives a monotonic shadow identity at carve. GES retains
that identity in the legacy queue and emits three lifecycle events:

1. `created`: source stock becomes persistent in-flight stock;
2. `resolved`: the same stock splits into delivered and headroom-refunded mass;
3. `cancelled`: a missing destination terminates the parcel explicitly.

The reservoir in `Phase3ZoneMassSystem` survives `begin_step`; only a full
simulation reset clears it. Events carry exact total and upper CO/CO2/HCN maps
from the legacy parcel. The complementary lower map is deterministic, allowing
separate upper/lower source, delivery and refund requests without collapsing
the journey into an immediate room-to-room transfer.

Runtime proof:

| Control | Created kg | Delivered kg | Refunded kg | In flight kg | Max parcels |
|---|---:|---:|---:|---:|---:|
| Two-room, 60 s | 0.039121 | 0.014704 | 0 | 0.024417 | 109 |
| Corridor, 120 s | 1.408540 | 1.031483 | 0.000152 | 0.376905 | 896 |
| v4 remote CO, 200 s | 6.718308 | 5.121284 | 0.095449 | 1.501574 | 1202 |

All controls had zero lifecycle residual, request rejection, orphan delivery,
duplicate identity and negative balance. OFF vs the F3.0e checkpoint and OFF
vs ON retained 42 rows and 115 identical legacy columns; ON exports 157 total
columns. A sealed control created no parcels, victim incapacitation remained
206.1 s and the zombie-ILV control retained all 7 known hits.

Smoke, irritants, O2 and parcel gas/energy are deliberately excluded. The
reservoir is passive and never writes `RoomModel`.

## F3.0g immediate background/counterflow

F3.0g owns two immediate horizontal paths. Classic background diffusion emits
one signed CO/CO2/HCN transfer before each legacy delta write. CO retains its
source upper fraction; CO2 and HCN are lower-only because this legacy path does
not mutate their upper stocks. No-delay doorway counterflow emits both gross
directions with explicit total and upper masses, preserving the churn that a
net-only event would hide.

The two paths cannot overlap F3.0e/F3.0f: canonical two-zone opening flow
returns before classic background, and counterflow exists only in the
non-delayed branch. At this checkpoint the vertical opening helpers remained
separate and unowned.

Runtime proof:

| Control | Background CO2 kg | Counterflow CO2 kg | Immediate residuals |
|---|---:|---:|---:|
| Two-room, 60 s | 0.000361 | 0 | 0 |
| Corridor, 120 s | 0.003248 | 0 | 0 |
| Sealed multi-room, 60 s | 0.001249 | 0.001671 | 0 |
| v4 remote CO, 200 s | 0.001948 | 0 | 0 |

OFF/ON retained 42 rows and 115 identical legacy columns; ON exports 171
columns. Delayed-parcel and immediate residuals close separately for CO, CO2
and HCN. Small inventory rejection remains visible because other producers are
still absent from shadow. Victim incapacitation remains 206.1 s and all 7
known zero-O2 flame hits remain visible.

## F3.0h legacy vertical-opening species

F3.0h owns `_apply_species_net_exchange` and
`_apply_directed_species_exchange` without changing their legacy arithmetic.
The canonical two-zone opening path returns before these helpers, so their
causes cannot duplicate `doorway_species_direct`.

The net helper computes total and upper CO exactly once, derives lower CO as
`total - upper`, and emits each signed zonal transfer independently. This is
necessary because upper and lower concentration gradients can point toward
opposite rooms. CO2 and HCN are lower-only because the helper changes only
their bulk stocks. The directed helper uses the exact legacy fraction for CO,
CO2 and HCN and preserves the same zonal semantics.

Runtime proof:

| Check | Result |
|---|---|
| Short OFF/ON control | 12/12 rows, 115 shared columns, 0 differences |
| Two-storey OFF/ON control | 793/793 rows, 115 shared columns, 0 differences |
| Real vertical requests | 2,154 |
| Vertical request rejection | 0 kg |
| CO/CO2/HCN residuals | 0 kg |
| Duplicate owner flag | 0 |
| Horizontal negative control | all 12 vertical fields equal 0 |

A deterministic Godot harness additionally exercised both helpers with all
three species. It produced four net and four directed zonal events and one
explicit upper/lower opposite-direction CO marker while legacy OFF/ON delta
dictionaries remained identical.

Shadow mode now exports 183 columns; OFF remains at 115. Exterior purge, HVAC,
thermal transport, smoke, irritants and O2 remain outside this contract. The
known zero-O2 flame defect is still only observed, never corrected or hidden.

## Next STOP gate

F3.0i should audit exterior species purge/removal and connect only an exact
pre-mutation CO/CO2/HCN result with a unique cause. HVAC and thermal transport
remain separate later contracts. No physical authority switch is allowed
until every active path has non-duplicated ownership.
