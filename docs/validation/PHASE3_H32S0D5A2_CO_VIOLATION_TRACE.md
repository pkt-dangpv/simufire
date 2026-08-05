# Phase 3 H3.2-S0d5a2 CO Violation Causal Trace

Date: 2026-08-05
Decision: **Root cause confirmed. The residual 18.1 % is a guard artefact, not a
physical writer.** Nothing was repaired; the correction plan is stated, not
implemented.

## Decisive question

The residual after S0d5a was 1 682 of 9 280 CO `upper > bulk` observations. The
question was whether they are (A) new violations by another writer, (B)
inherited persistence, (C) an observation between two writes that finally close,
(D) a clamp or projection altering a stock, (E) incoherent production/oxidation,
or (F) an error of the guard or its sampling point.

**Answer: F, with C as the mechanism.** The guard compares `co_upper > co_kg`
with a strict inequality and no tolerance. Every residual crossing happens in
the degenerate zero-headroom state, where `co_upper == co_kg` exactly, and is
caused by femtogram-scale floating-point rounding in the accumulated bulk sum.
The clamp resolves every one of them inside the same step.

## Trace: writers observed around every CO state mutation

Nine cases, 101 544 observations per writer, with S0d5a ON, the S0d4 zonal guard
ON and the causal trace ON. All diagnostic runs are byte-identical to the plain
run.

| Writer | Observations | **New** | Inherited | Resolved | Max excess kg |
|---|---:|---:|---:|---:|---:|
| `accumulator_application` | 101544 | **1034** | 0 | 0 | 3.90e−11 |
| `ach_infiltration` | 101544 | **648** | 1034 | 0 | 5.03e−11 |
| `final_upper_clamp` | 101544 | 0 | 0 | **1682** | 0 |
| `inherited_pre_room_loop` | 101544 | 0 | 0 | 0 | 0 |
| `parcel_delivery` | 19523 | 0 | 0 | 0 | 0 |
| `parcel_delivery_clamp` | 19523 | 0 | 0 | 0 | 0 |
| `parcel_refund` | 59 | 0 | 0 | 0 | 0 |
| `postfire_species_purge` | 53996 | 0 | 0 | 0 | 0 |
| `pressure_vent_species` | 5162 | 0 | 0 | 0 | 0 |

`1034 + 648 = 1682`, exactly the S0d4 guard count. The accounting closes.

Reading the table:

- **`inherited_pre_room_loop` = 0 new.** Nothing outside `GasExchangeSystem`
  creates a violation, so combustion, CO oxidation and the thermal CO paths are
  cleared. Hypothesis **E is refuted**.
- **Nothing crosses a step boundary.** `final_upper_clamp` resolves 1 682 of
  1 682, and the next step's entry observation finds a valid state. **B is
  refuted**; **C is confirmed as the lifetime**: every violation exists only
  between two writes inside one step.
- **The clamp never creates.** **D is refuted.**
- Parcel delivery, refund, post-fire purge and pressure venting create nothing.
  **A is refuted for every path except the accumulator and ACH.**

## Why the accumulator and ACH "create" violations

Every captured first crossing has the same signature:

```
room=0  writer=accumulator_application  excess=1.63e-18
        d_bulk=-1.63e-18   d_up=0   gap=1.63e-18   headroom=0
```

`headroom = co_kg - co_upper_kg = 0`: the room holds all its CO in the upper
layer. In that state any negative bulk delta of order 1e−18, produced by
ordinary floating-point summation over the eight accumulator contributors,
flips a strict `>` comparison. ACH then re-triggers it because it rescales
`co_upper_kg` by a fraction computed from `co_kg` before the subtraction, which
reintroduces a rounding difference of the same order.

The maximum excess across the whole corpus is **5.03e−11 kg**, thirteen orders
of magnitude below the S0d4 OFF maximum of 2.54e−05 kg.

## Confirmation with a material threshold

A second counter on the same observation, with a `1e−9 kg` threshold, separates
the two populations without hiding either:

| Case | OFF strict | OFF material | ON strict | ON material | ON max excess kg |
|---|---:|---:|---:|---:|---:|
| `v4_co_remote_rooms` | 1010 | 835 | 183 | **0** | 3.37e−11 |
| `victim_fed_incapacitation` | 1252 | 1075 | 194 | **0** | 3.34e−11 |
| `cfast_corridor_chain` | 1175 | 1024 | 168 | **0** | 3.43e−11 |
| `cfast_two_room_door_open` | 1036 | 822 | 236 | **0** | 3.35e−11 |
| `fuel_balance_diag_sealed` | 768 | 547 | 165 | **0** | 3.37e−11 |
| `o2_stoich_diag_sealed` | 768 | 547 | 165 | **0** | 3.37e−11 |
| `g3_gie_ppv_post_knockdown` | 1016 | 841 | 183 | **0** | 3.37e−11 |
| `pvc_curtain_hcl_release` | 1281 | 1115 | 189 | **0** | 3.40e−11 |
| `uk_bungalow_smoke` | 974 | 777 | 199 | **0** | 5.03e−11 |
| **Total** | **9280** | **7583** | **1682** | **0** | |

**S0d5a eliminates 7 583 of 7 583 material CO violations: 100 %, not 81.9 %.**
The 1 682 residual are entirely sub-threshold.

Zero-headroom applications also fall from 19 886 to 12 372, so the correction
additionally reduces how often a room ends a step with all its CO in the upper
layer.

## Correction to the earlier reports

Two statements must be revised:

1. The S0d5a record and commit say "7 598 (81.9 %) attributable, 1 682 (18.1 %)
   with no established provenance". The provenance is now established and the
   material figure is 100 %. The strict counter conflated two populations.
2. The S0d4 record's headline rates (CO 7.5 %, CO2 5.8 %, HCN 5.4 %) are strict
   counts. Measured materially with the same corpus and the fix ON, **CO2 keeps
   4 230 material violations and HCN only 122**. CO2's problem is real and is
   S0d5b's target; HCN's is mostly the same floating-point artefact.

## Scale of the material threshold

`1e-9 kg` is one microgram. In a representative 50 m³ room (60 kg of air) the
engine's own conversion `ppm = kg * 29e6 / (V * 1.2 * 28)` gives

| Quantity | Mass | CO ppm in a 50 m³ room |
|---|---:|---:|
| Material threshold | 1.0e−9 kg | **1.73e−05 ppm** |
| Observed maximum residual excess | 5.03e−11 kg | 8.68e−07 ppm |
| One unit of CSV output precision | 5.8e−05 kg | 1 ppm |

The threshold sits about **4.8 orders of magnitude below one ppm**, the
smallest quantity the CSV can represent, and the observed residual is another
20× below the threshold.

This number is **not a physical tolerance and not a gate**. It does not appear
in any acceptance decision, it never governs physics, and the strict
zero-tolerance counter is kept alongside it so neither population is hidden. It
is calibrated against CO's own floating-point behaviour in this corpus and
**must not be reused for another species without repeating the analysis**: CO2
and HCN have different molar masses, different stock magnitudes and different
accumulator arithmetic.

## Recommended fix, not implemented

Diagnostic only, no physics change:

1. Report the guard on the material threshold as the primary figure, keeping the
   strict count visible as a secondary. Both counters already exist.
2. Re-baseline the S0d4 headline numbers on the material threshold before S0d5b
   starts, so S0d5b targets CO2's 4 230 real violations rather than a mixed
   population.
3. Leave the `upper <= bulk` clamp alone: it is the mechanism that keeps the
   sub-threshold noise from persisting, and S0d5c should only revisit it once
   CO2 is coherent.

No physics change is recommended for the CO residual, because there is no
physical defect left to fix in it.

## STOP evidence

- All nine diagnostic runs are byte-identical to the corresponding plain runs;
  the trace and guard are pure observers.
- Fifteen sequential Godot 4.7.1 fixtures pass, including H1, H2.10, H3.2a,
  H3.2-M atomic acceptance, the coupled bundle shadow, the atomic parcel
  lifecycle and S0a through S0d5a.
- The S0d5a2 fixture covers the default OFF, single capture of a first crossing,
  no finding from a valid state, inheritance not counted as creation, visible
  resolution, a repeat crossing after a resolution, mandatory writer and carried
  context, the material threshold separating noise without hiding the strict
  count, the bounded sample list with unbounded counters, and a pure
  deterministic export. A temporary inverted assertion exits 1 with no PASS
  marker.
- Focused `pytest` for S0a-S0d5a2 is `132 PASS`. The broad Phase 3/guardrail
  selection is `1467 PASS / 2 FAIL`: the expected R2-1 freshness failure from
  the dirty motor and the pre-existing layer-interface export test.
- Physics coherence is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV coherence is
  `15 PASS / 14 CTRL / 0 FAIL`; the gap inventory is unchanged. No Godot process
  remains.
- No official case enables any flag, `sim/validation` is untouched and no
  baseline, expected value, tolerance, CTRL entry or VALID_GAP was modified.
