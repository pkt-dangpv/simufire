# Phase 3 F3.3p - Coupled Qc re-entry design

Date: 2026-07-24

## Decision

**Design GO for one staged, default-OFF F3.3p1 runtime experiment. The former
lower-zone collapse is not considered resolved yet.**

F3.3n supplies enough new evidence to justify retesting the unified source
contract removed after F3.3e1, but not enough to promote it or run directly
to 600 s. The next candidate must combine:

```text
accepted canonical HRR
    -> one effective radiative fraction
    -> one accepted convective HRR, Qc
    -> convective heat and complete Heskestad plume

hydrostatic opening slabs
    -> existing F3.3n CFAST flogo receiver split
```

No motor code, official case, report, baseline, expected value, tolerance,
gap, CTRL, FED path or HVAC path changes in F3.3p.

## Evidence revisited

F3.3e1 failed at 600 s because its lower reservoir reached zero. At the time
the accepted plume became inventory-limited, so the late plume deficit was a
symptom of the empty lower zone rather than a failure of the Heskestad
equation.

F3.3n now routes receiver deposition with the exact CFAST `flogo` helper.
Against the preceding F3.3m state, this increases R0 net lower return by:

| Time | F3.3m net lower return | F3.3n net lower return | Gain |
|---:|---:|---:|---:|
| 180 s | 34.61 kg | 40.79 kg | +6.18 kg |
| 300 s | 69.12 kg | 78.84 kg | +9.72 kg |
| 600 s | 153.41 kg | 174.33 kg | +20.92 kg |

That improvement is real but does not by itself prove that a CFAST-sized
plume can be sustained. The complete lower-zone comparison is:

| t | SF lower | SF plume | CFAST plume | SF lower inflow | CFAST lower destination inflow | SF lower outflow | CFAST lower source outflow | Missing route margin |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 60 s | 34.53 kg | 24.03 kg | 29.94 kg | 3.11 kg | 6.71 kg | 1.43 kg | 1.34 kg | 3.68 kg |
| 120 s | 27.45 kg | 50.29 kg | 67.48 kg | 25.14 kg | 35.38 kg | 2.96 kg | 1.34 kg | 11.86 kg |
| 180 s | 24.05 kg | 72.03 kg | 97.72 kg | 46.11 kg | 65.78 kg | 5.32 kg | 1.34 kg | 23.65 kg |
| 300 s | 23.88 kg | 111.34 kg | 159.96 kg | 104.98 kg | 132.30 kg | 26.14 kg | 1.34 kg | 52.12 kg |
| 600 s | 24.78 kg | 207.97 kg | 317.06 kg | 244.17 kg | 299.11 kg | 69.84 kg | 1.34 kg | 123.44 kg |

`Missing route margin` is:

```text
(CFAST lower destination inflow - SF lower inflow)
+ (SF lower source outflow - CFAST lower source outflow)
```

It tracks the plume discrepancy closely:

| t | CFAST plume minus SF plume | Missing route margin |
|---:|---:|---:|
| 180 s | 25.69 kg | 23.65 kg |
| 300 s | 48.62 kg | 52.12 kg |
| 600 s | 109.09 kg | 123.44 kg |

This is the key F3.3p result. CFAST sustains the larger plume because the same
two-zone state both returns more gas to R0 lower and removes almost no R0
lower gas through the outward hot slab. F3.3n corrects receiver deposition,
but the resulting temperatures and neutral plane still differ, so gross
return and source-slab flow have not converged yet.

## Why a runtime retest is still justified

A static subtraction cannot predict the coupled candidate:

- F3.3e1 already remained non-degenerate at 180 and 300 s with the old
  receiver routing: R0 lower mass was 14.30 and 9.90 kg.
- F3.3n improves lower return on the current trajectory and creates the Hall
  upper layer that was absent during F3.3e1.
- The coupled heat source changes R0 and Hall temperatures. Those temperatures
  feed both the `flogo` destination fraction and the hydrostatic neutral
  plane on the next step.
- In old F3.3e1, R0 pressure-family lower outflow was only 17.77 kg at
  590 s, versus 69.49 kg in F3.3n. Source coupling therefore changes the
  problematic route itself; the two old runs cannot be added linearly.

The evidence supports one controlled closed-loop experiment. It does not
support claiming in advance that F3.3n removes the collapse.

## F3.3p1 source contract

The candidate must use one accepted source:

```text
Qaccepted = accepted_hrr_kw from the canonical combustion/O2 decision
chi_rad   = configured physical radiative fraction
Qc        = Qaccepted * clamp(1 - chi_rad, 0, 0.90)

convective_energy = Qc * dt

z0    = -1.02 * D + 0.083 * Qaccepted^(2/5)
z_eff = max(0.1, interface - fire_base - z0)

plume_height = 0.071 * Qc^(1/3) * z_eff^(5/3) * dt
plume_source = 0.071 * 0.026 * Qc * dt
plume_total  = plume_height + plume_source
```

The Group C scratch overlay must provide the CFAST physical pair as one
contract:

- `chi_rad = 0.35`;
- equivalent fire diameter `D = 0.6196 m`.

They are not independent tuning controls and no sweep is authorized.

The canonical O2 selection, extinction limit and accepted HRR decision remain
unchanged. Heat and plume are already downstream of that decision, so the
existing `heat_scale` and cube-root `plume_scale` must not be applied again.
The common atomic bundle may still reduce every route together when a real
mass, energy, O2 or species inventory limit is reached.

## Minimal implementation surface

F3.3p1 should be small and reversible:

1. Add `phase3_coupled_qc_shadow_enabled = false` to `SimulationEngine`.
   It requires the complete canonical combustion/plume stack and the F3.3n
   buoyancy destination flag.
2. Expose the staged canonical combustion source decision read-only from
   `Phase3ZoneMassSystem`; do not reread mutated legacy HRR or O2.
3. Add one pure `ThermalSystem` preview that returns the coupled heat and
   plume requests from `Qaccepted`, `chi_rad`, `D` and the pre-step canonical
   state.
4. Mark the resulting source proposal as already accepted by the canonical
   O2 decision. Preserve the final common atomic inventory fraction.
5. Add diagnostic fields for `Qaccepted`, `Qc`, `chi_rad`, `D`, `z0`,
   `z_eff`, requested/accepted plume terms and lower-inventory limiting.
6. Add one CLI switch for scratch runs. Do not edit the official Group C
   case or report.

Expected files:

- `sim/core/SimulationEngine.gd`
- `sim/core/Phase3ZoneMassSystem.gd`
- `sim/core/ThermalSystem.gd`
- `tools/run_scenario_headless.gd`
- `scripts/run_scenario.py`
- focused structural and direct Godot fixture tests

CSV wiring is optional if the existing canonical combustion fields can carry
the decision unambiguously. Do not add duplicate telemetry merely to expose
the flag.

## Runtime STOP gates

### Gate 0 - structure and no-op

- default false;
- direct fixture reproduces CFAST plume within 3% at 180/300/590 s;
- OFF run byte-identical to F3.3n;
- all 115 legacy columns invariant ON;
- no double O2 or source scaling;
- exact room/building mass, energy, O2 and species residuals.

### Gate 1 - 180 s

Run only Group C with corrected topology, F3.3n routing and the physical
source pair.

- R0 lower gas at least 10 kg and no zone collapse;
- plume inventory acceptance at least 98%;
- R0 upper-mass error smaller than the F3.3n error of 3.14 kg;
- interface error smaller than the F3.3n error of 0.302 m;
- upper-temperature absolute error no worse than 31 C;
- Hall and R2 upper zones remain non-degenerate;
- zero-O2 flame and every atomic residual remain zero.

STOP and remove the candidate if any binding condition fails.

### Gate 2 - 300 s

Run only after Gate 1 passes.

- R0 lower gas at least 8 kg;
- no sustained plume inventory cap;
- R0 upper-temperature absolute error below 20 C;
- upper and lower mass remain finite and conservative;
- lower inflow/outflow moves toward the CFAST budget rather than only moving
  the interface.

STOP before 600 s if lower mass is falling toward zero or accepted plume
diverges from requested plume.

### Gate 3 - 600 s

Run only after Gate 2 passes.

- R0 lower gas at least 10 kg;
- no lower-zone collapse or reseed;
- cumulative plume within 15% of CFAST's 317.06 kg;
- accepted/requested plume ratio at least 98% in the 300-600 s window;
- R0 upper-temperature absolute error below the old F3.3e1 error of 33.77 C;
- upper and lower masses each within 25% of CFAST;
- all route and residence residuals zero;
- no O2E1, D1, S1, FED, pressure or species regression.

These gates authorize retaining an experimental mechanism only. Canonical
authority, official case changes and Group C gap retirement require a
separate decision.

## Risks and rollback

| Risk | Required response |
|---|---|
| Heat or plume receives O2 acceptance twice | Roll back immediately. |
| Lower inventory cap hides the requested plume | STOP; do not accept a closer temperature. |
| Extra heat changes pressure flow but lower mass still trends to zero | STOP at 180 or 300 s. |
| A coefficient sweep is proposed | Reject; only the CFAST physical pair is authorized. |
| Temperature improves while mass/interface worsens materially | Reject physical correspondence. |
| Official report or expected value changes during scratch work | Restore before evaluation. |
| Zero-O2 flame or nonzero atomic residual appears | Roll back immediately. |

## Next gate

F3.3p1 is the authorized next task: reintroduce the coupled source behind a
default-OFF flag and execute Gate 0 plus the 180 s STOP only. Do not start
300 or 600 s in the same unattended command. HVAC remains deferred.
