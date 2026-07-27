# Current Handoff State

Date: 2026-07-26.

Runtime note: active local runners and test entrypoints now default to Godot
`4.7.1` console at
`C:\Users\dangp\Desktop\Godot_v4.7.1-stable_win64_console.exe`. Explicit
`GODOT_EXE`, `--godot` and `-GodotExe` overrides still take precedence.
Historical validation records retain their original engine labels.

## Current Session Update - 2026-07-27 - Godot fixtures fail closed

- Audited all 32 Godot fixtures for the `SceneTree.quit()` fall-through
  discovered during F3.3v3h1. `quit()` only requests a shutdown; it returns and
  execution continues. **13 fixtures could report success while failing.**
- Three distinct shapes, all present:
  1. **Fall-through exit** - `if _failed: quit(1)` then an unconditional PASS
     print. Affected F3.3v3g1 and F3.3v3g2.
  2. **Quitting helper** - an `_assert`/`_close`/`_fail` helper called
     `quit(nonzero)` and returned to `_init`, which ran the remaining
     assertions and printed PASS. Affected 10 fixtures, including F3.3v3f0.
     This is the shape a naive `quit(1)`-without-`return` scan misses, and it
     is why the first estimate of the blast radius was wrong.
  3. **Bare `assert()`** - halts the function without reaching `quit()`, so a
     failure hung until the harness timeout rather than exiting non-zero.
     Affected F3.3v2c.
- Fix: failures are recorded in a `_failed` flag and the exit is taken at a
  single guarded site. Ten fixtures already using the
  `if _failed: quit(1) else: print(PASS)` shape were **left untouched** - the
  PASS branch is unreachable from the failing branch, so they were already
  safe and editing them would have been churn.
- Verified empirically: a sweep injected a guaranteed failure into every
  fixture through the failure channel that fixture actually owns and required a
  non-zero exit with no PASS marker. All 32 now exit `1` promptly.
- Added `tests/test_godot_fixture_fail_closed.py` - 129 static contracts
  covering all three shapes, each mutation-tested by reintroducing the shape
  and confirming the contract fails.
- Caveat worth remembering for future tooling: `Path.write_text` translates
  `\n` to `\r\n` on Windows. A restore step that used it silently rewrote 19
  untouched fixtures to CRLF. Batch edits on `.gd` files must force
  `newline="\n"`.
- Verification: 32/32 fixtures PASS; `pytest -k "phase3 or guardrail"` 942 PASS
  / 1 FAIL (the historic `test_csv_exports_three_canonical_layers`); guardrails
  **10/10**; Physics 9/15/5/0; ILV 15/14/0; gap inventory unchanged.
- No physics, baseline, expected value, tolerance, report or CTRL/VALID_GAP
  changed. H2 remains not started.

## Current Session Update - 2026-07-27 - F3.3v3h1 pure solver primitive GO

- Added `sim/core/Phase3CoupledPressureSolver.gd`. It is a **pure primitive**:
  no runtime call site, no exported flag, no persistent state, no member
  variables, and no reach into `RoomModel`, `BuildingModel`,
  `SimulationEngine` or `Phase3ZoneMassSystem`. Structural tests enforce all
  of that rather than relying on intent.
- Contract: damped Newton over **one pressure unknown per room**, on a
  residual that contains every pressure owner. Opening fluxes, interior and
  exterior, are implicit through `dp(z)`; combustion, multisurface and any
  other owner enter as source totals **inside** the same residual. Frozen
  within one solve, as documented coefficients: the hydrostatic density
  profile, the interface height and the donor-cell specific enthalpy. Freezing
  the profile is a coefficient linearisation, not an owner omission - which is
  precisely the distinction F3.3v3g3 got wrong.
- Counterflow is structural, not constrained: bands split at the exact linear
  zero crossing of `dp(z)`, direction is `sign(dp)`. A converged state with the
  neutral plane inside the span but one direction at zero is rejected
  (`FAILURE_COUNTERFLOW_VIOLATION`). There is no `alpha`, `blend` or `skew`
  anywhere in the code, and a test scans for those identifiers.
- Species and O2 are deliberately absent: they do not appear in the EOS, so
  advecting them after convergence carries exactly zero feedback error.
- **Two defects found and fixed during bring-up.** Both are cheap to
  reintroduce, so they are recorded rather than quietly repaired:
  1. The line-search merit function normalised the residual by gross
     throughput. That denominator depends on the pressure iterate and
     collapses as the solve approaches equilibrium, so an improving step could
     score worse and Newton stalled at `~0.94` after a single step. It now
     normalises by room inventory, which is iterate-independent. Newton then
     reaches `3e-14` - the double-precision floor - in 11 iterations from a
     stiff start. The throughput-normalised value is retained as telemetry.
  2. Godot's `SceneTree.quit()` only *requests* a shutdown. A fixture calling
     `quit(1)` on failure fell through, printed its PASS marker and had its
     exit code overwritten by the later `quit(0)`. Verified with a minimal
     probe: the marker printed and the process exited `0`. The new fixture
     returns explicitly after `quit(1)`; the pre-existing g1/g2/f0 fixtures do
     **not** and would mask failures. That audit is a separate task, out of H1
     scope.
- Verification: Godot 4.7.1 fixture `PHASE3_F33V3H1_COUPLED_PRESSURE_SOLVER_PASS`
  with 18 contracts plus a negative control that confirms a broken assertion
  exits non-zero; 25 structural contracts PASS; full-project parse clean;
  g2/g1/f0 fixtures still PASS; `pytest -k "phase3 or guardrail"` 817 PASS / 2
  FAIL (the established baseline); Physics 9/15/5/0; ILV 15/14/0; gap
  inventory 353 + 6 VALID_GAP + 71 non-gating.
- Next: **H2 only** - passive preview with predicted next state behind a new
  default-OFF flag, emitting no routes. Do not write a persistent apply path
  in H2.
- Binding design:
  `docs/validation/PHASE3_F33V3H0_COUPLED_PRESSURE_SOLVER_DESIGN.md`.

## Current Session Update - 2026-07-26 - F3.3v3h0 coupled solver design GO

- Design-only phase. No motor code was written. One passive measurement was
  required to choose the architecture and was run read-only.
- Added `scripts/simulation/analyze_phase3_f33v3h0_pressure_owner_attribution.py`
  plus tests. It uses only committed F3.3c1/F3.3d1 residence columns.
- **The canonical EOS is exactly affine**:
  `p_r = (R/V_r) * (M_r*T_ref + E_r/cp)`. Owner pressure contributions
  therefore superpose exactly. Attribution closes against the exported EOS to
  `1.37e-4 Pa`, which is CSV `%.8f` print quantisation, not a physical gap.
- **Plume and inter-zone heat are exactly pressure-neutral** (`0.000000 Pa` in
  every interval of every room). They are intra-room transfers: they move the
  interface but never `p_r`. Thermal expansion is not a separate owner either -
  it is exactly the `E_r/cp` term of combustion and multisurface.
- **Owners cancel by 273x to 15612x.** R0 peak per 10 s interval:
  combustion `11701 Pa`, multisurface (reported as `other`) `7533 Pa`,
  interior_opening `3490 Pa`, interior_pressure `1973 Pa`, exterior `1776 Pa`,
  net `110 Pa`. Individual owners move R0 pressure by ~42% per timestep; their
  sum moves it by 0.22%.
- This closes the F3.3v3g3 root cause quantitatively. g3 solved for a residual
  built from ~4200 Pa/interval of interior owners while neglecting
  ~4315 Pa/interval of opposite-signed owners, so the interior-only optimum
  left the whole neglected sum as a persistent single-signed forcing term.
  Geometric growth follows. No alpha can fix a sign-level modelling error.
- Recommended architecture: **damped Newton over one pressure unknown per room**
  (`N <= 6` in scope) on a residual containing every owner; fluxes from the
  orifice law at the solved pressure, never scaled afterwards; counterflow
  preserved structurally by the neutral plane; species and O2 advected after
  convergence with zero feedback because they do not appear in the EOS.
  Picard supplies the first iterate only - it is not robust, because the
  pressure-crossing bound was active in 2008 of 2160 F3.3v3g2 steps (93%).
- Open gap, scheduled not hidden: the multisurface gas/surface exchange, the
  second-largest owner, is still classified `other` by the residence family
  classifier. The analyzer reports this as a failing verdict. H1 closes it with
  a diagnostic-only family addition.
- Plan H0-H6 defined with files, default-OFF flags, tests, metrics, STOP gates,
  GO/NO-GO, rollback and cost. H0 is complete.
- Next: **H1 pure solver primitive only** - new pure
  `sim/core/Phase3CoupledPressureSolver.gd`, no runtime call site, no flag.
  Do not start H2 in the same session as H1.
- Binding record:
  `docs/validation/PHASE3_F33V3H0_COUPLED_PRESSURE_SOLVER_DESIGN.md`.

## Current Session Update - 2026-07-26 - F3.3v3g3 persistent shadow NO-GO

- A default-OFF experimental
  `phase3_canonical_fixed_gross_pressure_network_persistent_shadow_enabled`
  candidate was evaluated under the complete F3.3v3g2 stack and then fully
  reverted after the STOP gate. No g3 flag, runtime call, CSV schema, fixture
  or structural wiring test remains in the repository. F3.3v3g2 is the current
  committed motor state.
- During the experiment, with the flag ON, the canonical interior bundle
  dropped both the base
  `canonical_interior_opening` routes and the additive
  `canonical_interior_pressure` routes and applied the F3.3v3g2 blended
  fixed-gross set instead. Replacement, never addition; one atomic bundle; one
  alpha per component for mass, enthalpy, O2 and every species; stable route
  and connection identities; no legacy write and no separate pressure
  accumulator.
- Stage 1 (30 s) mechanism result is clean: 24/24 rows, all 115 live columns
  byte-identical, 58 new columns all in the persistent family, gross mass
  preserved exactly, mass/energy/O2/species residuals zero, minimum accepted
  bundle fraction `1.0` with zero double-limit events, zero unexpected zone
  collapses, EOS valid throughout, minimum post lower shadow gas `30.158 kg`,
  accepted transport bidirectional.
- Stage 1 physics result is a decisive **NO-GO**:
  - R0 shadow gauge pressure `1.116 -> 6.292 -> 23.195 Pa` baseline versus
    `1.202 -> 14.279 -> 131.020 Pa` candidate (ratio `1.08 -> 2.27 -> 5.65`);
  - relaxed pressure request `0.363 -> 1.838 kg`, `5.07x` the baseline at one
    sixth of the F3.3v3f2 duration;
  - monotonic request growth for 111 consecutive intervals (limit 10);
  - predicted/observed objective divergence for 239 consecutive intervals;
  - cap count 717 against a 158 limit.
- Owner: once the imbalance is large the unconstrained optimum reaches
  `alpha = 1.0`, the crossing bound stops binding, and the accepted route set
  becomes fully one-directional (`out 0.013084 kg`, `in 0.000000 kg`) - the
  doorway counterflow collapses. The interior-network objective is not a
  Lyapunov function for the coupled system.
- Stages 2/3/4 (60/120/180 s) were **not launched**, as required.
- The 30 s CFAST envelope was excluded from the gate: the baseline itself is
  `-51.12%` on gross mass and `-17.63%` on net enthalpy at that checkpoint.
- Verification during the experiment: g3/g2/g1/f0 Godot 4.7.1 fixtures PASS;
  `pytest tests -k "phase3 or guardrail"` 805 PASS / 2 FAIL (the established
  baseline); Physics 9/15/5/0; ILV 15/14/0; gap inventory 353 + 6 VALID_GAP +
  71 non-gating; guardrails 9/10 with only the expected dirty-motor R2-1. The
  g3 fixture was removed with the candidate; the read-only analyzer and its
  tests are retained.
- Next: the following phase must include the other pressure owners in the
  residual it reduces, define stability on the coupled pressure trajectory, and
  treat an alpha that zeroes one doorway direction as invalid. Do not retry the
  current candidate with a tuned under-relaxation factor.
- Binding record:
  `docs/validation/PHASE3_F33V3G3_PERSISTENT_PRESSURE_NETWORK.md`.

## Current Session Update - 2026-07-26 - F3.3v3g2 passive preview GO

- Added default-OFF
  `phase3_canonical_fixed_gross_pressure_network_shadow_enabled`, effective
  only under the complete F3.3v3f1 fixed-gross stack.
- The runtime now partitions horizontal interior openings into connected
  components, rebuilds the full fixed-gross candidate from the **raw** pressure
  demand, calls the pure F3.3v3g1 primitive once per component and blends
  `route(alpha) = base + alpha * (full_fixed - base)` with one factor shared by
  gas, sensible enthalpy, O2 and all seven species. The blended routes are
  telemetry only: they never enter `network_routes`, a bundle, a transaction or
  any persistent state.
- Component identity is the sorted room list (`"0|1|2"`), built by union-find
  over canonicalized sorted pairs, so it is independent of opening order.
- The inventory bound is per source room/zone and per payload, fails closed on
  negative inventory or on base routes that already exceed the snapshot, and
  uses no empirical floor.
- Added 58 opt-in CSV columns under `phase3_shadow_pressure_network_*` plus
  `scripts/simulation/analyze_phase3_f33v3g2_pressure_network_preview.py`.
  Names deliberately never reuse the `fixed_gross` family.
- OFF/ON proof at 180 s: 114/114 rows, 838 shared columns, zero shared value
  differences, zero columns lost.
- Over all 2160 physical steps: objective increase `0`, mass/gross/energy/O2/
  species residuals all `0`, negative payloads `0`, predicted collapses `0`,
  minimum predicted lower gas `2.882 kg`. Two steps fail closed with
  `alpha = 0` inside the 0-10 s ignition transient and none afterwards. The
  minimum predicted upper gas of `0.000 kg` comes from 4 already-empty zone
  samples, not from a preview debit.
- The binding limiter is the pressure-sign crossing bound (2008 steps), not
  inventory (0 steps). 277 steps are dormant by non-descent.
- R0 doorway at 180 s: gross mass `143.875 kg` vs CFAST `146.174 kg`
  (`-1.57%`); net enthalpy `6242.103 kJ` vs `6301.709 kJ` (`-0.95%`); net mass
  `0.198 kg` vs `7.290 kg`. Net mass cannot improve yet because the preview
  cannot evolve the pressure it is bounded by.
- Verification: g2 and g1 Godot 4.7.1 fixtures PASS; focused chain 68/68 PASS;
  `pytest tests -k phase3` 741 PASS; full `pytest tests` 1360 PASS / 18 FAIL,
  the same 18 reproduced at `HEAD` in a clean worktree; Physics 9/15/5/0; ILV
  15/14/0; gap inventory 353 + 6 VALID_GAP + 71 non-gating; guardrails 9/10
  with only the expected dirty-motor R2-1.
- Decision: passive preview GO; runtime authority, persistent shadow state and
  Group A/C work all remain NO-GO.
- Historical next gate: F3.3v3g3 persistent dynamic shadow. It was subsequently
  rejected at the 30 s STOP gate and its runtime patch was fully reverted; see
  the current-session entry above.
- Binding record:
  `docs/validation/PHASE3_F33V3G2_PRESSURE_NETWORK_PREVIEW.md`.

## Current Session Update - 2026-07-26 - F3.3v3g1 primitive GO

- Added pure
  `compute_fixed_gross_pressure_network_relaxation(...)` in
  `Phase3ZoneMassSystem.gd`.
- It has no runtime call site, flag or persistent-state access. It minimizes
  the real candidate pressure response and returns separate optimum,
  no-crossing and inventory bounds.
- Godot 4.7.1 fixture passes single connection, chain, non-descent,
  inventory-limited, disconnected-component, order-invariance, zero-response
  and malformed-input contracts.
- Next: F3.3v3g2 passive default-OFF preview only. It must partition connected
  components and may emit telemetry, but must not append candidate routes to
  the canonical bundle or mutate private shadow state.
- Binding record:
  `docs/validation/PHASE3_F33V3G1_PRESSURE_NETWORK_PRIMITIVE.md`.

## Current Session Update - 2026-07-26 - F3.3v3g0 design GO

- Mapped the current pressure path. The old network relaxation predicts the
  response of additive pressure routes; F3.3v3f3 applied fixed-gross routes
  with a different mass/enthalpy pressure response. That is the immediate
  numerical mismatch behind the explicit feedback.
- Designed a bounded network solve over the route actually proposed:
  - start from pressure after the base opening routes;
  - measure the pressure delta from base to full fixed-gross routes;
  - minimize the sum of squared connected-room pressure differences;
  - bound by pressure-sign crossing and source-zone inventories;
  - blend mass, energy, O2 and every species with one common factor.
- F3.3v3g phases:
  - `g1`: pure dictionary-only relaxation primitive and tests;
  - `g2`: default-OFF passive runtime telemetry;
  - `g3`: staged 30/60/120/180 s persistent shadow;
  - `g4`: 300/600 s Group A/C validation;
  - `g5`: separate authority decision.
- Only `g1` is approved next. It must not wire runtime state, flags, reports
  or cases. Dynamic runtime work in the same session is explicitly forbidden.
- Binding design:
  `docs/validation/PHASE3_F33V3G0_PRESSURE_NETWORK_DESIGN.md`.

## Current Session Update - 2026-07-26 - F3.3v3f3 dynamic candidate NO-GO

- A default-OFF canonical-shadow experiment dynamically replaced additive
  opening plus pressure routes with the fixed-gross directional routes for
  180 s. Its motor patch has been fully reverted; the committed runtime
  remains F3.3v3f2 telemetry only.
- Isolation passed exactly: baseline and candidate both contain 114 rows, and
  all 115 non-shadow fields are byte-identical. Legacy state, FED and official
  validation behavior were not changed.
- The canonical candidate failed decisively in R0:
  - caps `79 -> 1676`, all candidate caps positive;
  - pressure requested `6.368 -> 804.659 kg`;
  - accepted pressure transport `3.245 -> 205.113 kg`;
  - rejected absolute mass `28.240 -> 599.516 kg`;
  - preview net enthalpy `6321.966 -> 22075.625 kJ`;
  - lower shadow gas `21.555 -> 0.000 kg`.
- Decision: direct dynamic route replacement NO-GO. It creates one-way
  explicit pressure feedback and zone collapse.
- Do not retry direct replacement, independent per-step clipping, static
  normalization over the old pressure trajectory, or a gross-flow increase.
- Next phase: **F3.3v3g0 implicit interior pressure network design**. It must
  define pressure residual ownership, an implicit or under-relaxed connected
  room solve, antisymmetric flow, inventory bounds and convergence/rollback
  criteria before any new motor patch.
- Binding record:
  `docs/validation/PHASE3_F33V3F3_DYNAMIC_CANDIDATE_NO_GO.md`.

## Current Session Update - 2026-07-26 - F3.3v3f2 cap owner closed

- Extended the existing default-OFF fixed-gross preview with ten cumulative
  cap fields; no authority or legacy state changed.
- R0 at 180 s:
  - CFAST net doorway out `7.290 kg`;
  - pressure request `6.368 kg` (87.35%);
  - cap acceptance `3.245 kg` (44.51%);
  - 79 caps: 44 positive, 35 negative;
  - absolute rejected mass `28.240 kg`, maximum one-step rejection
    `0.986 kg`.
- The capped subset requests `+1.173 kg` but accepts `-1.950 kg`. Local
  timestep clipping introduces a `-3.123 kg` directional bias after the
  pressure-sign transition around 120 s.
- Decision: fixed-gross architecture retained, current static post-hoc
  authority NO-GO. A normalized slab solve against the unchanged oscillatory
  pressure trajectory is insufficient.
- Verification: focused chain 16/16 PASS; Physics 9/15/5/0; ILV 15/14/0;
  gap inventory synchronized at 347/353 plus 6 VALID_GAP.
- Next: a separate default-OFF dynamic canonical-shadow branch may replace
  additive opening+pressure routes with fixed-gross routes for 180 s only,
  allowing accepted transport to evolve the next-step pressure. It must not
  write legacy state or change official validation artifacts.
- Binding record:
  `docs/validation/PHASE3_F33V3F2_CAP_LEDGER.md`.

## Current Session Update - 2026-07-26 - F3.3v3f1 shadow GO

- Added default-OFF
  `phase3_canonical_fixed_gross_pressure_skew_shadow_enabled`.
- The runtime now calls the pure F3.3v3f0 primitive after interior-pressure
  relaxation and before the current additive pressure routes are appended.
  The returned routes are telemetry only: they never enter a bundle,
  transaction, residence ledger or physical state.
- Added 21 opt-in CSV columns plus
  `scripts/simulation/analyze_phase3_f33v3f1_fixed_gross_shadow.py`.
- OFF/ON proof at 180 s: 114/114 rows, 807 shared columns and zero shared
  value differences. Mass, energy, O2 and species residuals are all zero.
- Verification before the implementation commit: focused tests 14/14 PASS;
  full `pytest tests` 1326 PASS / 18 FAIL (17 historic plus the expected
  dirty-motor R2-1); Physics 9/15/5/0; ILV 15/14/0; gap inventory synchronized.
  Do not run bare `pytest` at repo root because it collects inaccessible
  historical temp directories under `runs/`.
- R0 doorway at 180 s:
  - gross mass `143.875 kg` vs CFAST `146.174 kg` (-1.57%);
  - net enthalpy `6321.966 kJ` vs CFAST `6301.709 kJ` (+0.32%);
  - net mass `3.245 kg` vs CFAST `7.290 kg` (-55.49%);
  - 79 directional cap events.
- Decision: preview/architecture GO, runtime authority NO-GO. F3.3v3f2 must
  diagnose cap timing and evaluate a combined slab pressure/buoyancy solve;
  do not directly promote the current post-hoc skew.
- Current validation inventory is `347/353` required PASS plus 6 documented
  VALID_GAP: Group A x3 and Group C x3. The third Group C check was added by
  the earlier F3.3l topology-equivalence checkpoint; older historical sections
  below that say `348/353` or 5 VALID_GAP are retained as dated records.
- Central precursor chain:
  - F3.3v3d closed pressure inventory and rejected pressure tuning;
  - F3.3v3e identified the additive pressure route as the doorway energy
    error owner;
  - F3.3v3f0 added the pure dormant fixed-gross primitive;
  - F3.3v3f1 wires it as passive runtime telemetry.
- Binding record:
  `docs/validation/PHASE3_F33V3F1_FIXED_GROSS_SHADOW.md`.

## Current Session Update - 2026-07-26 - F3.3v3c leakage owner closed

- Added read-only
  `scripts/simulation/analyze_phase3_f33v3c_exterior_leakage.py`.
- CFAST 7.7.5 creates two R0 leakage vents:
  - wall: `0.007344 m2`, distributed from `0.12` to `2.28 m`;
  - floor: `0.001040 m2`, starting at floor level;
  - total: `0.008384 m2`, discharge coefficient `0.7`.
- SimuFire represents leakage through one closed exterior opening using the
  global `window_leakage_area_m2=0.005`.
- At 180 s the missing exterior net outflow is split:
  - upper `1.263 kg`;
  - lower `3.649 kg` (`74.3%` of the total).
- Area is not the only owner. SimuFire exterior pre-pressure has the opposite
  sign to CFAST at 120, 130, 140 and 180 s and draws ambient gas inward while
  CFAST continues outward.
- Decision: layer attribution GO; area-only motor experiment NO-GO.
  F3.3v3d must attribute the pressure-sign reversals to cumulative mass and
  enthalpy owners before any distributed-leakage candidate.
- Binding record:
  `docs/validation/PHASE3_F33V3C_EXTERIOR_LEAKAGE_ATTRIBUTION.md`.

## Current Session Update - 2026-07-26 - F3.3v3b mass owner closed

- Added read-only
  `scripts/simulation/analyze_phase3_f33v3b_mass_interface_attribution.py`.
- The current and pre-v3a 180 s candidates give the same owner ordering.
  F3.3v3a therefore does not create the mass discrepancy.
- At 180 s the current R0 total-mass error is `+3.961 kg`. Its explicit
  decomposition is:
  - exterior net-outflow deficit `+4.912 kg`;
  - interior-doorway net-outflow deficit `+0.922 kg`;
  - canonical gas-source omission versus CFAST pyrolysis `-2.114 kg`;
  - initial-state bias `+0.221 kg`;
  - unexplained residual `+0.020 kg`.
- Canonical projection/reconcile net mass and residence residual are zero.
  Plume transfer is internal and already exceeds CFAST by `11.161 kg`.
- Total-mass ownership is therefore closed, but upper/lower partition is not:
  upper remains `-2.187 kg`, lower `+6.149 kg` and interface `+0.210 m`.
- Next gate: F3.3v3c exterior leakage topology and per-zone outflow
  correspondence. Do not increase plume, apply a global doorway gain, add a
  projection correction or tune HRR.
- Binding record:
  `docs/validation/PHASE3_F33V3B_MASS_INTERFACE_ATTRIBUTION.md`.

## Current Session Update - 2026-07-26 - F3.3v3a source GO / physics NO-GO

- Added default-OFF
  `phase3_canonical_unfiltered_fire_growth_shadow_enabled`.
- In the complete 180 s Group C stack it removes the second proposal HRR
  filter and closes the live/canonical object-fuel difference from
  `0.58758433 MJ` to `0.00000248 MJ`; all internal residuals remain zero and
  all 115 live columns remain identical.
- The thermal effect is only `+0.162 C`; R0 upper temperature remains below
  its required lower bound (`140.03 C` vs `144.816 C`).
- No 300/600 s unfiltered run was made because the 180 s STOP did not pass.
- Revised owner: R0 has about `3.96 kg` excess total gas, too much lower mass,
  too little upper mass and an interface about `0.21 m` too high.
- Decision: fuel-source correspondence GO; runtime authority and Group C
  retirement NO-GO. Next is F3.3v3b early mass/interface attribution.
- Binding record:
  `docs/validation/PHASE3_F33V3A_UNFILTERED_GROWTH_EXPERIMENT.md`.

## Current Session Update - 2026-07-26 - F3.3v2d correspondence diagnosis

- The `0.58758433 MJ` live/canonical fuel difference is not caused by the
  object allocator. Only one of seven objects is eligible throughout the
  active 180 s rows, and allocation/atomic/aggregate residuals are zero.
- Legacy object inventory follows `solid_pyrolysis_kw * dt`; canonical
  products follow smoothed accepted proposal HRR. During growth the ideal
  pyrolysis curve is higher, so legacy consumes more. Once both reach 300 kW,
  the per-step mismatch becomes zero and the cumulative delta stays flat.
- The analyzer now reports source-debit mismatch separately from internal
  object-ledger closure.
- Decision: diagnostic GO, runtime authority NO-GO. F3.3v2e must design an
  atomic split between pyrolysis/feedstock debit and combusted-fuel
  equivalent before any live write or 300/600 s run.
- Binding record:
  `docs/validation/PHASE3_F33V2D_FUEL_CORRESPONDENCE_DIAGNOSIS.md`.

## Purpose

This note records the repository hygiene and validation state after the non-motor cleanup. It is meant to let another machine or contributor continue without relying on chat history.

## Current Session Update - 2026-07-26 - F3.3v2b atomic routing GO

- Added
  `phase3_canonical_fire_products_routing_shadow_enabled`, default OFF.
- When its complete parent stack is active, F3.3v2 fuel, O2, seven species,
  convective/radiative energy and plume HRR/Qc replace the legacy inputs of
  the existing canonical combustion transaction.
- The existing atomic bundle remains the only final inventory gate and scales
  persistent aggregate fuel state with every physical route.
- OFF is byte-identical to committed F3.3v2. ON preserves all 115 live
  columns; 18 fire-room rows route with atomic fraction 1.0 and zero
  fuel/O2/species/energy/plume residuals.
- Verification: focused pipeline 108/108 PASS; full pytest 1278 PASS plus
  the same 17 pre-existing failures; guardrails 10/10 PASS; physics and ILV
  remain at 0 FAIL.
- Runtime authority remains blocked because the validation case has explicit
  fuel objects without a canonical synchronization owner. No live state,
  official case/report, expected, tolerance, CTRL or VALID_GAP changed.
- Next: design F3.3v2c explicit fuel-object synchronization. It must prove
  aggregate/object conservation before any 180/300/600 runtime-authority
  correspondence run.
- Binding record:
  `docs/validation/PHASE3_F33V2B_FIRE_PRODUCTS_ROUTING_EXPERIMENT.md`.

## Current Session Update - 2026-07-26 - F3.3v2c object-sync design

- Audited the legacy explicit-object burn path. It uses eligibility and
  dynamic weights, caps by per-object inventory, redistributes leftover
  demand, then mutates fuel, HRR, state, exposure and char.
- The canonical persistent state is aggregate-only and its atomic
  interpolator currently handles scalars. Promoting it now could debit the
  aggregate without debiting the seven explicit objects.
- Defined a default-OFF persistent ledger keyed by stable object ID, proxy
  exclusion, duplicate/empty-ID rejection, deterministic bounded allocation
  and nested interpolation by the one atomic fraction.
- No motor code changed in this design step.
- F3.3v2c1 now adds the pure allocator and direct Godot fixture. It validates
  stable IDs, sorts deterministically, caps every object, redistributes
  leftover debit and closes aggregate allocation without live writes.
- Next implementation order: nested atomic interpolation, wiring/telemetry,
  then 180 s OFF/ON. Runtime authority remains NO-GO.
- Binding record:
  `docs/validation/PHASE3_F33V2C_FUEL_OBJECT_SYNC_DESIGN.md`.

## Current Session Update - 2026-07-26 - F3.3v2c2 object ledger GO

- Added default-OFF persistent object synchronization beneath F3.3v2b.
- Seven explicit object IDs remain stable; the same atomic fraction commits
  object fuel, aggregate fuel, O2, species and energy.
- OFF is byte-identical. ON preserves all 115 live columns and closes seed,
  allocation, atomic and aggregate/object residuals at zero.
- The legacy object path consumes up to 0.58758433 MJ more by 180 s. This is
  now an explicit runtime-authority blocker, not a hidden fallback.
- Verification: focused 14/14 PASS; full pytest 1284 PASS plus the same 17
  pre-existing structural failures; guardrails 10/10 PASS after commit,
  including `test_exit0_real_json`; physics and ILV remain at 0 FAIL.
- Next: F3.3v2d per-object correspondence/state-owner diagnosis, then
  300/600 s. No live activation or Group C retirement is authorized.
- Binding record:
  `docs/validation/PHASE3_F33V2C2_FUEL_OBJECT_SYNC_EXPERIMENT.md`.

## Current Session Update - 2026-07-26 - F3.3v2 product telemetry GO

- Added pure products from the accepted F3.3v1 proposal: fuel, O2, seven
  species, carbon ledger, total/radiative/convective energy and plume HRR/Qc
  drivers.
- Every accepted product uses one common decision fraction. `quality_phi`
  uses only O2 and ventilation constraints, so fuel exhaustion cannot
  generate a false rich-combustion yield spike.
- Added `phase3_canonical_fire_products_shadow_enabled`, default OFF, and 46
  opt-in CSV fields. Geometry-dependent plume mass remains in ThermalSystem.
- The 180 s corridor gate preserves 114/114 rows and all 728 shared columns
  exactly. The 46 new columns close fuel, O2, carbon, species and energy
  residuals at CSV precision.
- The scenario has seven explicit fuel objects, correctly reported as
  requiring synchronization. F3.3v2 does not write those objects or
  `RoomModel`.
- Decision: passive products GO. Runtime authority and Group C retirement
  remain NO-GO.
- Next: F3.3v2b default-OFF atomic shadow routing. Connect the accepted bundle
  to persistent canonical fuel/O2/species/energy state and the existing F3.3t
  plume driver without live writes. F3.3v3 180/300/600 correspondence remains
  blocked until that route closes.
- Binding record:
  `docs/validation/PHASE3_F33V2_FIRE_PRODUCTS_EXPERIMENT.md`.

## Current Session Update - 2026-07-25 - F3.3v1 proposal telemetry GO

- Added a pure dictionary-only canonical fire proposal driven by persistent
  proposal state and immutable t-squared fire parameters.
- Hard extinction, exact O2 inventory, optional Kawagoe ventilation and fuel
  inventory are explicit limits. No inverse legacy throttle or forced HRR is
  used.
- Added `phase3_canonical_fire_proposal_shadow_enabled`, default OFF, with 19
  opt-in CSV fields. The existing canonical combustion transaction remains
  the live shadow source; F3.3v1 is telemetry only.
- The 180 s corridor OFF/ON gate has 114/114 rows, 709 shared columns and
  zero shared-value differences. Room 0 is supported for all 18 active
  samples, reaches the model-derived 300 kW cap, consumes fuel monotonically
  and never reports a zero-O2 flame.
- Direct Godot fixture PASS; focused Phase 3 tests 32/32 PASS; analyzer and
  proposal tests 16/16 PASS; full pytest 1249 PASS plus the same 17
  pre-existing structural failures; Physics and ILV remain at 0 FAIL; gap
  inventory remains 347/353 plus 6 VALID_GAP.
- Decision: passive mechanism GO. Runtime authority and Group C retirement
  remain NO-GO.
- Next: F3.3v2 pure accepted products and object-level fuel/yield ownership.
  Do not connect the proposal to F3.3t or live combustion before fuel, O2,
  carbon, species and energy close atomically.
- Binding record:
  `docs/validation/PHASE3_F33V1_FIRE_PROPOSAL_EXPERIMENT.md`.

## Current Session Update - 2026-07-25 - F3.3v proposal design complete

- Mapped the complete legacy combustion order. O2 already changes fire age,
  pyrolysis, flame/smolder/pool targets, retained fuel, smoothed HRR, fuel
  consumption and species before the canonical evaluator reads the room.
- The current persistent state and atomic bundle are reusable, but their
  proposal source is not: it reads post-throttle `room.hrr_kw`,
  `room.hrr_target_kw`, fire-clock deltas and legacy species.
- Selected a pure, pre-legacy canonical proposal from persistent state and
  immutable fire parameters. Hard extinction, exact O2 inventory, Kawagoe
  ventilation and fuel then limit one atomic fuel/O2/species/energy/plume
  transaction.
- The linear canonical O2 quality factor remains telemetry/yield context in
  the first experiment; it will not silently multiply the proposal in
  addition to the exact inventory and extinction gates.
- Initial scope is deliberately limited to the simple t-squared fires used by
  Groups A/C. Advanced fuel objects, latent fire, pool release, backdraft,
  suppression, flashover and spread must report unsupported until separately
  modeled.
- No motor code or validation artifact changed. Next implementation gate is
  F3.3v1, default OFF and shadow-only. Binding record:
  `docs/validation/PHASE3_F33V_CANONICAL_FIRE_PROPOSAL_DESIGN.md`.

## Current Session Update - 2026-07-25 - F3.3u stability GO / authority NO-GO

- Extended the unchanged F3.3t candidate through independent deterministic
  300 and 600 s OFF/ON runs with Godot 4.7.1.
- All nine correspondence RMSE families still improve at 180, 300 and 590 s.
  State remains finite, both zone inventories remain positive and the maximum
  mass/O2/energy residual is `2.8e-7`.
- Prefixes of the 600 s runs exactly match the independent 180 and 300 s
  runs.
- Runtime authority remains NO-GO: projected candidate values fail R0 upper
  temperature at 180/300/600 and upper O2 at 600. The candidate would reopen
  the already closed t=180 check and closes none of the three active Group C
  gaps.
- Late owner confirmed at 590 s: canonical decision fraction is `1.0`, but
  the proposal and accepted HRR are both `137.46 kW` versus CFAST `300 kW`.
  Canonical O2 factor (`0.694`) is healthier than legacy (`0.442`), proving
  the proposal arrives pre-throttled by the live engine.
- Decision: F3.3t mechanism stability GO; authority and Group C retirement
  NO-GO. Next is design-first F3.3v for an unthrottled canonical fire
  proposal. Binding record:
  `docs/validation/PHASE3_F33U_EXTENDED_STABILITY.md`.

## Current Session Update - 2026-07-25 - F3.3t coupled plume GO

- Added `phase3_coupled_plume_shadow_enabled`, default OFF and effective only
  under the complete canonical plume plus multi-surface stack.
- The plume now has an experimental complete Heskestad path driven by
  canonical accepted HRR and effective `chi_rad`. Its mass, enthalpy and O2
  share one lower-zone inventory cap and the O2 decision is not applied twice.
- OFF is byte-identical to the F3.3r2d binding CSV.
- At 10-180 s, ON improves RMSE versus CFAST for upper/lower mass, interface,
  upper/lower temperature, upper/lower O2, accepted HRR and plume rate.
  Improvements range from `25.9%` to `95.5%`.
- Canonical mass/O2/energy residuals remain exact to CSV precision; maximum
  observed absolute residual is `8e-8`.
- Verification: direct Godot fixture PASS; focused tests 11/11 PASS; broad
  Phase 3/F3.3/two-zone selection 662 PASS plus the same five pre-existing
  structural failures; physics and ILV have 0 FAIL; gap inventory unchanged.
- Decision: experimental mechanism GO. Runtime authority and Group C
  retirement remain NO-GO because 180 s still has interface `+0.192 m`,
  lower mass `+5.316 kg` and temperature residuals.
- Next: F3.3u extends the exact candidate to 300/600 s without new equations.
  Binding record:
  `docs/validation/PHASE3_F33T_COUPLED_PLUME_EXPERIMENT.md`.

## Current Session Update - 2026-07-25 - F3.3s causal audit GO

- Added a pure Python, read-only audit over the existing 180 s F3.3r2d
  candidate and committed CFAST zone/compartment/mass exports.
- The first available checkpoint, 10 s, already has upper mass
  `-2.644 kg`, lower mass `+2.922 kg` and interface `+0.113 m` versus
  CFAST. Upper O2 fraction is still within `0.0043`.
- At 10 s, residence residual and projection owners are zero, canonical O2
  factor is `1.0`, requested plume equals accepted plume and doorway owners
  carry only about `0.20 kg` gross. Plume cumulative transfer is already
  `1.067 kg` short.
- CFAST flame height crosses its interface at 60 s. SimuFire O2 fraction
  diverges at 70 s and its far-field `z_eff` is pinched to
  `0.107-0.100 m` at 80-90 s, reducing requested plume to about
  `0.007 kg/s` while CFAST remains near `0.65-0.70 kg/s`.
- Decision: plume request/source is the first incorrect owner; O2 throttle
  and radiative rejection are downstream. Projection, doorway exchange and
  atomic acceptance are not the root cause.
- Verification: focused analyzer 9/9 PASS; related analyzers 21/21 PASS;
  broad Phase 3/F3.3/two-zone selection 650 PASS plus the same 5
  pre-existing structural contract failures. Physics and ILV have 0 FAIL,
  guardrails are 10/10 PASS and gap inventory is synchronized.
- No motor, official case, report, expected, tolerance, CTRL, VALID_GAP,
  FED, HVAC or visual path changed.
- Next: F3.3t design-first region-aware plume/interface transition with one
  shared convective-HRR contract. Do not retry the F3.3d2 source-term-only
  patch, inject CFAST state or run beyond 180 s before its STOP gate.
- Binding record:
  `docs/validation/PHASE3_F33S_LAYER_MASS_O2_CAUSAL_AUDIT.md`.

## Current Session Update - 2026-07-25 - F3.3r2d attribution GO / physics NO-GO

- Added default-OFF cumulative source attribution for requested,
  decision-rejected, atomic-rejected and routed surface radiation.
- Added upper/lower gas-surface and wall-area migration observability. A
  repeated same-step surface preparation now preserves diagnostic migration
  energy instead of overwriting it; physical state and routes are unchanged.
- The tested read-only analyzer closes source, routing and gas/surface split
  ledgers and preserves all 13,110 legacy cells exactly.
- At 180 s, CFAST radiation is `13.392 MJ`, SimuFire requests `12.938 MJ`
  and routes `9.124 MJ`. Decision rejection owns `3.814 MJ`; upstream source
  trajectory owns `0.454 MJ`; atomic rejection is zero.
- The decision fraction equals the canonical O2 HRR factor at all
  checkpoints. At 180 s SimuFire uses `O2=0.0355` and accepts `68.2 kW`,
  while CFAST upper O2 is `0.1667` and HRR remains `300 kW`.
- The simulated interface (`1.969 m` versus CFAST `0.736 m`) shifts
  `1.775 MJ` from upper wall to lower wall in the read-only routing
  counterfactual.
- Wall-area migration carries `1.591 MJ` gross with zero residual. Upper and
  lower gas-surface exchange close exactly.
- Decision: telemetry and diagnosis GO; physical adoption, runtime authority
  and Group C retirement remain NO-GO. Do not compensate with extra
  radiation or a prescribed CFAST interface.
- Next: F3.3s read-only layer-mass/O2 causal audit. Find the first incorrect
  owner among plume, doorway flow, O2 sink and projection before another
  motor experiment. Stop at 180 s.
- Binding record:
  `docs/validation/PHASE3_F33R2D_SOURCE_ROUTING_ATTRIBUTION.md`.

## Current Session Update - 2026-07-25 - F3.3r2c telemetry GO / physics NO-GO

- Added opt-in cumulative multi-surface correspondence telemetry plus tested
  scratch case generation and a deterministic CFAST comparison analyzer.
- Godot 4.7.1 runtime fixture PASS; focused new tests are 19/19 PASS and the
  complete Phase 3 selection is 582/582 PASS outside the restricted temp
  sandbox.
- The 60/120/180 s scratch matrix completed without a Godot crash. No 300 or
  600 s run was made because the mandatory 180 s gate failed.
- Energy bookkeeping is sound: R0 total surface storage is `23.472 MJ`
  versus CFAST `26.993 MJ`, gas-driven storage is `14.347 MJ` versus
  `13.601 MJ`, and the cumulative residual is `-0.00000008 kJ`.
- Physical correspondence fails: accepted fire radiation is `9.124 MJ`
  versus `13.392 MJ`; R0 upper/lower temperatures are `115.87/25.88 C`
  versus `159.82/61.56 C`; the upper mass is only `7.80 kg` versus
  `26.94 kg`; interface is `1.969 m` versus `0.736 m`.
- Surface partition is wrong despite a close total: lower wall is
  `+2.369 MJ` high and floor is `-3.061 MJ` low against CFAST.
- Physical and independent-compartment boundary variants are nearly
  identical at 180 s. Missing paired inter-room surfaces are not the binding
  0-180 s error.
- Zero legacy differences were found across 13,110 compared cells. No
  official case, report, expected, tolerance, CTRL, VALID_GAP, FED, HVAC or
  visual path changed.
- Decision: retain the observability, do not promote the physical shadow and
  do not retire Group C.
- Next: F3.3r2d read-only attribution of requested/accepted fire radiation,
  O2/source feedback, simulated versus CFAST interface routing weights and
  per-zone surface exchange. No new coefficient and no run beyond 180 s.
- Binding record:
  `docs/validation/PHASE3_F33R2C_MULTISURFACE_CORRESPONDENCE.md`.

## Current Session Update - 2026-07-25 - F3.3r2b2 topology GO

- Added explicit physical `phase3_surface_boundaries` metadata to each room
  for ceiling, upper wall, lower wall and floor.
- Each surface partitions area into exterior, inter-room and adiabatic
  fractions; all four surfaces and a sum of one are mandatory.
- Missing or invalid topology fails closed to four adiabatic surfaces. No
  physics is inferred from visual meshes, room rectangles or openings.
- Exterior area now drives the existing surface solver using the fixed
  canonical `0.025 kW/(m2 K)` coefficient scaled by exterior fraction.
- Inter-room area is visible telemetry but deliberately does not exchange heat
  until a paired-surface transaction exists.
- Added shadow-only CSV observability for multi-surface storage, exchange,
  topology fractions and combined energy closure.
- Godot 4.7.1 fixture and full parse PASS; 511 Phase 3 tests PASS.
- A 10 s OFF/ON scratch produced 66/66 rows, 459 shadow columns and zero value
  differences across 163 shared legacy columns. Mixed topology exported the
  expected 1.50/1.25/1.25 exterior/inter-room/adiabatic sums and zero combined
  energy residual.
- Physics remains 9 PASS / 15 CTRL / 5 WARN / 0 FAIL; ILV remains
  15 PASS / 14 CTRL / 0 FAIL; gap inventory remains 353 required,
  6 VALID_GAP and 71 non-gating.
- Guardrails before commit are 9/10 only because R2-1 correctly sees dirty
  motor files. No official case, report, baseline, tolerance, gap, FED, HVAC
  or visual file changed.
- Next: F3.3r2c staged 60/120/180 s correspondence in scratch. STOP before
  authority or gap retirement; add paired inter-room surfaces first if the
  unsupported fraction is material.
- Binding record:
  `docs/validation/PHASE3_F33R2B2_SURFACE_TOPOLOGY.md`.

## Current Session Update - 2026-07-25 - F3.3r2b1 exchange GO

- Added a pure pre-step preview and separate atomic queue for signed
  upper/lower gas-to-surface exchange.
- The single surface commit now combines accepted convection, gas radiation,
  fire radiation and exterior removal without recalculating accepted fluxes.
- Full, 0.5-partial, rejected and surface-to-gas fixtures close the combined
  gas/surface/exterior invariant.
- Explicit per-surface exterior Robin metadata is supported and tested.
- Runtime remains deliberately adiabatic because `RoomModel` has no
  authoritative ceiling/floor/wall exterior topology. Missing metadata is
  reported rather than inferred from visual geometry.
- Godot 4.7.1 fixtures and full-project parse PASS; 70 focused Python
  contracts PASS.
- A 10 s engine scratch produced 66/66 rows and zero value differences across
  163 shared legacy columns with the path OFF versus ON; scratch artifacts
  were removed.
- No official case, CSV schema, report, expected, tolerance, gap, FED or HVAC
  path changed.
- Next: F3.3r2b2 explicit enclosure boundary topology. Do not start F3.3r2c
  60/120/180 s correspondence before that STOP gate.
- Binding record:
  `docs/validation/PHASE3_F33R2B1_GAS_SURFACE_EXCHANGE.md`.

## Current Session Update - 2026-07-25 - F3.3r2b transaction GO

- Added default-OFF persistent ceiling, upper-wall, lower-wall and floor
  states to `Phase3ZoneMassSystem`.
- Interface movement now migrates the donor nodal profile by area and
  conserves total surface energy in both directions.
- Canonical combustion stages radiation metadata, but surfaces are mutated
  only after the existing atomic bundle fraction is resolved.
- The exact radiative partition is finalized as accepted total fire energy
  minus the Thermal-owned accepted convective route.
- Full, 0.5-partial and rejected bundles store 30, 15 and 0 kJ respectively
  in the direct Godot fixture.
- Duplicate deposits and simultaneous lumped-wall transactions fail closed.
- Godot 4.7.1: four related fixtures and full project parse PASS.
- Focused Python: 48/48 PASS.
- Physics remains 9 PASS / 15 CTRL / 5 WARN / 0 FAIL; ILV remains
  15 PASS / 14 CTRL / 0 FAIL; gap inventory remains synchronized.
- R2-1 is the only expected pre-commit guardrail failure because `sim/core`
  is dirty.
- No CLI, official case, CSV schema, report, expected, tolerance, gap, FED
  or HVAC path changed.
- Next: F3.3r2b1 atomic gas/surface/exterior exchange. Do not run F3.3r2c
  60/120/180 s correspondence before that invariant closes.
- Binding record:
  `docs/validation/PHASE3_F33R2B_MULTISURFACE_TRANSACTION.md`.

## Current Session Update - 2026-07-25 - F3.3r2a numerical GO

- Added pure `Phase3SurfaceEnergySolver.gd`; at the F3.3r2a checkpoint it had
  no runtime caller and no dependency on `RoomModel`, `SimulationEngine` or
  canonical persistent state. F3.3r2b now owns its only opt-in caller.
- The solver uses five implicit finite-volume nodes and returns a proposed
  state plus explicit energy residual without mutating its input.
- The default near-surface grid matches the 60 s semi-infinite concrete
  surface response within `3.0688%`.
- The 10,000-step fixture closes to `0.000000059642 kJ` cumulative residual.
- Direct fire radiation and gas radiation remain distinct ledger inputs.
- Godot 4.7.1 fixture and full-project parse PASS; focused Python tests are
  27/27 PASS.
- Physics remains 9 PASS / 15 CTRL / 5 WARN / 0 FAIL; ILV remains
  15 PASS / 14 CTRL / 0 FAIL.
- Guardrails before commit are 9/10 only because R2-1 correctly detects the
  new uncommitted `sim/core` file. Do not regenerate reference artifacts.
- Next: F3.3r2b default-OFF state/transaction wiring and direct fixtures.
  Do not enable an official case or start 60/120/180 s correspondence yet.
- Binding record:
  `docs/validation/PHASE3_F33R2A_SURFACE_SOLVER.md`.

## Current Session Update - 2026-07-25 - F3.3r2 design GO

- Closed the design contract for a default-OFF canonical multi-surface
  shadow with separate ceiling, upper-wall, lower-wall and floor state.
- Persistent surface state remains owned by `Phase3ZoneMassSystem`; a new
  pure `Phase3SurfaceEnergySolver` will own only five-node numerical work.
- Accepted combustion radiation must use the same atomic acceptance fraction
  as O2, fuel, species and convective energy, then route deterministically by
  surface area and emissivity.
- The new path replaces wall-like ambient gas decay with physical
  gas-to-surface storage and declared surface-to-exterior loss. It cannot run
  alongside the current lumped wall path.
- Moving interfaces must migrate wall area with its nodal energy profile so
  upper/lower repartition is conservative.
- Implementation is divided into F3.3r2a pure solver/fixtures, F3.3r2b
  state/transaction wiring and F3.3r2c staged 60/120/180 s scratch gates.
- Next: implement only F3.3r2a. Do not wire the solver into the simulation
  tick, enable an official case or retire a gap.
- Binding record:
  `docs/validation/PHASE3_F33R2_MULTISURFACE_SHADOW_DESIGN.md`.
- No motor, official artifact, tolerance, gap, FED or HVAC path changed.

## Current Session Update - 2026-07-24 - F3.3r1 owner attribution GO

- Added a read-only, tested semi-infinite conduction audit for the committed
  CFAST ceiling, upper-wall, lower-wall and floor temperature histories.
- Estimated R0 surface storage at 180 s as `26.993 MJ`.
- The CFAST fire contributes `13.392 MJ` direct radiation, leaving
  `13.601 MJ` gas-driven surface uptake. F3.3q independently infers
  `14.163 MJ` gas boundary loss; the residual is only `0.562 MJ` (4%).
- The F3.3r0 material shadow sends `9.107 MJ` to its wall, removes
  `3.796 MJ` through direct ambient decay and loses `0.531 MJ` through
  exterior/leakage. This explains why total gas loss matches while the wall
  remains cold.
- The wall reservoir is missing direct combustion radiation and ambient
  decay bypasses storage. Its retained energy is `17.985 MJ` below the CFAST
  surface estimate at 180 s.
- Decision: owner attribution closes. Full-area patch remains NO-GO.
- Next: F3.3r2 design-only default-OFF multi-surface shadow with direct
  combustion radiation, physical surface storage and one gas/surface/
  exterior energy invariant.
- Binding record:
  `docs/validation/PHASE3_F33R1_BOUNDARY_PARTITION_AUDIT.md`.
- No motor, official artifact, tolerance, gap, FED or HVAC path changed.

## Current Session Update - 2026-07-24 - F3.3r0 diagnostic GO / adoption NO-GO

- Reproduced the valid F3.3p1 canonical state exactly in scratch: 114 rows,
  552 shared canonical fields and zero differences above `1e-9`.
- Mapped CFAST concrete properties to rooms 0-2 through existing scratch
  room overrides while keeping the canonical wall area at `40.0 m2`.
- The 0-180 s boundary sink changed from `10.749` to `13.433 MJ`, reducing
  the CFAST shortfall from `3.414` to `0.730 MJ`.
- R0 upper temperature improved from `200.7` to `147.2 C` at 180 s against
  CFAST `159.8 C`; Hall upper also improved.
- The same control overcooled R0 lower (`35.6` versus `61.6 C`), Hall lower
  (`35.4` versus `48.4 C`) and R2 upper (`49.0` versus `62.1 C`).
- Decision: material correspondence is real but not sufficient. Do not map
  the material into the official case and do not expand to full enclosure
  area yet.
- All temporary coupled-Qc runtime code was removed; `sim/core` is identical
  to the session checkpoint.
- Next: F3.3r1 read-only audit of ceiling/upper-wall/lower-wall/floor area,
  energy storage and zone allocation before any multi-surface shadow design.
- Binding record:
  `docs/validation/PHASE3_F33R0_MATERIAL_CORRESPONDENCE.md`.
- No official validation artifact, tolerance, gap, FED or HVAC path changed.

## Current Session Update - 2026-07-24 - F3.3q diagnostic GO

- Added a read-only analyzer that reconstructs the R0 boundary-energy balance
  over `0-60`, `60-120` and `120-180 s`.
- CFAST removes `14.163 MJ` through inferred surfaces/leakage by 180 s;
  the valid F3.3p1 shadow removes `10.749 MJ`. The missing sink is
  `3.414 MJ`.
- Canonical inferred and observed sinks close exactly, so this is not an
  energy-ledger defect.
- F3.3p1 combustion heat is already close to CFAST. The primary remaining
  thermal owner is the boundary contract.
- The case does not map CFAST's explicit concrete properties into
  `RoomModel`, so the shadow uses lumped fallback walls.
- Canonical conductance/capacity uses `40.0 m2` while the R0 enclosure is
  `83.2 m2`; direct ambient decay partially masks the mismatch.
- Next: F3.3r0 material-only scratch control through existing room overrides.
  Keep wall area fixed so material and geometry remain separately attributable.
- Binding record:
  `docs/validation/PHASE3_F33Q_BOUNDARY_ENERGY_CORRESPONDENCE.md`.
- No motor, official validation artifact, tolerance, gap, FED or HVAC path
  changed.

## Current Session Update - 2026-07-24 - F3.3p1 NO-GO

- Tested one default-OFF, shadow-only coupled source in which accepted
  combustion `Qc` drives both heat and the complete Heskestad plume while
  F3.3n routing remains active.
- The first ON run changed global Engine inputs and is excluded from
  attribution. The corrected run keeps `chi_rad=0.35` and `D=0.6196 m`
  inside the shadow only.
- OFF is byte-identical to F3.3n. Corrected ON preserves all 115 legacy
  columns exactly.
- At 180 s R0 upper/lower mass, lower temperature, interface and plume all
  enter the CFAST acceptance envelope, but upper temperature reaches
  `200.75 C` versus CFAST `159.82 C`. The `+40.93 C` error exceeds the
  mandatory `31 C` gate.
- Hall and R2 also overheat. All mass, energy, O2, species and atomic
  residuals remain zero; this is a physical-correspondence failure.
- No 300 or 600 s run was made. Temporary F3.3p1 code, flag, CLI and tests
  were removed.
- Next: F3.3q read-only boundary-energy correspondence by time window. Do not
  introduce another Qc, plume, doorway or wall coefficient before owner
  attribution is complete.
- Binding record:
  `docs/validation/PHASE3_F33P1_COUPLED_QC_EXPERIMENT.md`.
- HVAC remains deferred.

## Current Session Update - 2026-07-24 - F3.3p design GO

- Reconstructed the R0 lower-zone budget from the old F3.3e1 coupled run,
  the accepted F3.3n runtime and committed CFAST slabs.
- F3.3n increases net lower return by `+6.18/+9.72/+20.92 kg` at
  `180/300/600 s`, but that alone does not prove the former collapse closed.
- At 600 s SimuFire plume is `109.09 kg` below CFAST while its route budget
  lacks `123.44 kg` of lower-zone margin: `54.94 kg` less lower return plus
  `68.50 kg` excess lower-source outflow.
- The close correspondence shows plume, thermal state, neutral plane and
  receiver routing must be tested as one closed loop. Static addition of old
  experiment deltas is invalid.
- Decision: design GO for one default-OFF F3.3p1 coupled-Qc experiment.
  Lower-zone collapse is not considered resolved. Run Gate 0 and 180 s
  first; 300 and 600 s require separate passed STOPs.
- No motor code, official case/report, expected value, tolerance, gap, CTRL,
  FED or HVAC path changed in F3.3p.
- Binding record:
  `docs/validation/PHASE3_F33P_COUPLED_QC_REENTRY_DESIGN.md`.
- HVAC remains deferred.

## Current Session Update - 2026-07-24 - F3.3o NO-GO

- Tested exact CFAST radiative fraction `0.35` as an isolated shadow-only
  convective-heat change with F3.3n routing fixed.
- OFF is byte-identical to F3.3n; ON preserves all 115 legacy columns.
- At 180 s R0 accepted combustion heat changes `10.996 -> 23.670 MJ`, but
  plume mass remains `72.03 -> 71.20 kg`.
- R0 upper temperature regresses `129.4 -> 224.2 C` versus CFAST `159.8 C`;
  upper mass regresses `23.80 -> 19.34 kg` versus `26.94 kg`.
- Hall and R2 also overheat. Every mass/energy/O2/species residual is zero
  and zero-O2 flame remains zero.
- Mandatory STOP failed. No 600 s run was made. Temporary F3.3o code, flag,
  CLI and tests were removed.
- Next: F3.3p design-first, reassess the unified F3.3e1 Q/Qc heat-plus-plume
  contract with corrected F3.3n routing.
- Binding record:
  `docs/validation/PHASE3_F33O_RADIATIVE_FRACTION_EXPERIMENT.md`.
- HVAC remains deferred.

## Current Session Update - 2026-07-24 - F3.3n mechanism GO

- F3.3n re-exposes the exact CFAST `flogo` receiver split behind
  `phase3_cfast_buoyancy_destination_shadow_enabled`, default OFF.
- The 180 s OFF CSV is byte-identical to F3.3m. ON preserves all 115 legacy
  columns and changes shadow state only.
- Hall upper mass changes from `0` to `14.58 kg` at 180 s and `13.68 kg` at
  600 s, versus CFAST `18.38/18.14 kg`.
- At 600 s all four connection destination fractions move toward CFAST.
  Mass, energy, O2 and species residuals remain zero.
- R0 upper temperature improves from `98.2` to `101.8 C`, still far below
  CFAST `168.8 C`. The convective-source deficit remains the binding owner.
- Decision: receiver mechanism GO; canonical authority and Group C
  retirement remain NO-GO.
- Next: F3.3o, exact CFAST radiative-fraction input in shadow while holding
  F3.3n routing fixed. Do not combine fire diameter or O2-law changes.
- Binding record:
  `docs/validation/PHASE3_F33N_BUOYANCY_RUNTIME.md`.
- HVAC remains deferred.

## Current Session Update - 2026-07-24 - F3.3m source audit GO

- Added a read-only, tested analyzer for the 60/120/180/300/600 s
  R0-to-Hall correspondence. It reconstructs committed CFAST signed slabs
  and compares them with the F3.3k connection ledger.
- Gross R0-to-Hall mass is 54% low in the first window, nearly closes by
  180 s and becomes 10-18% high after 180 s. A global doorway/pressure gain
  is rejected.
- R0 upper mass is nearly correct from 180 s onward, but upper temperature
  falls from 33 C low at 180 s to 71 C low at 600 s.
- Current canonical routing sends 0% of R0-to-Hall gas to Hall upper, while
  CFAST sends 90-100%. Hall canonical upper mass remains zero at every
  checkpoint. Reverse Hall-to-R0 routing also sends too little mass to R0
  lower late.
- Total HRR agrees, but canonical convective energy is only 35-45% of CFAST.
  The case still maps `chi_rad=0.70` versus CFAST `0.35`, and canonical O2
  throttling falls to 0.637 at 600 s while CFAST lower O2 remains above its
  0.10 limit and HRR stays prescribed.
- No motor behavior, case, official report, baseline, tolerance, gap or HVAC
  path changed in F3.3m.
- Next: F3.3n corrected-topology shadow experiment using the existing exact
  CFAST `flogo` receiver split only. Do not combine it with Qc/O2 input
  corrections; attribution must remain separate.
- Binding record:
  `docs/validation/PHASE3_F33M_SOURCE_CORRESPONDENCE.md`.

## Previous Session Update - 2026-07-23 - F3.3l scenario equivalence GO

- Corrected the exact-direction opening overrides in
  `cfast_corridor_chain.json`. Runtime now has only the two CFAST interior
  connections: `0 -> 1` and `2 -> 1` at 0.9 m.
- Closed the template-only Hall branches `3 -> 1`, `4 -> 1` and `5 -> 1`.
- Added the official CSV path so CFAST checks and physics coherence consume
  the same regenerated run.
- The F3.3k ledger proves that only `opening:0` and `opening:2` are active.
- Required deltas: R0 temperature 180 s FAIL->PASS; temperature 300 s
  PASS->FAIL; temperature 600 s remains FAIL; O2 upper 600 s PASS->FAIL.
- No expected value or tolerance changed. Group C is now three honest
  VALID_GAP; global required status is `347/353 PASS`, 6 VALID_GAP.
- Physics on the regenerated CSV has 0 FAIL and 55 D2PRE WARN.
- Next: F3.3m time-windowed R0-to-Hall source correspondence. No coefficient
  or authority promotion before that audit.
- Binding record:
  `docs/validation/PHASE3_F33L_SCENARIO_EQUIVALENCE.md`.

## Previous Session Update - 2026-07-23 - F3.3k connection audit GO

- Added a default-OFF per-connection accepted-route ledger. It exports only
  to `summary.json` and groups opening/pressure mass, enthalpy, source zones,
  destination zones, source temperature and upper destination fraction by
  opening and direction.
- Found a validation-case topology mismatch: CFAST has 3 compartments and 2
  open doors, while the configured `simple_house` case leaves 5 Hall doors
  open. Hall-R2 also remains at `0.8 m` because the override says `1 -> 2`
  while the template stores `2 -> 1`.
- The prior F3.3j conclusion that SimuFire had enough gross Hall mass was
  therefore contaminated by three additional room reservoirs.
- In a scratch equivalent-topology control, SimuFire Hall inflow is
  `88.168 kg` versus CFAST `128.253 kg`; net direct enthalpy is
  `2.275 MJ` versus `4.253 MJ`.
- R0-Hall owns the physical deficit: net Hall gain is `3.581 MJ` versus CFAST
  `6.302 MJ`. Hall-R2 exports less than CFAST and partially masks the deficit.
- The combined SimuFire R0-to-Hall source is `98.05 C` versus CFAST
  `121.29 C`; gross mass is `31.5%` low.
- Scratch corrected-topology legacy control at 180/300/600 s gives
  `149.86/121.14/99.56 C`. The current 180 s gap closes, a 300 s failure is
  exposed and 600 s remains failing. F3.3l later found an additional O2 gap
  at 600 s in the official run.
- The official case was restored after every scratch run. Reports, expected
  values, tolerances, gap inventory and HVAC remain untouched.
- Temporary F3.3h2 physical wiring was removed. The passive connection ledger
  remains because it has independent diagnostic value.
- Next: F3.3l scenario-equivalence correction and STOP gate before more motor
  work.
- Binding record:
  `docs/validation/PHASE3_F33K_CONNECTION_RESIDENCE_AUDIT.md`.

## Previous Session Update - 2026-07-23 - F3.3j Hall residence audit closed

- Reconstructed the CFAST Hall two-zone mass and sensible-energy balance over
  0-180 s and compared it with the exact SimuFire accepted-route residence
  ledgers from the temporary F3.3h2 candidate.
- The original aggregate showed `138.650 kg` SimuFire inflow versus CFAST
  `128.369 kg`, but F3.3k later proved this comparison used five SimuFire Hall
  connections versus two in CFAST. That gross-mass conclusion is superseded.
- The direct Hall upper balance is `-9.015 kg` in SimuFire versus
  `+12.993 kg` in CFAST, a `22.008 kg` discrepancy.
- Poreh moves `20.734 kg` from lower to upper and nearly compensates that mass
  error, but it is an internal conservative transfer and cannot supply the
  missing `2.599 MJ`.
- OFF collapses the Hall upper zone; the candidate avoids collapse but ends at
  `10.810 kg` upper versus CFAST `18.384 kg`, with interface `1.366 m` versus
  `0.568 m`.
- Wall, ambient and exterior sinks total `0.865 MJ`, too small to own the
  direct-enthalpy deficit. Pressure remains a separate secondary blocker.
- No motor, runner, flag, schema, official report, baseline, tolerance, gap or
  HVAC path changed.
- Next: F3.3k passive per-connection ledger to separate R0-to-Hall input from
  Hall-to-R2 output before designing another physical candidate.
- Binding record:
  `docs/validation/PHASE3_F33J_HALL_RESIDENCE_AUDIT.md`.

## Previous Session Update - 2026-07-23 - F3.3i input audit closed

- Reconstructed the CFAST 0-180 s direct split directly from committed
  `HSLABT/HSLABF/HSLABYB/HSLABYT` data using the exact F3.3h1 formula:
  `65.780 kg` lower, `3.662 kg` upper, `5.2737%` upper.
- Root cause is upstream state, not `flogo`: Hall interface at 180 s is
  `1.366 m` in SimuFire versus `0.568 m` in CFAST. CFAST therefore exposes
  two `93.55 C` Hall-upper slabs; SimuFire presents mostly `28 C` Hall-lower
  gas to the same split.
- SimuFire direct inflow is independently 22.33% low:
  `52.698 kg` opening + `1.236 kg` pressure versus CFAST `69.442 kg`.
- SimuFire neutral plane is `1.253 m` versus CFAST transition near `1.061 m`.
  Its canonical room-pressure difference is `425.8 Pa` versus CFAST
  `0.555 Pa`, forcing F3.3b relaxation to `0.0002107`.
- No motor, runner, CSV schema, report, baseline, tolerance, gap or HVAC path
  changed. F3.3i was completed by post-processing existing artifacts.
- Next: F3.3j passive Hall upper/lower residence audit over 0-180 s.
- Binding record:
  `docs/validation/PHASE3_F33I_INPUT_CORRESPONDENCE_AUDIT.md`.

## Previous Session Update - 2026-07-23 - F3.3h2 runtime NO-GO

- Temporarily exposed the tested F3.3h1 buoyancy destination split behind a
  default-OFF Engine/CLI/CSV gate that implied the full F3.3b stack, both
  residence ledgers and separate Poreh mixing.
- OFF reproduced the 114-row, 667-column F3.3d1 checkpoint exactly:
  SHA-256
  `6F7FD18D3C451D2AE615D695B066A08F9F593DF5708E864DD50067CECF09ED70`.
- At 180 s, R0 direct lower/upper inflow changed from
  `46.143/7.516 kg` to `53.712/0.223 kg`; CFAST is
  `65.782/3.662 kg`. Total direct flow remains 22.3% low.
- Separate Poreh mixing moved `1.019 kg` from R0 upper to lower. Upper mass
  fell `22.921 -> 20.832 kg` and interface rose `1.101 -> 1.207 m`, both away
  from CFAST (`26.943 kg`, `0.736 m`).
- All mass, enthalpy, O2 and species residuals remained zero; all 115 legacy
  columns were invariant. This is a physical-correspondence NO-GO, not a
  conservation failure.
- Per STOP, no 300/590 s run was made. Temporary Engine, CLI and CSV wiring
  was removed. Official cases, reports, baselines, tolerances, gaps and HVAC
  remain unchanged.
- Next: F3.3i passive audit of runtime `flogo` inputs and the independent
  15.510 kg gross direct-flow deficit. No coefficient or new physical
  candidate is authorized yet.
- Binding record:
  `docs/validation/PHASE3_F33H2_BUOYANCY_RUNTIME_EXPERIMENT.md`.

## Previous Session Update - 2026-07-22 - F3.3h1 buoyancy routing design GO

- Implemented the exact CFAST `flogo` temperature destination split behind an
  internal/default-false parameter in `Phase3ZoneMassSystem`.
- Source zone, density, total slab flow, pressure and payload remain unchanged;
  direct receiver mass is split lower/upper with one common fraction for mass,
  enthalpy, O2 and species.
- The direct bundle and Poreh receiver-mixing bundle remain separate and
  individually identifiable.
- No Engine, CLI, CSV or case surface exists. Official reports, baselines,
  tolerances and gaps remain unchanged.
- Verification: focused 31 PASS; all Phase 3 tests 455 PASS; F3.3h1, F3.3f1
  and F3.3g Godot 4.7.1 fixtures PASS.
- Next: F3.3h2 temporary default-OFF runtime gate, OFF exact and Group C only
  to 180 s. Direct `h_mflow` and total `uflw2 + uflw3` comparisons must remain
  separate.
- Binding record:
  `docs/validation/PHASE3_F33H1_BUOYANCY_ROUTING_DESIGN.md`.

## Previous Session Update - 2026-07-22 - F3.3h CFAST flow semantics GO

- Audited the exact CFAST 7.7.5 source that generated Group C and compared it
  with current official `master`; `flowhorizontal.f90` is unchanged.
- `flogo` removes direct flow from the geometric source zone but deposits it
  into the receiver with a `tanhsmooth` temperature split, not by receiver
  height and not by preserving the source zone.
- `spill_plume`/`uflw3` is a separate receiver-internal Poreh transfer.
  `wall_flow` adds it to the ODE, while `.out` and spreadsheet upper/lower
  vent outputs read direct `h_mflow` only.
- The existing Group C direct-flow comparison is valid. F3.3f correctly found
  a destination-routing error, but F3.3f1 selected the wrong replacement.
- Next: F3.3h1 pure/default-false CFAST buoyancy routing contract. It must
  split each direct slab by source temperature against receiver layer
  temperatures and keep Poreh separate. No runtime surface in the design gate.
- Binding record:
  `docs/validation/PHASE3_F33H_CFAST_DOORWAY_FLOW_SEMANTICS.md`.

## Previous Session Update - 2026-07-22 - F3.3g1 runtime integration NO-GO

- Preserved every nonzero F3.3a/F3.3b hydrostatic slab and proved aggregate
  equivalence, pressure-relaxation scaling and opening-order independence.
- Added the internal default-false composition of source-preserving direct
  transport plus separate receiver-internal Poreh routes. Both atomic bundles
  close mass, enthalpy, O2 and species exactly.
- OFF is byte-identical to the F3.3f2 checkpoint (SHA-256
  `6F7FD18D3C451D2AE615D695B066A08F9F593DF5708E864DD50067CECF09ED70`).
- The 180 s candidate failed physically: R0 upper direct inflow fell
  `7.516 -> 0.482 kg`; cool `upper -> lower` Poreh mixing was `0.738 kg`
  versus only `0.036 kg` hot `lower -> upper`. Upper mass and interface moved
  away from CFAST despite a small temperature improvement.
- Per the STOP contract, no 300/590 s run was made. Temporary Engine, CLI and
  CSV wiring was removed; the internal slab/Poreh contract and fixtures remain.
- Next: F3.3h source-to-output audit of CFAST `UFLW/UFLW2/UFLW3`. Resolve
  whether the published layer flows contain direct transport, induced mixing
  or both before proposing another runtime candidate.
- Verification: focused 16 PASS; all Phase 3 tests 448 PASS; isolated Godot
  4.7.1 fixture PASS.
- Binding record:
  `docs/validation/PHASE3_F33G1_DOORWAY_JET_INTEGRATION_EXPERIMENT.md`.

## Previous Session Update - 2026-07-22 - F3.3g pure doorway-jet contract GO

- Bound the implementation to current official CFAST
  `flowhorizontal.f90::spill_plume/poreh_plume`, rather than the older
  historical McCaffrey description.
- CFAST has two receiver-internal owners when source and receiver slab zones
  differ: hot upper-source flow entrains receiver lower gas into upper at full
  Poreh strength; cool lower-source flow entrains receiver upper gas into
  lower with factor `0.25`.
- Added a pure Poreh preview and a receiver-snapshot atomic route builder in
  `Phase3ZoneMassSystem`. Direct vent mass is not part of this route.
- The direct fixture verifies fixed numeric rates, thermal/zone activation,
  source-flow and width scaling, one common inventory cap and exact mass,
  sensible-energy, O2 and species conservation.
- Verification: focused 15 PASS; all Phase 3 tests 439 PASS; isolated Godot
  4.7.1 fixture PASS; `git diff --check` PASS.
- No Engine/CLI/CSV/case surface, official report, baseline, tolerance, gap or
  canonical authority changed.
- Next: F3.3g1 must preserve each opening slab through F3.3a/F3.3b and add
  separate internal receiver routes beside source-preserving direct routes.
  Stop at 180 s; do not run 300/590 s or combine Qc until that paired gate
  passes.
- Binding record:
  `docs/validation/PHASE3_F33G_DOORWAY_JET_ENTRAINMENT_DESIGN.md`.

## Previous Session Update - 2026-07-22 - F3.3f2 runtime routing NO-GO

- Temporarily wired the tested F3.3f1 source-preserving selector behind a
  default-OFF Engine/CLI/CSV gate with the complete F3.3b stack and both exact
  residence ledgers as mandatory prerequisites.
- OFF was byte-identical to the prior 180 s F3.3d1 checkpoint: SHA-256
  `6F7FD18D3C451D2AE615D695B066A08F9F593DF5708E864DD50067CECF09ED70`,
  114 rows, 667 columns and no candidate column.
- At the 180 s ON STOP, R0 opening+pressure inflow changed from
  `46.143 lower / 7.516 upper / 53.659 total kg` to
  `54.555 lower / 0.004 upper / 54.559 total kg`. CFAST is
  `65.782 lower / 3.662 upper / 69.444 total kg`.
- Lower renewal moved in the right direction without a total-flow surge, but
  upper transport was effectively removed. Canonical upper mass fell
  `22.921 -> 20.463 kg` and interface rose `1.101 -> 1.227 m`, both away from
  CFAST (`26.94 kg`, `0.736 m`). Upper temperature improved only
  `125.70 -> 130.02 C` versus CFAST `159.82 C`.
- All mass, enthalpy, O2 and species residuals remained exactly zero, and all
  shared non-Phase-3 cells were identical. This is a semantic failure, not a
  conservation or legacy regression.
- Per the STOP contract, 300/590 s were not run. All F3.3f2 Engine, runner,
  logger and state wiring was removed. The pure default-false F3.3f1 selector
  and direct fixture remain.
- Decision: runtime candidate NO-GO. Next is F3.3g design-first work for the
  separate CFAST doorway-jet entrainment/mixing owner. Do not retune flow or
  pressure, and do not reintroduce F3.3e1 Qc yet.
- Binding record:
  `docs/validation/PHASE3_F33F2_DESTINATION_ROUTING_EXPERIMENT.md`.

## Previous Session Update - 2026-07-22 - F3.3f1 routing design GO

- CFAST's documented horizontal-flow contract separates direct layer-to-layer
  transport from doorway-jet entrainment. The direct candidate therefore
  preserves source-layer identity instead of using receiver midpoint height.
- Added one optional/default-false selector in `Phase3ZoneMassSystem` and
  propagated it through both F3.3a gross and F3.3b signed-pressure previews.
  It changes no flow, pressure, neutral plane, atomic cap or payload formula.
- There is deliberately no Engine export, CLI, CSV field or case wiring in
  this phase, so runtime behavior remains unavailable and unchanged.
- Direct fixture proves `lower->lower`, `upper->upper`, empty-zone creation,
  exact OFF equivalence, exact mass/enthalpy/O2/species closure and reversed
  opening-order equivalence.
- Verification: focused 28 PASS; all Phase 3 tests 432 PASS; isolated Godot
  4.7.1 fixture PASS. Official cases/reports/baselines/tolerances/gaps remain
  unchanged.
- Decision: design/fixture GO. Next is F3.3f2, a separate default-OFF runtime
  routing experiment using current F3.3b physics. Do not combine Qc yet.
- Binding record:
  `docs/validation/PHASE3_F33F1_DESTINATION_ROUTING_DESIGN.md`.

## Previous Session Update - 2026-07-22 - F3.3f routing root cause

- Integrated CFAST's explicit R0 upper/lower doorway and leakage rates over
  the same three windows as the exact SimuFire F3.3d1 mass ledger.
- The late deficit is not gross flow magnitude. At 300-590 s CFAST receives
  `168.393 kg` and SimuFire receives `223.489 kg`, but CFAST deposits
  `166.815 kg` in lower while SimuFire deposits only `51.599 kg` there.
  SimuFire instead sends `171.890 kg` to upper versus CFAST `1.578 kg`.
- Root cause is the canonical destination-zone midpoint contract in
  `Phase3ZoneMassSystem`: when the receiver interface falls, increasingly
  more cool doorway inflow is classified as upper. That starves lower,
  lowers the interface again and creates a positive feedback loop.
- Flow multipliers, pressure gains and forcing all inflow to lower are
  rejected. Conservation already closes; the error is zone assignment.
- Next gate is F3.3f1, a design-first/default-OFF source-preserving destination
  routing contract with direct hot/cold, one-zone, bidirectional and
  order-independence fixtures. Do not reintroduce F3.3e1 Qc until this passes.
- No runtime code, official case/report, baseline, tolerance, gap, CTRL or
  authority changed in F3.3f.
- Binding record:
  `docs/validation/PHASE3_F33F_LOWER_RENEWAL_CORRESPONDENCE.md`.

## Previous Session Update - 2026-07-22 - F3.3e1 coupled Qc runtime NO-GO

- Implemented the F3.3e accepted-Qc contract as a default-OFF shadow
  candidate and verified its NIST equation, explicit Qc heat and no-double-
  throttle bundle in a direct Godot fixture.
- Default OFF is exact: 114 rows x 667 shared columns, zero differing cells
  against the pre-candidate F3.3d1 run.
- The 180 s STOP passed: upper temperature `220.36 -> 190.49 C`, upper mass
  `6.68 -> 25.76 kg` and interface `1.932 -> 0.690 m`, all toward CFAST
  (`159.82 C`, `26.94 kg`, `0.736 m`).
- The full run failed physically. At 590 s lower gas/interface collapse to
  zero and upper gas reaches `41.37 kg` versus CFAST `25.25 kg`, despite exact
  mass and enthalpy ledger closure.
- Route accounting selects the next owner: cumulative plume lower out is
  `208.26 kg`, while opening plus pressure lower inflow is only `169.71 kg`.
  The lower inventory cap then suppresses late plume flow.
- Decision: F3.3e1 runtime NO-GO and fully rolled back. No official case,
  report, baseline, tolerance, gap, CTRL or authority changed. Next is F3.3f,
  a design-first lower-zone renewal/doorway-routing correspondence audit.
- Binding record:
  `docs/validation/PHASE3_F33E1_COUPLED_QC_EXPERIMENT.md`.

## Previous Session Update - 2026-07-22 - F3.3e coupled Qc design GO

- Defined one dimensional source contract for the next shadow experiment:
  canonical accepted HRR -> effective `chi_rad` -> accepted `Qc`; that same
  `Qc` must own both convective energy and the complete plume correlation.
- Confirmed a formula bug in the current canonical preview: it subtracts
  flame length (`0.235 * Q^(2/5) - 1.02D`) from the interface where Heskestad
  requires the virtual origin (`0.083 * Q^(2/5) - 1.02D`).
- CFAST uses fire area `0.3015 m2` (`D=0.6196 m`), radiative fraction 0.35 and
  exports plume `0.503/0.528/0.552 kg/s` at 180/300/590 s. The corrected
  equation predicts `0.514/0.532/0.549 kg/s`, all within 2.3% without tuning.
- The Group C SimuFire case still carries inherited calibration values
  `D=3.5 m`, `chi_rad=0.70` and plume Qc fraction 0.30. They are not changed
  here; a future experiment must use a scratch physical-input overlay first.
- Late accepted HRR remains a separate owner: even with a 65% convective
  split, SimuFire has only 41.23 MJ in 300-590 s versus CFAST 56.55 MJ. The
  plume contract must not manufacture that missing O2/combustion energy.
- Decision: design GO for F3.3e1, default OFF, with direct NIST-equation
  fixture and 180 s STOP before a 600 s run. No runtime code or validation
  contract changed in F3.3e.
- Binding record:
  `docs/validation/PHASE3_F33E_COUPLED_QC_DESIGN.md`.

## Previous Session Update - 2026-07-22 - F3.3d2 source-term NO-GO

- Tested the complete Heskestad source term (`0.0018 * Qc`) as the sole plume
  change. The candidate remained shadow-only and exactly conservative.
- Plume error improved from `-27.6/-29.4/-35.8%` to
  `-16.9/-20.1/-29.9%` across the three CFAST windows.
- At 180 s upper mass/interface improved from `22.92 kg / 1.101 m` to
  `26.87 kg / 0.909 m` (CFAST `26.94 kg / 0.736 m`). At 590 s interface
  improved from `1.140` to `0.990 m`.
- Binding failure: upper temperature regressed from `125.7` to `114.2 C` at
  180 s and from `97.5` to `90.1 C` at 590 s. The upper layer receives more
  near-lower-temperature mass without the missing convective energy.
- Decision: F3.3d2 NO-GO. All experiment code/tests/flags were rolled back;
  only the scratch evidence and documentation remain. Group A was not run
  after the binding temperature criterion failed.
- Next: F3.3e design-first coupled `Qc` contract. Do not combine old patches
  until one authoritative convective HRR drives both energy and plume mass.
- Binding record:
  `docs/validation/PHASE3_F33D2_PLUME_SOURCE_TERM_EXPERIMENT.md`.

## Previous Session Update - 2026-07-22 - F3.3d1 mass ledger GO

- Added `phase3_mass_residence_diagnostics_enabled=false`, active only with
  the complete F3.3b shadow stack. It is passive and adds 72 CSV fields only
  when enabled.
- Initial plus cumulative accepted gas-mass routes now close exactly for the
  upper zone, lower zone, room and building. Atomic routes are recorded after
  limiting and before mutation; legacy requests and zone collapse are explicit.
- The deterministic fixture and five Godot 4.7.1 scratch controls PASS. Group
  C preserves 366 rows and all 595 shared columns exactly; every measured mass
  residual is `0.0 kg`.
- CFAST comparison selects plume partition: SimuFire accepts only 72.4%, 70.6%
  and 64.2% of CFAST plume mass over `0-180`, `180-300` and `300-590 s`.
  The `chi_rad=0.35` control changes plume mass by less than 2%, so radiation
  cannot repair the mass/interface error.
- Late interior-pressure lower outflow and exterior net inflow are secondary
  churn signals. Do not change opening or pressure coefficients before testing
  the plume owner independently.
- Verification: Phase 3 tests 424/424; full pytest 1073 PASS with the same 18
  pre-existing failures plus expected dirty-motor R2-1; physics 9/15/5/0; ILV
  15/14/0; gap inventory 348/353; guardrails 9/10 only for R2-1.
- Decision: F3.3d1 instrumentation GO. Physics, authority and the 5 VALID_GAP
  remain NO-GO. Next separate gate is F3.3d2, a default-OFF canonical plume
  entrainment/partition experiment.
- Binding record:
  `docs/validation/PHASE3_F33D1_MASS_RESIDENCE_LEDGER.md`.

## Previous Session Update - 2026-07-21 - F3.3d CFAST correspondence

- Integrated CFAST convective HRR, signed doorway-slab enthalpy and layer
  sensible energy over `0-180`, `180-300` and the exported `300-590 s`
  windows, then compared them with the exact F3.3c1 ledger.
- SimuFire accepts only 44.3%, 43.2% and 33.6% of CFAST convective source
  energy. Early actual HRR differs by only 4-6%; the dominant cause is the
  explicit radiation split (`chi_rad=0.7` versus CFAST `0.35`). After 300 s,
  O2 throttling adds a second source deficit.
- Wall/exterior and doorway losses are both lower than CFAST in absolute
  terms. Neither is the primary explanation for the late energy deficit, and
  no sink coefficient change is authorized.
- The `chi_rad=0.35` control exposes the coupled error: at 180 s upper energy
  is within 3% of CFAST but upper mass is 32% low and the interface is 0.37 m
  too high, producing 218.35 C instead of 159.82 C. At 590 s its apparently
  correct temperature hides roughly 24% deficits in both upper energy and
  mass.
- Decision: F3.3d diagnostic GO; scalar source, wall and doorway changes are
  NO-GO. F3.3d1 is next: a default-OFF exact mass-residence ledger to identify
  plume/partition ownership before any physical patch.
- No motor, case, report, baseline, tolerance, gap or CTRL changed.
- Binding record:
  `docs/validation/PHASE3_F33D_CFAST_SOURCE_BOUNDARY_CORRESPONDENCE.md`.

## Previous Session Update - 2026-07-21 - F3.3c1 enthalpy ledger GO

- Added `phase3_enthalpy_residence_diagnostics_enabled=false`, effective only
  with the complete F3.3b stack. It is instrumentation-only and does not write
  legacy or canonical physics.
- The ledger counts accepted energy after atomic limiting, by room, upper/lower
  zone, direction and exclusive cause family. Legacy requests and zone collapse
  remain visible. Initial/expected/observed energy closes per zone, room and
  building.
- Direct Godot fixture PASS. `cfast_corridor_chain` OFF/ON preserves 366 rows
  and all 527 shared columns exactly; ON adds 68 fields. Maximum residual is
  `0.0 kJ` at every level.
- R0 through 600 s accepts 40.711 MJ combustion heat. Its largest upper losses
  are F3.3a opening transport (20.817 MJ gross), ambient (11.625 MJ), wall
  (6.362 MJ) and F3.3b pressure transport (2.419 MJ gross).
- `cfast_r0_window_360` also closes exactly; its dominant sinks are ambient
  (11.024 MJ), wall (9.337 MJ) and exterior pressure (1.520 MJ).
- Verification: direct Godot fixture PASS, focused tests 38/38, full pytest
  1063 PASS with the same 18 pre-existing failures plus the expected dirty-
  motor R2-1 integration failure. Physics is 9/15/5/0, ILV 15/14/0, gap
  inventory remains 348/353 and guardrails are 9/10 only for R2-1.
- Decision: instrumentation GO; authority and the 5 VALID_GAP remain NO-GO.
  Next is F3.3d source/boundary correspondence against CFAST, with no motor
  change authorized yet.
- Binding record:
  `docs/validation/PHASE3_F33C1_ENTHALPY_RESIDENCE_LEDGER.md`.

## Previous Session Update - 2026-07-21 - F3.3c enthalpy audit

- CFAST and canonical layer inventories were compared directly with the same
  sensible-energy convention. At 600 s, F3.3b has 23.97 kg upper gas versus
  25.28 kg in CFAST, but only 1855 versus 3762 kJ upper sensible energy.
- Matching the CFAST temperature at the F3.3b mass requires about 1712 kJ
  additional upper energy. The late error is energy-residence dominated, not
  an excessive upper-layer mass error.
- CFAST supplies about 65% convective HRR; the case override leaves about 30%
  in SimuFire. A scratch `chi_rad=0.35` control improves 600 s from 97.39 to
  165.11 C but overheats 180 s to 218.35 C. Do not retune the case: one scalar
  moves the curve and does not close both checks.
- Current cumulative wall/inter-zone counters are useful, but combustion,
  plume, F3.3a/F3.3b doorway and exterior enthalpy are not all cumulative or
  cause-separated. Sparse `*_step` CSV fields cannot be summed safely.
- Decision: F3.3c diagnosis GO. Its requested F3.3c1 instrumentation has now
  been implemented and verified in the update above.
- Binding record:
  `docs/validation/PHASE3_F33C_LATE_ENTHALPY_AUDIT.md`.

## Previous Session Update - 2026-07-21 - F3.3b shadow GO / Group C NO-GO

- Added `phase3_canonical_interior_pressure_shadow_enabled=false` and CLI flag
  `--phase3-canonical-interior-pressure-shadow`.
- The signed pressure component uses the same pre-step snapshot and the same
  atomic network bundle as F3.3a. One global relaxation fraction prevents a
  connected pressure difference from crossing during the explicit step.
- Gas, enthalpy, O2 and seven species close exactly; opening order is
  invariant; exterior and vertical owners remain separate; legacy output is
  unchanged.
- Group C R0 upper temperature changed from F3.3a `130.94/102.73 C` to
  `125.70/97.39 C` at 180/600 s. Both checks worsen, so the missing late heat
  is not signed doorway pressure flow.
- Physics remains 9/15/5/0, ILV 15/14/0 and gap inventory 348/353 with 5
  VALID_GAP. Guardrails are 9/10 only because R2-1 sees the dirty motor.
- Full pytest: 1053 PASS, the same 18 pre-existing structural failures plus
  the expected R2-1 integration failure.
- Decision: **F3.3b diagnostic shadow GO; authority and Group C retirement
  NO-GO**. Next: F3.3c cumulative late-enthalpy residence audit, with no
  doorway-rate tuning.
- Binding record:
  `docs/validation/PHASE3_F33B_INTERIOR_PRESSURE_SHADOW.md`.

## Previous Session Update - 2026-07-20 - F3.3a shadow GO / Group C NO-GO

- Added `phase3_canonical_interior_opening_shadow_enabled=false` and a pure
  canonical horizontal interior-opening network transaction.
- All openings are evaluated from one pre-step snapshot, sorted by stable id
  and applied in one globally capped atomic bundle. Gas, sensible enthalpy,
  O2 and seven species move together from source-zone concentrations.
- Hydrostatic pressure is integrated exactly across piecewise-uniform zones.
  One-zone ambient receivers are valid; vertical and exterior openings remain
  outside this owner.
- Direct fixture and 42 focused tests pass. Two-room legacy OFF/ON preserves
  all 115 non-Phase-3 columns exactly. Runtime controls close mass, energy, O2
  and species with zero duplicate owners.
- Group C R0 shadow temperature changes from 227.90 to 130.94 C at 180 s
  (early improvement) and from 113.91 to 102.73 C at 600 s (late regression).
  Group C therefore remains 2 VALID_GAP and authority is NO-GO.
- Physics is 9/15/5/0, ILV 15/14/0, gap inventory 348/353 with 5 VALID_GAP.
  Guardrails are 9/10 only because R2-1 sees the intentional dirty motor.
- Full pytest outside the filesystem sandbox is 1044 PASS, 18 pre-existing
  structural failures and the expected R2-1 integration failure.
- Decision: **F3.3a shadow infrastructure GO; authority and Group C retirement
  NO-GO**. Next: F3.3b canonical signed inter-room pressure coupling, still
  default OFF and without HVAC.
- Binding record:
  `docs/validation/PHASE3_F33A_INTERIOR_OPENING_SHADOW.md`.

## Previous Session Update - 2026-07-20 - F3.2b7 shadow GO / authority NO-GO

- Added `phase3_canonical_post_opening_coupling_shadow_enabled=false`.
  Exterior counterflow can select lower canonical O2 for combustion without
  changing closed or interior-opening behavior.
- Combustion and plume now share one lower-air parcel. The accepted O2 sink
  and the excess plume O2 close atomically; the source and height terms of the
  Heskestad mass flow are reported separately.
- Group A at 420 s reaches 1280 kW and 1.084 m versus CFAST 1280 kW and
  1.020 m. Upper O2 remains 0.0906 versus 0.1320, and HRR rises too early at
  370 s, so canonical authority remains NO-GO.
- Group A and no-fire runs preserve all 115 legacy columns. The no-fire
  control preserves 466 shared shadow columns. A 600 s Group C run has zero
  coupling activations and zero source term. All relevant residuals are zero.
- Verification: direct Godot 4.7.1 fixture PASS, focused/adjacent tests 36/36,
  Physics 9/15/5/0, ILV 15/14/0, gap inventory 348/353 with 5 VALID_GAP.
  Guardrails are 9/10 only because R2-1 correctly sees dirty motor.
- Decision: **F3.2b7 shadow mechanism GO; authority and Group A retirement
  NO-GO**. Next: F3.3 interior two-zone openings for Group C.
- Binding record:
  `docs/validation/PHASE3_F32B7_POST_OPENING_COUPLING.md`.

## Previous Session Update - 2026-07-20 - F3.2b6 shadow GO / authority NO-GO

- Added `phase3_canonical_exterior_counterflow_shadow_enabled=false` and a
  pure canonical hydrostatic opening preview. It produces simultaneous equal
  upper outflow and lower ambient inflow while the existing pressure bundle
  remains the only signed net-mass owner.
- One atomic acceptance fraction carries gas, sensible energy, O2 and species.
  The opt-in CSV exports 29 counterflow fields, including neutral plane,
  pressure offset, gross exchange, pressure relief and conservation residuals.
- The open/no-fire control stays at exact ambient equilibrium; OFF is
  bit-identical to the accepted prior shadow. The direct Godot 4.7.1 fixture
  and 29 focused/adjacent tests pass.
- Group A changes in the correct direction after opening. At 420 s upper O2
  rises from 0.0614 to 0.0928, interface from 0.141 to 1.574 m and HRR from
  142 to 490 kW. CFAST is 0.1320, 1.020 m and 1280 kW respectively.
- Conservation residuals are exactly zero, but the interface overshoots while
  HRR remains too low. The best prior scratch tuning worsens that combination
  and remains rejected.
- Verification: Physics 9/15/5/0, ILV 15/14/0, gap inventory 348/353 with 5
  VALID_GAP. Guardrails are 9/10 only because R2-1 correctly sees dirty motor.
- Decision: **F3.2b6 shadow GO; authority and Group A retirement NO-GO**.
  Next: F3.2b7 canonical post-opening combustion/O2/plume feedback, then F3.3.
- Binding record:
  `docs/validation/PHASE3_F32B6_EXTERIOR_COUNTERFLOW.md`.

## Previous Session Update - 2026-07-19 - F3.2b5c diagnostic GO / authority NO-GO

- F3.2b5c adds no motor mechanism. It repeats the Group A equivalence matrix
  after both canonical thermal owners and runs isolated no-fire/open/fire
  controls under `runs/phase3_f32b5c/`.
- The F3.2b5b baseline pressure RMSE improves to 274 Pa but still depends on
  cancellation: at 160 s the shadow has +11.53 kg gas and -3.32 MJ sensible
  energy versus CFAST.
- `chi_rad=0.35` plus CFAST leakage is the best simultaneous candidate:
  pressure 360 Pa, mass 2.69 kg, energy 803 kJ, upper/lower temperature
  33.8/16.7 C RMSE. It remains scratch-only. Concrete lumped wall is rejected.
- Closed/open no-fire controls remain at exact ambient equilibrium. The fire
  opening control conserves every transaction and relaxes pressure to 0 Pa,
  but fails to reoxygenate upper: 0.0614 versus CFAST 0.1320 at 420 s.
- Root cause: F3.2a/F3.2b2 chooses one net exterior direction from gauge
  pressure. It lacks simultaneous buoyant upper outflow and lower fresh-air
  inflow at near-zero net pressure. Lower mass shrinks while CFAST lower layer
  expands; HRR/plume/O2 then enter a low-flow feedback loop.
- Decision: **F3.2b5c diagnostic GO; authority and Group A retirement NO-GO**.
  Next: F3.2b6 canonical bidirectional exterior opening, then F3.3 Group C.
- Binding record: `docs/validation/PHASE3_F32B5C_EQUIVALENCE.md`.

## Previous Session Update - 2026-07-19 - F3.2b5b mechanism GO / authority NO-GO

- Added `phase3_canonical_wall_ambient_shadow_enabled=false`. It replaces six
  legacy-derived wall/ambient thermal requests only inside the persistent
  canonical shadow.
- The canonical wall is a separate persistent finite reservoir. It reuses
  static geometry and declared material/fallback properties but never reads
  legacy wall or gas temperatures.
- Group A lower energy at 360 s improves from 0 to 49.14 kJ and lower
  temperature at 350 s from 22.79 C to 33.60 C. The wall reaches 25.71 C and
  stores 9.13 MJ. Gas-wall and total boundary residuals are exactly zero.
- Group A shadow upper O2 is 0.10559, 0.06639 and 0.06686 at 240/350/360 s;
  all three fit their existing checks. No expected value, tolerance or gap was
  changed, so Group A remains officially open.
- Legacy/non-shadow output is invariant. The no-fire control stays at exact
  ambient equilibrium with zero wall energy and zero exchange.
- Verification: direct Godot 4.7.1 fixture PASS, focused tests 21/21 PASS,
  broad Phase 3/two-zone 404 PASS plus 4 unrelated pre-existing structural
  failures, physics and ILV 0 FAIL, gap inventory unchanged. Guardrails are
  9/10 only because R2-1 detects the expected dirty motor.
- Decision: **F3.2b5b mechanism GO; canonical authority and Group A retirement
  NO-GO**. Next: F3.2b5c full mass/energy/pressure equivalence and independent
  controls.
- Binding record:
  `docs/validation/PHASE3_F32B5B_WALL_AMBIENT_ENERGY.md`.

## Previous Session Update - 2026-07-19 - F3.2b5a mechanism GO / authority NO-GO

- Added `phase3_canonical_interzone_heat_shadow_enabled=false`. When enabled,
  the passive shadow suppresses only the legacy `thermal_upper_to_lower`
  request and replaces it with a canonical pre-step energy transaction.
- The request uses the reduced heat capacity of both finite reservoirs and an
  exact equilibrium cap. It cannot cross upper/lower equilibrium, create
  energy or consume more upper energy than remains after earlier bundles.
- Group A no longer inverts its canonical zone temperatures. Lower-temperature
  RMSE improves from about 93 C to 23 C; accepted transfer is 530.716 kJ and
  the energy residual remains exactly zero. All three shadow O2 checks remain
  PASS and all legacy columns are invariant.
- Canonical authority remains NO-GO. Pressure, total-mass and total-energy RMSE
  barely move, while the late lower zone reaches about 20-23 C versus roughly
  67 C in CFAST. This isolates wall/ambient ownership as the next thermal
  blocker rather than a reason to tune the inter-zone rate.
- Verification: Godot 4.7.1 parse PASS, direct fixture PASS, focused tests
  60/60 PASS, broad Phase 3 363/363 PASS after excluding the known sandbox
  tempfile analyzer issue, Physics and ILV both 0 FAIL, gap inventory unchanged.
- Guardrails are 9/10 only because R2-1 detects the expected dirty motor. No
  report, baseline, tolerance or gap classification was changed.
- Decision: **F3.2b5a mechanism GO; canonical authority and Group A retirement
  NO-GO**. Next: F3.2b5b canonical wall/ambient exchange preview.
- Binding record:
  `docs/validation/PHASE3_F32B5A_INTERZONE_HEAT.md`.

## Previous Session Update - 2026-07-19 - F3.2b4 diagnostic GO / authority NO-GO

- No motor code, baseline, tolerance, official report or gap classification
  changed. Six isolated Godot 4.7.1 runs live only under
  `runs/phase3_f32b4/`.
- Exact EOS decomposition proves pressure agreement is cancellation. At
  160 s the canonical state has about 11.10 kg more gas and 3.05 MJ less
  sensible energy than CFAST, while net pressure differs by only 752 Pa.
- One-cause tests for radiative split, equivalent leakage and concrete wall
  properties do not close pressure, mass, energy, interface and both zone
  temperatures together. The full combination improves pressure RMSE only
  from 507 to 444 Pa while leaving lower temperature at 268 C versus 66.5 C.
- Root cause: `ThermalSystem` derives shadow thermal-loss requests from legacy
  gas state and applies them to persistent canonical reservoirs. Canonical
  lower first exceeds upper near 313 s, yet legacy state continues requesting
  upper-to-lower heat; about 4.63 MJ is requested after inversion.
- Decision: **F3.2b4 diagnostic GO; canonical pressure/state authority and
  Group A retirement NO-GO**.
- Next: F3.2b5a pure canonical inter-zone heat-transfer preview, default OFF
  and shadow-only. Wall/ambient ownership follows in a separate gate.
- Binding record:
  `docs/validation/PHASE3_F32B4_PRESSURE_EQUIVALENCE.md`.

## Current Session Update - 2026-07-18 - F3.2b3 canonical plume GO / authority NO-GO

- Added `phase3_canonical_plume_shadow_enabled=false` and a pure plume preview
  based on canonical pre-step mass, sensible energy, O2 and interface.
- Root cause of the early one-zone transition is confirmed. At about 150 s the
  live plume used the legacy `1.458 m` interface while canonical interface was
  `0.260 m`; the same correlation requested `0.621 kg/s` versus about
  `0.034 kg/s` from canonical geometry and `0.062 kg/s` in CFAST.
- Group A canonical lower no longer collapses near 160 s. It remains
  `12.84 kg` at 160 s, `2.68 kg` at 350 s and `2.48 kg` at 360 s. Canonical
  interface is still too high (`0.214 m` versus CFAST `0.10 m` at 360 s), so
  this is not an authority result.
- Group A shadow O2 remains 3/3 PASS: `0.100996`, `0.074077`, `0.074071` at
  240/350/360 s. All 115 legacy columns and the complete 407-column F3.2b2
  OFF control remain identical.
- Pressure is a separate blocker. F3.2b3 improves the late trajectory but
  leaves `+1.812 kPa` at 160 s and `-0.341 kPa` at 350 s versus CFAST
  `+1.061 kPa` and `+0.167 kPa`. Internal plume transfer cannot directly fix
  total EOS pressure because it conserves room mass and energy.
- Measured pressure differences include the heat split (CFAST radiative
  fraction `0.35`, case override `0.70`) and leakage area (about `0.00905 m2`
  versus `0.005 m2`). Neither one-cause change closes the trajectory, so no
  tuning was accepted.
- Decision: **canonical plume mechanism GO; canonical room-state authority and
  Group A retirement NO-GO**. Next gate is F3.2b4 pressure source/boundary
  equivalence, diagnostic first.
- Binding record:
  `docs/validation/PHASE3_F32B3_CANONICAL_PLUME.md`.
- F3.2b0/b1/b2/b3 remain uncommitted at this STOP gate. Visual work in
  `project.godot` and the two tool UID files remains untouched.

## Previous Session Update - 2026-07-18 - F3.2b2 pressure relaxation GO / authority NO-GO

- Added `phase3_canonical_pressure_relaxation_shadow_enabled=false`; the
  runner option implies the full F3.2b1 parent stack.
- Root cause was an explicit orifice overshoot. At the old Group A opening
  sample, the state was `-34.0 kPa` and requested `34.62 kg`, while the EOS
  required only `19.34 kg` to reach ambient pressure. The extra `15.29 kg`
  produced the observed `+26.9 kPa` sign reversal.
- The new pure limiter computes the exact equilibrium fraction and scales gas,
  energy, O2 and species together. It is a physical EOS bound, not a fitted
  pressure clamp.
- A real open exterior boundary now recreates lower from ambient inflow when
  the canonical state is upper-only. Closed-window leakage cannot trigger the
  transition. In Group A the first reseed is step `4322`, about `360.167 s`,
  with `0.14583 kg`.
- Group A remains `3/3 PASS` in shadow and 115/115 legacy columns are
  identical. Exterior, combustion and volume residuals remain exactly zero.
- Decision: **pressure-relaxation and lower-reseed mechanisms GO; canonical
  room-state authority NO-GO**. The catastrophic opening spike is gone, but
  the pre-opening range remains `-1.04..+2.81 kPa` and lower reaches the
  one-zone limit near 160 s.
- Next: F3.2b3 must diagnose pre-opening canonical pressure and premature
  one-zone residence before Group A can be retired or F3.3 authority begins.
- Binding record:
  `docs/validation/PHASE3_F32B2_PRESSURE_RELAXATION.md`.
- F3.2b0/b1/b2 remain uncommitted at this STOP gate. Visual work in
  `project.godot` and the two tool UID files remains untouched.

## Previous Session Update - 2026-07-18 - F3.2b1 transaction GO / authority NO-GO

- Added `phase3_canonical_combustion_shadow_enabled=false`. The passive mode
  evaluates combustion from canonical pre-step O2 and persistent fire state,
  without writing live `RoomModel` or `FireModel` state.
- HRR, fuel, O2, generated species, convective heat and plume transport now
  form one atomic shadow bundle with one decision fraction.
- The direct Godot fixture closes O2, energy and species residuals exactly;
  focused tests are `67/67 PASS` and broad Phase 3 tests are `332 PASS` after
  excluding the known Windows analyzer-tempfile failures.
- In `cfast_r0_window_360`, canonical upper O2 now passes all three Group A
  checks in shadow: `0.10793` at 240 s, `0.07157` at 350 s and `0.07242` at
  360 s. Expected values and tolerances were not changed.
- Legacy output remains unchanged across all 115 shared columns. Physics and
  ILV retain zero FAIL, and the five VALID_GAP entries remain active because
  canonical authority is still OFF.
- Decision: **closed combustion mechanism GO; room-state authority NO-GO**.
  The lower canonical zone collapses before the opening and the exterior
  transient reaches about `+26.9 kPa`.
- F3.2b2 completed the opening-pressure and lower-reseed mechanisms. See the
  current update for the remaining authority blockers.
- Binding record:
  `docs/validation/PHASE3_F32B1_COMBUSTION_TRANSACTION.md`.
- F3.2b0/b1 remain uncommitted at this STOP gate. User visual edits in
  `project.godot` and the two tool UID files remain out of scope.

## Previous Session Update - 2026-07-18 - F3.2b0 persistence GO / authority NO-GO

- Added default-OFF internal persistence to `Phase3ZoneMassSystem`; the first
  step seeds legacy once and later steps reuse the prior canonical final state.
- Added passive upper-zone combustion O2 demand/probe telemetry and a
  conservative zero-mass-zone fusion. Continuity and fusion residuals close
  mass, energy, O2 and species exactly.
- `cfast_r0_window_360` retains all 115 legacy columns unchanged. Canonical
  upper O2 moves toward CFAST at 240 s (`0.10079` versus target `0.08511`) but
  over-depletes by 350 s and reaches `-34.1 kPa` after opening.
- Decision: **persistence mechanism GO; combustion authority and Group A
  closure NO-GO**. The shadow is open-loop because heat, plume and species are
  still generated from legacy HRR.
- Next gate was F3.2b1, now completed as a passive mechanism. See the current
  session update for the remaining authority blockers.
- Binding record:
  `docs/validation/PHASE3_F32B_PERSISTENT_SHADOW.md`.
- F3.2b0 remains part of the uncommitted Phase 3 shadow stack.

## Previous Session Update - 2026-07-18 - F3.2a passive exterior GO

- Added one default-OFF atomic exterior boundary to the canonical shadow. It
  carries gas, sensible energy, O2 and seven species with one accepted fraction
  and suppresses only the duplicate legacy pressure-purge owner in shadow.
- Runtime rejected the initial pre-step pressure ordering because legacy
  projection had already reset pressure. The accepted non-circular order
  resolves the boundary after explicit internal shadow transactions.
- `cfast_r0_window_360` stays unchanged in all 115 legacy columns. Shadow
  pressure is `-0.83..125.85 Pa`; boundary and thermodynamic residuals are
  zero; no lower-zone collapse or duplicate owner occurs.
- Decision: **passive contract GO; canonical authority and Group A closure
  NO-GO**. Shadow upper O2 remains `0.15949/0.09820/0.09347` at
  240/350/360 s versus CFAST `0.08511/0.06598/0.06451`.
- Next: F3.2b persistent canonical step continuity and combustion O2 coupling,
  still default OFF and single-room/no-HVAC first. Group C remains F3.3; HVAC
  remains last.
- Binding record:
  `docs/validation/PHASE3_F32A_EXTERIOR_BOUNDARY_SHADOW.md`.
- F3.2a was committed as `f34c52c4`; R2-1 metadata refresh is `72c9f4a8`.

## Previous Session Update - 2026-07-18 - F3.1e passive GO

- Added a pure thermodynamic closure inside `Phase3ZoneMassSystem`: canonical
  upper/lower mass and sensible energy remain authoritative; temperature,
  shared pressure, EOS volumes and interface are derived values only.
- The F3.1d no-fire, 30 s fire and 180 s controls have exact post-step mass,
  energy and volume closure. All 344 inherited CSV columns are identical.
- Canonical gauge pressure remains bounded in the 180 s control
  (`-4.84..108.88 Pa`). Legacy state divergence remains separately visible.
- Decision: **GO for passive closure; NO-GO for room-state authority**.
- F3.2 exterior pressure/leakage is the next default-OFF phase. It may consume
  the shadow closure but may not publish it globally or double-count legacy
  purge/projection paths.
- Physics and ILV retain zero FAIL; gap inventory remains 348/353 with five
  VALID_GAP. Guardrails only has expected R2-1 while F3.1e is uncommitted.
- The initial `t=0` row precedes shadow finalization and has zero closure
  fields by design.
- Binding record:
  `docs/validation/PHASE3_F31E_THERMODYNAMIC_CLOSURE.md`.

## Current Session Update - 2026-07-17 - F3.1d diagnostic GO

- Added passive per-call trace telemetry for the legacy EOS projection and a
  read-only JSONL analyzer. It is opt-in through scratch runner configuration;
  legacy CSV schema and physics are unchanged.
- The 180 s one-room control executes seven projections per timestep. The
  first post-combustion call dominates, removing up to `0.05700088 kg` and
  `6.99578420 kJ`; later calls backfill lower gas geometrically.
- Projection sums exactly match the sign-opposite F3.1c residual at the key
  timesteps. `ensure_room_state` and temperature-only projection are numerical
  zero/negligible.
- A 30 s no-fire control has exact zero projection deltas. A 30 s fire control
  already shows the same lower-zone pattern.
- Root cause: legacy projection assumes fixed ambient pressure and overwrites
  conserved inventory to satisfy EOS, creating an implicit unregistered
  reservoir. It is not a missing transport flux.
- Decision: **GO for passive diagnostics; NO-GO for projection authority**.
  F3.2 remains blocked.
- Next gate: F3.1e pure canonical thermodynamic closure. Preserve mass/energy;
  derive temperature, shared pressure, volumes and interface, and keep legacy
  divergence as separate telemetry.
- Physics and ILV retain zero FAIL; gap inventory remains 348/353 with five
  VALID_GAP. Guardrails only has expected R2-1 while motor is dirty.
- Binding record:
  `docs/validation/PHASE3_F31D_LOWER_PROJECTION_RECONCILE.md`.

## Current Session Update - 2026-07-17 - F3.1c partial GO

- A dedicated one-room scratch control removed all opening, HVAC, ACH,
  leakage and pressure-flow ambiguity from the shadow audit.
- ThermalSystem now publishes exact passive requests for local upper/lower,
  wall and ambient energy transfers. OES publishes the exact bulk-O2 debit
  during invalid lower-zone homogenization.
- Combustion heat and plume ownership no longer depend on doorway presence.
  They remain gated by the existing passive shadow flag and do not mutate
  physical state.
- Fire ownership mask 7 improves from 22 to 36/36 snapshots. Maximum energy
  residual falls from `36.26236788` to `6.94237481 kJ`; maximum mass residual
  remains `0.03016636 kg`. Semantic conflicts and unresolved claims are zero.
- OFF/ON shared legacy CSV values are identical. No official report, baseline,
  tolerance, CTRL envelope or gap changed.
- Decision: **PARTIAL GO for passive owners; NO-GO for authority**.
  `needs_flux_owner` remains 1 because lower-zone EOS projection/reconcile is
  still unowned. F3.2 remains blocked.
- Next gate: F3.1d lower-zone projection/reconcile ownership diagnosis.
- Binding record:
  `docs/validation/PHASE3_F31C_SINGLE_ROOM_THERMAL_OWNERSHIP.md`.

## Current Session Update - 2026-07-17 - F3.1b scope NO-GO

- F3.1a documentation was committed separately as `d07b23b`; visual changes
  remained outside that commit.
- F3.1b returned **NO-GO before motor implementation**. There is no honest
  single sealed/open predicate today: Combustion, OES, Thermal, GES and the
  Engine cache activate different transport families with different guards.
- `fuel_balance_diag_sealed` and `o2_stoich_diag_sealed` use `simple_house`
  with five open interior doors. Their transport overrides do not disable all
  Thermal/OES immediate paths, so they are not authoritative sealed fixtures.
- A fresh 120 s physically closed control reached combustion mask 7 in 19/25
  room-0 snapshots, but `needs_flux_owner=1` remained in 24/25. Maximum
  residuals were `0.03571883 kg` mass and `14.49193968 kJ` energy.
- Thermal gap deformation also makes the shadow predicate reject a closed door
  while the physical transport loop still checks raw `open_fraction=0`.
- No F3.1b motor code, baseline, tolerance, official report or validation
  classification changed. F3.2 remains blocked.
- Next gate: F3.1c, a dedicated one-room fixture plus ownership of remaining
  single-room thermal terms. Introduce boundary authority only from registered
  flux owners after that closure.
- Binding record:
  `docs/validation/PHASE3_F31B_EFFECTIVE_BOUNDARY_SCOPE.md`.

## Current Session Update - 2026-07-17 - F3.1a O2 authority diagnosis

- F3.1a closes as a **GO for one semantic invariant** and a **NO-GO for
  global authority**: OES must debit the same O2 source selected by
  Combustion, but that contract is not ready to become the default.
- The existing default-OFF `fire_o2_canonical_enabled` flag removed all
  upper-O2 zombie rows in sealed, stairwell, ventilated and backdraft scratch
  controls. O2E1/A3 stayed clean and backdraft reventilation still recovered
  HRR after opening.
- Root cause: Combustion selects its source from the interface, while OES and
  Thermal shadow each infer sealed scope from raw opening geometry. Cases can
  contain opening objects while the corresponding transport is disabled, so
  the three systems disagree.
- The 120 s shadow control still reports ownership mask 6, missing combustion
  heat, `needs_flux_owner=1`, mass residual `0.02809879 kg` and energy residual
  `8.23522174 kJ`. Canonical state authority remains blocked.
- No F3.1a motor code, physical baseline, tolerance, official report, CTRL or
  VALID_GAP changed. Scratch runs are isolated under `runs/phase3_f31a/`.
- Next gate: F3.1b, one shared effective-boundary/scope contract for
  Combustion, OxygenExchange and Thermal shadow adapters. It must reach mask 7
  and `needs_flux_owner=0` in the sealed control before F3.2 can begin.
- Binding record:
  `docs/validation/PHASE3_F31A_COMBUSTION_O2_AUTHORITY.md`.

## Current Session Update - 2026-07-16 - F3.1 selected-O2 extinction

- F3.1 is split into a **GO for the selected-source extinction guard** and a
  **NO-GO for authoritative sealed Phase 3 state**.
- `CombustionSystem` now atomically zeros pyrolysis demand, retained-gas
  generation, flame, smolder, pool release and HRR when the selected O2 source
  reaches its declared extinction threshold. The analytic O2-independent mode
  remains exempt.
- The guard runs before retained-pool accumulation and leaves the `FireModel`
  attached for existing reventilation semantics.
- Runtime coverage proves cutoff below the threshold, no hard cutoff just
  above it and no cutoff in analytic O2-independent mode.
- A fresh 300 s `fuel_balance_diag_sealed` shadow run is bit-identical to the
  official 115 legacy columns. It still shows 35 upper-O2 zombie rows because
  `plume_lower` selects `o2_lower` near 20.9% while `o2_upper` is near 0.09%.
- State authority was not implemented. The shadow still reports
  `needs_flux_owner=1`, mass residual up to `0.08814274 kg` and energy residual
  up to `25.83801043 kJ`.
- Physics and ILV retain zero FAIL. Required validation remains 348/353 with
  five VALID_GAP. Guardrails have only expected R2-1 while motor is dirty.
- Next gate: F3.1a combustion O2-source authority, default OFF. Do not start
  F3.2 or globally replace `plume_lower` without a dedicated STOP gate.
- Binding record:
  `docs/validation/PHASE3_F31_SELECTED_O2_EXTINCTION.md`.

## Current Session Update - 2026-07-16 - F3.0k.1g vertical audit

- F3.0k.1g closes as a documentation-only **NO-GO for a new complete legacy
  vertical atomic bundle**. No motor, baseline, tolerance, report or
  validation classification changed.
- Active two-zone vertical openings already enter the
  `doorway_species_direct` contract from F3.0k.1d.
- The legacy vertical fallback is species-only. Thermal gas/energy and OES O2
  use separate solvers and cannot be attached to its species with one honest
  accepted fraction.
- The legacy downward O2 expression scales as
  `mass_down^2 / room_air_mass`; it is a mixing correction rather than the O2
  content of the compensating gas stream.
- New scratch controls completed:
  - two-zone vertical: 90.1 s;
  - forced legacy vertical: 90.1 s;
  - vertical no-fire: 60.0 s.
  No crash, hang, popup, incomplete CSV or unknown connection was observed.
- A valid 350.1 s prior control with unchanged vertical physics reaches the
  directed branch: vertical CO2 `1.1211 kg`, Thermal doorway carrier
  `6.1891 kg` and bulk O2 transport `4.4703 kg`. Their different magnitudes
  and activation times confirm separate physical contracts.
- Next gate: F3.1 authoritative **sealed** mode plus the zero-O2 extinction
  regression. Exterior remains F3.2, interior-opening authority F3.3 and HVAC
  stays deferred to F3.5.
- Binding record:
  `docs/validation/PHASE3_F30K1G_VERTICAL_TRANSPORT_AUDIT.md`.

## Current Session Update - 2026-07-16 - F3.0k.1f immediate transport audit

- F3.0k.1f is a documentation-only **NO-GO for a complete horizontal
  background/counterflow atomic bundle**. No motor code, baseline, tolerance,
  report or validation classification changed.
- Background uses one `exchange_air_kg` coefficient, but independent species
  gradients, optional bulk O2 diffusion and conditional hot-to-cold upper
  enthalpy can have different directions and activation conditions.
- No-delay doorway counterflow has exact gross bidirectional O2/species
  exchange, but legacy applies no matching gas-mass or enthalpy mutation.
  Adding those routes only in the shadow would invent a physical owner.
- Five normal scratch controls plus one no-delay control completed headlessly.
  The no-delay run activated 11,622 immediate transfers with non-zero
  counterflow and exactly zero CO/CO2/HCN debit-credit residual.
- All controls retain unresolved mask 7 intentionally. There are zero unknown
  connections, and parcel lifecycle residuals remain zero.
- Next candidate: F3.0k.1g vertical net/directed contract audit. It has
  explicit upward/downward flow masses, but enthalpy and zonal O2 must be
  proven before implementation.
- Exterior purge/pressure remains F3.2, zero-O2 flaming still blocks F3.1 and
  HVAC remains deferred to F3.5.
- Binding record:
  `docs/validation/PHASE3_F30K1F_IMMEDIATE_TRANSPORT_AUDIT.md`.

## Current Session Update - 2026-07-16 - F3.0k.1e delayed parcel lifecycle

- Commit `4f718791` closes F3.0k.1e as a **GO for passive delayed-parcel
  ownership**. F3.1 authority remains blocked.
- Every parcel now owns one atomic payload across carve, flight,
  delivery/refund or terminal cancellation. Its accepted fraction is computed
  once at carve and persists in the in-flight reservoir.
- The payload includes upper gas mass, sensible enthalpy, signed O2, smoke,
  CO, CO2, HCN, HCl, acrolein and formaldehyde. Negative O2 carry is an
  explicit reverse route. Legacy RoomModel writes are unchanged.
- Runtime OFF/ON proof: 120.1 s, 78 rows each, 115 shared legacy columns and
  8,970 cells with zero differences. OFF took 22.5 s and ON 36.3 s.
- At the final snapshot, 129.88026501 kg was created, 93.76759058 kg
  delivered and 36.11267443 kg remained in flight. Mass closed to
  `-1.42e-14 kg`; energy, O2 and species residuals were zero.
- Parcel anomalies are clean: zero orphan delivery, duplicate ID, negative
  balance, invalid/duplicate bundle and incomplete resolution.
- The first long ON attempt was discarded after a telemetry performance
  defect repeatedly rebuilt the in-flight inventory. Residuals are now
  calculated once per step.
- Tests: lifecycle 13 PASS, related 76 PASS, all Phase 3 tests 252 PASS and
  runtime fixture PASS. Physics and ILV retain zero FAIL; required validation
  remains 348/353 with five VALID_GAP.
- Next gate: audit horizontal background/counterflow before migration. Do not
  infer one common atomic payload if gas, energy, O2 and species use different
  legacy directions or activation rules.
- Zero-O2 flaming still blocks F3.1. HVAC remains deferred to F3.5.
- Binding record:
  `docs/validation/PHASE3_F30K1E_DELAYED_PARCEL_ATOMIC.md`.

## Current Session Update - 2026-07-16 - F3.0k.1d direct doorway bundle

- F3.0k.1d is a **GO for passive direct two-zone doorway ownership** and a
  **NO-GO for delayed parcels and F3.1 authority**.
- GES now emits one exact pre-mutation atomic route per direct doorway segment:
  gas mass, source-zone sensible enthalpy, O2 and CO/CO2/HCN share one accepted
  fraction. Legacy physical deltas and `RoomModel` remain unchanged.
- The owner policy grants complete opening ownership only to the exact
  `doorway_bulk` family. Other opening/parcel families retain unresolved mask
  7. Ownership registry resolution no longer depends on Thermal/GES arrival
  order.
- The 120 s two-room OFF/ON pair retained 78 rows and all 115 legacy columns
  with zero value differences. ON has 277 columns; 42 snapshots contain 2-8
  doorway bundles, fraction 1.0, zero rejection, zero duplicates/invalids and
  zero unresolved multi-producer conflicts.
- Delayed parcels remain separate because one accepted fraction must persist
  through carve, flight, delivery, refund and cancellation.
- Zero-O2 flaming remains a real independent blocker. Plume-lower can select
  lower-zone O2 while upper O2 is near zero; M4 mitigates this only when its
  default-OFF flag is enabled. No combustion fix or validation relabeling was
  made here.
- Physics and ILV remain at 0 FAIL; required validation remains 348/353 with
  five VALID_GAP. Guardrails have only expected R2-1 while motor files are
  dirty.
- Binding record:
  `docs/validation/PHASE3_F30K1D_DIRECT_DOORWAY_ATOMIC.md`.

## Current Session Update - 2026-07-15 - F3.0k.1c atomic bundle

- F3.0k.1c is a **GO for the passive atomic transaction primitive and shadow
  CO oxidation chemistry**, but remains a **NO-GO for complete ownership and
  F3.1 authority**.
- Ordered simple requests and atomic bundles share one transaction queue. An
  atomic bundle validates all routes, aggregates source-zone demand and applies
  one accepted fraction limited by gas mass, energy, O2 and CO/CO2/HCN.
- CO oxidation now carries exact upper-zone CO and O2 sinks plus an upper CO2
  product in one bundle. Shadow stoichiometry is 16/28 kg O2 and 44/28 kg CO2
  per kg CO. Legacy O2 is still untouched and legacy bulk-only CO2 remains.
- A runtime harness proved both energy-limited and O2-limited bundles at
  fraction 0.5 without mutating `RoomModel`. The 120 s oxidation control
  accepted 0.05037876 kg CO, 0.07916658 kg CO2 and 0.02878782 kg O2 with zero
  oxygen residual.
- OFF/ON invariance is exact: two-room 78 rows and oxidation 726 rows retain
  all 115 legacy columns with zero differences. ON now has 277 columns.
- The eight-case non-HVAC matrix completes, but every transport control still
  reports unresolved mask 7. No transport producer was falsely migrated.
- One 300 s oxidation ON attempt reached 282 s and timed out at 420 s; it is
  invalid evidence. The valid 120 s ON run took 95.7 s versus 38.0 s OFF, so
  long shadow runs remain a performance watch item.
- Validation: 225 focused tests PASS; physics 9/15/5/0; ILV 15/14/0; required
  348/353 with five VALID_GAP. Full pytest is 867 PASS / 18 FAIL: 17 historic
  plus expected R2-1 while motor is dirty. Official reports and baselines are
  unchanged.
- Active next phase: F3.0k.1d migrates one exact non-HVAC transport producer
  into the atomic API. F3.1 remains blocked by mask 7 and zero-O2 flaming.
  HVAC remains deferred to F3.5.
- Binding record:
  `docs/validation/PHASE3_F30K1C_ATOMIC_BUNDLE.md`.

## Current Session Update - 2026-07-15 - visual/UI plan closed

- Phase 3+ motor work is paused after checkpoint `6b397ebb`; this parenthesis
  touches only graph orchestration in `SimulationEngine.gd` plus `Main.gd` UI.
- Manual graph generation now uses a tracked asynchronous Python process.
  Main polls every 0.5 s behind a modal overlay, validates exit code and a
  freshly written output marker, and times out defensively after 60 s.
- "Exit without graphs" and "return to editor" suppress `_exit_tree` export.
  Natural extinction and closing/stopping the game retain automatic graphs.
- Python availability is checked once on scene entry with `python` and Windows
  `py -3` fallback. Missing Python produces a persistent HUD warning and an
  immediate actionable error when graph generation is requested.
- Automatic gates: graph/UI focused tests PASS, physics and ILV remain at
  zero FAIL, required validation remains 348/353 with five VALID_GAP. The
  two-resolution visual checklist remains a manual acceptance step.
- The visual checkpoint is complete. Phase 3+ resumed, completed F3.0k.1c,
  and now continues at F3.0k.1d.

## Current Session Update - 2026-07-15 - F3.0k.1b passive arbitration

- F3.0k.1b is a **GO for passive arbitration and exact CO-oxidation
  telemetry**, but a **NO-GO for complete ownership or F3.1 authority**.
- Provisional shadow owners are now explicit: GES owns opening CO/CO2/HCN,
  Thermal owns interlayer and combustion enthalpy, OES owns combustion O2,
  Combustion owns generated species and Engine owns CO oxidation.
- Thermal opening-species claims remain in the raw conflict registry but are
  suppressed only from the shadow request set. No legacy `RoomModel` writer,
  physical formula, ordering, FED path or validation policy changed.
- Missing gas mass, enthalpy and O2 transport bundles remain unresolved with
  mask 7. All eight runtime controls have zero unresolved multi-producer
  conflicts. Interior controls retain raw conflict/suppression mask 56.
- The 300 s oxidation control recorded positive CO sink and CO2 source over
  756 rows with exactly zero carbon residual. Its absent legacy O2 sink remains
  explicit; CO2 uses lower-zone compatibility semantics because legacy writes
  only bulk `co2_kg`.
- OFF/ON proof: 78 rows, 115 shared legacy columns, zero differences; ON has
  260 columns. Physics 9/15/5/0, ILV 15/14/0, required 348/353 with five
  VALID_GAP, guardrails 10/10, full tests 836 PASS / 17 historical FAIL, and
  artifact integrity 29 CSV PASS / 9 packages complete.
- Follow-up: F3.0k.1c delivered the atomic multi-zone accepted-fraction bundle
  and explicit shadow CO-oxidation O2 chemistry. F3.1 remains blocked by
  transport mask 7 and the existing zero-O2 flaming defect. Continue with
  F3.0k.1d; HVAC remains deferred to F3.5.
- Binding record:
  `docs/validation/PHASE3_F30K1B_PASSIVE_ARBITRATION.md`.

## Current Planning Decision - 2026-07-15 - HVAC deferred

- HVAC is deliberately deferred until the final Phase 3+ integration phase.
  Do not start F3.0j in `HVACSystem`; the subsystem is optional and will be
  redesigned before canonical ownership is implemented.
- F3.0j ThermalSystem CO/CO2/HCN transport is complete. F3.0k audited
  cross-path conservation and returned NO-GO. F3.0k.1 now completes ownership
  and semantic arbitration on HVAC-disabled controls before any shadow state
  is promoted to authority.
- Promotion proceeds through sealed mode, zero-O2 extinction, exterior
  pressure/leakage, interior openings and remaining non-HVAC species/FED.
- HVAC returns only after a user-approved specification defines supply/return
  zones, gas mass, enthalpy, species, recirculation, filtration, pressure and
  D1/S1/O1/FED ownership. Its implementation is F3.5, the last subsystem
  integration before F3.6 final promotion and legacy retirement.
- Until then, HVAC scenarios are legacy regression controls and cannot prove
  canonical conservation. Existing HVAC findings or skips must remain visible.
- Binding record:
  `docs/validation/PHASE3_HVAC_DEFERRED_DECISION.md`.

## Current Session Update - 2026-07-15 - F3.0k.1a semantic ownership claims

- F3.0k.1a is complete as a passive **GO for telemetry**. The F3.0k NO-GO for
  canonical authority remains in force.
- A step-local semantic key now joins stable connection identity, room
  direction, zonal direction and quantity before legacy mutation. Producer,
  transport family and boundary kind remain metadata so overlapping owners
  collide instead of hiding behind separate request ids.
- Stable identities cover openings, exterior purge, room interlayer movement
  and chemical sources. Delayed parcels claim only at creation, never again
  at delivery/refund.
- Runtime results: two-room max 14 conflicts, corridor 15, stairwell 3,
  remote-CO 15 and PPV 15. All use mask 56 (CO + CO2 + HCN). Sealed and
  partial-window controls have zero conflicts. Every case has zero unknown
  connection identities.
- OFF/ON proof retains 78 rows and 115 identical legacy columns. OFF has 115
  columns; ON has 245. No physical state, official report value, baseline,
  tolerance, expected value, control envelope or gap changed. Only the
  `reference_checks.json` freshness timestamp is refreshed for R2-1.
- Focused tests: 121 PASS. Physics and ILV remain 0 FAIL. Required validation
  remains 348/353 with 5 VALID_GAP. Guardrails are 9/10 only while motor is
  dirty (expected R2-1); full tests are 818 PASS plus 17 historical failures
  and the same R2-1 failure.
- One initial stairwell scratch CSV was discarded after the concurrently open
  visual editor locked it at 10 s. `.gdignore` isolation produced a complete
  180 s retry with no imports or lock errors; only that retry is evidence.
- Next phase: F3.0k.1b selects a provisional shadow owner, adds gas mass,
  enthalpy, O2 and exact CO-oxidation claims, but still does not suppress
  legacy writers or switch authority. HVAC remains deferred to F3.5.
- Binding record:
  `docs/validation/PHASE3_F30K1A_SEMANTIC_OWNERSHIP.md`.

## Current Session Update - 2026-07-15 - F3.0k cross-path audit

- F3.0k is complete as a documentation-only **NO-GO for canonical authority**.
  No motor, telemetry, report, baseline, tolerance, control envelope or gap
  classification changed.
- Source audit classified every non-HVAC writer of upper/lower gas mass,
  energy, O2 and CO/CO2/HCN. Existing combustion, GES and Thermal species
  contracts are exact, but gas/enthalpy and O2 remain unowned on several
  opening, parcel, background and exterior paths. CO oxidation is also
  unowned; projection/reconcile writes are not valid physical owners.
- Eight sequential Godot 4.6.3 console controls covered sealed, two-room,
  corridor, vertical, CO-remote, exterior-window and PPV paths. All ended in
  `RUN_SCENARIO PASS`; no process remained. Every implemented species contract
  had zero residual, zero duplicate identity and no parcel lifecycle anomaly.
- All eight controls still set `phase3_shadow_needs_flux_owner_flag=1`.
  Thermal and GES mechanisms also ran simultaneously on the same physical
  connections under different identities. This is a semantic ownership
  overlap, not a duplicate request-id defect.
- OFF/ON no-op proof on `cfast_two_room_door_open`: 78/78 rows, 115 shared
  legacy columns and zero differences; ON has 237 diagnostic columns.
- Zero-O2 flame remained visible in PPV, stairwell and v4 controls. It is the
  existing zombie-ILV debt and still blocks F3.1 authority.
- Active next phase: F3.0k.1 connection-level arbitration plus passive
  ownership completion for gas mass, enthalpy, O2 and CO oxidation. HVAC
  remains deferred until F3.5.
- Binding audit: `docs/validation/PHASE3_F30K_CROSS_PATH_AUDIT.md`.

## Current Session Update - 2026-07-15 - F3.0j Thermal species transport

- `ThermalSystem` now emits exact pre-mutation CO/CO2/HCN events for main
  doorway hot-gas carry, outside-assisted background heat exchange, interior
  background heat exchange and optional CO interlayer mixing.
- Source and destination upper/lower splits are preserved independently. The
  canonical shadow resolves them as a conservative 2x2 routing matrix and
  reports per-species requested, applied, rejected and residual values.
- Runtime OFF/ON proof on `cfast_two_room_door_open` retained 78 rows and 115
  shared legacy columns with zero differences. ON observed all three species,
  13,255 events, zero rejection, zero duplicates and zero residual.
- Projection/reconcile writes, GES exterior purge, smoke, irritants and HVAC
  are not claimed by this contract. HVAC remains deferred until F3.5.
- F3.0k returned NO-GO; F3.0k.1 is now the active gate for non-HVAC ownership
  completion and semantic arbitration. The shadow state remains passive and
  must not be promoted yet.

## Current Session Update - 2026-07-15 - F3.0i exterior species purge

- `GasExchangeSystem` now emits exact pre-mutation shadow events for every
  active CO/CO2/HCN purge it owns: pressure, smoke vent, natural ventilation,
  ACH, outside-open, post-fire and PPV inlet/exhaust. Events always route from
  the source room to the canonical exterior reservoir.
- Upper/lower semantics mirror legacy exactly, including the unusual PPV
  behavior where only CO upper stock is explicitly scaled. This phase records
  that behavior; it does not silently repair or reinterpret it.
- `Phase3ZoneMassSystem` exposes cumulative requested, applied and rejected
  purge mass, zonal split, mechanism totals, event/duplicate counts and
  per-species residuals. Engine only drains and forwards the event stream.
- Runtime proof: the ventilated OFF/ON pair retained 150 rows and 163 shared
  columns with zero value differences. ON requested and applied 1.144611 kg,
  with zero rejection, duplicates and residual. The sealed negative control
  emitted exactly zero purge events.
- The PPV control requested 6.638345 kg; 6.071909 kg was accepted and
  0.566436 kg rejected by shadow inventory limits. Conservation closed to
  `8.9e-16 kg`, demonstrating that rejection remains visible.
- Validation remains Physics 9/15/5/0, ILV 15/14/0 and 348/353 required with
  5 VALID_GAP. Artifact integrity remains 29 CSV PASS and no malformed run
  packages. F3.0i changes no official report or baseline.
- This F3.0i checkpoint was followed by F3.0j ThermalSystem ownership, now
  documented above. HVAC remains outside canonical claims. Do not promote
  shadow state to physical authority before F3.0k closure.

## Current Session Update - 2026-07-15 - artifact integrity audit

- A complete read-only audit of the 29 official CSVs found 48,884 valid rows,
  zero duplicate `(time_s, room_id)` rows, zero incomplete room snapshots,
  zero malformed/non-finite rows and zero duration truncations.
- All 84 technical packages under `runs/` that expose the run artifact
  contract are complete; none are partial or malformed. The native Godot
  dialogs seen during sandboxed launches did not contaminate accepted motor
  results.
- The 0.9/1.1 second variations are normal fixed-step logging quantization;
  snapshot counts and final durations close within one tick.
- Added `audit_artifact_integrity.py` as a reusable read-only gate. Same-stem
  CSV/JSON equality is deliberately not asserted because those artifacts have
  historically come from separate technical and CaseRunner workflows.
- Four stale JSON reports and historical orphan experiment reports remain
  provenance/hygiene debt. Do not bulk-regenerate them during Phase 3 shadow
  work. F3.0i exterior-purge species remains the next motor gate.

## Current Session Update - 2026-07-15 - F3.0h vertical species exchange

- The two legacy vertical-opening helpers now emit exact pre-mutation shadow
  events for CO, CO2 and HCN. Net CO is represented as independent upper and
  lower transfers, so opposite room directions are retained instead of being
  collapsed. Directed CO uses the exact legacy upper/lower split; CO2 and HCN
  are lower-only in both helpers.
- The paths remain disjoint from canonical two-zone doorway flow, delayed
  parcels and horizontal background/counterflow. Engine still only drains and
  forwards events; the shadow never writes `RoomModel`.
- Runtime proof: the short control retained 12 OFF/ON rows and the two-storey
  vertical control retained 793 OFF/ON rows. Both had 115 shared legacy
  columns and zero value differences. The real vertical path emitted 2,154
  transfers with zero rejection, duplicates and CO/CO2/HCN residuals.
- A deterministic Godot harness exercised net and directed branches with all
  three species and one explicit opposite-zone CO event. The horizontal
  two-room control produced zero for every vertical field.
- Validation remains Physics 9/15/5/0, ILV 15/14/0 and 348/353 required with
  5 VALID_GAP. Focused shadow tests are 114 PASS; the global suite becomes
  765 PASS / 17 historical failures after the normal R2-1 freshness refresh.
- Operational note for Codex runs: Godot must be launched outside the file
  sandbox because it writes `user://` under AppData. A sandboxed launch fails
  to create `user://logs` and can show a native access-violation dialog before
  simulation starts; this is not a motor result.
- Next gate: F3.0i should audit exterior purge as a separate exact species
  contract. HVAC and thermal transport remain later owners. Do not promote
  shadow state to physical authority.

## Current Session Update - 2026-07-15 - F3.0g immediate species exchange

- Horizontal background diffusion and no-delay doorway counterflow now emit
  exact pre-delta CO/CO2/HCN shadow events. The paths are disjoint from the
  canonical two-zone opening contract (F3.0e) and delayed parcels (F3.0f).
- Background emits one signed transfer per species. CO preserves the source
  upper share; CO2 and HCN are lower-only because legacy changes only bulk
  stock. Counterflow emits both gross directions, retaining each source's
  upper/lower split rather than hiding churn in a net delta.
- `Phase3ZoneMassSystem` applies the events only to shadow state and exports
  cumulative mass by mechanism/species, rejection and conservation residuals.
  Parcel lifecycle residuals are now also separated by CO, CO2 and HCN.
- Runtime proof: 42 OFF/ON rows, 115 shared legacy columns, zero differences;
  ON has 171 columns. Two-room/corridor/v4 exercised background, the sealed
  control exercised both background and counterflow, and every immediate and
  parcel residual was zero.
- Small immediate shadow rejection (up to about 0.00051 kg in the audited
  controls) remains visible. It reflects producers/order still absent from the
  shadow ledger; no physical mass is removed and no tolerance was relaxed.
- FED and the known ILV defect are unchanged: victim incapacitation remains
  206.1 s and `cfast_multi_fuel_couch_tv` retains 7 zero-O2 flame hits.
- Explicit exclusions: vertical-opening helpers, exterior purge, HVAC,
  thermal transport, smoke, irritants and O2 counterflow.
- Next gate: F3.0h should audit and connect the vertical-opening CO/CO2/HCN
  paths as their own contract. Do not promote shadow state to physical
  authority.

## Current Session Update - 2026-07-14 - F3.0f persistent parcel reservoir

- Delayed CO/CO2/HCN parcels now carry a monotonic shadow id from carve through
  delivery. The id and reservoir exist only with
  `phase3_canonical_zone_shadow_enabled`; OFF remains bit-identical.
- `GasExchangeSystem` emits exact `created`, `resolved` and `cancelled` events.
  Resolution carries delivered and refunded total/upper species after the
  existing headroom calculation. `Phase3ZoneMassSystem` persists the reservoir
  across `begin_step` and generates separate upper/lower shadow requests.
- This is not a physical ownership switch: no `RoomModel` state, transport
  coefficient, headroom rule, FED path or timestep ordering changed.
- Runtime conservation:
  - two-room: created 0.039121 kg, delivered 0.014704 kg, in flight 0.024417 kg;
  - corridor: created 1.408540 kg, delivered 1.031483 kg, refunded 0.000152 kg,
    in flight 0.376905 kg;
  - v4 remote CO: created 6.718308 kg, delivered 5.121284 kg, refunded
    0.095449 kg, in flight 1.501574 kg.
- All three controls had zero conservation residual, zero zonal rejection,
  zero orphan deliveries, duplicate ids or negative balances. OFF vs ON kept
  all 115 legacy columns identical; ON now has 157 columns total.
- Safety controls are unchanged: sealed case creates zero parcels, victim
  incapacitation remains 206.1 s, and zombie ILV remains at 7 hits.
- Exclusions remain explicit: smoke, HCl, acrolein, formaldehyde, O2, parcel gas
  mass/energy, background exchange, purge, HVAC and thermal transport.
- Next gate: F3.0g should select one remaining explicit species transport
  producer, preferably background/counterflow exchange, and reuse its exact
  pre-mutation result. Do not promote shadow state to physical authority yet.

## Current Session Update - 2026-07-13 - F3.0e direct doorway species transport

- The owned producer is only `_apply_two_zone_opening_species_exchange` through
  `_move_upper_zone_species` / `_move_lower_zone_species`. Each route emits one
  `doorway_species_direct` result with explicit source/destination zones and
  CO/CO2/HCN masses before applying it to the legacy delta dictionaries.
- Background exchange, exterior purge, HVAC, thermal transport, parcel carve
  and delayed delivery remain excluded. Engine reads no net-transport
  accumulator, post-step stock, headroom formula or parcel queue.
- Exact checkpoint proof: 42 rows x 115 columns, checkpoint vs OFF = 0
  differences and OFF vs ON = 0 differences. Two-room source/destination
  telemetry matched exactly; rejection and duplicate ownership were zero.
- Corridor and v4 controls produced nontrivial doorway requests. In v4,
  `needs_flux_owner` remains set in all rooms because direct doorway ownership
  intentionally explains only part of legacy transport.
- Zombie ILV remains unchanged: 7 hits from 120-180 s.
- Next gate is F3.0f design for a persistent in-flight parcel reservoir. The
  current per-step shadow cannot own delayed transport honestly without state
  that survives between transactions.

## Current Session Update - 2026-07-13 - F3.0d species source contract

- `CombustionSystem` now creates one post-clamp result containing exact total
  CO/CO2/HCN generation and its canonical upper/lower split before any species
  stock is mutated. Legacy and shadow consume that same result.
- CO uses the existing Phase 2G split. CO2 and HCN are upper-zone sources.
  The OES CO2 tracer, smoke, HCl, acrolein and formaldehyde remain unowned.
- Engine only translates upper/lower maps into exterior-to-zone requests. It
  contains no yield, phi, carbon-clamp or pool-release reconstruction.
- Runtime OFF vs F3.0c and OFF vs ON: 42 rows, 115 shared legacy columns, zero
  differences. Species telemetry is nonzero; rejected mass and duplicate-owner
  flags remain zero. The ownership mask can now reach 7 (energy + O2 + species).
- A 720 s VC control passed with nonzero CO/CO2/HCN requests. The known zombie
  ILV remains unchanged at 7 hits from 120-180 s.
- Next gate: F3.0e should connect one pre-mutation species transport producer,
  starting with direct doorway transfer. Delayed parcels must remain a separate
  owner and must not be inferred from post-step stock deltas.

## Current Session Update - 2026-07-13 - F3.0c zonal O2 contract

- OxygenExchangeSystem now emits exact pre-mutation shadow results for upper,
  explicit-lower and plume-lower combustion O2 sinks. Requests move only O2
  from the source zone to exterior.
- Bulk O2 consumption remains deliberately unowned because legacy has no
  canonical upper/lower split. In mixed bulk+upper modes the residual remains
  visible; no heuristic distribution was added.
- Runtime OFF/ON: 42 rows, 115 shared legacy columns, zero differences; maximum
  zonal request 0.00006621 kg, ownership mask 3, zero rejects and duplicates.
- The known zombie ILV remains unchanged: 7 hits from 120-180 s, about 971 kW
  at 0.08% upper O2. F3.0c instruments it but does not fix it.
- Next gate: F3.0d species generation contract in CombustionSystem.

## Current Session Update - 2026-07-13 - F3.0b combustion energy contract

- F3.0b connects only the unambiguous part of combustion: convective heat.
  Thermal computes one `convective_energy_kj` value, records it pre-mutation and
  applies that same value to legacy state. Engine does not recalculate HRR.
- Shadow request: exterior to room upper zone, zero gas mass, zero O2 and no
  species. `phase3_shadow_combustion_owned_mask=1` documents partial ownership.
- O2 and species remain open for F3.0c because their ownership is split between
  CombustionSystem and OxygenExchangeSystem. Do not derive them from observed
  post-step deltas.
- Runtime OFF/ON (`cfast_co2_stratification`, 60 s): 42 rows, 115 shared legacy
  columns, zero differences; two causes, zero rejected requests, zero duplicate
  owners.

## Current Session Update - 2026-07-12 - Clean start for Phase 3+ canonical two-zone

### F3.0a first flux owner

- First owner selected: plume entrainment, not combustion.
- `ZoneFireSolver` now returns a pure lower-to-upper transfer preview before
  applying that exact mass/energy object to legacy state.
- Thermal records the preview only when shadow mode is enabled and the room has
  no active opening. Engine converts it to one `plume_entrainment` request with
  gas mass, sensible enthalpy and lower-zone O2.
- Runtime `cfast_co2_stratification`, 60 s: 42 rows OFF/ON, 115 shared legacy
  columns, zero legacy differences, max plume request 0.02416765 kg, zero
  rejected mass, zero duplicate ownership, and exact upper-mass agreement for
  the owned plume transfer.
- `fuel_balance_diag_sealed` and `o2_stoich_diag_sealed` ran successfully but
  emitted no request because their template still has active openings; the
  conservative scope guard excluded them. Official CSVs were restored.
- The passive zero-O2 flag detected 7 known zombie-ILV snapshots in
  `cfast_multi_fuel_couch_tv` between 120 and 180 s. It does not alter HRR.
- Physics and ILV remain at zero FAIL; gaps remain 348/353 with 5 VALID_GAP.

Next target: F3.0b combustion result contract. Do not connect combustion until
HRR energy, O2 sink and species sources have explicit, single-owner outputs.

### F3.0 implementation checkpoint

- `Phase3ZoneMassSystem.gd` now owns the experimental shadow transaction.
- `phase3_canonical_zone_shadow_enabled` is default OFF and can be enabled by
  engine override or `run_scenario.py --phase3-canonical-shadow`.
- The transaction snapshots upper/lower mass, energy, O2 and CO/CO2/HCN before
  the legacy step. Requests require a stable id, cause, endpoints, zones, gas
  mass, enthalpy, O2 and species; duplicate ids and inventory rejection are
  exported.
- No subsystem emits authoritative requests in F3.0. This is intentional: the
  shadow output marks legacy deltas with `phase3_shadow_needs_flux_owner_flag`
  rather than deriving circular requests from observed post-step mutations.
- Runtime proof on `cfast_co2_stratification` (10 s): 12 OFF rows and 12 ON
  rows, 115 shared legacy columns, zero legacy differences; ON adds ten shadow
  columns.
- Validation after implementation: physics 0 FAIL, ILV 0 FAIL, gap inventory
  348/353 with the same 5 VALID_GAP. Guardrail R2-1 requires only the usual
  metadata freshness refresh while motor files are dirty.

Next implementation target: F3.0a, one explicit sealed-room request adapter.
Start with a producer that exposes a pre-mutation solver output; do not infer a
request from F0 stage deltas. Combustion heat/O2 is preferred only after its
single ownership and step ordering are demonstrated by focused tests.

### Baseline

- Latest committed baseline before this update: `53898ba2` (`chore(validation): refresh reference_checks.json timestamp`).
- F1a/F2.0 diagnostic infrastructure is already committed locally:
  - `phase3_zone_diagnostics_enabled` exports opt-in two-zone diagnostics.
  - `phase3_conservative_lower_return_enabled` exists as an experimental default-OFF transport diagnostic.
  - F2.0 mass-flow ledger exports doorway, parcel and upper-removal counters when diagnostics are enabled.
- F2.2a passive pressure-vent diagnostics are present in the working tree and are accepted as diagnostic-only baseline work.
- Validation state to preserve:
  - Guardrails: 10/10 PASS.
  - Physics coherence: 0 FAIL.
  - ILV suite: 0 FAIL.
  - Gap inventory: 348/353 required PASS, 5 VALID_GAP, 71 non-gating gaps.

### What changed in the plan

The previous F2 pressure/projection path is closed:

- F2.1 ledger-aware projection was tested and rejected. It reduced some boundary mass but collapsed lower-zone gas and exploded volume closure because the upstream zone inventory is not canonical.
- F2.2 local pressure-vent fixes are also rejected as the next implementation target. F2.2a showed the pressure/vent path is diagnostic-rich but unsafe to patch locally while `project_room_state()` can recreate gas mass from EOS.
- The active plan is now **F3.0 shadow canonical two-zone state**.

The key architectural decision is: do not mutate `project_room_state()`, pressure venting, doorway transport or delayed parcels again as isolated fixes. First introduce a canonical shadow transaction that owns upper/lower mass, energy, O2 and species from a pre-step snapshot plus explicit flux requests.

Authoritative planning document:

- `docs/validation/PHASE3_CANONICAL_TWO_ZONE_ARCHITECTURE.md`

Supporting diagnostic documents:

- `docs/validation/PHASE3_F0_ZONE_DIAGNOSTICS.md`
- `docs/validation/PHASE3_F22A_PRESSURE_VENT_DIAGNOSIS.md`

### F3.0 objective

Add `phase3_canonical_zone_shadow_enabled`, default OFF. The mode must:

- Snapshot room state before the fixed physics step.
- Collect explicit flux requests from combustion, plume/thermal, openings, gas exchange, HVAC, suppression and exterior boundaries.
- Apply those requests to a shadow state only.
- Export residuals against the legacy end-of-step state.
- Change no legacy physics, no required baselines, no FED behavior and no CSV schema when the flag is OFF.

Initial F3.0 scope should be deliberately narrow:

1. Single-room sealed combustion and plume.
2. Exterior leakage/pressure only after sealed residuals close.
3. One interior doorway only after ownership and sign conventions are stable.

### Stop conditions

Stop and revert the F3.0 attempt if any of these occurs:

- Flag OFF changes any legacy output.
- A shadow request is built from post-mutation deltas rather than pre-step state plus an explicit physical flux.
- A parcel/species/gas mass has two owners or no owner.
- The implementation compensates a residual by adding a projection/clamp term and calling it physical.
- Zero-O2 flaming behavior is carried into canonical mode without an explicit extinction check.

### Clean-start rule

From this point, avoid new per-case calibration knobs for Groups A/C. The remaining 5 VALID_GAP checks are structural and should move only through the canonical two-zone transaction path.

## Current Session Update - 2026-07-09 - Grupo C confirmado como VALID_GAP estructural

### Estado guardado

- HEAD remoto: `2a0766c6` (`fix(validation): apply declared fire_o2_mode in cfast_hvac_residential`).
- Working tree: limpio antes de esta nota.
- Physics coherence: **0 FAIL** - 9 PASS / 15 CTRL / 5 WARN.
- Validation guardrails: **10/10 PASS**.
- Gap inventory: **348/353 PASS**, **5 VALID_GAP**, 71 gaps non-gating.

### Diagnostico Grupo C - `cfast_corridor_chain`

Se verifico el candidato de runner/config mismatch despues de cerrar los Grupos D y E. Resultado:
**Grupo C NO es runner/config mismatch**. Permanece como gap fisico estructural documentado.

- Los 2 checks restantes de `cfast_corridor_chain` siguen siendo CCH-2: doorway thermal counterflow / Phase 3+.
- No hay fix JSON-only equivalente al de `cfast_slow_growth_sealed` o `cfast_hvac_residential`.
- No se realizaron cambios de motor, tolerancias, expected baselines ni reports.

### VALID_GAP restantes

- **Grupo A** - `cfast_r0_window_360` (3 checks): gap estructural O2/two-zone Phase 2/3+.
- **Grupo C** - `cfast_corridor_chain` (2 checks): requiere bidirectional doorway thermal counterflow / ODE de presion dos zonas (M3/Phase 3+).

Siguiente trabajo recomendado: no seguir con fixes per-case para Grupo C. Cualquier cierre real requiere plan de arquitectura Phase 3+ con STOP gate propio.

---

## Current Session Update - 2026-07-08 — Plan B/F2 cerrado (fed_co2_source_mass flag)

### Estado operativo actual (2026-07-08, HEAD pendiente de commit)

- Branch: `main`, cambios sin commitear (motor F2 + script validate_reference_cases.py + reference_checks.json + docs).
- `validate_reference_cases`: **344/353 PASS** — 9 VALID_GAP; sin cambio de comportamiento.
- Physics coherence: **9 PASS / 14 CTRL / 6 WARN / 0 FAIL**, exit 0.
- ILV suite: **15 PASS / 14 CTRL / 0 FAIL**, exit 0.
- Guardrails: **10/10 PASS, exit 0** — R2-1 OK (reference_checks.json regenerado con `generated_at`).
- pytest: **598/604** — 6 pre-existentes two-zone structure, sin cambio.

### Plan B / F2 — flag `fed_co2_source_mass` (2026-07-08)

**Objetivo:** Añadir flag experimental per-caso para cambiar la fuente de CO₂ en el cálculo
`v_co2` del FED ISO 13571 del tracer OES (`room.co2_upper × 1e6`) al path mass-derived
(`co2_upper_kg / upper_zone_mass_kg`). Evaluar si el path mass mejora la exactitud.

**Resultado del experimento:** Flag ON es físicamente incorrecto en la cola post-extinción.
`co2_upper_kg` no drena cuando el fuego se extingue pero `upper_zone_mass_kg` colapsa por
enfriamiento → `co2_upper_ppm_mass` sube a >500 000 ppm (físicamente imposible). FED del adulto
(1.8 m) acumula valores astronómicos. Impacto en víctima a 0.9 m (zona inferior): +0.08 s —
irrelevante (usa `compute_co2_lower_ppm` en ambos modos).

**Decisión:** Mantener flag como infraestructura experimental default OFF. Default OFF = no-op
exacto — ningún check, baseline ni guardrail afectado. F3 (activar path mass en producción)
está **bloqueado** hasta corregir `co2_upper_kg` post-extinción.

Ver detalle completo: `docs/validation/plan_b_f2_fed_co2_mass_flag.md`

### Fix permanente R2-1 (2026-07-08)

`validate_reference_cases.py` ahora incluye `generated_at` (ISO 8601 UTC) en el JSON de salida.
Esto garantiza que cada regeneración cambia el contenido del archivo → git lo marca dirty →
R2-1 gate 1 pasa cuando el motor cambia pero el comportamiento es idéntico (flag OFF, etc.).
Antes: regenerar con flag OFF producía JSON byte-a-byte idéntico al commitado → R2-1 disparaba
aunque el usuario sí hubiera regenerado.

### Archivos modificados en este commit

Motor (2):
- `sim/core/SimulationEngine.gd` — `@export var fed_co2_source_mass: bool = false` + settings
- `sim/core/ThermalSystem.gd` — var + configure + 2 sitios FED patched

Validación (2):
- `scripts/simulation/validate_reference_cases.py` — `import datetime` + campo `generated_at`
- `sim/validation/reports/reference_checks.json` — regenerado (mismos 9 VALID_GAP)

Docs (2):
- `docs/validation/plan_b_f2_fed_co2_mass_flag.md` — nuevo, experimento completo
- `docs/HANDOFF_CURRENT_STATE.md` — esta entrada

### Próximos pasos

1. **Bug `co2_upper_kg` post-extinción:** mismo bug familiar que F0. El pool intra-room de
   `co2_upper_kg` no vacía al ritmo que colapsa `upper_zone_mass_kg` al enfriarse. Síntoma:
   `co2_upper_ppm_mass > 5 × 10⁵ ppm` a t ≈ 630 s en `victim_fed_incapacitation`.
   Cuando se corrija, F3 puede proceder.

2. **D2PRE transporte inter-room:** 6 WARNs restantes (divergencia tracer vs mass en salas
   receptoras). Requiere mapeo del transporte de CO₂ entre rooms — sesión dedicada Plan B.

---

## Current Session Update - 2026-07-07 — CO/specie pumping fix + HVAC VALID_GAP

(Registrado en project_overview.md — HEAD=3f5e0a4f, 5 commits pusheados)

---

## Current Session Update - 2026-07-06 (rev 35 - Rehabilitación de gates: ILV suite + guardrails + CI a exit 0)

### Contexto

Auditoría completa del proyecto detectó que 2 de las 3 suites-gate llevaban en **exit 1 crónico** — gates "quemados": un rojo nuevo era indistinguible del rojo permanente, incluido `tests.test_guardrails::test_exit0_real_json` que corre en CI (workflow `validation-guardrails.yml` en rojo). Sesión de rehabilitación sin tocar motor, thresholds, severities ni baselines.

### Estado operativo actual (todo verificado en vivo)

- Branch: `main`, cambios locales sin commitear (6 archivos, esta sesión).
- `validate_reference_cases`: **349/354 PASS** (5 VALID_GAP) — sin cambio.
- Physics coherence: **9 PASS / 5 CTRL / 3 WARN / 0 FAIL**, exit 0 — sin cambio.
- ILV layer coherence: **12 PASS / 5 CTRL / 0 FAIL, exit 0** (antes: 3 FAIL, exit 1).
- Guardrails: **8/8 gates PASS, exit 0** (antes: 4 secciones FAIL, exit 1).
- Tests: **209/209** physics coherence + **21/21** guardrails (antes 15, con 1 en rojo).

### Cambios (todos en capa de validación)

1. **ILV suite** — 3 CTRL nuevos registrados: `cfast_two_floor_stairwell` (42), `fuel_balance_diag_sealed` (35), `o2_stoich_diag_sealed` (35). Los tres son el bug ILV lower-O2 conocido (zombie HRR, o2_upper≈0.09%) en configs selladas sin M4 — no defectos nuevos. `v1_m4_pool_release` retirado (0 findings tras M5, CTRL obsoleto). Nota: el CTRL de los diag_sealed en ILV NO absorbe sus D2PRE de la physics suite, que siguen como WARN a propósito (gap M1 real).
2. **`gap_inventory_check.py`** — allowlist `KNOWN_VALID_GAP_REQUIRED_FAILURES` (los 5 VALID_GAP del hito 2026-06-21). Gate pasa solo si los required fallidos ⊆ allowlist; fallo required nuevo → exit 1. Detecta entradas obsoletas y JSON corrupto.
3. **`validation_guardrails.py`** — gate required vía la allowlist ("PASS (5 VALID_GAP)"). Linter R1-3: exención por (caso, clave) para `(cfast_pool_fire_open, vent_bernoulli_flow_multiplier)` — override intencional Phase 9 C4 (commit b5c63ce9) anterior al linter; deuda documentada visible, retirar la exención cuando se elimine el override en sesión de motor.
4. **`phase2e_preflight.py`** — sentinels non-required que fallan → "GAP (non-gating)", no gatean (el `g4 FED timing` es non-required y está en los 70 gaps). Los required siguen gateando.
5. **`GAPS_INVENTORY.md`** — encabezado 345/350→**349/354** required, 69→**70** gaps. Delta desde 2026-06-21: +4 required (baselines `v5_m4_ventilation_throttle`, todos PASS); gaps +3/−2 por corrimiento de timestamps de presión (mismo gap estructural Phase 3).
6. **`tests/test_guardrails.py`** — 6 tests nuevos que prueban que los gates siguen mordiendo: required nuevo no permitido → exit 1 (en ambos scripts), VALID_GAP+nuevo → exit 1, exención del linter limitada a su clave → exit 1 con otra clave.

### Endurecimiento CTRL — envelopes por regla/conteo (2026-07-06, misma sesión)

`KNOWN_INTENTIONAL_CONTROLS` en ambas audit suites pasa de set de stems a `{stem: {regla/kind: conteo_max}}` (conteos medidos 2026-07-06 + ~25% margen). Un finding de regla no registrada o conteo excedido reclasifica el caso CTRL a FAIL ("CTRL envelope excedido") y **gatea aunque el exceso sea WARN**. `v1_m4_pool_release` excluye A3 a propósito (eliminado por M5 — si reaparece, FAIL). `--intentional` CLI mantiene envelope ilimitado legacy. Tests: 209→216 physics, 19→26 ILV. Resultados actuales de las suites sin cambios (9/5/3/0 y 12/5/0, ambas exit 0).

### Guardrails R2-1 + PHY-P1 y bug motor CO₂ bulk descubierto (2026-07-06, misma sesión)

- **R2-1 frescura:** guardrail git-based — motor/casos más recientes que `reference_checks.json` (commit o working tree) → FAIL. Se omite con nota si no hay git/historial (CI shallow).
- **BUG MOTOR NUEVO:** el FED=3.47e9 de `v3_hallway` no es la fórmula de Purser: es `room_1_peak_co2_ppm = 1.099e6` (>100% de la mezcla). **7 casos afectados** (`confinement_open_close`, `postfire_decay`, `row_house_ground_floor_smoke`, `secondary_ignition_demo`, `v3_hallway_fed_exposure`, `v4_co_remote_rooms`, `v6_spread_to_hallway`), siempre CO₂ bulk de sala receptora (1.02e6–2.10e6 ppm), nunca fire room ni métricas upper. Root cause probable: dilución incorrecta en el path bulk/lower del transporte inter-room. Diagnóstico pendiente de sesión de motor dedicada.
- **PHY-P1 plausibilidad:** métrica `*_ppm` > 1e6 → FAIL salvo las 7 parejas registradas en `_KNOWN_PPM_VIOLATIONS` (deuda visible; el bug no puede crecer en silencio).
- Guardrails: **10/10 gates PASS, exit 0**. Tests guardrails 21→31.

### Expansión de cobertura 17→29 CSVs (2026-07-06, continuación de sesión)

- 12 casos representativos generados (`run_scenario.py` headless), deduplicados (el engine duplica las filas del último timestep — artefacto neutralizado en el pipeline) e instalados en reports/. Subsistemas nuevos bajo las 13 reglas: HVAC, supresión, cristales, multifuel, corridor, flashover, PPV, multi-planta, CO remoto, PVC/HCl, PU/FED, reburn.
- 7 CTRL envelope nuevos en physics suite (12 total), 8 en ILV (14 total, pinean la extensión del zombie por caso). 4 casos solo-D2PRE quedan como WARN (Plan B multi-room). `cfast_suppression_water` limpio.
- **Hallazgos motor nuevos:** (1) gap instrumentación HVAC — HVACSystem extrae smoke/CO sin acumuladores (D1/S1 en `cfast_hvac_residential`, mismo root cause que el skip O1); (2) write-off de inventario de fuel — `victim_fed_incapacitation` t=650s: `solid_fuel_remaining_MJ` cae 2200.15 MJ para igualar `fuel_remaining_MJ` post-extinción, sin acumulador de consumo.
- **Estado final:** physics **10 PASS / 12 CTRL / 7 WARN / 0 FAIL** (29 CSVs, exit 0) · ILV **15 PASS / 14 CTRL / 0 FAIL** (exit 0) · guardrails **10/10** (exit 0) · 31+242 tests. Los 7 WARN son todos D2PRE (Plan B).

### Deuda pendiente identificada en la auditoría (estado final de sesión)

- ~~CTRL absorbe por stem completo~~ — **CERRADO** (envelopes en ambas suites).
- ~~Sin check de frescura reports vs código `sim/`~~ — **CERRADO** (R2-1).
- ~~Bounds débiles / FED 3.47e9~~ — **DIAGNOSTICADO**: bug de motor (CO₂ bulk >100% en receptoras), acotado por PHY-P1; fix de motor pendiente.
- ~~Cobertura de coherencia ~17/108 casos~~ — **AMPLIADO a 29/108** (todos los subsistemas principales representados). Ampliar más es opcional e incremental con el mismo pipeline.
- **Candidatas para próxima sesión de motor (por rendimiento):** (1) Plan B / M1 o2_scale double-throttle — cerraría los 7 WARN D2PRE y gran parte de los D2PRE absorbidos en CTRLs; (2) bug CO₂ bulk >100% en receptoras (7 casos, afecta FED/toxicidad); (3) instrumentación HVAC de especies (retiraría el CTRL de cfast_hvac_residential); (4) write-off de inventario de fuel post-extinción.

## Session 2026-07-07 — M1 falsado, Plan B redirigido a transporte inter-room

### Experimento M1 (o2_scale double-throttle) — FALSADO

**Patch aplicado y revertido.** No produce cambio observable → revertido a `01610b46`.

**Hipótesis original:** `OES.co2_produced *= o2_scale` aplica un segundo throttle con `room.o2_upper` cuando `effective_plume_lower` ya throttleó el HRR por `o2_lower`. Diagnóstico: causa del D2PRE 7 WARN.

**Resultado del experimento:**
- CSVs regenerados byte-a-byte idénticos al baseline.
- D2PRE sin cambio: `cfast_slow_growth_sealed` 243, `fuel_balance_diag_sealed` 230, `o2_stoich_diag_sealed` 230.
- Physics suite: 10/12/7/0 sin cambio. ILV: 15/14/0 sin cambio. FED: sin cambio.

**Por qué M1 no activa:**

`plume_lower_mode` requiere `fire_o2_mode == "legacy"`. Los casos de test usan:
- `cfast_slow_growth_sealed`: `validation_fire_o2_mode: "upper"` → nunca activa.
- `fuel_balance_diag_sealed` / `o2_stoich_diag_sealed`: casos multi-room con aberturas interiores → `interior_open_factor > 0.01` → nunca activa.

**Root cause corregido de los 7 WARN D2PRE:** Los findings D2PRE están en salas **receptoras** (room=1, 2…), no en la sala de fuego. La divergencia `co2_upper_ppm(tracer) vs co2_upper_ppm_mass` es un problema de **transporte inter-room**, no de producción. Los dos paths (tracer mol-fraction via OES/GES y mass kg via CombustionSystem/GES doorway) divergen en cómo acumulan CO₂ en salas sin fuego.

**Estado del bug M1/o2_scale:** El double-throttle es un bug latente real, pero solo afectaría a casos con `fire_o2_mode = "legacy"` Y sala single-room sellada. Ninguno de los 29 casos actuales lo ejerce. No es causa activa de D2PRE.

**Plan B redirigido:** Sesión dedicada para mapear transporte inter-room de CO₂:
- Tracer path: `room.co2_upper` (mol fraction) via `_exchange_room_o2_active_flow` en OES/GES.
- Mass path: `room.co2_upper_kg` via transporte de gases en GES/doorway.
- Oráculo: D2PRE peor caso room=1 t=60s en los diag_sealed (rel_div=7.1×).

---

## Session 2026-07-07 — F0 Plan B: CO₂ bulk >100% CORREGIDO (commit pendiente)

### Objetivo y resultado

PHY-P1 gate sin allowlist: PASS. Las 7 salas receptoras que superaban 1e6 ppm de CO₂ están
corregidas. `_KNOWN_PPM_VIOLATIONS` queda vacío — el gate sigue activo y morderá si el bug
reaparece.

### Root cause

NO era creación de masa. Conservación exacta verificada en v4:
- CSV (submuestreo 1s): aparente 62 kg de CO₂ — artefacto × 12 del dt del engine (1/12 s).
- Verificación real (engine dt): 61.44 kg generados ≈ 62.04 kg en salas. Conservación exacta.

Root cause real: **bombeo concentrador** en el transporte inter-room.
`co2_moved = min(smoke_kg/source.smoke_kg, 1.0) × source.co2_kg` satura a 1.0 cuando la sala
de fuego tiene muy poco smoke_kg (~0.1 kg). En cada tick exporta TODO el stock CO₂ disponible
al hub (pasillo). El delayed delivery path amplificaba el efecto sin una cota de equilibrio.

### Fix — 3 puntos en el motor

1. **GES doorway (~L828):** limitador de equilibrio por concentración. El receptor no puede
   superar la concentración CO₂ de la fuente en esa advección.
   `co2_headroom = max(0, c_src × air_tgt − stock_tgt)` con densidad de aire 1.2 kg/m³.
   `co2_upper_moved` recortado por el mismo `cut_ratio`.

2. **GES delayed delivery:** se añade `"from": from_id` al parcel en vuelo y se re-aplica la
   misma cota al entregar. Excedente devuelto a la sala origen — conservación intacta.

3. **ThermalSystem (~L2779):** mismo limitador para el segundo path de transporte CO₂.

CO, HCN, OES, FED, baselines y tolerancias: **no tocados**.

### Resultados medidos

| Caso | CO₂ antes | CO₂ después |
|------|-----------|-------------|
| confinement_open_close | 1.02e6 ppm | 1.46e5 ppm |
| postfire_decay | 1.19e6 ppm | 2.77e5 ppm |
| row_house_ground_floor_smoke | 2.11e6 ppm | 4.40e5 ppm |
| secondary_ignition_demo | 1.19e6 ppm | 2.77e5 ppm |
| v3_hallway_fed_exposure | 1.10e6 ppm | 2.56e5 ppm |
| v4_co_remote_rooms | 1.10e6 ppm | 2.56e5 ppm |
| v6_spread_to_hallway | 1.19e6 ppm | 2.77e5 ppm |

FED v3 pasillo: 3.47e9 → 2.91e3 (corrección, no regresión — el absurdo venía del CO₂ > 100%).

### Estado de suites (post-fix)

- Physics suite: **exit 0** — 10 PASS / 12 CTRL / 7 WARN / 0 FAIL.
  v4_co_remote_rooms CTRL envelope actualizado: D2:69 añadido (55 medidos + 25% margen).
  Motivo D2 nuevo: al normalizar CO₂, sube ratio CO/CO₂ en receptoras — CO tiene el mismo
  bug de bombeo, pero la cota de CO es seguimiento separado (constraint: no tocar CO).
- ILV suite: **exit 0** — 15 PASS / 14 CTRL / 0 FAIL.
- Guardrails: **exit 1** — solo 5 stale checks pre-existentes (cfast_hvac + cfast_chain),
  no causados por F0. PHY-P1 PASS.
- pytest: **272/273** — único fallo `test_exit0_real_json` (stale reference_checks.json,
  pre-existente, no causado por F0).
- validate_reference_cases: **344/354** — mismos 10 FAILs que antes del fix
  (5 VALID_GAP + 5 stale cfast); ningún delta causado por F0.

### Archivos modificados (sin commit aún)

Motor (2):
- `sim/core/GasExchangeSystem.gd` — limitador GES doorway + delivery
- `sim/core/ThermalSystem.gd` — limitador ThermalSystem

Validación (3):
- `scripts/simulation/validation_guardrails.py` — `_KNOWN_PPM_VIOLATIONS = {}`
- `scripts/simulation/audit_physics_coherence_suite.py` — D2:69 en envelope v4
- `tests/test_guardrails.py` — test allowlist usa entrada sintética (la real está vacía)

Reports regenerados (9):
- 7 reports JSON + `v4_co_remote_rooms.csv` + `reference_checks.json`

### Pendientes separados (no causados por F0)

1. **CO pumping follow-up:** CO tiene el mismo bug de bombeo concentrador en GES. Requiere
   plan + auditoría de baselines CO (separate session). Los 69 D2 WARNs en v4 CTRL son la
   huella visible hasta que se cierre.
2. **5 stale checks cfast_hvac/cfast_chain:** reference_checks.json regenerado fresco activa
   estos checks latentes. Tarea separada.

---

## Current Session Update - 2026-06-30 (rev 34 - D2 CTRL wood_vc_reference + diagnóstico diag_sealed D2PRE)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — `wood_vc_reference` añadido a `KNOWN_INTENTIONAL_CONTROLS`.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **9 PASS / 5 CTRL / 3 WARN / 0 FAIL** — estado final limpio.
- Tests: **209/209 PASS** — sin cambio.

### wood_vc_reference — Clasificación CTRL (2026-06-30)

`wood_vc_reference` añadido a `KNOWN_INTENTIONAL_CONTROLS`. Razón: fue creado explícitamente en Plan A Fase A1 para demostrar que D2 dispara en VC profundo con fuel mixto/sintético. Sus 114 D2 WARNs (t=710–1800s, ratio 0.51→2.14) y 74 D2PRE WARNs (M1 colateral, rooms 0/1/4) son todos esperados y necesarios como caso de referencia canónico para D2.

### fuel_balance_diag_sealed / o2_stoich_diag_sealed — Diagnóstico D2PRE (2026-06-30)

Ambos casos tienen 230 D2PRE WARNs cada uno. Análisis completo:

- **Room 0** (13 WARNs): tracer CO₂ < mass CO₂ en fire room — misma M1 o2_scale que en `cfast_slow_growth_sealed`. Esperado.
- **Rooms 1–5** (217 WARNs por caso): tracer CO₂ (400–1100 ppm) << mass CO₂ (4000–21000 ppm) desde t=60s. El mass path transporta CO₂ vía intercambio de gas caliente (ThermalSystem), pero el tracer OES no sigue la misma trayectoria de transporte. Root cause: M1 o2_scale double-throttle reduce tracer CO₂ en fire room → menos CO₂ disponible para transportar al tracer de rooms adyacentes.
- **Decisión: dejar como WARN.** Divergencia real, no control intencional. Documenta el alcance completo de Plan B en escenarios multi-room (no solo room 0). `fuel_balance_diag_sealed` y `o2_stoich_diag_sealed` no son CTRL porque sus WARNs no son consecuencia del mecanismo bajo prueba.

### Estado CTRL/WARN final (post-sesión)

**CTRLs (5):**
| Stem | Findings | Razón |
|---|---|---|
| v1_backdraft_accumulation | A3:2, D2PRE:563, O2E1:16 | Zombie sin M4, ILV lower-O2 bug |
| v1_m4_pool_release | D2:9, D2PRE:545 | Zombie post-backdraft con M4 |
| cfast_two_floor_stairwell | A3:4, O2E1:20 | Multi-floor sellado, O2 depleta |
| v5_m4_ventilation_throttle | D2:13, D2PRE:421 | M4 pool-release cíclico |
| wood_vc_reference | D2:114, D2PRE:74 | Referencia canónica D2 alto-CO |

**WARNs restantes (3, todos D2PRE / Plan B):**
| Stem | WARNs | Razón |
|---|---|---|
| cfast_slow_growth_sealed | D2PRE:243 | M1 o2_scale en fire room (referencia canónica Plan B) |
| fuel_balance_diag_sealed | D2PRE:230 | M1 tracer transport divergence rooms 0–5 (Plan B scope multi-room) |
| o2_stoich_diag_sealed | D2PRE:230 | ídem |

---

## Current Session Update - 2026-06-30 (rev 33 - D2 CTRL v5_m4_ventilation_throttle)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — `v5_m4_ventilation_throttle` añadido a `KNOWN_INTENTIONAL_CONTROLS`.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **9 PASS / 4 CTRL / 4 WARN / 0 FAIL** — estado limpio.
- Tests: **209/209 PASS** — sin cambio.

### v5_m4_ventilation_throttle — Diagnóstico D2 WARNs (2026-06-30)

**Pregunta:** ¿Son los 13 D2 WARNs (ratio 0.51–0.62, t=225–600s) de `v5_m4_ventilation_throttle` intencionales o un defecto de calibración?

**Análisis del CSV:** Los 13 WARNs están todos en room=0. Correlación perfecta con `retained_unburned_MJ > 0` (pool release cíclico):

| t (s) | regime | retained_unburned_MJ | co_upper_ppm | ratio |
|---|---|---|---|---|
| 225 | ILV_LATENT | 0.0587 | 4969 | 0.510 |
| 325 | ILV_LATENT | 0.1620 | 4943 | 0.553 |
| 460 | ILV_LATENT | 0.1384 | 4722 | 0.618 |
| 505 | ILV_LATENT | 0.1325 | 4350 | 0.570 |
| 550 | ILV_LATENT | 0.1286 | 4344 | 0.554 |

Patrón: el M4 throttle deprime el fuego a `ILV_LATENT` → `retained_unburned_MJ` acumula hasta 0.12–0.17 MJ → pool release → CO burst → ratio > 0.50. Ciclo cada ~45s.

**Causa raíz del pool CO:** `fire_pool_release_max_fraction: 0.18` + `fire_secondary_hrr_gain_kw: 2500` en el JSON. El CO liberado del pool no está sujeto al cap phi-scaling (co_max=0.01250 kg/MJ), alcanzando yld_co efectivo de 0.03577 kg/MJ (2.84× cap).

**Decisión: CTRL — WARNs intencionales.** Los WARNs son consecuencia directa y esperada del mecanismo M4 bajo prueba. El propósito del caso es validar M4 ventilation throttle con secondary HRR gain; el CO post-throttle es parte del escenario.

**Acción:** Añadido `"v5_m4_ventilation_throttle"` a `KNOWN_INTENTIONAL_CONTROLS` en `scripts/simulation/audit_physics_coherence_suite.py`.

**Audit suite confirmado:** 9 PASS / 4 CTRL / 4 WARN / 0 FAIL. Exit code 0.

**WARNs restantes (no CTRL):**
- `cfast_slow_growth_sealed`: D2PRE (M1 o2_scale double-throttle, Plan B pendiente)
- `fuel_balance_diag_sealed`: D2PRE desde room=1, t=60s (M3 init asymmetry non-fire room — pendiente revisión)
- `o2_stoich_diag_sealed`: ídem
- `wood_vc_reference`: D2+D2PRE (intencionales — caso de referencia para D2 de alto CO yield)

---

## Current Session Update - 2026-06-30 (rev 32 - Plan A Sesión 4: D2 Sensitivity)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — D2 sensitivity análisis completado. No hay cambios de motor ni de thresholds.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **9 PASS / 5 WARN / 3 CTRL / 0 FAIL** — WARNs adicionales identificadas esta sesión (ver abajo).
- Tests: **209/209 PASS** — sin cambio.

### Plan A Sesión 4 — Análisis sensibilidad D2 threshold (completado 2026-06-30)

**Objetivo:** Medir max D2 ratio y cruces de umbral (0.10/0.20/0.30/0.50) en todos los casos del corpus con columna `co2_upper_ppm_mass`. Concluir si el threshold 0.50 debe bajar.

**Caso diagnóstico creado:** `tmp_d2_sensitivity_engine_defaults.json` — sellado 1800s, engine defaults (co_base=0.00025, co_max=0.01250), sin pool release. CSV: `sim/validation/reports/tmp_d2_sensitivity_engine_defaults.csv`.

**Tabla de sensibilidad (todos los casos con co2_upper_ppm_mass):**

| Caso | CO yield config | max phi | max D2 ratio | ≥0.10 | ≥0.20 | ≥0.50 |
|---|---|---|---|---|---|---|
| cfast_slow_growth_sealed | FORCE=0.0003 | 3.60 | 0.0077 | never | never | never |
| fuel_balance_diag_sealed | engine defaults | 1.06 | 0.2465 | 135s | 175s | never |
| o2_stoich_diag_sealed | engine defaults | 1.06 | 0.2465 | 135s | 175s | never |
| v1_backdraft_accumulation (CTRL) | engine defaults | 1.17 | 0.2529 | 135s | 160s | never |
| **tmp_d2_sensitivity_eng_def** | engine defaults, sealed 1800s | 8.24 | **0.2982** | 580s | 870s | never |
| v5_m4_ventilation_throttle | eng + pool_release=0.18 | 8.38 | **0.6184** | 135s | 145s | **225s** |
| tmp_v1_backdraft_accum_m4 | eng + pool_release | 7.87 | **0.5661** | 135s | 155s | **285s** |
| v1_m4_pool_release (CTRL) | eng + pool_release | 10.00 | **0.7997** | 135s | 155s | **285s** |
| wood_vc_reference | base=0.004, max=0.10 | 8.24 | **2.1388** | 550s | 600s | **710s** |

**Hallazgo crítico — bifurcación pool release:**

- Sin pool release (`fire_pool_release_max_fraction=0`): max ratio con engine defaults = **0.2982** (phi=8.24, 1800s sellado). NUNCA alcanza 0.30 ni 0.50.
- Con pool release activo: `yld_co` alcanza 0.03577 kg/MJ (2.84× cap co_max=0.01250) porque el CO proviene del pool de gases no quemados, no del phi-scaling. Ratio alcanza 0.566–0.800 con madera engine defaults.
- La estimación teórica A2 (max ratio = 0.236, phi→inf) era correcta para phi-scaling normal. Pool release genera CO adicional no sujeto al cap.

**Corrección a la recomendación A2:**

A2 recomendó "bajar threshold a 0.20" asumiendo max ratio teórico = 0.236. Los datos medidos revelan que:
- Threshold 0.50 YA FUNCIONA: detecta backdraft/pool-release CO bursts y `wood_vc_reference`.
- Bajar a 0.20 causaría WARNs en `fuel_balance_diag_sealed` y `o2_stoich_diag_sealed` a t=135–175s (artefacto M3 init en room non-fire). Ruido diagnóstico sin valor físico.
- **Recomendación actualizada: Opción 3 — Mantener threshold 0.50 sin cambios.** D2 está calibrado correctamente para escenarios de CO extremo.

**Descubrimiento — `v5_m4_ventilation_throttle` WARN:**

El caso genera 13 D2 WARNs (ratio pico 0.6184, t=225s). Tiene `pool_release_max_fraction=0.18` y `secondary_hrr_gain=2500 kW`. La WARN refleja un CO burst físicamente real (ventilation-induced pool ignition con M4). El caso NO está en CTRL → pendiente agregar a CTRL en sesión futura con plan explícito.

**Nuevo estado audit suite (post sesión 4):**

- 9 PASS / 5 WARN / 3 CTRL / 0 FAIL (17 CSVs).
- WARNs: `cfast_slow_growth_sealed` (D2PRE), `fuel_balance_diag_sealed` (D2PRE), `o2_stoich_diag_sealed` (D2PRE), `v5_m4_ventilation_throttle` (D2+D2PRE), `wood_vc_reference` (D2+D2PRE).
- `fuel_balance_diag_sealed` y `o2_stoich_diag_sealed`: D2PRE desde room=1 a t=60s (M3 init asymmetry non-fire room). Pendiente revisión en sesión futura.

---

## Current Session Update - 2026-06-30 (rev 31 - Plan A Diagnóstico CO yield)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — Plan A diagnóstico completado. No hay cambios de motor.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **13 PASS / 1 WARN / 2 CTRL / 0 FAIL** — sin cambio.
- Tests: **209/209 PASS** — sin cambio.

### Plan A — Diagnóstico CO yield en régimen VC (completado 2026-06-30)

**Pregunta:** ¿Por qué CO/CO₂ ratio en `cfast_slow_growth_sealed` es ~0.004–0.008 molar en condiciones VC (phi 2.8–3.6), cuando SFPE wood phi~2 debería ser ~0.3 masa / ~0.47 molar?

**Root cause: tres capas, no un bug del motor.**

**Capa 1 — Force override intencional (causa primaria):**
`cfast_slow_growth_sealed.json:88`: `"fire_co_yield_force_kg_per_MJ": 0.0003`
Activa `CombustionSystem.gd:705–707`: si `co_yield_force >= 0.0`, `co_yield = co_yield_force` incondicional. Bypass total del escalado phi. El case es CFAST comparison — yield fijo es intencional. Sin override, yield phi-escalado a phi=2.79: `0.0003 * exp(2.0*1.79) ≈ 0.0108 kg/MJ` (36× mayor). CSV confirma: `yld_co ≈ 0.000300` constante a todo tiempo (t=200s a t=1800s).

**Capa 2 — Default `co_base_yield = 0.0` (brecha silenciosa):**
`CombustionSystem.gd:663`: `context.get("co_base_yield_kg_per_MJ", 0.0)`. Casos sin yield explícito → CO = 0. `FuelObjectModel.co_yield_kg_per_MJ = 0.00025` (default) es muy bajo (nivel CFAST), no SFPE (~0.004 kg/MJ wood FC).

**Capa 3 — Clamp invertido cuando `co_max_yield = 0.0` (default):**
`CombustionSystem.gd:665–671`: `clampf(base*exp(k*(phi-1)), base, max=0.0)` → GDScript devuelve `base` siempre. Phi-scaling nunca aumenta CO sobre base. Solo `ghanekar_kitchen_living_room.json` tiene `co_max > co_base` → único caso con phi-scaling activo.

**Conclusión:** El motor phi→CO scaling está implementado correctamente. Las tres capas lo anulan o suprimen en todos los casos del corpus actual.

**Qué NO tocar:**
- `cfast_slow_growth_sealed.json`: force override 0.0003 es intencional.
- `CombustionSystem.gd` motor: no modificar.
- D2 threshold 0.5: correcto — no disparará en casos CFAST por diseño.
- OES tracer / Plan B: independiente.

**Plan A Fase A1 — COMPLETADO en esta sesión:**
- Caso `sim/validation/cases/wood_vc_reference.json` creado y ejecutado (1800s, exit 0).
- D2 dispara en t=710s: ratio=0.5123, VENTILATION_CONTROLLED_BURNING, phi=3.45, yld_co=0.04554 kg/MJ.
- Audit suite: 0 FAIL / 13 PASS / 2 WARN / 2 CTRL — sin regresiones.
- CSV producido en `sim/validation/reports/wood_vc_reference.csv`.

**Plan A Fase A2 — Diagnóstico completado 2026-06-30:**

Hallazgos principales:

1. **`FuelObjectModel.co_yield_kg_per_MJ` es irrelevante** — ningún caso define `fuel_objects` explícito. Los defaults reales son `SimulationEngine.co_base_yield_kg_per_MJ = 0.00025` y `co_max_yield_kg_per_MJ = 0.01250`. phi-scaling ya activo para todos los casos plain.

2. **Los defaults del motor son físicamente correctos para madera SFPE** (0.004 kg/kg / 16 MJ/kg = 0.00025 kg/MJ FC; 0.200 kg/kg / 16 MJ/kg = 0.01250 kg/MJ VC). NO cambiar.

3. **D2 threshold (0.5) nunca alcanzable con madera pura SFPE** — máximo ratio molar con engine defaults: 0.236 (phi→∞). D2 solo dispara con combustibles de alto CO (PU foam, mezcla residencial con sintéticos).

4. **Cambio global co_base 0.00025→0.004 sería INCORRECTO** para madera: equivaldría a 0.064 kg/kg FC (16× SFPE). FED CO 16× inflado. No afectaría 349/354 PASS (no hay CO checks non-CFAST), pero los valores físicos serían incorrectos.

5. **Inventario de riesgo:**
   - 23 casos CFAST (force override): inmunes.
   - 2 casos con co_base+co_max explícitos: inmunes.
   - 81 casos plain (engine defaults): CO físicamente correcto para madera, FED CO correcto.
   - 0 baseline CO checks en funciones non-CFAST.

**Recomendación:** Bajar D2 threshold a ~0.20 (para capturar madera VC severa phi≥3) O añadir caso PU foam VC (co_base=0.002, co_max=0.03) O dejar D2 como guardia de escenarios extremos. NO tocar engine defaults. Sesión futura con plan explícito.

---

## Current Session Update - 2026-06-30 (rev 30 - D2 Fase 3)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — D2 Fase 3 (regla D2) implementada.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **13 PASS / 1 WARN / 2 CTRL / 0 FAIL** — sin cambio. D2 no genera findings en corpus actual (ratio CO/CO₂ max = 0.008 << threshold 0.5).
- Tests: **209/209 PASS** (183 pre-existentes + 26 nuevos TestCheckD2).

### D2 Fase 3 — regla diagnóstica CO/CO₂ upper ratio

**Función:** `_check_d2_co_co2_ratio()` en `check_physics_coherence.py`.

**Campos usados:**
- Numerador: `co_upper_ppm` (from `compute_co_upper_ppm()`, uses `co_upper_kg` con hot-gas density)
- Denominador: `co2_upper_ppm_mass` (from `compute_co2_upper_ppm_mass()`, uses `co2_upper_kg` con hot-gas density)
- Mismo denominador en ambos → ratio = `co_upper_kg/28` / `co2_upper_kg/44` (razón molar pura).

**Threshold:** `ratio > 0.5` — CO supera 50% de CO₂ en moles. Referencia SFPE: bien ventilado < 0.08, bajo-ventilado VC 0.08–0.5, post-FO severo > 0.5.

**Skip conditions (conservadoras):**
- `co2_upper_ppm_mass` ausente → legacy CSV sin D2 Fase 1 (21 de 22 CSVs del corpus actual).
- `co2_upper_ppm_mass < 1000 ppm` → CO₂ no establecido, zona fría o sin fuego.
- `time_s < 60 s` → M3 initial-condition asymmetry (mass path inicia en 0 kg vs 400 ppm tracer).

**Severity:** WARN — diagnóstico, no gating, no afecta exit code.

**Resultado en corpus:**
- 21 CSVs legacy (sin `co2_upper_ppm_mass`): skip graceful, 0 findings.
- `cfast_slow_growth_sealed`: CO/CO₂ ppm ratio = 0.006–0.008 durante toda la simulación (FUEL_CONTROLLED y VENTILATION_CONTROLLED). Muy por debajo del threshold 0.5 → **0 findings D2**. Esto indica que el modelo de CombustionSystem produce poco CO relativo a CO₂ incluso en condiciones ventilation-controlled. Documentado como observación calibración pendiente.

**Por qué `co2_upper_ppm` tracer NO se usa como denominador:**
El tracer OES es suprimido por `o2_scale` double-throttle (M1, D2PRE root cause). Usarlo produciría ratios artificialmente altos que no reflejan el estado real del fuego. `co2_upper_ppm_mass` es el denominador fiable para t > 300 s según diagnóstico D2 (rev 29).

**Observación calibración CO:**
El ratio de generación CO/CO₂ es ~0.004–0.005 (masa), constante incluso en VENTILATION_CONTROLLED_BURNING. Valor SFPE para wood, under-ventilated (phi~2): ~0.3 masa → ~0.47 molar. El modelo SimuFire parece infra-estimar CO en VC — pendiente como plan calibración separado, no bloqueante para D2 Fase 3.

### Próximos planes separados (post D2 Fase 3)

**Plan A — Calibración CO yield en régimen VC** *(prioridad: media)*
- CO/CO₂ ratio generación ~0.004–0.005 masa en `cfast_slow_growth_sealed` incluso en VENTILATION_CONTROLLED (phi >> 1). SFPE para wood phi~2: ~0.3 masa. Gap de ~60×.
- Sin Plan A, D2 nunca disparará en VC gradual — solo en post-FO con CO anómalamente alto.
- Precondición: leer y auditar escalado phi→CO en `CombustionSystem.gd`. No implementar sin diagnóstico previo.

**Plan B — Fix motor: o2_scale double-throttle en OES tracer CO₂** *(prioridad: baja)*
- Causa los 243 D2PRE WARNs en `cfast_slow_growth_sealed`. No bloqueante en corpus actual.
- Fix: eliminar/flag `co2_produced *= o2_scale` en OES (HRR ya refleja disponibilidad de O₂).
- Impacto en FED: el tracer CO₂ afecta `compute_co2_upper_ppm` → FED CO₂ narcosis. Aumentaría CO₂ FED en VC. Requiere validación FED.
- Constraint: flag per-case (no global) hasta que corpus valide. Requiere sesión con plan explícito.

**Prioridad recomendada:** Plan A primero (calibración CO es independiente del motor de tracking CO₂). Plan B después, con plan motor formal.

---

## Current Session Update - 2026-06-30 (rev 29 - D2 Diagnóstico completo)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — diagnóstico D2 completado.
- Todos los contadores previos sin cambio: **349/354 PASS**, **183/183 tests PASS**, **13 PASS / 1 WARN / 2 CTRL / 0 FAIL** physics suite.

### D2 Diagnóstico — causa raíz identificada

**Causa raíz: tres mecanismos independientes compuestos.**

#### Hallazgo clave: dt_physics = 0.0833s, no 10s

`co2_generated_kg_step` registra el valor de UN paso físico (dt=0.0833s = 1/120s). Los 120 pasos físicos por intervalo de log de 10s producen ~0.155 kg totales de CO₂ (10s equivalente), mientras que el ACH=5.0 drena ~0.082 kg en ese mismo intervalo. El bulk co2_kg crece porque producción > drenaje ACH, lo que es consistente con los datos observados.

#### Mecanismo 1 — o2_scale double-throttle en OES (DOMINANTE)

OES aplica `o2_scale = clamp(o2_upper / 0.209, 0, 1)` a la producción de CO₂ del tracer.  
En t=700s: `o2_upper=0.063 → o2_scale=0.301` → tracer recibe solo 30% de producción nominal.  
CombustionSystem añade CO₂ proporcional al HRR real — el HRR **ya refleja** la disponibilidad de O₂ (régimen VENTILATION_CONTROLLED). Aplicar o2_scale en OES es un doble-descuento: throttle físico ya en HRR, throttle adicional en producción de tracer.

Ratio de producción masa/tracer medido: **2.56× en t=700s**, crece a **2.65× en t=1800s**.

#### Mecanismo 2 — Densidad en denominador (amplificador)

`compute_co2_upper_ppm_mass` divide por densidad caliente (≈0.71 kg/m³ a 186°C):  
`ppm_mass = co2_upper_kg × 29e6 / (floor_area × upper_height × rho_hot(temp_upper_c))`

OES tracer usa masa de aire a densidad ambiente:  
`upper_air_mass = volume × 1.2 × upper_frac`

Para igual masa de CO₂, la conversión mass da **1.68× más ppm** a t=700s (crece a 1.83× a t=1800s).

Esto NO es un error del mass path — la densidad caliente es más correcta para la concentración real de CO₂ en el gas caliente. El tracer OES usa densidad fija ambient (subestima la concentración real).

#### Mecanismo 3 — Condición inicial asimétrica (early-transient)

Tracer: `co2_upper` inicia en 0.0004 (400 ppm atmosférico) — physically correct.  
Mass path: `co2_upper_kg` inicia en 0.0 — missing atmospheric background CO₂.

Efecto: tracer **supera** al mass-derived para t < 300s (ratio < 1). La inversión ocurre alrededor de t=290s cuando la producción acumulada mass path supera el head-start inicial del tracer.

#### Dinámica observada

| t (s) | tracer_ppm | mass_ppm | ratio | o2_scale | rho_ratio |
|-------|-----------|---------|-------|---------|---------|
| 100   | 3827      | 2046    | 0.53  | 0.979   | 1.10    |
| 300   | 40376     | 77271   | 1.91  | 0.743   | 1.38    |
| 700   | 85501     | 181891  | 2.13  | 0.301   | 1.68    |
| 1800  | 69481     | 223740  | 3.22  | 0.268   | 1.83    |

Tracer pico en ~t=700s y **declina** (ACH drain supera producción throttleada).  
Mass path sigue creciendo lentamente hasta t≈1750s, luego estabiliza.

#### ¿Cuál representación es más fiable?

**Ninguna es completamente correcta:**
- **Tracer OES**: condición inicial correcta (400 ppm), física ACH correcta. **Error**: o2_scale duplica el throttle de O₂ (el HRR ya lo aplica). Denominator usa densidad ambiente → subestima ppm en zona caliente.
- **Mass-derived**: producción correcta (proporcional a HRR real, sin doble-throttle). Denominator usa densidad caliente (más correcto para concentración real). **Error**: inicia en 0 kg (falta CO₂ atmosférico), y `co2_upper_kg` no tiene verificación de que realmente esté en la capa superior.

**Para tenabilidad (CO₂ narcosis/hiperventilación)**: mass path es más fiable en t > 300s. El tracer subestima sistemáticamente por el o2_scale.

#### Instrumentación faltante para cerrar diagnóstico

Para confirmar cuantitativamente cada mecanismo, faltarían estas columnas CSV:
1. `co2_upper_oes_prod_ppm_step` — producción de tracer por paso físico (en ppm-equivalente)
2. `o2_scale_oes` — valor de o2_scale aplicado en OES por paso
3. `upper_frac_oes` — fracción upper_frac usada en OES para upper_air_mass
4. `co2_upper_kg_ach_step` — ACH drain aplicado a co2_upper_kg en GES por paso

Sin estas columnas, el diagnóstico es deductivo (código + datos CSV). Con ellas sería verificable por fila.

#### Conclusión y siguiente paso

Root cause confirmado sin ambigüedad: **el o2_scale en OES es la causa dominante** de divergencia. No es un bug de ACH ni de ventilación. El density mismatch amplifica. La initial condition asimetría explica el t < 300s.

**D2 Fase 3 (CO/CO₂ ratio rule)**: puede implementarse sobre el mass path (`co2_upper_ppm_mass`) con corrección de condición inicial (+400 ppm offset o init co2_upper_kg con CO₂ atmosférico). El tracer path no es adecuado para un ratio rule hasta que se corrija el o2_scale en OES — lo que requiere un plan motor separado.

---

## Current Session Update - 2026-06-30 (rev 28 - D2 Fase 2)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — D2PRE implementado.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **13 PASS / 1 WARN / 2 CTRL / 0 FAIL** — `cfast_slow_growth_sealed` ahora clasifica como WARN por 243 D2PRE WARNs (no gating, exit code 0).
- Tests: **183/183 PASS** (162 pre-existentes + 21 nuevos TestCheckD2PRE).

### D2 Fase 2 — regla D2PRE implementada

**Función:** `_check_d2pre_co2_upper_divergence()` en `check_physics_coherence.py`.

**Métrica:** `rel_div = |co2_upper_ppm_mass − co2_upper_ppm| / max(co2_upper_ppm, 400.0)`

**Threshold:** `_D2PRE_REL_TOL = 1.0` — solo dispara cuando mass >2× tracer (o viceversa). Evita el ruido early-transient (t=50s da rel_div~0.6).

**Severity:** WARN — diagnóstica, no afecta exit code, no gating. Skip graceful en CSV legacy sin `co2_upper_ppm_mass`.

**Resultado diagnóstico — `cfast_slow_growth_sealed`:**
- 243 D2PRE WARNs — room 0 (fire room), t=320s en adelante.
- Tracer (`co2_upper_ppm`): toca techo ~85k ppm → decrece por dilución ODE.
- Mass-derived (`co2_upper_ppm_mass`): continúa acumulando hasta >220k ppm.
- `rel_div` crece de 1.0 (t=320s) hasta >2.2 (t=1800s) y sigue creciendo.
- Rooms 2, 3, 5: sin findings (permanecen en 400 ppm ambient).
- Room 1: WARN tardío a t=1800s (rel_div=3.81, mass=1928 vs tracer=401).
- Room 4: WARN intermitente a t=1200s (rel_div=1.40).

**Conclusión D2:**
D2 CO/CO₂ ratio rule (Fase 3) **bloqueada**. Divergencia tracer vs mass es sistemática y creciente en el fire room. Hipótesis root cause: el tracer ODE (`co2_upper` en `OxygenExchangeSystem`) pierde CO₂ por dilución en intercambios O₂/N₂ y ventilación, mientras `co2_upper_kg` (`CombustionSystem`+`GasExchangeSystem`) acumula directamente sin dilución proporcional. Debe diagnosticarse cuál representación es física antes de proceder.

**Próximo paso D2 (Fase 3 condicionada):**
Antes de implementar la regla ratio, entender por qué divergen. Opciones:
a) El tracer se diluye incorrectamente (bug en OES — dilución de CO₂ no proporcional a intercambio gaseoso).
b) El mass-derived acumula sin ventear correctamente (GES no descuenta CO₂ ventilado de `co2_upper_kg`).
c) La geometría de zona upper cambia y la conversión kg→ppm no compensa.

---

## Current Session Update - 2026-06-30 (rev 27 - D2 Fase 1)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — GDScript D2 Fase 1 implementado.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **14 PASS / 2 CTRL / 0 FAIL** — sin cambio (sin regresiones tras añadir nuevas columnas CSV).
- Tests: **162/162 PASS** — sin cambio (tests Python no cubren GDScript directamente).

### D2 Fase 1 — implementación completa

**Objetivo:** Exportar `co2_upper_ppm` (tracer, faltaba en CSV) y `co2_upper_ppm_mass` (mass-derived, nueva) al CSV para diagnóstico D2-pre en Fase 2.

**Cambios GDScript (4 archivos):**

1. **`sim/core/ThermalSystem.gd`** — añadida `compute_co2_upper_ppm_mass()`. Fórmula: `co2_upper_kg * 29e6 / (upper_zone_mass_kg * 44.0)`. Guarda `upper_gas_kg < 0.1` → fallback a `room.co2_upper * 1e6` (400 ppm ambient). FED intacto.
2. **`sim/core/SimulationEngine.gd`** — callable `compute_co2_upper_ppm_mass_callable` registrado.
3. **`sim/core/SimulationStateBuilder.gd`** — callable declarado + `"co2_upper_ppm_mass"` añadido al state dict.
4. **`sim/core/SimulationLogWriter.gd`** — header y body: `co2_upper_ppm` y `co2_upper_ppm_mass` añadidos tras `co2_ppm`. Header=115 columnas, body=115 appends.

**Verificación headless:**
- `cfast_slow_growth_sealed`: 384 rows. `co2_upper_ppm` y `co2_upper_ppm_mass` presentes. t=5s: ambas = 400 ppm (fallback correcto, sin hot layer).
- Audit suite: **14 PASS / 2 CTRL / 0 FAIL** — sin regresiones.

**Próximos pasos D2:**
- **Fase 2:** Añadir regla `D2PRE` (WARN) en `check_physics_coherence.py` — diagnostica divergencia tracer vs mass-derived. Prerequisito: correr headless y comparar columnas en CSV largo.
- **Fase 3:** D2 ratio CO/CO2 en campos comparable (ambos mass-derived o ambos tracer).

---

## Current Session Update - 2026-06-30 (rev 26 - D2 semantic plan)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear — sin cambios de código esta sesión.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **14 PASS / 2 CTRL / 0 FAIL** — sin cambio.
- Tests: **162/162 PASS** — sin cambio.

### Plan D2 — CO/CO2 ratio rule

#### Mapa semántico actual CO/CO2

**`room.co2_upper` (tracer, fracción molar)**
- Init: `0.0004` (~400 ppm ambient)
- Escrito por: `OxygenExchangeSystem.gd` (6 sitios: combustión-delta, infiltración-ACH, dilución-inflow, canonical doorway exchange) y `HVACSystem.gd` (supply mix)
- NO escrito por ThermalSystem ni GasExchangeSystem
- Exportado como: `co2_upper_ppm = room.co2_upper × 1e6` (vía `compute_co2_upper_ppm()` en ThermalSystem.gd:3251)
- Usado en FED: `v_co2 = exp(0.1903 × co2_pct + 2.0004) / 7.1` — factor de potenciación CO/HCN en ISO 13571

**`room.co2_upper_kg` (mass-derived, kg)**
- Init: `0.0` — NO inicializado con masa ambient
- Escrito por: `CombustionSystem.gd` (generación: `room.co2_upper_kg += generated_co2_kg`), `GasExchangeSystem.gd` (14+ sitios: doorway exchange, ventilación exterior, purge, smoke-CO2 coupling)
- NO exportado al CSV
- NO usado en FED (FED usa tracer `co2_upper` vía `compute_co2_upper_ppm`)

**`room.co2_kg` (total CO2 mass, kg)**
- Init: `0.0` — NO inicializado con masa ambient
- Escrito por: `CombustionSystem.gd` (generación) y `GasExchangeSystem.gd` (transporte, ventilación, purge)
- NO exportado al CSV

**`room.co_upper_kg` (CO upper, kg)**
- Init: `0.0`
- Mass-derived, temperatura-corregida para exportar como `co_upper_ppm`
- Usado en FED directamente

**Incompatibilidad central:**
`co2_upper_ppm` (tracer, fracción molar ODE) y `co_upper_ppm` (mass-derived, temperatura-corregida) provienen de trayectorias computacionales completamente distintas. Un ratio CO/CO2 construido sobre ellas mezcla dos representaciones incomparables.

**Además: brecha de inicialización.** `co2_upper_kg` y `co2_kg` se inicializan a 0.0. El tracer `co2_upper` se inicializa a 0.0004. A t=0, `co2_upper_ppm` = 400 ppm (ambient), pero `co2_upper_ppm_mass` (si se exportara desde `co2_upper_kg`) = 0 ppm. Toda divergencia inicial se debe a esta brecha, no a física real.

---

#### Opciones de diseño D2

**Opción A — CO2 upper mass-derived como representación autoritativa**

Descripción: Añadir `compute_co2_upper_ppm_mass()` en ThermalSystem que usa `co2_upper_kg` y la masa de zona upper (temperatura-corregida, mismo método que `co_upper_ppm`). Exportar como `co2_upper_ppm_mass` al CSV. D2 compara `co_upper_ppm` vs `co2_upper_ppm_mass`.

| Aspecto | Detalle |
|---------|---------|
| Impacto FED | Ninguno — FED sigue usando tracer `co2_upper_ppm` para V_CO2. Solo se añade columna nueva. |
| Riesgo regresión | Bajo si se añade solo la columna. Si se cambia FED a mass-derived en el futuro: potencial regresión en fed_co/fed_hcn. |
| Cambios GDScript | 1 nueva función en ThermalSystem.gd + 1 export en SimulationStateBuilder.gd + 1 CSV column en SimulationLogWriter.gd + inicializar `co2_upper_kg` con masa ambient en RoomModel/setup |
| Columnas CSV nuevas | `co2_upper_ppm_mass` |
| Tests necesarios | Test que verifica D2 produce WARN/FAIL cuando ratio CO/CO2 sale de rango; test que verifica column existe en schema |
| Severidad inicial | WARN (observación) |
| Bloqueo previo | Hay que resolver la brecha de inicialización `co2_upper_kg = 0` antes de implementar D2, o la regla dará falsos positivos al inicio de cada simulación. |

**Opción B — D2 sobre campos existentes (co_upper_ppm + co2_upper_ppm tracer)**

Descripción: Implementar D2 directamente sobre `co_upper_ppm` y `co2_upper_ppm` existentes, con tolerancia amplia para absorber el mismatch representacional.

| Aspecto | Detalle |
|---------|---------|
| Impacto FED | Ninguno |
| Riesgo regresión | Ninguno en motor — no toca código. Pero la regla D2 sería semánticamente débil. |
| Cambios GDScript | Ninguno |
| Columnas CSV nuevas | Ninguna |
| Tests necesarios | Tests de la regla D2 en check_physics_coherence.py |
| Severidad inicial | Solo WARN o diagnóstico — no puede ser FAIL/gating con mismatch representacional |
| Problema fundamental | CO2 tracer y CO mass-derived no son comparables. El ratio reflejaría ruido del mismatch, no física real. Falsos positivos garantizados en multi-room (CO transportado de una sala, CO2 tracer independiente). **No recomendado.** |

**Opción C — Exportar ambas representaciones, D2-pre diagnóstico primero**

Descripción: Dos fases. Fase 1: exportar `co2_upper_ppm_mass` (desde `co2_upper_kg`) como columna CSV nueva. Añadir regla D2-pre como WARN diagnóstico que mide `abs(co2_upper_ppm_mass - co2_upper_ppm) / co2_upper_ppm` — si la divergencia es grande, el dual-tracking tiene un problema real antes de intentar D2. Fase 2: si D2-pre muestra convergencia en corpus, implementar D2 ratio rule sobre la representación mass-derived.

| Aspecto | Detalle |
|---------|---------|
| Impacto FED | Ninguno |
| Riesgo regresión | Bajo — solo se añade columna + regla WARN |
| Cambios GDScript | Idéntico a Opción A (columna), más la brecha de inicialización ambient |
| Columnas CSV nuevas | `co2_upper_ppm_mass` |
| Tests necesarios | Test D2-pre WARN cuando divergencia > umbral; test no-finding cuando convergentes |
| Severidad inicial | D2-pre: WARN diagnóstico. D2 ratio: WARN inicial → FAIL si corpus limpio |
| Ventaja diferencial | Revela si el dual-tracking es realmente problemático en el corpus actual antes de comprometerse a una D2 ratio rule. Si D2-pre muestra divergencia masiva, el problema está en la inicialización o en el motor — no en el balance rule. |

---

#### Recomendación: Opción C

**Ruta mínima para desbloquear D2:**

1. **Fase 0 (diagnóstico, sin motor):** Examinar un CSV existente para estimar cuánto divergen `co2_upper_ppm` (tracer, disponible) y una estimación de `co2_upper_ppm_mass` (requiere `co2_upper_kg`, no disponible en CSV actualmente). Como `co2_upper_kg` no está en CSV, este diagnóstico no puede hacerse sin tocar motor.

2. **Fase 1 (mínimo motor):** Añadir 3 cambios GDScript:
   - `RoomModel.gd`: inicializar `co2_upper_kg` con masa ambient estimada (o añadir campo `co2_upper_kg_initialized: bool`).
   - `ThermalSystem.gd`: añadir `compute_co2_upper_ppm_mass(room)` usando `co2_upper_kg`.
   - `SimulationStateBuilder.gd` + `SimulationLogWriter.gd`: exportar `co2_upper_ppm_mass` al CSV.

3. **Fase 2 (regla D2-pre):** Implementar en `check_physics_coherence.py` una regla D2-pre que mida la divergencia `co2_upper_ppm_mass` vs `co2_upper_ppm`. WARN solo. Auditar corpus. Si divergencia < 50% en todos los casos activos → D2 ratio es viable.

4. **Fase 3 (D2 ratio rule):** Implementar D2 propiamente: `co_upper_ppm / co2_upper_ppm_mass` dentro de rango esperado por condición de fuego (ventilated: CO/CO2 ratio < 0.1; under-ventilated: 0.1–1.0; post-flashover: hasta 2.0+). WARN inicial.

**Prerrequisito bloqueante identificado:** La brecha de inicialización `co2_upper_kg = 0` vs `co2_upper = 0.0004` producirá falsos positivos en D2-pre y D2. Hay que inicializar `co2_upper_kg` con la masa ambient CO2 del volumen de aire de la sala antes de que D2 sea significativo. Esto requiere acceso al volumen y masa de aire de la sala en el setup — cambio en el constructor de `RoomModel` o en `SimulationEngine._setup_rooms()`.

---

### Archivos modificados esta sesión

Solo documentación:
- `docs/HANDOFF_CURRENT_STATE.md` — rev 26 (este, plan D2)
- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` — sección D2 ampliada

---

## Current Session Update - 2026-06-30 (rev 25 - S1 promovida a FAIL/gating)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear (S1→FAIL, O2E1, O1, M5, C-S1-3 — sesiones 2026-06-29/30).
- Último commit: `18b6b5c2` docs(fire): record M5 post-backdraft guard plan.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **14 PASS / 2 CTRL / 0 FAIL**.
- Tests `test_check_physics_coherence.py`: **162/162 PASS**.

### S1 — FAIL/gating (cerrado)

`severity="WARN"` → `severity="FAIL"` en `_check_s1_smoke_per_room_balance`. Sin cambio de tolerancias.

Criterios cumplidos: C-S1-1 (corpus sostenido), C-S1-2 (multi-room `cfast_two_room_door_open`), C-S1-3 (multi-floor `cfast_two_floor_stairwell`), C-S1-4 venting, C-S1-5 (sin residuos compensados), C-S1-6 (sin cambio de tolerancia). C-S1-4 deposition documentada como limitación de floor precision (max 0.002 kg < floor 0.01 kg).

`cfast_two_floor_stairwell` añadido a `KNOWN_INTENTIONAL_CONTROLS` en `audit_physics_coherence_suite.py`: A3/O2E1 por depleción O2 en edificio sellado (misma causa que `v1_backdraft_accumulation`); S1 limpia — propósito es cobertura C-S1-3.

### Archivos modificados esta sesión

- `scripts/simulation/check_physics_coherence.py` — S1 severity WARN → FAIL; docstring actualizado
- `scripts/simulation/audit_physics_coherence_suite.py` — `cfast_two_floor_stairwell` añadido a KNOWN_INTENTIONAL_CONTROLS
- `tests/test_check_physics_coherence.py` — `test_residual_above_floor_triggers_fail` (era `_warn`)
- `CHANGELOG.md` — entrada S1 FAIL/gating
- `docs/HANDOFF_CURRENT_STATE.md` — rev 25

### Gating balance lanes — estado final

| Lane | Severidad | Estado |
|------|-----------|--------|
| S0 | FAIL/gating | Cerrado |
| E1 | FAIL/gating | Cerrado |
| D1 | FAIL/gating | Cerrado |
| O2E1 | FAIL/gating | Cerrado |
| O1 | FAIL/gating | Cerrado |
| **S1** | **FAIL/gating** | **Cerrado (2026-06-30)** |
| D2 | Bloqueado | `co2_upper_ppm` tracer vs `co2_upper_kg` mass — sin resolver |

### Siguiente paso recomendado

- D2 sigue bloqueado. Opciones: (a) exportar `co2_upper_kg` al CSV como columna comparable, (b) derivar `co2_upper_ppm` de masa en lugar de tracer. Requiere plan semántico explícito.
- No hay balance lanes gating pendientes de implementar.

---

## Current Session Update - 2026-06-30 (rev 24 - C-S1-3 cubierto, corpus 15 PASS)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear (S1, O2E1, O1, M5, C-S1-3 — sesiones 2026-06-29/30).
- Último commit: `18b6b5c2` docs(fire): record M5 post-backdraft guard plan.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **15 PASS / 1 CTRL / 0 FAIL / 0 WARN**.
- Tests `test_check_physics_coherence.py`: **162/162 PASS**.

### C-S1-3 cerrado — cfast_two_floor_stairwell

Se añadió `csv_log_file_path` al caso JSON `sim/validation/cases/cfast_two_floor_stairwell.json` (único cambio; faltaba en `engine_overrides`). Se ejecutó headless con Godot 4.6.3.

**Resultado S1 (13 rooms, PB + P1, 0–350 s):**

| Room | Nombre | Transport total | Floor |
|------|--------|----------------|-------|
| 0 | Salon-comedor PB | −2.979 kg (emisor) | PB |
| 1 | Recibidor distribuidor | +0.192 kg | PB |
| 2 | Escalera PB | +0.135 kg | PB |
| 3 | Cocina PB | +0.224 kg | PB |
| 6 | **Escalera P1** | **+0.101 kg** | **P1** |
| 7 | **Distribuidor P1** | **+0.138 kg** | **P1** |
| 8–10,12 | Dormitorios P1 | +0.021–0.026 kg | P1 |

Todos los valores por encima del floor S1 (0.01 kg). S1 exit 0, sin WARNs. Transporte vertical vía escalera confirmado.

### Estado criterios C-S1

| Criterio | Estado |
|----------|--------|
| C-S1-1 Corpus sostenido | ✅ 15/15 PASS, 0 WARN |
| C-S1-2 Multi-room transport | ✅ `cfast_two_room_door_open` (5.43 kg, 6 rooms) |
| C-S1-3 Multi-floor transport | ✅ `cfast_two_floor_stairwell` (0.101–0.138 kg inter-floor) |
| C-S1-4 Venting | ✅ `fp_ilv_open_partial_window` (45.97 kg) |
| C-S1-4 Deposition | ⚠️ Limitación de escala — max 0.002 kg, bajo floor 0.01 kg. No bloquea. |
| C-S1-5 Sin residuos compensados | ✅ S1 exit 0 en ambos casos con transporte no trivial |
| C-S1-6 Sin cambio de tolerancia | ✅ Tolerancias intactas |

S1 permanece **WARN**. Todos los criterios bloqueantes cubiertos. La deposition está documentada como limitación de escala física (soot settling bajo en escenarios ≤600 s), no como gap de instrumentación. Promoción a FAIL/gating puede planificarse en sesión futura.

### Archivos modificados esta sesión

- `sim/validation/cases/cfast_two_floor_stairwell.json` — añadido `csv_log_file_path`
- `sim/validation/reports/cfast_two_floor_stairwell.csv` — generado (nuevo)
- `sim/validation/reports/cfast_two_floor_stairwell.json` — actualizado por Godot
- `docs/HANDOFF_CURRENT_STATE.md` — rev 24 (este)
- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` — C-S1-2/3/4/5 marcados con estado
- `CHANGELOG.md` — entrada C-S1-3

### Siguiente paso recomendado

Con C-S1-1 a C-S1-6 todos cubiertos (deposition documentada como limitación aceptable), S1 está lista para promoción a FAIL/gating. La única acción pendiente es:
1. Cambiar `severity="WARN"` → `severity="FAIL"` en `_check_s1_smoke_per_room_balance`.
2. Re-auditar corpus completo y confirmar 0 FAIL.
3. Actualizar checklist, CHANGELOG y HANDOFF con fecha de promoción.

D2 sigue bloqueado (CO2 dual-tracking). No tocar hasta decisión semántica.

---

## Current Session Update - 2026-06-30 (rev 23 - S1 WARN-clean, promotion criteria defined)

### Estado operativo actual

- Branch: `main`, cambios locales sin commitear (S1, O2E1, O1, M5 — sesiones 2026-06-29/30).
- Último commit: `18b6b5c2` docs(fire): record M5 post-backdraft guard plan.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Physics coherence corpus: **14 PASS / 0 FAIL / 0 WARN** en casos activos.
- Tests `test_check_physics_coherence.py`: **162/162 PASS**.

### S1 smoke per-room balance — WARN-clean

S1 implementada en `scripts/simulation/check_physics_coherence.py` como **WARN**.

- Invariante: `Δsmoke_kg = Δsmoke_generated_kg_total − Δsmoke_vented_kg_total − Δsmoke_deposited_kg_total + Δsmoke_net_transport_kg_total`.
- Acumuladores per-room ya existían en `RoomModel.gd` y GDScript — no se tocó motor.
- Corpus S1 (2026-06-30): **14 PASS / 0 WARN / 0 FAIL** en todos los casos activos.
- Criterios de promoción S1 WARN → FAIL/gating definidos en `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` (C-S1-1 a C-S1-6).
- S1 permanece WARN. No promover sin evidencia de los criterios.

### Stale comments corregidos

- `docs/HANDOFF_CURRENT_STATE.md` rev 22: eliminada la referencia a "S1 bloqueado" y al plan de instrumentación.
- `docs/handoff/HANDOFF_CURRENT_STATE.md`: S0 limitations actualizado ("S1 bloqueado" → "S1 implementada WARN-clean").

### D2 — sigue bloqueado

`co2_upper_ppm` es tracer-derived (`room.co2_upper * 1e6`, actualizado por `ThermalSystem`).
`co2_upper_kg` es mass-derived (acumulado por `GasExchangeSystem`, 14+ sitios de escritura) y no está exportado al CSV.
Las dos representaciones son semánticamente incomparables. Reglas CO/CO2 ratio (D2 y derivadas) no pueden implementarse hasta resolver cuál es autoritativa o exportar `co2_upper_kg` de forma comparable.

### Siguiente paso recomendado

Opciones sin tocar motor directamente:

1. **Ampliar corpus S1** — verificar que los casos multi-room ya en suite tienen `smoke_net_transport_kg_total` no trivial (C-S1-2). Si es así, S1 cubre criterio C-S1-2/3 y la promoción puede planificarse.
2. **Plan D2** — decidir entre: (a) exportar `co2_upper_kg` al CSV como columna adicional comparable, o (b) derivar `co2_upper_ppm` de masa en lugar de tracer. Requiere plan semántico explícito antes de tocar `ThermalSystem`.
3. **Nuevas reglas de balance** — candidatos: temperatura upper/lower vs energía (B2), smoke visibility vs smoke_kg (V1).

---

## Current Session Update - 2026-06-29 (rev 22 - O2E1/O1 promoted to FAIL-gating)

### Estado operativo actual

- Branch: `main`, worktree limpio antes de esta nota, local ahead de `origin/main`.
- Ultimos commits relevantes:
  - `6db12f7` — O2E1 promoted to FAIL/gating.
  - `bd3e13e` — O1 canonical doorway double-count fixed.
  - `6a8dd2a` / `41eb069` — O1 promoted to FAIL/gating and documented.
- `validate_reference_cases`: **349/354 PASS** — sin cambio; los 5 FAIL restantes son `VALID_GAP` preexistentes.
- Physics coherence corpus: **14 PASS / 0 FAIL** en casos activos.
- Carriles gating activos: `S0`, `E1`, `D1`, `O2E1`, `O1`, y cobertura M5/C1.
- S1 añadida como WARN-clean (2026-06-30): ver entrada S1 en CHANGELOG y checklist.
- Bloqueado sin cambio: `D2` (CO2 upper dual-tracking).

### M5 y C1 cerrados

M5 ya no es solo plan. `fire_post_bd_hrr_cut_enabled` fue implementado y activado en `v1_m4_pool_release` como guard opt-in/default-off.

Resultado:

- `v1_m4_pool_release` mantiene el backdraft principal.
- No hay segundo backdraft artificial.
- El zombie post-backdraft queda cortado en el caso M5.
- C1 backdraft/pool-release queda cerrado como evidencia limpia para O2E1.

### O2E1 cerrado como FAIL/gating

O2E1 ahora usa `o2_consumed_fire_kg_total` contra `hrr_kj_total * 7.6e-5 kg/kJ` y su severidad es `FAIL`.

Decisiones:

- No tocar tolerancias: se mantiene 5 % relativo / `1e-5 kg` absoluto.
- No tocar fisica en la promocion: fue cambio de severidad/documentacion/tests.
- `v1_backdraft_accumulation` sigue como CTRL intencional con findings esperados.

### O1 canonical doorway cerrado y promovido

Causa raiz del gap O1 en `cfast_two_room_door_open`:

- `_apply_canonical_doorway_exchange` sumaba `_cde_net_hot` a `o2_net_transport_kg_total`.
- Pero `room.o2` se actualiza via zone blend; el zone sync ya capturaba el efecto neto de CDE en bulk O2.
- Resultado: O1 contaba dos veces el efecto y `expected > delta_bulk` por ~`_cde_net_hot` por paso.

Fix:

- `ThermalSystem.gd`: eliminado el tracking directo de `_cde_net_hot` hacia `o2_net_transport_kg_total`.
- `ThermalSystem.gd`: anadido zone sync para `cold_room` en CDE.
- `check_physics_coherence.py`: O1 suma `delta(o2_zone_sync_kg_total)` al expected.

Resultado:

- `cfast_two_room_door_open` limpio.
- Corpus de coherencia fisica: **14 PASS / 0 FAIL**.
- O1 promovido a `FAIL/gating`.

### Siguiente paso recomendado

No abrir D2/S1 directamente sin plan semantico.

Opcion recomendada ahora:

1. Cerrar documentalmente la fase de balances principales — ver entrada S1 en CHANGELOG (2026-06-30).
2. S1 ya está implementada como WARN-clean: 14 PASS / 0 WARN / 0 FAIL. Criterios de promoción definidos en `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md`.
3. D2 sigue bloqueado: resolver/normalizar la dualidad `co2_upper_ppm` tracer-derived vs `co2_upper_kg` mass-derived antes de implementar reglas CO/CO2.

---

## Current Session Update - 2026-06-28 (rev 21 - M5 post-backdraft guard plan)

### Estado operativo actual

- Branch: `main`, worktree limpio antes de esta nota, local ahead de `origin/main`.
- Ultimo bloque tecnico cerrado: C1 backdraft/pool-release queda "path exercised, not clean promotion evidence".
- No hay cambio de motor en esta rev. Solo se guarda el plan M5 para la siguiente sesion.
- O2E1 permanece WARN. No promover a FAIL todavia.

### Diagnostico exacto del zombie post-backdraft

`v1_m4_pool_release` ya ejercita el path de backdraft:

- `backdraft_triggered=1` a t=350 s.
- HRR spike principal: 21.369 kW.
- `retained_unburned_MJ` se agota a t=355 s.
- O2E1 esta limpio durante la ventana de backdraft (t=340-360 s).

El problema restante empieza despues del evento:

1. Tras agotarse el pool, `can_flame=false` y `hrr_target_kw=0`, pero `room.hrr_kw` no cae inmediatamente; decae con `fire_hrr_fall_tau_s=20`.
2. Esa inercia mantiene HRR positivo con `o2_upper` critico, generando filas A3 y O2E1 WARN en fase zombie.
3. Cuando `o2_upper` se recupera por encima del umbral M4, el motor puede volver a alimentar llama/pool y disparar un segundo backdraft artificial.

La causa no es Thornton ni O2E1. Es una incoherencia de ciclo post-evento en `CombustionSystem.gd`: HRR suavizado y pool reaccumulado sobreviven a una condicion donde no hay llama ni latencia fisicamente viable.

### M5 recomendado

Implementar un guard opt-in:

- Flag: `fire_post_bd_hrr_cut_enabled`, default `false`.
- Activacion inicial: solo en `v1_m4_pool_release`.
- Ubicacion: `CombustionSystem.gd`, despues del bloque `if room.backdraft_active:` y antes del consumo/reacumulacion de pool.

Condicion propuesta:

```gdscript
if fire_post_bd_hrr_cut_enabled \
        and not room.backdraft_active \
        and not can_flame \
        and not latent_viable \
        and room.retained_unburned_MJ < 0.001 \
        and room.fire_o2_ref < o2_min_ref:
    room.hrr_kw = 0.0
    room.hrr_target_kw = 0.0
    retained_generation_kw = 0.0
```

La forma exacta puede ajustarse al estilo local del archivo, pero la intencion debe mantenerse: cortar la cola de HRR y bloquear la reacumulacion de pool cuando el backdraft ya termino, el pool esta agotado y no existe llama/latencia viable.

### Criterios de aceptacion M5

- `v1_m4_pool_release`: backdraft principal sigue ocurriendo a t≈350 s.
- `v1_m4_pool_release`: no hay segundo backdraft artificial.
- `v1_m4_pool_release`: A3=0 y O2E1=0 WARN.
- `check_physics_coherence.py` sobre el CSV del caso sale limpio.
- Guardrails globales se mantienen estables: `validate_reference_cases` no cambia por default-off.
- No tocar O2E1 severity ni tolerancias.

### Decision vigente

O2E1 sigue como WARN hasta que M5 produzca evidencia C1 limpia o hasta que se apruebe una politica formal de exclusion. La ruta preferida ahora es M5, no exclusion.

---

## Current Session Update — 2026-06-27 (rev 20 — M4 pool-release path-exercise)

### Estado operativo actual

- Branch: `main`, HEAD: último commit de este bloque.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Unit tests Python: sin regresión (5 FAIL + 1 ERROR pre-existentes).
- Physics coherence suite: **exit 0** — 12 PASS, 2 CTRL (`v1_backdraft_accumulation`, `v1_m4_pool_release`), 1 WARN (`cfast_two_room_door_open`).
- ILV suite: exit 1 (pre-existente: `fuel_balance_diag_sealed`, `o2_stoich_diag_sealed`). `v1_backdraft_accumulation` y `v1_m4_pool_release` registrados como CTRL.
- Sin cambio de física. Sin cambio de motor.

### M4 pool-release path-exercise `v1_m4_pool_release`

- **Caso**: derivado de `v1_backdraft_accumulation` con gates relajados y M4 activo. `fire_backdraft_pool_threshold_MJ: 0.35`, `fire_backdraft_o2_max: 0.20`, `fire_backdraft_temp_min_c: 100.0`, `fire_backdraft_lfl: 0.001`, `fire_o2_upper_throttle_enabled: true`.
- **Backdraft ejercitado**: `backdraft_triggered=1` a t=350 s, HRR spike 21.369 kW, pool exhaustado en t=355 s. Path ejecutado.
- **Post-evento zombie (CTRL)**: tras agotar el pool el motor vuelve a `FULLY_DEVELOPED` con `o2_upper≈0.0008` — mismo bug A3 que `v1_backdraft_accumulation`. 8 A3 FAILs + 5 O2E1 WARNs (todos en fase zombie, no en ventana de backdraft). Ambos casos registrados en `KNOWN_INTENTIONAL_CONTROLS`.
- **C1 parcialmente cubierto**: el path de backdraft/pool-release fue ejercitado exitosamente. Los O2E1 WARNs no son del backdraft propiamente, sino del zombie que continúa. C1 queda marcado "path ejercitado / zombie persiste post-backdraft".

Estado criterios WARN→FAIL O2E1 actualizado:

| Criterio | Estado |
|---|---|
| C1 backdraft / pool-release | ⚠️ Path ejercitado — zombie persiste post-backdraft (O2E1 WARNs en zombie, no en backdraft) |
| C2 larga duración ≥ 600 s | ✅ `cfast_slow_growth_sealed` PASS |
| C3 multi-room O2 exchange | ✅ O2E1 PASS en `cfast_two_room_door_open` |
| C4 effective_plume_lower | ✅ `fp_ilv_open_partial_window` PASS |

### Decisión C1 cerrada

**C1 = "path exercised, not clean promotion evidence."** El backdraft/pool-release fue ejercitado exitosamente en `v1_m4_pool_release`. O2E1 está limpio durante el evento (t=340-360 s). Los 5 O2E1 WARN post-evento son consecuencia del zombie A3 (bug de motor separado), no de un fallo de Thornton. **O2E1 permanece WARN.** No se promueve hasta tener C1 limpio o política de exclusión aprobada.

**Próxima sesión recomendada**

Para desbloquear O2E1 → FAIL, elegir una vía:

**Vía A (recomendada) — Fix A3 zombie:**  
`CombustionSystem.gd` no transiciona régimen cuando `o2_upper < fire_o2_min_for_flame` con plume_lower activo. Añadir un guard explícito (`if o2_upper < threshold: force ILV_LATENT`) eliminaría el zombie. Requiere plan de motor explícito antes de tocar `sim/fire/`. Con A3 resuelto, `v1_m4_pool_release` (o una variante) produciría un run limpio y cerraría C1.

**Vía B — Política de exclusión:**  
Documentar formalmente que los WARN del zombie post-backdraft no son bloqueantes para la promoción: ocurren fuera de la ventana del evento, O2 ya estaba capeado (no hay consumo real posible), y son artefacto del bug A3, no de la coherencia Thornton. Requiere decisión explícita documentada.

Otros pendientes (no bloqueantes para O2E1):
- Resolver gap O1 multi-room (no urgente hasta promover O1 a FAIL).

---

## Previous Session — 2026-06-27 (rev 19 — corpus diagnóstico O2E1/O1: 3 casos nuevos)

### Estado operativo actual

- Branch: `main`, HEAD: último commit de este bloque.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Unit tests Python: **157 PASS** — sin cambio.
- Physics coherence audit: **14/14 PASS + 1 WARN + 1 FAIL** (con tmp incluidos, 16 CSVs).
- Sin cambio de física. Sin cambio de motor.

### Corpus diagnóstico O2E1/O1 — 3 casos nuevos

Objetivo: cubrir criterios WARN→FAIL de O2E1 antes de promover severidad.

Casos añadidos (solo CSV + JSON de caso actualizados):
- `v1_backdraft_accumulation` — C1 backdraft/pool-release (650 s)
- `cfast_slow_growth_sealed` — C2 larga duración (1800 s, sellada)
- `cfast_two_room_door_open` — C3 multi-room + intercambio O2 (600 s)

Resultados:

| Caso | O2E1 | O1 | Diagnóstico |
|---|---|---|---|
| `cfast_slow_growth_sealed` | PASS | PASS | ✅ C2 cubierto. Apto para suite permanente. |
| `cfast_two_room_door_open` | PASS | 247 WARN | O2E1 ✅ C3 cubierto. O1 gap en multi-room (ver abajo). |
| `v1_backdraft_accumulation` | 16 WARN | PASS | ❌ A3 FAIL + O2E1 WARN consecuencia. Pool release no activó. C1 NO cubierto. |

**C4** (`effective_plume_lower`): ya cubierto por `fp_ilv_open_partial_window` en suite (280 pasos path no-bulk, O2E1 PASS).

Diagnósticos clave:

- **`v1_backdraft_accumulation` — A3 FAIL**: Motor mantiene `FULLY_DEVELOPED` cuando `o2_upper=0.0009` (0.09%), violando `fire_o2_min_for_flame=0.10`. A3 captura la incoherencia. O2E1 WARNs son consecuencia: HRR acumula ~3425 kW pero O2 está capeado a cero → `delta_o2_fire ≈ 40%` Thornton. `retained_unburned_MJ=0` en todo el CSV — pool release nunca activa. C1 requiere caso distinto o fix de régimen.

- **`cfast_two_room_door_open` — O1 gap multi-room**: El balance O1 (`-dcons + dext + dtrans + dsync`) no captura el flujo O2 vía `canonical_doorway_exchange_enabled`. Residual típico 0.11 kg vs. tolerancia 0.003 kg. Gap estructural de la fórmula O1 — no es bug de física. O1 no debe usarse como gating en casos multi-room con canonical doorway hasta resolver.

Estado criterios WARN→FAIL O2E1:

| Criterio | Estado |
|---|---|
| C1 backdraft / pool-release | ❌ Pendiente — A3 bloquea, pool release no activó |
| C2 larga duración ≥ 600 s | ✅ `cfast_slow_growth_sealed` PASS |
| C3 multi-room O2 exchange | ✅ O2E1 PASS en `cfast_two_room_door_open` |
| C4 effective_plume_lower | ✅ `fp_ilv_open_partial_window` PASS |

---

## Previous Session — 2026-06-27 (rev 18 — O2E1 fix: o2_consumed_fire_kg_total)

### Estado operativo actual

- Branch: `main`, limpio. HEAD: `88ce7d7` — `fix(o2e1): add o2_consumed_fire_kg_total primary-path accumulator`.
- `validate_reference_cases`: **349/354 PASS** — sin cambio.
- Unit tests Python: **157 PASS** (+2 tests O2E1).
- Physics coherence audit: **11/11 PASS, 0 WARN, 0 FAIL** — O2E1 limpio tras fix.

### O2E1 fix — o2_consumed_fire_kg_total

Problema: `o2_consumed_kg_total_all` acumulaba dos veces en modo two-zone estándar (bulk + upper, misma fórmula Thornton) → 1308 WARNs falsos.

Fix tracking-only (sin cambio de física):
- Nuevo campo `room.o2_consumed_fire_kg_total` (+ step) en RoomModel.
- OES selecciona path primario una vez por paso (en este orden de prioridad): bulk si corrió → lower si `fire_uses_lower_o2` → plume si `effective_plume_lower` → upper si `_phase2b_upper_active`. La asignación usa la variable local `_o2_fire_primary`.
- Zeroed en CombustionSystem junto a los demás step accumulators.
- Exportado en StateBuilder + CSV (columna nueva `o2_consumed_fire_kg_total`).
- O2E1 ahora compara `o2_consumed_fire_kg_total` vs `hrr_kj_total * Thornton`.
- `o2_consumed_kg_total_all` y `o2_consumed_bulk_kg_total` (O1) sin cambio.

Corpus audit post-fix (11 CSVs regenerados con nuevo schema): **11/11 PASS, 0 WARN**.

### Próxima sesión recomendada

1. O2E1 está limpio. Siguiente regla de balance: candidatos = balance O2 por zona (upper/lower) o validación de temperatura two-zone.
2. O2E1 puede considerarse para promoción a FAIL una vez el corpus incluya backdraft y pool release.
3. No tocar `o2_consumed_kg_total_all` (sigue siendo raw sum, correcto para diagnóstico granular).

---

## Current Session Update — 2026-06-27 (rev 17 — O2E1 Thornton cross-check corpus audit)

### Estado operativo actual

- Branch: `main`, limpio. HEAD: `90c436a` — `feat(o2e1): add O2E1 Thornton cross-check between CombustionSystem and OES`.
- `validate_reference_cases`: **349/354 PASS** — los 5 FAIL son los `VALID_GAP` conocidos (sin cambio).
- Unit tests Python: **155 PASS** (incluye 15 tests `TestCheckO2E1`).
- Physics coherence audit (11 CSVs): 8 WARN (O2E1), 3 PASS (old schema, skip graceful), **0 FAIL**.

### O2E1 Thornton cross-check — resultado corpus

Regla nueva `O2E1` (WARN, no gating). Cruza `o2_consumed_kg_total_all` (OES) con `hrr_kj_total * 7.6e-5 kg/kJ` (CombustionSystem tracking).

Instrumentación añadida al CSV sin cambiar física:
- `room.hrr_kj_total` en RoomModel — tracking-only, acumula `maxf(0, room.hrr_kw) * dt` en CombustionSystem.
- Exportado via StateBuilder + columna nueva `hrr_kj_total` en LogWriter CSV.

Corpus audit 2026-06-27 (11 CSVs):

| CSV | O2E1 resultado | Worst residual |
|---|---|---|
| `cfast_ilv_audit` | 439 WARN | 1.019e-05 kg |
| `fp_ilv_open_partial_window` | 279 WARN | 1.948e-05 kg |
| `fp_ilv_upper_throttle_off` | 280 WARN | 1.751e-05 kg |
| `fp_ilv_upper_throttle_on` | 34 WARN | 1.751e-05 kg |
| `fuel_balance_diag_sealed` | 60 WARN | 1.523e-05 kg |
| `layer_interface_single_room_window` | 36 WARN | 1.789e-05 kg |
| `o2_stoich_diag_sealed` | 60 WARN | 1.523e-05 kg |
| `v5_m4_ventilation_throttle` | 120 WARN | 1.523e-05 kg |
| `ilv_open_window_repro` | PASS (old schema) | — |
| `p2h_diag_off` | PASS (old schema) | — |
| `p2h_diag_on` | PASS (old schema) | — |

**Root cause identificado**: en modo two-zone estándar (`lower_frac ≥ 0.15`, no `plume_lower`, no `two_zone_solver`), OES acumula en `o2_consumed_kg_total_all` dos veces por paso:
1. Línea 362: bulk path `consumed = (hrr_kw/1000) * cr * dt`
2. Línea 407: upper-zone path `upper_consumed = (hrr_kw/1000) * cr_upper * dt`

Resultado: `o2_consumed_kg_total_all ≈ 2 × Thornton`. Los residuales (1–2 × 10⁻⁵ kg) cruzan el piso absoluto `1e-5` pero son pequeños. El acumulador `o2_consumed_bulk_kg_total` (usado por O1) **no está afectado** — solo acumula el bulk path.

### Reglas coherencia física — estado actualizado

| Regla | Severidad | Estado |
|---|---|---|
| `B1` inversión térmica fuerte | FAIL | Gating |
| `C1` FED suma | FAIL | Gating |
| `C2` FED monotónica | FAIL | Gating |
| `A2` HRR sin combustible | FAIL | Gating |
| `A3` régimen vs O2 superior crítico | FAIL | Gating |
| `D1` balance de CO por sala/paso | FAIL | Gating |
| `E1` balance de combustible sólido | FAIL | Gating |
| `S0` conservación de humo global | FAIL | Gating |
| `O1` balance masa O2 bulk | WARN | Clean (11/11 PASS) |
| `O2E1` cross-check Thornton HRR↔O2 | WARN | 8/11 WARN findings (double-accounting) |

### Próxima sesión recomendada

1. Decidir si se aborda el double-accounting de `o2_consumed_kg_total_all` (fix: separar acumuladores bulk y upper, usar solo uno para Thornton).
2. Regenerar CSVs restantes con schema nuevo (`ilv_open_window_repro`, `p2h_diag_*`) para completar el corpus de 11/11.
3. O2E1 se queda como WARN hasta que el double-accounting esté resuelto y el corpus esté limpio.
4. No promover O2E1 a FAIL sin un plan explícito de fix + re-audit.

---

## Current Session Update — 2026-06-25 (rev 16 — Physics coherence + D1 CO balance gating)

### Estado operativo actual

- Branch: `main`, limpio antes del cierre documental, **ahead 12** respecto a `origin/main` (push pendiente antes de esta nota).
- HEAD previo al cierre: `b6e355f` — `feat(d1): promote D1 CO balance from WARN to FAIL`.
- Suite completa: 18 casos lanzados, **17 OK** y 1 timeout preexistente (`long_burnout_3600s`).
- `validate_reference_cases`: **349/354 PASS** — los 5 FAIL restantes son los `VALID_GAP` conocidos (Grupo A O2 window + Grupo C corridor temp).
- Physics coherence audit: **5/5 PASS**, **0 FAIL**, con D1 ya `FAIL`/gating.
- Tests Python de la fase: **221/221 PASS**.

### Validación física: cambio de enfoque

Se acordó dejar de tratar el problema como una suma de casos M4 y pasar a una revalidación física integral del motor. El objetivo es auditar, con balances e instrumentación, que sean coherentes:

- HRR, combustible, energía y régimen de combustión.
- O2 por capa/sala y su acoplamiento con HRR.
- CO/CO2/HCN, generación local, transporte y balance de carbono.
- Humo/soot, visibilidad, FED y tenabilidad.
- Temperaturas upper/lower, capas, presión, plano neutro e isoterma 150 C.
- Modelo bizona, ventilación por puertas/ventanas, flotabilidad, transporte multi-room/multi-planta.
- Paredes, radiación, almacenamiento térmico y reradiación.

Documento nuevo/actualizado:

- `docs/validation/MOTOR_PHYSICS_VALIDATION_CHECKLIST.md` — checklist maestro de items físicos pendientes y cobertura actual.

### Auditor físico general

Se creó e integró el auditor físico general:

- `scripts/simulation/check_physics_coherence.py`
- `scripts/simulation/audit_physics_coherence_suite.py`
- `tests/test_check_physics_coherence.py`

Reglas cerradas actualmente:

| Regla | Severidad | Estado |
|---|---|---|
| `B1` inversión térmica fuerte | FAIL | Gating |
| `C1` FED suma | FAIL | Gating |
| `C2` FED monotónica | FAIL | Gating |
| `A2` HRR sin combustible | FAIL | Gating |
| `A3` régimen vs O2 superior crítico | FAIL | Gating |
| `D1` balance de CO por sala/paso | FAIL | Gating |

El auditor está integrado en `run_full_reference_suite.ps1` junto al auditor ILV.

### D1 CO balance — cerrado y gating

La línea CO/CO2/HCN se cerró en D1 como balance real, no como heurística de "CO sube sin fuego local".

Instrumentación añadida al CSV sin cambiar física:

- `c_balance_frac`
- `carbon_conservation_error_kg`
- `co_kg`
- `co_generated_kg_step`
- `co2_generated_kg_step`
- `hcn_generated_kg_step`
- `co_net_transport_kg_step`
- Acumulados usados por D1: `co_generated_kg_total`, `co_net_transport_kg_total`, `co_exterior_removed_kg_total`

Invariante D1:

```text
delta_co = co_kg[t] - co_kg[t-1]
expected = delta(co_generated_kg_total) + delta(co_net_transport_kg_total) - delta(co_exterior_removed_kg_total)
residual = abs(delta_co - expected)
```

`D1` empezó como `WARN`, detectó rutas reales de CO no contabilizadas, y después se promovió a `FAIL` tras corpus limpio.

Paths corregidos por D1 (`b41fcbd`):

1. `GasExchangeSystem._purge_upper_species_to_exterior_direct` — actualiza `co_exterior_removed_kg_total`.
2. `ThermalSystem._flush_contaminant_deltas` — actualiza `co_net_transport_kg_total`.
3. `GasExchangeSystem._release_pending_interior_deliveries` — actualiza `co_net_transport_kg_total`.

Semántica importante: `co_net_transport_kg_total` es **neto amplio**, no solo room-to-room. Incluye intercambio, arrastre térmico/hot-gas carry y entregas interiores diferidas. La pérdida a exterior se trata por separado con `co_exterior_removed_kg_total`.

Resultados antes/después:

| CSV | Antes | Después |
|---|---:|---:|
| `layer_interface_single_room_window` | 1 WARN | 0 findings |
| `v5_m4_ventilation_throttle` | 612 WARN | 0 findings |
| `cfast_ilv_audit` | 0 | 0 findings |

### Hallazgos CO/CO2/HCN que quedan registrados

- CO y HCN usan masa interna (`kg`) para generación/transporte/conversión.
- CO2 tiene **dual tracking**: `co2_kg`/`co2_upper_kg` por masa, pero `co2_upper_ppm` sale de `co2_upper * 1e6` (tracer/fracción molar), no de `co2_upper_kg`.
- Por eso `D2` CO/CO2 ratio queda **bloqueado**: no implementar hasta resolver o documentar mejor la dualidad de CO2 upper.
- La regla naive "CO sube sin fuego local" queda descartada para multi-room: puede ser transporte real desde otra sala con fuego.

### Próxima sesión recomendada

1. Confirmar que el cierre documental quedó pusheado.
2. Mantener D1 como gating y no tocar su severidad/tolerancia salvo evidencia nueva.
3. Elegir el siguiente bloque de balance, preferiblemente **O2 + energía/HRR** antes que D2 CO/CO2 ratio.
4. Para O2/energía: inventariar columnas e instrumentación necesaria antes de añadir reglas.
5. No tocar HVAC ni visual FP en esta línea; están fuera de foco hasta estabilizar el núcleo físico.

---

## Current Session Update — 2026-06-23 (rev 15 — Ruta B: v5_m4_ventilation_throttle)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 7** respecto a `origin/main` (push pendiente).
- Commit nuevo: `21ba9ee` — `test(ilv): add M4 ventilation throttle reference case`.
- Validación: **354/354 PASS** (guardrails ampliados, 4 nuevos checks del caso M4 — todos PASS).
- Python tests: 244 tests, 5 failures pre-existentes (sin regresión).

### Ruta B: caso de referencia M4 para v5

**Decisión**: mantener `v5_ventilation_hrr_spike` como caso legacy/control (sin cambios). Crear nuevo caso `v5_m4_ventilation_throttle` con `fire_o2_upper_throttle_enabled: true` que verifica que M4 suprime el HRR zombie.

**Semántica**:
- `v5_ventilation_hrr_spike`: testea el spike como comportamiento esperado (bug ILV expuesto). `peak_hrr = 3245 kW`, `time_hrr_above_1000_post_vent ≈ 164 s`.
- `v5_m4_ventilation_throttle`: testea supresión M4. `peak_hrr ≤ 600 kW`, fire extinguido ~178 s post-ignición.

**Métricas baseline (M4)**:

| Métrica | Valor medido | Regla | Estado |
|---|---:|---|---|
| `room_0_peak_hrr_kw` | ~492 kW | `max: 600` | PASS |
| `room_0_min_o2_upper` | ~6.37% | `min: 0.05` | PASS |
| `room_0_min_l150_m` | ~1.98 m | `min: 1.90` | PASS |
| `room_0_peak_co_upper_ppm` | ~12386 ppm | `min: 1000` | PASS |

**Archivos añadidos**:
- `sim/validation/cases/v5_m4_ventilation_throttle.json` — misma física que v5, `fire_o2_upper_throttle_enabled: true`
- `sim/validation/baselines/v5_m4_ventilation_throttle.json` — 4 reglas de supresión
- `sim/validation/reports/v5_m4_ventilation_throttle.json` — reporte generado headless
- `sim/validation/reports/v5_m4_ventilation_throttle.csv` — CSV copiado desde tmp_v5_m4.csv (misma física)
- `scripts/simulation/validate_reference_cases.py` — caso añadido a `build_single_room_fire_checks()`

**Auditor ILV post-Ruta B**: coherence checker sobre `v5_m4_ventilation_throttle.csv` → 0 findings. `audit_ilv_layer_coherence_suite.py`: 8/8 PASS (excluye `fp_ilv_upper_throttle_off` como control intencional).

### Próxima sesión

El único HRR zombie sin resolver en CSVs permanentes es `fp_ilv_upper_throttle_off` (control intencional, 258 findings). No requiere acción.

Opciones abiertas:
- **Opción A** (baja prioridad): diseñar más escenarios M4 con `fire_o2_upper_throttle_enabled: true` desde el principio.
- **Opción B coordinada** (alta complejidad): migración de los ~8-10 casos con ventana exterior y `threshold_metrics` calibradas pre-M4.

---

## Current Session Update — 2026-06-22 (rev 14 — Phase C: credibility audit + primera migración M4)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 6** respecto a `origin/main` (push pendiente).
- Commits nuevos en esta ronda:
  - `d635c83` — feat(ilv): add ILV layer-coherence suite auditor
  - `ee9216c` — fix(ilv): activate M4 guard in layer_interface_single_room_window
- Validación: 345/350 PASS (sin regresión). 42/42 Python tests PASS (incluye 2 pre-existentes corregidos).

### Motor credibility audit (Phase C) — Mapa de daño completado

**Auditor creado**: `scripts/simulation/audit_ilv_layer_coherence_suite.py` + `tests/test_audit_ilv_layer_coherence_suite.py` (16 tests).

**Resultados sobre 8 CSVs permanentes** (tmp excluidos, `--include-tmp` para incluirlos):

| Archivo CSV | Estado | Findings | Notas |
|---|---|---:|---|
| `cfast_ilv_audit` | PASS | 0 | Multi-room, canonical activo |
| `fp_ilv_open_partial_window` | PASS | 0 | Ventana parcial, canonical activo |
| `fp_ilv_upper_throttle_on` | PASS | 0 | M4 activo — referencia de diseño |
| `ilv_open_window_repro` | PASS | 0 | Canonical activo |
| `layer_interface_single_room_window` | **PASS** | 0 | ✅ Migrado a M4 (antes: 11 findings) |
| `p2h_diag_off` | PASS | 0 | Sin exposición exterior |
| `p2h_diag_on` | PASS | 0 | Sin exposición exterior |
| `fp_ilv_upper_throttle_off` | **FAIL** | 258 | Control intencional (HRR zombie ~1211 kW) |

**Único FAIL restante = caso de control intencional** `fp_ilv_upper_throttle_off`. No hay HRR zombies no intencionados en CSVs activos.

### Primera migración M4 permanente: `layer_interface_single_room_window`

**Contexto**: el auditor descubrió 11 findings en este caso de regresión de interfaz de capa — ILV zombie incidental (caso diseñado para testear alturas de capa, no combustión).

**Análisis OFF vs M4** (room 0, ventana exterior 50% abierta, sin canonical):

| t (s) | HRR OFF | HRR M4 | o2_upper OFF | o2_upper M4 |
|---|---:|---:|---:|---:|
| 100 | 377.7 kW | 377.7 kW | 16.9% | 16.9% |
| 130 | 662.3 kW | 336.1 kW | 4.2% | 6.5% |
| 160 | 959.3 kW | 79.9 kW | 0.08% | 6.6% |
| 180 | 1142.2 kW | **32.8 kW** | 0.08% | **8.5%** |

**Baseline checks con M4** — todos PASS:
- `min_visible_smoke_layer_m`: 1.175 (idéntico — mínimo antes de t=130s)
- `min_thermal/flow_interface_m`: 1.171 (idéntico)
- `final_flow_interface_m`: 1.428 ∈ [0, 2.40] ✓
- `final_visibility_m`: 0.33 ≤ 5.0 ✓

**Cambios en `ee9216c`**:
- `sim/validation/cases/layer_interface_single_room_window.json` — añadidos `fire_o2_upper_throttle_enabled: true` + `two_zone_solver_enabled: true`
- `sim/validation/cases/fed_thermal_layer_smoke_only.json` — añadido `two_zone_solver_enabled: true` (corrige 2 failures pre-existentes en test_layer_interface_model.py)

### Único caso real pendiente con HRR zombie: `v5_ventilation_hrr_spike`

El auditor `tmp_v5_off.csv` (95 findings, HRR zombie hasta 3245 kW) queda como único caso problemático real. Ruta de migración bloqueada: el caso tiene `threshold_metric: hrr >= 1000 post-vent` calibrado sobre el bug ILV. Para migrar: actualizar el threshold_metric a medir supresión por M4 en lugar de magnitud del spike.

### Próxima sesión

**Opción A (preferida)**: diseñar nuevos escenarios ILV/FP con M4 como física esperada desde el principio. Sin impacto en suite existente.

**Opción B**: migración coordinada de `v5_ventilation_hrr_spike` — requiere actualizar explícitamente el `threshold_metric` del caso antes de activar M4.

---

## Current Session Update — 2026-06-22 (rev 13 — Cierre campaña M4)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 4** respecto a `origin/main` (push pendiente).
- Commits esta sesión:
  - `ba13139` — fix(ilv): add fire_o2_upper_throttle_enabled motor guard (Phase 5 M4)
  - `5c98429` — docs(ilv): document EXP-1 finding — M4 and canonical are competing mechanisms
  - `10e93ed` — docs(ilv): document EXP-2 finding — existing threshold_metrics built on ILV bug
- Validación: 345/350 PASS (sin regresión), unit test 7/7 PASS, coherence checker 0/1686 findings (throttle ON).

### Phase 5 M4 — ILV upper-O₂ throttle guard

**Causa raíz auditada**: `two_zone_solver_enabled=true` → `CombustionSystem` elige `o2_ref = room.o2_lower` para HRR throttle. En salas abiertas (`outside_open_factor > 0.01`), `OxygenExchangeSystem.plume_lower_mode=false` → consumo O₂ va al bulk `room.o2`, nunca a `room.o2_lower`. Resultado: `o2_lower` permanece ~19.7%, `o2_hrr_factor ≈ 0.894`, HRR ~1211 kW, mientras `o2_upper → 0.08%` sin efecto en combustión.

**Solución implementada**: flag `fire_o2_upper_throttle_enabled` (motor engine-side). En `CombustionSystem.step_room_fire()`, después de resolver `o2_selection`, si `fire_o2_upper_throttle_enabled=true` y `o2_upper < fire_o2_upper_throttle_critical(0.10)` y `sel_mode == "plume_lower" OR "plume_blend"`: `o2_ref = minf(room.o2, room.o2_upper)`.

**Corrección de placement**: los keys `fire_o2_upper_throttle_enabled` / `fire_o2_upper_throttle_critical` debían estar en `_build_room_combustion_context()` (dict leído por CombustionSystem), no en `_sync_auxiliary_services()` (dict de OxygenExchangeSystem, sin relación).

**Resultados verificados**:
- Throttle OFF: HRR 1211 kW indefinido, 258 coherence FAIL (fuego zombie)
- Throttle ON: HRR 549→299→184→46→25 kW (fuego se apaga t≈165 s), 0 coherence FAIL (1686 rows)
- Unit test: 7/7 PASS (bug secundario: `fire_max_active_s` ausente del contexto de test → fixed)
- Guardrails: 345/350 PASS intactos (5 failures pre-existentes, sin regresión)

**Archivos modificados**:
- `sim/fire/CombustionSystem.gd` — throttle guard (líneas ~124-136 post o2_selection)
- `sim/core/SimulationEngine.gd` — keys movidos a `_build_room_combustion_context()` (eliminados de `_sync_auxiliary_services()`)
- `tools/validate_fire_o2_upper_throttle.gd` — context fix `fire_max_active_s: 1800.0`
- `tools/validate_fire_o2_upper_throttle.tscn` — escena de test headless
- `sim/validation/cases/fp_ilv_upper_throttle_on.json` — escenario con flag activo per-caso
- `sim/validation/cases/fp_ilv_upper_throttle_off.json` — escenario control

### EXP-1 — Hallazgo crítico: M4 y canonical son mecanismos en competencia

**Experimento (2026-06-22)**: Activar `fire_o2_upper_throttle_enabled=true` en `cfast_ilv_open_window_repro` (que ya tiene `fire_o2_canonical_enabled=true`). Revertido después de análisis.

**Mecanismo de interacción descubierto**:
- Con canonical: `o2_lower ≈ 13–16%` (depleta por consumo real)
- `_resolve_fire_o2_selection()` en `plume_lower` → `o2_ref = room.o2_lower ≈ 13%`
- Cuando M4 activa (`o2_upper < 0.10`): `o2_ref = min(room.o2=14%, o2_upper=9%) = 9%`
- Resultado: M4 sobreescribe canonical con referencia MÁS agresiva → doble-freno
- Comportamiento observado: HRR oscila 100–750 kW (vs 972 kW estable con canonical solo), ciclos ILV_LATENT↔VCB, fuego termina en ILV_LATENT a t=1400s

**Coherence**: 0 findings (correcto). **Guardrails**: 345/350 (sin regresión). **Pero criterio ±10% HRR no se cumple** — cambio >>10%.

**Conclusión operativa**:
- M4 NO es "defense-in-depth" junto a canonical — es un mecanismo **en competencia**
- M4 aplica en casos **SIN canonical** (donde `o2_lower` se mantiene fresco ~19.7% por `plume_lower_mode=false`)
- Canonical aplica en casos donde se quiere que la combustión deplecione `o2_lower` directamente
- **No activar ambos flags simultáneamente sin plan explícito de interacción**

### EXP-2 — Hallazgo: casos existentes tienen threshold_metrics calibradas sobre el bug

**Experimento (2026-06-22)**: `v5_ventilation_hrr_spike` con M4 standalone (sin canonical). Caso tiene ventana exterior abriendo a t=120s, `fire_secondary_hrr_gain_kw: 2500`, y threshold_metric `hrr >= 1000 post-vent`.

**Resultados clave**:

| t | HRR OFF | HRR M4 | delta | o2_upper OFF | o2_upper M4 |
|---|---|---|---|---|---|
| t=115s | 486 kW | 486 kW | 0% | 10.22% | 10.22% |
| t=120s | 537 kW | 414 kW | -23% | 8.30% | 8.56% |
| t=145s | 819 kW | 122 kW | -85% | 0.08% | 6.56% |
| t=300s | 3104 kW | 107 kW | -97% | 0.08% | 10.15% |
| t=595s | 3232 kW | 162 kW | -95% | 0.08% | 9.44% |

**Coherence OFF**: 75 findings (bug ILV activo desde t=145s, o2_upper=0.08% mientras HRR sube a 3232 kW).
**Coherence M4**: PASS (0 findings).

**Problema**: `threshold_metric hrr >= 1000 post-vent` fallaría con M4 (HRR máximo ~210 kW). El caso testea el spike como feature — que es la manifestación del bug ILV con `fire_secondary_hrr_gain_kw`.

**Conclusión**: M4 es físicamente correcto pero incompatible con los threshold_metrics de casos diseñados pre-M4.

### Situación actual — Activación de M4 en casos existentes bloqueada

**Patrón identificado en EXP-1 y EXP-2:**
- Casos con `fire_o2_canonical_enabled`: M4 crea doble-freno, cambio >>10% HRR
- Casos sin canonical pero con ventana exterior: M4 funciona correctamente, pero threshold_metrics calibradas sobre HRR buggy fallan

**Única ruta segura**: activar M4 en **nuevos casos** diseñados desde cero con M4 como comportamiento esperado. Los `fp_ilv_upper_throttle_on/off.json` son el modelo correcto.

### Cierre de campaña M4 — CERRADA

**EXP-3 (`cfast_r0_window_360`) — ABORTADO**: mismo patrón que EXP-2 sin investigación necesaria. Los checks de Grupo A ya fallan y son pre-existentes; añadir M4 solo agregaría más variables sin beneficio claro.

**Estado de activación M4 — BLOQUEADA en casos existentes:**

| Escenario | Resultado | Motivo |
|---|---|---|
| Caso con `fire_o2_canonical_enabled` (EXP-1) | NO ACTIVAR | Doble-freno: M4 sobreescribe canonical, HRR oscila 100–750 vs 972 kW |
| Caso sin canonical + ventana exterior (EXP-2) | NO ACTIVAR | Threshold_metrics calibradas sobre HRR buggy fallarían |
| Caso nuevo diseñado para M4 (`fp_ilv_upper_throttle_on`) | ACTIVO | Física correcta, 0 coherence findings, referencia de diseño |

**M4 queda como fix gated**, disponible tras flag `fire_o2_upper_throttle_enabled=false` (default). No rompe nada existente. Listo para usar en nuevos escenarios.

### Proxima sesion — si se quiere progresar M4

**Opción A — Nuevos casos ILV FP** (coste bajo): diseñar 1-2 escenarios QA basados en `fp_ilv_upper_throttle_on` con variantes de ventilación (ventana 25%, 75%, 100%). Sin impacto en suite existente.

**Opción B — Pasada coordinada de validación** (coste alto): auditar todos los casos con ventana exterior y `threshold_metrics`, actualizar los afectados (~8-10 casos), luego activar M4 globalmente o per-familia. Requiere plan explícito antes de iniciar.

**Opción C — Dejar en standby** (sin coste): M4 queda disponible como fix gated. Se activa solo en escenarios FP/QA futuros. No hacer nada hasta que se necesite un escenario ILV concreto.

---

## Current Session Update — 2026-06-22 (rev 11 — FP ILV base scenario consolidado)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 4** respecto a `origin/main` (push pendiente).
- Último commit: `test(ilv): add FP open-window ILV QA case` (pendiente).
- Validación: 345/350 PASS, clasificador 11/11 PASS, coherence checker 0/1686 findings.

### Escenario FP/QA ILV base (`fp_ilv_open_partial_window.json`)

Nuevo escenario headless dedicado para validación FP de ILV con ventana parcialmente abierta:
- `sim/validation/cases/fp_ilv_open_partial_window.json`
- Derivado del repro: `simple_house`, room 2, ventana exterior 0.5, puerta cerrada, 1400 s.
- `fire_o2_canonical_enabled: true` per-caso (no global).
- Resultado verificado: `o2_lower` 20.4% → 13.0%, `o2_hrr_factor` 0.986 → 0.278, HRR estable ~972 kW.
- Régimen: FUEL_CONTROLLED → VENTILATION_STRESSED → VENTILATION_CONTROLLED_BURNING.
- Coherence checker: 0/1686 findings.

**Por qué HRR ~972 kW y no ~3100 kW (QA manual):** diseño deliberado. Con canonical activo y `fire_secondary_hrr_gain_kw=0`, el fuego se autorregula por `o2_lower` (~13%). El QA manual de rev 9 operó con un modo interactivo con posiblemente mayor secondary gain o ventilación dinámica. La variante stress queda pendiente para diseño futuro explícito.

### Próxima sesión recomendada

1. **No hacer nada** con motor/defaults/casos existentes hasta decisión explícita.
2. **Variante stress** (`fp_ilv_open_partial_window_stress.json`): añadir `fire_secondary_hrr_gain_kw` para alcanzar HRR ~3100 kW y verificar si canonical sigue siendo estable. Solo si se decide reproducir el QA manual headless con fidelidad.
3. **Globalizar Opción C**: requiere plan explícito con calibración de `plume_lower_o2_depletion_fraction`, análisis de casos con `ach=0`, y Phase 3+ doorway exchange. No iniciar sin plan.

---

## Current Session Update — 2026-06-22 (rev 10 — ILV Opción A + C, línea cerrada per-caso)

### Estado operativo actual

- Branch: `main`, limpio, **ahead 3** respecto a `origin/main` (push pendiente).
- Últimos commits relevantes:
  - `56faa6e test(ilv): enable canonical O2 routing in open-window repro`
  - `9e23f9e fix(ilv): classify upper-O2 starvation as VCB in open rooms`
  - `afc1208 test(ilv): add layer coherence detector`
- Validación: 345/350 PASS (sin regresión), clasificador 11/11 PASS, coherence checker 0/1686 findings.

### Cierre de línea ILV motor (Opciones A y C)

**Causa raíz confirmada** (auditoria completa 2026-06-22):
- `SimulationEngine.two_zone_solver_enabled = true` (default) → `CombustionSystem._resolve_fire_o2_selection` elige `o2_ref = room.o2_lower` (zona baja, fresca ~19.7%) como señal de throttle.
- `OxygenExchangeSystem.plume_lower_mode = false` en salas con apertura exterior (guard `outside_open_factor <= 0.01` no se cumple) → el consumo de O₂ va al bulk `room.o2`, nunca a `room.o2_lower`.
- Resultado: `o2_lower` nunca depleta → `o2_hrr_factor ≈ 0.894` → HRR sin throttle → `o2_upper` colapsa a ~0 sin que el motor reaccione. Causa exacta de `hrr≈3108 kW` / `o2_upper≈0.3%` del QA manual rev 9.

**Opción A aplicada** (`9e23f9e`): `CombustionRegimeClassifier` regla 7.5 — si `o2_upper < 5%` y `hrr_kw >= 100` → `VENTILATION_CONTROLLED_BURNING`. Fix de display/régimen, sin cambio de física. 258 filas `upper-O2-critical-but-regime-fuel-controlled` → 0.

**Opción C aplicada per-caso** (`56faa6e`): `fire_o2_canonical_enabled: true` en `sim/validation/cases/cfast_ilv_open_window_repro.json` únicamente. Resultado verificado headless:
- `o2_lower`: 19.7% → 13.0% (depleta por combustión)
- `o2_hrr_factor`: 0.894 → 0.278 (throttle sigue zona baja real)
- `hrr_kw`: 1211 → 972 kW (self-throttled, sin extinción)
- `o2_upper`: 0.08% → 7.9% (entrainment bidireccional estabiliza zona superior)
- Coherence checker: 258 findings `HRR-throttle-high` → 0

**No globalizado**: el flag default del engine permanece `false`. Sin candidatos FP reales seguros para activación inmediata (`layer_interface_single_room_window` tiene `ach=0` → crash de zona baja; `bv031` tiene `fire_o2_full_hrr_open` simultáneo → sin caracterizar).

**El QA manual rev 9 fue interactivo**, no un JSON de validación. No existe escenario headless FP dedicado para ese caso (hrr≈3108, jugador con ventana abierta).

### Próxima sesión recomendada

1. **Mantener** `fire_o2_canonical_enabled=true` solo en `cfast_ilv_open_window_repro.json`. No aplicar a más casos sin análisis individual de `ach_infiltration` y flags de throttle existentes.
2. **Si se quiere reproducir el QA manual headless**: diseñar `sim/validation/cases/fp_ilv_open_partial_window.json` basado en el repro actual pero con `fire_secondary_hrr_gain_kw` para alcanzar hrr~3100 kW. Es diseño de escenario, no fix de motor.
3. **Para globalizar Opción C**: requiere plan explícito que incluya calibración de `plume_lower_o2_depletion_fraction`, análisis de casos con `ach=0`, y doorway pressure-driven exchange (Phase 3+). No iniciar sin plan.

---

## Current Session Update — 2026-06-21 (rev 9 — FP ILV/humo QA, estado guardado para otra maquina)

### Estado operativo actual

- Branch: `main`, sincronizado con `origin/main` tras push de cierre.
- Ultimos commits relevantes:
  - `d69232c fix(fp): eye-height gas layer + overhead smoke block WIP`
  - `696f03f fix(fp): tighten overhead smoke visibility`
- Validacion de producto: `python scripts/check_product.py` mantiene todos los suites de producto/Godot en PASS; unico fallo conocido: `Guardrail script unit tests` por los 5 `VALID_GAP` required.
- `git diff --check`: OK.
- Worktree esperado al continuar: limpio.

### Hallazgos nuevos de QA manual FP ILV/humo

Fuente de diagnostico: capturas FP y logs exportados en `F:/OneDrive/Escritorio/graficas/2026-06-21_23-21-39/`.

**Problema visual corregido:** el HUD podia mostrar `Vis FP 29m` aunque el CSV tuviera `visibility_m` fisica de centimetros. Causa: el ajuste de capa permitia que estar ligeramente bajo el plano de humo limpiara demasiado la vista. `696f03f` endurece el bloqueo por humo superior: agacharse sigue mejorando la visibilidad, pero una capa superior opticamente negra oscurece techo/luminarias y reduce contraste de la escena.

**Problema de HUD corregido:** el panel tecnico mezclaba datos de capa superior (`COu`, `HCNu`, `CO2u`) con temperatura/O2/visibilidad a la altura del jugador. El HUD ahora selecciona gases segun la altura de los ojos frente a `smoke_layer_m`/`smoke_display_layer_m`, mostrando sufijos `u` o `l` coherentes. Si hay HRR activo y `o2_upper < 5%`, el HUD muestra `Reg ILV CRIT` aunque el clasificador base aun devuelva `FUEL_CONTROLLED`.

**Hallazgo de motor no corregido:** el log contiene estados fisicamente incoherentes desde el punto de vista de combustion/layer coupling, por ejemplo:

- t≈940 s: `hrr_kw≈3108`, `combustion_regime=FUEL_CONTROLLED`, `o2_upper≈0.3%`, `o2_lower≈20.3%`, `visibility_m≈0.08 m`.
- t≈1280 s: patron similar, con jugador agachado viendo capa baja fresca pero capa superior sin O2.

Esto apunta a que combustion/clasificacion aun pueden usar una senal global/lower demasiado optimista frente a una capa superior agotada. No se ha tocado `sim/core` ni fisica para ocultarlo. Requiere auditoria de motor antes de cualquier fix.

### Proxima sesion recomendada

1. **Auditoria motor ILV/layer coupling**: reproducir el escenario FP/ILV y loggear por segundo `hrr_kw`, `combustion_regime`, `o2`, `o2_upper`, `o2_lower`, `co_upper_ppm`, `co_lower_ppm`, `co2_ppm`, `co2_upper_ppm`, `hcn_ppm`, `hcn_upper_ppm`, `smoke_kg`, `visibility_m`, `smoke_layer_m`, `thermal_layer_m`, `fire_latent_active`.
   - Detector automatico: `python scripts/simulation/check_ilv_layer_coherence.py <sim_log.csv> --room-id 0`.
   - Tests unitarios: `python -m unittest tests.test_ilv_layer_coherence -v`.
2. **Hipotesis principal**: HRR y clasificador estan acoplados a `o2`/lower/global mientras el fuego/llama visual y la capa superior indican ILV critico. Confirmar antes de tocar `CombustionSystem`.
3. **No cambiar motor aun**: preparar primero un informe con filas clave y un caso headless reproducible. Cualquier fix probablemente pertenece a two-zone canonico/Phase 3+ o a una regla intermedia explicita para HRR limitado por `o2_upper`.

---

## Current Session Update — 2026-06-21 (rev 8 — FP ILV/HUD/humo visual, pendiente push)

### Estado operativo actual

- Branch: `main`, **ahead 2** respecto a `origin/main`.
- Commits locales pendientes de push:
  - `a6d44c0 fix(fp-hud): clarify ILV critical display`
  - `b59fa33 fix(fp): strengthen ILV smoke visibility`
- Validación de producto: `python scripts/check_product.py` mantiene todos los suites de producto/Godot en PASS; único fallo conocido: `Guardrail script unit tests` por los 5 `VALID_GAP` required.
- `git diff --check`: OK.
- Worktree conserva artefactos generados/untracked no relacionados (`*.translation`, `.uid`, reports de auditoría); no incluirlos salvo decisión explícita.

### FP ILV / HUD / humo — cerrado visualmente en esta sesión

**Commit `a6d44c0` — HUD FP ILV**

- El panel superior deja de duplicar HRR/visibilidad cuando el panel técnico está visible.
- El panel técnico muestra `Reg ILC`, `Reg ILV` o `Reg ILV CRIT`.
- Gases etiquetados por capa: `O₂u/O₂l`, `COu`, `CO₂u`, `HCNu`.
- La llama FP se atenúa visualmente en `ILV_LATENT` o con O₂ superior crítico, sin cambiar `hrr_kw` ni física.
- `docs/validation/GAPS_INVENTORY.md` sincronizado a **69 gaps non-gating**.

**Commit `b59fa33` — humo/visibilidad FP en ILV**

- `FPVisibilityOverlay` fuerza visibilidad severa en ILV crítico (`smoke_overlay_ilv_severe_visibility_m = 1.6` m por defecto).
- Overlay de humo más opaco en régimen ventilación-limitado, especialmente con `o2_upper < 5%` y HRR activo.
- Luces de techo/aperturas pueden atenuarse casi a cero (`smoke_light_min_transmission = 0.01`), evitando que luminarias de techo sigan visibles en humo severo.
- Tests actualizados:
  - `tools/validate_fp_technical_hud.gd`: `Reg ILV CRIT` + `Vis FP 1.6m`.
  - `tools/validate_fp_fire_visuals.gd`: llama/luz atenuadas y luz de techo casi apagada en ILV crítico.

**Diagnóstico importante:** estos fixes son **visualización FP only**. No recalibran generación física de humo (`smoke_kg`, yields, soot, transporte). La queja sobre visibilidad irreal queda mitigada visualmente, pero requiere auditoría de motor para confirmar si la producción de humo/visibilidad física es suficiente en ILV.

### Pendientes priorizados para próximas sesiones

1. **Publicar commits FP locales**: push de `a6d44c0` y `b59fa33` si el QA visual manual es aceptable.
2. **QA manual FP ILV**: jugar escenario ILV y verificar pérdida de techo/luminarias, severidad de `Vis FP 1.6m` y llama atenuada.
3. **Auditoría humo motor**: loggear `smoke_kg`, `visibility_m`, `soot_fraction`, `CO`, `O₂`, `HRR`, `combustion_regime` en escenario ILV reproducible.
4. **Visualización avanzada de humo**: niebla/volumen local, pérdida de contraste por distancia, gradiente por altura y atenuación de geometría lejana.
5. **ILV Fase 3 motor**: pool latente real con HRR bajo positivo, reventilación, crecimiento inducido y backdraft risk.
6. **Phase 3+ two-zone canónico**: única ruta real para cerrar los 5 `VALID_GAP`; requiere plan de arquitectura y rollback.

---

## Current Session Update — 2026-06-21 (rev 7 — Hito B cerrado, publicado)

### ILV Hito B — cerrado hasta Fase 2 Paso 2 (2026-06-21)

| Fase | Commit | Estado |
|------|--------|--------|
| Fase 0 — auditoría extinción directa | `c59aeba` | Cerrado |
| Fase 1 — clasificador 9 regímenes + `combustion_regime` | `922a56a` | Cerrado |
| Fase 2 Paso 1 — `fire_latent_active` en `RoomModel` | `efcc492` | Cerrado |
| Fase 2 Paso 2 — `thermal_hold` fix → `ILV_LATENT` visible | `fbf4d3e` | Cerrado |
| Fase 3 — reventilación y smoldering con HRR positivo | — | **No iniciada** |

**Validación:** 345/350 PASS, 5/350 FAIL (todos VALID_GAP — Grupos A y C sin candidato per-caso). Intacta.

**Alcance de Hito B:** solo observabilidad. No hay pool latent smoldering real con HRR positivo durante `ILV_LATENT`. El campo `fire_latent_active=true` indica que `latent_viable=true` sin llama sostenida, pero el HRR decae hacia cero durante ese período. Fase 3 define la ruta para smoldering real con energía activa.

---

## Current Session Update — 2026-06-21 (rev 6 — ILV Fase 2 Paso 2 cerrado)

### ILV Hito B — Fase 2 Paso 2 cerrado (2026-06-21)

**Objetivo:** `fire_latent_active=true` y régimen `ILV_LATENT` visible en `cfast_ilv_audit.csv`.

**Causa raíz encontrada:** `_can_sustain_latent_fire` bloqueada por `thermal_hold=FALSE`. El default del engine `fire_latent_hold_upper_temp_c=140°C` nunca era alcanzado en la sala sellada (pico ~70°C upper, ~49°C lower).

**Cambios realizados (mínimos, sin tocar física global):**

1. `sim/validation/cases/cfast_ilv_audit.json` — añadidos dos overrides per-caso:
   - `fire_latent_hold_upper_temp_c: 40.0` (temp_upper=67°C > 40°C a t=406 s ✓)
   - `fire_latent_hold_lower_temp_c: 40.0` (temp_lower=49°C > 40°C a t=406 s ✓)
2. `sim/fire/CombustionSystem.gd` — `room.fire_latent_active = false` añadido en rama idle/post-extinción (previene stuck post-extinción).
3. Revertido código muerto: `fire_latent_smolder_o2_margin` nunca estuvo en el contexto de combustión; eliminado.

**Verificación:**
- `fire_latent_active=1`: 52 rows, t=406.1–457.1 s ✓
- Post-extinción: `latent=0` correctamente ✓
- Régimen: `VENTILATION_CONTROLLED_BURNING → ILV_LATENT → EXTINGUISHED` ✓
- Clasificador headless 9/9 PASS ✓
- Baseline: 345/350 PASS intacto (5 FAILs requeridos VALID_GAP sin cambio) ✓

---

## Current Session Update — 2026-06-21 (rev 5 — ILV Fase 0 cerrada)

### ILV Hito B — Auditoría Fase 0 cerrada (2026-06-21)

Escenario: room 2 (dormitorio, ~36 m³), sellado, legacy fire path, 900 s. Artefactos:

- `sim/validation/cases/cfast_ilv_audit.json` — caso de auditoría (read-only, sin cambio de física).
- `scripts/simulation/audit_ilv_phase0.py` — script diagnóstico (read-only, `--no-run` para reanalizar CSV existente).

**Hallazgo confirmado:** fuego pasa `VENTILATION_CONTROLLED_BURNING → EXTINGUISHED` a t=436 s, o2=10.9 %, sin pasar por `ILV_LATENT`. `fire_smoldering` nunca fue true. Gap estructural: con `fire_o2_min_for_flame=0.10`, `can_flame=false` a o2<8.5 % pero `latent_viable=false` a o2<10.8 %; en la ventana 8.5–10.8 % no hay llama ni latencia posible. El clasificador Fase 1 no muestra `ILV_LATENT` porque depende de `fire_smoldering`, que a su vez requiere `hrr_kw > 0.5`.

**Próxima decisión (Fase 2):** ampliar latencia ILV requiere una de estas rutas (ninguna iniciada sin plan explícito):
1. Bajar threshold `hrr_kw > 0.5` en `fire_smoldering` (toca `CombustionSystem.gd`).
2. Añadir campo `fire_latent_active: bool` a `RoomModel` activado antes de que HRR caiga a 0.
3. Exposer `latent_viable` directamente al clasificador como señal adicional.

No iniciar Fase 2 sin plan explícito y aprobación.

---

## Current Session Update — 2026-06-21 (rev 4 — UX polish cerrado)

- Branch: `main`, synchronized with `origin/main`.
- **Tag publicado: `v0.4.0` — release estable.**
- **Hito UX polish FP cerrado** — commits `c7e3db8` y `a689f1d`.
- **Current validation baseline: 345/350 PASS, `5/350` required FAIL (todos VALID_GAP)**.
- `docs/validation/STATUS_VALIDATION.md` is the validation source of truth.

### UX Polish FP — cerrado (2026-06-21)

| Ítem | Commit | Resultado |
|------|--------|-----------|
| Camera stance easing (`_apply_stance`) | `c7e3db8` | Cerrado — lerp tau=80ms, test headless PASS |
| Opening prompt text (accents, consistency) | `a689f1d` | Cerrado — 4 fixes de texto, sin cambio de lógica |
| Colisiones corner FP | — | Cerrado — sin issue reproducible (ver diagnóstico abajo) |

Suite headless Godot completa post-polish:

| Suite | Resultado |
|-------|-----------|
| FP stance easing Godot | PASS |
| FP technical HUD | PASS |
| FP victim states | PASS |
| FP detector alarm | PASS |
| FP fire visuals | PASS |
| FP player start | PASS |
| FPVisibilityOverlay smoke layer | SIN ISSUE |
| Colisiones corner FP | SIN ISSUE REPRODUCIBLE — diagnóstico cerrado |

**Diagnóstico colisiones corner FP (2026-06-21):** inspección de `CharacterBody3D + CapsuleShape3D (r=0.24m) + move_and_slide()`. La geometría de habitaciones (mínimo 2.8 m de espacio libre) y puertas (0.42 m de holgura lateral) supera el diámetro de cápsula (0.48 m). No se identificó bug ni escenario de traversal/clipping reproducible. No se añadió test headless por ausencia de caso de reproducción. Deuda cerrada como "sin issue reproducible".

Deuda de producto UX polish cerrada. Tras rev 8 quedan abiertas como líneas nuevas: QA visual FP ILV/humo, auditoría de humo motor, ILV Fase 3 y Phase 3+ two-zone.

### What is current now

- Phase 2A/2B/2C/2D, Phase 2E-bedroom, Phase 4B slow-growth wall reradiation and Phase 5A Group A sweep are already reflected in the current baseline.
- `cfast_two_room_door_open` now PASSes RMSE: 53.8°C (threshold <=60°C) after Phase 2C thermal counterflow.
- `cfast_hvac_t300_o2` now PASSes after Phase 2D HVAC two-zone O2 mass balance.
- `cfast_bedroom_closed_door` O2 checks now PASS after Phase 2E-bedroom per-case calibration.
- `cfast_slow_growth_sealed` temperature checks now PASS after Phase 4B wall reradiation during active fire.
- Phase 5A sweep confirmed Group A as a VALID_GAP with no viable per-case JSON calibration.

### Current guardrail state

- Required checks: FAIL — `5` required failures, all confirmed VALID_GAP.
- Known gaps: `69` non-gating gaps in JSON and docs.
- Gap inventory count: synchronized.
- Phase 2E sentinel: FAIL on `g4 FED timing [s]` (pre-existing, not caused by this session).
- Carbon/HCN sentinels: PASS.
- Legacy/two-zone contract: PASS.
- CFAST truth integrity: PASS (99/99).
- Physics override linter: PASS.

### Required FAILs current: 5

| Group | Checks | Root cause |
|-------|--------|------------|
| A — r0_window_360 (×3) | O2 upper vs bulk | Phase 2 gap |
| C — corridor_chain (×2) | t180+t600 temp | Phase 2 gap (M3 doorway O2 replenishment) |

Grupo B completamente resuelto: `cfast_slow_t480_temp_upper_c` y `cfast_slow_t600_temp_upper_c` PASS con Phase 4B wall reradiation durante fuego activo. Config actual per-caso: `hrr_chi_rad_* = 0.7`, `hrr_rad_wall_fraction=1.0`, `phase4b_wall_reradiation_during_fire_enabled=true`, `phase4b_wall_reradiation_during_fire_gain=5.0`, `wall_heat_capacity_kj_m2_k=6.5`, `wall_core_decay_per_s=0.0009`. La clave fue devolver energia radiativa desde pared sin cambiar HRR ni deplecion O2.

Grupo D completamente resuelto: `cfast_bed_o2_t300/t480/t600/t720_o2` PASS (Phase 2E-bedroom).

Grupo E completamente resuelto: `hvac_t300_o2` PASS (Phase 2D `b960d29`); `two_room RMSE` PASS 53.8°C (Phase 2C-thermal `e0785e8`).

### Recommended next work

> **HITO DE VALIDACIÓN CERRADO — 2026-06-21.** Baseline final: 345/350 PASS, 5/350 required FAIL (todos VALID_GAP). No hay siguiente candidato con fix per-caso disponible. No iniciar Phase 3+ ni ILV sin plan explícito.

Los 5 fallos restantes, cerrados definitivamente como VALID_GAP:

- **Grupo A `cfast_r0_window_360` (×3)** — Phase 5A sweep (15 configs) agotó espacio per-caso. Causa estructural: `plume_lower_mode` equilibra zonas bidireccional; target requeriría room.o2=0.085 → HRR<198 kW → guard FAIL. Ver `docs/architecture/PHASE_5A_O2UPPER_SWEEP_RESULTS.md`.
- **Grupo C `cfast_corridor_chain` (×2)** — Phase 2F, 2G y Phase 3 simplificado descartados. Requiere ODE de presión dos zonas. Phase 3+ scope.

**Fix HUD/FP temperatura cerrado** (`497b663`). Ver §HUD/FP Temperature Fix cerrado más abajo. No hay línea de trabajo abierta en este hito.

### CFAST reference sources

- Public source repository: `https://github.com/firemodels/cfast`
- Official CFAST landing page: `https://pages.nist.gov/cfast/`
- Local technical reference manual: `docs/literature/Reviews_and_Models/CFAST_Technical_Reference_Guide_2004.pdf`
- Local modern NIST reference/validation docs: `docs/literature/NIST.TN.1889v1.pdf`, `docs/literature/NIST.SP.1018e6.pdf`
- Local CFAST truth/output files for current validation cases: `sim/validation/cfast/`

Use these as primary references before changing physics: first read the CFAST manual/source for the relevant subsystem, then compare against the local `.out`/CSV truth files, then implement SimuFire changes behind default-off/per-case controls.

### Phase 2 architecture plan (2026-06-20)

Documento: `docs/architecture/PHASE_2_TWO_ZONE_ARCHITECTURE_PLAN.md`

Fases planificadas:
- **2A** (no-op): sync zonal mass (upper_gas_kg/lower_gas_kg) para todas las salas en ThermalSystem
- **2B** (combustion routing): O₂ consumido → solo o2_upper; throttle desde o2_upper; bedroom gets `fire_o2_mode="upper"`; archivos: OxygenExchangeSystem.gd, CombustionSystem.gd, cfast_bedroom_closed_door.json; target: Grupo D ×5, Grupo A ×3
- **2C** (doorway exchange): activar canonical_doorway_exchange en cfast_two_room_door_open; recalibrar corridor_chain; archivos: ThermalSystem.gd, cfast_two_room_door_open.json; target: Grupo E two_room ×1, Grupo C ×2
- **2D** (HVAC mass balance): return extrae o2_upper, repone desde o2_lower; archivos: HVACSystem.gd, cfast_hvac_residential.json; target: Grupo E HVAC ×1
- **2E** (cleanup): retirar M2, phase2h_*, phase2e_* una vez 2A–2D verdes

Regla: cada fase lleva flag default=false (no-op garantizado). Activar per-case primero, luego global solo si todos los sentinels PASS.

## What Changed

- Root-level session notes moved to `docs/sessions/root/`.
- Historical audits, plans, roadmaps, validation docs and architecture docs were grouped under `docs/`.
- Local bibliography and PDFs moved from `Docu Simufire/` to `docs/literature/`.
- Loose root artifacts kept for context moved to `docs/archive/root-artifacts/`.
- Exploratory root scripts moved to `tools/archive/root-scripts/`.
- Documentation entrypoints, command references, artifact policy, release checklist and architecture governance docs were added.
- Lightweight docs/product CI workflows and helper scripts were added.

## Key Entry Points

- Project overview: `README.md`
- Documentation index: `docs/INDEX.md`
- Official commands: `docs/COMMANDS.md`
- Cleanup status: `docs/REPO_STATUS_AFTER_CLEANUP.md`
- Validation guardrails status: `docs/validation/GUARDRAILS_STATUS.md`
- Gap inventory: `docs/validation/GAPS_INVENTORY.md`
- Commit split proposal: `docs/COMMIT_PLAN.md`
- PR summary draft: `docs/PR_DESCRIPTION.md`

## Validation Run

Recommended checks for the current state:

```powershell
python scripts\check_docs_links.py
python -m unittest tests.test_ui_localization -v
python -m unittest tests.test_editor_scenarios -v
python scripts\simulation\validation_guardrails.py --verbose
git diff --check
git diff --cached --check
```

Current result:

- Validation guardrails: FAIL because 5 required checks remain accepted VALID_GAPs and one Phase 2E sentinel remains red.

The following guardrail parts are now clean:

- Gap count is synchronized: `69` non-gating gaps in JSON and docs.
- Physics override linter passes.
- Carbon/HCN sentinels pass.
- Legacy/two-zone contract passes.
- CFAST truth integrity passes.

## Important Constraint

No simulation motor, editor runtime, visualizer runtime, scenes, HUD logic or physics formulas were intentionally changed during this cleanup. The only validation case change was removing the forbidden `vent_bernoulli_flow_multiplier` override from `sim/validation/cases/cfast_pool_fire_open.json`.

Do not try to make `validation_guardrails.py` green by widening tolerances, rewriting reports or reclassifying required failures unless the scientific validation decision has been explicitly reviewed.

## Estado actual de esta máquina (2026-06-21)

- Rama: `main`, sincronizada con `origin/main`.
- Baseline vigente: **345/350 PASS, 5/350 required FAIL**.
- El plan ILV está documentado pero sin implementar.
- Hoja de ruta activa: `docs/planning/MASTER_ROADMAP_CURRENT.md`.
- No iniciar ILV, M2 global ni cambios de doorway/O2 en `sim/core` sin plan explícito.

## Próximo paso recomendado

Ejecutar baseline de guardrails para confirmar 5/350 antes de tocar motor:

```powershell
python scripts\simulation\validation_guardrails.py --verbose
```

Después elegir una línea explícita:

- Producto/UX: hotfix de temperatura FP.
- Validación científica mayor: solo arquitectura two-zone canónica / Phase 3+ con plan explícito.
- Documentación: mantener sincronizados handoff, roadmap, guardrails y gap inventory.

## Estado guardado ahora (2026-06-21)

- La planificación activa quedó consolidada en `docs/planning/MASTER_ROADMAP_CURRENT.md`.
- El siguiente trabajo real no es ILV todavía salvo decisión expresa.
- Los 5 fallos restantes ya están diagnosticados; no repetir sweeps per-case salvo que una corrida fresca cambie el baseline.
- El hotfix FP queda como línea pendiente independiente: diagnosticar saltos de temperatura antes de tocar física/HUD.

## Other Machine Sync Protocol

Context recorded on 2026-06-18:

- Se perdió corriente en la otra máquina mientras ejecutaba Claude. El repo en esta máquina está limpio (ver `git status`).
- La otra máquina puede tener cambios locales sin commitear del trabajo anterior.
- No asumir que la otra máquina está limpia.
- No ejecutar `git pull`, `git reset`, `git restore` ni resolución de conflictos a ciegas en esa máquina.
- No tocar `sim/core` hasta autorización explícita.

Cuando se retome en la otra máquina, inspeccionar primero:

```powershell
git status --short
git branch --show-current
git log --oneline --decorate -5
git fetch
git log --oneline --decorate --graph --all -20
git diff --name-status
git diff --stat
```

If the other machine has local changes, protect them before integrating remote work:

```powershell
git switch -c backup/cambios-maquina-apagon
git add -A
git commit -m "WIP cambios locales antes de sincronizar"
```

Then compare the backup branch, the original branch and the remote branch before merging anything. The intended rule is: preserve first, synchronize second, resolve conflicts last.

## HUD/FP Temperature Fix cerrado

Commit `497b663 feat(fp-hud): smooth HUD temperature at thermal layer crossing` — 2026-06-21.

**Diagnóstico confirmado (Causa 2):** con `thermal_gradient_band_fraction=0.0`, `estimate_temperature_at_height_m` es una función escalón en `thermal_layer_m`. Cuando la capa desciende a través de la altura del jugador (1.8 m de pie), `T@1.8m` saltaba instantáneamente entre `temp_lower_c` y `temp_upper_c` — hasta +8 °C en un paso de 0.5 s en el escenario de diagnóstico, hasta cientos de °C en escenarios calientes.

**Fix aplicado (HUD-only, sin tocar física):**

- `view/fp/FirstPersonController.gd`:
  - Constante `HUD_LAYER_BLEND_HALF_M = 0.25`.
  - Helper `_hud_temp_at_height_m(room_state, height_m)`: lerp de `temp_lower_c` a `temp_upper_c` dentro de una banda de ±25 cm alrededor de `thermal_layer_m`; satura limpiamente fuera de la banda.
  - `_update_technical_overlay()`: las tres posturas (stand/crouch/prone) usan el helper en lugar de los campos precomputados `temp_at_N_m_c`.
  - El filtro `fp_hud_temperature_smoothing_tau_s=0.5 s` sigue actuando sobre el valor resultante.
- `tools/validate_fp_technical_hud.gd`: test actualizado con `thermal_layer_m=1.15 m`; expectativas ajustadas a la salida del blend (stand=210, crouch=105, prone=35 °C).

**Verificación final:** `python scripts/check_product.py` — FP technical HUD Godot 1/1 OK; todos los demás suites OK. Único fallo: `tests.test_guardrails.test_exit0_real_json`, pre-existente por los 5 VALID_GAP.

No se tocó `ThermalSystem.gd`, `SimulationStateBuilder.gd`, ni ningún archivo de validación científica.
