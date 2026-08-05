# Phase 3 H3.2-S0d4 Zonal Attribution Audit for CO, CO2 and HCN

Date: 2026-08-05
Decision: **NO-GO for shipping per-owner zonal species attribution**

> **Interpretation corrected by H3.2-S0d5a2 (2026-08-05).** The counts below are
> **strict**, zero-tolerance comparisons and conflate two populations. Measured
> again with a material threshold, CO's violations are 7 583 material out of
> 9 280 strict, CO2 keeps 4 230 material and HCN only 122. The headline rates in
> this document should be read as strict counts, not as material defects. See
> `PHASE3_H32S0D5A2_CO_VIOLATION_TRACE.md`.

The audit found a blocking precondition failure: the zonal split that the
attribution would rest on is rewritten every step by an unowned clamp, at a
material rate, because several owner paths move a species' bulk stock without
moving its upper stock. No S0a contract extension and no owner enrichment was
implemented. A passive zonal guard was added, default OFF, as the evidence.

## The decisive precondition

The mandated rule is `lower_delta = bulk_delta - upper_delta`, valid only while
`upper <= bulk`. `GasExchangeSystem` closes every room step with

```
room.co_upper_kg  = clampf(room.co_upper_kg,  0.0, room.co_kg)
room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)
room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)
```

That clamp has no owner. When it binds it changes the zonal split by an amount
that belongs to no path, so the split that reaches the state is not the one the
owners produced.

## Measurement

`phase3_species_attribution_diagnostics_enabled` now also records the guard at
that clamp. Twelve cases, 98 690 applications per species:

| Species | Applications | `upper > bulk` | Rate | `upper < 0` | Max excess kg |
|---|---:|---:|---:|---:|---:|
| CO | 98690 | **7444** | 7.5 % | 0 | 2.5422e−05 |
| CO2 | 98690 | **5753** | 5.8 % | 0 | 1.2408e−06 |
| HCN | 98690 | **5324** | 5.4 % | 0 | 8.2153e−10 |

Every case violates it; the per-case counts range from 231 to 1125. The lower
bound of the same clamp never binds.

Cases: `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`,
`cfast_corridor_chain`, `cfast_two_room_door_open`, `v4_co_remote_rooms`,
`victim_fed_incapacitation`, `cfast_two_floor_stairwell`, `two_storey_smoke`,
`uk_bungalow_smoke`, `ppv_attack_pressurized`, `g3_gie_ppv_post_knockdown`,
`pvc_curtain_hcl_release`.

## Root cause

Several owner paths debit a species' **bulk** accumulator without debiting its
**upper** accumulator. Repeated application pushes `upper` above `bulk`, and the
unowned clamp then repairs it.

| Path | CO | CO2 | HCN |
|---|---|---|---|
| immediate/parcel transport source debit | `co_delta_kg[from_id] -= co_moved_kg` only. **No upper debit exists.** | debits both `co2_delta_kg` and `co2_upper_delta_kg` | debits both `hcn_delta_kg` and `hcn_upper_delta_kg` |
| background exchange | debits both | **bulk only**, upper untouched | **bulk only**, upper untouched |
| doorway counterflow | both, signed | both, signed | both, signed |
| exterior smoke vent / natural-vent purge | both | both | both |
| two-zone opening exchange | both | both | both |
| vertical opening | both (upper split explicit) | bulk only | bulk only |

So CO is broken mainly by the transport path and CO2/HCN mainly by the
background and vertical paths. The amount moved for CO is computed **from the
source's upper stock** and then removed from its bulk stock, which is
self-inconsistent before any clamp is involved.

## Why this blocks the phase

The prompt's own rule says to fail closed when `upper > bulk`. Applying it here
would mark 5.4-7.5 % of every room/species/step as `completeness = false`, and
the future source vector may only consume `completeness = true`. A species
source that is undefined in one step out of thirteen is not a usable vector, and
shipping roughly 150 lines of instrumentation into the hottest physics loop to
produce it is not justified.

More importantly, attributing CO zonally today would encode the defect: the
ledger would report CO leaving a room's **lower** zone in a transfer whose
magnitude was derived from that room's **upper** zone, and would then be
silently corrected by a clamp with no owner.

## Schema decision

The suggested extension

```
species_delta_kg = {"co": {"upper": x, "lower": y}, ...}
```

is representable, optional and backward compatible, and it can express local,
exterior, interior transport, parcel lifecycle and refunds without double
counting because every event carries its own zone identity. It was **not
implemented**: the precondition it depends on does not hold, so adding it now
would ship a validated container for unvalidatable data.

## What would unblock S0d4

1. Give the CO transport path an upper debit that matches the stock the moved
   amount was derived from, or derive the moved amount from the bulk stock.
2. Give the background and vertical CO2/HCN paths an explicit zonal split.
3. Own the `upper <= bulk` clamp as a `numerical_correction`, or remove it once
   1 and 2 make it unreachable.

All three change physics and need their own flags, matrices and STOP gates.
Only afterwards can the S0a schema extension and the per-owner attribution be
built on a zonal split that is actually the owners' own.

## STOP evidence

- The zonal guard observes only: it counts violations and the worst excess, and
  has no repair, no share and no derived lower stock. Structural tests pin that,
  and pin that the legacy CO/CO2/HCN statements are unchanged.
- Twelve OFF/ON pairs are byte-identical; the OFF summary carries no diagnostic
  block. No official case enables the flag.
- Thirteen sequential Godot 4.7.1 fixtures pass, including H1, H2.10, H3.2a,
  H3.2-M atomic acceptance, the coupled bundle shadow, the atomic parcel
  lifecycle and S0a/S0b/S0c/S0d1/S0d2/S0d3.
- Focused `pytest` for S0a-S0d4 is `105 PASS`. The broad Phase 3/guardrail
  selection is `1432 PASS / 2 FAIL`: the expected R2-1 freshness failure from
  the dirty motor and the pre-existing layer-interface export test.
- Physics coherence is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV coherence is
  `15 PASS / 14 CTRL / 0 FAIL`; the gap inventory is unchanged at
  `353 required + 6 VALID_GAP + 71 non-gating`. No Godot process remains.
- No `Phase3PhysicalOwnerLedger` change, no integrator, no HVAC work, no solver
  call, no CSV column, no expected value, tolerance, CTRL entry or VALID_GAP
  touched.
