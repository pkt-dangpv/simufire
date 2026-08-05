# Phase 3 H3.2-S0d5a CO Zonal Transport Consistency

Date: 2026-08-05
Decision: **GO to keep `phase3_co_zonal_transport_consistency_enabled` as an
experimental, default-OFF flag. NO-GO to promote it.**

> **Result corrected by H3.2-S0d5a2 (2026-08-05).** This record states that the
> change removes 81.9 % of the violations and leaves 1 682 without provenance.
> The strict counter conflated two populations. Measured with a material
> threshold, the change removes **7 583 of 7 583 material violations, 100 %**,
> and the 1 682 residual are floating-point noise below 5.03e−11 kg, created in
> the zero-headroom state and resolved by the clamp inside the same step. There
> is no residual physical defect in this scope. See
> `PHASE3_H32S0D5A2_CO_VIOLATION_TRACE.md`.

S0d stays open, S0d5b and S0d5c are not started, O2 and the zone-less species
stay blocked, HVAC stays deferred, no integrator exists, H3.2-S stays open,
H3.2b and H3.3 are not started and no runtime authority was granted.

## CO audit by path

| Path | Amount computed from | Bulk debit | Upper debit | Destination | Coherent? |
|---|---|---|---|---|---|
| immediate transport | `min(kg/smoke,1) * source.co_upper_kg`, capped by `source.co_kg` then by concentration headroom | yes | **no** | bulk **and** upper | **no** |
| parcel enqueue | same statement, same accepted amount | yes | **no** | parcel carries `co_kg == co_upper_kg` | **no** |
| parcel delivery | headroom at delivery time | — | — | bulk and upper, both cut by the same `co_cut` | yes |
| parcel refund | `co_parcel - co_headroom` | credit | credit, but through a second `minf(..., co_kg)` cap | — | partially |
| parcel cancellation | — | none | none | none; the source debit is a explicit loss | yes |
| background exchange | proportional `co_upper/co_kg` | yes | yes | symmetric | yes, out of scope |
| doorway counterflow | proportional upper share | yes | yes | signed, symmetric | yes, out of scope |
| two-zone opening | per zone | yes | per zone | per zone | yes, out of scope |
| vertical opening | explicit upper split | yes | yes | symmetric | yes, out of scope |
| exterior purges, ACH, post-fire, PPV | proportional | yes | yes | — | yes, out of scope |

Conservation of the defective path: bulk conserves, **upper does not** (the
destination gains upper that no source lost), and the source's derived
`lower = bulk - upper` absorbs the entire debit even though the amount was sized
from the upper stock. `upper > bulk` therefore appears at the source and the
unowned final clamp repairs it.

## Change

Two flag-gated statements, nothing else:

1. At the source debit, when enabled, `co_upper_delta_kg[from_id] -= co_moved_kg`
   with the same accepted amount. `co_moved_kg` is already bounded by
   `source.co_upper_kg`, so the upper stock cannot go negative.
2. In the parcel refund, when enabled, credit bulk and upper with the same
   `co_refund_kg` instead of passing the upper side through a second
   `minf(..., co_kg)` cap.

The legacy branches survive verbatim for OFF. Transport order, caps and the
final `upper <= bulk` clamp are untouched, as are CO2, HCN, O2 and every other
species.

Note on scope honesty: change 2 is **inert in a clean state**. The legacy `minf`
only differs once `upper > bulk` already holds. The fixture pins both facts.

## OFF/ON matrix

`OFF` is byte-identical to the S0d4 checkpoint. Verified directly by stashing
the change, running `v4_co_remote_rooms` for 180 s, restoring and re-running:

```
checkpoint OFF  07A4B49E791BD2CDF05B4BB99257AB9768AA6E53D6086A856525B71622BBA403
S0d5a      OFF  07A4B49E791BD2CDF05B4BB99257AB9768AA6E53D6086A856525B71622BBA403
S0d5a      ON   32B1188F17D0F6C90F2D0BF32ABE368B257D96CA34C73EB7AAF96ADB7B9F1824
```

1087 rows in all three.

### `upper > bulk` violations, OFF to ON

| Case | Duration | CO OFF | CO ON | CO2 | HCN |
|---|---:|---:|---:|---:|---:|
| `v4_co_remote_rooms` | 180 s | 1010 | **183** | 437 → 437 | 437 → 437 |
| `victim_fed_incapacitation` | 180 s | 1252 | **194** | 416 → 416 | 416 → 416 |
| `cfast_corridor_chain` | 120 s | 1175 | **168** | 480 → 480 | 480 → 480 |
| `cfast_two_room_door_open` | 120 s | 1036 | **236** | 625 → 625 | 625 → 625 |
| `fuel_balance_diag_sealed` | 120 s | 768 | **165** | 692 → 692 | 488 → 488 |
| `o2_stoich_diag_sealed` | 120 s | 768 | **165** | 692 → 692 | 488 → 488 |
| `g3_gie_ppv_post_knockdown` | 180 s | 1016 | **183** | 437 → 437 | 437 → 437 |
| `pvc_curtain_hcl_release` | 180 s | 1281 | **189** | 437 → 437 | 0 → 0 |
| `uk_bungalow_smoke` | 180 s | 974 | **199** | 439 → 439 | 439 → 439 |
| **Total** | | **9280** | **1682** | 4655 → 4655 | 3810 → 3810 |

**7 598 of 9 280 CO violations (81.9 %) are attributable to the immediate and
parcel paths and disappear.** The remaining **1 682 (18.1 %) are not** and stay
exactly where they were: they come from other CO writers, which S0d5a does not
touch and does not attempt to localise. CO2 and HCN are bit-for-bit unaffected,
which confirms the change is confined to CO.

This is a reduction, not a closure.

### Invariants and controls

- `upper < 0`: 0 in every case, OFF and ON.
- Aggregate CO clamp: 0 → 0 in every case; the correction does not push the bulk
  accumulator into the `maxf(0.0, ...)` clamp.
- No NaN and no negative value in any ON metric.
- `hrr_kw`, `o2` and `temp_upper_c` are identical OFF/ON in all nine cases: no
  combustion or oxygen feedback, as expected for a CO-only bookkeeping change.
- `co_ppm` peak rises slightly (for example 5274 → 5473 in `v4_co_remote_rooms`,
  +3.8 %) while `co_upper_ppm` peak falls slightly (101718 → 101665). That is the
  expected direction: the source no longer keeps upper CO it has already given
  away, so the clamp stops removing that excess.
- FED peak moves by at most 0.3 % and in both directions across cases
  (19.9552 → 19.9673, 28.0116 → 27.9639, 20.73 → 20.6669).

## Why it is not promoted

`co_ppm` and FED move. Both feed expected values and tenability tolerances, so
promotion needs a baseline review this phase is forbidden from doing. The
correction is also only 81.9 % of the CO story: S0d5b and S0d5c remain.

## STOP evidence

- Fourteen sequential Godot 4.7.1 fixtures pass, including H1, H2.10, H3.2a,
  H3.2-M atomic acceptance, the coupled bundle shadow, the atomic parcel
  lifecycle and S0a/S0b/S0c/S0d1/S0d2/S0d3.
- The S0d5a fixture drives the real `step_smoke` transport and the real
  `_release_pending_interior_deliveries`, with the other CO routes silenced so
  the assertions describe the audited path alone. It covers the flag default,
  the OFF defect, the ON symmetric debit, the invariant derived lower stock,
  non-negativity, `upper <= bulk` in the corrected path, symmetric refunds from
  both clean and already-violated states, cancellation creating no CO, and CO2
  and HCN being untouched. A temporary inverted assertion exits 1 with no PASS
  marker.
- Focused `pytest` for S0a-S0d5a is `117 PASS`. The broad Phase 3/guardrail
  selection is `1448 PASS / 2 FAIL`: the expected R2-1 freshness failure from
  the dirty motor and the pre-existing layer-interface export test.
- Physics coherence is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV coherence is
  `15 PASS / 14 CTRL / 0 FAIL`; the gap inventory is unchanged at
  `353 required + 6 VALID_GAP + 71 non-gating`. No Godot process remains.
- No official case enables the flag, no baseline, expected value, tolerance,
  CTRL entry or VALID_GAP was touched and no report was regenerated.
