# Phase 3+ F3.3i - Buoyancy-input and gross-flow correspondence audit

Date: 2026-07-23

## Decision

**Diagnostic closed without a motor patch.**

The F3.3h1 `flogo` formula is not the owner of the F3.3h2 runtime failure.
It receives a different upstream two-zone state from CFAST. The dominant
difference is the Hall interface: at 180 s it is `1.366 m` in the SimuFire
canonical shadow and `0.568 m` in CFAST.

Consequently, CFAST exposes a substantial hot Hall-upper stream to R0 while
SimuFire classifies almost the complete incoming opening as cool Hall-lower
gas. Applying the same `tanhsmooth` formula to those different inputs must
produce different receiver splits.

No runtime flag, telemetry field or physical coefficient was added. The audit
uses the retained F3.3h2 scratch CSV and the committed CFAST zone/slab CSV.

## Exact CFAST reconstruction

The CFAST source file exports every R0-Hall vent slab:

- `HSLABT_1_n`: source slab temperature;
- `HSLABF_1_n`: signed slab mass flow;
- `HSLABYB/YT_1_n`: slab bounds;
- `ULT_1/LLT_1`: R0 receiver temperatures.

Reapplying the exact F3.3h1 formula to those fields and trapezoid-integrating
from 0 to 180 s reconstructs the published direct flow:

| CFAST direct R0 inflow | Value |
|---|---:|
| Total | 69.44194 kg |
| Lower destination | 65.77975 kg |
| Upper destination | 3.66219 kg |
| Upper fraction | 5.2737% |
| Mass-weighted source temperature | 41.01 C |

Of the incoming CFAST mass, `73.94%` has source temperature below the lower
transition threshold and `26.06%` lies inside the `tanhsmooth` transition.
None is above the upper threshold.

## State and slabs at 180 s

| Quantity | CFAST | SimuFire F3.3h2 ON |
|---|---:|---:|
| R0 lower temperature | 61.56 C | 27.88 C |
| R0 upper temperature | 159.82 C | 128.42 C |
| R0 interface | 0.736 m | 1.207 m |
| Hall lower temperature | 48.38 C | 28.05 C |
| Hall upper temperature | 93.55 C | 80.46 C |
| Hall interface | 0.568 m | 1.366 m |

CFAST Hall-to-R0 inflow at 180 s contains:

| Slab | Bounds | Source temp | Flow |
|---|---:|---:|---:|
| Hall lower | 0.000-0.568 m | 48.38 C | 0.34751 kg/s |
| Hall upper | 0.568-0.736 m | 93.55 C | 0.09116 kg/s |
| Hall upper | 0.736-1.061 m | 93.55 C | 0.12880 kg/s |

The two hot slabs receive an upper fraction of `11.21%`, producing the exact
`0.02465 kg/s` CFAST upper inflow. SimuFire's Hall interface is 0.798 m
higher, so the equivalent opening region remains classified mostly as lower
source gas.

## SimuFire 0-180 s correspondence

From the exact accepted-route cumulative fields:

| SimuFire direct R0 inflow | Value |
|---|---:|
| F3.3a opening | 52.69844 kg |
| F3.3b signed pressure | 1.23603 kg |
| Total | 53.93447 kg |
| Lower destination | 53.71172 kg |
| Upper destination | 0.22275 kg |
| Upper fraction | 0.4130% |

Mass-weighted logged canonical temperatures over the accepted inflow are:

- Hall lower: `23.01 C`;
- Hall upper: `68.21 C`;
- R0 lower: `24.29 C`;
- R0 upper: `109.87 C`.

Once the R0 lower layer becomes warmer than the incoming Hall lower gas,
`tanhsmooth` correctly saturates near zero upper deposition. This is why the
candidate spends long intervals with no upper inflow. It is not a numerical
error in the split.

## Gross-flow deficit

SimuFire's integrated direct inflow is `15.50747 kg` or `22.33%` below CFAST.
At 180 s its last logged interval averages about `0.4679 kg/s`, versus CFAST
`0.5675 kg/s`, a `17.55%` deficit.

The discrepancy is also upstream of destination routing:

- SimuFire's canonical neutral plane is `1.253 m`;
- CFAST changes from inflow to outflow near `1.061 m`;
- the SimuFire canonical room-pressure difference is about `425.8 Pa`;
- CFAST's room-pressure difference is only `0.555 Pa`;
- F3.3b therefore limits its signed-pressure route with an equilibrium
  fraction of `0.0002107`.

Increasing F3.3b or adding a doorway coefficient would be unsafe: it would
amplify a route driven by non-corresponding pressure states. The F3.3a
hydrostatic flow is also reduced by the colder, higher-interface state and
the resulting weaker density profile.

## Root cause

F3.3i assigns both F3.3h2 discrepancies upstream:

1. **Upper destination deficit:** Hall upper volume is too small because its
   interface is too high. Source-zone selection therefore presents cold lower
   gas to the exact `flogo` split.
2. **Total direct-flow deficit:** R0/Hall thermal stratification and neutral
   plane differ from CFAST, while the separate pressure state is hundreds of
   pascals away and must be strongly relaxed.

The opening destination selector is downstream of both errors and cannot
close either one.

## Next gate

F3.3j should audit the upstream Hall two-zone residence balance over
0-180 s, using the existing OFF checkpoint and residence ledgers:

1. compare Hall upper/lower mass, energy and interface against CFAST;
2. separate R0-to-Hall opening and pressure inflow from Hall-to-R2 outflow;
3. quantify wall/ambient and interzone-energy ownership in Hall;
4. identify whether Hall's high interface comes from insufficient hot mass,
   insufficient enthalpy, excessive onward transport or projection;
5. keep pressure as a separately reported secondary blocker.

No new routing candidate, coefficient or long run is justified before that
upstream balance has an owner.

F3.3j subsequently closed the aggregate Hall residence audit. Gross incoming
mass is not deficient, but SimuFire carries only `38.88%` of CFAST's net
direct sensible enthalpy and its direct upper balance is `22.008 kg` below
CFAST. Poreh almost compensates that mass error internally without supplying
the missing energy. See `PHASE3_F33J_HALL_RESIDENCE_AUDIT.md`.
