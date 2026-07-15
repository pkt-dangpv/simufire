# Phase 3+ F3.0k.1b passive semantic arbitration

Date: 2026-07-15

## Decision

**GO for passive arbitration and the exact CO-oxidation compatibility
contract. NO-GO for complete non-HVAC ownership and F3.1 authority.**

F3.0k.1b assigns a provisional owner to the semantic claims measured in
F3.0k.1a. Arbitration changes only the canonical shadow transaction. Every
legacy writer still runs in the same order and writes the same physical
state. The phase also records the existing CO oxidation as an exact CO sink
and CO2 source without pretending that legacy consumes the required O2.

The audit found that a complete transport bundle cannot yet be built honestly
for all opening families. Delayed parcels have exact gas mass, enthalpy, O2
and species values, but their gas/energy ownership is upper-zone while species
may debit upper and lower zones independently. The current request contract
has one source zone, one destination zone and one accepted fraction. Combining
those values would either reconstruct a flux or apply different physical
routes under a false common fraction. These quantities therefore remain
explicitly unresolved.

## Provisional owner policy

| Boundary | Quantity | Shadow owner |
|---|---|---|
| Interior, vertical or exterior opening | CO, CO2, HCN | `GasExchangeSystem` |
| Interlayer transfer | gas, enthalpy, O2, CO, CO2, HCN | `ThermalSystem` |
| Combustion chemical source | enthalpy | `ThermalSystem` |
| Combustion chemical source | O2 | `OxygenExchangeSystem` |
| Combustion chemical source | CO, CO2, HCN | `CombustionSystem` |
| CO oxidation conversion | CO and CO2 | `SimulationEngine` |

Opening claims from `ThermalSystem` are still recorded in the raw conflict
registry, then suppressed only from shadow request application when GES is the
owner. No `RoomModel` write is suppressed. Raw conflicts therefore remain
visible while the canonical shadow no longer applies both species claims.

Missing gas mass, enthalpy or O2 are classified as `unresolved`; they are not
filled from final stock deltas. An unresolved declaration with no known amount
sets the count and quantity mask but correctly contributes zero to the amount
fields.

Quantity masks retain the F3.0k.1a bits:

| Quantity | Bit |
|---|---:|
| gas mass | 1 |
| enthalpy | 2 |
| O2 | 4 |
| CO | 8 |
| CO2 | 16 |
| HCN | 32 |

## CO oxidation contract

The legacy conversion is recorded before mutation:

```text
CO upper sink = oxidized_kg
CO2 lower compatibility source = oxidized_kg * 44 / 28
carbon residual = CO * 12 / 28 - CO2 * 12 / 44
```

The CO2 source is lower-zone because legacy adds only to bulk `co2_kg` and
does not add to `co2_upper_kg`. This is a compatibility description, not a
claim that hot chemistry physically occurs in the lower layer.

Legacy also omits the stoichiometric O2 sink. F3.0k.1b reports O2 as
unresolved instead of silently adding new physics. In the 300 s oxidation
control, 756 CSV rows contained oxidation, sampled CO sink total was
0.17344488 kg, sampled CO2 source total was 0.27255564 kg and the carbon
residual was exactly zero. These totals are sums of logged step values, not
integrated full-timestep totals.

## Runtime matrix

All cases ran sequentially with Godot 4.6.3 console and HVAC outside the
scope. Scratch outputs were isolated under `runs/phase3_f30k1b/.gdignore`.

| Case | Final time | Raw conflict max | Suppressed mask | Unresolved mask | Unresolved conflicts |
|---|---:|---:|---:|---:|---:|
| sealed control | 60 s | 0 | 0 | 7 | 0 |
| two-room doorway | 120 s | 14 | 56 | 7 | 0 |
| corridor chain | 120 s | 15 | 56 | 7 | 0 |
| two-floor stairwell | 60 s | 1 | 56 | 7 | 0 |
| remote CO | 120 s | 15 | 56 | 7 | 0 |
| partial exterior window | 90 s | 0 | 0 | 7 | 0 |
| PPV post-knockdown | 90 s | 12 | 56 | 7 | 0 |
| CO oxidation | 300 s | 15 | 56 | 7 | 0 |

Mask 56 is CO + CO2 + HCN and mask 7 is gas mass + enthalpy + O2. Zero
unresolved conflicts means every observed multi-producer conflict has a
provisional owner; it does not mean every required transport quantity exists.

The two-room OFF/ON pair retained 78 rows and all 115 shared legacy columns
with zero value differences. OFF has 115 columns and ON has 260.

## STOP gate

| Gate | Result |
|---|---|
| Focused shadow tests | 138 PASS |
| New arbitration tests | 17 PASS |
| Godot 4.6.3 parse and eight runs | PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Required validation | 348/353 PASS, 5 VALID_GAP |
| Artifact integrity | 29 CSV PASS; 9 scratch packages complete |
| Guardrails final | 10/10 PASS after metadata-only `generated_at` refresh |
| Full `tests/` suite | 836 PASS / 17 historical FAIL |
| Official reports/baselines/tolerances | unchanged |

## Why complete ownership is still NO-GO

1. Opening and parcel producers do not expose one atomic multi-zone bundle
   whose mass, enthalpy, O2 and species share one accepted fraction.
2. Gas/energy can travel upper-to-upper while species from the same legacy
   event use upper and lower source inventories.
3. `o2_carry_kg` can be signed, so its direction cannot be inferred from the
   positive species route.
4. CO oxidation lacks the legacy O2 mutation required by its own chemistry.
5. Zero-O2 flaming remains an independent blocker for F3.1 authority.

## Next phase: F3.0k.1c

F3.0k.1c should add an atomic transaction group or route matrix that can apply
multiple zone requests under one accepted fraction. Producers must emit the
exact pre-mutation gas mass, enthalpy, O2 and species routes; the shadow may
not reconstruct them from post-step state. It must also define and test the
stoichiometric O2 sink for CO oxidation as an explicit experimental contract.

F3.1 remains blocked until that bundle closes on the non-HVAC runtime matrix
and the zero-O2 extinction regression is fixed. HVAC remains deferred to F3.5.

## Follow-up status

F3.0k.1c is now complete as a partial GO. The atomic accepted-fraction bundle
and explicit shadow CO/O2 chemistry are delivered, but transport producers
still report unresolved mask 7. Continue with F3.0k.1d producer migration;
see `PHASE3_F30K1C_ATOMIC_BUNDLE.md`.
