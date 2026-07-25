# Phase 3+ F3.3r2b2 physical enclosure topology

Date: 2026-07-25

Status: GO for explicit default-OFF enclosure metadata and exterior exchange.
Inter-room surface conduction, official-case activation, thermal authority and
VALID_GAP retirement remain NO-GO.

## Physical contract

Each `RoomModel` can now carry `phase3_surface_boundaries`. The dictionary has
exactly four canonical surfaces:

```text
ceiling
upper_wall
lower_wall
floor
```

Each surface declares three area fractions:

```text
exterior_fraction
inter_room_fraction
adiabatic_fraction
```

Every value must be finite and in `[0, 1]`; all three must sum to one within
`1e-6`. All four surfaces must be present. The metadata is loaded as a deep
copy from `rooms_data`, so editor/runtime scenario serialization can preserve
it without coupling the motor to a visual node.

Missing, malformed or incomplete topology fails closed:

- no boundary is inferred from a mesh, facade, room rectangle or opening;
- all four surfaces are treated as adiabatic;
- metadata completeness is zero;
- no exterior energy is removed.

This is deliberate. A rectangle edge with no simulated neighbor is not
necessarily exterior: it can be a party wall, an unmodelled corridor or
another apartment. Ceiling and floor exposure also cannot be inferred safely
from `building_type` or the visual model.

## Exterior exchange

The existing F3.3r2b1 surface solver receives an effective Robin coefficient:

```text
h_effective = exterior_fraction * 0.025 kW/(m2 K)
```

This is equivalent to applying the canonical exterior coefficient to only the
exposed area while retaining one nodal state per canonical surface. The
coefficient is fixed and matches the existing exterior wall PDE default; no
new per-case calibration knob was added.

An explicit zero-exterior topology is still complete. It is not confused with
missing metadata.

## Inter-room boundary

`inter_room_fraction` is normalized and exported, but remains adiabatic in
this phase. The number of surfaces containing unsupported inter-room area is
also exported. No heat is silently sent to a room without an explicit paired
surface transaction.

F3.3r2c may use staged correspondence to decide whether aggregate adiabatic
handling is sufficient for the target cases. If not, paired room/surface
identities and an atomic two-surface conduction transaction must be designed
before runtime authority.

## Observability

The opt-in canonical shadow CSV now exports the previously internal
multi-surface transaction fields plus:

- boundary metadata completeness;
- fully adiabatic surface count;
- exterior, inter-room and adiabatic fraction sums;
- unsupported inter-room surface count;
- combined gas/surface/exterior energy residual.

The default CSV schema remains unchanged because every official case keeps
the parent canonical shadow disabled. No official case currently declares
`phase3_surface_boundaries`.

## STOP gate

Godot 4.7.1:

| Check | Result |
|---|---|
| F3.3r2b2 direct fixture | PASS |
| F3.3r2b1 regression fixture | PASS |
| Full project parse | PASS |
| Phase 3 Python contracts | 511 PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 353 required / 6 VALID_GAP / 71 non-gating |
| Guardrails before commit | 9/10; only expected R2-1 dirty-motor failure |

The direct fixture covers missing, mixed, zero-exterior and invalid topology;
deep-copy loading; fractional exterior coefficients; visible unsupported
inter-room area; and exact combined energy closure.

The 10 s engine scratch produced:

| Metric | OFF | ON |
|---|---:|---:|
| Rows | 66 | 66 |
| Shadow CSV columns | 459 | 459 |
| Shared legacy columns | 163 | 163 |
| Legacy value differences | 0 | 0 |

For the mixed room-0 topology, ON exported:

```text
metadata_complete = 1
exterior_fraction_sum = 1.50
inter_room_fraction_sum = 1.25
adiabatic_fraction_sum = 1.25
unsupported_inter_room_surface_count = 2
combined_energy_residual = -0.0 kJ
```

Scratch inputs and outputs were removed. No official CSV, report, expected,
tolerance, baseline, gap, FED, HVAC or visual file changed.

## Next phase

Proceed to F3.3r2c as scratch-only staged correspondence:

1. declare explicit topology in scratch copies, never official cases;
2. compare at 60, 120 and 180 s;
3. audit surface storage and gas/exterior energy closure;
4. measure sensitivity to unsupported inter-room fractions;
5. STOP before any runtime authority, baseline change or gap retirement.
