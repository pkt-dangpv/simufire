# Phase 3 H3.2-S0a Physical Owner Event Contract

Date: 2026-08-03
Decision: **GO at STOP gate for the isolated contract only**

## Scope

H3.2-S0a adds `Phase3PhysicalOwnerLedger.gd`, a pure `RefCounted` library.
It has no production call site, flag, persistent step state or dependency on
engine, building or room classes. It receives dictionaries and returns new
dictionaries. H3.2-S0b/S0c will decide how mutation sites emit these events.

No runtime physics, CSV schema, validation report, expected value or tolerance
changes in this phase.

## Event schema

Each event has stable owner and event IDs, room/source/destination identity,
source/destination zones, explicit upper/lower mass and energy deltas, optional
counterparty totals and copied metadata.

| Classification | Meaning | Contributes to physical source? | Conservation contract |
|---|---|---:|---|
| `local_source` | Signed local source/sink | yes | no transport identity |
| `exterior_boundary` | Signed room/exterior flow | yes | direction and signs agree |
| `interior_transport` | Flow between different rooms | no | source plus counterparty is zero |
| `interzone_redistribution` | Upper/lower movement in one room | no | upper plus lower is zero |
| `delayed_parcel` | Created/delivered/cancelled/inflight lifecycle | no | parcel ID and lifecycle required |
| `numerical_correction` | Projection/reconcile/clamp bookkeeping | no | never promoted to physical source |

The one global numerical comparison constant is
`CONSERVATION_EPSILON = 1e-12`. It is not configurable and is never read from
options or case files.

## Fail-closed behavior

- Missing fields, unknown classifications, invalid room/zone identity,
  non-finite values and conservation/sign violations are invalid.
- Duplicate IDs are detected before validation or aggregation. Every event
  carrying a duplicated ID is excluded; duplicates and invalid events remain
  visible in counters and error records.
- `physical_source_for_room()` returns zero if any input event is invalid. It
  never exposes a partial source vector.
- Only local and exterior events feed physical sources. Transport, interzone,
  parcels and numerical corrections are structurally excluded.
- Aggregation sorts owned deep copies by event ID and never mutates caller data.

## Fixture coverage

The Godot fixture covers:

- local source and signed exterior inflow/outflow;
- upper-to-lower and lower-to-upper redistribution;
- upper-to-lower transport across rooms and bidirectional counterflow;
- parcel creation/delivery and numerical correction exclusion;
- duplicate ID, unknown classification, NaN, invalid zone, non-conservative
  transport/interzone and direction-sign mismatch;
- deterministic aggregation under reversed input order;
- input immutability and multi-owner aggregation.

A runtime negative control inverted one fixture assertion. Godot exited 1,
printed the assertion error and emitted no PASS marker. The source was restored
and the positive fixture passed again.

## Isolation proof

Structural tests scan every other GDScript file and require zero production
references to `Phase3PhysicalOwnerLedger`. The only GDScript reference is the
dedicated fixture. There is no flag, runner argument, engine wiring or CSV
field.

## Open risks and next phase

- This phase validates event semantics, not mutation-site coverage.
- Surface storage needs both room and surface-side ownership in S0b.
- Existing doorway, parcel and projection observations must be adapted, never
  emitted a second time.
- Generic upper-layer removal callbacks still need owner provenance in S0c.
- HVAC remains deferred under the current motor plan.

H3.2-S0b may instrument thermal owners only after this STOP gate is approved.
H3.2-S, H3.2b and H3.3 remain unstarted/blocked.

## STOP verification

| Check | Result |
|---|---|
| S0a Godot fixture | PASS |
| Runtime negative control | exit 1, no PASS marker |
| S0a structural contracts | 19/19 PASS |
| Global fixture fail-closed contracts | 189/189 PASS |
| H1/H2.10/H3.2a/H3.2-M regression fixtures | 5/5 PASS |
| `pytest -k "phase3 or guardrail"` | 1322 PASS / 2 known failures |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 353 required / 6 VALID_GAP / 71 non-gating |
| Guardrails | 9/10; only expected R2-1 for new dirty `sim/core` file |
| Residual Godot processes | 0 |

The two broad-pytest failures are the expected R2-1 freshness integration test
and the historical `test_csv_exports_three_canonical_layers` failure. Neither
is introduced by the isolated primitive.
