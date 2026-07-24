# Phase 3 F3.3m - Time-windowed R0-Hall source correspondence

Date: 2026-07-24

## Decision

**Diagnostic GO. Motor candidate and authority remain NO-GO.**

F3.3m assigns the corrected-topology Group C discrepancy to two explicit
owners:

1. the current canonical geometric destination routing does not reproduce
   CFAST `flogo` semantics;
2. the fire-source input/acceptance contract supplies much less convective
   energy than the CFAST reference.

The gross doorway mass error is transient. It is large and negative before
180 s, but becomes positive after 180 s. A global opening or pressure
multiplier would therefore improve one window and worsen the next.

No motor state, case, official report, expected value, tolerance, gap, CTRL or
HVAC path changed in F3.3m.

## Reproducible audit

The new read-only analyzer is:

```text
scripts/simulation/analyze_phase3_f33m_source_correspondence.py
```

It reads:

- SimuFire opt-in checkpoints at 60, 120, 180, 300 and 600 s;
- the F3.3k accepted-route connection ledger;
- the F3.3c1/F3.3d1 enthalpy and mass residence fields;
- committed CFAST compartment and zone/slab CSVs.

For CFAST it trapezoid-integrates each signed vent slab and applies the exact
F3.3h1 `tanhsmooth` receiver split. Sensible enthalpy uses the shared
reference `20 C` and `cp=1.0 kJ/(kg K)`.

The committed CFAST reconstruction test reproduces the established F3.3i
Hall-to-R0 0-180 s values:

- total mass `69.44193552 kg`;
- sensible enthalpy `1459.09797265 kJ`;
- upper destination `3.66218629 kg`.

Scratch output is retained under `runs/phase3_f33m_*` and is ignored by Git.

## R0 source state

The canonical upper inventory is close to CFAST by 180 s and almost exact by
300 s. Its temperature is not.

| t | SF upper mass | CFAST | SF upper T | CFAST | SF total sensible E | CFAST |
|---:|---:|---:|---:|---:|---:|---:|
| 60 s | 21.12 kg | 23.88 kg | 50.3 C | 64.5 C | 0.658 MJ | 1.127 MJ |
| 120 s | 24.37 kg | 27.39 kg | 116.2 C | 139.2 C | 2.575 MJ | 3.512 MJ |
| 180 s | 24.57 kg | 26.94 kg | 126.4 C | 159.8 C | 3.112 MJ | 4.407 MJ |
| 300 s | 25.14 kg | 25.95 kg | 117.8 C | 166.3 C | 3.105 MJ | 4.652 MJ |
| 600 s | 26.13 kg | 25.25 kg | 98.2 C | 168.8 C | 2.587 MJ | 4.789 MJ |

The late Group C temperature gap is therefore not caused by too little upper
gas inventory. At 600 s SimuFire has slightly more upper gas and about 46%
less sensible energy.

## R0-to-Hall windows

Opening and signed-pressure families are combined for the physical
comparison and retained separately for attribution.

| Window | SF mass | CFAST | SF source T | CFAST | SF enthalpy | CFAST |
|---:|---:|---:|---:|---:|---:|---:|
| 0-60 s | 4.06 kg | 8.90 kg | 35.2 C | 46.6 C | 0.062 MJ | 0.237 MJ |
| 60-120 s | 25.01 kg | 33.16 kg | 82.2 C | 110.1 C | 1.556 MJ | 2.989 MJ |
| 120-180 s | 30.74 kg | 34.67 kg | 113.5 C | 150.8 C | 2.874 MJ | 4.535 MJ |
| 180-300 s | 81.98 kg | 69.71 kg | 105.9 C | 164.6 C | 7.039 MJ | 10.084 MJ |
| 300-600 s | 189.29 kg | 171.47 kg | 95.9 C | 167.4 C | 14.364 MJ | 25.272 MJ |

The mass ratio evolves from `0.456` to `1.104`. The enthalpy ratio only
reaches `0.698` and then falls to `0.568`. This is decisive:

- before 180 s, both gross mass and source temperature are deficient;
- after 180 s, gross mass is sufficient or excessive;
- the persistent late owner is source thermal content, not doorway gain.

The signed-pressure family contributes about 13-15% of mass at 60-180 s but
about 39-40% after 180 s. Increasing it globally is specifically rejected.

## Destination routing mismatch

Current accepted routes and CFAST direct slabs disagree in both useful
directions:

- R0-to-Hall: SimuFire sends `0%` to Hall upper in every window; CFAST sends
  `90%` in the first window and effectively `100%` thereafter.
- Hall-to-R0: SimuFire sends progressively too much return mass to R0 upper;
  CFAST sends almost all return flow to R0 lower.

At 300-600 s:

- Hall-to-R0 gross mass is close: `173.87 kg` versus `168.39 kg`;
- SimuFire lower return is only `122.74 kg`;
- CFAST lower return is `166.82 kg`.

The passive canonical Hall therefore never forms an upper zone:

| t | SF Hall upper mass | CFAST | SF Hall upper T | CFAST |
|---:|---:|---:|---:|---:|
| 60 s | 0.00 kg | 10.38 kg | 20.0 C | 37.8 C |
| 120 s | 0.00 kg | 17.80 kg | 20.0 C | 82.0 C |
| 180 s | 0.00 kg | 18.38 kg | 20.0 C | 93.6 C |
| 300 s | 0.00 kg | 18.23 kg | 20.0 C | 97.5 C |
| 600 s | 0.00 kg | 18.14 kg | 20.0 C | 98.0 C |

This is not a conservation error. It is the known semantic difference
between geometric receiver routing and CFAST temperature-based `flogo`.
The exact pure `flogo` helper from F3.3h1 still exists, but its temporary
runtime surface was removed after the pre-equivalence F3.3h2 experiment.

F3.3k already showed that applying the helper with equivalent topology at
180 s creates `15.747 kg` Hall upper mass versus `18.384 kg` in CFAST. That
evidence now deserves a controlled corrected-topology runtime gate, not an
automatic promotion.

## Fire-source contract mismatch

Total HRR is not the late owner. After 120 s both models are at approximately
`300 kW`, and cumulative total fire energy differs by less than 2% at 600 s.

Convective energy is different:

| Window | SF convective source | CFAST `HRRC` | Ratio |
|---:|---:|---:|---:|
| 0-60 s | 0.857 MJ | 2.321 MJ | 36.9% |
| 60-120 s | 4.841 MJ | 10.849 MJ | 44.6% |
| 120-180 s | 5.300 MJ | 11.700 MJ | 45.3% |
| 180-300 s | 9.641 MJ | 23.400 MJ | 41.2% |
| 300-600 s | 19.630 MJ | 56.550 MJ | 34.7% |

There are two already-known input/acceptance differences:

1. CFAST declares `RADIATIVE_FRACTION=0.35`, while the SimuFire validation
   case still carries the historical `hrr_chi_rad_*=0.70` overrides.
2. CFAST keeps the prescribed fire at 300 kW while lower O2 remains above its
   `0.10` limit. The canonical SimuFire shadow linearly throttles below
   `fire_o2_full_hrr_open=0.15`; its factor is `0.952/0.838/0.637` at
   180/300/600 s.

The separate fire-diameter mismatch (`3.5 m` versus CFAST's equivalent
`0.6196 m`) remains relevant to plume mass and was already documented by
F3.3e. None of these inputs is changed in F3.3m.

## Owner assignment

| Finding | Owner | Verdict |
|---|---|---|
| Early R0-Hall gross mass deficit | canonical hydrostatic/pressure input state | real before 180 s, not globally tunable |
| Late R0-Hall mass surplus | signed-pressure share plus state divergence | rejects a global flow gain |
| Hall upper zone absent | destination-routing semantics | primary structural owner |
| R0 lower return deficient late | destination-routing semantics | primary lower-renewal owner |
| R0 upper mass close but too cool | convective source/residence | primary thermal owner |
| Total HRR close | fire schedule/fuel | not binding |
| Late canonical HRR factor low | O2 acceptance law/input mapping | secondary late owner |
| Mass/energy residual | atomic ledgers | closes; not an accounting bug |

## Next gate: F3.3n

F3.3n should re-expose the existing exact CFAST `flogo` destination split
behind a temporary default-OFF shadow flag on the now-correct official
topology.

Required sequence:

1. preserve source removal, slab mass, pressure, enthalpy, O2 and species;
2. change only receiver lower/upper routing through the existing pure helper;
3. run OFF equivalence and direct fixtures;
4. run Group C to 180 s and STOP;
5. continue to 600 s only if Hall upper forms, R0 lower does not collapse and
   all atomic residuals remain zero;
6. compare the five F3.3m windows again;
7. remove the temporary surface if either direction moves away from CFAST.

F3.3n must not yet change radiative fraction, fire diameter or O2 throttling.
If routing closes lower renewal, the following gate may revisit the already
designed coupled-Qc contract with exact CFAST inputs. Combining routing and
source changes in one run would destroy attribution.

HVAC remains deferred.

## STOP gate

| Check | Result |
|---|---|
| New motor behavior | none |
| Official case/report/baseline change | none |
| Expected/tolerance/gap change | none |
| F3.3m analyzer tests | 6/6 PASS |
| CFAST F3.3i reconstruction | exact within `1e-6` |
| Five checkpoints completed with Godot 4.7.1 | PASS |
| Global doorway coefficient authorized | no |
| Authority / Group C retirement | NO-GO |
| F3.3n corrected-topology routing experiment | design GO |
