# Phase 3+ F3.3v3h2.5d/e coupled pressure solver in gauge coordinates

Date: 2026-07-28

## Decision

- **F3.3v3h2.5d: NO-GO for a combined patch.** Two mechanisms were measured
  offline against both real captures. Neither alone closes both, the only
  combination that does is a net regression, and the globalization the phase was
  named after turned out to be irrelevant to both captures.
- **F3.3v3h2.5e: GO, partial.** The one mechanism that strictly dominates -
  a gauge-pressure unknown - is now in the solver. It closes the
  `r0_window_360` capture and its whole failure mode. It does **not** close
  `corridor_chain`, which stays an open failure and keeps blocking H3.

## H2.5d - what was measured, and why the obvious answer was rejected

Everything below is offline replay of the two committed captures. The harness
was validated bit-exact against both before any variant was believed.

### Exact captures

| config | corridor | r0_window |
|---|---|---|
| baseline: absolute + L-infinity | FAIL (3 it) | FAIL (4 it) |
| A: gauge unknown | FAIL (3 it) | **PASS (3 it), 9.6e-17** |
| B: Armijo + stagnation/cycle detection | FAIL (3 it) | FAIL (4 it) |
| non-monotone L-infinity | FAIL (24 it) | FAIL (6 it) |
| gauge + L2 acceptance merit | **PASS (6 it)** | **PASS (3 it)** |

### Neighbourhood, 41 perturbations per topology

| config | corridor | r0 | regressions | gains |
|---|---:|---:|---:|---:|
| baseline | 26/41 | 37/41 | - | - |
| **gauge** | 26/41 | **40/41** | **0** | 3 |
| non-monotone | 2/41 | 20/41 | - | - |
| gauge + L2 | **40/41** | 27/41 | **12** | 16 |

**Armijo cannot help either capture, and this is structural**: a sufficient
decrease test is *stricter* than plain decrease, so it can never rescue a step
that already fails plain decrease. Cycle detection was proven to work - fed the
H2.5c centred-difference stimulus it reports `cycle_detected` at iteration 3,
diagnostically, never as convergence - and it never fires on either capture
under the shipped forward quotient. It is a correct safety net that would have
caught the H2.5c regression automatically, and it is a fix for nothing here.

**gauge and L2 are antagonistic.** L2 acceptance closes corridor (26 -> 40) and
wrecks r0 (37 -> 26). The combination passes both exact captures - meeting the
letter of the H2.5d gate - while breaking 12 neighbourhood cases the baseline
solved. That is the signature that preceded H2.5c's 86% -> 0.14% collapse, so
it was rejected despite passing the stated criterion. Gauge alone has zero
regressions.

## H2.5e - the change

One file: `sim/core/Phase3CoupledPressureSolver.gd`.

The unknown is now the gauge pressure relative to the exterior reference the
solve was given. Three places had to change together, and getting any one of
them wrong reintroduces the defect:

1. **The unknown and its seed.** The seed is read from a `gauge_pressure_pa`
   derived per room, never formed as `pressure_abs_pa - exterior`.
2. **The opening difference** is `q_a - q_b`, with the exterior at exactly zero,
   instead of subtracting two numbers near ambient to obtain something near
   zero.
3. **The EOS residual** is expanded about a per-room reference mass
   `M_ref = P_ext V / (R T_ref)`:

   ```text
   implied_gauge = (R T_ref / V) (M - M_ref) + (R / (cp V)) E
   ```

   Forming `implied_abs - exterior_abs` instead would have discarded about four
   significant digits to cancellation - exactly what this phase removes. The
   reference-mass form cancels about 1.7 digits, lowering the residual's
   rounding floor from `1.455e-11 Pa` to `1.14e-13 Pa`, a factor of 128.

`pressure_by_room` is rebuilt in absolute terms in `_pressure_map` and nowhere
else. The returned contract is unchanged, so `Phase3ZoneMassSystem`, the engine
and the runners are untouched.

`R = P_ref / (rho_ref T_ref)` still uses the canonical constant. It is the EOS
gas constant, not the exterior boundary, and tying it to the boundary would
change the physics.

### Explicitly not changed

Jacobian (still one-sided forward at `1e-3 Pa`), merit (still L-infinity
normalized by room inventory), damping schedule, tolerance (`1e-12`),
regularization width, band segments, flux law. No new tuning knob.

`exterior_pressure_abs_pa` is accepted through `options`, defaulting to
`AIR_PRESSURE_REF_PA`. It is a physical boundary condition with an unchanged
default, not a per-case knob - and it is what makes "use the reference this
solve received" a testable statement rather than a comment.

## Runtime gate

Ten runs before, ten after, all reaching full `duration_s`.

| stage | convergence before | after | damping_exhausted | iteration_cap |
|---|---:|---:|---:|---:|
| corridor 10 s | 66.67% | **67.50%** | 1 -> 0 | 39 -> 39 |
| corridor 30 s | 82.83% | **83.10%** | 16 -> 15 | 46 -> 46 |
| corridor 60 s | 86.39% | **86.53%** | 52 -> 51 | 46 -> 46 |
| corridor 120 s | 81.33% | **81.40%** | 52 -> 51 | 217 -> 217 |
| **r0_window_360 120 s** | 86.33% | **91.33%** | **72 -> 0** | 125 -> 125 |

- no stage regresses;
- `r0_window_360` improves by 5.0 points and its `damping_exhausted` mode is
  **eliminated entirely**;
- `iteration_cap` is unchanged everywhere, which is exactly right: gauge
  addresses the numerical-floor mode and nothing else;
- OFF runs byte-identical on all five pairs (SHA-256);
- ON adds no live-column movement - the isolation analyzer exits 0 on all five;
- zero counterflow violations; `max_normalized_residual = 0.0` on converged
  steps;
- runtime cost went **down**: `r0w360_120_on` 91.0 s -> 85.6 s,
  `corridor_120_on` 132.0 s -> 105.0 s.

Physics 9 PASS / 15 CTRL / 5 WARN / 0 FAIL; ILV 14 CTRL / 0 FAIL; gap inventory
unchanged at 6 VALID_GAP + 71; guardrails 9/10 with only the expected
dirty-motor R2-1.

## What is still open

**The `corridor_chain` capture still fails**, deterministically, and its fixture
still says so. Its mode is understood - the L-infinity acceptance test rejects a
step that fixes two rooms out of three because it worsens the current worst room
by 2.4% - and every remedy measured so far either does not help (Armijo, gauge),
pays for it elsewhere (L2), or is far worse (non-monotone).

**H2 is not resolved and H3 stays blocked.** A future phase must close corridor
without regressing `r0_window_360`, and both captures are the gate.

The exact captures are historical records and were **not** re-recorded. The
`corridor_chain` residual history is no longer reproducible bit for bit, because
removing the cancellation moved it in the tenth significant digit and Newton
amplifies that to about 2e-7 by the third iterate. The fixture now separates the
two things that recording used to test at once: a pure encoding round-trip that
involves no solver, and a behavioural check on the failure mode plus the stall
value.

## Unchanged

No legacy physics, FED, HVAC, visual, official case, report, baseline, expected
value, tolerance, CTRL envelope or VALID_GAP classification changed.
