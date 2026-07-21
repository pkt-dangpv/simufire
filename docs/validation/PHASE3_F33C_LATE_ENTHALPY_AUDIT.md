# Phase 3+ F3.3c - Group C late-enthalpy residence audit

Date: 2026-07-21

## Decision

**Diagnosis GO: the late Group C error is energy-residence dominated, not an
excess upper-layer mass error.** F3.3c1 has since supplied the exact cumulative
accepted-route ledger; its binding result is recorded in
`docs/validation/PHASE3_F33C1_ENTHALPY_RESIDENCE_LEDGER.md`.

No motor physics, official case, report, expected value, tolerance, gap or
CTRL envelope was changed. F3.3b remains default OFF and Group C remains a
VALID_GAP.

## State comparison

The comparison uses the committed F3.2b7, F3.3a and F3.3b evidence plus the
local CFAST truth. CFAST upper/lower masses are the sum of its per-species
layer inventories. Sensible energy uses the same `Cp = 1 kJ/(kg K)` and 20 C
reference as the canonical shadow.

| R0 at 600 s | CFAST | F3.2b7 | F3.3a | F3.3b |
|---|---:|---:|---:|---:|
| Upper temperature | 168.80 C | 113.92 C | 102.73 C | 97.39 C |
| Interface | 0.808 m | 0.288 m | 1.153 m | 1.138 m |
| Upper gas mass | 25.28 kg | 26.71 kg | 23.35 kg | 23.97 kg |
| Upper sensible energy | 3761.9 kJ | 2508.5 kJ | 1931.7 kJ | 1855.4 kJ |
| Lower sensible energy | 1033.1 kJ | 38.6 kJ | 427.3 kJ | 412.9 kJ |

F3.3b carries 94.8% of the CFAST upper-layer mass at 600 s, but only 49.3%
of its upper sensible energy. Holding the F3.3b mass fixed, matching the CFAST
temperature requires approximately 1712 kJ more upper-zone energy. The total
R0 gas-energy deficit is approximately 2527 kJ. At 180 s the upper mass is
85.0% of CFAST and the upper energy is 64.3%; the energy deficit is already
visible and grows with time.

This rejects the hypothesis that the late undershoot is primarily caused by
too much hot-layer mass. The higher F3.3a/F3.3b interface is partly a
consequence of the colder, denser upper gas, not proof of an oversized mass
reservoir.

## Heat-source mismatch

CFAST reports a 0.65 convective fraction for this input. A trapezoidal
integration of its 10 s rate output gives about 161.3 MJ total HRR and
104.8 MJ convective HRR through 600 s. The committed F3.3b evidence gives
about 135.7 MJ accepted HRR and 40.7 MJ accepted canonical convective heat by
the same explicitly approximate rate integration.

The validation case currently overrides both `hrr_chi_rad_normal` and
`hrr_chi_rad_low_o2` to 0.70, leaving roughly 0.30 convective heat. This is a
large explanatory term, but it is not an isolated fix:

| F3.3b R0 upper temperature | 180 s | 600 s |
|---|---:|---:|
| Committed case, chi_rad 0.70 | 125.70 C | 97.39 C |
| Scratch control, chi_rad 0.35 | 218.35 C | 165.11 C |
| CFAST target | 159.82 C | 168.80 C |

The scratch control lives only under `runs/phase3_f33c/`. It improves the late
point but recreates a severe early overshoot. A single radiation/convection
knob therefore moves the curve instead of fixing its time-dependent
residence. The official case must not be retuned from this experiment.

## What the current telemetry says

Exact cumulative counters already exist for canonical inter-zone heat and
wall absorbed/emitted/ambient energy. They show that F3.3b does not cure the
deficit by retaining more heat in R0. At 600 s its upper energy is 76 kJ below
F3.3a even though its cumulative wall absorption, ambient removal and
inter-zone transfer are all lower.

The sparse CSV also indicates a much larger net R0 doorway enthalpy export in
F3.3b than F3.3a. Integrating the sampled per-step values as instantaneous
rates gives approximately -25.0 MJ versus -16.1 MJ through 600 s. This is
useful directional evidence only. It is not an exact ledger because the CSV
samples every 10 s while the physical step is 1/12 s.

The present files cannot exactly attribute the energy trajectory. Combustion,
plume, gross doorway, signed-pressure doorway and exterior enthalpy are
exported mainly as current-step values. F3.3b does not export pressure-only
accepted enthalpy totals. Summing those sparse `*_step` columns would be
invalid.

## F3.3c1 required instrumentation

Before another physics experiment, add a passive cumulative accepted-route
ledger inside `Phase3ZoneMassSystem`. It must observe each atomic route only
after the common inventory fraction is known and must never derive a flux from
post-step state mutation.

Use a new default-OFF flag such as:

```text
phase3_enthalpy_residence_diagnostics_enabled = false
```

For each room and zone, accumulate accepted sensible enthalpy in/out by these
exclusive cause families:

- canonical combustion heat;
- canonical plume lower-to-upper transfer;
- upper-to-lower inter-zone transfer;
- canonical wall exchange and direct ambient loss;
- F3.3a gross interior-opening transport;
- F3.3b signed-pressure interior transport;
- exterior pressure boundary and exterior counterflow;
- delayed parcel lifecycle and any remaining atomic transport family.

Also export cumulative wall decay separately from direct gas-to-ambient loss,
initial upper/lower energy, expected upper/lower energy change, observed
change, per-zone closure residual and building closure residual. Source and
destination zone must be retained; room-total conservation alone cannot
explain the upper-layer temperature.

## F3.3c1 STOP gate

F3.3c1 is instrumentation only. It may proceed only if:

1. Default OFF is schema- and value-identical to the committed F3.3b state.
2. Every accepted route is counted once after atomic limiting.
3. Upper, lower, room and building energy residuals close at physical-step
   precision without summing sparse CSV step fields.
4. Direct fixtures cover each cause family and distinguish F3.3a gross from
   F3.3b signed transport.
5. Group C, Group A, two-room, no-fire and stairwell controls remain stable;
   physics and ILV retain zero FAIL.

This gate is complete. The 600 s OFF/ON run preserved all 527 shared columns,
added 68 diagnostic fields and closed every zone/room/building residual at
exactly `0.0 kJ`. The exact ranking is in the F3.3c1 record. F3.3d must compare
those routes with time-resolved CFAST source and boundary terms before any new
physics is selected.

## Evidence and repository state

- Committed evidence: `runs/phase3_f32b7/group_c_control`,
  `runs/phase3_f33a/group_c_on`, `runs/phase3_f33b/group_c_600`.
- Scratch control: `runs/phase3_f33c/chi035_f33b`.
- Godot 4.7.1 run completed normally with no orphan process.
- No official validation report was regenerated.
- No commit or push belongs to this audit STOP.
