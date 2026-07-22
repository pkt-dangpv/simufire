# Phase 3+ F3.3f2 - Destination-routing runtime experiment

Date: 2026-07-22

## Decision

**Runtime NO-GO at the 180 s STOP. The runtime wiring was fully removed.**

The pure F3.3f1 selector and its deterministic fixtures remain because they
correctly represent source-preserving direct transport and close every
conserved quantity. The Group C experiment shows that direct transport alone
is incomplete: it improves cold lower renewal but removes nearly all hot upper
return. F3.3g must design CFAST's separate doorway-jet entrainment/mixing owner
before source-preserving routing is reconsidered at runtime.

No 300 s or 590/600 s candidate run was started.

## Temporary runtime surface

The experiment temporarily added:

- a default-false `SimulationEngine` flag;
- one runner/headless argument that enabled the complete F3.3b prerequisite
  stack plus F3.3c1 and F3.3d1 ledgers;
- one opt-in CSV trace column;
- propagation of the already-tested selector to the atomic interior network.

It changed no opening coefficient, pressure solve, neutral plane, source
density, atomic cap or transported payload formula. All temporary runtime
wiring and its structural test were removed after the failed STOP.

## OFF invariance

The 180 s OFF control was compared with the prior F3.3d1 checkpoint.

| Check | Result |
|---|---|
| Rows | 114 / 114 |
| Columns | 667 / 667 |
| Candidate column while OFF | absent |
| CSV SHA-256 | `6F7FD18D3C451D2AE615D695B066A08F9F593DF5708E864DD50067CECF09ED70` both |
| Shared-cell differences | 0 |

Default-OFF behavior and schema were therefore exact.

## 180 s routing result

R0 cumulative accepted F3.3a opening plus F3.3b pressure inflow:

| Destination | OFF | ON | CFAST 0-180 s |
|---|---:|---:|---:|
| Lower inflow | 46.143 kg | 54.555 kg | 65.782 kg |
| Upper inflow | 7.516 kg | 0.004 kg | 3.662 kg |
| Total inflow | 53.659 kg | 54.559 kg | 69.444 kg |

The candidate increased lower renewal by 8.412 kg without artificially
increasing total flow. That is the intended direct-routing effect. It failed
the paired requirement, however: upper inflow fell by 7.511 kg and became
effectively zero.

Canonical R0 state at 180 s:

| Metric | OFF | ON | CFAST |
|---|---:|---:|---:|
| Upper temperature | 125.70 C | 130.02 C | 159.82 C |
| Upper gas mass | 22.921 kg | 20.463 kg | 26.94 kg |
| Interface height | 1.101 m | 1.227 m | 0.736 m |
| Lower gas mass | 25.000 kg | 28.932 kg | not binding |

Upper temperature moved slightly toward CFAST, but upper inventory decreased
and the interface rose, making the hot layer thinner. The state therefore
moved away from the binding mass/interface targets.

## Conservation and isolation

| Check | ON result |
|---|---:|
| F3.3d1 building mass residual | 0.0 kg |
| F3.3c1 building enthalpy residual | 0.0 kJ |
| Interior mass residual | 0.0 kg |
| Interior energy residual | 0.0 kJ |
| Interior O2 residual | 0.0 kg |
| Interior species residual | 0.0 kg |
| Non-Phase-3 shared cell differences | 0 |

The failure is semantic, not numerical. The transaction remains conservative
and legacy output remains unchanged because the candidate is shadow-only.

## Interpretation

The F3.3f diagnosis remains valid: receiver-midpoint routing sends too much
cool replacement flow into upper when the interface falls. But replacing that
rule with source identity for every direct slab is not a complete CFAST model.

CFAST treats doorway-jet entrainment as a separate term. A hot stream entering
a receiving compartment can entrain receiving-room lower gas into its upper
layer. That mechanism can create the upper circulation that the pure direct
candidate removes, without falsifying the direct stream's source identity.

The next phase must therefore keep two owners distinct:

1. direct vent transport preserves source-layer identity;
2. doorway-jet entrainment transfers gas inside the receiver from lower to
   upper, carrying its own enthalpy, O2 and species consistently.

F3.3g must establish the exact CFAST equation and ownership contract in a pure
fixture before any new runtime experiment. A flow multiplier, pressure gain,
forced upper fraction or Qc composition is not justified.

## Repository state after rollback

- F3.3f1 pure selector: retained, optional and default false at public APIs.
- F3.3f1 direct Godot fixture: retained.
- Engine export: absent.
- CLI/headless flag: absent.
- CSV runtime column: absent.
- Official cases/reports/baselines/tolerances/gaps: unchanged.
- Canonical authority: unchanged and NO-GO.

## Post-rollback verification

| Check | Result |
|---|---|
| Phase 3 pytest selection | 467 PASS |
| F3.3f1 isolated Godot 4.7.1 fixture | PASS |
| Physics coherence | 9 PASS / 15 CTRL / 5 WARN / 0 FAIL |
| ILV coherence | 15 PASS / 14 CTRL / 0 FAIL |
| Gap inventory | 348/353 PASS; 5 VALID_GAP; 71 non-gating |
| Guardrails | only expected R2-1 while the wider motor worktree is dirty |
| `git diff --check` | PASS |
