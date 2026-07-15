# Phase 3+ F3.0k.1c atomic shadow bundle

Date: 2026-07-15

## Decision

**GO for the passive atomic transaction primitive and explicit shadow CO
oxidation chemistry. NO-GO for complete non-HVAC ownership or F3.1
authority.**

F3.0k.1c adds the missing ability to bind several zonal routes to one
inventory-limited accepted fraction. The primitive is used first for CO
oxidation because that conversion has an exact pre-mutation reactant/product
bundle. Opening and delayed-parcel producers are not migrated in this phase:
they must emit their exact gas, enthalpy, O2 and zonal species routes before
the unresolved opening mask can be retired.

The canonical system remains a shadow. It never writes RoomModel, does not
change FED, and does not suppress any legacy physical writer.

## Atomic contract

An atomic bundle has one identity, one cause and an ordered route list. Every
route carries non-negative values for:

- source and destination room;
- source and destination zone;
- gas mass;
- sensible enthalpy;
- O2; and
- CO, CO2 and HCN.

Before applying any route, the shadow:

1. validates every internal source and destination;
2. aggregates all demands by source room and source zone;
3. calculates one fraction limited by available gas, energy, O2 and each
   species; and
4. applies every route with exactly that fraction, preserving transaction
   order relative to legacy single-route requests.

Invalid, duplicate and rejected quantities remain visible in CSV telemetry.
Negative or unknown quantities invalidate the bundle instead of changing
direction silently. Exterior reservoirs are unbounded, but all internal
sources are inventory limited.

## CO oxidation contract

The experimental shadow chemistry is:

    CO + 0.5 O2 -> CO2
    O2 sink  = oxidized_CO * 16 / 28
    CO2 gain = oxidized_CO * 44 / 28

The CO and O2 sinks share one upper-zone reactant route. The CO2 product is an
exterior-to-upper route in the same bundle, so it receives the same accepted
fraction. Carbon and oxygen residuals are reported separately.

Legacy behavior is intentionally unchanged: SimulationEngine still removes
upper/bulk CO and adds only bulk CO2, and still does not consume legacy O2.
phase3_shadow_co_oxidation_legacy_lower_co2_kg_step records that compatibility
split as telemetry only; the shadow does not apply a second lower CO2 source.

## Runtime results

All valid runs used Godot 4.6.3 console, headless and sequentially, with
scratch outputs under runs/phase3_f30k1c. HVAC was excluded.

| Control | Duration | Raw conflict max | Suppressed mask | Unresolved mask | Atomic bundles/routes max |
|---|---:|---:|---:|---:|---:|
| sealed | 60 s | 0 | 0 | 7 | 0 / 0 |
| two-room doorway | 120 s | 14 | 56 | 7 | 0 / 0 |
| corridor chain | 120 s | 15 | 56 | 7 | 0 / 0 |
| two-floor stairwell | 60 s | 1 | 56 | 7 | 0 / 0 |
| remote CO | 120 s | 15 | 56 | 7 | 0 / 0 |
| partial exterior window | 90 s | 0 | 0 | 7 | 0 / 0 |
| PPV post-knockdown | 90 s | 12 | 56 | 7 | 0 / 0 |
| CO oxidation | 120 s | 15 | 56 | 7 | 2 / 4 |

Mask 56 remains the suppressed parallel Thermal opening-species path. Mask 7
is still unresolved gas mass + enthalpy + O2 on opening/parcel paths. Every
case has zero unresolved multi-producer conflicts; missing quantities remain
visible rather than reconstructed.

The two-room OFF/ON pair retained 78 rows and all 115 legacy columns with zero
value differences. OFF has 115 columns and ON has 277.

The 120 s CO-oxidation OFF/ON pair retained 726 rows and all 115 legacy
columns with zero differences. Logged active rows report:

| Quantity | Sampled total |
|---|---:|
| requested/accepted CO sink | 0.05037876 kg |
| accepted CO2 source | 0.07916658 kg |
| requested/accepted O2 sink | 0.02878782 kg |
| rejected O2 | 0 kg |
| oxygen residual | 0 kg |
| minimum accepted fraction | 1.0 |

A separate runtime harness exercised an energy-limited multi-route bundle and
an O2-limited CO conversion at fraction 0.5. Both applied one common fraction
and left the source/destination RoomModel objects unchanged.

One 300 s CO-oxidation ON attempt reached 282 s and then hit the runner's
420 s timeout. It is invalid evidence. The valid 120 s control completed in
95.7 s versus 38.0 s OFF, so shadow performance on long oxidation runs is a
watch item. No retry was launched after a GUI/editor Godot process appeared.

## STOP gate

| Gate | Result |
|---|---|
| New/updated atomic tests | 35 PASS |
| Focused Phase 3 tests | 225 PASS |
| Godot parse before final defensive check | PASS |
| Runtime atomic harness | PASS |
| Valid non-HVAC runtime matrix | 8/8 PASS |
| OFF/ON legacy invariance | zero differences |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Required validation | 348/353 PASS, 5 VALID_GAP |
| Artifact integrity | 29 CSV PASS; 11 scratch packages complete |
| Full pytest | 867 PASS / 18 FAIL |
| Official reports/baselines/tolerances | unchanged |

Of the 18 full-suite failures, 17 are the historical structural failures
already present at the session start. The additional failure is the expected
R2-1 freshness gate while motor files are dirty. Guardrails are therefore
9/10 until a later approved commit/metadata refresh.

## Why F3.1 remains blocked

1. Every transport control still reports unresolved mask 7.
2. Direct doorway, background, vertical, exterior and delayed parcel
   producers have not yet emitted complete atomic bundles.
3. The shadow still has no authority over legacy physical state.
4. Zero-O2 flaming remains a separate required motor regression.
5. The long CO-oxidation shadow run has a performance watch item.

## Next phase: F3.0k.1d producer migration

Migrate one exact non-HVAC transport family to the delivered atomic API. Start
with the producer that can expose all pre-mutation routes without inference;
delayed parcels are the leading candidate but require a persistent accepted
fraction across creation, flight, delivery and refund. If that lifecycle
cannot be made exact in one phase, use the direct doorway bundle first.

The next STOP gate must prove that one active transport family removes the
corresponding mask-7 claims, preserves parcel/species conservation, keeps
OFF/ON legacy values identical and does not use projection or post-mutation
deltas. HVAC remains deferred to F3.5.
