# Phase 3+ F3.3h2 - Buoyancy destination runtime experiment

Date: 2026-07-23

## Decision

**Runtime candidate NO-GO at the mandatory 180 s STOP.**

The isolated F3.3h1 `flogo` destination split remains a valid conservative
building block. Its composition with the current F3.3b canonical state and
the separate Poreh bundle does not reproduce the Group C direct-flow split or
zone state. The temporary Engine, CLI and CSV candidate surface was removed.
No 300 s or 590 s run was started.

No official case, report, baseline, tolerance, CTRL, VALID_GAP or HVAC path
changed.

## Runtime contract

The temporary default-OFF candidate:

- implied the full F3.3b shadow stack;
- enabled both enthalpy and mass residence ledgers;
- routed direct opening and signed-pressure slabs with the F3.3h1
  temperature split;
- kept receiver-internal Poreh routes in a separate atomic bundle;
- added candidate-only CSV fields for the gate and Poreh residence totals;
- never wrote canonical state back to `RoomModel`.

The only difference between the paired runs was the candidate selector.

## OFF identity

The checkpoint run without F0 diagnostics reproduced the prior F3.3d1/F3.3g1
artifact exactly:

- SHA-256:
  `6F7FD18D3C451D2AE615D695B066A08F9F593DF5708E864DD50067CECF09ED70`;
- 114 rows;
- 667 columns.

The ON run retained all 115 legacy columns with zero value differences. The
candidate changed only shadow state and candidate-only telemetry.

## Group C 180 s STOP

R0 cumulative accepted direct inflow combines the F3.3a opening and relaxed
F3.3b signed-pressure families. Poreh mass is excluded from these direct
values.

| Quantity | OFF | Candidate ON | CFAST target |
|---|---:|---:|---:|
| Lower direct inflow | 46.143 kg | 53.712 kg | 65.782 kg |
| Upper direct inflow | 7.516 kg | 0.223 kg | 3.662 kg |
| Total direct inflow | 53.659 kg | 53.934 kg | 69.444 kg |
| Upper direct fraction | 14.01% | 0.41% | 5.27% |

The candidate corrects the direction of the legacy routing error, but
overshoots. It sends almost all cool incoming mass to the lower layer. It also
cannot repair the independent 15.510 kg total direct-flow deficit.

## Poreh route

At R0 the separate candidate Poreh bundle moved:

- `1.019187 kg` from receiver upper to receiver lower;
- `86.449716 kJ` with the same route;
- `0.0 kg` from lower to upper.

This transfer is conservative, but it further reduces upper-layer residence
for this runtime state.

## Zone state at 180 s

| Quantity | OFF | Candidate ON | CFAST target |
|---|---:|---:|---:|
| Upper temperature | 125.70 C | 128.42 C | 159.82 C |
| Lower temperature | 36.78 C | 27.88 C | n/a |
| Interface height | 1.101 m | 1.207 m | 0.736 m |
| Upper gas mass | 22.921 kg | 20.832 kg | 26.943 kg |
| Lower gas mass | 25.000 kg | 28.112 kg | 15.406 kg |

The upper temperature improves by 2.72 C, but the binding mass/interface
targets regress: upper mass falls by 2.09 kg and the interface rises by
0.106 m.

## Conservation

Across the ON run:

- upper, lower and building mass-residence residuals were exactly zero;
- upper, lower and building enthalpy-residence residuals were exactly zero;
- interior mass, energy, O2 and species residuals were exactly zero;
- candidate rejected mass was zero;
- all final accepted fractions were one.

The failure is physical correspondence, not transaction accounting.

## Root-cause interpretation

F3.3h2 separates two remaining discrepancies:

1. **Destination split input mismatch.** The F3.3h1 formula is exact in the
   isolated fixture, but the current runtime source-temperature and receiver
   threshold inputs produce `0.41%` upper deposition instead of CFAST's
   `5.27%`.
2. **Gross direct-flow deficit.** Routing changes only destination. Total
   direct R0 inflow remains `22.3%` below CFAST at 180 s.

The current canonical receiver state is already too cool and lower-heavy.
Applying Poreh after the nearly all-lower direct split compounds that state.
No coefficient is authorized to compensate for either discrepancy.

## Next gate

F3.3i should be a passive input-correspondence audit, not another physical
candidate. It should:

1. export or post-process accepted direct slabs by source temperature,
   receiver lower/upper thresholds and resulting `f_upper`;
2. compare the integrated SimuFire fraction with the CFAST 180 s fraction;
3. isolate opening versus signed-pressure contributions to the 15.510 kg
   total-flow deficit;
4. keep Poreh out of direct `h_mflow` quantities;
5. stop before any coefficient, authority promotion or long Group C run.

No new runtime candidate is justified until the destination-input mismatch
and gross-flow deficit have separate owners.

F3.3i subsequently closed this audit without a motor patch. The Hall
interface is `1.366 m` in SimuFire versus `0.568 m` in CFAST at 180 s, so the
same exact `flogo` formula receives fundamentally different source slabs.
The independent total-flow deficit is tied to the thermal/neutral-plane state
and a non-corresponding pressure field. See
`PHASE3_F33I_INPUT_CORRESPONDENCE_AUDIT.md`.
