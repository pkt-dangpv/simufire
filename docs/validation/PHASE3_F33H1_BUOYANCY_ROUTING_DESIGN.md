# Phase 3+ F3.3h1 - CFAST buoyancy destination routing

Date: 2026-07-22

## Decision

**Pure design and direct-fixture GO. Runtime wiring and Group C execution
remain NO-GO until F3.3h2.**

F3.3h1 implements the exact CFAST `flogo` receiver destination split behind
an internal/default-false parameter. It does not change source selection,
gross flow, pressure integration, neutral plane, source payload or Poreh
ownership. There is no Engine export, CLI option, CSV field or case override.

## Contract

For each hydrostatic slab:

1. source room and source zone remain selected by pressure direction and slab
   midpoint geometry;
2. source density determines mass flow exactly as before;
3. source-zone temperature becomes the CFAST slab temperature proxy;
4. receiver fractions use the exact CFAST 7.7.5 `tanhsmooth` formula;
5. the direct slab is accumulated as lower and upper routes according to those
   fractions;
6. each route receives the same proportional mass, sensible enthalpy, O2 and
   species payload from the common source snapshot.

The fractions are:

```text
Tlower_eff = min(Tlower_receiver, Tupper_receiver)
f_upper = tanhsmooth(Tsource,
                     Tupper_receiver + 1 K,
                     Tlower_eff - 1 K,
                     1, 0)
f_lower = 1 - f_upper
```

Default geometric routing remains byte-for-byte available when the new final
parameter is omitted or `false`. If buoyancy routing is explicitly enabled,
it takes precedence over the older source-preserving laboratory control.

## Poreh ownership

F3.3g remains separate. With both internal candidates enabled:

- `f33a_interior_network` owns direct temperature-split transport;
- `f33g_doorway_jet_network` owns receiver-internal Poreh transfer.

The fixture verifies that no Poreh route enters the direct bundle and every
mixing-bundle route has the Poreh cause. This matches the CFAST distinction
between published `h_mflow` and ODE-only `uflw3`.

## Code surface

`sim/core/Phase3ZoneMassSystem.gd` adds:

- `CFAST_DESTINATION_DELTA_TEMP_K = 1.0`;
- `_cfast_tanhsmooth()`;
- `preview_cfast_buoyancy_destination_split()`;
- optional/default-false propagation through F3.3a, F3.3b and the internal
  opening network queue;
- split-route accumulation in the common route accumulator.

Tests:

- `tests/fixtures/phase3_f33h1_buoyancy_routing.gd`;
- `tests/test_phase3_f33h1_buoyancy_routing.py`.

## Fixture coverage

The isolated Godot fixture proves:

1. exact lower, midpoint and upper `tanhsmooth` values;
2. the CFAST `min(Tlower,Tupper)` behavior for inverted legacy temperatures;
3. geometric source removal remains unchanged;
4. a geometrically upper receiver slab can split 50/50 by temperature;
5. split route mass equals original slab mass;
6. opening and signed-pressure total flow/neutral plane remain invariant;
7. direct and Poreh bundles remain separate;
8. building mass, energy, O2 and seven-species totals remain exact;
9. reversed opening order yields the same state.

## Verification

| Check | Result |
|---|---|
| Focused F3.3f1/g/g1/h1 pytest | 31 PASS |
| All `test_phase3*.py` | 455 PASS |
| F3.3h1 Godot 4.7.1 fixture | PASS |
| F3.3f1 regression fixture | PASS |
| F3.3g regression fixture | PASS |
| Default internal parameter | `false` |
| Engine/CLI/CSV/case surface | none |
| Official reports/baselines/tolerances/gaps | unchanged |

The certificate-store warning printed after fixture PASS belongs to the
isolated Windows `APPDATA` profile and does not affect simulation or exit code.

## F3.3h2 STOP

F3.3h2 may temporarily expose the candidate behind a default-OFF gate only
with both residence ledgers and the full F3.3b stack. It must:

1. prove OFF byte identity to the F3.3d1 checkpoint;
2. run Group C only to 180 s;
3. compare direct accepted lower/upper inflow to CFAST `h_mflow` targets;
4. report Poreh accepted mass separately;
5. compare upper/lower mass, temperatures and interface to CFAST;
6. verify exact mass, enthalpy, O2 and species residuals;
7. remove runtime wiring after either GO or NO-GO until a separate authority
   decision.

Stop without 300/590 s if upper/lower direct split moves away from CFAST,
total direct flow changes materially, upper mass/interface regress, any
residual is nonzero, legacy columns differ, or the implementation requires a
coefficient not present in CFAST.

