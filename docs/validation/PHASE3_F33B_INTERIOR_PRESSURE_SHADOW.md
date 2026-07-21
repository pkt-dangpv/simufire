# Phase 3+ F3.3b - Signed canonical interior-pressure shadow

Date: 2026-07-21

## Decision

**GO as default-OFF diagnostic shadow infrastructure. NO-GO for authority and
for retiring Group C.**

F3.3b adds the signed component missing from the equal-gross F3.3a interior
opening exchange. It does not tune a discharge coefficient and does not add a
second live transport owner. The signed routes are built from the same common
canonical pre-step snapshot, appended to the same network bundle and limited
by the same atomic inventory fraction as the F3.3a routes.

The mechanism is stable, opening-order independent and conservative for gas
mass, sensible enthalpy, O2 and all seven transported species. It nevertheless
worsens both Group C temperature checks. This falsifies the working hypothesis
that missing signed pressure flow was the source of the late R0 temperature
deficit.

## Contract

The opt-in flag is:

```text
phase3_canonical_interior_pressure_shadow_enabled = false
```

The CLI switch is:

```text
--phase3-canonical-interior-pressure-shadow
```

The switch implies F3.3a and the complete prior canonical shadow stack. When
enabled, F3.3b:

1. Reads all horizontal interior openings from one canonical pre-step
   snapshot and preserves the F3.3a stable opening order.
2. Uses each room canonical gauge pressure as the floor pressure offset in the
   exact piecewise hydrostatic opening integral.
3. Extracts only the directional excess from that pressure field. F3.3a
   remains the owner of balanced buoyant gross exchange.
4. Converts every signed route to one source-zone payload containing gas,
   sensible enthalpy, O2, smoke, CO, CO2, HCN, HCl, acrolein and formaldehyde.
5. Predicts the linear EOS pressure response of all F3.3a and F3.3b routes.
6. Applies one network-wide relaxation fraction so the signed component cannot
   reverse any connected room-pressure difference in one explicit step.
7. Adds the relaxed signed routes to the existing F3.3a atomic network bundle.
   One final inventory fraction therefore governs both components.

Exterior and vertical openings remain excluded. Legacy horizontal transport
is suppressed only inside the canonical shadow by the existing F3.3a
ownership rule. No `RoomModel` legacy state, FED path, validation expected,
tolerance, CTRL envelope or official report is changed.

## Telemetry

The F3.3b flag adds 19 CSV columns after the F3.3a block. They expose:

- canonical pre-step pressure and connected-opening count;
- raw, equilibrium-limited and atomically accepted signed gas flow;
- per-room signed net mass;
- network pressure-equilibrium fraction;
- full, limited and predicted post-step pressure deltas;
- prevented pressure-crossing count;
- mass, energy, O2 and species conservation residuals.

With F3.3b disabled, the schema remains the F3.3a schema. A fresh 60 s F3.3a
run matched the pre-F3.3b evidence in all 508 shared columns. In the F3.3a vs
F3.3b comparison, all 115 shared non-Phase-3 columns were exactly identical.

## Runtime evidence

Evidence is under `runs/phase3_f33b/`. No official validation report was
regenerated.

| Control | Result |
|---|---|
| Direct Godot 4.7.1 fixture | PASS: signed direction, reversed pressure, equal-pressure quiet state, anti-crossing cap, all-quantity conservation, opening-order equivalence, F3.3a-disabled equivalence and vertical exclusion |
| Group C, 600 s | Completed with exact volume closure and zero mass/energy/O2/species residuals |
| Group A, 60 s | Stable; maximum sampled signed transfer `1.47e-5 kg/step` |
| Two-floor stairwell, 60 s | Vertical opening skipped; horizontal openings remain active; residuals zero |
| Two-room no-fire, 60 s | Near-equilibrium numerical flow only; maximum sampled signed transfer `1.84e-5 kg/step` |

In Group C, the network equilibrium fraction ranges from approximately
`3.24e-6` to `1.0`; pressure crossing prevention is active when required. The
largest sampled signed per-room transfer is below `0.01 kg/step`. Building net
signed mass closes to approximately `2e-8 kg` at CSV precision.

## Group C result

Reference targets remain 159.816 C at 180 s and 168.796 C at 600 s, with the
existing tolerances of 15 C and 30 C.

| R0 upper temperature | F3.2b7 | F3.3a | F3.3b | Result |
|---|---:|---:|---:|---|
| 180 s | 227.903 C | 130.942 C | 125.699 C | Worse than F3.3a |
| 600 s | 113.915 C | 102.734 C | 97.391 C | Worse than F3.3a |

At 600 s, R0 canonical upper energy falls from `1931.7 kJ` in F3.3a to
`1855.4 kJ` in F3.3b. Sampled signed transport removes a net `1.46 kg` from R0
over the logged trajectory. The signed component therefore reinforces the
late enthalpy deficit instead of curing it.

Canonical R0 gauge pressure changes from `3.06 Pa` to `29.70 Pa` at 180 s and
from `-1.37 Pa` to `71.04 Pa` at 600 s. This does not indicate a one-step
crossing failure: the limiter controls each explicit opening solve, while
combustion, wall and other transactions continue to drive the next canonical
state. It does show that signed doorway relief is not the missing long-term
pressure/energy owner.

## Validation gates

| Gate | Result |
|---|---|
| F3.3a/F3.3b static tests | 20 PASS |
| Direct Godot F3.3b fixture | PASS |
| Full pytest outside sandbox | 1053 PASS; 18 pre-existing structural failures; 1 expected R2-1 failure |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 required PASS; 5 VALID_GAP; 71 non-gating gaps |
| Guardrails | 9/10; only R2-1 because `sim/core` is intentionally dirty at STOP |

## Next phase

Do not tune the F3.3a gross exchange or increase F3.3b pressure flow. Both
remove upper enthalpy and the late Group C deficit becomes larger.

The next phase is **F3.3c: Group C late-enthalpy residence audit**, diagnostic
first. It must attribute the R0 canonical energy trajectory to combustion,
plume, inter-zone heat, wall/ambient exchange, F3.3a gross doorway transport,
F3.3b signed transport and exterior boundaries. It must compare those
cumulative terms with the CFAST layer-temperature/interface history before any
new motor owner is proposed.

Authority remains blocked until one mechanism improves both 180 s and 600 s
without breaking mass, energy, O2, species, pressure or layer closure.
