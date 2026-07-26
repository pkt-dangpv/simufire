# Phase 3+ F3.3v2 canonical fire-products experiment

Date: 2026-07-26

## Decision

F3.3v2 is **GO as passive, default-OFF product telemetry**.

Runtime authority and retirement of Group C remain **NO-GO**. The products
are not routed into the canonical zone transaction or the F3.3t plume, and
the validation scenario has seven explicit fuel objects whose live fuel
inventories are still synchronized by the legacy path.

## Implemented contract

`CombustionSystem.evaluate_phase3_canonical_fire_products()` is a pure,
dictionary-only evaluator. It consumes the accepted F3.3v1 proposal and a
frozen fuel profile, then emits:

- requested and accepted fuel and O2;
- requested and accepted total, radiative and convective energy;
- requested and accepted smoke, CO, CO2, HCN, HCl, acrolein and
  formaldehyde;
- requested and accepted carbon available, represented and untracked;
- the accepted HRR and convective-HRR drivers for the plume;
- explicit residuals for fuel, O2, energy, carbon and the common species
  fraction.

Every accepted product receives the same F3.3v1 decision fraction. Carbon
products are capped to the carbon available from accepted fuel. HCl is
excluded from the carbon sum because it contains no carbon.

Combustion quality is separate from total acceptance. `quality_phi` is
derived only from O2-inventory and ventilation limits. A fuel-inventory cap
reduces every accepted product but does not falsely turn the final fuel step
into oxygen-starved combustion.

Geometry-dependent plume mass remains owned by `ThermalSystem`. F3.3v2
exports only accepted HRR and `Qc`; it does not duplicate the Heskestad
entrainment equation.

## Runtime surface

The new flag is
`phase3_canonical_fire_products_shadow_enabled`, default `false`. Enabling it
also requires the F3.3v1 proposal and its canonical parent stack.

With the flag OFF, the legacy schema and values are unchanged. With the flag
ON, 46 `phase3_shadow_fire_products_*` columns are appended.

The product profile is captured in persistent canonical fire state. When
explicit fuel objects are present, telemetry sets
`object_sync_required_flag=1` and reports their count. This is a hard
authority blocker, not a silent legacy fallback.

## Measured STOP gate

Scenario:

- input: `runs/phase3_f33t/cases/corridor_on.json`;
- Godot: `4.7.1`;
- duration: 180 s;
- baseline: F3.3v1 proposal stack;
- candidate: the same stack plus F3.3v2 products.

| Check | Result |
|---|---:|
| Rows baseline / products | 114 / 114 |
| Columns baseline / products | 728 / 774 |
| Shared columns | 728 |
| Shared value differences | 0 |
| New product columns | exactly 46 |
| Fire-room supported rows | 18 / 18 |
| Non-fire accepted products | exactly 0 |
| Requested carbon residual | 0 kg |
| Accepted carbon residual | 0 kg |
| Fuel residual | 0 MJ |
| O2 residual | 0 kg |
| Energy residual | 0 kJ |
| Species common-fraction residual | 0 kg |
| Explicit fuel objects | 7 |
| Object synchronization required | yes |

At 180 s, the accepted candidate is 300 kW and its one-second log interval
contains 0.025 MJ fuel, 0.0019 kg O2, 25 kJ energy and a 195 kW convective
plume driver. The products remain passive and do not alter any shared value.

The reproducible gate is:

```powershell
python scripts\simulation\analyze_phase3_f33v2_fire_products.py
```

## Verification

- direct Godot 4.7.1 fixture: PASS;
- focused F3.3v2/F3.3v1/F3.2b1 tests: 42 PASS;
- full pytest: 1271 PASS plus the same 17 pre-existing structural failures;
- Physics coherence: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL;
- ILV coherence: 15 PASS / 14 CTRL / 0 FAIL;
- gap inventory: synchronized, 347/353 required PASS, 6 VALID_GAP;
- validation guardrails: 10/10 PASS;
- documentation link checker: one pre-existing malformed external link under
  `runs/cfast_source_audit`, outside this change;
- no official case, physical report, expected, tolerance, CTRL, VALID_GAP,
  FED, HVAC or visual path changed.

## Remaining boundary

F3.3v2 proves that one accepted proposal can produce a closed product bundle.
It does not prove that the bundle can own the canonical zone update.

The next phase is F3.3v2b: route this bundle into a default-OFF atomic shadow
transaction, including persistent aggregate fuel debit, O2/species/energy
routes and the existing F3.3t plume driver. It must not write `RoomModel` or
fuel objects. Explicit object synchronization remains a separate prerequisite
for any runtime-authority experiment.

Only after F3.3v2b closes may F3.3v3 run 180/300/600 s correspondence. No
official case activation, tolerance change or Group C retirement is
authorized by this result.
