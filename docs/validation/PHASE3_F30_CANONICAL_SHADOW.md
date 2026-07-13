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

## Next STOP gate

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

## Next STOP gate

F3.0f must design a persistent canonical transit reservoir before delayed
parcels can be owned. The current shadow state resets each step, while parcel
carve and delivery occur in different steps. The next design must preserve one
parcel identity across source-to-transit and transit-to-destination events,
including refund/headroom handling, without pretending it is immediate flow.
