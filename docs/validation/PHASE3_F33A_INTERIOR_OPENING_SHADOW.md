# Phase 3+ F3.3a - Canonical horizontal interior-opening shadow

Date: 2026-07-20

## Decision

**GO as default-OFF shadow infrastructure. NO-GO for authority and for
retiring Group C.**

F3.3a adds a passive canonical owner for horizontal interior openings. It
does not write `RoomModel`, alter FED, change validation expectations or claim
vertical openings. The mechanism is conservative and opening-order
independent, but it improves the early Group C temperature while worsening
the late temperature. A pressure-coupled inter-room phase is still required.

## Contract

The opt-in flag is:

```text
phase3_canonical_interior_opening_shadow_enabled = false
```

When enabled, the engine:

1. Reads every horizontal interior opening from one common canonical pre-step
   snapshot.
2. Sorts openings by stable opening id.
3. Solves a hydrostatic neutral plane with equal gross mass in both
   directions. Signed pressure-driven net flow is deliberately outside F3.3a.
4. Integrates the piecewise-linear pressure field exactly between the two
   zone interfaces. No vertical sampling approximation is used.
5. Creates one network atomic bundle for all openings before mutating the
   canonical shadow.
6. Applies one globally inventory-limited acceptance fraction.
7. Carries gas mass, sensible enthalpy, O2, smoke, CO, CO2, HCN, HCl,
   acrolein and formaldehyde from source-zone concentrations.

A one-zone ambient receiver is valid. Its occupied-zone density is extended
through the empty geometric zone only for hydrostatic evaluation; no mass,
energy or species are created.

Vertical openings remain owned by the existing stairwell contract. Exterior
openings remain owned by F3.2a/F3.2b6. Legacy horizontal doorway/species
events are suppressed only inside the canonical shadow when F3.3a is active;
the live legacy engine is unchanged.

## Telemetry

The flag adds 27 CSV columns. They cover opening and route counts, vertical
skips, invalid previews, neutral plane, requested/accepted gas, energy, O2 and
species, accepted fraction, per-room net deltas, four building conservation
residuals and duplicate ownership.

With the flag OFF, the legacy CSV schema is unchanged. In the 60 s direct
two-room OFF/ON comparison, all 115 shared non-Phase-3 columns were exactly
identical.

## Runtime evidence

All evidence is under `runs/phase3_f33a/`; no official validation report was
regenerated.

| Control | Result |
|---|---|
| Direct Godot fixture | PASS: exact pressure integral, one-zone receiver, bidirectional flow, global cap, all-quantity conservation, reversed opening order and vertical exclusion |
| `cfast_two_room_door_open`, 60 s | 5 active horizontal openings, 0 invalid previews, 0 duplicate owners, exact mass/energy/O2/species residuals |
| Same case, legacy OFF/ON | 115/115 shared non-Phase-3 columns identical |
| No-fire two-room control, 60 s | Small passive exchange only: 0.0142 kg summed sampled outflow, 0.00123 kg maximum sampled step; all residuals zero |
| `cfast_two_floor_stairwell`, 60 s | Vertical opening explicitly skipped; horizontal doors active; all residuals zero |
| Group A, 60 s | Room 0 has 0 F3.3a openings and 0 requested flow because its interior door is closed; exterior owner remains exclusive |

The analytic implementation reduced the 60 s two-room runtime from 143.5 s
for the initial 64-band numerical prototype to 35.8 s. The predecessor stack
without F3.3a took 20.3 s. Performance remains a watch item for future live
authority, but is acceptable for an opt-in diagnostic run.

## Group C result

Reference targets are 159.816 C at 180 s and 168.796 C at 600 s. Existing
tolerances remain 15 C and 30 C respectively.

| R0 upper temperature | F3.2b7 shadow | F3.3a shadow | Direction |
|---|---:|---:|---|
| 180 s | 227.90 C | 130.94 C | Strong early improvement, but still outside tolerance |
| 600 s | 113.91 C | 102.73 C | Worse late undershoot |

F3.3a raises the canonical interface at 180 s from 0.620 m to 1.113 m and
keeps substantially more lower-zone inventory. It therefore fixes the early
thin-layer/overheating tendency, but equal-gross counterflow removes too much
late upper enthalpy. The two target checks do not improve together, so Group C
remains a VALID_GAP and the shadow must not become authoritative.

## Validation gates

| Gate | Result |
|---|---|
| Focused F3.3a/F0/F1 tests | 42 PASS |
| Relevant physics/ILV/guardrail tests outside sandbox | 283 PASS / 1 expected R2-1 failure |
| Full pytest outside sandbox | 1044 PASS / 18 pre-existing structural failures / 1 expected R2-1 failure |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 required PASS; 5 VALID_GAP; 71 non-gating gaps |
| Guardrails | 9/10; only R2-1 because `sim/core` is intentionally dirty at STOP |

The failures in the adjacent legacy two-zone and full structural selections
are pre-existing assertions unrelated to F3.3a. This includes the canonical
doorway O2 assertion against unchanged `ThermalSystem.gd`. Pytest tests that
use Windows temporary directories must run outside the filesystem sandbox;
otherwise permission failures are environmental, not product failures.

## Next phase

F3.3b must diagnose canonical inter-room pressure coupling. It must not add a
flow multiplier. The next question is whether a signed network pressure solve,
applied atomically together with the F3.3a gross counterflow, can retain late
upper enthalpy while preserving the early layer-mass correction.

Required constraints remain:

- default OFF and shadow-only;
- one pre-step network solve, not opening-by-opening mutation;
- no duplicate pressure, parcel or vertical owner;
- exact building mass, energy, O2 and species conservation;
- Group C must improve at both 180 s and 600 s before authority is considered;
- Group A, FED, expected values, tolerances, CTRL envelopes and HVAC remain
  unchanged.
