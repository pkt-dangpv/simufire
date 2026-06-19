# CFAST/Ghanekar model audit — 2026-06-19

Scope: geometry/topology equivalence between SimuFire validation cases, CFAST `.in` files, and the Ghanekar empirical reference. This audit checks whether the *dwelling models* used for comparison are valid enough before further calibration work.

No motor code, cases, reports, tolerances, or baselines were changed.

## Verdict

Some validation models are valid approximations, but several are not equivalent enough for strict calibration. The highest-risk discrepancies are topological, not numeric:

1. `cfast_multi_fuel_couch_tv`: CFAST has an open exterior door; SimuFire models a closed exterior window. This is a direct scenario mismatch.
2. `cfast_corridor_chain`: CFAST R2 volume is 33.6 m3; SimuFire `simple_house` room 2 is 25.2 m3. This can bias far-room O2/smoke transport and any R2 curve interpretation.
3. `cfast_window_break_t180`: CFAST break window is 1.2 x 1.0 m; SimuFire uses the template living-room window 2.0 x 1.2 m because the case only overrides `open_fraction`.
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
| `cfast_corridor_chain` | Volume mismatch | CFAST R2=3.5x4.0x2.4=33.6 m3, but SimuFire `simple_house` R2 (`Dormitorio1`) is 3.5x3.0x2.4=25.2 m3. R2 is 33% larger in CFAST. R0 and Hall match. | High | Do not treat R2 O2/smoke timing as strict until fixed. Either change CFAST R2 to 3.5x3.0 or create a dedicated SF case/template with R2 length 4.0. Re-run CFAST and SF after deciding. |
| `cfast_multi_fuel_couch_tv` | Topology mismatch | CFAST `.in` has `DoorHall` from R0 to OUTSIDE, 0.9x2.0, open from start. SimuFire case has only R0 exterior `window` with `open_fraction=0.0`; no equivalent open exterior door. This makes CFAST vented and SF effectively sealed. | Critical | Do not calibrate RMSE against current pair. Build an equivalent SF case with exterior door open, or regenerate CFAST as sealed. Current `cfast_multifuel_rmse_temp_upper_c` should remain suspect/stale. |
| `cfast_window_break_t180` | Opening geometry mismatch | CFAST break window is 1.2x1.0, sill 0.8, lintel 1.8. SimuFire `simple_house` R0 window is 2.0x1.2, sill 0.8, lintel 2.0. The case only overrides `open_fraction`, so SF opening area is 2.4 m2 vs CFAST 1.2 m2 after break. | Medium/high | Add `width_m=1.2`, `height_m=1.0`, `sill_m=0.8` to the SF case before using it for strict window-break calibration. Re-run and review. |
| `cfast_two_floor_stairwell` | Deliberate reduced-order mismatch | CFAST collapses the stair path into direct `R0_Living` to `R8_Upper` vent. SimuFire uses full `two_storey_house` path with stair rooms and a heat-bridge override. The `.in` comments explicitly call this an approximation. | Medium | Keep only as coarse stack-effect sentinel; not a strict geometry validation case. |

## Ghanekar Cases

| Case | Geometry/topology status | Evidence | Risk | Action |
|------|--------------------------|----------|------|--------|
| `ghanekar_bedroom_hallway` | Approximate empirical model | Template matches some paper traits: ranch-like plan, 2.45 m ceiling, bedroom fire, bedroom window 1.8x0.6 open, main exterior door open, far hallway metric. But the paper uses localized 0.9 m probes, sampling-line delay 16-23 s, HCN, and a specific full-scale floor plan not fully encoded here. | Medium | Keep as empirical trend check, not exact reproduction. Add future 0.9 m probe/postprocess case before claiming paper-level validation. |
| `ghanekar_kitchen_living_room` | Topology mismatch / known weak model | Ghanekar reference says kitchen fire has 0.9x0.9 m kitchen window open/removed. Historical analysis found production case uses fire in R3/living area and does not faithfully use the R4 kitchen-window topology; exploratory R4 variant still failed because R4-R3 opening is huge and heat dissipates into living area. | High | Do not use as proof of strict Ghanekar kitchen equivalence. Redesign the case from the paper floor plan or mark as empirical/loose benchmark only. |

## Priority Fix Queue

1. **Critical: multifuel topology**
   - Decide whether the intended reference is vented or sealed.
   - If vented: add an exterior door/opening equivalent to CFAST `DoorHall` (0.9x2.0 open from t=0), not a closed window.
   - If sealed: regenerate CFAST without the exterior door.

2. **High: corridor_chain R2 volume**
   - Choose one canonical R2 size.
   - Prefer matching the SimuFire template unless the CFAST scenario intentionally wants a 4.0 m bedroom.
   - Re-run both references after changing either side.

3. **Medium/high: window_break_t180 window geometry**
   - Add explicit opening geometry override in `cfast_window_break_t180.json`.
   - Re-run the case and check whether existing passes remain stable.

4. **High: Ghanekar kitchen**
   - Stop treating current production case as a strict experimental replica.
   - Build a new `ghanekar_kitchen_0_9m` case from the empirical reference with the kitchen window opened and a defined 0.9 m sampling point.

5. **Medium: Ghanekar bedroom**
   - Keep current case as approximate.
   - Add explicit documentation that PASS means selected timing benchmarks pass, not full paper reproduction.

## Implication For Current 15 FAIL Baseline

This audit changes interpretation, not the current baseline count.

- Group A, B, D and HVAC failures are still mainly engine/model architecture gaps.
- `cfast_corridor_chain` now has an additional geometry caveat for R2; current required failures are R0 temperature, but R2 O2 non-gating checks should not be used as strict evidence until the R2 volume is reconciled.
- `cfast_multifuel_rmse_temp_upper_c` should be treated as invalid for strict calibration until the vented/sealed mismatch and stale reference value are corrected.

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
