# Phase 3+ F3.1e passive thermodynamic closure

Date: 2026-07-18

## Decision

F3.1e is a **GO for passive canonical thermodynamic closure** and remains a
**NO-GO for canonical room-state authority**. The existing canonical shadow
keeps upper/lower gas mass and sensible energy authoritative. A pure function
now derives temperatures, one shared ideal-gas pressure, zone volumes and the
interface without writing `RoomModel` or changing inventory.

F3.2 exterior pressure/leakage is unblocked as the next default-OFF shadow
phase. This decision does not authorize publishing canonical pressure,
temperature, volume or interface into legacy state.

## Closure contract

Inputs are canonical upper/lower gas mass, upper/lower sensible energy, room
volume and geometry, plus the configured ambient reference temperature.

The closure uses:

```text
T_i = T_ref + E_i / (m_i cp)
P V_room = R_model (m_upper T_upper + m_lower T_lower)
V_i = m_i R_model T_i / P
interface = V_lower / floor_area
```

`R_model` is calibrated to the existing engine convention of `1.2 kg/m3` at
`101325 Pa` and the ambient reference temperature. Invalid, negative or
non-finite inventories are rejected. The function does not clamp or repair
mass and energy.

## Runtime evidence

The F3.1d one-room controls were repeated with shadow and diagnostics ON. All
344 inherited CSV columns and every inherited cell remained identical. F3.1e
adds 17 closure/divergence columns. Two additional passive columns complete
previously omitted atomic parcel refund telemetry for energy and O2; they do
not change the transaction.

| Control | Samples after t=0 | Invalid | Not closed | Gauge pressure | Interface |
|---|---:|---:|---:|---:|---:|
| No fire, 30 s | 6 | 0 | 0 | `0 Pa` | `2.5 m` |
| Fire, 30 s | 6 | 0 | 0 | `0.057..6.82 Pa` | `1.957..2.479 m` |
| Fire, 180 s | 36 | 0 | 0 | `-4.84..108.88 Pa` | `0.001..2.479 m` |

For every post-step sample, volume closure, mass invariance and energy
invariance residuals are exactly zero at CSV precision. The direct Godot
arithmetic fixture also covers ambient, stratified, near-empty and invalid
states and emits `PHASE3_F31E_THERMODYNAMIC_CLOSURE_PASS`.

The initial `t=0` CSV row is written before the first shadow transaction is
finalized, so its new fields remain zero and `thermo_valid_flag=0`. Analysis
must treat it as a pre-step snapshot, not a failed closure.

## Legacy divergence

Canonical transaction closure and legacy state equivalence remain separate.
The 180 s control still reports legacy divergence, peaking at approximately
`0.0302 kg` and `6.9424 kJ`. F3.1e does not relabel that projection-created
reservoir as transport and does not clear `phase3_shadow_needs_flux_owner_flag`.

## Validation

- Focused structural tests: `37 PASS`.
- Direct Godot closure fixture: PASS.
- Physics coherence: `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`.
- ILV coherence: `15 PASS / 14 CTRL / 0 FAIL`.
- Gap inventory: `348/353`, five documented VALID_GAP.
- Guardrails: only expected R2-1 while the motor patch is uncommitted.
- Broad selected pytest: F3.1e tests pass; four old two-zone structural tests,
  R2-1 and sandbox-denied temporary-file tests remain outside this change.

## Next gate

F3.2 may consume the passive canonical pressure and inventories to model
exterior leakage as one conservative gas/enthalpy/O2/species transaction.
It must remain default OFF and must not reuse legacy pressure purge or EOS
backfill as a second owner. Group A is the target; Group C remains F3.3.
