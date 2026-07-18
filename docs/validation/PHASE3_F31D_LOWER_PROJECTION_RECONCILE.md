# Phase 3+ F3.1d lower-zone EOS projection/reconcile trace

Date: 2026-07-17

## Decision

F3.1d is a **GO for passive diagnostic telemetry** and a **NO-GO for treating
legacy projection as a physical owner**.

The remaining F3.1c residual is not an unregistered transport or reservoir
flow. `ZoneFireSolver.project_room_state()` enforces EOS closure at fixed
reference pressure by overwriting the conserved gas inventories. It can delete
lower mass and sensible energy, or add ambient mass with zero sensible
enthalpy. Later calls repeat the same operation and converge geometrically.

The canonical model must not reproduce or own that mutation. Its gas mass and
energy remain authoritative; temperature, shared pressure, zone volumes and
interface are derived from those conserved inventories.

F3.2 remains blocked. The next gate is F3.1e: a passive, pure canonical
thermodynamic closure with explicit legacy-divergence telemetry.

## Instrumentation

The existing `phase3_zone_diagnostics_enabled` flag now enables a per-call
trace around `project_room_state()`. The trace is passive and is reset once per
physical timestep. Each event records:

- call index, cause, room and simulation time;
- state before `ensure_room_state`, after ensure, before geometry and after
  projection;
- upper/lower EOS densities and implied volumes;
- upper capacity and lower target mass;
- separate ensure, temperature, upper-cap and lower-projection deltas;
- total mass and energy delta introduced by that projection call.

`tools/run_scenario_headless.gd` writes `projection_trace.jsonl` only when the
scratch scenario opts into `phase3_projection_trace_enabled`. The trace does
not enter the CSV schema. Normal runs neither create nor require the file.

The read-only analyzer is:

```powershell
python scripts/simulation/analyze_phase3_projection_trace.py `
  runs/phase3_f31d/trace_labeled/projection_trace.jsonl
```

## Call order

The 180 s one-room control executes exactly seven projections per physical
timestep:

1. `thermal_post_combustion_sync`
2. `thermal_energy_projection`
3. `thermal_post_losses_sync`
4. `reconcile_layer_sync` inside `ThermalSystem.step`
5. `gas_exchange_sync`
6. `reconcile_layer_sync` from the engine final reconcile
7. `final_clamp_active`

All 2,161 room-steps have this order. There are 15,127 events. No call is
unlabelled.

## Runtime evidence

| Delta family | Absolute signed peak | Cause |
|---|---:|---|
| ensure mass | `7.1e-15 kg` | numerical zero |
| ensure energy | `9.1e-13 kJ` | numerical zero |
| temperature projection energy | `-0.000165 kJ` | negligible |
| upper cap mass | `-0.02044149 kg` | first post-combustion projection |
| upper cap energy | `-6.05868546 kJ` | first post-combustion projection |
| lower projection mass | `-0.05661950 kg` | first post-combustion projection |
| lower projection energy | `-6.99578420 kJ` | first post-combustion projection |
| total per-call mass | `-0.05700088 kg` | first post-combustion projection |
| total per-call energy | `-6.99578420 kJ` | first post-combustion projection |

At `t=100.0833 s`, the seven calls sum to `-0.03016636 kg` and
`-3.84606761 kJ`. Those values are the sign-opposite of the F3.1c shadow
residual at the same step. At `t=120.0833 s`, the summed energy mutation is
`-6.94237481 kJ`, matching the F3.1c maximum energy residual.

The first call removes most of the inventory. Subsequent calls add smaller
amounts of lower gas at ambient sensible enthalpy. Adding that mass lowers the
derived lower temperature, changes density and therefore changes the next EOS
target. This explains the repeated geometric backfill.

## Controls

| Control | Events | Result |
|---|---:|---|
| 30 s, no fire | 2,527 | every mass and energy delta exactly zero |
| 30 s, fire | 2,527 | lower projection already reaches `-0.00351586 kg`; pattern grows with heating |
| 180 s, fire | 15,127 | full peaks above; exact F3.1c residual correspondence |

The first unisolated Godot attempt crashed before simulation while opening
`user://logs`; it produced no summary, CSV or manifest and is excluded. Both
controls completed with exit 0 after isolating Godot `APPDATA` under the
scratch run directory. No Godot process remained after either run.

## Root cause

For a closed fixed-volume room, the current projection assumes ambient
pressure and then changes mass to satisfy that assumption. This is equivalent
to an implicit infinite ambient reservoir, but no physical boundary flow was
accepted. The operation therefore violates the canonical ownership model.

The canonical closure for two ideal-gas zones must instead use:

```text
T_upper = T_ref + E_upper / (m_upper * cp)
T_lower = T_ref + E_lower / (m_lower * cp)
p_shared = R * (m_upper*T_upper + m_lower*T_lower) / V_room
V_upper = m_upper * R * T_upper / p_shared
V_lower = m_lower * R * T_lower / p_shared
interface = V_lower / floor_area
```

This preserves `m_upper + m_lower` and `E_upper + E_lower` exactly. Exterior
flow may later change those inventories through F3.2, but projection itself
may not.

## Revised gate semantics

Requiring the passive canonical inventory to equal the post-projection legacy
inventory would force the new model to reproduce a known nonphysical mutation.
F3.1e must therefore separate two signals:

- canonical transaction closure: all accepted physical requests close;
- legacy state-definition divergence: the measured projection delta remains
  visible but is not called transport or assigned a physical owner.

Authority remains forbidden until the pure closure is runtime-tested and the
legacy divergence is bounded and explained. This is a stricter gate, not a
suppression of findings.

## Verification

| Check | Result |
|---|---|
| Focused trace/analyzer tests | 22 PASS |
| Broad Phase 3/two-zone selection | 161 PASS, 4 pre-existing structural failures |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 required, 5 VALID_GAP, sync PASS |
| Guardrails | 9/10; only expected R2-1 while motor is dirty |
| Legacy CSV shared cells, OFF vs traced ON | 0 differences |
| Official reports/baselines/tolerances | unchanged |

## F3.1e scope

F3.1e may add a pure function or shadow component that derives temperature,
shared pressure, volumes and interface from canonical mass and energy. It must
not write `RoomModel`, delete or add inventory, start exterior flow, alter FED,
or change validation classifications. It must retain the F3.1d trace until
canonical and legacy state definitions can be compared directly.

F3.2 starts only after the passive closure is finite, positive, volume-closing,
mass/energy-conserving and stable in the no-fire, short-fire and 180 s controls.
