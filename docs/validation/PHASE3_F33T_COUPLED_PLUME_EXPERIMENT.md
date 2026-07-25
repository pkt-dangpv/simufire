# Phase 3+ F3.3t coupled plume experiment

Date: 2026-07-25

Status: experimental mechanism GO; runtime authority and Group C retirement
NO-GO.

## Scope

F3.3t tests a continuous plume/interface correlation using the same accepted
combustion source that already owns canonical convective heat and radiation.
It is default OFF, changes no official case or report and is evaluated only
over the first 180 s of `cfast_corridor_chain`.

The experiment does not change the accepted heat partition. F3.3r2 already
routes exactly:

```text
convective heat = accepted HRR * (1 - effective chi_rad)
radiation       = accepted HRR * effective chi_rad
```

F3.3t only replaces the plume request when all canonical multi-surface parent
flags are active.

## Contract

The new preview uses the complete Heskestad expression:

```text
Qaccepted = canonical accepted HRR
Qc        = Qaccepted * (1 - effective chi_rad)
z0        = -1.02 * D + 0.083 * Qaccepted^0.4
z_eff     = max(0.1, interface - z0)

height term = 0.071 * Qc^(1/3) * z_eff^(5/3)
source term = 0.071 * 0.026 * Qc
plume       = height term + source term
```

The request is capped by canonical lower-zone mass. Enthalpy and O2 move in
the same fraction as accepted mass. Because `Qaccepted` already contains the
canonical O2 decision, the plume carries an explicit marker that prevents
`finalize_canonical_combustion_bundle()` from applying `plume_scale` a second
time. The legacy path retains its existing scaling.

Flag:

```gdscript
phase3_coupled_plume_shadow_enabled = false
```

The flag is effective only inside the canonical plume plus canonical
multi-surface stack.

## Reproducible runs

Both runs used Godot 4.7.1 and the complete parent stack implied by
`--phase3-cfast-buoyancy-destination-shadow`:

```powershell
python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_off.json `
  --out-dir runs\phase3_f33t\180_off `
  --duration 180 `
  --timeout 900 `
  --phase3-cfast-buoyancy-destination-shadow

python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33t\180_on `
  --duration 180 `
  --timeout 900 `
  --phase3-cfast-buoyancy-destination-shadow
```

The binding audit is:

```powershell
python scripts\simulation\analyze_phase3_f33t_coupled_plume.py `
  --json-out runs\phase3_f33t\stop_gate.json
```

## Results

RMSE uses the 10 s checkpoints from 10 through 180 s.

| Metric | OFF RMSE | ON RMSE | Improvement |
|---|---:|---:|---:|
| Upper mass | 15.625 kg | 1.744 kg | 88.8% |
| Lower mass | 21.331 kg | 3.161 kg | 85.2% |
| Interface | 0.872 m | 0.116 m | 86.8% |
| Upper temperature | 50.394 C | 9.952 C | 80.3% |
| Lower temperature | 15.256 C | 11.304 C | 25.9% |
| Upper O2 fraction | 0.0798 | 0.0036 | 95.5% |
| Lower O2 fraction | 0.0078 | 0.0041 | 47.1% |
| Accepted HRR | 107.619 kW | 11.687 kW | 89.1% |
| Plume rate | 0.479 kg/s | 0.085 kg/s | 82.2% |

The OFF CSV is byte-identical to the F3.3r2d binding candidate.

At 180 s, ON still has residual correspondence error:

- upper mass `-2.407 kg`;
- lower mass `+5.316 kg`;
- interface `+0.192 m`;
- upper temperature `-19.91 C`;
- lower temperature `-26.46 C`;
- plume rate `+0.112 kg/s`.

These residuals prevent authority promotion. They do not reproduce the
F3.3d2 regression: both upper and lower temperature RMSE improve.

## Conservation

The direct Godot fixture verifies:

- exact Heskestad height and source terms;
- lower mass cap;
- proportional enthalpy and O2;
- immutable transaction lookup;
- no second O2 plume throttle;
- unchanged legacy plume scaling.

The runtime audit checks canonical combustion, mass-residence and
multi-surface residuals. Maximum observed absolute residual is
`8e-8`, below the `1e-6` gate.

## STOP gate

- F3.3t structural/analyzer tests: 11/11 PASS.
- Direct Godot 4.7.1 fixture: PASS with no parser/runtime errors.
- OFF exact against F3.3r2d: PASS.
- All nine correspondence RMSE families improve: PASS.
- Mass/O2/energy ledger gate: PASS.
- Broad Phase 3/F3.3/two-zone selection: 662 PASS plus the same five
  pre-existing structural contract failures.
- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL.
- ILV coherence: 15 PASS / 14 CTRL / 0 FAIL.
- Gap inventory: synchronized, 353 required with 6 documented VALID_GAP.
- Official report, expected value, tolerance or CTRL change: none.
- Runtime authority: NO-GO.
- Group C retirement: NO-GO.

## F3.3u follow-up

F3.3u completed the 300/600 s extension. The mechanism remains stable and
conservative, but runtime authority remains NO-GO because the late HRR
proposal is already throttled by the legacy engine. See
`PHASE3_F33U_EXTENDED_STABILITY.md`.
