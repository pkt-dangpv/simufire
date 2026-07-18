# Phase 3+ F3.2b0 persistent canonical shadow

Date: 2026-07-18

## Decision

F3.2b0 closes with two separate results:

- **GO for passive step-to-step continuity.** Canonical mass, sensible energy,
  O2 and species can survive between steps without reseeding from `RoomModel`.
- **NO-GO for combustion authority and Group A closure.** The persistent
  shadow is still driven by legacy HRR, plume and source terms. Once canonical
  O2 diverges, those open-loop fluxes no longer describe the same fire.

The implementation is default OFF, never writes `RoomModel` and does not alter
legacy HRR, FED, reports, baselines or tolerances. It remains uncommitted at
this STOP gate.

## Delivered contract

`phase3_canonical_persistence_shadow_enabled` adds an internal persistent room
state to `Phase3ZoneMassSystem`. The runner flag implies the parent canonical
shadow and the F3.2a exterior boundary.

When enabled:

1. The first step seeds each room from the legacy pre-step snapshot.
2. `finalize_step()` commits the completed shadow only to an internal
   persistent dictionary.
3. Later steps start from that dictionary, not from legacy room fields.
4. `reset()` clears the persistent state and step index.
5. Combustion O2 telemetry compares the canonical upper-zone inventory with
   the actual legacy O2 reference.
6. The shadow replaces competing legacy upper/lower combustion sink records
   with one upper-zone request based on `o2_consumed_fire_kg_step`.

This last rule is passive. It does not throttle the live fire.

## Degenerate-zone normalization

Persistence exposed a state that one-step shadow runs could hide: plume
entrainment can reduce lower-zone gas mass to zero while later thermal terms
leave energy in that empty zone. F3.1e correctly rejects that state with
thermodynamic failure code 4.

F3.2b0 therefore includes a conservative representation change. If one zone
has zero gas mass, its residual gas, energy, O2 and every species are merged
into the remaining zone before exterior pressure is resolved. No room total
changes. Dedicated residuals for mass, energy, O2 and species remain exactly
zero.

This is not a mass source, pressure relief or physical transport event. It is
the canonical one-zone limit of a degenerate two-zone state.

## Runtime evidence

All evidence is under `runs/phase3_f32b/`; official reports were not touched.

### Direct multi-step fixture

- Upper O2 starts at 20%.
- A 0.5 kg upper-zone sink leaves 15%.
- Legacy is then reset artificially to 20%.
- The next canonical step still starts at 15%.
- Continuity residuals are zero for mass, energy, O2 and species.
- Full reset seeds 20% again.
- Degenerate-zone fusion conserves all four inventories exactly.

### `cfast_r0_window_360`

| Time | CFAST upper O2 | Legacy upper O2 | Persistent shadow upper O2 |
|---:|---:|---:|---:|
| 240 s | `0.085108` | `0.15951` | `0.10079` |
| 350 s | `0.065980` | `0.09819` | `0.00000` |
| 360 s | `0.064507` | `0.09345` | `0.00001` |

The 240 s point moves strongly in the expected direction. The later points
over-deplete because canonical O2 does not feed back into legacy combustion.
After the window opens, the shadow reaches about `-34.1 kPa`; this violates
the realistic-pressure authority gate. Before/after comparison retains all
115 legacy columns byte-identical across 228 rows.

Continuity residuals are exactly zero. Twenty-two logged room-0 rows exercise
the degenerate-zone fusion with zero normalization residual.

### `cfast_single_room_closed`

The 120 s control remains thermodynamically valid and has exact continuity,
but reaches about `2.58 kPa`. Canonical upper O2 is `0.18265` versus legacy
`0.20384`. This independently confirms that persistence works while the
open-loop fire/pressure coupling is not authoritative.

## Root cause of the NO-GO

The live engine computes HRR first and all downstream flux producers use that
legacy HRR. The persistent shadow can then discover that canonical O2 would
limit combustion, but it is too late to change consistently:

- combustion heat already follows legacy HRR;
- plume mass and enthalpy already follow legacy HRR;
- O2 demand and species generation already follow legacy HRR;
- exterior pressure therefore sees a mass/energy trajectory from a different
  fire than the canonical O2 inventory permits.

Scaling only the O2 sink would hide the mismatch. Scaling heat or species
independently would create a different mismatch. No partial multiplier is
accepted.

## Next gate: F3.2b1

F3.2b1 must design one closed shadow combustion/plume transaction. From one
canonical pre-step O2 state and one accepted fraction, it must derive and apply
together:

- candidate HRR and fuel consumption;
- combustion sensible energy;
- plume gas mass and transported enthalpy/O2/species;
- stoichiometric O2 sink;
- CO, CO2, HCN, smoke and irritant sources.

The transaction must not reuse already-mutated legacy outputs as independent
authority. A default-OFF live-authority experiment may only be considered
after this closed shadow stays finite and moves all three Group A O2 checks in
the expected direction.

### F3.2b1 outcome

F3.2b1 implemented this closed transaction and passed all three Group A O2
checks in shadow. The combustion mechanism is accepted as passive
infrastructure, but authority remains NO-GO because exterior-opening pressure
still reaches about `+26.9 kPa` and the lower canonical zone collapses. The
binding result is recorded in
`docs/validation/PHASE3_F32B1_COMBUSTION_TRANSACTION.md`.

## STOP gate

| Check | Result |
|---|---|
| New direct Godot fixture | PASS |
| Focused structural tests | `41 PASS` |
| Physics coherence | `9 PASS / 15 CTRL / 5 WARN / 0 FAIL` |
| ILV coherence | `15 PASS / 14 CTRL / 0 FAIL` |
| Gap inventory | `348/353`, five VALID_GAP, unchanged |
| Legacy OFF/ON columns | `115/115` byte-identical |
| Continuity and collapse residuals | exact zero |
| Group A direction at 240 s | improves |
| Group A at 350/360 s | overshoots to zero; NO-GO |
| Realistic pressure | FAIL; `-34.1 kPa` opening transient |
| Authority | NO-GO |

The broader `pytest -k phase3` run produced eight known Windows tempfile
permission failures plus one structural assertion updated for the new explicit
`begin_step` argument. Focused tests pass after that update.
