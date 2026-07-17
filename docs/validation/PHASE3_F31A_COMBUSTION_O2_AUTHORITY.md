# Phase 3+ F3.1a combustion O2 authority diagnosis

Date: 2026-07-17

## Decision

F3.1a closes with two separate decisions:

- **GO for the semantic invariant** that OxygenExchangeSystem must debit the
  same O2 zone selected by CombustionSystem for the current step.
- **NO-GO for global or authoritative activation** of that contract. The
  existing default-OFF `fire_o2_canonical_enabled` flag proves the invariant
  in the selected controls, but the engine still lacks a shared definition of
  active boundaries and complete O2 mass-flow ownership.

No new motor code, validation baseline, tolerance, official report, CTRL
classification or VALID_GAP was changed in F3.1a. F3.2 remains blocked.

## Root cause

The upper-O2 zombie was not a failure of the F3.1 extinction guard. The guard
correctly uses the O2 source selected by combustion. The problem is that three
systems do not agree on the physical scope of that source:

1. `CombustionSystem._resolve_fire_o2_selection()` uses the two-zone interface.
   With an interface above the fire it selects `plume_lower`, even if upper O2
   is exhausted.
2. `OxygenExchangeSystem` routes the debit to lower O2 only when its own
   sealed-room predicate passes. That predicate inspects opening geometry.
   Otherwise it can debit bulk O2 while combustion throttles against lower O2.
3. `ThermalSystem._phase3_shadow_sealed_room_scope()` also inspects opening
   geometry. It can reject a room even when the case has interior transport
   disabled, so the shadow omits combustion heat ownership.

`fuel_balance_diag_sealed` and `o2_stoich_diag_sealed` expose the mismatch:
their building topology contains interior openings, while the scenario turns
the corresponding transport paths off. Combustion treats the two-zone plume
as active, but OES and the shadow treat the room as open. A raw opening object
is therefore not a sufficient authority predicate.

## Runtime evidence

All runs were scratch runs with redirected output. Official reports were not
overwritten.

| Control | Legacy/default OFF | Canonical O2 routing ON | Result |
|---|---:|---:|---|
| `fuel_balance_diag_sealed`, zombie rows | 34 | 0 | Selected source and debit source agree |
| `fuel_balance_diag_sealed`, max HRR | 3394.69 kW | 796.52 kW | Legacy path was over-burning |
| `fuel_balance_diag_sealed`, fuel consumed | 384.87 MJ | 109.22 MJ | Large physical delta; not promotable globally |
| `o2_stoich_diag_sealed`, Thornton residual | not used as authority proof | about `8e-9 kg` | O2E1 closes |
| `cfast_two_floor_stairwell`, zombie rows | 36 | 0 | Zombie removed |
| `cfast_two_floor_stairwell`, max HRR | 4915.89 kW | 953.77 kW | Opening supply model still governs acceptance |
| `fp_ilv_upper_throttle_off`, zombie rows | 41 | 0 | Zombie removed in ventilated control |
| `v1_backdraft_accumulation`, zombie rows | 64 | 0 | Zombie removed |
| `v1_backdraft_accumulation`, post-open HRR | about 3425 kW legacy | 1493.23 kW canonical | Reventilation still recovers combustion |

The canonical controls pass O2E1/A3. The existing long
`fp_ilv_open_partial_window` control also uses canonical routing without a
zombie. This proves the semantic contract, not global physical completeness.

## Policy assessment

| Policy | Decision | Reason |
|---|---|---|
| Always use upper O2 | NO-GO | Ignores lower-zone entrainment and can extinguish a fire with valid fresh-air supply |
| Select lower O2 from interface only | Partial | Matches the current plume model but does not represent available O2 mass flow |
| Infer authority from opening geometry | NO-GO | Geometry can exist while its transport path is disabled |
| Bound combustion by explicit O2 mass-flow supply | Long-term target | Couples inventory, entrainment and ventilation without ambiguous concentration selection |
| Reuse `fire_o2_canonical_enabled` | Provisional GO | Correctly synchronizes the selected source and OES debit, remains default OFF |

## Shadow authority gate

The 120 s canonical shadow control remains a NO-GO for authority:

- maximum total mass residual: `0.02809879 kg`;
- maximum total energy residual: `8.23522174 kJ`;
- combustion ownership mask: `6`, meaning O2 plus species but no heat;
- `needs_flux_owner=1`;
- duplicate ownership: zero;
- zero-O2 flame flag: zero.

The missing heat bit is explained by the inconsistent sealed-room predicate,
not by a missing combustion result. Publishing the shadow while the mask is 6
would make partial ownership look complete.

## Next phase: F3.1b

F3.1b must introduce one shared, read-only active-boundary/scope contract used
by CombustionSystem, OxygenExchangeSystem and ThermalSystem shadow adapters.
It must describe effective transport, not merely the presence of an opening.

Minimum requirements:

1. Include the case transport flags that actually enable doorway, exterior,
   vertical and canonical opening flow.
2. Produce the same sealed/two-zone scope in Combustion, OES and Thermal.
3. Keep legacy physics and CSV output invariant when the experimental flag is
   OFF.
4. In the sealed shadow control, reach combustion mask `7` and
   `needs_flux_owner=0` without inventing a heat, O2 or species flux.
5. Retain zero duplicate owners, zero zero-O2 flame events and bounded
   mass/energy residuals.
6. Preserve reventilation and `fire_o2_independent` behavior.

F3.1b is still diagnostic/contract work. It does not authorize global
`fire_o2_canonical_enabled`, publish canonical state into `RoomModel`, start
F3.2, modify validation classifications or update physical baselines.

## STOP gate

F3.1a is accepted as a diagnosis and policy decision only. Any future
implementation must roll back if it changes default-OFF output, chooses an O2
zone independently in more than one subsystem, derives scope from raw opening
geometry alone, suppresses reventilation, or reports complete ownership while
the combustion mask is not 7.
