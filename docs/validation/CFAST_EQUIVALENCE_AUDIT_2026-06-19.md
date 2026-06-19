# CFAST equivalence audit — 2026-06-19

Scope: the 15 current required FAIL checks in `sim/validation/reports/reference_checks.json`.

Purpose: separate real SimuFire engine gaps from CFAST/SimuFire scenario mismatch, validator mismatch, and stale reference data. This audit does not change motor code, tolerances, cases, reports, or required/non-required classifications.

## Summary

SimuFire is not exactly equivalent to CFAST for the remaining failing checks. It has two-zone state variables and several two-zone transport mechanisms, but the failing paths still use hybrid/bulk behavior for combustion, oxygen consumption, doorway enthalpy exchange, HVAC lower-layer replenishment, or exterior venting.

Current classification:

| Class | Count | Meaning |
|-------|------:|---------|
| `VALID_GAP` | 14 | Scenario is close enough for validation; failure reflects a real SimuFire architecture/model gap. |
| `STALE_REFERENCE` | 1 | The tracked reference value does not match fresh case diagnostics and should be regenerated before using the number for calibration. |
| `MODEL_MISMATCH` | 1 | Also applies to the stale multifuel check: CFAST vented exterior topology is not represented by the tracked SimuFire case topology. |
| `CHECK_MISMATCH` | 0 | No current required FAIL appears to compare the wrong SF variable by accident. Several checks intentionally compare SF `o2_upper` to CFAST `ULO2`; the failures expose model gaps rather than validator bugs. |

The practical result is important: the remaining 15 FAILs should not be treated as proof that CFAST and SimuFire scenarios are exactly equal. They are a validation ledger over partially equivalent scenarios, and the audit confidence differs by cluster.

## Audit Table

| Check(s) | Case | Class | Evidence | Recommended action |
|----------|------|-------|----------|--------------------|
| `cfast_t240_o2_depleted`, `cfast_t350_o2`, `cfast_t360_o2` | `cfast_r0_window_360` | `VALID_GAP` | Case is closed until t=360 s. In legacy mode, fire throttle uses bulk/room O2 while CFAST depletes the upper layer directly. `fire_o2_full_hrr_open=0.15` is inactive pre-opening because `early_opening_signal=0`. | Keep as Phase 2 gap. Do not tune `fire_o2_full_hrr_open` or opening smoothing for these checks. |
| `cfast_slow_t480_temp_upper_c`, `cfast_slow_t600_temp_upper_c` | `cfast_slow_growth_sealed` | `VALID_GAP` | Sealed topology matches well enough, but SF thermal/O2 coupling cannot match both upper temperature and O2. Lowering `chi_rad` helps temperature but breaks tight O2 margins. | Keep as Phase 2/ZoneFireSolver gap. No per-case scalar fix. |
| `cfast_chain_r0_t180_temp_upper_c`, `cfast_chain_r0_t600_temp_upper_c` | `cfast_corridor_chain` | `VALID_GAP` | Door chain topology is represented, but thermal curve shape still differs after M3/canonical: early overshoot and late undershoot. t300 was fixed by `doorway_thermal_counterflow_gain=0.25`; t180/t600 remain mass+energy doorway gaps. | Keep as M3/Phase 2 gap. Avoid more gain sweeps unless paired with full curve criteria. |
| `cfast_bed_o2_t120_o2`, `cfast_bed_o2_t300_o2`, `cfast_bed_o2_t480_o2`, `cfast_bed_o2_t600_o2`, `cfast_bed_o2_t720_o2` | `cfast_bedroom_closed_door` | `VALID_GAP` | Closed bedroom topology is comparable, but SF case has no explicit `validation_fire_o2_mode`; legacy combustion consumes bulk/room O2 while checks compare SF `o2_upper` to CFAST `ULO2`. The validator comments for this block are stale because they still describe these O2 gaps as small/pass. | Keep as Phase 2 gap. Update validator comments later; do not change check variable. |
| `cfast_2r_r0_rmse_temp_upper_c` | `cfast_two_room_door_open` | `VALID_GAP` | Door-open two-room topology is represented, but SF lacks fully validated CFAST-equivalent bidirectional two-zone enthalpy exchange across rooms. The RMSE integrates drift rather than a point spike. | Keep as C3/Phase 2 gap. Diagnose only with a full doorway thermal model plan. |
| `cfast_hvac_t300_o2` | `cfast_hvac_residential` | `VALID_GAP` | HVAC topology is represented in the case JSON: outside air supplied low, return high. The failure is in coupling: `fire_o2_lower_for_flame=true` uses lower O2 for throttle, while upper O2 can collapse without CFAST-like upper/lower exchange. | Keep as C2/Phase 2C gap. Do not re-enable M2 globally or per-case without isolation tests. |
| `cfast_multifuel_rmse_temp_upper_c` | `cfast_multi_fuel_couch_tv` | `STALE_REFERENCE` + `MODEL_MISMATCH` | Tracked `reference_checks.json` reports `actual=200.86` while the fresh sealed-case diagnostic documented RMSE=232.5. The `open_fraction=0.25` experiment gave fresh RMSE=204.65 and broke internal smoke/final-temperature checks, then was reverted. Separately, the CFAST reference behaves like a vented exterior-door scenario while the tracked SF case has `open_fraction=0.0`, so the topology is not equivalent. | Regenerate the baseline multifuel report/checks deliberately before any calibration. Keep classified as C3 topology mismatch unless a new case maps CFAST exterior venting faithfully. |

## Findings

1. The remaining required FAILs are not all the same kind of evidence. Most are valid architecture gaps, but multifuel currently mixes a stale tracked reference value with a topology mismatch.

2. The validator is not obviously comparing the wrong variable for the 15 required FAILs. The `o2_upper` comparisons are intentional because CFAST references are upper-layer values. The failures show that SF upper-layer state is not yet driven by equivalent combustion/transport paths.

3. Documentation and code comments are partly fresher than each other. `STATUS_VALIDATION.md` already captures the bedroom attribution correction and multifuel vented/sealed diagnosis, but `validate_reference_cases.py` still has stale comments in the bedroom and multifuel sections that describe older pass margins.

4. Exact scenario equivalence has not been proven for every CFAST case. It is strongest for sealed/simple topology checks, weaker for doorway/HVAC coupling checks, and weakest for multifuel venting.

## Next Actions

1. Do not use the current `cfast_multifuel_rmse_temp_upper_c` value in `reference_checks.json` as a calibration target until the report is regenerated from the restored baseline case.

2. Add a future cleanup task to refresh stale comments in `scripts/simulation/validate_reference_cases.py` for bedroom O2 and multifuel RMSE. This is documentation/comment debt, not a validator logic bug.

3. Before Phase 2 implementation, build a small equivalence checklist per CFAST case: topology, openings to exterior, fire location/source, oxygen variable, HVAC routing, and RMSE window.

4. Keep the validation baseline at 15/350 until reports are deliberately regenerated and reviewed. If multifuel fresh baseline replaces the stale tracked value, the count likely remains 15, but the RMSE magnitude should be corrected.
