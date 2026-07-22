# Phase 3+ F3.3f - Lower-zone renewal and doorway-routing correspondence

Date: 2026-07-22

## Decision

**Diagnostic GO. Flow-magnitude correction is NO-GO. The selected next owner
is the destination-zone routing contract for horizontal interior openings.**

F3.3f compares CFAST and the rolled-back F3.3e1 candidate over the same three
Group C windows. The late lower-zone failure is not caused by too little total
doorway inflow. SimuFire receives more total gas than CFAST from 300-590 s,
but sends most of it to the upper zone. CFAST sends almost all of the incoming
gas to the lower zone and keeps that reservoir near 15.5 kg.

No runtime code, case, report, baseline, tolerance, gap, CTRL envelope or
authority changes in F3.3f.

## F3.3h correction

The direct CFAST flow comparison below remains valid, but the selected
source-preserving remedy does not. Source audit F3.3h proved that CFAST
deposits direct inflow using a smooth slab-temperature versus receiver-layer
temperature split. Source zone is used for removal, not destination. Poreh is
then added separately to layer evolution and is absent from the published
direct flow table. See `PHASE3_F33H_CFAST_DOORWAY_FLOW_SEMANTICS.md`.

## Sources and method

CFAST values come from the local reference outputs:

- `sim/validation/cfast/cfast_corridor_chain.out` for upper/lower doorway and
  leakage flow rates;
- `sim/validation/cfast/cfast_corridor_chain_compartments.csv` for plume and
  pyrolysis flow;
- `sim/validation/cfast/cfast_corridor_chain_zone.csv` for zone density,
  volume and interface state.

Rates were trapezoid-integrated over `0-180`, `180-300` and `300-590 s`.
CFAST zone masses are density times zone volume. SimuFire values come from the
exact accepted-route F3.3d1 mass ledger in the F3.3e1 600 s scratch run. Its
upper/lower, room and building mass residuals are exactly zero.

## CFAST R0 mass correspondence

All window values are kg. `Extra lower->upper` is inferred from the lower-zone
balance after explicit doorway, leakage, plume and pyrolysis terms. It is
small and the paired upper/lower residual remains below 0.023 kg.

| Window | Plume lower out | Upper in | Upper out | Lower in | Lower out | Leak upper out | Leak lower in | Leak lower out | Extra lower->upper |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0-180 s | 97.716 | 3.662 | 75.398 | 65.782 | 1.344 | 4.828 | 0.000 | 5.005 | 3.684 |
| 180-300 s | 62.244 | 1.825 | 69.695 | 66.520 | 0.000 | 1.191 | 0.064 | 0.338 | 3.846 |
| 300-590 s | 157.101 | 1.578 | 171.445 | 166.815 | 0.000 | 2.417 | 0.442 | 0.226 | 9.699 |

CFAST lower gas changes only from `15.406 kg` at 180 s to `15.794 kg` at
590 s. At the representative checkpoints, doorway lower inflow closely
tracks plume entrainment:

| t | Plume (kg/s) | Upper in | Upper out | Lower in | Lower out |
|---:|---:|---:|---:|---:|---:|
| 180 s | 0.503 | 0.025 | 0.583 | 0.543 | 0.000 |
| 300 s | 0.528 | 0.010 | 0.584 | 0.563 | 0.000 |
| 590 s | 0.552 | 0.003 | 0.597 | 0.584 | 0.000 |

This is the expected two-zone circulation: hot gas leaves through the upper
doorway and cool replacement gas enters the lower reservoir.

## SimuFire accepted routes

The F3.3e1 candidate used the physically aligned Qc/plume source and is useful
here only as a diagnostic replay. It was rolled back after the 600 s NO-GO.

| Window | Opening upper in | Opening upper out | Opening lower in | Opening lower out | Pressure upper in | Pressure upper out | Pressure lower in | Pressure lower out | Plume lower out |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0-180 s | 17.885 | 80.557 | 62.871 | 0.199 | 0.587 | 6.542 | 0.325 | 6.850 | 98.363 |
| 180-300 s | 26.828 | 78.645 | 51.817 | 0.000 | 7.624 | 12.177 | 3.101 | 5.649 | 53.672 |
| 300-590 s | 143.656 | 191.579 | 47.923 | 0.000 | 28.235 | 38.290 | 3.676 | 5.269 | 56.229 |

The decisive late-window comparison is:

| 300-590 s destination | CFAST | SimuFire | Difference |
|---|---:|---:|---:|
| Total doorway inflow | 168.393 kg | 223.489 kg | SimuFire +32.7% |
| Inflow deposited in lower | 166.815 kg | 51.599 kg | SimuFire -69.1% |
| Inflow deposited in upper | 1.578 kg | 171.890 kg | SimuFire +10,794% |

Increasing an opening coefficient, signed-pressure gain or total mass flow
would worsen the actual error. The missing quantity is lower-zone routing,
not gross doorway capacity.

## Binding code path

`Phase3ZoneMassSystem._integrate_canonical_interior_opening()` divides an
opening at both zone interfaces and the neutral plane. For each interval,
`_canonical_interior_interval_flow()` selects both zones from the interval
midpoint:

```text
source_zone      = zone_at_height(source, midpoint)
destination_zone = zone_at_height(destination, midpoint)
```

The route then carries that immutable destination through the F3.3a opening
bundle and F3.3b pressure bundle. `_apply_atomic_route()` deposits mass,
enthalpy, O2 and species directly into that selected destination inventory.
Conservation is exact, but the destination semantics are wrong for a dense,
cool inflow jet crossing a receiver whose interface is already low.

As the R0 interface falls, more interval midpoints lie above it. The same cool
replacement flow is then classified as upper inflow. Lower replenishment
falls, the plume removes more lower inventory, the interface falls further
and still more incoming gas is routed upper. This positive feedback explains
the F3.3e1 lower-zone collapse without any hidden mass loss.

## Hypothesis verdicts

| Candidate cause | Verdict | Evidence |
|---|---|---|
| Total doorway-flow magnitude | Rejected | Late SimuFire total inflow is 32.7% above CFAST. |
| Plume magnitude alone | Rejected as current owner | Correct early plume still collapses lower once routing feedback develops. |
| Source-zone selection | Retain provisionally | It identifies the thermodynamic inventory and payload actually leaving the source. |
| Destination-zone midpoint selection | Selected | It reverses the CFAST late split: 77% upper in SimuFire versus 0.9% upper in CFAST. |
| Coupling order | Reinforcing, not primary | The common pre-step solve is order-independent, but its next-step interface feeds the same bad routing rule. |
| Force every inflow to lower | Rejected | CFAST has nonzero upper inflow and hot upper-to-upper transport must remain possible. |

## Next gate: F3.3f1 destination-routing contract

F3.3f1 must be design-first and default OFF. It must not reintroduce the
F3.3e1 Qc runtime candidate until the routing contract passes direct fixtures.
The candidate contract should preserve the source stream's thermodynamic
identity across a horizontal doorway:

- cool/lower source flow should renew the receiver lower zone even when its
  geometric midpoint is above a depressed receiver interface;
- hot/upper source flow should remain eligible for the receiver upper zone;
- a missing/degenerate destination zone needs an explicit conservative
  transition, not silent reassignment;
- density/temperature and neutral-plane evidence may refine the decision, but
  no empirical gain or per-case threshold is authorized.

Required direct fixtures:

1. lower/cool source to a receiver with a low interface;
2. upper/hot source to a two-zone receiver;
3. bidirectional counterflow with exact mass, enthalpy, O2 and species closure;
4. one-zone receiver transition;
5. reversed opening order with identical results;
6. F3.3a and F3.3b route families using the same destination contract.

Runtime STOP sequence after fixture approval:

1. 180 s: preserve the early F3.3e1 mass/interface improvement and exact
   residence residuals;
2. 300 s: lower gas must not be below CFAST by more than the OFF control, and
   lower inflow must move toward the CFAST `66.52 kg` window integral;
3. 590 s: lower gas and interface must remain nonzero; lower/upper incoming
   split must move toward `166.815/1.578 kg` without increasing total inflow;
4. only then may the coupled-Qc source be replayed as a separate composition
   test.

Rollback immediately if total opening flow is increased to mask routing,
upper hot transport is forced into lower, any conserved quantity has a
nonzero residual, a zone collapses earlier, or shared legacy output changes
with the new flag OFF.

## STOP gate

| Check | Result |
|---|---|
| F3.3f runtime code | none |
| Official cases/reports/baselines/tolerances | unchanged |
| Group C VALID_GAP | unchanged |
| F3.3e1 candidate | remains fully rolled back |
| Root cause classification | destination-zone routing with positive interface feedback |
| Flow coefficient/pressure retune | NO-GO |
| F3.3f1 design | GO |
