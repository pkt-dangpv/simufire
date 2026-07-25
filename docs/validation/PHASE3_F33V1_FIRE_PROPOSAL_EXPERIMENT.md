# Phase 3+ F3.3v1 canonical fire proposal experiment

Date: 2026-07-25

## Decision

F3.3v1 is **GO as passive, default-OFF telemetry**.

Runtime authority and retirement of Group C remain **NO-GO**. The proposal
does not yet own species, heat, plume products or live fuel-object
synchronization. Those belong to F3.3v2.

## Implemented contract

`CombustionSystem.evaluate_phase3_canonical_fire_proposal()` is a pure,
dictionary-only evaluator. It starts from persistent proposal state and
immutable room-fire parameters, then computes:

1. the room-level t-squared HRR proposal;
2. hard O2 extinction;
3. exact O2-inventory acceptance;
4. optional Kawagoe ventilation acceptance;
5. exact remaining-fuel acceptance.

The accepted candidate debits one common fraction from HRR, O2 and fuel.
It never writes `RoomModel` or replaces the existing canonical combustion
transaction. The proposal state is persisted only inside the passive Phase 3
shadow.

The new flag is
`phase3_canonical_fire_proposal_shadow_enabled`, default `false`. When OFF,
the legacy CSV schema is unchanged. When ON, 19
`phase3_shadow_fire_proposal_*` columns are added.

## Scope guard

The first scope supports the aggregate room-level t-squared fires used by
Groups A/C. It rejects no fire, secondary HRR, flashover, thermal feedback,
retained/pool gas, active backdraft, room-to-room fire spread, latent fire and
O2-independent fire with an explicit reason mask.

The generic intraroom furniture-radiation capability is not itself an active
spread mode. `simple_house` enables that capability by default while the
Groups A/C fire still uses the aggregate room contract. F3.3v1 may diagnose
that aggregate proposal, but F3.3v2 must own object-level fuel and yield
synchronization before any authority experiment.

## Measured STOP gate

Scenario:

- input: `runs/phase3_f33t/cases/corridor_on.json`;
- Godot: `4.7.1`;
- duration: 180 s;
- base stack: complete F3.3t plus F3.3n receiver routing;
- comparison: proposal flag OFF versus ON.

| Check | Result |
|---|---:|
| Rows OFF / ON | 114 / 114 |
| Columns OFF / ON | 709 / 728 |
| Shared columns | 709 |
| Shared value differences | 0 |
| New proposal columns | exactly 19 |
| Fire-room supported rows | 18 / 18 |
| Non-fire rooms | explicit `NO_FIRE`, accepted HRR 0 |
| Maximum proposal HRR | 300 kW |
| Maximum accepted candidate HRR | 300 kW |
| Remaining proposal fuel | monotonic |
| Accepted HRR above proposal | 0 kW |
| Zero-O2 flame flag | 0 |

The proposal follows the model-derived t-squared curve, reaches its declared
300 kW cap near 80-90 s and remains there through 180 s. This is not a forced
case constant: it is derived from `growth_alpha_kw_s2`, proposal age and
`max_hrr_kw`.

The reproducible gate is:

```powershell
python scripts\simulation\analyze_phase3_f33v1_fire_proposal.py
```

## Verification

- direct Godot 4.7.1 fixture: PASS;
- focused Phase 3 tests: 32/32 PASS;
- proposal/analyzer tests: 16/16 PASS;
- full pytest: 1249 PASS plus the same 17 pre-existing structural failures;
- Physics coherence: 0 FAIL;
- ILV coherence: 0 FAIL;
- gap inventory: synchronized, 347/353 required PASS, 6 VALID_GAP;
- guardrails before commit: only R2-1, expected for dirty motor files;
- no official case, physical report, expected, tolerance, CTRL, VALID_GAP,
  FED, HVAC or visual path changed.

## Remaining boundary

F3.3v1 proves that an unthrottled, conservative fire proposal can coexist
with the current engine without changing it. It does not prove that this
proposal can drive the plume or become authoritative.

F3.3v2 must add pure products from the accepted candidate:

- fuel consumption;
- O2 debit;
- smoke, CO, CO2 and HCN generation;
- convective and radiative heat;
- plume mass, enthalpy and O2 transfer;
- object-level fuel synchronization for the intended authority scope.

All products must share the same accepted fraction and close fuel, carbon,
oxygen, species and energy residuals before the candidate is connected to
F3.3t. OFF invariance and runtime authority remain separate STOP gates.
