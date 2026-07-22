# Phase 3+ F3.3f1 - Source-preserving destination routing

Date: 2026-07-22

## Decision

**Design and direct-fixture GO. Runtime wiring, Group C execution, canonical
authority and gap retirement remain NO-GO.**

F3.3f2 subsequently wired this selector temporarily and rejected the runtime
candidate at its 180 s STOP. The wiring was fully removed, so the repository
again has no Engine, CLI, CSV or case surface for this selector. See
`PHASE3_F33F2_DESTINATION_ROUTING_EXPERIMENT.md`.

F3.3h later rejected the physical interpretation of this selector. Exact
CFAST 7.7.5 source shows that direct receiver deposition uses a smooth
slab-temperature versus receiver-layer temperature split; it does not preserve
the source zone. Keep this implementation only as an internal tested control.
It must not be re-exposed at runtime. See
`PHASE3_F33H_CFAST_DOORWAY_FLOW_SEMANTICS.md`.

F3.3f1 adds one optional pure routing contract to the common F3.3a/F3.3b
horizontal-opening integrator. The option is default `false`, is not exported
by `SimulationEngine`, has no CLI or CSV surface and cannot be enabled by a
validation case. Existing calls therefore retain the exact geometric
destination rule.

The fixture proves that source-preserving routing corrects the selected
semantic defect without changing pressure integration, mass-flow magnitude or
any transported payload. F3.3f2 may now wire the option behind a default-OFF
runtime flag for a separate Group C experiment.

## Physical basis

The binding primary reference is NIST SP 1026r1, CFAST Software Development
and Model Evaluation Guide, section 3.3 and figures 3.6-3.7:

- the vent is divided at layer interfaces, neutral planes and vent bounds;
- slab flow uses density from the source compartment;
- the direct circulation is represented by upper-layer hot outflow and
  lower-layer cool return;
- mixing induced by a hot doorway jet is calculated as a separate entrainment
  term analogous to a plume.

Official source and guide:

- `https://github.com/firemodels/cfast/blob/master/Source/CFAST/flowhorizontal.f90`
- `https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.1026r1.pdf`

This distinction matters. Direct vent transport should retain the source
stream's layer identity. Door-jet mixing must not be approximated by depositing
that direct stream according only to the receiver interface height.

## Candidate contract

The existing source selection remains geometric and physically local:

```text
source_zone = zone_at_height(source, slab_midpoint)
```

The optional destination becomes:

```text
candidate ON:  destination_zone = source_zone
candidate OFF: destination_zone = zone_at_height(destination, slab_midpoint)
```

Consequences when ON:

- a cool lower-source stream renews the receiver lower reservoir even if the
  receiver interface has fallen below the slab midpoint;
- a hot upper-source stream enters the receiver upper reservoir even if the
  receiver interface is above the slab midpoint;
- an empty destination zone can be created by a real incoming atomic route;
- F3.3a gross exchange and F3.3b signed-pressure routes use one shared rule;
- mass, sensible enthalpy, O2 and seven species retain the source-zone
  concentration and one common accepted fraction.

The candidate deliberately does not add CFAST's separate doorway-jet
entrainment owner. That is a later question only if direct routing alone leaves
a measured mixing deficit.

## Code surface

Only `sim/core/Phase3ZoneMassSystem.gd` changes:

- `_canonical_interior_destination_zone()` contains the pure selector;
- `preview_canonical_interior_opening()` accepts an optional default-false
  candidate argument;
- `preview_canonical_interior_pressure_flow()` accepts the same argument;
- `_integrate_canonical_interior_opening()` and
  `_canonical_interior_interval_flow()` propagate it;
- `queue_canonical_interior_opening_requests()` can pass it to both route
  families, also default false.

No flow coefficient, pressure equation, neutral-plane solve, source density,
atomic cap, energy/O2/species formula or legacy state write changes. There is
no Engine export, runner argument, report field, case override or authority
path in F3.3f1.

## Direct fixture

`tests/fixtures/phase3_f33f1_destination_routing.gd` covers:

1. lower source crossing above a depressed receiver interface:
   geometric `lower->upper`, candidate `lower->lower`;
2. upper source crossing below a high receiver interface:
   geometric `upper->lower`, candidate `upper->upper`;
3. exact OFF equivalence for implicit versus explicit `false` previews;
4. invariant gross A->B/B->A flow, net flow, exchange and neutral plane;
5. the same contract in signed-pressure routes;
6. conservative creation of an initially empty upper destination zone;
7. exact mass, enthalpy, O2 and species residuals;
8. identical three-room results with reversed opening order.

The first fixture invocation returned exit 1 because the assertion attempted
to read `source_zone` as a top-level interval field. The interval API stores
the complete route in `route_key`; its route was already correct. The fixture
was corrected to assert the actual API, then rerun in a fresh isolated Godot
profile.

## Verification

| Check | Result |
|---|---|
| Focused F3.3a/F3.3b/F3.3f1 pytest | 28 PASS |
| All `test_phase3*.py` | 432 PASS |
| Godot 4.7.1 isolated fixture | PASS |
| Default OFF preview equivalence | exact |
| Gross flow and neutral plane OFF/ON | exact in fixture |
| Atomic mass/energy/O2/species residuals | zero |
| Reversed opening order | identical |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 PASS; 5 VALID_GAP; 71 non-gating |
| Guardrails | 9/10; only expected R2-1 for dirty motor |
| Engine/CLI/CSV runtime wiring | none |
| Official cases/reports/baselines/tolerances/gaps | unchanged |

Godot prints the known nonbinding Windows root-certificate warning after the
PASS marker. It exits 0 and no process remains running.

## F3.3f2 outcome

F3.3f2 added a temporary default-OFF Engine/CLI/CSV gate without F3.3e1 Qc.
OFF was byte-identical. ON improved lower inflow but collapsed upper inflow to
nearly zero and moved upper mass/interface away from CFAST, so the experiment
stopped at 180 s and the wiring was removed.

The executed sequence was:

1. prove full scenario OFF invariance against the current F3.3d1 checkpoint;
2. run candidate ON to 180 s and compare total inflow plus upper/lower split;
3. stop because upper hot transport was lost;
4. preserve exact F3.3c1/F3.3d1 enthalpy and mass residuals;
5. roll back runtime wiring before any 300/590 s or coupled-Qc run.

The binding CFAST targets remain:

| Window | Lower doorway in | Upper doorway in |
|---|---:|---:|
| 0-180 s | 65.782 kg | 3.662 kg |
| 180-300 s | 66.520 kg | 1.825 kg |
| 300-590 s | 166.815 kg | 1.578 kg |

Rollback if the candidate changes flow magnitude at identical state, routes a
hot upper stream into lower, introduces a nonzero conserved residual, depends
on an empirical threshold, alters shared output while OFF, or requires a case
coefficient change.

## STOP gate

| Decision | Status |
|---|---|
| Direct transport source identity | GO |
| Separate door-jet entrainment owner | deferred |
| Runtime flag and Group C experiment | NO-GO; rolled back at 180 s |
| Reintroduce F3.3e1 coupled Qc | NO-GO before F3.3g |
| Canonical authority / retire Group C | NO-GO |
