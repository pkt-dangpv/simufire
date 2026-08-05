# Phase 3 H3.2-S0d3 Species and O2 Attribution Measurement

Date: 2026-08-05
Decision: **GO parcial (outcome B)** — measurement only; no attribution shipped

This phase adds a passive, default-OFF measurement of the aggregate species and
O2 clamp and answers the decisive question with data. It does **not** enrich the
S0a events, does not create the integrator and does not close H3.2-S.

## Decisive question

> Can the accepted delta per owner be known without modifying the physics?

The answer depends on two independent properties, both now measured or declared:

1. **Does the aggregate clamp bind?** If not, `accepted == requested` for every
   owner and attribution is exact.
2. **Does the path know the zone?** The S0a contract needs a zone for every
   transport and boundary identity.

## Measurement

`phase3_species_attribution_diagnostics_enabled`, default OFF, records at the
single site where `step_smoke` applies the accumulated deltas. It stores only
aggregate counters. There is no per-owner field of any kind, so a clamped
deficit cannot be silently distributed.

Twelve cases, 92 202 clamp applications per species:

| Species | Zone identity | Applications | Neg. req. | Pos. req. | Clamp bound (low) | Clamp bound (high) | Max deficit kg | Requested kg | Accepted kg |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `o2` | bulk_only | 92202 | 6035 | 3655 | 0 | **1798** | 0 | −1.56e−17 | −2.30e−13 |
| `smoke` | bulk_only | 92202 | 7415 | 56612 | **0** | — | 0 | 2.3364 | 2.3364 |
| `co` | bulk_and_upper | 92202 | 21852 | 68145 | **0** | — | 0 | −0.51344 | −0.51344 |
| `co_upper` | upper_zone | 92202 | 6419 | 10147 | **0** | — | 0 | −0.057937 | −0.057937 |
| `co2` | bulk_and_upper | 92202 | 21948 | 68049 | **0** | — | 0 | −8.4993 | −8.4993 |
| `co2_upper` | upper_zone | 92202 | 9217 | 524 | **0** | — | 0 | −7.5719 | −7.5719 |
| `hcn` | bulk_and_upper | 92202 | 20502 | 60853 | **0** | — | 0 | −0.0058677 | −0.0058677 |
| `hcn_upper` | upper_zone | 92202 | 8465 | 524 | **0** | — | 0 | −0.0049842 | −0.0049842 |
| `hcl` | bulk_only | 92202 | 2144 | 6498 | **0** | — | 0 | −0.079998 | −0.079998 |
| `acrolein` | bulk_only | 92202 | 4274 | 13010 | **0** | — | 0 | −0.00038284 | −0.00038284 |
| `formaldehyde` | bulk_only | 92202 | 4274 | 13010 | **0** | — | 0 | −0.00019126 | −0.00019126 |

Cases: `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`,
`cfast_corridor_chain`, `cfast_two_room_door_open`, `v4_co_remote_rooms`,
`victim_fed_incapacitation`, `pvc_curtain_hcl_release`,
`pu_sofa_fec_incapacitation`, `ppv_attack_pressurized`,
`g3_gie_ppv_post_knockdown`, `v8_suppression_reburn`, `flashover_simple_house`.

### What the numbers say

- **The `maxf(0.0, ...)` species clamp never bound.** Not once, in any case, for
  any of the ten species accumulators. `requested_kg_total` equals
  `accepted_kg_total` exactly for all of them.
- **This overturns the S0c assumption.** S0c declared species attribution
  blocked because "when that clamp binds, the per-owner accepted share is not
  recoverable". The clamp is real, but in these configurations it is slack, so
  case **A** applies to species: `accepted_owner_delta == requested_owner_delta`.
- **O2 is different.** Its clamp is two-sided on a fraction and the **upper**
  bound `o2_nominal` bound 1798 times. Whenever it binds the aggregate
  acceptance differs from the aggregate request, and with more than one owner
  contributing the split is case **C**: indeterminate.

## Cardinality and zone identity

Owner multiplicity is structural, not measured: in one step a room's CO
accumulator can receive negative contributions from immediate transport, doorway
counterflow, background exchange, exterior smoke vent, natural-ventilation
purge, two-zone opening exchange, vertical-opening exchange and parcel enqueue.
Eight distinct paths for one species. Multiplicity therefore only matters where
the clamp binds — which, for species, is nowhere in the measured suite.

| Species | Zone in legacy state | Attribution verdict |
|---|---|---|
| `co`, `co2`, `hcn` | bulk plus `*_upper_kg`, so lower = bulk − upper | **exact and zonal** |
| `smoke`, `hcl`, `acrolein`, `formaldehyde` | bulk only | exact but **`unknown_zone_identity`** |
| `o2` | bulk fraction only, no zone | **blocked**: `aggregate_clamp_multi_owner` and `unknown_zone_identity` |

## Verdict

**Outcome B, GO parcial.**

- Three species — CO, CO2 and HCN — have both an exact accepted delta and a
  usable zone. They are the only candidates for enriched S0a events.
- Four species — smoke, HCl, acrolein and formaldehyde — have an exact accepted
  delta but no zone, so they must carry `completeness = false` with
  `unknown_zone_identity`.
- O2 is blocked on both counts.

**This is not a closure of H3.2-S.** Even a perfect species attribution would
not repair the mass and energy gaps that S0d recorded: HVAC is still unowned,
and B1-lower is still an open physics question.

## What was deliberately not done

- The S0a events were **not** enriched with `species_kg` or `o2_kg`. Doing so
  requires instrumenting eight owner paths per species inside physics code, and
  the honest precondition — a runtime fail-closed check that the clamp did not
  bind for that room, species and step — must be part of that same patch. That
  is S0d4, not this phase.
- No proportional split, FIFO order or per-species priority was introduced. The
  measurement has no per-owner field at all, by construction.
- No integrator, no HVAC work, no RoomModel change, no solver call, no
  authority, no CSV column and no baseline touched.

## STOP evidence

- Twelve OFF/ON pairs are byte-identical with identical row counts; the OFF
  summary carries no `phase3_species_attribution` block.
- Thirteen sequential Godot 4.7.1 fixtures pass, including H1, H2.10, H3.2a,
  H3.2-M atomic acceptance, the coupled bundle shadow, the atomic parcel
  lifecycle and S0a/S0b/S0c/S0d1/S0d2.
- The S0d3 fixture covers the default OFF, the slack clamp (`accepted ==
  requested`), the binding clamp (deficit visible, no per-owner share), both O2
  bounds, the declared zone identities, a real `step_smoke` measurement and a
  pure, deterministic export. A temporary inverted assertion exits 1 with no
  PASS marker.
- Focused `pytest` for S0a-S0d3 is `95 PASS`. The broad Phase 3/guardrail
  selection is `1422 PASS / 2 FAIL`: the expected R2-1 freshness failure from
  the dirty motor and the pre-existing layer-interface export test.
- Physics coherence is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV coherence is
  `15 PASS / 14 CTRL / 0 FAIL`; the gap inventory is unchanged at
  `353 required + 6 VALID_GAP + 71 non-gating`. No Godot process remains.

## Risk

The non-binding result is empirical over twelve cases and one duration each. It
is strong evidence, not a proof. Any future attribution must therefore verify at
runtime, per room and per step, that the clamp stayed slack, and fall back to
`completeness = false` with `aggregate_clamp_multi_owner` when it does not.
