# Phase 3 H3.2-S0d1 Suppression Owner and Donor-less Mass Seeds

Date: 2026-08-04.

## Decision

**GO at STOP gate for passive instrumentation of B1-upper, B2 and B3 only.**
B1-lower is **not** instrumented: the audit found there is no accepted lower
energy sink to own. HVAC stays deferred, species/O2 stay pending, no integrator
was created, H3.2-S stays blocked, H3.2b still blocks H3.3 and no runtime
authority was granted.

## Causal table

| ID | Site | State mutated | Accepted magnitude | Donor | Class | Conserves? | Decision |
|---|---|---|---|---|---|---|---|
| B1-upper | `SimulationEngine.gd:3363` | `room.upper_energy_kj` | `min(upper_energy_kj, cooling_kj * suppression_upper_heat_fraction)` | water/steam, tracked in `room.steam_kg` | `local_source` (negative) | sink; counterpart is a separate inventory | **instrumented** |
| B1-lower | `SimulationEngine.gd:3400` | `room.temp_lower_c` | **none accepted** | — | not classifiable | n/a | **not instrumented; physics finding** |
| B2 | `ThermalSystem.gd:1631` | `tgt.upper_gas_kg` | `floor_area_m2 * 0.08 * density` minus the prior value | **none** | `numerical_correction` | no; reconciled later by projection volume closure | **instrumented as numerical** |
| B3 | `ThermalSystem.gd:3290` | `cold_room.upper_gas_kg` | `+0.005 kg` | **none** | `numerical_correction` | no; reconciled later by projection volume closure | **instrumented as numerical** |

## B1 — suppression

The upper sink is an explicit accepted `kJ` at a single mutation site. It is
recorded as a signed `local_source`, the same treatment S0b gives wall
absorption: energy leaves the gas phase into a separate inventory rather than
crossing a room boundary, so `exterior_boundary` would misstate the geometry and
would fail the contract's room/exterior zone identity. The `steam_kg` counterpart
travels as metadata. The event is emitted after the mutation and before
`sync_room_upper_layer`, so projection is never counted twice.

### B1-lower is a physics finding, not a ledger gap

Legacy writes the lower-zone cooling as a temperature:

```
room.temp_lower_c = max(ambient_c, room.temp_lower_c - lower_drop_c)
...
thermal_system.sync_room_upper_layer(room, dt, "suppression_sync")
```

`sync_room_upper_layer` reaches `ZoneFireSolver.project_room_state`, which
derives `temp_lower_c` **from** `lower_energy_kj` and then rewrites
`lower_energy_kj` from that temperature. Suppression never touches
`lower_energy_kj`, so the drop is discarded. A direct probe of that exact call
sequence confirms it:

| Configuration | `temp_lower_c` before | after the write | after the sync |
|---|---:|---:|---:|
| two-zone (default) | 80.000 | 60.000 | **80.000** |
| legacy | 80.000 | 60.000 | 60.000 |

Under the default two-zone configuration the suppression lower cooling has **no
effect on the state**. Emitting `suppression_lower_energy_sink` would fabricate
an owner for an effect the state never receives, which the phase forbids. The
correction is filed as separate work: either apply the sink to
`lower_energy_kj` at the physical site, or delete the dead temperature write.
Both change physics and therefore need their own flag and STOP gate.

## B2 and B3 — donor-less mass

Option A was selected for both, on the evidence:

- Both are guarded by a degenerate-state test (`upper_gas_kg <= 0.0001`,
  `upper_gas_kg < 0.01`), so they only fire when the upper layer does not exist.
- Both exist so a pure-energy transfer has somewhere to land; the surrounding
  transfer moves energy only.
- Both are immediately followed by `sync_room_upper_layer`, whose projection
  recloses the zone volumes and books the difference into
  `two_zone_boundary_mass_kg`.

They are therefore **numerical initialisation**, not physical sources. They are
now visible as `numerical_correction`, carry `donor: none` in metadata, and are
structurally excluded from the source vector by the S0a contract. Options B, C
and D were rejected for this phase because each changes physics; if the project
later wants a real donor or a deletion, that is a separate flagged experiment.

## Deliberate exclusions

- HVAC keeps no owner and its `remove_upper_layer_fraction` call keeps no
  provenance, by product decision.
- Species and O2 ownership is unchanged from S0c.
- Projection, doorway and parcel ledgers are reused, never re-emitted.
- No `Phase3PhysicalSourceIntegrator` was created.

## STOP evidence

- Eight OFF/ON pairs are byte-identical with identical row counts and the same
  115 legacy columns; the OFF summary carries no ledger key:
  `cfast_suppression_water`, `v8_suppression_reburn`, `flashover_simple_house`,
  `cfast_two_room_door_open`, `cfast_two_floor_stairwell`, `two_storey_smoke`,
  plus `cfast_corridor_chain` and `fuel_balance_diag_sealed` as controls.
- Every ledger is valid with zero invalid events, zero duplicates and unique IDs.
- `suppression_upper_energy_sink` fires in `cfast_suppression_water` at 150 s,
  inside the case's 120-180 s suppression window.
- `thermal_counterflow_minimum_upper_mass` fires in exactly the two cases that
  enable doorway counterflow: `cfast_two_room_door_open` (4 events, 0.020 kg)
  and `cfast_corridor_chain` (1 event, 0.005 kg). Both contribute `0.0` to the
  source vector, which counts only local and exterior classes.
- `thermal_opening_radiation_target_mass_seed` did not appear in any final-step
  ledger of the sampled cases; its site is exercised by the fixture, which
  drives `_step_radiation_openings` against an empty target layer.
- The Godot fixture drives the real `_apply_suppression_to_room`,
  `_step_radiation_openings` and `_apply_doorway_thermal_counterflow` sites, the
  projection-discard probe, and the fail-closed duplicate case. A temporary
  inverted assertion exits 1 with no PASS marker.
- Eleven sequential Godot 4.7.1 fixtures pass, including H1, H2.10, H3.2a,
  H3.2-M atomic acceptance, the coupled bundle shadow, the atomic parcel
  lifecycle and S0a/S0b/S0c.
- Focused `pytest` for S0a-S0d1 is `67 PASS`. The broad Phase 3/guardrail
  selection is `1386 PASS / 2 FAIL`: the expected R2-1 freshness failure from
  the dirty motor and the pre-existing layer-interface export test.
- Physics coherence is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV coherence is
  `15 PASS / 14 CTRL / 0 FAIL`; the gap inventory is unchanged at
  `353 required + 6 VALID_GAP + 71 non-gating`. Guardrails are `9/10` with only
  the expected R2-1 failure. No Godot process remains.

## Interpretation limit

S0d1 closes three of the six S0d blockers and converts one of them into a named
physics defect. It does not make the source vector complete: HVAC, species and
O2 remain uncovered, and the integrator's self-completeness problem (B6) is
untouched. H3.2-S still cannot close.
