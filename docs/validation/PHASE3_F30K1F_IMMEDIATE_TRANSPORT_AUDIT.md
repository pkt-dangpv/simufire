# Phase 3+ F3.0k.1f immediate horizontal transport audit

Date: 2026-07-16

## Decision

**NO-GO for migrating horizontal background diffusion or doorway counterflow
to one complete atomic gas/enthalpy/O2/species bundle. No motor code was
changed.**

Both paths already expose exact pre-mutation CO/CO2/HCN transfers and their
species-only shadow contracts close. They do not expose one physical payload
whose gas mass, sensible enthalpy, O2 and species share one direction, one
zonal route and one accepted fraction.

Using their shared exchange coefficient as if it were transported gas mass
would add a shadow flux that the legacy state does not apply. That would make
the canonical ledger non-circular in form but physically invented in content.

## Source contracts

### Background species exchange

Producer:

`GasExchangeSystem._apply_background_species_exchange()`

Semantic metadata:

| Field | Value |
|---|---|
| Producer | `GasExchangeSystem` |
| Transport family | `background_exchange` |
| Boundary | `interior_opening` |
| Connection | `opening:<opening_index>` |
| Source/destination | selected independently from each signed concentration gradient |

The path calculates `exchange_air_kg`, but legacy uses it as a turnover
coefficient:

- smoke, CO, CO2, HCN and irritants use independent concentration gradients;
- CO can split between upper and lower stock;
- legacy CO2 and HCN writes are bulk-only and map to lower compatibility
  routes in the shadow;
- O2 uses another signed gradient multiplied by
  `background_o2_exchange_multiplier`, which is zero by default; and
- gas/energy transfer is conditional on a temperature difference and moves
  only upper gas from the hotter room to the colder room.

Therefore species, O2 and upper enthalpy can have different directions and
activation conditions during the same opening step.

### Doorway species counterflow

Producer:

`GasExchangeSystem.step_smoke()`, no-delay branch.

Semantic metadata:

| Field | Value |
|---|---|
| Producer | `GasExchangeSystem` |
| Transport family | `doorway_counterflow` |
| Boundary | `interior_opening` |
| Connection | `opening:<opening_index>` |
| Source/destination | two explicit gross directions per species |

The no-delay branch calculates a symmetric `exchange_air_mass_kg` and uses it
to exchange O2 and species in both directions. Legacy does not debit and
credit upper/lower gas mass or sensible enthalpy for those gross air streams.
Adding paired gas routes to the shadow would therefore describe a new physical
model rather than the exact legacy mutation.

The counterflow is distinct from `doorway_bulk` and `delayed_parcel`: it is an
additional mixing term after the direct smoke transfer. It can share the same
opening and direction, so semantic overlap must remain visible.

## Runtime audit

All runs were Godot 4.6.3 console, headless, sequential and isolated under
`runs/phase3_f30k1f`. No official report was modified.

| Control | Final time | Background CO/CO2/HCN | Counterflow | Vertical | Exterior purge | Max unresolved claims |
|---|---:|---:|---:|---:|---:|---:|
| two-room | 120.1 s | 0.00261260 kg | 0 | 0 | 0.00287423 kg | 33 |
| corridor | 60.0 s | 0.00056664 kg | 0 | 0 | 0.00035991 kg | 33 |
| stairwell | 60.0 s | 0.00018971 kg | 0 | 0.00000018 kg | 0.00171203 kg | 63 |
| partial window | 60.0 s | 0 | 0 | 0 | 0.14139720 kg | 12 |
| PPV | 90.1 s | 0.00197499 kg | 0 | 0 | 0.00154802 kg | 36 |
| no-delay counterflow control | 60.0 s | 0.00080623 kg | 0.00059980 kg | 0 | present | 36 |

Every control retained unresolved quantity mask 7: gas mass + enthalpy + O2.
The corresponding unresolved amounts remain zero because no exact common
payload exists; the mask is a declaration of missing ownership, not an
estimated flux.

The no-delay control executed 11,622 immediate species transfers. CO, CO2 and
HCN debit/credit residuals were exactly zero. It reported zero unknown
connections. This proves the existing species contract and identity are
working; it does not provide the missing gas/energy contract.

Delayed parcel residuals remained zero in every case that exercised parcels.

## Family disposition

| Family | Current exact contract | Missing for complete bundle | Decision |
|---|---|---|---|
| Direct doorway bulk | gas, energy, O2, species | none in declared scope | Closed F3.0k.1d |
| Delayed parcel | persistent gas, energy, O2, smoke and species | none in declared lifecycle | Closed F3.0k.1e |
| Background diffusion | signed species; conditional upper gas/energy; optional bulk O2 | one common route/fraction | NO-GO |
| Doorway counterflow | gross bidirectional species and O2 | legacy gas mass and enthalpy mutation | NO-GO |
| Vertical net/directed | explicit zonal species and opening flow masses | exact enthalpy and consistent zonal O2 bundle | Next audit candidate |
| Exterior purge/pressure | exact species removal | canonical gas/energy/pressure boundary | Defer to F3.2 |
| HVAC | legacy only | redesign specification | Defer to F3.5 |

## Next step

Audit vertical net/directed exchange as F3.0k.1g. Its opening solver already
calculates upward and downward gas masses, so it is the smallest remaining
family with a plausible physical carrier. Before implementation, verify:

1. the exact pre-mutation enthalpy associated with each direction;
2. dimensional correctness and zonal ownership of the O2 term;
3. that vertical background and directed helpers do not represent the same
   event twice; and
4. that smoke and all irritants can join the same routes without inference.

If any quantity must be reconstructed from final state, stop at design.
Exterior pressure/leakage remains F3.2. Zero-O2 flaming remains the separate
blocker for F3.1 authority. HVAC remains deferred to F3.5.
