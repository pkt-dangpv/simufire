# Phase 3+ F3.3d2 - Heskestad plume source-term experiment

Date: 2026-07-22

## Decision

**NO-GO and full code rollback.**

The missing Heskestad source term is a real plume-mass omission, but enabling
it alone improves mass/interface state by cooling an already under-energized
upper layer. It worsens both Group C temperature checkpoints and therefore
cannot be retained as an independent physical mechanism.

No F3.3d2 flag, telemetry, fixture or runtime code remains in the working
tree. Scratch evidence remains under `runs/phase3_f33d2`; official reports,
cases, baselines, tolerances, gaps and CTRL envelopes were not changed.

## Root cause tested

The canonical preview uses:

```text
Qc = HRR * plume_mccaffrey_qc_fraction
height term = 0.071 * Qc^(1/3) * z_eff^(5/3)
source term = 0.0018 * Qc
```

The Group C case fixes `plume_mccaffrey_qc_fraction=0.3`. Its radiative
fraction is 0.70, so this is internally consistent with the 30% convective
source used by SimuFire. CFAST uses a 0.35 radiative fraction and therefore a
65% convective source.

The source term is implemented locally but is currently enabled only when the
canonical exterior-counterflow request is active. That boundary condition is
not part of the Heskestad plume correlation. Group C consequently uses only
the height term.

This also explains the previous radiation control: changing `chi_rad` from
0.70 to 0.35 did not change plume mass because the independent plume Qc
fraction remained 0.3.

## Candidate

The experiment enabled the existing `0.0018 * Qc` source term unconditionally
inside the canonical shadow. It did not change the 0.071 coefficient, Qc
fraction, effective height, radiation, openings, pressure, walls or legacy
physics.

The request retained:

- the canonical lower-inventory cap;
- proportional lower sensible enthalpy and O2 payloads;
- the existing atomic combustion/plume bundle;
- exact accepted-route mass and enthalpy ledgers.

The deterministic Godot fixture verified that the source term was added once,
was not doubled when the old counterflow condition was also present, and
preserved inventory limiting and payload conservation.

## Group C results

### Plume mass by common window

| Window | CFAST | Base | Candidate | Base error | Candidate error |
|---|---:|---:|---:|---:|---:|
| 0-180 s | 97.716 kg | 70.766 kg | 81.250 kg | -27.6% | -16.9% |
| 180-300 s | 62.244 kg | 43.935 kg | 49.732 kg | -29.4% | -20.1% |
| 300-590 s | 157.101 kg | 100.887 kg | 110.200 kg | -35.8% | -29.9% |

The candidate improves all three plume windows, but its feedback lowers the
canonical interface and therefore reduces the height term. The source term
does not simply add its open-loop integral. Late O2/HRR throttling leaves a
large residual plume deficit.

### State checkpoints

| t | Metric | CFAST | Base | Candidate | Verdict |
|---:|---|---:|---:|---:|---|
| 180 | upper mass (kg) | 26.943 | 22.921 | 26.874 | strong improvement |
| 180 | lower mass (kg) | 15.406 | 25.000 | 20.365 | improvement |
| 180 | interface (m) | 0.736 | 1.101 | 0.909 | improvement |
| 180 | upper temp (C) | 159.82 | 125.70 | 114.18 | regression |
| 300 | upper mass (kg) | 25.949 | 22.890 | 27.489 | overshoot |
| 300 | lower mass (kg) | 15.562 | 24.651 | 19.747 | improvement |
| 300 | interface (m) | 0.773 | 1.104 | 0.891 | improvement |
| 300 | upper temp (C) | 166.27 | 124.05 | 112.00 | regression |
| 590 | upper mass (kg) | 25.249 | 23.794 | 27.285 | overshoot |
| 590 | lower mass (kg) | 15.794 | 25.802 | 22.435 | partial improvement |
| 590 | interface (m) | 0.808 | 1.140 | 0.990 | improvement |
| 590 | upper temp (C) | 168.80 | 97.53 | 90.09 | regression |

Upper energy changes only from 2422.7 to 2531.1 kJ at 180 s while upper mass
rises by 3.95 kg. At 590 s it changes from 1844.9 to 1912.5 kJ while upper
mass rises by 3.49 kg. The added near-lower-temperature gas therefore dilutes
the upper layer. This is physically consistent and confirms that the existing
convective-energy deficit and plume-mass deficit are coupled.

### Boundary watch items

| Window | Base door net out | Candidate door net out | Base exterior net out | Candidate exterior net out |
|---|---:|---:|---:|---:|
| 0-180 s | 7.692 kg | 7.494 kg | +1.987 kg | +2.866 kg |
| 180-300 s | 6.841 kg | 6.988 kg | -6.461 kg | -6.985 kg |
| 300-590 s | 12.281 kg | 13.379 kg | -14.336 kg | -15.862 kg |

The candidate does not hide its result through a large doorway change, but it
slightly increases late exterior inflow and doorway churn. Those remain guard
signals for the next experiment, not independent tuning targets.

## Conservation

All measured candidate residuals are exactly zero:

- upper/lower/room/building mass residence;
- upper/lower/room/building enthalpy residence;
- combustion atomic fraction remained 1.0 at sampled checkpoints.

The candidate fails physics correspondence, not conservation.

## STOP gate

| Check | Result |
|---|---|
| Structural tests before runtime | 36/36 PASS |
| Direct Godot fixture | PASS |
| 180 s Group C run | PASS |
| 600 s Group C run | PASS (`RUN_SCENARIO PASS`) |
| First 600 s attempt | invalid: runner timeout at 120 s; discarded |
| Plume error improved in all windows | yes |
| Mass/interface improved early and late | mostly yes |
| Both temperature checkpoints preserved | no; both regress |
| Candidate code retained | no; fully rolled back |
| Group A/full matrix | not run after binding NO-GO criterion |
| Official validation artifacts | unchanged |

## Next gate: F3.3e

F3.3e must be a design-first coupled convective-source/plume contract. One
authoritative `Qc` must drive both upper convective energy and the complete
plume correlation. It must explain how case radiation configuration,
combustion O2 throttling and Heskestad source/height terms correspond to CFAST
before another implementation is attempted.

Do not simply combine the rejected `chi_rad=0.35` and F3.3d2 patches. First
prove dimensional and temporal consistency, define which Qc is authoritative,
and predict both energy and mass budgets over all three windows. Any future
runtime candidate remains default OFF and requires its own STOP gate.
