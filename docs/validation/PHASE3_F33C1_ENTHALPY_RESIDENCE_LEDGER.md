# Phase 3+ F3.3c1 - Cumulative enthalpy residence ledger

Date: 2026-07-21

## Decision

**Instrumentation GO; canonical authority and Groups A/C retirement remain
NO-GO.**

F3.3c1 adds a passive, default-OFF ledger to the persistent canonical shadow.
It changes no legacy physics, official case, report, expected value, tolerance,
gap or CTRL envelope.

## Contract

The flag is:

```text
phase3_enthalpy_residence_diagnostics_enabled = false
```

It is effective only with the full F3.3b stack. Each accepted transfer is
recorded after the common atomic inventory fraction is known and before the
shadow state is mutated. Legacy requests and conservative zone collapse are
also explicit families, so they cannot disappear into a closure residual.

For each room and upper/lower zone the CSV exports cumulative accepted energy
in/out for combustion, plume, inter-zone heat, wall, ambient, exterior
pressure, exterior counterflow, F3.3a gross interior transport, F3.3b signed
interior pressure, delayed parcels, legacy requests, zone collapse and any
unclassified canonical route. Initial, expected and observed zone energies
produce upper, lower, room and building residuals.

The flag adds 68 CSV columns. With the flag OFF the F3.3b schema is unchanged.

## Runtime proof

The direct Godot fixture moves energy through combustion, upper-to-lower
transfer, an interior opening, a wall sink and a legacy request. Every family
is separated and all zone, room and building residuals are exactly zero.

The 600 s `cfast_corridor_chain` OFF/ON comparison produced 366 rows. All 527
shared columns were string-identical; the ON run added only the 68 enthalpy
fields. Across all rows, the maximum absolute upper, lower, room and building
residual was `0.0 kJ`.

At 600.1 s, R0 contains 1855.35 kJ upper and 412.85 kJ lower sensible energy.
Its cumulative upper ledger is:

| Accepted upper route | In | Out |
|---|---:|---:|
| Combustion | 40.711 MJ | 0 |
| Plume | 3.202 MJ | 0 |
| F3.3a interior opening | 0.662 MJ | 20.817 MJ |
| F3.3b interior pressure | 0.410 MJ | 2.419 MJ |
| Wall | 0 | 6.362 MJ |
| Ambient | 0 | 11.625 MJ |
| Inter-zone heat | 0 | 1.498 MJ |
| Exterior pressure | 0 | 0.409 MJ |

The totals are 44.985 MJ in and 43.130 MJ out, leaving the observed 1.855 MJ.
From 180 to 600 s the room receives 29.696 MJ from combustion while net room
losses are dominated by interior openings (11.738 MJ), ambient (10.839 MJ),
wall (5.655 MJ) and signed interior pressure (1.801 MJ).

The 360 s `cfast_r0_window_360` control produced 222 rows with zero residual at
all four levels. R0 received 25.678 MJ from combustion and lost 9.337 MJ to
wall, 11.024 MJ directly to ambient and 1.520 MJ through the exterior pressure
boundary. No interior-opening energy appeared in that topology.

## Interpretation

F3.3c1 converts the late-temperature diagnosis into an exact budget. Group C
is not cold because the ledger loses energy numerically: it closes exactly.
The canonical model accepts only 40.7 MJ combustion heat through 600 s, versus
about 104.8 MJ convective HRR in CFAST, and then exports substantial energy
through interior openings and thermal boundaries.

The existing `chi_rad=0.35` scratch control proves that replacing the missing
source with one scalar is not valid: it fixes 600 s but overheats 180 s. The
next phase must compare the time-resolved CFAST source and boundary terms with
these exact canonical families before modifying physics.

## Next gate: F3.3d

F3.3d is a source/boundary correspondence audit, not a motor patch. It must:

1. integrate CFAST convective HRR over the same time windows;
2. extract or bound CFAST wall and opening enthalpy losses;
3. compare `0-180`, `180-300` and `300-600 s` against the exact F3.3c1 ledger;
4. decide whether the first physical candidate belongs to combustion/radiation
   partition, wall/ambient residence or interior-opening enthalpy transport;
5. reject any candidate that merely trades the 180 s and 600 s errors.

No F3.3d motor change is authorized by this record.

## Evidence

- `runs/phase3_f33c1/corridor_off`
- `runs/phase3_f33c1/corridor_on`
- `runs/phase3_f33c1/r0_window_on`
- `tests/fixtures/phase3_f33c1_enthalpy_residence_ledger.gd`
- `tests/test_phase3_f33c1_enthalpy_residence_ledger.py`

The run evidence is local/ignored and is not an official validation report.

## STOP gate

| Check | Result |
|---|---|
| Direct Godot 4.7.1 fixture | PASS |
| Focused/adjacent pytest | 38 PASS |
| Full pytest outside sandbox | 1063 PASS / 19 FAIL |
| Pre-existing structural failures | 18, unchanged |
| Expected dirty-motor integration failure | 1 (`test_exit0_real_json` / R2-1) |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 required, 5 VALID_GAP, synchronized |
| Guardrails | 9/10; only R2-1 because `sim/core` is uncommitted |
| Official reports/baselines | untouched |

The first two sandboxed full-pytest attempts were invalid: old ignored
`runs/` temp trees and `%TEMP%` were unreadable. The reported full result is
the clean outside-sandbox run, matching the established project procedure.
