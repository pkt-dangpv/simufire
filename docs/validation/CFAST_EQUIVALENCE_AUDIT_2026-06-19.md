# CFAST equivalence audit — 2026-06-19

Scope: historical audit of the required FAIL checks as they existed on 2026-06-19. Current validation state is maintained in `docs/validation/STATUS_VALIDATION.md`.

Purpose: separate real SimuFire engine gaps from CFAST/SimuFire scenario mismatch, validator mismatch, and stale reference data. This audit did not change motor code, tolerances, or required/non-required classifications. The follow-up equivalence fixes changed validation case geometry/topology and regenerated reports where needed.

## Summary

SimuFire is not exactly equivalent to CFAST for the remaining failing checks. It has two-zone state variables and several two-zone transport mechanisms, but the failing paths still use hybrid/bulk behavior for combustion, oxygen consumption, doorway enthalpy exchange, or HVAC lower-layer replenishment.

Classification at the time of this audit:

| Class | Count | Meaning |
|-------|------:|---------|
| `VALID_GAP` | 14 | Scenario is close enough for validation; failure reflects a real SimuFire architecture/model gap. |
| `RESOLVED_EQUIVALENCE` | 1 | `cfast_multifuel_rmse_temp_upper_c` was removed from the required FAIL set after matching the CFAST exterior venting topology and regenerating the report. |
| `STALE_REFERENCE` | 0 | No current required FAIL depends on a stale tracked value after report regeneration. |
| `MODEL_MISMATCH` | 0 | The known CFAST model mismatches found in this audit were corrected or moved out of the current required FAIL set. |
| `CHECK_MISMATCH` | 0 | No current required FAIL appears to compare the wrong SF variable by accident. Several checks intentionally compare SF `o2_upper` to CFAST `ULO2`; the failures expose model gaps rather than validator bugs. |

The practical result was important at the time: the then-remaining failures should not be treated as proof that CFAST and SimuFire scenarios are exactly equal. They were a validation ledger over partially equivalent scenarios, and the audit confidence differed by cluster.

## Audit Table

| Check(s) | Case | Class | Evidence | Recommended action |
|----------|------|-------|----------|--------------------|
| `cfast_t240_o2_depleted`, `cfast_t350_o2`, `cfast_t360_o2` | `cfast_r0_window_360` | `VALID_GAP` | Case is closed until t=360 s. In legacy mode, fire throttle uses bulk/room O2 while CFAST depletes the upper layer directly. `fire_o2_full_hrr_open=0.15` is inactive pre-opening because `early_opening_signal=0`. | Keep as Phase 2 gap. Do not tune `fire_o2_full_hrr_open` or opening smoothing for these checks. |
| `cfast_slow_t480_temp_upper_c`, `cfast_slow_t600_temp_upper_c` | `cfast_slow_growth_sealed` | `VALID_GAP` | Sealed topology matches well enough, but SF thermal/O2 coupling cannot match both upper temperature and O2. Lowering `chi_rad` helps temperature but breaks tight O2 margins. | Keep as Phase 2/ZoneFireSolver gap. No per-case scalar fix. |
| `cfast_chain_r0_t180_temp_upper_c`, `cfast_chain_r0_t600_temp_upper_c` | `cfast_corridor_chain` | `VALID_GAP` | Door chain topology is represented, but thermal curve shape still differs after M3/canonical: early overshoot and late undershoot. t300 was fixed by `doorway_thermal_counterflow_gain=0.25`; t180/t600 remain mass+energy doorway gaps. | Keep as M3/Phase 2 gap. Avoid more gain sweeps unless paired with full curve criteria. |
| `cfast_bed_o2_t120_o2`, `cfast_bed_o2_t300_o2`, `cfast_bed_o2_t480_o2`, `cfast_bed_o2_t600_o2`, `cfast_bed_o2_t720_o2` | `cfast_bedroom_closed_door` | `VALID_GAP` | Closed bedroom topology is comparable, but SF case has no explicit `validation_fire_o2_mode`; legacy combustion consumes bulk/room O2 while checks compare SF `o2_upper` to CFAST `ULO2`. The validator comments for this block are stale because they still describe these O2 gaps as small/pass. | Keep as Phase 2 gap. Update validator comments later; do not change check variable. |
| `cfast_2r_r0_rmse_temp_upper_c` | `cfast_two_room_door_open` | `VALID_GAP` | Door-open two-room topology is represented, but SF lacks fully validated CFAST-equivalent bidirectional two-zone enthalpy exchange across rooms. The RMSE integrates drift rather than a point spike. Topology fix applied 2026-06-19: closed Pasillo↔Dorm1 (r1↔r2) and Salon↔Cocina (r0↔r4) to match CFAST 2-compartment model — zero effect on RMSE=88.0°C confirmed by fresh run. Root cause: O2u in R0 depletes to 3.96% by t=180s; Pasillo O2u=20.7% (fresh) cannot replenish R0 without canonical_doorway_exchange. | Keep as C3/Phase 2 gap. Topology fix maintained. No further per-case scalar fix is available. |
| `cfast_hvac_t300_o2` | `cfast_hvac_residential` | `VALID_GAP` | HVAC topology is represented in the case JSON: outside air supplied low, return high. The failure is in coupling: `fire_o2_lower_for_flame=true` uses lower O2 for throttle, while upper O2 can collapse without CFAST-like upper/lower exchange. | Keep as C2/Phase 2C gap. Do not re-enable M2 globally or per-case without isolation tests. |
| `cfast_multifuel_rmse_temp_upper_c` | `cfast_multi_fuel_couch_tv` | `RESOLVED_EQUIVALENCE` | Original tracked case was sealed while CFAST has a 0.9x2.0 exterior opening from t=0. After adding the equivalent exterior opening to the SimuFire case and regenerating the report, RMSE=183.79°C against max 200°C and all required multifuel checks pass. | Keep the equivalent opening. Treat remaining multifuel pressure t120 as non-required pressure-model gap. |

## Findings

1. The remaining required FAILs are all currently classified as valid architecture/model gaps. Multifuel was removed from this set by correcting the scenario topology and regenerating the report.

2. The validator is not obviously comparing the wrong variable for the 14 required FAILs. The `o2_upper` comparisons are intentional because CFAST references are upper-layer values. The failures show that SF upper-layer state is not yet driven by equivalent combustion/transport paths.

3. Documentation and code comments are partly fresher than each other. `STATUS_VALIDATION.md` captures the bedroom attribution correction and multifuel resolution, but `validate_reference_cases.py` still has stale comments in the bedroom/multifuel areas that describe older pass margins.

4. Exact scenario equivalence has not been proven for every CFAST case. It is strongest for sealed/simple topology checks and weaker for doorway/HVAC coupling checks. Multifuel venting is now represented at the macro opening level.

## Next Actions

1. Keep `cfast_multi_fuel_couch_tv` on the equivalent exterior-opening topology; do not revert it to sealed while comparing against the current CFAST reference.

2. Add a future cleanup task to refresh stale comments in `scripts/simulation/validate_reference_cases.py` for bedroom O2 and historical multifuel RMSE. This is documentation/comment debt, not a validator logic bug.

3. Before Phase 2 implementation, build a small equivalence checklist per CFAST case: topology, openings to exterior, fire location/source, oxygen variable, HVAC routing, and RMSE window.

4. Historical note: after the report regeneration that resolved multifuel, future baseline movement was expected to come from fresh case runs plus review of all required and non-required checks for each case. The current baseline is documented in `STATUS_VALIDATION.md`.
