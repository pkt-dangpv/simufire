# Phase 3 H3.2-S0b Thermal Physical-Owner Events

Date: 2026-08-03.

## Decision

**GO at STOP gate for passive thermal instrumentation only.** This phase does
not construct independent coupled-solver sources, grant runtime authority or
close any validation gap. H3.2-S remains blocked on S0c gas owners and S0d
integration; H3.2b remains blocking before H3.3.

## Scope

`phase3_physical_owner_ledger_enabled` is default OFF. When enabled,
`ThermalSystem` emits step-local `Phase3PhysicalOwnerLedger` events from the
accepted mutation sites. Events are exposed only in the technical summary;
the legacy CSV schema is unchanged.

| Mutation family | Classification | Accounting |
|---|---|---|
| convective combustion heat | local source | upper sensible-energy credit |
| plume entrainment, layer lift and vertical mixing | interzone redistribution | measured upper/lower mass and energy deltas |
| radiation, ambient loss, decay and fresh-air cooling | exterior boundary | explicit room debit or exterior inflow |
| wall absorption/emission and wall conduction reservoir exchange | local source | room delta plus surface-storage counterpart metadata |
| opening radiation and thermal background/stairwell transport | interior transport | equal source debit and destination credit |
| outside-assisted room transport | interior transport + exterior boundary | delivered transfer separated from external loss |

## Deliberate Exclusions

- Projection and reconciliation reuse the existing `ZoneFireSolver`
  projection trace and `two_zone_boundary_energy_kj` ledger.
- Canonical doorway upper/lower/counterflow paths retain their existing unique
  ledger and are not emitted again.
- Delayed parcels retain their existing cross-step ledger.
- Legacy non-two-zone plume paths do not expose a truthful lower-zone donor and
  are not labelled as interzone transfer.
- Generic upper-layer removal needs caller provenance and remains for S0c/S0d.
- Gas exchange, HVAC and species ownership are outside S0b.

## STOP Evidence

- The Godot fixture covers default OFF, real vertical mixing, real minimum-layer
  transfer, deterministic IDs and pure exports. A temporary inverted assertion
  exits 1 and prints no PASS marker.
- Four official 30 s scenario pairs are byte-identical OFF/ON:
  `cfast_corridor_chain`, `cfast_r0_window_360`,
  `fuel_balance_diag_sealed` and `o2_stoich_diag_sealed`.
- Their final-step ledgers contain 11-14 valid events, zero invalid events and
  zero duplicate IDs. Maximum conservative residuals are
  `2.665e-15 kg` and `8.882e-16 kJ`.
- No `SimulationLogWriter` or `SimulationStateBuilder` fields were added.
- Seven sequential Godot 4.7.1 regression fixtures pass. The broad Phase 3 and
  guardrail selection reports `1338 PASS / 2 FAIL`: R2-1 freshness from the
  dirty motor and the pre-existing layer-interface export test.
- Physics is `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`; ILV is
  `15 PASS / 14 CTRL / 0 FAIL`; gap inventory remains
  `353 required + 6 VALID_GAP + 71 non-gating`. Guardrails are `9/10`, with
  only the expected R2-1 freshness failure. No Godot process remains.

## Interpretation Limit

The ledger proves that the listed legacy thermal mutations can be attributed
without changing their result. It does not prove those mutations are
physically correct, and it is not yet a non-circular source vector for the
coupled pressure solver.
