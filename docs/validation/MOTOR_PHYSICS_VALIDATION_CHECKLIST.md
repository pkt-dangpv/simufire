# Motor Physics Validation Checklist

Date: 2026-06-24.

This checklist tracks the physics and validation items that must be audited before treating the SimuFire motor as physically credible. It is intentionally focused on engine data and validation, not first-person visuals or presentation-layer effects.

## Scope

Primary goal: validate that the engine produces physically coherent data across combustion, two-zone transport, toxic gases, smoke, pressure, wall heat exchange and tenability.

Out of scope for this phase:

- First-person visual polish.
- HVAC, until the core fire, gas, smoke, pressure and two-zone behavior is stable.
- Global motor changes without an explicit validation plan.
- Widening tolerances or rewriting reports to force PASS.

## Baseline Principle

Validation must check more than isolated final values. Each scenario should be traceable through:

1. Source generation.
2. Storage by room and layer.
3. Transport between layers, rooms and exterior.
4. Conversion to observable metrics.
5. Comparison against CFAST or documented realistic scenarios.
6. Temporal consistency over the full fire, not only single checkpoints.

## 1. HRR And Energy

Items to check:

- HRR magnitude against fuel, pyrolysis and available oxygen.
- Integrated HRR against fuel energy consumed and `fuel_remaining_MJ`.
- Coherence among `hrr_kw`, `burned_hrr_kw`, `pyrolysis_kw` and `unburned_generation_kw`.
- Fuel-controlled, ventilation-controlled, smoldering, latent, extinguished and reventilation transitions.
- HRR response when doors/windows change the oxygen supply.
- Long-fire stability: no artificial HRR plateaus, spikes or zombie fires.
- Energy budget consistency with wall absorption, wall reradiation, ventilation losses and gas temperature.

Current auditor coverage:

- A2: HRR without fuel is checked.
- A3: fuel-controlled/full-developed regime with critical upper-layer O2 is checked.
- ILV HRR-zombie pattern is checked by the ILV coherence auditor.

Open gaps:

- Full HRR integrated-energy balance.
- Oxygen-limited HRR magnitude validation, not only zombie detection.
- Reventilation growth validation.

## 2. Oxygen

Items to check:

- O2 consumption from HRR and combustion chemistry.
- O2 storage by bulk, upper and lower layer: `o2`, `o2_upper`, `o2_lower`.
- O2 inflow through lower openings and outflow/entrainment through upper layers.
- O2 transport between connected rooms and exterior.
- O2 response to remote ventilation: opening a window in another room should affect the fire if doors connect the spaces.
- O2 and HRR coupling during ventilation-controlled burning.
- O2 recovery after extinguishment or ventilation changes.

Open gaps:

- Full O2 mass balance by room/layer.
- Door/window flow validation against two-zone expectations.
- Multi-floor convection and oxygen path validation.

## 3. CO, CO2 And HCN

Items to check:

- CO, CO2 and HCN generation from combustion yields.
- Yield dependence on fuel, ventilation state and `o2_hrr_factor`.
- Carbon budget enforcement.
- Transport conservation between rooms, layers and exterior.
- Distinguish local generation from imported gases.
- PPM conversion from internal mass and layer volume/density.
- CO/CO2/HCN consistency with FED and tenability metrics.

### D1 CO Mass Balance — CLOSED (2026-06-24, commit b41fcbd + promotion)

Rule D1 verifies per-room, per-step CO mass balance:

```
delta_co = co_kg[t] - co_kg[t-1]
expected = delta(co_generated_kg_total) + delta(co_net_transport_kg_total) - delta(co_exterior_removed_kg_total)
residual = abs(delta_co - expected)
threshold = max(1e-6, 0.05 * max(abs(expected), 1e-6))
```

D1 is **FAIL-gating** as of 2026-06-24. Validated on 5 permanent CSVs (0 findings across all).

Three previously untracked CO paths were instrumented (commit b41fcbd):

1. `GasExchangeSystem._purge_upper_species_to_exterior_direct` — two_zone=true pressure-venting branch now accumulates `co_exterior_removed_kg_total`.
2. `ThermalSystem._flush_contaminant_deltas` — hot-gas carry between rooms now accumulates `co_net_transport_kg_total` using actual post-clamp delta (`room.co_kg - _co_pre_thermal`).
3. `GasExchangeSystem._release_pending_interior_deliveries` — delayed inter-room CO deliveries now accumulate `co_net_transport_kg_total` using actual post-clamp delta (`target.co_kg - _co_pre_delivery`).

Semantic note: `co_net_transport_kg_total` is a broad net transport field. It includes inter-room exchange, hot-gas carry (ThermalSystem), and delayed interior deliveries — not only direct room-to-room doorway flow.

Required CSV columns: `co_kg`, `co_generated_kg_total`, `co_net_transport_kg_total`, `co_exterior_removed_kg_total`, `time_s`, `room_id`. D1 is silently skipped for CSVs that lack these columns.

### Current Toxic Gas Audit Findings

Internal storage:

- `co_kg`: total room CO mass.
- `co_upper_kg`: upper-layer CO mass.
- `co2_kg`: total room CO2 mass.
- `co2_upper_kg`: upper-layer CO2 mass.
- `co2_upper`: calibrated mole fraction tracer, not derived from `co2_upper_kg`.
- `hcn_kg`: total room HCN mass.
- `hcn_upper_kg`: upper-layer HCN mass.
- `c_burned_total_kg`: accumulated burned carbon.
- `c_exited_kg`: carbon exited through openings.
- `c_balance_frac`: unclamped-yield fraction; `1.0` means no carbon clamp, lower values mean clamp active.
- `carbon_conservation_error_kg`: gas carbon minus burned carbon; negative can mean carbon exited, positive suggests spurious creation.

Generation pipeline:

- CO generation is phi-dependent and HRR-based.
- CO yield is boosted in ventilation-limited and afterburning conditions.
- CO, CO2 and HCN generation are clamped by carbon budget (`SF-AUD-032`).
- Generated CO is added to `co_kg` and partitioned to `co_upper_kg`.

Transport:

- Gas transport uses delta accumulators and applies deltas at the end of the step.
- Doorway counterflow is bidirectional and proportional to exchanged air mass.
- Exterior ventilation and purge remove species; they should not create them.
- Smoke-CO coupling moves CO with smoke during doorway smoke movement.

Conversion to ppm:

- Bulk `co_ppm`, `co2_ppm` and `hcn_ppm` use constant density `1.2 kg/m3`.
- Upper-layer `co_upper_ppm` and `hcn_upper_ppm` use temperature-corrected layer density.
- `co2_upper_ppm` is computed from `co2_upper * 1e6`, not from `co2_upper_kg`.

Important caveats:

- `co2_upper_ppm` is not directly comparable to `co_upper_ppm`, because CO upper ppm is mass-derived while CO2 upper ppm is tracer-derived.
- A naive "CO rises without local HRR" rule is invalid in multi-room cases: CO can be transported from a burning room into a non-burning room.
- D1 CO-zombie detection requires local generation instrumentation, not only room-local concentration deltas.

Rules viable from current CSV columns:

- **D1**: CO mass balance — FAIL-gating, closed 2026-06-24.
- D2: CO/CO2 ratio out of expected range. Blocked: `co2_upper_ppm` uses a tracer path, not mass-derived. Do not implement until CO2 dual tracking is resolved.
- D3: CO absent with high HRR.
- D4: HCN present with zero CO.
- D5: CO/HRR/O2 magnitude consistency.

Instrumentation now available in CSV (as of 2026-06-24):

- `co_generated_kg_step`, `co2_generated_kg_step`, `hcn_generated_kg_step` per room and step.
- `co_net_transport_kg_step` per room and step (net, not split in/out).
- `co_generated_kg_total`, `co_net_transport_kg_total`, `co_exterior_removed_kg_total` per room (cumulative).
- `c_balance_frac`, `carbon_conservation_error_kg` per room and step.

Remaining gap: `co_transported_in_kg` and `co_transported_out_kg` (split in/out) are not tracked separately. `co_net_transport_kg_total` covers the net; split tracking would require additional instrumentation.

## 4. Smoke And Soot

Items to check:

- Smoke/soot generation against HRR, fuel and regime.
- Smoke transport conservation between rooms and layers.
- Coupling between smoke movement, CO movement and hot-layer transport.
- Smoke cooling over time when HRR falls.
- Smoke descent when cooled gases lose buoyancy and there is room below the hot layer.
- Relationship among `smoke_kg`, `visibility_m`, layer heights and ventilation.

Open gaps:

- Smoke mass balance by room/layer.
- Soot-yield validation.
- Cooling/descent validation.

## 5. Smoke Height, Layer Interfaces And Neutral Plane

Items to check:

- `smoke_layer_m`, `thermal_layer_m`, `visible_smoke_layer_m`, `flow_interface_m` and `hot_layer_m`.
- Neutral plane height.
- `layer_150c_m` / 150 C isotherm.
- Layer response to window and door changes.
- Layer response in multi-room and multi-floor fires.
- Directional interpretation: thermal and optical layer heights should not be blindly compared with `abs()` until conventions are confirmed.

Current B3 probe result:

- Existing corpus is too small to calibrate `abs(thermal_layer_m - smoke_layer_m)`.
- One transient outlier at 0.135 m appears physically legitimate.
- Do not implement B3 yet; revisit after a richer CSV corpus exists.

## 6. Visibility

Items to check:

- `visibility_m` derived from smoke/soot concentration, not from presentation-layer effects.
- Visibility degradation with smoke mass and layer position.
- Visibility recovery under ventilation/dilution.
- Consistency with FED, smoke layer and thermal state.

Open gaps:

- Need motor-side validation only; do not rely on first-person overlay behavior.
- Need scenarios where visibility curves can be compared against reference expectations.

## 7. FED And Tenability

Items to check:

- `fed = fed_co + fed_hcn + fed_hypoxia + fed_heat`.
- FED monotonicity.
- FED components correspond to CO, HCN, O2 and thermal conditions.
- Irritant FEC/HCl behavior where applicable.
- Long-duration accumulation behavior.

Current auditor coverage:

- C1: FED arithmetic.
- C2: FED monotonicity by room.

Open gaps:

- FED component magnitude validation against gas and temperature histories.
- HCN/FED coupling validation.

## 8. Temperatures

Items to check:

- `temp_upper_c` and `temp_lower_c` against HRR, ventilation, wall losses and layer height.
- No strong impossible inversion under active hot-layer conditions.
- Cooling after HRR decay.
- Temperature response to reventilation.
- Consistency with FED heat and 150 C isotherm.
- Consistency with wall temperature and wall reradiation.

Current auditor coverage:

- B1: strong thermal inversion.

Open gaps:

- Full energy balance.
- Cooling curves.
- Temperature response to remote ventilation and multi-room flows.

## 9. Two-Zone Model

Items to check:

- Upper/lower mass and energy storage.
- Upper/lower oxygen and gas species routing.
- Layer exchange and entrainment.
- Buoyancy: hot gases and smoke rise; cooler gases tend to descend or mix.
- Coupling between combustion, plume, hot layer and lower-layer oxygen.
- Stability over long fires.

Open gaps:

- Canonical two-zone mass and energy balance per layer.
- Explicit validation of two-zone flow equations against CFAST-like behavior.

## 10. Doors, Windows And Ventilation

Items to check:

- Partial door/window opening effects.
- Bidirectional flow through vertical openings.
- Upper hot-gas outflow and lower fresh-air inflow.
- Remote window effects through connected rooms.
- Multi-room and multi-floor convection paths.
- Pressure-driven direction and magnitude of flows.
- Reventilation and fire growth after opening changes.

Open gaps:

- Broad CFAST battery for opening fractions and remote ventilation.
- Multi-floor validation.
- Door/window transient validation.

## 11. Pressure

Items to check:

- `pressure_pa_therm` and `overpressure_pa` accumulation.
- Pressure by layer at a coarse two-zone level.
- Flow direction from pressure differences.
- Neutral plane calculation.
- Pressure response to fire growth, ventilation and cooling.

Recent lesson:

- A regression that reset `pressure_pa_therm` each step caused `cfast_closed_t120_pressure_pa` to fail. Pressure must be treated as a core validation signal, not an auxiliary output.

Open gaps:

- Coarse two-zone pressure ODE validation.
- Neutral plane validation.

## 12. Walls, Radiation And Heat Storage

Items to check:

- Radiative and convective absorption by walls.
- Wall heat capacity and saturation.
- Wall reradiation into rooms after saturation or HRR decay.
- Energy conservation among HRR, gases, walls, ventilation and residual terms.
- `wall_T_mid_c`, `bud_q_rad_kj`, `bud_de_upper_kj`, `bud_q_residual_kj`, `bud_chi_rad`.

Open gaps:

- Full wall heat budget validation.
- Long-fire wall reradiation curves.

## 13. Validation Battery

Required scenario families:

- Sealed single-room fires.
- Single-room with partial window openings.
- Door-open two-room fires.
- Remote window opened in a connected room.
- Multi-room corridor chains.
- Multi-floor convection cases.
- Long fires with cooling and wall reradiation.
- Reventilation cases.
- Toxic gas transport cases.
- Smoke/visibility cases.
- Pressure/neutral-plane cases.

Reference strategy:

- Compare against CFAST where possible.
- Use documented realistic scenarios where CFAST is not enough.
- Compare curves, not only point checks.
- Keep legacy/control cases separate from physical validation cases.
- Do not calibrate expected behavior around known bugs.

## 14. Instrumentation Backlog

High priority:

- Per-step local gas generation: `co_generated_kg`, `co2_generated_kg`, `hcn_generated_kg`.
- Per-step gas transport in/out by room: at least CO first.
- Carbon budget fields in CSV: `c_balance_frac`, `carbon_conservation_error_kg`.
- O2 consumed per room/step.
- Fuel energy consumed per room/step.
- Layer mass and energy terms in CSV for selected diagnostic cases.

Medium priority:

- Smoke generated and transported per step.
- Species exterior loss per step.
- Wall heat in/out per step.
- Neutral plane height.
- Door/window bidirectional flow components.

## 15. Current Priority Order

1. Keep the current auditors green and integrated.
2. Add missing instrumentation needed for gas and energy balances.
3. Build balance-based checks before heuristic checks.
4. Expand the CFAST/reference scenario battery.
5. Only then change motor physics, one subsystem at a time, behind explicit validation.

