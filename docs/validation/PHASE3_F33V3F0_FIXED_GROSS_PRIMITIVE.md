# Phase 3+ F3.3v3f0 fixed-gross skew primitive

Date: 2026-07-26

## Decision

F3.3v3f0 is **GO as a dormant motor primitive**.

`Phase3ZoneMassSystem.preview_fixed_gross_interior_pressure_skew()` implements
the route recomposition selected by F3.3v3e, but no runtime path calls it.
There is no flag, state mutation, CSV field or behavior change in this
subphase.

## Contract

For each interior connection:

```text
half_skew = 0.5 * pressure_net
out_new   = out_opening + half_skew
in_new    = in_opening  - half_skew
```

The half-skew is capped to:

```text
-out_opening <= half_skew <= in_opening
```

Therefore:

- neither direction becomes negative;
- opening gross mass is invariant;
- the accepted added net flow is `2 * half_skew`;
- mass, sensible enthalpy, O2 and every species are scaled by the same
  directional factor;
- each resulting route remains an atomic source debit/destination credit.

The primitive rejects invalid routes, exterior endpoints, self-routes,
unidentified connections and pressure routes without a corresponding opening
group.

## Runtime proof

The fixture:

```text
tests/fixtures/phase3_f33v3f0_fixed_gross_preview.gd
```

uses an 8 kg / 8 kg counterflow and a 2 kg pressure-net request. It verifies:

| Metric | Result |
|---|---:|
| Opening gross | 16 kg |
| Preview gross | 16 kg |
| Preview out/in | 9 kg / 7 kg |
| Accepted pressure net | 2 kg |
| Mass residual | 0 |
| Energy residual | 0 |
| O2 residual | 0 |
| Species residual | 0 |

A second request of 30 kg verifies the directional cap: the accepted net is
limited to 16 kg and gross mass remains 16 kg.

Godot 4.7.1 console result:

```text
PHASE3_F33V3F0_FIXED_GROSS_PREVIEW_PASS
```

The command must pass `--log-file` inside the workspace. Without it, the
current Windows environment can crash before project load while trying to
open the default `user://logs` path. That startup crash is unrelated to the
fixture or motor parse.

## STOP gate

| Check | Result |
|---|---|
| Pure function | PASS |
| Runtime call sites | zero |
| Fixed gross mass | PASS |
| Directional non-negative cap | PASS |
| Atomic payload scaling | PASS |
| Godot 4.7.1 parse/runtime | PASS |
| Physics behavior | unchanged by construction |
| Reports/baselines/tolerances | unchanged |

## Next gate: F3.3v3f1

F3.3v3f1 may wire the primitive as an opt-in preview:

1. add a default-OFF engine flag;
2. call the primitive after pressure-network relaxation, before additive
   pressure routes are appended;
3. accumulate preview-only directional mass/enthalpy telemetry;
4. continue applying the existing additive routes unchanged;
5. run the 180 s corridor candidate OFF and ON;
6. verify legacy and canonical shared columns are identical;
7. compare preview cumulative out/in and net enthalpy with CFAST.

No live route replacement is authorized in F3.3v3f1.
