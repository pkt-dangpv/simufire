# Phase 3+ F3.3v3c exterior leakage attribution

Date: 2026-07-26

## Decision

F3.3v3c is **diagnostic GO for exterior upper/lower ownership** and **NO-GO
for an area-only motor experiment**.

The committed CFAST `.out` contains layer-resolved leakage at every ten-second
checkpoint. Its local 7.7.5 source confirms how those vents are constructed.
No new CFAST run or SimuFire motor telemetry was needed.

The read-only analyzer is:

```text
scripts/simulation/analyze_phase3_f33v3c_exterior_leakage.py
```

No motor, case, official report, expected value, tolerance, CTRL, VALID_GAP,
FED, HVAC or visual path changed.

## Topology correspondence

CFAST derives leakage from the R0 envelope:

```text
wall area = 2 * (width + depth) * height * wall_ratio
floor area = width * depth * floor_ratio
```

For `width=5 m`, `depth=4 m`, `height=2.4 m` and
`LEAK_AREA_RATIO=0.00017, 5.2e-05`:

| Path | Area | Vertical extent |
|---|---:|---:|
| Wall leakage | 0.007344 m2 | 0.12-2.28 m |
| Floor leakage | 0.001040 m2 | 0-0.000257 m |
| Total | 0.008384 m2 | distributed |

CFAST applies discharge coefficient `0.7`.

The current SimuFire scenario has one closed exterior window. The canonical
exterior boundary therefore uses the global default
`window_leakage_area_m2=0.005` and partitions that one area over the window
sill/lintel relative to the canonical interface.

The CFAST/SimuFire area ratio is `1.6768`, but this is not an equivalent
one-parameter comparison: CFAST includes a floor path and a nearly full-height
wall path, whereas SimuFire attaches leakage to one window geometry.

## Layer-resolved cumulative outflow

At 180 s:

| Exterior net outflow | SimuFire | CFAST | Deficit |
|---|---:|---:|---:|
| Upper | 3.565 kg | 4.828 kg | 1.263 kg |
| Lower | 1.356 kg | 5.005 kg | 3.649 kg |
| Total | 4.921 kg | 9.833 kg | 4.912 kg |

The lower zone owns `74.3%` of the missing exterior outflow. This directly
supports the F3.3v3b observation that R0 retains `6.149 kg` too much lower
gas, but it does not prove that leakage alone owns the full interface error.

## Pressure and flow direction

| t | CFAST pressure | SimuFire exterior pre-pressure | CFAST net out | SF signed net out |
|---:|---:|---:|---:|---:|
| 60 s | +78.46 Pa | +213.25 Pa | +0.0781 kg/s | +0.0657 kg/s |
| 90 s | +152.01 Pa | +263.88 Pa | +0.1039 kg/s | +0.0677 kg/s |
| 120 s | +60.35 Pa | -46.01 Pa | +0.0641 kg/s | -0.0321 kg/s |
| 130 s | +44.98 Pa | -105.69 Pa | +0.0552 kg/s | -0.0486 kg/s |
| 140 s | +32.88 Pa | -195.80 Pa | +0.0473 kg/s | -0.0661 kg/s |
| 180 s | +6.63 Pa | -22.30 Pa | +0.0236 kg/s | -0.0223 kg/s |

Positive signed flow is outward. At four checkpoints SimuFire admits ambient
gas while CFAST continues to vent. Increasing the leakage area cannot repair
that sign error; it would increase the wrong-direction inflow at those times.

The pressure-relaxation bundle prevents its own single route from crossing
ambient pressure in one explicit solve. It does not guarantee that the next
canonical state remains on the same side after combustion, wall, interior
opening, pressure and other transactions. The owner of the sign reversal is
therefore upstream of the final exterior-area multiplication.

## STOP gate

| Check | Result |
|---|---|
| CFAST leakage geometry reconstructed | PASS |
| Layer-resolved CFAST leakage available | PASS |
| CFAST layer sum vs vents CSV net flow | PASS |
| Upper/lower deficit assigned | PASS |
| Pressure direction comparison | PASS |
| Area-only candidate | NO-GO |
| New analyzer tests | 5 PASS |
| F3.3v3b/v3c analyzer tests | 11 PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Guardrails | 10/10 PASS |
| Motor/cases/reports/baselines | unchanged |

## Next gate: F3.3v3d

F3.3v3d remains read-only. It must express canonical pressure as the ideal-gas
inventory:

```text
p_abs = R / V * (T_ref * m_total + E_sensible / cp)
```

Then, per 10-second window, attribute pressure change to cumulative mass and
enthalpy owners:

- combustion;
- plume;
- interior opening;
- interior signed pressure;
- exterior pressure;
- wall/ambient;
- surface exchange;
- reconciliation and other owners.

The audit must identify which owner first drives the canonical pressure below
ambient while CFAST remains positive. It must distinguish a real energy-loss
owner from a mass-routing owner and verify exact reconstruction of the
reported canonical pressure.

Do not implement distributed leakage, change `window_leakage_area_m2`, tune
pressure relaxation, modify HRR/plume/walls, or write canonical state live
until that owner is isolated.
