# Phase 3+ F3.2b3 canonical plume geometry

Date: 2026-07-18

## Decision

F3.2b3 closes with two separate decisions:

- **GO for the default-OFF canonical plume shadow.** Plume entrainment is now
  previewed from canonical pre-step mass, sensible energy, O2 and interface.
  This removes the premature one-zone collapse without writing legacy room or
  fire state.
- **NO-GO for canonical room-state authority and Group A retirement.** The
  pre-opening pressure trajectory remains outside the accepted CFAST envelope
  and needs its own heat/boundary contract diagnosis.

The plume mechanism is accepted as passive infrastructure. It is not approved
to drive production physics.

## Root cause: cross-state plume semantics

F3.2b2 closed combustion from canonical O2 but still evaluated plume
entrainment from `room.thermal_layer_m`, the legacy interface. The accepted
plume mass was then applied to the persistent canonical zones. The producer
and consumer therefore described different geometries.

At about 150 s in `cfast_r0_window_360`:

| Quantity | Value |
|---|---:|
| Legacy interface used by the live plume | `1.458 m` |
| Canonical interface before F3.2b3 | `0.260 m` |
| Plume from legacy geometry | `0.621 kg/s` |
| Same correlation from canonical geometry | `0.034 kg/s` |
| CFAST plume | `0.062 kg/s` |

The legacy geometry requested roughly eighteen times the canonical-geometry
entrainment at that sample. Repeated application exhausted canonical lower
near 160 s even though CFAST retained about `2.1 kg` of lower gas and held its
interface at `0.10 m`.

## Delivered contract

`phase3_canonical_plume_shadow_enabled=false` adds a pure canonical plume
preview on top of the complete F3.2b2 shadow stack.

The preview:

1. Reads canonical pre-step upper/lower mass and sensible energy.
2. Derives temperature and interface from the canonical EOS closure.
3. Evaluates the existing McCaffrey/Heskestad correlation using that interface.
4. Caps transfer by canonical lower inventory.
5. Moves proportional lower sensible enthalpy and O2 with plume gas.
6. Returns a request only; it does not mutate `RoomModel`, `FireModel` or the
   persistent canonical state directly.

The engine emits this request whenever the canonical combustion candidate is
active. It no longer requires a legacy plume event to exist, which avoids
making the shadow transaction depend on a post-legacy side effect.

The flag is default OFF. It adds no CSV columns and changes no legacy output.

## Runtime evidence

Scratch evidence is under `runs/phase3_f32b3/`; official reports were not
modified.

### Lower-zone residence

| Time | F3.2b2 lower gas | F3.2b3 lower gas | F3.2b3 interface | CFAST interface |
|---:|---:|---:|---:|---:|
| 140 s | `11.49 kg` | `15.62 kg` | `0.662 m` | `0.114 m` |
| 160 s | `0 kg` | `12.84 kg` | `0.549 m` | `0.100 m` |
| 240 s | `0 kg` | `6.35 kg` | `0.320 m` | `0.100 m` |
| 350 s | `0 kg` | `2.68 kg` | `0.223 m` | `0.100 m` |
| 360 s | `0 kg` | `2.48 kg` | `0.214 m` | `0.100 m` |

The lower zone no longer collapses. Its final mass is close to the CFAST
order of magnitude, although the interface remains too high and is not yet an
authority result.

### Group A O2

| Time | Canonical upper O2 | CFAST | Existing tolerance | Result |
|---:|---:|---:|---:|---|
| 240 s | `0.100996` | `0.085108` | `+/-0.031` | PASS |
| 350 s | `0.074077` | `0.065980` | `+/-0.015` | PASS |
| 360 s | `0.074071` | `0.064507` | `+/-0.015` | PASS |

All three checks remain shadow-only. The five VALID_GAP entries stay active.

### Pressure remains a separate blocker

F3.2b3 improves the late pre-opening pressure but does not close the full
trajectory:

| Time | F3.2b2 | F3.2b3 | CFAST |
|---:|---:|---:|---:|
| 160 s | `+1.925 kPa` | `+1.812 kPa` | `+1.061 kPa` |
| 240 s | `+1.279 kPa` | `+0.734 kPa` | `+0.013 kPa` |
| 350 s | `-0.700 kPa` | `-0.341 kPa` | `+0.167 kPa` |

Internal plume transfer conserves total room mass and sensible energy, so it
cannot by itself set total EOS pressure. Two configuration differences were
measured but are not accepted as one-cause fixes:

- CFAST uses radiative fraction `0.35` (65% convective). The Group A case
  forces `0.70` (30% convective).
- The CFAST leakage ratio corresponds to about `0.00905 m2` for R0, while the
  current SimuFire case uses `0.005 m2`.

Changing either value alone does not close the pressure trajectory. Their
combined effect improves some samples but still diverges mid-fire. No fitted
pressure clamp, case-only tuning or authority path is accepted in F3.2b3.

## Verification

| Check | Result |
|---|---|
| Direct Godot canonical-plume fixture | PASS |
| Focused F3.2b0-b3 tests | `42 PASS` |
| Broad Phase 3/two-zone tests | `383 PASS`, four pre-existing structural failures |
| Physics coherence | `9 PASS / 15 CTRL / 5 WARN / 0 FAIL` |
| ILV coherence | `15 PASS / 14 CTRL / 0 FAIL` |
| Gap inventory | `348/353`, five VALID_GAP, unchanged |
| Legacy Group A columns | `115/115` identical |
| F3.2b2 OFF control | `222 x 407` values identical |
| Canonical volume closure | exact zero |
| Combustion atomic fraction | `1.0` in sampled rows |

Guardrails report only R2-1 while `sim/core` is dirty. No baseline, expected
value, tolerance, CTRL envelope or official report was changed.

## Next gate: F3.2b4

F3.2b4 must diagnose canonical pressure source and boundary equivalence before
any authority move. It must reconcile the convective/radiative heat contract,
closed leakage and the CFAST boundary definition using measured mass and
energy residuals.

It may not tune a pressure cap, change Group A expected values, publish the
canonical state into `RoomModel`, or begin Group C/HVAC work. If no general
contract closes the pressure envelope, authority remains NO-GO and the result
must be documented rather than compensated.
