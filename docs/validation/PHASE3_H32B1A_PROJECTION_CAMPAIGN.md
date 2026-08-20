# Phase 3 H3.2b1a — Passive projection campaign over ten topologies

Status: **passive campaign, evidence only.** No file under `sim/` was modified in
this phase. No physics, no flag default, no CSV column, no case file, no report,
no expected value, no tolerance, no CTRL and no VALID_GAP is touched, and no
runtime authority is granted. H3.2b2 is not started.

This phase asks one question: **do the shapes H3.2b1 measured on a single
scenario hold across the corpus?** It answers it with the ledger committed in
H3.2b1, run unchanged over ten committed topologies, plus a read-only analyser
that reports what the ledger says and refuses to say more.

---

## 1. Corpus provenance

Ten **committed** case files. Scratch definitions are never binding evidence, so
each file is identified by its **git blob object**, not by a filesystem hash. A
matching filesystem SHA-256 proves byte equality for the files compared, but does
not identify the commit that supplied those bytes. A blob OID answers the stronger
provenance question: "what does this repository have committed?" Every file was
clean in the index at the time of the campaign.

| scenario | git blob OID (HEAD) | case file own `duration_s` | run duration |
|---|---|---:|---:|
| `cfast_corridor_chain` | `a4eeae6bebd0` | 600 s | **120 s** |
| `cfast_r0_window_360` | `3b93649cd09e` | 520 s | **120 s** |
| `cfast_two_floor_stairwell` | `2a91c9348eff` | 600 s | **120 s** |
| `two_storey_smoke` | `828812bfe0fd` | 300 s | **120 s** |
| `ghanekar_bedroom_hallway` | `2dbb0416d17e` | 420 s | **120 s** |
| `piso_mediterraneo_smoke` | `c9032b5e1cd4` | 700 s | **120 s** |
| `uk_bungalow_smoke` | `269e31f6ca59` | 700 s | **120 s** |
| `compact_apartment_smoke` | `52c76a6bc4be` | 600 s | **120 s** |
| `three_bed_apartment_smoke` | `78294dc3c0ee` | 700 s | **120 s** |
| `flashover_simple_house` | `e2931ea0e1e1` | 280 s | **120 s** |

**120 s is the official duration for this corpus**, fixed by the H3.2a runtime
matrix, which ran exactly these ten scenarios at exactly that duration. It is
deliberately *not* each case file's own `duration_s`, and that gap matters — see
§6.3, where churn is shown to grow with run length, so every churn figure here is
a lower bound for a full-length run.

Independent corroboration that the corpus and the duration are the intended ones:
the row counts this campaign produced are **identical, case by case, to the
H3.2a runtime matrix** — 79, 79, 170, 1574, 131, 1211, 848, 606, 1090, 727. That
matrix was produced by a different phase, for a different purpose, from a clean
worktree at `344ec5fe`.

---

## 2. Method

Four runs per scenario, forty runs in total, sequential, Godot 4.7.1 console,
through `scripts/run_scenario.py` — never `--script` against
`tools/run_scenario_headless.gd`.

| variant | flags | purpose |
|---|---|---|
| `base` | none | the OFF baseline |
| `causal` | `--phase3-projection-causal-diagnostics` | OFF byte-identity of the new flag alone |
| `zone` | `--phase3-zone-diagnostics` | the pre-existing diagnostics baseline |
| `on` | both | the measurement run |

Two comparisons are needed because the causal ledger consumes the zone
diagnostics: `base` versus `causal` proves the new flag alone changes nothing,
and `zone` versus `on` proves that adding it on top of the diagnostics changes no
legacy column either.

Analyser: `scripts/simulation/phase3_h32b1a_projection_campaign.py`, read-only —
it runs nothing, writes nothing, imports no engine module, and every number it
prints is read verbatim from the ledger or is an exact arithmetic combination of
ledger totals. Contracts: `tests/test_phase3_h32b1a_projection_campaign.py`.

---

## 3. Units and semantics, restated before any number

- A **room-step** is one room within one physical timestep. A **timestep** is one
  `SimulationEngine.step()`. They are different units and are never interchanged.
- **`gross_absolute` is projection churn** — the volume of rewriting a cause
  performed. It is not a physical contribution and not a source. `signed_net`,
  `gross_absolute` and `call_count` stay three separate numbers.
- A **static instrumentation gap** describes coverage known from reading the
  code. It never implies the path ran. An **observed active gap** is incremented
  only when that writer materially moved mass or energy.
- The physical residual is called **`candidate_incomplete_physical_residual`**
  unless `residual_physical_valid`, which needs `data_available`, no observed
  active gap and complete structural coverage. `numerical_correction` is a valid
  observation either way.
- Missing telemetry reports `data_available: false` with reason codes. It never
  reports zero.

---

## 4. Gates

Every gate is a comparison between artefacts, never a tolerance.

### 4.1 Gate results across the corpus

| gate | pass | failed |
|---|---:|---|
| `all_variants_present` | 10/10 | - |
| `off_byte_identical` | 10/10 | - |
| `on_changes_no_legacy_column` | 10/10 | - |
| `no_new_csv_column` | 10/10 | - |
| `legacy_columns_preserved` | 10/10 | - |
| `summary_delta_is_opt_in_block_only` | 10/10 | - |
| `rows_match_across_variants` | 10/10 | - |
| `manifests_valid` | 10/10 | - |
| `duration_reached` | 10/10 | - |
| `official_duration_used` | 10/10 | - |


### 4.2 CSV identity, per case

| scenario | lines (header + data) | data rows | base sha256[:16] | causal sha256[:16] | zone sha256[:16] | on sha256[:16] |
|---|---:|---:|---|---|---|---|
| `cfast_corridor_chain` | 79 | 78 | `15a7a84fc1b0f8d8` | `15a7a84fc1b0f8d8` | `c4e12860690964d8` | `c4e12860690964d8` |
| `cfast_r0_window_360` | 79 | 78 | `5ad6ea0de2796379` | `5ad6ea0de2796379` | `fd8cd05cb2ecf200` | `fd8cd05cb2ecf200` |
| `cfast_two_floor_stairwell` | 170 | 169 | `5768d6658c127e99` | `5768d6658c127e99` | `e30c56b3ff4a03b9` | `e30c56b3ff4a03b9` |
| `two_storey_smoke` | 1574 | 1573 | `dc101da56029cf7e` | `dc101da56029cf7e` | `dbec972cc7f75cfe` | `dbec972cc7f75cfe` |
| `ghanekar_bedroom_hallway` | 131 | 130 | `23fc8af1f816d2ab` | `23fc8af1f816d2ab` | `682fc1aa7d4c9e81` | `682fc1aa7d4c9e81` |
| `piso_mediterraneo_smoke` | 1211 | 1210 | `523261ba8156ad0d` | `523261ba8156ad0d` | `4288cad1aea9e496` | `4288cad1aea9e496` |
| `uk_bungalow_smoke` | 848 | 847 | `48a44214643cbeac` | `48a44214643cbeac` | `3e27253c585f02f1` | `3e27253c585f02f1` |
| `compact_apartment_smoke` | 606 | 605 | `952af0f39b766288` | `952af0f39b766288` | `2031432a6f5add29` | `2031432a6f5add29` |
| `three_bed_apartment_smoke` | 1090 | 1089 | `a4fec1c749b58935` | `a4fec1c749b58935` | `7ffbb7237d61ea37` | `7ffbb7237d61ea37` |
| `flashover_simple_house` | 727 | 726 | `45e9b3972abd35f0` | `45e9b3972abd35f0` | `383efa5804607454` | `383efa5804607454` |

---

## 5. Results
### 5.1 Multiplicity

| scenario | rooms | timesteps | room-steps | calls | mean/room-step | max/room-step | max/timestep | room-steps >1 | causes |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `cfast_corridor_chain` | 6 | 1441 | 8646 | 73729 | 8.53 | 17 | 62 | 8646 (100.0%) | 16 |
| `cfast_r0_window_360` | 6 | 1441 | 8646 | 60568 | 7.01 | 8 | 43 | 8646 (100.0%) | 7 |
| `cfast_two_floor_stairwell` | 13 | 1441 | 18733 | 135461 | 7.23 | 15 | 105 | 18733 (100.0%) | 14 |
| `two_storey_smoke` | 13 | 1441 | 18733 | 138360 | 7.39 | 14 | 103 | 18733 (100.0%) | 14 |
| `ghanekar_bedroom_hallway` | 10 | 1441 | 14410 | 117142 | 8.13 | 19 | 96 | 14410 (100.0%) | 16 |
| `piso_mediterraneo_smoke` | 10 | 1441 | 14410 | 114779 | 7.97 | 15 | 93 | 14410 (100.0%) | 11 |
| `uk_bungalow_smoke` | 7 | 1441 | 10087 | 82000 | 8.13 | 16 | 70 | 10087 (100.0%) | 14 |
| `compact_apartment_smoke` | 5 | 1441 | 7205 | 59938 | 8.32 | 13 | 49 | 7205 (100.0%) | 11 |
| `three_bed_apartment_smoke` | 9 | 1441 | 12969 | 100194 | 7.73 | 13 | 77 | 12969 (100.0%) | 11 |
| `flashover_simple_house` | 6 | 1441 | 8646 | 77071 | 8.91 | 20 | 72 | 8646 (100.0%) | 14 |


### 5.2 Causes

| cause | scenarios | calls | mass gross kg (sum) | energy gross kJ (sum) | mass gross/|net| per scenario |
|---|---:|---:|---:|---:|---|
| `reconcile_layer_sync` | 10/10 | 244970 | 15.191 | 1.546e-09 | 1.00 |
| `gas_exchange_sync` | 10/10 | 133243 | 1348.007 | 1101 | 1.00-10.68 |
| `thermal_energy_projection` | 10/10 | 122485 | 58.606 | 2.369e-09 | 1.00 |
| `thermal_post_combustion_sync` | 10/10 | 122485 | 308.791 | 5774 | 1.00-1.02 |
| `thermal_post_losses_sync` | 10/10 | 122485 | 3.137 | 2.207e-09 | 1.00 |
| `final_clamp_quiescent` | 10/10 | 89165 | 0.000 | 0 | - (net exactly 0 in 10) |
| `final_clamp_active` | 10/10 | 33320 | 0.750 | 1.334e-09 | 1.00 |
| `interior_background_source_sync` | 9/10 | 30486 | 34.618 | 2.27e-09 | 1.00 |
| `interior_background_target_sync` | 9/10 | 30486 | 34.748 | 44.11 | 1.00 |
| `opening_radiation_source_sync` | 8/10 | 7001 | 6.371 | 1.143e-09 | 1.00 |
| `opening_radiation_target_sync` | 8/10 | 7001 | 1460.380 | 448.6 | 1.00 |
| `exterior_background_source_sync` | 1/10 | 3303 | 6.797 | 0.0208 | 1.00 |
| `exterior_background_target_sync` | 1/10 | 3303 | 5.242 | 9.907 | 1.00 |
| `doorway_counterflow_cold_sync` | 1/10 | 2080 | 8.079 | 8.039 | 1.00 |
| `doorway_counterflow_hot_sync` | 1/10 | 2080 | 5.344 | 9.342e-11 | 1.00 |
| `doorway_cold_target_sync` | 6/10 | 1709 | 23.478 | 84.4 | 1.00 |
| `doorway_hot_source_sync` | 6/10 | 1709 | 22.650 | 1.779e-10 | 1.00 |
| `post_transfer_vertical_mix_sync` | 6/10 | 1709 | 0.010 | 5.526e-11 | 1.00-20.00 |
| `interlayer_source_sync` | 1/10 | 111 | 0.006 | 6.374e-12 | 1.00 |
| `interlayer_target_sync` | 1/10 | 111 | 0.006 | 0.0001169 | 1.00 |

distinct causes across the corpus: **20**


### 5.3 Corrections, upper cap and lower rewrite

| scenario | upper gross kg | upper net kg | lower gross kg | lower net kg | cap binds | cap rejected kJ |
|---|---:|---:|---:|---:|---:|---:|
| `cfast_corridor_chain` | 0.0000 | 0.0000 | 474.3020 | 55.2581 | 0 | 0.0000 |
| `cfast_r0_window_360` | 0.0000 | 0.0000 | 21.4242 | 2.9108 | 0 | 0.0000 |
| `cfast_two_floor_stairwell` | 0.0000 | 0.0000 | 115.9511 | -6.2710 | 0 | 0.0000 |
| `two_storey_smoke` | 0.0000 | 0.0000 | 138.5758 | 0.8464 | 0 | 0.0000 |
| `ghanekar_bedroom_hallway` | 0.0000 | 0.0000 | 184.5933 | 0.2551 | 0 | 0.0000 |
| `piso_mediterraneo_smoke` | 0.0000 | 0.0000 | 615.2151 | -471.5677 | 0 | 0.0000 |
| `uk_bungalow_smoke` | 0.0000 | 0.0000 | 449.0470 | -330.5067 | 0 | 0.0000 |
| `compact_apartment_smoke` | 0.0000 | 0.0000 | 136.2643 | 1.2217 | 0 | 0.0000 |
| `three_bed_apartment_smoke` | 0.0000 | 0.0000 | 242.4271 | -96.6902 | 0 | 0.0000 |
| `flashover_simple_house` | 0.0000 | 0.0000 | 964.4115 | -503.8474 | 0 | 0.0000 |


### 5.4 Residuals and numerical corrections

| scenario | candidate mass kg | candidate gross kg | closure mass kg | numerical corr. mass kg | candidate energy kJ | closure energy kJ | rel err mass | rel err energy |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `cfast_corridor_chain` | 1.0420 | 1.0420 | 0.0000 | 1.0420 | 7.896e-13 | 0.000e+00 | 0.00e+00 | 0.00e+00 |
| `cfast_r0_window_360` | 0.0012 | 0.0012 | 0.0000 | 0.0012 | 4.320e-12 | 0.000e+00 | 0.00e+00 | 0.00e+00 |
| `cfast_two_floor_stairwell` | 0.8202 | 0.8202 | 0.0000 | 0.8202 | -2.134e-12 | 0.000e+00 | 0.00e+00 | 0.00e+00 |
| `two_storey_smoke` | 0.5107 | 0.5107 | 0.0000 | 0.5107 | 4.138e-12 | 0.000e+00 | 0.00e+00 | 0.00e+00 |
| `ghanekar_bedroom_hallway` | 0.9643 | 0.9643 | 0.0000 | 0.9643 | 1.241e-12 | 0.000e+00 | 0.00e+00 | 0.00e+00 |
| `piso_mediterraneo_smoke` | 0.6412 | 0.6412 | 0.0000 | 0.6412 | -4.992e-12 | -5.421e-20 | 0.00e+00 | 0.00e+00 |
| `uk_bungalow_smoke` | 0.6762 | 0.6762 | 0.0000 | 0.6762 | 6.864e-12 | -5.421e-20 | 0.00e+00 | 0.00e+00 |
| `compact_apartment_smoke` | 0.6448 | 0.6448 | 0.0000 | 0.6448 | 2.817e-12 | 0.000e+00 | 0.00e+00 | 0.00e+00 |
| `three_bed_apartment_smoke` | 0.6541 | 0.6541 | 0.0000 | 0.6541 | -3.089e-12 | 0.000e+00 | 0.00e+00 | 0.00e+00 |
| `flashover_simple_house` | 8.0774 | 8.0774 | 0.0000 | 8.0774 | 4.307e-13 | 0.000e+00 | 0.00e+00 | 0.00e+00 |


### 5.5 Completeness, gaps and invalid states

| scenario | data_available | static gaps | active gaps | verdict | energy w/o mass | non-finite |
|---|---|---:|---:|---|---:|---:|
| `cfast_corridor_chain` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `cfast_r0_window_360` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `cfast_two_floor_stairwell` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `two_storey_smoke` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `ghanekar_bedroom_hallway` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `piso_mediterraneo_smoke` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `uk_bungalow_smoke` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `compact_apartment_smoke` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `three_bed_apartment_smoke` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |
| `flashover_simple_house` | True | 4 | 0 | STRUCTURALLY_INCOMPLETE | 0 | 0 |


### 5.6 Zone regime and transition instrumentation

| scenario | rooms | always one-zone | always two-zone | state births >= | state deaths >= | ledger births (invalid) | ledger deaths (invalid) | missed >= |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `cfast_corridor_chain` | 6 | 3 | 0 | 3 | 0 | 0 | 0 | **3** |
| `cfast_r0_window_360` | 6 | 5 | 0 | 1 | 0 | 0 | 0 | **1** |
| `cfast_two_floor_stairwell` | 13 | 11 | 0 | 2 | 0 | 0 | 0 | **2** |
| `two_storey_smoke` | 13 | 11 | 0 | 2 | 0 | 0 | 0 | **2** |
| `ghanekar_bedroom_hallway` | 10 | 8 | 0 | 2 | 0 | 0 | 0 | **2** |
| `piso_mediterraneo_smoke` | 10 | 6 | 0 | 4 | 0 | 0 | 0 | **4** |
| `uk_bungalow_smoke` | 7 | 2 | 0 | 5 | 0 | 0 | 0 | **5** |
| `compact_apartment_smoke` | 5 | 2 | 0 | 3 | 0 | 0 | 0 | **3** |
| `three_bed_apartment_smoke` | 9 | 6 | 0 | 3 | 0 | 0 | 0 | **3** |
| `flashover_simple_house` | 6 | 2 | 0 | 4 | 0 | 0 | 0 | **4** |

transitions the ledger missed across the corpus: **at least 29**

The exported ledger zeros in this table are **invalid / non-interpretable**, not
observations of no transitions. The independent state-column lower bound proves
that the current counter cannot see the event it claims to measure.


---

## 6. What the corpus establishes

### 6.1 Multiplicity is a corpus-wide property, not a corridor-chain artefact

Every scenario projects every room more than once in **every** room-step: the
count of room-steps with more than one call equals the total room-step count in
all ten. The maximum within a single room-step ranges from 8 to 20, and within a
single timestep across all rooms from 43 to 105. H3.2b0's estimate of "at least
three per timestep" is a floor that the corpus exceeds by between three and seven
times.

Twenty distinct causes appear across the corpus, against the **five** direct
`project_room_state(` call sites H3.2b0 mapped and the seventeen H3.2b1 saw on
one scenario. Three of them — `exterior_background_source_sync`,
`exterior_background_target_sync` and the `interlayer_*` pair — appear in only
one scenario each, which is exactly why one scenario was not enough. Any
deduplication or idempotence scheme must handle twenty causes, and must assume
that number is still a lower bound.

### 6.2 The upper cap never binds anywhere in the corpus

`upper_mass_correction_gross_absolute` is **exactly zero** in all ten scenarios,
and so are `thermal_cap_bind_count` and `thermal_cap_rejected_kj`. Every kilogram
of projection churn in this corpus comes from the **unconditional lower rewrite**
at `ZoneFireSolver.gd:281`, none from the conditional upper cap at `:264` and
none from the thermal cap.

This is the single most actionable result for H3.2b2. At the official **120 s
duration of this ten-case corpus**, a primitive that only reworks the cap, or
that treats the thermal cap as the interesting sink, would change nothing
measurable. This does not establish that the cap is irrelevant at longer
durations or outside these topologies. The lower rewrite is the measured target.

### 6.3 Churn grows with run length, so these figures are lower bounds

At 120 s most causes have a gross-to-net ratio of exactly 1.00: every rewrite
carries the same sign, so nothing cancels and gross equals net. Only
`gas_exchange_sync` (1.00–10.68 across the corpus) and
`post_transfer_vertical_mix_sync` (1.00–20.00) show real cancellation.

The same scenario run to its own 600 s duration in H3.2b1 gives
`gas_exchange_sync` a ratio of **28.03**, against **6.36** at 120 s here. Churn
therefore accumulates faster than run length, and every churn number in this
document is a **lower bound** for a full-length run. The corpus duration was
chosen for comparability with H3.2a, not to bound churn.

### 6.4 The engine's own residual still cannot fail

The closure-inclusive residual is **exactly zero** in all ten scenarios and the
relation error is **exactly zero** in mass and energy in all ten. The candidate
physical residual ranges from 0.0012 kg to 8.0774 kg and is carried entirely by
the numerical correction. This reconfirms H3.2b0 §1 across the corpus: while
`reconcile` and `projection_clamp` are counted as attribution, the residual the
engine computes for itself is structurally incapable of reporting a problem.

Two features of the candidate residual are worth separating from its size. Its
**gross-absolute total equals its signed total in every scenario**, so every
per-step contribution carries the same sign: this is a systematic one-directional
bias, not an oscillation that happens to sum small. And `flashover_simple_house`
carries **8.077 kg** on six rooms, roughly eight times the next largest and
nearly seven thousand times the smallest (`cfast_r0_window_360`, 0.0012 kg on the
same room count), so the magnitude tracks how energetic the scenario is rather
than how large the building is.

### 6.5 No invalid states

Zero energy-without-mass states and zero non-finite states, in every scenario and
every room.

### 6.6 The ledger's zone-transition counters are blind, and the corpus proves it

This is the one result that contradicts what H3.2b1 reported on a single
scenario, and it is a finding about the instrumentation rather than about the
physics.

The ledger exports **zero upper-zone births and zero deaths in all ten
scenarios**, but those values are invalid / non-interpretable. The logged
`upper_gas_kg` state column, read independently, shows
that **every room in the corpus starts one-zone** — `upper_gas_kg` is exactly
zero at t = 0 in all 85 rooms, and not one room is two-zone for the whole run —
and that **at least 29 upper-zone births occur**, spread across all ten
scenarios, from 1 in `cfast_r0_window_360` to 5 in `uk_bungalow_smoke`. Zero
deaths: every observed transition is one-way, one-zone to two-zone, at the moment
the fire first builds a layer in that room.

The ledger missed all 29. The mechanism is structural, not a threshold or a
rounding question: `_scan_zone_transition` compares the `pre` and `post`
snapshots of a **single `project_room_state` call**, and the layer is created by
another subsystem between calls. By the time projection next runs, both snapshots
already show the new regime, so the counter never moves. Projection does not
create upper mass, so it can essentially never witness a birth.

The comparison is sound in the strict direction. The state column is
interval-sampled at 10 s and is therefore itself a **lower** bound on real
transitions, while the ledger sees every step. A ledger count *below* the sampled
bound cannot be explained by sampling — it is a definite miss. The analyser
reports the difference as `missed_births_at_least` and never renders it negative
in the opposite case.

Consequence: the zone birth and death rules H3.2b0 §3.3 specifies are **not
merely unvalidated by this corpus — they are currently unmeasurable**, because
the only instrumentation for them cannot observe the event. Fixing it means
comparing the regime across a timestep boundary rather than across a projection
call, which is a change under `sim/` and therefore out of scope for this phase.

---

## 7. What the corpus does **not** establish

- **No physical residual is valid anywhere in the corpus.**
  `residual_physical_valid` is `false` in all ten, identically, because the same
  four static coverage gaps remain open: `hvac_mass_energy_unowned`,
  `other_stage_is_catchall`, `suppression_lower_write_dead` and
  `exterior_removal_not_zonal`. The candidate figures in T3 are candidates. They
  are not conservation measurements and must not be quoted as physical residuals.
- **Zero observed active gaps is a real negative, but a narrow one.** It means
  those three writers did not move material mass or energy in these ten runs at
  this duration. It is evidence the detector can produce, not a proof of absence:
  the positive control lives in the fixture, where injected material HVAC
  activity does raise the gap, carry a count and invalidate the residual. Sampled
  CSV rows corroborate quiet HVAC, `other` and suppression stages, but the ledger
  is the stronger witness because it sees every step while the CSV samples
  every 10 s.
- **No conclusion about full-length behaviour.** 120 s is between 17 % and 43 %
  of each case file's own duration.
- **No conclusion about HVAC-bearing topologies.** No case in this corpus
  exercises HVAC materially, so the largest static gap is untested here rather
  than shown to be harmless.

---

## 8. Declared-absent coverage

Not approximated, not estimated, not inferred:

| coverage | why it is absent |
|---|---|
| `calls_per_room_step_full_histogram` | the ledger exports a maximum and a multi-call count per room-step, not a histogram. A distribution reconstructed from a maximum and a count would be an invention. |
| `per_room_room_step_denominator` | per-room room-step counts are not exported, so a per-room mean calls-per-room-step is not exactly computable. The corpus-level mean is exact and is reported instead. |
| `zone_transitions_outside_a_projection_call` | the ledger's birth and death counters compare the `pre` and `post` of one projection call, and §6.6 shows this misses at least 29 real births across the corpus. The interval-sampled state-column check is the independent cross-check and is itself a lower bound. |

Adding any of these requires a change under `sim/`, which this phase forbids.

---

## 9. Risks

1. **Twenty causes is still a lower bound.** The count rose from 5 mapped to 17
   on one scenario to 20 across ten. A topology outside this corpus may add more.
   Any H3.2b2 design that enumerates causes will be brittle; idempotence, which
   H3.2b0 §8 already requires, does not depend on the enumeration and should be
   preferred.
2. **The corpus does not exercise the largest static gap.** HVAC is the widest
   coverage hole and no scenario here moves material HVAC mass or energy. A
   residual that looks clean across ten topologies may not stay clean on an
   HVAC-bearing one.
3. **120 s understates churn.** §6.3 measures the effect directly on one
   scenario. Sizing a primitive against these numbers would size it against a
   lower bound.
4. **The zone-transition instrumentation does not work.** §6.6 measures it: at
   least 29 real births, zero seen. Any H3.2b2 gate written against
   `upper_zone_birth_count_total` or `upper_zone_death_count_total` would pass
   vacuously today. The counters must be moved to a timestep boundary before
   they can gate anything, and until then the transition rules of H3.2b0 §3.3
   are unmeasurable rather than merely unvalidated.
5. **The candidate residual is small but not zero, and its sign is systematic.**
   Its gross-absolute total equals its signed total in every scenario, meaning
   every per-step contribution has the same sign. A small one-directional bias is
   harder to dismiss as arithmetic noise than a large oscillating one.

---

## 10. Decision

**Passive campaign complete. Evidence sufficient to design H3.2b2, with its
scope narrowed by what was measured.**

The corpus answers the three questions H3.2b0 said were shaping and unmeasured.
The projection call count is known and is far larger than assumed. The split
between the two residuals is known: one is exactly zero everywhere by
construction, the other is a small systematic candidate. The gross-versus-net
magnitudes are known, and they identify the lower rewrite — not the cap — as the
thing a primitive must replace.

What H3.2b2 may be designed against, from this evidence:

- the unconditional lower rewrite, which carries **all** measured churn;
- idempotence rather than deduplication, because the cause set is open-ended;
- the transition rules needing their own fixtures — and, before that, a
  transition counter that can actually observe a transition (§6.6).

One prerequisite is now explicit and was not visible before this campaign: **the
zone-transition counters must be repaired before H3.2b4 can gate on them.** That
is a small, passive change under `sim/`, out of scope here, and it should be
scheduled ahead of any physics work rather than discovered inside it.

What H3.2b2 may **not** assume:

- that the upper or thermal cap matters at 120 s in this corpus — it never binds
  here, but longer durations and other topologies remain unmeasured;
- that the candidate residual is a physical residual — it is not valid anywhere;
- that HVAC is harmless — it is untested, not cleared;
- that 120 s figures bound a full-length run — they do not.

**No physics change is unblocked by this phase.** H3.2b2 remains a design task,
H3.2-S, H3.2b and H3.3 stay open, S0d6b1 stays blocked, HVAC stays deferred, and
no runtime authority is granted.
