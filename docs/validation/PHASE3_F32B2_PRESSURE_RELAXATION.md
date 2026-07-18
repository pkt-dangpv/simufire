# Phase 3+ F3.2b2 canonical pressure relaxation

Date: 2026-07-18

## Decision

F3.2b2 closes with two decisions:

- **GO for passive exterior pressure relaxation and lower-zone reseed.** The
  mechanism prevents an explicit orifice step from crossing ambient pressure
  and restores a lower zone when real fresh-air inflow enters an upper-only
  canonical state.
- **NO-GO for canonical room-state authority and Group A retirement.** The
  pre-opening pressure trajectory and early one-zone residence remain outside
  the accepted physical envelope.

The feature is default OFF and never writes legacy room or fire state.

## Root cause

The F3.2a boundary computed an orifice flow from pressure at the beginning of
the physics step, then applied that full flow for the complete `dt`. It had no
bound for reaching equilibrium during the step.

At the old Group A opening sample:

| Quantity | Value |
|---|---:|
| Pre-boundary gauge pressure | `-34,018.54 Pa` |
| Raw requested inflow | `34.62479 kg` |
| EOS mass required for ambient pressure | `19.33844 kg` |
| Excess inflow | `15.28634 kg` |
| Old post-boundary pressure | `+26,890.43 Pa` |
| Exact equilibrium fraction | `0.5585144` |

The sign reversal is therefore an explicit integration overshoot, not a
combustion defect.

The lower-zone issue is separate. Plume entrainment reaches the conservative
upper-only limit near 160 s, roughly 200 s before the window opens. With
interface at floor level, F3.2a assigned every later inflow route to upper, so
lower could never reappear.

## Delivered contract

`phase3_canonical_pressure_relaxation_shadow_enabled=false` adds two passive
rules on top of the complete F3.2b1 stack.

### Exact pressure relaxation

For the raw atomic boundary bundle, pressure change is derived from the same
EOS used by the canonical thermodynamic closure:

`deltaP = sign * R / V * (delta_m * T_ref + delta_E / cp)`

If the full explicit step would cross ambient pressure, every route is scaled
by `-P_gauge / deltaP`. Gas mass, sensible energy, O2 and all species therefore
share one exact equilibrium fraction. This is not a fitted pressure clamp.

### Degenerate lower transition

If all canonical gas is in upper and a real exterior opening admits ambient
air, the first inflow is routed to lower. Closed-window leakage is excluded;
otherwise tiny leakage parcels would repeatedly create and entrain lower before
the opening event.

The first Group A reseed occurs at persistent step `4322`, approximately
`360.167 s`, and adds `0.14583 kg` to lower. No upper inventory is moved or
created by this representation transition.

## Runtime evidence

Scratch evidence is under `runs/phase3_f32b2/`; official reports were not
modified.

### `cfast_r0_window_360`

| Metric | F3.2b1 | F3.2b2 |
|---|---:|---:|
| Maximum final shadow pressure | `+26.89 kPa` | `+2.815 kPa` |
| Pressure at 370 s | `+26.89 kPa` | approximately `0 Pa` |
| Lower gas at 370 s | `0 kg` | `0.14583 kg` |
| Volume closure residual | `0` | `0` |
| Shared legacy columns changed | `0/115` | `0/115` |

Group A O2 remains:

| Time | Shadow upper O2 | Existing result |
|---:|---:|---|
| 240 s | `0.107933` | PASS |
| 350 s | `0.071571` | PASS |
| 360 s | `0.072421` | PASS |

Exterior mass, energy, O2 and species residuals are zero. Combustion residuals
and thermodynamic volume closure also remain zero.

### `cfast_single_room_closed`

F3.2b2 performs no equilibrium crossing or lower reseed. All 115 legacy fields
remain identical and the canonical pressure peak remains `+2.577 kPa`, exactly
as in F3.2b1. This proves that the new rule does not suppress pressure merely
because its magnitude is high.

## Remaining authority blockers

The catastrophic opening spike is closed, but authority is still premature:

1. Before opening, Group A canonical pressure spans approximately
   `-1.044..+2.815 kPa`, while its CFAST pressure is much closer to ambient.
2. Lower reaches the upper-only limit near 160 s. The transition is now
   reversible when fresh air arrives, but its early timing is not validated.
3. The five VALID_GAP entries must remain active until the canonical state,
   not only shadow O2, passes the authority gate.

## Verification

| Check | Result |
|---|---|
| Direct Godot F3.2b2 fixture | PASS |
| Focused Phase 3 tests | `75 PASS` |
| Broad Phase 3 tests excluding analyzer-tempfile tests | `340 PASS` |
| Physics coherence | `9 PASS / 15 CTRL / 5 WARN / 0 FAIL` |
| ILV coherence | `15 PASS / 14 CTRL / 0 FAIL` |
| Gap inventory | `348/353`, five VALID_GAP, unchanged |
| Legacy Group A columns | `115/115` identical |
| Group A shadow O2 | `3/3 PASS` |
| Atomic and volume residuals | exact zero |

Guardrails report only R2-1 while `sim/core` is dirty. No reference timestamp,
baseline, expected value, tolerance or official report was changed.

## Next gate: F3.2b3

F3.2b3 must diagnose the pre-opening pressure trajectory and early one-zone
residence separately. It should audit plume entrainment, sensible-energy
ownership, closed leakage and the one-zone thermodynamic contract before
proposing code.

Group A, Group C, HVAC, FED authority and baseline changes remain out of scope.
