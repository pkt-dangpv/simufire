# Phase 3 H3.2-S0d5b CO2 Zonal Transport Consistency

Date: 2026-08-05
Decision: **GO to keep `phase3_co2_zonal_transport_consistency_enabled` as an
experimental, default-OFF flag. NO-GO to promote it.**

HCN and O2 stay pending, HVAC stays deferred, S0d5c is not started, no
integrator exists, H3.2-S stays open, H3.2b and H3.3 are not started and no
runtime authority was granted.

## CO2 inventory by path

| Path | Amount sized from | Bulk | Upper | Declared zone | Can create `upper > bulk`? |
|---|---|---|---|---|---|
| **background exchange** | **bulk concentration** | debit/credit | **untouched** | lower-to-lower: shadow event records `0.0` upper | **yes** |
| **vertical net exchange** | **bulk** (`_compute_net_pair`) | debit/credit | **untouched** | lower-to-lower: shadow label `"lower"` | **yes** |
| **vertical directed exchange** | **bulk** (`co2_kg * frac`) | debit/credit | **untouched** | lower-to-lower: shadow label `"lower","lower"` | **yes** |
| immediate transport / parcel enqueue | upper, with `co2_cut_ratio` | debit | debit | upper | no |
| parcel delivery / refund | parcel inventory | credit | credit | upper | no |
| doorway counterflow | proportional upper share | signed | signed | both | no |
| two-zone opening | per zone | per zone | per zone | explicit | no |
| exterior smoke vent, natural-vent purge | proportional | debit | debit | both | no |
| ACH, post-fire purge, PPV | proportional | debit | scaled | both | no |
| combustion production | — | outside `GasExchangeSystem` | — | — | not observed |

## Direct causal attribution by writer

The CO2 invariant `co2_upper <= co2_kg` is observed immediately after every
writer of CO2 room state, with the state indexed per species and room so new
creations, inherited states and resolutions are counted separately. Twelve
cases, 177 163 observations per writer:

| Writer | Observations | **NEW OFF** | **NEW ON** | Inherited OFF | Resolved OFF |
|---|---:|---:|---:|---:|---:|
| `accumulator_application` | 177163 | **6242** | **0** | 0 | 0 |
| `ach_infiltration` | 177163 | 219 | 1644 | 6242 | 0 |
| `final_upper_clamp` | 177163 | 0 | 0 | 0 | **6461** |
| `inherited_pre_room_loop` | 177163 | **0** | 0 | 0 | 0 |
| `parcel_delivery` | 51574 | 0 | 0 | 0 | 0 |
| `parcel_delivery_clamp` | 51574 | 0 | 0 | 0 | 0 |
| `parcel_refund` | 234 | 0 | 0 | 0 | 0 |
| `postfire_species_purge` | 66182 | 0 | 0 | 0 | 0 |
| `pressure_vent_species` | 15361 | 0 | 0 | 0 | 0 |

This is the direct attribution, not an inference from the residual
disappearing:

- **`accumulator_application` is the causal writer**: 6 242 of 6 461 first
  crossings, and it drops to **zero** with the flag on.
- `inherited_pre_room_loop` records **zero** new violations, so nothing outside
  `GasExchangeSystem` — combustion, CO oxidation, the thermal CO2 paths —
  creates one.
- Parcel delivery, refund, post-fire purge and pressure venting create none.
- The final clamp only ever resolves.
- The 219 OFF crossings at `ach_infiltration` come exclusively from
  `cfast_single_room_closed`; with the flag on the residual moves to that writer
  at floating-point scale.

The single-room control is decisive on its own: with no inter-room transport at
all, `accumulator_application` still creates 509 violations OFF and 0 ON, which
confirms the defect is the bulk sizing of the in-room background exchange rather
than any multi-room artefact.

## Root cause: case B with a sizing defect

The three flagged paths **declare** a lower-to-lower movement. Mutating bulk
only is the *correct* encoding for that: with `lower = bulk - upper`, changing
bulk while upper stays puts the whole delta in the lower zone.

The defect is the **sizing**: all three compute the amount from the **bulk**
stock. When most CO2 lives in the upper layer, the path exports more CO2 than
the lower zone actually holds, the derived lower stock goes negative and
`upper > bulk` appears. The unowned final clamp then repairs it.

Options A, C and D were rejected on evidence: the code and its shadow ledger
both declare the zone, so there is no need to invent a split (C) and no absence
of information (D), and treating the paths as upper transport (A) would
contradict the recorded `0.0` upper movement.

## Change

One flag, three guarded statements, no new formula:

```
net_co2_a_to_b = _cap_co2_lower_transfer(net_co2_a_to_b, room_a, room_b)   # background
net_co2_a_to_b = _cap_co2_lower_transfer(net_co2_a_to_b, room_a, room_b)   # vertical net
d_co2          = minf(d_co2, _co2_lower_stock_kg(from_r))                  # vertical directed
```

`_co2_lower_stock_kg` is `co2_kg - clampf(co2_upper_kg, 0, co2_kg)` — the exact
expression `_move_lower_zone_species` already uses in this same file for a
declared lower-zone move. The cap is signed, only ever reduces, and never reads
post-state. No proportional split, no geometric fraction.

## OFF/ON matrix

`OFF` is byte-identical to the checkpoint. Verified by stashing the change and
re-running `v4_co_remote_rooms` at 180 s with S0d5a ON:

```
checkpoint (S0d5a ON, S0d5b absent)  32B1188F17D0F6C90F2D0BF32ABE368B257D96CA34C73EB7AAF96ADB7B9F1824
S0d5b OFF                            32B1188F17D0F6C90F2D0BF32ABE368B257D96CA34C73EB7AAF96ADB7B9F1824
S0d5b ON                             406D82B723E91F1493C2BC986270DC9F04481421B2308497EF2572E540C6431C
```

1087 rows in all three.

### CO2-specific material threshold, derived not inherited

`_material_eps_for(species)` returns a per-species value and **0.0 for any
species without its own derivation**, so no species can inherit another's
threshold. CO keeps the S0d5a2 value; CO2 gets its own:

| Bound | Value | Basis |
|---|---:|---|
| Lower | ≥ 1.1e−9 kg | observed CO2 floating-point noise peaks at 1.11e−10 kg; ×10 margin |
| Upper | ≤ 9.1e−7 kg | 1 ppm CO2 (44 g/mol) in a 50 m³ room is 9.10e−5 kg; ×100 margin |
| Geometric mean | 3.2e−8 kg | — |
| **Chosen** | **1.0e−8 kg** | 90× above the noise, 9 100× below one output unit |

Strict and material counters are always reported together; the threshold never
governs physics or acceptance.

### `upper > bulk`, strict and material

Twelve cases, all with identical row counts OFF/ON and all diverging in CSV
SHA-256 as expected for a physics change. D2PRE is the CO2 tracer-versus-mass
divergence rule; the closure delta is
`(rooms + inflight + exterior_removed)_ON − _OFF`.

| Case | Rows | OFF strict/material | ON strict/material | ON max excess kg | D2PRE OFF (F/W) | D2PRE ON (F/W) | Closure delta kg |
|---|---:|---:|---:|---:|---|---|---:|
| `v4_co_remote_rooms` | 1087 | 437 / 333 | 115 / **0** | 1.09e−11 | 0 / 166 | 0 / 166 | −8.9e−15 |
| `victim_fed_incapacitation` | 1087 | 416 / 318 | 105 / **0** | 1.02e−11 | 0 / 328 | 0 / 328 | −6.2e−15 |
| `cfast_corridor_chain` | 79 | 480 / 382 | 139 / **0** | 1.02e−11 | 0 / 12 | 0 / 12 | −8.9e−16 |
| `cfast_two_room_door_open` | 79 | 625 / 499 | 148 / **0** | 1.11e−11 | 0 / 19 | 0 / 19 | +2.2e−15 |
| `fuel_balance_diag_sealed` | 151 | 692 / 587 | 152 / **0** | 1.09e−11 | 0 / 39 | 0 / **38** | −6.2e−15 |
| `o2_stoich_diag_sealed` | 151 | 692 / 587 | 152 / **0** | 1.09e−11 | 0 / 39 | 0 / **38** | −6.2e−15 |
| `g3_gie_ppv_post_knockdown` | 1087 | 437 / 333 | 115 / **0** | 1.09e−11 | 0 / 166 | 0 / 166 | +1.5e−14 |
| `cfast_two_floor_stairwell` | 170 | 668 / 528 | 105 / **0** | 1.11e−10 | 0 / 2 | 0 / 2 | −5.6e−16 |
| `two_storey_smoke` | 2354 | 531 / 422 | 121 / **0** | 1.02e−11 | 0 / 152 | 0 / 152 | −7.1e−15 |
| `uk_bungalow_smoke` | 1268 | 439 / 358 | 126 / **0** | 1.02e−11 | 0 / 373 | 0 / 373 | +1.6e−14 |
| `cfast_single_room_closed` (control) | 115 | 728 / 506 | 285 / **0** | 1.11e−10 | 0 / 0 | 0 / 0 | −7.1e−15 |
| `postfire_decay` (post-fire, parcels) | 2407 | 316 / 245 | 81 / **0** | 1.14e−11 | 0 / 1391 | 0 / **1389** | −2.6e−13 |
| **Total** | | **6461 / 5098** | **1644 / 0** | | | | |

**All 5 098 material CO2 violations are eliminated: 100 %.** The 1 644 strict
residual are all below 1.14e−10 kg, an order of magnitude under the derived
1e−8 kg threshold and the same zero-headroom floating-point signature S0d5a2
established for CO. Both counters are reported together; the strict one is never
suppressed.

### Conservation, tracer and controls

- **Global CO2 balance closes.** `rooms + inflight + exterior_removed` differs
  between OFF and ON by at most `2.6e−13 kg` across all twelve cases, including
  the post-fire case with parcels in flight. Parcel refunds are tracked
  separately and are non-zero in five cases.
- **CO2 generation is untouched**: cumulative `co2_generated_kg_step` is
  bit-identical OFF/ON in every case, so combustion is unaffected.
- **D2PRE has zero FAIL in every case, OFF and ON.** The warning count is
  unchanged in nine cases and *falls* in three: 39 → 38 in both sealed cases and
  1391 → 1389 in `postfire_decay`. The OES tracer-versus-mass divergence
  therefore does not worsen; it improves slightly.

| Control | OFF | ON |
|---|---:|---:|
| CO strict `upper > bulk` | 2344 | **2344** |
| HCN strict `upper > bulk` | 6217 | **6217** |

CO and HCN are bit-for-bit unaffected, confirming the change is confined to CO2.
`hrr_kw`, `o2`, `o2_upper`, `temp_upper_c` and `co_ppm` show no divergence above
1e−9 in **any** of the twelve cases. No NaN and no negative value appears in any
ON metric.

**One exception, reported rather than smoothed:** `fed` peak moves in
`postfire_decay` only, from 262.4019 to 262.6661 (+0.10 %). FED is unchanged in
the other eleven cases. The shift is consistent with the CO2 concentration
changes over a 400 s decay and is the reason FED cannot be called invariant.

### CO2 output impact

Only CO2 channels move, and modestly:

| Case | `co2_ppm` max | `co2_upper_ppm_mass` max |
|---|---|---|
| `fuel_balance_diag_sealed` | 15104 → 15277 (+1.1 %) | 312762 → 316348 (+1.1 %) |
| `o2_stoich_diag_sealed` | 15104 → 15277 (+1.1 %) | 312762 → 316348 (+1.1 %) |
| `cfast_corridor_chain` | 9601 → 9610 (+0.09 %) | 66802 → 66866 (+0.10 %) |
| `uk_bungalow_smoke` | 24600 → 24541 (−0.24 %) | 561135 → 561138 (+0.001 %) |
| `victim_fed_incapacitation` | 26515 → 26515 (0 %) | 514231 → 514232 (0 %) |
| `v4_co_remote_rooms` | unchanged | 765001 → 765002 (0 %) |

The direction is expected: less CO2 is exported out of a nearly empty lower
zone, so the source retains slightly more and the peak bulk concentration rises
where the export was previously over-sized.

## Why it is not promoted

`co2_ppm` moves up to 1.1 % and FED moves 0.10 % in the post-fire case. Both
feed expected values and tolerances, so promotion needs a baseline review this
phase is forbidden from doing. HCN still carries its own material violations,
and S0d5c has not examined the clamp.

## Diagnostic instrumentation added for this audit

All default OFF, all pure observers, no physics change:

- `_co_trace` generalised to a species parameter, defaulting to `"co"` so the
  S0d5a2 contract is untouched. Invalid state is keyed per species and room.
  The export keeps `by_writer` as the CO view and adds `by_species`.
- `_material_eps_for(species)`: per-species thresholds with `0.0` for any
  species lacking its own derivation.
- `get_phase3_co2_mass_balance()`: rooms, upper, lower, in-flight, exterior
  removed and parcel refunded CO2, exported only when the diagnostics flag is on.
  With the flag off the attribution export stays completely empty, including the
  threshold declaration.

## STOP evidence

- Sixteen sequential Godot 4.7.1 fixtures pass, including H1, H2.10, H3.2a,
  H3.2-M atomic acceptance, the coupled bundle shadow, the atomic parcel
  lifecycle and S0a through S0d5a2. One regression was found and fixed during
  this audit: adding the threshold declaration to the attribution export made it
  non-empty with the flag off, which the S0d3 fixture caught; the export now
  returns empty when nothing was observed.
- The S0d5b fixture drives the real `_apply_background_species_exchange` and
  `_apply_directed_species_exchange`. It covers the flag default, the lower-stock
  helper including the already-violated and null cases, the signed cap in both
  directions and the non-binding case, the OFF over-export, the ON transfer
  equal to the available lower stock, bulk conservation, upper left untouched, a
  non-negative derived lower stock, `upper <= bulk` without the clamp, the
  vertical directed path, and CO and HCN being untouched. A temporary inverted
  assertion exits 1 with no PASS marker.
- Focused `pytest` for S0a-S0d5b is `144 PASS`. The broad Phase 3/guardrail
  selection is `1483 PASS / 2 FAIL`: the expected R2-1 freshness failure from the
  dirty motor and the pre-existing layer-interface export test.
- Physics coherence is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV coherence is
  `15 PASS / 14 CTRL / 0 FAIL`; the gap inventory is unchanged at
  `353 required + 6 VALID_GAP + 71 non-gating`. No Godot process remains.
- No official case enables the flag, `sim/validation` is untouched, the OES
  tracer, the final clamp, HCN, O2 and HVAC are untouched, and no baseline,
  expected value, tolerance, CTRL entry or VALID_GAP was modified.
