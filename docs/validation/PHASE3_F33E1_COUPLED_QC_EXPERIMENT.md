# Phase 3+ F3.3e1 - Coupled Qc runtime experiment

Date: 2026-07-22

## Decision

**NO-GO for retaining or promoting the runtime candidate. The complete
F3.3e1 code, flag, fixture and tests were rolled back.** The corrected
Heskestad source contract is validated early, but the 600 s run exhausts the
canonical lower zone because lower-zone renewal does not keep pace with plume
entrainment. No official case, report, baseline, tolerance, gap, CTRL or
authority changed.

Scratch evidence remains under `runs/phase3_f33e1/` and is ignored by Git.

## Candidate tested

The default-OFF candidate used one accepted canonical source:

```text
Qaccepted -> chi_rad(canonical O2) -> Qc
heat      = Qc * dt
z0        = -1.02 D + 0.083 Qaccepted^(2/5)
plume     = 0.071 Qc^(1/3) (z-z0)^(5/3) + 0.071*0.026*Qc
```

Heat and plume entered the existing atomic combustion bundle already
accepted, so no downstream `heat_scale` or cube-root `plume_scale` was
applied. The lower inventory cap and proportional lower enthalpy/O2 payload
remained active.

The scratch Group C overlay changed only the two CFAST physical inputs:

- `hrr_chi_rad_normal/low_o2 = 0.35`;
- `plume_fire_diameter_m = 0.6196`.

The official `cfast_corridor_chain.json` was not edited.

## Verification before runtime

- Structural Phase 3 tests: 27/27 PASS.
- Direct Godot 4.7.1 fixture: PASS for explicit Qc heat, Heskestad virtual
  origin, height and linear source terms, lower specific enthalpy and absence
  of double throttle.
- Default-OFF comparison against the pre-F3.3e1 F3.3d1 run: 114/114 rows,
  667/667 shared columns and zero differing cells.
- The first direct fixture attempt used the shared Godot `user://logs` path,
  failed before project execution and crashed in Godot. It produced no
  simulation evidence and is excluded. All accepted runs used isolated
  `APPDATA`, completed with `RUN_SCENARIO PASS` and left no Godot process.

## 180 s STOP gate

The candidate passed the binding first gate. All three canonical state
quantities moved toward CFAST using the same physical-input overlay:

| Metric at 180 s | OFF | F3.3e1 | CFAST | Result |
|---|---:|---:|---:|---|
| Upper temperature (C) | 220.36 | 190.49 | 159.82 | improved |
| Upper gas (kg) | 6.68 | 25.76 | 26.94 | improved |
| Interface (m) | 1.932 | 0.690 | 0.736 | improved |

Mass and enthalpy residence residuals were exactly zero. This authorized the
single 600 s run.

## Full-run state

| t | Metric | CFAST | F3.3e1 | Error |
|---:|---|---:|---:|---:|
| 180 | upper temperature (C) | 159.82 | 190.49 | +30.67 |
| 180 | upper gas (kg) | 26.943 | 25.762 | -1.181 |
| 180 | lower gas (kg) | 15.406 | 14.301 | -1.105 |
| 180 | interface (m) | 0.736 | 0.690 | -0.046 |
| 300 | upper temperature (C) | 166.27 | 178.17 | +11.90 |
| 300 | upper gas (kg) | 25.949 | 29.621 | +3.672 |
| 300 | lower gas (kg) | 15.562 | 9.899 | -5.663 |
| 300 | interface (m) | 0.773 | 0.491 | -0.282 |
| 590 | upper temperature (C) | 168.80 | 135.03 | -33.77 |
| 590 | upper gas (kg) | 25.249 | 41.367 | +16.118 |
| 590 | lower gas (kg) | 15.794 | 0.000 | -15.794 |
| 590 | interface (m) | 0.808 | 0.000 | -0.808 |

The early correspondence is real, but by 590 s the shadow has become a
one-zone room. A closer temperature cannot authorize a state with no lower
reservoir and an upper mass 64% above CFAST.

## Window budgets

| Window | CFAST Qc energy | F3.3e1 | CFAST plume | F3.3e1 |
|---|---:|---:|---:|---:|
| 0-180 s | 24.872 MJ | 24.028 MJ | 97.716 kg | 98.363 kg |
| 180-300 s | 23.400 MJ | 22.878 MJ | 62.244 kg | 53.672 kg |
| 300-590 s | 56.550 MJ | 44.562 MJ | 157.101 kg | 56.229 kg |

The corrected contract closes the first window without tuning. The late
plume deficit is not caused by the equation: the lower inventory cap becomes
binding after the lower reservoir is drained. Late energy remains limited by
the already documented canonical O2/HRR deficit.

## Lower-reservoir diagnosis

Room 0 cumulative mass routes expose the next owner:

| t | Plume lower out | Opening lower in | Pressure lower in | Pressure lower out |
|---:|---:|---:|---:|---:|
| 180 s | 98.363 kg | 62.871 kg | 0.325 kg | 6.850 kg |
| 300 s | 152.035 kg | 114.688 kg | 3.426 kg | 12.499 kg |
| 590 s | 208.264 kg | 162.611 kg | 7.102 kg | 17.768 kg |

By 590 s, lower inflow is about 169.7 kg while plume plus pressure lower
outflow is about 226.0 kg. Starting from roughly 50 kg cannot sustain that
deficit. The ledger remains exactly conservative; it is exposing insufficient
lower-zone renewal/routing, not deleting mass invisibly.

## What is retained

- The F3.3e source design and direct CFAST equation correspondence remain
  valid diagnostic evidence.
- The F3.3d1 mass and F3.3c1 enthalpy ledgers remain the accepted instruments.
- Scratch CSVs remain ignored for reproducibility.

## What is rolled back

- `phase3_coupled_qc_shadow_enabled`;
- coupled heat/plume previews;
- already-accepted bundle bypass;
- CLI wiring;
- F3.3e1 fixture and structural tests.

## Next gate: F3.3f lower-zone renewal correspondence

Do not reintroduce F3.3e1 yet. First compare CFAST and canonical Group C mass
routes over the same three windows:

1. lower doorway inflow into R0;
2. upper doorway outflow from R0;
3. plume lower-to-upper transfer;
4. pressure-driven lower transport;
5. initial/final upper and lower inventories.

F3.3f must decide whether the missing renewal is flow magnitude, slab-to-zone
routing or a plume/opening coupling-order problem. It is design/analysis
first; no opening coefficient, pressure gain, case value or authority change
is authorized.
