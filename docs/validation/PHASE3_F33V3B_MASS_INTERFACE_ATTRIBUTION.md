# Phase 3+ F3.3v3b R0 mass/interface attribution

Date: 2026-07-26

## Decision

F3.3v3b is **diagnostic GO for total-room mass ownership** and **NO-GO for
interface authority or Group C retirement**.

The existing canonical residence ledger is sufficient. No motor telemetry,
case parameter, validation report, expected value, tolerance, CTRL, gap or
HVAC path changed.

The read-only analyzer is:

```text
scripts/simulation/analyze_phase3_f33v3b_mass_interface_attribution.py
```

It combines:

- SimuFire canonical mass-residence owners;
- CFAST signed R0-Hall slab integrals;
- CFAST wall/floor leakage net flow;
- CFAST pyrolysis mass input;
- CFAST plume transfer and layer state.

## Closed total-mass equation

At 180 s:

| Term | SimuFire | CFAST | Contribution to SF excess |
|---|---:|---:|---:|
| Initial R0 gas | 57.600 kg | 57.379 kg | +0.221 kg |
| Gas source / pyrolysis | 0.000 kg | 2.114 kg | -2.114 kg |
| R0-Hall net outflow | 6.368 kg | 7.290 kg | +0.922 kg |
| Exterior net outflow | 4.921 kg | 9.833 kg | +4.912 kg |
| Final R0 gas | 46.310 kg | 42.349 kg | +3.961 kg |

The four contributions predict `+3.941 kg`. The observed error is
`+3.961 kg`; the remaining `0.020 kg` is the CFAST exported-budget residual
at ten-second integration precision.

Both source budgets close within the `0.05 kg` diagnostic tolerance. The
canonical mass-residence residual is zero.

## Time development

| t | Observed mass error | Exterior deficit | Doorway deficit | Gas-source bias |
|---:|---:|---:|---:|---:|
| 60 s | +0.106 kg | +0.153 kg | -0.108 kg | -0.197 kg |
| 90 s | +0.153 kg | +0.909 kg | -0.402 kg | -0.622 kg |
| 120 s | +1.648 kg | +2.344 kg | +0.180 kg | -1.120 kg |
| 150 s | +3.060 kg | +3.804 kg | +0.628 kg | -1.617 kg |
| 180 s | +3.961 kg | +4.912 kg | +0.922 kg | -2.114 kg |

The total error grows mainly after 100 s as exterior outflow falls behind
CFAST. A global opening multiplier is still rejected: the doorway term
changes sign during the early trajectory and is not the dominant owner.

## Owners rejected

### Plume

Plume transfers lower gas to upper inside one room. Its net room mass is
exactly zero. At 180 s SimuFire has transferred `108.877 kg` cumulatively,
versus `97.716 kg` in CFAST: it is already `+11.161 kg` higher.

Increasing plume cannot remove the excess total mass and would repeat a
previously rejected direction.

### Projection/reconcile

All canonical projection/reconcile residence families have zero net mass.
The exact upper/lower residence residual is also zero. EOS projection is not
the owner of the current canonical error.

### F3.3v3a fire-growth filter

The filtered pre-v3a candidate gives the same owner ordering:

- observed total error `+3.914 kg`;
- exterior deficit `+4.886 kg`;
- doorway deficit `+0.901 kg`;
- gas-source bias `-2.114 kg`;
- plume surplus `+10.061 kg`.

The F3.3v3a source correction therefore neither creates nor hides this mass
problem.

## Remaining interface problem

Closing total mass ownership does not yet close layer partition:

| R0 at 180 s | SimuFire | CFAST | Error |
|---|---:|---:|---:|
| Upper gas | 24.756 kg | 26.943 kg | -2.187 kg |
| Lower gas | 21.555 kg | 15.406 kg | +6.149 kg |
| Interface | 0.946 m | 0.736 m | +0.210 m |

Because plume transfer is already high, the layer error must be tested
against where exterior leakage removes mass and how the doorway/boundary
solver partitions source zones. A scalar increase in leakage could reduce
total mass while removing the wrong layer and worsening the interface.

The missing `2.114 kg` gas-source term is also real architectural debt:
fuel-derived gas products should eventually enter total gas mass. Adding it
alone would increase the current excess, so it must not be introduced without
the corresponding boundary-flow audit.

## Next gate: F3.3v3c

F3.3v3c is diagnostic first:

1. map CFAST `LEAK_AREA_RATIO` to wall/floor effective areas;
2. compare that topology with SimuFire's single closed-opening
   `window_leakage_area_m2`;
3. compare pressure history and cumulative upper/lower exterior removal;
4. separate exterior topology error from pressure-state error;
5. determine whether the missing lower removal explains the interface;
6. define a pure/default-OFF experiment only if one physical owner is
   isolated.

STOP before motor code if CFAST per-zone leakage cannot be reconstructed from
committed outputs. Do not tune a per-case area, multiply all doorway flow,
change plume/HRR/walls, write canonical state live, alter FED or touch HVAC.

## Verification

| Check | Result |
|---|---|
| New analyzer tests | 6 PASS |
| Related F3.3m/F3.3s/F3.3v3b tests | 21 PASS |
| Current F3.3v3a candidate | decomposition PASS |
| Filtered pre-v3a candidate | decomposition PASS |
| Total-mass residual | 0.020 kg |
| Canonical residence residual | zero |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Guardrails | 10/10 PASS |
| Gap inventory | 353 required, 6 VALID_GAP, sync PASS |
| Motor/cases/reports/baselines | unchanged |
