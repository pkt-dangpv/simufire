# Phase 3+ F3.3v3g3 persistent pressure-network shadow

Date: 2026-07-26

## Decision

F3.3v3g3 is **NO-GO at stage 1 (30 s)**.

The mechanism is exact. The physics is not.

Letting the F3.3v3g2 blended routes drive the persistent canonical shadow
reproduces the F3.3v3f3 failure class - one-way pressure feedback - even though
the transport is now bounded by a network solve with descent, pressure-crossing
and inventory limits.

Stages 2, 3 and 4 (60, 120 and 180 s) were **not launched**, as required.

The experimental runtime patch was **fully reverted** after collecting the
stage-1 evidence. No g3 flag, call site, persistent application path, CSV
schema, Godot fixture or structural wiring test remains in the repository.
F3.3v3g2 is the current committed motor state.

## Experimental wiring evaluated (not retained)

The experiment added a default-OFF flag,
`phase3_canonical_fixed_gross_pressure_network_persistent_shadow_enabled`,
effective only under the complete F3.3v3g2 stack and separate from it.

With the flag OFF the F3.3v3g2 preview stays exactly passive. With it ON, the
canonical interior bundle drops both the base `canonical_interior_opening`
routes and the additive `canonical_interior_pressure` routes and applies the
blended fixed-gross set instead:

```text
build interior_opening routes  ->  network_routes           (base)
build signed pressure routes   ->  pressure_routes_raw      (raw demand)
    |
    +-- legacy additive relaxation -> pressure_routes
    +-- F3.3v3f1 preview            (passive)
    +-- F3.3v3g2 preview            (passive, raw demand, blended routes)
    |
    +-- g3 OFF: append pressure_routes to the bundle          <- unchanged
    +-- g3 ON : replace network_routes with the blended set,
                never append pressure_routes                  <- candidate
```

Replacement, never addition. There is still exactly one atomic bundle
(`f33a_interior_network`), route and connection identities are unchanged, and
one alpha per connected component drives mass, sensible enthalpy, O2 and every
species. Pressure-driven doorway jets are dropped with the routes they follow.

The next timestep's pressure is derived from the updated canonical persistent
state through the existing EOS. No separate pressure accumulator exists.

## Retained artifacts

| File | Change |
|---|---|
| `scripts/simulation/analyze_phase3_f33v3g3_persistent_pressure_network.py` | read-only staged-gate analyzer for the captured OFF/ON CSVs |
| `tests/test_analyze_phase3_f33v3g3_persistent_pressure_network.py` | analyzer contracts, with the real-run assertion skipped when scratch CSVs are absent |
| `docs/validation/PHASE3_F33V3G3_PERSISTENT_PRESSURE_NETWORK.md` | binding result, failure owner and next architectural constraints |

The experiment temporarily touched `Phase3ZoneMassSystem`, engine/state/log
wiring, both runners, a Godot fixture and structural tests. All of those
runtime changes were reverted. No legacy physics, FED, HVAC, visual, official
case, report, expected value, tolerance, CTRL envelope or VALID_GAP
classification changed.

## Stage 1 - 30 s

Scenario `runs/phase3_f33t/cases/corridor_on.json`, Godot `4.7.1`, complete
F3.3v stack. Baseline is g2 ON / g3 OFF; candidate is g2 ON / g3 ON. The two
runs differ by exactly one flag.

### What passed

| Check | Result |
|---|---:|
| Rows baseline / candidate | 24 / 24 |
| Live (non `phase3_shadow_*`) columns | 115 |
| **Live value differences** | **0** |
| Columns lost | 0 |
| New columns | 58, all `..._persistent_*` |
| Canonical shadow columns changed | 239 (expected: this is the point) |
| Mass residual | `0.0` |
| Energy residual | `0.0` |
| O2 residual | `0.0` |
| Species residual | `0.0` |
| Gross mass residual per step | `0.0` |
| Minimum accepted bundle fraction | `1.000000` |
| Bundle double-limit events | `0` |
| Unexpected zone collapses | `0` |
| EOS invalid steps | `0` |
| Minimum post lower shadow gas | `30.158 kg` |
| Accepted transport bidirectional | yes (`+0.0466` / `-0.0396 kg`) |
| Live-isolation violations | `0` |

The candidate is atomically clean. Gross mass is preserved exactly at every
step, and the atomic bundle accepted the full requested fraction at every
step - so the F3.3v3g2 inventory bound is already sufficient and no second
limiting stage occurs.

### What failed

| Check | Limit | Measured |
|---|---:|---:|
| `no_pressure_runaway` | ratio `<= 2.0` | **`5.65`** |
| `no_monotonic_request_growth` | `< 10` intervals | **`111`** |
| `no_prediction_runaway` | `< 10` intervals | **`239`** |
| `cap_count_within_2x_baseline` | `<= 158` | **`717`** |

R0 canonical shadow gauge pressure, baseline versus candidate:

| t (s) | baseline (Pa) | candidate (Pa) | ratio | baseline request (kg) | candidate request (kg) |
|---:|---:|---:|---:|---:|---:|
| 10.0 | 1.116 | 1.202 | 1.08 | 0.0479 | 0.1545 |
| 20.1 | 6.292 | 14.279 | 2.27 | 0.1025 | 0.2444 |
| 30.1 | 23.195 | **131.020** | **5.65** | 0.3625 | **1.8382** |

The relaxed pressure request - the same basis as the F3.3v3f2 `6.368 kg`
reference - is already `1.838 kg` at 30 s, `5.07x` the baseline at one sixth of
the duration.

### The owner

The network objective that the *same* solve evaluates diverges:

| t (s) | baseline `J_pre` (Pa2) | candidate `J_pre` (Pa2) | ratio | candidate alpha | predicted `J_post` | observed next `J` |
|---:|---:|---:|---:|---:|---:|---:|
| 10.0 | 0.0 | 0.0 | - | 0.01456 | 0.0 | 0.0 |
| 20.1 | 25.5 | 155.0 | 6.07 | 0.00063 | 154.8 | 155.1 |
| 30.1 | 126.3 | **16438.2** | **130.1** | **1.00000** | 5614.7 | **16684.8** |

Two facts explain the failure together:

1. **Alpha escapes its bounds by construction.** Early on the pressure-crossing
   bound holds alpha near zero (`0.0006` at 20 s). Once the imbalance is large
   the unconstrained optimum reaches `1.0`, the crossing bound stops binding,
   and the *full* fixed-gross skew is applied. At 30.1 s the accepted route set
   is completely one-directional: `out = 0.013084 kg`, `in = 0.000000 kg`. The
   doorway counterflow is gone, replaced by pure one-way flow of the same gross
   mass.

2. **The objective is not a Lyapunov function for the coupled system.** At
   30.1 s the solve predicted it would reduce the disequilibrium to
   `5614.7 Pa2`; the next step actually showed `16684.8 Pa2`. Canonical
   pressure is co-owned by the plume, combustion and exterior leakage, none of
   which the network solve sees. Minimizing the instantaneous interior-network
   objective therefore over-corrects, and the over-correction compounds.

This is the same failure class as F3.3v3f3, reached through a bounded network
solve instead of direct route substitution. The descent, crossing and inventory
bounds are individually correct and individually insufficient.

### Not used as evidence

At 30 s the CFAST envelope is meaningless and was deliberately excluded from
the stage gate: the **baseline itself** is `-51.12%` on gross mass and
`-17.63%` on net enthalpy at that checkpoint, because the fire is still
growing. Both only approach the 5% envelope near 180 s. Gating an early stage
on a 180 s target would have compared the candidate against a target the
accepted architecture does not meet either.

For the record, at 30 s: baseline gross `-51.12%`, net mass `-57.90%`, net
enthalpy `-17.63%`; candidate gross `-43.84%`, net mass `+122.85%`, net
enthalpy `+18.05%`. The candidate overshoots net mass rather than
undershooting it - consistent with the one-way transport above, and further
evidence against promotion.

The three known ignition-transient fail-closed steps stayed bounded to the
first logged interval, as required. They are not part of the failure.

## Verification

| Suite | Result |
|---|---|
| Godot 4.7.1 g3 fixture during experiment | `PHASE3_F33V3G3_PERSISTENT_PRESSURE_NETWORK_PASS` (fixture removed with candidate) |
| Godot 4.7.1 g2 / g1 / f0 fixtures | PASS |
| `pytest tests -k "phase3 or guardrail"` | 805 PASS / 2 FAIL |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 353 required + 6 VALID_GAP + 71 non-gating, synchronized |
| Guardrails | 9/10, only R2-1 |

The 2 failures are the established repository baseline: `test_exit0_real_json`
is the expected R2-1 freshness gate while `sim/core` is dirty, and
`test_csv_exports_three_canonical_layers` is a historic structural failure
already reproduced at a clean `HEAD` in the previous session.

## What this rejects

Do not retry any of the following as a persistent-shadow candidate:

- applying the F3.3v3g2 blended routes to persistent state under the current
  bounds;
- tightening only the crossing bound - it already stops binding exactly when
  the imbalance is large enough to matter;
- adding a fixed under-relaxation factor tuned until 180 s passes; that is
  curve-fitting to a checkpoint, and F3.3v3g0 explicitly forbids it;
- capping alpha below 1.0 by fiat without a physical justification for the cap.

## Next architectural gate

The next phase must stop treating interior-network pressure equilibrium as an
objective that can be minimized independently each step. At minimum it must:

1. include the other pressure owners (plume, combustion, exterior leakage) in
   the residual the solve reduces, or prove they are negligible over one step;
2. define a stability criterion on the *coupled* pressure trajectory, not on
   the instantaneous interior objective;
3. keep the counterflow structure - an accepted alpha that zeroes one direction
   of a doorway is a physical red flag, not a valid optimum;
4. define rollback from a measured divergence signal, not from a checkpoint
   comparison.

The F3.3v3g2 passive preview remains committed, correct and default OFF. The
F3.3v3g1 primitive remains correct as a pure function. Neither is invalidated
by this result; only their promotion to persistent authority is.

## Evidence replay

```powershell
python scripts\simulation\analyze_phase3_f33v3g3_persistent_pressure_network.py `
  --stage 030 --json-out runs\phase3_f33v3g3\stage_030.json
```

The analyzer reads the captured scratch CSVs under
`runs/phase3_f33v3g3/030_off` and `runs/phase3_f33v3g3/030_on`. Those run
artifacts are intentionally uncommitted and may be absent in a fresh clone.
The removed runtime flag must not be recreated merely to replay this rejected
candidate.

The analyzer exits non-zero unless every duration-independent contract holds.
It intentionally succeeds only when both facts are provable: live isolation is
exact, and the candidate is stable. At stage 1 the first holds and the second
does not.

Godot must always be given a `--log-file` inside an existing directory; a
missing parent directory makes headless Godot crash with signal 11 before any
script runs, which is easy to misread as a script defect.
