# Phase 3 H3.2b3 — Shadow compare, legacy projection versus the pure primitive

Date: 2026-08-20
Status: **strictly passive shadow comparison. No authority, no application, no
commit.**

Created: `sim/core/Phase3ResidualProjectionShadow.gd`,
`tests/fixtures/phase3_h32b3_residual_projection_shadow.gd`,
`tests/test_phase3_h32b3_residual_projection_shadow.py`, this document, plus the
flag wiring in `SimulationEngine`, `scripts/run_scenario.py` and
`tools/run_scenario_headless.gd`.

Not touched: `ZoneFireSolver` (zero lines), legacy physics, the tick order, the
clamp, the thermal limit, CSV columns, reports, VALID_GAP, baselines, expected
values, tolerances. The primitive's output is computed, compared and discarded.

---

## 1. FASE 1 — the exact map, established before editing

**Is there a single point that sees pre-state and post-state under the same
cause?** Yes, and it already exists. `ZoneFireSolver.project_room_state()` emits
exactly one trace event per call (`ZoneFireSolver.gd:291-300`) carrying:

| field | meaning |
|---|---|
| `cause` | the `projection_cause` argument of this call |
| `room_id` | the room |
| `ambient_c` | the ambient temperature in force |
| `pre` | `_projection_state()` taken at entry, **before any mutation** |
| `ensured` | after `ensure_room_state()` |
| `pre_geometry` | after the temperature step, before the geometry rewrite |
| `post` | after the rewrite — what the engine actually wrote |
| `upper_volume_m3`, `lower_volume_m3` | the volumes legacy computed for itself |

That one event is the required point. **No blocker**, and no reconstruction from
CSV rows is needed or performed.

**How duplication with H3.2b1 is avoided.** Both ledgers read the same source.
`get_projection_trace_events()` returns `_projection_trace_events.duplicate(true)`
and does **not** consume, so two independent consumers cannot interfere.
`ZoneFireSolver` gains nothing: the shadow adds no hook, no snapshot and no
counter inside it, and a contract asserts the solver contains no reference to the
primitive or the shadow. `git diff --name-only HEAD -- sim/core/ZoneFireSolver.gd`
is empty, enforced by a test.

**What the trace does not carry: geometry.** `_projection_state()` holds
inventories, temperatures and `thermal_layer_m` only — no floor area, no room
height, no volume. The shadow therefore takes geometry from the caller, which
resolves it from `building.get_rooms()`. That is sound rather than an
approximation: room geometry is assigned once at construction
(`sim/BuildingModel.gd:641-643`) and nothing mutates `width_m`, `length_m` or
`height_m` during a run, so the values resolved at accumulate time are the values
in force during the call.

**Stored versus derivable.** Legacy *stores* `upper_gas_kg`, `lower_gas_kg`,
`upper_energy_kj`, `lower_energy_kj`, `temp_upper_c`, `temp_lower_c` and
`thermal_layer_m`, and the trace additionally records the densities and volumes
legacy computed. Legacy **stores no pressure and computes none** — it scales a
fixed reference density by an ambient/zone temperature ratio
(`ZoneFireSolver.gd:257`, `:275`). Nothing in this phase may therefore be called
a legacy pressure. See §5.

---

## 2. Wiring

| file | change |
|---|---|
| `sim/core/Phase3ResidualProjectionShadow.gd` | **new**, the passive accumulator |
| `sim/core/SimulationEngine.gd` | flag, trace-clear gate, one hook, geometry helper, accessor, opt-in summary block |
| `scripts/run_scenario.py` | `--phase3-residual-projection-shadow` |
| `tools/run_scenario_headless.gd` | the same flag, parsed and applied |
| `sim/core/ZoneFireSolver.gd` | **untouched** |
| CSV writer / state builder | **untouched** — no new column |

**The flag is isolated.** `phase3_residual_projection_shadow_enabled`, `@export`,
default `false`. Its setter enables the solver's own per-call trace, which is the
telemetry it needs, and **never writes
`phase3_projection_causal_diagnostics_enabled`**. Turning the shadow on does not
turn an H3.2b1 user into someone executing the primitive, and turning H3.2b1 on
does not start the shadow. Contracts pin both directions.

> **[PLAN CORRECTED 2026-08-20.]** The H3.2b0 phase table (§6) gave H3.2b3 the
> entry "same OFF flag" as H3.2b1. That is superseded. Reusing
> `phase3_projection_causal_diagnostics_enabled` would silently make every
> existing user of the H3.2b1 passive ledger start evaluating the primitive on
> every projection call, which is a different and much larger action than the one
> they opted into. H3.2b3 therefore ships its own flag.

**The hook runs immediately after `_phase3_projection_causal_accumulate()`**, on
purpose: H3.2b1 keeps its own "trace unavailable on the first step" semantics
unchanged, because the causal hook still sees the trace in whatever state it
would have seen it in.

**The trace-clear gate.** `_phase3_projection_diagnostics_active()` now includes
the shadow flag. Without that, `begin_projection_diagnostics_step()` would never
run for a shadow-only session and trace events would accumulate across steps,
counting every call many times over. This is also the assignment that
`_sync_auxiliary_services()` reasserts, which matters — see §10, finding 1.

---

## 3. What is compared

```
A  pre-state    the trace's `pre`: M_upper, E_upper, M_lower, E_lower,
                plus the room's floor area, height and the ambient temperature
B  residual     Phase3ResidualProjection.derive(A)
C  legacy post  the trace's `post`, what the engine actually wrote
```

The primitive returns `M` and `E` bit-identical to `A`, so **B's inventories are
A's**, and the inventory divergence B−C is the legacy rewrite seen from the other
side. Both directions are exported so the sign convention can never be guessed:

```
legacy_rewrite     = post - pre     (what legacy changed)
residual_vs_legacy = pre  - post    (residual minus legacy)
```

Per **room**, per **cause** and in **total**, for each of mass and energy in each
zone, plus interface, both volumes and both temperatures: `signed_net_total`,
`gross_absolute_total` and `max_absolute`. Net exactly zero is reported as
`net_exactly_zero` with a `null` ratio, never divided by. Gross is projection
churn and is documented as such — it is not a physical contribution and not a
source.

Every counter exists from the first step, so a reported zero is a measured zero
and never a missing key a reader has to interpret.


---

## 4. Isolation and run integrity

### T1 isolation and run integrity

| scenario | OFF sha256[:16] | ON sha256[:16] | byte-identical | lines | manifest | sim_time_s | summary delta |
|---|---|---|---|---:|---|---:|---|
| `cfast_corridor_chain` | `15a7a84fc1b0f8d8` | `15a7a84fc1b0f8d8` | **yes** | 79 | ok | 120.083 | opt-in block only |
| `cfast_r0_window_360` | `5ad6ea0de2796379` | `5ad6ea0de2796379` | **yes** | 79 | ok | 120.083 | opt-in block only |
| `cfast_two_floor_stairwell` | `5768d6658c127e99` | `5768d6658c127e99` | **yes** | 170 | ok | 120.083 | opt-in block only |
| `two_storey_smoke` | `dc101da56029cf7e` | `dc101da56029cf7e` | **yes** | 1574 | ok | 120.083 | opt-in block only |
| `ghanekar_bedroom_hallway` | `23fc8af1f816d2ab` | `23fc8af1f816d2ab` | **yes** | 131 | ok | 120.083 | opt-in block only |
| `piso_mediterraneo_smoke` | `523261ba8156ad0d` | `523261ba8156ad0d` | **yes** | 1211 | ok | 120.083 | opt-in block only |
| `uk_bungalow_smoke` | `48a44214643cbeac` | `48a44214643cbeac` | **yes** | 848 | ok | 120.083 | opt-in block only |
| `compact_apartment_smoke` | `952af0f39b766288` | `952af0f39b766288` | **yes** | 606 | ok | 120.083 | opt-in block only |
| `three_bed_apartment_smoke` | `a4fec1c749b58935` | `a4fec1c749b58935` | **yes** | 1090 | ok | 120.083 | opt-in block only |
| `flashover_simple_house` | `45e9b3972abd35f0` | `45e9b3972abd35f0` | **yes** | 727 | ok | 120.083 | opt-in block only |

---

## 5. Results

### T2 primitive outcome and presence

| scenario | calls | valid | invalid | invalid reasons | presence mismatch | data_available |
|---|---:|---:|---:|---|---:|---|
| `cfast_corridor_chain` | 73729 | 73729 | 0 | - | 0 | True |
| `cfast_r0_window_360` | 60568 | 60568 | 0 | - | 0 | True |
| `cfast_two_floor_stairwell` | 135461 | 135461 | 0 | - | 0 | True |
| `two_storey_smoke` | 138360 | 138360 | 0 | - | 0 | True |
| `ghanekar_bedroom_hallway` | 117142 | 117141 | 1 | energy_without_mass=1 | 0 | True |
| `piso_mediterraneo_smoke` | 114779 | 114779 | 0 | - | 0 | True |
| `uk_bungalow_smoke` | 82000 | 82000 | 0 | - | 0 | True |
| `compact_apartment_smoke` | 59938 | 59938 | 0 | - | 0 | True |
| `three_bed_apartment_smoke` | 100194 | 100194 | 0 | - | 0 | True |
| `flashover_simple_house` | 77071 | 77071 | 0 | - | 0 | True |

### T3 inventory divergence, residual minus legacy (kg, kJ)

| scenario | lower mass signed | lower mass gross | lower mass max | upper mass signed | upper mass gross | lower energy signed | lower energy gross | upper energy gross |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `cfast_corridor_chain` | -55.2581 | 474.3020 | 0.2277 | 0.0000 | 0.0000 | 287.562 | 287.562 | 0.062 |
| `cfast_r0_window_360` | -2.9108 | 21.4242 | 0.2104 | 0.0000 | 0.0000 | 17.416 | 17.416 | 0.000 |
| `cfast_two_floor_stairwell` | 6.2710 | 115.9511 | 0.3239 | 0.0000 | 0.0000 | 285.942 | 285.942 | 0.000 |
| `two_storey_smoke` | -0.8464 | 138.5758 | 0.2374 | 0.0000 | 0.0000 | 706.397 | 706.397 | 0.000 |
| `ghanekar_bedroom_hallway` | -0.2535 | 184.5918 | 1.0292 | 0.0000 | 0.0000 | 476.904 | 476.904 | 0.000 |
| `piso_mediterraneo_smoke` | 471.5677 | 615.2151 | 1.0352 | 0.0000 | 0.0000 | 857.720 | 857.720 | 0.041 |
| `uk_bungalow_smoke` | 330.5067 | 449.0470 | 1.5346 | 0.0000 | 0.0000 | 637.244 | 637.244 | 0.000 |
| `compact_apartment_smoke` | -1.2217 | 136.2643 | 0.4566 | 0.0000 | 0.0000 | 693.943 | 693.943 | 0.000 |
| `three_bed_apartment_smoke` | 96.6902 | 242.4271 | 0.9487 | 0.0000 | 0.0000 | 772.737 | 772.737 | 0.000 |
| `flashover_simple_house` | 503.8474 | 964.4115 | 1.4394 | 0.0000 | 0.0000 | 2734.138 | 2734.138 | 0.000 |

### T4 share of mass divergence from the lower rewrite

| scenario | lower gross kg | upper gross kg | total gross kg | lower share |
|---|---:|---:|---:|---:|
| `cfast_corridor_chain` | 474.3020 | 0.0000 | 474.3020 | **100.0000 %** |
| `cfast_r0_window_360` | 21.4242 | 0.0000 | 21.4242 | **100.0000 %** |
| `cfast_two_floor_stairwell` | 115.9511 | 0.0000 | 115.9511 | **100.0000 %** |
| `two_storey_smoke` | 138.5758 | 0.0000 | 138.5758 | **100.0000 %** |
| `ghanekar_bedroom_hallway` | 184.5918 | 0.0000 | 184.5918 | **100.0000 %** |
| `piso_mediterraneo_smoke` | 615.2151 | 0.0000 | 615.2151 | **100.0000 %** |
| `uk_bungalow_smoke` | 449.0470 | 0.0000 | 449.0470 | **100.0000 %** |
| `compact_apartment_smoke` | 136.2643 | 0.0000 | 136.2643 | **100.0000 %** |
| `three_bed_apartment_smoke` | 242.4271 | 0.0000 | 242.4271 | **100.0000 %** |
| `flashover_simple_house` | 964.4115 | 0.0000 | 964.4115 | **100.0000 %** |

### T5 interface, volume and temperature divergence

| scenario | interface gross m | interface max m | upper vol gross m3 | lower vol gross m3 | upper temp gross K | upper temp max K | lower temp gross K | temp comparable (u/l) |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `cfast_corridor_chain` | 5.5202 | 0.0043 | 70.792 | 70.792 | 0.409 | 0.409 | 11.216 | 32824/73729 |
| `cfast_r0_window_360` | 0.5129 | 0.0059 | 10.258 | 10.258 | 0.000 | 0.000 | 1.741 | 10133/60568 |
| `cfast_two_floor_stairwell` | 0.5621 | 0.0023 | 16.624 | 16.624 | 0.000 | 0.000 | 8.054 | 13770/135461 |
| `two_storey_smoke` | 0.7595 | 0.0017 | 21.874 | 21.874 | 0.000 | 0.000 | 15.504 | 18842/138360 |
| `ghanekar_bedroom_hallway` | 2.6859 | 0.0110 | 22.052 | 22.052 | 0.000 | 0.000 | 29.127 | 25395/117141 |
| `piso_mediterraneo_smoke` | 1.1543 | 0.0055 | 19.124 | 19.124 | 0.041 | 0.041 | 20.551 | 25844/114779 |
| `uk_bungalow_smoke` | 0.5959 | 0.0024 | 12.868 | 12.868 | 0.000 | 0.000 | 14.645 | 28389/82000 |
| `compact_apartment_smoke` | 1.0974 | 0.0038 | 17.756 | 17.756 | 0.000 | 0.000 | 21.313 | 25663/59938 |
| `three_bed_apartment_smoke` | 1.4037 | 0.0044 | 19.089 | 19.089 | 0.000 | 0.000 | 20.728 | 24525/100194 |
| `flashover_simple_house` | 5.0773 | 0.0056 | 86.961 | 86.961 | 0.000 | 0.000 | 146.366 | 27589/77071 |

### T6 pressures, correctly separated

| scenario | canonical_pressure_pre min | max | canonical_pressure_from_legacy_post min | max | post samples | post invalid |
|---|---:|---:|---:|---:|---:|---:|
| `cfast_corridor_chain` | 100582.2 | 102094.6 | 101318.6 | 101325.0 | 73729 | 0 |
| `cfast_r0_window_360` | 100950.4 | 101359.1 | 101320.4 | 101325.0 | 60568 | 0 |
| `cfast_two_floor_stairwell` | 100961.4 | 101627.4 | 101303.4 | 101325.0 | 135461 | 0 |
| `two_storey_smoke` | 101060.2 | 101575.4 | 101310.7 | 101325.0 | 138360 | 0 |
| `ghanekar_bedroom_hallway` | 98511.4 | 102268.0 | 101108.6 | 101325.0 | 117141 | 0 |
| `piso_mediterraneo_smoke` | 100362.4 | 104442.6 | 101310.6 | 101325.0 | 114779 | 0 |
| `uk_bungalow_smoke` | 100701.2 | 104701.4 | 101301.3 | 101325.0 | 82000 | 0 |
| `compact_apartment_smoke` | 100542.5 | 102714.8 | 101309.8 | 101325.0 | 59938 | 0 |
| `three_bed_apartment_smoke` | 100528.7 | 104565.0 | 101311.4 | 101325.0 | 100194 | 0 |
| `flashover_simple_house` | 99825.4 | 104702.1 | 101284.6 | 101325.0 | 77071 | 0 |

### T7 gross versus net churn, per cause (corpus-wide)

| cause | scenarios | calls | mass gross kg | mass signed kg | gross/|net| |
|---|---:|---:|---:|---:|---|
| `opening_radiation_target_sync` | 8/10 | 7001 | 1460.3799 | 1460.3799 | 1.00 |
| `gas_exchange_sync` | 10/10 | 133243 | 1348.0071 | -337.4888 | 3.99 |
| `thermal_post_combustion_sync` | 10/10 | 122485 | 308.7911 | 307.4297 | 1.00 |
| `thermal_energy_projection` | 10/10 | 122485 | 58.6059 | -58.6059 | 1.00 |
| `interior_background_target_sync` | 9/10 | 30486 | 34.7476 | 34.7476 | 1.00 |
| `interior_background_source_sync` | 9/10 | 30486 | 34.6180 | -34.6180 | 1.00 |
| `doorway_cold_target_sync` | 6/10 | 1709 | 23.4778 | 23.4778 | 1.00 |
| `doorway_hot_source_sync` | 6/10 | 1709 | 22.6503 | -22.6503 | 1.00 |
| `reconcile_layer_sync` | 10/10 | 244970 | 15.1909 | -15.1909 | 1.00 |
| `doorway_counterflow_cold_sync` | 1/10 | 2080 | 8.0792 | 8.0792 | 1.00 |
| `exterior_background_source_sync` | 1/10 | 3303 | 6.7959 | -6.7959 | 1.00 |
| `opening_radiation_source_sync` | 8/10 | 7001 | 6.3714 | -6.3714 | 1.00 |
| `doorway_counterflow_hot_sync` | 1/10 | 2080 | 5.3439 | -5.3439 | 1.00 |
| `exterior_background_target_sync` | 1/10 | 3303 | 5.2416 | 5.2416 | 1.00 |
| `thermal_post_losses_sync` | 10/10 | 122485 | 3.1371 | -3.1371 | 1.00 |
| `final_clamp_active` | 10/10 | 33320 | 0.7500 | -0.7500 | 1.00 |
| `post_transfer_vertical_mix_sync` | 6/10 | 1709 | 0.0105 | -0.0105 | 1.00 |
| `interlayer_source_sync` | 1/10 | 111 | 0.0060 | -0.0060 | 1.00 |
| `interlayer_target_sync` | 1/10 | 111 | 0.0058 | 0.0058 | 1.00 |
| `final_clamp_quiescent` | 10/10 | 89165 | 0.0000 | 0.0000 | net exactly 0 |

### T8 determinism repeats

| scenario | ON sha256[:16] | repeat sha256[:16] | csv identical | shadow totals identical |
|---|---|---|---|---|
| `cfast_corridor_chain` | `15a7a84fc1b0f8d8` | `15a7a84fc1b0f8d8` | **yes** | **yes** |
| `cfast_two_floor_stairwell` | `5768d6658c127e99` | `5768d6658c127e99` | **yes** | **yes** |
| `piso_mediterraneo_smoke` | `523261ba8156ad0d` | `523261ba8156ad0d` | **yes** | **yes** |

---

## 6. Findings

### 6.1 Legacy projection drives the room back to reference pressure

This is the headline, and it is the defect H3.2b0 described, now measured
directly rather than inferred from code.

Both columns of T6 are the **same** equation of state; only the inventory it is
applied to differs.

| | applied to | observed range across the corpus |
|---|---|---|
| `canonical_pressure_pre_pa` | the **pre**-state | **98 511 – 104 702 Pa**, a span of **6 191 Pa** |
| `canonical_pressure_from_legacy_post_pa` | the **legacy post** inventory | **101 108 – 101 325 Pa**, a span of **216 Pa** |

The pre-state pressure moves freely as the fire loads the room. The post-state
pressure is pinned into a band **29× narrower**, and in **every one of the ten
scenarios its maximum is exactly `AIR_PRESSURE_REF_PA = 101 325.0 Pa`** — the
reference pressure itself, hit to the last digit, not approached.

That is what the unconditional lower rewrite does. `ZoneFireSolver.gd:281` sets
`lower_gas_kg = remaining_volume · ρ_lower`, and `ρ_lower` is the fixed reference
density scaled by the ambient/zone temperature ratio, so the reconstructed
inventory is by construction the inventory that sits at reference pressure. The
legacy path does not merely lose a little mass at the margin: **it discards
whatever pressure state the physics had produced and rebuilds the room at the
reference state, on every projection call, in every room.**

Note what this does *not* say. It does not say the primitive's pre-state pressure
is correct, and it does not say the legacy result is wrong as fire physics. It
says the two models disagree structurally, that the disagreement is large, and
that its direction is systematic rather than noisy.

### 6.2 All divergence is the lower rewrite; the upper cap contributes nothing

Consistent with H3.2b1a's finding that the upper cap never binds, the upper-zone
mass divergence is exactly zero in every scenario, so the lower rewrite accounts
for **100 %** of the mass divergence corpus-wide. A primitive that reworked the
cap would change nothing; the lower rewrite is the whole target.

### 6.3 The primitive accepts essentially every real pre-state — but not all

Across **959 242** projection calls in the corpus the primitive rejected exactly
**one**: a single `energy_without_mass` state in `ghanekar_bedroom_hallway`, one
call in 117 142. Every other call's pre-state was valid — zero negative
inventories, zero non-finite inputs, zero `both_zones_absent`.

Both halves of that matter. The validity contract of H3.2b2 is not merely
defensible in the abstract: the states the engine actually produces at projection
entry satisfy it about 99.9999 % of the time. And the rejection is not zero, so
the fail-closed path is not dead code — the engine really can present a zone
holding energy with no mass at projection entry, and when it does, the shadow
counted it, named it, and fabricated no comparison for it. A contract that never
fires would be much weaker evidence than one that fires once and is seen to
behave.

### 6.4 The interface agrees closely while the inventory diverges wildly

**Units first, because the two numbers are not the same kind of quantity.**
`max_absolute` is the largest divergence observed in a **single projection
call**. `gross_absolute_total` is the sum of `|divergence|` over **every call in
the run** -- cumulative churn, not an instantaneous state error, and not a mass
the room is missing at any moment.

The largest **single-call** interface divergence anywhere in the corpus is
**0.011 m**. The largest **single-call** lower-mass divergence is **1.53 kg**
(`uk_bungalow_smoke`). The 964.41 kg quoted for `flashover_simple_house` is the
**cumulative gross churn over 77 071 projection calls** -- roughly 0.013 kg per
call on average -- and says how much rewriting happened in total, not how far the
room was ever out.

Compared like with like, the contrast still holds: per call, the interface
differs by at most 0.011 m out of a 2.5 m room (0.4 %), while the lower mass
differs by up to 1.53 kg. The two facts are consistent, and together they locate
the defect precisely.
Legacy derives its layer height from the **upper** mass
(`ZoneFireSolver.gd:266-268`), and the upper mass is exactly what legacy does not
rewrite — T3 and T4 show upper-zone divergence of exactly zero everywhere. So the
interface, which is what the UI and the FED gates read, is nearly the same in
both models, while the **lower inventory underneath it** is not. A reviewer
looking only at layer height would conclude the two models agree. They do not.

### 6.5 Zero presence-predicate mismatches, and what that does and does not mean

The primitive's predicate is `M > 0`; the legacy projection's is
`M > 1.0e-4`. Across the corpus the two never disagreed. That is a real negative
for **this corpus at this duration**, not a resolution: the seven engine-wide
predicates still span eleven orders of magnitude, the mismatch counter only
compares against the legacy *projection* predicate, and a zone parked between
`0` and `1e-4` kg would still be counted present by one and absent by the other.
Choosing one canonical predicate remains a blocker for H3.2b6.

### 6.6 Determinism

The three repeat runs — corridor chain, the two-floor stairwell and the
Mediterranean flat, chosen for a corridor, a multi-floor and a loop topology —
reproduced both the CSV **and every shadow total** byte for byte. The shadow
introduces no run-to-run variation of its own.


---

## 7. What this phase does not establish

- **Nothing about applying the residual.** The primitive was never applied. The
  divergences say what would change, not what would be better.
- **Nothing about baselines.** No baseline moved because nothing was applied.
  Whatever moves at H3.2b6 must be explained physically, never tuned.
- **Nothing about zone transitions.** The runtime birth/death counters are known
  blind (H3.2b1a: at least 29 missed births). This phase does not repair them,
  does not gate on them and does not present their zeros as evidence. H3.2b1b
  remains required before H3.2b4.
- **Nothing about full-length runs.** 120 s is between 17 % and 43 % of each case
  file's own duration, and H3.2b1a measured churn growing faster than run length.
- **Nothing about HVAC-bearing topologies**, which this corpus does not exercise.

---

## 8. Risks

1. **The divergence is large and systematic, not marginal.** §6.1 means switching
   authority at H3.2b6 changes the pressure state of every room on every step.
   That is the intended correction, but it is not a small perturbation and it
   must not be introduced without the shadow evidence being read first.
2. **The presence predicate is still unresolved**, and this corpus happens not to
   exercise the disagreement, which makes it easy to forget.
3. **The comparison uses `pre` as the primitive's input.** That is the honest
   choice — it is the state at entry — but it means the comparison spans the
   whole of `project_room_state`, including `ensure_room_state`'s own clamps and
   seeding. Attributing divergence to sub-stages inside the call would need the
   `ensured` and `pre_geometry` snapshots, which this phase reports but does not
   decompose.
4. **`canonical_pressure_from_legacy_post_pa` is a recomputation and could be
   misread** as something legacy produced. It is labelled in the metric name, in
   the summary note and in this document, and a contract forbids the string
   `legacy_pressure` anywhere in the component.
5. **H3.2b1's causal-only flag was inert and is now repaired** (§10). The
   failure mode was silent-but-closed: the flag appeared to work and produced
   `data_available: false`. Any future flag added without being registered in
   `_phase3_projection_diagnostics_active()` will fail the same way, and nothing
   structural prevents that recurring.

---

## 9. Decision

**GO for the shadow comparison only.**

The comparison is wired, isolated, byte-identical when off, and it produced the
first direct measurement of what the legacy projection actually does to the room
pressure state. Nothing was applied, no authority was granted, and
`ZoneFireSolver` was not touched.

**NO-GO for everything else.** H3.2b4, H3.2b1b and any runtime authority remain
blocked. H3.2-S, H3.2b and H3.3 stay open; S0d6b1 stays blocked; HVAC stays
deferred; the thermal limit remains H3.2b5's.

Prerequisites still on the record, unchanged by this phase:

- **H3.2b1b** must repair the zone-transition counters before H3.2b4 can gate on
  them.
- **A single presence predicate** must be agreed before H3.2b6 wires anything.

---

## 10. The H3.2b1 activation defect, and its repair

**Finding 1 — the H3.2b1 causal-only flag is inert.**
`_sync_auxiliary_services()` reasserts
`zone_fire_solver.projection_diagnostics_enabled = _phase3_projection_diagnostics_active()`
(`SimulationEngine.gd:1140`), and it is called from `_maybe_log_state()` among
others, so it runs repeatedly during a run.
`_phase3_projection_diagnostics_active()` did **not** include
`phase3_projection_causal_diagnostics_enabled`. A session started with
`--phase3-projection-causal-diagnostics` alone therefore has the per-call trace
switched back off at every logging point, and the H3.2b1 ledger accumulates
nothing.

Evidence, from the committed H3.2b1a campaign artefacts on
`cfast_corridor_chain` at 120 s:

| variant | `data_available` | reason codes | projection calls counted |
|---|---|---|---|
| `--phase3-projection-causal-diagnostics` alone | **`false`** | `projection_trace_unavailable`, `zone_stage_attribution_unavailable` | **none accumulated** |
| with `--phase3-zone-diagnostics` as well | `true` | — | 73 729 |

**It failed closed** — it reported no data rather than wrong data.

**Scope of the damage, verified against the artefacts before being asserted.**
All twenty H3.2b1a campaign summaries were re-read. In **all ten** causal-only
runs the ledger reported `data_available: false` with
`projection_trace_unavailable` present and **no calls accumulated at all**; in
**all ten** zone+causal runs it reported `data_available: true` with full counts.
Zero anomalies. Therefore:

- **H3.2b1 was inert as a standalone flag.** A run started with
  `--phase3-projection-causal-diagnostics` alone produced nothing.
- **H3.2b1a's measurements retain their validity**, because every one of them was
  taken from the zone+causal variant, where the zone diagnostics flag activated
  the trace. The causal-only variant was used **solely** for CSV byte-identity,
  which does not depend on the ledger, and it self-reported
  `data_available: false` — so no claim in that phase was ever built on empty
  data.
- The same applies to H3.2b1's own measurements, which were taken with both flags
  (`§11.3` of the H3.2b0 design document records the flag pair explicitly).

**REPAIRED 2026-08-20.** `phase3_projection_causal_diagnostics_enabled` is now
included in `_phase3_projection_diagnostics_active()`, so the authoritative
reassertion keeps the trace on for a causal-only session. Measured on
`cfast_corridor_chain` at 60 s:

| variant | `data_available` | reason codes | projection calls | room-steps |
|---|---|---|---:|---:|
| causal-only, **before** the repair | `false` | `projection_trace_unavailable`, `zone_stage_attribution_unavailable` | **0** | 0 |
| causal-only, **after** the repair | `false` | `zone_stage_attribution_unavailable` | **33 063** | 4 320 |
| causal + zone diagnostics | **`true`** | — | **33 063** | 4 320 |

The trace dependency is satisfied; `projection_trace_unavailable` is gone. The
remaining `zone_stage_attribution_unavailable` is **correct and unrelated**: the
ledger's residual half needs the per-stage attribution that
`--phase3-zone-diagnostics` provides, and it says so rather than reporting zeros.
`data_available` covers both dependencies, so causal-only legitimately still
reports `false` — with one reason instead of two.

The identical call counts across the last two rows are the evidence that the
trace now behaves the same way whether or not the zone diagnostics are on, and
`room_steps_total == timesteps × rooms` exactly (4 320 = 720 × 6), which could
not hold if events accumulated across steps.

Covered by `tests/fixtures/phase3_h32b1_causal_only_activation.gd` (6 assertions:
the gate, non-activation of anything else, real projection calls counted, the
per-step reset, legacy state untouched, and availability with its negative
control) and by contracts in `tests/test_phase3_h32b1_projection_causal.py`.

**The blind zone-transition counters are NOT repaired here.** They remain
H3.2b1b, before H3.2b4, and this phase neither gates on them nor reports them.
