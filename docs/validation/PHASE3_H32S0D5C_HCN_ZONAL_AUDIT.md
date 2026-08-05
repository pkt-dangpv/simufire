# Phase 3 H3.2-S0d5c HCN Zonal Transport Audit

Date: 2026-08-05
Decision: **NO-GO for an HCN zonal fix. There is no material defect to correct.**

The same structural bulk-only paths that broke CO2 exist for HCN, and the same
causal writer is confirmed by direct trace. But every HCN violation in the
corpus is floating-point noise: the largest is `3.12e-09 kg`, thirty-two times
below HCN's own derived material threshold and roughly five orders of magnitude
below a 1 % change in `FED_HCN`. No flag was added and no physics was changed.

O2 stays pending, HVAC stays deferred, the `upper <= bulk` clamp audit stays for
later, no integrator exists, H3.2-S stays open, H3.2b and H3.3 are not started
and no runtime authority was granted.

## HCN inventory by path

| Path | Amount sized from | Bulk | Upper | Declared zone | Can widen the gap? |
|---|---|---|---|---|---|
| background exchange | **bulk** | debit/credit | **untouched** | lower-to-lower, shadow records `0.0` upper | yes |
| vertical net exchange | **bulk** | debit/credit | **untouched** | lower-to-lower, shadow label `"lower"` | yes |
| vertical directed exchange | **bulk** | debit/credit | **untouched** | lower-to-lower, shadow label `"lower","lower"` | yes |
| **PPV inlet dilution** | bulk × `mix_frac` | debit | **untouched** | none declared | yes |
| **PPV exhaust** | bulk × `ex_frac` | debit | **untouched** | none declared | yes |
| immediate transport / parcel enqueue | bulk for the total, upper × `hcn_cut_ratio` for the upper part | debit | debit | mixed band | yes, the gap grows since the upper debit is the smaller one |
| parcel delivery | parcel inventory | credit | credit | upper | no |
| parcel refund | `hcn_parcel - hcn_headroom` | credit | credit through a second `minf` cap | upper | partially |
| doorway counterflow | proportional upper share | signed | signed | both | no |
| two-zone opening | per zone | per zone | per zone | explicit | no |
| exterior smoke vent, natural-vent purge, pressure vent | proportional | debit | debit | both | no |
| ACH, post-fire purge | proportional | debit | scaled | both | no |
| combustion production | — | outside `GasExchangeSystem` | — | — | not observed |

Note that HCN differs from CO in the transport path: it *does* debit its upper
stock, unlike CO which debited bulk only. It differs from CO2 in PPV: both PPV
branches are bulk-only for HCN, and PPV was never exonerated for HCN before this
audit, so a new `ppv_exhaust_species` observation point was added.

## Causal trace

The invariant `hcn_upper <= hcn_kg` is observed immediately after every writer of
HCN room state, with the state indexed per species and room. Twelve cases ranked
by HCN exposure, 214 566 observations per writer:

| Writer | Observations | **NEW** | Inherited | Resolved |
|---|---:|---:|---:|---:|
| `accumulator_application` | 214566 | **5263** | 0 | 0 |
| `ach_infiltration` | 214566 | **1891** | 5263 | 0 |
| `final_upper_clamp` | 214566 | 0 | 0 | **7154** |
| `inherited_pre_room_loop` | 214566 | **0** | 0 | 0 |
| `postfire_species_purge` | 65532 | 0 | 0 | 0 |
| `pressure_vent_species` | 21000 | 0 | 0 | 0 |
| `parcel_delivery` | 76263 | 0 | 0 | 0 |
| `parcel_delivery_clamp` | 76263 | 0 | 0 | 0 |
| `parcel_refund` | 8957 | 0 | 0 | 0 |

`accumulator_application` and `ach_infiltration` are the only creators, exactly
as for CO and CO2. `inherited_pre_room_loop` records zero, which clears
combustion and the thermal HCN paths. Parcels, purges, pressure venting and PPV
create none — PPV in particular is now measured, not assumed.

Every captured first crossing carries the same signature as CO and CO2:

```
room=0  writer=accumulator_application  excess=2.679e-19
        d_bulk=-2.679e-19   d_up=0   gap=2.679e-19   headroom=0
```

Zero headroom, zero upper delta, a bulk delta at 1e-19. This is the
zero-headroom floating-point pattern S0d5a2 established, not a physical
over-export.

## HCN material threshold, derived from scratch

The upper bound is deliberately **not** anchored on a rounded ppm: HCN is highly
toxic and `FED_HCN` is strongly non-linear, so a small mass can matter.

| Step | Value | Basis |
|---|---:|---|
| Observed FP noise maximum | 3.12e−09 kg | measured across the 12 ranked cases |
| Lower bound (≥ 10× noise) | 3.12e−08 kg | — |
| 1 ppm HCN in a 50 m³ room | 5.586e−05 kg | 27 g/mol, `ppm = kg·29e6/(V·1.2·27)` |
| Mass changing `FED_HCN` by 1 % | 2.4e−05 kg | Purser HCN response ≈ 1/43 per ppm near incapacitation, so 1 % ≈ 0.43 ppm |
| Upper bound (≤ 1/100 of that) | 2.4e−07 kg | — |
| **Chosen** | **1.0e−07 kg** | 32× above the noise, 240× below a 1 % FED_HCN change, 1/558 of one ppm |

`_material_eps_for("hcn")` returns this value; species without their own
derivation still return `0.0` so nothing inherits another species' threshold.
Strict and material counters are always reported together.

## Result: no material HCN violations exist

Re-measured on the five highest-HCN cases with HCN's own threshold:

| Case | HCN strict | **HCN material** | Max excess kg | CO2 s/m | CO s/m |
|---|---:|---:|---:|---:|---:|
| `wood_vc_reference` (highest HCN) | 1314 | **0** | 1.523e−09 | 464 / 0 | 576 / 0 |
| `victim_fed_incapacitation` | 416 | **0** | 8.215e−10 | 105 / 0 | 194 / 0 |
| `pu_sofa_fec_incapacitation` | 437 | **0** | 8.163e−10 | 107 / 0 | 190 / 0 |
| `cfast_slow_growth_sealed` | 830 | **0** | 3.122e−09 | 471 / 0 | 646 / 0 |
| `cfast_single_room_closed` (control) | 892 | **0** | 2.013e−09 | 285 / 0 | 346 / 0 |
| **Total** | **3889** | **0** | 3.122e−09 | | |

Across the full 12-case ranked set the strict total is 7 154 and the material
total is **0**. The margin between the threshold and the worst observed excess
is **32×**.

## Why NO-GO

The GO criteria for this phase require the candidate to *eliminate material
violations in scope*. There are none. Shipping a physics change, even behind a
flag, would:

- add a flag and a maintenance surface for a defect that never becomes material;
- require a baseline review, since any change to HCN moves `FED_HCN` and the FIC
  population;
- risk moving the defect while fixing nothing measurable.

## Why the difference from CO2 is real, not an artefact of the threshold

The structural defect is identical, but the magnitudes are not. CO2 stocks in
these scenarios are of order 1 kg, so a bulk-sized over-export of an almost-empty
lower zone produces excesses up to ~1e−05 kg — material by any reasonable
anchor. HCN stocks are three orders of magnitude smaller, so the same relative
error lands at 1e−09 kg. Even the CO threshold of 1e−09 kg would flag only a
fraction of the HCN crossings, and HCN's own FED-anchored threshold flags none.

This is precisely why thresholds are derived per species and never copied.

## Standing risk

The bulk-only HCN paths remain structurally wrong. If HCN yields or scenario
durations grow substantially, they could become material. The guard now reports
HCN strict and material side by side in every diagnostic run, so a future
regression would surface as a non-zero material count rather than silently.

## Instrumentation added

Diagnostic only, default OFF, no physics change:

- HCN added to the per-species causal trace at every HCN room-state writer,
  including a new `ppv_exhaust_species` observation point that did not exist.
- `ZONAL_GUARD_MATERIAL_EPS_HCN_KG` and its `_material_eps_for` branch.
- The threshold declaration exported alongside the counters now covers all three
  derived species.
