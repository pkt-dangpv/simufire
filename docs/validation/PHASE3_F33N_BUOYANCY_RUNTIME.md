# Phase 3 F3.3n - CFAST buoyancy destination runtime

Date: 2026-07-24

## Decision

**Mechanism GO. Canonical authority and Group C retirement remain NO-GO.**

F3.3n re-exposes the exact CFAST `flogo` receiver split from F3.3h1 behind
the default-OFF flag:

```text
phase3_cfast_buoyancy_destination_shadow_enabled
```

Only the receiver lower/upper destination changes. Source-zone removal,
gross slab mass, pressure flow, sensible enthalpy, O2, species and atomic
acceptance remain unchanged. Doorway-jet/Poreh entrainment stays disabled.

The mechanism fixes the principal routing error identified in F3.3m:
hot R0 gas now forms an upper layer in Hall and R2, while cool return flow is
sent predominantly to the lower layer. It does not fix the remaining
convective-source energy deficit.

No official case, report, expected value, tolerance, gap, CTRL, FED path or
HVAC path changes in F3.3n.

## Runtime surface

The experiment adds:

- one `SimulationEngine` flag, default `false`;
- one CLI switch:
  `--phase3-cfast-buoyancy-destination-shadow`;
- headless wiring that enables the complete canonical shadow and residence
  ledger stack;
- structural tests that pin the default, wiring and use of the existing pure
  CFAST helper.

The new flag is independent of the signed-pressure switch. The CLI enables
both because the Group C correspondence run needs both direct opening flow
and its signed-pressure component.

## No-op proof

The 180 s OFF run is byte-identical to the F3.3m corrected-topology run:

```text
SHA-256
14BF3C6E40D20FADFB3CAC3CB5B38B06A2F1A228E70A5766DD725CD020DCEE42
```

The 180 s ON comparison retains all `115` legacy columns with zero differing
cells. F3.3n changes only shadow state.

The direct Godot fixture also passes under an isolated Windows profile:

```text
PHASE3_F33H1_BUOYANCY_ROUTING_PASS
```

## State correspondence

Values are `OFF / ON / CFAST`.

### Fire room R0

| t | Upper mass kg | Upper T C | Lower mass kg | Lower T C |
|---:|---:|---:|---:|---:|
| 60 | 21.12 / 20.89 / 23.88 | 50.3 / 50.4 / 64.5 | 34.27 / 34.53 / 29.70 | 20.5 / 20.4 / 22.2 |
| 120 | 24.37 / 22.28 / 27.39 | 116.2 / 119.8 / 139.2 | 24.50 / 27.45 / 18.05 | 29.4 / 23.5 / 33.7 |
| 180 | 24.57 / 23.80 / 26.94 | 126.4 / 129.4 / 159.8 | 22.43 / 24.05 / 15.41 | 42.3 / 30.7 / 61.6 |
| 300 | 25.14 / 23.64 / 25.95 | 117.8 / 123.1 / 166.3 | 21.42 / 23.88 / 15.56 | 50.2 / 39.3 / 75.0 |
| 600 | 26.13 / 24.51 / 25.25 | 98.2 / 101.8 / 168.8 | 22.45 / 24.78 / 15.79 | 44.2 / 35.8 / 85.3 |

R0 upper mass is closer to CFAST at 600 s and upper temperature improves
slightly. R0 lower remains non-degenerate, but its temperature confirms that
receiver routing alone cannot supply the missing room energy.

### Hall

| t | Upper mass kg | Upper T C | Lower mass kg | Lower T C |
|---:|---:|---:|---:|---:|
| 60 | 0.00 / 3.28 / 10.38 | 20.0 / 38.5 / 37.8 | 30.08 / 26.77 / 19.13 | 21.7 / 20.0 / 20.1 |
| 120 | 0.00 / 12.71 / 17.80 | 20.0 / 76.5 / 82.0 | 27.88 / 15.02 / 8.38 | 45.0 / 21.6 / 26.9 |
| 180 | 0.00 / 14.58 / 18.38 | 20.0 / 85.6 / 93.6 | 26.67 / 11.91 / 6.50 | 59.3 / 31.7 / 48.4 |
| 300 | 0.00 / 13.10 / 18.23 | 20.0 / 90.7 / 97.5 | 26.46 / 13.06 / 6.37 | 63.3 / 42.5 / 52.4 |
| 600 | 0.00 / 13.68 / 18.14 | 20.0 / 74.5 / 98.0 | 27.14 / 13.39 / 6.44 | 54.3 / 37.4 / 52.7 |

The absent Hall upper layer is fixed structurally. Its remaining mass and
temperature deficit is consistent with the F3.3m source-enthalpy diagnosis.

### Remote room R2

| t | Upper mass kg | Upper T C | Lower mass kg | Lower T C |
|---:|---:|---:|---:|---:|
| 120 | 0.00 / 13.04 / 22.65 | 20.0 / 52.7 / 52.6 | 29.59 / 15.72 / 4.98 | 26.5 / 20.7 / 20.2 |
| 180 | 0.00 / 21.24 / 25.24 | 20.0 / 52.1 / 62.1 | 28.51 / 6.61 / 1.25 | 37.8 / 23.8 / 21.3 |
| 300 | 0.00 / 22.15 / 24.96 | 20.0 / 54.6 / 65.9 | 27.97 / 5.29 / 1.24 | 45.3 / 35.0 / 22.8 |
| 600 | 0.00 / 24.56 / 25.05 | 20.0 / 44.8 / 64.7 | 28.37 / 3.45 / 1.24 | 40.0 / 30.7 / 24.5 |

R2 lower mass becomes small but does not collapse. Its trend and upper mass
move strongly toward CFAST, so the low lower inventory is not by itself a
rollback signal.

## Connection correspondence at 600 s

Opening and signed-pressure families are combined.

| Route | Mass OFF / ON / CFAST kg | Enthalpy OFF / ON / CFAST MJ | Destination upper OFF / ON / CFAST |
|---|---:|---:|---:|
| R0 -> Hall | 331.1 / 304.1 / 317.9 | 25.90 / 23.31 / 43.12 | 0.0% / 77.1% / 99.7% |
| Hall -> R0 | 305.2 / 286.5 / 306.2 | 11.32 / 7.49 / 12.93 | 28.5% / 14.8% / 2.3% |
| Hall -> R2 | 293.0 / 215.7 / 258.5 | 10.81 / 11.64 / 18.85 | 0.0% / 85.1% / 99.8% |
| R2 -> Hall | 279.9 / 205.4 / 254.5 | 5.60 / 5.08 / 9.31 | 0.0% / 5.2% / 8.3% |

All four destination fractions move toward CFAST. Gross mass changes because
the corrected layer states feed back into the next pressure calculation.
That feedback improves some routes and worsens others, so F3.3n is not a
mass-flow calibration.

The enthalpy deficit remains large. This is expected: F3.3n deliberately
does not change the fire convective source, radiative fraction, fire
diameter or O2 acceptance law.

## Conservation and STOP gate

At 180 and 600 s:

- room and building mass residuals are zero;
- room and building enthalpy residuals are zero;
- interior opening mass, energy, O2 and species residuals are zero;
- lower gas does not collapse in R0;
- Hall upper forms;
- all four useful direction fractions move toward CFAST;
- legacy output remains invariant.

| Check | Result |
|---|---|
| Default OFF | PASS |
| OFF byte equivalence | PASS |
| 115 legacy columns invariant ON | PASS |
| Exact CFAST helper fixture | PASS |
| 180 s STOP criteria | PASS |
| 600 s conservation | PASS |
| Hall and R2 upper formation | PASS |
| Receiver direction correspondence | PASS |
| Thermal-source closure | NO |
| Canonical authority | NO-GO |
| Group C retirement | NO-GO |

## Next gate: F3.3o

F3.3o should revisit the fire-source input contract with F3.3n routing held
constant:

1. keep the corrected two-door topology and exact receiver split;
2. compare the existing SimuFire case inputs against exact CFAST inputs;
3. isolate the radiative-fraction mapping first;
4. do not combine radiative fraction, fire diameter and O2 law in one run;
5. STOP at 180 s before continuing to 600 s;
6. reject any candidate that improves temperature by inventing mass,
   violates O2/energy closure or creates zero-O2 flaming.

The first candidate should test exact CFAST `RADIATIVE_FRACTION=0.35`
semantics in shadow without changing the official legacy case. The existing
historical `hrr_chi_rad_*=0.70` mapping is the largest known convective-source
difference and is independently attributable.

HVAC remains deferred.
