# Phase 3+ F3.3v3h2 passive coupled pressure solver preview

Date: 2026-07-27

## Decision

F3.3v3h2 is **GO as a passive default-OFF preview**. Runtime authority and any
persistent application path remain **NO-GO**. H3 is not started.

The new `phase3_coupled_pressure_solver_shadow_enabled` flag is default OFF and
effective only under the canonical interior-opening stack. When active it runs
the pure F3.3v3h1 solver over the already-resolved canonical step and records
how the coupled solution differs from what the legacy interior path actually
did. It emits no route, no bundle and no physical state.

## Wiring

The preview runs at the tail of `finalize_step`, **after** the exterior
boundary has been applied, so every owner's accepted contribution is known:

```text
queue_canonical_interior_opening_requests
    +-- capture dt, reference temperature and the opening descriptors
        (the same geometry the legacy path used)
...
finalize_step
    +-- apply every queued request and atomic bundle
    +-- _collapse_degenerate_zones
    +-- _apply_canonical_exterior_boundary_requests
    +-- F3.3v3h2 preview          <- reads pre-step + resolved shadow
```

### Owner sources are recovered exactly, with no new plumbing

```text
owner_source_r = (post_r - pre_r) - interior_network_accepted_r
```

Because the interior network bundle carries both the base opening routes and
the additive pressure routes, subtracting its accepted totals from the total
step delta leaves precisely the sum of every other owner: combustion,
multisurface, exterior, plume, inter-zone, parcels and legacy. Those enter the
solver residual at their real accepted magnitude.

That is the property F3.3v3g3 lacked, and it is why this preview is a
meaningful test of the H0 architecture rather than a repeat of the same
mistake.

### Deliberate limits of this phase

- **Exterior openings stay a fixed source, not a solved flux.** Promoting them
  into the solve is an H3 question. The cost of freezing them is visible in
  the divergence this records.
- **The density profile, interface height and donor-cell specific enthalpy are
  frozen** within one solve, exactly as the H1 contract documents. Only the
  pressures and the opening fluxes are implicit.
- The preview is evaluated **after** the step, so it answers "what would the
  coupled transport have been, given identical owner sources", not "what would
  the trajectory have been". Trajectory questions belong to H3.

## Files changed

| File | Change |
|---|---|
| `sim/core/Phase3ZoneMassSystem.gd` | preview context capture, recorder, ledgers, 37 result fields, one passive solver call site |
| `sim/core/SimulationEngine.gd` | exported flag, `_phase3_coupled_pressure_solver_active()`, system and log-writer wiring |
| `sim/core/SimulationLogWriter.gd` | opt-in `_phase3_coupled_solver_fields()` header and row |
| `sim/core/SimulationStateBuilder.gd` | flag exported into the summary state |
| `scripts/run_scenario.py`, `tools/run_scenario_headless.gd` | `--phase3-coupled-pressure-solver-shadow` plus its parent stack |
| `scripts/simulation/analyze_phase3_f33v3h2_coupled_solver_preview.py` | new isolation and behaviour analyzer |
| `tests/test_phase3_f33v3h2_coupled_solver_preview.py` | 13 structural contracts |
| `tests/test_analyze_phase3_f33v3h2_coupled_solver_preview.py` | 7 analyzer contracts |
| `tests/test_phase3_f33v3h1_coupled_pressure_solver.py` | the H1 "no call site" contract becomes "exactly one passive call site" |

No physics, legacy path, official case, report, baseline, expected value,
tolerance, CTRL envelope or VALID_GAP changed.

## Isolation: OFF is bit-identical

| Scenario | Rows OFF/ON | Shared columns | Shared differences | New columns |
|---|---:|---:|---:|---:|
| `corridor_chain` 10 s | 12 / 12 | 807 | **0** | 37 |
| `corridor_chain` 30 s | 24 / 24 | 807 | **0** | 37 |
| `corridor_chain` 60 s | 42 / 42 | 807 | **0** | 37 |
| `cfast_r0_window_360` 120 s | 78 / 78 | 800 | **0** | 37 |

Zero columns lost in any run, and all 37 new columns are in the
`phase3_shadow_coupled_solver_` family. ON changes no legacy column and no
canonical shadow column, because the preview writes only its own ledger.

## Solver behaviour

| Scenario | Steps | Converged | Iteration cap | Damping exhausted | Max residual | Counterflow violations |
|---|---:|---:|---:|---:|---:|---:|
| 10 s | 120 | 66.7% | 39 | 1 | `0.0` | 0 |
| 30 s | 361 | 82.8% | 46 | 16 | `0.0` | 0 |
| 60 s | 720 | 86.4% | 46 | 52 | `0.0` | 0 |
| window 120 s | 1441 | 86.3% | 125 | 72 | `0.0` | 0 |

Three things follow.

1. **Every converged step closes its residual exactly.** The maximum
   normalized residual across every run is `0.0` at CSV precision. When the
   solver says it converged, the mass balance is closed.
2. **Counterflow never breaks.** Zero violations in 2642 solved steps across
   both scenarios. The structural neutral-plane split holds in the real
   pressure field, not just in the synthetic fixture.
3. **Convergence is not universal, and the two failure modes behave
   differently.** Iteration-cap failures are concentrated in the ignition
   transient: the cumulative count on `corridor_chain` reaches 39 by 10 s, 46
   by 20 s, and then **stops increasing entirely** through 60 s.
   Damping-exhausted failures instead accumulate slowly with time
   (1 → 16 → 52). They are separate problems and are counted separately.

## The substantive finding: the coupled solve equalises the chain

R0 at 60 s, all three connected rooms:

| Room | Coupled solved (Pa) | Legacy observed (Pa) | Delta (Pa) |
|---|---:|---:|---:|
| 0 | 172.361 | 202.598 | -30.237 |
| 1 | 172.434 | 153.963 | +18.471 |
| 2 | 172.427 | 133.304 | +39.123 |

The coupled solution leaves a spread of `0.07 Pa` across the chain. The legacy
additive path leaves `69.3 Pa`. Across three rooms joined by open doorways, a
69 Pa standing difference is not physical: it is the signature of a transport
that under-moves mass.

The net-mass column says the same thing directly. At 60 s, room 0:

| | Coupled | Legacy | Ratio |
|---|---:|---:|---:|
| Net mass out (kg/step) | `0.023933` | `0.007218` | **3.32x** |

The coupled solve transports about `3.3x` more net mass through the doorway
than the legacy additive path. That is consistent in sign and rough magnitude
with the standing F3.3v3f1 measurement that canonical net doorway mass is
`-55.49%` against CFAST — the legacy path under-transports, and the coupled
formulation moves in the direction that would close that gap.

**This is evidence about direction, not a correspondence claim.** The preview
cannot evolve the trajectory, so nothing here shows the CFAST error would
actually close. That is exactly what H3 must measure.

### Contrast: a simple network barely diverges

On `cfast_r0_window_360` the maximum divergence is `0.17 Pa` and the maximum
net-mass difference `0.000052 kg`, against `87.80 Pa` and `0.026462 kg` on
`corridor_chain`. Where the interior network is small and its gradients weak,
the two formulations agree. The divergence is specific to a multi-room chain
carrying real pressure gradients, which is where the accepted architecture is
known to be weakest.

## Naming correction

The divergence column was initially called `pressure_prediction_error_pa`. That
name is wrong and was changed to `coupled_vs_legacy_pressure_delta_pa` before
any result was recorded. It does not measure solver accuracy: the solver
predicts the pressure the *coupled* transport would produce, while `observed`
is what the *legacy* transport actually produced, and the two differ by
construction. Solver accuracy is `normalized_residual`, which is zero on every
converged step. A test now forbids the old name.

## Verification

| Suite | Result |
|---|---|
| Isolation, 4 scenarios | `preview_pass` on all four |
| `pytest -k "phase3 or guardrail"` | 954 PASS / 2 FAIL |
| H2 structural contracts | 13 PASS |
| H2 analyzer contracts | 7 PASS |
| H1 / g2 / g1 / f0 Godot fixtures | PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 353 required + 6 VALID_GAP + 71 non-gating |
| Guardrails | 9/10, only R2-1 while `sim/core` is dirty |

The 2 full-suite failures are the established baseline: `test_exit0_real_json`
is the R2-1 freshness gate, cleared by a separate timestamp commit;
`test_csv_exports_three_canonical_layers` is the historic structural failure
already reproduced at a clean `HEAD`.

## Limits and what H3 must resolve

1. **13.6% of steps do not converge** on `corridor_chain` at 60 s. That is the
   headline blocker. The two modes need different remedies:
   - *iteration cap*, concentrated in the ignition transient, is plausibly a
     bad initial guess — Newton starts from the pre-step pressure, which is far
     from the solution when the fire is ramping;
   - *damping exhausted*, growing with time, means no step length reduced the
     residual, which points at Jacobian quality rather than the starting point.
   Neither may be addressed by loosening a tolerance or raising the cap without
   first identifying which one is binding.
2. **Exterior openings are frozen sources.** If H3 promotes them into the
   solve, the divergence measured here will change, and the H2 numbers are the
   baseline to compare against.
3. **No trajectory evidence exists.** Everything here is a single-step
   comparison against a step the legacy path already took. The direction is
   encouraging; nothing more can be claimed until a persistent shadow runs.
4. The preview costs a full Newton solve per physical step. Step-time impact
   was not measured and should be before any always-on use.

## Reproduction

```powershell
$base = "--phase3-canonical-unfiltered-fire-growth-shadow",
        "--phase3-canonical-fire-products-routing-shadow",
        "--phase3-canonical-fuel-object-sync-shadow",
        "--phase3-cfast-buoyancy-destination-shadow"

python scripts\run_scenario.py runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33v3h2\060_off --duration 60 --timeout 1500 @base

python scripts\run_scenario.py runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33v3h2\060_on --duration 60 --timeout 1500 @base `
  --phase3-coupled-pressure-solver-shadow

python scripts\simulation\analyze_phase3_f33v3h2_coupled_solver_preview.py `
  --stage 060 --json-out runs\phase3_f33v3h2\stage_060.json
```

The analyzer exits non-zero unless isolation is exact, the preview is active,
every converged step closes its residual and no counterflow violation occurs.
It measures the convergence rate but deliberately does not gate on it:
characterising that rate is what this phase is for.
