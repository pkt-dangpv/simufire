# Phase 3+ F3.3d1 - accepted-route mass residence ledger

Date: 2026-07-22

## Decision

**Instrumentation GO. Physics, canonical authority and gap retirement remain
NO-GO.**

F3.3d1 adds a passive cumulative ledger for every accepted canonical gas-mass
route. It proves exact upper-zone, lower-zone, room and building mass closure
without reconstructing fluxes from post-mutation state. The ledger is default
OFF and adds CSV fields only when explicitly enabled.

The CFAST comparison selects plume entrainment and upper/lower partition as the
next physical owner. SimuFire entrains only 64-72% of CFAST plume mass in the
three common windows. Changing the radiation split from 0.70 to 0.35 changes
plume mass by less than 2%, so the partition gap is structural rather than a
source-energy scalar problem.

## Contract

The opt-in flag is:

```text
phase3_mass_residence_diagnostics_enabled = false
CLI: --phase3-mass-residence-diagnostics
```

The CLI enables the complete F3.3b prerequisite stack. The runtime flag is
inactive unless that stack is present.

The ledger captures the canonical upper/lower gas inventory before the first
persistent step. It then records gas mass only after the atomic accepted
fraction is known and immediately before the accepted route mutates the shadow
state. Legacy requests are recorded once at their accepted fraction. A
degenerate-zone collapse is recorded as one internal zone-to-zone transfer
before mutation.

Cause families are exclusive:

- combustion and plume;
- interzone heat, wall and ambient (normally zero mass by contract);
- exterior pressure and exterior counterflow;
- interior opening and signed interior pressure;
- delayed parcel lifecycle;
- legacy, zone collapse, reconcile and unclassified routes.

For every room and zone:

```text
expected mass = initial mass + cumulative accepted inflow
                              - cumulative accepted outflow
residual      = observed canonical mass - expected mass
```

Internal transfers cancel at room or building level. Exterior routes remain
visible as true building-boundary mass. There is no correction, clamp or
residual bucket that mutates state.

## CSV surface

The flag adds 72 fields:

- 16 initial/total/expected/observed/residual/count fields;
- 14 cause families x 2 zones x 2 directions.

The four binding residuals are:

- `phase3_shadow_mass_residence_upper_residual_kg`;
- `phase3_shadow_mass_residence_lower_residual_kg`;
- `phase3_shadow_mass_residence_room_residual_kg`;
- `phase3_shadow_mass_residence_building_residual_kg`.

With the flag OFF, the legacy CSV schema is unchanged. The Group C baseline
kept all 595 shared columns and all 366 rows byte-for-byte equal in parsed CSV
values. With the flag ON it has 667 columns.

## Runtime matrix

All runs used Godot 4.7.1 and scratch output under `runs/phase3_f33d1`; no
official report was regenerated.

| Case | Duration | Result | Max zone/room/building residual |
|---|---:|---|---:|
| `cfast_corridor_chain` baseline | 600 s | PASS | 0.0 kg |
| `cfast_corridor_chain` chi_rad=0.35 control | 600 s | PASS | 0.0 kg |
| `cfast_r0_window_360` | 520 s | PASS | 0.0 kg |
| `cfast_single_room_closed` | 60 s | PASS | 0.0 kg |
| `cfast_two_room_door_open` | 60 s | PASS | 0.0 kg |
| deterministic Godot fixture | n/a | PASS | exact |

The previous Group A control ended at 360.1 s whereas the current case ends at
520.1 s. Its first 222 rows and all 595 shared columns are identical; the extra
96 rows are duration coverage, not a physics delta.

The deterministic fixture also proves inventory limiting: a 100 kg request
from a 24.8 kg source records only accepted mass. It covers plume, interior,
exterior, parcel, zone-collapse and legacy routes while leaving wall,
ambient and reconcile mass at zero.

## CFAST mass correspondence

CFAST upper/lower gas mass is reconstructed directly as density times zone
volume. Plume mass is the trapezoidal integral of `PLUM_1`. Signed doorway
slabs are classified relative to the R0 interface and integrated over the
same windows as F3.3d.

### State endpoints

| t | State | CFAST | SimuFire base | SimuFire chi_rad=0.35 |
|---:|---|---:|---:|---:|
| 180 | upper gas (kg) | 26.943 | 22.921 | 18.510 |
| 180 | lower gas (kg) | 15.406 | 25.000 | 24.023 |
| 180 | interface (m) | 0.736 | 1.101 | 1.111 |
| 300 | upper gas (kg) | 25.949 | 22.890 | 18.464 |
| 300 | lower gas (kg) | 15.562 | 24.651 | 23.018 |
| 590 | upper gas (kg) | 25.249 | 23.794 | 19.465 |
| 590 | lower gas (kg) | 15.794 | 25.802 | 25.570 |

The late SimuFire upper mass is close to CFAST, but total gas is 8.55 kg high
at 590 s and the surplus is almost entirely in the lower zone. Early upper
mass is low while lower mass remains high, consistent with insufficient
lower-to-upper plume transfer.

### Window fluxes for R0

Masses are cumulative kg. Door net out is upper+lower out minus upper+lower
in. Exterior net out is positive for building loss.

| Window | CFAST plume | SF plume | SF/CF | CFAST door net out | SF door net out | SF exterior net out |
|---|---:|---:|---:|---:|---:|---:|
| 0-180 | 97.716 | 70.766 | 72.4% | 7.292 | 7.691 | +1.987 |
| 180-300 | 62.244 | 43.935 | 70.6% | 1.366 | 6.842 | -6.461 |
| 300-590 | 157.101 | 100.887 | 64.2% | 3.074 | 12.281 | -14.336 |

The first-window net doorway transport is already close. Later, SimuFire has
more net doorway loss, but growing exterior net inflow offsets it and adds to
the lower-zone surplus. The detailed slab comparison shows two secondary
differences: lower outflow persists in the signed interior-pressure family
after CFAST lower outflow is near zero, and late exterior flow reverses into
the room.

Neither difference explains the primary plume deficit. Absolute SimuFire
upper doorway outflow is below CFAST, and lower doorway inflow is broadly
present. Increasing an opening multiplier would therefore be the wrong first
change.

### Radiation control

| Window | Base plume (kg) | chi_rad=0.35 plume (kg) | Delta |
|---|---:|---:|---:|
| 0-180 | 70.766 | 70.561 | -0.3% |
| 180-300 | 43.935 | 44.060 | +0.3% |
| 300-590 | 100.887 | 102.815 | +1.9% |

The large source-energy change barely moves entrained mass. Radiation remains
a real calibration mismatch, but it cannot repair the mass/interface state.

## Hypothesis verdicts

| Candidate owner | Verdict | Evidence |
|---|---|---|
| Scalar source/radiation | Rejected as first physical change | Large temperature effect, less than 2% plume-mass effect. |
| Wall/ambient mass | Rejected | These are energy-only owners and correctly record zero mass. |
| Doorway gross exchange | Rejected as primary | Early net door mass already matches; absolute upper outflow is not excessive. |
| Exterior/pressure coupling | Secondary | Late net inflow and lower outflow create churn and lower-mass surplus. |
| Plume entrainment/partition | Selected | Accepted plume is 28-36% below CFAST and directly controls lower-to-upper mass. |

## Deferred source fields

F3.3d requested cumulative chemical HRR before radiation as an optional
addition. It is not added here. Existing combustion transaction fields plus
the exact F3.3c1 accepted-convective-energy ledger already separate actual HRR,
radiation and O2 limiting for the completed F3.3d energy audit. Adding another
energy accumulator to a mass-only gate would duplicate evidence and increase
schema scope. Revisit only if a future source-authority decision lacks a
time-integrated quantity.

## F3.3d2 result and next gate

F3.3d2 tested the missing Heskestad source term and closed conservation, but
it worsened both Group C temperature checkpoints. The candidate was fully
rolled back. See `PHASE3_F33D2_PLUME_SOURCE_TERM_EXPERIMENT.md`.

F3.3e must design a coupled convective-source/plume `Qc` contract before any
new implementation. The same authoritative convective HRR must determine
upper energy and plume entrainment.

Acceptance requires all of the following:

1. improve R0 upper/lower mass and interface at both 180 s and 590/600 s;
2. avoid worsening both Group C temperature checks;
3. retain Group A exterior-boundary closure;
4. do not increase late exterior/pressure churn to hide a plume error;
5. preserve every shared legacy column with the experiment OFF;
6. STOP before authority, report regeneration, gap retirement or source retune.

If no plume law can improve early and late mass/interface together, stop and
return to the exterior/interior pressure partition using this ledger. Do not
combine both mechanisms in one experiment.

## STOP gate

| Check | Result |
|---|---|
| New structural tests | 10/10 PASS |
| All Phase 3 tests | 424/424 PASS |
| Full pytest | 1073 PASS / 19 FAIL |
| Pre-existing pytest failures | 18 |
| Dirty-motor R2-1 integration failure | 1 expected |
| Physics suite | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV suite | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 PASS, 5 VALID_GAP |
| Guardrails | 9/10; only R2-1 dirty motor |
| Official cases/reports/baselines | unchanged |
| Physical state / canonical authority | unchanged |
| F3.3d1 commit | GO after explicit approval |
| F3.3d2 physical experiment | completed NO-GO; fully rolled back |
| F3.3e coupled Qc design | next gate |

The first raw fixture launch without an explicit Godot log path hit the known
Windows `user://logs` startup failure before project load. The valid rerun with
an explicit scratch log completed with exit 0 and the fixture PASS marker.
