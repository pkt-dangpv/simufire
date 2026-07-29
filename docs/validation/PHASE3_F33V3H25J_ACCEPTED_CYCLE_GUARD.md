# Phase 3+ F3.3v3h2.5j - Accepted-Cycle Guard

Date: 2026-07-29

Status: **GO with the revised cross-topology gate. Pending commit.**

The original gate incorrectly assumed that `r0_window_360` did not contain the
period-2 pathology. Runtime evidence shows 186 genuine activations with the same
signature, removing all 125 previous `iteration_cap` failures without creating
any regression. The revised gate permits cross-topology activation only under
the invariants listed in the STOP decision below.

## Scope

H2.5i identified a period-2 Newton zigzag hidden by monotonic L-infinity
residual decrease. Two consecutive full Newton steps can be nearly opposite
while the nonlinear sum-of-squares merit delivers less than 5% of the
improvement predicted by the linear model.

H2.5j adds an accepted-cycle guard after the existing L-infinity backtracking:

- both steps must have been accepted at full damping;
- both model gain ratios must be below `0.05`;
- their cosine must be below `-0.99`;
- the existing one-step LM budget must still be available.

The guard reuses the bounded H2.5g LM recovery. It does not add a second rescue
budget. If LM declines, the ordinary accepted Newton candidate is preserved.
The tolerance, iteration cap, Jacobian, regularization and signed square-root
orifice law are unchanged.

## Runtime Matrix

All runs used `scripts/run_scenario.py` and the full H2 passive stack.

| Scenario / stage | Convergence before | Convergence after | `iteration_cap` before/after | `damping_exhausted` before/after | Guard accepted |
| --- | ---: | ---: | ---: | ---: | ---: |
| corridor 10 s | 67.50% | 99.17% | 39 / 1 | 0 / 0 | 70 |
| corridor 30 s | 87.26% | 99.17% | 46 / 3 | 0 / 0 | 124 |
| corridor 60 s | 92.08% | 98.06% | 46 / 3 | 11 / 11 | 146 |
| corridor 120 s | 84.18% | 87.16% | 217 / 174 | 11 / 11 | 468 |
| r0_window 120 s | 91.33% | 100.00% | 125 / 0 | 0 / 0 | 186 |

There is no `iteration_cap -> damping_exhausted` displacement. The remaining
120 s corridor failures are still visible: 174 `iteration_cap` and 11
post-budget `damping_exhausted`.

## Late Corridor Limitation

The aggregate 120 s improvement is entirely earned before 60 s:

| Window | Failures before | Failures after | Improvement |
| --- | ---: | ---: | ---: |
| 0-60 s | 57 | 14 | 43 |
| 60-120 s increment | 171 | 171 | 0 |

The safeguard therefore does **not** fix the late corridor regime. Between
80.1 and 90.1 s it accepts 120 LM rescue steps and the solve still records 120
new `iteration_cap` failures. The last measured gain ratio there is about
`0.0478`, close to the `0.05` boundary, rather than the deep cycle signature
seen in the canonical capture and much of r0-window.

Across corridor 120 s, roughly 294 of 468 accepted guard activations do not
produce a newly converged solve. They add up to five linear solves plus
backtracking per attempt. This is not a regression in state or failure count,
but it is an explicit cost and selectivity limit for H2.5k.

## Invariance And Safety

- OFF CSVs are SHA-256 identical to the H2.5g OFF artifacts in all five stages.
- ON shared live columns are identical: 807 shared corridor columns and 800
  shared r0-window columns, with zero differences.
- The preview adds four opt-in cumulative telemetry fields only.
- Zero counterflow violations were observed.
- Converged steps report maximum normalized residual `0.0`.
- Where both old and new previews converge, solved pressures and net mass are
  identical in every sampled row.
- The real H2.5h capture changes from `iteration_cap` at 24 iterations to
  convergence in 8 iterations with one guard and one bounded LM rescue.
- A runtime mutation disabling the guard restores the original
  `iteration_cap`, exits the fixture with code 1 and emits no PASS marker.

## Verification

| Check | Result |
| --- | --- |
| Targeted H2.5j/H2.5h/H2.5g tests | 53 PASS |
| Godot fixtures H2.5h/g/a/c/e, H1, g2/g1/f0 | PASS |
| `pytest tests -k "phase3 or guardrail"` | 1075 PASS / 2 expected failures |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 353 required + 6 VALID_GAP + 71 non-gating |
| Guardrails | 9/10; only R2-1 because motor is dirty |

The two pytest failures are the historical
`test_csv_exports_three_canonical_layers` and the expected dirty-motor R2-1
through `test_exit0_real_json`.

## Godot Process Integrity Audit

Four native Godot popups occurred after the scenario matrix, during direct
fixture and negative-control execution. They were traced to restricted agent
launches of the Godot console/GUI pair, not to the solver or scenario runtime.

All ten matrix manifests completed before the popups. A controlled H2 run
outside the sandbox reproduced `sim_log.csv`, `sim_log.txt` and `events.json`
bit-for-bit. The nine critical fixtures and both gate-defining 120 s ON
scenarios were subsequently repeated outside the sandbox. Fixtures passed 9/9;
both scenarios completed at 120.083 s; CSV, technical log and events were
byte-identical to the original H2.5j artifacts; no Godot error, residual process
or new popup appeared. See `GODOT_471_HEADLESS_CRASH_AUDIT.md`.

## STOP Decision

**GO with the revised gate.** The old zero-activation requirement for
`r0_window_360` is retired because it prohibited correcting 125 failures with
the same measured period-2 signature. Activation outside corridor is accepted
only when all of the following hold:

1. the guard removes existing solver failures rather than creating new ones;
2. OFF output remains byte-identical;
3. shared live ON values remain identical;
4. already-converged sampled roots remain unchanged;
5. no counterflow, conservation or validation regression appears.

H2.5j satisfies all five conditions. The GO covers this bounded safeguard only.
H2 remains open, H3 remains blocked, and H2.5k must address late-regime
selectivity/cost without widening the LM budget or tuning per scenario.
