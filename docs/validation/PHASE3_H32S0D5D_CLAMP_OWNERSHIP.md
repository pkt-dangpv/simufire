# Phase 3 H3.2-S0d5d Species Clamp Ownership Audit

Date: 2026-08-06
Decision: **GO for diagnostic ownership. NO-GO for removing or relaxing the clamp.**

The species clamps rewrite room state with no physical donor. Until this phase
only one of the three families was observed, only at one of its two application
sites, and only as a count -- the mass each clamp actually rewrote was never
measured. S0d5d measures it, classifies it `numerical_correction`, and keeps it
strictly outside the physical source vector. No physics changed, no clamp was
removed and no clamp was relaxed.

O2 stays pending, HVAC stays deferred, no integrator exists, H3.2-S stays open,
H3.2b and H3.3 are not started and no runtime authority was granted.

## Phase 1 -- audited post-owner clamp inventory

The accumulator clamps and the final zonal clamps targeted by S0d5d, grouped by
the invariant they enforce. Other owner-local `maxf` expressions in purge and
transport paths are not claimed as covered here. The audited corrections are
counted separately and never merged: the three families have different causes
and different zonal consequences.

### Family A -- `bulk >= 0`, site `accumulator_application`

One statement per species, all at the single point where the per-step delta
accumulator is applied. Seven species.

| Species | Line | Expression |
|---|---|---|
| `smoke` | 2389 | `room.smoke_kg = maxf(0.0, room.smoke_kg + float(smoke_delta_kg[...]))` |
| `co` | 2397 | `room.co_kg = maxf(0.0, room.co_kg + float(co_delta_kg[...]))` |
| `co2` | 2402 | `room.co2_kg = maxf(0.0, room.co2_kg + float(co2_delta_kg[...]))` |
| `hcn` | 2404 | `room.hcn_kg = maxf(0.0, room.hcn_kg + float(hcn_delta_kg[...]))` |
| `hcl` | 2406 | `room.hcl_kg = maxf(0.0, room.hcl_kg + float(hcl_delta_kg[...]))` |
| `acrolein` | 2407 | `room.acrolein_kg = maxf(0.0, room.acrolein_kg + float(acrolein_delta_kg[...]))` |
| `formaldehyde` | 2408 | `room.formaldehyde_kg = maxf(0.0, room.formaldehyde_kg + float(formaldehyde_delta_kg[...]))` |

Bound: lower only, at `0.0`. `correction_bulk_kg = maxf(0, unclamped) - unclamped`,
so it is zero or **positive**: this family can only invent mass, never destroy it.
It does not touch `upper`, so it widens the `upper > bulk` gap rather than closing
it. S0d3 measured this family as never binding across 92 202 applications.

### Family B -- `upper >= 0`, site `accumulator_application`

Same site, but on the upper accumulator. Three species -- only the species that
carry an explicit upper stock.

| Species | Line | Expression |
|---|---|---|
| `co_upper` | 2401 | `room.co_upper_kg = maxf(0.0, room.co_upper_kg + float(co_upper_delta_kg[...]))` |
| `co2_upper` | 2403 | `room.co2_upper_kg = maxf(0.0, room.co2_upper_kg + float(co2_upper_delta_kg[...]))` |
| `hcn_upper` | 2405 | `room.hcn_upper_kg = maxf(0.0, room.hcn_upper_kg + float(hcn_upper_delta_kg[...]))` |

Bound: lower only, at `0.0`, and only on the upper face. The correction is zero or
positive on `upper`, which *narrows* the derived lower stock. Kept apart from
family A because the sign of its zonal effect is the opposite.

### Family C -- `upper <= bulk`, **two** application sites

| Site | Line | Expression |
|---|---|---|
| `room_loop` | 2629 | `room.co_upper_kg = clampf(room.co_upper_kg, 0.0, room.co_kg)` |
| `room_loop` | 2630 | `room.co2_upper_kg = clampf(room.co2_upper_kg, 0.0, room.co2_kg)` |
| `room_loop` | 2631 | `room.hcn_upper_kg = clampf(room.hcn_upper_kg, 0.0, room.hcn_kg)` |
| `parcel_delivery` | 2892 | `target.co_upper_kg = clampf(target.co_upper_kg, 0.0, target.co_kg)` |
| `parcel_delivery` | 2893 | `target.co2_upper_kg = clampf(target.co2_upper_kg, 0.0, target.co2_kg)` |
| `parcel_delivery` | 2894 | `target.hcn_upper_kg = clampf(target.hcn_upper_kg, 0.0, target.hcn_kg)` |

Two bounds in one call. The correction is zero or **negative** on `upper`: this
family can only remove upper mass, never add it, and it never touches `bulk`.
Because `lower` is derived as `bulk - upper`, a binding clamp silently moves mass
from the upper zone into the derived lower zone with no owner.

**The parcel-delivery site had never been measured.** S0d4, S0d5a2, S0d5b and
S0d5c all instrumented the room loop only. The parcel site was observed by
`_co_trace("parcel_delivery_clamp", ...)`, which reports whether the invariant
held but not how much mass the clamp rewrote. That gap is closed here.

### Not a clamp application -- defensive clamped reads

Thirteen further sites evaluate `clampf(upper, 0, bulk)` **without writing it
back**, to size a transport from a stock that is assumed valid:

| Lines | Purpose |
|---|---|
| 710 | `_co2_lower_stock_kg` helper (S0d5b) |
| 1576 | zonal shadow export |
| 2508 | outside-open CO purge |
| 3493-3495 | exterior smoke vent, CO/CO2/HCN |
| 3540-3542 | natural-vent purge, CO/CO2/HCN |
| 3593-3597 | upper-band transport, CO/CO2/HCN |
| 3667-3671 | lower-band transport, CO/CO2/HCN |

These correct no state, so they emit no `numerical_correction` and are outside the
scope of the ownership question. They are recorded here because they show the
invariant is assumed in many more places than it is enforced: while `upper > bulk`
holds, each of these silently sizes its transport from `bulk` instead of `upper`.
That is a physics consequence of the violation that the final clamp does not
undo, and it is why S0d5a and S0d5b fixed the transports rather than the clamp.

### Per-clamp answers to the twelve audit questions

| # | Question | Family A | Family B | Family C |
|---|---|---|---|---|
| 1 | exact expression | `maxf(0.0, stock + delta)` | `maxf(0.0, upper + delta)` | `clampf(upper, 0.0, bulk)` |
| 2 | stock pre | `room.<sp>_kg` | `room.<sp>_upper_kg` | `room.<sp>_upper_kg` |
| 3 | requested / unclamped | `stock + delta` | `upper + delta` | `upper` as written by the last writer |
| 4 | bound | lower `0.0` | lower `0.0` | lower `0.0`, upper `bulk` |
| 5 | stock post | `maxf(0.0, ...)` | `maxf(0.0, ...)` | `clampf(...)` |
| 6 | `correction = post - unclamped` | `>= 0` | `>= 0` | `<= 0` |
| 7 | cause | keep the stock non-negative | keep the upper stock non-negative | keep the zonal invariant |
| 8 | own material threshold | per species, `_material_eps_for` | per species | per species |
| 9 | noise or material mass | measured, see stack tables | measured | measured |
| 10 | conserves bulk | **no**, it creates bulk mass | yes, bulk untouched | yes, bulk untouched |
| 11 | effect on derived lower | widens it | narrows it | forces it to `>= 0` |
| 12 | pre-existing ledger/owner | none | none | count only, room loop only |

## The decisive question

> Can the clamp be represented honestly as `numerical_correction` without
> attributing physical provenance to it?

**Yes, under three conditions, all of which are enforced:**

1. **It exports only the correction actually applied.** `_record_clamp_correction`
   receives `post - unclamped` and stores nothing else as mass. It never receives
   a stock, a delta, or a transport amount.
2. **It can never feed a physical source.** `Phase3PhysicalOwnerLedger` treats
   only `local_source` and `exterior_boundary` as physical sources; a
   `numerical_correction` event aggregates to a zero contribution in
   `physical_source_for_room`. The fixture proves this behaviourally, not by
   reading a constant.
3. **It is not hidden inside the owner of the preceding transport.** The
   correction is keyed by `species|kind|site` in its own ledger, separate from
   `phase3_species_attribution`, and the sample records
   `writer_before_clamp` as an observation -- never as an attribution. When the
   causal trace is not active the field reports `unknown` rather than guessing.

The correction therefore appears as its own term:

```
pre + physical owners + transports + correction = post
```

It is never used to close the source vector: the vector stays incomplete, which
is the S0d finding, and this phase does not change that.

## Diagnostic design

No new flag. The measurement reuses
`phase3_species_attribution_diagnostics_enabled`, the flag that already gates the
clamp measurements from S0d3 and the zonal guard from S0d4. Default OFF; with the
flag off the export contains no key at all, not even the threshold header.

Per room, species and step the sample carries `step`, `room_id`, `species`,
`clamp_kind`, `site`, `classification`, `pre_bulk_kg`, `pre_upper_kg`,
`requested_bulk_kg`, `requested_upper_kg`, `post_bulk_kg`, `post_upper_kg`,
`correction_bulk_kg`, `correction_upper_kg`, `lower_derived_before_kg`,
`lower_derived_after_kg`, `strict_bound`, `material_bound`,
`material_epsilon_kg`, `cause`, `writer_before_clamp` and the active experimental
flags. The sample list is bounded at 256 entries and reports `sample_overflow`,
so a long run cannot grow it without limit and cannot silently truncate either.

The accumulated counters -- `applications`, `strict_count`, `material_count`,
`corrected_mass_abs_kg`, `corrected_mass_signed_kg`, `max_correction_kg`,
`strict_rooms`, `material_rooms` -- are fixed-size and unbounded in coverage.

For a species with no paired zonal stock the sample reports `NAN` rather than a
zero that would look measured. Thresholds are never inherited: `_material_eps_for`
returns the species' own derived epsilon or `0.0`, and strict and material counts
are always reported together.

## Runtime campaign

The campaign used only committed case files and Godot 4.7.1, sequentially. It
contains 65 unique completed runs:

| Group | Cases | Runs |
|---|---:|---:|
| A/B/C with diagnostics ON | 15 per stack | 45 |
| A/C with diagnostics OFF | 6 per stack | 12 |
| A/C with causal trace ON | 4 per stack | 8 |

Every run has a completed `run_manifest.json`, `sim_time_s >= duration_s`, the
scene entrypoint `res://tools/run_scenario_headless.tscn`, a Godot 4.7.1 label,
all six expected artifacts, and no parse, script, crash or native-memory error
signature. No run is accepted from return code alone.

The 12 OFF/ON pairs have identical row counts and byte-identical CSV SHA-256.
The OFF summaries contain neither `phase3_clamp_corrections` nor the existing
species-attribution block. Diagnostics therefore remain a no-op for physics and
legacy output.

Trace provenance is also explicit: all 2,048 bounded samples from the eight
trace runs carry a known preceding writer; all 11,520 samples from the 45 plain
diagnostic runs report `unknown`. The latter is intentional: provenance is not
guessed when the causal trace is disabled.

## Measured correction load

Only family C at `room_loop` binds in the 45 ON runs. All accumulator
non-negativity families and all three `parcel_delivery` zonal clamps have zero
strict corrections. The table aggregates the 15 cases in each stack:

| Stack | Species | Strict | Material | Corrected mass abs (kg) | Peak event (kg) |
|---|---|---:|---:|---:|---:|
| A legacy | CO | 26,116 | 20,125 | 4.021462175 | 3.60275e-3 |
| A legacy | CO2 | 29,696 | 27,503 | 0.267319832 | 1.76858e-4 |
| A legacy | HCN | 29,362 | 0 | 3.10825e-4 | 9.58680e-8 |
| B CO fix | CO | 5,998 | 0 | 2.00728e-8 | 1.30850e-10 |
| B CO fix | CO2 | 29,696 | 27,503 | 0.267319832 | 1.76858e-4 |
| B CO fix | HCN | 29,362 | 0 | 3.10825e-4 | 9.58680e-8 |
| C CO+CO2 fixes | CO | 5,998 | 0 | 2.00728e-8 | 1.30850e-10 |
| C CO+CO2 fixes | CO2 | 4,803 | 0 | 2.50731e-9 | 1.14514e-10 |
| C CO+CO2 fixes | HCN | 29,362 | 0 | 3.10825e-4 | 9.58680e-8 |

The experimental CO and CO2 fixes therefore remove every material correction
in their own species without moving the population into HCN. HCN remains a
strict-only population below its independently derived 1e-7 kg threshold.

For every binding family-C sample, bulk correction is exactly zero, upper
correction is non-positive, and derived-lower correction is equal and opposite.
Thus the clamp preserves bulk species mass and only repairs the zonal split.
The diagnostic exports that repair as `numerical_correction`; it never presents
it as a physical source.

## CO2 balance limitation discovered by the full-duration corpus

The S0d5b statement that global CO2 balance closed to 2.6e-13 kg was valid for
its shorter measured intervals, but is not a general result. In this complete
campaign, `rooms + inflight + exterior_removed` agrees between A and C to about
4e-13 kg in 13 of 15 cases, but the diagnostic differs by -4.09848e-3 kg in
`g3_gie_ppv_post_knockdown` and +1.53886e-4 kg in `uk_bungalow_smoke`.

Code audit identifies a diagnostic omission: exterior pressure-vent and
natural-vent species paths remove CO2 without calling
`_record_co2_exterior_removal`. The earlier short runs did not reach the late
opening regime that exposes the omission. This is **not evidence of physical
non-conservation**, but it means global conservation is not demonstrable from
the current `phase3_co2_mass_balance` export for those two full-duration runs.
S0d5d does not widen scope to repair that older diagnostic.

## Verification and decision

| Check | Result |
|---|---|
| Campaign artifacts | 65/65 valid and complete |
| OFF/ON byte identity | 12/12 PASS |
| Trace provenance | 2,048/2,048 known; plain diagnostic stays unknown |
| S0a-S0d5d focused pytest | 171 PASS |
| Godot S0 fixtures | 11/11 PASS with stderr scanning |
| `pytest -k "phase3 or guardrail"` | 1,514 PASS / 2 known FAIL |
| Physics / ILV | 0 FAIL / 0 FAIL |
| Gap inventory | 353 required + 6 VALID_GAP + 71 non-gating |
| Guardrails before commit | 9/10; only R2-1 for dirty motor |

The Godot fixture batch exposed a historical false green in the S0d3 fixture:
it treated the S0d5b summary-level `material_eps_kg` header as a species record,
raised `Invalid access`, and Godot still exited zero. The fixture now excludes
that one known metadata key and fails on any other non-species entry. All 11
fixtures were rerun with explicit stderr scanning, not exit-code-only checks.

**Decision: GO for passive clamp ownership diagnostics only. NO-GO for removing
or relaxing any clamp.** The experimental CO/CO2 flags are not promoted, the
CO2 full-duration balance export remains incomplete, H3.2-S remains open, O2
and HVAC remain pending, no source integrator exists, H3.2b still blocks H3.3,
and no runtime authority is granted.
