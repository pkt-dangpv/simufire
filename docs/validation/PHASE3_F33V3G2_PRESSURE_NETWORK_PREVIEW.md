# Phase 3+ F3.3v3g2 passive interior pressure-network preview

Date: 2026-07-26

## Decision

F3.3v3g2 is **GO as a passive default-OFF preview** and **NO-GO for runtime
authority and for persistent shadow state**.

The new
`phase3_canonical_fixed_gross_pressure_network_shadow_enabled` flag is default
OFF and effective only under the complete F3.3v3f1 fixed-gross stack. When
active it:

1. partitions the horizontal interior openings into connected components with
   an opening-order-independent identity;
2. rebuilds the full fixed-gross candidate from the **raw** pressure demand;
3. calls the pure F3.3v3g1 relaxation once per component;
4. bounds the accepted factor by the source-zone inventory of gas, sensible
   enthalpy, O2 and every species;
5. interpolates `route(alpha) = base + alpha * (full_fixed - base)` with one
   common factor per component;
6. emits telemetry.

It never appends a route to `network_routes`, never creates a bundle or
transaction, and never writes canonical, persistent or legacy state.

## Wiring

The preview runs inside `queue_canonical_interior_opening_requests`, after the
F3.3v3f1 preview and before the authoritative pressure routes are appended:

```text
build interior_opening routes  ->  network_routes            (base)
build signed pressure routes   ->  pressure_routes_raw       (raw demand)
    |
    +-- legacy additive relaxation -> pressure_routes (relaxed, authoritative)
    +-- F3.3v3f1 preview            (uses the relaxed routes)
    +-- F3.3v3g2 preview            (uses pressure_routes_raw)
    |
    +-- append pressure_routes to the atomic bundle
```

Using the raw demand is mandatory: the legacy relaxation was computed for the
additive route response, so applying it before the fixed-gross recomposition
would constrain the same candidate twice. This is the exact numerical mismatch
that made F3.3v3f3 diverge.

Base routes are strictly the `canonical_interior_opening` family. The full
candidate is `preview_fixed_gross_interior_pressure_skew(network_routes,
pressure_routes_raw)`, and its pressure response is measured with the same
`_canonical_route_pressure_delta_by_room` used by the legacy path.

## Component identity

Connected components are built by union-find over canonicalized `(min, max)`
room pairs, sorted by `"%010d|%010d"`. The component identity is the sorted
list of its rooms (`"0|1|2"`), and components are ordered by their minimum room
id. Neither the identity, the index nor the accepted factor depends on the
order in which openings were declared or iterated.

## Inventory bound

For every source room/zone and every payload quantity `q`:

```text
out(alpha) = out_base + alpha * (out_full - out_base)

if out_full - out_base > 0:
    alpha_limit = (inventory - out_base) / (out_full - out_base)
```

The accepted inventory factor is the minimum over gas, sensible enthalpy, O2
and each of the seven species. The bound fails closed with `alpha = 0` and an
explicit invalid flag when an inventory is negative or non-finite, or when the
base routes alone already exceed the pre-step snapshot. It never corrects,
clamps or mutates an inventory, and it uses no empirical floor.

## Files changed

| File | Change |
|---|---|
| `sim/core/Phase3ZoneMassSystem.gd` | components, inventory bound, component preview, telemetry ledgers, 58 result fields |
| `sim/core/SimulationEngine.gd` | exported flag, `_phase3_canonical_fixed_gross_pressure_network_active()`, queue argument, log-writer and state wiring |
| `sim/core/SimulationLogWriter.gd` | opt-in `_phase3_pressure_network_fields()` header and row |
| `sim/core/SimulationStateBuilder.gd` | flag exported into the summary state |
| `scripts/run_scenario.py` | `--phase3-canonical-fixed-gross-pressure-network-shadow` plus its parent stack |
| `tools/run_scenario_headless.gd` | CLI argument and engine propagation |
| `scripts/simulation/analyze_phase3_f33v3g2_pressure_network_preview.py` | new STOP-gate analyzer |
| `tests/fixtures/phase3_f33v3g2_pressure_network_preview.gd` | new Godot 4.7.1 runtime fixture |
| `tests/test_phase3_f33v3g2_pressure_network_preview.py` | new structural contracts |
| `tests/test_analyze_phase3_f33v3g2_pressure_network_preview.py` | new analyzer contracts |
| `tests/test_phase3_f33v3f0_fixed_gross_preview.py` | the f0 preview now has two passive callers, both before the apply site |
| `tests/test_phase3_f33v3g1_pressure_network_relaxation.py` | the g1 primitive now has exactly one passive call site |

No physics, FED, HVAC, visual, official case, report, expected value,
tolerance, CTRL envelope or VALID_GAP classification changed.

## STOP gate at 180 s

Scenario `runs/phase3_f33t/cases/corridor_on.json`, Godot `4.7.1`, complete
F3.3v stack with unfiltered growth, fire-products routing, object
synchronization and CFAST buoyancy destination. OFF and ON differ only by the
new flag.

| Check | Result |
|---|---:|
| OFF / ON rows | 114 / 114 |
| Shared CSV columns | 838 |
| Shared value differences | 0 |
| New columns | 58 |
| New columns outside the `pressure_network` family | 0 |
| Columns present OFF and missing ON | 0 |

Every live column, every FED input and every F3.3v3f1 shadow column is
byte-identical. No official report changed.

### Contract over every physical step

The step ledgers are sampled 54 times in the CSV, but the cumulative counters
cover all `2160` physical steps of the run.

| Check | Tolerance | Measured |
|---|---:|---:|
| Objective increase | `<= 1e-9 Pa2` | `0.0` |
| Mass residual | `<= 1e-9 kg` | `0.0` |
| Gross mass residual | `<= 1e-9 kg` | `0.0` |
| Energy residual | `<= 1e-7 kJ` | `0.0` |
| O2 residual | `<= 1e-9 kg` | `0.0` |
| Species residual | `<= 1e-9 kg` | `0.0` |
| Negative payload count | `0` | `0` |
| Predicted zone collapse count | `0` | `0` |
| Minimum predicted lower gas | `> 0` | `2.882 kg` |

Two of the 2160 steps fail closed with `alpha = 0` inside the 0-10 s ignition
transient and never again afterwards. In those steps the accepted routes are
exactly the base opening routes, so the preview is a no-op by construction.

The minimum predicted **upper** gas reaches `0.000 kg`, but the collapse
counter is `0`. That value comes from `4` degenerate zone samples in which the
receiving room's upper zone was already empty **before** the step; the preview
neither debits nor credits it. A collapse is counted only when an occupied
zone (`pre > 1e-12 kg`) would be driven to or below zero, and that never
happens.

### Bounds and limiting reason at the logged samples

| Bound | Minimum | Maximum |
|---|---:|---:|
| `alpha_optimal` | `0.00257373` | `1.00000000` |
| `alpha_crossing` | `0.00080632` | `0.82102192` |
| `alpha_inventory` | `1.00000000` | `1.00000000` |
| `alpha_accepted` | `0.00080632` | `0.82102192` |

| Limiting reason | Samples |
|---|---:|
| `crossing` | 36 |
| `optimal` | 18 |
| `inventory` | 0 |

Over all 2160 steps: `2008` crossing-limited, `277` non-descent (dormant),
`0` inventory-limited, `2` invalid.

The pressure-sign crossing bound, not the inventory, is the active limiter in
this scenario. The requested fixed-gross transport is large enough to reverse a
connected room pressure difference within one timestep, so the network solve
accepts only the fraction that reaches equilibrium without crossing.

### Component table at 180 s

One connected component covering rooms 0, 1 and 2 through two connections.
Rooms 3-5 have no horizontal interior opening and are correctly absent.

| Field | Value |
|---|---:|
| Component id / index | `0\|1\|2` / `0` |
| Rooms / connections | 3 / 2 |
| `alpha_optimal` | `0.25435912` |
| `alpha_crossing` | `0.00766055` |
| `alpha_inventory` | `1.00000000` |
| `alpha_accepted` | `0.00766055` |
| Limiting reason | `crossing` |
| `objective_pre_pa2` | `156196.800` |
| `objective_post_pa2` | `151019.690` |
| Directional derivative | `-686147.100 Pa2` |
| Worsening connections | 0 |

Per-room step values at 180 s:

| Room | base out/in kg | full out/in kg | accepted out/in kg | requested net kg | accepted net kg |
|---|---:|---:|---:|---:|---:|
| 0 | 0.042258 / 0.042258 | 0.084515 / 0.000000 | 0.042581 / 0.041934 | `+0.084515` | `+0.000647` |
| 1 | 0.076234 / 0.076234 | 0.000000 / 0.152468 | 0.075650 / 0.076818 | `-0.152468` | `-0.001168` |
| 2 | 0.033976 / 0.033976 | 0.067953 / 0.000000 | 0.034237 / 0.033716 | `+0.067953` | `+0.000521` |

Gross mass per room is preserved exactly: `out + in` is identical for the base
and accepted route sets in all three rooms.

Cumulative accepted net by sign at 180 s:

| Room | positive kg | negative abs kg |
|---|---:|---:|
| 0 | 3.432 | 3.235 |
| 1 | 3.514 | 2.123 |
| 2 | 1.090 | 2.679 |

The accepted net is bidirectional, not a one-way accumulation. This is the
opposite of the F3.3v3f3 signature, where all 1676 cap events had the same
sign.

### CFAST correspondence, R0 doorway at 180 s

| Metric | Preview | CFAST | Error |
|---|---:|---:|---:|
| Outbound mass | 72.036 kg | 76.732 kg | -6.12% |
| Inbound mass | 71.839 kg | 69.442 kg | +3.45% |
| Gross mass | 143.875 kg | 146.174 kg | **-1.57%** |
| Net outbound enthalpy | 6242.103 kJ | 6301.709 kJ | **-0.95%** |
| Net outbound mass | 0.198 kg | 7.290 kg | -97.29% |

Gross mass and net enthalpy stay well inside the mandatory 5% envelope. Net
mass is expected to remain far from CFAST at this phase: the preview cannot
mutate the persistent shadow, so the accepted transport does not evolve the
next-step pressure and the crossing bound stays tight. Closing net mass is the
declared objective of F3.3v3g3, not of this phase.

## Verification

| Suite | Result |
|---|---|
| Godot 4.7.1 g2 runtime fixture | `PHASE3_F33V3G2_PRESSURE_NETWORK_PREVIEW_PASS` |
| Godot 4.7.1 g1 runtime fixture | `PHASE3_F33V3G1_PRESSURE_NETWORK_RELAXATION_PASS` |
| Focused g2/g1/f1/f0/f33a/f33b chain | 68/68 PASS |
| `python -m pytest tests -k phase3` | 741 PASS |
| `python -m pytest tests` | 1360 PASS / 18 FAIL |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 353 required + 6 VALID_GAP + 71 non-gating, synchronized |
| Guardrails | 9/10, only R2-1 |

The 18 full-suite failures were reproduced at `HEAD` (`0c7fa7d6`) in a clean
worktree, which also fails 18. Seventeen are the identical established
repository baseline; the eighteenth here is the expected R2-1 freshness gate
while `sim/core` is dirty. There is no new regression.

Do not run a bare `pytest` from the repository root: it tries to collect
access-restricted historical temporary directories under `runs/`.

## Interpretation

Three facts are now measured rather than assumed:

1. the network solve descends the interior pressure objective at every active
   step and never worsens a connection;
2. the binding limiter in this scenario is the pressure-sign crossing bound,
   not inventory - so extra source inventory would not by itself increase the
   accepted transport;
3. one common blend factor per component keeps gross mass, mass, energy, O2 and
   species exactly closed while producing bidirectional net flow.

The `alpha_crossing` values are small (`0.0008` to `0.821`, `0.0077` at 180 s).
That is the expected consequence of a static preview: the pressure trajectory
it is evaluated against is produced by the unchanged additive routes, so a
large fixed-gross step would reverse a connection sign within one timestep.
Only a persistent shadow can let the accepted transport move the pressure it is
bounded by.

## Next gate

F3.3v3g3 may let the accepted blended routes update the **private canonical
shadow state only**. Legacy state, FED and official artifacts remain untouched.
It must be staged at 30, 60, 120 and 180 s and must stop immediately if:

- the pressure request or cap count grows monotonically for ten intervals;
- all material cap events keep one sign after a pressure sign change;
- either zone inventory reaches numerical zero unexpectedly;
- the objective increases;
- any conservation residual exceeds its invariant;
- gross or net enthalpy error exceeds 5% at 180 s.

Target at 180 s: net mass correspondence improves from the F3.3v3f1 `-55.49%`
error to within 25%, with lower shadow gas positive and EOS-valid.

Do not promote this preview to authority merely because its objective descends
and its residuals are zero.

## Reproduction

```powershell
python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33v3g2\180_off `
  --duration 180 --timeout 1800 `
  --phase3-canonical-unfiltered-fire-growth-shadow `
  --phase3-canonical-fire-products-routing-shadow `
  --phase3-canonical-fuel-object-sync-shadow `
  --phase3-cfast-buoyancy-destination-shadow `
  --phase3-canonical-fixed-gross-pressure-skew-shadow

python scripts\run_scenario.py `
  runs\phase3_f33t\cases\corridor_on.json `
  --out-dir runs\phase3_f33v3g2\180_on `
  --duration 180 --timeout 1800 `
  --phase3-canonical-unfiltered-fire-growth-shadow `
  --phase3-canonical-fire-products-routing-shadow `
  --phase3-canonical-fuel-object-sync-shadow `
  --phase3-cfast-buoyancy-destination-shadow `
  --phase3-canonical-fixed-gross-pressure-network-shadow

python scripts\simulation\analyze_phase3_f33v3g2_pressure_network_preview.py `
  --json-out runs\phase3_f33v3g2\stop_gate.json
```

The OFF run keeps the F3.3v3f1 flag so that the two runs differ by exactly one
flag. The analyzer exits non-zero unless isolation, descent, closure,
non-collapse and the 5% CFAST envelopes all hold.
