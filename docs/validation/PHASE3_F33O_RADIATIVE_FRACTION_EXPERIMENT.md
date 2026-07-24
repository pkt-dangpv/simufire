# Phase 3 F3.3o - Isolated CFAST radiative-fraction experiment

Date: 2026-07-24

## Decision

**NO-GO. The temporary runtime surface was removed. No 600 s run was made.**

F3.3o tested one isolated input difference while holding the accepted F3.3n
receiver routing fixed:

```text
CFAST radiative fraction = 0.35
shadow convective fraction = 0.65
```

The candidate changed only the shadow convective-heat proposal. The existing
plume proposal, fire diameter, O2 acceptance law, source removal, receiver
routing, species and every atomic ledger remained unchanged.

The result is conservative but physically worse at the mandatory 180 s STOP.
The extra heat is applied to nearly the same plume mass, so R0 and the
receiving rooms overheat while upper-zone mass correspondence regresses.

No official case, report, baseline, expected value, tolerance, gap, CTRL, FED
path or HVAC path changed.

## Candidate contract

The temporary default-OFF flag replaced the legacy thermal proposal:

```text
Qconv_requested = Qlegacy * 0.65 * dt
Qconv_accepted  = Qconv_requested * canonical_O2_acceptance
```

The atomic combustion bundle still applied O2 acceptance exactly once.
Plume mass retained the current canonical formula and historical diameter.
The F3.3n `flogo` receiver split remained active.

The temporary flag, helper, CLI wiring and structural test were removed after
the decision.

## No-op proof

The new-code OFF run is byte-identical to the accepted F3.3n 180 s run:

```text
rows: 114 / 114
columns: 667 / 667
SHA-256:
80BC7E10C4B5CE86CADB59AF84AA3538E58D78009D748899DFDBF70456170939
```

The ON run preserves all `115` legacy columns with zero differing cells.

## Mandatory 180 s STOP

Values are `F3.3n OFF / F3.3o ON / CFAST`.

| Room | Upper mass kg | Upper T C | Lower mass kg | Lower T C | Interface m |
|---|---:|---:|---:|---:|---:|
| R0 | 23.80 / 19.34 / 26.94 | 129.4 / 224.2 / 159.8 | 24.05 / 23.00 / 15.41 | 30.7 / 43.3 / 61.6 | 1.038 / 1.034 / 0.736 |
| Hall | 14.58 / 12.61 / 18.38 | 85.6 / 140.2 / 93.6 | 11.91 / 11.41 / 6.50 | 31.7 / 47.0 / 48.4 | 0.984 / 0.989 / 0.568 |
| R2 | 21.24 / 19.68 / 25.24 | 52.1 / 82.8 / 62.1 | 6.61 / 6.13 / 1.25 | 23.8 / 30.1 / 21.3 | 0.531 / 0.503 / 0.100 |

R0 upper-temperature absolute error grows from `30.4 C` to `64.4 C`.
R0 upper-mass error grows from `3.14 kg` to `7.60 kg`. Both binding STOP
criteria fail, even though interface height changes slightly toward CFAST.

## Source and sink attribution

At 180 s in R0:

| Quantity | F3.3n OFF | F3.3o ON |
|---|---:|---:|
| Accepted combustion heat | 10.996 MJ | 23.670 MJ |
| Plume lower-to-upper mass | 72.03 kg | 71.20 kg |
| Wall upper energy out | 1.428 MJ | 6.144 MJ |
| Ambient upper energy out | 2.527 MJ | 4.213 MJ |

The heat source increases by `115%`; plume mass changes by only `-1.2%`.
Wall and ambient losses respond strongly but cannot prevent overheating.
This is the expected failure mode of changing `chi_rad` independently from
the plume/source geometry.

The final sampled combustion transaction reports:

- accepted HRR `279.91 kW`;
- canonical effective fraction `0.933`;
- requested convective step `16.2500 kJ`;
- accepted convective step `15.1616 kJ`.

This confirms that O2 acceptance is not double-applied.

## Conservation

The candidate is numerically valid:

- mass-residence room/building residual: zero;
- enthalpy-residence room/building residual: zero;
- interior mass/energy/O2/species residual: zero;
- combustion O2/energy/species residual: zero;
- atomic rejected mass and energy: zero;
- invalid atomic bundles: zero;
- zero-O2 flame flag: zero.

The decision is therefore a physical-correspondence NO-GO, not a
conservation failure.

## What F3.3o proves

1. The historical `chi_rad=0.70` is a real source-energy mismatch.
2. Replacing it independently is not a valid fix.
3. Convective heat and plume entrainment must share one accepted `Qc`.
4. F3.3n receiver routing is necessary but cannot compensate for a split
   source contract.
5. No radiative-fraction sweep or intermediate tuning is justified.

## Next gate: F3.3p

F3.3p should be design-first and revisit the previously removed F3.3e1
coupled source now that F3.3n lower/upper routing is available:

```text
Qaccepted -> chi_rad -> Qc
Qc -> convective heat
Qc + exact Heskestad virtual origin -> plume mass
```

The design must:

- keep the F3.3n receiver split fixed;
- use one accepted Q/Qc for heat and plume;
- keep the canonical O2 law unchanged;
- explain why the former F3.3e1 lower-zone collapse should or should not be
  resolved by the corrected receiver routing;
- treat `chi_rad=0.35` and CFAST fire diameter as dimensions of one plume
  source contract, not as independent tuning knobs;
- require a 180 s STOP and prohibit 600 s unless upper/lower mass,
  temperature, interface and every residual improve together.

HVAC remains deferred.
