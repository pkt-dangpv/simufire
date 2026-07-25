# Phase 3+ F3.3u extended coupled-plume stability

Date: 2026-07-25

Status: stability GO; runtime authority and Group C retirement NO-GO.

## Scope

F3.3u extends the exact F3.3t default-OFF candidate to 300 and 600 s.
No equation, coefficient, case, official report, expected value, tolerance,
CTRL, FED, HVAC or visual path changes in this phase.

The purpose is to separate:

1. whether complete coupled Heskestad plume transport remains conservative
   and stable over the full CFAST horizon;
2. whether the complete shadow stack is ready to govern runtime physics.

Those are different gates.

## Runs

Godot 4.7.1 executed deterministic OFF/ON pairs at 300 and 600 s with the
same case files and parent stack used by F3.3t:

```powershell
python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_off.json `
  --out-dir runs\phase3_f33u\600_off `
  --duration 600 `
  --timeout 1800 `
  --phase3-cfast-buoyancy-destination-shadow

python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33u\600_on `
  --duration 600 `
  --timeout 1800 `
  --phase3-cfast-buoyancy-destination-shadow
```

The binding audit is:

```powershell
python scripts\simulation\analyze_phase3_f33u_extended_stability.py `
  --json-out runs\phase3_f33u\stop_gate.json
```

CFAST exports end at 590 s. The 600 s SimuFire row is retained for numerical
stability and required-check projection.

## Determinism and conservation

- The 600 s OFF/ON prefixes are exactly equal to the independent 180 and
  300 s runs.
- All audited values remain finite.
- Minimum active upper mass: `2.693 kg`.
- Minimum active lower mass: `20.469 kg`.
- Minimum upper O2 fraction: `0.12377`.
- Minimum lower O2 fraction: `0.13781`.
- Maximum canonical mass/O2/energy residual: `2.8e-7`, below the `1e-6`
  gate.
- No zone exhausts its inventory and no zero-O2 flame is introduced.

## Correspondence by horizon

Every audited RMSE family improves versus OFF at 180, 300 and 590 s.

| Metric | 180 s improvement | 300 s improvement | 590 s improvement |
|---|---:|---:|---:|
| Upper mass | 88.8% | 88.7% | 89.9% |
| Lower mass | 85.2% | 81.0% | 74.0% |
| Interface | 86.8% | 83.9% | 78.3% |
| Upper temperature | 80.3% | 74.1% | 33.4% |
| Lower temperature | 25.9% | 28.1% | 22.2% |
| Upper O2 | 95.5% | 96.4% | 84.0% |
| Lower O2 | 47.1% | 81.4% | 83.3% |
| Accepted HRR | 89.1% | 92.4% | 56.1% |
| Plume rate | 82.2% | 80.2% | 83.4% |

The declining late thermal/HRR improvement is real. At 590 s:

- upper mass error is only `-0.311 kg`;
- plume-rate error is only `+0.008 kg/s`;
- interface remains `+0.297 m`;
- upper temperature is `-76.62 C`;
- lower temperature is `-51.21 C`;
- accepted HRR is `137.46 kW` versus CFAST `300 kW`.

The plume and upper mass are no longer the primary late owner.

## Required-check projection

Applying the shadow state as runtime authority would currently produce:

| Check | Candidate | Expected +/- tolerance | Projection |
|---|---:|---:|---|
| R0 upper temp t=180 | 139.91 C | 159.816 +/- 15 C | FAIL |
| R0 upper temp t=300 | 136.61 C | 166.268 +/- 20 C | FAIL |
| R0 upper temp t=600 | 91.26 C | 168.796 +/- 30 C | FAIL |
| R0 upper O2 t=600 | 0.12377 | 0.09568 +/- 0.015 | FAIL |

This would reopen the already closed t=180 check and would not close any of
the three active Group C VALID_GAP checks. Authority promotion is therefore
explicitly rejected.

## Late HRR owner

At 590 s:

```text
legacy HRR proposal       = 137.464 kW
canonical accepted HRR    = 137.464 kW
canonical decision        = 1.000
canonical O2 HRR factor   = 0.694
legacy O2 HRR factor      = 0.442
CFAST HRR                 = 300.000 kW
```

The canonical transaction accepts the complete proposal, but that proposal
is already throttled by the live legacy engine. The canonical path can reject
legacy HRR; it cannot restore HRR that legacy removed before the transaction.
This is the primary late owner.

## STOP gate

- Independent 180/300/600 runs: PASS.
- Prefix determinism: PASS.
- All nine RMSE families improve at every horizon: PASS.
- Finite state and positive zone inventories: PASS.
- Mass/O2/energy residual gate: PASS.
- Focused F3.3t/F3.3u analyzer tests: 12/12 PASS.
- Stability of F3.3t mechanism: GO.
- Runtime authority: NO-GO.
- Required-check projection: 0/4 PASS.
- Group C retirement: NO-GO.

## Next phase

F3.3v is design-first. It must define an unthrottled canonical fire proposal
before O2 acceptance, instead of using `room.hrr_kw` after legacy O2
throttling.

Mandatory constraints:

- no change to the F3.3t plume equation;
- no corridor-only coefficient;
- no forced 300 kW HRR;
- fuel, species, O2 and energy remain one atomic transaction;
- preserve extinction and zero-O2 flame protection;
- derive the proposal from canonical persistent fire state and the existing
  growth/fuel/ventilation contracts;
- default OFF and STOP gate before any runtime experiment.
