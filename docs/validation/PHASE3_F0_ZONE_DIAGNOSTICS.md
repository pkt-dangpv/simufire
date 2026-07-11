# Phase 3+ F0 — Two-zone conservation diagnostics

Date: 2026-07-11

## Scope

F0 adds passive, opt-in telemetry for the existing two-zone state. It does not
change mass, energy, species, O2, FED, opening flows, tolerances, or reference
baselines.

Enable it in a validation case with:

```json
"phase3_zone_diagnostics_enabled": true
```

or for an isolated technical run:

```powershell
python scripts/run_scenario.py <case.json> --phase3-zone-diagnostics
```

The default is `false`. With the flag disabled the legacy CSV schema is
unchanged. With the flag enabled, `SimulationLogWriter` appends diagnostic
columns after `hvac_exists`.

## Existing telemetry reused

- Canonical state: `upper_gas_kg`, `lower_gas_kg`, `upper_energy_kj`,
  `lower_energy_kj`.
- Numerical boundary ledger: `two_zone_boundary_mass_kg` and
  `two_zone_boundary_energy_kj`.
- Opening ledgers: upper/lower in/out cumulative masses.
- Thermal interface and upper/lower temperatures.

These values already reached `SimulationStateBuilder`, but were not present as
a time series in the main CSV.

## F0 additions

- EOS-implied upper/lower volumes and room volume-closure error.
- Per-physics-step deltas for boundary corrections and opening ledgers.
- Exact plume lower-to-upper entrainment counter.
- Passive mass/energy attribution around these engine stages:
  oxygen exchange, combustion, thermal, suppression, gas exchange, HVAC,
  other post-HVAC work, reconcile, and final projection/clamp.
- Attribution residual: observed room delta minus the sum of all captured stage
  deltas. It verifies telemetry coverage, not physical conservation.

The `_step` suffix means one fixed physics step, not one CSV logging interval.

## Initial findings

### Group C — `cfast_corridor_chain`, room 0

At 180 s the upper zone occupies about 19.6% of room volume and has 7.05 kg of
gas. The cumulative numerical boundary ledger is already +134.38 kg. At 600 s
the upper zone reaches 31.5%, while cumulative boundary mass reaches +449.93 kg.

The room volume closes to floating-point precision only because
`project_room_state()` repeatedly reconstructs lower-zone mass at reference
pressure. The large cumulative boundary term is therefore the key F1 target;
zero volume-closure error alone is not evidence of conservation.

### Group A — `cfast_r0_window_360`, room 0

The pre-opening symptom is not the same thin upper layer as Group C. At 240 s
the upper zone occupies about 53.9% of room volume; at 350 s it occupies 65.7%.
This creates a large upper O2 reservoir and is consistent with O2 depletion
being slower than CFAST. After the window opens, the upper volume collapses to
22.5% by 400 s while HRR jumps to about 1280 kW and upper O2 approaches zero.

Group A and C share the non-conservative projection/reconcile architecture, but
must not be treated as one calibration knob.

## No-op evidence

A 120 s OFF/ON paired run of `cfast_corridor_chain` produced:

- 78 rows in each CSV.
- 115 legacy columns OFF and the same 115 plus 36 diagnostics ON.
- Zero value differences across every shared column.
- Attribution mass residual equal to zero in every sampled row.

Short diagnostic runs of `fuel_balance_diag_sealed`,
`o2_stoich_diag_sealed`, and `cfast_two_room_door_open` also produced zero
attribution mass residual. The doorway case populated upper/lower opening
telemetry; the sealed controls remained at zero opening flow.

## F0.5 shadow-ledger plan (not implemented)

F0.5 must calculate a canonical expected balance from physical requests, not
re-sum observed mutations. Its minimum implementation is:

1. Add a `ZoneFluxLedger` value object owned by `ZoneFireSolver`.
2. Snapshot immutable zone state at the beginning of each physics step.
3. Record source/flux requests without applying them:
   - combustion heat, O2 sink, and species sources;
   - plume lower-to-upper mass plus carried enthalpy/species;
   - opening air mass, enthalpy, and species with antisymmetric endpoints;
   - exterior, HVAC, suppression, and wall terms;
   - explicit numerical caps as separate non-physical terms.
4. Compute expected upper/lower mass, energy, and species from the snapshot plus
   ledger exactly once.
5. Compare expected state with the legacy end-of-step state and export shadow
   residuals. Do not apply the expected state.
6. Require every delayed parcel to expose air mass, enthalpy, species, source,
   destination, and in-flight ownership before it can participate.

F0.5 STOP criteria:

- Every source term has one owner and one sign convention.
- Interior opening requests are antisymmetric to floating-point precision.
- No residual is computed from already-mutated state.
- Shadow mode remains default OFF and produces zero shared-column deltas.
- Group A and C residuals identify the responsible source/flux class before F1.

Until these contracts exist, a shadow residual would be circular and should not
be presented as a conservation check.
