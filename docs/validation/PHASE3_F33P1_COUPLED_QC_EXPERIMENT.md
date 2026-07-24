# Phase 3+ F3.3p1 coupled-Qc runtime experiment

Date: 2026-07-24

Decision: **NO-GO at the mandatory 180 s STOP**.

## Purpose

F3.3p1 tested whether the accepted combustion heat and the complete
Heskestad plume could share one O2-accepted convective source while retaining
the accepted F3.3n receiver routing. The candidate was experimental,
default OFF and shadow-only. It did not write legacy physics.

The scratch physical inputs were the CFAST pair:

- radiative fraction: `chi_rad = 0.35`;
- fire diameter: `D = 0.6196 m`.

No official case, report, expected value, tolerance, gap or CTRL was changed.
HVAC remained out of scope.

## Isolation correction

The first ON run changed the Engine-wide radiative fraction and fire diameter.
That run is invalid for attribution because legacy output also changed. It is
retained only as scratch evidence under
`runs/phase3_f33p1_180_on/`.

The candidate was corrected so the physical pair existed only inside the
canonical shadow preview. The valid ON run is
`runs/phase3_f33p1_180_on_v2/`.

## Equivalence gates

The 180 s OFF run is byte-identical to the accepted F3.3n run:

```text
SHA256:
80BC7E10C4B5CE86CADB59AF84AA3538E58D78009D748899DFDBF70456170939

rows: 114
columns: 667
```

The corrected ON run preserves all 115 legacy columns with zero differing
cells. All changes are confined to the canonical shadow.

## Mandatory 180 s STOP

| R0 metric | F3.3n OFF | F3.3p1 ON | CFAST | Gate |
|---|---:|---:|---:|---|
| Upper gas mass | 23.799 kg | 25.484 kg | 26.943 kg | PASS |
| Lower gas mass | 24.046 kg | 14.673 kg | 15.406 kg | PASS |
| Upper temperature | 129.40 C | 200.75 C | 159.82 C | **FAIL** |
| Lower temperature | 30.66 C | 53.15 C | 61.60 C | PASS |
| Interface height | 1.038 m | 0.681 m | 0.736 m | PASS |
| Plume mass | 72.03 kg | 100.855 kg | 97.716 kg | PASS |

The binding upper-temperature error is `+40.93 C`; the authorized limit was
`31 C`. Therefore the experiment stops at 180 s. No 300 or 600 s candidate
run is permitted from this branch of work.

Hall and R2 also show excess upper-zone heating:

| Room | ON upper mass | CFAST upper mass | ON upper T | CFAST upper T |
|---|---:|---:|---:|---:|
| Hall | 14.820 kg | 18.384 kg | 134.20 C | 93.55 C |
| R2 | 24.347 kg | 25.240 kg | 77.72 C | 62.10 C |

## Conservation

The NO-GO is physical correspondence, not bookkeeping failure.

- Mass and enthalpy residence residuals are zero.
- Interior mass, energy, O2 and species residuals are zero.
- Combustion O2, energy and species residuals are zero.
- Atomic rejected mass and energy are zero.
- Invalid bundles are zero.
- Zero-O2 flame findings are zero.
- Requested versus accepted plume fraction remains `1.0` at sampled rows.
- Expected upper collapse occurs only in inert rooms 3-5, once each.

## Energy attribution

At 180 s:

| R0 cumulative term | F3.3n OFF | F3.3p1 ON |
|---|---:|---:|
| Accepted combustion heat | 10.996 MJ | 24.020 MJ |
| Plume sensible energy | 0.186 MJ | 0.725 MJ |
| Wall upper loss | 1.428 MJ | 4.796 MJ |
| Ambient upper loss | 2.527 MJ | 4.618 MJ |
| Opening upper outflow | - | 9.055 MJ |
| Pressure upper outflow | - | 0.529 MJ |
| Canonical upper-to-lower transfer | 0.395 MJ | 0.550 MJ |

The CFAST source convective energy is approximately `24.872 MJ`, so source
energy is no longer the dominant discrepancy. A balance reconstructed from
CFAST gives about `4.408 MJ` final R0 sensible energy and `6.302 MJ` net
R0-to-Hall transfer, implying roughly `14.16 MJ` of remaining boundary loss.

F3.3p1 retains approximately `5.09 MJ` in R0 and exports about `9.11 MJ`
directly while recording about `9.68 MJ` of wall plus ambient loss. The
remaining comparison is not one scalar Qc error: boundary-energy
correspondence, surface storage/loss and inter-room export must be aligned by
time window.

## Decision and cleanup

- Runtime candidate: **NO-GO**.
- Canonical authority: **NO-GO**.
- Group C retirement: **NO-GO**.
- Temporary flag, Engine/CLI wiring, preview helper, fixture and tests:
  removed.
- F3.3n remains the accepted receiver-routing mechanism.
- F3.3p design and scratch runs remain as evidence.

## Next phase: F3.3q

F3.3q is a read-only boundary-energy correspondence audit. Before another
motor candidate it must compare, over `0-60`, `60-120` and `120-180 s`:

1. CFAST inferred boundary sink from source, room storage and signed doorway
   enthalpy;
2. canonical wall, ambient and exterior-boundary energy;
3. canonical inter-zone heat transfer;
4. R0-to-Hall and Hall-to-R0 signed enthalpy;
5. wall/gas temperatures and available surface-storage terms.

The audit must identify a missing owner or a semantic mismatch. It must not
introduce another Qc, plume, doorway or wall coefficient.
