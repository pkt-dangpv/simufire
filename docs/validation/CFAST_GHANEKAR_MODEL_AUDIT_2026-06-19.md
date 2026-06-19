# CFAST/Ghanekar model audit — 2026-06-19

Scope: geometry/topology equivalence between SimuFire validation cases, CFAST `.in` files, and the Ghanekar empirical reference. This audit checks whether the *dwelling models* used for comparison are valid enough before further calibration work.

Initial audit note: no motor code, cases, reports, tolerances, or baselines were changed by the audit itself.

Resolution update (2026-06-19): the actionable CFAST equivalence mismatches found here were corrected after the audit. `cfast_multi_fuel_couch_tv` now has an equivalent 0.9x2.0 exterior opening open from t=0, `cfast_window_break_t180` now uses the CFAST 1.2x1.0 window geometry, and `cfast_corridor_chain.in` now uses R2=25.2 m3 with regenerated CFAST outputs.

## Verdict

Some validation models are valid approximations. The highest-risk CFAST discrepancies found in this audit were topological, not numeric, and have now been corrected where they affected tracked CFAST validation cases:

1. `cfast_multi_fuel_couch_tv`: resolved. CFAST has an open exterior door; SimuFire now represents it as an equivalent 0.9x2.0 exterior opening open from t=0. Result: required multifuel RMSE passes.
2. `cfast_corridor_chain`: resolved for geometry. CFAST R2 was 33.6 m3; it now matches SimuFire `simple_house` room 2 at 25.2 m3. Remaining R0 temperature failures are still model gaps, not this volume mismatch.
3. `cfast_window_break_t180`: resolved. SimuFire now overrides the break window to 1.2 x 1.0 m, sill 0.8 m, matching CFAST.
4. Ghanekar kitchen/living-room: production case does not faithfully represent the paper's kitchen-window/fire-compartment topology; prior exploratory notes already show this is a structural mismatch.
5. Ghanekar bedroom/hallway: approximate, not exact. It matches key macro traits, but still lacks localized 0.9 m sampling, HCN, sampling-line delay, and full experimental floor-plan fidelity.

## Method

Sources inspected:

- SimuFire templates: `sim/templates/BuildingTemplate.gd`
- SimuFire cases: `sim/validation/cases/*.json`
- CFAST inputs: `sim/validation/cfast/*.in`
- Ghanekar reference: `sim/validation/EMPIRICAL_REFERENCE_GHANEKAR_2026.md`
- Historical topology notes: `docs/sessions/root/ESTADO_SESION_2026-05-28.md`
- Case override behavior: `sim/validation/CaseRunner.gd`

Important implementation detail: `CaseRunner.gd` can override opening geometry, but only if the case JSON includes `width_m`, `height_m`, `sill_m`, etc. Many validation cases override only `open_fraction`; in those cases the geometry remains whatever the selected SimuFire template defines.

## CFAST Cases

| Case | Geometry/topology status | Evidence | Risk | Action |
|------|--------------------------|----------|------|--------|
| `cfast_r0_window_360` / `r0_hall_window_360.in` | Good macro equivalence | CFAST R0=5.0x4.0x2.4=48.0 m3; Hall=1.5x7.0x2.4=25.2 m3. Matches `simple_house` R0/R1. R0-Hall door 0.9x2.0 and R0 window 2.0x1.2 sill 0.8 match template geometry. | Low | Keep. Remaining O2 failures are model/combustion gaps, not geometry mismatch. |
| `cfast_slow_growth_sealed` | Good macro equivalence | Single R0 48.0 m3; all openings closed in both CFAST and SimuFire case. | Low | Keep. Failures are thermal/O2 coupling gaps. |
| `cfast_bedroom_closed_door` | Good macro equivalence | CFAST Bedroom=3.5x3.0x2.4=25.2 m3; SimuFire `Dormitorio1` R2 has same size; door/window closed by case overrides. | Low | Keep. O2 failures are bulk/upper combustion gaps. |
| `cfast_two_room_door_open` | Good macro equivalence | R0 48.0 m3 and Hall 25.2 m3 match `simple_house`; R0-Hall door 0.9x2.0 open. | Low/medium | Keep, but treat RMSE as doorway enthalpy model gap. |
| `cfast_hvac_residential` | Good macro equivalence | R0 48.0 m3. CFAST supply 0.08 m3/s at 0.25 m and return at 2.30 m; SimuFire case uses `hvac_data` with 0.08 m3/s, supply height_fraction 0.1 (~0.24 m), return height_fraction 0.96 (~2.30 m), outside air fraction 1.0. | Low | Keep. Failure is HVAC upper/lower coupling, not geometry. |
| `cfast_pool_fire_open`, `cfast_post_flashover_vented`, `cfast_suppression_water` | Good opening geometry | R0 48.0 m3 and window 2.0x1.2 sill 0.8 match `simple_house` living-room window; cases open the window and close R0-Hall door. | Low | Keep. |
| `cfast_fast_growth_closed`, `cfast_single_room_closed`, `cfast_long_burnout_3600s`, `cfast_door_close_midfire` | Good macro equivalence | Single/two-room variants use R0 48.0 m3 and/or Hall 25.2 m3 matching `simple_house`. | Low | Keep. |
| `cfast_corridor_chain` | Geometry resolved; model gap remains | CFAST R2 was corrected from 3.5x4.0x2.4=33.6 m3 to 3.5x3.0x2.4=25.2 m3, matching SimuFire `simple_house` R2 (`Dormitorio1`). R0 and Hall already matched. | Low for geometry; medium/high for doorway model | Keep the corrected CFAST file and regenerated outputs. Remaining R0 t180/t600 failures are doorway mass+energy model gaps; R2 O2 non-required checks remain transport-model evidence, not geometry evidence. |
| `cfast_multi_fuel_couch_tv` | Topology resolved | CFAST `.in` has `DoorHall` from R0 to OUTSIDE, 0.9x2.0, open from start. SimuFire now represents this with an equivalent exterior opening 0.9x2.0, sill 0.0, `open_fraction=1.0`. Required RMSE is now 183.79°C <= 200°C. | Low for current required checks | Keep the equivalent exterior opening. Do not compare the current CFAST reference against a sealed SimuFire case. |
| `cfast_window_break_t180` | Opening geometry resolved | CFAST break window is 1.2x1.0, sill 0.8, lintel 1.8. SimuFire now overrides width/height/sill to match. The pressure known gap at t300 closes (1.89 Pa <= 10 Pa). | Low | Keep explicit opening geometry in the case so future template changes do not silently alter this reference. |
| `cfast_two_floor_stairwell` | Deliberate reduced-order mismatch | CFAST collapses the stair path into direct `R0_Living` to `R8_Upper` vent. SimuFire uses full `two_storey_house` path with stair rooms and a heat-bridge override. The `.in` comments explicitly call this an approximation. | Medium | Keep only as coarse stack-effect sentinel; not a strict geometry validation case. |

## Ghanekar Cases

| Case | Geometry/topology status | Evidence | Risk | Action |
|------|--------------------------|----------|------|--------|
| `ghanekar_bedroom_hallway` | Approximate empirical model | Template matches some paper traits: ranch-like plan, 2.45 m ceiling, bedroom fire, bedroom window 1.8x0.6 open, main exterior door open, far hallway metric. But the paper uses localized 0.9 m probes, sampling-line delay 16-23 s, HCN, and a specific full-scale floor plan not fully encoded here. | Medium | Keep as empirical trend check, not exact reproduction. Add future 0.9 m probe/postprocess case before claiming paper-level validation. |
| `ghanekar_kitchen_living_room` | Topology mismatch / known weak model | Ghanekar reference says kitchen fire has 0.9x0.9 m kitchen window open/removed. Historical analysis found production case uses fire in R3/living area and does not faithfully use the R4 kitchen-window topology; exploratory R4 variant still failed because R4-R3 opening is huge and heat dissipates into living area. | High | Do not use as proof of strict Ghanekar kitchen equivalence. Redesign the case from the paper floor plan or mark as empirical/loose benchmark only. |

## Priority Fix Queue

1. **Done: multifuel topology**
   - SimuFire now uses an equivalent exterior opening to CFAST `DoorHall` (0.9x2.0 open from t=0).
   - Required multifuel RMSE passes after regeneration.

2. **Done: corridor_chain R2 volume**
   - CFAST R2 now matches the SimuFire template at 25.2 m3.
   - CFAST outputs and SimuFire validation report were regenerated.

3. **Done: window_break_t180 window geometry**
   - Explicit opening geometry override added in `cfast_window_break_t180.json`.
   - Existing required passes remain stable; pressure known gap closes.

4. **High: Ghanekar kitchen**
   - Stop treating current production case as a strict experimental replica.
   - Build a new `ghanekar_kitchen_0_9m` case from the empirical reference with the kitchen window opened and a defined 0.9 m sampling point.

5. **Medium: Ghanekar bedroom**
   - Keep current case as approximate.
   - Add explicit documentation that PASS means selected timing benchmarks pass, not full paper reproduction.

## Implication For Current 14 FAIL Baseline

The original audit changed interpretation; the follow-up equivalence fixes changed the baseline count from 15 to 14 required FAILs.

- Group A, B, D and HVAC failures are still mainly engine/model architecture gaps.
- `cfast_corridor_chain` no longer has the R2 geometry caveat; current required failures are R0 temperature and remain doorway thermal/Phase 2 gaps.
- `cfast_multifuel_rmse_temp_upper_c` is no longer a required FAIL after matching the exterior venting topology.
- `cfast_window_break_t180` no longer has the window-geometry caveat; its t300 pressure known gap now passes.

## Rule For Future Validation Cases

Every CFAST/Ghanekar validation case should have a model-equivalence row before calibration:

| Required field | Example |
|----------------|---------|
| Room dimensions/volumes | `R0: CFAST 48.0 m3 == SF 48.0 m3` |
| Interior openings | `R0-Hall door: 0.9x2.0, open fraction schedule identical` |
| Exterior openings | `Window: 2.0x1.2 sill 0.8, schedule identical` |
| Fire location and HRR curve | `R0 center, alpha/cap/table equivalent` |
| HVAC/supply/return | `Supply/return height and flow equivalent` |
| Measurement point | `upper layer`, `bulk`, `0.9 m probe`, or RMSE window |
| Known approximations | e.g. `stairwell collapsed`, `paper floor plan approximate` |
