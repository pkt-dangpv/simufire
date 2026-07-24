# Phase 3+ F3.3j - Hall two-zone residence audit

Date: 2026-07-23

## Decision

**Diagnostic closed without a motor patch, then superseded in part by
F3.3k.**

The Hall does not lack gross incoming gas mass. Its binding mismatch is the
temperature and zonal composition of the transported gas. Over 0-180 s the
temporary F3.3h2 candidate receives slightly more direct gas mass than CFAST,
but only `38.88%` of CFAST's net direct sensible enthalpy.

The candidate Poreh route prevents the complete Hall upper-zone collapse seen
in the OFF checkpoint. It does so by moving `20.734 kg` from lower to upper,
almost compensating a `22.008 kg` error in the direct upper-zone balance.
That internal transfer conserves total energy and cannot replace the missing
hot-source enthalpy. The resulting Hall upper layer remains too small and too
cool.

No motor, runner, flag, CSV schema, official report, baseline, tolerance, gap
or HVAC path changed.

### F3.3k correction

F3.3k found that this aggregate comparison used non-equivalent topologies.
CFAST has two Hall connections; the configured SimuFire case has five active
Hall connections because three direction-exact opening overrides are missing
or ineffective. The `138.650 kg` SimuFire inflow below is correct for that
six-room case but cannot be compared directly with CFAST's three-room total.

With equivalent topology, SimuFire Hall inflow is `88.168 kg` versus CFAST
`128.253 kg`, and net direct enthalpy is `2.275 MJ` versus `4.253 MJ`.
The binding deficit originates on R0-to-Hall. See
`PHASE3_F33K_CONNECTION_RESIDENCE_AUDIT.md`.

## Endpoint state at 180 s

The CFAST masses use the exported zone densities and the exact zone volumes
implied by the interface. Sensible energy is measured relative to `20 C`.

| Hall state | CFAST | SimuFire OFF | F3.3h2 candidate |
|---|---:|---:|---:|
| Upper gas mass | 18.384 kg | 0.000 kg | 10.810 kg |
| Lower gas mass | 6.501 kg | 27.710 kg | 16.764 kg |
| Upper sensible energy | 1352.146 kJ | 0.000 kJ | 653.577 kJ |
| Lower sensible energy | 184.508 kJ | 741.719 kJ | 134.997 kJ |
| Upper temperature | 93.55 C | 20.00 C | 80.46 C |
| Lower temperature | 48.38 C | 46.77 C | 28.05 C |
| Interface height | 0.568 m | 2.400 m | 1.366 m |

The OFF checkpoint records one canonical upper-zone collapse. The candidate
avoids that collapse, but its final upper mass remains `41.2%` below CFAST
and its lower mass remains `157.9%` above CFAST.

## CFAST Hall mass balance

Integrating the committed CFAST doorway slabs for both Hall connections gives:

| Direct doorway mass, 0-180 s | Upper | Lower | Total |
|---|---:|---:|---:|
| In | 82.912 kg | 45.457 kg | 128.369 kg |
| Out | 69.919 kg | 54.612 kg | 124.531 kg |
| Net | +12.993 kg | -9.155 kg | +3.838 kg |

The two Hall leakage records integrate to `9.067 kg` of exterior loss.
Therefore:

```text
initial Hall mass + direct net - leakage
= 30.124 kg + 3.838 kg - 9.067 kg
= 24.895 kg
```

CFAST's final reconstructed mass is `24.884 kg`; the `0.011 kg` difference is
integration/rounding error.

The zonal leakage allocation is not exported. Depending on whether none or
all of that leakage is assigned to the upper layer, the internal lower-to-upper
transfer implied by CFAST is bounded at approximately `5.4-14.5 kg`.

## SimuFire candidate mass balance

The accepted-route residence ledger closes exactly:

| Direct route, 0-180 s | In | Out | Net |
|---|---:|---:|---:|
| F3.3a opening | 127.536 kg | 127.534 kg | +0.002 kg |
| F3.3b pressure | 11.113 kg | 10.037 kg | +1.077 kg |
| Combined | 138.650 kg | 137.571 kg | +1.079 kg |

SimuFire therefore receives `138.650 kg` of direct gas, `8.0%` more than
CFAST's `128.369 kg`. Gross incoming mass is not the missing source.

The zonal direct balance is different:

| SimuFire direct net | Value |
|---|---:|
| Upper | -9.015 kg |
| Lower | +10.093 kg |
| Total | +1.079 kg |

CFAST has `+12.993 kg` direct net upper mass. The SimuFire candidate is thus
`22.008 kg` short in the direct upper balance.

The separate Poreh bundle moves net `20.734 kg` from lower to upper. It nearly
compensates that routing error in mass, but it is larger than the
`5.4-14.5 kg` CFAST internal-transfer bound. Poreh is acting as a compensator
for an upstream zonal-flow mismatch, not reproducing the CFAST mechanism.

## Enthalpy ownership

The decisive discrepancy is energy carried by the direct flows:

| Direct sensible enthalpy, 0-180 s | In | Out | Net |
|---|---:|---:|---:|
| CFAST doorway slabs | 8828.028 kJ | 4575.024 kJ | +4253.004 kJ |
| SimuFire opening + pressure | 5170.373 kJ | 3516.831 kJ | +1653.542 kJ |

SimuFire's net direct enthalpy is only `38.88%` of CFAST. The deficit is
`2599.462 kJ`.

The candidate's complete wall, ambient and exterior sensible-energy loss is:

| Boundary sink | Energy |
|---|---:|
| Wall | 212.954 kJ |
| Ambient | 600.269 kJ |
| Exterior | 51.745 kJ |
| Total | 864.968 kJ |

Even deleting every one of those losses would recover only one third of the
direct-flow enthalpy deficit. Boundary cooling is real but is not the first
owner.

Poreh transfers energy internally and sums to zero at room level. It can place
existing energy in the upper zone, but cannot close the missing `2.599 MJ`
doorway contribution. This explains why the candidate obtains an upper layer
without reproducing the CFAST upper temperature, mass or interface.

## Original owner assignment

The table below records the F3.3j interpretation before the topology mismatch
was known. F3.3k supersedes the gross-mass and connection-ownership rows.

| Hypothesis | Verdict | Evidence |
|---|---|---|
| Insufficient gross incoming mass | Rejected | SimuFire direct inflow is 8.0% above CFAST. |
| Excessive onward transport alone | Rejected as primary | Gross in/out churn is high, but the direct zonal net is already wrong before projection. |
| Projection/collapse | Secondary symptom | OFF collapses the upper zone; candidate avoids collapse but remains far from CFAST. |
| Excessive wall/ambient loss | Secondary | Total candidate boundary loss is only 0.865 MJ versus a 2.599 MJ direct-enthalpy deficit. |
| Insufficient hot-source enthalpy | Selected | Direct net enthalpy is only 38.88% of CFAST. |
| Wrong zonal doorway routing | Selected | Direct upper net is -9.015 kg versus CFAST +12.993 kg. |
| Poreh mixing | Compensating, not causal | Its +20.734 kg upper transfer nearly cancels the 22.008 kg direct upper error. |
| Pressure state | Separate secondary blocker | The F3.3i `425.8 Pa` versus `0.555 Pa` mismatch remains unresolved. |

The surviving conclusion is that connection-level hot-mass and enthalpy
transport owns the physical deficit. F3.3k resolves the ambiguity: the owner
is R0-to-Hall inflow, not excessive Hall-to-R2 export.

## Next gate

F3.3k should add or temporarily expose a passive per-connection accepted-route
ledger for the Hall:

1. separate R0-to-Hall and Hall-to-R2 opening and pressure routes;
2. report upper/lower mass and sensible enthalpy in both directions;
3. report accepted source-zone temperature and destination fraction;
4. preserve Poreh as a separate receiver-internal route;
5. compare only 0-180 s against the committed CFAST slabs;
6. remove temporary runtime wiring after the decision unless the telemetry is
   independently useful and passes a STOP gate.

No physical coefficient, authority promotion, 300/590 s run or gap retirement
is justified before that connection-level owner is known.

F3.3k subsequently supplied that connection-level ledger and exposed the
scenario-topology mismatch. Its next gate is F3.3l scenario equivalence, not a
new physical coefficient.
