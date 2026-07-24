# Phase 3+ F3.3k - Per-connection residence audit

Date: 2026-07-23

## Decision

**Instrumentation GO. Physical candidate and Group C retirement remain
NO-GO.**

F3.3k adds a default-OFF accepted-route ledger keyed by opening, direction and
transport family. It exports only to `summary.json`; the CSV schema and all
legacy physical state remain unchanged.

The audit found a validation-case topology mismatch before it found a new
motor coefficient:

- CFAST contains three compartments and two open doors:
  `R0-Hall` and `Hall-R2`, both `0.9 m` wide.
- SimuFire's `simple_house` contains six rooms and five normally open interior
  doors connected to the Hall.
- `cfast_corridor_chain.json` attempts to override Hall-R2 as `1 -> 2`, while
  the template stores the opening as `2 -> 1`. Overrides are direction-exact,
  so the width remains `0.8 m`.
- The case attempts to close `0 -> 4`, an opening that does not exist. The
  real `4 -> 1` kitchen door remains open, as do `3 -> 1` and `5 -> 1`.

Consequently, the F3.3j aggregate Hall comparison mixed two CFAST connections
with five SimuFire connections. Its runtime arithmetic is correct for the
configured SimuFire case, but its conclusion that gross Hall mass was
sufficient is not a valid CFAST correspondence result.

No official case, report, expected value, tolerance, gap or HVAC path was
changed in F3.3k.

## Diagnostic contract

The new opt-in flag is:

```text
phase3_connection_residence_diagnostics_enabled = false
CLI: --phase3-connection-residence-diagnostics
```

It requires the full F3.3b stack plus both accepted-route residence ledgers.
For each opening, direction and family (`interior_opening` or
`interior_pressure`) it records:

- accepted gas mass and sensible enthalpy;
- source upper/lower mass;
- destination upper/lower mass;
- mass-weighted source temperature;
- destination upper fraction;
- accepted route count.

The connection identity is attached before the route enters the common atomic
bundle. Values are recorded after the common accepted fraction is known and
before canonical state mutation. Reset clears all cumulative records.

## Configured-case audit

The original six-room case produces these active Hall branches over 0-180 s:

| Opening | Connection |
|---:|---|
| 0 | R0-Hall |
| 1 | Hall-Kitchen |
| 2 | Hall-R2 |
| 3 | Hall-Bedroom 2 |
| 4 | Hall-Bathroom |

This explains the previous aggregate SimuFire direct inflow of `138.650 kg`.
It is not comparable with CFAST's `128.253 kg`, because it includes three
additional reservoirs.

## Equivalent-topology control

A scratch-only control corrected the exact directed overrides:

- Hall-R2: `2 -> 1`, width `0.9 m`, open;
- Kitchen-Hall: `4 -> 1`, closed;
- Bedroom 2-Hall: `3 -> 1`, closed;
- Bathroom-Hall: `5 -> 1`, closed.

The official JSON was restored immediately after each run. No report under
`sim/validation/reports` was regenerated.

### Direct connection budgets, 0-180 s

Opening and signed-pressure families are combined. Energy is sensible
enthalpy relative to `20 C`.

| Direction | CFAST mass | SimuFire mass | CFAST energy | SimuFire energy |
|---|---:|---:|---:|---:|
| R0 -> Hall | 76.617 kg | 52.491 kg | 7760.804 kJ | 4096.947 kJ |
| Hall -> R0 | 69.367 kg | 47.769 kg | 1459.098 kJ | 515.567 kJ |
| Hall -> R2 | 55.071 kg | 38.597 kg | 3115.926 kJ | 1662.644 kJ |
| R2 -> Hall | 51.637 kg | 35.677 kg | 1067.221 kJ | 356.661 kJ |

SimuFire gross flow is consistently about `30-32%` below CFAST on all four
directions. The equivalent-topology Hall receives `88.168 kg`, not
`138.650 kg`; CFAST receives `128.253 kg`.

### Net energy ownership

| Hall connection balance | CFAST | SimuFire | Difference |
|---|---:|---:|---:|
| Net gain from R0-Hall | +6301.706 kJ | +3581.380 kJ | -2720.326 kJ |
| Net loss through Hall-R2 | -2048.705 kJ | -1305.984 kJ | +742.721 kJ |
| Net direct Hall gain | +4253.001 kJ | +2275.396 kJ | -1977.605 kJ |

Hall-R2 does not export too much energy. It exports `0.743 MJ` less than
CFAST and therefore partially masks the upstream deficit. The binding owner
is R0-Hall.

The combined SimuFire R0-to-Hall source temperature is `98.05 C`, versus
CFAST `121.29 C`. The route is deficient in both mass (`-31.5%`) and thermal
content per kilogram. No destination-routing coefficient can create either
missing quantity.

## Equivalent-topology state

At 180 s, applying the topology correction to the temporary F3.3h2 shadow
candidate changes:

| State | Original topology | Equivalent topology | CFAST |
|---|---:|---:|---:|
| R0 upper temperature | 128.42 C | 129.17 C | 159.82 C |
| R0 interface | 1.207 m | 1.031 m | 0.736 m |
| R0 upper mass | 20.832 kg | 23.943 kg | 26.943 kg |
| Hall upper temperature | 80.46 C | 78.14 C | 93.55 C |
| Hall interface | 1.366 m | 0.902 m | 0.568 m |
| Hall upper mass | 10.810 kg | 15.747 kg | 18.384 kg |

Removing the extra branches materially improves upper mass and interface, but
does not close source temperature or enthalpy.

## Legacy 600 s topology control

The corrected topology was also run with legacy physics and no Phase 3
diagnostics:

| R0 checkpoint | Current official case | Correct topology | CFAST target |
|---|---:|---:|---:|
| 180 s upper temp | 196.25 C | 149.86 C | 159.82 C |
| 300 s upper temp | 156.02 C | 121.14 C | 165.84 C |
| 600 s upper temp | 107.89 C | 99.56 C | 168.39 C |

The topology correction closes the current 180 s required failure, creates a
300 s required failure and leaves 600 s failing. The number of Group C gaps
remains two, but their identity changes. This is why the correction requires
its own validation STOP gate instead of being folded into a motor experiment.

## Verification

- Focused Phase 3 Python tests: `45/45 PASS`.
- Direct Godot 4.7.1 fixture:
  `PHASE3_F33K_CONNECTION_RESIDENCE_LEDGER_PASS`.
- Both 180 s diagnostic runs: `RUN_SCENARIO PASS`.
- Corrected-topology legacy 600 s scratch run: `RUN_SCENARIO PASS`.
- Physics coherence: `9 PASS / 15 CTRL / 5 WARN / 0 FAIL`, exit 0.
- ILV coherence: `15 PASS / 14 CTRL / 0 FAIL`, exit 0.
- Gap inventory: `348/353 PASS`, `5 VALID_GAP`, exit 0.
- Validation guardrails: `9/10 PASS`; only R2-1 fails because the motor
  instrumentation is intentionally uncommitted. No physical baseline changed.
- The unrestricted repository-wide `pytest` invocation is not a valid result:
  collection entered ignored scratch directories under `runs/` and stopped
  with Windows `PermissionError` failures. The focused 45-test result above is
  the valid code signal for this gate.
- Default-OFF no-op proof: the 115 legacy CSV columns are bit-identical to the
  same-session checkpoint, and `summary.json` contains no connection ledger.
- Temporary F3.3h2 physical selector removed.
- Official case restored; official reports and validation metadata unchanged.
- `git diff --check`: PASS.

## Next gate

F3.3l must correct and validate scenario equivalence before more motor work:

1. apply the exact directed opening overrides to
   `cfast_corridor_chain.json`;
2. regenerate only this case with Godot 4.7.1;
3. prove that the runtime has exactly the two CFAST interior connections;
4. review all required and non-gating deltas without changing CFAST expected
   values or tolerances;
5. retire the t=180 VALID_GAP only if it passes and classify the newly exposed
   t=300 failure explicitly;
6. run physics, ILV, guardrails and the focused Phase 3 tests;
7. STOP before commit.

Only after F3.3l should the physical program resume at R0-to-Hall hot-mass and
enthalpy generation. HVAC remains deferred.
