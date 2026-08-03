# Phase 3 H3.2-M Coupled Bundle Shadow

Date: 2026-08-03
Decision: **GO for the mechanical shadow bundle only**
Authority: none

## Scope

H3.2-M converts the coupled pressure solver's H3.2a zonal output into the
existing atomic route representation and evaluates one global donor-limited
fraction. It never registers the bundle in the legacy atomic registry, never
applies a route, never writes a room and never suppresses a legacy writer.

The opt-in flag is
`phase3_coupled_interior_bundle_shadow_enabled`, default `false`. It requires
the coupled pressure solver stack. With the flag OFF, the legacy CSV schema is
unchanged.

## Source-provenance blocker

The solver input sources remain circular:

```text
source = (post_state - pre_state) - legacy_interior_transport
```

Therefore coupled-vs-legacy agreement is not independent evidence. H3.2-M
exports this limitation rather than zero-filling a comparison:

- `source_inputs_independent = false`
- `source_provenance = post_minus_pre_minus_legacy_interior`
- `comparison_valid = false`
- `comparison_invalid_reason = circular_legacy_source_reconstruction`

No coupled-vs-legacy delta is emitted. H3.2-S must provide explicit
non-transport owner sources before that comparison or any runtime authority is
valid.

## Reused primitives

- `make_atomic_route`
- `_tag_connection_route`
- `make_atomic_bundle`
- `_evaluate_atomic_bundle_acceptance`
- `_scaled_atomic_routes`

The donor acceptance was extracted from `_apply_atomic_bundle` as a pure
function of `(shadow, routes)`. The legacy caller still uses the same moved
body and keeps all legacy counters and application order. A real GDScript
fixture caught an omitted `source_demands` return that text-only tests missed;
the evaluator now returns a defensive copy and both paths compile.

H3.2-M owns separate `_coupled_*` records and IDs. It never calls
`add_atomic_bundle`, `_apply_atomic_bundle` or `_apply_atomic_route`, and never
increments an `_atomic_*` counter.

## Mechanical contract

1. H3.2a zonal routes become stable atomic routes.
2. Counterflow remains two opposite routes under one `connection_id`.
3. One donor fraction scales mass and sensible enthalpy exactly once.
4. O2 and species are zero/deferred; H3.4 owns their future advection.
5. `inventory_limited_*` and shadow `accepted_*` are separately named but
   equal in H3.2-M because there is no application stage.
6. Delayed parcels are read only to count overlap; the reservoir is untouched.
7. Non-convergence and invalid zoning produce explicit fallback records; no
   copied legacy bundle is presented as coupled output.
8. Exact-zero zonal buckets are not transport requests. They are skipped with
   an exact comparison and counted by `zero_route_skipped_count`; no epsilon or
   case knob was introduced.

## Runtime matrix

Ten committed topologies were run sequentially with Godot 4.7.1 for 10 s and
compared with the matching initial horizon of the H3.2a artifacts.

| Case | Rows | Shared columns | New columns | Routes | Zero buckets |
|---|---:|---:|---:|---:|---:|
| cfast_corridor_chain | 12 | 672 | 57 | 261 | 0 |
| cfast_r0_window_360 | 12 | 672 | 57 | 656 | 1 |
| cfast_two_floor_stairwell | 26 | 672 | 57 | 1297 | 0 |
| compact_apartment_smoke | 55 | 672 | 57 | 447 | 0 |
| flashover_simple_house | 66 | 672 | 57 | 718 | 0 |
| ghanekar_bedroom_hallway | 20 | 672 | 57 | 1065 | 0 |
| piso_mediterraneo_smoke | 110 | 672 | 57 | 1004 | 0 |
| three_bed_apartment_smoke | 99 | 672 | 57 | 835 | 0 |
| two_storey_smoke | 143 | 672 | 57 | 1291 | 0 |
| uk_bungalow_smoke | 77 | 672 | 57 | 727 | 0 |

All shared values are byte-identical. All 57 new columns use the
`phase3_shadow_coupled_bundle_` prefix. Across 1,200 physical steps:

- valid steps: 1,200/1,200;
- solver fallbacks: 0;
- invalid zonal steps: 0;
- duplicate bundles/routes: 0;
- double limits: 0;
- counterflow violations: 0;
- maximum mass and energy conservation residuals across every step: at most
  `1e-12`;
- requested mass equals inventory-limited mass in this 10 s corpus.

The one exact-zero zonal bucket in `cfast_r0_window_360` is observed and
skipped; it no longer invalidates that step.

## Evidence limits

- No runtime case needed donor limiting during the 10 s horizon. The global
  `0.5` donor fraction and shared mass/enthalpy scaling are exercised by a
  direct Godot fixture.
- No runtime case had a matching delayed parcel in flight during this horizon.
  Read-only overlap accounting is exercised by a fixture with a non-zero
  parcel.
- A 120 s matrix was attempted but the first case did not complete within the
  operational timeout and left child processes requiring cleanup. It is not
  counted as evidence. This is a coverage/performance limitation, not a
  physics result.
- The comparison remains circular by construction. Zero differences in legacy
  columns prove isolation, not physical superiority.

## Verification

- direct Godot fixtures: 15/15 PASS across H1-H2.10, H3.2a and H3.2-M;
- focused H3.2a/H3.2-M and retargeted atomic tests: 116/116 PASS;
- `pytest tests -k "phase3 or guardrail"`: 1298 PASS / 2 known FAIL
  (`test_exit0_real_json` from dirty-motor R2-1 and the historical
  `test_csv_exports_three_canonical_layers`);
- ten-topology matrix analyzer: PASS;
- physics: 9 PASS / 15 CTRL / 5 WARN / 0 FAIL;
- ILV: 15 PASS / 14 CTRL / 0 FAIL;
- gap inventory unchanged: 353 required, 6 VALID_GAP, 71 non-gating;
- guardrails: 9/10, only R2-1 as expected from dirty motor;
- Godot logs: no error signatures; residual Godot processes: 0.

## Decision and next phases

**GO for H3.2-M mechanics only.** This does not close H3.2 and grants no
authority.

- **H3.2-S remains required:** independent non-transport owner sources.
- **H3.2b remains a hard prerequisite:** residual projection must stop
  rebuilding committed energy while preserving the thermal cap as a reported
  sink.
- **H3.3 remains blocked** until H3.2-S and H3.2b pass their own STOP gates.
