# Phase 3+ F3.3v3f1 fixed-gross pressure-skew shadow

Date: 2026-07-26

## Decision

F3.3v3f1 is **GO as a passive shadow preview** and **NO-GO for runtime
authority**.

The new
`phase3_canonical_fixed_gross_pressure_skew_shadow_enabled` flag is default
OFF. When its canonical opening and pressure parents are active, it:

1. reads the already-limited opening and signed-pressure routes;
2. recomposes their directional split while preserving opening gross mass;
3. records step and cumulative mass/enthalpy telemetry;
4. does not enqueue, apply or otherwise mutate the canonical or legacy state.

The existing additive opening plus pressure routes remain authoritative inside
the shadow transaction.

## Why

F3.3v3e showed that the opening-only route already matches CFAST doorway net
enthalpy to 0.14%, but adding the independent signed-pressure route creates
`39.729 kg` of extra gross churn and `795.539 kJ` of excess net enthalpy.

F3.3v3f0 introduced a pure primitive that treats pressure as a directional
skew of the existing counterflow instead of an additional transport route.
F3.3v3f1 wires that primitive into runtime as telemetry only.

## STOP gate

Scenario:

- `runs/phase3_f33t/cases/corridor_on.json`;
- Godot `4.7.1`;
- complete 180 s F3.3v stack, unfiltered growth and object synchronization;
- OFF and ON differ only by the F3.3v3f1 flag.

| Check | Result |
|---|---:|
| OFF / ON rows | 114 / 114 |
| Shared CSV columns | 807 |
| Shared value differences | 0 |
| New preview columns | 21 |
| Max mass residual | 0 kg |
| Max energy residual | 0 kJ |
| Max O2 residual | 0 kg |
| Max species residual | 0 kg |
| Focused F3.3v3f0/f1 tests | 14 PASS |
| Full `pytest tests` | 1326 PASS / 18 FAIL |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 347/353 PASS + 6 VALID_GAP |

R0-to-corridor correspondence at 180 s:

| Metric | Preview | CFAST | Error |
|---|---:|---:|---:|
| Outbound mass | 73.560 kg | 76.732 kg | -4.13% |
| Inbound mass | 70.315 kg | 69.442 kg | +1.26% |
| Gross mass | 143.875 kg | 146.174 kg | -1.57% |
| Net outbound mass | 3.245 kg | 7.290 kg | -55.49% |
| Net outbound enthalpy | 6321.966 kJ | 6301.709 kJ | +0.32% |

The primitive preserves the physically important gross counterflow and
removes the additive pressure enthalpy error. It does not yet reproduce the
full directional net mass because the non-negative directional cap activates
79 times for room 0 during the run.

Of the 18 full-suite failures, 17 are the established repository baseline.
The additional failure is the expected R2-1 freshness gate while motor files
are dirty; it is cleared by committing the implementation and refreshing only
the report timestamp. A root-level `pytest` invocation is not valid in this
workspace because pytest attempts to collect access-restricted historical
temporary directories under `runs/`; use `python -m pytest tests`.

## Interpretation

The result validates the architecture but not the current capped skew as a
drop-in authority:

- pressure should bias a common bidirectional slab field, not add a second
  gross transport path;
- mass, enthalpy, O2 and species must continue to scale atomically;
- the directional cap is necessary for non-negative routes, but its frequency
  shows that post-hoc route scaling is still weaker than solving pressure and
  buoyancy together at slab level.

## Next gate

F3.3v3f2 must remain default OFF and stop at 180 s. Before any authoritative
replacement it must:

1. attribute the 79 R0 cap events by time, opening direction and available
   base counterflow;
2. test whether a combined slab pressure/buoyancy solve can recover the
   missing net mass without increasing gross mass;
3. preserve the F3.3v3f1 enthalpy correspondence and all atomic residuals;
4. prove OFF invariance and avoid changing official cases, expected values,
   tolerances, CTRL envelopes or VALID_GAP classifications.

Do not promote the current preview directly merely because net enthalpy is
close.

## Reproduction

```powershell
python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33v3f1\180_off `
  --duration 180 --timeout 900 `
  --phase3-canonical-unfiltered-fire-growth-shadow `
  --phase3-canonical-fire-products-routing-shadow `
  --phase3-canonical-fuel-object-sync-shadow `
  --phase3-cfast-buoyancy-destination-shadow

python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33v3f1\180_on `
  --duration 180 --timeout 900 `
  --phase3-canonical-unfiltered-fire-growth-shadow `
  --phase3-canonical-fire-products-routing-shadow `
  --phase3-canonical-fuel-object-sync-shadow `
  --phase3-cfast-buoyancy-destination-shadow `
  --phase3-canonical-fixed-gross-pressure-skew-shadow

python scripts\simulation\analyze_phase3_f33v3f1_fixed_gross_shadow.py `
  --json-out runs\phase3_f33v3f1\stop_gate.json
```
