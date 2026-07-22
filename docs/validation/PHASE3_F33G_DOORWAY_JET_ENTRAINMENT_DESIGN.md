# Phase 3+ F3.3g - Receiver-side doorway-jet entrainment

Date: 2026-07-22

## Decision

**Pure design and direct-fixture GO. Runtime wiring, Group C execution,
canonical authority and gap retirement remain NO-GO.**

F3.3g implements the current CFAST doorway-jet mixing equation as a pure
preview and maps its result to one conservative receiver-internal atomic
route. It has no Engine flag, runner argument, CSV field, case override or
`RoomModel` write. Existing runtime behavior is therefore unchanged.

The next phase is F3.3g1: preserve each hydrostatic opening slab through the
F3.3a/F3.3b preview and build the separate receiver-mixing routes beside, not
inside, source-preserving direct transport. That integration must remain
default OFF and stop at 180 s before any longer Group C run.

## F3.3g1 outcome

F3.3g1 completed the requested integration and returned runtime **NO-GO** at
180 s. Conservation and slab/order contracts passed, but the cool Poreh branch
dominated the hot branch and moved upper mass/interface away from CFAST. The
temporary public runtime surface was removed; this pure design remains as an
internal default-false contract. See
`PHASE3_F33G1_DOORWAY_JET_INTEGRATION_EXPERIMENT.md`. The next phase is F3.3h,
an audit of CFAST `UFLW/UFLW2/UFLW3` source-to-output semantics.

## Binding CFAST contract

The primary implementation reference is the current official CFAST source:

- `Source/CFAST/flowhorizontal.f90`, `wall_flow`, `spill_plume` and
  `poreh_plume`;
- `https://github.com/firemodels/cfast/blob/master/Source/CFAST/flowhorizontal.f90`.

NIST SP 1026r1 section 3.3 remains the ownership reference for direct slab
flow versus induced mixing:

- `https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.1026r1.pdf`.

The current source uses the Poreh spill-plume correlation, not the older
McCaffrey virtual-origin expression shown in historical descriptions. The
implemented preview follows the current source.

For one source slab with mass flow `mdot`, width `w`, mixing depth `z`, upper
temperature `Tu` and lower temperature `Tl` in kelvin:

```text
Qdot = cp * (Tu - Tl) * mdot
rhol = 352.981915 / Tl

mentrain = f * 0.44 * (Tl / Tu)^(2/3)
           * (g * rhol^2 / (cp * Tl))^(1/3)
           * Qdot^(1/3) * w^(2/3) * z
```

`cp` is `1000 J/(kg K)` in the present SimuFire air model. The result is
`kg/s`; the atomic request multiplies it by the physical `dt`.

## Two distinct mixing families

CFAST activates mixing only when the source slab and geometric receiver slab
belong to different zones.

### Hot upper source into receiver lower

- Thermal condition: source upper `Tu` exceeds receiver lower `Tl`.
- Mixing depth:
  `z = receiver_interface - max(vent_bottom, source_interface)`.
- Factor `f = 1.0`.
- Internal receiver route: `lower -> upper`.
- The entrained mass, enthalpy, O2 and species come from receiver lower.

### Cool lower source into receiver upper

- Thermal condition: source lower `Tl` is below receiver upper `Tu`.
- Mixing depth:
  `z = min(vent_top, source_interface)
       - max(receiver_interface, vent_bottom)`.
- Factor `f = 0.25`, matching CFAST's reduced Kelvin-Helmholtz mixing.
- Internal receiver route: `upper -> lower`.
- The entrained payload comes from receiver upper.

This second family is important. F3.3g is not a generic lower-to-upper smoke
promotion and must not be implemented as one.

## Ownership and conservation

Direct vent transport and doorway-jet entrainment are separate owners:

1. F3.3f1 direct transport preserves source-zone identity.
2. F3.3g transfers existing receiver inventory internally.

`make_canonical_doorway_jet_entrainment_route()` reads the pre-step receiver
snapshot. Requested sensible enthalpy, O2 and all seven species use the same
inventory fraction as requested gas mass. `make_atomic_bundle()` then applies
one accepted fraction to the complete route at transaction time.

Consequences:

- room and building gas mass remain invariant under mixing;
- room sensible energy, O2 and species remain invariant;
- an oversized request cannot partially move one quantity;
- source-stream composition is not incorrectly assigned to entrained gas;
- no delayed parcel or direct opening payload is duplicated.

The cause is classified under the existing `interior_opening` mass and
enthalpy residence families. No new CSV family is needed before runtime.

## Code surface

Only `sim/core/Phase3ZoneMassSystem.gd` changes:

- three constants copied from the current CFAST contract;
- `preview_canonical_doorway_jet_entrainment()`;
- `make_canonical_doorway_jet_entrainment_route()`;
- residence-family classification for the future route.

New direct checks:

- `tests/fixtures/phase3_f33g_doorway_jet_entrainment.gd`;
- `tests/test_phase3_f33g_doorway_jet_entrainment.py`.

## Direct fixture

The isolated Godot fixture verifies:

1. hot upper jet: full Poreh mixing and receiver `lower -> upper` route;
2. cool lower jet: quarter-strength mixing and receiver `upper -> lower`;
3. same-zone slabs and reversed thermal gradients remain inactive;
4. cube-root scaling with source flow and two-thirds scaling with width;
5. exact numeric rates for two fixed Poreh examples;
6. a deliberately oversized request is capped by one atomic fraction;
7. total gas mass, sensible energy, O2 and species remain exact.

The two fixed rates are `0.3857160247 kg/s` for the hot case and
`0.0906337952 kg/s` for the cool case.

## Verification

| Check | Result |
|---|---|
| Focused F3.3f1/F3.3g pytest | 15 PASS |
| All `test_phase3*.py` | 439 PASS |
| Godot 4.7.1 isolated F3.3g fixture | PASS |
| Hot and cool mixing families | PASS |
| Numeric Poreh examples | PASS |
| Atomic mass/energy/O2/species conservation | exact |
| Engine/CLI/CSV/case runtime surface | none |
| Official reports/baselines/tolerances/gaps | unchanged |
| `git diff --check` | PASS |

The fixture used an isolated `APPDATA` profile. No Godot process remained
running after exit 0.

## F3.3g1 integration requirements

The current F3.3a/F3.3b integrator aggregates mass by four-part route key and
discards slab bounds. Poreh needs source flow and geometry per slab. F3.3g1
must therefore preserve nonzero interval records containing at least:

- slab bottom/top;
- source and destination side;
- source zone and geometric receiver zone;
- source mass-flow rate;
- opening width and vent bounds;
- whether the interval belongs to gross exchange or signed pressure.

The future network bundle must add direct routes and internal mixing routes
from one common pre-step snapshot. Mixing routes may not alter direct flow,
neutral-plane pressure, source density or the F3.3b relaxation fraction.

## STOP and rollback

F3.3g1 must stop and roll back if:

- OFF differs from the current F3.3d1 checkpoint in schema or values;
- direct source-preserving transport and mixing are merged into one route;
- slab aggregation changes a Poreh result;
- mixing uses source-stream composition instead of receiver inventory;
- hot/cool activation or the `0.25` branch differs from CFAST;
- any mass, energy, O2 or species residual is nonzero;
- upper flow again collapses, lower renewal regresses, or the 180 s upper
  mass/interface moves farther from CFAST;
- implementation requires a per-case coefficient or changed opening/pressure
  coefficient.

Do not run 300/590 s, reintroduce coupled Qc, promote canonical authority or
retire Group C until the 180 s paired routing/mixing STOP passes.
